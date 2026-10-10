"""Prepare an isolated native engine probe; never copy the player database."""
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUN = ROOT / 'backups/five_pet_probe_20261004/native_runtime/gmsv'
OUT = ROOT / 'docs/five_pet_probe'
RUN.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
for name in ('cgmsv.exe', 'setup.cf', 'cgmsv.cf'):
    if name == 'cgmsv.exe' and (RUN / name).exists():
        assert (ROOT / 'gmsv' / name).read_bytes() == (RUN / name).read_bytes()
        continue
    shutil.copy2(ROOT / 'gmsv' / name, RUN / name)
for name in ('lua', 'data'):
    shutil.copytree(ROOT / 'gmsv' / name, RUN / name, dirs_exist_ok=True)
for name in ('store', 'log', 'Dengon', 'GMLog', 'dump', 'house'):
    (RUN / name).mkdir(exist_ok=True)
shutil.copy2(ROOT / 'gmsv/log/log.cf', RUN / 'log/log.cf')
setup = (RUN / 'setup.cf').read_bytes()
for key, value in (('port', 19034), ('dummynum', 40), ('dbengine', 1)):
    setup = re.sub(rb'(?m)^' + key.encode() + rb'=\d+',
                   (key + '=' + str(value)).encode(), setup)
(RUN / 'setup.cf').write_bytes(setup)
(RUN / 'lua/ModuleConfig.lua').write_bytes(
    b"moduleInitial()\r\ndofile('lua/five_pet_probe.lua')\r\n")
source = (ROOT / 'tools/five-pet-probe/probe.lua').read_text(encoding='utf-8')
source = source.replace('__OUTPUT__', OUT.as_posix())
(RUN / 'lua/five_pet_probe.lua').write_bytes(source.encode('gbk'))
print(json.dumps({'runtime': str(RUN), 'port': 19034,
                  'output': str(OUT), 'production_modified': False}))
