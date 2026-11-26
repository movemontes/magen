// Visual do Magen: o mesmo estilo do Treco (branco, bordas pretas grossas,
// sombra preta "dura", fonte Archivo larga), com vermelho no lugar do azul.
import AppKit
import CoreText

enum Theme {
    static let ink = NSColor.black
    static let paper = NSColor.white
    static let red = NSColor(srgbRed: 225 / 255, green: 0, blue: 0, alpha: 1)
    static let gray = NSColor(srgbRed: 176 / 255, green: 176 / 255, blue: 176 / 255, alpha: 1)
    static let dark = NSColor(srgbRed: 92 / 255, green: 92 / 255, blue: 92 / 255, alpha: 1)
    static let line: CGFloat = 2
    static let shadow: CGFloat = 7

    private static var registered = false

    /// Loads Archivo (SIL Open Font License) from the app's Resources folder.
    static func registerFont() {
        guard !registered else { return }
        registered = true
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("fonts/Archivo-Variable.ttf"),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent("../../Resources/fonts/Archivo-Variable.ttf"),
        ]
        for case let url? in candidates where FileManager.default.fileExists(atPath: url.path) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            return
        }
    }

    /// Archivo Expanded (width 125), like Treco. Falls back to the system font.
    static func font(_ size: CGFloat, bold: Bool = false, weight: CGFloat? = nil) -> NSFont {
        registerFont()
        let wght = weight ?? (bold ? 800 : 500)
        let variation: [NSNumber: NSNumber] = [
            NSNumber(value: 0x7767_6874): NSNumber(value: Double(wght)), // 'wght'
            NSNumber(value: 0x7764_7468): NSNumber(value: 125),          // 'wdth'
        ]
        let desc = NSFontDescriptor(fontAttributes: [.family: "Archivo", .variation: variation])
        if let f = NSFont(descriptor: desc, size: size), f.familyName == "Archivo" { return f }
        return .systemFont(ofSize: size, weight: bold ? .heavy : .medium)
    }

    static func label(_ text: String, size: CGFloat, bold: Bool = false, color: NSColor = Theme.ink,
                      wrap: CGFloat? = nil, align: NSTextAlignment = .left) -> NSTextField {
        let l = wrap != nil ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        l.font = font(size, bold: bold)
        l.textColor = color
        l.alignment = align
        l.isSelectable = false
        if let w = wrap { l.preferredMaxLayoutWidth = w }
        return l
    }

    static func symbol(_ name: String, size: CGFloat, color: NSColor = Theme.ink, weight: NSFont.Weight = .semibold) -> NSImageView {
        let v = NSImageView()
        v.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        v.symbolConfiguration = .init(pointSize: size, weight: weight)
        v.contentTintColor = color
        return v
    }
}

/// Plain view with the origin at the top-left (easier manual layout).
class FlippedView: NSView {
    override var isFlipped: Bool { true }
    var fill: NSColor?
    var border: NSColor?
    override func draw(_ dirtyRect: NSRect) {
        if let fill { fill.setFill(); bounds.fill() }
        if let border {
            border.setFill()
            let t = Theme.line
            NSRect(x: 0, y: 0, width: bounds.width, height: t).fill()
            NSRect(x: 0, y: bounds.height - t, width: bounds.width, height: t).fill()
            NSRect(x: 0, y: 0, width: t, height: bounds.height).fill()
            NSRect(x: bounds.width - t, y: 0, width: t, height: bounds.height).fill()
        }
    }
}

/// White card with a black border and a hard black shadow (bottom-right).
final class CardView: FlippedView {
    /// Area inside the card (the shadow takes the last `Theme.shadow` points).
    var inner: NSRect { NSRect(x: 0, y: 0, width: bounds.width - Theme.shadow, height: bounds.height - Theme.shadow) }
    override func draw(_ dirtyRect: NSRect) {
        let s = Theme.shadow
        Theme.ink.setFill()
        NSRect(x: s, y: s, width: bounds.width - s, height: bounds.height - s).fill()
        Theme.paper.setFill()
        inner.fill()
        Theme.ink.setFill()
        let r = inner, t = Theme.line
        NSRect(x: 0, y: 0, width: r.width, height: t).fill()
        NSRect(x: 0, y: r.height - t, width: r.width, height: t).fill()
        NSRect(x: 0, y: 0, width: t, height: r.height).fill()
        NSRect(x: r.width - t, y: 0, width: t, height: r.height).fill()
    }
}

