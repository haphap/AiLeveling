#!/usr/bin/env python3
"""Draw the addon's small UI symbols and reusable round corner as RGBA TGA."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

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

    draw.rounded_rectangle((S, S, 31*S, 31*S), radius=5*S, fill=(40, 30, 18, 190),
                           outline=(157, 123, 69, 110), width=S)
    paint(line, ellipse, polygon)
    image = image.resize((64, 64), Image.Resampling.LANCZOS)
    image.save(OUT / (name + '.tga'))
    assert image.mode == 'RGBA' and image.getpixel((0, 0))[3] == 0

# Quest glyphs share one transparent, bevelled silhouette at every size. Points
# are in a 32-unit square; outlines are grown from the finished alpha mask so
# internal seams never acquire a second border.
def glyph(name, colors, paint):
    size = 32 * S
    face = Image.new('RGBA', (size, size))
    brush = ImageDraw.Draw(face)
    base, shade, light = colors.split()
    def polygon(points, ink=base):
        brush.polygon([(round(x*S), round(y*S)) for x, y in points], fill=ink)
    def oval(box, ink=base):
        brush.ellipse(tuple(round(n*S) for n in box), fill=ink)
    def stroke(points, width, ink=base):
        brush.line([(round(x*S), round(y*S)) for x, y in points], fill=ink,
                   width=round(width*S), joint='curve')
    paint(polygon, oval, stroke, base, shade, light)
    alpha = face.getchannel('A')
    outline = alpha.filter(ImageFilter.MaxFilter(2*S+1))
    result = Image.new('RGBA', face.size, '#151523')
    result.putalpha(outline)
    result.alpha_composite(face)
    result.resize((64, 64), Image.Resampling.LANCZOS).save(OUT / (name + '.tga'))


gold = '#FFD165 #C87D38 #FFF2BA'
jade = '#74E4A8 #359772 #DEFFE2'
steel = '#AEDFFF #6795CA #F3F9FF'
violet = '#C19AFF #8364C7 #F3DFFF'
water = '#73DAE4 #3991AD #DCFFFF'
amber = '#F3AB72 #B66548 #FFDEAF'
silver = '#CED3DD #858A9F #F6F7FF'

def exclamation(polygon, oval, line, base, shade, light):
    polygon([(10,3),(22,3),(19,19),(16,22),(13,19)])
    polygon([(18,5),(22,3),(19,19),(16,22)],shade)
    line([(12,5),(17,5)],1.5,light)
    polygon([(16,23),(21,27),(16,31),(11,27)])
    line([(13,27),(16,25)],1,light)

def question(polygon, oval, line, base, shade, light):
    polygon([(4,10),(7,5),(12,2),(21,2),(26,5),(28,10),(27,15),(23,19),
       (18,21),(18,23),(12,23),(12,18),(15,15),(20,12),(20,9),(18,7),(13,7),(10,11)])
    line([(6,9),(10,5),(14,4),(20,4)],1.5,light)
    line([(25,13),(23,16),(16,20)],1.5,shade)
    polygon([(15,24),(20,27.5),(15,31),(10,27.5)])

def sword(polygon, oval, line, base, shade, light):
    polygon([(11,17),(22,5),(30,2),(27,11),(16,22)])
    polygon([(13,19),(29,3),(27,11),(16,22)],shade)
    line([(14,16),(23,6),(28,4)],1.3,light)
    polygon([(10,19),(14,23),(7,30),(2,26)],'#BD8150')
    polygon([(5,14),(9,14),(20,24),(20,28),(16,27),(6,18)],'#F1C076')
    line([(7,15),(17,24)],1.3,'#FFE3A9')
    polygon([(2,24),(8,29),(6,31),(1,27)],'#F1C076')

def sack(polygon, oval, line, base, shade, light):
    polygon([(8,3),(14,5),(17,2),(23,4),(19,11),(12,11)])
    polygon([(12,11),(20,11),(25,16),(28,22),(27,26),(23,29),(9,29),(5,27),(4,22),(7,16)])
    polygon([(23,15),(28,22),(27,26),(23,29),(9,29),(7,27),(20,26),(24,22)],shade)
    line([(8,21),(10,17),(13,14)],1.7,light)
    line([(10,10),(21,10)],2.7,'#F2D49B')

def speech(polygon, oval, line, base, shade, light):
    polygon([(3,7),(7,4),(25,4),(29,8),(29,19),(25,23),(16,23),(7,30),(8,23),(3,20)])
    polygon([(28,9),(29,9),(29,19),(25,23),(16,23),(7,30),(14,21),(24,21),(27,18)],shade)
    line([(6,9),(8,7),(19,7)],1.4,light)
    for x in (8,15,22): oval((x,12,x+3,15),'#26566A')

def hand(polygon, oval, line, base, shade, light):
    polygon([(4,16),(7,14),(12,18),(12,5),(13,2),(16,2),(17,5),(17,11),
       (20,10),(22,12),(24,12),(26,14),(29,15),(28,23),(24,29),(13,29),(9,24)])
    polygon([(27,17),(29,15),(28,23),(24,29),(13,29),(12,26),(22,26),(25,22)],shade)
    line([(14,5),(14,14)],1.4,light)

def bearing(polygon, oval, line, base, shade, light):
    polygon([(16,2),(29,28),(16,22),(3,28)])
    polygon([(16,2),(16,22),(29,28)],shade)
    line([(4,26),(16,3)],1,light)

glyph('bearing', '#FDFDFD #ADADAD #FFFFFF', bearing)

def lightning(polygon, oval, line, base, shade, light):
    polygon([(16,2),(27,2),(20,12),(28,12),(9,30),(13,18),(5,18)])
    polygon([(25,13),(9,30),(16,16)],shade)
    line([(9,15),(17,5),(23,5)],1.6,light)

def pin(polygon, oval, line, base, shade, light):
    oval((5,2,27,23))
    polygon([(5.8,16),(26.2,16),(23,22),(16,31),(9,22)])
    polygon([(25,13),(26.2,16),(23,22),(16,31),(18,23)],shade)
    oval((11,7,21,17),'#254B64')
    line([(8,11),(9,8),(12,5),(16,4)],1.2,light)

def crosshair(polygon, oval, line, base, shade, light):
    for a in (0,90,180,270):
        pts = [(5,13),(5,8),(9,4),(14,4),(14,8),(11,8),(9,10),(9,13)]
        for _ in range(a//90): pts=[(32-y,x) for x,y in pts]
        polygon(pts)
    polygon([(16,10),(22,16),(16,22),(10,16)],light)

def check(polygon, oval, line, base, shade, light):
    polygon([(2,15),(6,11),(13,18),(26,4),(31,8),(13,28)])
    polygon([(4,17),(13,23),(29,7),(31,8),(13,28)],shade)
    line([(6,13),(12,19)],1.2,light)

def gate(polygon, oval, line, base, shade, light):
    polygon([(3,29),(3,13),(7,7),(16,2),(25,7),(29,13),(29,29),(21,29),
       (21,15),(19,12),(16,10),(13,12),(11,15),(11,29)])
    polygon([(22,14),(26,12),(26,26),(29,26),(29,29),(21,29)],shade)
    polygon([(13,5),(16,3),(19,5),(18,9),(14,9)],light)
    line([(5,25),(5,14),(8,10)],1.3,light)

def shield(polygon, oval, line, base, shade, light):
    polygon([(4,5),(11,5),(16,2),(21,5),(28,5),(27,18),(23,25),(16,30),(8,24),(5,18)])
    polygon([(16,6),(25,8),(24,17),(21,23),(16,27)],shade)
    line([(8,16),(7,8),(12,8),(16,6)],1.4,light)

def anvil(polygon, oval, line, base, shade, light):
    polygon([(2,8),(13,8),(13,5),(29,5),(29,13),(23,16),(19,16),(18,20),(20,23),
       (26,25),(26,28),(7,28),(7,25),(13,22),(14,18),(12,15),(7,14)])
    line([(14,7),(27,7)],2,light)
    polygon([(8,26),(25,26),(26,28),(7,28)],shade)

def horse(polygon, oval, line, base, shade, light):
    polygon([(3,16),(9,10),(12,7),(13,2),(17,5),(23,5),(21,8),(26,11),(24,12),
       (28,17),(26,18),(29,23),(28,29),(9,29),(11,23),(17,17),(16,14),
       (13,17),(7,20),(4,19)])
    polygon([(19,8),(25,11),(23,13),(27,17),(25,18),(28,23),(27,28),(23,28),(23,21)],shade)
    oval((12,10,15,12),'#3A3151')
    line([(5,16),(9,13)],1.3,light)

def links(polygon, oval, line, base, shade, light):
    for x,y in ((1,12),(13,2)):
        points=[(x+2,y+6),(x+8,y),(x+14,y),(x+17,y+3),(x+17,y+8),(x+13,y+12)]
        line(points,4.5,base)
        line(points[1:3],1.3,light)
    line([(5,18),(3,21),(3,25),(7,28),(12,28),(17,23)],4,base)
    line([(11,21),(21,11)],4,light)

def wing(polygon, oval, line, base, shade, light):
    polygon([(2,19),(7,13),(15,10),(29,2),(26,10),(20,16),(25,14),(20,21),
       (14,24),(17,24),(11,29),(4,29),(7,23)])
    line([(7,24),(13,18),(21,13)],2,shade)
    line([(9,14),(16,11),(25,6)],1.5,light)

def boat(polygon, oval, line, base, shade, light):
    polygon([(14,3),(16,3),(16,21),(13,21)])
    polygon([(18,4),(28,18),(18,18)],light)
    polygon([(11,7),(11,19),(3,19)])
    polygon([(1,22),(31,20),(25,28),(8,29)],shade)
    line([(4,23),(28,21)],2,base)

def tram(polygon, oval, line, base, shade, light):
    polygon([(5,5),(9,2),(23,2),(27,5),(27,21),(24,24),(8,24),(5,21)])
    polygon([(8,7),(14,7),(14,13),(8,13)],'#314967')
    polygon([(18,7),(24,7),(24,13),(18,13)],'#314967')
    oval((8,16,12,20),light);oval((20,16,24,20),light)
    polygon([(9,24),(13,24),(10,28),(22,28),(19,24),(23,24),(29,31),(25,31),(24,30),(8,30),(7,31),(3,31)],shade)

def hearth(polygon, oval, line, base, shade, light):
    polygon([(3,14),(9,5),(18,2),(25,6),(29,15),(28,23),(20,29),(9,29),(3,24)])
    polygon([(27,14),(29,15),(28,23),(20,29),(9,29),(7,26),(18,26),(25,21)],shade)
    line([(11,23),(8,18),(10,12),(15,8),(21,9),(23,14),(21,19),
       (16,20),(14,17),(15,14),(18,14)],2.8,'#466794')

def banner(polygon, oval, line, base, shade, light):
    polygon([(6,2),(10,2),(10,30),(6,30)],light)
    polygon([(10,5),(18,3),(27,5),(24,11),(28,17),(19,16),(10,19)])
    polygon([(12,15),(19,12),(25,14),(28,17),(19,16),(10,19)],shade)

def compass(polygon, oval, line, base, shade, light):
    oval((3,3,29,29),shade);oval((6,6,26,26),'#293444')
    polygon([(26,5),(19,19),(6,27),(12,13)],base)
    polygon([(26,5),(16,16),(12,13)],light)
    polygon([(16,16),(19,19),(6,27)],shade)


for name, colors, painter in [
    ('accept',gold,exclamation),('active',water,crosshair),('turnin',jade,question),('done',jade,check),
    ('objective',steel,sword),('collect',violet,sack),('talk',water,speech),
    ('interact',amber,hand),('spell',violet,lightning),('location',steel,pin),
    ('target',amber,crosshair),('entry',silver,gate),('class',jade,shield),
    ('pending',silver,question),('reputation',jade,banner),('compass',gold,compass),
    ('flight',gold,wing),('boat',water,boat),('tram',steel,tram),('hearth',silver,hearth),
    ('profession',amber,anvil),('mount',violet,horse),('chain',gold,links),
]:
    glyph(name, colors, painter)


icon('party', (156, 201, 166, 255), lambda line, circle, poly: (
    circle((8, 7, 16, 15)), circle((20, 10, 26, 16), width=1.6),
    line([(5, 25), (6, 21), (9, 18), (15, 18), (18, 21), (19, 25)]),
    line([(21, 19), (25, 19), (28, 22), (28, 25)], 1.7),
))
icon('xp', (232, 196, 125, 255), lambda line, circle, poly: (
    poly([(16, 5), (19, 12), (27, 16), (19, 20), (16, 27), (13, 20), (5, 16), (13, 12)]),
    line([(24, 5), (24, 9)], 1.3), line([(22, 7), (26, 7)], 1.3),
))
icon('gear', (158, 201, 222, 255), lambda line, circle, poly: (
    line([(11, 6), (15, 10), (17, 10), (21, 6), (27, 10), (24, 17), (21, 15), (22, 27), (10, 27), (11, 15), (8, 17), (5, 10), (11, 6)]),
    line([(16, 12), (16, 24)], 1.4),
))
icon('settings', (204, 166, 99, 255), lambda line, circle, poly: (
    line([(7, 8), (25, 8)]), line([(7, 16), (25, 16)]), line([(7, 24), (25, 24)]),
    line([(12, 5), (12, 11)], 3), line([(21, 13), (21, 19)], 3), line([(15, 21), (15, 27)], 3),
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
# Two 32 px cells for the map pin backing and focus ring.
markers = Image.new('RGBA', (64*S, 32*S))
draw = ImageDraw.Draw(markers)
def bounds(cell, box):
    x, y, right, bottom = box
    return tuple(round(n) for n in ((cell*32+x)*S, y*S, (cell*32+right)*S-1, bottom*S-1))

draw.ellipse(bounds(0, (1, 1, 31, 31)), fill='white')
draw.ellipse(bounds(1, (1, 1, 31, 31)), outline='white', width=2*S)
markers.resize((64, 32), Image.Resampling.LANCZOS).save(OUT / 'map-markers.tga')
dash = Image.new('RGBA', (8, 2))
ImageDraw.Draw(dash).rectangle((0, 0, 3, 1), fill='white')
dash.save(OUT / 'map-dash.tga')
print('Generated UI textures in Media/')
