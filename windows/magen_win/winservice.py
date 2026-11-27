"""Serviço do Windows ("Magen"): instalar, ligar, parar e remover.

O mesmo Magen.exe faz tudo:
    Magen.exe --service            o Windows chama assim (não rode à mão)
    Magen.exe --install-service    instalador (como administrador)
    Magen.exe --stop-service       instalador, antes de trocar os arquivos
    Magen.exe --uninstall-service  desinstalador
"""
import os
import subprocess
import sys
import time

from . import core

NAME = "Magen"
_NO_WINDOW = 0x08000000


def _sc(*args):
    p = subprocess.run(["sc.exe", *args], capture_output=True, text=True, creationflags=_NO_WINDOW)
    return p.returncode, p.stdout + p.stderr


def exe_command():
    if getattr(sys, "frozen", False):
        return f'"{sys.executable}" --service'
    # Rodando pelo código (testes no notebook): python.exe magen.py --service
    script = os.path.abspath(sys.argv[0])
    return f'"{sys.executable}" "{script}" --service'


def is_installed():
    return _sc("query", NAME)[0] == 0


def is_running():
    code, out = _sc("query", NAME)
    return code == 0 and "RUNNING" in out


def protect_folder():
    """Pasta de dados: o serviço e os administradores mudam; as outras contas só leem."""
    d = core.data_dir()
    os.makedirs(d, exist_ok=True)
    subprocess.run(["icacls", d, "/inheritance:r",
                    "/grant:r", "*S-1-5-18:(OI)(CI)F",       # SYSTEM
                    "/grant:r", "*S-1-5-32-544:(OI)(CI)F",   # Administradores
                    "/grant:r", "*S-1-5-32-545:(OI)(CI)RX"], # Usuários: só ler
                   capture_output=True, creationflags=_NO_WINDOW)


def install():
    protect_folder()
    if not os.path.exists(core.config_path()):
        core.save_config(core.load_config())
    if is_installed():
        # Pode estar rodando de outro lugar (versão antiga, ou ligado direto da pasta de montagem):
        # para antes, senão o Windows continua com o programa velho até reiniciar.
        if is_running():
            stop()
        _sc("config", NAME, "binPath=", exe_command(), "start=", "auto")
    else:
        code, out = _sc("create", NAME, "binPath=", exe_command(), "start=", "auto", "DisplayName=", "Magen")
        if code != 0:
            print(out)
            return 1
    _sc("description", NAME, "Magen: bloqueia sites adultos (DNS local). https://movemontes.github.io/magen")
    # Se cair, volta sozinho em 2 s (sem ele, o DNS aponta para um porteiro que não responde).
    _sc("failure", NAME, "reset=", "86400", "actions=", "restart/2000/restart/5000/restart/10000")
    _sc("failureflag", NAME, "1")
    _sc("start", NAME)
    for _ in range(30):
        if is_running():
            return 0
        time.sleep(0.5)
    return 0 if is_running() else 2


def stop(wait=30):
    if not is_installed():
        return 0
    _sc("stop", NAME)
    for _ in range(wait * 2):
        if not is_running():
            break
        time.sleep(0.5)
    # Mesmo que algo tenha dado errado, o DNS do Windows volta ao normal.
    from . import systemdns
    if systemdns.pointing_to_magen():
        systemdns.restore()
    return 0


def uninstall():
    stop()
    _sc("delete", NAME)
    d = core.data_dir()
    if os.path.isdir(d):
        to_recycle_bin(d)
    return 0


def to_recycle_bin(path):
    """Nunca apaga de vez: manda para a Lixeira."""
    import ctypes
    from ctypes import wintypes

    class SHFILEOPSTRUCTW(ctypes.Structure):
        _fields_ = [("hwnd", wintypes.HWND), ("wFunc", wintypes.UINT), ("pFrom", wintypes.LPCWSTR),
                    ("pTo", wintypes.LPCWSTR), ("fFlags", ctypes.c_ushort), ("fAnyOperationsAborted", wintypes.BOOL),
                    ("hNameMappings", ctypes.c_void_p), ("lpszProgressTitle", wintypes.LPCWSTR)]

    FO_DELETE, FOF_ALLOWUNDO, FOF_NOCONFIRMATION, FOF_SILENT, FOF_NOERRORUI = 3, 0x40, 0x10, 0x4, 0x400
    op = SHFILEOPSTRUCTW(wFunc=FO_DELETE, pFrom=os.path.abspath(path) + "\0",
                         fFlags=FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI)
    return ctypes.windll.shell32.SHFileOperationW(ctypes.byref(op)) == 0


def host():
    """Chamado pelo Windows com --service: liga o serviço e espera o pedido de parar."""
    import servicemanager
    import win32service
    import win32serviceutil

    from .service import Service

    class MagenService(win32serviceutil.ServiceFramework):
        _svc_name_ = NAME
        _svc_display_name_ = "Magen"

        def __init__(self, args):
            super().__init__(args)
            self.magen = Service()

        def SvcStop(self):
            self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)
            self.magen.stop_event.set()

        # Desligando o computador: também devolve o DNS (se o Magen não ligar na volta,
        # a internet continua funcionando).
        SvcShutdown = SvcStop

        def GetAcceptedControls(self):
            return super().GetAcceptedControls() | win32service.SERVICE_ACCEPT_SHUTDOWN

        def SvcDoRun(self):
            code = self.magen.run()
            if code:
                raise SystemExit(code)  # o Windows tenta de novo (sc failure)

    servicemanager.Initialize()
    servicemanager.PrepareToHostSingle(MagenService)
    servicemanager.StartServiceCtrlDispatcher()
