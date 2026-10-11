"""Exercise /help in a disposable native server without copying player data."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import time
import argparse
import sys
sys.stdout.reconfigure(encoding="utf-8")
from verify_help import verify

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE = ROOT / 'backups/command_help_20261010'
RUN = BASE / 'native_runtime/gmsv'


def main(probe_name='help'):
    global BASE, RUN
    if probe_name in ('fivepet_death', 'clock_full', 'difficulty6', 'fight_count'):
        BASE = ROOT / 'backups/fivepet_death_20261010'
        RUN = BASE / 'native_runtime/gmsv'
    verify()
    RUN.mkdir(parents=True, exist_ok=True)
    for rel in ('cgmsv.exe', 'setup.cf', 'cgmsv.cf', 'log/log.cf'):
        dest = RUN / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'gmsv' / rel, dest)
    for rel in ('lua', 'data'):
        def copy_changed(source, dest):
            source, dest = Path(source), Path(dest)
            if not dest.exists() or (source.stat().st_size, source.stat().st_mtime_ns) != \
                    (dest.stat().st_size, dest.stat().st_mtime_ns):
                shutil.copy2(source, dest)
            return str(dest)
        shutil.copytree(ROOT / 'gmsv' / rel, RUN / rel, dirs_exist_ok=True, copy_function=copy_changed)
    for rel in ('store/itemcount', 'store/dungeon', 'store/house', 'log', 'Dengon', 'GMLog', 'dump', 'house'):
        (RUN / rel).mkdir(parents=True, exist_ok=True)
    setup = (RUN / 'setup.cf').read_bytes()
    for key, value in (('port', 19074 if probe_name in ('fivepet_death', 'clock_full', 'difficulty6', 'fight_count') else 19073), ('dbengine', 1), ('dummynum', 100)):
        setup = re.sub(rb'(?m)^' + key.encode() + rb'=\d+', f'{key}={value}'.encode(), setup)
    (RUN / 'setup.cf').write_bytes(setup)
    config = (RUN / 'lua/ModuleConfig.lua').read_bytes()
    for module in ('autoRegister', 'loginGate', 'http'):
        config = re.sub(rb"(?m)^loadModule\('" + module.encode() + rb"'\)\r?\n?", b'', config)
    config += f"\ndofile('lua/{probe_name}_probe.lua')\n".encode('ascii')
    (RUN / 'lua/ModuleConfig.lua').write_bytes(config)
    source_name = 'test.lua' if probe_name == 'regression' else f'{probe_name}_probe.lua'
    source_path = ROOT / 'tools/five-pet/default_probe.lua' if probe_name == 'fivepet_default' else HERE / source_name
    if probe_name == 'fivepet_formation_lifecycle':
        source_path = ROOT / 'tools/five-pet/lifecycle_test.lua'
    if probe_name == 'fivepet_runtime':
        source_path = ROOT / 'tools/five-pet/runtime_probe.lua'
    if probe_name == 'fivepet_ai':
        source_path = ROOT / 'tools/five-pet/five_ai_probe.lua'
    if probe_name == 'fivepet_element':
        source_path = ROOT / 'tools/five-pet/element_probe.lua'
    probe = source_path.read_text('utf-8').replace('__OUTPUT__', BASE.as_posix())
    if probe_name == 'fivepet_formation_lifecycle':
        probe = probe.replace('lifecycle_result.json', 'fivepet_formation_lifecycle_native.json')
    if probe_name == 'regression':
        probe = probe.replace('test_result.json', 'regression_native.json')
    if probe_name == 'fivepet_ai':
        probe = probe.replace('__REPORT__', (BASE / 'fivepet_ai_native.json').as_posix())
    (RUN / f'lua/{probe_name}_probe.lua').write_bytes(probe.encode('gbk'))
    result = BASE / f'{probe_name}_native.json'
    result.unlink(missing_ok=True)
    process_type = subprocess.Popen
    if probe_name == 'pet_animation':
        from native_battle_capture import captured_process_type
        process_type = captured_process_type(result, BASE / 'pet_animation_capture_ack.json', RUN)
    with (BASE / f'{probe_name}_native.log').open('wb') as log:
        process = process_type([str(RUN / 'cgmsv.exe')], cwd=RUN, stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + 55
            report = None
            while process.poll() is None and time.monotonic() < deadline:
                if result.exists():
                    try:
                        report = json.loads(result.read_bytes().decode('gbk'))
                    except (UnicodeDecodeError, json.JSONDecodeError):
                        pass
                    else:
                        if report.get('status') != 'RUNNING':
                            break
                time.sleep(.2)
            assert report is not None, f'No probe report; exit={process.poll()}; see {log.name}'
            report['tested_sha256'] = {
                rel: hashlib.sha256((RUN / rel).read_bytes()).hexdigest()
                for rel in ('cgmsv.exe', 'lua/Modules/commandHelp.lua', 'lua/Modules/gameQoL.lua',
                            'lua/Modules/admin.lua', 'lua/Modules/adminCommands.lua', 'lua/Modules/fivePet.lua',
                            'lua/Modules/gameDifficulty.lua', 'lua/Modules/fight.lua')
            }
            result.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', 'utf-8')
            print(json.dumps({'status': report['status'], 'checks': len(report['checks']),
                              'error': report.get('error'), 'report': str(result)}, ensure_ascii=False))
            assert report['status'] == 'PASS', report.get('error')
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('probe', nargs='?', default='help', choices=('help', 'heal', 'after_battle', 'regression', 'fivepet_default', 'fivepet_partial', 'fivepet_formation_lifecycle', 'fivepet_runtime', 'fivepet_death', 'clock_full', 'difficulty6', 'fight_count', 'fivepet_ai', 'fivepet_element', 'loyalty', 'pet_obedience', 'pet_animation'))
    args = parser.parse_args()
    main(args.probe)
