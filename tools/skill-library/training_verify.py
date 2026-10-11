"""Verify installed tutors in an isolated native server and empty SQLite DB."""
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
HERE = Path(__file__).resolve().parent
RUN = ROOT / 'backups/skill_training_20261010/native_runtime/gmsv'
OUT = ROOT / 'docs/skill_training'


def copy_changed(source, dest):
    source, dest = Path(source), Path(dest)
    if not dest.exists() or source.stat().st_size != dest.stat().st_size or source.stat().st_mtime_ns != dest.stat().st_mtime_ns:
        shutil.copy2(source, dest)
    return str(dest)


def main(probe='training'):
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
    for key, val in (('port', 19210), ('dbengine', 1), ('dummynum', 100)):
        setup, count = re.subn(rb'(?m)^' + key.encode() + rb'=\d+', f'{key}={val}'.encode(), setup)
        assert count == 1, key
    (RUN / 'setup.cf').write_bytes(setup)
    # This fixed path is an isolated test database, never the player database.
    assert RUN.resolve().is_relative_to((ROOT / 'backups').resolve())
    (RUN / 'data.db3').unlink(missing_ok=True)
    with sqlite3.connect(RUN / 'data.db3') as db:
        db.executescript((ROOT / 'gmsv/sql/sqlite.sql').read_text('utf-8'))
    http = RUN / 'lua/Modules/http.lua'
    http.write_bytes(http.read_bytes().replace(b'Http.Start("0.0.0.0", 10086)', b'Http.Start("127.0.0.1", 19211)'))
    config = (ROOT / 'gmsv/lua/ModuleConfig.lua').read_bytes()
    (RUN / 'lua/ModuleConfig.lua').write_bytes(config + b"\r\ndofile('lua/skill_training_probe.lua')\r\n")
    result = OUT / ('native_result.json' if probe == 'training' else probe + '_native_result.json')
    result.unlink(missing_ok=True)
    probe_dir = ROOT / 'tools/five-pet' if probe == 'five_ai' else HERE
    source = (probe_dir / (probe + '_probe.lua')).read_text('utf-8').replace('__REPORT__', result.as_posix())
    (RUN / 'lua/skill_training_probe.lua').write_bytes(source.encode('gbk'))
    print('Loading complete server configuration on isolated ports 19210/19211.', flush=True)
    with result.with_suffix('.log').open('wb') as log:
        process_type = subprocess.Popen
        if probe == 'pet_qigong_battle':
            sys.path.insert(0, str(ROOT / 'tools/game-qol'))
            from native_battle_capture import captured_process_type
            process_type = captured_process_type(result, OUT / 'pet_qigong_capture_ack.json', RUN)
        process = process_type([str(RUN / 'cgmsv.exe')], cwd=RUN, stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + 55
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
                        if report.get('status') != 'RUNNING':
                            break
                time.sleep(.2)
            if report is None:
                raise RuntimeError(f'Native probe did not complete; exit={process.poll()}; see {log.name}')
            report['source_sha256'] = {'cgmsv.exe': hashlib.sha256((RUN / 'cgmsv.exe').read_bytes()).hexdigest()}
            for rel in ('lua/ModuleConfig.lua', 'lua/Modules/skillLibrary.lua', 'lua/Modules/skillTraining.lua', 'lua/Modules/skillTrainingData.lua', 'lua/Modules/petSkillTutor.lua', 'lua/Modules/sanctuaryData.lua', 'lua/Modules/jobTutorData.lua', 'data/map/60003_sanctuary',
                        'lua/libs/Module/Parts/Npc.lua', 'lua/Modules/fivePet.lua', 'lua/Modules/autoStat.lua',
                        'lua/Modules/cg71JobSkills.lua', 'lua/Modules/sharedTaskGuide.lua',
                        'lua/Modules/sharedTaskRoutes.lua', 'lua/Modules/sharedTaskAdapters.lua',
                        'data/skilllv.txt', 'data/tech.txt', 'lua/Modules/commandHelp.lua'):
                raw = (ROOT / 'gmsv' / rel).read_bytes()
                assert raw == (config if rel == 'lua/ModuleConfig.lua' else (RUN / rel).read_bytes()), rel
                report['source_sha256'][rel] = hashlib.sha256(raw).hexdigest()
            result.write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
            print(json.dumps({'status': report['status'], 'checks': len(report['checks']), 'npcs': len(report['npcs']),
                              'windows': report.get('windows'),
                              'error': report.get('error'), 'report': str(result)}, ensure_ascii=False))
            assert report['status'] == 'PASS', report.get('error')
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('probe', nargs='?', default='training', choices=('training', 'menus', 'magic_skills', 'magic_battle', 'pet_forget', 'separation', 'five_ai', 'pet_qigong', 'pet_qigong_battle'))
    args = parser.parse_args()
    main(args.probe)
