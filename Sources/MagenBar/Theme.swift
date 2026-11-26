// Visual do Magen: o estilo novo da família Treco (como o Treco e o Pauta):
// fundo creme, tinta quase preta, trilho preto à esquerda, títulos enormes na
// Archivo larga com marca-texto, textos na Clash Grotesk, cartões brancos com
// sombra dura. A cor de destaque do Magen é o vermelho.
import AppKit
import CoreText

enum Theme {
    static let ink = NSColor(srgbRed: 10 / 255, green: 10 / 255, blue: 10 / 255, alpha: 1)      // #0A0A0A
    static let paper = NSColor.white
    static let cream = NSColor(srgbRed: 253 / 255, green: 249 / 255, blue: 238 / 255, alpha: 1)  // #FDF9EE
    static let red = NSColor(srgbRed: 225 / 255, green: 0, blue: 0, alpha: 1)
    /// Light red "highlighter" under big titles (Treco uses light blue).
    static let highlight = NSColor(srgbRed: 255 / 255, green: 190 / 255, blue: 190 / 255, alpha: 1)
    /// Hover fill: a touch of red on white.
    static let hover = NSColor(srgbRed: 255 / 255, green: 232 / 255, blue: 232 / 255, alpha: 1)
    static let gray = NSColor(srgbRed: 176 / 255, green: 176 / 255, blue: 176 / 255, alpha: 1)
    static let dark = NSColor(srgbRed: 92 / 255, green: 92 / 255, blue: 92 / 255, alpha: 1)
    static let line: CGFloat = 2
    static let shadow: CGFloat = 7      // big cards (verse window, donation)
    static let smallShadow: CGFloat = 4 // buttons and small cards

    private static var registered = false

    /// Loads the fonts in the app's Resources/fonts: Archivo (SIL OFL, in the code) and,
    /// when present, Clash Grotesk (ITF FFL: may go inside the app, not in the public repo).
    static func registerFont() {
        guard !registered else { return }
        registered = true
        let dirs = [
            Bundle.main.resourceURL?.appendingPathComponent("fonts"),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent("../../Resources/fonts"),
        ]
        for case let dir? in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for f in files where ["ttf", "otf"].contains(f.pathExtension.lowercased()) {
                CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
            }
            return
        }
    }

    private static func archivo(_ size: CGFloat, weight: CGFloat, width: CGFloat) -> NSFont? {
        let variation: [NSNumber: NSNumber] = [
            NSNumber(value: 0x7767_6874): NSNumber(value: Double(weight)), // 'wght'
            NSNumber(value: 0x7764_7468): NSNumber(value: Double(width)),  // 'wdth'
        ]
        let desc = NSFontDescriptor(fontAttributes: [.family: "Archivo", .variation: variation])
        if let f = NSFont(descriptor: desc, size: size), f.familyName == "Archivo" { return f }
        return nil
    }

    /// Text font: Clash Grotesk (Medium / Semibold). Without it, Archivo normal width.
    static func font(_ size: CGFloat, bold: Bool = false, weight: CGFloat? = nil) -> NSFont {
        registerFont()
        let semibold = bold || (weight ?? 500) >= 600
        if let f = NSFont(name: semibold ? "ClashGrotesk-Semibold" : "ClashGrotesk-Medium", size: size) { return f }
        return archivo(size, weight: weight ?? (bold ? 700 : 500), width: 100)
            ?? .systemFont(ofSize: size, weight: bold ? .semibold : .medium)
    }

    /// Title font: Archivo Expanded, very heavy (logo, page titles, big numbers).
    static func wide(_ size: CGFloat, weight: CGFloat = 900) -> NSFont {
        registerFont()
        return archivo(size, weight: weight, width: 125) ?? .systemFont(ofSize: size, weight: .black)
    }

    static func label(_ text: String, size: CGFloat, bold: Bool = false, color: NSColor = Theme.ink,
                      wrap: CGFloat? = nil, align: NSTextAlignment = .left, wide: Bool = false) -> NSTextField {
        let text = tr(text)
        let l = wrap != nil ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        l.font = wide ? Theme.wide(size, weight: bold ? 900 : 800) : font(size, bold: bold)
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
/// Optional hard shadow (bottom-right), like the Treco cards.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
    var fill: NSColor? { didSet { needsDisplay = true } }
    var border: NSColor? { didSet { needsDisplay = true } }
    var shadowSize: CGFloat = 0 { didSet { needsDisplay = true } }
    var shadowColor: NSColor = Theme.ink { didSet { needsDisplay = true } }
    /// The card itself (the shadow takes the last `shadowSize` points).
    var face: NSRect { NSRect(x: 0, y: 0, width: bounds.width - shadowSize, height: bounds.height - shadowSize) }
    /// Mouse pointer shown over this view (the Magen arrow), if set.
    var cursor: NSCursor? { didSet { window?.invalidateCursorRects(for: self) } }
    override func resetCursorRects() { if let cursor { addCursorRect(bounds, cursor: cursor) } }
    override func draw(_ dirtyRect: NSRect) {
        let r = face
        if shadowSize > 0 {
            shadowColor.setFill()
            r.offsetBy(dx: shadowSize, dy: shadowSize).fill()
        }
        if let fill { fill.setFill(); r.fill() }
        if let border { strokeBox(r, border) }
    }
}

