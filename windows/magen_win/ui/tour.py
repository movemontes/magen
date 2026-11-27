"""Tour da primeira vez (como o do Treco, sem mascote): escurece a janela, deixa aceso só o
pedaço que o passo explica e mostra um balão com o texto, "Próximo" e "Pular o tour".

São duas janelinhas por cima da janela do Magen, sem borda:
- a sombra: preta e meio transparente, com um "buraco" (cor-chave) em cima do que o passo mostra;
- o balão: dono da sombra, por isso fica sempre na frente dela, mesmo se a pessoa clicar no escuro.
"""
import tkinter as tk

from .. import prefs
from ..i18n import tr, trf
from . import theme as T

TOUR_VERSION = 1  # aumente quando o tour mudar: ele aparece de novo uma vez
HOLE = "#FF00FE"  # cor que o Windows deixa transparente (o "buraco" da sombra)

# (aba, alvo, título, texto). O alvo é um nome que a janela marca em window.spots.
STEPS = [
    ("inicio", None, "Bem-vindo ao Magen",
     "Em poucos passos, você vê como ele protege este computador. Dá para pular quando quiser."),
    ("inicio", "hero", "Está protegendo?",
     "Preto quer dizer protegendo. Vermelho quer dizer desligado: aí aparece o botão “Ligar a proteção”, "
     "e o Windows pede permissão."),
    ("inicio", "stats", "Os números",
     "Quantos sites adultos foram bloqueados hoje e no total, e quando as listas foram atualizadas. "
     "O nome dos sites nunca é guardado."),
    ("inicio", "rail", "As seções",
     "Início, Sites, Versículos e Proteção ficam aqui. Embaixo fica o Sobre."),
    ("sites", "sitebox", "Testar, liberar ou bloquear",
     "Digite um site para saber se ele está bloqueado. “Liberar” é só para site que não é adulto: pede uma "
     "frase, a permissão do Windows, e só vale 1 hora depois."),
    ("versiculos", "panel", "O versículo",
     "Quando um site adulto é bloqueado, a tela fica vermelha com um versículo e só fecha depois de alguns "
     "segundos. Aqui você escolhe esse tempo. “Ver como fica” mostra um exemplo."),
    ("protecao", "antiburla", "Contra burla",
     "Deixe isto ligado: assim os navegadores não fogem do Magen pelo “DNS seguro”. Remover o Magen pede "
     "uma frase, de propósito."),
    ("inicio", None, "Pronto",
     "Fechar a janela não desliga a proteção: o Magen fica no escudo perto do relógio. Para rever este tour, "
     "vá em Sobre."),
]

BALLOON_W = 340


def pending():
    seen = prefs.get("tourVisto")
    return not (isinstance(seen, int) and not isinstance(seen, bool) and seen >= TOUR_VERSION)


