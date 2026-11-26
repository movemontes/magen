# Ícone do Magen: broquel (escudo redondo) com "M", no estilo do ícone do Pauta:
# quadrado creme, contorno preto grosso, sombra dura, traço de desenho animado.
# Uso: python3 desenhar_icone.py <pasta de saída> <Archivo-Variable.ttf>
# Gera icone-1024.png (com o quadrado) e escudo-512.png (só o escudo, fundo transparente).
# Precisa do Pillow (pip install pillow). Os PNGs prontos ficam no repositório.
import sys, math
from PIL import Image, ImageDraw, ImageFont
out, archivo = sys.argv[1], sys.argv[2]

def draw(with_tile):
    K = 4                      # desenha 4x maior e reduz (bordas lisas)
    N = 1024 * K
    INK=(10,10,10,255); CREAM=(253,249,238,255); RED=(225,0,0,255); DARKRED=(160,0,0,255); WHITE=(255,255,255,255)
    img = Image.new("RGBA", (N, N), (0,0,0,0)); d = ImageDraw.Draw(img)
    def s(v): return int(v * K)
    def circle(cx, cy, r, fill=None, outline=None, width=0):
        d.ellipse((s(cx-r), s(cy-r), s(cx+r), s(cy+r)), fill=fill, outline=outline, width=s(width) if width else 0)

    # Tile: rounded square, black outline, hard shadow (same grid as Pauta: 824 body in 1024)
    x0, y0, x1, y1, rad, sh = 100, 100, 880, 880, 170, 46
    if with_tile:
        d.rounded_rectangle((s(x0+sh), s(y0+sh), s(x1+sh), s(y1+sh)), radius=s(rad), fill=INK)
        d.rounded_rectangle((s(x0), s(y0), s(x1), s(y1)), radius=s(rad), fill=INK)
        d.rounded_rectangle((s(x0+30), s(y0+30), s(x1-30), s(y1-30)), radius=s(rad-30), fill=CREAM)

    cx, cy, R = 490, 490, 255
    # Shield: hard shadow, black outline, red body, inner rim
    circle(cx+22, cy+22, R+16, fill=INK)
    circle(cx, cy, R+16, fill=INK)
    circle(cx, cy, R-10, fill=RED)
    circle(cx, cy, R-56, outline=INK, width=13)
    # Rivets on the rim
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        rx, ry = cx + math.cos(a) * (R - 31), cy + math.sin(a) * (R - 31)
        circle(rx, ry, 13, fill=CREAM, outline=INK, width=6)
    # Shine (cartoon highlight)
    d.arc((s(cx-R+52), s(cy-R+52), s(cx+R-52), s(cy+R-52)), 200, 250, fill=(255,255,255,200), width=s(16))

    if True:
        # Boss in the middle with the M
        circle(cx, cy, 104, fill=INK)
        circle(cx, cy, 90, fill=CREAM)
        f = ImageFont.truetype(archivo, s(112)); f.set_variation_by_axes([900, 125])
        bb = d.textbbox((0, 0), "M", font=f)
        tw, th = bb[2]-bb[0], bb[3]-bb[1]
        d.text((s(cx) - tw/2 - bb[0], s(cy) - th/2 - bb[1]), "M", font=f, fill=RED)
    else:
        # Face, like Pauta's eighth note: big white eyes, brows, smile
        for ex in (cx-66, cx+66):
            d.ellipse((s(ex-46), s(cy-80), s(ex+46), s(cy+36)), fill=WHITE, outline=INK, width=s(12))
            d.ellipse((s(ex-19), s(cy-48), s(ex+23), s(cy+14)), fill=INK)
            d.arc((s(ex-42), s(cy-146), s(ex+42), s(cy-84)), 200, 340, fill=INK, width=s(13))
        d.arc((s(cx-60), s(cy+36), s(cx+60), s(cy+130)), 20, 160, fill=INK, width=s(14))

    img = img.resize((1024, 1024), Image.LANCZOS)
    if with_tile:
        img.save(f"{out}/icone-1024.png")
    else:
        # Only the shield (with its shadow), cropped square, 512 px.
        box = (490 - 285, 490 - 285, 490 + 285 + 24, 490 + 285 + 24)
        img.crop(box).resize((512, 512), Image.LANCZOS).save(f"{out}/escudo-512.png")

draw(True)
draw(False)
print("ok")
