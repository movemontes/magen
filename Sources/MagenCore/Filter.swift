import Foundation

/// Decides whether a DNS name is blocked.
/// Rule order: the person's "allow" list wins, then everything else blocks.
public final class Filter {
    private let lock = NSLock()
    private var blockSet = DomainSet()
    private var allowSet = DomainSet()
    private var bypassSet = DomainSet()

    public enum Verdict { case allowed, blocked, blockedBypass }

    public init() {}

    /// `listDomains` are the domains read from downloaded lists.
    public func rebuild(listDomains: [String], config: MagenConfig) {
        var all = [String]()
        all.reserveCapacity(listDomains.count + config.block.count + BuiltIn.antiBypassDomains.count)
        for d in listDomains where !BuiltIn.neverListEntries.contains(d) { all.append(d) }
        for d in config.block { if let n = Domains.normalize(Substring(d)) { all.append(n) } }
        let newBlock = DomainSet(all)
        var bypass = config.antiBypass ? BuiltIn.antiBypassDomains : []
        if config.blockPrivateRelay { bypass += BuiltIn.privateRelayDomains }
        let newBypass = DomainSet(bypass)
        let newAllow = DomainSet(config.allow.compactMap { Domains.normalize(Substring($0)) })
        lock.lock()
        blockSet = newBlock
        bypassSet = newBypass
        allowSet = newAllow
        lock.unlock()
    }

    public var count: Int { lock.lock(); defer { lock.unlock() }; return blockSet.count + bypassSet.count }

    /// `.blockedBypass` = a "skip the filter" service, blocked silently
    /// (the system asks for these by itself, so no notification for them).
    public func verdict(_ name: [UInt8]) -> Verdict {
        lock.lock()
        let b = blockSet, a = allowSet, x = bypassSet // cheap copies (copy-on-write arrays)
        lock.unlock()
        if a.matchesSelfOrParent(name) { return .allowed }
        if x.matchesSelfOrParent(name) { return .blockedBypass }
        return b.matchesSelfOrParent(name) ? .blocked : .allowed
    }

    public func isBlocked(_ name: [UInt8]) -> Bool { verdict(name) != .allowed }

    public func isBlocked(_ name: String) -> Bool {
        var s = name.lowercased()
        while s.hasSuffix(".") { s.removeLast() }
        return isBlocked(Array(s.utf8))
    }

    /// Reads a whole downloaded list into clean domains.
    public static func parseList(_ text: String) -> [String] {
        var out = [String]()
        text.enumerateLines { line, _ in
            if let d = Domains.normalize(Substring(line)) { out.append(d) }
        }
        return out
    }
}
