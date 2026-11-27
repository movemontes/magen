"""Ícone perto do relógio (no Mac é o ícone da barra de menus).

O pystray roda em outra linha de execução: os cliques no menu só põem a ação numa fila
que o Tk lê a cada 50 ms (nunca chamar o Tk direto daqui; senão o app fecha sozinho)."""
from PIL import Image, ImageEnhance

from .. import assets
from ..i18n import is_en, num, tr, trf


def _icon_image(on):
    img = Image.open(assets.icon("escudo-512.png")).convert("RGBA").resize((64, 64), Image.LANCZOS)
    if not on:
        # Desligado: o escudo fica cinza.
        gray = ImageEnhance.Color(img).enhance(0.0)
        img = ImageEnhance.Brightness(gray).enhance(0.9)
    return img


class Tray:
    def __init__(self, app):
        self.app = app
        self.icon = None
        self.on = None

    def start(self):
        try:
            import pystray
        except Exception:
            return False
        self.pystray = pystray
        self.icon = pystray.Icon("Magen", _icon_image(True), "Magen", self._menu())
        self.icon.run_detached()
        self.refresh()
        return True

    def _do(self, action):
        return lambda icon=None, item=None: self.app.queue.put(action)

    def _menu(self):
        P = self.pystray
        a = self.app

        def status(_):
            return tr("✅ Magen está protegendo este computador") if a.service_on() else tr("⚠️ Magen está desligado")

        def today(_):
            return trf("Bloqueios hoje: %s", num(a.blocked_today()))
        return P.Menu(
            P.MenuItem(status, None, enabled=False),
            P.MenuItem(today, None, enabled=False),
            P.Menu.SEPARATOR,
            P.MenuItem(lambda _: tr("Abrir o Magen…"), self._do(a.show_window), default=True),
            P.MenuItem(lambda _: tr("Testar ou liberar um site…"), self._do(lambda: a.show_window("sites"))),
            P.MenuItem(lambda _: tr("Atualizar as listas agora"), self._do(a.request_update)),
            P.Menu.SEPARATOR,
            P.MenuItem(lambda _: "Support Magen…" if is_en() else "Apoie o Magen (Pix)…", self._do(a.show_donation)),
            P.MenuItem(lambda _: tr("Procurar atualização…"), self._do(lambda: a.check_updates(manual=True))),
            P.MenuItem(lambda _: tr("Sobre o Magen"), self._do(lambda: a.show_window("sobre"))),
            P.MenuItem(lambda _: "Idioma / Language", P.Menu(
                P.MenuItem("Português", self._do(lambda: a.change_language("pt")), checked=lambda _: not is_en(), radio=True),
                P.MenuItem("English", self._do(lambda: a.change_language("en")), checked=lambda _: is_en(), radio=True),
            )),
            P.Menu.SEPARATOR,
            P.MenuItem(lambda _: tr("Fechar o ícone (o bloqueio continua)"), self._do(a.quit)),
        )

    def refresh(self):
        if not self.icon:
            return
        on = self.app.service_on()
        if on != self.on:
            self.on = on
            self.icon.icon = _icon_image(on)
        self.icon.title = tr("Magen: protegendo") if on else tr("Magen: desligado")
        try:
            self.icon.update_menu()
        except Exception:
            pass

    def stop(self):
        if self.icon:
            self.icon.stop()
