"""Expose imported professions, recipes and otherwise unobtainable materials."""
import collections,re,json
from pathlib import Path

def build(b):
 from integrate_shared_tasks import OUT,label
 jobs=[]
 for (uid,family),new in sorted(b.job_families.items()):
  ranks=[]
  for rank in range(1,8):
   c=b.transformed.get(('jobs',new+rank))
   if c:ranks.append(dict(id=new+rank,name=label(c[0]),cost=int(c[4] or b'0'),fame=int(c[5] or b'0'),need=[[int(c[p]),int(c[33+p-6] or b'0')] for p in range(6,11) if c[p] and int(c[p])>0]))
  if ranks:jobs.append(dict(family=new,name=re.sub(r'(学徒|见习|传承者)$','',ranks[0]['name']),ranks=ranks))
 recipes=[]
 for e in b.entities['itemrecipe']:
  c=b.transformed.get(('itemrecipe',e['new_id']))
  if not c:continue
  levels=[]
  for t in b.entities['tech']:
   tc=t['columns']
   if t['units'][0]==e['units'][0] and tc[1]==b'TECH_MergeItem' and int(tc[5])==int(e['columns'][3]) and tc[13].isdigit() and tc[14].isdigit() and int(tc[13])<=e['old_id']<=int(tc[14]):levels.append(int(tc[6]))
  item=b.transformed.get(('itemset',int(c[2]))) or b.base['itemset'].get(int(c[2]))
  level=min(levels) if levels else max(1,min(15,int(item[24] or b'1') if item else 1))
  recipes.append(dict(id=e['new_id'],skill=int(c[3]),level=level))
 # Determine actual producers, including the weighted source reward syntax.
 produced=set()
 for u in b.units:
  for s in u['scripts']:
   for m in re.finditer(rb'(?im)^\s*Give(?:Stack|Time|Leak\d*)?Item\s+([^\r\n]+)',s['data']):
    raw=m[1];ids=[int(m[1])] if (m:=re.match(rb'(\d+)',raw)) else [int(n) for n in re.findall(rb'(\d+)%',raw)]
    for id in ids:
     for e in b.local.get((u['id'],'itemset',id),[]):produced.add(e['new_id'])
  for e in b.entities['enemy']:
   c=b.transformed.get(('enemy',e['new_id']),[])
   if c:produced.update(int(c[p]) for p in list(range(13,23))+list(range(33,38)) if c[p] and c[p].isdigit() and int(c[p])>0)
 produced.update(int(c[2]) for c in b.additions.get('itemrecipe',[]))
 materials=[]
 created=json.loads((OUT/'custom_generated_assets.json').read_text(encoding='utf-8'))
 custom={(r['root'],r['table'],r['id']) for r in created}
 for e in b.entities['itemset']:
  uid=e['units'][0]
  if (b.unit_by_id[uid]['root'],'itemset',e['old_id']) not in custom or e['new_id'] in produced:continue
  c=b.transformed[('itemset',e['new_id'])]
  if c[14]!=b'26':continue
  # The recovery board gives a named material after a real solo battle. It
  # does not sell story proofs or grant completion flags and quest titles.
  materials.append(dict(name=label(c[1])+'（'+Path(b.unit_by_id[uid]['root']).name[:10]+'）',key='stp:recover:'+str(e['new_id'])))
  b.custom_actions.append(dict(key=materials[-1]['key'],unit=uid,name=materials[-1]['name'],kind='battle',level=20,cooldown=300,nativeRoles=True,nativeEnemies=True,rounds=[[[1,30]]],give=[[e['old_id'],1]],roles=[dict(name='远征后勤官',floor=1000,mapType=0)]))
 data=dict(key='stp:services',unit=0,kind='services',roles=[],jobs=jobs,recipes=recipes,materials=materials)
 b.custom_actions.append(data)
 b.notes.append(dict(kind='custom_shared_services',professions=len(jobs),recipes=len(recipes),material_recovery_challenges=len(materials)))
 (OUT/'shared_services.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
