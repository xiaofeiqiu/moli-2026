-- Run after native maps, static NPCs, and all configured Lua modules have loaded.
local R={status='RUNNING',checks={},npcs={},overlaps={},production_accounts_used=false}
local modules={'cg71JobSkills','skillLibrary','fivePet','knightHybridGear','sharedTaskAdapters','sharedTaskRoutes','sharedTaskGuide','autoStat'}
local routeData=dofile('lua/Modules/sharedTaskRoutesData.lua')
local player=-1
local function get(c,key) return Char.GetData(c,CONST[key]) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function describe(c)
 return {index=c,name=get(c,'CHAR_名字'),mapType=get(c,'CHAR_地图类型'),floor=get(c,'CHAR_地图'),x=get(c,'CHAR_X'),y=get(c,'CHAR_Y')}
end
local function at(mt,floor,x,y)
 local list={};local _,objects=Obj.GetObject(mt,floor,x,y)
 for _,obj in ipairs(objects or {}) do
  if Obj.GetType(obj)==1 then
   local c=Obj.GetCharIndex(obj)
   -- Native shops use a different character type from normal Lua NPCs.
   if c>=0 and Char.IsValidCharIndex(c) and not Char.IsPlayer(c) and not Char.IsPet(c) and not Char.IsEnemy(c) then list[#list+1]=describe(c) end
  end
 end
 return list
end
local function inspect(phase)
  R.npcs={};R.overlaps={}
  for _,name in ipairs(modules) do
   local M=getModule(name)
   check(M~=nil,'configured module loaded: '..name)
   check(M and M.npcList and #M.npcList>0,'module owns NPCs: '..name)
   for _,c in ipairs(M and M.npcList or {}) do
    local row=describe(c);row.module=name
    row.walkable=Map.IsWalkable(row.mapType,row.floor,row.x,row.y)
    row.occupants=at(row.mapType,row.floor,row.x,row.y)
    row.approaches={}
    for dx=-1,1 do for dy=-1,1 do
     if dx~=0 or dy~=0 then
      local x,y=row.x+dx,row.y+dy
      if Map.IsWalkable(row.mapType,row.floor,x,y)==1 and #at(row.mapType,row.floor,x,y)==0 then row.approaches[#row.approaches+1]={x=x,y=y} end
     end
    end end
    check(row.walkable==1,'walkable NPC tile: '..name..'/'..row.name..'/'..row.floor..'/'..row.x..','..row.y)
    check(#row.occupants==1 and row.occupants[1].index==c,'no NPC overlap: '..name..'/'..row.name..'/'..row.floor..'/'..row.x..','..row.y)
    check(#row.approaches>0,'NPC can be approached: '..name..'/'..row.name..'/'..row.floor..'/'..row.x..','..row.y)
    if #row.occupants~=1 then R.overlaps[#R.overlaps+1]=row end
    if name=='sharedTaskRoutes' and c~=M.hub then
     for i,npc in pairs(M.npcs) do if npc==c then
      row.route=i;row.destinations={}
      for _,dest in ipairs(routeData[i].destinations) do row.destinations[#row.destinations+1]=dest.name..'（'..dest.floor..'）' end
      break
     end end
    end
    R.npcs[#R.npcs+1]=row
   end
  end
  check(#R.npcs==219,phase..': all 219 custom NPCs created')
end
local function finish(err)
 if err then R.status='FAIL';R.error=tostring(err) else R.status='PASS' end
 if player>=0 then pcall(Char.DelDummy,player);player=-1 end
 local f=assert(io.open('__OUTPUT__/current_npc_audit.json','wb'));f:write(JSON.encode(R));f:close()
end
Cron.AddInterval(1500,function()
 local ok,err=xpcall(function()
  inspect('startup')
  local routes=assert(getModule('sharedTaskRoutes'))
  player=Char.CreateDummy({mapType=0,floor=1000,x=153,y=114,image=100002,name='NPC_ROUTE_AUDIT'})
  check(player>=0,'isolated route interaction witness')
  for _,row in ipairs(R.npcs) do if row.module=='sharedTaskRoutes' then
   local position=row.approaches[1]
   check(Char.Warp(player,row.mapType,row.floor,position.x,position.y),'reach route NPC: '..row.floor..'/'..row.x..','..row.y)
   _G['sharedTaskRoutes_npc_'..row.index..'_TalkedEvent'](row.index,player)
   local session=routes.sessions[player]
   check(session and session.npc==row.index and #session.actions>0,'route NPC opens correct destination menu: '..row.index)
  end end
  Char.DelDummy(player);player=-1
  reloadModule('sharedTaskRoutes')
  reloadModule('sharedTaskAdapters')
  -- Reload again before the delayed spawn fires: the old task must cancel.
  reloadModule('sharedTaskRoutes')
  Cron.AddInterval(1500,function()
   local success,error=xpcall(function() inspect('reload') end,debug.traceback)
   finish(not success and error or nil)
  end,0)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
