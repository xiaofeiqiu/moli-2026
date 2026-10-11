"""Read current installed content for guide authoring, never touch player data."""
from pathlib import Path
import collections
import json
import re
import struct

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'gmsv/data'


def text(path):
    raw = path.read_bytes()
    try:
        return raw.decode('utf-8')
    except UnicodeDecodeError:
        return raw.decode('gbk', errors='replace')


def rows(name):
    for ln, line in enumerate(text(DATA / name).splitlines(), 1):
        if line.strip() and not line.lstrip().startswith(('#', '//')):
            yield ln, line.split('\t')


def number(value):
    try:
        return int(value)
    except (ValueError, TypeError):
        return None


def table(name, key, value):
    return {number(c[key]): c[value] for ln, c in rows(name) if len(c) > max(key, value)}


MESSAGES = table('msg.txt', 0, 1)
ITEMS = table('itemset.txt', 11, 1)
NPCS = []
for ln, c in rows('npc.txt'):
    if len(c) < 25:
        continue
    NPCS.append(dict(line=ln, kind=c[0].lower(), name=c[1] or '任务接待员',
                     id=number(c[3]), mapType=number(c[7]), floor=number(c[8]),
                     x=number(c[9]), y=number(c[10]), payload=c[24]))

MAPS = {}
MAP_PATHS = {}
MAP_SIZES = {}
for f in (DATA / 'map').iterdir():
    if not f.is_file():
        continue
    with f.open('rb') as stream:
        h = stream.read(60)
    if not h.startswith(b'LS2MAP') or len(h) < 44:
        continue
    floor = struct.unpack_from('>H', h, 6)[0]
    if floor == 65535 and len(h) >= 52:
        floor = struct.unpack_from('>I', h, 48)[0]
    MAPS[floor] = h[8:40].split(b'\0', 1)[0].decode('gbk', errors='replace')
    MAP_PATHS[floor] = f
    MAP_SIZES[floor] = struct.unpack_from('>HH', h, 40)


def messages(script):
    return [(int(m[1]), MESSAGES.get(int(m[1]), '')) for m in
            re.finditer(r'(?im)^\s*(?:EndWindow|Window|Message)\s+(\d+)', script)]


def brief(pattern):
    result = []
    for n in NPCS:
        if not re.search(pattern, n['payload'], re.I):
            continue
        p = DATA / 'npc' / n['payload']
        script = text(p) if p.is_file() else ''
        result.append({**n, 'map': MAPS.get(n['floor'], ''),
                       'dialog': messages(script)[:5],
                       'items': sorted({int(x) for x in re.findall(r'(?i)(?:give(?:leak[01])?item|killitem|item)[ _]*(\d+)', script)}),
                       'conditions': [l.strip() for l in script.splitlines() if re.match(r'(?i)\s*block\b', l)][:4]})
    return result


if __name__ == '__main__':
    import sys
    pattern = sys.argv[1] if len(sys.argv) > 1 else 'EV_rk_1odr|EV_tane_main1_(001|100|101)|EV_suto_puk3m1_000'
    print(json.dumps(brief(pattern), ensure_ascii=False, indent=2))
