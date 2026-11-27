package io.github.movemontes.magen.ui

import android.Manifest
import android.app.admin.DevicePolicyManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.github.movemontes.magen.BuildConfig
import io.github.movemontes.magen.Magen
import io.github.movemontes.magen.core.Rules
import io.github.movemontes.magen.core.Verdict
import io.github.movemontes.magen.tr
import io.github.movemontes.magen.trf
import io.github.movemontes.magen.vpn.AdminReceiver
import io.github.movemontes.magen.vpn.MagenVpnService
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Uma janelinha aberta por cima do app (aviso, frase, doação, atualização). */
sealed class Popup {
    class Message(val title: String, val text: String) : Popup()
    class Ask(val title: String, val text: String, val yes: String, val onYes: () -> Unit) : Popup()
    class Sentence(val title: String, val text: String, val sentence: String, val yes: String,
                   val onResult: (Boolean) -> Unit) : Popup()
    object Donation : Popup()
    class Update(val release: Updates.Release) : Popup()
}

/**
 * A tela do Magen (como o MainWindow do Mac e o window.py do Windows). As páginas estão em Pages.kt,
 * as janelinhas em Dialogs.kt e o tour em Tour.kt.
 */
class MainActivity : ComponentActivity() {
    // Estado da tela. Mudar qualquer um destes redesenha.
    var tab by mutableStateOf("inicio")
    var siteText by mutableStateOf("")
    var siteResult by mutableStateOf("")
    var popup by mutableStateOf<Popup?>(null)
    var busy by mutableStateOf(false)
    var tourStep by mutableStateOf<Int?>(null)
    var versePreview by mutableStateOf<Verse?>(null)
    var tick by mutableIntStateOf(0) // muda quando o porteiro avisa algo
    val spots = SpotMap()

    private val handler = Handler(Looper.getMainLooper())
    private val listener: () -> Unit = { tick++ }
    private val every5s = object : Runnable {
        override fun run() { tick++; handler.postDelayed(this, 5000) }
    }

