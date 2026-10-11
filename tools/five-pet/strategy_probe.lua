-- Actual nine-pet commands and damage, with disposable carried/bank fixtures only.
local R={status='RUNNING',checks={},actions={},effects={},production_database_modified=false}
local M=assert(getModule('fivePet'));local T=ModuleBase:createModule('strategyProbe'):new();T:load()
local p,bankOwner,b=-1,-1,-1;local bank={};local s;local round=1;local finished=false
local manualCommand,beforeMainMP
local originalPool=Char.GetPoolPet
Char.GetPoolPet=function(q,slot) if q==p then return bank[slot] or -1 end;return originalPool(q,slot) end
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function set(q,k,v) return Char.SetData(q,assert(CONST[k],k),v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function finish(err)
 if finished then return end;finished=true
 if p>=0 then pcall(Battle.ExitBattle,p);pcall(M.disable,M,p) end
 for _,q in ipairs({p,bankOwner}) do if q>=0 then
  for slot=0,4 do if Char.GetPet(q,slot)>=0 then pcall(Char.DelSlotPet,q,slot) end end;pcall(Char.DelDummy,q)
 end end
 Char.GetPoolPet=originalPool;R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end
local function flag(q,k,v) Battle.SetEntryData(b,q,CONST[k],v) end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b then return 0 end;return rate end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi,c1,c2,c3)
 if bi==b then R.effects[#R.effects+1]={round=round,a=a,d=d,original=ori,command=c1,tech=c3};return 0 end;return damage
end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi~=b then return false end
 -- Change the Boss's actual attack after pets were queued; recheck live state.
 local boss=Battle.GetPlayer(b,10)
 for pos=10,12 do set(Battle.GetPlayer(b,pos),'CHAR_攻击力',0) end
 set(boss,'CHAR_BattleCom1',round==2 and CONST.BATTLE_COM.BATTLE_COM_P_MAGIC or CONST.BATTLE_COM.BATTLE_COM_ATTACK)
 set(boss,'CHAR_BattleCom2',0);set(boss,'CHAR_BattleCom3',round==2 and 1930 or 7300)
 check((next(M:bossBlockers(b,p))~=nil)==(round~=2),'automatic tactic follows actual Boss reach this turn')
 return false
end)
T:regCallback('BattleBeforeActionEvent',function(bi,q)
 if bi==b and s and (M.proxies[q] or q==s.normal) and get(q,'CHAR_BattleCom3')>=0 then
  R.actions[#R.actions+1]={round=round,q=q,front=Battle.GetEntryData(b,q,CONST.BATTLE_ENTRY_POSITION)==0,
   command=get(q,'CHAR_BattleCom1'),target=get(q,'CHAR_BattleCom2'),tech=get(q,'CHAR_BattleCom3'),hp=get(q,'CHAR_血'),ending=M:forecast(bi,q).ending,nextEnding=M:forecast(bi,q).nextEnding}
 end;return 0
end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished then return end
 local ok,err=xpcall(function()
  local front,rear,main=0,0,0
  for _,a in ipairs(R.actions) do if a.round==round then
   if a.q==s.normal then
    check(a.command==manualCommand[1] and a.target==manualCommand[2] and a.tech==manualCommand[3],'main pet executes the exact manual command round '..round);main=main+1
   elseif round~=2 and a.front then check(a.tech==1930 and a.target==10,'safe front automatic bank pet attacks Boss '..a.q);front=front+1
   elseif not a.front then
    if round~=2 then check(a.tech==1930 and a.target==10,'rear AI uses safe single spell on rear Boss '..a.q) end
    rear=rear+1
   elseif round==2 and M.proxies[a.q] then check(a.tech~=7400,'front automatic pet resumes offense when Boss bypasses screen') end
  end end
  check(main==1,'main pet executes one manual action round '..round)
  check(get(s.normal,'CHAR_魔')==beforeMainMP-M:tech(manualCommand[3]).cost,'manual main-pet skill charges native MP exactly once round '..round)
  if round~=2 then check(front==4,'four front bank pets act without a fixed defense tactic') end
  check(rear>=4,'four rear automatic pets act intelligently')
  for _,effect in ipairs(R.effects) do if round~=2 and effect.round==round and M.proxies[effect.a] then
   check(effect.d~=Battle.GetPlayer(b,11) and effect.d~=Battle.GetPlayer(b,12),'AI damage never reaches protected front blocker')
  end end
  check(get(Battle.GetPlayer(b,11),'CHAR_血')>0 and get(Battle.GetPlayer(b,12),'CHAR_血')>0,'both front blockers remain alive')
  R.rounds=round;round=round+1
  if round>3 then
   M:finish(s);check(not s.battle,'battle cleanup releases tactic with battle roster')
  end
 end,debug.traceback)
 if not ok or round>3 then finish(not ok and err or nil) end
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  local function player(name)
   local q=Char.CreateDummy({mapType=0,floor=60003,x=16,y=35,image=100002,name=name});assert(q>=0)
   set(q,'CHAR_等级',150);set(q,'CHAR_体力',50000);NLG.UpChar(q);set(q,'CHAR_血',get(q,'CHAR_最大血'));return q
  end
  p=player('STRATEGY_TEST');bankOwner=player('STRATEGY_BANK')
  for slot=0,4 do
   local pet=Char.GivePet(p,3004,100);assert(pet>=0)
   for n=9,0,-1 do if Pet.GetSkill(pet,n)>=0 then Pet.DelSkill(pet,n) end end
   for _,id in ipairs({1930,2330,2700,409}) do assert(Pet.AddSkill(pet,id)==1) end
   set(pet,'CHAR_体力',20000);set(pet,'CHAR_魔法',20000);Pet.UpPet(p,pet);set(pet,'CHAR_血',get(pet,'CHAR_最大血'));set(pet,'CHAR_魔',get(pet,'CHAR_最大魔'))
  end
  assert(Pet.AddSkill(Char.GetPet(p,0),730)==1)
  for slot=0,3 do
   local pet=Char.GivePet(bankOwner,3004,100);assert(pet>=0);bank[slot]=pet
   for n=9,0,-1 do if Pet.GetSkill(pet,n)>=0 then Pet.DelSkill(pet,n) end end
   assert(Pet.AddSkill(pet,1930)==1);set(pet,'CHAR_魔法',20000);set(pet,'CHAR_体力',20000);Pet.UpPet(bankOwner,pet);set(pet,'CHAR_血',get(pet,'CHAR_最大血'));set(pet,'CHAR_魔',get(pet,'CHAR_最大魔'))
  end
  assert(Char.SetPetDepartureState(p,0,2)==1);assert(M:enable(p));s=M.active[p]
  local i1,i2=Data.EnemyGetDataIndex(1),Data.EnemyGetDataIndex(2)
  local f1,f2=Data.EnemyGetData(i1,CONST.DATA_ENEMY_BOSS_FLG),Data.EnemyGetData(i2,CONST.DATA_ENEMY_BOSS_FLG)
  local tactics=Data.EnemyGetData(i1,CONST.DATA_ENEMY_TACTICSOPTION)
  Data.EnemySetData(i1,CONST.DATA_ENEMY_TACTICSOPTION,'at:100;1;1')
  Data.EnemySetData(i1,CONST.DATA_ENEMY_BOSS_FLG,1);Data.EnemySetData(i2,CONST.DATA_ENEMY_BOSS_FLG,0)
  b=Battle.PVE(p,p,nil,{1,2,2},{100,100,100},{0,0,0})
  Data.EnemySetData(i1,CONST.DATA_ENEMY_BOSS_FLG,f1);Data.EnemySetData(i2,CONST.DATA_ENEMY_BOSS_FLG,f2)
  Data.EnemySetData(i1,CONST.DATA_ENEMY_TACTICSOPTION,tactics)
  check(b>=0 and Battle.IsBossBattle(b)==1,'isolated native Boss battle');M:formation(b,s)
  local boss=Battle.GetPlayer(b,10);flag(boss,'BATTLE_ENTRY_POSITION',1)
  set(boss,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(boss,'CHAR_BattleCom3',7300)
  for pos=11,12 do local q=Battle.GetPlayer(b,pos);flag(q,'BATTLE_ENTRY_POSITION',0);set(q,'CHAR_最大血',10000);set(q,'CHAR_血',10000) end
  for _,actor in ipairs(M:actors(s)) do M:attributes(actor) end
  local blockers=M:bossBlockers(b,p);check(blockers[11] and blockers[12] and not blockers[10],'native rear Boss flag identifies front blockers')
  R.initialDecision=M:choose(b,s.rows[1]);R.initialHP=get(s.rows[1].proxy,'CHAR_血');R.initialMP=get(s.rows[1].proxy,'CHAR_魔')
  check(M:choose(b,s.rows[1])[3]==1930 and M:choose(b,s.rows[1])[2]==10,'ordinary intelligent mode also preserves rear Boss blockers')
  flag(boss,'BATTLE_ENTRY_POSITION',0);check(next(M:bossBlockers(b,p))==nil,'front Boss has no protected screen');flag(boss,'BATTLE_ENTRY_POSITION',1)
  flag(p,'BATTLE_ENTRY_POSITION',0);check(next(M:bossBlockers(b,p))==nil,'front player is not treated as shielded');flag(p,'BATTLE_ENTRY_POSITION',1)
  check(next(M:bossBlockers(b,p))~=nil,'screened Boss protects enemy blockers without forcing defense')
  check(M.proxies[s.normal]==nil,'Boss tactics always exclude the manually controlled main pet')
  local mainMode=get(s.normal,'CHAR_BattleMode');local mainTech=get(s.normal,'CHAR_BattleCom3')
  M:tick();check(get(s.normal,'CHAR_BattleMode')==mainMode and get(s.normal,'CHAR_BattleCom3')==mainTech,'AI tick preserves main-pet state before native command phase')
  for _,row in ipairs(s.companions) do check(M:choose(b,row)[3]==1930,'safe front bank pet attacks instead of fixed defense') end
  check(M:choose(b,s.rows[1])[3]==1930,'rear pet keeps learned intelligent skill')
  set(boss,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_P_MAGIC);set(boss,'CHAR_BattleCom3',1930)
  check(next(M:bossBlockers(b,p))==nil,'ranged Boss attack bypasses screen and releases defense')
  set(boss,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(boss,'CHAR_BattleCom3',7300)
  flag(boss,'BATTLE_ENTRY_POSITION',0)
  local row=s.rows[1];local normal=M:tech(7300);local blockers={}
  set(boss,'CHAR_最大血',1000000);set(boss,'CHAR_血',1000000);set(boss,'CHAR_防御力',0);set(boss,'CHAR_闪躲',0)
  set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(p,'CHAR_BattleCom2',10);set(p,'CHAR_BattleCom3',7300);set(p,'CHAR_BattleMode',3)
  check(M:comboBenefit(b,row,10,normal,blockers)>0,'healthy reachable Boss and committed same-target owner attack favor combo')
  local learned={};for slot=0,9 do local id=Pet.GetSkill(row.pet,slot);if id>=0 then learned[#learned+1]=id end end
  for slot=9,0,-1 do if Pet.GetSkill(row.pet,slot)>=0 then Pet.DelSkill(row.pet,slot) end end;assert(Pet.AddSkill(row.pet,1930)==1)
  local enemyHP={};for pos=11,12 do local enemy=Battle.GetPlayer(b,pos);enemyHP[pos]=get(enemy,'CHAR_血');set(enemy,'CHAR_血',0) end
  check(M:comboBenefit(b,row,10,normal,blockers)>0,'committed same-target attack contributes expected combo damage')
  for pos=11,12 do set(Battle.GetPlayer(b,pos),'CHAR_血',enemyHP[pos]) end
  for slot=9,0,-1 do if Pet.GetSkill(row.pet,slot)>=0 then Pet.DelSkill(row.pet,slot) end end
  for _,id in ipairs(learned) do assert(Pet.AddSkill(row.pet,id)==1) end
  Battle.SetBattleCharacterStatus(boss,CONST['战属_攻反'],2)
  check(M:comboBenefit(b,row,10,normal,blockers)==0,'reflected Boss prevents combo')
  Battle.SetBattleCharacterStatus(boss,CONST['战属_攻反'],0)
  set(boss,'CHAR_闪躲',100);check(M:comboBenefit(b,row,10,normal,blockers)==0,'high evasion prevents speculative combo');set(boss,'CHAR_闪躲',0)
  set(boss,'CHAR_血',1);check(M:comboBenefit(b,row,10,normal,blockers)==0,'already finishable Boss needs no combo bonus')
  set(boss,'CHAR_血',1000000)
  assert(Pet.AddSkill(row.pet,6100)==1)
  local mainHP=get(s.normal,'CHAR_血');set(s.normal,'CHAR_血',100)
  local oldDex=get(row.proxy,'CHAR_敏捷');set(row.proxy,'CHAR_敏捷',10000);set(boss,'CHAR_敏捷',1)
  s.damageHistory={[s.normal]={[boss]={turn=Battle.GetTurn(b),physical=110,physicalTech=7300}}}
   for pos=11,12 do s.damageHistory[s.normal][Battle.GetPlayer(b,pos)]={turn=Battle.GetTurn(b),physical=0,physicalTech=7300} end
  R.healDiagnostic={command=M:choose(b,row),attack=M:automaticAttack(b,row,M:skills(row.pet)),mp=get(row.proxy,'CHAR_魔'),reply=get(row.proxy,'CHAR_回复'),mainHP=get(s.normal,'CHAR_血'),mainMax=get(s.normal,'CHAR_最大血'),mainDamage=M:forecast(b,s.normal).damage,enemyCommand=get(boss,'CHAR_BattleCom1'),enemyTech=get(boss,'CHAR_BattleCom3'),rowDex=get(row.proxy,'CHAR_敏捷'),enemyDex=get(boss,'CHAR_敏捷')};check(M:choose(b,row)[3]==6100,'predicted lethal damage makes healing override Boss combo preference')
  s.damageHistory=nil;set(row.proxy,'CHAR_敏捷',oldDex)
  set(s.normal,'CHAR_血',mainHP)
  for slot=0,9 do if Pet.GetSkill(row.pet,slot)==6100 then Pet.DelSkill(row.pet,slot) end end
  for _,actor in ipairs(M:actors(s)) do
   set(actor.proxy,'CHAR_攻击力',0);set(actor.proxy,'CHAR_精神',100);set(actor.proxy,'CHAR_魔攻',0)
  end
  check(M:comboBenefit(b,row,10,normal,blockers)==0,'negligible physical damage gives no combo benefit')
  check(M:choose(b,row)[3]~=7300,'stronger learned magic beats poor physical combo')
  flag(boss,'BATTLE_ENTRY_POSITION',1)
  check(M:comboBenefit(b,row,10,normal,M:bossBlockers(b,p))==0,'blocked rear Boss never induces melee combo')
  check(next(M:bossBlockers(b,p))~=nil,'screen protection resumes automatically')
  T:AddInterval(100,function()
   if finished then return end
   local success,e=xpcall(function()
    if Battle.IsWaitingCommand(p)==1 then
     set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',0);set(p,'CHAR_BattleCom3',7400)
     set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3)
    end
    if Battle.IsWaitingCommand(s.normal)==1 then
     M:tick();check(Battle.IsWaitingCommand(s.normal)==1,'AI does not submit a main-pet command round '..round)
     manualCommand=round==1 and {CONST.BATTLE_COM.BATTLE_COM_ATTACK,11,7300}
      or (round==2 and {CONST.BATTLE_COM.BATTLE_COM_P_MAGIC,10,1930}
       or {CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD,0,730})
     beforeMainMP=get(s.normal,'CHAR_魔')
     check(Battle.ActionSelect(s.normal,manualCommand[1],manualCommand[2],manualCommand[3])==0,'manual main-pet selection accepted round '..round)
     R.manualCommands=R.manualCommands or {};R.manualCommands[#R.manualCommands+1]={round=round,command=manualCommand,mp=beforeMainMP}
    end
    M:tick()
    if manualCommand then
     check(get(s.normal,'CHAR_BattleCom1')==manualCommand[1] and get(s.normal,'CHAR_BattleCom2')==manualCommand[2]
      and get(s.normal,'CHAR_BattleCom3')==manualCommand[3],'AI tick preserves the submitted main-pet command round '..round)
    end
   end,debug.traceback)
   if not success then finish(e) end
  end,1)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
