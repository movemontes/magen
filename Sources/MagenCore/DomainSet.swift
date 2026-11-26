import Foundation

/// 64-bit FNV-1a hash of ASCII bytes (lowercased by the caller).
@inline(__always)
public func fnv1a<C: Collection>(_ bytes: C) -> UInt64 where C.Element == UInt8 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in bytes {
        h ^= UInt64(b)
        h = h &* 0x100000001b3
    }
    return h
}

/// A compact set of domains stored as sorted 64-bit hashes.
/// About 8 bytes per domain, so ~1.5 million domains fit in ~12 MB.
public struct DomainSet {
    private var hashes: [UInt64]

    public init() { hashes = [] }

    public init<S: Sequence>(_ domains: S) where S.Element == String {
        var hs = [UInt64]()
        for d in domains { hs.append(fnv1a(Array(d.utf8))) }
        hs.sort()
        var unique = [UInt64]()
        unique.reserveCapacity(hs.count)
        for h in hs where unique.last != h { unique.append(h) }
        hashes = unique
    }

    public var count: Int { hashes.count }

    public func contains(hash h: UInt64) -> Bool {
        var lo = 0, hi = hashes.count - 1
        while lo <= hi {
            let mid = (lo + hi) >> 1
            let v = hashes[mid]
            if v == h { return true }
            if v < h { lo = mid + 1 } else { hi = mid - 1 }
        }
        return false
    }

    public func contains(_ domain: String) -> Bool {
        contains(hash: fnv1a(Array(domain.lowercased().utf8)))
    }

    /// True if `name` or any parent domain (except the bare TLD) is in the set.
    /// `name` must be lowercased ASCII bytes without a trailing dot.
    public func matchesSelfOrParent(_ name: [UInt8]) -> Bool {
        if hashes.isEmpty || name.isEmpty { return false }
        var start = 0
        while true {
            guard let dot = name[start...].firstIndex(of: UInt8(ascii: ".")) else {
                return false // only the TLD is left
            }
            if contains(hash: fnv1a(name[start...])) { return true }
            start = dot + 1
        }
    }
}

public enum Domains {
    /// Turns one line of a blocklist (hosts, plain domains, wildcard or
    /// adblock "||domain^" style) into a clean domain, or nil.
    public static func normalize(_ rawLine: Substring) -> String? {
        var line = rawLine
        if let hash = line.firstIndex(of: "#") { line = line[..<hash] }
        line = line.drop(while: { $0 == " " || $0 == "\t" })
        if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { return nil }
        if line.hasPrefix("@@") { return nil } // adblock exception rule
        if line.hasPrefix("||") {
            line = line.dropFirst(2)
            if let caret = line.firstIndex(where: { $0 == "^" || $0 == "/" || $0 == "$" }) {
                line = line[..<caret]
            }
        }
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" })
        guard let first = parts.first else { return nil }
        var token = first
        if ["0.0.0.0", "127.0.0.1", "::", "::1", "0", "fe80::1%lo0"].contains(String(first)) {
            guard parts.count >= 2 else { return nil }
            token = parts[1]
        }
        var d = token.lowercased()
        while d.hasPrefix("*.") { d.removeFirst(2) }
        while d.hasPrefix(".") { d.removeFirst() }
        while d.hasSuffix(".") { d.removeLast() }
        guard d.contains("."), d.count <= 253 else { return nil }
        for c in d.utf8 {
            let ok = (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 45 || c == 46 || c == 95
            if !ok { return nil }
        }
        if d.split(separator: ".").allSatisfy({ $0.allSatisfy(\.isNumber) }) { return nil } // IP address
        return d
    }
}
