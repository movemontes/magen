package io.github.movemontes.magen.core

/**
 * Regras fixas do Magen: as mesmas do Mac (Sources/MagenCore) e do Windows (windows/magen_win/core.py).
 */
object Rules {
    val DEFAULT_LISTS = listOf(
        "https://nsfw.oisd.nl/domainswild2",
        "https://blocklistproject.github.io/Lists/alt-version/porn-nl.txt",
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts",
    )
    val DEFAULT_UPSTREAM = listOf("1.1.1.1", "1.0.0.1", "9.9.9.9")

    /** Nunca podem vir de uma lista baixada (sites grandes, sufixos públicos). */
    val NEVER_LIST_ENTRIES = setOf(
        // sufixos públicos de várias partes
        "com.br", "net.br", "org.br", "gov.br", "edu.br", "art.br", "blog.br", "co.uk", "org.uk",
        "com.au", "co.jp", "co.nz", "com.mx", "com.ar", "com.pt", "co.za", "co.in", "com.tr",
        // plataformas grandes e hospedagem compartilhada
        "google.com", "google.com.br", "youtube.com", "googlevideo.com", "gstatic.com",
        "googleapis.com", "googleusercontent.com", "ggpht.com", "ytimg.com",
        "apple.com", "icloud.com", "mzstatic.com", "microsoft.com", "live.com", "bing.com",
        "facebook.com", "fbcdn.net", "instagram.com", "cdninstagram.com", "whatsapp.com", "whatsapp.net",
        "twitter.com", "x.com", "twimg.com", "t.co", "reddit.com", "redd.it", "redditmedia.com",
        "tumblr.com", "imgur.com", "discord.com", "discordapp.com", "discord.gg", "tiktok.com",
        "amazon.com", "amazon.com.br", "amazonaws.com", "cloudfront.net", "akamaihd.net",
        "akamaized.net", "fastly.net", "cloudflare.com", "cloudflare.net", "github.com", "github.io",
        "githubusercontent.com", "gitlab.io", "blogspot.com", "blogger.com", "wordpress.com",
        "wp.com", "medium.com", "wikipedia.org", "wikimedia.org", "telegram.org", "t.me",
        "globo.com", "uol.com.br", "netflix.com", "spotify.com", "bit.ly", "linktr.ee",
        "dropbox.com", "vercel.app", "netlify.app", "pages.dev", "herokuapp.com",
        // bloqueados por engano nos 2.000 sites mais visitados (nov. 2026)
        "xiaohongshu.com", "ekstrabladet.dk", "suruga-ya.jp", "character.ai", "gotinder.com",
        "tinder.com", "sslip.io", "nip.io",
        // Windows: endereços que o sistema usa para saber se há internet e para se atualizar
        "msftconnecttest.com", "msftncsi.com", "windowsupdate.com", "windows.com",
        // Android: o mesmo (o teste de internet do Android fica em gstatic.com, já protegido acima)
        "android.com", "googlezip.net",
    )

    /** "DNS seguro" dos navegadores: bloqueados quando a opção contra burla está ligada. */
    val ANTI_BYPASS_DOMAINS = listOf(
        // Firefox: este domínio "canário" diz para ele não ligar o DNS-over-HTTPS sozinho
        "use-application-dns.net",
        // Servidores comuns de "DNS seguro" (DNS-over-HTTPS / TLS) dos navegadores
        "dns.google", "dns.google.com", "dns64.dns.google",
        "cloudflare-dns.com", "one.one.one.one", "1dot1dot1dot1.cloudflare-dns.com",
        "dns.quad9.net", "dns9.quad9.net", "dns10.quad9.net", "dns11.quad9.net", "dns12.quad9.net",
        "doh.opendns.com", "dns.opendns.com", "doh.familyshield.opendns.com",
        "dns.adguard.com", "dns.adguard-dns.com", "dns-unfiltered.adguard.com",
        "dns.nextdns.io", "doh.cleanbrowsing.org", "doh.mullvad.net", "dns.mullvad.net",
        "doh.dns.sb", "dns.controld.com", "freedns.controld.com", "doh.libredns.gr",
        "dns.alidns.com", "doh.pub", "dns.twnic.tw", "chrome.cloudflare-dns.com",
        "mozilla.cloudflare-dns.com", "doh.xfinity.com", "dns.brahma.world",
    )

