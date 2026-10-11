"""Run nine-pet tests in a fresh server checkout, never copying player stores."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import sqlite3
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'backups/nine_pet_20261011'
RUN = BASE / 'native_runtime/gmsv'


def main(probe_name='nine', five_pet_source=None, bank_count=4):
    global BASE, RUN
    if probe_name == 'single_action':
        BASE = ROOT / 'backups/single_action_20261011'
        RUN = BASE / 'native_runtime/gmsv'
    if probe_name == 'bank_exp':
        BASE = ROOT / 'backups/bank_pet_experience_20261011'
        RUN = BASE / 'native_runtime/gmsv'
    if probe_name == 'breed':
        BASE = ROOT / 'backups/pet_strengthening_20261011'
        RUN = BASE / 'native_runtime/gmsv'
    sys.stdout.reconfigure(encoding='utf-8')
    RUN.mkdir(parents=True, exist_ok=True)
    for rel in ('cgmsv.exe', 'setup.cf', 'cgmsv.cf', 'log/log.cf'):
        dest = RUN / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        if rel == 'cgmsv.exe' and dest.exists() and dest.read_bytes() == (ROOT / 'gmsv' / rel).read_bytes():
            continue
        shutil.copy2(ROOT / 'gmsv' / rel, dest)
    for rel in ('lua', 'data'):
        def copy_changed(source, destination):
            source, destination = Path(source), Path(destination)
            if not destination.exists() or (source.stat().st_size, source.stat().st_mtime_ns) != (destination.stat().st_size, destination.stat().st_mtime_ns):
                shutil.copy2(source, destination)
            return str(destination)
        shutil.copytree(ROOT / 'gmsv' / rel, RUN / rel, dirs_exist_ok=True, copy_function=copy_changed)
    for source_rel, runtime_rel in ((five_pet_source or 'tools/five-pet/fivePet.lua', 'lua/Modules/fivePet.lua'),
                                    ('tools/game-qol/gameQoL.lua', 'lua/Modules/gameQoL.lua')):
        source = (ROOT / source_rel).read_bytes().decode('utf-8')
        (RUN / runtime_rel).write_bytes(source.encode('gbk'))
    for rel in ('store/itemcount', 'store/dungeon', 'store/house', 'log', 'Dengon', 'GMLog', 'dump', 'house'):
        (RUN / rel).mkdir(parents=True, exist_ok=True)
    setup = (RUN / 'setup.cf').read_bytes()
    for key, value in (('port', 19097 if probe_name == 'breed' else 19089), ('dbengine', 1), ('dummynum', 100)):
        setup, count = re.subn(rb'(?m)^' + key.encode() + rb'=\d+', f'{key}={value}'.encode(), setup)
        assert count == 1, key
    (RUN / 'setup.cf').write_bytes(setup)
    assert RUN.resolve().is_relative_to((ROOT / 'backups').resolve())
    if not (RUN / 'data.db3').exists():
        with sqlite3.connect(RUN / 'data.db3') as db:
            db.executescript((ROOT / 'gmsv/sql/sqlite.sql').read_text('utf-8'))
    config = (RUN / 'lua/ModuleConfig.lua').read_bytes()
    for module in ('autoRegister', 'loginGate', 'http'):
        config = re.sub(rb"(?m)^loadModule\('" + module.encode() + rb"'\)\r?\n?", b'', config)
    config += b"\ndofile('lua/nine_pet_probe.lua')\n"
    (RUN / 'lua/ModuleConfig.lua').write_bytes(config)
    source_rel, result_name = {
        'nine': ('tools/five-pet/nine_pet_probe.lua', 'nine_pet_native.json'),
        'single_action': ('tools/five-pet/single_action_probe.lua', f'single_action_{bank_count}_native.json'),
        'bank_exp': ('tools/five-pet/bank_exp_probe.lua', 'bank_exp_native.json'),
        'help': ('tools/game-qol/help_probe.lua', 'help_native.json'),
        'smart_ai': ('tools/five-pet/smart_ai_probe.lua', 'smart_ai_native.json'),
        'strategy': ('tools/five-pet/strategy_probe.lua', 'strategy_native.json'),
        'adaptive': ('tools/five-pet/adaptive_probe.lua', 'adaptive_native.json'),
        'idle': ('tools/five-pet/idle_probe.lua', 'idle_native.json'),
        'breed': ('tools/five-pet/breed_probe.lua', 'breed_native.json'),
        'bank_ai': ('tools/five-pet/bank_ai_probe.lua', 'bank_ai_native.json'),
    }[probe_name]
    result = BASE / result_name
    probe = (ROOT / source_rel).read_text('utf-8').replace('__OUTPUT__', BASE.as_posix()).replace('__REPORT__', result.as_posix()).replace('__BANK_COUNT__', str(bank_count))
    (RUN / 'lua/nine_pet_probe.lua').write_bytes(probe.encode('gbk'))
    result.unlink(missing_ok=True)
    fixture_request = BASE / 'bank_fixture_request.json'
    fixture_ready = BASE / 'bank_fixture_ready'
    if probe_name in ('bank_exp', 'bank_ai', 'breed'):
        fixture_request.unlink(missing_ok=True)
        fixture_ready.unlink(missing_ok=True)
    process_type = subprocess.Popen
    if probe_name == 'bank_ai':
        sys.path.insert(0, str(ROOT / 'tools/game-qol'))
        from native_battle_capture import captured_process_type
        process_type = captured_process_type(result, BASE / 'bank_ai_capture_ack.json', RUN)
    with (BASE / (result.stem + '.log')).open('wb') as log:
        process = process_type([str(RUN / 'cgmsv.exe')], cwd=RUN, stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + (90 if probe_name == 'breed' else 45)
            report = None
            while process.poll() is None and time.monotonic() < deadline:
                if probe_name in ('bank_exp', 'bank_ai', 'breed') and fixture_request.exists() and not fixture_ready.exists():
                    from bank_fixture import install
                    fixture = json.loads(fixture_request.read_bytes().decode('gbk'))
                    install(process, RUN / 'cgmsv.exe', fixture)
                    fixture_ready.write_bytes(b'ready')
                if result.exists():
                    try:
                        report = json.loads(result.read_bytes().decode('gbk'))
                    except (UnicodeDecodeError, json.JSONDecodeError):
                        pass
                    else:
                        if report.get('status') != 'RUNNING':
                            break
                time.sleep(.2)
            assert report is not None, f'No report: exit={process.poll()}; log={log.name}'
            report['tested_sha256'] = {rel: hashlib.sha256((RUN / rel).read_bytes()).hexdigest()
                                      for rel in ('cgmsv.exe', 'lua/Modules/fivePet.lua', 'lua/Modules/autoStat.lua', 'lua/Modules/petSkillAI.lua', 'lua/Modules/gameQoL.lua', 'lua/Modules/commandHelp.lua')}
            result.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', 'utf-8')
            print(json.dumps({'status': report['status'], 'rounds': report.get('rounds'), 'checks': len(report['checks']), 'error': report.get('error'), 'report': str(result)}, ensure_ascii=False))
            assert report['status'] == 'PASS', report.get('error')
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('probe', nargs='?', default='nine', choices=('nine', 'bank_exp', 'help', 'smart_ai', 'strategy', 'adaptive', 'idle', 'bank_ai', 'breed', 'single_action'))
    args = parser.parse_args()
    if args.probe == 'single_action':
        reports = []
        for count in (4, 2, 0):
            main(args.probe, bank_count=count)
            reports.append(json.loads((BASE / f'single_action_{count}_native.json').read_text('utf-8')))
        summary = {'status': 'PASS', 'rounds': sum(r['rounds'] for r in reports),
                   'checks': [check for r in reports for check in r['checks']],
                   'production_database_modified': False, 'bank_lookup_injected': True,
                   'squads': dict(zip(('nine', 'seven', 'five'), reports))}
        (BASE / 'single_action_native.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    else:
        main(args.probe)
