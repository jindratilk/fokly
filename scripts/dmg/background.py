"""Draws the DMG window background (640×400 pt, @1x and @2x): the website's dusk skyline,
an arrow from Fokly to Applications and one line of instructions. Icons sit at (180, 170)
and (460, 170); scripts/dmg/settings.py places them there.

Usage: python3 scripts/dmg/background.py <out_dir>   → background.png, background@2x.png
"""
import os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
W, H = 640, 400
ICON_Y, LEFT_X, RIGHT_X = 170, 180, 460
FONT = "/System/Library/Fonts/SFNS.ttf"


def font(px, weight):
    f = ImageFont.truetype(FONT, px)
    f.set_variation_by_axes([100, 28 if px < 40 else 40, 400, weight])
    return f


def draw(scale):
    s = lambda v: round(v * scale)
    photo = Image.open(os.path.join(ROOT, "site/assets/hero.jpg")).convert("RGB")
    # The skyline sits low so both icons and their labels are on open sky.
    img = photo.crop((200, 0, 2200, 1250)).resize((s(W), s(H)), Image.LANCZOS)

    # Sink the skyline into dusk under the instructions so the line reads; the sky stays as shot.
    shade = Image.new("L", (1, s(H)))
    for y in range(s(H)):
        t = max(0.0, (y / s(H) - 0.6) / 0.4)
        shade.putpixel((0, y), int(200 * t ** 1.6))
    img = Image.composite(Image.new("RGB", img.size, (10, 8, 14)), img, shade.resize(img.size))

    # Arrow: a rounded shaft and chevron, white, with a soft shadow so it lifts off the sky.
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, x1, y, w, head = s(LEFT_X + 92), s(RIGHT_X - 92), s(ICON_Y), s(4.5), s(15)
    d.line([(x0, y), (x1, y)], fill=(255, 255, 255, 235), width=w)
    d.line([(x1 - head, y - head), (x1, y), (x1 - head, y + head)], fill=(255, 255, 255, 235), width=w, joint="curve")
    for cx, cy in [(x0, y), (x1, y), (x1 - head, y - head), (x1 - head, y + head)]:
        d.ellipse([cx - w / 2, cy - w / 2, cx + w / 2, cy + w / 2], fill=(255, 255, 255, 235))
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow.putalpha(layer.getchannel("A").point(lambda a: a * 0.35).filter(ImageFilter.GaussianBlur(s(6))))
    img = Image.alpha_composite(img.convert("RGBA"), shadow)
    img = Image.alpha_composite(img, layer)

    # "Drag Fokly to Applications to install", with Fokly in semibold.
    d = ImageDraw.Draw(img)
    parts = [("Drag ", font(s(14), 400)), ("Fokly", font(s(14), 620)), (" to Applications to install", font(s(14), 400))]
    width = sum(d.textlength(t, font=f) for t, f in parts)
    x, base = (s(W) - width) / 2, s(H - 38)
    for t, f in parts:
        d.text((x, base), t, font=f, fill=(255, 255, 255, 225), anchor="ls")
        x += d.textlength(t, font=f)
    return img.convert("RGB")


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    draw(1).save(os.path.join(out, "background.png"))
    draw(2).save(os.path.join(out, "background@2x.png"))
