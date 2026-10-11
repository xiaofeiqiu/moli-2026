"""Install sanctuary merchants without touching player data."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    itemset = ROOT / 'gmsv/data/itemset.txt'
    raw = itemset.read_bytes()
    expected = {700000 + family * 15 + rank - 1: (name + 'R' + str(rank), rank * 1000)
                for family, name in enumerate(('宠服', '宠甲', '宠圈', '宠晶', '宠饰'))
                for rank in (1, 5, 10, 15)}
    found = set()
    lines = []
    for line in raw.splitlines(keepends=True):
        body = line.rstrip(b'\r\n')
        cols = body.split(b'\t')
        if len(cols) > 13 and cols[11].isdigit() and int(cols[11]) in expected:
            iid = int(cols[11])
            name, price = expected[iid]
            assert cols[1].decode('gbk') == name, (iid, name)
            assert cols[13] in (b'0', str(price).encode()), (iid, cols[13])
            cols[13] = str(price).encode()
            line = b'\t'.join(cols) + line[len(body):]
            found.add(iid)
        lines.append(line)
    assert found == set(expected), 'Missing pet equipment'
    itemset.write_bytes(b''.join(lines))
    for name in ('sanctuaryShops', 'sanctuaryData', 'petEquipment'):
        (ROOT / f'gmsv/lua/Modules/{name}.lua').write_bytes(
            (HERE / f'{name}.lua').read_bytes().decode('utf-8').encode('gbk'))
    (ROOT / 'gmsv/lua/sanctuaryDiagnose.lua').write_bytes(
        (HERE / 'sanctuaryDiagnose.lua').read_bytes().decode('utf-8').encode('gbk'))
    config = ROOT / 'gmsv/lua/ModuleConfig.lua'
    raw = config.read_bytes()
    newline = b'\r\n' if b'\r\n' in raw else b'\n'
    for name in ('sanctuaryShops', 'petEquipment'):
        command = f"loadModule('{name}')".encode()
        if command not in raw:
            raw += newline + command + newline
    config.write_bytes(raw)



if __name__ == '__main__':
    main()
