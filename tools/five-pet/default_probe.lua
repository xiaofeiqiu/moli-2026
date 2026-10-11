local R={status='RUNNING',checks={}}
local M=assert(getModule('fivePet'))
local Q=assert(getModule('gameQoL'))
local T=ModuleBase:createModule('fivePetDefaultProbe'):new();T:load()
local p,other,b=-1,-1,-1
local pets={}
local stage='initial'
local started=os.time()
local finished=false
local originalPlayers=NLG.GetPlayer
local originalDummy=Char.IsDummy
local originalMessage=NLG.SystemMessage
local messages={}
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=ok and true or false};assert(ok,label) end
local function get(q,key) return Char.GetData(q,CONST[key]) end
local function set(q,key,value) return Char.SetData(q,CONST[key],value) end
local function rescan()
 M.nextAutoCheck=0;M.autoAttempts[p]=nil;M:tick()
end
local function command(msg)
 messages={};check(TalkEvent(p,msg,0,0,0)==0,'consumed '..msg)
 return table.concat(messages,'\n')
end
local function finish(err)
 if finished then return end;finished=true
 if err then R.status='FAIL';R.error=tostring(err) else R.status='PASS' end
 if p>=0 then
  M:setEnabled(p,false)
  if Char.GetBattleIndex(p)>=0 then pcall(Battle.ExitBattle,p) end
  pcall(Char.DelDummy,p);p=-1
 end
 if other>=0 then pcall(Char.DelDummy,other);other=-1 end
 NLG.GetPlayer=originalPlayers;Char.IsDummy=originalDummy;NLG.SystemMessage=originalMessage
 local f=assert(io.open('__OUTPUT__/fivepet_default_native.json','wb'));f:write(JSON.encode(R));f:close()
