"""Exercise automatic stat allocation against a private native CGMSV runtime."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding='utf-8')
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE = ROOT / 'backups/auto_stat_20261010'
RUN = BASE / 'native_runtime/gmsv'
OUT = ROOT / 'docs/auto_stat'


def copy_changed(source, dest):
    source, dest = Path(source), Path(dest)
    if not dest.exists() or (source.stat().st_size, source.stat().st_mtime_ns) != (dest.stat().st_size, dest.stat().st_mtime_ns):
        shutil.copy2(source, dest)
    return str(dest)


def prepare(name):
    OUT.mkdir(parents=True, exist_ok=True)
    RUN.mkdir(parents=True, exist_ok=True)
    for rel in ('cgmsv.exe', 'setup.cf', 'cgmsv.cf', 'log/log.cf'):
        dest = RUN / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'gmsv' / rel, dest)
    for rel in ('lua', 'data'):
        shutil.copytree(ROOT / 'gmsv' / rel, RUN / rel, dirs_exist_ok=True, copy_function=copy_changed)
    if name in ('auto_stat_explore', 'auto_stat_test'):
        for suffix in ('', '-wal', '-shm'):
            database = RUN / ('data.db3' + suffix)
            assert database.resolve().parent == RUN.resolve()
            database.unlink(missing_ok=True)
    for rel in ('store/itemcount', 'store/dungeon', 'store/house', 'log', 'Dengon', 'GMLog', 'dump', 'house'):
        (RUN / rel).mkdir(parents=True, exist_ok=True)
    setup = (RUN / 'setup.cf').read_bytes()
    for key, value in (('port', 19063), ('dbengine', 1), ('dummynum', 100)):
        setup = re.sub(rb'(?m)^' + key.encode() + rb'=\d+', f'{key}={value}'.encode(), setup)
    (RUN / 'setup.cf').write_bytes(setup)
    source = (HERE / (name + '.lua')).read_text('utf-8').replace('__OUTPUT__', OUT.as_posix())
    (RUN / 'lua/auto_stat_probe.lua').write_bytes(source.encode('gbk'))
    config = "moduleInitial()\n"
    if name != 'auto_stat_explore':
        config += "loadModule('cg71JobSkills')\nloadModule('skillLibrary')\nloadModule('fivePet')\nloadModule('fight')\nloadModule('knightHybridGear')\nloadModule('gameQoL')\nloadModule('autoStat')\n"
        (RUN / 'lua/Modules/autoStat.lua').write_bytes((HERE / 'autoStat.lua').read_text('utf-8').encode('gbk'))
    config += "dofile('lua/auto_stat_probe.lua')\n"
    (RUN / 'lua/ModuleConfig.lua').write_bytes(config.encode('ascii'))


def run(name):
    result = OUT / (name + '.json')
    result.unlink(missing_ok=True)
    with (OUT / (name + '.log')).open('wb') as log:
        process = subprocess.Popen([str(RUN / 'cgmsv.exe')], cwd=RUN,
                                   stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + 100
            report = None
            while time.monotonic() < deadline and process.poll() is None:
                if result.exists():
                    raw = result.read_bytes()
                    try:
                        try:
                            report = json.loads(raw.decode('utf-8'))
                        except UnicodeDecodeError:
                            report = json.loads(raw.decode('gbk'))
                    except json.JSONDecodeError:
                        pass
                    else:
                        break
                time.sleep(.25)
            if report is None:
                raise RuntimeError(f'No probe report; exit={process.poll()}; see {log.name}')
            result.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', 'utf-8')
            if name != 'auto_stat_explore':
                tested = hashlib.sha256((RUN / 'lua/Modules/autoStat.lua').read_bytes()).hexdigest()
                report['module_sha256'] = tested
                report['native_binary_sha256'] = hashlib.sha256((RUN / 'cgmsv.exe').read_bytes()).hexdigest()
                result.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', 'utf-8')
            print(json.dumps({'status': report['status'], 'checks': len(report.get('checks', [])),
                              'error': report.get('error'), 'report': str(result)}, ensure_ascii=False))
            if report['status'] != 'PASS':
                raise SystemExit(1)
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)


def install():
    source = (HERE / 'autoStat.lua').read_text('utf-8').encode('gbk')
    module_hash = hashlib.sha256(source).hexdigest()
    binary_hash = hashlib.sha256((ROOT / 'gmsv/cgmsv.exe').read_bytes()).hexdigest()
    total = 0
    for name in ('auto_stat_test', 'auto_stat_restart', 'auto_stat_battle'):
        report = json.loads((OUT / (name + '.json')).read_text('utf-8'))
        assert report['status'] == 'PASS' and all(c['pass'] for c in report['checks']), name
        assert report['module_sha256'] == module_hash, 'Untested module source: ' + name
        assert report['native_binary_sha256'] == binary_hash, 'Different server executable: ' + name
        total += len(report['checks'])
    config_path = ROOT / 'gmsv/lua/ModuleConfig.lua'
    config = config_path.read_bytes()
    if not re.search(rb"(?m)^\s*loadModule\(['\"]autoStat['\"]", config):
        config = config.rstrip(b'\r\n') + b"\r\n\r\nloadModule('autoStat')\r\n"
    files = {'lua/ModuleConfig.lua': config, 'lua/Modules/autoStat.lua': source}
    for rel in files:
        path = ROOT / 'gmsv' / rel
        backup = BASE / 'original/gmsv' / rel
        if path.exists() and not backup.exists():
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup)
    for rel, content in files.items():
        path = ROOT / 'gmsv' / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        assert path.read_bytes() == content
    metadata = {'installed': True, 'checks': total, 'position': {'floor': 1000, 'x': 223, 'y': 85},
                'module_sha256': module_hash, 'native_binary_sha256': binary_hash,
                'production_database_modified': False, 'client_verified': False,
                'backup': str(BASE / 'original/gmsv')}
    (OUT / 'installed.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    print(json.dumps(metadata, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('probe', choices=['auto_stat_explore', 'auto_stat_test', 'auto_stat_battle', 'auto_stat_restart', 'install'])
    args = parser.parse_args()
    if args.probe == 'install':
        install()
    else:
        prepare(args.probe)
        run(args.probe)
