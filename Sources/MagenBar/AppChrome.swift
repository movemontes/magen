// Ícone do app, menus da barra de cima (ao lado da maçã), pop-up de doação
// e atualização (por enquanto só um aviso).
import AppKit
import MagenCore

enum Author {
    static let name = "Mateus"
    /// Same Pix key as Treco (random key, PicPay: shows no CPF or phone).
    static let pix = "e2a1f4a9-ebfe-4c3c-a531-92a0e7433f14"
}

var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }

// MARK: - App icon (Dock and Finder), like Treco's: colored tile, white letter with a black hard shadow

enum AppIconArt {
    /// Pictures that ship inside the app (Resources/icone): the buckler with "M".
    static func bundled(_ name: String) -> NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(name) else { return nil }
        return NSImage(contentsOf: url)
    }
    static var shield: NSImage? { bundled("escudo-512.png") }

    static func image(size: CGFloat) -> NSImage {
        if let img = bundled("icone-1024.png") { return img }
        return drawn(size: size)
    }

    /// Old drawn icon (red tile with "M"), used only if the picture is missing.
    static func drawn(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let k = size / 1024
            let body = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
            Theme.red.setFill()
            NSBezierPath(roundedRect: body, xRadius: 185 * k, yRadius: 185 * k).fill()
            let font = Theme.wide(430 * k)
            let line = { (color: NSColor) in
                CTLineCreateWithAttributedString(NSAttributedString(string: "M", attributes: [.font: font, .foregroundColor: color]))
            }
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let white = line(.white), black = line(.black)
            let b = CTLineGetImageBounds(white, ctx)
            let x = body.midX - b.width / 2 - b.minX - 14 * k
            let y = body.midY - b.height / 2 - b.minY + 14 * k
            ctx.textPosition = CGPoint(x: x + 28 * k, y: y - 28 * k)
            CTLineDraw(black, ctx)
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(white, ctx)
            return true
        }
    }

    /// Writes a .iconset folder (used by montar-app.sh with `iconutil`).
    static func writeIconset(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = CGFloat(base * scale)
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                drawn(size: px).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
                NSGraphicsContext.restoreGraphicsState()
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
            }
        }
    }
}

// MARK: - Dock: the icon shows only while the Magen window is open

