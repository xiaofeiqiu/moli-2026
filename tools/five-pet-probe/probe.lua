-- Disposable dummies and pets in an independent SQLite server.
local M = ModuleBase:createModule('fivePetNativeProbe')
local report = {client_verified=false, production_modified=false,
  native_tests={}, proxy_test={status='PENDING'}}
local output = '__OUTPUT__/native_result.json'
local function write()
  local f=assert(io.open(output,'w')); f:write(JSON.encode(report)); f:close()
end
local function c(key)
  local value=CONST[key];assert(value,'Missing constant '..key);return value
end
local function get(p,key) return Char.GetData(p,c(key)) end
local function set(p,key,v) return Char.SetData(p,c(key),v) end
local function dummy(name,image)
  local p=Char.CreateDummy({mapType=0,floor=1000,x=150,y=111,
    image=image or 100002,name=name})
  assert(p>=0,'Could not create dummy')
  set(p,'CHAR_等级',100);set(p,'CHAR_体力',100000)
  set(p,'CHAR_魔法',100000);NLG.UpChar(p)
  set(p,'CHAR_血',get(p,'CHAR_最大血'))
  set(p,'CHAR_魔',get(p,'CHAR_最大魔'))
  return p
end
local function pets(p)
  local ar={}
  for slot=0,4 do
    local pet=Char.GivePet(p,3004,1);assert(pet>=0,'Could not give pet')
    ar[#ar+1]=pet
  end
  return ar
end
local function state(p,ar)
  local s={selected_slot=get(p,'CHAR_战宠'),pet_states={}}
  for _,pet in ipairs(ar) do s.pet_states[#s.pet_states+1]=get(pet,'PET_DepartureBattleStatus') end
  return s
end
local function roster(b,ar)
  local s={slots={},own_pet_count=0,ally_count=0}
  local owned={};for _,p in ipairs(ar) do owned[p]=true end
  for pos=0,19 do
    local p=Battle.GetPlayer(b,pos)
    if p>=0 then
      local row={pos=pos,index=p,type=get(p,'CHAR_类型'),owned_pet=owned[p] or false}
      s.slots[#s.slots+1]=row
      if pos<10 then
        s.ally_count=s.ally_count+1
        if owned[p] then s.own_pet_count=s.own_pet_count+1 end
      end
    end
  end
  return s
end
local function native(mode)
  local p=dummy('FIVE_PET_'..mode);local ar=pets(p)
  local r={mode=mode,before=state(p,ar)}
  report.native_tests[#report.native_tests+1]=r
  if mode=='single' then
    r.set_return=Char.SetPetDepartureState(p,0,2)
  elseif mode=='bulk' then
    r.set_return=Char.SetPetDepartureStateAll(p,2,2,2,2,2)
  elseif mode=='sequential' then
    r.set_returns={}
    for slot=0,4 do r.set_returns[#r.set_returns+1]=Char.SetPetDepartureState(p,slot,2) end
  elseif mode=='raw_states' then
    for _,pet in ipairs(ar) do set(pet,'PET_DepartureBattleStatus',2) end
    set(p,'CHAR_战宠',0)
  end
  r.after_set=state(p,ar)
  local b=Battle.PVE(p,p,nil,{1},{10},{0});r.battle=b
  if b>=0 then
    r.roster=roster(b,ar);r.after_entry=state(p,ar)
    Battle.ExitBattle(p)
  end
  for slot=0,4 do Char.DelSlotPet(p,slot) end
  Char.DelDummy(p);write()
end
local function proxy()
  local p=dummy('FIVE_PET_PROXY_OWNER');local ar=pets(p)
  assert(Char.SetPetDepartureState(p,0,2)==1)
  local proxies={};local actors={p,ar[1]}
  for slot=2,5 do
    local pet=ar[slot]
    local q=dummy('PET_PROXY_'..slot,get(pet,'CHAR_形象'))
    for _,key in ipairs({'CHAR_等级','CHAR_最大血','CHAR_最大魔',
      'CHAR_血','CHAR_魔','CHAR_攻击力','CHAR_防御力','CHAR_敏捷','CHAR_精神','CHAR_回复'}) do
      set(q,key,get(pet,key))
    end
    assert(Char.JoinParty(q,p,true)==0,'Proxy party join failed')
    proxies[#proxies+1]=q;actors[#actors+1]=q
  end
  local b=Battle.PVE(p,p,nil,{1},{20},{0});assert(b>=0)
  local target=-1
  for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then target=q;break end end
  assert(target>=0,'No enemy target')
  -- Keep the enemy alive so every companion can perform its own attack.
  set(target,'CHAR_最大血',1000000);set(target,'CHAR_血',1000000)
  set(target,'CHAR_攻击力',1)
  report.proxy_test={status='RUNNING',battle=b,owner=p,
    proxy_count=#proxies,roster=roster(b,ar),actions={},turns=0,
    damage_events={},enemy_hp_before=get(target,'CHAR_血'),
    owned_native_pet_count=1,remaining_pets_are_proxies=true,
    test_enemy_hp_modified=true}
  local r=report.proxy_test;local seen={};local started=os.time()
  local function finish(status)
    r.status=status;r.elapsed=os.time()-started
    for _,q in ipairs(actors) do if Char.IsDummy(q) then Char.UnsetLoopEvent(q) end end
    for _,q in ipairs(proxies) do Battle.ExitBattle(q);Char.LeaveParty(q);Char.DelDummy(q) end
    Battle.ExitBattle(p)
    for slot=0,4 do Char.DelSlotPet(p,slot) end
    Char.DelDummy(p);write();b=-1
  end
  M:regCallback('BattleActionEvent',function(q,c1,c2,c3,n)
    if b<0 or Char.GetBattleIndex(q)~=b then return end
    for _,a in ipairs(actors) do
      if a==q then
        r.actions[#r.actions+1]={index=q,command=c1,number=n}
        if c1==CONST.BATTLE_COM.BATTLE_COM_ATTACK then seen[q]=true end
      end
    end
  end)
  M:regCallback('DamageCalculateEvent',function(attacker,defender,ori,damage,bi)
    if bi==b and defender==target then
      r.damage_events[#r.damage_events+1]={attacker=attacker,damage=damage}
    end
    return damage
  end)
  M:regCallback('AfterBattleTurnEvent',function(bi)
    if bi~=b then return end
    r.turns=r.turns+1
    local count=0;for _,q in ipairs(actors) do if seen[q] then count=count+1 end end
    r.distinct_actors=count
    r.enemy_hp_after=get(target,'CHAR_血')
    local hits,total=0,0
    for _,event in ipairs(r.damage_events) do
      if event.damage>0 then hits=hits+1;total=total+event.damage end
    end
    r.positive_damage_events=hits;r.total_calculated_damage=total
    r.enemy_released_after_turn=r.enemy_hp_after==nil
    if count==#actors and hits>=#actors then finish('PASS')
    elseif r.turns>=3 then finish('FAIL_ACTION_COUNT') else write() end
  end)
  local loop=M:regCallback(function()
    if b<0 then return end
    if os.time()-started>30 then finish('TIMEOUT');return end
    for _,q in ipairs(actors) do
      if Battle.IsWaitingCommand(q)==1 then
        Battle.ActionSelect(q,CONST.BATTLE_COM.BATTLE_COM_ATTACK,Battle.GetPos(b,target),-1)
      end
    end
    -- Dummies have no client; send both character command slots.
    for _,q in ipairs(actors) do
      if Char.IsDummy(q) then
        set(q,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK)
        set(q,'CHAR_BattleCom2',Battle.GetPos(b,target));set(q,'CHAR_BattleCom3',-1)
        set(q,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_GUARD)
        set(q,'CHAR_Battle2Com2',Battle.GetPos(b,q));set(q,'CHAR_Battle2Com3',7400)
        set(q,'CHAR_BattleMode',3)
      end
    end
    write()
  end)
  Char.SetLoopEvent(nil,loop,p,250);write()
end
local ok,err=xpcall(function()
  for _,mode in ipairs({'single','bulk','sequential','raw_states'}) do native(mode) end
  proxy()
end,debug.traceback)
if not ok then report.error=err;write() end
