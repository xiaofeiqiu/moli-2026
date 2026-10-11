-- Tutor, existing native/copy upgrades, and manual/automatic native V-X casts.
local R={status='RUNNING',checks={},npcs={},cases={},production_accounts_used=false,client_verified=false}
local T=ModuleBase:createModule('petPhysicalProbe'):new();T:load()
local M=assert(getModule('fivePet'));local tutor=assert(getModule('petSkillTutor'))
local upgrade=assert(getModule('petSkillUpgrade'));local battles={};local completed=0;local finished=false
local started=os.time();local lessonOwner=-1;local originalHitChance=M.hitChance;local originalChoose=M.choose
-- Preserve production AI policy. Automatic cast fixtures override confidence
-- only after checking that the real policy avoids risky Smash ranks.
function M:hitChance(b,q,p,tech)
 local c=battles[b]
 if c and c.actor==q and c.forceReliable then return 0.95 end
 return originalHitChance(self,b,q,p,tech)
end
function M:choose(b,row)
 local c=battles[b]
 if c and c.row==row and c.forceCommand then
  return {CONST.BATTLE_COM.BATTLE_COM_P_PARAMETER,10,c.tech}
 end
 return originalChoose(self,b,row)
end
local families={
 {name='native_double',ids={130,132,134,136,138,140,142,144,146,148},double=true},
 {name='native_smash',ids={330,332,334,336,338,340,342,344,346,348}},
 {name='copy_double',ids={700029,700030,700031,700032,700033,910500,910501,910502,910503,910504},double=true},
 {name='copy_smash',ids={700047,700048,700049,700050,700051,910510,910511,910512,910513,910514}},
}
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function set(q,k,v) local field=assert(CONST[k],k);return Char.SetData(q,field,v) end
local function check(ok,name) R.checks[#R.checks+1]={name=name,pass=not not ok};assert(ok,name) end
local function clear(q) for i=9,0,-1 do if Pet.GetSkill(q,i)>=0 then assert(Pet.DelSkill(q,i)==1) end end end
local function write()
 local r={status=R.status,error=R.error,checks=R.checks,npcs=R.npcs,cases={},production_accounts_used=false,client_verified=false,
  automatic_smash_cast_confidence_fixture=true,automatic_cast_command_fixture=true}
 for _,c in ipairs(R.cases) do r.cases[#r.cases+1]={label=c.label,casts=c.casts,lastRound=c.lastRound} end
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(r));f:close()
end
local function finish(err)
 if finished then return end;finished=true;M.hitChance=originalHitChance;M.choose=originalChoose
 if lessonOwner>=0 then pcall(Char.DelDummy,lessonOwner) end
 for _,c in ipairs(R.cases) do if c.owner then
  c.done=true;pcall(M.disable,M,c.owner);pcall(Battle.ExitBattle,c.owner);pcall(Char.DelDummy,c.owner)
 end end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil;write()
end
local function setup(c)
 c.tech=c.family.ids[c.rank];c.hits={}
 clear(c.learnedPet);check(Pet.AddSkill(c.learnedPet,c.tech)==1,'learn cast '..c.label..' rank '..c.rank)
 set(c.learnedPet,'CHAR_最大魔',5000);set(c.learnedPet,'CHAR_魔',5000)
 if c.row then M:attributes(c.row) end
 set(c.actor,'CHAR_最大魔',5000);set(c.actor,'CHAR_魔',5000)
 set(c.actor,'CHAR_最大血',10000);set(c.actor,'CHAR_血',10000);set(c.actor,'CHAR_命中',100)
 local enemy=Battle.GetPlayer(c.battle,10)
 set(enemy,'CHAR_最大血',1000000);set(enemy,'CHAR_血',1000000);set(enemy,'CHAR_闪躲',0)
 local tech=assert(M:tech(c.tech))
 check(tech.command==CONST.BATTLE_COM.BATTLE_COM_P_PARAMETER and tech.scope=='single' and not tech.ranged,
  'native physical handler and target '..c.label..' rank '..c.rank)
 check(tech.cost==20*c.rank-10,'native MP metadata '..c.label..' rank '..c.rank)
 check(tech.damageFactor==(c.family.double and (1+(10*c.rank-5)/100) or (1+(20*c.rank-10)/100)),
  'native damage metadata '..c.label..' rank '..c.rank)
 if c.row then
  c.forceCommand=false
  c.forceReliable=false
  if not c.family.double then
   check(M:choose(c.battle,c.row)[3]~=c.tech,'real AI avoids risky Smash rank '..c.label..' rank '..c.rank)
   c.forceReliable=true
  end
  check(M:choose(c.battle,c.row)[3]==c.tech,'AI selects affordable learned rank '..c.label..' rank '..c.rank)
  set(c.actor,'CHAR_魔',tech.cost-1)
  check(M:choose(c.battle,c.row)[3]~=c.tech,'AI skips unaffordable rank '..c.label..' rank '..c.rank)
  set(c.actor,'CHAR_魔',5000)
  c.forceCommand=true -- Execution fixture; planning assertions above use real choose.
 end
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleDodgeRateEvent',function(b,a,d,rate) if battles[b] then return 0 end;return rate end)
T:regCallback('BattleEscapeEvent',function(b,q,rate) if battles[b] then return 0 end;return rate end)
T:regCallback('DamageCalculateEvent',function(a,d,original,damage,b,c1,c2,c3)
 local c=battles[b];if not c then return damage end
 if a==c.actor and c3==c.tech then
  c.hits[#c.hits+1]={tech=c3,original=original,damage=damage,target=Battle.GetPos(b,d)}
  return damage
 end
 return 0
end)
T:regCallback('BeforeBattleTurnStartEvent',function(b)
 local c=battles[b];if not c or c.done or finished then return end
 c.beforeMP=get(c.actor,'CHAR_魔')
 c.nativeCost=Char.CalcConsumeFp(c.actor,c.tech)
 local enemy=Battle.GetPlayer(b,10)
 set(enemy,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(enemy,'CHAR_BattleCom2',10);set(enemy,'CHAR_BattleCom3',7400)
 c.beforeHP=get(enemy,'CHAR_血')
end)
T:regCallback('AfterBattleTurnEvent',function(b)
 local c=battles[b];if not c or c.done or finished then return end
 local ok,err=xpcall(function()
  local used=c.beforeMP-get(c.actor,'CHAR_魔')
  c.lastRound={rank=c.rank,tech=c.tech,mp_used=used,native_cost=c.nativeCost,declared_cost=20*c.rank-10,hits=c.hits}
  if used==0 and #c.hits==0 then return end -- Initial dummy guard turn.
  check(used==c.nativeCost and used>0,'calculated native MP paid once '..c.label..' rank '..c.rank)
  check(#c.hits==1 and c.hits[1].original>0 and c.hits[1].damage>0,
   'one positive native damage hit '..c.label..' rank '..c.rank)
  check(get(Battle.GetPlayer(b,10),'CHAR_血')<c.beforeHP,'enemy HP reduced '..c.label..' rank '..c.rank)
  check(Pet.GetSkill(c.learnedPet,0)==c.tech,'learned skill retained '..c.label..' rank '..c.rank)
  c.casts[#c.casts+1]=c.lastRound
  if c.rank==10 then
   if c.row then
    c.forceCommand=false
    check(Pet.AddSkill(c.learnedPet,c.family.ids[5])==1,'keep lower rank for MP fallback '..c.label)
    set(c.actor,'CHAR_魔',90)
    check(M:choose(b,c.row)[3]==c.family.ids[5],'AI falls back to learned V '..c.label)
    clear(c.learnedPet)
    check(M:choose(b,c.row)[3]~=c.family.ids[5],'AI skips forgotten rank '..c.label)
   end
   c.done=true;completed=completed+1
   if completed==#R.cases then finish() else write() end
  else c.rank=c.rank+1;setup(c) end
 end,debug.traceback)
 if not ok then finish(err) end
end)
local function add(kind,family)
 local c={kind=kind,family=family,rank=5,label=kind..'_'..family.name,casts={}};R.cases[#R.cases+1]=c
 c.owner=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='PET_PHYSICAL_CAST'})
 check(c.owner>=0,'isolated battle owner '..c.label)
 set(c.owner,'CHAR_等级',100);set(c.owner,'CHAR_体力',50000);NLG.UpChar(c.owner)
 c.pet=Char.GivePet(c.owner,3004,1);check(c.pet>=0,'native main pet '..c.label)
 c.learnedPet=kind=='proxy' and Char.GivePet(c.owner,3004,1) or c.pet
 for _,q in ipairs({c.pet,c.learnedPet}) do
  clear(q);set(q,'CHAR_等级',100);set(q,'CHAR_体力',50000);set(q,'CHAR_魔法',10000);set(q,'CHAR_力量',1000)
  Pet.UpPet(c.owner,q);set(q,'CHAR_命中',100);set(q,'CHAR_攻击力',500);set(q,'CHAR_敏捷',1000)
 end
 check(Char.SetPetDepartureState(c.owner,0,2)==1,'main pet selected '..c.label)
 if kind=='proxy' then check(M:enable(c.owner),'automatic squad enabled '..c.label);c.row=M.active[c.owner].rows[1];c.actor=c.row.proxy
 else c.actor=c.pet end
 c.battle=Battle.PVE(c.owner,c.owner,nil,{1},{100},{0})
 check(c.battle>=0,'native physical battle '..c.label);battles[c.battle]=c
 local enemy=Battle.GetPlayer(c.battle,10)
 set(enemy,'CHAR_防御力',100);set(enemy,'CHAR_攻击力',1);set(enemy,'CHAR_敏捷',1);set(enemy,'对象_ENEMY_BossFlg',0)
 setup(c)
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  lessonOwner=Char.CreateDummy({mapType=0,floor=60003,x=36,y=19,image=100002,name='PET_PHYSICAL_LESSONS'})
  check(lessonOwner>=0,'isolated lesson owner');Char.AddGold(lessonOwner,900000)
  local pet=Char.GivePet(lessonOwner,3004,1);check(pet>=0,'native lesson pet');clear(pet)
  local lessons=tutor:lessons('physical');local indexes={}
  for i,s in ipairs(lessons) do check(not indexes[s.id],'unique physical lesson '..s.id);indexes[s.id]=i end
  for _,family in ipairs(families) do
   for rank=5,10 do
    local id=family.ids[rank];local index=assert(indexes[id]);local ix=Tech.GetTechIndex(id)
    check(ix>=0 and lessons[index].cost==1000,'pet physical lesson '..id)
    check(Tech.GetData(ix,CONST.TECH_REMAIN)==0,'pet-only technique '..id)
    local uuid=Pet.GetUUID(pet);local gold=Char.GetGold(lessonOwner)
    tutor:show(tutor.npc,lessonOwner,'learning',math.ceil(index/5),0,uuid,nil,'physical')
    tutor:answer(tutor.npc,lessonOwner,7320,0,tostring((index-1)%5+1))
    check(tutor.sessions[lessonOwner].id==id and tutor.sessions[lessonOwner].kind=='learnConfirm','exact paginated confirmation '..id)
    tutor:answer(tutor.npc,lessonOwner,7322,8,'')
    check(Pet.GetSkill(pet,0)<0 and Char.GetGold(lessonOwner)==gold,'cancel free '..id)
    tutor:answer(tutor.npc,lessonOwner,7320,0,tostring((index-1)%5+1));tutor:answer(tutor.npc,lessonOwner,7322,4,'')
    check(Pet.GetSkill(pet,0)==id and Char.GetGold(lessonOwner)==gold-1000,'learn exact rank and fee '..id)
    check(not tutor:learnPet(tutor.npc,lessonOwner,0,uuid,id) and Char.GetGold(lessonOwner)==gold-1000,'duplicate free '..id)
    check(tutor:forget(tutor.npc,lessonOwner,0,uuid,0,id),'forget exact rank '..id)
   end
   Char.Warp(lessonOwner,0,60003,38,19)
   for _,old in ipairs({family.ids[1],family.ids[5]}) do
    clear(pet);check(Pet.AddSkill(pet,old)==1,'learn old upgrade rank '..old);set(pet,'CHAR_最大魔',190);set(pet,'CHAR_魔',0)
    local uuid=Pet.GetUUID(pet);local quote=upgrade:quote(lessonOwner,0,uuid)
    check(#quote.entries==1 and quote.entries[1].id==family.ids[10],'old native/copy upgrades to matching X '..old)
    check(quote.total==(10-(old==family.ids[1] and 1 or 5))*1000,'upgrade rank difference fee '..old)
    set(pet,'CHAR_最大魔',170);check(upgrade:quote(lessonOwner,0,uuid).entries[1].id==family.ids[9],'MP170 selects IX '..old)
    set(pet,'CHAR_最大魔',169);check(upgrade:quote(lessonOwner,0,uuid).entries[1].id==family.ids[8],'MP169 skips IX '..old)
    set(pet,'CHAR_最大魔',190);quote=upgrade:quote(lessonOwner,0,uuid);local gold=Char.GetGold(lessonOwner)
    check(upgrade:upgrade(upgrade.npc,lessonOwner,quote),'upgrade existing rank '..old)
    check(Pet.GetSkill(pet,0)==family.ids[10] and Char.GetGold(lessonOwner)==gold-quote.total,'exact upgraded ID and fee '..old)
    check(#upgrade:quote(lessonOwner,0,uuid).entries==0,'X has no paid upgrade '..old)
   end
   clear(pet);Char.Warp(lessonOwner,0,60003,36,19)
  end
  clear(pet);check(Pet.AddSkill(pet,337)==1,'zero-cost legacy V still valid');set(pet,'CHAR_最大魔',190)
  check(upgrade:quote(lessonOwner,0,Pet.GetUUID(pet)).entries[1].id==348,'legacy V337 joins native X series')
  Char.DelDummy(lessonOwner);lessonOwner=-1
  for _,kind in ipairs({'main','proxy'}) do for _,family in ipairs(families) do add(kind,family) end end
  T:AddInterval(100,function()
   if finished then return end
   local good,e=xpcall(function()
    if os.time()-started>48 then error('pet physical probe timeout') end
    for _,c in ipairs(R.cases) do
     if Battle.IsWaitingCommand(c.owner)==1 then
      set(c.owner,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(c.owner,'CHAR_BattleCom2',-1)
      set(c.owner,'CHAR_BattleCom3',7400);set(c.owner,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(c.owner,'CHAR_BattleMode',3)
     end
     if Battle.IsWaitingCommand(c.pet)==1 then
      local manual=c.kind=='main' and not c.done
      Battle.ActionSelect(c.pet,manual and CONST.BATTLE_COM.BATTLE_COM_P_PARAMETER or CONST.BATTLE_COM.BATTLE_COM_GUARD,
       manual and 10 or Battle.GetPos(c.battle,c.pet),manual and c.tech or 7400)
     end
    end
    M:tick()
   end,debug.traceback);if not good then finish(e) end
  end,1)
  write()
 end,debug.traceback);if not ok then finish(err) end
end,0)