    /**
     * Só no Android: endereços (IP) dos mesmos servidores de "DNS seguro". Com a opção contra burla
     * ligada, eles passam pela VPN do Magen: a pergunta de DNS comum (porta 53) é filtrada como as
     * outras, e o "DNS seguro" (DoH na 443, DoT na 853) é recusado na hora. Assim um app que fala
     * direto com 8.8.8.8 não foge do filtro.
     */
    val ANTI_BYPASS_IPV4 = listOf(
        "8.8.8.8", "8.8.4.4", "1.1.1.1", "1.0.0.1", "1.1.1.2", "1.0.0.2", "1.1.1.3", "1.0.0.3",
        "9.9.9.9", "149.112.112.112", "9.9.9.10", "149.112.112.10", "9.9.9.11", "149.112.112.11",
        "208.67.222.222", "208.67.220.220", "208.67.222.123", "208.67.220.123",
        "94.140.14.14", "94.140.15.15", "94.140.14.140", "94.140.14.141",
        "76.76.2.0", "76.76.10.0", "185.228.168.9", "185.228.169.9", "185.228.168.168",
        "194.242.2.2", "185.222.222.222", "45.11.45.11", "223.5.5.5", "223.6.6.6",
    )
    val ANTI_BYPASS_IPV6 = listOf(
        "2001:4860:4860::8888", "2001:4860:4860::8844", "2606:4700:4700::1111", "2606:4700:4700::1001",
        "2620:fe::fe", "2620:fe::9", "2620:119:35::35", "2620:119:53::53",
        "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff", "2a07:a8c0::", "2a07:a8c1::",
    )

    const val UNBLOCK_DELAY_SECONDS = 60 * 60L
    fun unblockSentence(en: Boolean) = if (en) "this site is not pornographic" else "este site não é pornográfico"
    fun removeSentence(en: Boolean) = if (en) "i want to remove the protection" else "quero remover a proteção"

    private val ADULT_WORDS = listOf(
        "porn", "xxx", "xvideo", "xnxx", "hentai", "onlyfans", "xhamster", "redtube",
        "youporn", "brazzers", "chaturbate", "spankbang", "stripchat", "camsoda",
        "bongacams", "livejasmin", "fansly", "rule34", "nhentai", "pornhub", "erome",
    )

    fun isObviouslyAdult(domain: String): Boolean {
        val d = domain.lowercase()
        return ADULT_WORDS.any { d.contains(it) }
    }

    private val HOST_PREFIXES = setOf("0.0.0.0", "127.0.0.1", "::", "::1", "0", "fe80::1%lo0")

    private fun okChar(c: Char) = c in 'a'..'z' || c in '0'..'9' || c == '-' || c == '.' || c == '_'

    /** Uma linha de lista (hosts, domínio puro, "*." ou "||dominio^") vira um domínio limpo, ou null. */
    fun normalize(raw: String): String? {
        var line = raw.substringBefore('#').trimStart(' ', '\t')
        if (line.isEmpty() || line[0] == '!' || line[0] == '[' || line.startsWith("@@")) return null
        if (line.startsWith("||")) {
            line = line.substring(2)
            val end = line.indexOfFirst { it == '^' || it == '/' || it == '$' }
            if (end >= 0) line = line.substring(0, end)
        }
        val parts = line.trim().split(' ', '\t').filter { it.isNotEmpty() }
        if (parts.isEmpty()) return null
        var token = parts[0]
        if (token in HOST_PREFIXES) {
            if (parts.size < 2) return null
            token = parts[1]
        }
        var d = token.lowercase()
        while (d.startsWith("*.")) d = d.substring(2)
        d = d.trim('.')
        if ('.' !in d || d.length > 253 || !d.all(::okChar)) return null
        if (d.split('.').all { p -> p.isNotEmpty() && p.all { it.isDigit() } }) return null // endereço IP
        return d
    }

    /** O que a pessoa digitou ("https://www.x.com/pagina") vira "www.x.com", ou null. */
    fun cleanSite(text: String): String? {
        var t = text.trim().lowercase()
        for (p in listOf("https://", "http://")) if (t.startsWith(p)) t = t.substring(p.length)
        t = t.substringBefore('/')
        return normalize(t)
    }
}
