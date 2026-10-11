-- Repair idle characters with an orphaned battle index. Active participants
-- and spectators keep their native state. Never calls Battle.ExitBattle.
local M=ModuleBase:createModule('battleState')
local native=Char.GetBattleIndex
local function get(p,k) return tonumber(Char.GetData(p,CONST[k])) or 0 end
function M:participant(p,b)
 for pos=0,19 do if Battle.GetPlayer(b,pos)==p then return true end end
 return false
end
function M:normalize(p)
 local b=native(p)
 if b<0 or not Char.IsPlayer(p) or self:participant(p,b) then self.pending[p]=nil;return b end
 local mode=get(p,'CHAR_BattleMode')
 if mode==0 then
  Char.SetData(p,CONST.CHAR_BattleIndex,-1);self.pending[p]=nil;return -1
 end
 -- An invalid native battle cannot have spectators. Wait for two observations
 -- to avoid changing a character during a battle initialization/exit.
 if Battle.GetPlayer(b,0)==-3 then
  local uid=Char.GetUUID(p);local s=self.pending[p]
  if s and s.uid==uid and s.b==b and s.mode==mode and os.time()-s.at>=3 then
   Char.SetData(p,CONST.CHAR_BattleIndex,-1)
   Char.SetData(p,CONST.CHAR_BattleMode,0)
   self.pending[p]=nil;NLG.UpChar(p);return -1
  end
  if not s or s.uid~=uid or s.b~=b or s.mode~=mode then self.pending[p]={uid=uid,b=b,mode=mode,at=os.time()} end
 else self.pending[p]=nil end
 return b
end
function M:onLoad()
 self.pending={}
 self.wrapper=function(p) return self:normalize(p) end
 Char.GetBattleIndex=self.wrapper
 self:regCallback('LoginEvent',function(p) self:normalize(p);return 1 end)
 self:regCallback('LogoutEvent',function(p) self.pending[p]=nil;return 1 end)
 self.timer=self:AddInterval(2000,function()
  local players,list=NLG.GetPlayer()
  if type(players)~='table' then players=list end
  if type(players)=='table' then for _,p in ipairs(players) do self:normalize(p) end end
 end)
end
function M:onUnload()
 if self.timer then self:RemoveTask(self.timer) end
 if Char.GetBattleIndex==self.wrapper then Char.GetBattleIndex=native end
end
return M
