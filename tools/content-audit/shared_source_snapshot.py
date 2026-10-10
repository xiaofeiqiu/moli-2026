"""A compact authoring snapshot; original files and production are read only."""
import json,collections,re
from integrate_shared_tasks import Builder,OUT,label,SPECS,save
b=Builder();b.scan()
missing=json.loads((OUT/'unresolved.json').read_text(encoding='utf-8'))
units={x['unit'] for x in missing}
snapshot=[]
for u in b.units:
 if u['id'] not in units:continue
 snapshot.append({'id':u['id'],'root':u['root'],'name':u['name'],
  'tables':{k:[{'path':r['path'],'line':r['line'],'c':[label(c) for c in r['columns']]} for r in rs] for k,rs in u['tables'].items()},
  'scripts':[{'name':s['name'] if 'name' in s else s['path'].rsplit('\\',1)[-1],'path':s['path'],'text':label(s['data'])} for s in u['scripts']]})
save(OUT/'source_authoring_snapshot.json',snapshot)
for u in b.units:
 if u['id'] not in {12,24,76,179,183,198,215,216,230,242,258,260}:continue
 print('UNIT',u['id'],u['root'])
 for k in ['group','skill','tech','itemrecipe','itemset']:
  rs=u['tables'].get(k,[])
  if k=='itemset': rs=[r for r in rs if re.search('证明|钥匙|笔记|戒指|项链|耳饰|龙骨|剑|星灵|线索|种植|通行|水晶|奖|奖品|晶石|情报|报告',label(r['columns'][1]))]
  print(k,[(label(r['columns'][0 if k in {'group','skill','tech','itemrecipe'} else 1]),label(r['columns'][SPECS[k][0]])) for r in rs][:80])
print('SNAPSHOT',len(snapshot))