    private val vpnPermission = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == RESULT_OK) startProtection()
        else {
            busy = false
            popup = Popup.Message("Não deu certo", "Sem a permissão de VPN, o Magen não consegue proteger este celular. Toque em “Ligar a proteção” e depois em “OK”.")
        }
    }
    private val notifPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { askVpn() }
    private val adminRequest = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { tick++ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        T.load(this)
        setContent {
            @Suppress("UNUSED_EXPRESSION") tick // lê o tick para redesenhar
            BackHandler(enabled = tourStep != null || tab != "inicio") {
                if (tourStep != null) endTour() else tab = "inicio"
            }
            MagenScreen(this)
        }
        if (savedInstanceState == null) firstRun()
    }

    override fun onResume() {
        super.onResume()
        Magen.listeners += listener
        handler.post(every5s)
        if (Updates.shouldCheckNow()) checkUpdates(manual = false)
    }

    override fun onPause() {
        Magen.listeners -= listener
        handler.removeCallbacks(every5s)
        super.onPause()
    }

    // ------------------------------------------------------------ estado

    val serviceOn get() = Magen.running
    fun state() = Magen.store.state()
    fun config() = Magen.store.config()

    // ------------------------------------------------------------ ligar

    fun turnOn() {
        if (busy) return
        busy = true
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else askVpn()
    }

    private fun askVpn() {
        val i = VpnService.prepare(this)
        if (i != null) vpnPermission.launch(i) else startProtection()
    }

    private fun startProtection() {
        Magen.prefs.set("protecaoLigada", true)
        MagenVpnService.start(this)
        handler.postDelayed({
            busy = false
            tab = "inicio"
            tick++
            if (!Magen.running) {
                popup = Popup.Message("Não deu certo", "O Magen não conseguiu ligar a VPN. Se outro app de VPN estiver ligado, desligue-o e tente de novo.")
            } else if (!Magen.prefs.bool("doacaoVista", false)) {
                popup = Popup.Donation
            }
        }, 1500)
    }

    // ------------------------------------------------------------ sites

    private fun typedSite(): String? {
        val raw = siteText.trim()
        val d = Rules.cleanSite(raw)
        if (d == null) {
            siteResult = if (raw.isEmpty()) tr("Digite o endereço de um site.")
                         else tr("Endereço inválido. Digite só o endereço, por exemplo: exemplo.com")
        }
        return d
    }

    fun testSite() {
        val site = typedSite() ?: return
        siteResult = when (Magen.test(site)) {
            Verdict.BLOCKED, Verdict.BYPASS -> trf("🚫 %s está BLOQUEADO (ou não existe).", site)
            Verdict.ALLOWED -> trf("✅ %s está liberado.", site)
            null -> tr("O Magen não respondeu. Ele está ligado?")
        }
    }

    /** Liberar é difícil de propósito: nome adulto é recusado, precisa digitar uma frase, e só vale 1 hora depois. */
    fun unblockSite() {
        val site = typedSite() ?: return
        if (Rules.isObviouslyAdult(site)) {
            siteResult = trf("🚫 %s tem nome de site adulto. Ele não pode ser liberado.", site)
            return
        }
        val minutes = Rules.UNBLOCK_DELAY_SECONDS / 60
        popup = Popup.Sentence(trf("Liberar %s?", site),
            trf("Liberar é só para um site que NÃO é adulto e foi bloqueado por engano.\n\nO site só vai abrir daqui " +
                "a %d minutos. Se for um momento de tentação, esse tempo é para você respirar e desistir. Dá para " +
                "cancelar a qualquer hora na aba Sites.\n\nPara continuar, digite exatamente:", minutes),
            Rules.unblockSentence(io.github.movemontes.magen.I18n.isEn()), "Pedir liberação") { ok ->
            if (!ok) {
                siteResult = tr("A frase não confere. Nada foi liberado.")
                return@Sentence
            }
            val at = System.currentTimeMillis() + Rules.UNBLOCK_DELAY_SECONDS * 1000
            Magen.changeConfig { c ->
                c.copy(pendingAllow = c.pendingAllow.filter { it.domain != site } + io.github.movemontes.magen.core.Pending(site, at),
                       block = c.block - site)
            }
            siteResult = trf("⏳ %s será liberado às %s. Até lá, continua bloqueado.", site, fmtTime(at, withDate = false))
            siteText = ""
        }
    }

    fun blockSite() {
        val site = typedSite() ?: return
        Magen.changeConfig { c ->
            c.copy(block = (c.block + site).distinct(), allow = c.allow - site,
                   pendingAllow = c.pendingAllow.filter { it.domain != site })
        }
        siteResult = trf("🚫 %s agora está bloqueado.", site)
        siteText = ""
    }

    /** O × ao lado de um site das listas da pessoa. */
    fun undo(domain: String) {
        Magen.changeConfig { c ->
            c.copy(allow = c.allow - domain, block = c.block - domain,
                   pendingAllow = c.pendingAllow.filter { it.domain != domain })
        }
    }

    // ------------------------------------------------------------ proteção

    fun setAntiBypass(on: Boolean) {
        if (on) { Magen.changeConfig { it.copy(antiBypass = true) }; return }
        popup = Popup.Ask("Desligar a proteção contra burla?",
            "Sem ela, os navegadores podem usar o “DNS seguro” e passar por fora do Magen.", "Desligar") {
            Magen.changeConfig { it.copy(antiBypass = false) }
        }
    }

    fun adminActive() = getSystemService(DevicePolicyManager::class.java).isAdminActive(AdminReceiver.component(this))

    fun setAdmin(on: Boolean) {
        if (on) {
            val i = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, AdminReceiver.component(this))
                .putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    tr("Com isto ativo, o Android não deixa desinstalar o Magen direto. Para remover, use o botão dentro do app, que pede uma frase."))
            adminRequest.launch(i)
            return
        }
        popup = Popup.Sentence("Deixar fácil de desinstalar?",
            "Sem isto, o Magen pode ser desinstalado em dois toques. Se for um momento de tentação, feche esta janela e respire.\n\nPara continuar, digite exatamente:",
            Rules.removeSentence(io.github.movemontes.magen.I18n.isEn()), "Continuar") { ok ->
            if (!ok) popup = Popup.Message("Nada foi mudado", "A frase não confere.")
            else { getSystemService(DevicePolicyManager::class.java).removeActiveAdmin(AdminReceiver.component(this)); handler.postDelayed({ tick++ }, 800) }
        }
    }

    fun remove() {
        popup = Popup.Sentence("Remover o Magen?",
            "Sem o Magen, os sites adultos voltam a abrir neste celular. Se for um momento de tentação, feche esta janela e respire.\n\nPara remover, digite exatamente:",
            Rules.removeSentence(io.github.movemontes.magen.I18n.isEn()), "Remover") { ok ->
            if (!ok) { popup = Popup.Message("Nada foi removido", "A frase não confere."); return@Sentence }
            Magen.prefs.set("protecaoLigada", false)
            startService(Intent(this, MagenVpnService::class.java).setAction(MagenVpnService.ACTION_STOP))
            runCatching { getSystemService(DevicePolicyManager::class.java).removeActiveAdmin(AdminReceiver.component(this)) }
            // O Android leva um instante para soltar o "administrador"; depois abre a desinstalação.
            handler.postDelayed({
                runCatching { startActivity(Intent(Intent.ACTION_DELETE, Uri.parse("package:$packageName"))) }
            }, 1500)
        }
    }

    fun requestUpdate() {
        Magen.requestUpdate()
        popup = Popup.Message("Pedido enviado", "As listas novas chegam em 1 ou 2 minutos. (O Magen atende no máximo um pedido a cada 5 minutos.)")
    }

    // ------------------------------------------------------------ permissões e configurações do Android

    fun openOverlaySettings() {
        runCatching { startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))) }
    }

    fun openVpnSettings() {
        runCatching { startActivity(Intent(Settings.ACTION_VPN_SETTINGS)) }
    }

    fun openPrivateDnsSettings() {
        // Não existe atalho oficial para o "DNS privado": tenta a tela de rede, senão as configurações.
        for (action in listOf("android.settings.WIRELESS_SETTINGS", Settings.ACTION_SETTINGS)) {
            if (runCatching { startActivity(Intent(action)) }.isSuccess) return
        }
    }

    /** Nome do "DNS privado" fixo, se estiver ligado (ele passa por fora de qualquer filtro de DNS). */
    fun privateDnsHost(): String? {
        if (Build.VERSION.SDK_INT < 28) return null
        runCatching {
            val mode = Settings.Global.getString(contentResolver, "private_dns_mode")
            if (mode == "hostname") return Settings.Global.getString(contentResolver, "private_dns_specifier") ?: "?"
        }
        val cm = getSystemService(ConnectivityManager::class.java)
        @Suppress("DEPRECATION")
        for (n in cm.allNetworks) {
            val name = cm.getLinkProperties(n)?.privateDnsServerName
            if (!name.isNullOrEmpty()) return name
        }
        return null
    }

    // ------------------------------------------------------------ versículo, doação, tour, idioma

    fun showVersePreview() {
        if (!VerseOverlay.preview(this)) versePreview = Verses.random(this)
    }

    fun copyPix() {
        getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Pix", PIX))
    }

    fun changeLanguage(lang: String) {
        Magen.prefs.set("idioma", lang)
        io.github.movemontes.magen.I18n.languageChanged()
        tick++
    }

    /** Na primeira vez: o recado de doação e, depois dele, o tour (como no Treco). */
    private fun firstRun() {
        if (!Magen.prefs.bool("doacaoVista", false)) popup = Popup.Donation
        else if (tourPending()) startTour()
    }

    fun popupClosed(was: Popup?) {
        if (was is Popup.Donation && tourPending() && tourStep == null) startTour()
    }

    fun startTour() {
        tab = TOUR[0].tab
        tourStep = 0
    }

    fun nextTour() {
        val s = tourStep ?: return
        if (s + 1 >= TOUR.size) { endTour(); return }
        tourStep = s + 1
        tab = TOUR[s + 1].tab
    }

    fun endTour() {
        if (tourStep != null) Magen.prefs.set("tourVisto", TOUR_VERSION)
        tourStep = null
    }

    // ------------------------------------------------------------ atualização do app

    fun checkUpdates(manual: Boolean) {
        Thread {
            val rel = Updates.fetchLatest()
            Updates.markChecked()
            handler.post {
                when {
                    rel == null -> if (manual) popup = Popup.Message("Não deu para procurar agora", "Confira a internet e tente de novo mais tarde.")
                    !Updates.isNewer(rel.version, BuildConfig.VERSION_NAME) ->
                        if (manual) popup = Popup.Message("Você está com a versão mais nova", trf("Magen %s.", BuildConfig.VERSION_NAME))
                    !manual && Updates.skipped() == rel.version -> {}
                    else -> popup = Popup.Update(rel)
                }
            }
        }.start()
    }

    fun installUpdate(rel: Updates.Release) {
        Thread {
            val apk = Updates.download(this, rel.url)
            handler.post {
                if (apk == null) popup = Popup.Message("Não deu certo", "Não consegui baixar a versão nova. Tente de novo mais tarde.")
                else if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                    popup = Popup.Message("Falta uma permissão", "Na tela que vai abrir, deixe o Magen instalar apps. Depois toque em “Procurar atualização” de novo.")
                    runCatching { startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))) }
                } else runCatching { Updates.install(this, apk) }
            }
        }.start()
    }

    companion object {
        const val AUTHOR = "Mateus"
        const val PIX = "e2a1f4a9-ebfe-4c3c-a531-92a0e7433f14"

        fun fmtTime(ms: Long, withDate: Boolean = true): String {
            if (ms <= 0) return "—"
            val en = io.github.movemontes.magen.I18n.isEn()
            val d = Date(ms)
            if (!withDate) return SimpleDateFormat(if (en) "h:mm a" else "HH:mm", Locale.US).format(d)
            val months = if (en) "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ")
                         else "jan fev mar abr mai jun jul ago set out nov dez".split(" ")
            val cal = java.util.Calendar.getInstance().apply { time = d }
            val m = months[cal.get(java.util.Calendar.MONTH)]
            val day = cal.get(java.util.Calendar.DAY_OF_MONTH)
            return if (en) "$m $day, ${SimpleDateFormat("h:mm a", Locale.US).format(d)}"
                   else "$day de $m, ${SimpleDateFormat("HH:mm", Locale.US).format(d)}"
        }
    }
}
