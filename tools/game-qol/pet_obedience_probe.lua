local R={status='RUNNING',checks={},trace={},production_database_modified=false}
local T=ModuleBase:createModule('petObedienceProbe'):new();T:load()
local p,pet,b=-1,-1,-1
local rounds=0;local calls=0;local attacks=0;local finished=false;local started=os.time()
local function g(q,k) return Char.GetData(q,CONST[k]) end
local function s(q,k,v) return Char.SetData(q,CONST[k],v) end
local function write() local f=assert(io.open('__OUTPUT__/pet_obedience_native.json','wb'));f:write(JSON.encode(R));f:close() end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function finish(err)
 if finished then return end;finished=true
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil;R.rounds=rounds;R.native_pet_checks=calls
 if p>=0 then pcall(Battle.ExitBattle,p);pcall(Char.DelDummy,p) end
 write()
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('DamageCalculateEvent',function(a,d,original,damage,bi)
 if bi==b then if a==pet then attacks=attacks+1 end;return 0 end;return damage
end)
T:regCallback('BattleDodgeRateEvent',function(bi,a,d,rate) if bi==b then return 0 end;return rate end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi~=b then return end
 for pos=10,19 do local enemy=Battle.GetPlayer(bi,pos);if enemy>=0 then
  s(enemy,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD)
  s(enemy,'CHAR_BattleCom2',pos);s(enemy,'CHAR_BattleCom3',7400)
 end end
end)
T:regCallback('BattlePetLeaveCheckEvent',OrderedCallback(function(bi,q,kind,c1,c2,c3)
 if bi==b then
  calls=calls+1
  R.trace[#R.trace+1]={when='before',q=q,isPet=Char.IsPet(q),kind=kind,c1=c1,c2=c2,c3=c3,base=g(q,'宠物_基础忠诚'),loyalty=g(q,'宠物_忠诚')}
  -- Exercise the native return path, including escape, in the disposable server.
  if q==pet and kind~=1 then return rounds%6+2 end
 end
 return kind
end,10000))
T:regCallback('BattlePetLeaveCheckEvent',OrderedCallback(function(bi,q,kind,c1,c2,c3)
 if bi==b then
  R.trace[#R.trace+1]={when='after',q=q,isPet=Char.IsPet(q),kind=kind,c1=c1,c2=c2,c3=c3}
  check(q~=pet or kind==6 or kind==1,'native disobedience type suppressed '..rounds)
 end
 return kind
end,-10000))
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished then return end
 local ok,err=xpcall(function()
  rounds=rounds+1
  local slots={};for pos=0,19 do slots[#slots+1]={pos=pos,q=Battle.GetPlayer(b,pos)} end
  R.trace[#R.trace+1]={when='turn_state',round=rounds,command=g(pet,'CHAR_BattleCom1'),pos=Battle.GetPos(b,pet),petBattle=Char.GetBattleIndex(pet),hp=g(pet,'CHAR_血'),slots=slots}
  check(Battle.GetPos(b,pet)>=0,'pet still in native battle '..rounds)
  check(g(pet,'宠物_基础忠诚')==100 and g(pet,'宠物_忠诚')==100,'native loyalty 100 '..rounds)
  R.trace[#R.trace+1]={when='turn',round=rounds,command=g(pet,'CHAR_BattleCom1'),pos=Battle.GetPos(b,pet)}
  check(attacks==rounds,'selected attack executed once '..rounds)
  if rounds>=8 then
   check(calls>=8,'native engine invoked leave check')
   check(BattlePetLeaveCheckEvent(b,pet,1,0,0,0)==1,'deliberate recall preserved')
   finish()
  else write() end
 end,debug.traceback)
 if not ok then finish(err) end
end)
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='PET_OBEDIENCE_TEST'});check(p>=0,'isolated player')
 s(p,'CHAR_账号','PET_OBEDIENCE_TEST');s(p,'对象_RegistNumber',0);s(p,'CHAR_等级',1);s(p,'CHAR_体力',50000);NLG.UpChar(p);s(p,'CHAR_血',g(p,'CHAR_最大血'))
 pet=Char.GivePet(p,3004,1);check(pet>=0,'isolated level 1 pet');Pet.UpPet(p,pet);s(pet,'CHAR_血',g(pet,'CHAR_最大血'))
 check(Char.SetPetDepartureState(p,0,2)==1,'normal main battle pet selected')
 b=Battle.PVE(p,p,nil,{1},{20},{0});check(b>=0,'native battle created')
 T:AddInterval(100,function()
  if finished then return end
  local success,error=xpcall(function()
   if os.time()-started>48 then error('native battle timeout') end
   if Char.GetBattleIndex(p)~=b then error('battle ended unexpectedly') end
   if Battle.IsWaitingCommand(p)==1 then
    s(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);s(p,'CHAR_BattleCom2',-1);s(p,'CHAR_BattleCom3',7400)
    s(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);s(p,'CHAR_Battle2Com2',-1);s(p,'CHAR_Battle2Com3',-1);s(p,'CHAR_BattleMode',3)
   end
   if Battle.IsWaitingCommand(pet)==1 then Battle.ActionSelect(pet,CONST.BATTLE_COM.BATTLE_COM_ATTACK,10,7300) end
  end,debug.traceback)
  if not success then finish(error) end
 end,1)
 write()
end,debug.traceback)
if not ok then finish(err) end
