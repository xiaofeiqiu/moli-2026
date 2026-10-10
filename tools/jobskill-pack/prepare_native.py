"""Make an isolated server with its own SQLite database and staged DATA."""
import json
import re
import shutil
from pathlib import Path
from build_pack import ROOT, BATCH, STAGE, OUT

RUN = BATCH/'native_runtime/gmsv'
RUN.mkdir(parents=True,exist_ok=True)
for name in ['cgmsv.exe','setup.cf','cgmsv.cf']:
    if name=='cgmsv.exe' and (RUN/name).exists():
        assert (RUN/name).read_bytes()==(ROOT/'gmsv'/name).read_bytes(),'Isolated executable differs'
        continue
    shutil.copy2(ROOT/'gmsv'/name,RUN/name)
for name in ['lua','data']:
    shutil.copytree(ROOT/'gmsv'/name,RUN/name,dirs_exist_ok=True)
for name in ['store','log','Dengon','GMLog','dump','house']:
    (RUN/name).mkdir(exist_ok=True)
for p in (STAGE/'gmsv').rglob('*'):
    if p.is_file():
        dest=RUN/p.relative_to(STAGE/'gmsv');dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
setup=(RUN/'setup.cf').read_bytes()
setup=re.sub(rb'(?m)^port=\d+',b'port=19032',setup)
setup=re.sub(rb'(?m)^dummynum=\d+',b'dummynum=100',setup)
(RUN/'setup.cf').write_bytes(setup)
(RUN/'lua/ModuleConfig.lua').write_bytes(b"moduleInitial()\r\nloadModule('cg71JobSkills')\r\ndofile('lua/map_probe.lua')\r\ndofile('lua/native_probe.lua')\r\ndofile('lua/native_battle_probe.lua')\r\n")
(RUN/'lua/native_probe.lua').write_bytes((Path(__file__).parent/'native_probe.lua').read_text(encoding='utf-8').encode('gbk'))
(RUN/'lua/native_battle_probe.lua').write_bytes((Path(__file__).parent/'native_battle_probe.lua').read_text(encoding='utf-8').encode('gbk'))
(RUN/'lua/map_probe.lua').write_text("local cells={}\nfor y=105,115 do for x=148,160 do cells[#cells+1]={x=x,y=y,walk=Map.IsWalkable(0,1000,x,y)} end end\nlocal f=assert(io.open('../../../../docs/jobskill_pack/map_probe.json','w'));f:write(JSON.encode(cells));f:close()\n",encoding='ascii')
print(json.dumps({'runtime':str(RUN),'port':19032,'database':'new local data.db3; no production database copied'}))
