import collections,json,struct
from integrate_shared_tasks import OUT,STAGE,DATA,label
known={int(c.split()[0]) for c in (DATA/'map/newmapset.txt').read_bytes().splitlines() if c.strip() and not c.lstrip().startswith(b'#')}
m=json.loads((OUT/'id_mapping.json').read_text(encoding='utf-8'))
r=json.loads((OUT/'native_result.json').read_text(encoding='utf-8'))
bad={x['id'] for x in r['failures'] if x['kind']=='map'}
for x in [m for m in m['maps'] if m['new_id'] in bad][:12]:
 d=(STAGE/'gmsv/data/map'/f'stp_{x["new_id"]}').read_bytes(); n=x['width']*x['height']
 planes=[struct.unpack_from('>'+str(n)+'H',d,44+2*n*i) for i in [0,1]]
 print(x['new_id'],x['name'],x['width'],x['height'],[collections.Counter(v for v in p if v not in known).most_common(5) for p in planes],x['source'])
