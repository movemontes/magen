"""Visual da família Treco em vermelho (igual ao Sources/MagenBar/Theme.swift do Mac):
creme, tinta preta, vermelho #E10000, marca-texto #FFBEBE, bordas de 2 px e sombra dura.

Títulos grandes: Archivo larga (wdth 125, peso 900) desenhada com o Pillow, porque o Tk
não escolhe a largura de uma fonte variável. Textos: Clash Grotesk (ou Segoe UI)."""
import os
import tkinter as tk
import tkinter.font as tkfont
from functools import lru_cache

from PIL import Image, ImageDraw, ImageFont, ImageTk

from .. import assets
from ..core import WINDOWS
from ..i18n import tr

CREAM = "#FDF9EE"
PAPER = "#FFFFFF"
INK = "#0A0A0A"
RED = "#E10000"
HIGHLIGHT = "#FFBEBE"
HOVER = "#FFE8E8"
DARK = "#3C3C3C"
GRAY = "#8A8A8A"
LINE = 2
SHADOW = 4

SCALE = 1.0          # tela com zoom (125 %, 150 %...): tudo em pixels passa por px()
TEXT_FAMILY = "Segoe UI" if WINDOWS else "Helvetica"
TEXT_BOLD_FAMILY = TEXT_FAMILY
ICON_FAMILY = None   # Segoe Fluent Icons / Segoe MDL2 Assets, se houver

# Ícones (Segoe MDL2 Assets / Fluent Icons, que vêm no Windows 10 e 11)
ICONS = {"inicio": "", "sites": "", "versiculos": "", "protecao": "",
         "sobre": "", "heart": "", "download": "", "eye": "", "trash": ""}


def px(v):
    return int(round(v * SCALE))


def setup(root):
    """Chamar uma vez, logo depois de criar o Tk: zoom da tela e fontes."""
    global SCALE, TEXT_FAMILY, TEXT_BOLD_FAMILY, ICON_FAMILY
    try:
        SCALE = max(1.0, root.winfo_fpixels("1i") / 96.0) if WINDOWS else 1.0
    except tk.TclError:
        SCALE = 1.0
    families = set(tkfont.families(root))
    for medium, semibold in (("Clash Grotesk Medium", "Clash Grotesk Semibold"),
                             ("Clash Grotesk", "Clash Grotesk")):
        if medium in families:
            TEXT_FAMILY, TEXT_BOLD_FAMILY = medium, semibold if semibold in families else medium
            break
    for fam in ("Segoe Fluent Icons", "Segoe MDL2 Assets"):
        if fam in families:
            ICON_FAMILY = fam
            break


def load_private_fonts():
    """Fontes que vão dentro do app, só para o Magen (antes de criar o Tk). Só no Windows."""
    if not WINDOWS:
        return
    import ctypes
    for name in assets.CLASH + (assets.ARCHIVO,):
        p = assets.font(name)
        if os.path.exists(p):
            ctypes.windll.gdi32.AddFontResourceExW(p, 0x10, 0)  # FR_PRIVATE


def font(size, bold=False):
    return (TEXT_BOLD_FAMILY if bold else TEXT_FAMILY, -px(size * 1.0), "bold" if bold and TEXT_BOLD_FAMILY == "Segoe UI" else "normal")


def icon_font(size):
    return (ICON_FAMILY or TEXT_FAMILY, -px(size))


def icon_char(key):
    return ICONS.get(key, "") if ICON_FAMILY else ""


# ---------------------------------------------------------------- títulos desenhados

@lru_cache(maxsize=8)
def _archivo(pixels, wide=True, weight=900):
    try:
        f = ImageFont.truetype(assets.font(assets.ARCHIVO), pixels)
        f.set_variation_by_axes([weight, 125 if wide else 100])
        return f
    except (OSError, ValueError):
        return ImageFont.load_default(pixels)


def _wrap(text, f, width):
    lines, cur = [], ""
    for word in text.split():
        trial = (cur + " " + word).strip()
        if cur and f.getlength(trial) > width:
            lines.append(cur)
            cur = word
        else:
            cur = trial
    if cur:
        lines.append(cur)
    return lines or [""]


