"""Janela principal (como o MainWindow.swift do Mac): trilho preto à esquerda com o
escudo e as seções, título enorme com marca-texto, conteúdo no creme e barra branca embaixo."""
import tkinter as tk
from datetime import datetime

from .. import assets, core, prefs, updates
from ..i18n import is_en, num, tr, trf
from ..version import VERSION
from . import theme as T
from .verse import credit_long

TABS = [("inicio", "Início"), ("sites", "Sites"), ("versiculos", "Versículos"), ("protecao", "Proteção"),
        ("sobre", "Sobre")]
LEADS = {
    "inicio": "Veja se o Magen está protegendo este computador.",
    "sites": "Teste, libere ou bloqueie um site.",
    "versiculos": "A janela que aparece quando um site adulto é bloqueado.",
    "protecao": "Opções contra burla e como o Magen funciona.",
    "sobre": "Quem fez, créditos e atualizações.",
}
SIZE = (760, 700)


def fmt_time(iso_text, with_date=True):
    dt = core.parse_iso(iso_text)
    if not dt:
        return "—"
    local = dt.astimezone()
    if not with_date:
        return local.strftime("%I:%M %p").lstrip("0") if is_en() else local.strftime("%H:%M")
    months_pt = "jan fev mar abr mai jun jul ago set out nov dez".split()
    months_en = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
    if is_en():
        return f"{months_en[local.month - 1]} {local.day}, {local.strftime('%I:%M %p').lstrip('0')}"
    return f"{local.day} de {months_pt[local.month - 1]}, {local:%H:%M}"


