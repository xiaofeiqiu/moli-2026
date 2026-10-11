-- All 40 tutor lessons and actual native casts at every rank, manual and AI.
local R={status='RUNNING',checks={},npcs={},cases={},production_accounts_used=false,client_verified=false}
local T=ModuleBase:createModule('petElementalProbe'):new();T:load()
local M=assert(getModule('fivePet'));local tutor=assert(getModule('petSkillTutor'))
local bases={2700,2800,2900,3000};local cases={};local completed=0;local finished=false;local started=os.time()
local lessonOwner=-1;local originalPool=Char.GetPoolPet
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function set(q,k,v) return Char.SetData(q,assert(CONST[k],k),v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function write()
 local report={status=R.status,error=R.error,checks=R.checks,npcs=R.npcs,cases={},
  production_accounts_used=false,client_verified=false,bank_inventory_fixture=R.bank_inventory_fixture}
 for _,c in ipairs(R.cases) do report.cases[#report.cases+1]={kind=c.kind,base=c.base,label=c.label,casts=c.casts,lastRound=c.lastRound} end
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(report));f:close()
end
local function finish(err)
 if finished then return end;finished=true;Char.GetPoolPet=originalPool
 if lessonOwner>=0 then pcall(Char.DelDummy,lessonOwner) end
 for _,c in ipairs(R.cases) do if c.owner then
  c.done=true
  pcall(M.disable,M,c.owner);pcall(Battle.ExitBattle,c.owner)
  for slot=0,4 do if Char.GetPet(c.owner,slot)>=0 then pcall(Char.DelSlotPet,c.owner,slot) end end
  pcall(Char.DelDummy,c.owner)
 end end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil;write()
end
local function clear(pet)
 for i=9,0,-1 do if Pet.GetSkill(pet,i)>=0 then Pet.DelSkill(pet,i) end end
end
local function setup(c)
 c.tech=c.base+c.level-1;c.hits={};c.beforeHP={}
 clear(c.learnedPet);check(Pet.AddSkill(c.learnedPet,c.tech)==1,'learn cast '..c.label..' LV'..c.level)
 set(c.learnedPet,'CHAR_魔',5000)
 if c.row then M:attributes(c.row) end
 set(c.actor,'CHAR_魔',5000)
 for pos=10,19 do local q=Battle.GetPlayer(c.battle,pos);if q>=0 then
  set(q,'CHAR_血',1000000);c.beforeHP[pos]=1000000
 end end
 local t=M:tech(c.tech)
 check(t.command==CONST.BATTLE_COM.BATTLE_COM_P_MAGIC and t.scope=='all' and t.element==c.base/100-26,
  'native all-enemy element decoded '..c.label..' LV'..c.level)
 check(t.cost==40*c.level,'native MP progression '..c.label..' LV'..c.level)
 if c.row then
  local cmd=M:choose(c.battle,c.row)
  check(cmd[1]==t.command and cmd[2]==41 and cmd[3]==c.tech,'AI chooses learned all-enemy rank '..c.label..' LV'..c.level)
  set(c.actor,'CHAR_魔',t.cost-1)
  local fallback=M:choose(c.battle,c.row)
  check(fallback[3]~=c.tech,'unaffordable rank skipped '..c.label..' LV'..c.level)
  set(c.actor,'CHAR_魔',5000)
 end
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(b,q,r) if cases[b] then return 0 end;return r end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,b,c1,c2,c3)
 local c=cases[b];if not c then return damage end
 if a==c.actor and c3==c.tech then
  c.hits[#c.hits+1]={pos=Battle.GetPos(b,d),damage=damage,tech=c3};return damage
 end
 return 0
end)
T:regCallback('BeforeBattleTurnStartEvent',function(b)
 local c=cases[b];if not c or c.done or finished then return end
 c.beforeMP=get(c.actor,'CHAR_魔')
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then
  set(q,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(q,'CHAR_BattleCom2',pos);set(q,'CHAR_BattleCom3',7400)
 end end
end)
T:regCallback('AfterBattleTurnEvent',function(b)
 local c=cases[b];if not c or c.done or finished then return end
 local ok,err=xpcall(function()
  local used=c.beforeMP-get(c.actor,'CHAR_魔')
  c.lastRound={level=c.level,beforeMP=c.beforeMP,afterMP=get(c.actor,'CHAR_魔'),mp_used=used,hits=c.hits,
   command=get(c.actor,'CHAR_BattleCom1'),tech=get(c.actor,'CHAR_BattleCom3'),maxMP=get(c.actor,'CHAR_最大魔')}
  if used==0 and #c.hits==0 then return end -- Dummy battles can start with a guard turn.
  check(used==40*c.level,'native MP charged once '..c.label..' LV'..c.level)
  local damaged=0
  for pos,hp in pairs(c.beforeHP) do if get(Battle.GetPlayer(b,pos),'CHAR_血')<hp then damaged=damaged+1 end end
  check(damaged==3 and #c.hits==3,'all three native enemies damaged '..c.label..' LV'..c.level)
  check(Pet.GetSkill(c.learnedPet,0)==c.tech,'learned ID retained '..c.label..' LV'..c.level)
  c.casts[#c.casts+1]={level=c.level,tech=c.tech,mp_used=used,targets=c.hits}
  if c.level==10 then
   if c.row then
    check(Pet.AddSkill(c.learnedPet,c.base)==1,'learn lower rank for MP fallback '..c.label)
    set(c.actor,'CHAR_魔',40)
    check(M:choose(b,c.row)[3]==c.base,'AI falls back to affordable learned LV1 '..c.label)
    clear(c.learnedPet)
    check(M:choose(b,c.row)[3]~=c.base,'AI stops using forgotten rank '..c.label)
   end
   c.done=true;completed=completed+1
   if completed==#R.cases then finish() else write() end
  else c.level=c.level+1;setup(c) end
 end,debug.traceback)
 if not ok then finish(err) end
end)
local function add(kind,base)
 local c={kind=kind,base=base,level=1,label=kind..'_'..base,casts={}};R.cases[#R.cases+1]=c
 c.owner=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='PET_ELEMENTAL_CAST'})
 check(c.owner>=0,'isolated battle owner '..c.label)
 set(c.owner,'CHAR_等级',50);set(c.owner,'CHAR_体力',50000);NLG.UpChar(c.owner)
 c.pet=Char.GivePet(c.owner,3004,1);check(c.pet>=0,'native main pet '..c.label)
 c.learnedPet=kind=='proxy' and Char.GivePet(c.owner,3004,1) or c.pet
 for _,q in ipairs({c.pet,c.learnedPet}) do
  clear(q);set(q,'CHAR_等级',50);set(q,'CHAR_体力',50000);set(q,'CHAR_魔法',50000);Pet.UpPet(c.owner,q)
  set(q,'CHAR_最大血',10000);set(q,'CHAR_血',10000)
  set(q,'CHAR_最大魔',5000);set(q,'CHAR_魔',5000);set(q,'CHAR_攻击力',1)
  set(q,'CHAR_精神',300);set(q,'CHAR_魔攻',200);set(q,'CHAR_敏捷',1000)
 end
 check(Char.SetPetDepartureState(c.owner,0,2)==1,'primary pet selected '..c.label)
 if kind=='proxy' then
  check(M:enable(c.owner),'automatic squad enabled '..c.label)
  c.row=M.active[c.owner].rows[1];c.actor=c.row.proxy
 else c.actor=c.pet end
 c.battle=Battle.PVE(c.owner,c.owner,nil,{1,1,1},{100,100,100},{0,1,2})
 check(c.battle>=0,'native elemental battle '..c.label);cases[c.battle]=c
 for pos=10,19 do local q=Battle.GetPlayer(c.battle,pos);if q>=0 then
  set(q,'CHAR_最大血',1000000);set(q,'CHAR_血',1000000);set(q,'CHAR_精神',100)
  set(q,'CHAR_魔抗',0);set(q,'CHAR_攻击力',1);set(q,'CHAR_敏捷',1);set(q,'对象_ENEMY_BossFlg',0)
 end end
 setup(c)
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  reloadModule('petSkillTutor');tutor=assert(getModule('petSkillTutor'))
  lessonOwner=Char.CreateDummy({mapType=0,floor=60003,x=36,y=19,image=100002,name='PET_ELEMENTAL_LESSONS'})
  check(lessonOwner>=0,'isolated tutor owner');Char.AddGold(lessonOwner,100000)
  local pet=Char.GivePet(lessonOwner,3004,1);check(pet>=0,'native lesson pet');clear(pet)
  local lessons=tutor:lessons('magic');local indexes={}
  for i,s in ipairs(lessons) do check(not indexes[s.id],'no duplicate magic lesson '..s.id);indexes[s.id]=i end
  for _,base in ipairs(bases) do for level=1,10 do
   local id=base+level-1;local index=assert(indexes[id]);local lesson=lessons[index]
   check(lesson.name:find('LV'..level,1,true) and lesson.cost==1000,'explicit tutor rank and fee '..id)
   local page=math.ceil(index/5);local uuid=Pet.GetUUID(pet);local gold=Char.GetGold(lessonOwner)
   tutor:show(tutor.npc,lessonOwner,'learning',page,0,uuid,nil,'magic')
   tutor:answer(tutor.npc,lessonOwner,7320,0,tostring((index-1)%5+1))
   check(tutor.sessions[lessonOwner].id==id,'paginated selection resolves exact rank '..id)
   tutor:answer(tutor.npc,lessonOwner,7322,8,'')
   check(Pet.GetSkill(pet,0)<0 and Char.GetGold(lessonOwner)==gold,'cancel learning preserves gold and skill '..id)
   tutor:answer(tutor.npc,lessonOwner,7320,0,tostring((index-1)%5+1))
   tutor:answer(tutor.npc,lessonOwner,7322,4,'')
   check(Pet.GetSkill(pet,0)==id and Char.GetGold(lessonOwner)==gold-1000,'confirm teaches native ID and charges once '..id)
   check(not tutor:learnPet(tutor.npc,lessonOwner,0,uuid,id) and Char.GetGold(lessonOwner)==gold-1000,'duplicate not charged '..id)
   check(tutor:forget(tutor.npc,lessonOwner,0,uuid,0,id),'native rank can be forgotten '..id)
  end end
  -- Bank inventory lookup is a fixture; teaching still uses the real native pet API.
  R.bank_inventory_fixture=true
  Char.GetPoolPet=function(p,slot) if p==lessonOwner and slot==0 then return pet end;return originalPool(p,slot) end
  for _,base in ipairs(bases) do
   local id=base+9;local gold=Char.GetGold(lessonOwner);local uuid=Pet.GetUUID(pet)
   check(tutor:learnPet(tutor.npc,lessonOwner,5,uuid,id),'bank original learns LV10 '..id)
   check(Pet.GetSkill(pet,0)==id and Char.GetGold(lessonOwner)==gold-1000,'bank original ID and fee '..id)
   check(tutor:forget(tutor.npc,lessonOwner,5,uuid,0,id),'bank original forgets LV10 '..id)
  end
  Char.GetPoolPet=originalPool;Char.DelDummy(lessonOwner);lessonOwner=-1
  for _,kind in ipairs({'main','proxy'}) do for _,base in ipairs(bases) do add(kind,base) end end
  T:AddInterval(100,function()
   if finished then return end
   local good,e=xpcall(function()
    if os.time()-started>48 then error('pet elemental probe timeout') end
    for _,c in ipairs(R.cases) do
     if Battle.IsWaitingCommand(c.owner)==1 then
      set(c.owner,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(c.owner,'CHAR_BattleCom2',-1)
      set(c.owner,'CHAR_BattleCom3',7400);set(c.owner,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE)
      set(c.owner,'CHAR_BattleMode',3)
     end
     if Battle.IsWaitingCommand(c.pet)==1 then
      local manual=c.kind=='main' and not c.done
      Battle.ActionSelect(c.pet,manual and CONST.BATTLE_COM.BATTLE_COM_P_MAGIC or CONST.BATTLE_COM.BATTLE_COM_GUARD,
       manual and 41 or Battle.GetPos(c.battle,c.pet),manual and c.tech or 7400)
     end
    end
    M:tick()
   end,debug.traceback);if not good then finish(e) end
  end,1)
  write()
 end,debug.traceback);if not ok then finish(err) end
end,0)
