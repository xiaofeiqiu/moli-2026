"""Collect the authored role of each genuinely missing script for adaptation."""
import collections,json,re
from pathlib import Path
from integrate_shared_tasks import OUT,SOURCE,source_bytes,label
missing=json.loads((OUT/'unresolved.json').read_text(encoding='utf-8'))
mapping=json.loads((OUT/'id_mapping.json').read_text(encoding='utf-8'))
by=collections.defaultdict(list)
cache={}
for e in missing:
 if e['kind']!='missing_script':continue
 ctx=e['context'];path,sep,n=ctx.rpartition(':');p=Path(path)
 if p not in cache and p.is_file():cache[p]=source_bytes(p,[]).splitlines()
 row=cache.get(p,[])
 line=row[int(n)-1] if n.isdigit() and int(n)<=len(row) else b''
 cols=line.split(b'\t')
 by[e['script']].append({'unit':e['unit'],'context':ctx,'text':label(line)[:450],
                        'npc':label(cols[1]) if len(cols)>=25 else None,
                        'floor':label(cols[8]) if len(cols)==25 else None})
out=[{'script':name,'roles':roles} for name,roles in by.items()]
(OUT/'missing_script_roles.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(out,ensure_ascii=False,indent=2))
