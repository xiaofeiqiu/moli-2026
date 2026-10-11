"""Render the installed shrine's original client assets to inspect occlusion.

Read-only access to client resources. This preview does not edit game graphics.
"""
from pathlib import Path
import json
import mmap
import struct
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/cg71-pets'))
from scan import unpack_rd
from export_previews import default_palette, inner_palette


def main():
    out = ROOT / 'docs/sanctuary'
    out.mkdir(parents=True, exist_ok=True)
    raw = (ROOT / 'gmsv/data/map/60003_sanctuary').read_bytes()
    w, h = struct.unpack_from('>HH', raw, 40)
    cells = w * h
    ground = struct.unpack_from(f'>{cells}H', raw, 44)
    objects = struct.unpack_from(f'>{cells}H', raw, 44 + cells * 2)
    rows = json.loads((out / 'native_result.json').read_text('utf-8'))['npcs']
    rows = [r for r in rows if r['floor'] == 60003]
    gi = (ROOT / 'bin/GraphicInfo_66.bin').read_bytes()
    by_serial, by_index = {}, {}
    for pos in range(0, len(gi), 40):
        meta = struct.unpack_from('<IIIiiII', gi, pos) + (struct.unpack_from('<I', gi, pos + 36)[0],)
        by_index[meta[0]] = meta
        if meta[7]:
            by_serial[meta[7]] = meta
    ai = (ROOT / 'bin/AnimeInfo_4.bin').read_bytes()
    animation = {a[0]: a for a in struct.iter_unpack('<IIHH', ai)}
    ad = (ROOT / 'bin/Anime_4.bin').read_bytes()
    palette = default_palette(ROOT / 'bin/pal/palet_00.cgp')
    cache = {}
    # The automatic-stat tutor is a static V3 resource, not an Anime_4 entry.
    v3_info = (ROOT / 'bin/GraphicInfoV3_19.bin').read_bytes()
    for pos in range(0, len(v3_info), 40):
        if struct.unpack_from('<I', v3_info, pos+36)[0] == 14722:
            meta = struct.unpack_from('<IIIiiII', v3_info, pos) + (14722,)
            with (ROOT / 'bin/GraphicV3_19.bin').open('rb') as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as data:
                detail, pixels = unpack_rd(data, meta)
                colors = inner_palette(pixels[meta[5]*meta[6]:]) if detail['palette_bytes'] else palette
                rendered = Image.frombytes('RGBA', (meta[5], meta[6]), b''.join(colors[i] for i in pixels[:meta[5]*meta[6]]))
                cache[meta] = rendered.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
            by_serial[14722] = meta
            break
    font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 14)
    with (ROOT / 'bin/Graphic_66.bin').open('rb') as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as data:
        def sprite(meta):
            if meta not in cache:
                detail, pixels = unpack_rd(data, meta)
                assert detail['palette_bytes'] == 0
                image = Image.frombytes('RGBA', (meta[5], meta[6]), b''.join(palette[i] for i in pixels[:meta[5]*meta[6]]))
                cache[meta] = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
            return cache[meta]

        def idle(appearance):
            entry = animation.get(appearance)
            if entry is None:
                return by_serial.get(appearance), 0, 0
            pos = entry[1]
            for _ in range(entry[2]):
                direction, action, cycle, count = struct.unpack_from('<HHII', ad, pos)
                extended = ad[pos+16:pos+20] == b'\xff'*4
                head = 20 if extended else 12
                if direction == 4 and action == 0:
                    index, dx, dy, flags = struct.unpack_from('<IhhH', ad, pos+head)
                    return by_index[index], dx, dy
                pos += head + count * 10
            raise ValueError('No idle frame ' + str(appearance))

        canvas = Image.new('RGBA', (5000, 2600), (12, 12, 18, 255))
        def anchor(x, y):
            return 1600 + (x-y)*32, 100 + (x+y)*16

        def paste(x, y, meta, dx=0, dy=0):
            sx, sy = anchor(x, y)
            canvas.alpha_composite(sprite(meta), (sx+meta[3]+dx, sy+meta[4]+dy))

        for y in range(h):
            for x in range(w):
                serial = ground[y*w+x]
                if serial in by_serial:
                    paste(x, y, by_serial[serial])
        entries = []
        for y in range(h):
            for x in range(w):
                serial = objects[y*w+x]
                if serial and serial in by_serial:
                    entries.append((x+y, x, y, 'object', by_serial[serial], 0, 0, None))
        for row in rows:
            name = row['name']
            appearance = row['image']
            meta, dx, dy = idle(appearance)
            if meta:
                entries.append((row['x']+row['y'], row['x'], row['y'], 'npc', meta, dx, dy, row))
        ordered = sorted(entries, key=lambda e: (e[0], e[1], e[3]))
        visibility = []
        for i, (_, x, y, kind, meta, dx, dy, row) in enumerate(ordered):
            if kind == 'npc':
                sx, sy = anchor(x, y)
                left, top = sx+meta[3]+dx, sy+meta[4]+dy
                npc_mask = sprite(meta).getchannel('A')
                covered = Image.new('L', npc_mask.size)
                for _, ox, oy, other_kind, other_meta, odx, ody, _ in ordered[i+1:]:
                    if other_kind != 'object':
                        continue
                    ax, ay = anchor(ox, oy)
                    wall_mask = sprite(other_meta).getchannel('A')
                    covered.paste(wall_mask, (ax+other_meta[3]+odx-left, ay+other_meta[4]+ody-top), wall_mask)
                overlap = ImageChops.multiply(npc_mask, covered).getbbox()
                visibility.append({'name': row['name'], 'x': x, 'y': y, 'wall_occlusion': bool(overlap)})
            paste(x, y, meta, dx, dy)
        # Labels are drawn last so obscured sprites can still be identified.
        draw = ImageDraw.Draw(canvas)
        for row in rows:
            sx, sy = anchor(row['x'], row['y'])
            text = f"{row['x']},{row['y']}"
            draw.text((sx-20, sy+15), text, font=font, fill='yellow', stroke_width=2, stroke_fill='black')
        canvas.crop((150, 0, 4900, 2450)).convert('RGB').save(out / 'room_preview.png')
        (out / 'visual_result.json').write_text(json.dumps(visibility, ensure_ascii=False, indent=2), 'utf-8')
        assert len(visibility) == 86
        assert not any(row['wall_occlusion'] for row in visibility), 'Foreground wall obscures an NPC'
        print(out / 'room_preview.png')


if __name__ == '__main__':
    main()
