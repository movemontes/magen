package io.github.movemontes.magen.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import io.github.movemontes.magen.Magen
import io.github.movemontes.magen.R
import io.github.movemontes.magen.core.DnsMessage
import io.github.movemontes.magen.core.Rules
import io.github.movemontes.magen.core.Verdict
import io.github.movemontes.magen.tr
import io.github.movemontes.magen.ui.MainActivity
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit

/**
 * O porteiro do Magen no Android: uma VPN local que só recebe as perguntas de DNS.
 *
 * Um app comum não pode abrir a porta 53 nem trocar o DNS do sistema. Então o Magen cria uma VPN
 * (nada sai do celular) que diz ao Android "o DNS é 10.111.222.2" e só leva esse endereço para
 * dentro do Magen. Todo o resto da internet passa direto, sem tocar no Magen: por isso não fica lento.
 *
 * Site adulto → "não existe". O resto → pergunta à Cloudflare (Quad9 de reserva) e devolve.
 * Mesmo comportamento do Mac e do Windows: cache de 30 s, segunda tentativa, resposta antiga
 * (até 1 dia) quando a internet falha, e no máximo 48 perguntas ao mesmo tempo.
 */
class MagenVpnService : VpnService() {

    companion object {
        const val ACTION_START = "io.github.movemontes.magen.LIGAR"
        const val ACTION_STOP = "io.github.movemontes.magen.DESLIGAR"
        private const val CHANNEL = "protecao"
        private const val CHANNEL_ALERT = "avisos"
        private const val NOTE_ID = 1
        private const val NOTE_OFF = 2

        const val ADDRESS4 = "10.111.222.1"
        const val DNS4 = "10.111.222.2"
        const val ADDRESS6 = "fd00:6d61:6765:6e00::1"
        const val DNS6 = "fd00:6d61:6765:6e00::2"
        private const val MTU = 4096 // as respostas de DNS só passam por dentro do celular

        @Volatile var instance: MagenVpnService? = null
            private set

        fun start(ctx: Context) {
            val i = Intent(ctx, MagenVpnService::class.java).setAction(ACTION_START)
            ctx.startService(i)
        }

        /** Estado da "VPN sempre ativa" (só o próprio serviço sabe; Android 10 ou mais novo). */
        fun alwaysOn(): Boolean? = instance?.let { if (Build.VERSION.SDK_INT >= 29) it.isAlwaysOn else null }
        fun lockdown(): Boolean? = instance?.let { if (Build.VERSION.SDK_INT >= 29) it.isLockdownEnabled else null }
    }

    private var tun: ParcelFileDescriptor? = null
    private var reader: Thread? = null
    private var ticker: Thread? = null
    @Volatile private var stopping = false
    @Volatile private var starting = false
    private val pool = Executors.newFixedThreadPool(48) { r -> Thread(r, "dns").apply { isDaemon = true } }
    private val slots = Semaphore(48)
    private val cache = ConcurrentHashMap<Key, Pair<ByteArray, Long>>()
    @Volatile private var out: FileOutputStream? = null
    @Volatile private var failures = 0
    @Volatile private var dropped = 0

    /** A pergunta sem o número dela (bytes 2 em diante), para o cache. */
    private class Key(val b: ByteArray) {
        private val h = b.contentHashCode()
        override fun hashCode() = h
        override fun equals(other: Any?) = other is Key && other.b.contentEquals(b)
    }

