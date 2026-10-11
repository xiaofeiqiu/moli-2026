-- Isolated native skill permissions, learning, equipment, and tutor menu checks.
local R={status='RUNNING',checks={},npcs={},production_accounts_used=false}
local D=dofile('lua/Modules/skillTrainingData.lua')
local costs={};for _,s in ipairs(D.players) do costs[s.id]=s.cost end
local p=-1
local shown
local original=NLG.ShowWindowTalked
NLG.ShowWindowTalked=function(q,n,kind,buttons,seq,data,...)
 if q==p then shown=data end
 return original(q,n,kind,buttons,seq,data,...)
end
local function set(k,v) Char.SetData(p,assert(CONST[k],k),v) end
local function check(ok,name)
 R.checks[#R.checks+1]={name=name,pass=not not ok};assert(ok,name)
end
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
Cron.AddInterval(1500,function()
 local ok,err=xpcall(function()
  local L=assert(getModule('skillLibrary'));local M=assert(getModule('skillTraining'))
  p=Char.CreateDummy({mapType=0,floor=1000,x=153,y=123,image=100002,name='MAGIC_SKILLS_TEST'})
  check(p>=0,'independent dummy character')
  set('CHAR_职业',181);set('CHAR_职类ID',180);set('CHAR_职阶',0)
  set('CHAR_等级',200);set('CHAR_技能栏',15)
  local learned={};local valid,invalid,boss=0,0,0
  for _,s in ipairs(D.players) do
   if s.source=='pet' then
   elseif s.unavailable then invalid=invalid+1 else
    valid=valid+1
    if s.source=='boss' then boss=boss+1 end
    local slot=Char.AddSkill(p,s.id,0,0)
    check(slot>=0 and Char.GetSkillID(p,slot)==s.id,'native add skill '..s.id)
    check(Char.DelSkill(p,s.id,0)>=0,'native remove skill '..s.id)
   end
  end
  R.learnable_records=valid;R.unavailable_records=invalid;R.boss_skills=boss
  check(boss==139,'all 139 BOSS player variants included')
  for job=181,187 do
   set('CHAR_职业',job);set('CHAR_职阶',job-181)
   for _,s in ipairs(D.players) do
    local ix=Skill.GetSkillIndex(s.id)
    check(ix>=0 and Skill.GetMaxSkillLevelOfJob(ix,job)==(s.source=='pet' and 0 or 30),'native permission '..job..'/'..s.id)
    check(L:allowed(p,s.id)==not not (not s.unavailable and s.source~='pet'),'archive permission '..job..'/'..s.id)
   end
   for n,cat in pairs(M.categories) do if cat.kind=='boss' or cat.family==180 then
    Char.Warp(p,0,Char.GetData(n,CONST.CHAR_地图),Char.GetData(n,CONST.CHAR_X),Char.GetData(n,CONST.CHAR_Y)+1)
    local list=M:list(p,cat.id,'all','player')
    for page=1,math.ceil(#list/(cat.kind=='boss' and 10 or 5)) do
     shown=nil;M:show(n,p,'player',page,'all')
     check(shown and not shown:find('职业受限',1,true),'unrestricted menu '..job..'/'..cat.id..'/'..page)
    end
    if job==181 then
     R.npcs[#R.npcs+1]={name=cat.name}
     local chosen
     for _,s in ipairs(list) do if not s.unavailable then chosen=s;break end end
     if chosen then
      Char.AddGold(p,chosen.cost+10000)
      local gold=Char.GetGold(p);local success,msg=M:learnPlayer(n,p,chosen.id)
      check(success,'learn category '..cat.id..'/'..tostring(msg))
      check(Char.GetGold(p)==gold-chosen.cost,'exact category fee '..cat.id)
      learned[#learned+1]=chosen.id
     end
    end
   end
   end
   if job==181 then
    for _,id in ipairs({196,300,301,302,303}) do
     Char.AddGold(p,60000)
     local success,msg=L:learn(p,id)
     check(success,'learn screenshot skill '..id..'/'..tostring(msg));learned[#learned+1]=id
    end
   end
   check(L:loadout(p,learned),'equip all categories and screenshot skills at job '..job)
   check(#L:active(p)==#learned,'native loadout size at job '..job)
   check(L:loadout(p,{}),'clear native loadout at job '..job)
  end
  local snapshot=L:read(p);L.cache[p]=nil;Char.SetExtData(p,'SkillLibraryV1',nil)
  check(equal(L:read(p),snapshot),'durable SQL archive reread')
  -- The character remains subject to skill-specific caps and normal fees.
  set('CHAR_职业',181);set('CHAR_职阶',0)
  check(L:loadout(p,{300}),'equip authored quest skill')
  L:gainExperience(p,300,100000000)
  local max
  for _,s in ipairs(D.players) do if s.id==300 then max=s.max_level end end
  check(Char.GetSkillLevel(p,Char.HaveSkill(p,300))<=max,'quest keeps authored maximum')
  check(L:loadout(p,{}),'clear quest skill')
  local gold=Char.GetGold(p)
  check(not L:learn(p,300) and Char.GetGold(p)==gold,'duplicate learning charges nothing')
  -- Exclusive profession skills must also work beyond the shared archive.
  local J=assert(getModule('cg71JobSkills'))
  local jobs=dofile('lua/Modules/cg71JobSkillsData.lua')
  local advanced
  for _,n in ipairs(J.npcList) do
   if Char.GetData(n,CONST.CHAR_名字)=='职业进阶导师' then advanced=n end
  end
  check(advanced~=nil,'advanced profession tutor exists')
  Char.Warp(p,0,Char.GetData(advanced,CONST.CHAR_地图),Char.GetData(advanced,CONST.CHAR_X),Char.GetData(advanced,CONST.CHAR_Y)+1)
  local reached={}
  for page=1,6 do
   shown=nil;J:menu(advanced,p,nil,page)
   local session=J.sessions[p]
   check(session.kind=='all_professions' and #session.actions<=8,'all professions page '..page)
   local normalized=shown:gsub('\\n','\n'):gsub('\r\n','\n')
   local lines={};for line in (normalized..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
   local headers=assert(tonumber(lines[1]))
   for i,action in ipairs(session.actions) do
    if action.id then
     local name=Skill.GetData(Skill.GetSkillIndex(action.id),CONST.SKILL_NAME)
     local cost=Skill.GetData(Skill.GetSkillIndex(action.id),CONST.SKILL_COST)
     check(lines[headers+1+i]==name..'（'..cost..'金）','visible advanced row '..action.id)
     reached[action.id]=true
    elseif action.page then
     _G['cg71JobSkills_npc_'..advanced..'_WindowTalkedEvent'](advanced,p,7101,0,tostring(i))
     check(J.sessions[p].kind=='all_professions','native advanced paging callback')
     J:menu(advanced,p,nil,page)
    end
   end
  end
  for _,id in ipairs(J:eligible(p)) do check(reached[id],'advanced skill reachable '..id) end
  check(#J:eligible(p)==27,'all 27 profession advancement skills offered')
  set('CHAR_等级',1)
  for _,s in ipairs(jobs.skills) do
   local archive=L:read(p)
   if not archive.skills[tostring(s.id)] then
    Char.AddGold(p,20000);local before=Char.GetGold(p)
    local success,msg=J:learn(p,s.id)
    check(success,'cross-profession teacher learns '..s.id..'/'..tostring(msg))
    check(Char.GetGold(p)==before-costs[s.id],'teacher uses archive fee '..s.id)
   end
   check(L:read(p).skills[tostring(s.id)]~=nil,'exclusive skill stored '..s.id)
  end
  check(L:loadout(p,{2100}),'equip foreign profession manufacturing')
  Recipe.RemoveRecipe(p,6200);J:giveRecipes(p,2100)
  check(Recipe.HasRecipe(p,6200)==1,'foreign profession recipe is granted')
  check(L:loadout(p,{}),'clear manufacturing skill')
  set('CHAR_等级',200)
  set('CHAR_体力',100000);set('CHAR_魔法',100000);NLG.UpChar(p)
  local battle=Battle.PVE(p,p,nil,{1},{1},{0})
  check(battle>=0,'native battle for exclusive effects')
  set('CHAR_最大魔',10000);set('CHAR_魔',10000)
  local target
  for pos=10,19 do if Battle.GetPlayer(battle,pos)>=0 then target=pos;break end end
  for _,s in ipairs(jobs.skills) do if s.kind=='buff' then
   local slot=Char.AddSkill(p,s.id,0,0);check(slot>=0,'equip exclusive effect '..s.id)
   Char.SetSkillLevel(p,slot,5,0)
   set('CHAR_BattleCom3',s.techs[5])
   local hostile=s.effect=='curse' or s.effect=='nonlethal'
   set('CHAR_BattleCom2',hostile and target or Battle.GetPos(battle,p))
   if s.effect=='nonlethal' then
    local q=Battle.GetPlayer(battle,target);local before=Char.GetData(q,CONST.CHAR_血)
    J:luaSkill(battle,p,function() end,function() end)
    check(Char.GetData(q,CONST.CHAR_血)<before,'foreign nonlethal skill deals damage')
   else
    J:luaSkill(battle,p,function() end,function() end)
    local q=hostile and Battle.GetPlayer(battle,target) or p
    check(J:buff(battle,q,s.effect)==5,'foreign profession effect active '..s.id)
   end
   Char.DelSkill(p,s.id,0)
  end end
  Battle.ExitBattle(p)
  gold=Char.GetGold(p)
  set('CHAR_职业',1);set('CHAR_职类ID',0)
  check(not L:allowed(p,300),'unemployed still restricted')
  check(not L:learn(p,301) and Char.GetGold(p)==gold,'other-job learning rejected without charge')
  set('CHAR_职业',11);set('CHAR_职类ID',10)
  check(not L:allowed(p,300),'swordsman still restricted')
  check(not L:loadout(p,{300}),'other-job equip still restricted')
 end,debug.traceback)
 NLG.ShowWindowTalked=original
 if p>=0 then
  if Char.GetBattleIndex(p)>=0 then pcall(Battle.ExitBattle,p) end
  pcall(Char.DelDummy,p);p=-1
 end
 R.status=ok and 'PASS' or 'FAIL';R.error=not ok and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end,0)
