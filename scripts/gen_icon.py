#!/usr/bin/env python3
"""Generate TTS Bandmate app icon using reference silhouettes — black & gold."""
from PIL import Image, ImageDraw
import os

SIZE   = 1024
QUAD   = SIZE // 2          # 512
GOLD   = (212, 175, 55)
BLACK  = (18, 18, 18)

BASE   = '/Users/em/Documents/github/TTS-App'
SHOTS  = os.path.join(BASE, '.claude', 'screenshots')


def gold_silhouette(path):
    """Load a dark-on-white silhouette PNG → gold-on-transparent."""
    gray = Image.open(path).convert('L')
    # dark pixels → opaque, light pixels → transparent
    mask = gray.point(lambda p: 255 if p < 160 else 0)
    gold = Image.new('RGBA', gray.size, GOLD + (255,))
    gold.putalpha(mask)
    return gold


def fit(img, max_w, max_h):
    """Scale image to fit within max_w × max_h, preserving aspect ratio."""
    ar = img.width / img.height
    if ar > max_w / max_h:
        w, h = max_w, int(max_w / ar)
    else:
        h, w = max_h, int(max_h * ar)
    return img.resize((w, h), Image.LANCZOS)


def stamp(canvas, img, cx, cy):
    """Paste img centred at (cx, cy) on canvas."""
    canvas.paste(img, (cx - img.width // 2, cy - img.height // 2), img)


# ── Canvas ────────────────────────────────────────────────────────────
canvas = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
bg = ImageDraw.Draw(canvas)
bg.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=200, fill=BLACK)

# Each instrument fills its quadrant and its inner corner touches the centre.
OUTER_PAD = 48          # minimum gap from outer edges
MAX = QUAD - OUTER_PAD  # max dimension per instrument (464 px)

# ── 1. Music note  — top-left  (bottom-right corner → centre) ─────────
note = gold_silhouette(os.path.join(SHOTS, 'image.png'))
note = fit(note, MAX, MAX)
canvas.paste(note, (QUAD - note.width, QUAD - note.height), note)

# ── 2. Microphone  — top-right  (bottom-left corner → centre) ─────────
mic = gold_silhouette(os.path.join(SHOTS, 'mic.png'))
mic = fit(mic, MAX, MAX)
canvas.paste(mic, (QUAD, QUAD - mic.height), mic)

# ── 3. Guitar  — bottom-left  (top-right corner → centre) ────────────
guitar = gold_silhouette(os.path.join(SHOTS, 'guitar.png'))
guitar = guitar.rotate(90, expand=True)   # 90° CCW → neck points up
guitar = fit(guitar, MAX, MAX)
canvas.paste(guitar, (QUAD - guitar.width, QUAD), guitar)

# ── 4. Trombone  — bottom-right  (top-left corner → centre) ──────────
trombone = gold_silhouette(os.path.join(SHOTS, 'trombone.png'))
trombone = fit(trombone, MAX, MAX)
canvas.paste(trombone, (QUAD, QUAD), trombone)

# ── Gold border ring ──────────────────────────────────────────────────
ring = ImageDraw.Draw(canvas)
ring.ellipse([20, 20, SIZE - 20, SIZE - 20], outline=GOLD + (255,), width=8)

# ── Subtle divider lines ──────────────────────────────────────────────
ov = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
od = ImageDraw.Draw(ov)
od.line([QUAD, 60, QUAD, SIZE - 60], fill=GOLD + (50,), width=2)
od.line([60, QUAD, SIZE - 60, QUAD], fill=GOLD + (50,), width=2)
canvas = Image.alpha_composite(canvas, ov)

# ── Save ──────────────────────────────────────────────────────────────
out = os.path.join(BASE, 'assets', 'images', 'app_icon.png')
canvas.save(out)
print(f"Saved: {out}")
