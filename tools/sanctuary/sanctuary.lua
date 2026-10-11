local M=ModuleBase:createModule('sanctuary')
local D=dofile('lua/Modules/sanctuaryData.lua')
local function get(p,k) return Char.GetData(p,CONST[k]) end
function M:near(npc,p)
 return Char.IsPlayer(p) and Char.GetBattleIndex(p)<0
  and get(p,'CHAR_地图类型')==get(npc,'CHAR_地图类型') and get(p,'CHAR_地图')==get(npc,'CHAR_地图')
  and math.abs(get(p,'CHAR_X')-get(npc,'CHAR_X'))<=2 and math.abs(get(p,'CHAR_Y')-get(npc,'CHAR_Y'))<=2
end
function M:music(p)
 -- Tone 230 is the client's existing looping PUK2 shrine track (bgm.cf).
 NLG.PlaySe(p,D.music,320,0)
end
function M:travel(npc,p,destination)
 if not self:near(npc,p) then return false end
 local floor,point,mapType,music=1000,D.return_arrival,0,200
 if npc==self.entrance then floor,point=D.floor,D.arrival
 elseif npc==self.training then
  if not destination then return false end
  floor,point,mapType,music=destination.map,destination,destination.mapType or 0,destination.music or 200
 elseif npc~=self.exit then return false end
 if Map.IsWalkable(mapType,floor,point.x,point.y)~=1 then return false end
 if not Char.Warp(p,mapType,floor,point.x,point.y) then return false end
 if floor==D.floor then self:music(p);self.musicPlayed[p]=Char.GetUUID(p)
 else NLG.PlaySe(p,music,320,0);self.musicPlayed[p]=nil end
 return true
end
function M:stepOn(npc,p)
 -- PostOver belongs to the lower object (the stone), not the walking player.
 if npc~=self.entrance and npc~=self.exit then return false end
 if not self:near(npc,p) or get(p,'CHAR_X')~=get(npc,'CHAR_X') or get(p,'CHAR_Y')~=get(npc,'CHAR_Y') then return false end
 return self:travel(npc,p)
end
-- Resolve random dungeons each time: generated floor IDs change on refresh.
function M:trainingDestination(entry)
 if not entry.dungeonId then return entry end
 local best,depth,area=nil,-1,-1
 for floor=0,self.dungeonLimit-1 do
  if Map.GetDungeonId(floor)==entry.dungeonId then
   local name=NLG.GetMapName(1,floor)
   local level=type(name)=='string' and tonumber(name:match('地下(%d+)楼'))
   local w,h=Map.GetMapSize(1,floor)
   if level and w and h and (level>depth or level==depth and w*h>area) then
    best,depth,area={mapType=1,map=floor,music=entry.music},level,w*h
   end
  end
 end
 if not best then return nil end
 local w,h=Map.GetMapSize(1,best.map)
 -- Avoid stairs, NPCs and other objects at the arrival tile.
 for y=1,h-2 do for x=1,w-2 do
  if Map.IsWalkable(1,best.map,x,y)==1 then
   local _,objects=Obj.GetObject(1,best.map,x,y)
   if not objects or #objects==0 then
    best.x,best.y=x,y;return best
   end
  end
 end end
 return nil
end
function M:trainingMenu(npc,p,page)
 self.trainingSessions[p]=nil
 if npc~=self.training or not self:near(npc,p) then return false end
 page=math.max(1,math.min(page or 1,math.max(1,math.ceil(#self.trainingCatalog/6))))
 local labels,actions={},{}
 for i=(page-1)*6+1,math.min(page*6,#self.trainingCatalog) do
  labels[#labels+1]=self.trainingCatalog[i].name
  actions[#actions+1]={destination=self.trainingCatalog[i]}
 end
 if page>1 then labels[#labels+1]='上一页';actions[#actions+1]={page=page-1} end
 if page*6<#self.trainingCatalog then labels[#labels+1]='下一页';actions[#actions+1]={page=page+1} end
 self.trainingSessions[p]={uuid=Char.GetUUID(p),at=os.time(),actions=actions}
 NLG.ShowWindowTalked(p,npc,2,2,7301,self:NPC_buildSelectionText('练级点传送（免费） '..page..'/'..math.max(1,math.ceil(#self.trainingCatalog/6)),labels))
 return true
end
function M:trainingAnswer(npc,p,seq,select,data)
 local session=self.trainingSessions[p]
 self.trainingSessions[p]=nil
 if not session or npc~=self.training or seq~=7301 or select~=0
  or session.uuid~=Char.GetUUID(p) or os.time()-session.at>120 or not self:near(npc,p) then return false end
 local choice=type(data)=='string' and data:match('^%d+$') and tonumber(data)
 local action=choice and session.actions[choice]
 if not action then return false end
 if action.page then return self:trainingMenu(npc,p,action.page) end
 local dest=self:trainingDestination(action.destination)
 if not dest then NLG.SystemMessage(p,'该练级地点暂不可用，请稍后重新选择。');return false end
 if not self:travel(npc,p,dest) then NLG.SystemMessage(p,'传送失败，请走近传送员后重新选择。');return false end
 return true
end
function M:onLoad()
 local w,h=Map.GetMapSize(0,D.floor)
 assert(w==100 and h==50,'Sanctuary map missing; restart the server after installing the map')
 NLG.SetMapName(0,D.floor,D.name..'|0')
 self.musicPlayed={};self.trainingSessions={};self.trainingCatalog=D.training_destinations
 local settings=assert(io.open('setup.cf','rb'));local config=settings:read('*a');settings:close()
 self.dungeonLimit=assert(tonumber(config:match('autodungeonnum=(%d+)')),'Missing random dungeon capacity')
 self.entrance=self:NPC_createNormal(D.entrance.name,103013,D.entrance)
 self.exit=self:NPC_createNormal(D.exit.name,103011,D.exit)
 assert(self.entrance>=0 and self.exit>=0,'Could not create sanctuary teleport stones')
 self.training=self:NPC_createNormal(D.training.name,100005,D.training)
 assert(self.training>=0,'Could not create sanctuary training guide')
 self:NPC_regTalkedEvent(self.training,function(n,p) return self:trainingMenu(n,p,1) end)
 self:NPC_regWindowTalkedEvent(self.training,Func.bind(self.trainingAnswer,self))
 local overFn=self:regCallback(self.name..'_stone_PostOverEvent',Func.bind(self.stepOn,self))
 for _,npc in ipairs({self.entrance,self.exit}) do
  self:NPC_regTalkedEvent(npc,Func.bind(self.travel,self))
  Char.SetPostOverEvent(nil,overFn,npc)
 end
 self.timer=self:AddInterval(1000,function()
  local present={}
  local players,list=NLG.GetMapPlayer(0,D.floor)
  if type(players)~='table' then players=list end
  for _,p in ipairs(type(players)=='table' and players or {}) do
   present[p]=true;local uid=Char.GetUUID(p)
   if self.musicPlayed[p]~=uid then self:music(p);self.musicPlayed[p]=uid end
  end
  for p in pairs(self.musicPlayed) do if not present[p] then self.musicPlayed[p]=nil end end
 end)
 self:regCallback('LogoutEvent',function(p) self.musicPlayed[p]=nil;self.trainingSessions[p]=nil;return 1 end)
end
function M:onUnload()
 if self.timer then self:RemoveTask(self.timer) end
end
return M