enum Dock {
    static func show() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.applicationIconImage = AppIconArt.image(size: 512)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    /// "Sumir do Dock ao fechar": on by default (Magen keeps running in the menu bar).
    static var hideOnClose: Bool {
        get { UserDefaults.standard.object(forKey: "sumirDoDock") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sumirDoDock") }
    }
    static func hide() {
        guard hideOnClose else { return }
        DispatchQueue.main.async {
            let visible = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
            if !visible { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

// MARK: - Donation pop-up (like Treco's welcome note)

final class DonatePopup: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var copyButton: BoxButton?
    static let seenKey = "doacaoVista"
    static let version = 1 // raise to show it once more to everyone

    static var alreadySeen: Bool { (UserDefaults.standard.object(forKey: seenKey) as? Int ?? 0) >= version }

    func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let width: CGFloat = 460, pad: CGFloat = 22
        let inner = width - Theme.shadow, textW = inner - pad * 2
        let card = CardView()
        var y: CGFloat = 22
        func place(_ v: NSView, h: CGFloat? = nil, gap: CGFloat = 8) {
            let height = h ?? ((v as? NSTextField).map { textHeight($0, width: textW) } ?? v.frame.height)
            v.frame = NSRect(x: pad, y: y, width: textW, height: height)
            card.addSubview(v)
            y += height + gap
        }
        place(Theme.label("ME AJUDA: TENHO 5 BOCAS PRA ALIMENTAR", size: 18, bold: true, color: Theme.red, wrap: textW, wide: true), gap: 6)
        place(Theme.label("e fiz esse app de graça pra você.", size: 13, bold: true, wrap: textW), gap: 14)
        place(Theme.label(trf("Oi, eu sou o %@. O Magen não tem anúncio, não pede conta e não manda nada seu pra internet.", Author.name),
                          size: 12, color: Theme.dark, wrap: textW), gap: 10)
        if Lang.isEnglish {
            // English: no Pix (Brazil only). Just the thanks, until a dollar option exists.
            place(Theme.label("Se ele te ajudar nessa luta, o melhor apoio é mostrar o Magen para alguém que precisa. Obrigado de coração!",
                              size: 12, color: Theme.dark, wrap: textW), gap: 20)
            let ok = BoxButton("Bora usar") { [weak self] in self?.close() }
            ok.accent = true
            ok.frame = NSRect(x: pad, y: y, width: textW, height: 40)
            card.addSubview(ok)
        } else {
            place(Theme.label("Se ele te ajudar nessa luta, qualquer valor ajuda muito aqui em casa. Obrigado de coração!",
                              size: 12, color: Theme.dark, wrap: textW), gap: 16)
            place(Theme.label("Pix (chave aleatória, PicPay):", size: 12, bold: true), gap: 4)
            let key = Theme.label(Author.pix, size: 12, color: Theme.red)
            key.isSelectable = true
            place(key, gap: 20)
            let gap: CGFloat = 10, bw = (textW - gap) / 2
            let later = BoxButton("Bora usar") { [weak self] in self?.close() }
            let copy = BoxButton("Copiar chave Pix") { [weak self] in self?.copyPix() }
            copy.accent = true
            later.frame = NSRect(x: pad, y: y, width: bw, height: 40)
            copy.frame = NSRect(x: pad + bw + gap, y: y, width: bw, height: 40)
            card.addSubview(later); card.addSubview(copy)
            copyButton = copy
        }
        y += 40 + pad
        card.frame = NSRect(x: 0, y: 0, width: width, height: y + Theme.shadow)
        card.cursor = Cursors.arrowCursor

        let w = NSWindow(contentRect: card.frame, styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = tr("Apoie o Magen")
        w.isMovableByWindowBackground = true
        w.backgroundColor = Theme.paper
        w.appearance = NSAppearance(named: .aqua)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = card
        w.center()
        window = w
        Dock.show()
        w.makeKeyAndOrderFront(nil)
    }

    private func copyPix() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Author.pix, forType: .string)
        copyButton?.title = tr("Copiado!")
    }

    func close() { window?.close() }

    func windowWillClose(_ n: Notification) {
        UserDefaults.standard.set(Self.version, forKey: Self.seenKey)
        window = nil
        Dock.hide()
    }
}

// MARK: - Updates (GitHub releases, like Treco's updater)

enum Updates {
    static let repo = "movemontes/magen"
    static let releasesPage = URL(string: "https://github.com/movemontes/magen/releases/latest")!
    private static let d = UserDefaults.standard

    static var autoCheck: Bool {
        get { d.object(forKey: "atualizarSozinho") as? Bool ?? true }
        set { d.set(newValue, forKey: "atualizarSozinho") }
    }
    private static var lastCheck: Date {
        get { d.object(forKey: "ultimaProcura") as? Date ?? .distantPast }
        set { d.set(newValue, forKey: "ultimaProcura") }
    }
    private static var skipped: String? {
        get { d.string(forKey: "versaoPulada") }
        set { d.set(newValue, forKey: "versaoPulada") }
    }
    static var busy = false

    struct Release { let version: String; let notes: String; let dmg: URL }

    /// "1.10" > "1.9"; missing parts count as 0.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Only the part of the notes in the app's language (between <!-- pt --> and <!-- /pt -->), as plain text.
    static func notesPart(_ body: String) -> String {
        let lang = Lang.current
        var text = body
        if let a = body.range(of: "<!-- \(lang) -->"), let b = body.range(of: "<!-- /\(lang) -->"), a.upperBound <= b.lowerBound {
            text = String(body[a.upperBound..<b.lowerBound])
        }
        return text.replacingOccurrences(of: "**", with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("- ") ? "• " + $0.dropFirst(2) : String($0) }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Uses Apple's own /usr/bin/curl: some antivirus/firewall apps (e.g. Kaspersky) block
    /// the network for apps without a paid Apple signature, but never for curl.
    static func curl(_ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        p.arguments = ["-sSfL", "--max-time", "300", "-A", "Magen/\(appVersion)"] + args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }

    static func fetchLatest(_ done: @escaping (Release?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var result: Release?
            if let data = curl(["--max-time", "20", "-H", "Accept: application/vnd.github+json",
                                "https://api.github.com/repos/\(repo)/releases/latest"]),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String,
               let assets = json["assets"] as? [[String: Any]],
               let asset = assets.first(where: { ($0["name"] as? String) == "Magen-mac.dmg" })
                    ?? assets.first(where: { ($0["name"] as? String)?.hasSuffix("-mac.dmg") == true }),
               let link = asset["browser_download_url"] as? String, let url = URL(string: link) {
                let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                result = Release(version: v, notes: notesPart(json["body"] as? String ?? ""), dmg: url)
            }
            if result == nil { result = fetchLatestWithoutAPI() }
            DispatchQueue.main.async { done(result) }
        }
    }

    /// Fallback when the GitHub API refuses (it allows 60 checks per hour per internet
    /// connection): the public page /releases/latest redirects to /releases/tag/v<version>,
    /// and the .dmg has a fixed address. No notes in this case.
    static func fetchLatestWithoutAPI() -> Release? {
        guard let data = curl(["--max-time", "20", "-o", "/dev/null", "-w", "%{url_effective}",
                               "https://github.com/\(repo)/releases/latest"]),
              let final = String(data: data, encoding: .utf8),
              let range = final.range(of: "/releases/tag/") else { return nil }
        var tag = String(final[range.upperBound...])
        if tag.hasPrefix("v") { tag.removeFirst() }
        guard !tag.isEmpty, tag.allSatisfy({ $0.isNumber || $0 == "." }),
              let dmg = URL(string: "https://github.com/\(repo)/releases/latest/download/Magen-mac.dmg") else { return nil }
        return Release(version: tag, notes: "", dmg: dmg)
    }

    /// Automatic: at most once a day, quiet unless there is a new version.
    /// Manual (menu / button): always answers.
    static func check(manual: Bool) {
        if !manual {
            guard autoCheck, Date().timeIntervalSince(lastCheck) > 20 * 3600 else { return }
        }
        guard !busy else { return }
        lastCheck = Date()
        fetchLatest { rel in
            guard let rel, isNewer(rel.version, than: appVersion) else {
                if manual {
                    Service.alert(rel == nil ? tr("Não deu para procurar agora") : tr("Você está com a versão mais nova"),
                                  rel == nil ? tr("Confira a internet e tente de novo mais tarde.") : trf("Magen %@.", appVersion))
                }
                return
            }
            if !manual && skipped == rel.version { return }
            offer(rel)
        }
    }

    private static func offer(_ rel: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = trf("Saiu o Magen %@", rel.version)
        a.informativeText = trf("Você está com a versão %@.", appVersion) + (rel.notes.isEmpty ? "" : "\n\n" + rel.notes)
        a.addButton(withTitle: tr("Atualizar agora"))
        a.addButton(withTitle: tr("Depois"))
        a.addButton(withTitle: tr("Pular esta versão"))
        switch a.runModal() {
        case .alertFirstButtonReturn: install(rel)
        case .alertThirdButtonReturn: skipped = rel.version
        default: break
        }
    }

    /// Downloads the .dmg, then swaps the app (old one goes to the Trash) and reopens it.
    /// With the protection on, the new service is installed too (one password).
    static func install(_ rel: Release) {
        busy = true
        downloadAndMount(rel) { newApp, mount in
            guard let newApp else { fail(); return }
            swap(to: newApp) { done in
                run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
                busy = false
                if done { relaunch() } else { fail() }
            }
        }
    }

    /// Downloads the release .dmg and opens it (read-only, hidden from Finder).
    /// Calls back on the main thread with the Magen.app inside, or nil.
    static func downloadAndMount(_ rel: Release, _ done: @escaping (URL?, URL) -> Void) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("magen-update-\(rel.version)")
        let mount = tmp.appendingPathComponent("disco")
        try? FileManager.default.removeItem(at: tmp)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let dmg = tmp.appendingPathComponent("Magen-mac.dmg")
            var app: URL?
            if curl(["-o", dmg.path, rel.dmg.absoluteString]) != nil,
               run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path]) {
                let candidate = mount.appendingPathComponent("Magen.app")
                if FileManager.default.fileExists(atPath: candidate.path + "/Contents/Resources/servico/instalar-servico.sh") { app = candidate }
            }
            DispatchQueue.main.async { done(app, mount) }
        }
    }

    private static func swap(to newApp: URL, done: @escaping (Bool) -> Void) {
        if Service.isInstalled {
            let pid = String(ProcessInfo.processInfo.processIdentifier)
            Service.runAsAdmin(["/bin/bash", newApp.path + "/Contents/Resources/servico/instalar-servico.sh", newApp.path, "--from-app", pid]) { ok, _, _ in done(ok) }
            return
        }
        // Protection off: just replace the app where it is (the old one goes to the Trash).
        let target = URL(fileURLWithPath: "/Applications/Magen.app")
        do {
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.trashItem(at: target, resultingItemURL: nil) }
            try FileManager.default.copyItem(at: newApp, to: target)
            _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])
            done(true)
        } catch { done(false) }
    }

    private static func relaunch() {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Magen.app"), configuration: cfg) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func fail() {
        busy = false
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = tr("Não deu para atualizar sozinho")
        a.informativeText = tr("Baixe a versão nova pela página do Magen no GitHub.")
        a.addButton(withTitle: tr("Abrir a página"))
        a.addButton(withTitle: tr("Fechar"))
        if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(releasesPage) }
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}

