"""Install the isolated sanctuary map and GBK Lua runtime from UTF-8 sources."""
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
FLOOR = 60003


def main():
    target = ROOT / 'gmsv/data/map/60003_sanctuary'
    for p in target.parent.iterdir():
        if not p.is_file() or p == target:
            continue
        raw = p.read_bytes()
        if raw[:6] == b'LS2MAP' and struct.unpack('>H', raw[6:8])[0] == FLOOR:
            raise RuntimeError('Map ID collision: ' + str(p))
    source = bytearray((ROOT / 'gmsv/data/map/04130_shrine').read_bytes())
    assert source[:6] == b'LS2MAP'
    assert struct.unpack('>HH', source[40:44]) == (50, 50)
    source[6:8] = struct.pack('>H', FLOOR)
    source[8:40] = '圣殿|0'.encode('gbk').ljust(32, b'\0')
    # The original shrine has tall arches and walls extending across walkable
    # tiles. Build one open hall from its existing stone floor/wall resources.
    width, height = 100, 50
    ground, objects = [0] * (width * height), [0] * (width * height)
    for y in range(7, 44):
        for x in range(7, 94):
            ground[y * width + x] = 3390 + (x + y) % 3
            if x in (7, 93) or y in (7, 43):
                objects[y * width + x] = 16250
    source[40:44] = struct.pack('>HH', width, height)
    source[44:10044] = struct.pack(f'>{width * height}H', *ground) + struct.pack(f'>{width * height}H', *objects)
    target.write_bytes(source)
    for name in ('sanctuary', 'sanctuaryData', 'battleState'):
        (ROOT / f'gmsv/lua/Modules/{name}.lua').write_bytes((HERE / f'{name}.lua').read_bytes().decode('utf-8').encode('gbk'))
    (ROOT / 'gmsv/lua/libs/Module/Parts/Npc.lua').write_bytes((HERE / 'Npc.lua').read_bytes().decode('utf-8').encode('gbk'))
    config = ROOT / 'gmsv/lua/ModuleConfig.lua'
    raw = config.read_bytes()
    if b"loadModule('battleState')" not in raw:
        raw = raw.replace(b'moduleInitial();', b"moduleInitial();\r\nloadModule('battleState')", 1)
    if b"loadModule('sanctuary')" not in raw:
        raw += b"\r\nloadModule('sanctuary')\r\n"
    config.write_bytes(raw)
    settings = ROOT / 'gmsv/data/mapset.txt'
    raw = settings.read_bytes()
    if not any(line.split()[:1] == [b'60003'] for line in raw.splitlines()):
        # Inherit the original safe indoor shrine's native map flags.
        row = next(line for line in raw.splitlines() if line.split()[:1] == [b'4130'])
        raw = raw.rstrip(b'\r\n') + b'\r\n60003' + row[len(b'4130'):] + b'\r\n'
        settings.write_bytes(raw)


if __name__ == '__main__':
    main()
    from shops_install import main as install_shops
    install_shops()
