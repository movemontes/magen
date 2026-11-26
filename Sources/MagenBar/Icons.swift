// Ícone da barra de menus (broquel com M) e ponteiros do mouse do Magen.
import AppKit

enum Icons {
    /// Broquel (escudo redondo) cheio, com o aro e o "M" vazados, como o "T" do Treco.
    /// É uma "template image": o macOS pinta de preto ou branco conforme o tema.
    /// `off` = Magen desligado: o broquel fica só com o contorno e um risco.
    static func buckler(size: CGFloat = 18, off: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let r = rect.insetBy(dx: 0.75, dy: 0.75)
            NSColor.black.setFill()
            NSColor.black.setStroke()
            if off {
                let ring = NSBezierPath(ovalIn: r.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.5
                ring.stroke()
            } else {
                NSBezierPath(ovalIn: r).fill()
                // Knock out an inner rim and the letter.
                ctx.setBlendMode(.clear)
                let rim = NSBezierPath(ovalIn: r.insetBy(dx: size * 0.12, dy: size * 0.12))
                rim.lineWidth = max(1, size * 0.055)
                rim.stroke()
                ctx.setBlendMode(.normal)
            }
            // The "M" (Archivo, very bold), centered.
            let font = Theme.wide(size * 0.5)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let m = NSAttributedString(string: "M", attributes: attrs)
            let line = CTLineCreateWithAttributedString(m)
            let bounds = CTLineGetImageBounds(line, ctx)
            let x = rect.midX - bounds.width / 2 - bounds.minX
            let y = rect.midY - bounds.height / 2 - bounds.minY
            if !off { ctx.setBlendMode(.clear) }
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, ctx)
            ctx.setBlendMode(.normal)
            if off {
                // Diagonal strike: protection is off.
                let strike = NSBezierPath()
                strike.move(to: NSPoint(x: r.minX + 2, y: r.minY + 2))
                strike.line(to: NSPoint(x: r.maxX - 2, y: r.maxY - 2))
                strike.lineWidth = 1.6
                strike.stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Big colored version (red buckler, white M, hard black shadow) for test pictures.
    static func bucklerPreview(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = size * 0.06
            let body = NSRect(x: rect.minX, y: rect.minY + s, width: rect.width - s, height: rect.height - s)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: body.offsetBy(dx: s, dy: -s)).fill()
            Theme.red.setFill()
            NSBezierPath(ovalIn: body).fill()
            let mask = buckler(size: body.width)
            let white = mask.tinted(.white)
            white.draw(in: body)
            return true
        }
    }
}

enum Cursors {
    /// Arrow points (in a 24×24 box, origin top-left), tip at (3, 2).
    private static let arrow: [NSPoint] = [
        NSPoint(x: 3, y: 2), NSPoint(x: 3, y: 19), NSPoint(x: 7.5, y: 15), NSPoint(x: 10.5, y: 21.5),
        NSPoint(x: 13.5, y: 20.2), NSPoint(x: 10.6, y: 14), NSPoint(x: 16.5, y: 14),
    ]

    private static func make(body: NSColor, edge: NSColor, shadow: NSColor) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let img = NSImage(size: size, flipped: true) { _ in
            func path(offset: CGFloat) -> NSBezierPath {
                let p = NSBezierPath()
                p.move(to: arrow[0].offset(offset))
                for pt in arrow.dropFirst() { p.line(to: pt.offset(offset)) }
                p.close()
                p.lineJoinStyle = .miter
                return p
            }
            // Hard shadow, like the Treco cards.
            shadow.setFill()
            path(offset: 2).fill()
            let main = path(offset: 0)
            body.setFill()
            main.fill()
            edge.setStroke()
            main.lineWidth = 1.5
            main.stroke()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 3, y: 2))
    }

    /// Normal pointer: black arrow, white edge, red shadow.
    static let arrowCursor = make(body: Theme.ink, edge: Theme.paper, shadow: Theme.red)
    /// Over buttons: red arrow, white edge, black shadow.
    static let pressCursor = make(body: Theme.red, edge: Theme.paper, shadow: Theme.ink)
}

private extension NSPoint {
    func offset(_ d: CGFloat) -> NSPoint { NSPoint(x: x + d, y: y + d) }
}
