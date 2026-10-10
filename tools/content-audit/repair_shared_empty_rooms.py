"""Repair imported empty mini-rooms proven entirely inaccessible by the engine."""
import json,struct
from integrate_shared_tasks import BATCH,OUT,STAGE,core,sha,save
from validate_shared_tasks_native import fingerprint
m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'));assert m['status']=='staged'
r=json.loads((OUT/'native_access_result.json').read_text(encoding='gbk'));assert r['manifest_sha256']==fingerprint()
mapping=json.loads((OUT/'id_mapping.json').read_text(encoding='utf-8'))
notes=json.loads((OUT/'source_repairs.json').read_text(encoding='utf-8'))
changed=[]
for floor in sorted({f[1] for f in r['failures']}):
 rel='gmsv/data/map/stp_'+str(floor);entry=m['files'][rel]
 assert entry['before'] is None,'cannot remodel existing map'
 p=STAGE/rel;raw=p.read_bytes();assert sha(raw)==entry['after']
 info=core.native_map(raw);assert info['variant']=='LS2MAP' and info['width']<=5 and info['height']<=5,'unexpected non-placeholder scene'
 count=info['width']*info['height'];data=raw[:44]+struct.pack('>'+str(count)+'H',*([1003]*count))+b'\0\0'*count
 p.write_bytes(data);entry['after']=sha(data);entry['bytes']=len(data)
 for v in mapping['maps']:
  if v['new_id']==floor:v['geometry']=sha(data[40:]);v['custom_empty_room_floor_repaired']=True
 notes.append(dict(kind='custom_native_empty_room_floor_repaired',floor=floor,width=info['width'],height=info['height'],before_sha256=sha(raw),after_sha256=sha(data),reason='Supplied miniature scene has no walkable tile; preserve dimensions and replace the empty ground with installed walkable tile 1003'))
 changed.append(floor)
save(BATCH/'manifest.json',m);save(OUT/'id_mapping.json',mapping);save(OUT/'source_repairs.json',notes)
print(json.dumps({'empty_scenes_repaired':changed}))
