"""Apply native placement evidence only to imported NPCs and their guide entries."""
import json
from integrate_shared_tasks import BATCH,OUT,STAGE,DATA,core,label,sha,save
from validate_shared_tasks_native import fingerprint
m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'));assert m['status']=='staged'
r=json.loads((OUT/'native_access_result.json').read_text(encoding='gbk'));assert r['state']=='PASS'
assert r['manifest_sha256']==fingerprint(),'native access report is stale'
fixes={f['id']:f for f in r['placements']};tasks=json.loads((OUT/'task_guide_catalog.json').read_text(encoding='utf-8'))
rel='gmsv/data/npc.txt';p=STAGE/rel;assert sha(p.read_bytes())==m['files'][rel]['after']
prefix=(DATA/'npc.txt').read_bytes();assert p.read_bytes().startswith(prefix)
rows=[];used=set()
for _,c in core.records(p.read_bytes()[len(prefix):]):
 if len(c)>=25 and core.number(c[3]) in fixes:
  f=fixes[int(c[3])];assert [int(c[9]),int(c[10])]==f['before'] and int(c[8])==f['floor']
  for pos in [9,11,13,15]:c[pos],c[pos+1]=[str(v).encode() for v in f['after']]
  used.add(int(c[3]))
  for t in tasks:
   e=t['entry']
   if e and e['floor']==f['floor'] and [e['x'],e['y']]==f['before'] and (e['name']==f['name'] or (not f['name'] and e['name']=='任务接待员')):
    e['x'],e['y']=f['after']
 rows.append(b'\t'.join(c))
assert used==set(fixes),'native repair NPC not found'
def lua(v):
 if v is None:return 'nil'
 if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
 if isinstance(v,int):return str(v)
 if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
 return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in v.items())+'}'
for rel,data in {
 'gmsv/data/npc.txt':prefix+(b'' if prefix.endswith(b'\n') else b'\r\n')+b'\r\n'.join(rows)+b'\r\n',
 'gmsv/lua/Modules/sharedTaskGuideData.lua':('return '+lua({'tasks':tasks})+'\n').encode('gbk',errors='replace')
}.items():
 (STAGE/rel).write_bytes(data);m['files'][rel]['after']=sha(data);m['files'][rel]['bytes']=len(data)
save(BATCH/'manifest.json',m);save(OUT/'task_guide_catalog.json',tasks)
save(OUT/'custom_native_npc_placements.json',r['placements'])
notes=json.loads((OUT/'source_repairs.json').read_text(encoding='utf-8'))
notes.extend(dict(kind='custom_native_unreachable_npc_placement',**f) for f in r['placements'])
save(OUT/'source_repairs.json',notes)
print(json.dumps({'native_npc_placements_repaired':len(used)}))
