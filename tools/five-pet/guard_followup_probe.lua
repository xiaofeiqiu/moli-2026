-- Native single-action bodyguard regression; disposable characters only.
local R={status='RUNNING',checks={},npcs={},actions={},production_accounts_used=false}
local M=assert(getModule('fivePet'));local T=ModuleBase:createModule('guardFollowupProbe'):new();T:load()
local p,b=-1,-1;local pets,rows={},{};local row;local round=1;local finished=false;local start=os.time();local beforeMP,beforeHP
local function get(q,k) return Char.GetData(q,assert(CONST[k])) end
local function set(q,k,v) return Char.SetData(q,assert(CONST[k]),v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function finish(err)
 if finished then return end;finished=true
 if p>=0 then pcall(M.disable,M,p);pcall(Battle.ExitBattle,p);for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end;pcall(Char.DelDummy,p) end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end
local function setupRound()
 set(p,'CHAR_血',get(p,'CHAR_最大血'))
 for _,pet in ipairs(pets) do set(pet,'CHAR_血',get(pet,'CHAR_最大血')) end
 for _,r in ipairs(rows) do M:attributes(r);set(r.proxy,'CHAR_血',get(r.proxy,'CHAR_最大血')) end
 set(pets[1],'CHAR_血',20)
 if round==1 then set(rows[2].pet,'CHAR_血',1);set(rows[2].proxy,'CHAR_血',1) end
 if round==3 then for n=9,0,-1 do if Pet.GetSkill(row.pet,n)==6100 then Pet.DelSkill(row.pet,n) end end end
 if round==4 then check(Pet.AddSkill(row.pet,6100)==1,'relearn heal for MP budget test') end
 set(row.pet,'CHAR_魔',round==4 and 10 or math.min(1000,get(row.pet,'CHAR_最大魔')));set(row.proxy,'CHAR_魔',round==4 and 10 or math.min(1000,get(row.pet,'CHAR_最大魔')))
 if round==5 then set(pets[1],'CHAR_血',get(pets[1],'CHAR_最大血')) end
end
local nativeChoose=M.choose
M.choose=function(self,bi,r,live)
 if live and bi==b and r==row then
  R.live=R.live or {};R.live[#R.live+1]={round=round,mp=get(r.proxy,'CHAR_魔'),hp=get(pets[1],'CHAR_血'),max=get(pets[1],'CHAR_最大血'),command=get(r.proxy,'CHAR_BattleCom1'),tech=get(r.proxy,'CHAR_BattleCom3')}
 end
 return nativeChoose(self,bi,r,live)
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b then return 0 end;return rate end)
T:regCallback('BattleDodgeRateEvent',function(bi,a,d,rate) if bi==b then return 0 end;return rate end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi)
 if bi==b then R.hits=R.hits or {};R.hits[#R.hits+1]={round=round,attacker=a,defender=d};return 0 end;return damage
end)
T:regCallback('BattleBeforeActionEvent',function(bi,q)
 if bi==b then R.trace=R.trace or {};R.trace[#R.trace+1]={round=round,actor=q,command=get(q,'CHAR_BattleCom1'),target=get(q,'CHAR_BattleCom2'),mainGuard=Battle.GetEntryData(b,pets[1],CONST.BATTLE_ENTRY_GUARDIAN),otherGuard=Battle.GetEntryData(b,rows[2].proxy,CONST.BATTLE_ENTRY_GUARDIAN)} end
 if bi==b and q==row.proxy and get(q,'CHAR_BattleCom1')~=CONST.BATTLE_COM.BATTLE_COM_NONE then R.actions[#R.actions+1]={round=round,command=get(q,'CHAR_BattleCom1'),target=get(q,'CHAR_BattleCom2'),tech=get(q,'CHAR_BattleCom3')} end
 return 0
end)
T:regCallback('BattleAfterActionEvent',function(bi,q,addAction)
 if bi==b and q==row.proxy and round==1 then
  R.guardActions=(R.guardActions or 0)+1
  if R.guardActions==1 then
   R.extraAttacks=type(addAction)
   addAction(Battle.GetPlayer(b,10),CONST.BATTLE_COM.BATTLE_COM_ATTACK,Battle.GetPos(b,pets[1]),7300)
   addAction(Battle.GetPlayer(b,11),CONST.BATTLE_COM.BATTLE_COM_ATTACK,Battle.GetPos(b,rows[2].proxy),7300)
  end
 end
 return 0
end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi==b then
  beforeMP=get(row.proxy,'CHAR_魔');beforeHP=get(pets[1],'CHAR_血');R.queued=R.queued or {};R.queued[#R.queued+1]={round=round,first=row.command,second=row.secondCommand,secondSlot=get(row.proxy,'CHAR_Battle2Com1'),otherHP=get(rows[2].proxy,'CHAR_血')}
  for i=10,11 do local e=Battle.GetPlayer(b,i);if e>=0 then set(e,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(e,'CHAR_BattleCom2',Battle.GetPos(b,i==10 and pets[1] or rows[2].proxy));set(e,'CHAR_BattleCom3',7300) end end
 end
 return false
end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished then return end
 local ok,err=xpcall(function()
  R.guardians=R.guardians or {};R.guardians[#R.guardians+1]={round=round,main=Battle.GetEntryData(b,pets[1],CONST.BATTLE_ENTRY_GUARDIAN),other=Battle.GetEntryData(b,rows[2].proxy,CONST.BATTLE_ENTRY_GUARDIAN),guardian=row.proxy};R.mp=R.mp or {};R.mp[#R.mp+1]={round=round,before=beforeMP,after=get(row.proxy,'CHAR_魔'),cost=M:tech(730).cost};local acts={};for _,act in ipairs(R.actions) do if act.round==round then acts[#acts+1]=act end end
  if round<=4 then
   check(#acts==1,'bodyguard gets exactly one native action round '..round)
   check(row.secondCommand==nil and R.queued[#R.queued].secondSlot==CONST.BATTLE_COM.BATTLE_COM_NONE,'bodyguard second slot stays empty round '..round)
   check(acts[1].command==CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD,'first action bodyguard round '..round)
   if round==1 then
    check(get(row.proxy,'CHAR_魔')==beforeMP-10,'single bodyguard pays native MP once')
    local intercepted=0;for _,hit in ipairs(R.hits or {}) do if hit.round==1 and (hit.attacker==Battle.GetPlayer(b,10) or hit.attacker==Battle.GetPlayer(b,11)) and hit.defender==row.proxy then intercepted=intercepted+1 end end
    check(intercepted>=1,'single bodyguard intercepts attacks on its protected ally')
   elseif round==2 then
    check(get(pets[1],'CHAR_血')==beforeHP,'bodyguard does not append a healing action')
    check(get(row.proxy,'CHAR_魔')==beforeMP-10,'only bodyguard MP is charged')
    local intercepted=false;for _,hit in ipairs(R.hits or {}) do if hit.round==2 and hit.attacker==Battle.GetPlayer(b,10) and hit.defender==row.proxy then intercepted=true end end
    check(intercepted,'bodyguard remains active with an empty second slot')
   else
    check(get(row.proxy,'CHAR_魔')==beforeMP-10,'single guard spends exactly one skill cost round '..round)
   end
  else
   check(row.command[1]==CONST.BATTLE_COM.BATTLE_COM_ATTACK and row.secondCommand==nil,'healthy team retains original single-action attack')
   check(R.queued[#R.queued].secondSlot==CONST.BATTLE_COM.BATTLE_COM_NONE,'non-bodyguard clears second slot')
  end
  M:sync(p,row,true);check(get(row.pet,'CHAR_魔')==get(row.proxy,'CHAR_魔'),'single-action MP syncs back to real pet round '..round)
  round=round+1
  if round<=5 then setupRound() end
 end,debug.traceback)
 if not ok or round>5 then finish(not ok and err or nil) end
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=60003,x=16,y=35,image=100002,name='GUARD_FOLLOWUP_TEST'});check(p>=0,'isolated owner')
  set(p,'CHAR_等级',50);set(p,'CHAR_体力',50000);NLG.UpChar(p)
  for slot=0,2 do local pet=Char.GivePet(p,3004,1);pets[slot+1]=pet;check(pet>=0,'isolated pet '..slot)
   for i=9,0,-1 do if Pet.GetSkill(pet,i)>=0 then Pet.DelSkill(pet,i) end end
   set(pet,'CHAR_血',get(pet,'CHAR_最大血'));set(pet,'CHAR_最大魔',2000);set(pet,'CHAR_魔',1000)
  end
  check(Pet.AddSkill(pets[2],730)==1 and Pet.AddSkill(pets[2],6100)==1,'guardian learns bodyguard and heal')
  set(pets[2],'CHAR_敏捷',10000);check(Char.SetPetDepartureState(p,0,2)==1,'main pet selected')
  M:saveAI(p,pets[3],{mode='guard'});check(M:enable(p),'automatic squad enabled')
  rows=M.active[p].rows;row=rows[1];check(row.pet==pets[2],'guardian row selected')
  b=Battle.PVE(p,p,nil,{1,1},{100,100},{0,0});check(b>=0,'native battle with two attackers')
  M:formation(b,M.active[p]);setupRound()
  -- No AI configuration: guard takes precedence over self defense and healing.
  set(row.proxy,'CHAR_血',1)
  check(M:choose(b,row)[1]==CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD,'bodyguard priority beats low-HP defense and healing')
  setupRound()
  R.planned={first=M:choose(b,row),other={hp=get(rows[2].proxy,'CHAR_血'),max=get(rows[2].proxy,'CHAR_最大血')}}
  T:AddInterval(100,function()
   if finished then return end
   local ok,e=xpcall(function()
    if os.time()-start>40 then error('native followup timeout') end
    if Battle.IsWaitingCommand(p)==1 then set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',Battle.GetPos(b,p));set(p,'CHAR_BattleCom3',7400);set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3) end
    if Battle.IsWaitingCommand(pets[1])==1 then Battle.ActionSelect(pets[1],CONST.BATTLE_COM.BATTLE_COM_ATTACK,10,7300) end
    M:tick()
   end,debug.traceback)
   if not ok then finish(e) end
  end,1)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
