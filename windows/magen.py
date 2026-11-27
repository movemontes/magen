"""Magen para Windows: um programa só (Magen.exe) que faz tudo.

    Magen.exe                       abre o app (janela + ícone perto do relógio)
    Magen.exe --login               abre só o ícone (início com o Windows)
    Magen.exe --service             o Windows chama assim (serviço)
    Magen.exe --install-service     instalador, como administrador
    Magen.exe --stop-service        instalador, antes de trocar os arquivos
    Magen.exe --uninstall-service   desinstalador
    Magen.exe --admin <comando>     mudanças que pedem administrador (veja magen_win/admin.py)

Para testar pelo código (no Windows ou no Mac):
    python magen.py --foreground --port 53535 --no-system-dns   serviço na tela, sem mexer no DNS
    python magen.py --admin testar exemplo.com
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def main(argv):
    if "--service" in argv:
        from magen_win import winservice
        winservice.host()
        return 0
    if "--install-service" in argv:
        from magen_win import winservice
        return winservice.install()
    if "--stop-service" in argv:
        from magen_win import winservice
        return winservice.stop()
    if "--uninstall-service" in argv:
        from magen_win import winservice
        return winservice.uninstall()
    if "--admin" in argv:
        from magen_win import admin
        return admin.run(argv[argv.index("--admin") + 1:])
    if "--foreground" in argv:
        # Serviço rodando na tela (testes). Ctrl+C para.
        from magen_win.service import Service
        port = int(argv[argv.index("--port") + 1]) if "--port" in argv else None
        svc = Service(port=port, manage_system_dns="--no-system-dns" not in argv,
                      allow_updates="--no-update" not in argv)
        import signal
        signal.signal(signal.SIGINT, lambda *_: svc.stop_event.set())
        signal.signal(signal.SIGTERM, lambda *_: svc.stop_event.set())
        return svc.run()
    from magen_win.ui.app import App
    App(at_login="--login" in argv).run()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]) or 0)
