import Foundation
import Darwin
import MagenCore

final class DNSServer {
    let filter: Filter
    var upstream: [String]
    private let work = DispatchQueue(label: "magen.work", attributes: .concurrent)
    private let limiter = DispatchSemaphore(value: 256) // at most 256 lookups at once
    private let counterLock = NSLock()
    private(set) var blockedCount = 0

    init(filter: Filter, upstream: [String]) {
        self.filter = filter
        self.upstream = upstream
    }

    /// Answers one query: blocked → NXDOMAIN, otherwise asks the real DNS.
    func answer(_ query: [UInt8], overTCP: Bool) -> [UInt8]? {
        guard let q = DNSMessage.parseQuery(query) else {
            return forward(query, overTCP: overTCP) // unusual query: pass it on untouched
        }
        if filter.isBlocked(q.name) {
            counterLock.lock(); blockedCount += 1; counterLock.unlock()
            return DNSMessage.blockedResponse(query: query, question: q)
        }
        return forward(query, overTCP: overTCP) ?? DNSMessage.failureResponse(query: query, question: q)
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
                limiter.wait()
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
                limiter.wait()
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
