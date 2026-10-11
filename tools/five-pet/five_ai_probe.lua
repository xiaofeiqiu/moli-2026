-- Real native battle with configured companions; owner and main pet stay manual.
local R={status='RUNNING',checks={},npcs={},actions={},damage={},production_accounts_used=false}
local M=getModule('fivePet');local T=ModuleBase:createModule('fiveAiProbe'):new();T:load()
local p,b=-1,-1;local pets={};local rows={};local finished=false;local started=os.time()
local rounds=0
local enemyData,originalTactics
local nativeDisable=M.disable
M.disable=function(self,q,reason) R.disabled=R.disabled or {};R.disabled[#R.disabled+1]={q=q,reason=reason,turn=b>=0 and Battle.GetTurn(b) or -1};return nativeDisable(self,q,reason) end
T:regCallback('BattleExitEvent',function(q,bi,kind) if bi==b then R.exits=R.exits or {};R.exits[#R.exits+1]={q=q,kind=kind,turn=Battle.GetTurn(bi)} end end)
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
 if enemyData then Data.EnemySetData(enemyData,CONST.DATA_ENEMY_TACTICSOPTION,originalTactics) end
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b and Char.IsEnemy(q) then return 0 end;return rate end)
T:regCallback('BattleDodgeRateEvent',function(bi,a,d,rate) if bi==b then return 0 end;return rate end)
T:regCallback('BattleActionEvent',function(q,c1,c2,c3,n)
 if M.proxies[q] then R.actions[#R.actions+1]={char=q,command=c1,target=c2,tech=c3} end
end)
T:regCallback('BattleBeforeActionEvent',function(bi,q,extra)
 if bi==b then
  R.trace=R.trace or {};local guardian={}
  for i=0,9 do local a=Battle.GetPlayer(b,i);if a>=0 then guardian[tostring(i)]={Battle.GetEntryData(b,a,CONST.BATTLE_ENTRY_GUARDIAN),get(a,'CHAR_血')} end end
  R.trace[#R.trace+1]={actor=q,command=get(q,'CHAR_BattleCom1'),target=get(q,'CHAR_BattleCom2'),guardian=guardian}
 end
 return 0
end)
T:regCallback('BattleAfterActionEvent',function(bi,q,extra)
 if bi==b and q==rows[2].proxy then
  R.after_guard=R.after_guard or {};R.after_guard[#R.after_guard+1]={target=get(q,'CHAR_BattleCom2'),guardian=Battle.GetEntryData(b,pets[1],CONST.BATTLE_ENTRY_GUARDIAN)}
 end
 return 0
end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi,c1,c2,c3)
 if bi==b then R.damage[#R.damage+1]={attacker=a,defender=d,tech=c3};return a==Battle.GetPlayer(b,10) and 5 or 0 end
 return damage
end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi==b then
  local e=Battle.GetPlayer(b,10)
  set(e,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(e,'CHAR_BattleCom2',Battle.GetPos(b,pets[1]));set(e,'CHAR_BattleCom3',7300)
  R.before_turns=R.before_turns or {};R.before_turns[#R.before_turns+1]={turn=Battle.GetTurn(bi),enemy=e,hp=e>=0 and get(e,'CHAR_血') or -1}
  R.guard_before_mp=get(rows[2].proxy,'CHAR_魔')
  R.spell_before_mp=get(rows[3].proxy,'CHAR_魔')
 end
 return false
end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished then return end
 local ok,err=xpcall(function()
  R.after_turns=R.after_turns or {};local e=Battle.GetPlayer(bi,10);R.after_turns[#R.after_turns+1]={turn=Battle.GetTurn(bi),enemy=e,hp=e>=0 and get(e,'CHAR_血') or -1}
  rounds=rounds+1;R.rounds=rounds;R.turns=R.turns or {};R.turns[#R.turns+1]=Battle.GetTurn(bi)
  local g=rows[2].command;local c=rows[3].command
  R.guard_command=g;R.guard_mp=get(rows[2].proxy,'CHAR_魔')
  check(g and g[1]==CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD and g[3]==730 and R.guard_mp==R.guard_before_mp-10,'bodyguard command executes and consumes native MP')
  if rounds==1 then
   local attacked=false
   for _,d in ipairs(R.damage) do if d.attacker==rows[3].proxy and d.tech==7300 then attacked=true end end
   check(c and c[1]==CONST.BATTLE_COM.BATTLE_COM_ATTACK and c[2]==10 and attacked,'BOSS preference executes native normal attack at common target')
  else
   local cast=false
   for _,d in ipairs(R.damage) do if d.attacker==rows[3].proxy and d.tech==1930 then cast=true end end
   R.spell_state={command=c,before=R.spell_before_mp,after=get(rows[3].proxy,'CHAR_魔'),cost=M:tech(1930).cost}
   check(c and c[3]==1930 and cast and get(rows[3].proxy,'CHAR_魔')==R.spell_before_mp-M:tech(1930).cost,'selected spell executes natively after BOSS preference is disabled')
  end
  local intercepted=false
  for _,d in ipairs(R.damage) do if d.attacker==Battle.GetPlayer(b,10) and d.defender==rows[2].proxy then intercepted=true end end
  check(intercepted,'bodyguard intercepts native attack on lowest-HP ally')
  R.damage={}
  if rounds==1 then
   M:saveAI(p,pets[3],{mode='skill',tech=1930,target='weak',threshold=30,bossCombo=false})
  end
 end,debug.traceback)
 if not ok or rounds>=3 then finish(not ok and err or nil) end
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=60003,x=16,y=35,image=100002,name='FIVE_AI_TEST'})
  check(p>=0,'isolated owner');set(p,'CHAR_等级',50);set(p,'CHAR_体力',50000);NLG.UpChar(p)
  for slot=0,4 do local q=Char.GivePet(p,3004,1);assert(q>=0);pets[slot+1]=q
   for i=9,0,-1 do if Pet.GetSkill(q,i)>=0 then Pet.DelSkill(q,i) end end
   set(q,'CHAR_血',get(q,'CHAR_最大血'));set(q,'CHAR_最大魔',1000);set(q,'CHAR_魔',1000)
  end
  check(Char.SetPetDepartureState(p,0,2)==1,'main pet selected')
  R.native_types={player=Char.GetData(p,3),pet=Char.GetData(pets[2],3),pet_constant=CONST['对象类型_宠']}
  check(Pet.AddSkill(pets[2],730)==1 and Pet.AddSkill(pets[3],1930)==1,'native bodyguard and spell learned')
  set(pets[2],'CHAR_敏捷',10000)
  M:petMenu(p,pets[2]);local menu=M.menus[p]
  check(#menu.options==9,'pet configuration includes bodyguard fallback skill option')
  M:answer(M.npc,p,menu.seq,0,'2');check(M.menus[p].kind=='skills','skill-priority mode opens explicit skill picker when unconfigured')
  menu=M.menus[p];check(menu.options[1].tech==730,'native bodyguard visible in skill picker')
  M:answer(M.npc,p,menu.seq,0,'1');check(M:ai(p,pets[2]).tech==730 and M:ai(p,pets[2]).mode=='skill','chosen skill activates and persists priority mode')
  M:petMenu(p,pets[3]);menu=M.menus[p];M:answer(M.npc,p,menu.seq,0,'7')
  check(M:ai(p,pets[3]).bossCombo,'BOSS preference switch persists')
  M:saveAI(p,pets[3],{mode='skill',tech=1930,target='random',threshold=30,bossCombo=true})
  M.configs[p]=nil;check(M:ai(p,pets[3]).bossCombo and M:ai(p,pets[2]).tech==730,'configuration reread retains preference and chosen skill')
  local ix=Data.EnemyGetDataIndex(1);local flag=Data.EnemyGetData(ix,CONST.DATA_ENEMY_BOSS_FLG)
  enemyData=ix;originalTactics=Data.EnemyGetData(ix,CONST.DATA_ENEMY_TACTICSOPTION)
  Data.EnemySetData(ix,CONST.DATA_ENEMY_TACTICSOPTION,'at:100;1;1')
  Data.EnemySetData(ix,CONST.DATA_ENEMY_BOSS_FLG,1)
  check(M:enable(p),'automatic companions enabled')
  for _,r in ipairs(M.active[p].rows) do for i,q in ipairs(pets) do if r.pet==q then rows[i]=r end end end
  b=Battle.PVE(p,p,nil,{1},{100},{0});Data.EnemySetData(ix,CONST.DATA_ENEMY_BOSS_FLG,flag)
  check(b>=0 and Battle.IsBossBattle(b)==1,'actual BOSS battle from isolated enemy flag')
  set(pets[2],'CHAR_敏捷',10000)
  M:formation(b,M.active[p])
  check(Battle.GetPos(b,p)==0 and Battle.GetPos(b,pets[1])==5 and Battle.GetEntryData(b,p,CONST.BATTLE_ENTRY_POSITION)==1 and Battle.GetEntryData(b,pets[1],CONST.BATTLE_ENTRY_POSITION)==0,'owner in rear slot 0 and main pet in front slot 5')
  for i=2,5 do check(Battle.GetPos(b,rows[i].proxy)==4+i and Battle.GetEntryData(b,rows[i].proxy,CONST.BATTLE_ENTRY_POSITION)==0 and Battle.GetPlayer(b,4+i)==rows[i].proxy and Battle.GetPlayer(b,i-1)<0,'automatic pet uses native front battle ID and leaves no rear battle ID '..i) end
  local allies={p,pets[1]};for i=2,5 do allies[#allies+1]=rows[i].proxy end
  local maxhp={};for _,q in ipairs(allies) do maxhp[q]=get(q,'CHAR_最大血');set(q,'CHAR_最大血',1000);set(q,'CHAR_血',1000) end
  local function protects(q,label)
   local c=M:choose(b,rows[2]);check(c[1]==CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD and c[2]==Battle.GetPos(b,q),label)
  end
  local function attacks(label) check(M:choose(b,rows[2])[1]==CONST.BATTLE_COM.BATTLE_COM_ATTACK,label) end
  attacks('healthy team uses normal attack')
  for _,q in ipairs(allies) do set(q,'CHAR_血',500) end
  attacks('exactly 50 percent does not trigger bodyguard')
  set(rows[2].proxy,'CHAR_血',1);attacks('only guardian below half cannot protect itself');set(rows[2].proxy,'CHAR_血',1000)
  set(pets[1],'CHAR_血',499);protects(pets[1],'just below half triggers bodyguard on main pet')
  set(rows[4].proxy,'CHAR_血',100);protects(rows[4].proxy,'healthy owner yields to lowest current HP pet')
  set(rows[5].proxy,'CHAR_最大血',4000);set(rows[5].proxy,'CHAR_血',200)
  protects(rows[4].proxy,'pet target compares current HP rather than HP ratio')
  set(p,'CHAR_血',499);protects(p,'low owner has priority over pet with less HP')
  set(p,'CHAR_血',0);protects(rows[4].proxy,'dead owner is excluded')
  set(rows[4].proxy,'CHAR_血',0);protects(rows[5].proxy,'dead lowest HP pet is excluded')
  set(rows[5].proxy,'CHAR_血',499);protects(pets[1],'equal pet HP resolves by battle position')
  set(pets[1],'CHAR_血',0);set(rows[5].proxy,'CHAR_血',500);set(rows[5].proxy,'CHAR_最大血',1000)
  attacks('no living eligible ally falls back to normal attack')
  for _,q in ipairs(allies) do set(q,'CHAR_最大血',maxhp[q]) end
  set(p,'CHAR_血',40);for i=2,5 do set(rows[i].proxy,'CHAR_血',100+i) end;set(pets[1],'CHAR_血',90)
  local cmd=M:choose(b,rows[2]);check(cmd[1]==CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD and cmd[2]==Battle.GetPos(b,p) and cmd[3]==730,'bodyguard prioritizes low owner, excluding self')
  set(rows[4].proxy,'CHAR_血',30);check(M:choose(b,rows[2])[2]==Battle.GetPos(b,p),'bodyguard keeps low owner priority when pet HP changes')
  set(rows[4].proxy,'CHAR_血',0);check(M:choose(b,rows[2])[2]==Battle.GetPos(b,p),'bodyguard excludes dead ally');set(rows[4].proxy,'CHAR_血',104)
  set(rows[2].proxy,'CHAR_魔',0);check(M:choose(b,rows[2])[1]==CONST.BATTLE_COM.BATTLE_COM_ATTACK,'no MP uses normal attack');set(rows[2].proxy,'CHAR_魔',1000)
  set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set(p,'CHAR_BattleCom2',10)
  cmd=M:choose(b,rows[3]);check(cmd[1]==CONST.BATTLE_COM.BATTLE_COM_ATTACK and cmd[2]==10,'BOSS preference uses common normal-attack target')
  M:saveAI(p,pets[3],{mode='skill',tech=1930,target='weak',threshold=30,bossCombo=false})
  check(M:choose(b,rows[3])[3]==1930,'turning off BOSS preference restores selected skill')
  M:saveAI(p,pets[3],{mode='skill',tech=1930,target='weak',threshold=30,bossCombo=true})
  local originalBoss=Battle.IsBossBattle;Battle.IsBossBattle=function() return 0 end
  local ordinary=M:choose(b,rows[3]);Battle.IsBossBattle=originalBoss
  check(ordinary[3]==1930,'ordinary battle retains selected spell')
  check(M.proxies[p]==nil and M.proxies[pets[1]]==nil,'owner and main pet are outside AI control')
  set(p,'CHAR_血',get(p,'CHAR_最大血'));set(pets[1],'CHAR_血',20)
  T:AddInterval(100,function()
   if finished then return end
   local ok,e=xpcall(function()
    if os.time()-started>35 then error('native AI battle timeout') end
    set(pets[2],'CHAR_敏捷',10000)
    if Battle.IsWaitingCommand(p)==1 then
     set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',Battle.GetPos(b,p));set(p,'CHAR_BattleCom3',7400)
     set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3)
    end
    if Battle.IsWaitingCommand(pets[1])==1 then Battle.ActionSelect(pets[1],CONST.BATTLE_COM.BATTLE_COM_ATTACK,10,7300) end
    local c1=get(p,'CHAR_BattleCom1');local c2=get(p,'CHAR_BattleCom2');local main=get(pets[1],'CHAR_BattleCom1')
    M:tick();check(get(p,'CHAR_BattleCom1')==c1 and get(p,'CHAR_BattleCom2')==c2 and get(pets[1],'CHAR_BattleCom1')==main,'AI preserves manually submitted owner and main-pet commands')
   end,debug.traceback)
   if not ok then finish(e) end
  end,1)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
