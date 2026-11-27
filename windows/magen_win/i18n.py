"""Idiomas: o app é escrito em português; tr() troca pelo inglês (data/en.json),
como no Treco e no Magen do Mac. Automático pelo idioma do Windows, com troca no menu."""
import json
import locale
import os

from . import prefs

_HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(_HERE, "data", "en.json"), encoding="utf-8") as _f:
    ENGLISH = json.load(_f)


def system_lang():
    try:
        import ctypes
        lang_id = ctypes.windll.kernel32.GetUserDefaultUILanguage()
        return "pt" if lang_id & 0x3FF == 0x16 else "en"  # 0x16 = português
    except Exception:
        loc = (locale.getlocale()[0] or os.environ.get("LANG", "pt")).lower()
        return "pt" if loc.startswith("pt") else "en"


def current():
    forced = os.environ.get("MAGEN_LANG")
    if forced in ("pt", "en"):
        return forced
    chosen = prefs.get("idioma")
    return chosen if chosen in ("pt", "en") else system_lang()


def is_en():
    return current() == "en"


def tr(pt):
    return ENGLISH.get(pt, pt) if is_en() else pt


def trf(pt, *args):
    return tr(pt) % args


def num(n):
    s = f"{int(n):,}"
    return s if is_en() else s.replace(",", ".")
