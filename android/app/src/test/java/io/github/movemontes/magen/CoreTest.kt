package io.github.movemontes.magen

import io.github.movemontes.magen.core.DnsMessage
import io.github.movemontes.magen.core.DomainSet
import io.github.movemontes.magen.core.Filter
import io.github.movemontes.magen.core.Config
import io.github.movemontes.magen.core.Rules
import io.github.movemontes.magen.core.Verdict
import io.github.movemontes.magen.vpn.Packets
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Autoteste do núcleo (como o magen-selftest do Mac). Roda no computador, sem celular. */
class CoreTest {
    @Test fun normalize() {
        assertEquals("exemplo.com", Rules.normalize("0.0.0.0 exemplo.com"))
        assertEquals("exemplo.com", Rules.normalize("||exemplo.com^"))
        assertEquals("a.exemplo.com", Rules.normalize("*.a.exemplo.com"))
        assertEquals("exemplo.com", Rules.normalize("exemplo.com # comentário"))
        assertNull(Rules.normalize("# só comentário"))
        assertNull(Rules.normalize("127.0.0.1 localhost"))
        assertNull(Rules.normalize("1.2.3.4"))
        assertNull(Rules.normalize("!adblock"))
        assertEquals("www.x.com", Rules.cleanSite("https://WWW.x.com/pagina?q=1"))
    }

    @Test fun adultNames() {
        assertTrue(Rules.isObviouslyAdult("meu-pornhub-favorito.net"))
        assertFalse(Rules.isObviouslyAdult("wikipedia.org"))
    }

    @Test fun domainSetMatchesParents() {
        val ds = DomainSet.of(listOf("exemplo-adulto.com", "b.c.net"))
        assertTrue(ds.matches("exemplo-adulto.com"))
        assertTrue(ds.matches("www.exemplo-adulto.com"))
        assertTrue(ds.matches("x.y.b.c.net"))
        assertFalse(ds.matches("c.net"))
        assertFalse(ds.matches("com"))
        assertFalse(ds.matches("outro.com"))
    }

    @Test fun domainSetSaveLoad() {
        val f = java.io.File.createTempFile("magen", ".bin")
        DomainSet.of(listOf("a.com", "b.com", "a.com")).save(f)
        val back = DomainSet.load(f)
        assertEquals(2, back.size)
        assertTrue(back.matches("x.b.com"))
        f.delete()
    }

    @Test fun filterOrder() {
        val f = Filter()
        f.setLists(DomainSet.of(listOf("adulto.com", "liberado.com")))
        f.applyConfig(Config(allow = listOf("liberado.com"), block = listOf("extra.org")))
        assertEquals(Verdict.BLOCKED, f.verdict("www.adulto.com."))
        assertEquals(Verdict.ALLOWED, f.verdict("liberado.com"))
        assertEquals(Verdict.BLOCKED, f.verdict("extra.org"))
        assertEquals(Verdict.BYPASS, f.verdict("dns.google"))
        assertEquals(Verdict.ALLOWED, f.verdict("google.com"))
        f.applyConfig(Config(antiBypass = false))
        assertEquals(Verdict.ALLOWED, f.verdict("dns.google"))
    }

    private fun query(name: String): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        out.write(byteArrayOf(0x12, 0x34, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0))
        for (l in name.split('.')) { out.write(l.length); out.write(l.toByteArray()) }
        out.write(byteArrayOf(0, 0, 1, 0, 1))
        return out.toByteArray()
    }

    @Test fun dnsBlockedResponse() {
        val q = query("WWW.Exemplo.com")
        val p = DnsMessage.parseQuery(q, 0, q.size)!!
        assertEquals("www.exemplo.com", p.name)
        assertEquals(1, p.type)
        val r = DnsMessage.blockedResponse(q, 0, p.end)
        assertEquals(0x12, r[0].toInt()); assertEquals(0x34, r[1].toInt())
        assertEquals(3, DnsMessage.rcode(r))
        assertTrue(r[2].toInt() and 0x80 != 0)
        assertEquals(0, r[7].toInt()) // nenhuma resposta
    }

    /** Monta um pacote IPv4/UDP como o Android manda para o DNS falso e confere a volta. */
    @Test fun udpRoundTrip() {
        val dns = query("exemplo.com")
        val ip = ByteArray(28 + dns.size)
        ip[0] = 0x45; ip[2] = (ip.size shr 8).toByte(); ip[3] = ip.size.toByte(); ip[8] = 64; ip[9] = 17
        byteArrayOf(10, 111, 222.toByte(), 1).copyInto(ip, 12)
        byteArrayOf(10, 111, 222.toByte(), 2).copyInto(ip, 16)
        ip[20] = 0x9c.toByte(); ip[21] = 0x40; ip[23] = 53
        ip[24] = ((8 + dns.size) shr 8).toByte(); ip[25] = (8 + dns.size).toByte()
        dns.copyInto(ip, 28)
        val p = Packets.parse(ip, ip.size)!!
        assertEquals(53, p.dstPort)
        assertEquals(dns.size, p.payloadLen)
        val reply = Packets.udpReply(p, byteArrayOf(1, 2, 3))
        val back = Packets.parse(reply, reply.size)!!
        assertEquals(53, back.srcPort)
        assertEquals(0x9c40, back.dstPort)
        assertEquals(3, back.payloadLen)
        assertEquals(10, back.dst[0].toInt()); assertEquals(1, back.dst[3].toInt())
        // soma de verificação do cabeçalho IP confere (dá zero quando somada com ela mesma)
        var sum = 0
        for (i in 0 until 20 step 2) sum += ((reply[i].toInt() and 0xff) shl 8) or (reply[i + 1].toInt() and 0xff)
        while (sum shr 16 != 0) sum = (sum and 0xffff) + (sum shr 16)
        assertEquals(0xffff, sum)
    }

    @Test fun tcpResetForSyn() {
        val ip = ByteArray(40)
        ip[0] = 0x45; ip[3] = 40; ip[9] = 6
        byteArrayOf(10, 111, 222.toByte(), 1).copyInto(ip, 12)
        byteArrayOf(8, 8, 8, 8).copyInto(ip, 16)
        ip[22] = 0x01; ip[23] = 0xbb.toByte() // porta 443
        ip[27] = 100 // seq = 100
        ip[32] = 0x50; ip[33] = 0x02 // SYN
        val p = Packets.parse(ip, ip.size)!!
        val rst = Packets.tcpReset(p)
        assertNotNull(rst)
        val back = Packets.parse(rst!!, rst.size)!!
        assertEquals(443, back.srcPort)
        assertEquals(0x14, back.tcpFlags)
        assertEquals(101, rst[31].toInt()) // ack = 101
    }
}
