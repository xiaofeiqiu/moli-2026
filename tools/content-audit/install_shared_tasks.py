"""Hash-guarded installation and rollback of the validated shared content."""
import argparse,hashlib,json,os,shutil
from datetime import datetime,timezone
from pathlib import Path
from integrate_shared_tasks import ROOT,BATCH,STAGE,OUT,SPECS,core,sha,save
from validate_shared_tasks_native import fingerprint,RUN

def read_report(name):
 p=OUT/name
 try:return json.loads(p.read_text(encoding='utf-8'))
 except UnicodeDecodeError:return json.loads(p.read_text(encoding='gbk'))

def verify():
 m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'));failures=[]
 for rel,entry in m['files'].items():
  target=(ROOT/rel).resolve();assert target.is_relative_to(ROOT.resolve()),rel
  if sha((STAGE/rel).read_bytes())!=entry['after']:failures.append(dict(file=rel,reason='staged bytes changed'))
  before=sha(target.read_bytes()) if target.exists() else None
  if before!=entry['before']:failures.append(dict(file=rel,reason='live baseline changed; rebuild against latest live data'))
  if rel.startswith('gmsv/data/') and rel.endswith('.txt') and target.exists() and Path(rel).stem in SPECS:
   if not (STAGE/rel).read_bytes().startswith(target.read_bytes()):failures.append(dict(file=rel,reason='existing DATA prefix not retained'))
 for k,(idcol,width,*_) in SPECS.items():
  staged=STAGE/'gmsv/data'/f'{k}.txt';live=ROOT/'gmsv/data'/f'{k}.txt'
  if not staged.exists():continue
  old={core.number(c[idcol]) for _,c in core.records(live.read_bytes()) if len(c)>idcol} if live.exists() else set()
  ids=set()
  suffix=staged.read_bytes()[len(live.read_bytes()) if live.exists() else 0:]
  for ln,c in core.records(suffix):
   if len(c)<=idcol or core.number(c[idcol]) is None:continue
   id=int(c[idcol])
   if id in old or id in ids:failures.append(dict(table=k,id=id,reason='new ID collision'))
   ids.add(id)
 unresolved=read_report('unresolved.json')
 if unresolved:failures.append(dict(reason='unresolved dependencies',count=len(unresolved)))
 result=dict(state='PASS' if not failures else 'FAIL',manifest_sha256=fingerprint(),failures=failures,files=len(m['files']))
 save(OUT/'static_validation.json',result);print(json.dumps(result,ensure_ascii=False))
 return result

def apply():
 m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'))
 assert m['status']=='staged','batch already applied or not staged'
 result=verify();assert result['state']=='PASS','static validation failed'
 for name in ['native_result.json','native_guide_result.json','native_adapters_result.json','native_services_result.json','native_access_result.json']:
  r=read_report(name);assert r.get('state')=='PASS',(name,r.get('exception'),r.get('failures'))
  assert r.get('scope')!='battle-only','partial development probe cannot approve installation'
  assert r.get('manifest_sha256')==fingerprint(),name+' validates an older stage'
  if name=='native_access_result.json':assert not r.get('placements'),'unrepaired inaccessible NPCs'
 # Tests may change isolated launch settings, but cannot substitute another
 # DATA file or module and use its result to approve this staged payload.
 for rel,e in m['files'].items():
  if rel in {'gmsv/setup.cf','gmsv/lua/ModuleConfig.lua'}:continue
  p=RUN/Path(rel).relative_to('gmsv');assert p.exists() and sha(p.read_bytes())==e['after'],'tested runtime differs: '+rel
 backup=BATCH/'before-install';assert not backup.exists(),'backup already exists; inspect prior install state'
 backup.mkdir();done=[]
 save(backup/'manifest.json',m)
 try:
  # Back up all existing files before changing any of them.
  for rel,e in m['files'].items():
   p=ROOT/rel
   if p.exists():q=backup/rel;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
  for rel,e in m['files'].items():
   p=ROOT/rel;current=sha(p.read_bytes()) if p.exists() else None
   assert current==e['before'],'concurrent live edit: '+rel
   p.parent.mkdir(parents=True,exist_ok=True);temp=p.with_name(p.name+'.shared-install.tmp')
   shutil.copyfile(STAGE/rel,temp);os.replace(temp,p);done.append(rel)
  for rel,e in m['files'].items():assert sha((ROOT/rel).read_bytes())==e['after'],rel
 except Exception:
  for rel in reversed(done):
   p=ROOT/rel
   assert sha(p.read_bytes())==m['files'][rel]['after'],'concurrent change; cannot undo '+rel
   q=backup/rel
   if q.exists():shutil.copy2(q,p)
   else:p.unlink()
  raise
 m['status']='applied';m['applied_utc']=datetime.now(timezone.utc).isoformat();m['validated_manifest_sha256']=fingerprint()
 save(BATCH/'manifest.json',m)
 save(OUT/'installation.json',dict(state='APPLIED',files=len(done),manifest_sha256=m['validated_manifest_sha256'],backup=str(backup),production_runtime_restarted=False))
 print(json.dumps(dict(state='APPLIED',files=len(done),backup=str(backup))))

def rollback():
 m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'));assert m['status']=='applied'
 backup=BATCH/'before-install'
 for rel,e in m['files'].items():assert sha((ROOT/rel).read_bytes())==e['after'],'live file changed; manual merge required: '+rel
 for rel,e in m['files'].items():
  p=(ROOT/rel).resolve();assert p.is_relative_to(ROOT.resolve())
  q=backup/rel
  if q.exists():shutil.copy2(q,p)
  else:p.unlink()
 m['status']='rolled_back';save(BATCH/'manifest.json',m);print('ROLLED_BACK')

def verify_installed():
 m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'));assert m['status']=='applied'
 failures=[]
 for rel,e in m['files'].items():
  p=ROOT/rel
  if not p.exists() or sha(p.read_bytes())!=e['after']:failures.append(rel)
 report=dict(state='PASS' if not failures else 'FAIL',files=len(m['files']),manifest_sha256=m['validated_manifest_sha256'],failures=failures)
 save(OUT/'installed_validation.json',report);print(json.dumps(report))
 return report

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['verify','apply','rollback','verify-installed']);globals()[p.parse_args().mode.replace('-','_')]()
