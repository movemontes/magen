"""Aponta o DNS de todas as conexões do Windows (Wi-Fi, cabo, VPN...) para o Magen
e devolve o que havia antes quando o Magen para. Só roda como administrador (o serviço).

Lê o que está configurado direto no registro (rápido) e só chama o netsh quando
precisa mudar. Como no Mac, confere a cada 30 s e desfaz uma troca manual.
"""
import json
import os
import subprocess

from . import core

V4, V6 = "127.0.0.1", "::1"
_NO_WINDOW = 0x08000000  # CREATE_NO_WINDOW: não pisca janela preta


def _run(args, timeout=30):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                           creationflags=_NO_WINDOW if core.WINDOWS else 0)
        return p.returncode, p.stdout
    except (OSError, subprocess.SubprocessError):
        return -1, ""


def adapters(only_up=True):
    """Conexões (só as ligadas, ou todas): [{"guid", "index", "name"}]."""
    where = "Where-Object { $_.Status -eq 'Up' } | " if only_up else ""
    script = ("Get-NetAdapter | " + where +
              "Select-Object @{n='guid';e={$_.InterfaceGuid}}, @{n='index';e={$_.ifIndex}}, @{n='name';e={$_.Name}} | "
              "ConvertTo-Json -Compress")
    code, out = _run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script])
    if code != 0 or not out.strip():
        return []
    try:
        data = json.loads(out)
    except ValueError:
        return []
    if isinstance(data, dict):
        data = [data]
    return [{"guid": str(a["guid"]).lower(), "index": int(a["index"]), "name": a["name"]} for a in data]


def _static_servers(guid, v6=False):
    """DNS fixo da conexão (lista vazia = automático, vindo do roteador)."""
    import winreg
    key = (r"SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces" if v6 else
           r"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces") + "\\" + guid
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, key) as k:
            value, _ = winreg.QueryValueEx(k, "NameServer")
    except OSError:
        return []
    return [x for x in str(value).replace(",", " ").split() if x]


def _set(index, family, servers):
    """servers vazio = volta para automático."""
    if not servers:
        _run(["netsh", "interface", family, "set", "dnsservers", f"name={index}", "source=dhcp"])
        return
    _run(["netsh", "interface", family, "set", "dnsservers", f"name={index}", "static", servers[0],
          "primary", "validate=no"])
    for i, extra in enumerate(servers[1:], start=2):
        _run(["netsh", "interface", family, "add", "dnsservers", f"name={index}", extra, f"index={i}",
              "validate=no"])


def _load_saved():
    try:
        with open(core.saved_dns_path(), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _save(saved):
    core.write_json(core.saved_dns_path(), saved)


def enforce():
    """Garante que todas as conexões usam o Magen. Devolve os nomes das que mudaram."""
    saved = _load_saved()
    changed = []
    for a in adapters():
        v4, v6 = _static_servers(a["guid"]), _static_servers(a["guid"], v6=True)
        if v4 == [V4] and v6 == [V6]:
            continue
        if a["guid"] not in saved:  # guarda só o que havia antes do Magen
            saved[a["guid"]] = {"v4": v4, "v6": v6, "name": a["name"]}
            _save(saved)
        if v4 != [V4]:
            _set(a["index"], "ipv4", [V4])
        if v6 != [V6]:
            _set(a["index"], "ipv6", [V6])
        changed.append(a["name"])
    if changed:
        _run(["ipconfig", "/flushdns"])
    return changed


def restore():
    """Devolve o DNS de antes do Magen (ou automático) em toda conexão que aponta para ele."""
    saved = _load_saved()
    for a in adapters(only_up=False):  # também as desligadas agora (Wi-Fi fora, cabo solto)
        old = saved.get(a["guid"], {"v4": [], "v6": []})
        if V4 in _static_servers(a["guid"]):
            _set(a["index"], "ipv4", [s for s in old.get("v4", []) if s != V4])
        if V6 in _static_servers(a["guid"], v6=True):
            _set(a["index"], "ipv6", [s for s in old.get("v6", []) if s != V6])
    try:
        os.remove(core.saved_dns_path())
    except OSError:
        pass
    _run(["ipconfig", "/flushdns"])


def pointing_to_magen():
    """Para o app: alguma conexão ligada usa o Magen? (lê o registro, não precisa de admin)."""
    try:
        return any(V4 in _static_servers(a["guid"]) for a in adapters())
    except Exception:
        return False
