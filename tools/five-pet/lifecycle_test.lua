-- Separate native battle cases. No character database is copied into this server.
local M=getModule('fivePet')
local T=ModuleBase:createModule('fivePetLifecycleTest')
local R={status='RUNNING',checks={},trace={},client_verified=false}
local OUT='__OUTPUT__/lifecycle_result.json'
local p=-1;local pets={};local b=-1;local row;local stage='death';local rounds=0;local started=os.time()
local function write() local f=assert(io.open(OUT,'w'));f:write(JSON.encode(R));f:close() end
local function g(q,k) return Char.GetData(q,CONST[k]) end
local function s(q,k,v) return Char.SetData(q,CONST[k],v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label);write() end
local function cleanup()
 if p>=0 then M:disable(p);Battle.ExitBattle(p)
  for n=0,4 do if Char.GetPet(p,n)>=0 then Char.DelSlotPet(p,n) end end
  Char.DelDummy(p);p=-1
 end
end
local function begin()
 p=Char.CreateDummy({mapType=0,floor=1000,x=151,y=113,image=100002,name='FIVE_PET_LIFECYCLE_TEST'})
 assert(p>=0);s(p,'CHAR_等级',50);s(p,'CHAR_体力',50000);NLG.UpChar(p)
 s(p,'CHAR_血',g(p,'CHAR_最大血'))
 for n=1,5 do local pet=Char.GivePet(p,3004,1);pets[n]=pet;assert(pet>=0)
  M:saveAI(p,pet,{mode='guard',tech=0,target='weak',threshold=30}) end
 assert(Char.SetPetDepartureState(p,0,2)==1);check(M:enable(p),'enabled for native lifecycle test')
 row=M.active[p].rows[1]
 b=Battle.PVE(p,p,nil,{1},{20},{0});assert(b>=0);M.active[p].battle=b
end
T:regCallback('BattleSurpriseEvent',function()return 0 end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi~=b then return end
 if stage=='death' then
  local enemy=Battle.GetPlayer(b,10)
  s(enemy,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK)
  s(enemy,'CHAR_BattleCom2',Battle.GetPos(b,row.proxy));s(enemy,'CHAR_BattleCom3',-1)
 end
end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi)
 if bi==b and stage=='death' and d==row.proxy then return 9999 end
 return damage
end)
T:regCallback('BattleInjuryEvent',function(d,a,bi,inj,new)
 if bi==b and d==row.proxy then R.trace[#R.trace+1]={event='injury',hp=g(d,'CHAR_血'),injury=new} end
 return new
end)
T:regCallback('ResetCharaBattleStateEvent',function(q)
 if q==row.proxy then R.trace[#R.trace+1]={event='reset',hp=g(q,'CHAR_血')} end
end)
T:regCallback('BattleExitEvent',function(q,bi,kind)
 if bi==b then R.trace[#R.trace+1]={event='exit',index=q,kind=kind,hp=g(q,'CHAR_血')} end
end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate)
 if bi==b and q==p and stage=='escape' then return 1 end
 return rate
end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b then return end
 local ok,e=xpcall(function()
  rounds=rounds+1
  if stage=='death' then
   R.trace[#R.trace+1]={event='death-turn',proxy_hp=g(row.proxy,'CHAR_血'),pet_hp=g(row.pet,'CHAR_血'),mode=g(row.proxy,'CHAR_BattleMode')}
   if g(row.proxy,'CHAR_血')==0 or row.dead then
    check(g(row.pet,'CHAR_血')==0,'native lethal hit writes zero HP to original pet')
    check(g(row.pet,'CHAR_受伤')>=0,'native injury is preserved')
    M:disable(p);Battle.ExitBattle(p);stage='wait_escape'
   elseif rounds>=3 then error('Native enemy did not kill configured target') end
  end
  write()
 end,debug.traceback)
 if not ok then R.status='FAIL';R.error=e;write();cleanup();b=-1 end
end)
local ok,e=xpcall(begin,debug.traceback)
if not ok then R.status='FAIL';R.error=e;write();cleanup() end
local loop=M:regCallback(function()
 local ok,e=xpcall(function()
  if p<0 then return end
  if os.time()-started>30 then error('Lifecycle native test timeout at '..stage) end
  if stage=='wait_escape' then
   if Char.GetBattleIndex(p)>=0 then return end
   for _,pet in ipairs(pets) do s(pet,'CHAR_血',g(pet,'CHAR_最大血'));Pet.UpPet(p,pet) end
   check(M:enable(p),'enabled after native death cleanup')
   row=M.active[p].rows[1];stage='escape';rounds=0
   b=Battle.PVE(p,p,nil,{1},{1},{0});assert(b>=0);M.active[p].battle=b
  end
  if stage=='escape' and not M.active[p] then
   check(next(M.proxies)==nil,'native escape removes all four proxies')
   check(Char.PartyNum(p)<=1,'native escape has no ghost party')
   R.status='PASS';write();cleanup();b=-1;return
  end
  if Battle.IsWaitingCommand(p)==1 then
   s(p,'CHAR_BattleCom1',stage=='escape' and CONST.BATTLE_COM.BATTLE_COM_ALLESCAPE or CONST.BATTLE_COM.BATTLE_COM_GUARD)
   s(p,'CHAR_BattleCom2',-1);s(p,'CHAR_BattleCom3',stage=='escape' and -1 or 7400)
   s(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);s(p,'CHAR_Battle2Com2',-1);s(p,'CHAR_Battle2Com3',-1);s(p,'CHAR_BattleMode',3)
  end
  if Battle.IsWaitingCommand(pets[1])==1 then Battle.ActionSelect(pets[1],CONST.BATTLE_COM.BATTLE_COM_GUARD,Battle.GetPos(b,pets[1]),7400) end
  M:tick();write()
 end,debug.traceback)
 if not ok then R.status='FAIL';R.error=e;write();cleanup();b=-1 end
end)
if p>=0 then Char.SetLoopEvent(nil,loop,p,250) end
