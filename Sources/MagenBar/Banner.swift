import AppKit

/// Magen's own notification balloon (top-right corner). Used when macOS does
/// not allow normal notifications (apps without a paid Apple signature).
/// It never takes the keyboard focus and disappears by itself.
final class Banner {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(title: String, text: String, ref: String, snapshotTo png: URL? = nil) {
        hide(animated: false)
        let width: CGFloat = 360
        let pad: CGFloat = 14

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "Magen")
        icon.symbolConfiguration = .init(pointSize: 22, weight: .regular)
        icon.contentTintColor = .controlAccentColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        let body = NSTextField(wrappingLabelWithString: "“\(text)”")
        body.font = .systemFont(ofSize: 13)
        body.textColor = .labelColor
        body.preferredMaxLayoutWidth = width - pad * 2 - 34

        let refLabel = NSTextField(labelWithString: "\(ref) · Bíblia Livre")
        refLabel.font = .systemFont(ofSize: 11, weight: .medium)
        refLabel.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleLabel, body, refLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        let row = NSStackView(views: [icon, textStack])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: pad, left: pad, bottom: pad, right: pad)
        row.translatesAutoresizingMaskIntoConstraints = false

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true
        blur.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            row.topAnchor.constraint(equalTo: blur.topAnchor),
            row.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            row.widthAnchor.constraint(equalToConstant: width),
        ])
        blur.layoutSubtreeIfNeeded()
        let size = row.fittingSize

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.contentView = blur
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        blur.addGestureRecognizer(click)

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let vis = screen.visibleFrame
        p.setFrameOrigin(NSPoint(x: vis.maxX - size.width - 12, y: vis.maxY - size.height - 12))
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 }
        panel = p

        if let png { saveSnapshot(of: blur, to: png) }

        // Longer verses stay a little longer on screen (8–16 s).
        let seconds = min(16, max(8, Double(text.count) / 14))
        let work = DispatchWorkItem { [weak self] in self?.hide(animated: true) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    @objc private func clicked() { hide(animated: true) }

    func hide(animated: Bool) {
        hideWork?.cancel()
        guard let p = panel else { return }
        panel = nil
        if animated {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; p.animator().alphaValue = 0 }) { p.orderOut(nil) }
        } else { p.orderOut(nil) }
    }

    /// Test helper: saves a picture of the balloon (MAGEN_BANNER_PNG).
    private func saveSnapshot(of view: NSView, to url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("Imagem do balão salva em \(url.path)")
        }
    }
}
