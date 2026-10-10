local R={status='RUNNING',checks={},messages={},tiers={},damage_events={},enemy_turns={}}
local M,p,member,liveBattle
local rawEnemies,preDamage={},{}
local actors={}
local PRE=ModuleBase:createModule('difficultyPreProbe'):new();PRE:load()
local POST=ModuleBase:createModule('difficultyPostProbe'):new();POST:load()
local oldMessage=NLG.SystemMessage
local began=os.time()
local function get(q,k) return Char.GetData(q,CONST[k]) end
local function set(q,k,v) return Char.SetData(q,CONST[k],v) end
local function round(n) return math.floor(n+0.5) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function snapshot(q) return {hp=get(q,'CHAR_最大血'),defense=get(q,'CHAR_防御力'),agility=get(q,'CHAR_敏捷')} end
local function write()
 local f=assert(io.open('__OUTPUT__/command_native.json','wb'));f:write(JSON.encode(R));f:close()
end
local function leave(q)
 if q and q>=0 then
  if Char.GetBattleIndex(q)>=0 then pcall(Battle.ExitBattle,q) end
  set(q,'CHAR_BattleIndex',-1);set(q,'CHAR_BattleMode',0)
 end
end
local function finish(err)
 if R.status~='RUNNING' then return end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or ''
 NLG.SystemMessage=oldMessage
 for _,q in ipairs(actors) do pcall(Char.UnsetLoopEvent,q);leave(q);pcall(Char.LeaveParty,q);pcall(Char.DelDummy,q) end
 write()
end
local function command(q,msg) check(TalkEvent(q,msg,0,0,0)==0,'native command consumed '..msg) end
local function enemy(b)
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 and Char.IsEnemy(q) then return q end end
 error('No native enemy')
end
local function initialize(b)
 local q=enemy(b)
 if not M.battles[b] then rawEnemies[b]={[q]=snapshot(q)} end
 BeforeBattleTurnStartEvent(b)
 return q
