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
        draw.rounded_rectangle((S, S, 31*S, 31*S), radius=5*S, fill=(40, 30, 18, 190),
                               outline=(157, 123, 69, 110), width=S)
    paint(line, ellipse, polygon)
    image = image.resize((64, 64), Image.Resampling.LANCZOS)
    image.save(OUT / (name + '.tga'))
    assert image.mode == 'RGBA' and image.getpixel((0, 0))[3] == 0

    if name in {'accept', 'objective', 'turnin', 'collect', 'location', 'entry', 'target'}:
        image = Image.new('RGBA', (32*S, 32*S))
        draw = ImageDraw.Draw(image)
        paint(line, ellipse, polygon)
        image.putdata([(255, 255, 255, 0 if pixel[:3] == (40, 30, 18) else pixel[3])
                       for pixel in image.getdata()])
        image.resize((64, 64), Image.Resampling.LANCZOS).save(OUT / ('hud-' + name + '.tga'))


icon('accept', (158, 201, 222, 255), lambda line, circle, poly: (
    line([(9, 7), (24, 7), (24, 24), (11, 24), (11, 9)]),
    line([(9, 7), (7, 9), (7, 12), (11, 12)]),
    line([(11, 24), (8, 24), (8, 27), (21, 27), (24, 24)]),
    line([(15, 12), (20, 12)], 1.7), line([(15, 16), (20, 16)], 1.7),
))
icon('objective', (204, 166, 99, 255), lambda line, circle, poly: (
    poly([(7, 5), (12, 7), (24, 21), (21, 24), (7, 10)]),
    poly([(25, 5), (25, 10), (11, 24), (8, 21), (20, 7)]),
    line([(6, 19), (13, 26)], 2.4), line([(19, 26), (26, 19)], 2.4),
    line([(5, 27), (9, 23)], 2.8), line([(23, 23), (27, 27)], 2.8),
))
icon('turnin', (232, 196, 125, 255), lambda line, circle, poly: (
    circle((6, 6, 26, 26)), line([(10, 16), (14, 20), (22, 12)], 2.5),
))
icon('party', (156, 201, 166, 255), lambda line, circle, poly: (
    circle((8, 7, 16, 15)), circle((20, 10, 26, 16), width=1.6),
    line([(5, 25), (6, 21), (9, 18), (15, 18), (18, 21), (19, 25)]),
    line([(21, 19), (25, 19), (28, 22), (28, 25)], 1.7),
))
icon('xp', (232, 196, 125, 255), lambda line, circle, poly: (
    poly([(16, 5), (19, 12), (27, 16), (19, 20), (16, 27), (13, 20), (5, 16), (13, 12)]),
    line([(24, 5), (24, 9)], 1.3), line([(22, 7), (26, 7)], 1.3),
))
icon('entry', (158, 201, 222, 255), lambda line, circle, poly: (
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

icon('collect', (196, 176, 222, 255), lambda line, circle, poly: (
    poly([(11, 5), (22, 5), (19, 11), (13, 11)]),
    circle((7, 12, 26, 28), fill=(196, 176, 222, 255), outline=None),
    line([(12, 11), (21, 11)], 2.2),
))
icon('location', (232, 196, 125, 255), lambda line, circle, poly: (
    circle((7, 3, 25, 21), fill=(232, 196, 125, 255), outline=None),
    poly([(8, 16), (16, 30), (24, 16)]),
    circle((12, 8, 20, 16), fill=(40, 30, 18, 255), outline=None),
))

icon('profession', (204, 166, 99, 255), lambda line, circle, poly: (
    poly([(6, 11), (27, 11), (23, 16), (18, 16), (18, 21), (24, 24), (24, 26), (8, 26), (8, 24), (13, 21), (13, 16), (6, 14)]),
    line([(12, 7), (22, 7)], 2),
))
icon('class', (150, 204, 156, 255), lambda line, circle, poly: (
    line([(16, 5), (26, 8), (24, 20), (16, 28), (8, 20), (6, 8), (16, 5)]),
    line([(16, 10), (16, 22)], 2), line([(11, 15), (21, 15)], 2),
))
icon('mount', (196, 176, 222, 255), lambda line, circle, poly: (
    line([(8, 26), (9, 20), (16, 15), (10, 16), (6, 13), (13, 7), (14, 4), (18, 8), (22, 9), (26, 16), (25, 26), (8, 26)]),
    circle((12, 10, 14, 12), fill=(196, 176, 222, 255), outline=None),
    line([(19, 10), (22, 15), (22, 23)], 1.4),
))
icon('gear', (158, 201, 222, 255), lambda line, circle, poly: (
    line([(11, 6), (15, 10), (17, 10), (21, 6), (27, 10), (24, 17), (21, 15), (22, 27), (10, 27), (11, 15), (8, 17), (5, 10), (11, 6)]),
    line([(16, 12), (16, 24)], 1.4),
))
icon('settings', (204, 166, 99, 255), lambda line, circle, poly: (
    line([(7, 8), (25, 8)]), line([(7, 16), (25, 16)]), line([(7, 24), (25, 24)]),
    line([(12, 5), (12, 11)], 3), line([(21, 13), (21, 19)], 3), line([(15, 21), (15, 27)], 3),
))
icon('chain', (204, 166, 99, 255), lambda line, circle, poly: (
    circle((5, 9, 18, 23)), circle((14, 9, 27, 23)), line([(12, 16), (20, 16)]),
))

corner = Image.new('RGBA', (32*S, 32*S))
ImageDraw.Draw(corner).ellipse((0, 0, 64*S-1, 64*S-1), fill='white')
corner.resize((32, 32), Image.Resampling.LANCZOS).save(OUT / 'corner.tga')
rim = Image.new('RGBA', (32*S, 32*S))
ImageDraw.Draw(rim).ellipse((0, 0, 64*S-1, 64*S-1), outline='white', width=4*S)
rim.resize((32, 32), Image.Resampling.LANCZOS).save(OUT / 'rim.tga')
sky = Image.new('RGBA', (512, 64))
draw = ImageDraw.Draw(sky)
for y in range(64):
    draw.line((0, y, 511, y), fill=(64, 79, 125, round(80*(1-y/64))))
for x, y in [(28, 7), (74, 15), (135, 5), (206, 10), (280, 4), (344, 13), (415, 6), (484, 17)]:
    draw.ellipse((x, y, x+2, y+2), fill=(194, 210, 244, 55))
sky.save(OUT / 'hud-header.tga')
print('Generated 26 RGBA textures in Media/')
