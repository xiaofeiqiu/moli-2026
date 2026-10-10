"""Refresh only owned staged Lua templates, retaining the live baseline guards."""
import json
from pathlib import Path
from integrate_shared_tasks import BATCH,STAGE,sha,save
m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'))
assert m['status']=='staged'
for name in ['sharedTaskAdapters','sharedTaskGuide','sharedTaskRoutes']:
 rel='gmsv/lua/Modules/'+name+'.lua';entry=m['files'][rel]
 target=STAGE/rel
 assert sha(target.read_bytes())==entry['after'],'stage changed unexpectedly: '+rel
 data=(Path(__file__).parent/'templates'/f'{name}.lua').read_text(encoding='utf-8').encode('gbk')
 target.write_bytes(data);entry['after']=sha(data);entry['bytes']=len(data)
save(BATCH/'manifest.json',m)
print('Refreshed staged Lua templates; native validations must be rerun.')
