#!/usr/bin/env python3
"""Render a simple on-brand assembly preview for the printable prototype."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent / "enclosure-preview.png"
image = Image.new("RGB", (1200, 900), "#201e1d")
draw = ImageDraw.Draw(image)

try:
    regular = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", 27)
    bold = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", 34)
except OSError:
    regular = bold = ImageFont.load_default()

# Stand and rear depth.
draw.polygon([(314, 688), (875, 688), (972, 748), (235, 748)], fill="#2d2b2b", outline="#f3f2f2", width=4)
draw.polygon([(334, 640), (390, 640), (430, 704), (294, 704)], fill="#f3f2f2", outline="#201e1d", width=4)
draw.polygon([(796, 640), (852, 640), (910, 704), (774, 704)], fill="#f3f2f2", outline="#201e1d", width=4)
draw.polygon([(270, 176), (890, 176), (955, 222), (335, 222)], fill="#aaa5a2", outline="#f3f2f2", width=4)
draw.polygon([(890, 176), (955, 222), (955, 648), (890, 604)], fill="#8b8581", outline="#f3f2f2", width=4)

# Front shell and screen aperture, proportional to 100 × 72 and 74 × 50 mm.
draw.rectangle((270, 176, 890, 622), fill="#f3f2f2", outline="#201e1d", width=7)
draw.rectangle((350, 244, 810, 554), fill="#201e1d", outline="#2d2b2b", width=5)
draw.rectangle((372, 266, 788, 532), outline="#66615e", width=3)

draw.text((396, 292), "MOMO LABZ", font=bold, fill="#f3f2f2")
draw.text((396, 340), "3 AGENTS WORKING", font=regular, fill="#aaa5a2")
draw.rectangle((396, 405, 418, 475), fill="#E25C48")
draw.text((444, 411), "CLAUDE NEEDS YOU", font=bold, fill="#E25C48")
draw.text((444, 459), "APPROVAL WAITING", font=regular, fill="#f3f2f2")

draw.text((62, 72), "MOMO LABZ / AGENT DESK", font=bold, fill="#f3f2f2")
draw.text((62, 116), "100 × 72 × 28 MM PIXEL PROTOTYPE", font=regular, fill="#aaa5a2")
draw.text((62, 810), "BODY + VENTED BACK + STAND / PLA OR PETG / NO SUPPORTS", font=regular, fill="#aaa5a2")

image.save(OUT)
print(OUT)
