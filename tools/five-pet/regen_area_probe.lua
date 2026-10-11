-- Observe native area recovery coverage with disposable characters only.
local R={status='RUNNING',checks={},npcs={},production_accounts_used=false,coverage={}}
local M=assert(getModule('fivePet'))
local T=ModuleBase:createModule('fivepetRegenAreaProbe'):new();T:load()
local p,b=-1,-1;local pets,allies={},{};local row;local finished=false;local started=os.time()
local centers={5,0,6,7,8,9};local round=1
local expected={[0]='0,5',[5]='0,5,6,7',[6]='5,6,8',[7]='5,7,9',[8]='6,8',[9]='7,9'}
local originalTarget=M.recoveryTarget
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function set(q,k,v) return Char.SetData(q,assert(CONST[k],k),v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function finish(err)
 if finished then return end;finished=true;M.recoveryTarget=originalTarget
 if p>=0 then pcall(M.disable,M,p);pcall(Battle.ExitBattle,p)
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end
  pcall(Char.DelDummy,p)
 end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end
local function reset()
 for _,q in ipairs(allies) do set(q,'CHAR_血',get(q,'CHAR_最大血'));Battle.SetBattleCharacterStatus(q,CONST['战属_恢复回合'],0) end
 set(row.proxy,'CHAR_魔',get(row.pet,'CHAR_最大魔'));set(row.pet,'CHAR_魔',get(row.pet,'CHAR_最大魔'))
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi) if bi==b then return 0 end;return damage end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b then return 0 end;return rate end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi) if bi==b then R.beforeMP=get(row.proxy,'CHAR_魔') end end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished then return end
 local ok,err=xpcall(function()
  local hit={}
  for _,q in ipairs(allies) do if Battle.GetBattleCharacterStatus(q,CONST['战属_恢复回合'])>0 then hit[#hit+1]=Battle.GetPos(b,q) end end
  table.sort(hit);R.coverage[#R.coverage+1]={center=centers[round],hit=hit,command=row.command,beforeMP=R.beforeMP,afterMP=get(row.proxy,'CHAR_魔'),ai=M:ai(p,row.pet),learned=M:learned(row.pet,6500)}
  check(row.command and row.command[3]==6500,'native area recovery executed for center '..centers[round])
  check(table.concat(hit,',')==expected[centers[round]],'native cross coverage matches center '..centers[round])
  if round==1 then check(#hit==4,'first AI cast buffs four living allies') end
  check(get(row.proxy,'CHAR_魔')==R.beforeMP-36,'native area recovery consumes MP once')
  round=round+1;reset()
  if round>#centers then
   M.recoveryTarget=originalTarget
   local a=M:ai(p,row.pet);local rule=a.recoveryRules.regen
   local function chosen(target,label) check(M:choose(b,row)[2]==target,label) end
   set(p,'CHAR_血',1);chosen(25,'injured owner does not pull opening area recovery off center');reset()
   rule.scope='owner';M:saveAI(p,row.pet,a);chosen(25,'owner scope permits central splash covering owner')
   rule.scope='self';M:saveAI(p,row.pet,a);chosen(25,'self scope permits central splash covering caster')
   rule.scope='pets';M:saveAI(p,row.pet,a);chosen(25,'pet scope retains maximum coverage')
   rule.scope='team';M:saveAI(p,row.pet,a)
   for _,q in ipairs(allies) do if Battle.GetPos(b,q)<=7 then Battle.SetBattleCharacterStatus(q,CONST['战属_恢复回合'],3) end end
   chosen(26,'later casts cover unbuffed outer pets');reset()
   rule.when='low';rule.threshold=60;M:saveAI(p,row.pet,a)
   check(M:choose(b,row)[3]~=6500,'healthy team does not trigger low-HP regeneration')
   local edge=M.active[p].rows[4].proxy;set(edge,'CHAR_血',1);chosen(27,'low-HP edge trigger is inside selected native cross');reset()
   rule.when='start';M:saveAI(p,row.pet,a)
   for _,q in ipairs(allies) do Battle.SetBattleCharacterStatus(q,CONST['战属_恢复回合'],3) end
   check(M:choose(b,row)[3]~=6500,'fully buffed team does not repeat recovery');reset()
   set(pets[1],'CHAR_血',0);chosen(26,'fallen center is excluded and best living coverage chosen');reset()
   check(Pet.AddSkill(row.pet,6400)==1,'learn single recovery')
   rule.tech=6400;rule.scope='owner';M:saveAI(p,row.pet,a);chosen(0,'single recovery keeps direct owner target')
   check(Pet.AddSkill(row.pet,6600)==1,'learn all recovery')
   rule.tech=6600;M:saveAI(p,row.pet,a);chosen(40,'all recovery keeps native whole-team target')
  end
 end,debug.traceback)
 if not ok or round>#centers then finish(not ok and err or nil) end
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=60003,x=16,y=35,image=100002,name='REGEN_AREA_TEST'})
  check(p>=0,'isolated owner');set(p,'CHAR_等级',150);set(p,'CHAR_体力',50000);NLG.UpChar(p)
  for slot=0,4 do
   local pet=Char.GivePet(p,3004,100);assert(pet>=0);pets[slot+1]=pet
   for n=9,0,-1 do if Pet.GetSkill(pet,n)>=0 then Pet.DelSkill(pet,n) end end
   set(pet,'CHAR_血',get(pet,'CHAR_最大血'));set(pet,'CHAR_最大魔',2000);set(pet,'CHAR_魔',2000)
   M:saveAI(p,pet,{mode='guard'})
  end
  check(Char.SetPetDepartureState(p,0,2)==1,'main pet selected')
  check(Pet.AddSkill(pets[2],6500)==1,'learned area recovery')
  M:saveAI(p,pets[2],{mode='attack',recoveryRules={regen={enabled=true,tech=6500,scope='team',when='start'}}})
  check(M:enable(p),'companions enabled');row=M.active[p].rows[1]
  b=Battle.PVE(p,p,nil,{1},{100},{0});check(b>=0,'isolated native battle');M:formation(b,M.active[p])
  allies={p,pets[1]};for _,r in ipairs(M.active[p].rows) do allies[#allies+1]=r.proxy end
  set(row.proxy,'CHAR_最大魔',2000);set(row.proxy,'CHAR_魔',2000)
  set(row.proxy,'CHAR_敏捷',10000);reset()
  check(M:choose(b,row)[2]==25,'opening AI chooses the center for four allies')
  M.recoveryTarget=function(self,bi,r,rule,t) if bi==b and round>1 then return centers[round] end;return originalTarget(self,bi,r,rule,t) end
  T:AddInterval(100,function()
   if finished then return end
   local success,e=xpcall(function()
    if os.time()-started>35 then error('native area recovery timeout') end
    if Battle.IsWaitingCommand(p)==1 then
     set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',Battle.GetPos(b,p));set(p,'CHAR_BattleCom3',7400)
     set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3)
    end
    if Battle.IsWaitingCommand(pets[1])==1 then Battle.ActionSelect(pets[1],CONST.BATTLE_COM.BATTLE_COM_GUARD,Battle.GetPos(b,pets[1]),7400) end
    M:tick()
   end,debug.traceback)
   if not success then finish(e) end
  end,1)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