/// Square button in the Treco style: outlined; black when selected; red while pressed.
final class BoxButton: NSView {
    var title: String { didSet { needsDisplay = true } }
    var symbolName: String?
    var selected = false { didSet { needsDisplay = true } }
    var enabled = true { didSet { needsDisplay = true } }
    var accent = false { didSet { needsDisplay = true } } // red fill (main action)
    var fontSize: CGFloat = 12
    var onClick: (() -> Void)?
    private var pressed = false { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    init(_ title: String, symbol: String? = nil, onClick: (() -> Void)? = nil) {
        self.title = title
        self.symbolName = symbol
        self.onClick = onClick
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }
    override func mouseDown(with e: NSEvent) { if enabled { pressed = true } }
    override func mouseUp(with e: NSEvent) {
        let inside = bounds.contains(convert(e.locationInWindow, from: nil))
        if pressed && inside && enabled { onClick?() }
        pressed = false
    }
    override func resetCursorRects() { if enabled { addCursorRect(bounds, cursor: .pointingHand) } }

    override func draw(_ dirtyRect: NSRect) {
        let back: NSColor, fore: NSColor
        if !enabled { back = Theme.paper; fore = Theme.gray }
        else if pressed { back = Theme.red; fore = Theme.paper }
        else if selected { back = Theme.ink; fore = Theme.paper }
        else if accent { back = Theme.red; fore = Theme.paper }
        else { back = Theme.paper; fore = Theme.ink }
        back.setFill(); bounds.fill()
        (enabled ? Theme.ink : Theme.gray).setFill()
        let t = Theme.line
        NSRect(x: 0, y: 0, width: bounds.width, height: t).fill()
        NSRect(x: 0, y: bounds.height - t, width: bounds.width, height: t).fill()
        NSRect(x: 0, y: 0, width: t, height: bounds.height).fill()
        NSRect(x: bounds.width - t, y: 0, width: t, height: bounds.height).fill()
        if hovering && enabled && !selected && !pressed && !accent {
            Theme.ink.setFill()
            NSRect(x: t, y: bounds.height - t - 3, width: bounds.width - 2 * t, height: 3).fill()
        }

        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.font(fontSize, bold: selected || accent), .foregroundColor: fore]
        let text = NSAttributedString(string: title, attributes: attrs)
        let ts = text.size()
        if let name = symbolName, let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: fontSize + 5, weight: .semibold)) {
            let tinted = img.tinted(fore)
            let isz = tinted.size
            let total = isz.height + 6 + ts.height
            let top = (bounds.height - total) / 2
            tinted.draw(in: NSRect(x: (bounds.width - isz.width) / 2, y: top, width: isz.width, height: isz.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            text.draw(at: NSPoint(x: (bounds.width - ts.width) / 2, y: top + isz.height + 6))
        } else {
            text.draw(at: NSPoint(x: (bounds.width - ts.width) / 2, y: (bounds.height - ts.height) / 2))
        }
    }
}

/// Square on/off switch with a label, Treco style.
final class CheckRow: FlippedView {
    private let box = BoxButton("")
    private let titleLabel: NSTextField
    private let detail: NSTextField
    var isOn: Bool { didSet { update() } }
    var onToggle: ((Bool) -> Void)?

    init(title: String, detail: String, isOn: Bool, width: CGFloat) {
        self.isOn = isOn
        titleLabel = Theme.label(title, size: 13, bold: true, wrap: width - 44)
        self.detail = Theme.label(detail, size: 11, color: Theme.dark, wrap: width - 44)
        super.init(frame: .zero)
        box.fontSize = 13
        box.onClick = { [weak self] in
            guard let self else { return }
            self.onToggle?(!self.isOn)
        }
        addSubview(box); addSubview(titleLabel); addSubview(self.detail)
        box.frame = NSRect(x: 0, y: 0, width: 26, height: 26)
        let th = textHeight(titleLabel, width: width - 44)
        titleLabel.frame = NSRect(x: 40, y: 3, width: width - 44, height: th)
        let dh = textHeight(self.detail, width: width - 44)
        self.detail.frame = NSRect(x: 40, y: 3 + th + 4, width: width - 44, height: dh)
        frame = NSRect(x: 0, y: 0, width: width, height: max(26, 3 + th + 4 + dh))
        update()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func update() {
        box.title = isOn ? "✓" : ""
        box.selected = isOn
    }
}

/// Height a label needs at a given width (more reliable than fittingSize for wrapped text).
func textHeight(_ l: NSTextField, width: CGFloat) -> CGFloat {
    ceil(l.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000)).height ?? l.fittingSize.height)
}

extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        draw(in: NSRect(origin: .zero, size: size))
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        img.unlockFocus()
        return img
    }
}

/// Saves a picture of a view (used by the tests, never by the person).
func snapshot(_ view: NSView, to url: URL) {
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}
