import Foundation
import Darwin

func makeAddr(_ ip: String, _ port: UInt16) -> sockaddr_in? {
    var a = sockaddr_in()
    a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    a.sin_family = sa_family_t(AF_INET)
    a.sin_port = port.bigEndian
    guard inet_pton(AF_INET, ip, &a.sin_addr) == 1 else { return nil }
    return a
}

func setTimeouts(_ fd: Int32, seconds: Int) {
    var tv = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
}

func withSockaddr<T>(_ a: inout sockaddr_in, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
    withUnsafePointer(to: &a) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
}

/// Sends a query to one upstream server over UDP and waits for the answer.
func udpExchange(_ query: [UInt8], server: String, timeout: Int = 2) -> [UInt8]? {
    guard var addr = makeAddr(server, 53) else { return nil }
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    setTimeouts(fd, seconds: timeout)
    let sent = withSockaddr(&addr) { p, l in query.withUnsafeBytes { sendto(fd, $0.baseAddress, query.count, 0, p, l) } }
    guard sent == query.count else { return nil }
    var buf = [UInt8](repeating: 0, count: 65535)
    let deadline = Date().addingTimeInterval(Double(timeout))
    while Date() < deadline {
        let n = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress, 65535, 0) }
        if n <= 0 { return nil }
        // Only accept the answer to our own question (same ID).
        if n >= 12 && buf[0] == query[0] && buf[1] == query[1] { return Array(buf[0..<n]) }
    }
    return nil
}

func readExactly(_ fd: Int32, _ count: Int) -> [UInt8]? {
    var out = [UInt8](repeating: 0, count: count)
    var got = 0
    while got < count {
        let n = out.withUnsafeMutableBytes { recv(fd, $0.baseAddress! + got, count - got, 0) }
        if n <= 0 { return nil }
        got += n
    }
    return out
}

func writeAll(_ fd: Int32, _ data: [UInt8]) -> Bool {
    var sent = 0
    while sent < data.count {
        let n = data.withUnsafeBytes { send(fd, $0.baseAddress! + sent, data.count - sent, 0) }
        if n <= 0 { return false }
        sent += n
    }
    return true
}

func framed(_ msg: [UInt8]) -> [UInt8] { [UInt8(msg.count >> 8), UInt8(msg.count & 0xff)] + msg }

/// Sends a query to one upstream server over TCP (used for big answers).
func tcpExchange(_ query: [UInt8], server: String, timeout: Int = 4) -> [UInt8]? {
    guard var addr = makeAddr(server, 53) else { return nil }
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    setTimeouts(fd, seconds: timeout)
    let ok = withSockaddr(&addr) { p, l in connect(fd, p, l) }
    guard ok == 0, writeAll(fd, framed(query)) else { return nil }
    guard let lenBytes = readExactly(fd, 2) else { return nil }
    let len = Int(lenBytes[0]) << 8 | Int(lenBytes[1])
    return readExactly(fd, len)
}
