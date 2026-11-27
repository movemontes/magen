"""Atualização automática (como Updates no AppChrome.swift do Mac e o updater.py do Treco).

Procura a última versão no GitHub, pega o instalador "Magen-<versão>-win-setup.exe" e roda
ele em modo silencioso. O instalador para o serviço, troca os arquivos, liga de novo e
reabre o app. O Windows pede "Permitir?" uma vez.
"""
import json
import os
import re
import tempfile
import time
import urllib.request

from . import prefs
from .i18n import current
from .version import REPO, VERSION


def is_newer(a, b):
    """"1.10" > "1.9"; partes que faltam contam como 0."""
    def parts(v):
        return [int(x) if x.isdigit() else 0 for x in v.split(".")]
    x, y = parts(a), parts(b)
    n = max(len(x), len(y))
    x += [0] * (n - len(x))
    y += [0] * (n - len(y))
    return x > y


def notes_part(body, lang=None):
    """Só o trecho das notas no idioma do app (entre <!-- pt --> e <!-- /pt -->), em texto simples."""
    lang = lang or current()
    m = re.search(rf"<!-- {lang} -->(.*?)<!-- /{lang} -->", body or "", re.S)
    text = m.group(1) if m else (body or "")
    lines = [("• " + l[2:]) if l.startswith("- ") else l for l in text.replace("**", "").splitlines()]
    return "\n".join(lines).strip()


def _get(url, timeout=20, accept=None):
    headers = {"User-Agent": f"Magen/{VERSION}"}
    if accept:
        headers["Accept"] = accept
    req = urllib.request.Request(url, headers=headers)
    return urllib.request.urlopen(req, timeout=timeout)


def fetch_latest():
    """{"version", "notes", "url"} ou None."""
    try:
        with _get(f"https://api.github.com/repos/{REPO}/releases/latest", accept="application/vnd.github+json") as r:
            data = json.load(r)
        tag = data.get("tag_name", "")
        asset = next((a for a in data.get("assets", []) if a.get("name", "").endswith("-win-setup.exe")), None)
        if asset:
            return {"version": tag.lstrip("v"), "notes": notes_part(data.get("body", "")),
                    "url": asset["browser_download_url"]}
        return None  # versão sem instalador de Windows (só Mac)
    except Exception:
        pass
    # Plano B: a API do GitHub aceita 60 consultas por hora por conexão. A página pública
    # /releases/latest leva para /releases/tag/v<versão>, e o instalador tem nome fixo.
    try:
        with _get(f"https://github.com/{REPO}/releases/latest") as r:
            final = r.geturl()
        tag = final.rsplit("/releases/tag/", 1)[1].lstrip("v")
        if not re.fullmatch(r"[0-9.]+", tag):
            return None
        return {"version": tag, "notes": "",
                "url": f"https://github.com/{REPO}/releases/download/v{tag}/Magen-{tag}-win-setup.exe"}
    except Exception:
        return None


def auto_check_on():
    return prefs.get("atualizarSozinho", True)


def should_check_now():
    return auto_check_on() and time.time() - prefs.get("ultimaProcura", 0) > 20 * 3600


def mark_checked():
    prefs.set("ultimaProcura", time.time())


def skipped():
    return prefs.get("versaoPulada")


def skip(version):
    prefs.set("versaoPulada", version)


def download(url):
    """Baixa o instalador para a pasta temporária. Devolve o caminho ou None."""
    target = os.path.join(tempfile.gettempdir(), os.path.basename(url.split("?")[0]) or "Magen-setup.exe")
    try:
        with _get(url, timeout=300) as r, open(target + ".part", "wb") as f:
            while True:
                chunk = r.read(1 << 16)
                if not chunk:
                    break
                f.write(chunk)
        os.replace(target + ".part", target)
        return target if os.path.getsize(target) > 100_000 else None
    except Exception:
        return None


def run_installer(path):
    """Roda o instalador em modo silencioso (o Windows pergunta "Permitir?"). True se começou."""
    import ctypes
    r = ctypes.windll.shell32.ShellExecuteW(None, "open", path,
                                           "/SILENT /SUPPRESSMSGBOXES /NORESTART /MAGENUPDATE", None, 1)
    return r > 32
