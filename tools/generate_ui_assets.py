#!/usr/bin/env python3
"""Draw the addon's small UI symbols and reusable round corner as RGBA TGA."""
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[1] / 'Media'
OUT.mkdir(exist_ok=True)
S = 8


def icon(name, color, paint):
    image = Image.new('RGBA', (32*S, 32*S))
    draw = ImageDraw.Draw(image)

    def line(points, width=2, fill=color):
        draw.line([(round(x*S), round(y*S)) for x, y in points], fill=fill,
                  width=round(width*S), joint='curve')

    def ellipse(box, fill=None, outline=color, width=2):
        draw.ellipse(tuple(round(n*S) for n in box), fill=fill, outline=outline, width=round(width*S))

    def polygon(points, fill=color):
        draw.polygon([(round(x*S), round(y*S)) for x, y in points], fill=fill)

    if name != 'compass':
        ellipse((1, 1, 31, 31), fill=(32, 42, 57, 230), outline=None)
    paint(line, ellipse, polygon)
    image = image.resize((64, 64), Image.Resampling.LANCZOS)
    image.save(OUT / (name + '.tga'))
    assert image.mode == 'RGBA' and image.getpixel((0, 0))[3] == 0


icon('accept', (149, 211, 255, 255), lambda line, circle, poly: (
    line([(9, 7), (24, 7), (24, 24), (11, 24), (11, 9)]),
    line([(9, 7), (7, 9), (7, 12), (11, 12)]),
    line([(11, 24), (8, 24), (8, 27), (21, 27), (24, 24)]),
    line([(15, 12), (20, 12)], 1.7), line([(15, 16), (20, 16)], 1.7),
))
icon('objective', (246, 158, 190, 255), lambda line, circle, poly: (
    poly([(7, 5), (12, 7), (24, 21), (21, 24), (7, 10)]),
    poly([(25, 5), (25, 10), (11, 24), (8, 21), (20, 7)]),
    line([(6, 19), (13, 26)], 2.4), line([(19, 26), (26, 19)], 2.4),
    line([(5, 27), (9, 23)], 2.8), line([(23, 23), (27, 27)], 2.8),
))
icon('turnin', (255, 211, 123, 255), lambda line, circle, poly: (
    circle((6, 6, 26, 26)), line([(10, 16), (14, 20), (22, 12)], 2.5),
))
icon('party', (175, 202, 237, 255), lambda line, circle, poly: (
    circle((8, 7, 16, 15)), circle((20, 10, 26, 16), width=1.6),
    line([(5, 25), (6, 21), (9, 18), (15, 18), (18, 21), (19, 25)]),
    line([(21, 19), (25, 19), (28, 22), (28, 25)], 1.7),
))
icon('xp', (255, 211, 123, 255), lambda line, circle, poly: (
    poly([(16, 5), (19, 12), (27, 16), (19, 20), (16, 27), (13, 20), (5, 16), (13, 12)]),
    line([(24, 5), (24, 9)], 1.3), line([(22, 7), (26, 7)], 1.3),
))
icon('entry', (171, 208, 244, 255), lambda line, circle, poly: (
    line([(8, 26), (8, 10), (11, 6), (19, 6), (22, 10), (22, 14)]),
    line([(13, 21), (27, 21)], 2.2), line([(23, 17), (27, 21), (23, 25)], 2.2),
    line([(5, 27), (14, 27)], 2),
))
icon('compass', (255, 255, 255, 255), lambda line, circle, poly: (
    circle((3, 3, 29, 29), width=1.4),
    poly([(22, 8), (18, 18), (8, 24), (13, 13)]),
    line([(3, 16), (6, 16)], 1.5), line([(26, 16), (29, 16)], 1.5),
))
icon('target', (255, 255, 255, 255), lambda line, circle, poly: (
    circle((7, 7, 25, 25)), circle((14, 14, 18, 18), fill=(255, 255, 255, 255), outline=None),
    line([(16, 3), (16, 9)]), line([(16, 23), (16, 29)]),
    line([(3, 16), (9, 16)]), line([(23, 16), (29, 16)]),
))

icon('collect', (203, 188, 235, 255), lambda line, circle, poly: (
    poly([(11, 5), (22, 5), (19, 11), (13, 11)]),
    circle((7, 12, 26, 28), fill=(203, 188, 235, 255), outline=None),
    line([(12, 11), (21, 11)], 2.2),
))
icon('location', (187, 203, 226, 255), lambda line, circle, poly: (
    circle((7, 3, 25, 21), fill=(187, 203, 226, 255), outline=None),
    poly([(8, 16), (16, 30), (24, 16)]),
    circle((12, 8, 20, 16), fill=(32, 42, 57, 255), outline=None),
))

corner = Image.new('RGBA', (32*S, 32*S))
ImageDraw.Draw(corner).ellipse((0, 0, 64*S-1, 64*S-1), fill='white')
corner.resize((32, 32), Image.Resampling.LANCZOS).save(OUT / 'corner.tga')
print('Generated 11 RGBA textures in Media/')
