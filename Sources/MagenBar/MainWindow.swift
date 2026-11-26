// Janela principal do Magen, no estilo do Treco: cabeçalho "MAGEN" com o estado,
// uma fileira de abas quadradas e um painel com borda grossa.
import AppKit
import MagenCore

/// Ajustes de cada pessoa (não precisam de senha).
enum Prefs {
    static let d = UserDefaults.standard
    static var versesOn: Bool {
        get { d.object(forKey: "versiculos") as? Bool ?? true }
        set { d.set(newValue, forKey: "versiculos") }
    }
    static var lockSeconds: Int {
        get { d.object(forKey: "segundosParaFechar") as? Int ?? 5 }
        set { d.set(newValue, forKey: "segundosParaFechar") }
    }
    static var gapMinutes: Int {
        get { d.object(forKey: "minutosEntreJanelas") as? Int ?? 1 }
        set { d.set(newValue, forKey: "minutosEntreJanelas") }
    }
}

protocol MagenActions: AnyObject {
    func readState() -> MagenState?
    var serviceIsOn: Bool { get }
    func showVersePreview()
    func showDonate()
    func turnOn()
    func turnOff()
    func requestUpdate()
    func dnsCheck(_ name: String) -> Bool?
    func runAdmin(_ args: [String], done: String, then: (() -> Void)?)
}

final class MainWindow: NSObject, NSWindowDelegate {
    enum Tab: Int, CaseIterable {
        case inicio, sites, versiculos, protecao, sobre
        var title: String { tr(["Início", "Sites", "Versículos", "Proteção", "Sobre"][rawValue]) }
        var symbol: String { ["shield.lefthalf.filled", "globe", "book", "lock", "info.circle"][rawValue] }
    }

    private weak var app: MagenActions?
    private(set) var window: NSWindow!
    private var tab: Tab = .inicio
    private let root = FlippedView()
    private let panel = FlippedView()
    private var tabButtons: [RailButton] = []
    private let statusLabel = Theme.label("", size: 11)
    private var refreshTimer: Timer?
    // Sites tab state
    private let siteField = NSTextField()
    private var siteResult = ""

    static let size = NSSize(width: 760, height: 700)
    static let railW: CGFloat = 92, barH: CGFloat = 64
    private let pad: CGFloat = 16

    init(app: MagenActions) {
        self.app = app
        super.init()
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Magen"
        w.isMovableByWindowBackground = true
        w.backgroundColor = Theme.cream
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.appearance = NSAppearance(named: .aqua) // always the light Treco look
        root.frame = NSRect(origin: .zero, size: Self.size)
        root.fill = Theme.cream
        root.cursor = Cursors.arrowCursor
        w.contentView = root
        w.contentMinSize = Self.size
        window = w
        w.center()
        // Remembers size and place between openings.
        w.setFrameAutosaveName("MagenJanela")
        buildChrome()
        select(.inicio)
    }

    /// Resizable by every edge: redo the layout for the new size.
    func windowDidResize(_ notification: Notification) { relayout() }

    func relayout() {
        root.frame = window.contentView?.bounds ?? root.frame
        buildChrome()
        reload()
    }