end
local function dummy(reg)
 local q=Char.CreateDummy({mapType=0,floor=1000,x=150+reg,y=111,image=100002,name='DIFFICULTY_COMMAND_'..reg})
 check(q>=0,'disposable character '..reg);actors[#actors+1]=q
 set(q,'CHAR_账号','DIFF_CMD_PERSIST');set(q,'对象_RegistNumber',reg);set(q,'CHAR_等级',100)
 set(q,'CHAR_体力',100000);set(q,'CHAR_魔法',100000);Char.UpCharStatus(q)
 set(q,'CHAR_血',get(q,'CHAR_最大血'));set(q,'CHAR_魔',get(q,'CHAR_最大魔'))
 return q
end
NLG.SystemMessage=function(q,text,...) R.messages[#R.messages+1]=text;return oldMessage(q,text,...) end
PRE:regCallback('BattleStartEvent',OrderedCallback(function(b)
 rawEnemies[b]={}
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 and Char.IsEnemy(q) then rawEnemies[b][q]=snapshot(q) end end
end,100))
PRE:regCallback('DamageCalculateEvent',OrderedCallback(function(a,d,ori,damage,b)
 if b==liveBattle and Char.IsEnemy(a) and damage>0 then preDamage[a..':'..d]=damage end
 return damage
end,100))
local success,error=xpcall(function()
 M=assert(loadModule('gameDifficulty'))
 check(M.configs~=nil and #M.tiers==5,'five difficulty tiers loaded')
 check(#(M.npcList or {})==0,'command module creates no NPC')
 check(getModule('fivePet') and getModule('skillLibrary') and getModule('knightHybridGear'),'existing gameplay modules coexist')
 check(SQL.QueryEx('DELETE FROM hook_charaext WHERE cdKey=? AND sKey=?','DIFF_CMD_PERSIST','GameDifficultyV1').status==0,'reset isolated preference fixtures')
 p=dummy(0);member=dummy(1)
 check(M:preference(p)==2,'initial preference preserves hard challenge')
 check(TalkEvent(p,'ordinary chat',0,0,0)==1 and TalkEvent(p,'/difficultyx 4',0,0,0)==1,'unrelated chat untouched')
 command(p,'/difficulty');command(p,'/difficulty help')
 for tier=1,5 do
  local messageStart=#R.messages
  command(p,'/difficulty '..tier);check(M:preference(p)==tier,'tier saved '..tier)
  local expected={
   '1 正常：怪物生命 ×1，伤害 ×1，防御 ×1，敏捷 ×1。',
   '2 困难：怪物生命 ×1.3，伤害 ×1.2，防御 ×1.15，敏捷 ×1.1。',
   '3 极难：怪物生命 ×1.8，伤害 ×1.5，防御 ×1.3，敏捷 ×1.15。',
   '4 地狱：怪物生命 ×2.5，伤害 ×2，防御 ×1.5，敏捷 ×1.2。',
   '5 炼狱：怪物生命 ×4，伤害 ×3，防御 ×2，敏捷 ×1.3。'}
  local printed=false;for i=messageStart+1,#R.messages do if R.messages[i]==expected[tier] then printed=true end end
  check(printed,'confirmation prints selected attribute multipliers '..tier)
  local control=snapshot(p);local pet=Char.GivePet(p,3004,1);check(pet>=0,'pet fixture '..tier)
  local petControl=snapshot(pet)
  local b=Battle.PVE(p,p,nil,{1},{60},{0});check(b>=0,'native PvE '..tier)
  local q=initialize(b);local base=assert(rawEnemies[b][q]);local t=M.tiers[tier]
  local actual=snapshot(q)
  check(actual.hp==round(base.hp*t.hp) and actual.defense==round(base.defense*t.defense) and actual.agility==round(base.agility*t.agility),'native enemy tier scaling '..tier)
  local playerAfter=snapshot(p)
  check(playerAfter.hp==control.hp and playerAfter.defense==control.defense and playerAfter.agility==control.agility,'player stats untouched '..tier)
  local petAfter=snapshot(pet)
  check(petAfter.hp==petControl.hp and petAfter.defense==petControl.defense and petAfter.agility==petControl.agility,'pet stats untouched '..tier)
  M:scan(b);local again=snapshot(q)
  check(again.hp==actual.hp and again.defense==actual.defense and again.agility==actual.agility,'repeated scan does not multiply twice '..tier)
  local physical=DamageCalculateEvent(q,p,100,100,b,CONST.BATTLE_COM.BATTLE_COM_ATTACK,0,0,0,0,0,0,0)
  local magic=DamageCalculateEvent(q,p,100,100,b,CONST.BATTLE_COM.BATTLE_COM_M_EARTHQUAKE,0,0,0,0,0,0,0)
  check(physical==round(100*t.damage) and magic==round(100*t.damage),'physical and magic damage dispatch '..tier)
  check(DamageCalculateEvent(p,q,100,100,b,CONST.BATTLE_COM.BATTLE_COM_ATTACK,0,0,0,0,0,0,0)==100,'player outgoing damage untouched '..tier)
  local woundedHP=actual.hp-100
  set(q,'CHAR_血',woundedHP);Char.UpCharStatus(q)
  local recalculated=snapshot(q)
  check(recalculated.hp==actual.hp and recalculated.defense==actual.defense and recalculated.agility==actual.agility,'native status recalculation preserves difficulty '..tier)
  check(get(q,'CHAR_血')==woundedHP,'native status recalculation preserves health lost '..tier)
  command(p,'/difficulty 1');check(M:preference(p)==tier and M.battles[b].tier==tier,'in-combat difficulty change rejected '..tier)
  R.tiers[#R.tiers+1]={tier=tier,name=t.name,before=base,after=actual,physical_damage=physical,magic_damage=magic}
  leave(p);Char.DelSlotPet(p,0)
 end
 for _,arg in ipairs({'0','6','-1','2.5','2 extra','01','normal'}) do command(p,'/difficulty '..arg);check(M:preference(p)==5,'invalid input retains tier '..arg) end
 command(member,'/difficulty 1')
 check(Char.JoinParty(member,p,true)==0,'native party join')
 check(M:leader(member)==p,'party member resolves leader')
 local b=Battle.PVE(p,p,nil,{1},{60},{0});check(b>=0,'native party PvE')
 initialize(b)
 check(M.battles[b].leader==p and M.battles[b].tier==5,'party follows leader despite member tier 1')
 leave(p);leave(member);Char.LeaveParty(member);Char.LeaveParty(p)
 b=Battle.PVP(p,member);check(b>=0,'native PvP created')
 check(M.battles[b]==nil,'PvP is excluded')
 leave(p);leave(member)
 b=Battle.PVE(p,p,nil,{1},{1},{0});check(b>=0,'native capture target')
 local q=initialize(b);local base=rawEnemies[b][q];local boosted=snapshot(q)
 check(SealEvent(p,q,-100)==-100 and get(q,'CHAR_最大血')==boosted.hp,'failed capture keeps enemy difficulty')
 check(SealEvent(p,q,1)==1,'successful capture result preserved')
 local restored=snapshot(q)
 check(restored.hp==base.hp and restored.defense==base.defense and restored.agility==base.agility,'capture removes temporary monster stat boosts')
 leave(p)
 reloadModule('gameDifficulty');M=assert(getModule('gameDifficulty'))
 check(M:preference(p)==5 and M:preference(member)==1,'separate characters persist across module reload')
 local saved=SQL.QueryEx('SELECT val FROM hook_charaext WHERE cdKey=? AND regNo=? AND sKey=?','DIFF_CMD_PERSIST',0,'GameDifficultyV1')
 check(saved.status==0 and saved.rows[1] and JSON.decode(saved.rows[1].val).tier==5,'difficulty is stored in native SQLite')
 -- Previous immediate-exit fixtures still await an engine tick. A fresh actor
 -- keeps their delayed exit cleanup from clearing the live witness's battle.
 p=dummy(0);check(M:preference(p)==5,'fresh live witness loads saved highest tier')
 liveBattle=Battle.PVE(p,p,nil,{1},{60},{0});check(liveBattle>=0,'live native combat')
 local liveEnemy=enemy(liveBattle)
 set(liveEnemy,'CHAR_命中',100);set(p,'CHAR_闪躲',0)
 local maxHP=M.battles[liveBattle] and get(liveEnemy,'CHAR_最大血') or round(get(liveEnemy,'CHAR_最大血')*4)
 R.lifecycle={};R.native_apis={}
 for _,event in ipairs({'BattleStartEvent','BeforeBattleTurnStartEvent','BeforeBattleTurnEvent','BattleOverEvent','BattleExitEvent'}) do
  R.native_apis[event]=type(NL['Reg'..event])
  POST:regCallback(event,OrderedCallback(function(a,b)
   local bi=event=='BattleExitEvent' and b or a
   if bi==liveBattle then R.lifecycle[#R.lifecycle+1]={event=event,battle=bi,state_tier=M.battles[bi] and M.battles[bi].tier or -1,player_battle=Char.GetBattleIndex(p),player_hp=get(p,'CHAR_血'),roster0=Battle.GetPlayer(bi,0)} end
  end,-100))
 end
 POST:regCallback('DamageCalculateEvent',OrderedCallback(function(a,d,ori,damage,bi)
  if bi==liveBattle and Char.IsEnemy(a) and damage>0 and preDamage[a..':'..d] then
   R.damage_events[#R.damage_events+1]={before=preDamage[a..':'..d],after=damage}
   check(damage==round(preDamage[a..':'..d]*3),'live enemy damage uses highest multiplier')
  end
  return damage
 end,-100))
 POST:regCallback('AfterBattleTurnEvent',function(bi)
  if bi~=liveBattle or R.status~='RUNNING' then return end
  local ok,err=xpcall(function()
   R.turns=(R.turns or 0)+1
   R.enemy_turns[#R.enemy_turns+1]={max_hp=get(liveEnemy,'CHAR_最大血'),hp=get(liveEnemy,'CHAR_血'),expected_max_hp=maxHP}
   check(M.battles[bi] and M.battles[bi].tier==5,'native lifecycle initializes highest tier '..R.turns)
   check(get(liveEnemy,'CHAR_最大血')==maxHP,'monster HP survives actual turn '..R.turns..' (actual '..tostring(get(liveEnemy,'CHAR_最大血'))..', expected '..maxHP..')')
   if R.turns==1 then
    reloadModule('gameDifficulty');M=assert(getModule('gameDifficulty'))
    check(M.battles[bi] and get(liveEnemy,'CHAR_最大血')==maxHP,'reload retains active battle without double scaling')
   end
   if #R.damage_events>0 and R.turns>=2 then finish()
   elseif R.turns>=5 then error('No positive native enemy hit in five turns') end
  end,debug.traceback)
  if not ok then finish(err) end
 end)
 local loop=POST:regCallback(function()
  if R.status~='RUNNING' then return end
  if os.time()-began>35 then finish('live combat timeout');return end
  if Char.GetBattleIndex(p)==liveBattle then
   set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',Battle.GetPos(liveBattle,p));set(p,'CHAR_BattleCom3',7400)
   set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_Battle2Com2',Battle.GetPos(liveBattle,p));set(p,'CHAR_Battle2Com3',7400)
   set(p,'CHAR_BattleMode',3)
  end
 end)
 Char.SetLoopEvent(nil,loop,p,200)
 write()
end,debug.traceback)
if not success then finish(error) end
