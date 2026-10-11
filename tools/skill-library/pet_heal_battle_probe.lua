-- Actual primary-pet/manual and five-pet/AI E1 casts, with native wire capture.
local R={status='RUNNING',checks={},npcs={},cases={},production_accounts_used=false,client_verified=false}
local T=ModuleBase:createModule('petHealBattleProbe'):new();T:load()
local M=assert(getModule('fivePet'));local tutor=assert(getModule('petSkillTutor'))
local cases={};local finished=false;local completed=0;local started=os.time()
local function get(q,k) return Char.GetData(q,CONST[k]) end
local function set(q,k,v) return Char.SetData(q,CONST[k],v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function write() local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close() end
local function finish(err)
 if finished then return end;finished=true
 for _,c in ipairs(R.cases) do if c.owner then
  pcall(M.disable,M,c.owner);pcall(Battle.ExitBattle,c.owner)
  for slot=0,4 do if Char.GetPet(c.owner,slot)>=0 then pcall(Char.DelSlotPet,c.owner,slot) end end
  pcall(Char.DelDummy,c.owner)
 end end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil;write()
end
local function capture(c)
 R.capture_requested=c.label;write();local stop=os.clock()+3
 repeat
  local f=io.open(('__REPORT__'):gsub('pet_heal_battle_native_result.json','pet_heal_capture_ack.json'),'rb')
  if f then
   local raw=f:read('*a');f:close();local ok,v=pcall(JSON.decode,raw)
   if ok and v.capture==c.label then
    c.packet=v.buffers.main..v.buffers.extra
    c.wire_techs={};for id in c.packet:gmatch('SKL|s([0-9A-F]+)|') do c.wire_techs[#c.wire_techs+1]=tonumber(id,16) end
    check(c.packet:find('SKL|s'..string.format('%X',6350)..'|',1,true)~=nil,'original heal animation emitted '..c.label)
    check(c.packet:find('SKL|s'..string.format('%X',700826)..'|',1,true)==nil,'copied animation absent '..c.label)
    return
   end
  end
 until os.clock()>stop
 error('capture timeout '..c.label)
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('DamageCalculateEvent',function(a,d,o,damage,b) if cases[b] then return 0 end;return damage end)
T:regCallback('BattleEscapeEvent',function(b,q,r) if cases[b] then return 0 end;return r end)
T:regCallback('BattleHealCalculateEvent',function(a,d,ori,heal,b,com1,com2,com3)
 local c=cases[b]
 if c and a==c.actor and heal>0 then
  c.targets[#c.targets+1]={pos=Battle.GetPos(b,d),heal=heal,tech=com3}
  if #c.targets==1 then local ok,err=xpcall(function() capture(c) end,debug.traceback);if not ok then finish(err) end end
 end
 return heal
end)
T:regCallback('BeforeBattleTurnStartEvent',function(b)
 local c=cases[b];if not c then return end
 c.beforeMP=get(c.actor,'CHAR_魔');c.beforeHP=get(c.owner,'CHAR_血')
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then
  set(q,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(q,'CHAR_BattleCom2',pos);set(q,'CHAR_BattleCom3',7400)
 end end
end)
T:regCallback('AfterBattleTurnEvent',function(b)
 local c=cases[b];if not c or c.done or finished or #c.targets==0 then return end
 local ok,err=xpcall(function()
  c.mp_used=c.beforeMP-get(c.actor,'CHAR_魔');c.afterHP=get(c.owner,'CHAR_血')
  check(c.mp_used==48,'original E1 MP cost retained '..c.label)
  check(c.afterHP>c.beforeHP,'real native owner HP recovered '..c.label)
  check(#c.targets>=2,'group healing retains allied targets '..c.label)
  check(Pet.GetSkill(c.learnedPet,0)==c.tech,'learned pet ID retained '..c.label)
  if c.kind=='proxy' then check(M:ai(c.owner,c.learnedPet).recoveryRules.heal.tech==c.tech,'saved recovery configuration retained '..c.label) end
  for _,t in ipairs(c.targets) do check(t.tech==6350,'native E1 handler used '..c.label) end
  c.done=true;completed=completed+1
  if completed==#R.cases then finish() else write() end
 end,debug.traceback)
 if not ok then finish(err) end
end)
local function add(kind,tech)
 local c={kind=kind,tech=tech,label=kind..'_'..tech,targets={}}
 R.cases[#R.cases+1]=c
 c.owner=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='HEAL_E1_CAST_TEST'})
 check(c.owner>=0,'isolated owner '..c.label)
 local p=c.owner;set(p,'CHAR_等级',50);set(p,'CHAR_体力',50000);NLG.UpChar(p)
 c.pet=Char.GivePet(p,3004,1);check(c.pet>=0,'owned primary pet '..c.label)
 c.learnedPet=kind=='proxy' and Char.GivePet(p,3004,1) or c.pet
 for i=9,0,-1 do if Pet.GetSkill(c.learnedPet,i)>=0 then Pet.DelSkill(c.learnedPet,i) end end
 check(Pet.AddSkill(c.learnedPet,tech)==1,'learned heal '..c.label)
 if tech==700826 then
  local n=tutor.npc;Char.Warp(p,0,60003,get(n,'CHAR_X'),get(n,'CHAR_Y')+1)
  local gold=Char.GetGold(p);local slot=kind=='proxy' and 1 or 0
  local learned=tutor:learnPet(n,p,slot,Pet.GetUUID(c.learnedPet),6350)
  check(not learned and Char.GetGold(p)==gold and Pet.GetSkill(c.learnedPet,0)==700826,'existing copy prevents duplicate native learning/fee '..c.label)
  Char.Warp(p,0,1000,225,75)
 end

 check(Char.SetPetDepartureState(p,0,2)==1,'primary pet selected '..c.label)
 if kind=='proxy' then
  M:saveAI(p,c.learnedPet,{mode='attack',recoveryRules={heal={tech=tech,enabled=true,target='owner',threshold=60}}})
  check(M:enable(p),'five-pet recovery enabled '..c.label);c.actor=M.active[p].rows[1].proxy
 else c.actor=c.pet end
 c.battle=Battle.PVE(p,p,nil,{1},{20},{0});check(c.battle>=0,'native battle '..c.label);cases[c.battle]=c
 set(p,'CHAR_最大血',10000);set(p,'CHAR_血',1000)
 set(c.learnedPet,'CHAR_最大魔',2000);set(c.learnedPet,'CHAR_魔',2000)
 set(c.actor,'CHAR_最大魔',2000);set(c.actor,'CHAR_魔',2000)
 set(c.actor,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_P_HEAL);set(c.actor,'CHAR_BattleCom3',tech)
 set(c.actor,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_P_HEAL);set(c.actor,'CHAR_Battle2Com3',tech)
 set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_P_HEAL);set(p,'CHAR_BattleCom3',tech)
 tutor:normalizeBattleTechs(c.battle)
 check(get(c.actor,'CHAR_BattleCom3')==6350 and get(c.actor,'CHAR_Battle2Com3')==6350,'both pet command slots compatible '..c.label)
 check(get(p,'CHAR_BattleCom3')==tech,'human command is unchanged '..c.label)
 set(c.actor,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(c.actor,'CHAR_BattleCom3',tech)
 tutor:normalizeBattleTechs(c.battle);check(get(c.actor,'CHAR_BattleCom3')==tech,'unrelated command unchanged '..c.label)
 set(c.actor,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(c.actor,'CHAR_BattleCom3',7400)
 set(c.actor,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE)
 set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom3',7400)
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  reloadModule('petSkillTutor');tutor=assert(getModule('petSkillTutor'))
  local handlers=0
  for _,callback in pairs(tutor.callbacks) do if callback.key=='BeforeBattleTurnStartEvent' then handlers=handlers+1 end end
  check(handlers==1,'reload retains one compatibility callback')
  local catalog=dofile('lua/Modules/skillTrainingData.lua');local count=0
  for _,lesson in ipairs(catalog.pets) do
   check(lesson.id~=700826,'catalog does not teach unsafe E1 copy '..lesson.id)
   if lesson.id==6350 then count=count+1 end
  end
  check(count==1,'catalog teaches native E1 once')

  for _,kind in ipairs({'main','proxy'}) do for _,tech in ipairs({6350,700826}) do add(kind,tech) end end
  T:AddInterval(100,function()
   if finished then return end
   local ok,e=xpcall(function()
    if os.time()-started>45 then error('native heal cast timeout') end
    for _,c in ipairs(R.cases) do if not c.done then
     local p=c.owner
     if Battle.IsWaitingCommand(p)==1 then
      set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',-1);set(p,'CHAR_BattleCom3',7400)
      set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3)
     end
     if Battle.IsWaitingCommand(c.pet)==1 then
      Battle.ActionSelect(c.pet,c.kind=='main' and CONST.BATTLE_COM.BATTLE_COM_P_HEAL or CONST.BATTLE_COM.BATTLE_COM_GUARD,40,c.kind=='main' and c.tech or 7400)
     end
    end end
    M:tick()
   end,debug.traceback)
   if not ok then finish(e) end
  end,1);write()
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
