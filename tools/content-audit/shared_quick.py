"""Focused inspection of missing source resources."""
import json,collections
from integrate_shared_tasks import *
import audit_content as core
m=json.loads((OUT/'id_mapping.json').read_text(encoding='utf-8'))
u=json.loads((OUT/'unresolved.json').read_text(encoding='utf-8'))
tables={}
for kind,(key,*_) in SPECS.items():
 p=STAGE/'gmsv/data'/f'{kind}.txt'
 if not p.exists(): p=DATA/f'{kind}.txt'
 tables[kind]={int(c[key]):c for _,c in core.records(p.read_bytes()) if len(c)>key and core.number(c[key]) is not None}
ids=sorted({x['id'] for x in u if x['kind']=='unresolved_reference' and x['table']=='enemy'})
print('MISSING_ENEMY',len(ids),'EXISTING_BASE_SAME_ID',sum(x in tables['enemybase'] for x in ids))
print('ENEMY_SAMPLE',[(x,label(tables['enemybase'][x][0]) if x in tables['enemybase'] else None) for x in ids[:45]])
for k in ['group','encount','enemyai','tech','skill','itemmaterial','itemrecipe','titlename']:
 x=[v for v in u if v['kind']=='unresolved_reference' and v['table']==k]
 print(k,len(x),json.dumps(x[:2],ensure_ascii=False))
print('BASES',[(id,label(tables['enemybase'][id][0])) for id in [601,602,603,604,312,331,276,330038,330044,330082,30829,900250] if id in tables['enemybase']])
for id in [330038,330044,330082]:
 if id in tables['enemybase']: print(id,[label(v) for v in tables['enemybase'][id]])
print('MISSING_SCRIPTS',json.dumps(sorted({x['script'] for x in u if x['kind']=='missing_script'}),ensure_ascii=False))
