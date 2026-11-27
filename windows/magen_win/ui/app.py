"""O app do Magen (no Mac é o MagenBar): ícone perto do relógio, janela de opções e a
janela com versículo quando um site adulto é bloqueado. Roda na conta da pessoa, sem
administrador; o que muda o Magen pede permissão ("Permitir?") na hora."""
import os
import queue
import socket
import sys
import threading
import time
import tkinter as tk

from .. import core, prefs, updates
from ..i18n import is_en, tr, trf
from ..version import VERSION
from . import popups, theme as T
from .tray import Tray
from .verse import VerseAlert
from .window import MainWindow


class App:
    def __init__(self, at_login=False):
        self.at_login = at_login
        self.queue = queue.Queue()
        self.busy = False
        self.last_alert = 0.0
        self.last_seen_block = core.load_state().get("lastBlockAt")
        self._sock = self._listen()

        if core.WINDOWS:
            try:
                import ctypes
                ctypes.windll.shcore.SetProcessDpiAwareness(1)  # nítido em tela com zoom
                ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("io.github.movemontes.magen")
            except Exception:
                pass
        T.load_private_fonts()
        self.root = tk.Tk()
        self.root.withdraw()
        T.setup(self.root)
        try:
            from PIL import Image, ImageTk
            from .. import assets
            self.root.magen_icon = ImageTk.PhotoImage(Image.open(assets.icon("icone-1024.png")).resize((64, 64)))
            self.root.iconphoto(True, self.root.magen_icon)
        except Exception:
            pass
        self.alert = VerseAlert(self.root)
        self.window = MainWindow(self.root, self)
        self.tray = Tray(self)

    # ------------------------------------------------------------ uma cópia só

    def _listen(self):
        """Porta local do app: recebe "blocked" do serviço e "show" de uma segunda cópia."""
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.bind(("127.0.0.1", core.APP_PORT))
        except OSError:
            core.send_local(core.APP_PORT, "show")  # já está aberto: só mostra a janela dele
            sys.exit(0)
        threading.Thread(target=self._listen_loop, args=(s,), daemon=True).start()
        return s

    def _listen_loop(self, s):
        while True:
            try:
                data, addr = s.recvfrom(64)
            except ConnectionResetError:
                continue
            except OSError:
                return
            if addr[0] != "127.0.0.1":
                continue
            msg = data.decode(errors="replace")
            if msg == "blocked":
                self.queue.put(self.site_blocked)
            elif msg == "show":
                self.queue.put(self.show_window)

    def _pump(self):
        """Lê a fila a cada 50 ms (o ícone e a porta local nunca mexem no Tk direto)."""
        try:
            while True:
                self.queue.get_nowait()()
        except queue.Empty:
            pass
        self.root.after(50, self._pump)

    # ------------------------------------------------------------ estado

    def state(self):
        return core.load_state()

    def config(self):
        return core.load_config()

    def service_on(self):
        """O serviço reescreve o state.json a cada 30 s enquanto roda."""
        try:
            return time.time() - os.path.getmtime(core.state_path()) < 90
        except OSError:
            return False

    def service_installed(self):
        if not core.WINDOWS:
            return os.path.exists(core.config_path())
        from .. import winservice
        return winservice.is_installed()

    def dns_points_to_magen(self):
        if not core.WINDOWS:
            return False
        from .. import systemdns
        return systemdns.pointing_to_magen()

    def blocked_today(self):
        s = self.state()
        return s.get("blockedToday", 0) if s.get("todayKey") == core.today_key() else 0

    def dns_check(self, site):
        return core.dns_check(site)

    # ------------------------------------------------------------ ações

    def show_window(self, tab=None):
        self.window.show(tab)

    def run_admin(self, args, then=None):
        """Roda "Magen.exe --admin …" como administrador. O Windows pergunta "Permitir?"."""
        if not core.WINDOWS:
            from .. import admin  # teste no Mac: roda direto, sem pedir nada
            code = admin.run(list(args))
        else:
            from ..admin import elevate
            code = elevate(["--admin", *args])
        if code is None:
            return  # a pessoa clicou em Não
        if code == 3:
            popups.message(self.root, "Não deu certo", trf("%s tem nome de site adulto e não pode ser liberado.", args[-1]))
            return
        if code != 0:
            popups.message(self.root, "Não deu certo", trf("O Magen não conseguiu fazer isso (código %d).", code))
            return
        if then:
            self.root.after(1500, then)  # o serviço relê a configuração; dá um tempinho

    def confirm_unblock(self, site):
        """Liberar é difícil de propósito: nome adulto é recusado, precisa digitar uma frase,
        depois a permissão de administrador, e o site só abre 1 hora depois."""
        if core.is_obviously_adult(site):
            self.window.site_result = trf("🚫 %s tem nome de site adulto. Ele não pode ser liberado.", site)
            return False
        sentence = core.UNBLOCK_SENTENCE["en" if is_en() else "pt"]
        ok = popups.ask_sentence(
            self.root, trf("Liberar %s?", site),
            trf("Liberar é só para um site que NÃO é adulto e foi bloqueado por engano.\n\nO site só vai abrir daqui "
                "a %d minutos. Se for um momento de tentação, esse tempo é para você respirar e desistir. Dá para "
                "cancelar a qualquer hora na aba Sites.\n\nPara continuar, digite exatamente:",
                core.UNBLOCK_DELAY // 60),
            sentence, "Pedir liberação")
        if ok is False:
            self.window.site_result = tr("A frase não confere. Nada foi liberado.")
        return bool(ok)

    def turn_on(self):
        if self.busy:
            return
        self.busy = True
        self.window.build()

        def work():
            code = self._elevate_blocking(["--admin", "ligar"])
            self.queue.put(lambda: self._turned_on(code))
        threading.Thread(target=work, daemon=True).start()

    def _elevate_blocking(self, args):
        if not core.WINDOWS:
            return 0
        from ..admin import elevate
        return elevate(args)

    def _turned_on(self, code):
        self.busy = False
        self.window.show("inicio")
        if code not in (None, 0):
            popups.message(self.root, "Não deu certo", trf("O serviço do Magen não ligou (código %d).", code))
        elif code == 0 and not popups.donation_seen():
            popups.show_donation(self.root)

    def fix_internet(self):
        self.run_admin(["restaurar-dns"], self.window.build)

    def remove(self):
        sentence = core.REMOVE_SENTENCE["en" if is_en() else "pt"]
        ok = popups.ask_sentence(
            self.root, "Remover o Magen?",
            "Sem o Magen, os sites adultos voltam a abrir neste computador. Se for um momento de tentação, "
            "feche esta janela e respire.\n\nPara remover, digite exatamente:", sentence, "Remover")
        if ok is False:
            popups.message(self.root, "Nada foi removido", "A frase não confere.")
        if not ok:
            return
        uninstaller = os.path.join(os.path.dirname(sys.executable), "unins000.exe")
        if core.WINDOWS and os.path.exists(uninstaller):
            import ctypes
            # /MAGENOK: a frase já foi digitada aqui (o desinstalador pediria de novo).
            ctypes.windll.shell32.ShellExecuteW(None, "open", uninstaller, "/MAGENOK", None, 1)
            self.quit()
        else:
            popups.message(self.root, "Remover o Magen",
                           "Abra Configurações > Aplicativos > Aplicativos instalados, procure o Magen e clique em "
                           "Desinstalar.")

    def request_update(self):
        core.send_local(core.CONTROL_PORT, "update")
        popups.message(self.root, "Pedido enviado", "As listas novas chegam em 1 ou 2 minutos. (O Magen atende no "
                                                    "máximo um pedido a cada 5 minutos.)")

    def show_donation(self):
        popups.show_donation(self.root)

    def show_verse_preview(self):
        self.alert.show(heading="Exemplo", lock_seconds=min(prefs.get("segundosParaFechar", 5), 3))

    def change_language(self, lang):
        prefs.set("idioma", lang)
        self.window.build()
        self.tray.refresh()

    def site_blocked(self):
        s = self.state()
        at = s.get("lastBlockAt")
        if at and self.last_seen_block and at <= self.last_seen_block:
            return  # notícia velha
        self.last_seen_block = at
        gap = prefs.get("minutosEntreJanelas", 1) * 60
        if not prefs.get("versiculos", True) or self.alert.showing or time.time() - self.last_alert < gap:
            return
        self.last_alert = time.time()
        self.alert.show(heading="Site bloqueado", lock_seconds=prefs.get("segundosParaFechar", 5))

    # ------------------------------------------------------------ atualização

    def check_updates(self, manual=False):
        if not manual and not updates.should_check_now():
            return
        updates.mark_checked()

        def work():
            rel = updates.fetch_latest()
            self.queue.put(lambda: self._update_found(rel, manual))
        threading.Thread(target=work, daemon=True).start()

    def _update_found(self, rel, manual):
        if not rel or not updates.is_newer(rel["version"], VERSION):
            if manual:
                if rel:
                    popups.message(self.root, "Você está com a versão mais nova", trf("Magen %s.", VERSION))
                else:
                    popups.message(self.root, "Não deu para procurar agora", "Confira a internet e tente de novo mais tarde.")
            return
        if not manual and updates.skipped() == rel["version"]:
            return
        choice = popups.offer_update(self.root, rel["version"], VERSION, rel["notes"])
        if choice == "skip":
            updates.skip(rel["version"])
        elif choice == "now":
            self._install_update(rel)

    def _install_update(self, rel):
        def work():
            path = updates.download(rel["url"])
            self.queue.put(lambda: self._downloaded(path))
        threading.Thread(target=work, daemon=True).start()

    def _downloaded(self, path):
        if not path:
            popups.message(self.root, "Não deu certo", "Não consegui baixar a versão nova. Tente de novo mais tarde.")
            return
        if core.WINDOWS and updates.run_installer(path):
            self.quit()  # o instalador troca tudo e reabre o Magen
        else:
            popups.message(self.root, "Não deu certo", "O instalador não abriu.")

    # ------------------------------------------------------------ ciclo

    def quit(self):
        try:
            prefs.set("janela", self.root.geometry())
        except Exception:
            pass
        self.tray.stop()
        self.root.destroy()

    def _refresh(self):
        self.tray.refresh()
        self.root.after(15000, self._refresh)

    def snapshot_test(self, out):
        """Teste (MAGEN_TEST_SHOTS=pasta): fotografa cada aba, o versículo e a doação, e sai.
        Não clica em nada: só abre as telas por código."""
        import subprocess
        os.makedirs(out, exist_ok=True)
        steps = [("aba-" + k, lambda k=k: self.window.show(k)) for k, _ in __import__(
            "magen_win.ui.window", fromlist=["TABS"]).TABS]
        steps.append(("versiculo", lambda: self.alert.show(lock_seconds=5)))

        def shoot(name, widget):
            widget.update()
            x, y, w, h = widget.winfo_rootx(), widget.winfo_rooty(), widget.winfo_width(), widget.winfo_height()
            path = os.path.join(out, name + ".png")
            if core.WINDOWS:
                from PIL import ImageGrab
                ImageGrab.grab((x, y, x + w, y + h), all_screens=True).save(path)
            else:
                subprocess.run(["screencapture", "-x", "-R", f"{x},{y},{w},{h}", path])
            print("foto:", path, flush=True)

        def step(i=0):
            if i < len(steps):
                name, action = steps[i]
                action()
                target = self.alert.card if name == "versiculo" else self.root
                self.root.after(700, lambda: (shoot(name, target), step(i + 1)))
            else:
                self.alert.close()
                self.root.after(300, self.quit)
        self.root.after(500, step)

    def run(self):
        if os.environ.get("MAGEN_TEST_CYCLE"):
            # Teste visual: mostra cada aba por alguns segundos, depois o versículo e a doação (sem clicar em nada).
            from .window import TABS
            secs = int(os.environ["MAGEN_TEST_CYCLE"]) * 1000
            seq = [lambda k=k: self.window.show(k) for k, _ in TABS]
            seq += [lambda: self.alert.show(lock_seconds=5), lambda: (self.alert.close(), self.show_donation()), self.quit]
            for i, f in enumerate(seq):
                self.root.after(500 + i * secs, f)
            self.root.mainloop()
            return
        if os.environ.get("MAGEN_TEST_SHOTS"):
            self.snapshot_test(os.environ["MAGEN_TEST_SHOTS"])
            self.root.mainloop()
            return
        self.tray.start()
        self._pump()
        self.root.after(15000, self._refresh)
        if not self.at_login:
            self.window.show()
            if not popups.donation_seen():
                self.root.after(800, self.show_donation)
        # Procura versão nova 20 s depois de abrir e a cada 6 horas (no máximo uma vez por dia de verdade).
        self.root.after(20000, self.check_updates)

        def every_6h():
            self.check_updates()
            self.root.after(6 * 3600 * 1000, every_6h)
        self.root.after(6 * 3600 * 1000, every_6h)
        self.root.mainloop()
