-- Reproduce a level-one modified Cupid with the reported seven skills.
-- Uses real bank inventory on a disposable server; no player stores are copied.
local R={status='RUNNING',checks={},actions={},effects={},production_database_modified=false,native_bank_inventory=true,bank_lookup_injected=false,client_verified=false,packets={}}
local M=assert(getModule('fivePet'));local T=ModuleBase:createModule('bankAiProbe'):new();T:load()
local p,bankOwner,b=-1,-1,-1;local bank,s,row;local phase=1;local finished=false
local function get(q,k) return Char.GetData(q,CONST[k]) end
local function set(q,k,v) return Char.SetData(q,CONST[k],v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function write() local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close() end
local function capture()
 R.capture_requested='bank_'..phase;write();local deadline=os.clock()+3
 repeat
  local f=io.open('__OUTPUT__/bank_ai_capture_ack.json','rb')
  if f then
   local raw=f:read('*a');f:close();local ok,v=pcall(JSON.decode,raw)
   if ok and v.capture==R.capture_requested then
    R.packets[phase]=v.buffers.main..v.buffers.extra
    local tech=R.actions[#R.actions].tech
    if tech==7400 then return end
    check(R.packets[phase]:find('SKL|s'..string.format('%X',tech)..'|',1,true)~=nil,'native bank skill animation emitted phase '..phase)
    return
   end
  end
 until os.clock()>deadline
 error('bank animation capture timeout '..phase)
end
local function finish(err)
 if finished then return end;finished=true
 if p>=0 then pcall(Battle.ExitBattle,p);pcall(M.disable,M,p) end
 for _,q in ipairs({p,bankOwner}) do if q>=0 then
  for slot=0,4 do if Char.GetPet(q,slot)>=0 then pcall(Char.DelSlotPet,q,slot) end end;pcall(Char.DelDummy,q)
 end end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil;write()
end
local function learn(ids)
 for slot=9,0,-1 do if Pet.GetSkill(bank,slot)>=0 then Pet.DelSkill(bank,slot) end end
 for _,id in ipairs(ids) do check(Pet.AddSkill(bank,id)==1,'learn bank technique '..id) end
end
local function prepare()
 if phase==3 then
  set(p,'CHAR_最大血',1000);set(p,'CHAR_血',300)
  R.beforeMainHP=math.floor(get(s.normal,'CHAR_最大血')*0.35);set(s.normal,'CHAR_血',R.beforeMainHP)
 end
 local mp=phase==2 and 179 or 359;set(bank,'CHAR_魔',mp);set(row.proxy,'CHAR_魔',mp)
 if phase==1 then set(bank,'CHAR_血',get(bank,'CHAR_最大血'));set(row.proxy,'CHAR_血',get(bank,'CHAR_最大血')) end
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(bi,q,r) if bi==b then return 0 end;return r end)
T:regCallback('DamageCalculateEvent',function(a,d,o,damage,bi,c1,c2,c3)
 if bi==b then
  if row and a==row.proxy then R.effects[#R.effects+1]={phase=phase,kind='damage',target=d,original=o,tech=c3} end
  return 0
 end;return damage
end)
T:regCallback('BattleHealCalculateEvent',function(a,d,o,heal,bi,c1,c2,c3)
 if bi==b and row and a==row.proxy then R.effects[#R.effects+1]={phase=phase,kind='heal',target=d,original=o,tech=c3} end
 return heal
end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi==b then
  R.queued=R.queued or {};R.queued[#R.queued+1]={phase=phase,command=row.command,actual={get(row.proxy,'CHAR_BattleCom1'),get(row.proxy,'CHAR_BattleCom2'),get(row.proxy,'CHAR_BattleCom3')},mp=get(row.proxy,'CHAR_魔'),hp=get(row.proxy,'CHAR_血'),maxhp=get(row.proxy,'CHAR_最大血'),dead=row.dead,skills=M:skills(bank),sourceHP=get(bank,'CHAR_血'),sourceMax=get(bank,'CHAR_最大血')}
  for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then
   set(q,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(q,'CHAR_BattleCom3',7400)
  end end
 end;return false
end)
T:regCallback('BattleBeforeActionEvent',function(bi,q)
 if bi==b and row and q==row.proxy and get(q,'CHAR_BattleCom3')>=0 then
  R.actions[#R.actions+1]={phase=phase,command=get(q,'CHAR_BattleCom1'),target=get(q,'CHAR_BattleCom2'),tech=get(q,'CHAR_BattleCom3'),mp=get(q,'CHAR_魔')}
 end;return 0
end)
T:regCallback('BattleAfterActionEvent',function(bi,q)
 if bi==b and row and q==row.proxy and not R.packets[phase] then
  local ok,err=xpcall(capture,debug.traceback);if not ok then finish(err) end
 end;return 0
end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished then return end
 local ok,err=xpcall(function()
  R.rounds=phase;R.afterMP=R.afterMP or {};R.afterMP[phase]=get(row.proxy,'CHAR_魔')
  local action;for _,a in ipairs(R.actions) do if a.phase==phase then action=a end end
  check(action~=nil,'bank Cupid enters actual native action phase '..phase)
  if phase==1 then
   check(action.tech==6550,'seven-skill bank Cupid casts learned area regeneration')
   local buffed=0;for pos=0,9 do local ally=Battle.GetPlayer(b,pos)
    if ally>=0 and Battle.GetBattleCharacterStatus(ally,CONST['战属_恢复回合'])>0 then buffed=buffed+1 end
   end
   check(buffed>=2,'native area regeneration affects multiple allies')
   check(get(row.proxy,'CHAR_魔')<359,'bank regeneration actually consumes MP')
  elseif phase==2 then
   check(action.tech==2130 or action.tech==2230,'bank Cupid uses learned fire or wind')
   local hit=false;for _,e in ipairs(R.effects) do if e.phase==phase and e.kind=='damage' and e.original>0 then hit=true end end
   check(hit,'bank elemental spell produces native damage')
  else
   check(action.tech==6350,'bank Cupid selects native E1 whole-side healing')
   check(get(p,'CHAR_血')>300 and get(s.normal,'CHAR_血')>R.beforeMainHP,'native E1 heals player and main pet')
  end
  phase=phase+1;if phase<=3 then prepare() end
 end,debug.traceback)
 if not ok or phase>3 then finish(not ok and err or nil) end
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  local function player(name)
   local q=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name=name});assert(q>=0)
   set(q,'CHAR_等级',50);set(q,'CHAR_体力',50000);NLG.UpChar(q);set(q,'CHAR_血',get(q,'CHAR_最大血'));return q
  end
  p=player('BANK_AI_TEST');bankOwner=player('BANK_AI_SOURCE')
  for slot=0,2 do check(Char.GivePet(p,3004,1)>=0,'carried fixture '..slot) end
  local unused=Char.GivePet(bankOwner,3004,1);check(unused>=0,'bank first-slot fixture');set(unused,'CHAR_血',0)
  bank=Char.GivePet(bankOwner,12400,1);check(bank>=0,'native modified Cupid fixture')
  for k,v in pairs({CHAR_体力=1200,CHAR_力量=950,CHAR_强度=900,CHAR_速度=2250,CHAR_魔法=2450}) do set(bank,k,v) end
  for i,key in ipairs({'宠档_体成','宠档_力成','宠档_强成','宠档_敏成','宠档_魔成'}) do Pet.SetArtRank(bank,CONST[key],({22,22,17,47,47})[i]) end
  Pet.UpPet(bankOwner,bank);set(bank,'CHAR_攻击力',82);set(bank,'CHAR_血',124);set(bank,'CHAR_魔',359)
  learn({7300,7400,2130,2230,6350,6550,6800})
  local fixture={player=p,donor=bankOwner,player_pointer=tostring(Char.GetCharPointer(p)),donor_pointer=tostring(Char.GetCharPointer(bankOwner)),pets={}}
  for _,pet in ipairs({unused,bank}) do fixture.pets[#fixture.pets+1]={index=pet,pointer=tostring(Char.GetCharPointer(pet))} end
  local f=assert(io.open('__OUTPUT__/bank_fixture_request.tmp','wb'));f:write(JSON.encode(fixture));f:close()
  assert(os.rename('__OUTPUT__/bank_fixture_request.tmp','__OUTPUT__/bank_fixture_request.json'))
  local fixtureReady=false
  T:AddInterval(100,function()
   if finished or fixtureReady then return end
   local yes,e=xpcall(function()
    local ready=io.open('__OUTPUT__/bank_fixture_ready','rb');if not ready then return end;ready:close();fixtureReady=true
    check(Char.GetPoolPet(p,0)==unused and Char.GetPoolPet(p,1)==bank,'real native bank slots populated')
    check(Char.PetNum(bankOwner)==0 and Char.PetNum(p)==3,'bank originals absent from carried inventories')
    assert(Char.SetPetDepartureState(p,0,2)==1);check(M:enable(p),'bank squad enabled');s=M.active[p];row=s.companions[1]
  check(row and row.bankSlot==1,'second bank slot paired with matching carrier')
  R.pet={attack=get(bank,'CHAR_攻击力'),defense=get(bank,'CHAR_防御力'),agility=get(bank,'CHAR_敏捷'),spirit=get(bank,'CHAR_精神'),recovery=get(bank,'CHAR_回复'),hp=get(bank,'CHAR_血'),mp=get(bank,'CHAR_魔')}
  R.skills={};for _,t in ipairs(M:skills(bank)) do R.skills[#R.skills+1]={id=t.id,effect=t.effect,cost=t.cost,scope=t.scope} end
  local ix=Data.EnemyGetDataIndex(1);local boss=Data.EnemyGetData(ix,CONST.DATA_ENEMY_BOSS_FLG);Data.EnemySetData(ix,CONST.DATA_ENEMY_BOSS_FLG,0)
  b=Battle.PVE(p,p,nil,{1,1,1},{20,20,20},{0,0,0});Data.EnemySetData(ix,CONST.DATA_ENEMY_BOSS_FLG,boss)
  check(b>=0 and Battle.IsBossBattle(b)==0,'ordinary native battle');M:formation(b,s);M:attributes(row)
  R.initialDecision=M:choose(b,row);check(R.initialDecision[3]==6350,'actual stored HP selects whole-party healing rather than idle')
  prepare()
  T:AddInterval(100,function()
   if finished then return end
   local yes,e=xpcall(function()
    if Battle.IsWaitingCommand(p)==1 then
     set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',0);set(p,'CHAR_BattleCom3',7400)
     set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3)
    end
    if Battle.IsWaitingCommand(s.normal)==1 then Battle.ActionSelect(s.normal,CONST.BATTLE_COM.BATTLE_COM_GUARD,5,7400) end
    M:tick()
   end,debug.traceback)
   if not yes then finish(e) end
  end,1)
   end,debug.traceback)
   if not yes then finish(e) end
  end,1)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