class MainWindow:
    def __init__(self, root, app):
        self.root, self.app = root, app
        self.tab = "inicio"
        self.site_result = ""
        self.site_text = tk.StringVar()
        self._images = []
        root.title("Magen")
        root.configure(bg=T.CREAM)
        root.minsize(T.px(SIZE[0]), T.px(SIZE[1]))
        geo = prefs.get("janela")
        root.geometry(geo if geo else f"{T.px(SIZE[0])}x{T.px(SIZE[1])}")
        root.protocol("WM_DELETE_WINDOW", self.hide)
        self._last_size = None
        root.bind("<Configure>", self._resized)
        self.build()
        self._tick()

    # ------------------------------------------------------------ mostrar / esconder

    def show(self, tab=None):
        if tab:
            self.tab = tab
        self.build()
        self.root.deiconify()
        self.root.lift()
        self.root.focus_force()

    def hide(self):
        """Fechar a janela só esconde: o Magen continua perto do relógio."""
        try:
            prefs.set("janela", self.root.geometry())
        except OSError:
            pass
        self.root.withdraw()

    def _resized(self, e):
        if e.widget is self.root:
            size = (e.width, e.height)
            if self._last_size and size != self._last_size:
                self.root.after_idle(self.build)
            self._last_size = size

    def _tick(self):
        """A cada 5 s, com a janela aberta: atualiza o estado (e a página Início)."""
        if self.root.winfo_viewable():
            if self.tab == "inicio":
                self.build()
            else:
                self._status()
        self.root.after(5000, self._tick)

    def select(self, tab):
        self.tab = tab
        self.build()

    # ------------------------------------------------------------ montagem

    def img(self, image):
        self._images.append(image)
        return image

    def build(self):
        for w in self.root.winfo_children():
            if not isinstance(w, tk.Toplevel):
                w.destroy()
        self._images = []
        root = self.root

        rail = tk.Frame(root, bg=T.INK, width=T.px(92))
        rail.pack(side="left", fill="y")
        rail.pack_propagate(False)
        logo = T.image(assets.icon("escudo-512.png"), 66)
        if logo:
            tk.Label(rail, image=self.img(logo), bg=T.INK, bd=0).pack(pady=(T.px(18), T.px(14)))
        for key, title in TABS:
            b = T.RailButton(rail, title, key, lambda k=key: self.select(k), selected=key == self.tab)
            if key == "sobre":
                b.pack(side="bottom", pady=(0, T.px(12)))
            else:
                b.pack(pady=(0, T.px(6)))

        main = tk.Frame(root, bg=T.CREAM)
        main.pack(side="left", fill="both", expand=True)
        self.build_bottom_bar(main)

        head = tk.Frame(main, bg=T.CREAM, padx=T.px(28))
        head.pack(fill="x", pady=(T.px(12), 0))
        self.status_label = tk.Label(head, font=T.font(11), bg=T.CREAM, anchor="w")
        self.status_label.pack(fill="x")
        title = dict(TABS)[self.tab]
        tk.Label(head, image=self.img(T.title_image(tr(title), 40, highlight=T.HIGHLIGHT, bg=T.CREAM)),
                 bg=T.CREAM, bd=0).pack(anchor="w", pady=(T.px(4), 0))
        T.label(head, LEADS[self.tab], size=13, color=T.DARK).pack(anchor="w", pady=(T.px(2), T.px(8)))
        self._status()

        self.panel = tk.Frame(main, bg=T.CREAM, padx=T.px(28), pady=T.px(10))
        self.panel.pack(fill="both", expand=True)
        self.root.update_idletasks()
        self.content_w = max(400, int(self.panel.winfo_width() / T.SCALE) - 56)
        getattr(self, "page_" + self.tab)()

    def _status(self):
        on = self.app.service_on()
        s = self.app.state()
        domains = s.get("domains", 0)
        count = tr("baixando as listas…") if domains < 1000 else trf("%s sites", num(domains))
        self.status_label.configure(text=trf("Protegendo · %s", count) if on else tr("Desligado"),
                                    fg=T.DARK if on else T.RED, font=T.font(11, not on))

    def build_bottom_bar(self, main):
        bar = tk.Frame(main, bg=T.PAPER, height=T.px(64))
        bar.pack(side="bottom", fill="x")
        bar.pack_propagate(False)
        tk.Frame(bar, bg=T.INK, height=T.px(T.LINE)).pack(side="top", fill="x")
        inner = tk.Frame(bar, bg=T.PAPER)
        inner.pack(fill="both", expand=True, padx=T.px(20), pady=(T.px(12), 0))
        on = self.app.service_on()
        busy = self.app.busy
        main_btn = T.BoxButton(inner, "Ver versículo" if on else ("Ligando…" if busy else "Ligar a proteção"),
                               self.app.show_verse_preview if on else self.app.turn_on,
                               width=160, height=40, accent=True, bg=T.PAPER, enabled=on or not busy)
        main_btn.pack(side="right")
        upd = T.BoxButton(inner, "Atualizar listas", self.app.request_update, width=160, height=40, bg=T.PAPER,
                          enabled=on)
        upd.pack(side="right", padx=(0, T.px(10)))
        dashed = T.DashedButton(inner, "Testar um site", lambda: self.select("sites"), height=36)
        dashed.pack(side="left", fill="x", expand=True, padx=(0, T.px(16)), pady=(0, T.px(4)))

    def section(self, text, pady=(0, 8)):
        T.label(self.panel, tr(text).upper(), size=11, bold=True, color=T.DARK, translate=False).pack(
            anchor="w", pady=(T.px(pady[0]), T.px(pady[1])))

    # ------------------------------------------------------------ Início

    def page_inicio(self):
        on = self.app.service_on()
        s = self.app.state()
        W = self.content_w
        outer, hero = T.boxed(self.panel, fill=T.INK if on else T.RED, border=None, shadow=6,
                              shadow_color=T.RED if on else T.INK, pad=20)
        outer.pack(anchor="w", pady=(T.px(6), T.px(16)))
        hero.configure(width=T.px(W), height=T.px(100))
        hero.pack_propagate(False)
        bg = hero["bg"]
        left = tk.Frame(hero, bg=bg)
        left.pack(side="left", fill="both", expand=True)
        big = "PROTEGENDO" if on else "DESLIGADO"
        tk.Label(left, image=self.img(T.title_image(tr(big), 28, color=T.PAPER, bg=bg)), bg=bg, bd=0).pack(anchor="w")
        if on:
            small = "Sites adultos não abrem neste computador."
        elif self.app.busy:
            small = "Ligando… pode levar até 1 minuto."
        elif self.app.service_installed():
            small = "O serviço está instalado, mas não respondeu. Tente ligar de novo."
        else:
            small = "Clique em “Ligar a proteção”. O Windows vai pedir permissão de administrador."
        T.label(left, small, size=12, color=T.PAPER, bg=bg, wrap=W - (240 if not on else 60)).pack(anchor="w")
        if not on:
            T.BoxButton(hero, "Ligando…" if self.app.busy else "Ligar a proteção", self.app.turn_on,
                        width=180, height=42, bg=bg, enabled=not self.app.busy).pack(side="right")

        if not on and self.app.dns_points_to_magen():
            warn_o, warn = T.boxed(self.panel, fill=T.PAPER, border=T.RED, shadow=T.SHADOW, shadow_color=T.RED)
            warn_o.pack(anchor="w", fill="x", pady=(0, T.px(16)))
            T.BoxButton(warn, "Consertar a internet", self.app.fix_internet, width=190, height=40,
                        accent=True, bg=T.PAPER).pack(side="right")
            T.label(warn, "A internet pode estar parada", size=13, bold=True, color=T.RED, bg=T.PAPER).pack(anchor="w")
            T.label(warn, "O Windows ainda pergunta os endereços ao Magen, mas ele está desligado. Conserte "
                          "aqui (pede permissão de administrador) ou ligue a proteção de novo.",
                    size=11, wrap=W - 240, bg=T.PAPER).pack(anchor="w")

        today = s.get("blockedToday", 0) if s.get("todayKey") == core.today_key() else 0
        domains = s.get("domains", 0)
        stats = [
            (num(today), "bloqueios hoje"),
            (num(s.get("blockedTotal", 0)), "bloqueios no total"),
            (tr("Baixando…") if domains < 1000 else num(domains),
             "as listas chegam em até 1 minuto" if domains < 1000 else "sites na lista"),
            (fmt_time(s.get("lastUpdate")), "listas atualizadas"),
        ]
        grid = tk.Frame(self.panel, bg=T.CREAM)
        grid.pack(anchor="w")
        bw = (W - 10) / 2
        for i, (n, label) in enumerate(stats):
            o, box = T.boxed(grid, fill=T.PAPER, shadow=3, pad=12)
            o.grid(row=i // 2, column=i % 2, padx=(0, T.px(10)) if i % 2 == 0 else 0, pady=(0, T.px(10)), sticky="w")
            box.configure(width=T.px(bw - 3), height=T.px(66))
            box.pack_propagate(False)
            tk.Label(box, image=self.img(T.title_image(n, 22, bg=T.PAPER)), bg=T.PAPER, bd=0).pack(anchor="w")
            T.label(box, label, size=11, color=T.DARK, bg=T.PAPER).pack(anchor="w")

    # ------------------------------------------------------------ Sites

    def page_sites(self):
        W = self.content_w
        self.section("Testar, liberar ou bloquear um site")
        entry = tk.Entry(self.panel, textvariable=self.site_text, font=T.font(14), relief="flat", bg=T.PAPER,
                         fg=T.INK, insertbackground=T.INK, highlightthickness=T.px(T.LINE),
                         highlightbackground=T.INK, highlightcolor=T.RED)
        entry.pack(fill="x", ipady=T.px(6), pady=(0, T.px(10)))
        entry.bind("<Return>", lambda e: self.test_site())
        entry.focus_set()
        row = tk.Frame(self.panel, bg=T.CREAM)
        row.pack(fill="x", pady=(0, T.px(10)))
        bw = (W - 16) / 3
        for i, (text, fn) in enumerate((("Testar", self.test_site), ("Liberar", lambda: self.change_site("liberar")),
                                        ("Bloquear", lambda: self.change_site("bloquear")))):
            T.BoxButton(row, text, fn, width=bw, height=42).pack(side="left", padx=(0 if i == 0 else T.px(8), 0))
        text = self.site_result or trf("Liberar é só para site que NÃO é adulto: pede uma frase, a permissão de "
                                       "administrador, e só vale %d minutos depois.", core.UNBLOCK_DELAY // 60)
        T.label(self.panel, text, size=12, bold=bool(self.site_result), translate=False,
                color=T.RED if self.site_result.startswith("🚫") else T.DARK, wrap=W).pack(anchor="w", pady=(0, T.px(18)))

        cfg = self.app.config()
        cols = tk.Frame(self.panel, bg=T.CREAM)
        cols.pack(fill="x")
        cw = (W - 16) / 2
        pending = [(trf("⏳ %s — às %s", p["domain"], fmt_time(p.get("at"), with_date=False)), p["domain"])
                   for p in cfg.get("pendingAllow", [])]
        allowed = pending + [(d, d) for d in cfg.get("allow", [])]
        blocked = [(d, d) for d in cfg.get("block", [])]
        for col, (title, items) in enumerate((("Liberados por você", allowed), ("Bloqueados a mais", blocked))):
            f = tk.Frame(cols, bg=T.CREAM, width=T.px(cw))
            f.grid(row=0, column=col, sticky="nw", padx=(0, T.px(16)) if col == 0 else 0)
            T.label(f, tr(title).upper(), size=11, bold=True, color=T.DARK, translate=False).pack(anchor="w", pady=(0, T.px(6)))
            if not items:
                T.label(f, "Nenhum", size=12, color=T.GRAY).pack(anchor="w")
            for shown, domain in items[:6]:
                r = tk.Frame(f, bg=T.PAPER, highlightthickness=T.px(T.LINE), highlightbackground=T.INK,
                             width=T.px(cw), height=T.px(32))
                r.pack(anchor="w", pady=(0, T.px(4)))
                r.pack_propagate(False)
                T.BoxButton(r, "×", lambda d=domain: self.app.run_admin(["desfazer", d], self.build), width=30,
                            height=28, size=11, bg=T.PAPER).pack(side="right")
                T.label(r, shown, size=12, bg=T.PAPER, translate=False).pack(side="left", padx=T.px(8))
            if len(items) > 6:
                T.label(f, trf("e mais %d…", len(items) - 6), size=11, color=T.DARK, translate=False).pack(anchor="w")

    def typed_site(self):
        raw = self.site_text.get().strip()
        d = core.clean_site(raw)
        if not d:
            self.site_result = tr("Digite o endereço de um site.") if not raw else \
                tr("Endereço inválido. Digite só o endereço, por exemplo: exemplo.com")
            self.build()
        return d

    def test_site(self):
        site = self.typed_site()
        if not site:
            return
        r = self.app.dns_check(site)
        self.site_result = {True: trf("🚫 %s está BLOQUEADO (ou não existe).", site),
                            False: trf("✅ %s está liberado.", site),
                            None: tr("O Magen não respondeu. Ele está ligado?")}[r]
        self.build()

    def change_site(self, cmd):
        site = self.typed_site()
        if not site:
            return
        if cmd == "liberar":
            if not self.app.confirm_unblock(site):
                self.build()
                return

            def done():
                at = datetime.now().timestamp() + core.UNBLOCK_DELAY
                when = datetime.fromtimestamp(at).strftime("%I:%M %p" if is_en() else "%H:%M")
                self.site_result = trf("⏳ %s será liberado às %s. Até lá, continua bloqueado.", site, when)
                self.site_text.set("")
                self.build()
            self.app.run_admin(["liberar", site], done)
            return

        def done_block():
            self.site_result = trf("🚫 %s agora está bloqueado.", site)
            self.site_text.set("")
            self.build()
        self.app.run_admin(["bloquear", site], done_block)

    # ------------------------------------------------------------ Versículos

    def page_versiculos(self):
        W = self.content_w
        on = prefs.get("versiculos", True)

        def toggle(v):
            prefs.set("versiculos", v)
            self.build()
        T.CheckRow(self.panel, "Mostrar a janela com versículo quando um site adulto for bloqueado",
                   "Ela cobre a tela, mostra um versículo e só fecha depois de alguns segundos. "
                   "O nome do site nunca aparece.", on, toggle, width=W).pack(anchor="w", pady=(T.px(4), T.px(22)))

        def choices(title, key, options, default):
            self.section(title)
            row = tk.Frame(self.panel, bg=T.CREAM)
            row.pack(fill="x", pady=(0, T.px(22)))
            cur = prefs.get(key, default)
            bw = (W - 8 * (len(options) - 1)) / len(options)
            for i, (text, value) in enumerate(options):
                def pick(v=value):
                    prefs.set(key, v)
                    self.build()
                T.BoxButton(row, text, pick, width=bw, height=38, selected=value == cur, enabled=on).pack(
                    side="left", padx=(0 if i == 0 else T.px(8), 0))
        choices("Tempo até poder fechar", "segundosParaFechar", [("3 s", 3), ("5 s", 5), ("10 s", 10), ("15 s", 15)], 5)
        choices("Intervalo mínimo entre janelas", "minutosEntreJanelas", [("1 min", 1), ("5 min", 5), ("15 min", 15)], 1)
        row = tk.Frame(self.panel, bg=T.CREAM)
        row.pack(fill="x")
        T.BoxButton(row, "Ver como fica", self.app.show_verse_preview, width=200, height=56, icon="eye").pack(side="left")
        T.label(row, credit_long(), size=11, color=T.DARK, wrap=W - 230, translate=False).pack(
            side="left", padx=(T.px(16), 0))

    # ------------------------------------------------------------ Proteção

    def page_protecao(self):
        W = self.content_w
        cfg = self.app.config()

        def toggle(v):
            self.app.run_admin(["antiburla", "sim" if v else "nao"], self.build)
        T.CheckRow(self.panel, "Bloquear o “DNS seguro” dos navegadores",
                   "Chrome, Firefox e Edge têm uma opção que pergunta os endereços por fora do Windows. "
                   "Com isso ligado, eles voltam a passar pelo Magen.",
                   cfg.get("antiBypass", True), toggle, width=W).pack(anchor="w", pady=(T.px(4), T.px(24)))
        self.section("Como funciona")
        T.label(self.panel, trf("Para sites normais, o Magen pergunta à Cloudflare (%s). Ele só vê o nome do site, "
                                "nunca o conteúdo das páginas, por isso não deixa a internet lenta.\n\nAs listas de "
                                "sites adultos se atualizam sozinhas a cada %d horas. Mudar estas opções pede "
                                "permissão de administrador.", (cfg.get("upstream") or ["1.1.1.1"])[0],
                                int(cfg.get("updateEveryHours", 24))),
                size=12, wrap=W, translate=False).pack(anchor="w", pady=(0, T.px(20)))
        if self.app.service_installed():
            T.BoxButton(self.panel, "Remover o Magen deste computador…", self.app.remove, width=320, height=56,
                        icon="trash").pack(anchor="w")

    # ------------------------------------------------------------ Sobre

    def page_sobre(self):
        W = self.content_w
        tk.Label(self.panel, image=self.img(T.title_image("MAGEN", 44, bg=T.CREAM)), bg=T.CREAM, bd=0).pack(anchor="w")
        T.label(self.panel, trf("“escudo” em hebraico · versão %s", VERSION), size=13, bold=True, color=T.RED,
                translate=False).pack(anchor="w", pady=(T.px(2), T.px(16)))
        T.label(self.panel, trf("Feito por %s, de graça, para quem quer vencer essa luta.", "Mateus"), size=14,
                bold=True, wrap=W, translate=False).pack(anchor="w", pady=(0, T.px(8)))
        about = ("Free adult-site blocker for Windows and Mac. No account, no ads, no data collected.\n\n"
                 "Block lists: OISD NSFW, Block List Project and StevenBlack (downloaded straight from the source).\n"
                 "Verses: World English Bible (public domain) and Bíblia Livre (CC BY 4.0 Brasil). "
                 "Font: Archivo, SIL Open Font License. Code: MIT license.") if is_en() else (
                 "Bloqueador grátis de sites adultos para Windows e Mac. Sem conta, sem anúncios, sem coletar nada.\n\n"
                 "Listas de bloqueio: OISD NSFW, Block List Project e StevenBlack (baixadas direto da fonte).\n"
                 "Versículos: Bíblia Livre (BLIVRE), CC BY 4.0 Brasil, e World English Bible (domínio público). "
                 "Fonte: Archivo, SIL Open Font License. Código: licença MIT.")
        T.label(self.panel, about, size=12, color=T.DARK, wrap=W, translate=False).pack(anchor="w", pady=(0, T.px(16)))
        row = tk.Frame(self.panel, bg=T.CREAM)
        row.pack(fill="x", pady=(0, T.px(14)))
        bw = (W - 10) / 2
        T.BoxButton(row, "Support Magen" if is_en() else "Apoie o Magen (Pix)", self.app.show_donation, width=bw,
                    height=56, accent=True, icon="heart").pack(side="left")
        T.BoxButton(row, "Procurar atualização", lambda: self.app.check_updates(manual=True), width=bw, height=56,
                    icon="download").pack(side="left", padx=(T.px(10), 0))

        def toggle(v):
            prefs.set("atualizarSozinho", v)
        T.CheckRow(self.panel, "Procurar atualização sozinho",
                   "Uma vez por dia, o Magen procura uma versão nova no GitHub e avisa. A atualização troca o "
                   "app e o serviço de uma vez (o Windows pede permissão).",
                   updates.auto_check_on(), toggle, width=W).pack(anchor="w", pady=(0, T.px(14)))
        lang = tk.Frame(self.panel, bg=T.CREAM)
        lang.pack(anchor="w")
        T.label(lang, "Idioma / Language", size=11, bold=True, color=T.DARK, translate=False).pack(side="left", padx=(0, T.px(12)))
        for code, name in (("pt", "Português"), ("en", "English")):
            T.BoxButton(lang, name, lambda c=code: self.app.change_language(c), width=120, height=34, size=11,
                        selected=(code == "en") == is_en()).pack(side="left", padx=(0, T.px(8)))