    func show(tab: Tab? = nil) {
        if let tab { select(tab) } else { reload() }
        Dock.show()
        window.makeKeyAndOrderFront(nil)
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.tab == .inicio else { self?.updateHeader(); return }
            self.reload()
        }
    }

    func windowWillClose(_ notification: Notification) { refreshTimer?.invalidate(); Dock.hide() }

    // MARK: layout

    /// Short sentence under each page title.
    private func lead(_ t: Tab) -> String {
        switch t {
        case .inicio: return tr("Veja se o Magen está protegendo este Mac.")
        case .sites: return tr("Teste, libere ou bloqueie um site.")
        case .versiculos: return tr("A janela que aparece quando um site adulto é bloqueado.")
        case .protecao: return tr("Opções contra burla e como o Magen funciona.")
        case .sobre: return tr("Quem fez, créditos e atualizações.")
        }
    }

    private func buildChrome() {
        root.subviews.forEach { $0.removeFromSuperview() }
        tabButtons.removeAll()
        let size = window?.contentView?.bounds.size ?? Self.size
        let W = size.width, H = size.height, R = Self.railW

        // Black rail on the left: logo tile on top (below the window buttons), pages, "Sobre" at the bottom.
        let rail = FlippedView(frame: NSRect(x: 0, y: 0, width: R, height: H))
        rail.fill = Theme.ink
        root.addSubview(rail)
        // Logo: the buckler with "M" (same picture as the app icon).
        if let shield = AppIconArt.shield {
            let logo = NSImageView(frame: NSRect(x: (R - 66) / 2, y: 36, width: 66, height: 66))
            logo.image = shield
            logo.imageScaling = .scaleProportionallyUpOrDown
            rail.addSubview(logo)
        } else {
            let tile = FlippedView(frame: NSRect(x: (R - 56) / 2, y: 40, width: 56, height: 56))
            tile.fill = Theme.red
            let m = Theme.label("M", size: 30, align: .center, wide: true)
            m.font = Theme.wide(30); m.textColor = Theme.paper
            m.frame = NSRect(x: 0, y: (56 - m.fittingSize.height) / 2, width: 56, height: m.fittingSize.height)
            tile.addSubview(m)
            rail.addSubview(tile)
        }
        var ry: CGFloat = 116
        for t in Tab.allCases {
            let b = RailButton(t.title, symbol: t.symbol) { [weak self] in self?.select(t) }
            b.selected = t == tab
            let y = t == .sobre ? H - 76 : ry
            b.frame = NSRect(x: 8, y: y, width: R - 12, height: 66)
            rail.addSubview(b)
            tabButtons.append(b)
            ry += 70
        }

        // Page header: small status line, big title on a highlighter, lead.
        let x0 = R + 28
        statusLabel.frame = NSRect(x: x0, y: 14, width: W - x0 - 20, height: 16)
        statusLabel.alignment = .left
        root.addSubview(statusLabel)
        let title = PageTitle(tab.title, size: 40)
        title.setFrameOrigin(NSPoint(x: x0, y: 34))
        root.addSubview(title)
        let leadLabel = Theme.label(lead(tab), size: 13, color: Theme.dark)
        leadLabel.frame = NSRect(x: x0, y: title.frame.maxY + 6, width: W - x0 - 24, height: 18)
        root.addSubview(leadLabel)

        // Content area (cream) and white bottom bar.
        let top = leadLabel.frame.maxY + 10
        panel.frame = NSRect(x: R + 8, y: top, width: W - R - 16, height: H - top - Self.barH - 6)
        panel.fill = nil
        panel.border = nil
        root.addSubview(panel)
        buildBottomBar(W: W, H: H)
    }

    /// White bar at the bottom: dashed "test a site" area + the main actions.
    private func buildBottomBar(W: CGFloat, H: CGFloat) {
        let R = Self.railW, bh = Self.barH
        let bar = FlippedView(frame: NSRect(x: R, y: H - bh, width: W - R, height: bh))
        bar.fill = Theme.paper
        let rule = FlippedView(frame: NSRect(x: 0, y: 0, width: W - R, height: Theme.line))
        rule.fill = Theme.ink
        bar.addSubview(rule)
        let on = app?.serviceIsOn ?? false
        let main = BoxButton(on ? "Ver versículo" : (Service.busy ? "Ligando…" : "Ligar a proteção")) { [weak self] in
            if on { self?.app?.showVersePreview() } else { self?.app?.turnOn() }
        }
        main.accent = true
        main.enabled = on || !Service.busy
        main.fontSize = 12
        let update = BoxButton("Atualizar listas") { [weak self] in self?.app?.requestUpdate() }
        update.enabled = on
        update.fontSize = 12
        let bw: CGFloat = 150, gap: CGFloat = 10, by: CGFloat = 14, bht: CGFloat = 38
        main.frame = NSRect(x: W - R - 20 - bw, y: by, width: bw, height: bht)
        update.frame = NSRect(x: main.frame.minX - gap - bw, y: by, width: bw, height: bht)
        let dashed = DashedButton("Testar um site") { [weak self] in
            self?.select(.sites)
            DispatchQueue.main.async { self?.window.makeFirstResponder(self?.siteField) }
        }
        dashed.frame = NSRect(x: 20, y: by, width: update.frame.minX - 20 - 16, height: bht - Theme.smallShadow)
        [dashed, update, main].forEach { bar.addSubview($0) }
        root.addSubview(bar)
    }

    private func select(_ t: Tab) {
        let changed = t != tab
        tab = t
        buildChrome()
        reload()
        if changed {
            // Page enters with a small slide, like Pauta.
            let end = panel.frame
            panel.frame = end.offsetBy(dx: 0, dy: 10)
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().frame = end
                panel.animator().alphaValue = 1
            }
        }
    }

    private func updateHeader() {
        guard let app else { return }
        let on = app.serviceIsOn
        let s = app.readState()
        let count = s.map { $0.domains < 1000 ? tr("baixando as listas…") : trf("%@ sites", num($0.domains)) } ?? ""
        statusLabel.stringValue = on ? trf("Protegendo · %@", count) : tr("Desligado")
        statusLabel.textColor = on ? Theme.dark : Theme.red
        statusLabel.font = Theme.font(11, bold: !on)
    }

    func reload() {
        updateHeader()
        panel.subviews.forEach { $0.removeFromSuperview() }
        switch tab {
        case .inicio: buildInicio()
        case .sites: buildSites()
        case .versiculos: buildVersiculos()
        case .protecao: buildProtecao()
        case .sobre: buildSobre()
        }
    }

    private var contentW: CGFloat { panel.frame.width - 2 * 20 }

    @discardableResult
    private func add(_ v: NSView, x: CGFloat = 20, y: CGFloat, w: CGFloat? = nil, h: CGFloat? = nil) -> CGFloat {
        // Labels start with a frame measured in the system font, so always measure again
        // (custom views like CheckRow already have the right frame).
        let measured = v is NSTextField ? v.fittingSize : v.frame.size
        let width = w ?? measured.width
        let height = h ?? ((v as? NSTextField).map { textHeight($0, width: width) } ?? measured.height)
        v.frame = NSRect(x: x, y: y, width: width, height: height)
        panel.addSubview(v)
        return v.frame.maxY
    }

    private func sectionTitle(_ s: String, y: CGFloat) -> CGFloat {
        add(Theme.label(tr(s).uppercased(), size: 11, bold: true, color: Theme.dark), y: y) + 8
    }

    // MARK: Início

    private func buildInicio() {
        guard let app else { return }
        let on = app.serviceIsOn
        let s = app.readState()
        var y: CGFloat = 20

        let hero = FlippedView()
        hero.fill = on ? Theme.ink : Theme.red
        hero.shadowSize = 6
        hero.shadowColor = on ? Theme.red : Theme.ink
        hero.frame = NSRect(x: 20, y: y, width: contentW, height: 102)
        let icon = Theme.symbol(on ? "shield.lefthalf.filled" : "shield.slash", size: 40, color: Theme.paper)
        icon.frame = NSRect(x: 22, y: 22, width: 52, height: 52)
        let big = Theme.label(on ? "PROTEGENDO" : "DESLIGADO", size: 28, bold: true, color: Theme.paper, wide: true)
        big.frame = NSRect(x: 92, y: 20, width: contentW - 110, height: big.fittingSize.height)
        let installed = Service.isInstalled
        let small = Theme.label(on ? "Sites adultos não abrem neste Mac." :
                                    Service.busy ? "Ligando… pode levar até 1 minuto." :
                                    installed ? "O serviço está instalado, mas não respondeu. Tente ligar de novo." :
                                    "Clique em “Ligar a proteção”. O Mac vai pedir a sua senha.", size: 12, color: Theme.paper)
        small.frame = NSRect(x: 92, y: 20 + big.fittingSize.height + 4, width: contentW - 110, height: small.fittingSize.height)
        [icon, big, small].forEach { hero.addSubview($0) }
        if !on {
            let b = BoxButton(Service.busy ? "Ligando…" : "Ligar a proteção") { [weak self] in self?.app?.turnOn() }
            b.enabled = !Service.busy
            b.fontSize = 13
            b.frame = NSRect(x: contentW - 190, y: 28, width: 170, height: 40)
            small.frame.size.width = contentW - 300
            big.frame.size.width = contentW - 300
            hero.addSubview(b)
        }
        panel.addSubview(hero)
        y = hero.frame.maxY + 16

        if PrivateRelay.isOn() == true {
            let warn = FlippedView()
            warn.fill = Theme.paper
            warn.border = Theme.red
            warn.shadowSize = Theme.smallShadow
            warn.shadowColor = Theme.red
            let t = Theme.label("A Retransmissão Privada do iCloud está ligada", size: 13, bold: true, color: Theme.red)
            let d = Theme.label(trf("Com ela ligada, apps como o Claude podem ficar sem internet. Desligue em: %@", PrivateRelay.howTo),
                                size: 11, wrap: contentW - 190)
            let b = BoxButton("Abrir Ajustes") { PrivateRelay.openSettings() }
            b.accent = true
            let dh = textHeight(d, width: contentW - 190)
            let h = max(68, 12 + 18 + 4 + dh + 16)
            warn.frame = NSRect(x: 20, y: y, width: contentW, height: h)
            t.frame = NSRect(x: 14, y: 12, width: contentW - 190, height: 18)
            d.frame = NSRect(x: 14, y: 34, width: contentW - 190, height: dh)
            b.frame = NSRect(x: contentW - 160, y: (h - 40) / 2, width: 146, height: 40)
            [t, d, b].forEach { warn.addSubview($0) }
            panel.addSubview(warn)
            y = warn.frame.maxY + 16
        }

        let today = (s?.todayKey == AppDelegate.todayKey()) ? (s?.blockedToday ?? 0) : 0
        let stats: [(String, String)] = [
            (num(today), "bloqueios hoje"),
            (num(s?.blockedTotal ?? 0), "bloqueios no total"),
            ((s?.domains ?? 0) < 1000 ? tr("Baixando…") : num(s?.domains ?? 0),
             (s?.domains ?? 0) < 1000 ? "as listas chegam em até 1 minuto" : "sites na lista"),
            (s?.lastUpdate.map { $0.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Lang.locale)) } ?? "—", "listas atualizadas"),
        ]
        let gap: CGFloat = 10
        let bw = (contentW - gap) / 2, bh: CGFloat = 70
        for (i, st) in stats.enumerated() {
            let box = FlippedView()
            box.border = Theme.ink
            box.fill = Theme.paper
            box.shadowSize = Theme.smallShadow
            box.frame = NSRect(x: 20 + CGFloat(i % 2) * (bw + gap), y: y + CGFloat(i / 2) * (bh + gap), width: bw, height: bh)
            let n = Theme.label(st.0, size: 22, bold: true, wide: true)
            n.frame = NSRect(x: 14, y: 12, width: bw - 28, height: n.fittingSize.height)
            let l = Theme.label(st.1, size: 11, color: Theme.dark)
            l.frame = NSRect(x: 14, y: 14 + n.fittingSize.height, width: bw - 28, height: l.fittingSize.height)
            box.addSubview(n); box.addSubview(l)
            panel.addSubview(box)
        }
    }

    // MARK: Sites

    private func buildSites() {
        var y = sectionTitle("Testar, liberar ou bloquear um site", y: 20)
        siteField.placeholderString = tr("exemplo.com")
        siteField.font = Theme.font(14)
        siteField.isBordered = true
        siteField.bezelStyle = .squareBezel
        siteField.focusRingType = .none
        siteField.wantsLayer = true
        siteField.layer?.borderWidth = Theme.line
        siteField.layer?.borderColor = Theme.ink.cgColor
        siteField.backgroundColor = Theme.paper
        siteField.textColor = Theme.ink
        y = add(siteField, y: y, w: contentW, h: 34) + 10

        let gap: CGFloat = 8, bw = (contentW - 2 * gap) / 3
        let test = BoxButton("Testar") { [weak self] in self?.testSite() }
        let allow = BoxButton("Liberar") { [weak self] in self?.changeSite("liberar") }
        let block = BoxButton("Bloquear") { [weak self] in self?.changeSite("bloquear") }
        for (i, b) in [test, allow, block].enumerated() {
            b.frame = NSRect(x: 20 + CGFloat(i) * (bw + gap), y: y, width: bw, height: 40)
            panel.addSubview(b)
        }
        y += 40 + 10
        let result = Theme.label(siteResult.isEmpty ? trf("Liberar é só para site que NÃO é adulto: pede uma frase, a senha do Mac, e só vale %d minutos depois.", Int(Unblock.delay / 60)) : siteResult,
                                 size: 12, bold: !siteResult.isEmpty, color: siteResult.hasPrefix("🚫") ? Theme.red : Theme.dark, wrap: contentW)
        y = add(result, y: y, w: contentW) + 18

        let cfg = MagenConfig.load(from: Paths.config(magenDir))
        let colW = (contentW - 16) / 2
        func list(_ title: String, _ items: [String], x: CGFloat) {
            var ly = y
            let t = Theme.label(tr(title).uppercased(), size: 11, bold: true, color: Theme.dark)
            t.frame = NSRect(x: x, y: ly, width: colW, height: t.fittingSize.height)
            panel.addSubview(t)
            ly += t.fittingSize.height + 6
            if items.isEmpty {
                let e = Theme.label("Nenhum", size: 12, color: Theme.gray)
                e.frame = NSRect(x: x, y: ly, width: colW, height: e.fittingSize.height)
                panel.addSubview(e)
            }
            for item in items.prefix(6) {
                let row = FlippedView()
                row.border = Theme.ink
                row.fill = Theme.paper
                row.frame = NSRect(x: x, y: ly, width: colW, height: 30)
                let l = Theme.label(item, size: 12)
                l.lineBreakMode = .byTruncatingMiddle
                l.frame = NSRect(x: 10, y: 7, width: colW - 50, height: 16)
                let x2 = BoxButton("×") { [weak self] in
                    let domain = item.hasPrefix("⏳ ") ? String(item.dropFirst(2).split(separator: " ").first ?? "") : item
                    self?.app?.runAdmin(["desfazer", domain], done: "") { self?.reload() }
                }
                x2.fontSize = 14
                x2.frame = NSRect(x: colW - 30, y: 0, width: 30, height: 30)
                row.addSubview(l); row.addSubview(x2)
                panel.addSubview(row)
                ly += 30 - Theme.line
            }
            if items.count > 6 {
                let more = Theme.label(trf("e mais %d…", items.count - 6), size: 11, color: Theme.dark)
                more.frame = NSRect(x: x, y: ly + 6, width: colW, height: more.fittingSize.height)
                panel.addSubview(more)
            }
        }
        let pending = cfg.pendingAllow.map { trf("⏳ %@ — às %@", $0.domain, $0.at.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Lang.locale))) }
        list("Liberados por você", pending + cfg.allow, x: 20)
        list("Bloqueados a mais", cfg.block, x: 20 + colW + 16)
    }

    private func typedSite() -> String? {
        var t = siteField.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        for p in ["https://", "http://"] where t.hasPrefix(p) { t.removeFirst(p.count) }
        if let slash = t.firstIndex(of: "/") { t = String(t[..<slash]) }
        guard let d = Domains.normalize(Substring(t)) else {
            siteResult = t.isEmpty ? "Digite o endereço de um site." : "Endereço inválido. Digite só o endereço, por exemplo: exemplo.com"
            reload(); return nil
        }
        return d
    }

    private func testSite() {
        guard let site = typedSite(), let app else { return }
        switch app.dnsCheck(site) {
        case .some(true): siteResult = trf("🚫 %@ está BLOQUEADO (ou não existe).", site)
        case .some(false): siteResult = trf("✅ %@ está liberado.", site)
        case .none: siteResult = "O Magen não respondeu. Ele está ligado?"
        }
        reload()
    }

    private func changeSite(_ cmd: String) {
        guard let site = typedSite() else { return }
        if cmd == "liberar" {
            guard confirmUnblock(site) else { return }
            let when = Date().addingTimeInterval(Unblock.delay).formatted(date: .omitted, time: .shortened)
            app?.runAdmin(["liberar", site], done: "") { [weak self] in
                self?.siteResult = trf("⏳ %@ será liberado às %@. Até lá, continua bloqueado.", site, when)
                self?.siteField.stringValue = ""
                self?.reload()
            }
            return
        }
        app?.runAdmin([cmd, site], done: "") { [weak self] in
            self?.siteResult = trf("🚫 %@ agora está bloqueado.", site)
            self?.siteField.stringValue = ""
            self?.reload()
        }
    }

    /// Unblocking is hard on purpose: obvious adult names are refused, the person must
    /// type a sentence, then the Mac password, and the site only opens 1 hour later.
    private func confirmUnblock(_ site: String) -> Bool {
        if Unblock.isObviouslyAdult(site) {
            siteResult = trf("🚫 %@ tem nome de site adulto. Ele não pode ser liberado.", site)
            reload(); return false
        }
        let minutes = Int(Unblock.delay / 60)
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = trf("Liberar %@?", site)
        let sentence = Lang.isEnglish ? "this site is not pornographic" : Unblock.sentence
        a.informativeText = trf("Liberar é só para um site que NÃO é adulto e foi bloqueado por engano.\n\nO site só vai abrir daqui a %d minutos. Se for um momento de tentação, esse tempo é para você respirar e desistir. Dá para cancelar a qualquer hora na aba Sites.\n\nPara continuar, digite exatamente:\n%@", minutes, sentence)
        a.addButton(withTitle: tr("Pedir liberação"))
        a.addButton(withTitle: tr("Desistir"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = sentence
        a.accessoryView = field
        a.window.initialFirstResponder = field
        a.buttons.first?.isEnabled = true
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return false }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard typed == sentence else {
            siteResult = tr("A frase não confere. Nada foi liberado.")
            reload(); return false
        }
        return true
    }

    // MARK: Versículos

    private func buildVersiculos() {
        var y: CGFloat = 20
        let on = CheckRow(title: "Mostrar a janela com versículo quando um site adulto for bloqueado",
                          detail: "Ela cobre a tela, mostra um versículo e só fecha depois de alguns segundos. O nome do site nunca aparece.",
                          isOn: Prefs.versesOn, width: contentW)
        on.onToggle = { [weak self] v in Prefs.versesOn = v; self?.reload() }
        y = add(on, y: y) + 22

        func choices(_ title: String, _ options: [(String, Int)], current: Int, set: @escaping (Int) -> Void) {
            y = sectionTitle(title, y: y)
            let gap: CGFloat = 8, bw = (contentW - gap * CGFloat(options.count - 1)) / CGFloat(options.count)
            for (i, o) in options.enumerated() {
                let b = BoxButton(o.0) { [weak self] in set(o.1); self?.reload() }
                b.selected = o.1 == current
                b.enabled = Prefs.versesOn
                b.frame = NSRect(x: 20 + CGFloat(i) * (bw + gap), y: y, width: bw, height: 38)
                panel.addSubview(b)
            }
            y += 38 + 22
        }
        choices("Tempo até poder fechar", [("3 s", 3), ("5 s", 5), ("10 s", 10), ("15 s", 15)], current: Prefs.lockSeconds) { Prefs.lockSeconds = $0 }
        choices("Intervalo mínimo entre janelas", [("1 min", 1), ("5 min", 5), ("15 min", 15)], current: Prefs.gapMinutes) { Prefs.gapMinutes = $0 }

        let preview = BoxButton("Ver como fica", symbol: "eye") { [weak self] in self?.app?.showVersePreview() }
        preview.frame = NSRect(x: 20, y: y, width: 200, height: 56)
        panel.addSubview(preview)
        let credit = Theme.label(verseCreditLong,
                                 size: 11, color: Theme.dark, wrap: contentW - 220)
        add(credit, x: 236, y: y + 2, w: contentW - 216)
    }

    // MARK: Proteção

    private func buildProtecao() {
        let cfg = MagenConfig.load(from: Paths.config(magenDir))
        var y: CGFloat = 20
        let relay = CheckRow(title: "Bloquear a Retransmissão Privada do iCloud",
                             detail: trf("Sem isso, o Safari e os apps podem passar por fora do Magen. O melhor é desligar a Retransmissão Privada nos Ajustes (%@). Se ela ficar ligada, apps como o Claude podem perder a internet até você responder o aviso do Mac.", PrivateRelay.howTo),
                             isOn: cfg.blockPrivateRelay, width: contentW)
        relay.onToggle = { [weak self] v in
            self?.app?.runAdmin(["retransmissao", v ? "sim" : "nao"],
                                done: v ? "A Retransmissão Privada agora é bloqueada." : "A Retransmissão Privada foi liberada.") { self?.reload() }
        }
        y = add(relay, y: y) + 20
        let doh = CheckRow(title: "Bloquear o “DNS seguro” dos navegadores",
                           detail: "Chrome, Firefox e Edge têm uma opção que pergunta os endereços por fora do Mac. Com isso ligado, eles voltam a passar pelo Magen.",
                           isOn: cfg.antiBypass, width: contentW)
        doh.onToggle = { [weak self] v in
            self?.app?.runAdmin(["antiburla", v ? "sim" : "nao"],
                                done: v ? "O “DNS seguro” dos navegadores agora é bloqueado." : "O “DNS seguro” foi liberado.") { self?.reload() }
        }
        y = add(doh, y: y) + 26

        y = sectionTitle("Como funciona", y: y)
        let info = Theme.label(trf("Para sites normais, o Magen pergunta à Cloudflare (%@). Ele só vê o nome do site, nunca o conteúdo das páginas, por isso não deixa a internet lenta.\n\nAs listas de sites adultos se atualizam sozinhas a cada %d horas. Mudar estas opções pede a senha do Mac.", cfg.upstream.first ?? "1.1.1.1", Int(cfg.updateEveryHours)), size: 12, color: Theme.ink, wrap: contentW)
        y = add(info, y: y, w: contentW) + 20
        if Service.isInstalled {
            let remove = BoxButton("Remover o Magen deste Mac…", symbol: "trash") { [weak self] in self?.app?.turnOff() }
            remove.frame = NSRect(x: 20, y: y, width: 260, height: 56)
            panel.addSubview(remove)
        }
    }

    // MARK: Sobre

    private func buildSobre() {
        var y: CGFloat = 24
        let logo = Theme.label("MAGEN", size: 44, bold: true, wide: true)
        y = add(logo, y: y)
        let sub = Theme.label(trf("“escudo” em hebraico · versão %@", appVersion), size: 13, color: Theme.red)
        sub.font = Theme.font(13, bold: true)
        y = add(sub, y: y + 2) + 18
        let made = Theme.label(trf("Feito por %@, de graça, para quem quer vencer essa luta.", Author.name), size: 14, bold: true, wrap: contentW)
        y = add(made, y: y, w: contentW) + 10
        let text = Theme.label(Lang.isEnglish
            ? "Free adult-site blocker for Mac. No account, no ads, no data collected.\n\nBlock lists: OISD NSFW, Block List Project and StevenBlack (downloaded straight from the source).\nVerses: World English Bible (public domain) and Bíblia Livre (CC BY 4.0 Brasil). Font: Archivo, SIL Open Font License. Code: MIT license."
            : "Bloqueador grátis de sites adultos para Mac. Sem conta, sem anúncios, sem coletar nada.\n\nListas de bloqueio: OISD NSFW, Block List Project e StevenBlack (baixadas direto da fonte).\nVersículos: Bíblia Livre (BLIVRE), CC BY 4.0 Brasil, e World English Bible (domínio público). Fonte: Archivo, SIL Open Font License. Código: licença MIT.",
            size: 12, color: Theme.dark, wrap: contentW)
        y = add(text, y: y, w: contentW) + 18

        let gap: CGFloat = 10, bw = (contentW - gap) / 2
        let donate = BoxButton(Lang.isEnglish ? "Support Magen" : "Apoie o Magen (Pix)", symbol: "heart") { [weak self] in self?.app?.showDonate() }
        donate.accent = true
        let update = BoxButton("Procurar atualização", symbol: "arrow.down.circle") { Updates.check(manual: true) }
        donate.frame = NSRect(x: 20, y: y, width: bw, height: 56)
        update.frame = NSRect(x: 20 + bw + gap, y: y, width: bw, height: 56)
        panel.addSubview(donate); panel.addSubview(update)
        y += 56 + 14
        let auto = CheckRow(title: "Procurar atualização sozinho", detail: "Uma vez por dia, o Magen procura uma versão nova no GitHub e avisa. A atualização troca o app e o serviço de uma vez (pede a senha do Mac).",
                            isOn: Updates.autoCheck, width: contentW)
        auto.onToggle = { [weak self] v in Updates.autoCheck = v; self?.reload() }
        add(auto, y: y)
    }
}
