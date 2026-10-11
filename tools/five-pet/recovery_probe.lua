-- Native NPC/configuration and battle checks with disposable characters only.
local R={status='RUNNING',checks={},npcs={},production_accounts_used=false}
local M=assert(getModule('fivePet'))
local T=ModuleBase:createModule('fivepetRecoveryProbe'):new();T:load()
local p,b=-1,-1;local pets={};local row;local finished=false;local started=os.time()
local rounds=0
local originalWindow=NLG.ShowWindowTalked;local window
NLG.ShowWindowTalked=function(q,n,kind,buttons,seq,data,...)
 if q==p then window={seq=seq,data=data} end
 return originalWindow(q,n,kind,buttons,seq,data,...)
end
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function set(q,k,v) local field=assert(CONST[k],k);return Char.SetData(q,field,v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function write() local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close() end
local function finish(err)
 if finished then return end;finished=true
 if p>=0 then pcall(M.disable,M,p);pcall(Battle.ExitBattle,p)
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end
  pcall(Char.DelDummy,p)
 end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil;write()
 NLG.ShowWindowTalked=originalWindow
end
local function click(action,value)
 local menu=assert(M.menus[p]);local choice
 for i,o in ipairs(menu.options) do if o[action]==value then choice=i;break end end
 check(choice~=nil,'menu offers '..action..' '..tostring(value))
 local lines={};local text=window.data:gsub('\\n','\n')
 for line in (text..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
 local headers=assert(tonumber(lines[1]));local visible={}
 for i=headers+2,#lines do visible[#visible+1]=lines[i] end
 if visible[#visible]=='' then table.remove(visible) end
 check(window.seq==menu.seq and #visible==#menu.options and #visible<=8,'displayed menu has all configured rows '..menu.kind)
 for i,o in ipairs(menu.options) do check(visible[i]==o.label,'visible click index '..menu.kind..' '..i) end
 M:answer(M.npc,p,menu.seq,0,tostring(choice))
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi) if bi==b then return 0 end;return damage end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b then return 0 end;return rate end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi==b then R.beforeMP=get(row.proxy,'CHAR_魔');R.beforeHP=get(p,'CHAR_血') end
end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished then return end
 local ok,err=xpcall(function()
  rounds=rounds+1
  local id=rounds==1 and 6400 or 6100
  R.nativeCommand={command=row.command,hp=get(p,'CHAR_血'),maxhp=get(p,'CHAR_最大血'),regen=Battle.GetBattleCharacterStatus(p,CONST['战属_恢复回合']),ai=M:ai(p,row.pet)}
  check(row.command and row.command[3]==id,'native execution selects '..id..' in round '..rounds)
  R.execution=R.execution or {};R.execution[#R.execution+1]={tech=id,beforeMP=R.beforeMP,afterMP=get(row.proxy,'CHAR_魔'),beforeHP=R.beforeHP,afterHP=get(p,'CHAR_血')}
  check(get(row.proxy,'CHAR_魔')==R.beforeMP-M:tech(id).cost,'native recovery consumes MP exactly once in round '..rounds)
  if rounds==1 then
   check(Battle.GetBattleCharacterStatus(p,CONST['战属_恢复回合'])>0,'first round applies native continuous recovery on full-HP owner')
   set(p,'CHAR_血',400)
  else check(get(p,'CHAR_血')>R.beforeHP,'second round heals low-HP owner while regeneration remains active') end
  M:sync(p,row,true)
  check(get(row.pet,'CHAR_魔')==get(row.proxy,'CHAR_魔'),'native MP syncs to real pet in round '..rounds)
 end,debug.traceback)
 if not ok or rounds>=2 then finish(not ok and err or nil) end
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=60003,x=16,y=35,image=100002,name='RECOVERY_AI_TEST'})
  check(p>=0,'isolated owner');set(p,'CHAR_等级',50);set(p,'CHAR_体力',50000);NLG.UpChar(p)
  for slot=0,2 do
   local pet=Char.GivePet(p,3004,1);assert(pet>=0);pets[slot+1]=pet
   for n=9,0,-1 do if Pet.GetSkill(pet,n)>=0 then Pet.DelSkill(pet,n) end end
   set(pet,'CHAR_血',get(pet,'CHAR_最大血'));set(pet,'CHAR_最大魔',2000);set(pet,'CHAR_魔',2000)
  end
  check(Char.SetPetDepartureState(p,0,2)==1,'manual main pet selected')
  local pet=pets[2]
  for _,id in ipairs({1930,6100,6400,6700,6800,6300,6500}) do check(Pet.AddSkill(pet,id)==1,'learned native tech '..id) end
  M:saveAI(p,pet,{mode='skill',tech=6100})
  local migrated=M:ai(p,pet)
  check(migrated.tech==0 and migrated.mode=='attack' and migrated.recoveryRules.heal.tech==6100 and migrated.recoveryRules.heal.enabled,'legacy healing primary migrates to healing rule')
  M:saveAI(p,pet,{mode='skill',tech=1930,recoveryTech=6400,recoveryEnabled=true,recoveryThreshold=70})
  migrated=M:ai(p,pet)
  check(migrated.recoveryRules.regen.tech==6400 and migrated.recoveryRules.regen.enabled and migrated.recoveryRules.regen.when=='start','legacy regeneration migrates to independent opening rule')
  M:saveAI(p,pet,{mode='skill',tech=1930,bossCombo=true})
  local defaults=M:ai(p,pet)
  check(not defaults.recoveryRules.heal.enabled and defaults.recoveryRules.heal.threshold==60 and defaults.recoveryRules.regen.when=='start','new defaults are heal below 60 and opening regeneration')
  M:skillMenu(p,pet,1)
  for _,o in ipairs(M.menus[p].options) do check(not o.tech or o.tech==1930,'primary picker excludes all recovery skills') end
  M:petMenu(p,pet);click('action','menuPage');click('action','fallbackSkills')
  for _,o in ipairs(M.menus[p].options) do check(not o.fallbackTech or o.fallbackTech==0 or o.fallbackTech==1930,'fallback excludes recovery skills') end
  M:petMenu(p,pet);click('action','recovery');click('ruleKind','heal');click('action','recoveryToggle')
  check(M.menus[p].kind=='recoverySkills','empty heal toggle opens healing picker')
  for _,o in ipairs(M.menus[p].options) do check(not o.recoveryTech or o.recoveryTech==0 or o.recoveryTech==6100 or o.recoveryTech==6300,'heal picker excludes regeneration, cleanse and revive') end
  click('recoveryTech',6100);click('action','recoveryScopes');click('recoveryScope','owner')
  click('action','recoveryThresholds');click('action','menuPage');click('recoveryThreshold',100)
  check(M:ai(p,pet).recoveryRules.heal.threshold==100,'high threshold remains visible and selectable')
  click('action','recoveryThresholds');click('recoveryThreshold',60)
  click('action','back');click('ruleKind','regen');click('action','recoverySkills')
  for _,o in ipairs(M.menus[p].options) do check(not o.recoveryTech or o.recoveryTech==0 or o.recoveryTech==6400 or o.recoveryTech==6500,'regen picker only lists regeneration') end
  click('recoveryTech',6400);click('action','recoveryScopes');click('recoveryScope','owner')
  click('action','recoveryThresholds');click('recoveryThreshold',30)
  click('action','recoveryWhen');click('recoveryWhen','low')
  M.configs[p]=nil;local a=M:ai(p,pet)
  check(a.recoveryRules.heal.tech==6100 and a.recoveryRules.heal.threshold==60 and a.recoveryRules.regen.tech==6400 and a.recoveryRules.regen.threshold==30 and a.recoveryRules.regen.when=='low','two skills and their independent conditions persist')
  click('action','recoveryToggle');check(not M:ai(p,pet).recoveryRules.regen.enabled and M:ai(p,pet).recoveryRules.heal.enabled,'turning off regeneration preserves healing')
  click('action','recoveryToggle');click('action','recoverySkills');click('recoveryTech',0)
  check(M:ai(p,pet).recoveryRules.regen.tech==0 and M:ai(p,pet).recoveryRules.heal.tech==6100,'clearing regeneration preserves healing')
  click('action','recoverySkills');click('recoveryTech',6400)
  click('action','recoveryWhen');click('recoveryWhen','start')
  M.configs[p]=nil;a=M:ai(p,pet)
  check(a.recoveryRules.heal.enabled and a.recoveryRules.regen.enabled and a.recoveryRules.regen.when=='start' and a.tech==1930,'both recovery rules coexist with original attack skill')
  local messages={};local send=NLG.SystemMessage
  NLG.SystemMessage=function(q,text) if q==p then messages[#messages+1]=text else return send(q,text) end end
  local help=assert(loadfile('lua/Modules/commandHelp.lua'))();help:show(p,'fivepet');NLG.SystemMessage=send
  check(table.concat(messages):find('回复技能与触发条件',1,true)~=nil,'native GBK help describes recovery configuration')
  for _,text in ipairs(messages) do check(#text<=120,'help chunks remain within client limit') end
  check(M:enable(p),'companions enabled');row=M.active[p].rows[1]
  M:saveAI(p,pets[3],{mode='guard'})
  b=Battle.PVE(p,p,nil,{1},{100},{0});check(b>=0,'isolated native battle');M:formation(b,M.active[p])
  local ownerMaxHP=get(p,'CHAR_最大血')
  local allies={p,pets[1],row.proxy,M.active[p].rows[2].proxy}
  for _,q in ipairs(allies) do set(q,'CHAR_最大血',1000);set(q,'CHAR_血',1000) end
  set(row.proxy,'CHAR_最大魔',2000);set(row.proxy,'CHAR_魔',2000)
  local function save() M:saveAI(p,pet,a) end
  local function chosen(id,label) check(M:choose(b,row)[3]==id,label) end
  local function healthy() for _,q in ipairs(allies) do set(q,'CHAR_血',1000) end end
  local heal=a.recoveryRules.heal;local regen=a.recoveryRules.regen
  a.bossCombo=false;regen.enabled=false;save();chosen(1930,'healthy team does not instant heal')
  set(p,'CHAR_血',601);chosen(1930,'above 60 percent does not heal')
  set(p,'CHAR_血',600);chosen(1930,'exactly 60 percent does not heal')
  set(p,'CHAR_血',599);chosen(6100,'strictly below 60 percent heals')
  heal.threshold=50;save();set(p,'CHAR_血',500);chosen(1930,'exact custom threshold does not heal')
  set(p,'CHAR_血',499);chosen(6100,'custom healing threshold is independent')
  heal.threshold=60;regen.enabled=true;save();healthy();chosen(6400,'opening regeneration triggers even at full HP')
  Battle.SetBattleCharacterStatus(p,CONST['战属_恢复回合'],3);chosen(1930,'ongoing regeneration is not overwritten')
  set(p,'CHAR_血',599);chosen(6100,'healing still triggers with regeneration active')
  Battle.SetBattleCharacterStatus(p,CONST['战属_恢复回合'],0);chosen(6100,'urgent healing precedes missing regeneration')
  a.bossCombo=true;save();chosen(6100,'urgent healing precedes BOSS combo')
  a.mode='guard';save();chosen(7400,'full defense precedes both rules')
  a.mode='skill';a.lowHpGuard=true;save();set(row.proxy,'CHAR_血',300);chosen(7400,'low self HP guard precedes both rules')
  a.lowHpGuard=false;a.bossCombo=false;save();set(row.proxy,'CHAR_血',1000)
  set(row.proxy,'CHAR_魔',0);chosen(7300,'no MP safely falls back');set(row.proxy,'CHAR_魔',2000)
  heal.enabled=false;regen.when='low';regen.threshold=30;save();set(p,'CHAR_血',300);chosen(1930,'regen exact threshold does not trigger')
  set(p,'CHAR_血',299);chosen(6400,'regen uses its own low-HP threshold')
  set(p,'CHAR_血',400);heal.enabled=true;save();chosen(6100,'heal below 60 works while regen below 30 is not eligible')
  heal.scope='self';regen.enabled=false;save();chosen(1930,'self healing excludes injured owner')
  set(row.proxy,'CHAR_血',500);check(M:choose(b,row)[2]==Battle.GetPos(b,row.proxy),'self healing targets own proxy')
  healthy();heal.scope='pets';save();set(p,'CHAR_血',1);chosen(1930,'pet scope excludes owner')
  set(pets[1],'CHAR_血',500);check(M:choose(b,row)[2]==Battle.GetPos(b,pets[1]),'pet scope includes main pet')
  heal.scope='team';save();check(M:choose(b,row)[2]==Battle.GetPos(b,p),'team scope selects lowest HP ratio')
  healthy();heal.enabled=false;local cleanse=a.recoveryRules.cleanse
  cleanse.tech=6700;cleanse.enabled=true;cleanse.status='poison';save();chosen(1930,'cleanse ignores healthy team')
  Battle.SetBattleCharacterStatus(p,CONST['战属_睡'],3);chosen(1930,'specific cleanse ignores different status')
  Battle.SetBattleCharacterStatus(p,CONST['战属_毒'],3);chosen(6700,'cleanse selected poison condition')
  Battle.SetBattleCharacterStatus(p,CONST['战属_毒'],0);cleanse.status='any';save();chosen(6700,'any cleanse condition includes sleep')
  Battle.SetBattleCharacterStatus(p,CONST['战属_睡'],0);cleanse.enabled=false
  local revive=a.recoveryRules.revive;revive.tech=6800;revive.enabled=true;save();chosen(1930,'revive ignores living team')
  set(pets[1],'CHAR_血',0);chosen(6800,'revive selects fallen main pet');healthy();revive.enabled=false
  heal.enabled=true;heal.tech=6300;save();set(p,'CHAR_血',500);check(M:choose(b,row)[2]==40,'all heal uses native side target')
  heal.enabled=false;regen.enabled=true;regen.tech=6500;regen.when='start';save();check(M:choose(b,row)[2]==Battle.GetPos(b,pets[1])+20,'area regeneration centers native cross on four allies')
  regen.enabled=false;heal.enabled=true;heal.tech=6400;save();chosen(1930,'wrong-category saved heal tech is rejected')
  heal.tech=6100;save();check(Pet.DelSkill(pet,1)==1,'forget heal');chosen(1930,'forgotten heal safely falls back')
  check(Pet.AddSkill(pet,6100)==1,'relearn heal')
  heal.scope='owner';regen.enabled=true;regen.tech=6400;regen.scope='owner';regen.when='start';save()
  healthy();set(row.proxy,'CHAR_敏捷',10000)
  set(p,'CHAR_最大血',ownerMaxHP);set(p,'CHAR_血',ownerMaxHP)
  R.beforeHP=get(p,'CHAR_血');R.beforeMP=get(row.proxy,'CHAR_魔')
  T:AddInterval(100,function()
   if finished then return end
   local success,e=xpcall(function()
    if os.time()-started>35 then error('native recovery execution timeout') end
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
