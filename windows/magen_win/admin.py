"""Comandos que mudam o Magen (como o "magen" do Mac). Precisam de administrador:
o app chama "Magen.exe --admin <comando> [site]" e o Windows pergunta "Permitir?".

    liberar <site>     pede para liberar (só vale 1 hora depois; nome adulto é recusado)
    desfazer <site>    tira o site dos liberados, dos pendentes e dos bloqueados a mais
    bloquear <site>    bloqueia um site a mais
    antiburla sim|nao  bloqueia o "DNS seguro" dos navegadores
    restaurar-dns      devolve o DNS do Windows (se a internet parou com o Magen desligado)
    ligar              instala/liga o serviço

Sem administrador (pelo código, no terminal): status, testar <site>, atualizar.
"""
import os
import sys
from datetime import timedelta

from . import core

# Códigos de saída que o app entende
OK, ERR_ARGS, ERR_ADULT, ERR_SAVE, ERR_DOWN = 0, 1, 3, 4, 5


def _edit(change):
    cfg = core.load_config()
    change(cfg)
    try:
        core.save_config(cfg)
    except OSError:
        print("Não consegui salvar a configuração (precisa de administrador).")
        return ERR_SAVE
    core.send_local(core.CONTROL_PORT, "reload")
    print("Feito. O Magen já está usando a nova configuração.")
    return OK


def run(args):
    if not args:
        print(__doc__)
        return ERR_ARGS
    cmd, rest = args[0], args[1:]
    site = core.clean_site(rest[0]) if rest else None

    if cmd == "status":
        s = core.load_state()
        print(f"Sites na lista: {s.get('domains', 0)} · listas de {s.get('lastUpdate')}")
        print(f"Bloqueios hoje: {s.get('blockedToday', 0)} · total: {s.get('blockedTotal', 0)}")
        return OK
    if cmd == "testar":
        if not site:
            return ERR_ARGS
        r = core.dns_check(site)
        print({True: f"🚫 {site} está BLOQUEADO (ou não existe).", False: f"✅ {site} está liberado.",
               None: "O Magen não respondeu. Ele está ligado?"}[r])
        return OK if r is not None else ERR_DOWN
    if cmd == "atualizar":
        core.send_local(core.CONTROL_PORT, "update")
        return OK
    if cmd == "liberar":
        if not site:
            return ERR_ARGS
        if core.is_obviously_adult(site):
            print(f"🚫 {site} tem nome de site adulto e não pode ser liberado.")
            return ERR_ADULT
        cfg = core.load_config()
        if site in cfg["allow"]:
            return OK
        when = next((p["at"] for p in cfg["pendingAllow"] if p.get("domain") == site), None) \
            or core.iso(core.now() + timedelta(seconds=core.UNBLOCK_DELAY))

        def change(c):
            c["pendingAllow"] = [p for p in c["pendingAllow"] if p.get("domain") != site]
            c["pendingAllow"].append({"domain": site, "at": when})
            c["block"] = [b for b in c["block"] if b != site]
        return _edit(change)
    if cmd == "desfazer":
        if not site:
            return ERR_ARGS

        def change(c):
            c["allow"] = [a for a in c["allow"] if a != site]
            c["block"] = [b for b in c["block"] if b != site]
            c["pendingAllow"] = [p for p in c["pendingAllow"] if p.get("domain") != site]
        return _edit(change)
    if cmd == "bloquear":
        if not site:
            return ERR_ARGS

        def change(c):
            if site not in c["block"]:
                c["block"].append(site)
            c["allow"] = [a for a in c["allow"] if a != site]
        return _edit(change)
    if cmd == "antiburla":
        if not rest or rest[0] not in ("sim", "nao"):
            return ERR_ARGS
        return _edit(lambda c: c.__setitem__("antiBypass", rest[0] == "sim"))
    if cmd == "restaurar-dns":
        from . import systemdns
        systemdns.restore()
        return OK
    if cmd == "ligar":
        from . import winservice
        return winservice.install()
    print(__doc__)
    return ERR_ARGS


# ---------------------------------------------------------------- pedir administrador

def elevate(args, wait=True):
    """Roda este Magen como administrador (o Windows mostra "Permitir?").
    Devolve o código de saída, ou None se a pessoa clicou em Não."""
    import ctypes
    from ctypes import wintypes

    class SHELLEXECUTEINFOW(ctypes.Structure):
        _fields_ = [("cbSize", wintypes.DWORD), ("fMask", ctypes.c_ulong), ("hwnd", wintypes.HWND),
                    ("lpVerb", wintypes.LPCWSTR), ("lpFile", wintypes.LPCWSTR), ("lpParameters", wintypes.LPCWSTR),
                    ("lpDirectory", wintypes.LPCWSTR), ("nShow", ctypes.c_int), ("hInstApp", wintypes.HINSTANCE),
                    ("lpIDList", ctypes.c_void_p), ("lpClass", wintypes.LPCWSTR), ("hkeyClass", wintypes.HKEY),
                    ("dwHotKey", wintypes.DWORD), ("hIconOrMonitor", wintypes.HANDLE), ("hProcess", wintypes.HANDLE)]

    if getattr(sys, "frozen", False):
        exe, params = sys.executable, []
    else:
        exe, params = sys.executable, [os.path.abspath(sys.argv[0])]
    # Os argumentos só têm palavras fixas e sites já limpos (a-z 0-9 . - _), então aspas bastam.
    params = " ".join(f'"{p}"' for p in params + list(args))
    info = SHELLEXECUTEINFOW(cbSize=ctypes.sizeof(SHELLEXECUTEINFOW), fMask=0x40,  # NOCLOSEPROCESS
                             lpVerb="runas", lpFile=exe, lpParameters=params, nShow=0)
    if not ctypes.windll.shell32.ShellExecuteExW(ctypes.byref(info)):
        return None  # 1223 = a pessoa recusou
    if not wait:
        return OK
    ctypes.windll.kernel32.WaitForSingleObject(info.hProcess, 0xFFFFFFFF)
    code = wintypes.DWORD()
    ctypes.windll.kernel32.GetExitCodeProcess(info.hProcess, ctypes.byref(code))
    ctypes.windll.kernel32.CloseHandle(info.hProcess)
    return code.value
