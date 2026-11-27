package io.github.movemontes.magen

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.github.movemontes.magen.core.Config
import io.github.movemontes.magen.core.DomainSet
import io.github.movemontes.magen.core.Filter
import io.github.movemontes.magen.core.Lists
import io.github.movemontes.magen.core.Store
import io.github.movemontes.magen.core.Verdict
import io.github.movemontes.magen.ui.VerseOverlay
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

class MagenApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Magen.init(this)
    }
}

/**
 * O coração do Magen, compartilhado pelo app e pelo porteiro (a VPN), que rodam no mesmo processo.
 * É o que no Mac é o magend + MagenCore e no Windows é o service.py + core.py.
 */
object Magen {
    lateinit var context: Context
        private set
    lateinit var store: Store
        private set
    lateinit var prefs: Prefs
        private set
    val filter = Filter()
    private val main = Handler(Looper.getMainLooper())
    private val updating = AtomicBoolean(false)
    @Volatile private var listsLoaded = false
    @Volatile private var lastSignal = 0L
    @Volatile private var lastUpdateRequest = 0L

    /** O porteiro está rodando agora (a VPN está ligada). */
    @Volatile var running = false
        internal set

    /** Avisos para a tela (o app redesenha quando algo muda). */
    val listeners = mutableSetOf<() -> Unit>()

    fun init(ctx: Context) {
        context = ctx.applicationContext
        store = Store(context)
        prefs = Prefs(context.getSharedPreferences("prefs", Context.MODE_PRIVATE))
        I18n.load(context)
        filter.applyConfig(store.config())
    }

    fun changed() = main.post { listeners.toList().forEach { it() } }

    fun log(msg: String) {
        Log.i("Magen", msg)
        try {
            val f = File(store.dir, "magen.log")
            if (f.length() > 1_000_000) f.renameTo(File(store.dir, "magen.log.antigo"))
            val ts = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
            f.appendText("[$ts] $msg\n")
        } catch (_: Exception) {
        }
    }

    // ------------------------------------------------------------ listas

    /** Carrega as listas do disco (rápido) na primeira vez. */
    fun loadListsIfNeeded() {
        if (listsLoaded) return
        synchronized(this) {
            if (listsLoaded) return
            val ds = DomainSet.load(store.hashesFile)
            filter.setLists(ds)
            filter.applyConfig(store.config())
            store.updateState { it.copy(domains = filter.count) }
            listsLoaded = true
            log("Listas carregadas do disco: ${ds.size} domínios.")
        }
    }

    fun listsAreOld(): Boolean {
        val last = store.state().lastUpdate
        return last == 0L || filter.lists.size == 0 ||
            System.currentTimeMillis() - last > store.config().updateEveryHours * 3600_000L
    }

    /** Baixa as listas de novo, num fio separado. Devolve false se já estava baixando. */
    fun updateLists(reason: String): Boolean {
        if (!updating.compareAndSet(false, true)) return false
        Thread {
            try {
                log("Atualizando listas ($reason)…")
                val r = Lists.download(store.config().lists, ::log)
                if (r == null) {
                    log("Nenhuma lista baixou; mantendo as listas antigas.")
                } else {
                    r.set.save(store.hashesFile)
                    filter.setLists(r.set)
                    store.updateState { it.copy(lastUpdate = System.currentTimeMillis(), domains = filter.count) }
                    store.saveState()
                    log("Pronto: ${filter.count} domínios bloqueados.")
                }
            } finally {
                updating.set(false)
                changed()
            }
        }.apply { name = "listas"; priority = Thread.MIN_PRIORITY }.start()
        return true
    }

    /** Pedido da pessoa (botão "Atualizar listas"): no máximo um a cada 5 minutos. */
    fun requestUpdate() {
        if (System.currentTimeMillis() - lastUpdateRequest < 5 * 60_000) return
        lastUpdateRequest = System.currentTimeMillis()
        updateLists("pedida pelo app")
    }

    val isUpdating get() = updating.get()

    // ------------------------------------------------------------ configuração

    fun changeConfig(change: (Config) -> Config) {
        val before = store.config()
        val c = store.updateConfig(change)
        filter.applyConfig(c)
        store.updateState { it.copy(domains = filter.count) }
        if (before.antiBypass != c.antiBypass) vpnRoutesChanged?.invoke()
        changed()
    }

    /** O porteiro registra aqui como refazer a VPN (as rotas mudam com a opção contra burla). */
    @Volatile var vpnRoutesChanged: (() -> Unit)? = null

    // ------------------------------------------------------------ bloqueios

    /** Um site adulto foi bloqueado: conta e mostra o versículo (no máximo uma vez por segundo). */
    fun onAdultBlock() {
        val now = System.currentTimeMillis()
        val key = Store.todayKey()
        store.updateState {
            val today = if (it.todayKey == key) it.blockedToday + 1 else 1
            it.copy(blockedTotal = it.blockedTotal + 1, blockedToday = today, todayKey = key, lastBlockAt = now)
        }
        if (now - lastSignal < 1000) return
        lastSignal = now
        main.post {
            VerseOverlay.siteBlocked(context)
            listeners.toList().forEach { it() }
        }
    }

    /** "Testar" da aba Sites. null = o Magen não está ligado. */
    fun test(site: String): Verdict? = if (running) filter.verdict(site) else null
}

/** Ajustes da pessoa (no Windows, prefs.json; no Mac, UserDefaults). Mesmos nomes. */
class Prefs(private val p: SharedPreferences) {
    fun bool(key: String, def: Boolean) = p.getBoolean(key, def)
    fun int(key: String, def: Int) = p.getInt(key, def)
    fun long(key: String, def: Long) = p.getLong(key, def)
    fun string(key: String): String? = p.getString(key, null)
    fun set(key: String, v: Any?) {
        val e = p.edit()
        when (v) {
            null -> e.remove(key)
            is Boolean -> e.putBoolean(key, v)
            is Int -> e.putInt(key, v)
            is Long -> e.putLong(key, v)
            else -> e.putString(key, v.toString())
        }
        e.apply()
    }
}

/** Idiomas: o app é escrito em português; tr() troca pelo inglês (assets/en.json). */
object I18n {
    private var english: Map<String, String> = emptyMap()

    fun load(ctx: Context) {
        english = try {
            val j = JSONObject(ctx.assets.open("en.json").bufferedReader().readText())
            j.keys().asSequence().associateWith { j.getString(it) }
        } catch (e: Exception) {
            emptyMap()
        }
    }

    fun current(): String {
        val chosen = Magen.prefs.string("idioma")
        if (chosen == "pt" || chosen == "en") return chosen
        return if (Locale.getDefault().language == "pt") "pt" else "en"
    }

    /** Muda quando a pessoa troca o idioma: os textos já desenhados leem isto e se redesenham. */
    private val changes = androidx.compose.runtime.mutableIntStateOf(0)
    fun languageChanged() { changes.intValue++ }

    fun isEn(): Boolean { changes.intValue; return current() == "en" }
    fun tr(pt: String) = if (isEn()) english[pt] ?: pt else pt
    fun trf(pt: String, vararg args: Any?) = String.format(Locale.US, tr(pt), *args)
    fun num(n: Number): String {
        val s = String.format(Locale.US, "%,d", n.toLong())
        return if (isEn()) s else s.replace(',', '.')
    }
}

fun tr(pt: String) = I18n.tr(pt)
fun trf(pt: String, vararg args: Any?) = I18n.trf(pt, *args)
