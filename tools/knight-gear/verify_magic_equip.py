"""Verify all shop items on seven magic swordsman jobs in an isolated native server."""
from pathlib import Path
import json
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
RUN = ROOT / 'backups/magic_equip_validation/native_runtime/gmsv'
OUT = ROOT / 'docs/knight_hybrid_gear/magic_equip_result.json'


def main():
    source = (ROOT / 'tools/knight-gear/knightHybridGear.lua').read_bytes().decode('utf-8')
    runtime = (ROOT / 'gmsv/lua/Modules/knightHybridGear.lua').read_bytes().decode('gbk')
    assert source == runtime, 'UTF-8/GBK module mismatch'
    RUN.mkdir(parents=True, exist_ok=True)
    for name in ('cgmsv.exe', 'setup.cf', 'cgmsv.cf'):
        shutil.copy2(ROOT / 'gmsv' / name, RUN / name)
    for name in ('lua', 'data'):
        shutil.copytree(ROOT / 'gmsv' / name, RUN / name, dirs_exist_ok=True)
    for name in ('store/itemcount', 'log', 'Dengon', 'GMLog', 'dump', 'house'):
        (RUN / name).mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'gmsv/log/log.cf', RUN / 'log/log.cf')
    setup = (RUN / 'setup.cf').read_bytes()
    for key, value in [('port', 19062), ('dummynum', 100), ('dbengine', 1)]:
        setup = re.sub(rb'(?m)^' + key.encode() + rb'=\d+', f'{key}={value}'.encode(), setup)
    (RUN / 'setup.cf').write_bytes(setup)
    (RUN / 'lua/ModuleConfig.lua').write_bytes(
        b"moduleInitial()\nloadModule('knightHybridGear')\ndofile('lua/magic_equip_probe.lua')\n")
    probe = (ROOT / 'tools/knight-gear/magic_equip_probe.lua').read_text('utf-8')
    (RUN / 'lua/magic_equip_probe.lua').write_bytes(probe.replace('__OUTPUT__', OUT.as_posix()).encode('gbk'))
    OUT.unlink(missing_ok=True)
    with (OUT.parent / 'magic_equip_native.log').open('wb') as log:
        process = subprocess.Popen([str(RUN / 'cgmsv.exe')], cwd=RUN, stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + 100
            while time.monotonic() < deadline and process.poll() is None:
                if OUT.exists():
                    try:
                        result = json.loads(OUT.read_bytes().decode('gbk'))
                    except (ValueError, UnicodeDecodeError):
                        time.sleep(.25)
                        continue
                    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', 'utf-8')
                    print(json.dumps(result, ensure_ascii=False))
                    assert result['status'] == 'PASS', result.get('error')
                    return
                time.sleep(.25)
            raise RuntimeError('Native probe did not finish; inspect magic_equip_native.log')
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)


if __name__ == '__main__':
    main()
