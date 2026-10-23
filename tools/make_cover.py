#!/usr/bin/env python3
"""Makes assets/cover.png (630x500) and scales the screenshots in assets/screenshots/ from raw 320x180
captures of the web build. Usage: tools/make_cover.py <dir with 01-title.png 03-play.png 04-shop.png>"""
import sys
from PIL import Image
src = sys.argv[1]
names = {"01-title.png": "01-title.png", "03-play.png": "02-play.png", "04-shop.png": "03-shop.png"}
for raw, out in names.items():
    Image.open(f"{src}/{raw}").convert("RGB").resize((960, 540), Image.NEAREST).save(f"assets/screenshots/{out}")
# The cover is composed from the captures: the wall band, the title banner, the player and the Thing,
# each scaled up with nearest neighbour.
play = Image.open(f"{src}/03-play.png").convert("RGB")
title = Image.open(f"{src}/01-title.png").convert("RGB")
cover = Image.new("RGB", (630, 500), play.getpixel((150, 100)))
band = title.crop((16, 0, 32, 16)).resize((96, 96), Image.NEAREST)  # a 16x16 wall tile
for x in range(0, 630, 96):
    cover.paste(band, (x, 0))
    cover.paste(band, (x, 404))
banner = title.crop((122, 52, 198, 64)).resize((456, 72), Image.NEAREST)
cover.paste(banner, ((630 - 456) // 2, 120))
player = play.crop((100, 129, 108, 143)).resize((64, 112), Image.NEAREST)
thing = play.crop((275, 130, 285, 141)).resize((80, 88), Image.NEAREST)
cover.paste(player, (150, 292))
cover.paste(thing, (400, 304))
cover.save("assets/cover.png")
