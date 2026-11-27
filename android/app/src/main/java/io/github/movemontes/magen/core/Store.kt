package io.github.movemontes.magen.core

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Um site esperando a hora de ser liberado. */
data class Pending(val domain: String, val at: Long)

/** Configuração (mesmos campos do config.json do Mac e do Windows). */
data class Config(
    val upstream: List<String> = Rules.DEFAULT_UPSTREAM,
    val lists: List<String> = Rules.DEFAULT_LISTS,
    val allow: List<String> = emptyList(),
    val pendingAllow: List<Pending> = emptyList(),
    val block: List<String> = emptyList(),
    val antiBypass: Boolean = true,
    val updateEveryHours: Int = 24,
)

/** Estado que o porteiro escreve e o app mostra. Só contagens: nunca o nome de um site. */
data class State(
    val blockedTotal: Long = 0,
    val blockedToday: Long = 0,
    val todayKey: String = "",
    val lastBlockAt: Long = 0,
    val lastUpdate: Long = 0,
    val domains: Int = 0,
)

/**
 * Guarda tudo na pasta particular do app (só o Magen lê e escreve). O app e o porteiro rodam no
 * mesmo processo, então leem e escrevem pelo mesmo objeto.
 */
class Store(context: Context) {
    val dir: File = context.filesDir
    private val configFile = File(dir, "config.json")
    private val stateFile = File(dir, "state.json")
    val hashesFile = File(dir, "blocklist-hashes.bin")
    private val lock = Any()

    @Volatile private var configCache: Config? = null

    // ------------------------------------------------------------ configuração

    fun config(): Config = configCache ?: synchronized(lock) { readConfig().also { configCache = it } }

    fun updateConfig(change: (Config) -> Config): Config = synchronized(lock) {
        val c = change(config())
        writeJson(configFile, configToJson(c))
        configCache = c
        c
    }

    /** Passa os sites cuja espera acabou de "pendingAllow" para "allow". Devolve os passados. */
    fun applyDue(now: Long = System.currentTimeMillis()): List<String> = synchronized(lock) {
        val c = config()
        val due = c.pendingAllow.filter { it.at <= now }
        if (due.isEmpty()) return emptyList()
        updateConfig {
            it.copy(pendingAllow = it.pendingAllow.filter { p -> p.at > now },
                    allow = (it.allow + due.map { p -> p.domain }).distinct())
        }
        due.map { it.domain }
    }

    private fun readConfig(): Config {
        val j = readJson(configFile) ?: return Config()
        val d = Config()
        return Config(
            upstream = j.strings("upstream") ?: d.upstream,
            lists = j.strings("lists") ?: d.lists,
            allow = j.strings("allow") ?: d.allow,
            pendingAllow = j.optJSONArray("pendingAllow")?.let { a ->
                (0 until a.length()).mapNotNull { i ->
                    val o = a.optJSONObject(i) ?: return@mapNotNull null
                    val at = parseIso(o.optString("at")) ?: return@mapNotNull null
                    Pending(o.optString("domain"), at)
                }
            } ?: d.pendingAllow,
            block = j.strings("block") ?: d.block,
            antiBypass = j.optBoolean("antiBypass", d.antiBypass),
            updateEveryHours = j.optInt("updateEveryHours", d.updateEveryHours),
        )
    }

    private fun configToJson(c: Config) = JSONObject().apply {
        put("upstream", JSONArray(c.upstream))
        put("lists", JSONArray(c.lists))
        put("allow", JSONArray(c.allow))
        put("pendingAllow", JSONArray(c.pendingAllow.map {
            JSONObject().put("domain", it.domain).put("at", iso(it.at))
        }))
        put("block", JSONArray(c.block))
        put("antiBypass", c.antiBypass)
        put("blockPrivateRelay", true) // só existe no Mac; fica para o arquivo ser igual
        put("updateEveryHours", c.updateEveryHours)
    }

    // ------------------------------------------------------------ estado

    @Volatile private var stateCache: State? = null

    fun state(): State = stateCache ?: synchronized(lock) { readState().also { stateCache = it } }

    fun updateState(change: (State) -> State): State = synchronized(lock) {
        val s = change(state())
        stateCache = s
        s
    }

    /** Grava o estado no disco (o porteiro chama de tempos em tempos, não a cada bloqueio). */
    fun saveState() = synchronized(lock) {
        val s = state()
        writeJson(stateFile, JSONObject().apply {
            put("blockedTotal", s.blockedTotal)
            put("blockedToday", s.blockedToday)
            put("todayKey", s.todayKey)
            put("lastBlockAt", iso(s.lastBlockAt))
            put("lastUpdate", iso(s.lastUpdate))
            put("domains", s.domains)
        })
    }

    private fun readState(): State {
        val j = readJson(stateFile) ?: return State()
        return State(
            blockedTotal = j.optLong("blockedTotal"),
            blockedToday = j.optLong("blockedToday"),
            todayKey = j.optString("todayKey"),
            lastBlockAt = parseIso(j.optString("lastBlockAt")) ?: 0,
            lastUpdate = parseIso(j.optString("lastUpdate")) ?: 0,
            domains = j.optInt("domains"),
        )
    }

    fun blockedTodayNow(): Long = state().let { if (it.todayKey == todayKey()) it.blockedToday else 0 }

    // ------------------------------------------------------------ arquivos

    private fun readJson(f: File): JSONObject? = try {
        if (f.exists()) JSONObject(f.readText()) else null
    } catch (e: Exception) {
        null
    }

    private fun writeJson(f: File, j: JSONObject) {
        val tmp = File(f.path + ".tmp")
        tmp.writeText(j.toString(2))
        replaceFile(tmp, f)
    }

    private fun JSONObject.strings(key: String): List<String>? =
        optJSONArray(key)?.let { a -> (0 until a.length()).map { a.optString(it) }.filter { it.isNotEmpty() } }

    companion object {
        fun todayKey(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

        private fun isoFormat() = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

        fun iso(ms: Long): Any = if (ms > 0) isoFormat().format(Date(ms)) else JSONObject.NULL

        fun parseIso(s: String?): Long? {
            if (s.isNullOrEmpty() || s == "null") return null
            return try { isoFormat().parse(s)?.time } catch (e: Exception) { null }
        }
    }
}
