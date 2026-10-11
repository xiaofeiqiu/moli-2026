-- Native creation, growth and a real attack; only disposable dummy owners.
local R={status='RUNNING',checks={},npcs={},production_accounts_used=false}
local T=ModuleBase:createModule('greenGiantProbe'):new();T:load()
local p,pet,b=-1,-1,-1;local finished=false;local hit=false;local start=os.time()
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function set(q,k,v) local field=assert(CONST[k],k);return Char.SetData(q,field,v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function finish(err)
 if finished then return end;finished=true
 if p>=0 then pcall(Battle.ExitBattle,p)
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end
  pcall(Char.DelDummy,p)
 end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b then return 0 end;return rate end)
T:regCallback('BattleDodgeRateEvent',function(bi,a,d,rate) if bi==b then return 0 end;return rate end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi)
 if bi==b and a==pet then hit=damage>0;R.attack_damage=damage end;return damage
end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi~=b then return false end
 local e=Battle.GetPlayer(b,10);set(e,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(e,'CHAR_BattleCom2',10);set(e,'CHAR_BattleCom3',7400)
 return false
end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished then return end
 local ok,err=xpcall(function() check(hit,'new giant executes native physical attack');check(get(pet,'CHAR_血')>0,'new giant survives native turn') end,debug.traceback)
 finish(not ok and err or nil)
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  local ix=Data.EnemyBaseGetDataIndex(800412);local old=Data.EnemyBaseGetDataIndex(811)
  check(ix>=0 and old>=0,'new and original species loaded')
  local fields={'BASEVITAL','BASESTR','BASETGH','BASEQUICK','BASEMAGIC'};local ranks={36,45,22,25,12};local original={36,33,22,7,12}
  for i,k in ipairs(fields) do
   check(Data.EnemyBaseGetData(ix,CONST['DATA_ENEMYBASE_'..k])==ranks[i],'new species base rank '..k)
   check(Data.EnemyBaseGetData(old,CONST['DATA_ENEMYBASE_'..k])==original[i],'original species unchanged '..k)
  end
  for _,k in ipairs({'INITNUM','LVUPPOINT','TRIBE','MODLOYALTY','GET','RUN','HITRATE','AVOIDRATE','EARTHAT','WATERAT','FIREAT','WINDAT','POISON','SLEEP','STONE','DRUNK','CONFUSION','AMNESIA','RARE','LEVELUPRANDOMPATTERN','CRITICAL','COUNTER','SLOT','IMGNUMBER','MODEXP','SIZE','ALBUMNO','ALBUMEXPLAINATION','ALBUMCANPETFLG','PETSKILL1','PETSKILL2','PETSKILL3','PETSKILL4','PETSKILL5','PETSKILL6','PETSKILL7','PETSKILL8','PETSKILL9','PETSKILL10'}) do
   check(Data.EnemyBaseGetData(ix,CONST['DATA_ENEMYBASE_'..k])==Data.EnemyBaseGetData(old,CONST['DATA_ENEMYBASE_'..k]),'inherited native species field '..k)
  end
  local ei=Data.EnemyGetDataIndex(800412);check(ei>=0 and Data.EnemyGetData(ei,CONST.DATA_ENEMY_TEMPNO)==800412,'summon ID maps to new species')
  p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='GREEN_GIANT_TEST'});check(p>=0,'isolated owner')
  set(p,'CHAR_等级',50);set(p,'CHAR_体力',50000);NLG.UpChar(p)
  local donor=Char.GivePet(p,811,1);pet=Char.GivePet(p,800412,1)
  check(donor>=0 and pet>=0,'native ordinary and modified giant creation')
  check(get(pet,'CHAR_名字')=='改造绿巨人','native generated pet name')
  check(get(pet,'宠物_PETID')==800412 and get(donor,'宠物_PETID')==811,'separate species identities')
  check(get(pet,'CHAR_等级')==1,'new giant begins at level 1')
  for _,k in ipairs({'CHAR_形象','CHAR_种族','CHAR_地属性','CHAR_水属性','CHAR_火属性','CHAR_风属性','宠物_技能栏'}) do check(get(pet,k)==get(donor,k),'inherited generated field '..k) end
  local arts={'宠档_体成','宠档_力成','宠档_强成','宠档_敏成','宠档_魔成'};R.native_full_ranks={};R.donor_full_ranks={}
  for i,k in ipairs(arts) do
   local full=Pet.FullArtRank(pet,CONST[k]);local before=Pet.FullArtRank(donor,CONST[k])
   R.native_full_ranks[i]=full;R.donor_full_ranks[i]=before
   check(full-before==ranks[i]-original[i],'native full-rank difference '..i)
  end
  for slot=0,9 do check(Pet.GetSkill(pet,slot)==Pet.GetSkill(donor,slot),'inherited initial skill '..slot) end
  local admin=assert(getModule('adminCommands'));admin.commandHandlers.getPet(p,{'800412'})
  local generated=Char.GetPet(p,2);check(generated>=0 and get(generated,'宠物_PETID')==800412 and get(generated,'CHAR_名字')=='改造绿巨人','existing GM getPet command creates correct pet')
  set(pet,'CHAR_经验',1000000);Pet.UpPet(p,pet);R.grown_level=get(pet,'CHAR_等级')
  check(R.grown_level>1 and R.grown_level<=50,'native experience-based growth')
  for i,k in ipairs(arts) do check(Pet.FullArtRank(pet,CONST[k])==R.native_full_ranks[i],'species rank retained after growth '..i) end
  check(Char.SetPetDepartureState(p,1,2)==1,'modified giant selected as main pet')
  b=Battle.PVE(p,p,nil,{1},{100},{0});check(b>=0,'native battle created')
  T:AddInterval(100,function()
   if finished then return end
   local good,e=xpcall(function()
    if os.time()-start>40 then error('green giant native timeout') end
    if Battle.IsWaitingCommand(p)==1 then set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',-1);set(p,'CHAR_BattleCom3',7400);set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3) end
    if Battle.IsWaitingCommand(pet)==1 then Battle.ActionSelect(pet,CONST.BATTLE_COM.BATTLE_COM_ATTACK,10,7300) end
   end,debug.traceback);if not good then finish(e) end
  end)
 end,debug.traceback);if not ok then finish(err) end
end,0)
