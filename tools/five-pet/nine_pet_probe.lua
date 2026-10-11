-- Native combat; only bank lookup uses disposable carried-pet fixtures.
local R={status='RUNNING',checks={},rounds=0,before_actions={},production_database_modified=false,bank_lookup_injected=true}
local M=assert(getModule('fivePet'))
local T=ModuleBase:createModule('ninePetProbe'):new();T:load()
local p,bankOwner,b=-1,-1,-1
local bank,all,beforeMP={},{},{};local finished=false;local started=os.time();local victoryXP={}
local originalPool=Char.GetPoolPet
Char.GetPoolPet=function(q,slot) if q==p then return bank[slot] or -1 end;return originalPool(q,slot) end
local function g(q,k) return Char.GetData(q,CONST[k]) end
local function s(q,k,v) return Char.SetData(q,CONST[k],v) end
local function write() local f=assert(io.open('__OUTPUT__/nine_pet_native.json','wb'));f:write(JSON.encode(R));f:close() end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};write();assert(ok,label) end
local function dispose(q)
 if q<0 then return end;pcall(Battle.ExitBattle,q)
 for slot=0,4 do if Char.GetPet(q,slot)>=0 then pcall(Char.DelSlotPet,q,slot) end end
 pcall(Char.DelDummy,q)
