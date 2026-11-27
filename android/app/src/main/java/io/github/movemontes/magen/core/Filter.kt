package io.github.movemontes.magen.core

enum class Verdict { ALLOWED, BLOCKED, BYPASS }

/** Decide se um nome está bloqueado. A lista "liberados" da pessoa ganha de tudo. */
class Filter {
    @Volatile var lists = DomainSet()     // vindo das listas baixadas (enorme)
        private set
    @Volatile private var extra = DomainSet()   // "bloqueados a mais" da pessoa
    @Volatile private var allow = DomainSet()
    @Volatile private var bypass = DomainSet()

    fun setLists(ds: DomainSet) { lists = ds }

    fun applyConfig(c: Config) {
        extra = DomainSet.of(c.block.mapNotNull { Rules.normalize(it) })
        allow = DomainSet.of(c.allow.mapNotNull { Rules.normalize(it) })
        bypass = if (c.antiBypass) DomainSet.of(Rules.ANTI_BYPASS_DOMAINS) else DomainSet()
    }

    val count: Int get() = lists.size + extra.size + bypass.size

    fun verdict(rawName: String): Verdict {
        val name = rawName.lowercase().trimEnd('.')
        if (allow.matches(name)) return Verdict.ALLOWED
        if (bypass.matches(name)) return Verdict.BYPASS
        if (extra.matches(name) || lists.matches(name)) return Verdict.BLOCKED
        return Verdict.ALLOWED
    }
}

/** Mensagens de DNS: ler a pergunta e montar a resposta "não existe". */
object DnsMessage {
    class Question(val name: String, val type: Int, val end: Int)

    /** Lê a primeira pergunta de uma consulta DNS (a partir de [off], com [len] bytes). */
    fun parseQuery(msg: ByteArray, off: Int, len: Int): Question? {
        if (len < 12 || (msg[off + 2].toInt() and 0x80) != 0) return null // curta demais, ou é resposta
        val qd = (msg[off + 4].toInt() and 0xff shl 8) or (msg[off + 5].toInt() and 0xff)
        if (qd < 1) return null
        var i = 12
        val sb = StringBuilder()
        while (true) {
            if (i >= len) return null
            val n = msg[off + i].toInt() and 0xff
            if (n == 0) { i++; break }
            if (n and 0xC0 != 0 || n > 63 || i + 1 + n > len) return null
            if (sb.isNotEmpty()) sb.append('.')
            for (k in 1..n) {
                val c = (msg[off + i + k].toInt() and 0xff).toChar()
                sb.append(if (c in 'A'..'Z') c + 32 else c)
            }
            i += 1 + n
            if (sb.length > 254) return null
        }
        if (i + 4 > len) return null
        val type = (msg[off + i].toInt() and 0xff shl 8) or (msg[off + i + 1].toInt() and 0xff)
        return Question(sb.toString(), type, i + 4)
    }

    /** Resposta "este endereço não existe" (NXDOMAIN; rcode=2 é SERVFAIL). */
    fun blockedResponse(query: ByteArray, off: Int, end: Int, rcode: Int = 3): ByteArray {
        val r = query.copyOfRange(off, off + end)
        r[2] = (0x80 or (query[off + 2].toInt() and 0x78) or (query[off + 2].toInt() and 0x01)).toByte()
        r[3] = (0x80 or rcode).toByte()
        r[4] = 0; r[5] = 1
        for (k in 6 until 12) r[k] = 0
        return r
    }

    fun rcode(resp: ByteArray): Int = if (resp.size >= 4) resp[3].toInt() and 0x0f else -1
}
