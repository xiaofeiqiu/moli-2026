"""Stage numeric difficulty commands, verify in a disposable engine, then install."""
from datetime import datetime, timezone
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import sqlite3
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'docs/game_difficulty'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def manifest():
    return json.loads((OUT / 'command_staged.json').read_text('utf-8'))


def stage():
    assert not (OUT / 'command_installed.json').exists(), 'Command difficulty already installed'
    cf = (ROOT / 'gmsv/cgmsv.cf').read_bytes()
    base = cf
    prior_path = OUT / 'installed.json'
    if prior_path.exists():
        prior = json.loads(prior_path.read_text('utf-8'))
        if not prior.get('superseded_by'):
            for key, change in prior['changes'].items():
                current = re.findall(rb'(?m)^' + key.encode() + rb'=([^\r\n]+)', cf)
                assert current == [change['after'].encode()], 'Enemy coefficients changed concurrently: ' + key
                base, count = re.subn(rb'(?m)^' + key.encode() + rb'=[^\r\n]+', (key + '=' + change['before']).encode(), base)
                assert count == 1
    config = (ROOT / 'gmsv/lua/ModuleConfig.lua').read_bytes()
    if b"loadModule('gameDifficulty')" not in config:
        config = config.rstrip() + b"\r\n\r\nloadModule('gameDifficulty')\r\n"
    updates = {'gmsv/cgmsv.cf': base,
               'gmsv/lua/ModuleConfig.lua': config,
               'gmsv/lua/Modules/gameDifficulty.lua': (HERE / 'gameDifficulty.lua').read_text('utf-8').encode('gbk')}
    batch = ROOT / ('backups/game_difficulty_command_' + datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_UTC'))
    m = {'batch': str(batch), 'files': {}}
    for path, raw in updates.items():
        source = ROOT / path
        old = source.read_bytes() if source.exists() else None
        target = batch / 'staged' / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        if old is not None:
            backup = batch / 'before' / path
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_bytes(old)
        m['files'][path] = {'before': digest(old) if old is not None else None, 'after': digest(raw)}
    (OUT / 'command_staged.json').write_text(json.dumps(m, indent=2), 'utf-8')
    run = batch / 'native_runtime/gmsv'
    run.mkdir(parents=True)
    shutil.copy2(ROOT / 'gmsv/cgmsv.exe', run / 'cgmsv.exe')
    for name in ('data', 'lua'):
        shutil.copytree(ROOT / 'gmsv' / name, run / name)
    for name in ('store/itemcount', 'store/dungeon', 'log', 'Dengon', 'GMLog', 'dump', 'house'):
        (run / name).mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'gmsv/log/log.cf', run / 'log/log.cf')
    setup = (ROOT / 'gmsv/setup.cf.example').read_bytes()
    for key, value in (('port', 19108), ('dbengine', 1), ('dummynum', 100)):
        setup, count = re.subn(rb'(?m)^' + key.encode() + rb'=\d+', f'{key}={value}'.encode(), setup)
        assert count == 1
    (run / 'setup.cf').write_bytes(setup)
    with sqlite3.connect(run / 'data.db3') as db:
        db.executescript((ROOT / 'gmsv/sql/sqlite.sql').read_text('utf-8'))
    for path in updates:
        shutil.copy2(batch / 'staged' / path, run / path.removeprefix('gmsv/'))
    print(json.dumps({'staged': True, 'batch': str(batch)}), flush=True)


def test(name):
    m = manifest()
    run = Path(m['batch']) / 'native_runtime/gmsv'
    # Refresh other gameplay modules so concurrent installs are included in QA.
    shutil.copytree(ROOT / 'gmsv/lua', run / 'lua', dirs_exist_ok=True)
    for data in (ROOT / 'gmsv/data').iterdir():
        if data.is_file():
            shutil.copy2(data, run / 'data' / data.name)
    for path in m['files']:
        shutil.copy2(Path(m['batch']) / 'staged' / path, run / path.removeprefix('gmsv/'))
    # The disposable combat witness must attack rather than randomly flee.
    # Only its isolated enemy table is changed; production AI is untouched.
    enemy_lines = []
    witness_count = 0
    for line in (ROOT / 'gmsv/data/enemy.txt').read_bytes().splitlines(keepends=True):
        row = line.rstrip(b'\r\n').split(b'\t')
        if len(row) >= 3 and row[2] == b'1':
            row[1] = b'at:100;1;1'
            line = b'\t'.join(row) + (b'\r\n' if line.endswith(b'\r\n') else b'\n')
            witness_count += 1
        enemy_lines.append(line)
    assert witness_count == 1
    (run / 'data/enemy.txt').write_bytes(b''.join(enemy_lines))
    config = (run / 'lua/ModuleConfig.lua').read_bytes()
    # Keep all installed gameplay modules; omit unrelated login/admin/HTTP services.
    for module in ('admin', 'adminCommands', 'autoRegister', 'autoUnlock', 'loginGate', 'http', 'gameDifficulty'):
        config = re.sub(rb"(?m)^loadModule\('" + module.encode() + rb"'\)\r?\n?", b'', config)
    if name == 'restart':
        config += b"\r\nloadModule('gameDifficulty')\r\n"
    config += b"\r\ndofile('lua/difficulty_command_probe.lua')\r\n"
    (run / 'lua/ModuleConfig.lua').write_bytes(config)
    probe = HERE / ('difficulty_command_restart.lua' if name == 'restart' else 'difficulty_command_probe.lua')
    raw = probe.read_text('utf-8').replace('__OUTPUT__', OUT.as_posix())
    (run / 'lua/difficulty_command_probe.lua').write_bytes(raw.encode('gbk'))
    result = OUT / ('command_' + name + '.json')
    result.unlink(missing_ok=True)
    with (OUT / ('command_' + name + '.log')).open('wb') as log:
        process = subprocess.Popen([str(run / 'cgmsv.exe')], cwd=run, stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + 55
            while process.poll() is None and time.monotonic() < deadline:
                if result.exists():
                    try:
                        report = json.loads(result.read_bytes().decode('gbk'))
                    except (UnicodeDecodeError, json.JSONDecodeError):
                        time.sleep(.1)
                        continue
                    if report['status'] != 'RUNNING':
                        report['module_sha256'] = digest((run / 'lua/Modules/gameDifficulty.lua').read_bytes())
                        report['config_sha256'] = digest((run / 'cgmsv.cf').read_bytes())
                        result.write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
                        assert report['status'] == 'PASS', report.get('error')
                        print(json.dumps({'probe': name, 'status': report['status'], 'checks': len(report['checks'])}), flush=True)
                        return
                time.sleep(.2)
            raise RuntimeError(f'{name} did not finish; inspect {log.name}')
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)


