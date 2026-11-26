import Foundation

public struct MagenConfig: Codable {
    /// DNS servers that answer the questions Magen does not block.
    public var upstream: [String] = ["1.1.1.1", "1.0.0.1", "9.9.9.9"]
    /// Blocklists downloaded automatically.
    public var lists: [String] = MagenConfig.defaultLists
    /// Sites the person chose to unblock (they and their subdomains).
    public var allow: [String] = []
    /// Sites asked to be unblocked; each one only becomes "allowed" after the wait.
    public var pendingAllow: [PendingAllow] = []
    /// Extra sites the person chose to block (they and their subdomains).
    public var block: [String] = []
    /// Block tricks that skip Magen (browser "secure DNS", iCloud Private Relay).
    public var antiBypass: Bool = true
    /// Block iCloud Private Relay (macOS then shows a warning once per network).
    public var blockPrivateRelay: Bool = true
    /// Hours between list updates.
    public var updateEveryHours: Double = 24

    public init() {}

    public static let defaultLists = [
        "https://nsfw.oisd.nl/domainswild2",
        "https://blocklistproject.github.io/Lists/alt-version/porn-nl.txt",
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts",
    ]

    // Tolerant decoding: missing keys keep their default value.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MagenConfig()
        upstream = try c.decodeIfPresent([String].self, forKey: .upstream) ?? d.upstream
        lists = try c.decodeIfPresent([String].self, forKey: .lists) ?? d.lists
        allow = try c.decodeIfPresent([String].self, forKey: .allow) ?? d.allow
        pendingAllow = try c.decodeIfPresent([PendingAllow].self, forKey: .pendingAllow) ?? d.pendingAllow
        block = try c.decodeIfPresent([String].self, forKey: .block) ?? d.block
        antiBypass = try c.decodeIfPresent(Bool.self, forKey: .antiBypass) ?? d.antiBypass
        blockPrivateRelay = try c.decodeIfPresent(Bool.self, forKey: .blockPrivateRelay) ?? d.blockPrivateRelay
        updateEveryHours = try c.decodeIfPresent(Double.self, forKey: .updateEveryHours) ?? d.updateEveryHours
    }

    public static func load(from url: URL) -> MagenConfig {
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(MagenConfig.self, from: data) else { return MagenConfig() }
        return cfg
    }

    public func save(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}

public struct PendingAllow: Codable, Equatable {
    public var domain: String
    /// When it becomes allowed.
    public var at: Date
    public init(domain: String, at: Date) { self.domain = domain; self.at = at }
}

/// Rules that make unblocking a site hard on purpose.
public enum Unblock {
    /// Wait between asking and the site really opening.
    public static let delay: TimeInterval = 60 * 60
    /// The exact sentence the person must type in the app.
    public static let sentence = "este site não é pornográfico"

    /// Names that are obviously adult: these can never be unblocked.
    private static let words = ["porn", "xxx", "xvideo", "xnxx", "hentai", "onlyfans", "xhamster", "redtube",
                                "youporn", "brazzers", "chaturbate", "spankbang", "stripchat", "camsoda",
                                "bongacams", "livejasmin", "fansly", "rule34", "nhentai", "pornhub", "erome"]
    public static func isObviouslyAdult(_ domain: String) -> Bool {
        let d = domain.lowercased()
        return words.contains { d.contains($0) }
    }

    /// Moves the sites whose wait is over from `pendingAllow` to `allow`. Returns the moved ones.
    public static func applyDue(_ c: inout MagenConfig, now: Date = Date()) -> [String] {
        let due = c.pendingAllow.filter { $0.at <= now }.map(\.domain)
        guard !due.isEmpty else { return [] }
        c.pendingAllow.removeAll { $0.at <= now }
        for d in due where !c.allow.contains(d) { c.allow.append(d) }
        return due
    }
}

public struct MagenState: Codable {
    public var domains: Int = 0
    public var lastUpdate: Date? = nil
    public var lists: [ListResult] = []
    public var blockedSinceStart: Int = 0
    public var startedAt: Date? = nil
    /// Counters for the menu bar (only adult-site blocks, not anti-bypass ones).
    public var blockedTotal: Int = 0
    public var blockedToday: Int = 0
    public var todayKey: String = ""
    public var lastBlockAt: Date? = nil

