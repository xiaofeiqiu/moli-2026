-- Disposable pets and owner, native interception in both manual and proxy modes.
local R={status='RUNNING',checks={},npcs={},production_accounts_used=false}
local M=assert(getModule('fivePet'));local tutor=assert(getModule('petSkillTutor'))
local T=ModuleBase:createModule('strongGuardProbe'):new();T:load()
local p,b=-1,-1;local pets,rows={},{};local row;local round=1;local finished=false;local start=os.time();local beforeMP;local tested=false
local function get(q,k) return Char.GetData(q,assert(CONST[k])) end
local function set(q,k,v) return Char.SetData(q,assert(CONST[k]),v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function finish(err)
 if finished then return end;finished=true
 if p>=0 then pcall(M.disable,M,p);pcall(Battle.ExitBattle,p)
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end
  pcall(Char.DelDummy,p)
 end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end
local function actor() return round==1 and row.proxy or pets[1] end
local function setup()
 tested=false;set(p,'CHAR_血',100)
 for _,pet in ipairs(pets) do set(pet,'CHAR_血',100);set(pet,'CHAR_最大魔',2000);set(pet,'CHAR_魔',1000) end
 for _,r in ipairs(rows) do M:attributes(r);set(r.proxy,'CHAR_血',100);set(r.proxy,'CHAR_魔',1000) end
 set(round==1 and row.pet or pets[1],'CHAR_敏捷',10000);set(actor(),'CHAR_敏捷',10000);beforeMP=get(actor(),'CHAR_魔')
 if round==2 then M:saveAI(p,row.pet,{mode='guard'}) end
 if round==4 then set(pets[1],'CHAR_魔',39);beforeMP=39 end
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b then return 0 end;return rate end)
T:regCallback('BattleDodgeRateEvent',function(bi,a,d,rate) if bi==b then return 0 end;return rate end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi)
 if bi==b then R.hits=R.hits or {};R.hits[#R.hits+1]={round=round,attacker=a,defender=d};return 0 end;return damage
end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi==b then beforeMP=get(actor(),'CHAR_魔');local targets=tutor:strongGuardTargets(b,actor(),Battle.GetPos(b,p))
  local included={};for _,pos in ipairs(targets) do included[pos]=true end
  for pos=0,9 do local ally=Battle.GetPlayer(b,pos);if ally>=0 and ally~=actor() and not included[pos] then targets[5]=pos;break end end
  for pos=10,14 do local e=Battle.GetPlayer(b,pos);if e>=0 then
  set(e,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(e,'CHAR_BattleCom2',targets[pos-9]);set(e,'CHAR_BattleCom3',7300)
 end end end;return false
end)
T:regCallback('BattleAfterActionEvent',function(bi,q,addAction)
 if bi~=b or q~=actor() or tested or round>2 or get(q,'CHAR_BattleCom1')~=CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD then return 0 end
 local ok,err=xpcall(function()
  tested=true;local positions=assert(tutor.strongTargets[q]).positions
  check(#positions==4,'exactly four of five allies guarded round '..round)
  check(positions[1]==Battle.GetPos(b,p),'owner included round '..round)
  R.mp=R.mp or {};R.mp[round]={before=beforeMP,after=get(q,'CHAR_魔')}
  check(get(q,'CHAR_魔')==beforeMP-40,'strong guard costs exactly 40 MP round '..round)
  for _,pos in ipairs(positions) do check(Battle.GetPlayer(b,pos)~=q,'guardian cannot protect itself round '..round) end
  R.positions=R.positions or {};R.positions[round]=positions
 end,debug.traceback)
 if not ok then finish(err) end;return 0
end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished then return end
 local ok,err=xpcall(function()
  if round<=2 then check(tested,'strong guard executes round '..round) end
  local n=0;for _,hit in ipairs(R.hits or {}) do if hit.round==round and hit.defender==actor() then n=n+1 end end
  check(n==(round<=2 and 4 or 0),round<=2 and ('four attacks intercepted; fifth ally stays unguarded round '..round) or 'strong guard expires at next turn')
  if round>2 then check(tutor.strongTargets[actor()]==nil,round==3 and 'expired binding removed' or 'insufficient MP does not activate manual strong guard') end
  if round==1 then
   R.finalMP=get(row.proxy,'CHAR_魔');check(get(row.proxy,'CHAR_魔')==beforeMP-40,'followup defense does not charge another strong guard')
  M:sync(p,row,true);check(get(row.pet,'CHAR_魔')==math.min(get(row.proxy,'CHAR_魔'),get(row.pet,'CHAR_最大魔')),'MP syncs to original pet within native maximum')
  end
  round=round+1;if round<=4 then setup() end
 end,debug.traceback)
 if not ok or round>4 then finish(not ok and err or nil) end
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=60003,x=36,y=19,image=100002,name='STRONG_GUARD_TEST'});check(p>=0,'isolated owner')
  set(p,'CHAR_等级',50);set(p,'CHAR_体力',50000);NLG.UpChar(p)
  for slot=0,4 do local pet=Char.GivePet(p,3004,1);pets[slot+1]=pet;check(pet>=0,'isolated pet '..slot)
   for i=9,0,-1 do if Pet.GetSkill(pet,i)>=0 then Pet.DelSkill(pet,i) end end
  end
  check(Pet.AddSkill(pets[1],731)==1,'manual pet learns new native technique')
  check(Pet.AddSkill(pets[2],730)==1,'automatic pet learns ordinary guard')
  Char.AddGold(p,2000);local gold=Char.GetGold(p)
  check(tutor:learnPet(tutor.npc,p,1,Pet.GetUUID(pets[2]),731),'tutor teaches strong guard')
  check(Char.GetGold(p)==gold-1000,'learning costs 1000 gold')
  check(not tutor:learnPet(tutor.npc,p,1,Pet.GetUUID(pets[2]),731) and Char.GetGold(p)==gold-1000,'duplicate learning does not charge')
  for i=3,5 do M:saveAI(p,pets[i],{mode='guard'}) end
  check(Char.SetPetDepartureState(p,0,2)==1,'main pet selected');check(M:enable(p),'squad enabled')
  rows=M.active[p].rows;row=rows[1]
  b=Battle.PVE(p,p,nil,{1,1,1,1,1},{100,100,100,100,100},{0,0,0,0,0});check(b>=0,'native battle');M:formation(b,M.active[p]);setup()
  check(M:choose(b,row)[3]==731,'strong guard preferred over ordinary guard')
  set(row.proxy,'CHAR_魔',39);check(M:choose(b,row)[3]==730,'insufficient MP falls back to ordinary guard');set(row.proxy,'CHAR_魔',1000)
  local target=rows[2].proxy;set(target,'CHAR_血',0)
  local list=tutor:strongGuardTargets(b,row.proxy,Battle.GetPos(b,p))
  for _,pos in ipairs(list) do check(Battle.GetPlayer(b,pos)~=target,'dead ally excluded') end
  set(target,'CHAR_血',100)
  T:AddInterval(100,function()
   if finished then return end
   local good,e=xpcall(function()
    if os.time()-start>40 then error('native strong guard timeout') end
    if Battle.IsWaitingCommand(p)==1 then set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',Battle.GetPos(b,p));set(p,'CHAR_BattleCom3',7400);set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3) end
    if Battle.IsWaitingCommand(pets[1])==1 then local strong=round==2 or round==4;Battle.ActionSelect(pets[1],strong and CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD or CONST.BATTLE_COM.BATTLE_COM_GUARD,strong and Battle.GetPos(b,p) or Battle.GetPos(b,pets[1]),strong and 731 or 7400) end
    M:tick()
   end,debug.traceback);if not good then finish(e) end
  end)
 end,debug.traceback);if not ok then finish(err) end
end,0)
