-- Native manual/AI casts and wire animation IDs, using only disposable owners.
local R={status='RUNNING',checks={},npcs={},cases={},production_accounts_used=false,client_verified=false}
local T=ModuleBase:createModule('petQigongBattleProbe'):new();T:load()
local M=getModule('fivePet');local tutor=getModule('petSkillTutor')
local cases={};local completed=0;local started=os.time();local finished=false
local limits={{1,1},{1,2},{2,2},{2,3},{3,3},{3,4},{3,5},{4,5},{4,6},{5,7}}
local function g(q,k)return Char.GetData(q,CONST[k])end
local function s(q,k,v)return Char.SetData(q,CONST[k],v)end
local function write()local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()end
local function check(ok,label)R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label)end
local function finish(err)
 if finished then return end;finished=true
 for _,c in ipairs(R.cases)do if c.owner then pcall(M.disable,M,c.owner);pcall(Battle.ExitBattle,c.owner);pcall(Char.DelDummy,c.owner)end end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil;write()
end
local function capture(c)
 R.capture_requested=c.label..':'..(c.rounds+1);write()
 local stop=os.clock()+3
 repeat
  local f=io.open(('__REPORT__'):gsub('pet_qigong_battle_native_result.json','pet_qigong_capture_ack.json'),'rb')
  if f then local raw=f:read('*a');f:close();local ok,value=pcall(JSON.decode,raw)
   if ok and value.capture==R.capture_requested then
    c.packets[#c.packets+1]=value.buffers
    local packet=value.buffers.main..value.buffers.extra
    local expected=c.phase=='empty_mp' and 7300 or c.native
    check(packet:find('SKL|s'..string.format('%X',expected)..'|',1,true)~=nil,'compatible animation '..R.capture_requested)
    check(packet:find('SKL|s'..string.format('%X',c.tech)..'|',1,true)==nil,'custom animation absent '..R.capture_requested)
    return
   end
  end
 until os.clock()>stop
 error('native packet capture timeout '..c.label)
end
T:regCallback('BattleSurpriseEvent',function()return 0 end)
T:regCallback('BattleDodgeRateEvent',function(b,a,d,r)if cases[b]then return 0 end;return r end)
T:regCallback('BattleEscapeEvent',function(b,q,r)if cases[b]then return 0 end;return r end)
T:regCallback('DamageCalculateEvent',function(a,d,o,damage,b,c1,c2,c3)
 local c=cases[b];if not c then return damage end
 if a==c.actor then
  c.hits=c.hits+1;c.damage=c.damage+damage;c.lastTech=c3
  if c.hits==1 and not finished then local ok,err=xpcall(function()capture(c)end,debug.traceback);if not ok then finish(err)end end
 end
 return 0 -- Preserve targets for the second real cast.
end)
T:regCallback('BeforeBattleTurnStartEvent',function(b)
 local c=cases[b];if not c then return end
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then s(q,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);s(q,'CHAR_BattleCom2',pos);s(q,'CHAR_BattleCom3',7400)end end
 c.beforeMp=g(c.actor,'CHAR_魔');c.hits=0;c.damage=0;c.lastTech=nil
end)
T:regCallback('AfterBattleTurnEvent',function(b)
 local c=cases[b];if not c or c.complete or finished then return end
 local ok,err=xpcall(function()
  local used=c.beforeMp-g(c.actor,'CHAR_魔')
  if c.phase=='empty_mp' then
   c.empty_mp={used=used,mp=g(c.actor,'CHAR_魔'),hits=c.hits,tech=c.lastTech,command=g(c.actor,'CHAR_BattleCom1')}
   check(used==0 and g(c.actor,'CHAR_魔')==0,'insufficient MP never consumes MP '..c.label)
   check(c.kind=='proxy' and c.lastTech==7300 and c.hits==1 or c.kind=='main' and (c.hits==0 or c.lastTech==7300),'insufficient MP skips skill or uses normal attack '..c.label)
   check(Pet.GetSkill(c.learnedPet,0)==c.tech,'insufficient MP preserves learned skill '..c.label)
   if c.kind=='proxy' then check(M:ai(c.owner,c.learnedPet).tech==c.tech,'insufficient MP preserves AI '..c.label)end
   c.complete=true;completed=completed+1
   if completed==#R.cases then finish()else write()end
   return
  end
  if used==0 and c.hits==0 then return end
  c.casts[#c.casts+1]={hits=c.hits,mp_used=used,damage=c.damage,tech=c.lastTech}
  check(used==c.rank*5,'native MP '..c.label)
  check(c.hits>=limits[c.rank][1] and c.hits<=limits[c.rank][2],'ordinary projectile count '..c.label)
  check(c.damage>0 and c.lastTech==c.native,'native damage '..c.label)
  check(Pet.GetSkill(c.learnedPet,0)==c.tech,'learned ID retained '..c.label)
  if c.kind=='proxy' then check(M:ai(c.owner,c.learnedPet).tech==c.tech,'saved AI retained '..c.label)end
  c.rounds=c.rounds+1
  -- Pet.UpPet restores the native MP ceiling; refill only these disposable pets.
  s(c.learnedPet,'CHAR_魔',g(c.learnedPet,'CHAR_最大魔'));s(c.actor,'CHAR_魔',g(c.actor,'CHAR_最大魔'))
  if c.rounds>=2 then
   c.phase='empty_mp';s(c.learnedPet,'CHAR_魔',0);s(c.actor,'CHAR_魔',0)
  end
  if completed==#R.cases then finish()else write()end
 end,debug.traceback)
 if not ok then finish(err)end
end)
local function add(kind,rank)
 local c={kind=kind,rank=rank,label=kind..'_LV'..rank,tech=910399+rank,native=399+rank,rounds=0,hits=0,damage=0,casts={},packets={}}
 R.cases[#R.cases+1]=c
 c.owner=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='QIGONG_CAST_TEST'});check(c.owner>=0,'isolated owner '..c.label)
 local p=c.owner;s(p,'CHAR_等级',50);s(p,'CHAR_体力',50000);NLG.UpChar(p)
 c.pet=Char.GivePet(p,3004,1);check(c.pet>=0,'main pet '..c.label)
 c.learnedPet=kind=='proxy' and Char.GivePet(p,3004,1) or c.pet
 for i=9,0,-1 do if Pet.GetSkill(c.learnedPet,i)>=0 then Pet.DelSkill(c.learnedPet,i)end end
 check(Pet.AddSkill(c.learnedPet,c.tech)==1,'learned rank '..c.label);Pet.UpPet(p,c.learnedPet)
 check(Char.SetPetDepartureState(p,0,2)==1,'main pet selected '..c.label)
 if kind=='proxy' then M:saveAI(p,c.learnedPet,{mode='skill',tech=c.tech,target='weak',threshold=30});check(M:enable(p),'five pet enabled '..c.label);c.actor=M.active[p].rows[1].proxy
 else c.actor=c.pet end
 c.battle=Battle.PVE(p,p,nil,{1,1,1,1,1},{20,20,20,20,20},{0,1,2,3,4});check(c.battle>=0,'native battle '..c.label);cases[c.battle]=c
 s(c.learnedPet,'CHAR_最大魔',10000);s(c.learnedPet,'CHAR_魔',10000);s(c.actor,'CHAR_最大魔',10000);s(c.actor,'CHAR_魔',10000)
 s(c.actor,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_P_SPIRACLESHOT);s(c.actor,'CHAR_BattleCom3',c.tech)
 s(c.actor,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_P_SPIRACLESHOT);s(c.actor,'CHAR_Battle2Com3',c.tech)
 s(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_P_SPIRACLESHOT);s(p,'CHAR_BattleCom3',c.tech)
 tutor:normalizeBattleTechs(c.battle)
 check(g(c.actor,'CHAR_BattleCom3')==c.native and g(c.actor,'CHAR_Battle2Com3')==c.native,'both command slots mapped '..c.label)
 check(g(p,'CHAR_BattleCom3')==c.tech,'owner unchanged '..c.label)
 s(c.actor,'CHAR_BattleCom3',451);tutor:normalizeBattleTechs(c.battle);check(g(c.actor,'CHAR_BattleCom3')==451,'EX unchanged '..c.label)
 s(c.actor,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);s(c.actor,'CHAR_BattleCom3',c.tech)
 tutor:normalizeBattleTechs(c.battle);check(g(c.actor,'CHAR_BattleCom3')==c.tech,'other commands unchanged '..c.label)
 s(c.actor,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);s(c.actor,'CHAR_BattleCom3',7400);s(c.actor,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE)
 s(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);s(p,'CHAR_BattleCom3',7400)
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  reloadModule('petSkillTutor');tutor=assert(getModule('petSkillTutor'))
  check(type(tutor.normalizeBattleTechs)=='function' and Char.IsValidCharIndex(tutor.npc),'hot reload retains pet tutor and animation fix')
  local handlers=0;for _,callback in pairs(tutor.callbacks)do if callback.key=='BeforeBattleTurnStartEvent' then handlers=handlers+1 end end
  check(handlers==1,'hot reload registers exactly one animation mapping callback')
  for _,kind in ipairs({'main','proxy'})do for rank=1,10 do add(kind,rank)end end
  T:AddInterval(100,function()
   if finished then return end
   local ok,e=xpcall(function()
    if os.time()-started>45 then error('native cast timeout')end
    for _,c in ipairs(R.cases)do if not c.complete then local p=c.owner
     if Battle.IsWaitingCommand(p)==1 then s(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);s(p,'CHAR_BattleCom2',-1);s(p,'CHAR_BattleCom3',7400);s(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);s(p,'CHAR_BattleMode',3)end
     if Battle.IsWaitingCommand(c.pet)==1 then Battle.ActionSelect(c.pet,c.kind=='main' and CONST.BATTLE_COM.BATTLE_COM_P_SPIRACLESHOT or CONST.BATTLE_COM.BATTLE_COM_GUARD,c.kind=='main' and 10 or 5,c.kind=='main' and c.tech or 7400)end
    end end
    M:tick()
   end,debug.traceback)
   if not ok then finish(e)end
  end,1);write()
 end,debug.traceback)
 if not ok then finish(err)end
end,0)
