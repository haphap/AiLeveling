#!/usr/bin/env python3
"""Render the actual tracker widget layout with example state, outside the WoW client."""
import json
import sys
import re
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageChops

ROOT = Path(__file__).resolve().parents[1]
SCALE = 2
FONT = '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc'


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] in ('dungeon', 'assist', 'plan') else 'tracker'
    blocked = mode == 'dungeon' and 'entry-blocked' in sys.argv[2:]
    journey = mode == 'dungeon' and 'journey' in sys.argv[2:]
    loot = mode == 'dungeon' and 'loot' in sys.argv[2:]
    large = mode != 'dungeon' and 'large' in sys.argv[1:]
    records = json.loads(subprocess.check_output(['lua5.1', 'tools/preview_tracker.lua', mode] + (['entry-blocked'] if blocked else ['journey'] if journey else ['loot'] if loot else ['large'] if large else []), cwd=ROOT))
    canvas = Image.new('RGBA', (round(records[0]['rect']['w'] * SCALE), round(records[0]['rect']['h'] * SCALE)))
    draw = ImageDraw.Draw(canvas)
    for y in range(canvas.height):
        ratio = y / canvas.height
        draw.line((0, y, canvas.width, y), fill=(int(24 + ratio * 9), int(36 + ratio * 6), int(43 + ratio * 5)))

    def color(value, default=(235, 242, 247, 255)):
        if not value:
            return default
        return tuple(round(v * 255) for v in (value + [1])[:4])

    def texture(path, width, height, tint=None, uv=None):
        path = ROOT / path.replace('\\', '/').removeprefix('Interface/AddOns/AiLeveling/')
        asset = Image.open(path).convert('RGBA')
        if uv:
            if uv[0] > uv[1]:
                asset = asset.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            if uv[2] > uv[3]:
                asset = asset.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        asset = asset.resize((max(1, round(width)), max(1, round(height))), Image.Resampling.LANCZOS)
        if tint:
            asset = ImageChops.multiply(asset, Image.new('RGBA', asset.size, color(tint)))
        return asset

    for row in records:
        overlay = Image.new('RGBA', canvas.size)
        d = ImageDraw.Draw(overlay)
        r = row['rect']
        x, y, w, h = (r[k] * SCALE for k in ['x', 'y', 'w', 'h'])
        if row.get('background'):
            d.rectangle((x, y, x + w, y + h), fill=color(row['background']))
        if row.get('border'):
            d.rectangle((x, y, x + w, y + h), outline=color(row['border']), width=1)
        if row['kind'] == 'Texture':
            if row.get('texture', '').startswith('Interface\\AddOns\\AiLeveling\\Media\\'):
                asset = texture(row['texture'], w, h, row.get('color'), row.get('uv'))
                overlay.alpha_composite(asset, (round(x), round(y)))
            else:
                d.rectangle((x, y, x + w, y + h), fill=color(row.get('color')))
        if row['kind'] == 'Line':
            d.line(tuple(v * SCALE for pt in [row['start'], row['finish']] for v in pt),
                   fill=color(row.get('color')), width=round(row['thickness'] * SCALE))
        if row.get('text'):
            font = ImageFont.truetype(FONT, max(1, round(row['size'] * SCALE)))
            lines, line_width = [[]], 0
            ink = color(row.get('color'))
            for token in re.split(r'(\|c[0-9a-fA-F]{8}|\|r|\|T[^|]+\|t)', re.sub(r'\|H[^|]+\|h(.*?)\|h', r'\1', row['text'])):
                if token.startswith('|c'):
                    ink = tuple(int(token[i:i+2], 16) for i in (4, 6, 8, 2))
                    continue
                if token == '|r':
                    ink = color(row.get('color'))
                    continue
                glyphs = re.findall(r'[0-9]+/[0-9]+|.', token, re.S) if row.get('nonSpaceWrap') is False else token
                if token.startswith('|T'):
                    path, height, width, *_ = token[2:-2].split(':')
                    glyphs = [texture(path, float(width)*SCALE, float(height)*SCALE)]
                for char in glyphs:
                    advance = char.width if isinstance(char, Image.Image) else 0 if char == '\n' else d.textlength(char, font=font)
                    if char == '\n' or (lines[-1] and line_width + advance > w):
                        lines.append([])
                        line_width = 0
                    if char != '\n':
                        lines[-1].append((char, ink, advance))
                        line_width += advance
            for i, line in enumerate(lines[:row.get('maxLines') or len(lines)]):
                xx = x
                line_width = sum(glyph[2] for glyph in line)
                if row.get('justify') == 'RIGHT':
                    xx += w - line_width
                elif row.get('justify') == 'CENTER':
                    xx += (w - line_width) / 2
                yy = y + i * (row['size'] + 4) * SCALE
                for char, ink, advance in line:
                    if isinstance(char, Image.Image):
                        overlay.alpha_composite(char, (round(xx), round(yy+(row['size']*SCALE-char.height)/2)))
                    else:
                        d.text((xx, yy + row['size'] * SCALE), char, font=font, fill=ink, anchor='ls',
                               stroke_width=1, stroke_fill=(0, 0, 0, 150))
                    xx += advance
        if row.get('clip'):
            c = row['clip']
            bounds = tuple(round(v * SCALE) for v in [c['x'], c['y'], c['x'] + c['w'], c['y'] + c['h']])
            clipped = Image.new('RGBA', canvas.size)
            clipped.paste(overlay.crop(bounds), bounds[:2])
            overlay = clipped
        canvas = Image.alpha_composite(canvas, overlay)
    d = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(FONT, 12 * SCALE)
    d.text((100 * SCALE, 38 * SCALE), '布局预览 · 示例数据', font=font, fill=(145, 165, 176), anchor='lt')
    output = ROOT / f'dist/{mode}{"-entry-blocked" if blocked else "-journey" if journey else "-loot" if loot else "-large" if large else ""}-preview.png'
    canvas.convert('RGB').save(output)
    print(output)


if __name__ == '__main__':
    main()
