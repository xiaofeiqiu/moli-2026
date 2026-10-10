import json,re,collections
from integrate_shared_tasks import OUT,source_bytes,label
from pathlib import Path
m=json.loads((OUT/'id_mapping.json').read_text(encoding='utf-8'))
have=collections.defaultdict(set)
for e in m['entities']: have[e['kind']].add((e['units'][0],e['old_id']))
stats=collections.Counter();examples=collections.defaultdict(list)
for e in [e for e in m['entities'] if e['kind']=='npc']:
 p=Path(e['path'])
 if not p.is_file():continue
 # All file content is cached below for script references too.
data={}
paths={(e['units'][0],e['path']) for e in m['entities'] if e['kind']=='npc' and Path(e['path']).is_file()}
for unit,path in paths:
 raw=source_bytes(Path(path),[])
 for line in raw.splitlines():
  c=line.split(b'\t')
  if len(c)>=25 and c[0].lower()==b'standenemy':
   p=c[24].split(b'|')
   if len(p)>9 and p[9].isdigit():
    id=int(p[9]); key=(p[0].decode(),p[8].decode(),(unit,id) in have['group'],(unit,id) in have['encount']);stats[key]+=1
    if len(examples[key])<2:examples[key].append((id,path,label(c[24])))
print(dict(stats));print(json.dumps({str(k):v for k,v in examples.items()},ensure_ascii=False,indent=2))
