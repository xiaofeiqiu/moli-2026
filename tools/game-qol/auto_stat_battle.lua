local R={status='RUNNING',checks={},events={},stages={},production_accounts_used=false,client_verified=false}
local p,b=-1,-1
local pets={}
local A=assert(getModule('autoStat'))
local F=assert(getModule('fivePet'))
local T=ModuleBase:createModule('autoStatBattleProbe'):new();T:load()
local stage=1
local started=os.time()
local finishing=false
local before={}
local function get(c,key) return Char.GetData(c,CONST[key]) end
local function set(c,key,value) return Char.SetData(c,CONST[key],value) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function finish(err)
 if finishing then return end;finishing=true
 if err then R.status='FAIL';R.error=tostring(err) else R.status='PASS' end
 if p>=0 then F:disable(p);if Char.GetBattleIndex(p)>=0 then Battle.ExitBattle(p) end;Char.DelDummy(p);p=-1 end
 local f=assert(io.open('__OUTPUT__/auto_stat_battle.json','wb'));f:write(JSON.encode(R));f:close()
end
local function begin()
 before={}
 for _,c in ipairs({p,pets[1],pets[2],pets[3],pets[4],pets[5]}) do
  if c==p then NLG.UpChar(c) else Pet.UpPet(p,c) end
  set(c,'CHAR_血',get(c,'CHAR_最大血'));set(c,'CHAR_魔',get(c,'CHAR_最大魔'))
  set(c,'CHAR_升级点',5);set(c,'CHAR_经验',Char.GetNextExp(c)-1)
  before[c]={level=get(c,'CHAR_等级'),bp=5}
 end
 if stage==2 then check(F:enable(p),'five-pet battle mode enabled alongside automatic allocation') end
 b=Battle.PVE(p,p,nil,{1},{30},{0});check(b>=0,'actual native battle started '..stage)
 if stage==2 then F.active[p].battle=b end
end
T:regCallback('BattleSurpriseEvent',function() return CONST.BATTLE_SurpriseFlag.Normal end)
T:regCallback('DamageCalculateEvent',function(a,d,original,damage,bi)
 if bi==b then
  if a==p or a==pets[1] or F.proxies[a] then return 999999 end
  return 0
 end
 return damage
end)
T:regCallback('LevelUpEvent',function(c,levels) R.events[#R.events+1]={kind='player',char=c,levels=levels,oldBP=get(c,'CHAR_升级点')} end)
T:regCallback('PetLevelUpEvent',function(owner,pet,levels) R.events[#R.events+1]={kind='pet',char=pet,levels=levels,oldBP=get(pet,'CHAR_升级点')} end)
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=223,y=86,image=100002,name='AUTO_STAT_BATTLE'});check(p>=0,'isolated battle player')
 set(p,'CHAR_账号','AUTO_STAT_BATTLE_WITNESS');set(p,'对象_RegistNumber',0)
 set(p,'CHAR_等级',10);set(p,'CHAR_体力',1500);NLG.UpChar(p)
 check(A:setPlan(p,'player',{1,1,1,1,1}),'battle player plan configured')
 for i=1,5 do
  pets[i]=Char.GivePet(p,3004,1);check(pets[i]>=0,'battle pet '..i)
  set(pets[i],'CHAR_等级',10);Pet.UpPet(p,pets[i])
  local w={0,0,0,0,0};w[i]=1
  check(A:setPlan(p,tostring(Pet.GetUUID(pets[i])),w),'independent battle pet scheme '..i)
  F:saveAI(p,pets[i],{mode='attack',tech=0,target='weak',threshold=30})
 end
 check(Char.SetPetDepartureState(p,0,2)==1,'first pet set to normal native battle state')
 begin()
 local key=T:regCallback(function()
  if p<0 or finishing then return end
  local success,error=xpcall(function()
   if os.time()-started>60 then error('native battle timed out at stage '..stage) end
   if Char.GetBattleIndex(p)~=b then
    F:tick()
    if not R.stages[stage] then R.stages[stage]={ended=os.time(),levels={}} end
    -- Let both real module timers finish native pet growth and queued BP work.
    if os.time()-R.stages[stage].ended<1 then return end
    check(get(p,'CHAR_等级')>before[p].level,'actual victory upgrades player '..stage)
    check(get(p,'CHAR_升级点')==5,'actual victory automatically distributes player award '..stage)
    for i=1,5 do
     local c=pets[i];R.stages[stage].levels[i]=get(c,'CHAR_等级')
     if stage==2 or i==1 then
      check(get(c,'CHAR_等级')>before[c].level,'actual victory upgrades pet '..i..'/'..stage)
      check(get(c,'CHAR_升级点')==5,'actual victory automatically distributes pet award '..i..'/'..stage)
     else check(get(c,'CHAR_等级')==before[c].level and get(c,'CHAR_升级点')==5,'standby pet untouched in normal battle '..i) end
    end
    if stage==2 then
     check(F.active[p] and #F.active[p].rows==4,'five-pet companions remain active after automatic allocation')
     for _,row in ipairs(F.active[p].rows) do check(get(row.proxy,'CHAR_攻击力')==get(row.pet,'CHAR_攻击力'),'proxy reflects allocated original-pet stats '..row.slot) end
    end
    b=-1
    if stage==1 then stage=2;begin() else finish() end
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
