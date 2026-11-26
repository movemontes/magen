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

// Used by the installer: prints "ligada", "desligada" or "desconhecida" and exits.
if CommandLine.arguments.contains("--relay-status") {
    print(PrivateRelay.isOn().map { $0 ? "ligada" : "desligada" } ?? "desconhecida")
    exit(0)
}
// Used by montar-app.sh: draws the app icon into a .iconset folder and exits.
if let i = CommandLine.arguments.firstIndex(of: "--make-iconset"), i + 1 < CommandLine.arguments.count {
    AppIconArt.writeIconset(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, MagenActions {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var blockToken: Int32 = 0
    private var lastAlert = Date.distantPast
    private var lastSeenBlockAt: Date?
    private var lastVerseIndex = -1
    private let alert = VerseAlert()
    private lazy var mainWindow = MainWindow(app: self)
    private let donate = DonatePopup()

    func applicationDidFinishLaunching(_ n: Notification) {
        Theme.registerFont()
        buildMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()

        lastSeenBlockAt = readState()?.lastBlockAt
        notify_register_dispatch(Signals.blocked, &blockToken, DispatchQueue.main) { [weak self] _ in self?.siteBlocked() }
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refreshIcon() }
        print("Magen (app) rodando. Pasta: \(magenDir.path)")

        print("Retransmissão Privada: \(PrivateRelay.isOn().map { $0 ? "ligada" : "desligada" } ?? "não sei")")
        if let tab = env["MAGEN_TEST_TAB"].flatMap(Int.init).flatMap(MainWindow.Tab.init(rawValue:)) {
            runSnapshotTest(tab)
        } else if !startedAtLogin || (PrivateRelay.isOn() == true && serviceIsOn) {
            // Opened by the person, or Private Relay needs attention: show the window.
            mainWindow.show()
            // First time: the donation note, like Treco's welcome.
            if !DonatePopup.alreadySeen && !startedAtLogin {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.donate.show() }
            }
        }
        if Updates.autoCheck { Updates.check(manual: false) }
    }

    // MARK: top menu actions

    @objc func menuAbout() { mainWindow.show(tab: .sobre) }
    @objc func menuDonate() { donate.show() }
    func showDonate() { donate.show() }
    @objc func menuUpdate() { Updates.check(manual: true) }
    @objc func menuSettings() { mainWindow.show(tab: .versiculos) }
    @objc func menuTab(_ sender: NSMenuItem) { mainWindow.show(tab: MainWindow.Tab(rawValue: sender.tag)) }
    @objc func menuSites() { mainWindow.show(tab: .sites) }
    @objc func menuUpdateLists() { requestUpdate() }
    @objc func menuVerse() { showVersePreview() }
    @objc func menuRelay() { mainWindow.show(tab: .protecao) }
    @objc func menuHelp() { mainWindow.show(tab: .protecao) }

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
        let img = Icons.buckler(size: 18, off: !on)
        img.accessibilityDescription = on ? "Magen ligado" : "Magen desligado"
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
        if PrivateRelay.isOn() == true {
            item("⚠️ Desligar a Retransmissão Privada do iCloud…", #selector(openRelaySettings))
        }
        menu.addItem(.separator())
        item("Abrir o Magen…", #selector(openWindow))
        item("Testar ou liberar um site…", #selector(openSites))
        item("Atualizar as listas agora", #selector(updateFromMenu))
        menu.addItem(.separator())
        item("Apoie o Magen (Pix)…", #selector(menuDonate))
        item("Procurar atualização…", #selector(menuUpdate))
        item("Sobre o Magen", #selector(menuAbout))
        menu.addItem(.separator())
        item("Fechar o ícone (o bloqueio continua)", #selector(quit))
    }

    static func todayKey() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }

    @objc private func openWindow() { mainWindow.show() }
    @objc private func openRelaySettings() { PrivateRelay.openSettings() }
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
        savePNG(iconSheet(), to: out.appendingPathComponent("icones.png"))
        savePNG(AppIconArt.image(size: 256), to: out.appendingPathComponent("icone-app.png"))
        for top in NSApp.mainMenu?.items ?? [] {
            print("MENU \(top.title): " + (top.submenu?.items.map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: " | ") ?? ""))
        }
        var tabs = MainWindow.Tab.allCases.filter { $0.rawValue >= first.rawValue }
        func next() {
            guard !tabs.isEmpty else {
                self.donate.show()
                if let w = NSApp.windows.first(where: { $0.title == "Apoie o Magen" }), let c = w.contentView {
                    snapshot(c, to: out.appendingPathComponent("doacao.png"))
                }
                self.donate.close()
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

/// Test picture: menu bar icons (light and dark bar, on and off) and the two pointers, enlarged.
private func iconSheet() -> NSImage {
    NSImage(size: NSSize(width: 520, height: 140), flipped: true) { _ in
        Theme.paper.setFill(); NSRect(x: 0, y: 0, width: 520, height: 140).fill()
        let bars: [(NSColor, NSColor)] = [(NSColor(white: 0.93, alpha: 1), .black), (NSColor(white: 0.15, alpha: 1), .white)]
        for (i, bar) in bars.enumerated() {
            bar.0.setFill(); NSRect(x: 10, y: 10 + CGFloat(i) * 60, width: 200, height: 50).fill()
            for (j, off) in [false, true].enumerated() {
                Icons.buckler(size: 36, off: off).tinted(bar.1)
                    .draw(in: NSRect(x: 30 + CGFloat(j) * 90, y: 17 + CGFloat(i) * 60, width: 36, height: 36))
            }
        }
        Icons.bucklerPreview(size: 110).draw(in: NSRect(x: 225, y: 15, width: 110, height: 110))
        for (k, c) in [Cursors.arrowCursor, Cursors.pressCursor].enumerated() {
            c.image.draw(in: NSRect(x: 360 + CGFloat(k) * 80, y: 30, width: 72, height: 72))
        }
        return true
    }
}

private func savePNG(_ img: NSImage, to url: URL) {
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