def install():
    m = manifest()
    batch = Path(m['batch'])
    for name in ('native', 'restart'):
        report = json.loads((OUT / ('command_' + name + '.json')).read_text('utf-8'))
        assert report['status'] == 'PASS' and all(c['pass'] for c in report['checks'])
        assert report['module_sha256'] == m['files']['gmsv/lua/Modules/gameDifficulty.lua']['after']
        assert report['config_sha256'] == m['files']['gmsv/cgmsv.cf']['after']
    assert digest((HERE / 'gameDifficulty.lua').read_text('utf-8').encode('gbk')) == m['files']['gmsv/lua/Modules/gameDifficulty.lua']['after']
    for path, hashes in m['files'].items():
        source = ROOT / path
        assert (digest(source.read_bytes()) if source.exists() else None) == hashes['before'], 'Concurrent change: ' + path
        assert digest((batch / 'staged' / path).read_bytes()) == hashes['after']
        if path != 'gmsv/lua/ModuleConfig.lua':
            assert digest((batch / 'native_runtime/gmsv' / path.removeprefix('gmsv/')).read_bytes()) == hashes['after']
    for path in m['files']:
        shutil.copy2(batch / 'staged' / path, ROOT / path)
    m.update(status='PASS', tiers=5, default_tier=2, scope='character; party follows leader',
             requires_server_restart=True, production_database_modified=False)
    (OUT / 'command_installed.json').write_text(json.dumps(m, indent=2), 'utf-8')
    prior_path = OUT / 'installed.json'
    if prior_path.exists():
        prior = json.loads(prior_path.read_text('utf-8'))
        prior['superseded_by'] = 'command_installed.json'
        prior_path.write_text(json.dumps(prior, ensure_ascii=False, indent=2), 'utf-8')
    print(json.dumps({'installed': True, 'tiers': 5, 'default_tier': 2, 'requires_server_restart': True}), flush=True)


def refresh():
    m = manifest()
    assert not (OUT / 'command_installed.json').exists(), 'Command difficulty already installed'
    config_path = 'gmsv/lua/ModuleConfig.lua'
    current = (ROOT / config_path).read_bytes()
    if digest(current) != m['files'][config_path]['before']:
        # Preserve both the initial snapshot and the latest pre-install loader.
        backup = Path(m['batch']) / 'before_latest' / config_path
        backup.parent.mkdir(parents=True, exist_ok=True)
        backup.write_bytes(current)
        updated = current
        if b"loadModule('gameDifficulty')" not in updated:
            updated = updated.rstrip() + b"\r\n\r\nloadModule('gameDifficulty')\r\n"
        (Path(m['batch']) / 'staged' / config_path).write_bytes(updated)
        m['files'][config_path] = {'before': digest(current), 'after': digest(updated),
                                  'before_backup': str(backup)}
    path = 'gmsv/lua/Modules/gameDifficulty.lua'
    raw = (HERE / 'gameDifficulty.lua').read_text('utf-8').encode('gbk')
    (Path(m['batch']) / 'staged' / path).write_bytes(raw)
    m['files'][path]['after'] = digest(raw)
    (OUT / 'command_staged.json').write_text(json.dumps(m, indent=2), 'utf-8')
    print('Staged module refreshed; native and restart probes must pass again')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['stage', 'refresh', 'native', 'restart', 'install'])
    action = parser.parse_args().action
    if action == 'stage':
        stage()
    elif action == 'refresh':
        refresh()
    elif action == 'install':
        install()
    else:
        test(action)