end
NLG.GetPlayer=function() return p>=0 and {p} or {} end
Char.IsDummy=function(q) if q==p then return false end;return originalDummy(q) end
NLG.SystemMessage=function(q,text,...) if q==p then messages[#messages+1]=text end;return originalMessage(q,text,...) end
T:regCallback('BattleSurpriseEvent',function() return CONST.BATTLE_SurpriseFlag.Normal end)
T:regCallback('DamageCalculateEvent',function(a,d,original,damage,bi)
 if bi==b then return a==p and 999999 or 0 end;return damage
end)
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=151,y=113,image=100002,name='FIVE_PET_DEFAULT_TEST'})
 check(p>=0,'isolated native player created')
 set(p,'CHAR_账号','FIVE_DEFAULT_'..os.time());set(p,'对象_RegistNumber',0)
 check(M:enabled(p),'five-pet preference defaults on')
 local cfg=Q:settings(p)
 check(cfg.autoidentify and cfg.autosell,'identify and stone selling default on')
 check(cfg.autosort and cfg.autorepair,'sort and repair defaults remain on')
 rescan();check(not M.active[p],'fewer than five pets does not create companions')
 for slot=0,4 do pets[slot+1]=Char.GivePet(p,3004,1);check(pets[slot+1]>=0,'pet fixture '..slot) end
 Char.SetPetDepartureState(p,0,0)
 set(p,'CHAR_战宠',-1)
 rescan();check(not M.active[p],'unselected main pet waits without creating companions')
 check(Char.SetPetDepartureState(p,0,2)==1,'normal battle pet selected')
 set(pets[5],'CHAR_血',0)
 rescan();check(not M.active[p] and next(M.proxies)==nil,'dead pet rejects automatic mode without partial companions')
 set(pets[5],'CHAR_血',get(pets[5],'CHAR_最大血'))
 other=Char.CreateDummy({mapType=0,floor=1000,x=151,y=113,image=100002,name='FIVE_PET_REAL_TEAMMATE'})
 check(other>=0 and Char.JoinParty(other,p,true)==0,'ordinary teammate joins before mode starts')
 rescan();check(not M.active[p],'ordinary party is preserved while default-on preference waits')
 Char.LeaveParty(other);Char.DelDummy(other);other=-1
 rescan()
 check(M.active[p] and #M.active[p].rows==4 and Char.PartyNum(p)==5,'eligible player automatically receives exactly four companions')
 command('/fivepet off');rescan()
 check(not M:enabled(p) and not M.active[p] and next(M.proxies)==nil,'explicit off persists and prevents automatic restart')
 M.configs[p]=nil
 check(not M:enabled(p),'off preference read back from character extension')
 check(reloadModule('fivePet')~=nil,'five-pet module reload succeeds')
 M=assert(getModule('fivePet'));rescan()
 check(not M:enabled(p) and not M.active[p],'off remains off after module reload')
 LoginEvent(p);rescan()
 check(not M.active[p] and not M:enabled(p),'login respects explicit off')
 command('/fivepet on')
 check(M.active[p] and M:enabled(p),'explicit on resumes five-pet mode')
 check(M:saveAI(p,pets[2],{mode='guard',tech=0,target='weak',threshold=30}),'AI configuration saved with enabled preference')
 M:disable(p)
 check(M:enabled(p),'temporary cleanup preserves on preference')
 rescan();check(M.active[p] and M:ai(p,pets[2]).mode=='guard','automatic resume preserves pet AI')
 M:disable(p);set(pets[5],'CHAR_血',0);rescan()
 check(not M.active[p],'dead companion temporarily suspends mode')
 set(pets[5],'CHAR_血',get(pets[5],'CHAR_最大血'));rescan()
 check(M.active[p],'recovered pets automatically resume mode')
 command('/fivepet off');M:menu(p)
 local menu=M.menus[p];check(menu~=nil,'NPC menu opens while mode is off')
 M:answer(M.npc,p,menu.seq,1,'1')
 check(M:enabled(p) and M.active[p],'NPC toggle enables persisted preference')
 M:menu(p);menu=M.menus[p];M:answer(M.npc,p,menu.seq,1,'1');rescan()
 check(not M:enabled(p) and not M.active[p],'NPC toggle off prevents automatic restart')
 check(command('/help fivepet'):find('默认开启',1,true)~=nil,'help explains default-on mode')
 check(command('/help autoidentify'):find('默认开启',1,true)~=nil,'help explains default-on identify')
 check(command('/help autosell'):find('默认开启',1,true)~=nil,'help explains default-on stone selling')
 command('/fivepet on')
 set(p,'CHAR_等级',20);set(p,'CHAR_体力',50000);set(p,'CHAR_力量',50000)
 NLG.UpChar(p);set(p,'CHAR_血',get(p,'CHAR_最大血'));set(p,'CHAR_魔',get(p,'CHAR_最大魔'))
 b=Battle.PVE(p,p,nil,{1},{20},{0});check(b>=0,'native five-pet battle started')
 local roster=0
 for pos=0,19 do if Battle.GetPlayer(b,pos)>=0 then roster=roster+1 end end
 check(roster==7,'actual battle has owner, five pets and enemy')
 stage='battle'
 local ended
 local callback=T:regCallback(function()
  if finished then return end
  local success,error=xpcall(function()
   if os.time()-started>45 then error('five-pet default test timed out at '..stage) end
   if Char.GetBattleIndex(p)~=b then
    ended=ended or os.time()
    if os.time()-ended<1 then return end
    check(M.active[p] and M:enabled(p),'native victory retains enabled five-pet mode')
    check(Char.PartyNum(p)==5 and #M.active[p].rows==4,'native victory retains four companions without duplicates')
    command('/fivepet off');rescan()
    check(not M.active[p] and next(M.proxies)==nil,'off after victory removes all companions')
    finish()
   elseif Battle.IsWaitingCommand(p)==1 then
    set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(p,'CHAR_BattleCom2',10);set(p,'CHAR_BattleCom3',-1)
    set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_Battle2Com2',-1);set(p,'CHAR_Battle2Com3',-1)
    set(p,'CHAR_BattleMode',3)
   end
   local normal=pets[1]
   if Char.GetBattleIndex(normal)==b and Battle.IsWaitingCommand(normal)==1 then
    Battle.ActionSelect(normal,CONST.BATTLE_COM.BATTLE_COM_ATTACK,10,-1)
   end
  end,debug.traceback)
  if not success then finish(error) end
 end)
 Char.SetLoopEvent(nil,callback,p,200)
end,debug.traceback)
if not ok then finish(err) end
