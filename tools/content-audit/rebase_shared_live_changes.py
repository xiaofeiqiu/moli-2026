"""Preserve concurrent append-only item additions and current module configuration."""
import json
from integrate_shared_tasks import ROOT,BATCH,STAGE,OUT,core,sha,save
m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'));assert m['status']=='staged'
mapping=json.loads((OUT/'id_mapping.json').read_text(encoding='utf-8'))
newids={e['new_id'] for e in mapping['entities'] if e['kind']=='itemset'}
rel='gmsv/data/itemset.txt';entry=m['files'][rel];raw=(STAGE/rel).read_bytes();assert sha(raw)==entry['after']
offset=0;boundary=None
for line in raw.splitlines(keepends=True):
 c=line.rstrip(b'\r\n').split(b'\t')
 if len(c)>11 and core.number(c[11]) in newids:boundary=offset;break
 offset+=len(line)
assert boundary is not None
old=raw[:boundary];assert sha(old)==entry['before'],'cannot recover original item prefix'
live=(ROOT/rel).read_bytes();assert live.startswith(old),'concurrent item edits require manual review'
liveids={core.number(c[11]) for _,c in core.records(live) if len(c)>11};assert not liveids&newids,'new item ID collision'
data=live+(b'' if live.endswith(b'\n') else b'\r\n')+raw[boundary:]
(STAGE/rel).write_bytes(data);entry.update(before=sha(live),after=sha(data),bytes=len(data))
rel='gmsv/lua/ModuleConfig.lua';live=(ROOT/rel).read_bytes();data=live
for name in ['sharedTaskAdapters','sharedTaskRoutes','sharedTaskGuide']:
 line=("loadModule('"+name+"')").encode()
 if line not in data:data+=b'\r\n'+line+b'\r\n'
(STAGE/rel).write_bytes(data);m['files'][rel].update(before=sha(live),after=sha(data),bytes=len(data))
save(BATCH/'manifest.json',m)
save(OUT/'concurrent_rebase.json',dict(item_addition_bytes=len((ROOT/'gmsv/data/itemset.txt').read_bytes())-len(old),current_module_configuration_preserved=True))
print('Concurrent item additions and module configuration retained; rerun native validation.')
