import Foundation

/// Points every network service (Wi-Fi, Ethernet...) of the Mac at Magen,
/// and puts the old settings back when Magen stops.
final class SystemDNS {
    let savedFile: URL
    let ownIP = "127.0.0.1"

    init(savedFile: URL) { self.savedFile = savedFile }

    @discardableResult
    private func run(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    func services() -> [String] {
        run(["-listallnetworkservices"])
            .split(separator: "\n")
            .dropFirst() // first line is an explanation
            .map { String($0) }
            .filter { !$0.hasPrefix("*") && !$0.isEmpty } // "*" = turned off
    }

    /// "Empty" when the service gets DNS automatically from the router.
    func current(_ service: String) -> [String] {
        let out = run(["-getdnsservers", service])
        if out.contains("There aren't any DNS Servers") || out.contains("Não há") { return ["Empty"] }
        let ips = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return ips.isEmpty ? ["Empty"] : ips
    }

    private func loadSaved() -> [String: [String]] {
        guard let text = try? String(contentsOf: savedFile, encoding: .utf8) else { return [:] }
        var map = [String: [String]]()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t").map(String.init)
            if parts.count >= 2 { map[parts[0]] = Array(parts[1...]) }
        }
        return map
    }

    private func save(_ map: [String: [String]]) {
        let text = map.sorted { $0.key < $1.key }.map { ([$0.key] + $0.value).joined(separator: "\t") }.joined(separator: "\n")
        try? (text + "\n").write(to: savedFile, atomically: true, encoding: .utf8)
    }

    /// Makes sure all services use Magen. Called at start and every 30 s,
    /// so a manual DNS change is undone while Magen is on.
    func enforce() -> [String] {
        var saved = loadSaved()
        var changed = [String]()
        for s in services() {
            let cur = current(s)
            if cur == [ownIP] { continue }
            if saved[s] == nil { saved[s] = cur } // remember only the original setting
            save(saved)
            run(["-setdnsservers", s, ownIP])
            changed.append(s)
        }
        return changed
    }

    /// Puts back the DNS settings that existed before Magen.
    func restore() {
        let saved = loadSaved()
        for s in services() where current(s) == [ownIP] {
            let old = saved[s] ?? ["Empty"]
            run(["-setdnsservers", s] + old)
        }
        try? FileManager.default.removeItem(at: savedFile)
    }
}
