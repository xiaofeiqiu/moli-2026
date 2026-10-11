-- Count native actions and costs in nine-, seven- and five-pet squads.
-- All characters and bank fixtures are disposable; player stores are never used.
local R={status='RUNNING',checks={},actions={},effects={},queued={},rounds=0,bank_partner_count=__BANK_COUNT__,production_database_modified=false,bank_lookup_injected=true}
local M=assert(getModule('fivePet'));local T=ModuleBase:createModule('singleActionProbe'):new();T:load()
local p,donor,b=-1,-1,-1;local session;local pets,bank,actors={},{},{}
local bankCounts={__BANK_COUNT__};local phase,round=1,1;local finished=false;local started=os.time();local beforeMP={}
local C=CONST.BATTLE_COM;local originalPool=Char.GetPoolPet
Char.GetPoolPet=function(q,slot) if q==p and slot<bankCounts[phase] then return bank[slot] or -1 end;if q==p then return -1 end;return originalPool(q,slot) end
local function get(q,k) return Char.GetData(q,assert(CONST[k])) end
local function set(q,k,v) return Char.SetData(q,assert(CONST[k]),v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function finish(err)
 if finished then return end;finished=true
 if p>=0 then pcall(Battle.ExitBattle,p);pcall(M.disable,M,p) end
 Char.GetPoolPet=originalPool
 for _,q in ipairs({p,donor}) do if q>=0 then
  for slot=0,4 do if Char.GetPet(q,slot)>=0 then pcall(Char.DelSlotPet,q,slot) end end
  pcall(Char.DelDummy,q)
 end end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end
local function learn(pet,ids)
 for slot=9,0,-1 do if Pet.GetSkill(pet,slot)>=0 then Pet.DelSkill(pet,slot) end end
 for _,id in ipairs(ids) do check(Pet.AddSkill(pet,id)==1,'learn technique '..id) end
end
local function prepare()
 for _,q in ipairs({p,session.normal}) do set(q,'CHAR_血',get(q,'CHAR_最大血')) end
 for _,row in ipairs(M:actors(session)) do
  set(row.pet,'CHAR_血',get(row.pet,'CHAR_最大血'));set(row.pet,'CHAR_魔',get(row.pet,'CHAR_最大魔'));M:refresh(row)
 end
 local guardian=session.rows[1]
 M:saveAI(p,guardian.pet,{mode=round==1 and 'guard' or 'attack'})
 learn(guardian.pet,round==3 and {730,6100} or (round==4 and {731,6100} or {7300}))
 set(p,'CHAR_血',math.floor(get(p,'CHAR_最大血')*0.55))
 if round>=3 then set(session.normal,'CHAR_血',math.floor(get(session.normal,'CHAR_最大血')*0.35)) end
 M:attributes(guardian);M:attributes(session.rows[3])
end
local function startBattle()
 check(M:enable(p),'squad enabled with '..bankCounts[phase]..' bank partners');session=M.active[p]
 check(#session.rows==4 and #session.companions==bankCounts[phase],'expected carried and bank actors phase '..phase)
 actors={};for _,row in ipairs(M:actors(session)) do actors[row.proxy]=row end
 prepare();b=Battle.PVE(p,p,nil,{1,1},{100,100},{0,0});check(b>=0,'native battle starts phase '..phase)
 local count=0;for pos=0,9 do if Battle.GetPlayer(b,pos)>=0 then count=count+1 end end
 check(count==6+bankCounts[phase],'distinct ally count phase '..phase)
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b then return 0 end;return rate end)
T:regCallback('BattleDodgeRateEvent',function(bi,a,d,rate) if bi==b then return 0 end;return rate end)
T:regCallback('DamageCalculateEvent',function(a,d,o,damage,bi,c1,c2,c3)
 if bi==b then R.effects[#R.effects+1]={phase=phase,round=round,actor=a,target=d,tech=c3,guardianVisits=session.rows[1].actionCount};return 0 end;return damage
end)
T:regCallback('BeforeBattleTurnStartEvent',OrderedCallback(function(bi)
 if bi~=b or finished then return false end
 local ok,err=xpcall(function()
  for _,row in ipairs(session.rows) do
   R.queued[#R.queued+1]={phase=phase,round=round,actor=row.proxy,first={get(row.proxy,'CHAR_BattleCom1'),get(row.proxy,'CHAR_BattleCom2'),get(row.proxy,'CHAR_BattleCom3')},second={get(row.proxy,'CHAR_Battle2Com1'),get(row.proxy,'CHAR_Battle2Com2'),get(row.proxy,'CHAR_Battle2Com3')}}
  end
  for _,row in ipairs(M:actors(session)) do beforeMP[row.proxy]=get(row.proxy,'CHAR_魔') end
  -- Enemy attacks also exercise guard interception after the empty second slot.
  for pos=10,19 do local enemy=Battle.GetPlayer(b,pos);if enemy>=0 then
   set(enemy,'CHAR_BattleCom1',C.BATTLE_COM_ATTACK);set(enemy,'CHAR_BattleCom2',Battle.GetPos(b,session.normal));set(enemy,'CHAR_BattleCom3',7300)
  end end
 end,debug.traceback)
 if not ok then finish(err) end;return false
end,-30000))
T:regCallback('BattleBeforeActionEvent',OrderedCallback(function(bi,q)
 if bi==b and actors[q] then
  R.actions[#R.actions+1]={phase=phase,round=round,actor=q,command=get(q,'CHAR_BattleCom1'),target=get(q,'CHAR_BattleCom2'),tech=get(q,'CHAR_BattleCom3'),selectedTech=actors[q].command[3]}
 end;return 0
end,-30000))
T:regCallback('BattleAfterActionEvent',OrderedCallback(function(bi,q,addAction)
 if bi==b and round>=3 and q==session.rows[1].proxy then
  local tutor=assert(getModule('petSkillTutor'));local row=session.rows[1]
  R.guards=R.guards or {};R.guards[#R.guards+1]={phase=phase,round=round,actor=q,command=get(row.proxy,'CHAR_BattleCom1'),tech=get(row.proxy,'CHAR_BattleCom3'),binding=tutor.strongTargets[row.proxy],guardian=Battle.GetEntryData(b,session.normal,CONST.BATTLE_ENTRY_GUARDIAN)}
  addAction(Battle.GetPlayer(b,10),C.BATTLE_COM_ATTACK,Battle.GetPos(b,session.normal),7300)
 end;return 0
end,-30000))
T:regCallback('AfterBattleTurnEvent',OrderedCallback(function(bi)
 if bi~=b or finished then return end
 local ok,err=xpcall(function()
  R.rounds=R.rounds+1
  for _,row in ipairs(M:actors(session)) do
   local acts={};for _,a in ipairs(R.actions) do
    if a.phase==phase and a.round==round and a.actor==row.proxy and a.command~=C.BATTLE_COM_NONE then acts[#acts+1]=a end
   end
   check(#acts==1,'exactly one native action phase '..phase..' round '..round..' actor '..row.proxy)
   local action=acts[1];local cost=M:tech(action.selectedTech).cost
   check(get(row.proxy,'CHAR_魔')==beforeMP[row.proxy]-cost,'MP charged once phase '..phase..' round '..round..' actor '..row.proxy)
   check(get(row.pet,'CHAR_魔')==get(row.proxy,'CHAR_魔'),'MP synchronized phase '..phase..' round '..round..' actor '..row.proxy)
   if row.bankSlot==nil then
    local queued;for _,v in ipairs(R.queued) do if v.phase==phase and v.round==round and v.actor==row.proxy then queued=v.second end end
    check(queued and queued[1]==C.BATTLE_COM_NONE and queued[2]==-1 and queued[3]==-1,'second slot empty phase '..phase..' round '..round..' actor '..row.proxy)
    check(row.secondCommand==nil,'no second command phase '..phase..' round '..round..' actor '..row.proxy)
   end
  end
  local guardian=session.rows[1];local expected=({7400,7300,730,731})[round]
  check(guardian.command[3]==expected,'guard / attack / bodyguard / strong guard selected phase '..phase..' round '..round)
  check(session.rows[2].command[3]==1930,'magic executes phase '..phase..' round '..round)
  check(session.rows[3].command[3]==6100,'healing executes phase '..phase..' round '..round)
  if round>=3 then
   local intercepted=false;for _,e in ipairs(R.effects) do if e.phase==phase and e.round==round and e.guardianVisits>=2 and e.target==guardian.proxy and Char.IsEnemy(e.actor) then intercepted=true end end
   check(intercepted,'bodyguard still intercepts after single action phase '..phase..' round '..round)
  end
  if round<4 then round=round+1;prepare() else finish() end
 end,debug.traceback)
 if not ok then finish(err) end
end,-30000))
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  local function player(name)
   local q=Char.CreateDummy({mapType=0,floor=60003,x=16,y=35,image=100002,name=name});assert(q>=0)
   set(q,'CHAR_等级',150);set(q,'CHAR_体力',50000);NLG.UpChar(q);set(q,'CHAR_血',get(q,'CHAR_最大血'));return q
  end
  p=player('SINGLE_ACTION_TEST');donor=player('SINGLE_ACTION_BANK')
  for slot=0,4 do
   local pet=Char.GivePet(p,3004,100);check(pet>=0,'carried fixture '..slot);pets[slot+1]=pet
   set(pet,'CHAR_体力',5000);set(pet,'CHAR_魔法',5000)
   -- Use native growth stats so status recalculation preserves action order.
   if slot==1 then set(pet,'CHAR_速度',50000) elseif slot==3 then set(pet,'CHAR_速度',0) end
   Pet.UpPet(p,pet);set(pet,'CHAR_血',get(pet,'CHAR_最大血'))
   learn(pet,slot==2 and {1930} or (slot==3 and {6100} or {7300}))
   if slot==4 then M:saveAI(p,pet,{mode='guard'}) end
  end
  for slot=0,3 do
   local pet=Char.GivePet(donor,3004,100);check(pet>=0,'bank fixture '..slot);bank[slot]=pet
   set(pet,'CHAR_魔法',5000);Pet.UpPet(donor,pet);set(pet,'CHAR_血',get(pet,'CHAR_最大血'));learn(pet,{1930})
   if slot==0 then M:saveAI(p,pet,{mode='guard'}) end
  end
  check(Char.SetPetDepartureState(p,0,2)==1,'main pet selected')
  local ix=Data.EnemyGetDataIndex(1);Data.EnemySetData(ix,CONST.DATA_ENEMY_BOSS_FLG,0)
  startBattle()
  T:AddInterval(100,function()
   if finished then return end
   local yes,error=xpcall(function()
    if os.time()-started>40 then error('single-action native combat timed out') end
    if Battle.IsWaitingCommand(p)==1 then
     set(p,'CHAR_BattleCom1',C.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',Battle.GetPos(b,p));set(p,'CHAR_BattleCom3',7400)
     set(p,'CHAR_Battle2Com1',C.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3)
    end
    if Battle.IsWaitingCommand(session.normal)==1 then Battle.ActionSelect(session.normal,C.BATTLE_COM_ATTACK,10,7300) end
    M:tick()
   end,debug.traceback)
   if not yes then finish(error) end
  end,1)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