end
local function finish(err)
 if finished then return end;finished=true;R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 if p>=0 then pcall(Battle.ExitBattle,p);pcall(M.disable,M,p) end
 dispose(p);dispose(bankOwner);Char.GetPoolPet=originalPool;write()
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b then return 0 end;return rate end)
T:regCallback('DamageCalculateEvent',function(a,d,o,damage,bi)
 if bi==b then if R.phase=='victory' and all[a] and Char.IsEnemy(d) then return 999999 end;return 0 end;return damage
end)
T:regCallback('GetExpEvent',function(q,xp)
 R.exp_events=R.exp_events or {};R.exp_events[#R.exp_events+1]={index=q,xp=xp,phase=R.phase or 'rounds'};return xp
end)
T:regCallback('BattleBeforeActionEvent',function(bi,q)
 if bi==b and all[q] then
  local turn=tostring(Battle.GetTurn(bi));local id=tostring(q)
  R.before_actions[id]=R.before_actions[id] or {};R.before_actions[id][turn]=true
 end;return 0
end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi==b and M.active[p] then for _,row in ipairs(M.active[p].companions) do beforeMP[row.proxy]=g(row.proxy,'CHAR_魔') end end
end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished or R.postChecksScheduled or R.phase=='victory' then return end
 local ok,err=xpcall(function()
  R.rounds=R.rounds+1;local turn=Battle.GetTurn(bi);local session=assert(M.active[p])
  for q in pairs(all) do check(R.before_actions[tostring(q)] and R.before_actions[tostring(q)][tostring(turn)],'ally acts in native turn '..turn..':'..q) end
  for _,row in ipairs(session.companions) do
   check(row.command and row.command[3]==1930,'bank pet automatically selects learned spell '..row.bankSlot..' turn '..turn)
   check(g(row.proxy,'CHAR_魔')==beforeMP[row.proxy]-10,'bank spell costs exactly 10 MP '..row.bankSlot..' turn '..turn)
   check(g(row.pet,'CHAR_魔')==g(row.proxy,'CHAR_魔'),'spent MP reaches bank original '..row.bankSlot..' turn '..turn)
  end
  if R.rounds<3 or R.postChecksScheduled then return end
  R.postChecksScheduled=true
  T:AddInterval(100,function()
   local success,failure=xpcall(function()
  local first=session.companions[1];local original=first.pet;local uuid=Pet.GetUUID(original)
  local xp=g(original,'CHAR_经验');GetExpEvent(first.proxy,123)
  s(first.proxy,'CHAR_血',g(first.proxy,'CHAR_血')-7);s(first.proxy,'CHAR_受伤',10)
  local hp,mp=g(first.proxy,'CHAR_血'),g(first.proxy,'CHAR_魔')
  Battle.ExitBattle(p);M:finish(session)
  check(g(original,'CHAR_经验')==xp+123,'bank experience forwarded once')
  check(g(original,'CHAR_血')==hp and g(original,'CHAR_魔')==mp and g(original,'CHAR_受伤')>=10,'bank HP MP injury retained after battle')
  check(Pet.GetUUID(original)==uuid and Char.GetPet(bankOwner,0)==original,'bank identity and ownership preserved')
  M:finish(session);check(g(original,'CHAR_经验')==xp+123,'repeated finish cannot duplicate bank experience')
  local proxies={};for _,row in ipairs(M:actors(session)) do proxies[#proxies+1]=row.proxy end
  M:disable(p)
  for _,q in ipairs(proxies) do check(not Char.IsValidCharIndex(q),'battle proxy disposed '..q) end
  check(Char.PetNum(bankOwner)==4 and Char.PetNum(p)==5,'all nine originals retained')
  check(M:saveAI(p,bank[0],{mode='guard'}),'bank full-defense preference saves by source UUID')
  -- Disconnected dummy fixtures have no client acknowledgement to clear mode.
  s(p,'CHAR_BattleIndex',-1);s(p,'CHAR_BattleMode',0)
  s(p,'CHAR_地图类型',g(M.npc,'CHAR_地图类型'));s(p,'CHAR_地图',g(M.npc,'CHAR_地图'))
  s(p,'CHAR_X',g(M.npc,'CHAR_X'));s(p,'CHAR_Y',g(M.npc,'CHAR_Y')+1)
  M:menu(p);local menu=M.menus[p]
  R.menu_trace={near=M:near(p),battle=Char.GetBattleIndex(p),normal=g(p,'CHAR_战宠'),options=menu and #menu.options,allOptions=menu and menu.allOptions and #menu.allOptions}
  check(menu and menu.allOptions and #menu.allOptions==10,'commander lists eight AI pets with pagination')
  local nextPage;for i,o in ipairs(menu.options) do if o.action=='menuPage' then nextPage=i end end
  check(nextPage~=nil,'next-page entry exists')
  M:answer(M.npc,p,menu.seq,1,tostring(nextPage));check(M.menus[p] and M.menus[p].page==2,'next page opens bank choices')
  local saved=bank[1];bank[1]=nil
  check(M:enable(p),'partial bank squad starts')
  check(#M.active[p].companions==3 and M.active[p].companions[2].bankSlot==2,'empty bank slot skipped without shifting sources')
  bank[1]=saved;M:tick();check(M.active[p]==nil,'bank roster change safely rebuilds squad')
  check(M:enable(p),'nine-pet squad restarts after bank change');session=M.active[p]
  local extra=session.companions[1];Pet.DelSkill(extra.pet,0);Pet.AddSkill(extra.pet,7400);M:refresh(extra)
  check(Pet.GetSkill(extra.proxy,0)==7400,'changed bank skill refreshes battle pet')
  b=Battle.PVE(p,p,nil,{1},{100},{0});check(b>=0,'owner-death battle starts with nine pets')
  local actors=M:actors(session);s(p,'CHAR_血',0)
  session.battle=b
  check(session.endingDeath or M:endOnOwnerDeath(b,session),'owner death ends nine-pet battle')
  for _,row in ipairs(actors) do
   local present=false;for pos=0,19 do if Battle.GetPlayer(b,pos)==row.proxy then present=true end end
   check(not present,'companion leaves roster on owner death '..row.proxy)
  end
  M:tick();check(M.active[p]==nil,'owner-death tick disposes all proxies')
  check(Char.PetNum(bankOwner)==4,'owner death keeps bank originals')
  T:AddInterval(100,function()
   local yes,error=xpcall(function()
    s(p,'CHAR_BattleIndex',-1);s(p,'CHAR_BattleMode',0)
    check(getModule('gameQoL'):heal(p),'heal restores carried pets and bank originals')
    for slot=0,3 do check(g(bank[slot],'CHAR_血')==g(bank[slot],'CHAR_最大血') and g(bank[slot],'CHAR_魔')==g(bank[slot],'CHAR_最大魔'),'bank original fully healed '..slot) end
    check(M:enable(p),'nine-pet victory squad starts');session=M.active[p]
    all={};all[p]=true;all[session.normal]=true;for _,r in ipairs(M:actors(session)) do all[r.proxy]=true end
    for slot=0,4 do local pet=Char.GetPet(p,slot);victoryXP[pet]=g(pet,'CHAR_经验') end
    for slot=0,3 do victoryXP[bank[slot]]=g(bank[slot],'CHAR_经验') end
    R.phase='victory';b=Battle.PVE(p,p,nil,{1},{100},{0});check(b>=0,'native victory battle starts')
   end,debug.traceback)
   if not yes then finish(error) end
  end,0)
   end,debug.traceback)
   if not success then finish(failure) end
  end,0)
 end,debug.traceback)
 if not ok then finish(err) end
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  local function player(name)
   local q=Char.CreateDummy({mapType=g(M.npc,'CHAR_地图类型'),floor=g(M.npc,'CHAR_地图'),x=g(M.npc,'CHAR_X'),y=g(M.npc,'CHAR_Y')+1,image=100002,name=name})
   assert(q>=0);s(q,'CHAR_等级',50);s(q,'CHAR_体力',50000);NLG.UpChar(q);s(q,'CHAR_血',g(q,'CHAR_最大血'));return q
  end
  p=player('NINE_PET_PROBE');bankOwner=player('NINE_PET_BANK_FIXTURE')
  local growth=Char.GivePet(bankOwner,3004,1);assert(growth>=0)
  s(growth,'CHAR_经验',1000000);local before=g(growth,'CHAR_等级');Char.UpCharStatus(growth)
  local afterStatus=g(growth,'CHAR_等级');s(p,'CHAR_等级',1)
  M:updatePet(bankOwner,{bankSlot=0,carrier=p,pet=growth})
  R.growth_trace={before=before,afterStatus=afterStatus,afterUpPet=g(growth,'CHAR_等级')}
  check(g(growth,'CHAR_等级')>afterStatus and g(p,'CHAR_等级')==1,'native bank growth uses real owner level and restores carrier level')
  s(p,'CHAR_等级',50)
  Char.DelSlotPet(bankOwner,0)
  for slot=0,4 do check(Char.GivePet(p,3004,1)>=0,'five carried originals '..slot) end
  for slot=0,3 do
   local pet=Char.GivePet(bankOwner,3004,1);check(pet>=0,'four bank source fixtures '..slot);bank[slot]=pet
   s(pet,'CHAR_名字','BANK_PET_'..slot);s(pet,'CHAR_等级',25+slot)
   s(pet,'CHAR_体力',20000);s(pet,'CHAR_魔法',20000);Char.UpCharStatus(pet)
   s(pet,'CHAR_血',g(pet,'CHAR_最大血'));s(pet,'CHAR_魔',g(pet,'CHAR_最大魔'));s(pet,'CHAR_攻击力',1)
   for i=9,0,-1 do if Pet.GetSkill(pet,i)>=0 then Pet.DelSkill(pet,i) end end
   check(Pet.AddSkill(pet,1930)==1,'bank original learns spell '..slot)
  end
  check(Char.SetPetDepartureState(p,0,2)==1,'main pet selected')
  local yes,msg=M:enable(p);check(yes,'production nine-pet module starts: '..tostring(msg));local session=M.active[p]
  check(#session.rows==4 and #session.companions==4 and #M:actors(session)==8,'four proxies each carry a bank battle pet')
  check(M:enabled(p),'new squad defaults to enabled')
  for _,row in ipairs(M:actors(session)) do check(M:ai(p,row.pet).mode=='attack','carried/bank automatic pet defaults to intelligent combat '..row.proxy) end
  all[p]=true;all[session.normal]=true;for _,row in ipairs(M:actors(session)) do all[row.proxy]=true end
  for _,row in ipairs(session.companions) do
   check(g(row.proxy,'CHAR_等级')==g(row.pet,'CHAR_等级') and g(row.proxy,'CHAR_魔攻')==g(row.pet,'CHAR_魔攻'),'bank level and effective equipment stats copied '..row.bankSlot)
   check(g(row.proxy,'CHAR_名字')==g(row.pet,'CHAR_名字') and Pet.GetSkill(row.proxy,0)==1930,'bank name and learned skill copied '..row.bankSlot)
  end
  local ix=Data.EnemyGetDataIndex(1);Data.EnemySetData(ix,CONST.DATA_ENEMY_TACTICSOPTION,'gu:1');Data.EnemySetData(ix,CONST.DATA_ENEMY_BOSS_FLG,1)
  b=Battle.PVE(p,p,nil,{1},{100},{0});check(b>=0,'native nine-pet battle starts')
  R.roster={};local seen={}
  for pos=0,9 do local q=Battle.GetPlayer(b,pos)
   check(q>=0 and all[q] and not seen[q],'distinct ally fills position '..pos);seen[q]=true
   R.roster[#R.roster+1]={index=q,pos=pos,bid=Battle.GetPos(b,q),isPet=Char.IsPet(q),isDummy=Char.IsDummy(q)}
  end
  check(#R.roster==10,'one player and nine pet combatants')
  T:AddInterval(100,function()
   if finished then return end
   local yes,error=xpcall(function()
    if os.time()-started>40 then error('nine-pet native combat timed out') end
    if R.phase=='victory' and Char.GetBattleIndex(p)~=b then
     M:tick();R.victory_xp={}
     for pet,xp in pairs(victoryXP) do
      R.victory_xp[tostring(pet)]={before=xp,after=g(pet,'CHAR_经验')}
      check(g(pet,'CHAR_经验')>xp,'native victory awards experience to original '..pet)
     end
     check(M.active[p] and not M.active[p].battle,'native victory keeps squad and finalizes companions');finish();return
    end
    session=M.active[p] or session
    if Battle.IsWaitingCommand(p)==1 then
     s(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);s(p,'CHAR_BattleCom2',0);s(p,'CHAR_BattleCom3',7400)
     s(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);s(p,'CHAR_BattleMode',3)
    end
    if Battle.IsWaitingCommand(session.normal)==1 then Battle.ActionSelect(session.normal,CONST.BATTLE_COM.BATTLE_COM_GUARD,5,7400) end
    M:tick()
   end,debug.traceback)
   if not yes then finish(error) end
  end,1)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
