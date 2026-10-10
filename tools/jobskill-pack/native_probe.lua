local output=assert(io.open('../../../../docs/jobskill_pack/native_result.json','w'))
local detail=assert(io.open('../../../../docs/jobskill_pack/native_detail.tsv','w'))
detail:write('kind\tid\tresult\n')
local owner=-1
local counts={jobs=0,skills=0,techs=0,items=0,recipes=0,buffs=0,checks=0}
local D=dofile('lua/Modules/cg71JobSkillsData.lua')
local M=getModule('cg71JobSkills')
local function c(name) local value=CONST[name];assert(value,name);return value end
local function set(p,name,v) Char.SetData(p,c(name),v) end
local function get(p,name) return Char.GetData(p,c(name)) end
local function check(x,msg) assert(x,msg); counts.checks=counts.checks+1 end
local function dummy(f)
  local p=Char.CreateDummy({mapType=0,floor=1000,x=150,y=111,image=100002,name='CG71_JOB_VALIDATOR'})
  check(p>=0 and Char.IsDummy(p),'dummy creation')
  set(p,'CHAR_职业',f+7);set(p,'CHAR_职类ID',f);set(p,'CHAR_职阶',6)
  set(p,'CHAR_等级',200);set(p,'CHAR_声望',1000000)
  Char.AddGold(p,1000000)
  NLG.UpChar(p)
  return p
end
local function del(p)
  if Char.GetBattleIndex(p)>=0 then Battle.ExitBattle(p) end
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then Char.DelSlotPet(p,slot) end end
  check(Char.DelDummy(p)==0,'dummy cleanup')
end
local function add(p,id,lv)
  local slot=Char.HaveSkill(p,id)
  if slot<0 then slot=Char.AddSkill(p,id,0,0) end
  check(slot>=0,'add skill '..id..' result '..tostring(slot))
  local result=Char.SetSkillLevel(p,slot,lv,0)
  -- This engine returns -1 when setting exactly the profession cap, despite
  -- successfully updating the level; verify the native stored state.
  check(Char.GetSkillLevel(p,slot)==lv,'set skill level '..id..' result '..tostring(result)..' slot='..slot..' actual='..Char.GetSkillLevel(p,slot)..' job='..get(p,'CHAR_职业')..' cap='..Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(id),get(p,'CHAR_职业')))
  return slot
