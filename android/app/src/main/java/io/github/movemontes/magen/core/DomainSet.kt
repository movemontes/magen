package io.github.movemontes.magen.core

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.BufferedInputStream
import java.io.BufferedOutputStream

/** Troca [target] por [tmp] de uma vez (quem lê nunca vê um arquivo pela metade). */
fun replaceFile(tmp: File, target: File) {
    java.nio.file.Files.move(tmp.toPath(), target.toPath(),
        java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE)
}

/**
 * Conjunto compacto de domínios: só um resumo de 64 bits de cada um, em ordem.
 * 1,1 milhão de sites = uns 9 MB de memória. Procurar é uma busca binária (~20 passos).
 */
class DomainSet(internal val hashes: LongArray = LongArray(0)) {
    val size: Int get() = hashes.size

    fun hasHash(h: Long): Boolean = java.util.Arrays.binarySearch(hashes, h) >= 0

    /** True se o nome ou um domínio acima dele (menos o final ".com") está no conjunto. */
    fun matches(name: String): Boolean {
        if (hashes.isEmpty() || name.isEmpty()) return false
        var start = 0
        while (true) {
            val dot = name.indexOf('.', start)
            if (dot < 0) return false // sobrou só "com": nunca conta
            if (hasHash(hash64(name, start))) return true
            start = dot + 1
        }
    }

    fun save(file: File) {
        val tmp = File(file.path + ".tmp")
        DataOutputStream(BufferedOutputStream(tmp.outputStream(), 1 shl 16)).use { out ->
            out.writeInt(hashes.size)
            for (h in hashes) out.writeLong(h)
        }
        replaceFile(tmp, file)
    }

    companion object {
        /** Resumo de 64 bits do nome a partir de [start] (FNV-1a com mistura final). Sem criar texto novo. */
        fun hash64(s: String, start: Int = 0): Long {
            var h = -0x340d631b7bdddcdbL // 0xcbf29ce484222325
            for (i in start until s.length) {
                h = h xor (s[i].code.toLong() and 0xff)
                h *= 0x100000001b3L
            }
            // mistura final (do splitmix64): espalha bem os bits
            h = (h xor (h ushr 30)) * -0x40a7b892e31b1a47L
            h = (h xor (h ushr 27)) * -0x6b2fb644ecceee15L
            return h xor (h ushr 31)
        }

        fun of(domains: Iterable<String>): DomainSet {
            val b = Builder()
            for (d in domains) b.add(d)
            return b.build()
        }

        fun load(file: File): DomainSet {
            if (!file.exists()) return DomainSet()
            return try {
                DataInputStream(BufferedInputStream(file.inputStream(), 1 shl 16)).use { inp ->
                    val n = inp.readInt()
                    if (n < 0 || n > 20_000_000) return DomainSet()
                    val a = LongArray(n)
                    for (i in 0 until n) a[i] = inp.readLong()
                    DomainSet(a)
                }
            } catch (e: Exception) {
                DomainSet()
            }
        }
    }

    /** Junta resumos sem guardar os textos (pouca memória mesmo com 1,5 milhão de linhas). */
    class Builder {
        private var a = LongArray(1 shl 16)
        private var n = 0
        fun add(domain: String) = addHash(hash64(domain))
        fun addHash(h: Long) {
            if (n == a.size) a = a.copyOf(a.size * 2)
            a[n++] = h
        }
        fun build(): DomainSet {
            val s = a.copyOf(n)
            s.sort()
            var w = 0
            for (i in s.indices) if (w == 0 || s[i] != s[w - 1]) s[w++] = s[i]
            return DomainSet(s.copyOf(w))
        }
    }
}
