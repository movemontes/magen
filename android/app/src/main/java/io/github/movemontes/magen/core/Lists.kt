package io.github.movemontes.magen.core

import io.github.movemontes.magen.BuildConfig
import java.net.HttpURLConnection
import java.net.URL

/** Baixa as 3 listas abertas e monta o conjunto. Lê linha por linha: não guarda o texto inteiro. */
object Lists {
    class Result(val set: DomainSet, val okCount: Int)

    fun download(urls: List<String>, log: (String) -> Unit): Result? {
        val b = DomainSet.Builder()
        var any = false
        for (url in urls) {
            var found = 0
            try {
                val c = URL(url).openConnection() as HttpURLConnection
                c.connectTimeout = 30_000
                c.readTimeout = 120_000
                c.setRequestProperty("User-Agent", "Magen-blocker/${BuildConfig.VERSION_NAME}")
                if (c.responseCode != 200) {
                    log("  falhou (${c.responseCode}): $url"); c.disconnect(); continue
                }
                // Guarda os resumos desta lista à parte: se ela for pequena demais (página de erro), descarta.
                val mine = DomainSet.Builder()
                c.inputStream.reader(Charsets.UTF_8).buffered(1 shl 16).useLines { lines ->
                    for (line in lines) {
                        val d = Rules.normalize(line) ?: continue
                        if (d in Rules.NEVER_LIST_ENTRIES) continue
                        mine.add(d); found++
                    }
                }
                c.disconnect()
                if (found < 1000) {
                    log("  ignorada (só $found linhas válidas): $url"); continue
                }
                for (h in mine.build().hashes) b.addHash(h)
                any = true
                log("  ok: $found domínios de $url")
            } catch (e: Exception) {
                log("  falhou: $url ($e)")
            }
        }
        if (!any) return null
        val set = b.build()
        return Result(set, set.size)
    }
}
