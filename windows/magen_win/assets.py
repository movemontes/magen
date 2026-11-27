"""Onde ficam imagens e fontes: dentro do Magen.exe, ou no projeto quando roda pelo código."""
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.dirname(os.path.dirname(_HERE))


def _base():
    return os.path.join(sys._MEIPASS, "assets") if getattr(sys, "frozen", False) else None


def icon(name):
    """escudo-512.png (logo) ou icone-1024.png (ícone do app), de Resources/icone."""
    b = _base()
    return os.path.join(b, name) if b else os.path.join(_REPO, "Resources", "icone", name)


ARCHIVO = "Archivo-Variable.ttf"
CLASH = ("ClashGrotesk-Medium.otf", "ClashGrotesk-Semibold.otf")


def font(name):
    """Archivo vem de Resources/fonts (licença livre). A Clash Grotesk não vai no GitHub
    (licença ITF FFL): fica em windows/fontes-privadas/ e só vai dentro do .exe."""
    b = _base()
    if b:
        return os.path.join(b, "fonts", name)
    for d in (os.path.join(_REPO, "Resources", "fonts"), os.path.join(_REPO, "windows", "fontes-privadas")):
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    return os.path.join(_REPO, "Resources", "fonts", name)
