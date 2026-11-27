"""Janelinhas do Magen no estilo da família: aviso, frase para digitar, doação e atualização."""
import tkinter as tk

from .. import prefs
from ..i18n import is_en, tr, trf
from . import theme as T

AUTHOR = "Mateus"
PIX = "e2a1f4a9-ebfe-4c3c-a531-92a0e7433f14"


class Dialog(tk.Toplevel):
    """Janela modal creme, centrada no Magen (ou na tela)."""

    def __init__(self, root, title, width=460):
        super().__init__(root)
        self.withdraw()
        self.title(tr(title))
        self.configure(bg=T.CREAM)
        self.resizable(False, False)
        self.result = None
        self.body = tk.Frame(self, bg=T.CREAM, padx=T.px(26), pady=T.px(22))
        self.body.pack(fill="both", expand=True)
        self.width = width
        self.protocol("WM_DELETE_WINDOW", self.cancel)
        self.bind("<Escape>", lambda e: self.cancel())
        try:
            icon = getattr(root, "magen_icon", None)
            if icon:
                self.iconphoto(False, icon)
        except tk.TclError:
            pass

    def heading(self, text, color=T.RED, size=20):
        self._img = T.title_image(tr(text), size, color=color, width=self.width - 52, bg=T.CREAM)
        tk.Label(self.body, image=self._img, bg=T.CREAM, bd=0).pack(anchor="w", pady=(0, T.px(10)))

    def text(self, text, size=12, bold=False, color=T.INK, pady=(0, 10)):
        T.label(self.body, text, size=size, bold=bold, color=color, wrap=self.width - 52).pack(
            anchor="w", pady=(T.px(pady[0]), T.px(pady[1])))

    def buttons(self, items):
        """items: [(texto, ação, destaque)]. O primeiro com destaque responde ao Enter."""
        row = tk.Frame(self.body, bg=T.CREAM)
        row.pack(fill="x", pady=(T.px(8), 0))
        n = len(items)
        bw = (self.width - 52 - 10 * (n - 1)) / n
        for i, (text, action, accent) in enumerate(items):
            b = T.BoxButton(row, text, action, width=bw, height=42, accent=accent)
            b.pack(side="left", padx=(0 if i == 0 else T.px(10), 0))
            if accent:
                self.bind("<Return>", lambda e, a=action: a())
        return row

    def run(self):
        self.update_idletasks()
        m = self.master
        w, h = self.winfo_reqwidth(), self.winfo_reqheight()
        if m.winfo_viewable():
            x = m.winfo_rootx() + (m.winfo_width() - w) // 2
            y = m.winfo_rooty() + (m.winfo_height() - h) // 3
        else:
            x, y = (self.winfo_screenwidth() - w) // 2, (self.winfo_screenheight() - h) // 3
        self.geometry(f"+{max(0, x)}+{max(0, y)}")
        self.deiconify()
        self.attributes("-topmost", True)
        self.lift()
        self.focus_force()
        self.grab_set()
        self.wait_window()
        return self.result

    def done(self, value):
        self.result = value
        self.grab_release()
        self.destroy()

    def cancel(self):
        self.done(None)


def message(root, title, text):
    d = Dialog(root, title)
    d.heading(title, color=T.INK, size=18)
    d.text(text)
    d.buttons([("OK", lambda: d.done(True), True)])
    return d.run()


def ask(root, title, text, yes, no="Desistir"):
    d = Dialog(root, title)
    d.heading(title, color=T.INK, size=18)
    d.text(text)
    d.buttons([(no, lambda: d.done(False), False), (yes, lambda: d.done(True), True)])
    return bool(d.run())


def ask_sentence(root, title, text, sentence, yes):
    """A pessoa precisa digitar a frase exata. Devolve True se conferiu, False se não, None se desistiu."""
    d = Dialog(root, title, width=500)
    d.heading(title, color=T.RED, size=20)
    d.text(text)
    T.label(d.body, sentence, size=13, bold=True, color=T.RED, translate=False).pack(anchor="w", pady=(0, T.px(8)))
    field = tk.Entry(d.body, font=T.font(14), relief="flat", bg=T.PAPER, fg=T.INK, insertbackground=T.INK,
                     highlightthickness=T.px(T.LINE), highlightbackground=T.INK, highlightcolor=T.RED)
    field.pack(fill="x", ipady=T.px(6), pady=(0, T.px(8)))
    field.focus_set()

    def confirm():
        d.done(field.get().strip().lower() == sentence)
    d.buttons([("Desistir", d.cancel, False), (yes, confirm, True)])
    d.after(50, field.focus_force)
    return d.run()


# ---------------------------------------------------------------- doação (como o welcome.py do Treco)

def donation_seen():
    return bool(prefs.get("doacaoVista"))


def signature(d):
    """Foto redonda pequena, "Mateus" em negrito e a frase em vermelho."""
    import tkinter as tk
    from .. import assets
    row = tk.Frame(d.body, bg=T.CREAM)
    row.pack(anchor="w", pady=(T.px(2), T.px(12)))
    d._photo = T.image(assets.icon("mateus.png"), 32)
    if d._photo:
        tk.Label(row, image=d._photo, bg=T.CREAM, bd=0).pack(side="left", padx=(0, T.px(10)))
    words = tk.Frame(row, bg=T.CREAM)
    words.pack(side="left")
    T.label(words, AUTHOR, size=12, bold=True, translate=False).pack(anchor="w")
    T.label(words, "Tudo para honra e glória do Senhor!", size=12, color=T.RED).pack(anchor="w")


def show_donation(root):
    prefs.set("doacaoVista", True)
    d = Dialog(root, "Apoie o Magen", width=480)
    d.heading("ME AJUDA: TENHO 5 BOCAS PRA ALIMENTAR", size=22)
    d.text("e fiz esse app de graça pra você.", size=13, bold=True, pady=(0, 14))
    d.text(trf("Oi, eu sou o %s. O Magen não tem anúncio, não pede conta e não manda nada seu pra internet.", AUTHOR))
    if is_en():
        # Sem Pix em inglês (regra dos apps do Mateus).
        d.text("Se ele te ajudar nessa luta, o melhor apoio é mostrar o Magen para alguém que precisa. Obrigado de coração!")
        signature(d)
        d.buttons([("Bora usar", lambda: d.done(True), True)])
    else:
        d.text("Se ele te ajudar nessa luta, qualquer valor ajuda muito aqui em casa. Obrigado de coração!")
        signature(d)
        d.text("Pix (chave aleatória, PicPay):", bold=True, pady=(4, 2))
        T.label(d.body, PIX, size=12, color=T.RED, translate=False).pack(anchor="w", pady=(0, T.px(10)))
        copy_btn = []

        def copy():
            d.clipboard_clear()
            d.clipboard_append(PIX)
            copy_btn[0].configure_button(text="Copiado!")
        row = d.buttons([("Bora usar", lambda: d.done(True), False), ("Copiar chave Pix", copy, True)])
        copy_btn.append(row.winfo_children()[1])
    return d.run()


# ---------------------------------------------------------------- atualização

def offer_update(root, version, current, notes):
    """Devolve "now", "later" ou "skip"."""
    d = Dialog(root, "Atualização do Magen", width=480)
    d.heading(trf("Magen %s chegou", version), size=20)
    d.text(trf("Você está com a %s.", current), color=T.DARK)
    if notes:
        d.text(notes[:900])
    d.buttons([("Pular esta versão", lambda: d.done("skip"), False), ("Depois", lambda: d.done("later"), False),
               ("Atualizar agora", lambda: d.done("now"), True)])
    return d.run() or "later"
