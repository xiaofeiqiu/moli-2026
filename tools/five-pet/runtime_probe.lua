local R={status='RUNNING',checks={},trace={},production_database_modified=false}
local M=assert(getModule('fivePet'))
local T=ModuleBase:createModule('fivepetRuntimeProbe'):new();T:load()
local p,pet,b=-1,-1,-1;local started=os.time();local rounds=0;local finished=false;local ticks=0
local enemyData,originalTactics
local function g(q,k) return Char.GetData(q,CONST[k]) end
local function s(q,k,v) return Char.SetData(q,CONST[k],v) end
local function write() local f=assert(io.open('__OUTPUT__/fivepet_runtime_native.json','wb'));f:write(JSON.encode(R));f:close() end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function finish(err)
 if finished then return end;finished=true;R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil;R.rounds=rounds
 if p>=0 then pcall(M.disable,M,p);pcall(Battle.ExitBattle,p);pcall(Char.DelDummy,p) end;write()
 if enemyData then Data.EnemySetData(enemyData,CONST.DATA_ENEMY_TACTICSOPTION,originalTactics) end
end
local function snap(label)
 local rows={};for pos=0,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then
  rows[#rows+1]={q=q,hp=g(q,'CHAR_血'),maxhp=g(q,'CHAR_最大血'),roster=pos,bid=Battle.GetPos(b,q),position=Battle.GetEntryData(b,q,CONST.BATTLE_ENTRY_POSITION),side=Battle.GetEntryData(b,q,CONST.BATTLE_ENTRY_SIDE),waiting=Battle.IsWaitingCommand(q),mode=g(q,'CHAR_BattleMode'),c1=g(q,'CHAR_BattleCom1'),c2=g(q,'CHAR_BattleCom2'),c3=g(q,'CHAR_BattleCom3')}
 end end;R.trace[#R.trace+1]={label=label,turn=Battle.GetTurn(b),rows=rows};write()
end
local preChecked=false
T:regCallback('BattleExitEvent',function(q,bi,kind)
 if bi==b then R.exits=R.exits or {};R.exits[#R.exits+1]={q=q,kind=kind,hp=g(q,'CHAR_血'),c1=g(q,'CHAR_BattleCom1')};write() end
end)
T:regCallback('BattleBeforeActionEvent',function(bi,q,extra)
 if bi==b then R.actions=R.actions or {};R.actions[#R.actions+1]={q=q,extra=tostring(extra),turn=Battle.GetTurn(bi),c1=g(q,'CHAR_BattleCom1'),hp=g(q,'CHAR_血')} end
 return 0
end)
T:regCallback('BattlePreEvent',OrderedCallback(function(bi)
 if not M.active[p] or Battle.GetPos(bi,p)<0 then return 0 end
 local position=Battle.GetEntryData(bi,pet,CONST.BATTLE_ENTRY_POSITION)
 check(Battle.GetPos(bi,p)==0 and Battle.GetPos(bi,pet)==5 and position==0,'fixed owner rear and main pet front before client packet')
 for i,row in ipairs(M.active[p].rows) do
  check(Battle.GetPos(bi,row.proxy)==5+i and Battle.GetEntryData(bi,row.proxy,CONST.BATTLE_ENTRY_POSITION)==0 and Battle.GetPlayer(bi,i)<0,'native front battle ID and no old rear battle ID before first client packet '..row.slot)
  check(Battle.GetPlayer(bi,Battle.GetPos(bi,row.proxy))==row.proxy,'native command ID matches roster before packet '..row.slot)
 end
 preChecked=true;return 0
end,-10000))
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b and Char.IsEnemy(q) then return 0 end;return rate end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi==b then local enemy=Battle.GetPlayer(bi,10);if enemy>=0 then
  s(enemy,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);s(enemy,'CHAR_BattleCom2',10);s(enemy,'CHAR_BattleCom3',7400)
  s(enemy,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_GUARD);s(enemy,'CHAR_Battle2Com2',10);s(enemy,'CHAR_Battle2Com3',7400)
 end end
 return false
end)
T:regCallback('DamageCalculateEvent',function(a,d,original,damage,bi) if bi==b then return 0 end;return damage end)
local attacks={};local beforeMP={}
T:regCallback('BeforeBattleTurnStartEvent',function(bi) if bi==b then for _,r in ipairs(M.active[p].rows) do beforeMP[r.proxy]=g(r.proxy,'CHAR_魔') end end end)
T:regCallback('DamageCalculateEvent',function(a,d,original,damage,bi)
 if bi==b and M.proxies[a] then local turn=Battle.GetTurn(bi);attacks[turn]=attacks[turn] or {};attacks[turn][a]=(attacks[turn][a] or 0)+1 end
 return damage
end)
T:regCallback('BattleDodgeRateEvent',function(bi,a,d,rate) if bi==b then return 0 end;return rate end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished then return end
 local success,error=xpcall(function()
  rounds=rounds+1;snap('turn '..rounds)
  local executed=attacks[Battle.GetTurn(bi)] or {}
  for i,row in ipairs(M.active[p].rows) do
   check(g(row.proxy,'CHAR_魔')==beforeMP[row.proxy]-10,'selected skill consumes MP once in turn '..rounds..':'..row.slot)
   check(executed[row.proxy]==1,'companion executes once in actual turn '..rounds..':'..row.slot)
   check(Battle.GetPos(bi,row.proxy)==5+i and Battle.GetPlayer(bi,5+i)==row.proxy and Battle.GetEntryData(bi,row.proxy,CONST.BATTLE_ENTRY_POSITION)==0,'native front battle ID survives turn '..rounds..':'..row.slot)
  end
  if rounds>=3 then check(preChecked,'formation applied before initial roster packet');finish() end
 end,debug.traceback)
 if not success then finish(error) end
end)
-- Wait for the server's native enemy/NPC initialization before creating a
-- multi-round battle. ModuleConfig itself runs before that initialization.
Cron.AddInterval(1800,function()
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='FIVEPET_RUNTIME_TEST'});assert(p>=0)
 s(p,'CHAR_账号','FIVEPET_RUNTIME_TEST');s(p,'CHAR_等级',50);s(p,'CHAR_体力',50000);NLG.UpChar(p);s(p,'CHAR_血',g(p,'CHAR_最大血'))
 for slot=0,4 do local q=Char.GivePet(p,3004,1);assert(q>=0);s(q,'CHAR_血',g(q,'CHAR_最大血'));if slot==0 then pet=q end end
 assert(Char.SetPetDepartureState(p,0,2)==1);assert(M:enable(p))
 -- Use a non-fleeing boss fixture so an enemy escape cannot end the battle
 -- before the three-round assertion. Change only this process's in-memory data.
 local ix=Data.EnemyGetDataIndex(1);local boss=Data.EnemyGetData(ix,CONST.DATA_ENEMY_BOSS_FLG)
 enemyData=ix;originalTactics=Data.EnemyGetData(ix,CONST.DATA_ENEMY_TACTICSOPTION)
 Data.EnemySetData(ix,CONST.DATA_ENEMY_TACTICSOPTION,'gu:1')
 Data.EnemySetData(ix,CONST.DATA_ENEMY_BOSS_FLG,1)
 b=Battle.PVE(p,p,nil,{1},{100},{0});Data.EnemySetData(ix,CONST.DATA_ENEMY_BOSS_FLG,boss);assert(b>=0)
 -- Keep the foe alive through all three rounds even if another loaded damage
 -- callback applies a minimum after this fixture's zero-damage hook.
 for _,r in ipairs(M.active[p].rows) do assert(Pet.AddSkill(r.pet,1930)==1);s(r.pet,'CHAR_魔',g(r.pet,'CHAR_最大魔'));s(r.proxy,'CHAR_魔',g(r.pet,'CHAR_最大魔'));M:saveAI(p,r.pet,{mode='skill',tech=1930,target='weak',threshold=30}) end
 snap('initial')
 T:AddInterval(100,function()
  if finished then return end
  local success,error=xpcall(function()
   if os.time()-started>20 then error('native five-pet battle timeout') end
   if Battle.IsWaitingCommand(p)==1 then
    s(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);s(p,'CHAR_BattleCom2',-1);s(p,'CHAR_BattleCom3',7400)
    s(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);s(p,'CHAR_Battle2Com2',-1);s(p,'CHAR_Battle2Com3',-1);s(p,'CHAR_BattleMode',3)
   end
   if Battle.IsWaitingCommand(pet)==1 then Battle.ActionSelect(pet,CONST.BATTLE_COM.BATTLE_COM_ATTACK,10,-1) end
   M:tick();ticks=ticks+1;if ticks<=3 or ticks%40==0 then snap('tick '..ticks) end
  end,debug.traceback)
  if not success then finish(error) end
 end,1)
end,debug.traceback)
if not ok then finish(err) end
end,0)
