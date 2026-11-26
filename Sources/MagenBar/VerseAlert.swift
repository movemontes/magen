// A janela que aparece quando um site adulto é bloqueado: cobre a tela com
// vermelho, mostra um cartão no centro com um título e o versículo, e só
// deixa fechar depois de alguns segundos. É de propósito que incomoda.
import AppKit

private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onKey: ((NSEvent) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
}

final class VerseAlert {
    private var windows: [NSWindow] = []
    private var timer: Timer?
    private var button: BoxButton?
    private var remaining = 0

    var isShowing: Bool { !windows.isEmpty }

    /// `lockSeconds`: how long before the "Entendi" button works.
    func show(_ v: Verse, heading: String, lockSeconds: Int, snapshotTo png: URL? = nil) {
        close()
        let screens = NSScreen.screens
        guard let main = NSScreen.main ?? screens.first else { return }

        // Red cover on every screen; the card goes on the main one.
        for screen in screens {
            let w = KeyWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.isOpaque = false
            w.backgroundColor = Theme.red.withAlphaComponent(0.93)
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.onKey = { [weak self] e in
                guard let self else { return false }
                // Return, Enter, Escape or space close it, but only after the countdown.
                if [36, 76, 53, 49].contains(Int(e.keyCode)) { self.tryClose(); return true }
                return false
            }
            let content = FlippedView(frame: NSRect(origin: .zero, size: screen.frame.size))
            content.cursor = Cursors.arrowCursor
            w.contentView = content
            if screen == main {
                let card = buildCard(v, heading: heading, width: min(680, screen.frame.width - 80))
                card.setFrameOrigin(NSPoint(x: (screen.frame.width - card.frame.width) / 2,
                                            y: (screen.frame.height - card.frame.height) / 2))
                content.addSubview(card)
                if let png {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { snapshot(card, to: png); print("Imagem da janela salva em \(png.path)") }
                }
            }
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; w.animator().alphaValue = 1 }
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first { $0.screen == main }?.makeKeyAndOrderFront(nil)

        remaining = max(0, lockSeconds)
        updateButton()
        if remaining > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
                guard let self else { t.invalidate(); return }
                self.remaining -= 1
                self.updateButton()
                if self.remaining <= 0 { t.invalidate() }
            }
        }
    }

    private func updateButton() {
        guard let b = button else { return }
        if remaining > 0 {
            b.title = trf("Respire… %d", remaining)
            b.enabled = false
            b.accent = false
        } else {
            b.title = tr("Entendi")
            b.enabled = true
            b.accent = true
        }
    }

    private func tryClose() { if remaining <= 0 { close() } }

    func close() {
        timer?.invalidate(); timer = nil
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        button = nil
    }

    private func buildCard(_ v: Verse, heading: String, width: CGFloat) -> CardView {
        let pad: CGFloat = 28
        let inner = width - Theme.shadow
        let textW = inner - pad * 2
        let card = CardView()

        // Header: MAGEN ··· SITE BLOQUEADO (like the Treco title bar)
        let logo = Theme.label("MAGEN", size: 26, bold: true)
        let tag = Theme.label(heading.uppercased(), size: 12, bold: true, color: Theme.red)
        let shield = Theme.symbol("shield.lefthalf.filled", size: 18, color: Theme.red)
        var y: CGFloat = 16
        logo.frame = NSRect(x: pad - 6, y: y, width: logo.fittingSize.width, height: logo.fittingSize.height)
        let tagSize = tag.fittingSize
        tag.frame = NSRect(x: inner - pad - tagSize.width, y: y + (logo.fittingSize.height - tagSize.height) / 2,
                           width: tagSize.width, height: tagSize.height)
        shield.frame = NSRect(x: tag.frame.minX - 30, y: y + 2, width: 24, height: logo.fittingSize.height - 4)
        y += logo.fittingSize.height + 12
        let rule = FlippedView(frame: NSRect(x: 0, y: y, width: inner, height: Theme.line))
        rule.fill = Theme.ink
        y += Theme.line + 26

        let title = Theme.label(v.title, size: 34, bold: true, color: Theme.red, wrap: textW)
        let th = textHeight(title, width: textW)
        title.frame = NSRect(x: pad, y: y, width: textW, height: th)
        y += th + 18

        let body = Theme.label("“\(v.text)”", size: 19, wrap: textW)
        body.font = Theme.font(19, weight: 450)
        let bh = textHeight(body, width: textW)
        body.frame = NSRect(x: pad, y: y, width: textW, height: bh)
        y += bh + 14

        let ref = Theme.label(v.ref.uppercased() + "  ·  " + tr("BÍBLIA LIVRE"), size: 12, bold: true, color: Theme.dark)
        ref.frame = NSRect(x: pad, y: y, width: textW, height: ref.fittingSize.height)
        y += ref.fittingSize.height + 26

        let hint = Theme.label("Feche o navegador por alguns minutos. Levante, beba água, fale com alguém.", size: 12,
                               color: Theme.dark, wrap: textW)
        let hh = textHeight(hint, width: textW)
        hint.frame = NSRect(x: pad, y: y, width: textW, height: hh)
        y += hh + 18

        let b = BoxButton("Entendi") { [weak self] in self?.tryClose() }
        b.fontSize = 15
        b.frame = NSRect(x: pad, y: y, width: textW, height: 48)
        button = b
        y += 48 + pad

        for v in [logo, tag, shield, rule, title, body, ref, hint, b] as [NSView] { card.addSubview(v) }
        card.frame = NSRect(x: 0, y: 0, width: width, height: y + Theme.shadow)
        return card
    }
}
