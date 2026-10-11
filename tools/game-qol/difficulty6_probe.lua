local R={status='RUNNING',checks={},production_database_modified=false}
local M=assert(getModule('gameDifficulty'));local actors={};local captured={};local original=NLG.SystemMessage
local T=ModuleBase:createModule('difficulty6Probe'):new();T:load();local raw={}
local function get(q,k) return Char.GetData(q,CONST[k]) end
local function set(q,k,v) Char.SetData(q,CONST[k],v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function round(v) return math.floor(v+0.5) end
local function snapshot(q) return {hp=get(q,'CHAR_最大血'),defense=get(q,'CHAR_防御力'),agility=get(q,'CHAR_敏捷')} end
local function send(p,msg) captured={};check(TalkEvent(p,msg,0,0,0)==0,'consumed '..msg);return table.concat(captured,'\n') end
local function leave(p) if Char.GetBattleIndex(p)>=0 then Battle.ExitBattle(p) end;set(p,'CHAR_BattleIndex',-1);set(p,'CHAR_BattleMode',0) end
NLG.SystemMessage=function(q,text,...) captured[#captured+1]=text;return original(q,text,...) end
T:regCallback('BattleStartEvent',OrderedCallback(function(b) raw[b]={};for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then raw[b][q]=snapshot(q) end end end,100))
local function dummy()
 local p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='DIFFICULTY6_TEST'});assert(p>=0);actors[#actors+1]=p
 set(p,'CHAR_等级',50);set(p,'CHAR_体力',50000);NLG.UpChar(p);set(p,'CHAR_血',get(p,'CHAR_最大血'));return p
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
 local p=dummy();local member=dummy()
 check(#M.tiers==6 and M:preference(p)==6,'six tiers and default 6')
 local text=send(p,'/difficulty');check(text:find('当前难度：6 深渊（下场 PvE）',1,true),'idle query shows numbered effective default')
 check(M:savePreference(p,5),'saved tier 5 fixture');reloadModule('gameDifficulty');M=assert(getModule('gameDifficulty'));check(M:preference(p)==5,'existing saved tier 5 preserved')
 for tier=1,6 do
  send(p,'/difficulty '..tier);check(M:preference(p)==tier,'tier selectable '..tier)
  check(send(p,'/difficulty'):find('当前难度：'..tier..' '..M.tiers[tier].name,1,true),'query reports selected tier '..tier)
  local b=Battle.PVE(p,p,nil,{1},{60},{0});check(b>=0,'native battle '..tier)
  local q=Battle.GetPlayer(b,10);check(q>=0,'enemy created '..tier)
  local base=raw[b] and raw[b][q] or snapshot(q)
  M:start(b);M:scan(b);local t=M.tiers[tier];local current=snapshot(q)
  check(current.hp==round(base.hp*t.hp) and current.defense==round(base.defense*t.defense) and current.agility==round(base.agility*t.agility),'native enemy multipliers '..tier)
  local damage=DamageCalculateEvent(q,p,100,100,b,CONST.BATTLE_COM.BATTLE_COM_ATTACK,0,0,0,0,0,0,0)
  check(damage==round(100*t.damage),'native damage multiplier '..tier)
  check(send(p,'/difficulty'):find('当前难度：'..tier..' '..t.name..'（本场战斗）',1,true),'query shows battle snapshot '..tier)
  send(p,'/difficulty 1');check(M.battles[b].tier==tier and M:preference(p)==tier,'switch rejected in battle '..tier)
  leave(p)
 end
 check(M.tiers[6].hp==6 and M.tiers[6].damage==4 and M.tiers[6].defense==4 and M.tiers[6].agility==1.5,'tier 6 exact multipliers including defense 4')
 for _,args in ipairs({'7','0','6 extra','6.0'}) do send(p,'/difficulty '..args);check(M:preference(p)==6,'invalid input preserves preference '..args) end
 send(member,'/难度 1');check(Char.JoinParty(member,p,true)==0,'party joined')
 check(send(member,'/difficulty'):find('当前难度：6 深渊（下场 PvE）',1,true),'member query follows leader')
 local b=Battle.PVE(p,p,nil,{1},{60},{0});check(b>=0,'party battle');M:start(b);M:scan(b)
 check(M.battles[b].tier==6,'party battle uses leader tier 6')
 M:savePreference(p,2)
 check(send(member,'/difficulty'):find('当前难度：6 深渊（本场战斗）',1,true),'current battle query uses snapshot despite different saved preference')
 reloadModule('gameDifficulty');M=assert(getModule('gameDifficulty'))
 check(send(member,'/difficulty'):find('当前难度：6 深渊（本场战斗）',1,true),'battle snapshot retained across reload')
 leave(p);leave(member);Char.LeaveParty(member);Char.LeaveParty(p)
 send(p,'/difficulty 6');check(send(p,'/DIFFICULTY'):find('当前难度：6 深渊',1,true),'uppercase query supported')
 check(send(member,'/难度'):find('当前难度：1 正常',1,true),'leaving party restores personal difficulty')
 local help=send(p,'/help difficulty');check(help:find('1~6',1,true) and help:find('默认 6 深渊',1,true) and help:find('防御×4',1,true),'help has range default and defense multiplier')
 R.status='PASS'
 end,debug.traceback)
 if not ok then R.status='FAIL';R.error=tostring(err) end
 NLG.SystemMessage=original
 for _,p in ipairs(actors) do pcall(leave,p);pcall(Char.LeaveParty,p);pcall(Char.DelDummy,p) end
 local f=assert(io.open('__OUTPUT__/difficulty6_native.json','wb'));f:write(JSON.encode(R));f:close()
end,0)
