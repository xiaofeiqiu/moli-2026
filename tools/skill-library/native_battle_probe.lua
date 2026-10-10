-- Real native turns exercise both player and copied BOSS handlers at level 30.
local M=getModule('skillLibrary');local old=getModule('cg71JobSkills')
local D=dofile('lua/Modules/skillLibraryData.lua')
local specs={};for _,s in ipairs(D.skills) do specs[s.id]=s end
local path='../../../../docs/skill_library/native_battle_result.json'
local cases={};local results={};local live=0;local began=os.time()
local function set(p,k,v) Char.SetData(p,CONST[k],v) end
local function get(p,k) return Char.GetData(p,CONST[k]) end
local function allies(b)
  local n=0;for pos=0,9 do if Battle.GetPlayer(b,pos)>=0 then n=n+1 end end;return n
end
local function write(status,err)
  local f=assert(io.open(path,'w'));f:write(JSON.encode({result=status,error=err or '',cases=results,pack_sha256='__PACK_SHA256__',client_verified=false,elapsed=os.time()-began}));f:close()
end
local function finish(t)
  if t.done then return end;t.done=true
  local lv=Char.GetSkillLevel(t.p,Char.HaveSkill(t.p,t.skill))
  local success=t.kind=='buff' and t.buff==30 or (t.kind~='buff' and t.damage>0)
  if t.kind=='progression' or t.kind=='boss_progression' then success=lv==30 and (t.kind=='progression' and t.buff==29 or t.kind=='boss_progression' and t.damage>0) end
  if t.kind=='summon' then success=t.summoned>0 end
  if t.kind=='death' then success=t.target_hp<1000000 and get(t.p,'CHAR_魔')<10000 end
  results[#results+1]={kind=t.kind,skill=t.skill,damage=t.damage,buff=t.buff or 0,experience_callbacks=t.xp,starting_level=t.starting_level,turns=t.turn_count or 0,level=lv,summoned=t.summoned or 0,magic_points=get(t.p,'CHAR_魔'),result=success and 'PASS' or 'FAIL'}
  Char.UnsetLoopEvent(t.p);if Char.GetBattleIndex(t.p)>=0 then Battle.ExitBattle(t.p) end
  for slot=0,4 do if Char.GetPet(t.p,slot)>=0 then Char.DelSlotPet(t.p,slot) end end
  Char.DelDummy(t.p);live=live-1
  if live==0 then local ok=true;for _,r in ipairs(results) do if r.result~='PASS' then ok=false end end;write(ok and 'PASS' or 'FAIL') else write('RUNNING') end
end
M:regCallback('DamageCalculateEvent',function(p,q,ori,dmg,b)
  local t=cases[p];if t and t.battle==b and dmg>0 then t.damage=t.damage+dmg end
  return dmg
end)
M:regCallback('AfterBattleTurnEvent',function(b)
  for _,t in pairs(cases) do if not t.done and t.battle==b then
    if t.kind=='buff' or t.kind=='progression' then t.buff=old:buff(b,t.p,'magic') end
    if t.kind=='summon' then local a=M.auras[b] and M.auras[b][t.p];t.summoned=a and a.summon and a.summon.level or 0 end
    if t.kind=='death' then local q=Battle.GetPlayer(b,t.target);t.target_hp=q>=0 and get(q,'CHAR_血') or 0 end
    t.turn_count=(t.turn_count or 0)+1
    -- Dummy battles may advance a guard turn before their command loop runs.
    -- Require an executed, MP-consuming action; allow native attacks to miss.
    t.turn=(get(t.p,'CHAR_魔')<10000 and (t.damage>0 or t.buff or t.summoned or t.kind=='death')) or t.turn_count>=5
  end end
end)
for _,entry in ipairs({{'magic',19,30},{'buff',2204,30},{'boss',__EARTH_SKILL__,30},{'progression',2204,29},{'boss_progression',__EARTH_SKILL__,29},{'summon',__SUMMON_SKILL__,30},{'death',__DEATH_SKILL__,30}}) do
  local p=Char.CreateDummy({mapType=0,floor=1000,x=153,y=111,image=100002,name='LIBRARY_BATTLE_TEST'})
  assert(p>=0)
  set(p,'CHAR_职业',37);set(p,'CHAR_职类ID',30);set(p,'CHAR_职阶',6);set(p,'CHAR_等级',200);set(p,'CHAR_技能栏',15)
  set(p,'CHAR_体力',100000);set(p,'CHAR_魔法',100000);NLG.UpChar(p)
  local slot=Char.AddSkill(p,entry[2],0,0);assert(slot>=0);Char.SetSkillLevel(p,slot,entry[3],0)
  if entry[3]==29 then
    local group=Skill.GetData(Skill.GetSkillIndex(entry[2]),CONST.SKILL_EXPTABLE)
    Char.SetSkillExp(p,slot,D.experience[group][30]-10,0)
  end
  local b=Battle.PVE(p,p,nil,{1},{1},{0});assert(b>=0)
  set(p,'CHAR_最大血',10000);set(p,'CHAR_血',10000);set(p,'CHAR_最大魔',10000);set(p,'CHAR_魔',10000)
  local target=-1;for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then target=pos;set(q,'CHAR_最大血',1000000);set(q,'CHAR_血',1000000);break end end
  assert(target>=0)
  local t={kind=entry[1],p=p,battle=b,skill=entry[2],starting_level=entry[3],tech=specs[entry[2]].techs[entry[3]],damage=0,xp=0,target=target,before_allies=allies(b)}
  cases[p]=t;live=live+1
  local function command(ch)
    local isBuff=t.kind=='buff' or t.kind=='progression';local isBoss=t.kind=='boss' or t.kind=='boss_progression'
    local command=isBuff and CONST.BATTLE_COM.BATTLE_COM_LUA or (isBoss and CONST.BATTLE_COM.BATTLE_COM_M_EARTHQUAKE or CONST.BATTLE_COM.BATTLE_COM_P_MAGIC)
    if t.kind=='summon' or t.kind=='death' then command=CONST.BATTLE_COM.BATTLE_COM_LUA end
    set(ch,'CHAR_BattleCom1',command)
    set(ch,'CHAR_BattleCom2',(isBuff or t.kind=='summon') and Battle.GetPos(b,ch) or t.target)
    set(ch,'CHAR_BattleCom3',t.tech)
    set(ch,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(ch,'CHAR_Battle2Com2',Battle.GetPos(b,ch));set(ch,'CHAR_Battle2Com3',7400)
    set(ch,'CHAR_BattleMode',3)
  end
  command(p)
  local loop=M:regCallback(function(ch)
    if t.done then return end
    if t.turn or os.time()-began>25 then finish(t);return end
    command(ch)
  end)
  Char.SetLoopEvent(nil,loop,p,500)
end
write('RUNNING')
