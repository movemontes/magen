// MagenBar — o app do Magen: ícone na barra de menus, janela de opções e a
// janela com versículo que aparece quando um site adulto é bloqueado.
import AppKit
import Darwin
import notify
import MagenCore

setvbuf(stdout, nil, _IOLBF, 0)
let env = ProcessInfo.processInfo.environment
let magenDir = URL(fileURLWithPath: env["MAGEN_DIR"] ?? Paths.defaultDir.path)
let dnsPort = UInt16(env["MAGEN_PORT"] ?? "") ?? 53
let magenCLI = "/usr/local/bin/magen"
let startedAtLogin = CommandLine.arguments.contains("--login")

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, MagenActions {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var blockToken: Int32 = 0
    private var lastAlert = Date.distantPast
    private var lastSeenBlockAt: Date?
    private var lastVerseIndex = -1
    private let alert = VerseAlert()
    private lazy var mainWindow = MainWindow(app: self)

    func applicationDidFinishLaunching(_ n: Notification) {
        Theme.registerFont()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()

        lastSeenBlockAt = readState()?.lastBlockAt
        notify_register_dispatch(Signals.blocked, &blockToken, DispatchQueue.main) { [weak self] _ in self?.siteBlocked() }
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refreshIcon() }
        print("Magen (app) rodando. Pasta: \(magenDir.path)")

        if let tab = env["MAGEN_TEST_TAB"].flatMap(Int.init).flatMap(MainWindow.Tab.init(rawValue:)) {
            runSnapshotTest(tab)
        } else if !startedAtLogin {
            mainWindow.show() // opened by the person (not at login): show the window
        }
    }

    /// Double-clicking Magen.app again while it runs opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show(); return false
    }

    // MARK: state

    func readState() -> MagenState? {
        guard let d = try? Data(contentsOf: Paths.state(magenDir)) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(MagenState.self, from: d)
    }

    /// The service rewrites its state file every 30 s while it runs.
    var serviceIsOn: Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: Paths.state(magenDir).path),
              let mod = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(mod) < 90 && FileManager.default.fileExists(atPath: Paths.pid(magenDir).path)
    }

    private func refreshIcon() {
        let on = serviceIsOn
        let img = NSImage(systemSymbolName: on ? "shield.lefthalf.filled" : "shield.slash",
                          accessibilityDescription: on ? "Magen ligado" : "Magen desligado")
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.toolTip = on ? "Magen: protegendo" : "Magen: desligado"
    }

    // MARK: verse window

    private func siteBlocked() {
        let s = readState()
        if let at = s?.lastBlockAt, let seen = lastSeenBlockAt, at <= seen { return } // old news
        lastSeenBlockAt = s?.lastBlockAt
        guard Prefs.versesOn, !alert.isShowing,
              Date().timeIntervalSince(lastAlert) >= Double(Prefs.gapMinutes) * 60 else { return }
        lastAlert = Date()
        let v = randomVerse()
        alert.show(v, heading: "Site bloqueado", lockSeconds: Prefs.lockSeconds,
                   snapshotTo: env["MAGEN_ALERT_PNG"].map { URL(fileURLWithPath: $0) })
        print("Janela de versículo: \(v.ref)")
    }

    func showVersePreview() {
        alert.show(randomVerse(), heading: "Exemplo", lockSeconds: min(Prefs.lockSeconds, 3))
    }

    private func randomVerse() -> Verse {
        var i = Int.random(in: 0..<verses.count)
        if verses.count > 1 && i == lastVerseIndex { i = (i + 1) % verses.count }
        lastVerseIndex = i
        return verses[i]
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let on = serviceIsOn
        let s = readState()
        func info(_ t: String) { let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i) }
        func item(_ t: String, _ sel: Selector) { let i = NSMenuItem(title: t, action: sel, keyEquivalent: ""); i.target = self; menu.addItem(i) }

        info(on ? "✅ Magen está protegendo este Mac" : "⚠️ Magen está desligado")
        if let s {
            let today = s.todayKey == Self.todayKey() ? s.blockedToday : 0
            info("Bloqueios hoje: \(today.formatted())")
        }
        menu.addItem(.separator())
        item("Abrir o Magen…", #selector(openWindow))
        item("Testar ou liberar um site…", #selector(openSites))
        item("Atualizar as listas agora", #selector(updateFromMenu))
        menu.addItem(.separator())
        item("Fechar o ícone (o bloqueio continua)", #selector(quit))
    }

    static func todayKey() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }

    @objc private func openWindow() { mainWindow.show() }
    @objc private func openSites() { mainWindow.show(tab: .sites) }
    @objc private func updateFromMenu() { requestUpdate() }
    @objc private func quit() { NSApp.terminate(nil) }

    func requestUpdate() {
        notify_post(Signals.updateRequest)
        message("Pedido enviado", "As listas novas chegam em 1 ou 2 minutos. (O Magen atende no máximo um pedido a cada 5 minutos.)")
    }

    // MARK: helpers

    private func message(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    /// Asks the Magen service directly. true = blocked, false = allowed, nil = no answer.
    func dnsCheck(_ name: String) -> Bool? {
        let q = DNSMessage.buildQuery(id: UInt16.random(in: 1...65000), name: name)
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); a.sin_family = sa_family_t(AF_INET); a.sin_port = dnsPort.bigEndian
        inet_pton(AF_INET, "127.0.0.1", &a.sin_addr)
        let fd = socket(AF_INET, SOCK_DGRAM, 0); defer { close(fd) }
        var tv = timeval(tv_sec: 4, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let sent = withUnsafePointer(to: &a) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
            q.withUnsafeBytes { sendto(fd, $0.baseAddress, q.count, 0, sp, socklen_t(MemoryLayout<sockaddr_in>.size)) } } }
        guard sent == q.count else { return nil }
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress, 4096, 0) }
        guard n > 0 else { return nil }
        let r = Array(buf[0..<n])
        return DNSMessage.rcode(r) == 3 && DNSMessage.answerCount(r) == 0
    }

    /// Runs `magen …` as administrator. macOS shows its own password window.
    func runAdmin(_ args: [String], done: String, then: (() -> Void)?) {
        // `args` only hold fixed command words and domains checked by Domains.normalize (a-z 0-9 . - _).
        let cmd = ([magenCLI] + args).joined(separator: " ")
        let script = "do shell script \"\(cmd)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
        do { try p.run() } catch { message("Não deu certo", error.localizedDescription); return }
        p.waitUntilExit()
        if p.terminationStatus == 0 {
            // The service reloads in the background; give it a moment before redrawing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { then?() }
        } else {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if !msg.contains("-128") { message("Não deu certo", msg) } // -128 = the person clicked Cancel
        }
    }

    // MARK: test helper (MAGEN_TEST_TAB / MAGEN_TEST_OUT): saves pictures, then quits

    private func runSnapshotTest(_ first: MainWindow.Tab) {
        let out = URL(fileURLWithPath: env["MAGEN_TEST_OUT"] ?? NSTemporaryDirectory())
        var tabs = MainWindow.Tab.allCases.filter { $0.rawValue >= first.rawValue }
        func next() {
            guard !tabs.isEmpty else {
                let v = verses.first { $0.ref == "1 Coríntios 10:13" } ?? verses[0]
                alert.show(v, heading: "Site bloqueado", lockSeconds: 5, snapshotTo: out.appendingPathComponent("janela-versiculo.png"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.alert.close(); NSApp.terminate(nil) }
                return
            }
            let t = tabs.removeFirst()
            mainWindow.show(tab: t)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let v = self.mainWindow.window.contentView {
                    snapshot(v, to: out.appendingPathComponent("aba-\(t.rawValue)-\(t.title).png"))
                }
                next()
            }
        }
        next()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
