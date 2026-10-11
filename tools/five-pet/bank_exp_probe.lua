-- Real native bank slots; fixture setup moves only disposable pets, never player data.
local M=assert(getModule('fivePet'))
local A=assert(getModule('autoStat'))
local T=ModuleBase:createModule('bankExpProbe'):new();T:load()
local R={status='RUNNING',checks={},native_bank_inventory=true,bank_lookup_injected=false,production_database_modified=false}
local p,donor,b=-1,-1,-1
local bank,before,session={},{},nil
local started=os.time();local finished=false;local fixtureReady=false
local messages={};local nativeMessage=NLG.SystemMessage
NLG.SystemMessage=function(q,message,...)
 if q==p and message:find('获得经验：',1,true) then messages[#messages+1]=message end
 return nativeMessage(q,message,...)
end
local function g(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function s(q,k,v) local field=assert(CONST[k],k);return Char.SetData(q,field,v) end
local function write() local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close() end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};write();assert(ok,label) end
local function finish(err)
 if finished then return end;finished=true
 if p>=0 then pcall(Battle.ExitBattle,p);pcall(M.disable,M,p) end
 NLG.SystemMessage=nativeMessage
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil;write()
end
local function player(name)
 local q=Char.CreateDummy({mapType=0,floor=1000,x=151,y=113,image=100002,name=name})
 assert(q>=0);s(q,'CHAR_等级',80);s(q,'CHAR_体力',50000);NLG.UpChar(q)
 s(q,'CHAR_血',g(q,'CHAR_最大血'));return q
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi)
 if bi==b then return Char.IsEnemy(d) and 999999 or 0 end;return damage
end)
T:regCallback('PetLevelUpEvent',function(owner,pet,levels)
 if owner==p then R.upgrades=R.upgrades or {};R.upgrades[#R.upgrades+1]={pet=pet,levels=levels,old_points=g(pet,'CHAR_升级点')} end
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  p=player('BANK_EXP_PLAYER');donor=player('BANK_EXP_DONOR')
  for slot=0,4 do check(Char.GivePet(p,3004,1)>=0,'carried original '..slot) end
  local fixture={player=p,donor=donor,player_pointer=tostring(Char.GetCharPointer(p)),donor_pointer=tostring(Char.GetCharPointer(donor)),pets={}}
  for slot=0,4 do
   local pet=Char.GivePet(donor,3004,1);assert(pet>=0);bank[slot]=pet
   s(pet,'CHAR_名字','BANK_EXP_'..slot);s(pet,'CHAR_等级',slot==0 and 1 or 10+slot)
   s(pet,'CHAR_升级点',7);s(pet,'CHAR_经验',slot==0 and Char.GetNextExp(pet)-1 or 0)
   Char.UpCharStatus(pet);s(pet,'CHAR_血',g(pet,'CHAR_最大血'))
   before[slot]={xp=g(pet,'CHAR_经验'),level=g(pet,'CHAR_等级'),strength=g(pet,'CHAR_力量'),uuid=Pet.GetUUID(pet)}
   fixture.pets[#fixture.pets+1]={index=pet,pointer=tostring(Char.GetCharPointer(pet))}
  end
  local f=assert(io.open('__OUTPUT__/bank_fixture_request.tmp','wb'));f:write(JSON.encode(fixture));f:close()
  assert(os.rename('__OUTPUT__/bank_fixture_request.tmp','__OUTPUT__/bank_fixture_request.json'))
  T:AddInterval(100,function()
   if finished then return end
   local yes,error=xpcall(function()
    if os.time()-started>40 then error('bank experience probe timed out') end
    if not fixtureReady then
     local ready=io.open('__OUTPUT__/bank_fixture_ready','rb');if not ready then return end;ready:close();fixtureReady=true
     for slot=0,4 do check(Char.GetPoolPet(p,slot)==bank[slot],'real native bank slot '..slot) end
     check(Char.PetNum(donor)==0 and Char.PetNum(p)==5,'bank originals are absent from carried inventories')
     check(Pet.UpPet(p,bank[0])==-5,'native UpPet rejects a bank original')
     check(A:setPlan(p,tostring(Pet.GetUUID(bank[0])),{0,1,0,0,0},true),'bank automatic strength allocation enabled')
     check(Char.SetPetDepartureState(p,0,2)==1,'main pet selected')
     check(M:enable(p),'native bank squad enabled');session=M.active[p]
     check(#session.companions==4,'exactly four bank originals participate')
     b=Battle.PVE(p,p,nil,{1},{100},{0});check(b>=0,'native victory battle started')
     return
    end
    if Char.GetBattleIndex(p)==b then
     if Battle.IsWaitingCommand(p)==1 then
      s(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);s(p,'CHAR_BattleCom2',10);s(p,'CHAR_BattleCom3',-1)
      s(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);s(p,'CHAR_BattleMode',3)
     end
     if Battle.IsWaitingCommand(session.normal)==1 then Battle.ActionSelect(session.normal,CONST.BATTLE_COM.BATTLE_COM_GUARD,5,7400) end
     M:tick();return
    end
    M:tick();A:flushOwner(p)
    R.bank_results={}
    for slot=0,4 do
     local pet=bank[slot];R.bank_results[#R.bank_results+1]={slot=slot,before=before[slot],xp=g(pet,'CHAR_经验'),level=g(pet,'CHAR_等级'),points=g(pet,'CHAR_升级点'),strength=g(pet,'CHAR_力量')}
     check(Char.GetPoolPet(p,slot)==pet and Pet.GetUUID(pet)==before[slot].uuid,'bank identity and inventory preserved '..slot)
     if slot==0 then
      check(g(pet,'CHAR_等级')==2,'bank original levels up at native experience threshold')
      check(g(pet,'CHAR_力量')>=before[slot].strength+200 and g(pet,'CHAR_升级点')==7,'bank native growth and automatic allocation preserve old points')
     elseif slot<4 then check(g(pet,'CHAR_经验')>before[slot].xp,'participating bank original gains experience '..slot)
     else check(g(pet,'CHAR_经验')==before[slot].xp and g(pet,'CHAR_等级')==before[slot].level,'fifth bank slot receives no battle experience') end
    end
    check(#messages==4,'one experience message for each participating bank pet')
    check(M.active[p] and not session.battle,'victory finishes bank settlement and keeps squad')
    for _,row in ipairs(session.rows) do check(g(row.proxy,'CHAR_等级')==g(row.pet,'CHAR_等级'),'carrier level restored '..row.slot) end
    local xp,level=g(bank[0],'CHAR_经验'),g(bank[0],'CHAR_等级')
    M:finish(session);check(g(bank[0],'CHAR_经验')==xp and g(bank[0],'CHAR_等级')==level,'repeat settlement cannot duplicate experience or growth')
    check(#messages==4,'repeat settlement does not repeat experience messages')
    local dead=session.companions[2];local deadXP=g(dead.pet,'CHAR_经验')
    s(dead.proxy,'CHAR_血',0);dead.xp=123;session.battle=-1
    M:finish(session)
    check(g(dead.pet,'CHAR_经验')==deadXP and dead.xp==0,'fallen bank pet receives no queued experience')
    check(g(dead.pet,'CHAR_血')==0,'fallen bank original remains fallen after growth refresh')
    M:disable(p)
    for slot=0,4 do check(Char.GetPoolPet(p,slot)==bank[slot],'cleanup keeps bank original '..slot) end
    finish()
   end,debug.traceback)
   if not yes then finish(error) end
  end,1)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
