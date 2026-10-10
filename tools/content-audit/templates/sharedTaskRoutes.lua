local M=ModuleBase:createModule('sharedTaskRoutes')
local D=dofile('lua/Modules/sharedTaskRoutesData.lua')
local function get(p,k) local f=assert(CONST[k],k);return Char.GetData(p,f) end
function M:near(n,p)
 return Char.IsPlayer(p) and Char.GetBattleIndex(p)<0 and get(p,'CHAR_地图类型')==0
 and get(n,'CHAR_地图')==get(p,'CHAR_地图') and math.abs(get(n,'CHAR_X')-get(p,'CHAR_X'))<=3 and math.abs(get(n,'CHAR_Y')-get(p,'CHAR_Y'))<=3
end
function M:show(n,p,index,page)
 if not self:near(n,p) then return end
 local c=D[index];local options,actions={},{};page=page or 1
 if index==0 then
  local first=(page-1)*5+1
  for i=first,math.min(first+4,#D) do
   options[#options+1]=D[i].destinations[1].name..'的通路';actions[#actions+1]={route=i}
  end
  if page>1 then options[#options+1]='上一页';actions[#actions+1]={cataloguePage=page-1} end
  if first+5<=#D then options[#options+1]='下一页';actions[#actions+1]={cataloguePage=page+1} end
  self.sessions[p]={npc=n,index=0,actions=actions,expires=os.time()+90}
  NLG.ShowWindowTalked(p,n,2,2,7293,self:NPC_buildSelectionText('共享通路目录',options));return
 end
 local first=(page-1)*6+1
 for i=first,math.min(first+5,#c.destinations) do
  local d=c.destinations[i];options[#options+1]=d.name..'（'..d.floor..'）';actions[#actions+1]={destination=d}
 end
 if page>1 then options[#options+1]='上一页';actions[#actions+1]={page=page-1} end
 if first+6<=#c.destinations then options[#options+1]='下一页';actions[#actions+1]={page=page+1} end
 self.sessions[p]={npc=n,index=index,actions=actions,expires=os.time()+90}
 NLG.ShowWindowTalked(p,n,2,2,7293,self:NPC_buildSelectionText('共享任务通路',options))
end
function M:answer(n,p,seq,button,text)
 local s=self.sessions[p];self.sessions[p]=nil
 if not s or s.npc~=n or seq~=7293 or s.expires<os.time() or not self:near(n,p) then return end
 local a=s.actions[tonumber(text) or 0];if not a then return end
 if a.route then self:show(n,p,a.route,1);return end
 if a.cataloguePage then self:show(n,p,0,a.cataloguePage);return end
 if a.page then self:show(n,p,s.index,a.page);return end
 if Char.PartyNum(p)>1 then NLG.SystemMessage(p,'请先解散队伍，再选择任务通路。');return end
 local d=a.destination;local x,y
 for radius=0,8 do
  for dx=-radius,radius do for dy=-radius,radius do
   if not x and Map.IsWalkable(0,d.floor,d.x+dx,d.y+dy)==1 then x,y=d.x+dx,d.y+dy end
  end end
  if x then break end
 end
 if not x then
  local a,b=Map.GetAvailablePos(0,d.floor)
  if a and a>=0 and Map.IsWalkable(0,d.floor,a,b)==1 then x,y=a,b end
 end
 if not x then NLG.SystemMessage(p,'该通路暂无安全落脚位置，请稍后再来。');return end
 Char.Warp(p,0,d.floor,x,y)
 if get(p,'CHAR_地图')==d.floor then NLG.SystemMessage(p,'已抵达 '..d.name..'。') end
end
local function vacant(floor,x,y)
 if Map.IsWalkable(0,floor,x,y)~=1 then return false end
 local _,objects=Obj.GetObject(0,floor,x,y)
 return not objects or #objects==0
end
local function accessible(floor,x,y)
 if not vacant(floor,x,y) then return false end
 for dx=-1,1 do for dy=-1,1 do
  if (dx~=0 or dy~=0) and vacant(floor,x+dx,y+dy) then return true end
 end end
 return false
end
function M:createRoutes()
 for i,c in ipairs(D) do
  local x,y
  for radius=1,8 do
   for dx=-radius,radius do for dy=-radius,radius do
    if not x and math.max(math.abs(dx),math.abs(dy))==radius and accessible(c.floor,c.x+dx,c.y+dy) then x,y=c.x+dx,c.y+dy end
   end end
   if x then break end
  end
  if not x then
   local a,b=Map.GetAvailablePos(0,c.floor)
   if a and a>=0 and accessible(c.floor,a,b) then x,y=a,b end
  end
  if x then
   local n=self:NPC_createNormal('共享通路',14058,{mapType=0,map=c.floor,x=x,y=y,direction=4})
   assert(n>=0,'shared route creation failed: '..i);self.npcs[i]=n
   self:NPC_regTalkedEvent(n,function(n,p) self:show(n,p,i,1) end)
   self:NPC_regWindowTalkedEvent(n,Func.bind(self.answer,self))
  else self.npcs[i]=self.hub;self.fallbacks[#self.fallbacks+1]=i end
 end
end
function M:onLoad()
 self.sessions={};self.npcs={};self.fallbacks={}
 self.hub=self:NPC_createNormal('共享通路向导',14058,{mapType=0,map=1000,x=155,y=114,direction=4})
 assert(self.hub>=0,'shared route catalogue creation failed')
 self:NPC_regTalkedEvent(self.hub,function(n,p) self:show(n,p,0,1) end)
 self:NPC_regWindowTalkedEvent(self.hub,Func.bind(self.answer,self))
 -- Static npc.txt objects are loaded after ModuleConfig.lua. Choose local route
 -- positions on the first native loop so both static and Lua NPCs are reserved.
 self:AddInterval(1000,function() self:createRoutes() end,0)
 self:regCallback('LogoutEvent',function(p) self.sessions[p]=nil end)
 self:logInfo('Loaded shared route selections: '..#D)
end
function M:onUnload() self.sessions={} end
return M
