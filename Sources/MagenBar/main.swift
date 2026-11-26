// MagenBar — o ícone do Magen na barra de menus.
// Mostra se o bloqueio está ligado e, quando um site adulto é bloqueado,
// manda uma notificação com um versículo (sem dizer qual site foi).
import AppKit
import UserNotifications
import Darwin
import notify
import MagenCore

setvbuf(stdout, nil, _IOLBF, 0)
let env = ProcessInfo.processInfo.environment
let magenDir = URL(fileURLWithPath: env["MAGEN_DIR"] ?? Paths.defaultDir.path)
let dnsPort = UInt16(env["MAGEN_PORT"] ?? "") ?? 53
let magenCLI = "/usr/local/bin/magen"

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var blockToken: Int32 = 0
    private var lastNotification = Date.distantPast
    private var lastSeenBlockAt: Date?
    private var lastVerseIndex = -1
    private let defaults = UserDefaults.standard
    private let banner = Banner()
    /// True only if macOS allowed normal notifications (needs an Apple signature).
    private var systemNotificationsAllowed = false

    private var notificationsOn: Bool {
        get { defaults.object(forKey: "versiculos") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "versiculos") }
    }
    /// Minimum time between two verse notifications.
    private let minGap: TimeInterval = 60

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { ok, err in
            DispatchQueue.main.async { self.systemNotificationsAllowed = ok }
            print(ok ? "Notificações do macOS: permitidas." :
                  "Notificações do macOS indisponíveis (\(err?.localizedDescription ?? "negado")); uso o balão do Magen.")
        }

        lastSeenBlockAt = readState()?.lastBlockAt
        notify_register_dispatch(Signals.blocked, &blockToken, DispatchQueue.main) { [weak self] _ in self?.siteBlocked() }
        // Keep the icon right even if the service stops or starts.
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refreshIcon() }
        print("Magen (ícone) rodando. Pasta: \(magenDir.path)")
    }

    // MARK: state

    private func readState() -> MagenState? {
        guard let d = try? Data(contentsOf: Paths.state(magenDir)) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(MagenState.self, from: d)
    }

    /// The service rewrites its state file every 30 s while it runs.
    private var serviceIsOn: Bool {
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

    // MARK: notification

    private func siteBlocked() {
        let s = readState()
        // Ignore old news (e.g. the signal arrived twice for the same block).
        if let at = s?.lastBlockAt, let seen = lastSeenBlockAt, at <= seen { return }
        lastSeenBlockAt = s?.lastBlockAt
        guard notificationsOn, Date().timeIntervalSince(lastNotification) >= minGap else { return }
        lastNotification = Date()
        sendVerse(title: "Site bloqueado pelo Magen")
    }

    private func randomVerse() -> Verse {
        var i = Int.random(in: 0..<verses.count)
        if verses.count > 1 && i == lastVerseIndex { i = (i + 1) % verses.count }
        lastVerseIndex = i
        return verses[i]
    }

    private func sendVerse(title: String) {
        let v = randomVerse()
        guard systemNotificationsAllowed else {
            let png = env["MAGEN_BANNER_PNG"].map { URL(fileURLWithPath: $0) }
            banner.show(title: title, text: v.text, ref: v.ref, snapshotTo: png)
            print("Balão mostrado: \(v.ref)")
            return
        }
        let c = UNMutableNotificationContent()
        c.title = title
        c.subtitle = "\(v.ref) (BLIVRE)"
        c.body = v.text
        c.sound = nil
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req) { err in
            if let err { print("Não consegui mostrar a notificação: \(err.localizedDescription)") }
            else { print("Notificação enviada: \(v.ref)") }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list])
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
            info("Sites adultos na lista: \(s.domains.formatted())")
            if let u = s.lastUpdate { info("Listas atualizadas: \(u.formatted(date: .abbreviated, time: .shortened))") }
        }
        menu.addItem(.separator())
        item("Ver um versículo agora", #selector(showVerseNow))
        item("Testar um site…", #selector(testSite))
        item("Liberar um site bloqueado por engano…", #selector(allowSite))
        item("Bloquear um site a mais…", #selector(blockSite))
        item("Atualizar as listas agora", #selector(updateNow))
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: "Notificação com versículo ao bloquear", action: #selector(toggleNotifications), keyEquivalent: "")
        toggle.target = self
        toggle.state = notificationsOn ? .on : .off
        menu.addItem(toggle)
        item("Sobre o Magen e créditos", #selector(about))
        item("Fechar o ícone (o bloqueio continua)", #selector(quit))
    }

    static func todayKey() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }

    @objc private func showVerseNow() { sendVerse(title: "Um versículo para você") }

    @objc private func toggleNotifications() { notificationsOn.toggle() }

    @objc private func updateNow() {
        notify_post(Signals.updateRequest)
        alert("Pedido enviado", "As listas novas chegam em 1 ou 2 minutos. (Para não sobrecarregar, o Magen atende no máximo um pedido a cada 5 minutos.)")
    }

    @objc private func testSite() {
        guard let site = askSite("Testar um site", "Digite o endereço, por exemplo: exemplo.com") else { return }
        switch dnsCheck(site) {
        case .some(true): alert("🚫 \(site) está bloqueado", "O Magen não deixa este site abrir (ou ele não existe).")
        case .some(false): alert("✅ \(site) está liberado", "Este site abre normalmente.")
        case .none: alert("Sem resposta", "O Magen não respondeu. Ele está ligado?")
        }
    }

    @objc private func allowSite() {
        guard let site = askSite("Liberar um site", "Use só para um site que NÃO é adulto e foi bloqueado por engano.\nO Mac vai pedir a senha de administrador.") else { return }
        runAdmin(["liberar", site], done: "\(site) foi liberado.")
    }

    @objc private func blockSite() {
        guard let site = askSite("Bloquear um site a mais", "O site e tudo o que estiver dentro dele serão bloqueados.\nO Mac vai pedir a senha de administrador.") else { return }
        runAdmin(["bloquear", site], done: "\(site) agora está bloqueado.")
    }

    @objc private func about() {
        alert("Magen — escudo",
              """
              Bloqueador grátis de sites adultos. Sem conta e sem anúncios.
              Listas: OISD NSFW, Block List Project e StevenBlack.

              Versículos: \(verseCredit).
              Bíblia Livre, Copyright © Diego Santos, Mario Sérgio e Marco Teles, fevereiro de 2018. \
              Licença Creative Commons Atribuição 4.0 Brasil.
              """)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: helpers

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    private func askSite(_ title: String, _ text: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancelar")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "exemplo.com"
        a.accessoryView = field
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        var t = field.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        for p in ["https://", "http://"] where t.hasPrefix(p) { t.removeFirst(p.count) }
        if let slash = t.firstIndex(of: "/") { t = String(t[..<slash]) }
        guard let d = Domains.normalize(Substring(t)) else {
            if !t.isEmpty { alert("Endereço inválido", "Digite só o endereço, por exemplo: exemplo.com") }
            return nil
        }
        return d
    }

    /// Asks the Magen service directly. true = blocked, false = allowed, nil = no answer.
    private func dnsCheck(_ name: String) -> Bool? {
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
    private func runAdmin(_ args: [String], done: String) {
        // `args` only contain command words and a domain checked by Domains.normalize (a-z 0-9 . - _).
        let cmd = ([magenCLI] + args).joined(separator: " ")
        let script = "do shell script \"\(cmd)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
        do { try p.run() } catch { alert("Não deu certo", error.localizedDescription); return }
        p.waitUntilExit()
        if p.terminationStatus == 0 { alert("Feito", done) }
        else {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if !msg.contains("-128") { alert("Não deu certo", msg) } // -128 = the person clicked Cancel
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
