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
    func requestUpdate()
    func dnsCheck(_ name: String) -> Bool?
    func runAdmin(_ args: [String], done: String, then: (() -> Void)?)
}

final class MainWindow: NSObject, NSWindowDelegate {
    enum Tab: Int, CaseIterable {
        case inicio, sites, versiculos, protecao, sobre
        var title: String { ["Início", "Sites", "Versículos", "Proteção", "Sobre"][rawValue] }
        var symbol: String { ["shield.lefthalf.filled", "globe", "book", "lock", "info.circle"][rawValue] }
    }

    private weak var app: MagenActions?
    private(set) var window: NSWindow!
    private var tab: Tab = .inicio
    private let root = FlippedView()
    private let panel = FlippedView()
    private var tabButtons: [BoxButton] = []
    private let statusLabel = Theme.label("", size: 12)
    private var refreshTimer: Timer?
    // Sites tab state
    private let siteField = NSTextField()
    private var siteResult = ""

    static let size = NSSize(width: 660, height: 650)
    private let pad: CGFloat = 16

    init(app: MagenActions) {
        self.app = app
        super.init()
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Magen"
        w.isMovableByWindowBackground = true
        w.backgroundColor = Theme.paper
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.appearance = NSAppearance(named: .aqua) // always the light Treco look
        root.frame = NSRect(origin: .zero, size: Self.size)
        root.fill = Theme.paper
        root.cursor = Cursors.arrowCursor
        w.contentView = root
        window = w
        buildChrome()
        select(.inicio)
        w.center()
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

    private func buildChrome() {
        let W = Self.size.width
        // Header (the window's traffic lights sit at the left, so the logo starts after them)
        let logo = Theme.label("MAGEN", size: 26, bold: true)
        logo.frame = NSRect(x: 84, y: 12, width: 160, height: logo.fittingSize.height)
        root.addSubview(logo)
        statusLabel.alignment = .right
        statusLabel.frame = NSRect(x: 250, y: 22, width: W - 250 - pad, height: 18)
        root.addSubview(statusLabel)
        let rule = FlippedView(frame: NSRect(x: 0, y: 56, width: W, height: Theme.line))
        rule.fill = Theme.ink
        root.addSubview(rule)

        // Tabs
        let tabsY: CGFloat = 72, tabH: CGFloat = 56, gap: CGFloat = 8
        let tabW = (W - pad * 2 - gap * CGFloat(Tab.allCases.count - 1)) / CGFloat(Tab.allCases.count)
        for t in Tab.allCases {
            let b = BoxButton(t.title, symbol: t.symbol) { [weak self] in self?.select(t) }
            b.fontSize = 11
            b.frame = NSRect(x: pad + CGFloat(t.rawValue) * (tabW + gap), y: tabsY, width: tabW, height: tabH)
            root.addSubview(b)
            tabButtons.append(b)
        }
        panel.frame = NSRect(x: pad, y: tabsY + tabH + 10, width: W - pad * 2, height: Self.size.height - tabsY - tabH - 10 - pad)
        panel.fill = Theme.paper
        panel.border = Theme.ink
        root.addSubview(panel)
    }

    private func select(_ t: Tab) {
        tab = t
        for (i, b) in tabButtons.enumerated() { b.selected = i == t.rawValue }
        reload()
    }

    private func updateHeader() {
        guard let app else { return }
        let on = app.serviceIsOn
        let s = app.readState()
        let count = s.map { "\($0.domains.formatted()) sites" } ?? ""
        statusLabel.stringValue = on ? "Protegendo · \(count)" : "Desligado"
        statusLabel.textColor = on ? Theme.ink : Theme.red
        statusLabel.font = Theme.font(12, bold: !on)
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
        add(Theme.label(s.uppercased(), size: 11, bold: true, color: Theme.dark), y: y) + 8
    }

    // MARK: Início

    private func buildInicio() {
        guard let app else { return }
        let on = app.serviceIsOn
        let s = app.readState()
        var y: CGFloat = 20

        let hero = FlippedView()
        hero.fill = on ? Theme.ink : Theme.red
        hero.frame = NSRect(x: 20, y: y, width: contentW, height: 96)
        let icon = Theme.symbol(on ? "shield.lefthalf.filled" : "shield.slash", size: 40, color: Theme.paper)
        icon.frame = NSRect(x: 22, y: 22, width: 52, height: 52)
        let big = Theme.label(on ? "PROTEGENDO" : "DESLIGADO", size: 28, bold: true, color: Theme.paper)
        big.frame = NSRect(x: 92, y: 20, width: contentW - 110, height: big.fittingSize.height)
        let small = Theme.label(on ? "Sites adultos não abrem neste Mac." :
                                    "Para ligar, dê dois cliques em instalar.command.", size: 12, color: Theme.paper)
        small.frame = NSRect(x: 92, y: 20 + big.fittingSize.height + 4, width: contentW - 110, height: small.fittingSize.height)
        [icon, big, small].forEach { hero.addSubview($0) }
        panel.addSubview(hero)
        y = hero.frame.maxY + 16

        if PrivateRelay.isOn() == true {
            let warn = FlippedView()
            warn.fill = Theme.paper
            warn.border = Theme.red
            let t = Theme.label("A Retransmissão Privada do iCloud está ligada", size: 13, bold: true, color: Theme.red)
            let d = Theme.label("Com ela ligada, apps como o Claude podem ficar sem internet. Desligue em: " + PrivateRelay.howTo,
                                size: 11, wrap: contentW - 190)
            let b = BoxButton("Abrir Ajustes") { PrivateRelay.openSettings() }
            b.accent = true
            let dh = textHeight(d, width: contentW - 190)
            let h = max(64, 12 + 18 + 4 + dh + 12)
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
            (today.formatted(), "bloqueios hoje"),
            ((s?.blockedTotal ?? 0).formatted(), "bloqueios no total"),
            ((s?.domains ?? 0).formatted(), "sites na lista"),
            (s?.lastUpdate.map { $0.formatted(.dateTime.day().month(.abbreviated).hour().minute()) } ?? "—", "listas atualizadas"),
        ]
        let gap: CGFloat = 10
        let bw = (contentW - gap) / 2, bh: CGFloat = 70
        for (i, st) in stats.enumerated() {
            let box = FlippedView()
            box.border = Theme.ink
            box.fill = Theme.paper
            box.frame = NSRect(x: 20 + CGFloat(i % 2) * (bw + gap), y: y + CGFloat(i / 2) * (bh + gap), width: bw, height: bh)
            let n = Theme.label(st.0, size: 22, bold: true)
            n.frame = NSRect(x: 14, y: 12, width: bw - 28, height: n.fittingSize.height)
            let l = Theme.label(st.1, size: 11, color: Theme.dark)
            l.frame = NSRect(x: 14, y: 14 + n.fittingSize.height, width: bw - 28, height: l.fittingSize.height)
            box.addSubview(n); box.addSubview(l)
            panel.addSubview(box)
        }
        y += 2 * bh + gap + 16

        let bw2 = (contentW - gap) / 2
        let up = BoxButton("Atualizar as listas", symbol: "arrow.clockwise") { [weak self] in self?.app?.requestUpdate() }
        let verse = BoxButton("Ver a janela do versículo", symbol: "book") { [weak self] in self?.app?.showVersePreview() }
        up.frame = NSRect(x: 20, y: y, width: bw2, height: 56)
        verse.frame = NSRect(x: 20 + bw2 + gap, y: y, width: bw2, height: 56)
        panel.addSubview(up); panel.addSubview(verse)
    }

    // MARK: Sites

    private func buildSites() {
        var y = sectionTitle("Testar, liberar ou bloquear um site", y: 20)
        siteField.placeholderString = "exemplo.com"
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
        let result = Theme.label(siteResult.isEmpty ? "Liberar é só para site que NÃO é adulto: pede uma frase, a senha do Mac, e só vale \(Int(Unblock.delay / 60)) minutos depois." : siteResult,
                                 size: 12, bold: !siteResult.isEmpty, color: siteResult.hasPrefix("🚫") ? Theme.red : Theme.dark, wrap: contentW)
        y = add(result, y: y, w: contentW) + 18

        let cfg = MagenConfig.load(from: Paths.config(magenDir))
        let colW = (contentW - 16) / 2
        func list(_ title: String, _ items: [String], x: CGFloat) {
            var ly = y
            let t = Theme.label(title.uppercased(), size: 11, bold: true, color: Theme.dark)
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
                let more = Theme.label("e mais \(items.count - 6)…", size: 11, color: Theme.dark)
                more.frame = NSRect(x: x, y: ly + 6, width: colW, height: more.fittingSize.height)
                panel.addSubview(more)
            }
        }
        let pending = cfg.pendingAllow.map { "⏳ \($0.domain) — às \($0.at.formatted(date: .omitted, time: .shortened))" }
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
        case .some(true): siteResult = "🚫 \(site) está BLOQUEADO (ou não existe)."
        case .some(false): siteResult = "✅ \(site) está liberado."
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
                self?.siteResult = "⏳ \(site) será liberado às \(when). Até lá, continua bloqueado."
                self?.siteField.stringValue = ""
                self?.reload()
            }
            return
        }
        app?.runAdmin([cmd, site], done: "") { [weak self] in
            self?.siteResult = "🚫 \(site) agora está bloqueado."
            self?.siteField.stringValue = ""
            self?.reload()
        }
    }

    /// Unblocking is hard on purpose: obvious adult names are refused, the person must
    /// type a sentence, then the Mac password, and the site only opens 1 hour later.
    private func confirmUnblock(_ site: String) -> Bool {
        if Unblock.isObviouslyAdult(site) {
            siteResult = "🚫 \(site) tem nome de site adulto. Ele não pode ser liberado."
            reload(); return false
        }
        let minutes = Int(Unblock.delay / 60)
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Liberar \(site)?"
        a.informativeText = """
        Liberar é só para um site que NÃO é adulto e foi bloqueado por engano.

        O site só vai abrir daqui a \(minutes) minutos. Se for um momento de tentação, esse tempo é para você respirar e desistir. Dá para cancelar a qualquer hora na aba Sites.

        Para continuar, digite exatamente:
        \(Unblock.sentence)
        """
        a.addButton(withTitle: "Pedir liberação")
        a.addButton(withTitle: "Desistir")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = Unblock.sentence
        a.accessoryView = field
        a.window.initialFirstResponder = field
        a.buttons.first?.isEnabled = true
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return false }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard typed == Unblock.sentence else {
            siteResult = "A frase não confere. Nada foi liberado."
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
        let credit = Theme.label("\(verses.count) versículos da Bíblia Livre (BLIVRE), Copyright © Diego Santos, Mario Sérgio e Marco Teles, fevereiro de 2018. Licença Creative Commons Atribuição 4.0 Brasil. Os títulos acima de cada versículo são do Magen.",
                                 size: 11, color: Theme.dark, wrap: contentW - 220)
        add(credit, x: 236, y: y + 2, w: contentW - 216)
    }

    // MARK: Proteção

    private func buildProtecao() {
        let cfg = MagenConfig.load(from: Paths.config(magenDir))
        var y: CGFloat = 20
        let relay = CheckRow(title: "Bloquear a Retransmissão Privada do iCloud",
                             detail: "Sem isso, o Safari e os apps podem passar por fora do Magen. O melhor é desligar a Retransmissão Privada nos Ajustes (" + PrivateRelay.howTo + "). Se ela ficar ligada, apps como o Claude podem perder a internet até você responder o aviso do Mac.",
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
        let info = Theme.label("""
        Para sites normais, o Magen pergunta à Cloudflare (\(cfg.upstream.first ?? "1.1.1.1")). Ele só vê o nome do site, nunca o conteúdo das páginas, por isso não deixa a internet lenta.

        As listas de sites adultos se atualizam sozinhas a cada \(Int(cfg.updateEveryHours)) horas. Mudar estas opções pede a senha do Mac. Para remover o Magen, dê dois cliques em desinstalar.command.
        """, size: 12, color: Theme.ink, wrap: contentW)
        add(info, y: y, w: contentW)
    }

    // MARK: Sobre

    private func buildSobre() {
        var y: CGFloat = 24
        let logo = Theme.label("MAGEN", size: 44, bold: true)
        y = add(logo, y: y)
        let sub = Theme.label("“escudo” em hebraico · versão \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")", size: 13, color: Theme.red)
        sub.font = Theme.font(13, bold: true)
        y = add(sub, y: y + 2) + 18
        let made = Theme.label("Feito por \(Author.name), de graça, para quem quer vencer essa luta.", size: 14, bold: true, wrap: contentW)
        y = add(made, y: y, w: contentW) + 10
        let text = Theme.label("""
        Bloqueador grátis de sites adultos para Mac. Sem conta, sem anúncios, sem coletar nada.

        Listas de bloqueio: OISD NSFW, Block List Project e StevenBlack (baixadas direto da fonte).
        Versículos: Bíblia Livre (BLIVRE), CC BY 4.0 Brasil. Fonte: Archivo, SIL Open Font License. Código: licença MIT.
        """, size: 12, color: Theme.dark, wrap: contentW)
        y = add(text, y: y, w: contentW) + 18

        let gap: CGFloat = 10, bw = (contentW - gap) / 2
        let donate = BoxButton("Apoie o Magen (Pix)", symbol: "heart") { [weak self] in self?.app?.showDonate() }
        donate.accent = true
        let update = BoxButton("Procurar atualização", symbol: "arrow.down.circle") { Updates.check(manual: true) }
        donate.frame = NSRect(x: 20, y: y, width: bw, height: 56)
        update.frame = NSRect(x: 20 + bw + gap, y: y, width: bw, height: 56)
        panel.addSubview(donate); panel.addSubview(update)
        y += 56 + 14
        let auto = CheckRow(title: "Procurar atualização sozinho", detail: "Em breve: quando o Magen estiver no GitHub, ele avisa quando sair uma versão nova.",
                            isOn: Updates.autoCheck, width: contentW)
        auto.onToggle = { [weak self] v in Updates.autoCheck = v; self?.reload() }
        add(auto, y: y)
    }
}
