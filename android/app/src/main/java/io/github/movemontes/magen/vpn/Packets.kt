package io.github.movemontes.magen.vpn

/**
 * Pacotes IP que chegam pela VPN. O Magen só mexe em dois tipos:
 * - UDP para a porta 53 (pergunta de DNS): responde com outro pacote UDP;
 * - TCP (DNS seguro por endereço fixo, ou DNS por TCP): responde "recusado" (RST) na hora.
 * O resto é descartado.
 */
object Packets {
    const val UDP = 17
    const val TCP = 6

    class Parsed(
        val version: Int,
        val protocol: Int,
        val src: ByteArray,
        val dst: ByteArray,
        val srcPort: Int,
        val dstPort: Int,
        val payloadOff: Int,
        val payloadLen: Int,
        val tcpSeq: Long = 0,
        val tcpFlags: Int = 0,
    )

    private fun u8(b: ByteArray, i: Int) = b[i].toInt() and 0xff
    private fun u16(b: ByteArray, i: Int) = (u8(b, i) shl 8) or u8(b, i + 1)
    private fun u32(b: ByteArray, i: Int) =
        (u8(b, i).toLong() shl 24) or (u8(b, i + 1).toLong() shl 16) or (u8(b, i + 2).toLong() shl 8) or u8(b, i + 3).toLong()

    fun parse(b: ByteArray, len: Int): Parsed? {
        if (len < 20) return null
        val version = u8(b, 0) ushr 4
        val proto: Int
        val src: ByteArray
        val dst: ByteArray
        val l4: Int
        val end: Int
        if (version == 4) {
            val ihl = (u8(b, 0) and 0x0f) * 4
            if (ihl < 20 || len < ihl + 8) return null
            if ((u16(b, 6) and 0x3fff) != 0) return null // pedaço de pacote: ignora
            proto = u8(b, 9)
            src = b.copyOfRange(12, 16)
            dst = b.copyOfRange(16, 20)
            l4 = ihl
            end = minOf(len, u16(b, 2))
        } else if (version == 6) {
            if (len < 48) return null
            proto = u8(b, 6) // sem cabeçalhos extras (DNS nunca usa)
            src = b.copyOfRange(8, 24)
            dst = b.copyOfRange(24, 40)
            l4 = 40
            end = minOf(len, 40 + u16(b, 4))
        } else return null
        return when (proto) {
            UDP -> {
                if (end < l4 + 8) return null
                val ulen = minOf(u16(b, l4 + 4), end - l4)
                Parsed(version, proto, src, dst, u16(b, l4), u16(b, l4 + 2), l4 + 8, ulen - 8)
            }
            TCP -> {
                if (end < l4 + 20) return null
                val dataOff = (u8(b, l4 + 12) ushr 4) * 4
                Parsed(version, proto, src, dst, u16(b, l4), u16(b, l4 + 2), l4 + dataOff,
                       maxOf(0, end - l4 - dataOff), u32(b, l4 + 4), u8(b, l4 + 13))
            }
            else -> null
        }
    }

    /** Pacote UDP de resposta: troca origem e destino e põe [payload] dentro. */
    fun udpReply(q: Parsed, payload: ByteArray): ByteArray {
        val ipLen = if (q.version == 4) 20 else 40
        val total = ipLen + 8 + payload.size
        val p = ByteArray(total)
        writeIp(p, q.version, UDP, q.dst, q.src, total)
        val u = ipLen
        put16(p, u, q.dstPort); put16(p, u + 2, q.srcPort); put16(p, u + 4, 8 + payload.size)
        System.arraycopy(payload, 0, p, u + 8, payload.size)
        var sum = transportChecksum(p, q.version, UDP, q.dst, q.src, u, 8 + payload.size)
        if (sum == 0) sum = 0xffff
        put16(p, u + 6, sum)
        return p
    }

    /** "Conexão recusada" (TCP RST): o outro lado desiste na hora, em vez de esperar. */
    fun tcpReset(q: Parsed): ByteArray? {
        if (q.tcpFlags and 0x04 != 0) return null // já é um RST
        val ipLen = if (q.version == 4) 20 else 40
        val total = ipLen + 20
        val p = ByteArray(total)
        writeIp(p, q.version, TCP, q.dst, q.src, total)
        val t = ipLen
        put16(p, t, q.dstPort); put16(p, t + 2, q.srcPort)
        // seq = 0; ack = seq dele + tamanho (+1 se for SYN ou FIN)
        var adv = q.payloadLen.toLong()
        if (q.tcpFlags and 0x02 != 0) adv++
        if (q.tcpFlags and 0x01 != 0) adv++
        put32(p, t + 8, (q.tcpSeq + adv) and 0xffffffffL)
        p[t + 12] = (5 shl 4).toByte()
        p[t + 13] = 0x14 // RST + ACK
        put16(p, t + 16, transportChecksum(p, q.version, TCP, q.dst, q.src, t, 20))
        return p
    }

    private fun writeIp(p: ByteArray, version: Int, proto: Int, src: ByteArray, dst: ByteArray, total: Int) {
        if (version == 4) {
            p[0] = 0x45
            put16(p, 2, total)
            p[6] = 0x40 // não fragmentar
            p[8] = 64
            p[9] = proto.toByte()
            System.arraycopy(src, 0, p, 12, 4)
            System.arraycopy(dst, 0, p, 16, 4)
            put16(p, 10, checksum(p, 0, 20, 0))
        } else {
            p[0] = 0x60
            put16(p, 4, total - 40)
            p[6] = proto.toByte()
            p[7] = 64
            System.arraycopy(src, 0, p, 8, 16)
            System.arraycopy(dst, 0, p, 24, 16)
        }
    }

    private fun transportChecksum(p: ByteArray, version: Int, proto: Int, src: ByteArray, dst: ByteArray,
                                  off: Int, len: Int): Int {
        var sum = 0L
        for (a in arrayOf(src, dst)) {
            var i = 0
            while (i < a.size) { sum += u16(a, i); i += 2 }
        }
        sum += proto
        sum += len
        return checksum(p, off, len, sum)
    }

    private fun checksum(p: ByteArray, off: Int, len: Int, start: Long): Int {
        var sum = start
        var i = off
        while (i + 1 < off + len) { sum += u16(p, i); i += 2 }
        if (i < off + len) sum += u8(p, i) shl 8
        while (sum ushr 16 != 0L) sum = (sum and 0xffff) + (sum ushr 16)
        return (sum.inv() and 0xffff).toInt()
    }

    private fun put16(p: ByteArray, i: Int, v: Int) { p[i] = (v ushr 8).toByte(); p[i + 1] = v.toByte() }
    private fun put32(p: ByteArray, i: Int, v: Long) {
        p[i] = (v ushr 24).toByte(); p[i + 1] = (v ushr 16).toByte(); p[i + 2] = (v ushr 8).toByte(); p[i + 3] = v.toByte()
    }
}