/// 2-point square outline (no anti-aliasing blur).
func strokeBox(_ r: NSRect, _ color: NSColor, _ t: CGFloat = Theme.line) {
    color.setFill()
    NSRect(x: r.minX, y: r.minY, width: r.width, height: t).fill()
    NSRect(x: r.minX, y: r.maxY - t, width: r.width, height: t).fill()
    NSRect(x: r.minX, y: r.minY, width: t, height: r.height).fill()
    NSRect(x: r.maxX - t, y: r.minY, width: t, height: r.height).fill()
}

/// Big white card with a black border and a big hard black shadow (verse window, donation).
final class CardView: FlippedView {
    var inner: NSRect { face }
    override init(frame: NSRect) {
        super.init(frame: frame)
        fill = Theme.paper; border = Theme.ink; shadowSize = Theme.shadow
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
}

/// Button in the new family style (Treco/Pauta): white face, black outline and a
/// small hard shadow; hover tints it red; press sinks it into the shadow;
/// selected or main action = black face with a red shadow.
final class BoxButton: NSView {
    var title: String { didSet { needsDisplay = true } }
    var symbolName: String?
    var selected = false { didSet { needsDisplay = true } }
    var enabled = true { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) } }
    var accent = false { didSet { needsDisplay = true } } // main action
    var fontSize: CGFloat = 12
    var onClick: (() -> Void)?
    private var pressed = false { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    init(_ title: String, symbol: String? = nil, onClick: (() -> Void)? = nil) {
        self.title = tr(title)
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
    override func resetCursorRects() { addCursorRect(bounds, cursor: enabled ? Cursors.pressCursor : Cursors.arrowCursor) }

    override func draw(_ dirtyRect: NSRect) {
        let s = Theme.smallShadow
        let dark = (selected || accent) && enabled
        var face = NSRect(x: 0, y: 0, width: bounds.width - s, height: bounds.height - s)
        if pressed && enabled {
            face = face.offsetBy(dx: s, dy: s) // sinks into its shadow
        } else if enabled {
            (dark ? Theme.red : Theme.ink).setFill()
            face.offsetBy(dx: s, dy: s).fill()
        }
        let back: NSColor = !enabled ? Theme.cream : dark ? Theme.ink : (hovering || pressed) ? Theme.hover : Theme.paper
        let fore: NSColor = !enabled ? Theme.gray : dark ? Theme.paper : Theme.ink
        back.setFill(); face.fill()
        strokeBox(face, enabled ? Theme.ink : Theme.gray)

        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.font(fontSize, bold: dark || hovering), .foregroundColor: fore]
        let text = NSAttributedString(string: title, attributes: attrs)
        let ts = text.size()
        if let name = symbolName, let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: fontSize + 5, weight: .semibold)) {
            let tinted = img.tinted(hovering && !dark && enabled ? Theme.red : fore)
            let isz = tinted.size
            let total = isz.height + 6 + ts.height
            let top = face.minY + (face.height - total) / 2
            tinted.draw(in: NSRect(x: face.minX + (face.width - isz.width) / 2, y: top, width: isz.width, height: isz.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            text.draw(at: NSPoint(x: face.minX + (face.width - ts.width) / 2, y: top + isz.height + 6))
        } else {
            text.draw(at: NSPoint(x: face.minX + (face.width - ts.width) / 2, y: face.minY + (face.height - ts.height) / 2))
        }
    }
}

