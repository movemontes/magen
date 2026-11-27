package io.github.movemontes.magen.ui

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import io.github.movemontes.magen.BuildConfig
import io.github.movemontes.magen.I18n
import io.github.movemontes.magen.Magen
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Atualização pelo GitHub (como o updates.py do Windows): procura a última versão, baixa
 * "Magen-<versão>-android.apk" e abre o instalador do Android, que pergunta antes de instalar.
 */
object Updates {
    const val REPO = "movemontes/magen"

    class Release(val version: String, val notes: String, val url: String)

    fun isNewer(a: String, b: String): Boolean {
        fun parts(v: String) = v.split('.').map { it.toIntOrNull() ?: 0 }
        val x = parts(a); val y = parts(b)
        for (i in 0 until maxOf(x.size, y.size)) {
            val p = x.getOrElse(i) { 0 }; val q = y.getOrElse(i) { 0 }
            if (p != q) return p > q
        }
        return false
    }

    /** Só o trecho das notas no idioma do app (entre <!-- pt --> e <!-- /pt -->), em texto simples. */
    fun notesPart(body: String?): String {
        val lang = I18n.current()
        val m = Regex("<!-- $lang -->(.*?)<!-- /$lang -->", RegexOption.DOT_MATCHES_ALL).find(body ?: "")
        val text = m?.groupValues?.get(1) ?: body ?: ""
        return text.replace("**", "").lines().joinToString("\n") { if (it.startsWith("- ")) "• " + it.drop(2) else it }.trim()
    }

    private fun open(url: String, accept: String? = null): HttpURLConnection {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 20_000
        c.readTimeout = 20_000
        c.setRequestProperty("User-Agent", "Magen/${BuildConfig.VERSION_NAME}")
        if (accept != null) c.setRequestProperty("Accept", accept)
        return c
    }

    /** A última versão com .apk de Android, ou null. Roda fora do fio da tela. */
    fun fetchLatest(): Release? {
        try {
            val c = open("https://api.github.com/repos/$REPO/releases/latest", "application/vnd.github+json")
            if (c.responseCode == 200) {
                val j = JSONObject(c.inputStream.bufferedReader().readText())
                val tag = j.optString("tag_name").removePrefix("v")
                val assets = j.optJSONArray("assets")
                if (assets != null) for (i in 0 until assets.length()) {
                    val a = assets.getJSONObject(i)
                    if (a.optString("name").endsWith("-android.apk")) {
                        return Release(tag, notesPart(j.optString("body")), a.getString("browser_download_url"))
                    }
                }
                return null // versão sem .apk de Android (só Mac ou Windows)
            }
        } catch (_: Exception) {
        }
        // Plano B: a API aceita 60 consultas por hora. A página pública leva para /releases/tag/v<versão>.
        return try {
            val c = open("https://github.com/$REPO/releases/latest")
            c.instanceFollowRedirects = false
            val loc = c.getHeaderField("Location") ?: return null
            val tag = loc.substringAfter("/releases/tag/", "").removePrefix("v")
            if (!Regex("[0-9.]+").matches(tag)) return null
            Release(tag, "", "https://github.com/$REPO/releases/download/v$tag/Magen-$tag-android.apk")
        } catch (_: Exception) {
            null
        }
    }

    fun autoCheckOn() = Magen.prefs.bool("atualizarSozinho", true)
    fun shouldCheckNow() = autoCheckOn() &&
        System.currentTimeMillis() - Magen.prefs.long("ultimaProcura", 0) > 20 * 3600_000L
    fun markChecked() = Magen.prefs.set("ultimaProcura", System.currentTimeMillis())
    fun skipped() = Magen.prefs.string("versaoPulada")
    fun skip(v: String) = Magen.prefs.set("versaoPulada", v)

    /** Baixa o .apk para a pasta temporária do app. */
    fun download(ctx: Context, url: String): File? {
        val dir = File(ctx.cacheDir, "atualizacao").apply { mkdirs() }
        val target = File(dir, "Magen.apk")
        return try {
            var c = open(url)
            c.readTimeout = 120_000
            var hops = 0
            while (c.responseCode in 300..399 && hops++ < 5) {
                c = open(c.getHeaderField("Location"))
                c.readTimeout = 120_000
            }
            if (c.responseCode != 200) return null
            val part = File(dir, "Magen.apk.part")
            c.inputStream.use { inp -> part.outputStream().use { inp.copyTo(it, 1 shl 16) } }
            part.renameTo(target)
            if (target.length() > 100_000) target else null
        } catch (_: Exception) {
            null
        }
    }

    /** Abre o instalador do Android para o .apk baixado. */
    fun install(ctx: Context, apk: File) {
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.arquivos", apk)
        val i = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(i)
    }
}
