import Foundation
import Darwin
import MagenCore

final class DNSServer {
    let filter: Filter
    var upstream: [String]
    private let work = DispatchQueue(label: "magen.work", attributes: .concurrent)
    private let limiter = DispatchSemaphore(value: 48) // lookups at once (each one waits on the network)
    private let cacheLock = NSLock()
    /// Short answer cache: same question within 30 s → same answer, without asking again.
    private var cache: [ArraySlice<UInt8>: (answer: [UInt8], until: Date)] = [:]
    private let failLock = NSLock()
    private(set) var upstreamFailures = 0
    private(set) var droppedBusy = 0

    /// Returns and resets the failure counters (for the log).
    func takeFailureCounts() -> (failed: Int, dropped: Int) {
        failLock.lock(); defer { failLock.unlock() }
        let r = (upstreamFailures, droppedBusy)
        upstreamFailures = 0; droppedBusy = 0
        return r
    }
    private let counterLock = NSLock()
    private(set) var blockedCount = 0
    /// Called (on a work thread) each time an adult site is blocked.
    var onAdultBlock: (() -> Void)?

    init(filter: Filter, upstream: [String]) {
        self.filter = filter
        self.upstream = upstream
    }

    /// Answers one query: blocked → NXDOMAIN, otherwise asks the real DNS.
    func answer(_ query: [UInt8], overTCP: Bool) -> [UInt8]? {
        guard let q = DNSMessage.parseQuery(query) else {
            return forward(query, overTCP: overTCP) // unusual query: pass it on untouched
        }
        switch filter.verdict(q.name) {
        case .blocked:
            counterLock.lock(); blockedCount += 1; counterLock.unlock()
            onAdultBlock?()
            return DNSMessage.blockedResponse(query: query, question: q)
        case .blockedBypass:
            return DNSMessage.blockedResponse(query: query, question: q)
        case .allowed:
            break
        }
        let key = query[2...] // the question without its ID
        cacheLock.lock()
        if let hit = cache[key], hit.until > Date() {
            cacheLock.unlock()
            var r = hit.answer
            r[0] = query[0]; r[1] = query[1]
            return r
        }
        cacheLock.unlock()
        guard let r = forward(query, overTCP: overTCP) else {
            failLock.lock(); upstreamFailures += 1; failLock.unlock()
            return DNSMessage.failureResponse(query: query, question: q)
        }
        // Keep good answers and "does not exist" answers; never keep truncated ones.
        if let rc = DNSMessage.rcode(r), (rc == 0 || rc == 3), r.count > 3, r[2] & 0x02 == 0 {
            cacheLock.lock()
            if cache.count > 20_000 { cache.removeAll(keepingCapacity: true) }
            cache[key] = (r, Date().addingTimeInterval(30))
            cacheLock.unlock()
        }
        return r
    }

    private func forward(_ query: [UInt8], overTCP: Bool) -> [UInt8]? {
        for server in upstream {
            if overTCP {
                if let r = tcpExchange(query, server: server) { return r }
            } else if let r = udpExchange(query, server: server) {
                // Answer too big for UDP: the client will retry over TCP by itself.
                return r
            }
        }
        return nil
    }

    // MARK: UDP

    func startUDP(ip: String, port: UInt16) throws {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw err("socket UDP") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        guard var addr = makeAddr(ip, port) else { throw err("endereço") }
        guard withSockaddr(&addr, { bind(fd, $0, $1) }) == 0 else { throw err("bind UDP \(ip):\(port)") }
        Thread.detachNewThread { [self] in
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                var from = sockaddr_storage()
                var fromLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
                let n = buf.withUnsafeMutableBytes { b in
                    withUnsafeMutablePointer(to: &from) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, b.baseAddress, 4096, 0, $0, &fromLen) }
                    }
                }
                if n < 12 { continue }
                let query = Array(buf[0..<n])
                let client = from
                // If everything is busy (slow network), drop this one instead of freezing:
                // the Mac asks again by itself in a moment.
                if limiter.wait(timeout: .now() + 0.3) == .timedOut {
                    failLock.lock(); droppedBusy += 1; failLock.unlock()
                    continue
                }
                work.async { [self] in
                    defer { limiter.signal() }
                    guard let resp = answer(query, overTCP: false) else { return }
                    var c = client
                    _ = resp.withUnsafeBytes { r in
                        withUnsafePointer(to: &c) {
                            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, r.baseAddress, resp.count, 0, $0, fromLen) }
                        }
                    }
                }
            }
        }
    }

    // MARK: TCP

    func startTCP(ip: String, port: UInt16) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw err("socket TCP") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        guard var addr = makeAddr(ip, port) else { throw err("endereço") }
        guard withSockaddr(&addr, { bind(fd, $0, $1) }) == 0 else { throw err("bind TCP \(ip):\(port)") }
        guard listen(fd, 64) == 0 else { throw err("listen TCP") }
        Thread.detachNewThread { [self] in
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { continue }
                if limiter.wait(timeout: .now() + 2) == .timedOut { close(c); continue }
                work.async { [self] in
                    defer { close(c); limiter.signal() }
                    setTimeouts(c, seconds: 10)
                    while let lb = readExactly(c, 2) {
                        let len = Int(lb[0]) << 8 | Int(lb[1])
                        guard len >= 12, let q = readExactly(c, len),
                              let resp = answer(q, overTCP: true),
                              writeAll(c, framed(resp)) else { return }
                    }
                }
            }
        }
    }

    private func err(_ what: String) -> NSError {
        NSError(domain: "Magen", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "\(what): \(String(cString: strerror(errno)))"])
    }
}
