-- Disposable native combat: real HP drops, damage forecasting, survival choices and main-pet control.
local R={status='RUNNING',checks={},actions={},production_database_modified=false,client_verified=false}
local M=assert(getModule('fivePet'));local T=ModuleBase:createModule('adaptiveProbe'):new();T:load()
local p,donor,b=-1,-1,-1;local bank={};local s,row,enemy;local phase=1;local done=false
local originalPool=Char.GetPoolPet
Char.GetPoolPet=function(q,slot) if q==p then return bank[slot] or -1 end;return originalPool(q,slot) end
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function set(q,k,v) return Char.SetData(q,assert(CONST[k],k),v) end
local function check(ok,name) R.checks[#R.checks+1]={name=name,pass=not not ok};assert(ok,name) end
local function finish(err)
 if done then return end;done=true
 if p>=0 then pcall(Battle.ExitBattle,p);pcall(M.disable,M,p) end
 for _,q in ipairs({p,donor}) do if q>=0 then
  for slot=0,4 do if Char.GetPet(q,slot)>=0 then pcall(Char.DelSlotPet,q,slot) end end;pcall(Char.DelDummy,q)
 end end
 Char.GetPoolPet=originalPool;R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local ok,encoded=pcall(JSON.encode,R)
 if not ok then encoded=JSON.encode({status='FAIL',error='report encoding: '..tostring(encoded),checks=R.checks}) end
 local f=assert(io.open('__REPORT__','wb'));f:write(encoded);f:close()
end
local function learn(r,ids)
 local health=get(r.proxy,'CHAR_血')
 for slot=9,0,-1 do if Pet.GetSkill(r.pet,slot)>=0 then Pet.DelSkill(r.pet,slot) end end
 for _,id in ipairs(ids) do assert(Pet.AddSkill(r.pet,id)==1) end
 set(r.pet,'CHAR_最大血',1000);set(r.pet,'CHAR_血',health);set(r.pet,'CHAR_最大魔',2000);set(r.pet,'CHAR_魔',2000)
 M:attributes(r);set(r.proxy,'CHAR_最大血',1000);set(r.proxy,'CHAR_血',health);set(r.proxy,'CHAR_最大魔',2000);set(r.proxy,'CHAR_魔',2000)
end
local function hp(q,value)
 set(q,'CHAR_最大血',1000);set(q,'CHAR_血',value)
 local r=M.proxies[q];if r then set(r.pet,'CHAR_最大血',1000);set(r.pet,'CHAR_血',value);r.dead=false end
end
local function hitHistory(q,physical,magic)
 s.damageHistory=s.damageHistory or {};s.damageHistory[q]={[enemy]={turn=Battle.GetTurn(b),physical=physical,magic=magic,physicalTech=get(enemy,'CHAR_BattleCom3'),magicTech=get(enemy,'CHAR_BattleCom3')}}
end
local function enemyCommand(id)
 local t=assert(M:tech(id));set(enemy,'CHAR_BattleCom1',t.command);set(enemy,'CHAR_BattleCom2',Battle.GetPos(b,row.proxy));set(enemy,'CHAR_BattleCom3',id)
end
local function prepare()
 for pos=0,9 do local ally=Battle.GetPlayer(b,pos);if ally>=0 and ally~=row.proxy then hitHistory(ally,0,0) end end
 hp(row.proxy,phase==1 and 1000 or (phase==2 and 500 or (phase==3 and 400 or 275)))
 enemyCommand(phase==4 and 7400 or 7300)
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b then return 0 end;return rate end)
T:regCallback('BattleDodgeRateEvent',function(bi,a,d,rate) if bi==b then return 0 end;return rate end)
T:regCallback('BattleCounterRateEvent',function(bi,a,d,rate) if bi==b then return 0 end;return rate end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi)
 if bi~=b then return damage end
 if a==enemy and d==row.proxy then
  R.damageCalls=R.damageCalls or {};R.damageCalls[#R.damageCalls+1]={phase=phase,hp=get(d,'CHAR_血'),command=get(d,'CHAR_BattleCom1'),guard=CONST.BATTLE_COM.BATTLE_COM_GUARD,original=ori,damage=damage}
  local expected=phase==1 and 30 or 250;return get(d,'CHAR_BattleCom1')==CONST.BATTLE_COM.BATTLE_COM_GUARD and expected/2 or expected
 end
 return 0
end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi==b then enemyCommand(phase==4 and 7400 or 7300) end;return false
end)
T:regCallback('BattleBeforeActionEvent',function(bi,q)
 if bi==b and s and (q==row.proxy or q==s.normal) and get(q,'CHAR_BattleCom3')>=0 then
  R.actions[#R.actions+1]={phase=phase,actor=q,tech=get(q,'CHAR_BattleCom3'),hp=get(q,'CHAR_血')}
  if q==s.normal then check(get(q,'CHAR_BattleCom3')==7400,'native main pet keeps manual guard phase '..phase) end
 end;return 0
end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or done then return end
 local ok,err=xpcall(function()
  for pos=0,9 do local ally=Battle.GetPlayer(b,pos);if ally>=0 and ally~=row.proxy then hitHistory(ally,0,0) end end
  if phase<=3 then
   local observed=s.damageHistory[row.proxy][enemy].physical
   R.observed=R.observed or {};local forecast=M:forecast(b,row.proxy);R.observed[#R.observed+1]={phase=phase,hp=get(row.proxy,'CHAR_血'),damage=observed,ending=forecast.ending,nextEnding=forecast.nextEnding}
   check(math.abs(observed-(phase==1 and 30 or 250))<0.01,'actual HP loss recorded, guard normalized phase '..phase)
  end
  R.roundDiagnostic=R.roundDiagnostic or {};local diag={phase=phase,choose=M:choose(b,row),attack=M:automaticAttack(b,row,M:skills(row.pet)),mp=get(row.proxy,'CHAR_魔'),enemyHP=get(enemy,'CHAR_血'),enemyPos=Battle.GetPos(b,enemy),forecasts={}};R.roundDiagnostic[#R.roundDiagnostic+1]=diag
   for pos=0,9 do local ally=Battle.GetPlayer(b,pos);if ally>=0 then local f=M:forecast(b,ally);diag.forecasts[#diag.forecasts+1]={pos=pos,hp=f.hp,ending=f.ending,nextEnding=f.nextEnding} end end
   if phase==1 then check(M:choose(b,row)[3]~=7400,'minor real damage permits offense next turn') end
  if phase==2 then check(M:choose(b,row)[3]==7400,'large real damage triggers survival planning before next command') end
  if phase==3 then check(M:forecast(b,row.proxy).physical==250,'defending does not erase the learned threat') end
  if phase==4 then
   local attacked=false;for _,a in ipairs(R.actions) do if a.phase==4 and a.actor==row.proxy and a.tech==1930 then attacked=true end end
   check(attacked,'offense resumes when enemy ceases threatening attacks')
   M:finish(s);check(s.damageHistory==nil and s.damagePending==nil,'damage history clears at battle end')
  end
  R.rounds=phase;phase=phase+1;if phase<=4 then prepare() end
 end,debug.traceback)
 if not ok or phase>4 then finish(not ok and err or nil) end
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  local function player(name)
   local q=Char.CreateDummy({mapType=0,floor=60003,x=16,y=35,image=100002,name=name});assert(q>=0)
   set(q,'CHAR_等级',150);set(q,'CHAR_体力',50000);NLG.UpChar(q);hp(q,1000);return q
  end
  p=player('ADAPTIVE_TEST');donor=player('ADAPTIVE_BANK');assert(getModule('gameDifficulty'):savePreference(p,1));R.fixture_difficulty=1
  for slot=0,2 do local pet=Char.GivePet(p,3004,100);assert(pet>=0);hp(pet,1000) end
  bank[0]=Char.GivePet(donor,3004,100);assert(bank[0]>=0);hp(bank[0],1000)
  assert(Char.SetPetDepartureState(p,0,2)==1);assert(M:enable(p));s=M.active[p];row=s.companions[1]
  check(row~=nil,'automatic front bank pet plus rear carried proxies created')
  local ix=Data.EnemyGetDataIndex(1);local bossFlag=Data.EnemyGetData(ix,CONST.DATA_ENEMY_BOSS_FLG)
  Data.EnemySetData(ix,CONST.DATA_ENEMY_BOSS_FLG,1)
  b=Battle.PVE(p,p,nil,{1,2,2},{100,100,100},{0,0,0});Data.EnemySetData(ix,CONST.DATA_ENEMY_BOSS_FLG,bossFlag)
  check(b>=0,'isolated native Boss combat started');M:formation(b,s);enemy=Battle.GetPlayer(b,10)
  for _,r in ipairs(M:actors(s)) do
   learn(r,{1930});set(r.pet,'CHAR_最大魔',2000);set(r.pet,'CHAR_魔',2000);M:refresh(r);hp(r.proxy,1000)
  end
  for pos=10,12 do local e=Battle.GetPlayer(b,pos)
   set(e,'CHAR_最大血',1000000);set(e,'CHAR_血',1000000);set(e,'CHAR_攻击力',0);set(e,'CHAR_防御力',0);set(e,'CHAR_闪躲',0)
   set(e,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(e,'CHAR_BattleCom3',7300)
  end
  enemyCommand(7300);Battle.SetEntryData(b,enemy,CONST.BATTLE_ENTRY_POSITION,1)
  for pos=11,12 do Battle.SetEntryData(b,Battle.GetPlayer(b,pos),CONST.BATTLE_ENTRY_POSITION,0) end
  check(next(M:bossBlockers(b,p))~=nil,'rear melee Boss screen still protected')
  check(M:choose(b,row)[3]==1930,'safe front pet may attack through screen instead of fixed defense')
  check(M:choose(b,s.rows[1])[3]==1930,'safe rear pet uses a single attack without hitting blockers')
  check(M:choose(b,row)[2]==10,'safe spell targets Boss rather than its front blocker')
  for pos=11,12 do set(Battle.GetPlayer(b,pos),'CHAR_血',0) end
  Battle.SetEntryData(b,enemy,CONST.BATTLE_ENTRY_POSITION,0)
  hp(row.proxy,50);check(M:choose(b,row)[3]==1930,'low absolute HP alone does not force defense against harmless attacks')
  hp(row.proxy,400);hitHistory(row.proxy,500)
  check(M:forecast(b,row.proxy).ending<0 and M:choose(b,row)[3]==7400,'predicted lethal turn selects defense instead of offense')
  hp(row.proxy,500);hitHistory(row.proxy,300);learn(row,{1930,809})
   check(M:choose(b,row)[3]==809,'learned stronger defense beats ordinary guard when it preserves more HP')
   hp(row.proxy,400);hitHistory(row.proxy,200)
  learn(row,{1930,6109});R.healDiagnostic={command=M:choose(b,row),mp=get(row.proxy,'CHAR_魔'),max=get(row.proxy,'CHAR_最大血'),hp=get(row.proxy,'CHAR_血')};check(M:choose(b,row)[3]==6109,'healing outperforms guard when it secures two-round survival')
  learn(row,{1930});hp(row.proxy,400);hitHistory(row.proxy,500)
  set(enemy,'CHAR_血',1);set(enemy,'CHAR_敏捷',1);set(row.proxy,'CHAR_敏捷',10000)
  check(M:choose(b,row)[3]~=7400,'reliable fast finishing attack removes lethal enemy pressure')
  -- A strong area spell hurts more in total, but a single finishing hit saves the owner.
   local threat=Battle.GetPlayer(b,11);learn(row,{1930,2330});hp(row.proxy,1000);hp(p,200)
   Battle.SetEntryData(b,p,CONST.BATTLE_ENTRY_POSITION,0)
   local attackStat=get(row.proxy,'CHAR_攻击力');set(row.proxy,'CHAR_攻击力',0);set(row.proxy,'CHAR_敏捷',10000)
   set(enemy,'CHAR_血',1000000);set(enemy,'CHAR_敏捷',1);set(threat,'CHAR_敏捷',1);set(threat,'CHAR_攻击力',0)
   set(threat,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(threat,'CHAR_BattleCom3',7300)
   local single=M:magicDamage(row.proxy,threat,M:tech(1930));local area=M:magicDamage(row.proxy,threat,M:tech(2330))
   set(threat,'CHAR_血',math.floor((single+area)/2));hitHistory(row.proxy,0);hitHistory(p,0)
   s.damageHistory[p][threat]={turn=Battle.GetTurn(b),physical=500,physicalTech=7300}
   check(M:automaticAttack(b,row,M:skills(row.pet))[3]==2330,'fixture area attack wins raw damage but cannot finish the lethal attacker')
   local rescueAttack=M:choose(b,row)
   check(rescueAttack[3]==1930 and rescueAttack[2]==11,'alternative finishing attack overrides higher area damage to save owner')
   set(threat,'CHAR_血',0);set(row.proxy,'CHAR_攻击力',attackStat);hp(p,1000);Battle.SetEntryData(b,p,CONST.BATTLE_ENTRY_POSITION,1);s.damageHistory=nil
   set(enemy,'CHAR_血',1000000);set(enemy,'CHAR_敏捷',10000);set(row.proxy,'CHAR_敏捷',10)
  set(enemy,'CHAR_敏捷',1);set(row.proxy,'CHAR_敏捷',10000)
  learn(row,{1930,730});hp(row.proxy,1000);hp(p,200);Battle.SetEntryData(b,p,CONST.BATTLE_ENTRY_POSITION,0)
  hitHistory(row.proxy,0);hitHistory(p,300)
  R.guardDiagnostic={command=M:choose(b,row),ownerHP=get(p,'CHAR_血'),ownHP=get(row.proxy,'CHAR_血'),ownMP=get(row.proxy,'CHAR_魔'),ownDex=get(row.proxy,'CHAR_敏捷'),enemyDex=get(enemy,'CHAR_敏捷'),ownerDamage=M:forecast(b,p).damage,ownerPhysical=M:forecast(b,p).remainingPhysical,ownerProtected=M:protected(b,p),guardian=Battle.GetEntryData(b,p,CONST.BATTLE_ENTRY_GUARDIAN),ownerIndex=p,ownDamage=M:forecast(b,row.proxy).damage,skills=M:skills(row.pet)}
  check(M:choose(b,row)[3]==730 and M:choose(b,row)[2]==Battle.GetPos(b,p),'healthy guardian saves predicted dying owner before HP threshold')
  hp(row.proxy,430);hitHistory(row.proxy,0)
   check(M:choose(b,row)[3]~=730,'bodyguard defense penalty cannot be mistaken for damage reduction')
   hp(row.proxy,200);hitHistory(row.proxy,250)
  check(M:choose(b,row)[3]~=730,'dying guardian never takes suicidal transferred damage')
  hp(p,1000);hp(row.proxy,1000);Battle.SetEntryData(b,p,CONST.BATTLE_ENTRY_POSITION,1)
  enemyCommand(7300);hitHistory(row.proxy,0);enemyCommand(400)
   check(M:forecast(b,row.proxy).physical>0,'changing physical skill invalidates the weaker observed sample')
   enemyCommand(1930);hitHistory(row.proxy,300)
  check(M:forecast(b,row.proxy).magic>0,'switching to magic does not reuse a physical zero sample')
  hp(row.proxy,500);hitHistory(row.proxy,nil,300);learn(row,{1930,1009})
   check(M:choose(b,row)[3]==1009,'magic threat selects learned magic defense rather than ordinary physical guard')
   hp(row.proxy,1000);hp(p,100);hitHistory(p,nil,150);learn(row,{1930,6109})
   set(enemy,'CHAR_敏捷',10000);set(row.proxy,'CHAR_敏捷',1)
   check(M:choose(b,row)[3]~=6109,'healing too late cannot be credited as rescuing a lethal first hit')
   set(enemy,'CHAR_敏捷',1);set(row.proxy,'CHAR_敏捷',10000)
  check(M:choose(b,row)[3]==6109 and M:choose(b,row)[2]==Battle.GetPos(b,p),'healer anticipates lethal ranged damage to rear owner')
  hp(p,1000);hp(s.normal,1000);learn(row,{1930});s.damageHistory=nil;s.damagePending=nil
  set(enemy,'CHAR_敏捷',10000);set(row.proxy,'CHAR_敏捷',10)
  set(enemy,'CHAR_最大魔',2000);set(enemy,'CHAR_魔',2000);prepare()
  local started=os.time()
  T:AddInterval(100,function()
   if done then return end
   local yes,e=xpcall(function()
    if os.time()-started>35 then error('adaptive native test timeout') end
    if Battle.IsWaitingCommand(p)==1 then
     set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',0);set(p,'CHAR_BattleCom3',7400)
     set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3)
    end
    if Battle.IsWaitingCommand(s.normal)==1 then
     M:tick();check(Battle.IsWaitingCommand(s.normal)==1,'AI waits for manual main-pet selection phase '..phase)
     assert(Battle.ActionSelect(s.normal,CONST.BATTLE_COM.BATTLE_COM_GUARD,Battle.GetPos(b,s.normal),7400)==0)
    end
    M:tick()
   end,debug.traceback)
   if not yes then finish(e) end
  end,1)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
