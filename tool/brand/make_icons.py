"""Build the launcher icons and in-app marks from the brand PDFs' renders.

The mark is cropped out of the full lockup: a wordmark that is legible
on a brand sheet is a grey smear at 48dp, so the launcher gets the
phone-and-arrow only, and the words stay on the welcome screen where
there is room to read them.
"""
import os, sys
from PIL import Image

SRC = sys.argv[1]
OUT = sys.argv[2]
NAVY = (12, 41, 90)


def content_bbox(im, bg, tol=18, ymax=None):
    """Tightest box around anything that is not the background."""
    w, h = im.size
    px = im.load()
    ymax = ymax or h
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(ymax):
        for x in range(w):
            r, g, b = px[x, y]
            if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > tol:
                x0 = min(x0, x); x1 = max(x1, x)
                y0 = min(y0, y); y1 = max(y1, y)
    return x0, y0, x1 + 1, y1 + 1


def keyed(im, bg):
    """Background to transparent, with the fringe left the background's
    colour: every surface this lands on is that colour, so a halo that
    matches it is invisible, and guessing at un-premultiplied edge
    colour on a gradient arrow would look worse than not guessing."""
    im = im.convert('RGB')
    w, h = im.size
    px = im.load()
    out = Image.new('RGBA', (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            d = abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2])
            op[x, y] = (r, g, b, 255 if d >= 120 else int(255 * d / 120))
    return out


def square(mark, size, fill, frac):
    """Mark centred on a square, occupying `frac` of the shorter side."""
    canvas = Image.new('RGBA', (size, size), fill)
    target = int(size * frac)
    w, h = mark.size
    scale = target / max(w, h)
    m = mark.resize((max(1, round(w * scale)), max(1, round(h * scale))),
                    Image.LANCZOS)
    canvas.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
    return canvas


blue = Image.open(os.path.join(SRC, 'render-navy.png')).convert('RGB')
white = Image.open(os.path.join(SRC, 'render-white.png')).convert('RGB')

# The lockup is mark over wordmark; crop above the gap found at y=800.
# One box for both: the two files are the same artwork on different
# grounds, and measuring the navy one directly only finds its own
# rounded corners, which are not part of the mark.
mb = content_bbox(white, (255, 255, 255), ymax=800)
print('mark bbox:', mb)

mark_dark = keyed(blue.crop(mb), NAVY)            # white phone, for navy
mark_light = keyed(white.crop(mb), (255, 255, 255))  # navy phone, for white

os.makedirs(os.path.join(OUT, 'assets/brand'), exist_ok=True)
mark_dark.resize((512, int(512 * mark_dark.height / mark_dark.width)),
                 Image.LANCZOS).save(os.path.join(OUT, 'assets/brand/mark-on-dark.png'))
mark_light.resize((512, int(512 * mark_light.height / mark_light.width)),
                  Image.LANCZOS).save(os.path.join(OUT, 'assets/brand/mark-on-light.png'))
# The full lockup, for the one place with room for words.
white.crop(content_bbox(white, (255, 255, 255))).save(
    os.path.join(OUT, 'assets/brand/lockup-light.png'))
blue.save(os.path.join(OUT, 'assets/brand/lockup-dark.png'))

RES = os.path.join(OUT, 'android/app/src/main/res')
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for name, s in DENSITIES.items():
    d = os.path.join(RES, 'mipmap-' + name)
    os.makedirs(d, exist_ok=True)
    # Legacy icon: full-bleed navy, mark at 70%.
    square(mark_dark, round(48 * s), NAVY + (255,), 0.70).convert('RGB').save(
        os.path.join(d, 'ic_launcher.png'))
    # Adaptive foreground: 108dp canvas. The fraction is set so the
    # arrow's tail — the point furthest from centre — stays inside the
    # 33dp radius Android guarantees every launcher mask will show. At
    # 0.56 it reached 37.8dp and a circular mask cut the tail off.
    square(mark_dark, round(108 * s), (0, 0, 0, 0), 0.48).save(
        os.path.join(d, 'ic_launcher_foreground.png'))
print('wrote icons for', ', '.join(DENSITIES))