class Tour:
    def __init__(self, app):
        self.app = app
        self.root = app.root
        self.step = None
        self.shade = self.balloon = None
        self._binds = []

    @property
    def active(self):
        return self.step is not None

    # ------------------------------------------------------------ começar / andar / terminar

    def start(self):
        self.end(save=False)
        self.step = 0
        self.app.window.show(STEPS[0][0])
        self._make_windows()
        for seq, fn in (("<Configure>", lambda e: self._later()), ("<Unmap>", lambda e: self._hide()),
                        ("<Map>", lambda e: self._later())):
            self._binds.append((seq, self.root.bind(seq, fn, add="+")))
        self._show_step()

    def next(self):
        if self.step is None:
            return
        if self.step + 1 >= len(STEPS):
            self.end()
            return
        self.step += 1
        tab = STEPS[self.step][0]
        if self.app.window.tab != tab:
            self.app.window.select(tab)
        self._show_step()

    def end(self, save=True):
        was = self.step is not None
        self.step = None
        for seq, fid in self._binds:
            try:
                self.root.unbind(seq, fid)
            except tk.TclError:
                pass
        self._binds = []
        for w in (self.balloon, self.shade):
            if w is not None:
                try:
                    w.destroy()
                except tk.TclError:
                    pass
        self.shade = self.balloon = None
        if save and was:
            prefs.set("tourVisto", TOUR_VERSION)

    # ------------------------------------------------------------ janelas

    def _make_windows(self):
        shade = tk.Toplevel(self.root)
        shade.withdraw()
        shade.overrideredirect(True)
        shade.transient(self.root)
        shade.configure(bg=T.INK)
        try:
            shade.attributes("-alpha", 0.55)
            shade.attributes("-transparentcolor", HOLE)
        except tk.TclError:
            pass
        self.canvas = tk.Canvas(shade, bg=T.INK, highlightthickness=0, bd=0)
        self.canvas.pack(fill="both", expand=True)
        self.shade = shade

        balloon = tk.Toplevel(self.root)
        balloon.withdraw()
        balloon.overrideredirect(True)
        balloon.transient(shade)  # o balão pertence à sombra: fica sempre na frente dela
        balloon.configure(bg=T.INK)
        for key in ("<Return>", "<KP_Enter>", "<Right>", "<space>"):
            balloon.bind(key, lambda e: self.next())
        balloon.bind("<Escape>", lambda e: self.end())
        self.balloon = balloon
        # Se a janela do Magen estiver "sempre por cima", o tour também precisa estar, senão some atrás dela.
        try:
            if int(self.root.attributes("-topmost")):
                shade.attributes("-topmost", True)
                balloon.attributes("-topmost", True)
        except tk.TclError:
            pass

    def _later(self):
        if self.step is not None:
            self.root.after_idle(self._place)

    def _hide(self):
        for w in (self.shade, self.balloon):
            if w is not None:
                w.withdraw()

    def _show_step(self):
        """Monta o balão do passo atual e põe tudo no lugar."""
        b = self.balloon
        for w in b.winfo_children():
            w.destroy()
        _, _, title, text = STEPS[self.step]
        outer, box = T.boxed(b, fill=T.PAPER, shadow=T.SHADOW, shadow_color=T.RED, pad=16)
        outer.configure(bg=T.INK)
        outer.pack()
        # O balão fica sobre a sombra escura: os cantos da sombra dura ficam pretos, não creme.
        for child in outer.place_slaves():
            child.configure(bg=T.INK)
        inner = BALLOON_W - 32
        T.label(box, tr(title), size=15, bold=True, bg=T.PAPER, translate=False).pack(anchor="w")
        T.label(box, tr(text), size=12, color=T.DARK, bg=T.PAPER, wrap=inner, translate=False).pack(
            anchor="w", pady=(T.px(6), T.px(14)))
        foot = tk.Frame(box, bg=T.PAPER)
        foot.pack(fill="x")
        last = self.step == len(STEPS) - 1
        T.label(foot, f"{self.step + 1}/{len(STEPS)}", size=11, color=T.GRAY, bg=T.PAPER,
                translate=False).pack(side="left")
        T.BoxButton(foot, "Começar" if last else "Próximo", self.next, width=110, height=36, size=11,
                    accent=True, bg=T.PAPER).pack(side="right")
        if not last:
            T.BoxButton(foot, "Pular o tour", self.end, width=130, height=36, size=11, bg=T.PAPER).pack(
                side="right", padx=(0, T.px(8)))
        self.root.update_idletasks()
        self._place()
        b.focus_force()

    def _target_box(self, name):
        """Retângulo do alvo, em coordenadas da tela (x0, y0, x1, y1), ou None."""
        widgets = [w for w in self.app.window.spots.get(name, []) if w.winfo_exists()]
        if not widgets:
            return None
        xs0, ys0, xs1, ys1 = [], [], [], []
        for w in widgets:
            x, y = w.winfo_rootx(), w.winfo_rooty()
            xs0.append(x)
            ys0.append(y)
            xs1.append(x + w.winfo_width())
            ys1.append(y + w.winfo_height())
        m = T.px(6)
        return min(xs0) - m, min(ys0) - m, max(xs1) + m, max(ys1) + m

    def _place(self):
        if self.step is None or self.shade is None:
            return
        root = self.root
        if not root.winfo_viewable():
            self._hide()
            return
        rx, ry, rw, rh = root.winfo_rootx(), root.winfo_rooty(), root.winfo_width(), root.winfo_height()
        self.shade.geometry(f"{rw}x{rh}+{rx}+{ry}")
        c = self.canvas
        c.delete("all")
        box = self._target_box(STEPS[self.step][1]) if STEPS[self.step][1] else None
        if box:
            x0, y0, x1, y1 = box[0] - rx, box[1] - ry, box[2] - rx, box[3] - ry
            c.create_rectangle(x0, y0, x1, y1, fill=HOLE, width=0)
            c.create_rectangle(x0 - 1, y0 - 1, x1 + 1, y1 + 1, outline=T.RED, width=T.px(3))

        b = self.balloon
        b.update_idletasks()
        bw, bh = b.winfo_reqwidth(), b.winfo_reqheight()
        gap = T.px(14)
        if not box:
            x, y = rx + (rw - bw) // 2, ry + (rh - bh) // 2
        else:
            x0, y0, x1, y1 = box
            if x1 - rx < rw * 0.25:  # alvo estreito à esquerda (o trilho): balão à direita dele
                x, y = x1 + gap, (y0 + y1) // 2 - bh // 2
            elif ry + rh - y1 >= bh + gap:  # cabe embaixo
                x, y = x0, y1 + gap
            elif y0 - ry >= bh + gap:  # cabe em cima
                x, y = x0, y0 - gap - bh
            else:  # alvo grande: balão no canto de baixo, à direita, por cima do alvo
                x, y = rx + rw - bw - gap, ry + rh - bh - gap
        x = max(rx + gap, min(x, rx + rw - bw - gap))
        y = max(ry + gap, min(y, ry + rh - bh - gap))
        b.geometry(f"+{x}+{y}")
        self.shade.deiconify()
        b.deiconify()
        self.shade.lift()
        b.lift()