/// Item of the black rail on the left (like Treco and Pauta): icon + small caps label.
/// Selected = white tile with a red hard shadow.
final class RailButton: NSView {
    let title: String
    let symbolName: String
    var selected = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    init(_ title: String, symbol: String, onClick: @escaping () -> Void) {
        self.title = title; self.symbolName = symbol; self.onClick = onClick
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }
    override func mouseUp(with e: NSEvent) { if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() } }
    override func resetCursorRects() { addCursorRect(bounds, cursor: Cursors.pressCursor) }

    override func draw(_ dirtyRect: NSRect) {
        let s = Theme.smallShadow
        let face = NSRect(x: 0, y: 0, width: bounds.width - s, height: bounds.height - s)
        if selected {
            Theme.red.setFill(); face.offsetBy(dx: s, dy: s).fill()
            Theme.paper.setFill(); face.fill()
        } else if hovering {
            NSColor(white: 1, alpha: 0.12).setFill(); face.fill()
        }
        let fore: NSColor = selected ? Theme.ink : Theme.paper
        let text = NSAttributedString(string: title.uppercased(), attributes: [
            .font: Theme.font(9.5, bold: true), .foregroundColor: fore, .kern: 0.4])
        let ts = text.size()
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .semibold))?.tinted(fore) {
            let isz = img.size
            let top = (face.height - isz.height - 6 - ts.height) / 2
            img.draw(in: NSRect(x: (face.width - isz.width) / 2, y: top, width: isz.width, height: isz.height),
                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            text.draw(at: NSPoint(x: (face.width - ts.width) / 2, y: top + isz.height + 6))
        }
    }
}

/// Big page title on a highlighter stripe (wide Archivo), like Treco's "Converter".
final class PageTitle: FlippedView {
    init(_ text: String, size: CGFloat = 40) {
        super.init(frame: .zero)
        let l = Theme.label(text, size: size, wide: true)
        l.font = Theme.wide(size)
        let sz = l.fittingSize
        // Stripe behind the lower half of the letters.
        let stripe = FlippedView(frame: NSRect(x: -4, y: sz.height * 0.48, width: sz.width + 8, height: sz.height * 0.42))
        stripe.fill = Theme.highlight
        addSubview(stripe)
        l.frame = NSRect(x: 0, y: 0, width: sz.width, height: sz.height)
        addSubview(l)
        frame = NSRect(x: 0, y: 0, width: sz.width + 8, height: sz.height)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Dashed area (like "+ ADICIONAR ARQUIVOS" in Treco), clickable.
final class DashedButton: NSView {
    let title: String
    var onClick: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    init(_ title: String, onClick: @escaping () -> Void) {
        self.title = tr(title); self.onClick = onClick
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }
    override func mouseUp(with e: NSEvent) { if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() } }
    override func resetCursorRects() { addCursorRect(bounds, cursor: Cursors.pressCursor) }
    override func draw(_ dirtyRect: NSRect) {
        if hovering { Theme.hover.setFill(); bounds.fill() }
        let p = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        p.lineWidth = 2
        p.setLineDash([6, 4], count: 2, phase: 0)
        Theme.ink.setStroke(); p.stroke()
        let text = NSAttributedString(string: "+  " + title.uppercased(), attributes: [
            .font: Theme.font(11, bold: true), .foregroundColor: hovering ? Theme.red : Theme.ink, .kern: 0.5])
        let ts = text.size()
        text.draw(at: NSPoint(x: 16, y: (bounds.height - ts.height) / 2))
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
        box.frame = NSRect(x: 0, y: 0, width: 30, height: 30)
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
