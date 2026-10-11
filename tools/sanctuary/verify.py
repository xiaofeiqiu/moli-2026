"""Verify installed tutors in an isolated native server and empty SQLite DB."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import sqlite3
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
RUN = ROOT / 'backups/sanctuary_20261010/native_runtime/gmsv'
OUT = ROOT / 'docs/sanctuary'


def copy_changed(source, dest):
    source, dest = Path(source), Path(dest)
    if not dest.exists() or source.stat().st_size != dest.stat().st_size or source.stat().st_mtime_ns != dest.stat().st_mtime_ns:
        shutil.copy2(source, dest)
    return str(dest)


def main(probe='native_probe.lua', report_name='native_result'):
    RUN.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ('lua', 'data'):
        shutil.copytree(ROOT / 'gmsv' / name, RUN / name, dirs_exist_ok=True, copy_function=copy_changed)
    for name in ('cgmsv.exe', 'cgmsv.cf', 'log/log.cf'):
        dest = RUN / name;dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'gmsv' / name, dest)
    for name in ('store/itemcount', 'store/dungeon', 'store/house', 'log', 'Dengon', 'GMLog', 'dump', 'house'):
        (RUN / name).mkdir(parents=True, exist_ok=True)
    setup = (ROOT / 'gmsv/setup.cf.example').read_bytes()
    for key, val in (('port', 19230), ('dbengine', 1), ('dummynum', 100)):
        setup, count = re.subn(rb'(?m)^' + key.encode() + rb'=\d+', f'{key}={val}'.encode(), setup)
        assert count == 1, key
    (RUN / 'setup.cf').write_bytes(setup)
    if not (RUN / 'data.db3').exists():
        with sqlite3.connect(RUN / 'data.db3') as db:
            db.executescript((ROOT / 'gmsv/sql/sqlite.sql').read_text('utf-8'))
    http = RUN / 'lua/Modules/http.lua'
    http.write_bytes(http.read_bytes().replace(b'Http.Start("0.0.0.0", 10086)', b'Http.Start("127.0.0.1", 19231)'))
    config = (ROOT / 'gmsv/lua/ModuleConfig.lua').read_bytes()
    (RUN / 'lua/ModuleConfig.lua').write_bytes(config + b"\r\ndofile('lua/sanctuary_probe.lua')\r\n")
    result = OUT / (report_name + '.json')
    result.unlink(missing_ok=True)
    source = (HERE / probe).read_text('utf-8').replace('__REPORT__', result.as_posix())
    (RUN / 'lua/sanctuary_probe.lua').write_bytes(source.encode('gbk'))
    print('Loading complete server configuration on isolated ports 19230/19231.', flush=True)
    with (OUT / (report_name + '.log')).open('wb') as log:
        process = subprocess.Popen([str(RUN / 'cgmsv.exe')], cwd=RUN, stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + 120
            report = None
            while process.poll() is None and time.monotonic() < deadline:
                if result.exists():
                    try:
                        raw = result.read_bytes()
                        try:
                            report = json.loads(raw.decode('utf-8'))
                        except UnicodeDecodeError:
                            report = json.loads(raw.decode('gbk'))
                    except json.JSONDecodeError:
                        pass
                    else:
                        if report['status'] in ('PASS', 'FAIL'):
                            break
                        report = None
                time.sleep(.2)
            if report is None:
                raise RuntimeError(f'Native probe did not complete; exit={process.poll()}; see {log.name}')
            report['source_sha256'] = {}
            for rel in ('lua/ModuleConfig.lua', 'lua/Modules/sanctuary.lua', 'lua/Modules/sanctuaryData.lua', 'lua/Modules/sanctuaryShops.lua', 'lua/Modules/petEquipment.lua', 'data/itemset.txt', 'lua/Modules/battleState.lua', 'lua/libs/Module/Parts/Npc.lua', 'lua/Modules/fivePet.lua', 'lua/Modules/cg71JobSkills.lua', 'data/map/60003_sanctuary'):
                raw = (ROOT / 'gmsv' / rel).read_bytes()
                assert raw == (config if rel == 'lua/ModuleConfig.lua' else (RUN / rel).read_bytes()), rel
                report['source_sha256'][rel] = hashlib.sha256(raw).hexdigest()
            result.write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
            print(json.dumps({'status': report['status'], 'checks': len(report['checks']), 'npcs': len(report['npcs']),
                              'error': report.get('error'), 'report': str(result)}, ensure_ascii=False))
            assert report['status'] == 'PASS', report.get('error')
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
