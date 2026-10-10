"""Find native-unreachable imported NPC placements before installation."""
import json
from validate_shared_tasks_native import RUN,OUT,STAGE,start,stop,probe_config
from integrate_shared_tasks import DATA,core,label
stop()
mapping=json.loads((OUT/'id_mapping.json').read_text(encoding='utf-8'))
ids={e['new_id'] for e in mapping['entities'] if e['kind']=='npc'}
rows=[]
for _,c in core.records((STAGE/'gmsv/data/npc.txt').read_bytes()):
 if len(c)>=25 and core.number(c[3]) in ids and c[7]==b'0' and c[8] not in {b'0',b'777'} and all(core.number(c[i]) is not None for i in [8,9,10]) and [core.number(c[9]),core.number(c[10])]!=[0,0]:
  rows.append([int(c[3]),int(c[8]),int(c[9]),int(c[10]),label(c[1])])
def lua(v):
 if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
 if isinstance(v,int):return str(v)
 return '{'+','.join(lua(x) for x in v)+'}'
(RUN/'lua/shared_access_data.lua').write_bytes(('return '+lua(rows)).encode('gbk'))
probe=r'''local R={state='RUNNING',manifest_sha256=dofile('lua/shared_native_data.lua').manifest_sha256,production_accounts_used=false,checked=0,placements={},failures={}}
local path='../../../../../docs/cg71_content_audit/shared_integration/native_access_result.json'
local function write() local f=assert(io.open(path,'w'));f:write(JSON.encode(R));f:close() end
write()
Cron.AddInterval(1000,function()
 local ok,why=pcall(function()
  for _,c in ipairs(dofile('lua/shared_access_data.lua')) do
   R.checked=R.checked+1
   local nearby=false
   for dx=-3,3 do for dy=-3,3 do if Map.IsWalkable(0,c[2],c[3]+dx,c[4]+dy)==1 then nearby=true end end end
   if not nearby then
    local x,y
    for radius=4,64 do
     for dx=-radius,radius do for _,dy in ipairs({-radius,radius}) do
      if not x and Map.IsWalkable(0,c[2],c[3]+dx,c[4]+dy)==1 then x,y=c[3]+dx,c[4]+dy end
     end end
     for dy=-radius+1,radius-1 do for _,dx in ipairs({-radius,radius}) do
      if not x and Map.IsWalkable(0,c[2],c[3]+dx,c[4]+dy)==1 then x,y=c[3]+dx,c[4]+dy end
     end end
     if x then break end
    end
    if not x then x,y=Map.GetAvailablePos(0,c[2]) end
    if x and x>=0 and Map.IsWalkable(0,c[2],x,y)==1 then R.placements[#R.placements+1]={id=c[1],floor=c[2],before={c[3],c[4]},after={x,y},name=c[5]}
    else R.failures[#R.failures+1]=c end
   end
  end
 end)
 R.state=ok and #R.failures==0 and 'PASS' or 'FAIL';if not ok then R.exception=tostring(why) end;write()
end,0)
'''
(RUN/'lua/shared_access_probe.lua').write_bytes(probe.encode('gbk'))
(RUN/'lua/ModuleConfig.lua').write_bytes(probe_config('shared_access_probe.lua'))
start()
