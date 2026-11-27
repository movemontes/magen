"""A janela que aparece quando um site adulto é bloqueado: cobre todas as telas de
vermelho, mostra um cartão no centro com um título e o versículo, e só deixa fechar
depois de alguns segundos. É de propósito que incomoda (como o VerseAlert do Mac)."""
import json
import os
import random
import tkinter as tk

from ..core import WINDOWS
from ..i18n import current, is_en, tr, trf
from . import theme as T

_DATA = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "versiculos.json")
with open(_DATA, encoding="utf-8") as _f:
    VERSES = json.load(_f)


def verses():
    return VERSES["en" if is_en() else "pt"]


def credit_long():
    if is_en():
        return (f"{len(VERSES['en'])} verses from the World English Bible (public domain). "
                "The titles above each verse are Magen's.")
    return (f"{len(VERSES['pt'])} versículos da Bíblia Livre (BLIVRE), Copyright © Diego Santos, Mario Sérgio e "
            "Marco Teles, fevereiro de 2018. Licença Creative Commons Atribuição 4.0 Brasil. "
            "Os títulos acima de cada versículo são do Magen.")


def virtual_screen(root):
    """Retângulo que cobre todos os monitores (x, y, largura, altura)."""
    if WINDOWS:
        import ctypes
        m = ctypes.windll.user32.GetSystemMetrics
        return m(76), m(77), m(78), m(79)  # SM_XVIRTUALSCREEN, Y, CX, CY
    return 0, 0, root.winfo_screenwidth(), root.winfo_screenheight()


class VerseAlert:
    def __init__(self, root):
        self.root = root
        self.cover = self.card = None
        self.remaining = 0
        self.last_index = -1
        self.button = None

    @property
    def showing(self):
        return self.cover is not None

    def random_verse(self):
        vs = verses()
        i = random.randrange(len(vs))
        if len(vs) > 1 and i == self.last_index:
            i = (i + 1) % len(vs)
        self.last_index = i
        return vs[i]

    def show(self, verse=None, heading="Site bloqueado", lock_seconds=5):
        self.close()
        v = verse or self.random_verse()
        x, y, w, h = virtual_screen(self.root)

        # Capa vermelha sobre todas as telas
        cover = tk.Toplevel(self.root)
        cover.overrideredirect(True)
        cover.configure(bg=T.RED)
        cover.geometry(f"{w}x{h}+{x}+{y}")
        cover.attributes("-topmost", True)
        try:
            cover.attributes("-alpha", 0.93)
        except tk.TclError:
            pass
        self.cover = cover

        # Cartão no centro da tela principal
        card = tk.Toplevel(self.root)
        card.overrideredirect(True)
        card.configure(bg=T.INK)
        card.attributes("-topmost", True)
        self.card = card
        width = min(680, int(self.root.winfo_screenwidth() / T.SCALE) - 80)
        self._build(card, v, tr(heading), width)
        card.update_idletasks()
        cw, ch = card.winfo_reqwidth(), card.winfo_reqheight()
        sw, sh = self.root.winfo_screenwidth(), self.root.winfo_screenheight()
        card.geometry(f"+{(sw - cw) // 2}+{(sh - ch) // 2}")
        for win in (cover, card):
            for key in ("<Return>", "<KP_Enter>", "<Escape>", "<space>"):
                win.bind(key, lambda e: self.try_close())
        card.lift()
        card.focus_force()

        self.remaining = max(0, int(lock_seconds))
        self._update_button()
        if self.remaining > 0:
            self.root.after(1000, self._tick)
        print(f"Janela de versículo: {v['ref']}", flush=True)

    def _tick(self):
        if not self.showing:
            return
        self.remaining -= 1
        self._update_button()
        if self.remaining > 0:
            self.root.after(1000, self._tick)
        else:
            # Volta para a frente se a pessoa tentou trocar de janela.
            self.card.lift()

    def _update_button(self):
        if not self.button:
            return
        if self.remaining > 0:
            self.button.configure_button(text=trf("Respire… %d", self.remaining), enabled=False, accent=False)
        else:
            self.button.configure_button(text="Entendi", enabled=True, accent=True)

    def try_close(self):
        if self.remaining <= 0:
            self.close()

    def close(self):
        for w in (self.card, self.cover):
            if w is not None:
                try:
                    w.destroy()
                except tk.TclError:
                    pass
        self.card = self.cover = self.button = None

    def _build(self, card, v, heading, width):
        pad = 28
        outer, box = T.boxed(card, fill=T.PAPER, shadow=0, pad=0)
        outer.configure(bg=T.INK)
        outer.pack()
        inner_w = width - 2 * pad
        box.configure(padx=T.px(pad), pady=T.px(18))
        head = tk.Frame(box, bg=T.PAPER)
        head.pack(fill="x")
        self._logo = T.title_image("MAGEN", 26, bg=T.PAPER)
        tk.Label(head, image=self._logo, bg=T.PAPER, bd=0).pack(side="left")
        tk.Label(head, text=heading.upper(), font=T.font(12, True), fg=T.RED, bg=T.PAPER).pack(side="right")
        tk.Frame(box, bg=T.INK, height=T.px(T.LINE)).pack(fill="x", pady=(T.px(12), T.px(24)))
        self._title = T.title_image(v["title"], 32, color=T.RED, width=inner_w, bg=T.PAPER)
        tk.Label(box, image=self._title, bg=T.PAPER, bd=0).pack(anchor="w")
        tk.Label(box, text=f"“{v['text']}”", font=T.font(19), fg=T.INK, bg=T.PAPER, justify="left",
                 anchor="w", wraplength=T.px(inner_w)).pack(anchor="w", pady=(T.px(16), T.px(12)))
        source = "WORLD ENGLISH BIBLE" if current() == "en" else "BÍBLIA LIVRE"
        tk.Label(box, text=f"{v['ref'].upper()}  ·  {source}", font=T.font(12, True), fg=T.DARK,
                 bg=T.PAPER).pack(anchor="w")
        tk.Label(box, text=tr("Feche o navegador por alguns minutos. Levante, beba água, fale com alguém."),
                 font=T.font(12), fg=T.DARK, bg=T.PAPER, justify="left", anchor="w",
                 wraplength=T.px(inner_w)).pack(anchor="w", pady=(T.px(22), T.px(16)))
        self.button = T.BoxButton(box, "Entendi", self.try_close, width=inner_w, height=50, size=15, bg=T.PAPER)
        self.button.pack(anchor="w")
