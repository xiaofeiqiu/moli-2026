"""Read-only dependency report for source recovery and explicit custom repairs."""
import collections, json, re
from integrate_shared_tasks import OUT, DATA, STAGE, SOURCE, label, SPECS, decode_source
import audit_content as core

m=json.loads((OUT/'id_mapping.json').read_text(encoding='utf-8'))
missing=json.loads((OUT/'unresolved.json').read_text(encoding='utf-8'))
native=json.loads((OUT/'native_result.json').read_text(encoding='utf-8'))
defs=collections.defaultdict(dict)
tables={}
for e in m['entities']: defs[e['kind']][e['new_id']]=e
for kind,(key,*_) in SPECS.items():
 p=STAGE/'gmsv/data'/f'{kind}.txt'
 if not p.exists(): p=DATA/f'{kind}.txt'
 tables[kind]={int(c[key]):c for _,c in core.records(p.read_bytes()) if len(c)>key and core.number(c[key]) is not None}
names=collections.defaultdict(list)
for id,c in tables['enemybase'].items(): names[label(c[0]).strip()].append(id)
fails=[]
for f in native['failures']:
 if f['kind']=='enemy':
  e=defs['enemy'][f['id']]; c=tables['enemy'][f['id']]
  fails.append(dict(id=f['id'],name=label(c[0]),base=label(c[3]),ai=label(c[8]),templates=names[label(c[0]).strip()],source=e['path']))
 elif f['kind']=='group' and len([x for x in fails if 'members' in x])<12:
  c=tables['group'][f['id']]; e=defs['group'][f['id']]
  fails.append(dict(id=f['id'],name=label(c[0]),members=[label(x) for x in c[5:15]],missing=[label(x) for x in c[5:15] if core.number(x) and int(x)>0 and int(x) not in tables['enemy']],source=e['path']))
samples=collections.defaultdict(list)
seen=set()
for x in missing:
 key=(x['kind'],x.get('table'),x.get('id',x.get('floor',x.get('script'))))
 if key in seen: continue
 seen.add(key)
 cat=x['kind']+':'+str(x.get('table',''))
 if len(samples[cat])<15: samples[cat].append(x)
reward=[]
cached={}
for x in missing:
 if x['kind']=='unresolved_reference' and x['table']=='itemset':
  path,_,ln=x['context'].rpartition(':')
  p=__import__('pathlib').Path(path)
  if p.is_file() and ln.isdigit():
   if p not in cached: cached[p]=decode_source(p.read_bytes())[0].replace('\r\n','\n').replace('\r','\n').split('\n')
   lines=cached[p]
   if int(ln)>len(lines): continue
   line=lines[int(ln)-1].encode('gbk',errors='replace')
   if re.match(rb'\s*Give',line,re.I): reward.append(dict(**x,text=label(line)))
outside=[]
units=json.loads((OUT/'source_units.json').read_text(encoding='utf-8'))
roots=[__import__('pathlib').Path(u['root']) for u in units]
for p in SOURCE.rglob('*.txt'):
 if not any(p.is_relative_to(r) for r in roots):
  d=p.read_bytes()
  if re.search(rb'(?im)^\s*(Block|Window|Encount|Warp|GiveItem)\b',d): outside.append(str(p))
report={'native_failures':fails,'unresolved_samples':samples,'missing_rewards':reward,'unscanned_scripts':outside}
(OUT/'dependency_diagnostics.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'native_failures':len(native['failures']),'reward_count':len(reward),'unscanned_scripts':outside},ensure_ascii=False))
