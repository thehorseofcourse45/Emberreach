#!/usr/bin/env python3
"""Generate the 13-image UI kit for the Melvor clone (Godot)."""
from PIL import Image, ImageDraw
import os, math

BASE = r"C:\Godot\melvor_clone_godot\assets"
UI = os.path.join(BASE, "ui")
ICONS = os.path.join(BASE, "icons")
os.makedirs(UI, exist_ok=True)
os.makedirs(ICONS, exist_ok=True)

# Palette (matches the brief's dark blue-grey panels + gold accent)
PANEL = (43, 54, 71, 255)        # #2b3647
PANEL_D = (32, 41, 55, 255)      # #202937
PANEL_L = (60, 75, 97, 255)       # lighter rim
BORDER = (20, 26, 36, 255)        # dark outline #141a24
GOLD = (232, 178, 74, 255)       # #e8b24a
GOLD_L = (255, 214, 120, 255)
FILL_G = (95, 214, 138, 255)     # green progress
TRACK = (24, 31, 42, 255)
HP_P = (196, 56, 46, 255)         # player hp red/orange
HP_E = (88, 190, 90, 255)         # enemy hp green... actually player green, enemy red
FILLER = (62, 77, 99, 255)

def rr(d, box, r, fill=None, outline=None, width=1):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)

def save(img, path):
    img.save(path)
    print("wrote", path, img.size)

# ---------- 1. ui/panel_9slice.png 48x48, 12px corners ----------
img = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
rr(d, [1, 1, 46, 46], 10, fill=PANEL, outline=BORDER, width=2)
# inner highlight on top edge, shadow on bottom
d.line([9, 2, 38, 2], fill=PANEL_L, width=1)
d.line([9, 45, 38, 45], fill=(16, 20, 28, 255), width=1)
save(img, os.path.join(UI, "panel_9slice.png"))

# ---------- 2. ui/button_9slice.png 32x32, 8px margins ----------
img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
rr(d, [1, 1, 30, 30], 6, fill=PANEL_L, outline=BORDER, width=2)
d.line([6, 2, 25, 2], fill=(86, 105, 131, 255), width=1)   # top sheen
d.line([6, 29, 25, 29], fill=(16, 20, 28, 255), width=1)  # bottom shadow
save(img, os.path.join(UI, "button_9slice.png"))

# ---------- 3. ui/progress_bg.png 16x16 tileable ----------
img = Image.new("RGBA", (16, 16), TRACK)
d = ImageDraw.Draw(img)
d.line([0, 0, 15, 0], fill=(18, 23, 31, 255))   # subtle top shadow
d.line([0, 15, 15, 15], fill=(34, 43, 56, 255)) # bottom lighten
save(img, os.path.join(UI, "progress_bg.png"))

# ---------- 4. ui/progress_fill.png 16x16 tileable ----------
img = Image.new("RGBA", (16, 16), FILL_G)
d = ImageDraw.Draw(img)
d.rectangle([0, 0, 15, 5], fill=(140, 235, 175, 255))  # top sheen band
d.rectangle([0, 12, 15, 15], fill=(70, 165, 105, 255)) # bottom shade
save(img, os.path.join(UI, "progress_fill.png"))

# ---------- 5. icons/icon.png 256x256 app icon ----------
img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
rr(d, [4, 4, 251, 251], 40, fill=(14, 19, 26, 255), outline=GOLD, width=6)
# crossed pickaxe & sword-ish glyph: simple stylized "M" sigil
d.polygon([(78, 180), (108, 76), (128, 130), (148, 76), (178, 180),
           (160, 180), (148, 130), (138, 170), (118, 170), (108, 130), (96, 180)],
          fill=GOLD)
d.line([(60, 210), (196, 210)], fill=GOLD, width=8)
save(img, os.path.join(ICONS, "icon.png"))

