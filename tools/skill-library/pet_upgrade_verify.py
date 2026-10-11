"""Verify upgrades against a disposable native server and real bank inventories."""
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
BASE = ROOT / 'backups/pet_skill_upgrade_20261011'
RUN = BASE / 'native_runtime/gmsv'


def main(mode='upgrade'):
    sys.stdout.reconfigure(encoding='utf-8')
    RUN.mkdir(parents=True, exist_ok=True)
    assert RUN.resolve().is_relative_to((ROOT / 'backups').resolve())
    for name in ('lua', 'data'):
        def copy_changed(source, destination):
            source, destination = Path(source), Path(destination)
            if not destination.exists() or (source.stat().st_size, source.stat().st_mtime_ns) != (destination.stat().st_size, destination.stat().st_mtime_ns):
                shutil.copy2(source, destination)
            return str(destination)
        shutil.copytree(ROOT / 'gmsv' / name, RUN / name, dirs_exist_ok=True, copy_function=copy_changed)
    for name in ('cgmsv.exe', 'cgmsv.cf', 'log/log.cf'):
        dest = RUN / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'gmsv' / name, dest)
    for name in ('store/itemcount', 'store/dungeon', 'store/house', 'log', 'Dengon', 'GMLog', 'dump', 'house'):
        (RUN / name).mkdir(parents=True, exist_ok=True)
    setup = (ROOT / 'gmsv/setup.cf.example').read_bytes()
    for key, value in (('port', 19260), ('dbengine', 1), ('dummynum', 100)):
        setup, count = re.subn(rb'(?m)^' + key.encode() + rb'=\d+', f'{key}={value}'.encode(), setup)
        assert count == 1, key
    (RUN / 'setup.cf').write_bytes(setup)
    (RUN / 'data.db3').unlink(missing_ok=True)
    with sqlite3.connect(RUN / 'data.db3') as db:
        db.executescript((ROOT / 'gmsv/sql/sqlite.sql').read_text('utf-8'))
    config = (ROOT / 'gmsv/lua/ModuleConfig.lua').read_bytes()
    for module in ('autoRegister', 'loginGate', 'http'):
        config = re.sub(rb"(?m)^loadModule\('" + module.encode() + rb"'\)\r?\n?", b'', config)
    (RUN / 'lua/ModuleConfig.lua').write_bytes(config + b"\ndofile('lua/pet_upgrade_probe.lua')\n")
    result = BASE / (mode + '_native.json')
    result.unlink(missing_ok=True)
    request, ready = BASE / 'bank_fixture_request.json', BASE / 'bank_fixture_ready'
    request.unlink(missing_ok=True)
    ready.unlink(missing_ok=True)
    source = ROOT / ('tools/skill-library/pet_upgrade_probe.lua' if mode == 'upgrade' else 'tools/game-qol/help_probe.lua')
    probe = source.read_text('utf-8').replace('__OUTPUT__', BASE.as_posix()).replace('__REPORT__', result.as_posix())
    (RUN / 'lua/pet_upgrade_probe.lua').write_bytes(probe.encode('gbk'))
    print(f'Running {mode} in isolated server on port 19260, with an empty test database.', flush=True)
    with result.with_suffix('.log').open('wb') as log:
        process = subprocess.Popen([str(RUN / 'cgmsv.exe')], cwd=RUN, stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + 55
            report = None
            while process.poll() is None and time.monotonic() < deadline:
                if mode == 'upgrade' and request.exists() and not ready.exists():
                    sys.path.insert(0, str(ROOT / 'tools/five-pet'))
                    from bank_fixture import install
                    install(process, RUN / 'cgmsv.exe', json.loads(request.read_bytes().decode('gbk')))
                    ready.write_bytes(b'ready')
                if result.exists():
                    try:
                        report = json.loads(result.read_bytes().decode('gbk'))
                    except (UnicodeDecodeError, json.JSONDecodeError):
                        pass
                    else:
                        if report.get('status') != 'RUNNING':
                            break
                time.sleep(.2)
            assert report is not None, f'No report: exit={process.poll()}; see {log.name}'
            files = ('cgmsv.exe', 'lua/Modules/petSkillUpgrade.lua', 'lua/Modules/sanctuaryData.lua',
                     'lua/Modules/skillTrainingData.lua', 'lua/Modules/commandHelp.lua')
            report['tested_sha256'] = {rel: hashlib.sha256((RUN / rel).read_bytes()).hexdigest() for rel in files}
            result.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', 'utf-8')
            print(json.dumps({'status': report['status'], 'checks': len(report['checks']),
                              'error': report.get('error'), 'report': str(result)}, ensure_ascii=False))
            assert report['status'] == 'PASS', report.get('error')
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)


if __name__ == '__main__':
    assert len(sys.argv) <= 2 and (len(sys.argv) == 1 or sys.argv[1] in ('upgrade', 'help'))
    main(sys.argv[1] if len(sys.argv) == 2 else 'upgrade')