// MARK: - Menus at the top of the screen (next to the Apple menu)

extension AppDelegate {
    func buildMainMenu() {
        let main = NSMenu()
        func item(_ title: String, _ action: Selector?, _ key: String = "", mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: tr(title), action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            return i
        }
        func checked(_ i: NSMenuItem, _ on: Bool) -> NSMenuItem { i.state = on ? .on : .off; return i }
        func raw(_ title: String, _ action: Selector) -> NSMenuItem { // language names are never translated
            let i = NSMenuItem(title: title, action: action, keyEquivalent: ""); i.target = self; return i
        }
        func submenu(_ title: String, _ items: [NSMenuItem?]) -> NSMenu {
            let m = NSMenu(title: tr(title))
            for i in items { m.addItem(i ?? .separator()) }
            let holder = NSMenuItem(title: tr(title), action: nil, keyEquivalent: "")
            holder.submenu = m
            main.addItem(holder)
            return m
        }

        _ = submenu("Magen", [
            item("Sobre o Magen", #selector(menuAbout), target: self),
            item(Lang.isEnglish ? "Support Magen…" : "Apoie o Magen (Pix)…", #selector(menuDonate), target: self),
            item("Procurar atualização…", #selector(menuUpdate), target: self),
            nil,
            item("Ajustes…", #selector(menuSettings), ",", target: self),
            checked(item("Sumir do Dock ao fechar", #selector(menuToggleDock), target: self), Dock.hideOnClose),
            checked(raw("Português", #selector(menuLangPT)), Lang.current == "pt"),
            checked(raw("English", #selector(menuLangEN)), Lang.current == "en"),
            nil,
            item("Ocultar o Magen", #selector(NSApplication.hide(_:)), "h"),
            item("Ocultar os outros", #selector(NSApplication.hideOtherApplications(_:)), "h", mods: [.command, .option]),
            item("Mostrar tudo", #selector(NSApplication.unhideAllApplications(_:))),
            nil,
            item("Fechar o Magen (o bloqueio continua)", #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = submenu("Editar", [
            item("Desfazer", Selector(("undo:")), "z"),
            item("Refazer", Selector(("redo:")), "z", mods: [.command, .shift]),
            nil,
            item("Recortar", #selector(NSText.cut(_:)), "x"),
            item("Copiar", #selector(NSText.copy(_:)), "c"),
            item("Colar", #selector(NSText.paste(_:)), "v"),
            item("Selecionar tudo", #selector(NSText.selectAll(_:)), "a"),
        ])
        var tabItems: [NSMenuItem?] = []
        for t in MainWindow.Tab.allCases {
            let i = item(t.title, #selector(menuTab(_:)), "\(t.rawValue + 1)", target: self)
            i.tag = t.rawValue
            tabItems.append(i)
        }
        _ = submenu("Ver", tabItems)
        _ = submenu("Proteção", [
            item("Testar ou liberar um site…", #selector(menuSites), target: self),
            item("Atualizar as listas agora", #selector(menuUpdateLists), target: self),
            item("Ver a janela do versículo", #selector(menuVerse), target: self),
            nil,
            item("Retransmissão Privada do iCloud…", #selector(menuRelay), target: self),
        ])
        let windowMenu = submenu("Janela", [
            item("Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Fechar", #selector(NSWindow.performClose(_:)), "w"),
        ])
        NSApp.windowsMenu = windowMenu
        _ = submenu("Ajuda", [
            item("Como o Magen funciona", #selector(menuHelp), target: self),
            item(Lang.isEnglish ? "Support Magen…" : "Apoie o Magen (Pix)…", #selector(menuDonate), target: self),
        ])
        NSApp.mainMenu = main
    }
}