# ---------- 6. ui/button_hover.png 32x32 ----------
img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
rr(d, [1, 1, 30, 30], 6, fill=(74, 92, 117, 255), outline=GOLD, width=2)
d.line([6, 2, 25, 2], fill=(110, 130, 158, 255), width=1)
save(img, os.path.join(UI, "button_hover.png"))

# ---------- 7/8. ui/hp_fill_player.png + hp_fill_enemy.png 16x16 ----------
for name, col, hi, lo in [
    ("hp_fill_player.png", (95, 214, 138, 255), (150, 240, 185, 255), (60, 160, 95, 255)),
    ("hp_fill_enemy.png", (198, 60, 50, 255), (240, 110, 95, 255), (150, 38, 30, 255)),
]:
    img = Image.new("RGBA", (16, 16), col)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 15, 5], fill=hi)
    d.rectangle([0, 12, 15, 15], fill=lo)
    save(img, os.path.join(UI, name))

# ---------- 9/10. ui/tab_active.png + tab_inactive.png 64x28 ----------
def make_tab(fill, sheen):
    img = Image.new("RGBA", (64, 28), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # body: square bottom, rounded top corners — build from rects + pieslices
    d.rectangle([0, 6, 63, 27], fill=fill)                      # lower body
    d.rectangle([7, 2, 56, 7], fill=fill)                       # top middle band
    d.pieslice([1, 1, 14, 14], 180, 270, fill=fill)             # top-left corner
    d.pieslice([49, 1, 62, 14], 270, 360, fill=fill)            # top-right corner
    # outline: top + sides only (bottom stays open to merge with panel below)
    d.arc([1, 1, 14, 14], 180, 270, fill=BORDER, width=2)
    d.arc([49, 1, 62, 14], 270, 360, fill=BORDER, width=2)
    d.line([8, 1, 55, 1], fill=BORDER, width=2)                 # top
    d.line([0, 8, 0, 26], fill=BORDER, width=2)                 # left
    d.line([62, 8, 62, 26], fill=BORDER, width=2)               # right
    if sheen:
        d.line([8, 3, 55, 3], fill=PANEL_L, width=1)
    d.rectangle([2, 24, 61, 27], fill=fill)  # reinforce bottom edge outside outline
    return img

make_tab(PANEL, True).save(os.path.join(UI, "tab_active.png"))
print("wrote", os.path.join(UI, "tab_active.png"), (64, 28))
make_tab(PANEL_D, False).save(os.path.join(UI, "tab_inactive.png"))
print("wrote", os.path.join(UI, "tab_inactive.png"), (64, 28))

# ---------- 11. ui/toast.png 48x32 ----------
img = Image.new("RGBA", (48, 32), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
rr(d, [1, 1, 46, 30], 6, fill=(30, 38, 50, 235), outline=GOLD, width=2)
save(img, os.path.join(UI, "toast.png"))

# ---------- 12. ui/scrollbar.png 12x24 ----------
img = Image.new("RGBA", (12, 24), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
rr(d, [1, 1, 10, 22], 4, fill=FILLER, outline=BORDER, width=1)
d.line([4, 7, 7, 7], fill=(100, 120, 148, 255))
d.line([4, 11, 7, 11], fill=(100, 120, 148, 255))
d.line([4, 15, 7, 15], fill=(100, 120, 148, 255))
save(img, os.path.join(UI, "scrollbar.png"))

# ---------- 13. ui/logo.png 512x128 ----------
img = Image.new("RGBA", (512, 128), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
# simple emblem-left + bar logo: gold sigil block + underline stroke
rr(d, [8, 24, 88, 104], 12, fill=(14, 19, 26, 255), outline=GOLD, width=4)
d.polygon([(30, 86), (42, 42), (48, 64), (54, 42), (66, 86),
           (59, 86), (54, 62), (50, 80), (46, 80), (42, 62), (37, 86)], fill=GOLD)
d.rectangle([108, 88, 500, 94], fill=GOLD)
d.rectangle([108, 100, 380, 103], fill=(120, 140, 165, 255))
save(img, os.path.join(UI, "logo.png"))

print("done")
