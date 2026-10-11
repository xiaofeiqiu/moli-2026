local R={status='RUNNING',checks={},production_database_modified=false}
local M=assert(getModule('fivePet'))
local T=ModuleBase:createModule('fivepetDeathProbe'):new();T:load()
local p,pet,b=-1,-1,-1;local rows={};local phase=0;local dying=false;local done=false
local started=os.time()
local function get(q,k) return Char.GetData(q,CONST[k]) end
local function set(q,k,v) return Char.SetData(q,CONST[k],v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function write() local f=assert(io.open('__OUTPUT__/fivepet_death_native.json','wb'));f:write(JSON.encode(R));f:close() end
local function cleanup()
 if p>=0 then M:disable(p);if Char.GetBattleIndex(p)>=0 then Battle.ExitBattle(p) end
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then Char.DelSlotPet(p,slot) end end
  Char.DelDummy(p);p=-1
 end
end
local function finish(err) if done then return end;done=true;pcall(cleanup);R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil;write() end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b and Char.IsEnemy(q) then return 0 end;return rate end)
T:regCallback('BattleDodgeRateEvent',function(bi,a,d,rate) if bi==b then return 0 end;return rate end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi)
 if bi==b then
  if d==p then dying=true;return get(p,'CHAR_血')+10000 end
  return 0
 end
 return damage
end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi==b then local e=Battle.GetPlayer(b,10)
  set(e,'CHAR_魔',10000)
  set(e,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_P_MAGIC);set(e,'CHAR_BattleCom2',Battle.GetPos(b,p));set(e,'CHAR_BattleCom3',1930)
  set(e,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE)
 end
 return false
end)
T:regCallback('BattleBeforeActionEvent',function(bi,q)
 if bi==b and dying and (q==pet or M.proxies[q]) then R.pet_actions_after_death=(R.pet_actions_after_death or 0)+1 end
 return 0
end)
local function start(count,tick)
 phase=phase+1;dying=false;rows={}
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='FIVEPET_DEATH_TEST'});assert(p>=0)
 set(p,'CHAR_等级',50);set(p,'CHAR_体力',50000);NLG.UpChar(p);set(p,'CHAR_血',100)
 for slot=0,count-1 do local q=Char.GivePet(p,3004,1);assert(q>=0);set(q,'CHAR_血',get(q,'CHAR_最大血'));if slot==0 then pet=q end end
 assert(Char.SetPetDepartureState(p,0,2)==1);assert(M:enable(p))
 for _,row in ipairs(M.active[p].rows) do rows[#rows+1]=row;set(row.proxy,'CHAR_敏捷',1) end
 set(p,'CHAR_敏捷',1);set(pet,'CHAR_敏捷',1)
 b=Battle.PVE(p,p,nil,{1},{100},{0});assert(b>=0)
 set(Battle.GetPlayer(b,10),'CHAR_敏捷',10000)
 if tick then set(p,'CHAR_血',0);M:tick();dying=true end
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
 start(5,false)
 T:AddInterval(100,function()
  if done then return end
  local ok,err=xpcall(function()
   assert(os.time()-started<20,'death battle timeout')
   if dying and Char.GetBattleIndex(p)<0 then
    check(dying,'lethal damage observed in case '..phase)
    check(Char.GetBattleIndex(pet)<0,'main pet exits in case '..phase)
    for _,r in ipairs(rows) do check(not Char.IsValidCharIndex(r.proxy) or Char.GetBattleIndex(r.proxy)<0,'companion exits without waiting for next turn in case '..phase) end
    check((R.pet_actions_after_death or 0)==0,'no pet action after lethal damage in case '..phase)
    M:tick();check(M.active[p]==nil,'squad cleaned in case '..phase)
    check(M:enabled(p),'on setting retained in case '..phase)
    set(p,'CHAR_血',0)
    check(not M:enable(p),'dead owner cannot restart squad in case '..phase)
    cleanup()
    if phase==1 then start(1,false) elseif phase==2 then start(5,true) else finish() end
    return
   end
   if Battle.IsWaitingCommand(p)==1 then
    set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',0);set(p,'CHAR_BattleCom3',7400)
    set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3)
   end
   if Battle.IsWaitingCommand(pet)==1 then Battle.ActionSelect(pet,CONST.BATTLE_COM.BATTLE_COM_GUARD,5,7400) end
   M:tick()
  end,debug.traceback)
  if not ok then finish(err) end
 end,1)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
