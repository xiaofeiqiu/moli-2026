-- Automatic learned-skill decisions and actual native effects, with no player database.
local R={status='RUNNING',checks={},npcs={},actions={},production_accounts_used=false}
local M=assert(getModule('fivePet'));local T=ModuleBase:createModule('smartAiProbe'):new();T:load()
local p,b=-1,-1;local pets,rows,allies={},{},{};local row;local round=1;local finished=false;local started=os.time()
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function set(q,k,v) local field=assert(CONST[k],k);return Char.SetData(q,field,v) end
local function status(q,k,v) local field=assert(CONST[k],k);Battle.SetBattleCharacterStatus(q,field,v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function finish(err)
 if finished then return end;finished=true
 if p>=0 then pcall(M.disable,M,p);pcall(Battle.ExitBattle,p)
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end
  pcall(Char.DelDummy,p)
 end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end
local function learn(ids)
 for slot=9,0,-1 do if Pet.GetSkill(row.pet,slot)>=0 then Pet.DelSkill(row.pet,slot) end end
 for _,id in ipairs(ids) do check(Pet.AddSkill(row.pet,id)==1,'learn skill '..id) end
end
local function reset()
 for _,q in ipairs(allies) do
  set(q,'CHAR_最大血',1000);set(q,'CHAR_血',1000)
  set(q,'对象_战死',0)
  for _,k in ipairs({'战属_毒','战属_睡','战属_石','战属_醉','战属_忘','战属_乱','战属_恢复回合'}) do status(q,k,0) end
 end
 for _,pet in ipairs(pets) do set(pet,'CHAR_最大血',1000);set(pet,'CHAR_血',1000) end
 set(row.pet,'CHAR_最大魔',2000);set(row.pet,'CHAR_魔',1000)
 set(row.proxy,'CHAR_最大魔',2000);set(row.proxy,'CHAR_魔',1000)
 set(row.pet,'CHAR_回复',100);set(row.proxy,'CHAR_回复',100)
 set(row.pet,'CHAR_攻击力',100);set(row.proxy,'CHAR_攻击力',100)
 set(row.proxy,'CHAR_命中',0);set(row.proxy,'CHAR_精神',100);set(row.proxy,'CHAR_魔攻',0)
 for pos=10,19 do local q=Battle.GetPlayer(b,pos)
  if q>=0 then
   set(q,'CHAR_最大血',10000);set(q,'CHAR_血',10000)
   set(q,'CHAR_防御力',200);set(q,'CHAR_闪躲',0);set(q,'CHAR_精神',100);set(q,'CHAR_魔抗',0)
   set(q,'CHAR_攻击力',100);set(q,'CHAR_魔',100)
   set(q,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK)
   set(q,'CHAR_BattleCom3',7300)
   for _,k in ipairs({'战属_攻反','战属_攻吸','战属_攻无','战属_魔反','战属_魔吸','战属_魔无','战属_毒','战属_睡','战属_石','战属_醉','战属_乱','战属_忘'}) do status(q,k,0) end
  end
 end
end
local function buffAll()
 for _,q in ipairs(allies) do status(q,'战属_恢复回合',3) end
end
local function planned(id,label) local cmd=M:choose(b,row);R.decisions=R.decisions or {};R.decisions[#R.decisions+1]={label=label,cmd=cmd};check(cmd[3]==id,label);return cmd end
local function decisions()
 reset();learn({730,6100,6101,6200,6709,6800,6500,1930,1931})
 check(M:config(p).pets[tostring(Pet.GetUUID(row.pet))]==nil,'no stored AI configuration required')
 set(p,'CHAR_血',400);set(pets[1],'CHAR_血',300)
 local first=planned(730,'learned guard precedes every support skill')
 check(first[2]==0,'guard prioritizes owner')
 set(row.proxy,'CHAR_魔',10)
 planned(730,'single guard affordable with exactly one skill cost')
 reset();set(pets[1],'CHAR_血',590)
 planned(6100,'small deficit selects inexpensive heal tier')
 reset();learn({6100,6101});set(pets[1],'CHAR_血',300)
 planned(6101,'larger deficit selects stronger learned heal tier')
 set(row.proxy,'CHAR_魔',30);planned(6100,'insufficient MP falls back to affordable healing tier')
 reset();learn({6100,6200})
 for _,q in ipairs({p,pets[1],rows[1].proxy,rows[2].proxy}) do set(q,'CHAR_血',550) end
 check(planned(6200,'multiple injured allies select area healing')[2]==25,'area heal selects useful native cross')
 reset();learn({6100,6500});set(pets[1],'CHAR_血',600)
 planned(6500,'exactly sixty percent does not trigger healing')
 check(M:choose(b,row)[2]==25,'opening area regeneration covers four allies')
 for _,q in ipairs(allies) do if Battle.GetPos(b,q)<=7 then status(q,'战属_恢复回合',3) end end
 check(M:choose(b,row)[2]==28,'regeneration covers outer pet with fewer redundant buffs')
 buffAll();check(M:choose(b,row)[3]~=6500,'active regeneration is not repeatedly overwritten')
 reset();learn({6800,6100,6709,6500});set(pets[1],'CHAR_血',0)
 check(planned(6800,'dead ally automatically triggers learned resurrection')[2]==5,'resurrection targets fallen main pet')
 reset();status(pets[1],'战属_毒',3);planned(6709,'cleanse automatically detects actual poison')
 status(pets[1],'战属_毒',0);planned(6500,'cleanse stops after anomaly disappears')
 reset();learn({1930,1931,7100});check(#M:skills(row.pet)==2,'passive skills excluded from active catalog')
 check(planned(1931,'stronger magic selected against durable enemies')[1]==CONST.BATTLE_COM.BATTLE_COM_P_MAGIC,'learned magic uses native magic command')
 set(row.proxy,'CHAR_魔',10);planned(1930,'lower learned spell tier used when MP limited')
 set(row.proxy,'CHAR_魔',0);planned(7300,'no MP uses normal attack')
 set(row.proxy,'CHAR_魔',1000);status(row.proxy,'战属_忘',3);planned(7300,'forget status prevents every learned spell');status(row.proxy,'战属_忘',0)
 learn({1930,6100});set(row.proxy,'CHAR_魔',30);planned(7300,'offense preserves MP for learned emergency healing')
 reset();learn({1930});set(row.proxy,'CHAR_攻击力',10000)
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then set(q,'CHAR_血',1);set(q,'CHAR_防御力',0) end end
 planned(7300,'conservative lethal normal attack saves skill MP')
 reset();learn({1930})
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then status(q,'战属_攻反',3) end end
 planned(1930,'physical reflection makes magic preferable')
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then status(q,'战属_魔反',3) end end
 planned(7400,'both physical and magic reflection cause defense')
 reset();learn({1930,2330})
 check(M:choose(b,row)[3]==2330,'multiple enemies favor learned area magic')
 -- Every single/strong elemental spell uses its own skill element, not pet elements.
 local elementFields={'CHAR_地属性','CHAR_水属性','CHAR_火属性','CHAR_风属性'}
 local single={1930,2030,2130,2230};local strong={2330,2430,2530,2630}
 R.propMatrix={}
 for i=1,4 do local ap={0,0,0,0};ap[i]=100;R.propMatrix[i]={}
  for j=1,4 do local dp={0,0,0,0};dp[j]=100;R.propMatrix[i][j]={Battle.CalcPropScore(ap,dp,0),Battle.CalcPropScore(ap,dp,1)} end
 end
 for magic=1,4 do
  reset();learn(single)
  local vulnerable=magic%4+1
  for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then
   for element,k in ipairs(elementFields) do set(q,k,element==vulnerable and 100 or 0) end
  end end
  R.elementScores=R.elementScores or {};R.elementScores[magic]={}
  for _,id in ipairs(single) do local t=M:tech(id);R.elementScores[magic][#R.elementScores[magic]+1]={tech=t,score=M:attackScore(b,row,t,10)} end
  planned(single[magic],'single element '..magic..' exploits actual enemy element')
  learn({1930,2030,2130,2230,2330,2430,2530,2630})
  check(planned(strong[magic],'strong element '..magic..' chosen for several vulnerable enemies')[2]>=20,'strong element '..magic..' uses native cross target')
 end
 reset();learn({130})
 planned(130,'诸刃 automatically used by healthy pet')
 set(row.proxy,'CHAR_血',499);planned(7300,'诸刃 defense penalty avoided below half HP')
 -- 乾坤 metadata, target choice, accuracy cost, support priority and MP fallbacks.
 local function kunStats(avoid)
  set(row.proxy,'CHAR_攻击力',1000);set(row.proxy,'CHAR_命中',0)
  for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then
   set(q,'CHAR_防御力',0);set(q,'CHAR_闪躲',avoid or 0)
  end end
 end
 reset();kunStats();learn({300});planned(300,'standard 乾坤 uses DD and HR parameters')
 learn({330});planned(330,'native pet 乾坤 tier is automatically recognized')
 learn({804928});planned(804928,'generated pet 乾坤 needs no manual configuration')
 learn({804928,804937});planned(804937,'乾坤 higher damage tier selected when useful and affordable')
 set(row.proxy,'CHAR_魔',10);planned(804928,'乾坤 insufficient MP selects cheaper learned tier')
 set(row.proxy,'CHAR_魔',9);planned(7300,'乾坤 no affordable tier falls back to normal attack')
 set(row.proxy,'CHAR_魔',1000);set(row.proxy,'CHAR_血',499)
 planned(804937,'乾坤 does not inherit 诸刃 half HP restriction')
 set(row.proxy,'CHAR_血',300);planned(7400,'乾坤 still respects emergency survival at thirty percent HP')
 reset();kunStats();learn({730,804937});set(p,'CHAR_血',400)
 planned(730,'learned guard keeps priority over 乾坤')
 reset();kunStats();learn({6100,804937});set(pets[1],'CHAR_血',550)
 planned(6100,'learned healing keeps priority over 乾坤')
 reset();kunStats();learn({6100,804937});set(row.proxy,'CHAR_魔',30)
 planned(7300,'乾坤 reserves learned emergency healing MP')
 reset();kunStats();learn({804937});status(row.proxy,'战属_忘',3)
 planned(7300,'forget status disables 乾坤');status(row.proxy,'战属_忘',0)
 kunStats(80);planned(7300,'乾坤 avoids risky misses against high dodge enemies')
 learn({1930,804937});planned(1930,'high dodge makes learned magic preferable to 乾坤')
 learn({804937});set(Battle.GetPlayer(b,10),'CHAR_闪躲',0)
 check(planned(804937,'乾坤 chooses safer low dodge enemy')[2]==10,'乾坤 selected actual low dodge target')
 kunStats(20)
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then
  set(q,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_P_DODGE);set(q,'CHAR_BattleCom3',930)
 end end
 planned(7300,'乾坤 includes enemy 阳炎 avoidance bonus')
 reset();kunStats(80);set(row.proxy,'CHAR_命中',80);learn({804937})
 planned(804937,'pet hit bonus offsets enemy dodge risk for 乾坤')
 reset();kunStats();learn({130,804937})
 planned(804937,'乾坤 DD damage compared correctly with 诸刃 TR damage')
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then status(q,'战属_攻反',3) end end
 planned(7400,'乾坤 rejects every physically reflected target')
 reset();kunStats();learn({804937})
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then set(q,'CHAR_血',1) end end
 planned(7300,'乾坤 saves MP when normal attack can finish target')
 kunStats()
 reset();learn({530})
 planned(7300,'崩击 not wasted against non-defending enemies')
 local defending=Battle.GetPlayer(b,10);set(defending,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD)
 check(planned(530,'崩击 automatically punishes a defending enemy')[2]==10,'崩击 selects the defending target')
 reset();learn({6100,6200,6300})
 for _,q in ipairs(allies) do set(q,'CHAR_血',590) end
 check(planned(6300,'widespread small deficits select efficient whole-party healing')[2]==40,'whole-party healing uses native side target')
 reset();learn({6400,6500,6600})
 check(planned(6600,'whole-party recovery covers six unbuffed allies')[2]==40,'whole-party recovery uses native side target')
 buffAll();status(rows[4].proxy,'战属_恢复回合',0)
 check(planned(6400,'one missing recovery selects single spell without overwriting group')[2]==9,'single recovery selects the unbuffed outer pet')
 reset();learn({1930,730})
 M:saveAI(p,row.pet,{mode='skill',tech=7100,recoveryRules={heal={enabled=false}}})
 set(pets[1],'CHAR_血',300);planned(730,'old manual priority does not restrict learned skill strategy')
 M:saveAI(p,row.pet,{mode='guard'});planned(7400,'explicit full defense remains available')
 M:saveAI(p,row.pet,{mode='attack'});planned(730,'switching back enables automatic learned skills')
 local guarded=pets[1];Battle.SetEntryData(b,guarded,CONST.BATTLE_ENTRY_GUARDIAN,rows[2].proxy)
 rows[2].guardTurn=Battle.GetTurn(b);rows[2].guardTargets={[5]=true}
 check(M:choose(b,row,true)[3]~=730,'live decision skips ally already guarded by living companion')
 rows[2].guardTurn=nil;rows[2].guardTargets=nil
 Battle.SetEntryData(b,guarded,CONST.BATTLE_ENTRY_GUARDIAN,-1)
 reset()
end
local function metadataDecisions()
 local magic=M:tech(1930);local cross=M:tech(2330);local whole=M:tech(2700)
 check(magic.category=='magic' and magic.scope=='single' and magic.element==1,'single spell classified from native metadata')
 check(cross.scope=='cross' and #M:affected(b,10,cross)==4 and M:encodeTarget(10,cross)==30,'cross scope and native target code')
 check(whole.scope=='all' and #M:affected(b,10,whole)==10 and M:encodeTarget(10,whole)==41,'whole-side scope and native target code')
 check(M:tech(807718).element==1 and M:tech(808018).element==2,'generated spells retain original family identity despite new catalog group')
 check(M:tech(7600).statusKey=='战属_睡' and M:tech(7700).statusKey=='战属_石','physical status subtype comes from original family')
 check(M:tech(700937).statusKey=='战属_睡','copied status subtype does not depend on copied technique ID')
 check(M:ai(p,row.pet).mode=='attack','every unconfigured automatic pet defaults to intelligent combat')
 reset();learn({1930,2330})
 for pos=11,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then set(q,'CHAR_血',0) end end
 planned(1930,'one surviving enemy favors single spell over sparse area spell')
 reset();learn({1930,2700});planned(2700,'whole-side spell used when its actual coverage beats a single spell')
 reset();learn({1930});set(row.proxy,'CHAR_攻击力',1000)
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then set(q,'CHAR_防御力',0) end end
 planned(7300,'strong normal hit beats weak learned magic even without a lethal target')
 reset();learn({1930});set(row.proxy,'CHAR_魔攻',2000)
 planned(1930,'magic attack contributes to magic candidate value')
 reset();learn({409});set(row.proxy,'CHAR_攻击力',1000)
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then set(q,'CHAR_防御力',0) end end
 planned(409,'random multi-hit attack evaluates all potential enemies and projectile count')
 local shot=M:tech(409);local full=M:attackScore(b,row,shot,10);local hits=shot.minHits
 shot.minHits=1;local single=M:attackScore(b,row,shot,10)
 check(hits>1 and full>single,'additional random projectiles contribute beyond enemy count')
 status(Battle.GetPlayer(b,11),'战属_攻反',3)
 check(M:choose(b,row)[3]~=409,'random attack refuses a reflected possible splash target')
 reset();learn({7600})
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then status(q,'战属_睡',3) end end
 planned(7300,'sleep attack is not repeatedly spent on sleeping enemies')
 reset();learn({3300})
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then set(q,'CHAR_抗睡',0);status(q,'战属_毒',3) end end
 planned(3300,'learned control spell can affect poisoned enemies with a different status')
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then status(q,'战属_睡',3) end end
 planned(7300,'control spell stops when all enemies already have its actual status')
 reset();learn({3300})
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then set(q,'CHAR_抗睡',100) end end
 planned(7300,'control does not waste MP against full matching status resistance')
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then set(q,'CHAR_抗睡',0) end end
 reset();learn({5500});set(pets[1],'CHAR_血',550)
 check(planned(5500,'physical barrier protects vulnerable ally against physical threats')[2]==5,'barrier targets actual vulnerable ally')
 status(pets[1],'战属_攻反',3)
 check(M:choose(b,row)[3]~=5500,'existing barrier prevents redundant replacement')
 status(pets[1],'战属_攻反',0)
 reset();learn({6500});set(row.proxy,'CHAR_攻击力',10000)
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then set(q,'CHAR_血',pos==10 and 1 or 0);set(q,'CHAR_防御力',0) end end
 planned(7300,'last safe kill suppresses unnecessary opening regeneration')
 reset()
end
local function gradeDecisions()
 local arts={CONST['宠档_体成'],CONST['宠档_力成'],CONST['宠档_强成'],CONST['宠档_敏成'],CONST['宠档_魔成']};local saved={}
 for i,art in ipairs(arts) do saved[i]=Pet.GetArtRank(row.pet,art) end
 local function ranks(values) for i,art in ipairs(arts) do check(Pet.SetArtRank(row.pet,art,values[i])==0,'set disposable growth rank '..i) end end
 local ok,err=xpcall(function()
  reset();learn({1930});set(row.proxy,'CHAR_攻击力',160)
  for _,key in ipairs({'CHAR_地属性','CHAR_水属性','CHAR_火属性','CHAR_风属性'}) do set(row.proxy,key,0) end
  for pos=10,19 do local enemy=Battle.GetPlayer(b,pos);if enemy>=0 then
   set(enemy,'CHAR_防御力',0);for _,key in ipairs({'CHAR_地属性','CHAR_水属性','CHAR_火属性','CHAR_风属性'}) do set(enemy,key,0) end
  end end
  local ordinary,spell=M:tech(7300),M:tech(1930);local matched=false
  for attack=20,2000,5 do
   set(row.proxy,'CHAR_攻击力',attack);local normalScore,magicScore=0,0
   for pos=10,19 do
    normalScore=math.max(normalScore,M:attackScore(b,row,ordinary,pos) or 0)
    magicScore=math.max(magicScore,M:attackScore(b,row,spell,pos) or 0)
   end
   if normalScore>=magicScore*0.95 and normalScore<=magicScore*1.05 then
    R.gradeComparison={attack=attack,normal=normalScore,magic=magicScore};matched=true;break
   end
  end
  check(matched,'growth comparison uses similarly valuable physical and magical damage')
  ranks({20,60,20,25,10});check(M:petProfile(row.pet).kind=='physical','actual strength growth identifies physical tendency')
  planned(7300,'physical growth favors physical candidate when damage values are close')
  ranks({20,10,20,25,60});check(M:petProfile(row.pet).kind=='magic','actual magic growth identifies magic tendency')
  planned(1930,'same final stats and learned skills choose magic after magic growth changes')
  ranks({30,30,30,30,30});check(M:petProfile(row.pet).kind=='balanced','similar growth stays balanced')
  ranks({20,20,20,60,20});check(M:petProfile(row.pet).kind=='agile' and M:petProfile(row.pet).control>1,'agility growth increases useful control preference')
  ranks({60,20,60,20,20});check(M:petProfile(row.pet).kind=='defensive','vigor and toughness growth identify defensive tendency')
  reset();learn({5500});set(pets[1],'CHAR_血',650)
  planned(5500,'defensive pet proactively shields an ally below seventy percent')
  ranks({20,60,20,25,10});check(M:choose(b,row)[3]~=5500,'other pet types keep the sixty percent barrier threshold')
  learn({6100,1930});set(pets[1],'CHAR_血',300)
  planned(6100,'urgent learned healing keeps priority over physical growth preference')
 end,debug.traceback)
 for i,art in ipairs(arts) do Pet.SetArtRank(row.pet,art,saved[i]) end
 assert(ok,err);reset()
end
local function arbitraryMetadata()
 -- Repurpose an unused catalog record only in this disposable native process.
 -- Its arbitrary ID/name never appears in the production AI rules.
 local ix=Tech.GetTechIndex(7109);local keys={'TECH_FUNCNAME','TECH_OPTION','TECH_COMMENT','TECH_SKILLID','TECH_TARGET','TECH_FORCEPOINT','TECH_NAME'};local saved={}
 for _,key in ipairs(keys) do saved[key]=Tech.GetData(ix,CONST[key]) end
 local ok,err=xpcall(function()
  for _,key in ipairs(keys) do Tech.SetData(ix,CONST[key],Tech.GetData(Tech.GetTechIndex(1930),CONST[key])) end
  Tech.SetData(ix,CONST.TECH_NAME,'Unlisted renamed effect');Tech.SetData(ix,CONST.TECH_SKILLID,9999)
  reset();learn({7109});check(M:tech(7109).element==1,'arbitrary copied group retains original element')
  planned(7109,'arbitrary ID and renamed spell enters AI from effect metadata')
  Tech.SetData(ix,CONST.TECH_TARGET,317)
  check(M:tech(7109).scope=='all' and M:choose(b,row)[2]==41,'changing native target metadata automatically changes selection and command scope')
  Tech.SetData(ix,CONST.TECH_FUNCNAME,'TECH_Heal_Magic');Tech.SetData(ix,CONST.TECH_TARGET,93)
  Tech.SetData(ix,CONST.TECH_OPTION,'AR:60,');set(pets[1],'CHAR_血',550)
  check(M:tech(7109).category=='support' and planned(7109,'same arbitrary technique automatically changes to learned support after metadata change')[2]==5,'support uses allied target')
 end,debug.traceback)
 for _,key in ipairs(keys) do Tech.SetData(ix,CONST[key],saved[key]) end
 assert(ok,err);reset()
end
local function setupRound()
 reset()
 if round<=2 then learn({6100});set(pets[1],'CHAR_血',550)
 elseif round==3 then learn({6500})
 elseif round==4 then learn({6800});set(pets[1],'CHAR_血',0);set(pets[1],'对象_战死',1)
 elseif round==5 then learn({6709});status(pets[1],'战属_毒',3)
 elseif round==6 then learn({130})
 elseif round==7 then learn({530});set(Battle.GetPlayer(b,10),'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD)
 elseif round==8 then learn({1930})
 elseif round==9 then learn({2330})
 elseif round==10 then learn({804928})
 elseif round==11 then learn({5500});set(pets[1],'CHAR_血',550)
 elseif round==12 then learn({3309});Tech.SetData(Tech.GetTechIndex(3309),CONST.TECH_OPTION,'SR:100,CH:2,')
 else learn({2700}) end
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
-- Force a hit only for the native 乾坤 effect check; decision scenarios use real stats.
T:regCallback('BattleDodgeRateEvent',function(bi,a,d,rate)
 if bi==b and round==10 and a==row.proxy then return 0 end;return rate
end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b then return 0 end;return rate end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi,c1,c2,c3)
 if bi==b then
  R.effects=R.effects or {};R.effects[#R.effects+1]={round=round,actor=a,target=d,original=ori,damage=damage,command=c1,tech=c3}
  return 0
 end
 return damage
end)
T:regCallback('BattleHealCalculateEvent',function(a,d,ori,heal,bi,c1,c2,c3)
 if bi==b then R.heals=R.heals or {};R.heals[#R.heals+1]={round=round,actor=a,target=d,original=ori,heal=heal,command=c1,tech=c3,reply=get(d,'CHAR_回复')} end
 return heal
end)
T:regCallback('BattleBeforeActionEvent',function(bi,q)
 if bi==b and q==row.proxy then
  local hp={};for _,a in ipairs(allies) do hp[#hp+1]={pos=Battle.GetPos(b,a),hp=get(a,'CHAR_血'),max=get(a,'CHAR_最大血')} end
  local id=get(q,'CHAR_BattleCom3')
  R.actions[#R.actions+1]={round=round,cmd={get(q,'CHAR_BattleCom1'),get(q,'CHAR_BattleCom2'),id},hp=hp,count=row.actionCount,mp=get(q,'CHAR_魔'),nativeCost=id>=0 and Char.CalcConsumeFp(q,id) or 0}
 end
 return 0
end)
T:regCallback('BattleAfterActionEvent',function(bi,q)
 if bi==b and q==row.proxy then
  if round==11 then R.nativeBarrier=Battle.GetBattleCharacterStatus(pets[1],CONST['战属_攻反'])>0
  elseif round==12 then
   for pos=10,19 do local enemy=Battle.GetPlayer(b,pos)
    if enemy>=0 and Battle.GetBattleCharacterStatus(enemy,CONST['战属_睡'])>0 then R.nativeControl=true end
   end
  end
 end
 return 0
end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi==b then
  -- Native preparation recalculates maximum stats; build scenarios from those values.
  for _,q in ipairs(allies) do set(q,'CHAR_血',get(q,'CHAR_最大血')) end
  set(row.proxy,'CHAR_魔',get(row.proxy,'CHAR_最大魔'))
  if round==6 then set(row.proxy,'CHAR_魔',100)
  elseif round==7 then
   set(row.proxy,'CHAR_魔',100)
   local enemy=Battle.GetPlayer(b,10);set(enemy,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD)
   set(enemy,'CHAR_BattleCom2',10);set(enemy,'CHAR_BattleCom3',7400)
  end
  if round==10 then
   set(row.proxy,'CHAR_魔',100);set(row.proxy,'CHAR_命中',0)
   for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then set(q,'CHAR_闪躲',0) end end
  end
  if round<=2 then set(pets[1],'CHAR_血',math.floor(get(pets[1],'CHAR_最大血')*0.55))
  elseif round==4 then set(pets[1],'CHAR_血',0);set(pets[1],'对象_战死',1)
  elseif round==11 then set(pets[1],'CHAR_血',math.floor(get(pets[1],'CHAR_最大血')*0.55)) end
  if round==11 or round==12 then
   for pos=10,19 do local enemy=Battle.GetPlayer(b,pos);if enemy>=0 then
    set(enemy,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(enemy,'CHAR_BattleCom3',7300)
    if round==12 then set(enemy,'CHAR_抗睡',0);set(enemy,'CHAR_攻击力',10000) end
   end end
  end
  R.beforeMP=get(row.proxy,'CHAR_魔');R.beforeHP=get(pets[1],'CHAR_血')
  R.queued=R.queued or {};R.queued[#R.queued+1]={round=round,cmd=row.command,second=row.secondCommand,mainHP=R.beforeHP,mainMax=get(pets[1],'CHAR_最大血'),ownerHP=get(p,'CHAR_血'),ownerMax=get(p,'CHAR_最大血')}
  if round==2 then check(row.command[3]==6100,'healing initially queued');set(pets[1],'CHAR_血',get(pets[1],'CHAR_最大血')) end
 end
 return false
end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished then return end
 local ok,err=xpcall(function()
  if round==1 then
   check(row.command[3]==6100 and get(pets[1],'CHAR_血')>R.beforeHP,'automatic learned healing actually restores native HP')
   check(get(row.proxy,'CHAR_魔')==R.beforeMP-30,'native heal spends actual skill MP')
  elseif round==2 then
   check(row.command[3]==7300,'execution rechecks healed target and switches to attack')
   check(get(row.proxy,'CHAR_魔')==R.beforeMP,'execution recheck prevents redundant healing MP cost')
  elseif round==3 then
   local count=0;for _,q in ipairs(allies) do if Battle.GetBattleCharacterStatus(q,CONST['战属_恢复回合'])>0 then count=count+1 end end
   check(row.command[3]==6500 and count==4,'automatic area regeneration actually buffs four native allies')
   check(get(row.proxy,'CHAR_魔')==R.beforeMP-36,'native area regeneration pays correct MP')
  elseif round==4 then
   check(row.command[3]==6800 and get(pets[1],'CHAR_血')>0,'automatic resurrection actually revives native main pet')
   check(get(row.proxy,'CHAR_魔')==R.beforeMP-10,'native resurrection pays correct MP')
  elseif round==5 then
   check(row.command[3]==6709 and Battle.GetBattleCharacterStatus(pets[1],CONST['战属_毒'])==0,'automatic cleanse actually removes native poison')
   check(get(row.proxy,'CHAR_魔')==R.beforeMP-M:tech(6709).cost,'native cleanse pays correct MP')
  elseif round<=7 or round==10 then
   local id=round==10 and 804928 or (round==6 and 130 or 530)
   check(row.command[3]==id,'native physical skill actually selected: '..id)
   -- GuardBreak can deduct its preparation fee before the native before-action
   -- callback. Check execution against that boundary, keeping the fee visible.
   local executionMP,nativeCost
   for _,action in ipairs(R.actions) do if action.round==round and action.count==1 then executionMP=action.mp;nativeCost=action.nativeCost end end
   local preparation=R.beforeMP-executionMP
   R.physical_preparation=R.physical_preparation or {};R.physical_preparation[tostring(id)]=preparation
   R.physicalCosts=R.physicalCosts or {};R.physicalCosts[tostring(id)]={before=R.beforeMP,execution=executionMP,after=get(row.proxy,'CHAR_魔'),declared=M:tech(id).cost,nativeCost=nativeCost}
   check(preparation>=0 and preparation<=M:tech(id).cost,'physical preparation fee bounded by native cost: '..id)
   check(get(row.proxy,'CHAR_魔')==executionMP-nativeCost,'physical execution pays calculated native cost exactly once: '..id)
   if round==10 then
    check(row.command[1]==CONST.BATTLE_COM.BATTLE_COM_P_PARAMETER,'乾坤 uses native parameter command')
    local hit=false;for _,effect in ipairs(R.effects or {}) do
     if effect.round==round and effect.actor==row.proxy and effect.tech==id and effect.original>0 then hit=true end
    end
    check(hit,'乾坤 native skill produces actual physical damage')
   end
  elseif round==11 then
   check(row.command[3]==5500 and R.nativeBarrier,'automatic barrier actually applies native physical reflection')
   check(get(row.proxy,'CHAR_魔')==R.beforeMP-M:tech(5500).cost,'barrier spends native MP exactly once')
  elseif round==12 then
   check(row.command[3]==3309 and R.nativeControl,'automatic control actually applies matching native sleep status')
   check(get(row.proxy,'CHAR_魔')==R.beforeMP-M:tech(3309).cost,'control spends native MP exactly once')
  else
   local id=round==8 and 1930 or (round==9 and 2330 or 2700)
   check(row.command[3]==id,'native elemental spell actually selected: '..id)
   check(get(row.proxy,'CHAR_魔')==R.beforeMP-M:tech(id).cost,'elemental spell pays exact native MP: '..id)
   local hits=0;for _,effect in ipairs(R.effects or {}) do
    if effect.round==round and effect.actor==row.proxy and effect.tech==id then hits=hits+1 end
   end
   check(hits>=(round==8 and 1 or (round==9 and 2 or 3)),'elemental spell reaches correct native number of targets: '..id)
  end
  M:sync(p,row,true);check(get(row.pet,'CHAR_魔')==get(row.proxy,'CHAR_魔'),'MP sync back to real pet round '..round)
  for _,r in ipairs(rows) do check(Battle.GetEntryData(b,r.proxy,CONST.BATTLE_ENTRY_POSITION)==0,'companion remains front row') end
  check(Battle.GetEntryData(b,p,CONST.BATTLE_ENTRY_POSITION)==1,'owner remains back row')
  R.rounds=round;round=round+1;if round<=13 then setupRound() else arbitraryMetadata() end
 end,debug.traceback)
 if not ok or round>13 then finish(not ok and err or nil) end
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=60003,x=16,y=35,image=100002,name='SMART_AI_TEST'});check(p>=0,'isolated owner')
  set(p,'CHAR_等级',150);set(p,'CHAR_体力',50000);NLG.UpChar(p)
  for slot=0,4 do local pet=Char.GivePet(p,3004,100);check(pet>=0,'isolated pet '..slot);pets[slot+1]=pet
   for n=9,0,-1 do if Pet.GetSkill(pet,n)>=0 then Pet.DelSkill(pet,n) end end
   set(pet,'CHAR_血',get(pet,'CHAR_最大血'))
   if slot>1 then M:saveAI(p,pet,{mode='guard'}) end
  end
  set(pets[2],'CHAR_魔法',5000);set(pets[2],'CHAR_体力',5000);Pet.UpPet(p,pets[2])
  check(Char.SetPetDepartureState(p,0,2)==1,'main pet selected');check(M:enable(p),'automatic squad enabled')
  rows=M.active[p].rows;row=rows[1]
  M:petMenu(p,row.pet);local menu=M.menus[p]
  check(menu and #menu.options==4 and menu.options[1].mode=='attack','NPC defaults to automatic mode without skill configuration menus')
  b=Battle.PVE(p,p,nil,{1,1,1},{100,100,100},{0,0,0});check(b>=0,'isolated native battle');M:formation(b,M.active[p])
  allies={p,pets[1]};for _,r in ipairs(rows) do allies[#allies+1]=r.proxy end
  decisions();metadataDecisions();gradeDecisions();setupRound()
  T:AddInterval(100,function()
   if finished then return end
   local success,e=xpcall(function()
    if os.time()-started>45 then error('smart AI native timeout') end
    if Battle.IsWaitingCommand(p)==1 then
     set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',Battle.GetPos(b,p));set(p,'CHAR_BattleCom3',7400)
     set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3)
    end
    if Battle.IsWaitingCommand(pets[1])==1 then Battle.ActionSelect(pets[1],CONST.BATTLE_COM.BATTLE_COM_ATTACK,10,7300) end
    M:tick()
   end,debug.traceback)
   if not success then finish(e) end
  end,1)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
