local R={status='RUNNING',checks={},events={},production_database_modified=false}
local Q=assert(getModule('gameQoL'))
local F=assert(getModule('fivePet'))
local T=ModuleBase:createModule('loyaltyProbe'):new();T:load()
local p,b=-1,-1
local pets={}
local started=os.time()
local finished=false
local stage=1
local squadRows={}
local originalDummy=Char.IsDummy
local function get(q,key) return Char.GetData(q,CONST[key]) end
local function set(q,key,v) return Char.SetData(q,CONST[key],v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function loyal(pet,label)
 if get(pet,'宠物_基础忠诚')~=100 or get(pet,'宠物_忠诚')~=100 then
  R.failed_state={label=label,index=pet,base=get(pet,'宠物_基础忠诚'),loyalty=get(pet,'宠物_忠诚'),hp=get(pet,'CHAR_血'),owner=Pet.GetOwner(pet),ownerBattle=Char.GetBattleIndex(p),ownerMode=get(p,'CHAR_BattleMode'),pending=Q.pendingBattle[p]}
 end
 check(get(pet,'宠物_基础忠诚')==100,'base loyalty 100: '..label)
 check(get(pet,'宠物_忠诚')==100,'calculated loyalty 100: '..label)
end
local function lower(pet)
 set(pet,'宠物_基础忠诚',1);set(pet,'宠物_忠诚',1)
end
local function all(label) for i,pet in ipairs(pets) do loyal(pet,label..'/'..i) end end
local function finish(err)
 if finished then return end;finished=true
 if err then R.status='FAIL';R.error=tostring(err) else R.status='PASS' end
 if p>=0 then
  pcall(F.disable,F,p)
  if Char.GetBattleIndex(p)>=0 then pcall(Battle.ExitBattle,p) end
  pcall(Char.DelDummy,p)
 end
 Char.IsDummy=originalDummy
 local f=assert(io.open('__OUTPUT__/loyalty_native.json','wb'));f:write(JSON.encode(R));f:close()
end
local function begin()
 for _,pet in ipairs(pets) do
  set(pet,'CHAR_受伤',0);Pet.UpPet(p,pet)
  set(pet,'CHAR_血',get(pet,'CHAR_最大血'))
  lower(pet)
 end
 if stage==2 then
  check(F:enable(p),'five-pet mode enabled')
  squadRows=F.active[p].rows
 end
 b=Battle.PVE(p,p,nil,{1},{20},{0});check(b>=0,'native battle '..stage)
 if stage==2 then
  -- A dead native proxy exercises five-pet death synchronization at settlement.
  for _,row in ipairs(squadRows) do
   set(row.pet,'CHAR_血',0);set(row.proxy,'CHAR_血',0);row.dead=true
  end
 end
end
Char.IsDummy=function(q) if q==p then return false end;return originalDummy(q) end
local function witness()
T:regCallback('BattleSurpriseEvent',function() return CONST.BATTLE_SurpriseFlag.Normal end)
T:regCallback('DamageCalculateEvent',function(a,d,original,damage,bi)
 if bi==b then
  return a==p and 999999 or 0
 end
 return damage
end)
T:regCallback('BattleDodgeRateEvent',function(bi,a,d,rate) if bi==b then return 0 end;return rate end)
T:regCallback('BeforeBattleTurnEvent',OrderedCallback(function(bi)
 if bi==b then
  R.events[#R.events+1]={kind='turn',stage=stage}
  all('native turn '..stage)
 end
end,-1000))
T:regCallback('BattleStartEvent',function(bi)
 if bi==b then R.events[#R.events+1]={kind='start',stage=stage} end
 return 0
end)
T:regCallback('BattleExitEvent',OrderedCallback(function(q,bi)
 if q==p then R.events[#R.events+1]={kind='exit',stage=stage};all('native exit '..stage) end
end,-1000))
end
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='LOYALTY_NATIVE_TEST'})
 check(p>=0,'isolated native player')
 set(p,'CHAR_账号','LOYALTY_NATIVE_TEST');set(p,'对象_RegistNumber',0)
 set(p,'CHAR_等级',1);set(p,'CHAR_体力',50000);set(p,'CHAR_力量',50000)
 NLG.UpChar(p);set(p,'CHAR_血',get(p,'CHAR_最大血'))
 for slot=0,4 do
  local pet=Char.GivePet(p,3004,1);check(pet>=0,'new pet '..slot)
  pets[#pets+1]=pet;loyal(pet,'immediately after creation '..slot)
  set(pet,'CHAR_等级',200);lower(pet);Pet.UpPet(p,pet)
  loyal(pet,'level 200 pet with level 1 owner and no training '..slot)
  lower(pet);Char.UpCharStatus(pet);loyal(pet,'native status recalculation '..slot)
  set(pet,'CHAR_受伤',25);set(pet,'CHAR_血',0);lower(pet);Pet.UpPet(p,pet)
  loyal(pet,'dead and injured '..slot)
 end
 for key in pairs(Q:settings(p)) do Q:settings(p)[key]=false end
 for _,pet in ipairs(pets) do lower(pet) end
 set(p,'CHAR_BattleMode',1);Q:maintain(p);all('maintenance during combat with all automatic settings off')
 set(p,'CHAR_BattleMode',0)
 CharaStallStartEvent(p)
 for _,pet in ipairs(pets) do lower(pet) end
 Q:maintain(p);all('maintenance while stalled');CharaStallEndEvent(p)
 for _,pet in ipairs(pets) do lower(pet) end
 BeforeCharaSaveEvent(p);all('before save')
 for _,pet in ipairs(pets) do lower(pet) end
 LoginEvent(p);all('login')
 for kind=0,7 do
  lower(pets[1])
  check(BattlePetLeaveCheckEvent(-1,pets[1],kind,0,0,0)==(kind==1 and 1 or 6),'behaviour kind '..kind..' (recall preserved)')
  loyal(pets[1],'behaviour check '..kind)
 end
 check(BattlePetLeaveCheckEvent(-1,p,7,0,0,0)==7,'non-pet behaviour unchanged')
 check(not Q:lockPetLoyalty(-1) and not Q:lockPetLoyalty(p),'invalid index and players ignored')
 Char.DelSlotPet(p,1);Char.DelSlotPet(p,3)
 pets={Char.GetPet(p,0),Char.GetPet(p,2),Char.GetPet(p,4)}
 for _,pet in ipairs(pets) do lower(pet) end
 Q:maintainPetLoyalty(p);all('sparse slots')
 check(reloadModule('gameQoL')~=nil,'module hot reload')
 Q=assert(getModule('gameQoL'))
 witness()
 for _,pet in ipairs(pets) do lower(pet);Pet.UpPet(p,pet) end
 all('status recalculation after hot reload')
 check(Char.SetPetDepartureState(p,0,2)==1,'normal battle pet selected')
 begin()
 local ended
 local key=T:regCallback(function()
  if finished then return end
  local success,error=xpcall(function()
   if os.time()-started>40 then error('native battle timeout') end
   if Char.GetBattleIndex(p)~=b then
    if not ended then ended=os.time() end
    if os.time()-ended<3 or Q.pendingBattle[p] then return end
    all('after actual battle '..stage)
    if stage==1 then stage=2;ended=nil;begin()
    else
     check(#squadRows==2,'two companions participated in five-pet battle')
     for _,row in ipairs(squadRows) do
      check(get(row.pet,'CHAR_血')==0,'five-pet original received proxy death')
      loyal(row.pet,'dead five-pet original')
     end
     finish()
    end
   else
    if Battle.IsWaitingCommand(p)==1 then
     set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(p,'CHAR_BattleCom2',10);set(p,'CHAR_BattleCom3',-1)
     set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_Battle2Com2',-1);set(p,'CHAR_Battle2Com3',-1)
     set(p,'CHAR_BattleMode',3)
    end
    if Battle.IsWaitingCommand(pets[1])==1 then Battle.ActionSelect(pets[1],CONST.BATTLE_COM.BATTLE_COM_ATTACK,10,-1) end
    if stage==2 then F:tick() end
   end
  end,debug.traceback)
  if not success then finish(error) end
 end)
 Char.SetLoopEvent(nil,key,p,200)
end,debug.traceback)
if not ok then finish(err) end
