"""Load and exercise the staged catalogue only in the isolated native runtime."""
import json
from validate_shared_tasks_native import RUN,OUT,start,stop,probe_config
stop()
probe=r'''local R={production_accounts_used=false,manifest_sha256=dofile('lua/shared_native_data.lua').manifest_sha256}
local path='../../../../../docs/cg71_content_audit/shared_integration/native_guide_result.json'
local function write() local f=assert(io.open(path,'w'));f:write(JSON.encode(R));f:close() end
local ok,why=pcall(function()
 local m=assert(loadModule('sharedTaskGuide'))
 R.npc=m.guide;assert(R.npc and R.npc>=0,'catalogue NPC did not load')
 local D=dofile('lua/Modules/sharedTaskGuideData.lua')
 R.catalogue=#D.tasks;R.badEntries={};R.walkable=Map.IsWalkable(0,1000,155,111)
 for i,t in ipairs(D.tasks) do
  if t.entry then
   local p=t.entry;local w,h=Map.GetMapSize(0,p.floor)
   if w<1 or p.x<0 or p.y<0 or p.x>=w or p.y>=h then R.badEntries[#R.badEntries+1]={task=i,name=t.name,entry=p,size={w,h}} end
  end
 end
 assert(#R.badEntries==0,'catalogue has invalid entry coordinates')
 local p=Char.CreateDummy({mapType=0,floor=1000,x=155,y=111,image=100002,name='CATALOGUE_VALIDATOR'})
 assert(p>=0,'dummy failed');R.dummy=p
 m:show(m.guide,p,1);R.menu=m.sessions[p] and #m.sessions[p].actions
 assert(R.menu and R.menu<=8,'catalogue pagination invalid')
 R.entryWarps=0;R.pages=0
 for page=1,math.ceil(#D.tasks/6) do
  m:show(m.guide,p,page);assert(#m.sessions[p].actions<=8,'catalogue page overflow');R.pages=R.pages+1
 end
 for i,t in ipairs(D.tasks) do
  Char.Warp(p,0,1000,155,111)
  for scenePage=1,math.max(1,math.ceil(#t.scenes/4)) do
   m:show(m.guide,p,math.ceil(i/6),i,scenePage)
   assert(m.sessions[p] and #m.sessions[p].actions<=8,'scene page overflow '..i)
  end
  if t.entry then
   m:show(m.guide,p,math.ceil(i/6),i,1)
   m:answer(m.guide,p,7291,0,'1')
   assert(Char.GetData(p,CONST.CHAR_地图)==t.entry.floor,'catalogue warp failed '..i)
   assert(math.abs(Char.GetData(p,CONST.CHAR_X)-t.entry.x)<=4 and math.abs(Char.GetData(p,CONST.CHAR_Y)-t.entry.y)<=4,'landing too far from NPC '..i)
   R.entryWarps=R.entryWarps+1
  end
 end
 Char.Warp(p,0,1000,155,111);m:show(m.guide,p,1)
 m:answer(m.guide,p,7291,0,'1')
 R.taskMenu=m.sessions[p] and #m.sessions[p].actions
 assert(R.taskMenu and R.taskMenu<=8,'task pagination invalid')
 local t=D.tasks[1]
 if t.entry then
  m:answer(m.guide,p,7291,0,'1')
  R.destination={floor=Char.GetData(p,CONST.CHAR_地图),x=Char.GetData(p,CONST.CHAR_X),y=Char.GetData(p,CONST.CHAR_Y)}
  assert(R.destination.floor==t.entry.floor,'entry warp failed')
 end
 R.cleaned=Char.DelDummy(p)
 local routes=assert(loadModule('sharedTaskRoutes'),'route module failed')
 local routeData=dofile('lua/Modules/sharedTaskRoutesData.lua')
 R.routePoints=#routeData;R.routeDestinations=0
 p=Char.CreateDummy({mapType=0,floor=1000,x=155,y=111,image=100002,name='ROUTE_VALIDATOR'})
 for i,c in ipairs(routeData) do
  local n=routes.npcs[i];assert(n and n>=0,'route NPC missing '..i)
  local floor=Char.GetData(n,CONST.CHAR_地图);local x=Char.GetData(n,CONST.CHAR_X);local y=Char.GetData(n,CONST.CHAR_Y)
  for j,d in ipairs(c.destinations) do
   Char.Warp(p,0,floor,x,y)
   routes:show(n,p,i,math.ceil(j/6))
   assert(routes.sessions[p] and #routes.sessions[p].actions<=8,'route menu overflow '..i)
   routes:answer(n,p,7293,0,tostring((j-1)%6+1))
   assert(Char.GetData(p,CONST.CHAR_地图)==d.floor,'route destination failed '..i..':'..j)
   R.routeDestinations=R.routeDestinations+1
  end
 end
 Char.DelDummy(p)
end)
R.state=ok and 'PASS' or 'FAIL';if not ok then R.exception=tostring(why) end;write()
'''
(RUN/'lua/shared_guide_probe.lua').write_bytes(probe.encode('gbk'))
(RUN/'lua/ModuleConfig.lua').write_bytes(probe_config('shared_guide_probe.lua'))
start()
