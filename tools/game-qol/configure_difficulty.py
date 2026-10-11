"""Back up, natively verify, and install a moderate enemy challenge preset."""
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
import hashlib
import json
import re
import shutil
import sqlite3
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
CF = ROOT / 'gmsv/cgmsv.cf'
KEYS = ('enemyvitrate', 'enemystrrate', 'enemydefrate', 'enemyagirate', 'enemymagrate')
FACTORS = {0: Decimal('1.30'), 2: Decimal('1.20'), 3: Decimal('1.15'), 4: Decimal('1.10')}
OUT = ROOT / 'docs/game_difficulty'


def values(raw, key):
    matches = re.findall(rb'(?m)^' + key.encode() + rb'=([^\r\n]+)', raw)
    assert len(matches) == 1, key
    return matches[0]


def probe(run, config, name):
    (run / 'cgmsv.cf').write_bytes(config)
    report_path = OUT / (name + '.json')
    assert not report_path.exists(), 'Existing probe report: ' + str(report_path)
    source = (Path(__file__).parent / 'difficulty_probe.lua').read_text('utf-8')
    source = source.replace('__REPORT__', report_path.as_posix())
    (run / 'lua/difficulty_probe.lua').write_bytes(source.encode('gbk'))
    with (OUT / (name + '.log')).open('wb') as log:
        process = subprocess.Popen([str(run / 'cgmsv.exe')], cwd=run,
                                   stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + 55
            while process.poll() is None and time.monotonic() < deadline:
                if report_path.exists():
                    try:
                        report = json.loads(report_path.read_bytes().decode('gbk'))
                    except (UnicodeDecodeError, json.JSONDecodeError):
                        time.sleep(.1)
                        continue
                    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
                    assert report['status'] == 'PASS', report.get('error')
                    return report
                time.sleep(.2)
            raise RuntimeError(f'{name} did not finish; inspect {log.name}')
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    assert not (OUT / 'installed.json').exists(), 'Challenge already installed; restore before applying again'
    before = CF.read_bytes()
    after = before
    changes = {}
    for key in KEYS:
        old = values(before, key)
        parts = old.decode('ascii').split(',')
        assert len(parts) == 7, key
        for column, factor in FACTORS.items():
            parts[column] = format(Decimal(parts[column]) * factor, 'f').rstrip('0').rstrip('.')
        new = ','.join(parts).encode('ascii')
        after, count = re.subn(rb'(?m)^' + key.encode() + rb'=[^\r\n]+', key.encode() + b'=' + new, after)
        assert count == 1
        changes[key] = {'before': old.decode('ascii'), 'after': new.decode('ascii')}
    # Prove that all bytes outside these five numeric settings are preserved.
    strip = lambda raw: re.sub(rb'(?m)^(?:' + b'|'.join(k.encode() for k in KEYS) + rb')=[^\r\n]+', b'<enemy-coefficients>', raw)
    assert strip(before) == strip(after)
    batch = ROOT / ('backups/game_difficulty_' + datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_UTC'))
    batch.mkdir(parents=True)
    (batch / 'cgmsv.cf.before').write_bytes(before)
    (batch / 'cgmsv.cf.challenge').write_bytes(after)
    run = batch / 'native_runtime/gmsv'
    run.mkdir(parents=True)
    shutil.copy2(ROOT / 'gmsv/cgmsv.exe', run / 'cgmsv.exe')
    for name in ('data', 'lua'):
        shutil.copytree(ROOT / 'gmsv' / name, run / name)
    for name in ('store/itemcount', 'store/dungeon', 'log', 'Dengon', 'GMLog', 'dump', 'house'):
        (run / name).mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'gmsv/log/log.cf', run / 'log/log.cf')
    # Sanitized setup uses its own relative SQLite database and a separate port.
    setup = (ROOT / 'gmsv/setup.cf.example').read_bytes()
    for key, value in (('port', 19107), ('dbengine', 1), ('dummynum', 20)):
        setup, count = re.subn(rb'(?m)^' + key.encode() + rb'=\d+', f'{key}={value}'.encode(), setup)
        assert count == 1
    (run / 'setup.cf').write_bytes(setup)
    with sqlite3.connect(run / 'data.db3') as database:
        database.executescript((ROOT / 'gmsv/sql/sqlite.sql').read_text('utf-8'))
    (run / 'lua/ModuleConfig.lua').write_bytes(b"moduleInitial()\r\ndofile('lua/difficulty_probe.lua')\r\n")
    print(json.dumps({'phase': 'native baseline', 'backup': str(batch)}), flush=True)
    stamp = batch.name.removeprefix('game_difficulty_')
    baseline = probe(run, before, 'baseline_' + stamp)
    print(json.dumps({'phase': 'native challenge', 'baseline_enemies': len(baseline['enemies'])}), flush=True)
    challenge = probe(run, after, 'challenge_' + stamp)
    assert baseline['controls'] == challenge['controls'], 'Player/pet stat calculation changed'
    comparisons = []
    wanted = {'CHAR_最大血': 1.30, 'CHAR_攻击力': 1.20, 'CHAR_防御力': 1.15, 'CHAR_敏捷': 1.10}
    for old, new in zip(baseline['enemies'], challenge['enemies'], strict=True):
        assert (old['id'], old['level']) == (new['id'], new['level'])
        ratios = {}
        for stat, factor in wanted.items():
            a, b = old['normalized'][stat], new['normalized'][stat]
            assert b > a > 0, (stat, a, b)
            ratio = b / a
            assert abs(ratio - factor) < .035, (stat, ratio, factor)
            ratios[stat] = ratio
        for stat in ('CHAR_最大魔', 'CHAR_精神', 'CHAR_回复'):
            assert old['normalized'][stat] == new['normalized'][stat], stat
        comparisons.append({'id': old['id'], 'level': old['level'], 'ratios': ratios})
    assert len(comparisons) == 9
    assert CF.read_bytes() == before, 'Concurrent change in cgmsv.cf; installation aborted'
    CF.write_bytes(after)
    assert CF.read_bytes() == after
    restore = "$ErrorActionPreference = 'Stop'\n$challengePath = '" + CF.as_posix() + "'\n"
    restore += "$challengeEncoding = [System.Text.Encoding]::GetEncoding(28591)\n"
    restore += "$challengeText = $challengeEncoding.GetString([System.IO.File]::ReadAllBytes($challengePath))\n"
    for key, change in changes.items():
        restore += f"if ([regex]::Match($challengeText, '(?m)^{key}=([^\\r\\n]+)').Groups[1].Value -ne '{change['after']}') {{ throw 'Setting changed since installation: {key}' }}\n"
    for key, change in changes.items():
        restore += f"$challengeText = [regex]::Replace($challengeText, '(?m)^{key}=[^\\r\\n]+', '{key}={change['before']}')\n"
    restore += "[System.IO.File]::WriteAllBytes($challengePath,$challengeEncoding.GetBytes($challengeText))\nWrite-Output 'Enemy settings restored. Restart the game server to apply.'\n"
    (batch / 'RestoreDifficulty.ps1').write_text(restore, 'ascii')
    report = {'status': 'PASS', 'preset': 'moderate challenge', 'changes': changes,
              'native_enemy_cases': comparisons, 'player_pet_control_unchanged': True,
              'before_sha256': hashlib.sha256(before).hexdigest(), 'after_sha256': hashlib.sha256(after).hexdigest(),
              'backup': str(batch), 'restore_script': str(batch / 'RestoreDifficulty.ps1'),
              'requires_server_restart': True, 'production_database_modified': False}
    (OUT / 'installed.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
    print(json.dumps({'status': 'PASS', 'enemy_cases': len(comparisons), 'backup': str(batch), 'requires_server_restart': True}), flush=True)


if __name__ == '__main__':
    main()
