"""Exercise staged custom scripts with an isolated dummy and a real native win."""
from validate_shared_tasks_native import RUN,OUT,start,stop,probe_config
import sys
stop()
probe=r'''local R={state='RUNNING',production_accounts_used=false,manifest_sha256=dofile('lua/shared_native_data.lua').manifest_sha256,cases={},events={}}
local path='../../../../../docs/cg71_content_audit/shared_integration/native_adapters_result.json'
local function write() local f=assert(io.open(path,'w'));f:write(JSON.encode(R));f:close() end
write()
local player,npc,m,config,originalConfig,phase
local function field(p,key) local k=assert(CONST[key],key);return Char.GetData(p,k) end
Cron.AddInterval(1000,function()
local ok,why=pcall(function()
 m=assert(loadModule('sharedTaskAdapters'),'adapter module failed')
 local D=dofile('lua/Modules/sharedTaskAdaptersData.lua');R.configurations=#D
 local reserved=Char.CreateDummy({mapType=0,floor=1000,x=150,y=112,image=100002,name='RESERVED_DUMMY_ZERO'})
 R.reserved=reserved
 player=Char.CreateDummy({mapType=0,floor=1000,x=150,y=111,image=100002,name='ADAPTER_VALIDATOR'})
 assert(player>=0,'dummy failed');R.player=player
 local originalMessage=NLG.SystemMessage
 NLG.SystemMessage=function(p,s) if p==player then R.messages=R.messages or {};R.messages[#R.messages+1]=s end;return originalMessage(p,s) end
 R.fixture={bagLimit=Char.GetData(player,CONST.CHAR_道具栏),skillLimit=Char.GetData(player,CONST.CHAR_技能栏),type=Char.GetData(player,CONST.CHAR_类型),itemIndex=Data.ItemsetGetIndex(18255)}
 Char.SetData(player,CONST.CHAR_道具栏,28)
 R.fixture.give=Char.GiveItem(player,18255,1,false);R.fixture.num=Char.ItemNum(player,18255)
 R.fixture.slot=Char.GetItemIndex(player,8);write()
 Char.SetData(player,CONST.CHAR_血,10000);Char.SetData(player,CONST.CHAR_最大血,10000)
 Char.SetData(player,CONST.CHAR_金币,1000000);Char.SetData(player,CONST.CHAR_等级,180)
 for _,field in ipairs({'CHAR_体力','CHAR_力量','CHAR_强度','CHAR_速度','CHAR_魔法'}) do Char.SetData(player,assert(CONST[field]),50000) end
 Char.UpCharStatus(player)
 R.inventory={};for s=8,30 do R.inventory[#R.inventory+1]={s,Char.GetItemIndex(player,s)} end
 for _,c in ipairs(D) do
  if c.kind=='exchange' and c.roles[1] then
   local r=c.roles[1];local x,y=Map.GetAvailablePos(r.mapType,r.floor)
   if x and x>=0 then
    Char.Warp(player,r.mapType,r.floor,x,y)
    local n=NL.CreateArgNpc('Event','',''..r.name,14058,r.mapType,r.floor,x,y,4)
    assert(n>=0,'fixture NPC failed')
    for _,i in ipairs(c.need or {}) do
     for j=1,i[2] do if Char.ItemNum(player,i[1])<i[2] then assert(Char.GiveItem(player,i[1],i[2]-Char.ItemNum(player,i[1]),false)>=0,'fixture item failed') end end
    end
    if c.needDone then Char.SetExtData(player,'sharedTasks:v1:'..c.needDone,1) end
    if not R.guards and #(c.give or {})>0 then
     Char.SetData(player,CONST.CHAR_X,x+10)
     assert(m:execute(n,player,c.key)==0,'remote exchange accepted')
     Char.Warp(player,r.mapType,r.floor,x,y)
     for fill=1,20 do local slot=Char.GetEmptyItemSlot(player);if slot<0 then break end;Char.GiveItem(player,1,1,false) end
     assert(m:execute(n,player,c.key)==0,'full-bag exchange accepted')
     for _,i in ipairs(c.need or {}) do assert(Char.ItemNum(player,i[1])>=i[2],'failed exchange consumed materials') end
     Char.DelItem(player,1,Char.ItemNum(player,1),false)
     R.guards={remote=true,full_bag=true,materials_preserved=true}
    end
    R.before={ready=m:requirements(player,c),counts={},bagLimit=Char.GetData(player,CONST.CHAR_道具栏)}
    for _,i in ipairs(c.need or {}) do R.before.counts[#R.before.counts+1]={i[1],Char.ItemNum(player,i[1])} end
    write()
    local result=m:execute(n,player,c.key)
    local ready,reason=m:requirements(player,c)
    local case={key=c.key,result=result,rewards={},ready=ready,reason=reason,allowed=m:allowed(n,player,c),config=c,playerFloor=field(player,'CHAR_地图'),npcFloor=field(n,'CHAR_地图'),npcName=field(n,'CHAR_名字'),claimed=Char.GetExtData(player,'sharedTasks:v1:'..c.key)}
    R.cases[#R.cases+1]=case;write()
    case.inventory={};for slot=8,27 do local item=Char.GetItemIndex(player,slot);case.inventory[#case.inventory+1]={slot,item,item>=0 and Item.GetData(item,CONST.道具_ID) or -1,item>=0 and Item.GetData(item,CONST.道具_堆叠数) or -1} end
    case.needCounts={};for _,i in ipairs(c.need or {}) do case.needCounts[#case.needCounts+1]={i[1],Char.ItemNum(player,i[1])} end;write()
    for _,i in ipairs(c.give or {}) do case.rewards[#case.rewards+1]=Char.ItemNum(player,i[1]);assert(Char.ItemNum(player,i[1])>=i[2],'exchange reward missing') end
    assert(result==1,'exchange rejected')
    if c.warp then assert(field(player,'CHAR_地图')==c.warp[2],'exchange transport failed');Char.Warp(player,r.mapType,r.floor,x,y) end
    if c.once then case.repeatResult=m:execute(n,player,c.key);assert(case.repeatResult==0,'repeat reward accepted') end
    for _,i in ipairs(c.give or {}) do Char.DelItem(player,i[1],Char.ItemNum(player,i[1]),false) end
    for _,i in ipairs(c.need or {}) do local q=Char.ItemNum(player,i[1]);if q>0 then Char.DelItem(player,i[1],q,false) end end
    NL.DelNpc(n)
   end
  end
 end
 -- Item mutation and predicate use the same native item field. This checks
 -- the translated first-slot enhancement, rather than just loading its Lua.
 local example
 for _,c in ipairs(D) do if c.kind=='legacy' and c.target=='item' and c.value~=nil and c.field=='道具_VAR1' and (#c.roles>0 or #c.useItems>0) then example=c;break end end
 if example then
  local use=example.useItems[1];if use then Char.GiveItem(player,use,1,false) end
  local n=-1
  if example.roles[1] then local r=example.roles[1];local x,y=Map.GetAvailablePos(r.mapType,r.floor);Char.Warp(player,r.mapType,r.floor,x,y);n=NL.CreateArgNpc('Event','',r.name,14058,r.mapType,r.floor,x,y,4) end
  if Char.GetItemIndex(player,8)<0 then Char.GiveItem(player,700075,1,false) end
  local item=Char.GetItemIndex(player,8);local old=Item.GetData(item,CONST.道具_VAR1)
  R.enhancement={result=m:execute(n,player,example.key),before=old,after=Item.GetData(item,CONST.道具_VAR1)}
  assert(R.enhancement.after==math.max(0,old)+example.value,'legacy equipment mutation failed')
  if n>=0 then NL.DelNpc(n) end
 end
 config=nil;for _,c in ipairs(D) do if c.kind=='battle' and c.cooldown and c.roles[1] then config=c;break end end
 originalConfig=config;phase='recovery'
 assert(config,'no actual battle interaction')
 local r=config.roles[1];local x,y=Map.GetAvailablePos(r.mapType,r.floor)
 Char.Warp(player,r.mapType,r.floor,x,y);npc=NL.CreateArgNpc('Event','',r.name,14058,r.mapType,r.floor,x,y,4)
  for _,i in ipairs(config.need or {}) do for j=1,i[2] do if Char.ItemNum(player,i[1])<i[2] then Char.GiveItem(player,i[1],i[2]-Char.ItemNum(player,i[1]),false) end end end
 if config.needDone then Char.SetExtData(player,'sharedTasks:v1:'..config.needDone,1) end
 local saved=m.won
 function m:won(b,p)
  R.events[#R.events+1]={event='win',battle=b,player=p,winSide=Battle.GetWinSide(b),pending=self.pending[b]~=nil,hp=field(p,'CHAR_血')}
  saved(self,b,p);write()
 end
 m.winFunction=m:regCallback('shared_task_win_probe',Func.bind(m.won,m))
 m:regCallback('AfterBattleTurnEvent',function(b)
  if config and b==R.battle.index then R.turns=(R.turns or 0)+1;R.lastTurn=Battle.GetTurn(b);write() end
 end)
 m:regCallback('BattleExitEvent',function(p,b,typ)
  if p==player or (R.battle and b==R.battle.index) then R.events[#R.events+1]={event='exit',player=p,battle=b,type=typ};write() end
 end)
 m:regCallback('BattleActionEvent',function(p,c1,c2,c3,n)
  if p==player then R.nativeActions=(R.nativeActions or 0)+1;write() end
 end)
 local started=m:execute(npc,player,config.key)
 R.battle={key=config.key,started=started,index=Char.GetBattleIndex(player),actions=0}
 R.battle.slots={};for s=0,19 do R.battle.slots[#R.battle.slots+1]=Battle.GetPlayer(R.battle.index,s) end
 assert(started==1 and R.battle.index>=0,'custom battle not started')
end)
if not ok then R.state='FAIL';R.exception=tostring(why);write();return end
local ticks=0
local function drive()
 ticks=ticks+1
 local ok,why=pcall(function()
  local b=Char.GetBattleIndex(player)
  R.currentBattle=b;R.ticks=ticks;R.currentMode=field(player,'CHAR_BattleMode');R.playerHP=field(player,'CHAR_血')
  if b>=0 then
   local target=10
   for s=19,10,-1 do local e=Battle.GetPlayer(b,s);if e>=0 and field(e,'CHAR_血')>0 then Char.SetData(e,CONST.CHAR_血,1);Char.SetData(e,CONST.CHAR_最大血,1);target=s end end
   Char.SetData(player,CONST.CHAR_血,1000000);Char.SetData(player,CONST.CHAR_最大血,1000000)
   Char.SetData(player,CONST.CHAR_攻击力,100000);Char.SetData(player,CONST.CHAR_命中,1000)
   local waiting=Battle.IsWaitingCommand(player);R.battle.waiting=waiting;R.battle.mode=field(player,'CHAR_BattleMode')
   if waiting==1 or waiting==true then
    local acted=Battle.ActionSelect(player,CONST.BATTLE_COM.BATTLE_COM_ATTACK,target,-1)
    if acted==1 or acted==true then R.battle.actions=R.battle.actions+1 end
    Battle.ActionSelect(player,CONST.BATTLE_COM.BATTLE_COM_ATTACK,target,-1)
   end
   -- A dummy has no client to acknowledge the turn animation or provide
   -- its second command slot. Supply both native command fields.
   Char.SetData(player,CONST.CHAR_BattleCom1,CONST.BATTLE_COM.BATTLE_COM_ATTACK)
   Char.SetData(player,CONST.CHAR_BattleCom2,target);Char.SetData(player,CONST.CHAR_BattleCom3,-1)
   Char.SetData(player,CONST.CHAR_Battle2Com1,CONST.BATTLE_COM.BATTLE_COM_GUARD)
   Char.SetData(player,CONST.CHAR_Battle2Com2,Battle.GetPos(b,player));Char.SetData(player,CONST.CHAR_Battle2Com3,7400)
   Char.SetData(player,CONST.CHAR_BattleMode,3)
   R.battle.commands= (R.battle.commands or 0)+1
  end
  local earned=(tonumber(Char.GetExtData(player,'sharedTasks:v1:'..config.key..(config.cooldown and ':claimed_at' or ''))) or 0)>0
  if earned then
   R.battle.victory=Char.GetExtData(player,'sharedTasks:v1:'..config.key..':victory');R.battle.rewards={}
   for _,r in ipairs(config.give or {}) do local qty=Char.ItemNum(player,r[1]);R.battle.rewards[#R.battle.rewards+1]=qty;assert(qty>=r[2],'native win reward missing') end
   assert(#R.events>0,'no native victory callback')
   if phase=='recovery' then
    assert(m:execute(npc,player,config.key)==0,'recovery cooldown bypassed');R.guards.cooldown=true
    R.recovery=R.battle
    config={key='stp:probe:three_rounds',kind='battle',once=true,roles=originalConfig.roles,give={{18255,1}},rounds={{{1,30}},{{1,30}},{{1,30}}}}
    phase='three_rounds';R.battle={key=config.key,index=-1,commands=0,actions=0}
    assert(m:startRound(player,npc,config,1)==1,'multi-round start failed');R.battle.index=Char.GetBattleIndex(player)
    Cron.AddInterval(200,drive,0);write();return
   end
   local wins=0;for _,event in ipairs(R.events) do if event.event=='win' then wins=wins+1 end end
   assert(wins>=4,'multi-round native victory sequence incomplete');R.three_rounds=true
   local previous=Char.ItemNum(player,originalConfig.give[1][1])
   Char.SetExtData(player,'sharedTasks:v1:'..originalConfig.key..':claimed_at',0)
   assert(m:execute(npc,player,originalConfig.key)==1,'exit fixture battle failed')
   local exited=Char.GetBattleIndex(player);Battle.ExitBattle(player)
   assert(m.pending[exited]==nil,'exit retained pending reward')
   assert(Char.ItemNum(player,originalConfig.give[1][1])==previous,'exit granted victory reward');R.guards.exit_no_reward=true
   R.state='PASS';if b>=0 then Battle.ExitBattle(player) end;Char.DelDummy(player);Char.DelDummy(R.reserved);NL.DelNpc(npc);write();return
  end
  if ticks>=300 then error('native battle did not produce an earned victory within 60 seconds') end
  Cron.AddInterval(200,drive,0);write()
 end)
 if not ok then R.state='FAIL';R.exception=tostring(why);write() end
end
Cron.AddInterval(1000,drive,0)
end,0)
'''
if '--battle-only' in sys.argv:
 probe=probe.replace("if c.kind=='exchange' and c.roles[1] then","if false then")
 probe=probe.replace("state='RUNNING',production_accounts_used=false", "scope='battle-only',state='RUNNING',production_accounts_used=false")
(RUN/'lua/shared_adapters_probe.lua').write_bytes(probe.encode('gbk'))
(RUN/'lua/ModuleConfig.lua').write_bytes(probe_config('shared_adapters_probe.lua'))
start()