    // ------------------------------------------------------------ ligar e desligar

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopping = true
            shutdown()
            stopSelf()
            return START_NOT_STICKY
        }
        // Sem ação = o Android ligou sozinho ("VPN sempre ativa" ou depois de reiniciar).
        Magen.prefs.set("protecaoLigada", true)
        if (tun == null && !starting) startVpn()
        return START_STICKY
    }

    private fun startVpn() {
        instance = this
        stopping = false
        goForeground()
        starting = true
        Thread {
            Magen.loadListsIfNeeded()
            val ok = establish()
            starting = false
            if (!ok) return@Thread
            Magen.running = true
            Magen.vpnRoutesChanged = { Thread { establish() }.start() }
            Magen.log("Magen ligado. Servidores de verdade: ${Magen.store.config().upstream.joinToString()}")
            Magen.changed()
            if (Magen.listsAreOld()) Magen.updateLists("início")
            startTicker()
        }.start()
    }

    /** Cria (ou refaz) a VPN. Só o DNS falso, e os servidores de "DNS seguro" se a opção contra burla estiver ligada. */
    @Synchronized
    private fun establish(): Boolean {
        val cfg = Magen.store.config()
        val b = Builder()
            .setSession("Magen")
            .setMtu(MTU)
            .addAddress(ADDRESS4, 32)
            .addDnsServer(DNS4)
            .addRoute(DNS4, 32)
            .setBlocking(true)
            .setConfigureIntent(PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE))
        // IPv6: o mesmo, para quando a rede só tem IPv6.
        try {
            b.addAddress(ADDRESS6, 128)
            b.addDnsServer(DNS6)
            b.addRoute(DNS6, 128)
        } catch (e: Exception) {
            Magen.log("Sem IPv6 na VPN: $e")
        }
        if (cfg.antiBypass) {
            for (ip in Rules.ANTI_BYPASS_IPV4) runCatching { b.addRoute(ip, 32) }
            for (ip in Rules.ANTI_BYPASS_IPV6) runCatching { b.addRoute(ip, 128) }
        }
        // O próprio Magen fica fora da VPN: ele baixa as listas e pergunta à Cloudflare pela rede normal.
        runCatching { b.addDisallowedApplication(packageName) }
        if (Build.VERSION.SDK_INT >= 29) b.setMetered(false)

        val fd = try {
            b.establish()
        } catch (e: Exception) {
            Magen.log("Não consegui criar a VPN: $e")
            null
        }
        if (fd == null) {
            // null = a pessoa não deu (ou tirou) a permissão de VPN.
            Magen.log("O Android não deixou criar a VPN (permissão retirada?).")
            shutdown()
            stopSelf()
            return false
        }
        val old = tun
        tun = fd
        out = FileOutputStream(fd.fileDescriptor)
        runCatching { Os.pipe() }.getOrNull()?.let { stopPipes[fd] = it }
        val t =Thread({ readLoop(fd) }, "tun")
        reader = t
        t.start()
        closeTun(old) // o leitor antigo para
        return true
    }

    override fun onRevoke() {
        // A pessoa desligou a VPN nas configurações, ou outro app de VPN tomou o lugar.
        Magen.log("A VPN foi desligada por fora do Magen.")
        val wanted = Magen.prefs.bool("protecaoLigada", false)
        shutdown()
        stopSelf()
        if (wanted) notifyTurnedOff()
    }

    override fun onDestroy() {
        shutdown()
        super.onDestroy()
    }

    private fun shutdown() {
        Magen.running = false
        Magen.vpnRoutesChanged = null
        ticker?.interrupt()
        ticker = null
        closeTun(tun)
        tun = null
        out = null
        if (instance === this) instance = null
        runCatching { Magen.store.saveState() }
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
        Magen.changed()
    }

    // ------------------------------------------------------------ ciclo de 30 s

    private fun startTicker() {
        ticker?.interrupt()
        ticker = Thread({
            var ticks = 0
            while (!Thread.currentThread().isInterrupted && tun != null) {
                try {
                    Thread.sleep(30_000)
                } catch (e: InterruptedException) {
                    return@Thread
                }
                try {
                    val moved = Magen.store.applyDue()
                    if (moved.isNotEmpty()) {
                        Magen.changeConfig { it }
                        Magen.log("Liberado(s) depois da espera: ${moved.size}")
                    }
                    Magen.store.saveState()
                    if (failures > 0 || dropped > 0) {
                        Magen.log("Atenção: nos últimos 30 s, $failures perguntas ficaram sem resposta e $dropped foram descartadas.")
                        failures = 0; dropped = 0
                    }
                    ticks++
                    if (ticks % 20 == 0 && Magen.listsAreOld()) Magen.updateLists("agendada")
                    Magen.changed()
                } catch (e: Exception) {
                    Magen.log("Erro no ciclo: $e")
                }
            }
        }, "ciclo").apply { isDaemon = true; start() }
    }

    // ------------------------------------------------------------ pacotes

    /**
     * Espera pacotes sem gastar bateria: dorme até chegar um pacote ou até alguém mexer no "cano"
     * de parar ([wake]). Fechar a VPN só com close() não acorda quem está lendo.
     */
    private fun readLoop(fd: ParcelFileDescriptor) {
        val input = FileInputStream(fd.fileDescriptor)
        val wake = stopPipes[fd]
        val buf = ByteArray(MTU + 100)
        val fds = if (wake != null) arrayOf(StructPollfd().apply { this.fd = fd.fileDescriptor; events = OsConstants.POLLIN.toShort() },
                                            StructPollfd().apply { this.fd = wake[0]; events = OsConstants.POLLIN.toShort() })
                  else null
        while (true) {
            if (fds != null) {
                try {
                    Os.poll(fds, -1)
                } catch (e: ErrnoException) {
                    if (e.errno == OsConstants.EINTR) continue
                    break
                }
                if (fds[1].revents.toInt() != 0) break // pediram para parar
                if (fds[0].revents.toInt() and (OsConstants.POLLERR or OsConstants.POLLHUP) != 0) break
                if (fds[0].revents.toInt() and OsConstants.POLLIN == 0) continue
            }
            val n = try {
                input.read(buf)
            } catch (e: Exception) {
                break // a VPN foi fechada
            }
            if (n < 0) break
            if (n == 0) continue
            val p = Packets.parse(buf, n) ?: continue
            when {
                p.protocol == Packets.UDP && p.dstPort == 53 && p.payloadLen >= 12 -> {
                    val query = buf.copyOfRange(p.payloadOff, p.payloadOff + p.payloadLen)
                    if (!slots.tryAcquire()) { dropped++; continue } // ocupado demais: o celular pergunta de novo
                    pool.execute {
                        try {
                            val r = answer(query)
                            if (r != null) write(Packets.udpReply(p, r), fd)
                        } catch (_: Exception) {
                        } finally {
                            slots.release()
                        }
                    }
                }
                // DNS por TCP, "DNS privado" (853) e "DNS seguro" por endereço fixo (443): recusa na hora.
                p.protocol == Packets.TCP -> Packets.tcpReset(p)?.let { write(it, fd) }
            }
        }
        stopPipes.remove(fd)
        wake?.forEach { runCatching { Os.close(it) } }
    }

    private val stopPipes = ConcurrentHashMap<ParcelFileDescriptor, Array<java.io.FileDescriptor>?>()

    /** Acorda o leitor desta VPN (ele para) e fecha a VPN. */
    private fun closeTun(fd: ParcelFileDescriptor?) {
        if (fd == null) return
        stopPipes[fd]?.let { p -> runCatching { Os.write(p[1], byteArrayOf(1), 0, 1) } }
        runCatching { fd.close() }
    }

    private fun write(packet: ByteArray, fd: ParcelFileDescriptor) {
        if (tun !== fd) return
        val o = out ?: return
        synchronized(o) { runCatching { o.write(packet) } }
    }

    // ------------------------------------------------------------ respostas

    private fun answer(query: ByteArray): ByteArray? {
        val q = DnsMessage.parseQuery(query, 0, query.size) ?: return forward(query)
        when (Magen.filter.verdict(q.name)) {
            Verdict.BLOCKED -> {
                Magen.onAdultBlock() // nunca guarda o nome: só conta
                return DnsMessage.blockedResponse(query, 0, q.end)
            }
            Verdict.BYPASS -> return DnsMessage.blockedResponse(query, 0, q.end)
            Verdict.ALLOWED -> {}
        }
        val key = Key(query.copyOfRange(2, query.size))
        val hit = cache[key]
        val now = System.currentTimeMillis()
        if (hit != null && hit.second > now) return withId(hit.first, query)
        // Mais uma volta se todos falharem (pacote perdido é comum no Wi-Fi e no 4G).
        val r = forward(query) ?: forward(query)
        if (r == null) {
            failures++
            // Internet soluçou: devolve a última resposta boa (até 1 dia) em vez de "não encontrado".
            if (hit != null && hit.second + 86_400_000 > now) return withId(hit.first, query)
            return DnsMessage.blockedResponse(query, 0, q.end, rcode = 2)
        }
        val rc = DnsMessage.rcode(r)
        if ((rc == 0 || rc == 3) && r.size > 3 && (r[2].toInt() and 0x02) == 0) { // nunca guarda resposta cortada
            if (cache.size > 50_000) cache.clear()
            cache[key] = r to now + 30_000
        }
        return r
    }

    private fun withId(r: ByteArray, query: ByteArray): ByteArray {
        val c = r.copyOf()
        c[0] = query[0]; c[1] = query[1]
        return c
    }

    private fun forward(query: ByteArray): ByteArray? {
        for (server in Magen.store.config().upstream) {
            try {
                DatagramSocket().use { s ->
                    protect(s) // esta pergunta sai pela internet normal, não volta para a VPN
                    s.soTimeout = 1000
                    val addr = InetAddress.getByName(server)
                    s.send(DatagramPacket(query, query.size, addr, 53))
                    val buf = ByteArray(MTU)
                    val deadline = System.currentTimeMillis() + 1000
                    while (System.currentTimeMillis() < deadline) {
                        val pkt = DatagramPacket(buf, buf.size)
                        s.receive(pkt)
                        if (pkt.length >= 12 && buf[0] == query[0] && buf[1] == query[1]) {
                            return buf.copyOf(pkt.length)
                        }
                    }
                }
            } catch (_: Exception) {
            }
        }
        return null
    }

    // ------------------------------------------------------------ notificações

    private fun channels() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, tr("Proteção ligada"), NotificationManager.IMPORTANCE_MIN))
        nm.createNotificationChannel(NotificationChannel(CHANNEL_ALERT, tr("Avisos do Magen"), NotificationManager.IMPORTANCE_HIGH))
    }

    private fun openApp() = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    private fun goForeground() {
        channels()
        val n = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notificacao)
            .setContentTitle(tr("Magen: protegendo"))
            .setContentText(tr("Sites adultos não abrem neste celular."))
            .setContentIntent(openApp())
            .setOngoing(true)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTE_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
            } else {
                startForeground(NOTE_ID, n)
            }
        } catch (e: Exception) {
            // A VPN funciona mesmo sem a notificação fixa.
            Magen.log("Sem notificação fixa: $e")
        }
    }

    private fun notifyTurnedOff() {
        channels()
        val n = Notification.Builder(this, CHANNEL_ALERT)
            .setSmallIcon(R.drawable.ic_notificacao)
            .setContentTitle(tr("⚠️ Magen está desligado"))
            .setContentText(tr("A VPN do Magen foi desligada. Toque para ligar de novo."))
            .setContentIntent(openApp())
            .setAutoCancel(true)
            .build()
        runCatching { getSystemService(NotificationManager::class.java).notify(NOTE_OFF, n) }
    }
}