    public struct ListResult: Codable {
        public var url: String
        public var ok: Bool
        public var count: Int
        public init(url: String, ok: Bool, count: Int) { self.url = url; self.ok = ok; self.count = count }
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        domains = try c.decodeIfPresent(Int.self, forKey: .domains) ?? 0
        lastUpdate = try c.decodeIfPresent(Date.self, forKey: .lastUpdate)
        lists = try c.decodeIfPresent([ListResult].self, forKey: .lists) ?? []
        blockedSinceStart = try c.decodeIfPresent(Int.self, forKey: .blockedSinceStart) ?? 0
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        blockedTotal = try c.decodeIfPresent(Int.self, forKey: .blockedTotal) ?? 0
        blockedToday = try c.decodeIfPresent(Int.self, forKey: .blockedToday) ?? 0
        todayKey = try c.decodeIfPresent(String.self, forKey: .todayKey) ?? ""
        lastBlockAt = try c.decodeIfPresent(Date.self, forKey: .lastBlockAt)
    }
}

/// Darwin notification names (system-wide, they carry no data).
public enum Signals {
    /// Posted by the service when an adult site was blocked (at most once per second).
    public static let blocked = "io.github.movemontes.magen.blocked"
    /// Posted by anyone to ask for a list update (the service limits how often).
    public static let updateRequest = "io.github.movemontes.magen.update-request"
}

public enum Paths {
    public static let defaultDir = URL(fileURLWithPath: "/Library/Application Support/Magen")
    public static func config(_ dir: URL) -> URL { dir.appendingPathComponent("config.json") }
    public static func state(_ dir: URL) -> URL { dir.appendingPathComponent("state.json") }
    public static func cache(_ dir: URL) -> URL { dir.appendingPathComponent("blocklist-cache.txt") }
    public static func pid(_ dir: URL) -> URL { dir.appendingPathComponent("magend.pid") }
    public static func savedDNS(_ dir: URL) -> URL { dir.appendingPathComponent("dns-anterior.txt") }
}

public enum BuiltIn {
    /// Never accept these as list entries. A list entry also blocks all
    /// subdomains, so a broken list containing e.g. "com.br" or "google.com"
    /// would otherwise break huge parts of the internet. Subdomains listed on
    /// their own (like "some-adult-blog.tumblr.com") are still blocked.
    public static let neverListEntries: Set<String> = [
        // multi-part public suffixes
        "com.br", "net.br", "org.br", "gov.br", "edu.br", "art.br", "blog.br", "co.uk", "org.uk",
        "com.au", "co.jp", "co.nz", "com.mx", "com.ar", "com.pt", "co.za", "co.in", "com.tr",
        // big platforms and shared hosting
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
        // Found wrongly blocked when checking the 2,000 most visited sites (Nov 2026)
        "xiaohongshu.com", "ekstrabladet.dk", "suruga-ya.jp", "character.ai", "gotinder.com",
        "tinder.com", "sslip.io", "nip.io",
    ]

    /// iCloud Private Relay: Apple's documented way for a network to turn it off.
    public static let privateRelayDomains: [String] = ["mask.icloud.com", "mask-h2.icloud.com"]

    /// Blocked when `antiBypass` is on. These are ways a browser or the
    /// system can look up sites without asking Magen.
    public static let antiBypassDomains: [String] = [
        // Firefox: this "canary" domain tells it not to turn on DNS-over-HTTPS by itself
        "use-application-dns.net",
        // iCloud Private Relay (Apple documents this way for networks to turn it off)
        // Common DNS-over-HTTPS / DNS-over-TLS servers used by browser "secure DNS"
        "dns.google", "dns.google.com", "dns64.dns.google",
        "cloudflare-dns.com", "one.one.one.one", "1dot1dot1dot1.cloudflare-dns.com",
        "dns.quad9.net", "dns9.quad9.net", "dns10.quad9.net", "dns11.quad9.net", "dns12.quad9.net",
        "doh.opendns.com", "dns.opendns.com", "doh.familyshield.opendns.com",
        "dns.adguard.com", "dns.adguard-dns.com", "dns-unfiltered.adguard.com",
        "dns.nextdns.io", "doh.cleanbrowsing.org", "doh.mullvad.net", "dns.mullvad.net",
        "doh.dns.sb", "dns.controld.com", "freedns.controld.com", "doh.libredns.gr",
        "dns.alidns.com", "doh.pub", "dns.twnic.tw", "chrome.cloudflare-dns.com",
        "mozilla.cloudflare-dns.com", "doh.xfinity.com", "dns.brahma.world",
    ]
}
