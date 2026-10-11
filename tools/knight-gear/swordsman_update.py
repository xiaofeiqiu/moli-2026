"""Stage the installed hybrid shops as swords and open the swordsman skill library."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'backups/swordsman_upgrade_20261010'
OUT = ROOT / 'docs/swordsman_upgrade'
STAGE = BASE / 'staged'
RUN = BASE / 'native_runtime/gmsv'
sys.path.insert(0, str(Path(__file__).parent))
from build import lua, records


def digest(data):
    return hashlib.sha256(data).hexdigest()


def stage():
    assert not (BASE / 'manifest.json').exists(), 'Update already staged'
    gear = json.loads((ROOT / 'docs/knight_hybrid_gear/manifest.json').read_text('utf-8'))
    skills = json.loads((ROOT / 'docs/skill_library/manifest.json').read_text('utf-8'))
    skill_ids = {s['id'] for s in skills['player_skills']}
    updates = {}
    raw = (ROOT / 'gmsv/data/itemset.txt').read_bytes()
    rows = {int(r[11]): r for r in records(raw)}
    sword_templates = {}
    for rank in range(1, 12):
        candidates = [r for r in rows.values() if r[14] == b'0' and r[16] == b'0'
                      and int(r[23] or 0) == rank and int(r[11]) < 700000 and int(r[13] or 0) > 0]
        assert candidates, rank
        sword_templates[rank] = max(candidates, key=lambda r: (int(r[31] or 0) + int(r[32] or 0), -int(r[11])))
    replacements = {}
    sword_ids = []
    for spec in gear['items']:
        if spec['type'] != 2:
            continue
        sword_ids.append(spec['id'])
        row = list(rows[spec['id']])
        template = sword_templates[spec['native_rank']]
        spec['name'] = '魔剑·' + str(spec['min_level']) + '级'
        spec['type'] = 0
        spec['sword_visual_template'] = int(template[11])
        row[0] = row[1] = spec['name'].encode('gbk')
        row[2] = f"剑士/骑士{spec['min_level']}级，物理与魔法属性融合".encode('gbk')
        row[12] = template[12]
        row[14] = b'0'
        row[16] = b'0'
        replacements[spec['id']] = row
    for shop in gear['shops']:
        shop['name'] = shop['name'].replace('骑士装备', '魔剑装备')
    result = []
    for line in raw.splitlines(keepends=True):
        row = line.rstrip(b'\r\n').split(b'\t')
        if len(row) == 102 and row[11].isdigit() and int(row[11]) in replacements:
            line = b'\t'.join(replacements[int(row[11])]) + (b'\r\n' if line.endswith(b'\r\n') else b'\n')
        result.append(line)
    updates['gmsv/data/itemset.txt'] = b''.join(result)
    updates['gmsv/lua/Modules/knightHybridGearData.lua'] = ('return ' + lua({'items': gear['items'], 'shops': gear['shops']}) + '\n').encode('gbk')
    for path, encoding in [('gmsv/lua/Modules/knightHybridGear.lua', 'gbk'), ('tools/knight-gear/knightHybridGear.lua', 'utf-8')]:
        text = (ROOT / path).read_bytes().decode(encoding)
        assert 'if job < 31 or job > 37 then' in text
        text = text.replace('if job < 31 or job > 37 then', 'if not ((job >= 11 and job <= 17) or (job >= 31 and job <= 37)) then')
        text = text.replace('这套魔骑装备需要骑士职业。', '这套装备需要剑士或骑士职业。')
        updates[path] = text.encode(encoding)
    raw = (ROOT / 'gmsv/data/skilllv.txt').read_bytes()
    result = []
    found = set()
    changed_caps = 0
    for line in raw.splitlines(keepends=True):
        row = line.rstrip(b'\r\n').split(b'\t')
        if len(row) >= 4 and row[1].isdigit() and row[2].isdigit() and int(row[1]) in skill_ids and 11 <= int(row[2]) <= 17:
            pair = (int(row[1]), int(row[2]))
            assert pair not in found, pair
            found.add(pair)
            changed_caps += row[3] != b'30'
            row[3] = b'30'
            line = b'\t'.join(row) + (b'\r\n' if line.endswith(b'\r\n') else b'\n')
        result.append(line)
    for sid in sorted(skill_ids):
        for job in range(11, 18):
            if (sid, job) not in found:
                result.append(f'{sid}\t{sid}\t{job}\t30\r\n'.encode('ascii'))
    updates['gmsv/data/skilllv.txt'] = b''.join(result)
    # Custom profession skills also consult their Lua family gate when used.
    for path, encoding in [('gmsv/lua/Modules/cg71JobSkills.lua', 'gbk'), ('tools/jobskill-pack/cg71JobSkills.lua', 'utf-8')]:
        text = (ROOT / path).read_bytes().decode(encoding)
        old = 'if s and not contains(s.families,family(p)) then return 0 end'
        assert text.count(old) == 1
        text = text.replace(old, 'if s and family(p)~=10 and not contains(s.families,family(p)) then return 0 end')
        updates[path] = text.encode(encoding)
    manifest = {'sword_ids': sword_ids, 'shops': gear['shops'], 'items': gear['items'],
                'skill_ids': sorted(skill_ids), 'swordsman_jobs': list(range(11, 18)),
                'changed_skill_caps': changed_caps, 'files': {}}
    for path, data in updates.items():
        old = (ROOT / path).read_bytes()
        for directory, value in [('before', old), ('staged', data)]:
            target = BASE / directory / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value)
        manifest['files'][path] = {'before': digest(old), 'after': digest(data)}
    (BASE / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), 'utf-8')
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), 'utf-8')
    verify()
    print(json.dumps({'swords': len(sword_ids), 'shops': len(gear['shops']), 'skills': len(skill_ids), 'changed_caps': changed_caps}))


def verify():
    m = json.loads((BASE / 'manifest.json').read_text('utf-8'))
    for path, hashes in m['files'].items():
        assert digest((STAGE / path).read_bytes()) == hashes['after'], path
    old = {int(r[11]): r for r in records((BASE / 'before/gmsv/data/itemset.txt').read_bytes())}
    current = {int(r[11]): r for r in records((STAGE / 'gmsv/data/itemset.txt').read_bytes())}
    assert old.keys() == current.keys()
    for item_id, row in current.items():
        if item_id in m['sword_ids']:
            assert row[14] == b'0' and row[16] == b'0'
            assert all(v == old[item_id][n] for n, v in enumerate(row) if n not in (0, 1, 2, 12, 14, 16))
        else:
            assert row == old[item_id], item_id
    caps = {(int(r[1]), int(r[2])): int(r[3]) for r in records((STAGE / 'gmsv/data/skilllv.txt').read_bytes()) if len(r)>=4 and all(v.isdigit() for v in r[1:4])}
    assert all(caps[sid, job] == 30 for sid in m['skill_ids'] for job in m['swordsman_jobs'])
    before = {(int(r[1]), int(r[2])): int(r[3]) for r in records((BASE / 'before/gmsv/data/skilllv.txt').read_bytes()) if len(r)>=4 and all(v.isdigit() for v in r[1:4])}
    assert all(caps[pair] == cap for pair, cap in before.items() if pair[1] not in m['swordsman_jobs'])
    return m


def prepare():
    m = verify()
    seed = ROOT / 'backups/knight_hybrid_gear_20261004/native_runtime/gmsv'
    shutil.copytree(seed, RUN, dirs_exist_ok=True)
    shutil.copytree(ROOT / 'gmsv/lua', RUN / 'lua', dirs_exist_ok=True)
    for name in ['npc.txt', 'skill.txt', 'skilllv.txt', 'tech.txt', 'skillexp.txt', 'itemset.txt', 'jobs.txt']:
        shutil.copy2(ROOT / 'gmsv/data' / name, RUN / 'data' / name)
    shutil.copy2(ROOT / 'gmsv/cgmsv.cf', RUN / 'cgmsv.cf')
    for path in m['files']:
        if path.startswith('gmsv/'):
            target = RUN / path.removeprefix('gmsv/')
            shutil.copy2(STAGE / path, target)
    setup = (RUN / 'setup.cf').read_bytes()
    setup = re.sub(rb'(?m)^port=\d+', b'port=19052', setup)
    (RUN / 'setup.cf').write_bytes(setup)
    config = "moduleInitial()\nloadModule('cg71JobSkills')\nloadModule('skillLibrary')\nloadModule('fivePet')\nloadModule('fight')\nloadModule('knightHybridGear')\ndofile('lua/swordsman_probe.lua')\n"
    (RUN / 'lua/ModuleConfig.lua').write_bytes(config.encode('gbk'))
    probe = (Path(__file__).parent / 'native_probe.lua').read_text('utf-8')
    probe = probe.replace('__OUTPUT__', OUT.as_posix()).replace('__ITEMSET_SHA256__', m['files']['gmsv/data/itemset.txt']['after'])
    probe = probe.replace('[2]=CONST', '[0]=CONST').replace('slots[2]', 'slots[0]')
    probe = probe.replace("'CHAR_职业',37", "'CHAR_职业',17").replace("'CHAR_职类ID',30", "'CHAR_职类ID',10")
    extension = (Path(__file__).parent / 'swordsman_probe_extra.lua').read_text('utf-8')
    probe = probe.replace('  Char.DelDummy(owner);owner=-1\n  R.status', extension + '\n  Char.DelDummy(owner);owner=-1\n  R.status')
    (RUN / 'lua/swordsman_probe.lua').write_bytes(probe.encode('gbk'))
    print(json.dumps({'runtime': str(RUN), 'port': 19052}))


def test():
    report_path = OUT / 'native_result.json'
    report_path.unlink(missing_ok=True)
    process = None
    try:
        with (OUT / 'native.log').open('wb') as log:
            process = subprocess.Popen([str(RUN / 'cgmsv.exe')], cwd=RUN, stdin=subprocess.DEVNULL,
                                       stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            deadline = time.monotonic() + 100
            while time.monotonic() < deadline and process.poll() is None:
                if report_path.exists():
                    try:
                        report = json.loads(report_path.read_bytes().decode('gbk'))
                    except (json.JSONDecodeError, UnicodeDecodeError):
                        pass
                    else:
                        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
                        print(json.dumps({'status': report['status'], 'checks': len(report['checks']), 'error': report.get('error')}, ensure_ascii=False))
                        assert report['status'] == 'PASS'
                        return
                time.sleep(.25)
            raise RuntimeError('Native test did not finish; inspect docs/swordsman_upgrade/native.log')
    finally:
        if process is not None:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)


def install():
    m = verify()
    report = json.loads((OUT / 'native_result.json').read_text('utf-8'))
    assert report['status'] == 'PASS'
    assert report['itemset_sha256'] == m['files']['gmsv/data/itemset.txt']['after']
    for path, hashes in m['files'].items():
        assert digest((ROOT / path).read_bytes()) == hashes['before'], path
        if path.startswith('gmsv/'):
            assert digest((RUN / path.removeprefix('gmsv/')).read_bytes()) == hashes['after'], path
    for path, hashes in m['files'].items():
        shutil.copy2(STAGE / path, ROOT / path)
        assert digest((ROOT / path).read_bytes()) == hashes['after']
    (OUT / 'installed.json').write_text(json.dumps({'files': m['files'], 'checks': len(report['checks']), 'requires_restart': True}, indent=2), 'utf-8')
    print('Installed; server restart required')


if __name__ == '__main__':
    {'stage': stage, 'verify': verify, 'prepare': prepare, 'test': test, 'install': install}[sys.argv[1]]()
