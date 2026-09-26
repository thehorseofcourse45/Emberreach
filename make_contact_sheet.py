#!/usr/bin/env python3
"""Contact sheet for the UI kit PNGs — labels beside, not overlapping."""
from PIL import Image, ImageDraw
import os

BASE = r"C:\Godot\melvor_clone_godot\assets"
files = ["ui/panel_9slice.png","ui/button_9slice.png","ui/button_hover.png",
         "ui/progress_bg.png","ui/progress_fill.png","ui/hp_fill_player.png",
         "ui/hp_fill_enemy.png","ui/tab_active.png","ui/tab_inactive.png",
         "ui/toast.png","ui/scrollbar.png","ui/logo.png","icons/icon.png"]
rows = []
maxh = 0
for f in files:
    im = Image.open(os.path.join(BASE, f))
    scale = 1 if im.height >= 64 else (6 if im.height <= 16 else 3)
    s = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    rows.append((f, s))
    maxh = max(maxh, s.height)

W = 620
H = sum(max(s.height + 20, 44) for _, s in rows) + 20
sheet = Image.new("RGBA", (W, H), (14, 19, 26, 255))
d = ImageDraw.Draw(sheet)
y = 10
for f, s in rows:
    rh = max(s.height, 32)
    d.text((16, y + rh // 2 - 6), f, fill=(200, 210, 225))
    # checker pattern for alpha visibility
    cx0 = 260
    for i in range(s.width):
        for j in range(s.height):
            if (i // 8 + j // 8) % 2 == 0:
                d.point((cx0 + i, y + j), fill=(70, 70, 80))
    sheet.paste(s, (cx0, y), s)
    y += max(s.height + 20, 44)
sheet.save(r"C:\Godot\melvor_clone_godot\ui_kit_contact_sheet.png")
print("ok", sheet.size)