def title_image(text, size, color=INK, highlight=None, width=None, bg=None):
    """Título na Archivo larga. Com highlight, um marca-texto atrás da metade de baixo
    (como o PageTitle do Mac). width = quebra em várias linhas."""
    pixels = px(size)
    f = _archivo(pixels)
    lines = _wrap(text, f, px(width)) if width else [text]
    asc, desc = f.getmetrics()
    lh = int((asc + desc) * 1.02)
    w = max(int(f.getlength(l)) for l in lines) + px(12)
    h = lh * len(lines) + px(4)
    img = Image.new("RGBA", (w, h), bg or (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, line in enumerate(lines):
        y = i * lh
        if highlight:
            lw = int(f.getlength(line))
            d.rectangle([0, y + int(lh * 0.52), lw + px(8), y + int(lh * 0.92)], fill=highlight)
        d.text((px(2), y), line, font=f, fill=color)
    return ImageTk.PhotoImage(img)


def image(path, size):
    try:
        img = Image.open(path).convert("RGBA")
    except OSError:
        return None
    img = img.resize((px(size), px(size)), Image.LANCZOS)
    return ImageTk.PhotoImage(img)


# ---------------------------------------------------------------- peças

class BoxButton(tk.Canvas):
    """Botão branco com borda preta e sombra dura; o mouse por cima tinge de vermelho
    clarinho; apertar afunda. accent/selected = face preta com sombra vermelha."""

    def __init__(self, master, text, command=None, width=150, height=40, size=12, accent=False,
                 icon=None, bg=None, enabled=True, selected=False):
        super().__init__(master, width=px(width), height=px(height), highlightthickness=0, bd=0,
                         bg=bg or master["bg"], cursor="hand2")
        self.text, self.command, self.size, self.icon = tr(text), command, size, icon
        self.accent, self.enabled, self.selected = accent, enabled, selected
        self.hover = self.pressed = False
        self.bind("<Enter>", lambda e: self._set(hover=True))
        self.bind("<Leave>", lambda e: self._set(hover=False, pressed=False))
        self.bind("<ButtonPress-1>", lambda e: self._set(pressed=True))
        self.bind("<ButtonRelease-1>", self._release)
        self.bind("<Configure>", lambda e: self.draw())

    def _set(self, **kw):
        for k, v in kw.items():
            setattr(self, k, v)
        self.draw()

    def _release(self, e):
        was = self.pressed
        self._set(pressed=False)
        if was and self.enabled and self.command and 0 <= e.x <= self.winfo_width() and 0 <= e.y <= self.winfo_height():
            self.command()

    def configure_button(self, **kw):
        if "text" in kw:
            kw["text"] = tr(kw["text"])
        for k, v in kw.items():
            setattr(self, k, v)
        self.draw()

    def draw(self):
        self.delete("all")
        W, H = self.winfo_width(), self.winfo_height()
        if W < 4:
            W, H = int(self["width"]), int(self["height"])
        sh = px(SHADOW if self.size >= 12 else 3)
        dark = self.accent or self.selected
        off = sh if (self.pressed and self.enabled) else 0
        face = INK if dark else (HOVER if self.hover and self.enabled else PAPER)
        fg = CREAM if dark else INK
        if not self.enabled:
            face, fg = ("#5A5A5A" if dark else "#F2EFE6"), ("#DDDDDD" if dark else GRAY)
        if not off:
            self.create_rectangle(sh, sh, W - 1, H - 1, fill=RED if dark else INK, width=0)
        x0, y0, x1, y1 = off, off, W - sh - 1 + off, H - sh - 1 + off
        self.create_rectangle(x0 + 1, y0 + 1, x1, y1, fill=face, outline=INK, width=px(LINE))
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        ic = icon_char(self.icon) if self.icon else ""
        if ic:
            self.create_text(x0 + px(22), cy, text=ic, font=icon_font(self.size + 4), fill=RED if not dark else CREAM)
            self.create_text(x0 + px(42), cy, text=self.text.upper(), anchor="w", font=font(self.size, True), fill=fg)
        else:
            self.create_text(cx, cy, text=self.text.upper(), font=font(self.size, True), fill=fg)


class DashedButton(tk.Canvas):
    """Área tracejada da barra de baixo ("+ TESTAR UM SITE")."""

    def __init__(self, master, text, command, width=300, height=34):
        super().__init__(master, width=px(width), height=px(height), highlightthickness=0, bd=0,
                         bg=master["bg"], cursor="hand2")
        self.text, self.command, self.hover = tr(text), command, False
        self.bind("<Enter>", lambda e: self._h(True))
        self.bind("<Leave>", lambda e: self._h(False))
        self.bind("<ButtonRelease-1>", lambda e: self.command())
        self.bind("<Configure>", lambda e: self.draw())

    def _h(self, v):
        self.hover = v
        self.draw()

    def draw(self):
        self.delete("all")
        W, H = self.winfo_width(), self.winfo_height()
        self.create_rectangle(1, 1, W - 2, H - 2, outline=RED if self.hover else INK, width=px(LINE),
                              dash=(6, 4), fill=HOVER if self.hover else PAPER)
        self.create_text(W / 2, H / 2, text="+ " + self.text.upper(), font=font(12, True),
                         fill=RED if self.hover else INK)


class RailButton(tk.Canvas):
    """Seção no trilho preto: ícone + nome pequeno. A selecionada vira bloco branco com sombra vermelha."""

    def __init__(self, master, text, icon, command, selected=False):
        super().__init__(master, width=px(80), height=px(64), highlightthickness=0, bd=0, bg=INK, cursor="hand2")
        self.text, self.icon, self.command, self.selected, self.hover = text, icon, command, selected, False
        self.bind("<Enter>", lambda e: self._h(True))
        self.bind("<Leave>", lambda e: self._h(False))
        self.bind("<ButtonRelease-1>", lambda e: self.command())
        self.draw()

    def _h(self, v):
        self.hover = v
        self.draw()

    def draw(self):
        self.delete("all")
        W, H = px(80), px(64)
        if self.selected:
            self.create_rectangle(px(4), px(4), W - 1, H - 1, fill=RED, width=0)
            self.create_rectangle(0, 0, W - px(5), H - px(5), fill=PAPER, outline=PAPER)
        fg = INK if self.selected else (RED if self.hover else CREAM)
        ic = icon_char(self.icon)
        cx = (W - (px(5) if self.selected else 0)) / 2
        if ic:
            self.create_text(cx, px(22), text=ic, font=icon_font(20), fill=RED if self.selected else fg)
        self.create_text(cx, px(46) if ic else px(30), text=tr(self.text).upper(), font=font(9.5, True), fill=fg)


class CheckRow(tk.Frame):
    """Caixinha + título em negrito + explicação embaixo."""

    def __init__(self, master, title, detail, value, on_toggle, width=560, enabled=True):
        super().__init__(master, bg=master["bg"])
        self.value, self.on_toggle, self.enabled = value, on_toggle, enabled
        self.box = tk.Canvas(self, width=px(24), height=px(24), highlightthickness=0, bg=self["bg"],
                             cursor="hand2")
        self.box.grid(row=0, column=0, rowspan=2, sticky="n", padx=(0, px(12)), pady=(px(2), 0))
        t = tk.Label(self, text=tr(title), font=font(13, True), bg=self["bg"], fg=INK, anchor="w",
                     justify="left", wraplength=px(width - 40), cursor="hand2")
        t.grid(row=0, column=1, sticky="w")
        d = tk.Label(self, text=tr(detail), font=font(11), bg=self["bg"], fg=DARK, anchor="w",
                     justify="left", wraplength=px(width - 40))
        d.grid(row=1, column=1, sticky="w", pady=(px(2), 0))
        for w in (self.box, t):
            w.bind("<ButtonRelease-1>", lambda e: self.toggle())
        self.draw()

    def toggle(self):
        if not self.enabled:
            return
        self.value = not self.value
        self.draw()
        self.on_toggle(self.value)

    def draw(self):
        c = self.box
        c.delete("all")
        s = px(24)
        c.create_rectangle(1, 1, s - 2, s - 2, outline=INK, width=px(LINE), fill=INK if self.value else PAPER)
        if self.value:
            c.create_line(px(6), px(12), px(10), px(17), px(18), px(7), fill=RED, width=px(3))


def label(master, text, size=12, bold=False, color=INK, wrap=None, bg=None, translate=True):
    return tk.Label(master, text=tr(text) if translate else text, font=font(size, bold), fg=color,
                    bg=bg or master["bg"], anchor="w", justify="left", wraplength=px(wrap) if wrap else 0)


def boxed(master, fill=PAPER, border=INK, shadow=SHADOW, shadow_color=INK, pad=14):
    """Cartão com borda e sombra dura. Devolve (fora, dentro): ponha o conteúdo em "dentro"."""
    outer = tk.Frame(master, bg=shadow_color if shadow else master["bg"])
    inner = tk.Frame(outer, bg=fill, highlightbackground=border, highlightthickness=px(LINE) if border else 0,
                     padx=px(pad), pady=px(pad))
    inner.pack(padx=(0, px(shadow)), pady=(0, px(shadow)))
    if shadow:
        # Sombra deslocada: os cantos de cima à direita e de baixo à esquerda ficam com a cor da página.
        s = px(shadow)
        tk.Frame(outer, bg=master["bg"]).place(relx=1, x=-s, y=0, width=s, height=s)
        tk.Frame(outer, bg=master["bg"]).place(x=0, rely=1, y=-s, width=s, height=s)
    return outer, inner
