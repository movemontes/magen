"""Ajustes de cada pessoa (não precisam de administrador): %APPDATA%\\Magen\\prefs.json."""
import json
import os
import threading

_lock = threading.Lock()
_cache = None


def path():
    if os.environ.get("MAGEN_PREFS"):
        return os.environ["MAGEN_PREFS"]
    base = os.environ.get("APPDATA") or os.path.expanduser("~/.magen-windows-teste")
    return os.path.join(base, "Magen", "prefs.json")


def _load():
    global _cache
    if _cache is None:
        try:
            with open(path(), encoding="utf-8") as f:
                _cache = json.load(f)
        except (OSError, ValueError):
            _cache = {}
    return _cache


def get(key, default=None):
    with _lock:
        return _load().get(key, default)


def set(key, value):  # noqa: A001 (como prefs.set no Treco)
    with _lock:
        data = _load()
        data[key] = value
        os.makedirs(os.path.dirname(path()), exist_ok=True)
        tmp = path() + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=1, ensure_ascii=False)
        os.replace(tmp, path())
