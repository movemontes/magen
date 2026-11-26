import Foundation

public struct DNSQuestion {
    public let id: UInt16
    /// Lowercased name without trailing dot, e.g. "www.example.com".
    public let name: [UInt8]
    public let qtype: UInt16
    /// Offset just after the question section (name + type + class).
    public let end: Int

    public var nameString: String { String(decoding: name, as: UTF8.self) }
}

public enum DNSMessage {
    /// Reads the first question of a DNS query. Returns nil if malformed.
    public static func parseQuery(_ msg: [UInt8]) -> DNSQuestion? {
        guard msg.count >= 12 else { return nil }
        let flags = UInt16(msg[2]) << 8 | UInt16(msg[3])
        if flags & 0x8000 != 0 { return nil } // it is a response, not a query
        let qdcount = UInt16(msg[4]) << 8 | UInt16(msg[5])
        guard qdcount >= 1 else { return nil }
        var i = 12
        var name = [UInt8]()
        while true {
            guard i < msg.count else { return nil }
            let len = Int(msg[i])
            if len == 0 { i += 1; break }
            if len & 0xC0 != 0 { return nil } // compression is not used in questions
            guard i + 1 + len <= msg.count, len <= 63 else { return nil }
            if !name.isEmpty { name.append(UInt8(ascii: ".")) }
            for b in msg[(i + 1)...(i + len)] {
                name.append((b >= 65 && b <= 90) ? b + 32 : b)
            }
            i += 1 + len
            if name.count > 253 { return nil }
        }
        guard i + 4 <= msg.count else { return nil }
        let qtype = UInt16(msg[i]) << 8 | UInt16(msg[i + 1])
        let id = UInt16(msg[0]) << 8 | UInt16(msg[1])
        return DNSQuestion(id: id, name: name, qtype: qtype, end: i + 4)
    }

    /// Builds an answer saying "this domain does not exist" (NXDOMAIN).
    public static func blockedResponse(query: [UInt8], question q: DNSQuestion) -> [UInt8] {
        var r = Array(query[0..<q.end])
        let rd = query[2] & 0x01
        let opcode = query[2] & 0x78
        r[2] = 0x80 | opcode | rd          // QR=1, AA=0, TC=0
        r[3] = 0x80 | 0x03                 // RA=1, RCODE=3 (NXDOMAIN)
        r[4] = 0; r[5] = 1                 // QDCOUNT=1
        r[6] = 0; r[7] = 0                 // ANCOUNT
        r[8] = 0; r[9] = 0                 // NSCOUNT
        r[10] = 0; r[11] = 0               // ARCOUNT
        return r
    }

    /// Answer used when no upstream server answered (SERVFAIL).
    public static func failureResponse(query: [UInt8], question q: DNSQuestion) -> [UInt8] {
        var r = blockedResponse(query: query, question: q)
        r[3] = 0x80 | 0x02
        return r
    }

    /// Builds a simple query (used by the `magen testar` command).
    public static func buildQuery(id: UInt16, name: String, qtype: UInt16 = 1) -> [UInt8] {
        var m: [UInt8] = [UInt8(id >> 8), UInt8(id & 0xff), 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            m.append(UInt8(bytes.count))
            m.append(contentsOf: bytes)
        }
        m.append(0)
        m.append(contentsOf: [UInt8(qtype >> 8), UInt8(qtype & 0xff), 0, 1])
        return m
    }

    public static func rcode(_ response: [UInt8]) -> Int? {
        response.count >= 4 ? Int(response[3] & 0x0f) : nil
    }

    public static func answerCount(_ response: [UInt8]) -> Int {
        response.count >= 8 ? Int(response[6]) << 8 | Int(response[7]) : 0
    }
}
