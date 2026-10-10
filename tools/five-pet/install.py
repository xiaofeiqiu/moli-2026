"""Install only the verified, opt-in Lua feature, retaining original configuration."""
import hashlib,json,re,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'backups/five_pet_feature_20261004'
OUT=ROOT/'docs/five_pet'
STAGE=BASE/'staged/gmsv/lua/Modules/fivePet.lua'
RUN=BASE/'native_runtime/gmsv'
def read_report(name):
 b=(OUT/name).read_bytes()
 try:s=b.decode('utf-8')
 except UnicodeDecodeError:s=b.decode('gb18030')
 return json.loads(s)
report=read_report('native_result.json')
life=read_report('lifecycle_result.json')
follow=read_report('follow_result.json')
assert report['status']=='PASS' and life['status']=='PASS' and follow['status']=='PASS'
assert all(c['pass'] for c in report['checks']+life['checks']+follow['checks'])
assert STAGE.read_bytes()==(RUN/'lua/Modules/fivePet.lua').read_bytes()
assert (OUT/'native_result.json').stat().st_mtime>(RUN/'lua/Modules/fivePet.lua').stat().st_mtime
assert (OUT/'follow_result.json').stat().st_mtime>(ROOT/'tools/five-pet/fivePet.lua').stat().st_mtime
original=BASE/'original/gmsv'
for rel in ('setup.cf','lua/ModuleConfig.lua'):
 src=ROOT/'gmsv'/rel;dest=original/rel
 dest.parent.mkdir(parents=True,exist_ok=True)
 if not dest.exists():shutil.copy2(src,dest)
dest=ROOT/'gmsv/lua/Modules/fivePet.lua'
if dest.exists() and not (original/'lua/Modules/fivePet.lua').exists():
 (original/'lua/Modules').mkdir(parents=True,exist_ok=True)
 shutil.copy2(dest,original/'lua/Modules/fivePet.lua')
shutil.copy2(STAGE,dest)
config=ROOT/'gmsv/lua/ModuleConfig.lua'
cf=config.read_bytes()
if not re.search(rb"(?m)^\s*loadModule\(['\"]fivePet['\"]\)",cf):
 cf=cf.rstrip()+b"\r\n\r\nloadModule('fivePet')\r\n"
config.write_bytes(cf)
setup=ROOT/'gmsv/setup.cf';raw=setup.read_bytes()
m=re.search(rb'(?m)^dummynum=(\d+)',raw);assert m
capacity=max(100,int(m[1]))
raw=re.sub(rb'(?m)^dummynum=\d+',b'dummynum='+str(capacity).encode(),raw)
setup.write_bytes(raw)
manifest={'module_sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),
 'native_checks':len(report['checks']),'native_lifecycle_checks':len(life['checks']),
 'native_follow_checks':len(follow['checks']),'follow_fix_installed':True,
 'native_turns':report['turns'],'client_verified':False,'default_enabled':False,
 'npc':{'name':'五宠指挥官','map':1000,'x':151,'y':112},
 'dummy_capacity':capacity,'requires_server_restart':True,
 'database_modified_by_installer':False,'backup':str(original)}
(OUT/'installed.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
for name,r in [('native_result.json',report),('lifecycle_result.json',life),('follow_result.json',follow)]:
 shutil.copy2(OUT/name,OUT/(name+'.raw'))
 (OUT/name).write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(manifest,ensure_ascii=False))
