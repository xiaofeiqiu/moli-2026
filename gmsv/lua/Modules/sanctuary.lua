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
function M:travel(npc,p)
 if not self:near(npc,p) then return false end
 local floor,point=1000,D.return_arrival
 if npc==self.entrance then floor,point=D.floor,D.arrival elseif npc~=self.exit then return false end
 if Map.IsWalkable(0,floor,point.x,point.y)~=1 then return false end
 if not Char.Warp(p,0,floor,point.x,point.y) then return false end
 if floor==D.floor then self:music(p);self.musicPlayed[p]=Char.GetUUID(p)
 else NLG.PlaySe(p,200,320,0);self.musicPlayed[p]=nil end
 return true
end
function M:stepOn(npc,p)
 -- PostOver belongs to the lower object (the stone), not the walking player.
 if npc~=self.entrance and npc~=self.exit then return false end
 if not self:near(npc,p) or get(p,'CHAR_X')~=get(npc,'CHAR_X') or get(p,'CHAR_Y')~=get(npc,'CHAR_Y') then return false end
 return self:travel(npc,p)
end
function M:onLoad()
 local w,h=Map.GetMapSize(0,D.floor)
 assert(w==100 and h==50,'Sanctuary map missing; restart the server after installing the map')
 NLG.SetMapName(0,D.floor,D.name..'|0')
 self.musicPlayed={}
 self.entrance=self:NPC_createNormal(D.entrance.name,103013,D.entrance)
 self.exit=self:NPC_createNormal(D.exit.name,103011,D.exit)
 assert(self.entrance>=0 and self.exit>=0,'Could not create sanctuary teleport stones')
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
 self:regCallback('LogoutEvent',function(p) self.musicPlayed[p]=nil;return 1 end)
end
function M:onUnload()
 if self.timer then self:RemoveTask(self.timer) end
end
return M
