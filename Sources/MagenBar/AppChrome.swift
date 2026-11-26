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
    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let k = size / 1024
            let body = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
            Theme.red.setFill()
            NSBezierPath(roundedRect: body, xRadius: 185 * k, yRadius: 185 * k).fill()
            let font = Theme.font(430 * k, weight: 900)
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
                image(size: px).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
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
    static func hide() {
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
        place(Theme.label("ME AJUDA: TENHO 5 BOCAS PRA ALIMENTAR", size: 18, bold: true, color: Theme.red, wrap: textW), gap: 6)
        place(Theme.label("e fiz esse app de graça pra você.", size: 13, bold: true, wrap: textW), gap: 14)
        place(Theme.label("Oi, eu sou o \(Author.name). O Magen não tem anúncio, não pede conta e não manda nada seu pra internet.",
                          size: 12, color: Theme.dark, wrap: textW), gap: 10)
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
        y += 40 + pad
        card.frame = NSRect(x: 0, y: 0, width: width, height: y + Theme.shadow)
        card.cursor = Cursors.arrowCursor

        let w = NSWindow(contentRect: card.frame, styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Apoie o Magen"
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
        copyButton?.title = "Copiado!"
    }

    func close() { window?.close() }

    func windowWillClose(_ n: Notification) {
        UserDefaults.standard.set(Self.version, forKey: Self.seenKey)
        window = nil
        Dock.hide()
    }
}

// MARK: - Updates (placeholder until the GitHub page exists)

enum Updates {
    static var autoCheck: Bool {
        get { UserDefaults.standard.object(forKey: "atualizarSozinho") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "atualizarSozinho") }
    }

    /// TODO: when the project is on GitHub, read the latest release here
    /// (like Treco's update_ui.py) and offer to download it.
    static func check(manual: Bool) {
        guard manual else { return } // automatic check: nothing to do yet
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Você está com o Magen \(appVersion)"
        a.informativeText = "A atualização automática chega numa próxima versão, quando o Magen estiver publicado no GitHub. Por enquanto, esta é a versão mais nova."
        a.runModal()
    }
}

// MARK: - Menus at the top of the screen (next to the Apple menu)

extension AppDelegate {
    func buildMainMenu() {
        let main = NSMenu()
        func item(_ title: String, _ action: Selector?, _ key: String = "", mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            return i
        }
        func submenu(_ title: String, _ items: [NSMenuItem?]) -> NSMenu {
            let m = NSMenu(title: title)
            for i in items { m.addItem(i ?? .separator()) }
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = m
            main.addItem(holder)
            return m
        }

        _ = submenu("Magen", [
            item("Sobre o Magen", #selector(menuAbout), target: self),
            item("Apoie o Magen (Pix)…", #selector(menuDonate), target: self),
            item("Procurar atualização…", #selector(menuUpdate), target: self),
            nil,
            item("Ajustes…", #selector(menuSettings), ",", target: self),
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
            item("Apoie o Magen (Pix)…", #selector(menuDonate), target: self),
        ])
        NSApp.mainMenu = main
    }
}
