"""Stage the opt-in five-pet module and make an isolated native test server."""
import json,re,shutil,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'backups/five_pet_feature_20261004'
RUN=BASE/'native_runtime/gmsv'
STAGE=BASE/'staged/gmsv'
OUT=ROOT/'docs/five_pet'
for p in (RUN,STAGE/'lua/Modules',OUT):p.mkdir(parents=True,exist_ok=True)
source=(ROOT/'tools/five-pet/fivePet.lua').read_text(encoding='utf-8')
(STAGE/'lua/Modules/fivePet.lua').write_bytes(source.encode('gbk'))
for name in ('cgmsv.exe','setup.cf','cgmsv.cf'):
 if name=='cgmsv.exe' and (RUN/name).exists():
  assert (RUN/name).read_bytes()==(ROOT/'gmsv'/name).read_bytes();continue
 shutil.copy2(ROOT/'gmsv'/name,RUN/name)
for name in ('lua','data'):shutil.copytree(ROOT/'gmsv'/name,RUN/name,dirs_exist_ok=True)
for name in ('store/itemcount','log','Dengon','GMLog','dump','house'):(RUN/name).mkdir(parents=True,exist_ok=True)
shutil.copy2(ROOT/'gmsv/log/log.cf',RUN/'log/log.cf')
shutil.copytree(STAGE,RUN,dirs_exist_ok=True)
cf=(RUN/'setup.cf').read_bytes()
for key,val in [('port',19035),('dummynum',100),('dbengine',1)]:
 cf=re.sub(rb'(?m)^'+key.encode()+rb'=\d+',(key+'='+str(val)).encode(),cf)
(RUN/'setup.cf').write_bytes(cf)
test='follow_test.lua' if '--follow' in sys.argv else ('movement_test.lua' if '--movement' in sys.argv else ('lifecycle_test.lua' if '--lifecycle' in sys.argv else 'native_test.lua'))
(RUN/'lua/ModuleConfig.lua').write_bytes(("moduleInitial()\r\nloadModule('cg71JobSkills')\r\nloadModule('fivePet')\r\ndofile('lua/five_pet_test.lua')\r\n").encode('ascii'))
probe=ROOT/'tools/five-pet'/test
if probe.exists():
 s=probe.read_text(encoding='utf-8').replace('__OUTPUT__',OUT.as_posix())
 (RUN/'lua/five_pet_test.lua').write_bytes(s.encode('gbk'))
print(json.dumps({'runtime':str(RUN),'stage':str(STAGE),'output':str(OUT),'port':19035}))
