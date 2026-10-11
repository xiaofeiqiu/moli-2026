-- Native LV1-LV10 ranks: AI budget selection, four interceptions and real DR options.
local R={status='RUNNING',checks={},npcs={},production_accounts_used=false,hits={}}
local M=assert(getModule('fivePet'));local tutor=assert(getModule('petSkillTutor'))
local T=ModuleBase:createModule('strongGuardLevelsProbe'):new();T:load()
local ids,costs,dr={},{},{}
for level=1,10 do ids[level]=729+2*level;costs[level]=40+16*(level-1);dr[level]=level==10 and 100 or (level-1)*10 end
local p,b=-1,-1;local pets,rows={},{};local row;local round=1;local finished=false;local start=os.time();local beforeMP;local tested=false
local function get(q,k) return Char.GetData(q,assert(CONST[k])) end
local function set(q,k,v) return Char.SetData(q,assert(CONST[k]),v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function rank() return math.min(round,10) end
local function actor() return round<=10 and row.proxy or pets[1] end
local function finish(err)
 if finished then return end;finished=true
 if p>=0 then pcall(M.disable,M,p);pcall(Battle.ExitBattle,p)
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end
  pcall(Char.DelDummy,p)
 end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end
local function setup()
 tested=false;set(p,'CHAR_血',100)
 for _,pet in ipairs(pets) do set(pet,'CHAR_血',get(pet,'CHAR_最大血'));set(pet,'CHAR_魔',get(pet,'CHAR_最大魔')) end
 for i=3,5 do set(pets[i],'CHAR_血',100) end
 for _,r in ipairs(rows) do M:attributes(r);set(r.proxy,'CHAR_血',r==row and get(r.proxy,'CHAR_最大血') or 100) end
 if round<=10 then
  set(row.pet,'CHAR_魔',costs[rank()]);set(row.proxy,'CHAR_魔',costs[rank()])
 else M:saveAI(p,row.pet,{mode='guard'});set(pets[1],'CHAR_魔',costs[10]) end
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b then return 0 end;return rate end)
T:regCallback('BattleDodgeRateEvent',function(bi,a,d,rate) if bi==b then return 0 end;return rate end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi)
 if bi==b then R.hits[#R.hits+1]={round=round,attacker=a,defender=d,original=ori,damage=damage,
  option=Battle.GetTechOption(d,'DR:')};return 1 end
 return damage
end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi~=b then return false end
 beforeMP=get(actor(),'CHAR_魔');set(actor(),'CHAR_防御力',100)
 local targets=tutor:strongGuardTargets(b,actor(),Battle.GetPos(b,p));check(#targets==4,'four planned allies rank '..rank())
 for pos=10,13 do local e=Battle.GetPlayer(b,pos)
  set(e,'CHAR_攻击力',1000);set(e,'CHAR_敏捷',1)
  set(e,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(e,'CHAR_BattleCom2',targets[pos-9]);set(e,'CHAR_BattleCom3',7300)
 end
 return false
end)
T:regCallback('BattleAfterActionEvent',function(bi,q)
 if bi~=b or q~=actor() or tested or get(q,'CHAR_BattleCom1')~=CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD then return 0 end
 local ok,err=xpcall(function()
  tested=true;local a=assert(tutor.strongTargets[q])
  check(a.tech==ids[rank()],'bound rank matches selected skill round '..round)
  check(#a.positions==4,'exactly four protected allies round '..round)
  check(get(q,'CHAR_魔')==beforeMP-costs[rank()],'exact native MP cost round '..round)
  check(get(q,'CHAR_BattleCom3')==ids[rank()] or get(q,'CHAR_BattleCom3')==699+rank(),'matching native rank executed round '..round)
 end,debug.traceback);if not ok then finish(err) end;return 0
end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished then return end
 local ok,err=xpcall(function()
  check(tested,'guard rank executes round '..round)
  local count=0;for _,hit in ipairs(R.hits) do if hit.round==round and hit.defender==actor() then
   count=count+1;check(hit.option==dr[rank()],'native DR matches rank '..rank()..' attack '..count)
  end end
  check(count==4,'four actual interceptions round '..round)
  check(get(actor(),'CHAR_魔')==beforeMP-costs[rank()],'followup spends no additional guard MP round '..round)
  round=round+1;if round<=11 then setup() end
 end,debug.traceback)
 if not ok or round>11 then finish(not ok and err or nil) end
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=60003,x=36,y=19,image=100002,name='STRONG_GUARD_LEVELS'});check(p>=0,'isolated owner')
  set(p,'CHAR_等级',50);set(p,'CHAR_体力',50000);NLG.UpChar(p)
  for slot=0,4 do local pet=Char.GivePet(p,3004,1);pets[slot+1]=pet;check(pet>=0,'isolated pet '..slot)
   for i=9,0,-1 do if Pet.GetSkill(pet,i)>=0 then Pet.DelSkill(pet,i) end end
   set(pet,'CHAR_体力',50000);set(pet,'CHAR_魔法',50000);set(pet,'CHAR_速度',10000);Pet.UpPet(p,pet)
   set(pet,'宠物_技能栏',10)
  end
  check(get(pets[1],'CHAR_最大魔')>=184,'manual pet has enough native maximum MP')
  Char.AddGold(p,10000)
  for n,id in ipairs(ids) do
   local gold=Char.GetGold(p)
   check(tutor:learnPet(tutor.npc,p,1,Pet.GetUUID(pets[2]),id),'tutor learns rank '..n)
   check(Char.GetGold(p)==gold-1000,'rank '..n..' learning cost')
   local strong,native=M:tech(id),M:tech(699+n)
   check(strong.option==native.option and strong.cost==costs[n],'DATA rank '..n..' matches ordinary guard')
  end
  check(Pet.AddSkill(pets[1],749)==1,'manual pet learns LV10')
  for i=3,5 do M:saveAI(p,pets[i],{mode='guard'}) end
  check(Char.SetPetDepartureState(p,0,2)==1,'main pet selected');check(M:enable(p),'squad enabled')
  rows=M.active[p].rows;row=rows[1]
  b=Battle.PVE(p,p,nil,{1,1,1,1},{100,100,100,100},{0,0,0,0});check(b>=0,'native battle');M:formation(b,M.active[p]);setup()
  for n,cost in ipairs(costs) do set(row.proxy,'CHAR_魔',cost);check(M:choose(b,row)[3]==ids[n],'AI selects highest affordable rank '..n)
   if n>1 then set(row.proxy,'CHAR_魔',cost-1);check(M:choose(b,row)[3]==ids[n-1],'AI downgrades one rank below budget '..n) end
  end
  set(row.proxy,'CHAR_魔',39);check(not tutor:strongGuardTech(M:choose(b,row)[3]),'no affordable strong rank falls back')
  setup()
  T:AddInterval(100,function()
   if finished then return end
   local good,e=xpcall(function()
    if os.time()-start>48 then error('strong guard levels timeout') end
    if Battle.IsWaitingCommand(p)==1 then set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',Battle.GetPos(b,p));set(p,'CHAR_BattleCom3',7400);set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3) end
    if Battle.IsWaitingCommand(pets[1])==1 then local manual=round==11;Battle.ActionSelect(pets[1],manual and CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD or CONST.BATTLE_COM.BATTLE_COM_GUARD,manual and Battle.GetPos(b,p) or Battle.GetPos(b,pets[1]),manual and 749 or 7400) end
    M:tick()
   end,debug.traceback);if not good then finish(e) end
  end)
 end,debug.traceback);if not ok then finish(err) end
end,0)