end
local ok,why=pcall(function()
  assert(M and #M.npcList==5,'module/NPC load')
  for n=1,5 do
    local walk=Map.IsWalkable(0,1000,n==5 and 153 or 149+(n-1)*2,n==5 and 109 or 106)
    check(walk==1 or walk==true,'NPC accessible approach '..n..' value='..tostring(walk)..' type='..type(walk))
  end
  check(NL.RegBattleLuaSkillEvent~=nil,'native Lua skill support')
  for _,j in ipairs(D.jobs) do
    for rank=1,7 do
      local id=j.family+rank;local ix=Data.GetJobIndex(id)
      check(ix>=0 and Data.GetJobData(ix,CONST.JOBS_ID)==id,'job '..id)
      check(Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(j.skill),id)==j.caps[rank],'job cap '..id)
      counts.jobs=counts.jobs+1;detail:write('job\t'..id..'\tPASS\n')
    end
    check(Data.GetJobAncestryIndex(j.family)>=0,'job ancestry')
  end
  for _,s in ipairs(D.skills) do
    local ix=Skill.GetSkillIndex(s.id)
    check(ix>=0 and Skill.GetData(ix,CONST.SKILL_NAME)==s.name,'skill definition '..s.id)
    for lv,tid in ipairs(s.techs) do
      local tx=Tech.GetTechIndex(tid)
      check(tx>=0 and Tech.GetData(tx,CONST.TECH_SKILLID)==s.id and Tech.GetData(tx,CONST.TECH_NECESSARYLV)==lv,'tech '..tid..' index='..tostring(tx)..' skill='..tostring(Tech.GetData(tx,CONST.TECH_SKILLID))..' lv='..tostring(Tech.GetData(tx,CONST.TECH_NECESSARYLV)))
      counts.techs=counts.techs+1
    end
    owner=dummy(s.families[1])
    if s.kind=='trial' then set(owner,'CHAR_职业',1);set(owner,'CHAR_职类ID',0);set(owner,'CHAR_职阶',0) end
    local before=Char.GetGold(owner)
    if s.prerequisite and s.prerequisite>0 then add(owner,M:prerequisite(owner,s),s.prerequisite_level) end
    local learned,reason=M:learn(owner,s.id)
    check(learned,'learn '..s.id..' '..tostring(reason))
    check(Char.GetGold(owner)<=before,'learning gold')
    local repeatOk=M:learn(owner,s.id);check(not repeatOk,'duplicate learning')
    add(owner,s.id,s.max_level)
    M:giveRecipes(owner,s.id)
    for _,r in ipairs(D.recipes) do if r.skill==s.id then check(Recipe.HasRecipe(owner,r.id)==1,'recipe unlock '..r.id);counts.recipes=counts.recipes+1 end end
    if s.kind=='buff' then
      local battle=Battle.PVE(owner,owner,nil,{1},{1},{0});check(battle>=0,'battle creation')
      set(owner,'CHAR_血',1000);set(owner,'CHAR_魔',1000)
      local target=owner
      if s.effect=='curse' or s.effect=='nonlethal' then
        for pos=10,19 do local q=Battle.GetPlayer(battle,pos);if q>=0 then target=q;break end end
      end
      set(target,'CHAR_血',1000)
      set(owner,'CHAR_BattleCom2',Battle.GetPos(battle,target))
      set(owner,'CHAR_BattleCom3',s.techs[s.max_level])
      local calls=0
      M:luaSkill(battle,owner,function() calls=calls+1 end,function() calls=calls+1 end,function() end)
      check(calls>=2,'Lua skill emission '..s.id)
      if s.effect=='nonlethal' then check(get(target,'CHAR_血')>=1 and get(target,'CHAR_血')<1000,'nonlethal damage')
      else check(M:buff(battle,target,s.effect)==5,'buff activation '..s.id) end
      if s.effect=='physical' then
        check(M:damage(owner,target,100,100,battle,0,0,0,0,0,0,1)==125,'physical formula')
      elseif s.effect=='magic' then check(M:damage(owner,target,100,100,battle,0,0,0,0,0,0,CONST.DamageFlags.Magic)==140,'magic formula')
      elseif s.effect=='healing' then check(M:heal(owner,target,100,100,battle)==150,'healing formula')
      elseif s.effect=='barrier' then check(M:damage(owner,target,100,100,battle,0,0,0,0,0,0,1)==75,'barrier formula') end
      Battle.SetTurn(battle,Battle.GetTurn(battle)+3)
      if s.effect~='nonlethal' then check(M:buff(battle,target,s.effect)==0,'buff expiry '..s.id) end
      counts.buffs=counts.buffs+1
      Battle.ExitBattle(owner)
    end
    detail:write('skill\t'..s.id..'\tPASS\n');counts.skills=counts.skills+1
    del(owner);owner=-1
  end
  for _,s in ipairs(D.extended_skills) do
    for n,id in ipairs(s.techs) do
      local ix=Tech.GetTechIndex(id)
      check(ix>=0 and Tech.GetData(ix,CONST.TECH_NECESSARYLV)==n+10,'extended tech '..id)
      counts.techs=counts.techs+1
    end
    -- Verify native experience progression to fifteen on a permitted profession.
    local jid=nil
    for _,family in ipairs({10,20,30,40,60,70,80,130,140,150,160,420,430,440}) do
      if Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(s.id),family+7)==15 then jid=family;break end
    end
    check(jid~=nil,'extended profession cap '..s.id)
    owner=dummy(jid);local slot=add(owner,s.id,13)
    Char.SetSkillExp(owner,slot,20000000,0)
    add(owner,s.id,15)
    check(Char.GetSkillExp(owner,slot)>0,'finite high-level experience '..s.id)
    del(owner);owner=-1;detail:write('extended\t'..s.id..'\tPASS\n')
  end
  for _,i in ipairs(D.items) do
    local ix=Data.ItemsetGetIndex(i.id);check(ix>=0,'item definition '..i.id)
    local obj=Item.MakeItem(i.id);check(obj>=0,'item creation '..i.id)
    check(Item.GetData(obj,c('道具_ID'))==i.id,'native item id '..i.id..' const='..tostring(c('道具_ID'))..' got='..tostring(Item.GetData(obj,c('道具_ID'))))
    check(Item.GetData(obj,c('道具_类型'))==i.type,'native item type '..i.id)
    Item.UnlinkItem(obj);counts.items=counts.items+1;detail:write('item\t'..i.id..'\tPASS\n')
  end
  owner=dummy(200);add(owner,2226,5)
  local refined=Item.MakeItem(700030)
  local before=Item.GetData(refined,c('道具_攻击'))
  M:merge(owner,200,10,refined,-1)
  check(Item.GetData(refined,c('道具_攻击'))>before,'craft refinement modifier')
  check(Char.GetSkillExp(owner,Char.HaveSkill(owner,2226))>0,'passive refinement experience')
  Item.UnlinkItem(refined);del(owner);owner=-1
  check(M:repair(0,2221,5,0,-1,0)==0,'repair rank check is preserved')
  for typ=56,60 do check(Item.GetPetEquipPlace(typ,typ<=57 and 0 or typ-57)==1,'pet equipment mask '..typ) end
  -- Wrong profession and insufficient funds are rejected before learning.
  owner=dummy(40);local gold=Char.GetGold(owner)
  check(not M:learn(owner,2100),'wrong profession rejected')
  check(Char.GetGold(owner)==gold,'rejection preserves gold')
  del(owner);owner=dummy(1020);Char.AddGold(owner,-Char.GetGold(owner))
  check(not M:learn(owner,2100),'insufficient funds rejected')
  del(owner);owner=-1
  for _,j in ipairs(D.jobs) do
    owner=dummy(j.family)
    set(owner,'CHAR_职业',1);set(owner,'CHAR_职类ID',0);set(owner,'CHAR_职阶',0)
    check(not M:join(owner,j.family),'missing trial rejected')
    check(M:learn(owner,2105),'learn trial for joining')
    check(Char.GiveItem(owner,700075,1)>=0,'give trial product')
    local joined,reason=M:join(owner,j.family)
    check(joined,'join '..j.family..' '..tostring(reason))
    check(get(owner,'CHAR_职业')==j.family+1 and get(owner,'CHAR_职类ID')==j.family,'joined job state')
    check(Char.ItemNum(owner,700075)==0,'trial item consumed')
    check(Char.HaveSkill(owner,2105)<0,'trial skill removed after joining')
    check(M:learn(owner,j.skill),'learn profession crafting')
    for rank=1,6 do
      add(owner,j.skill,j.caps[rank])
      local promoted,why=M:promote(owner,j.family)
      check(promoted,'promotion '..j.family..' rank '..rank..' '..tostring(why))
      check(get(owner,'CHAR_职业')==j.family+rank+1 and get(owner,'CHAR_职阶')==rank,'promotion state')
    end
    check(not M:promote(owner,j.family),'max promotion rejected')
    del(owner);owner=-1
  end
end)
if owner>=0 then pcall(del,owner) end
detail:close()
output:write(JSON.encode({result=ok and 'PASS' or 'FAIL',error=ok and '' or tostring(why),counts=counts,isolated=true,client_verified=false}))
output:close()
print('[CG71_JOB_PROBE] '..(ok and 'PASS' or 'FAIL '..tostring(why)))
