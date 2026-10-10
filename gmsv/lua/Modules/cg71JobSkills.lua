-- Taiwan 7.1 names and profession scope; local custom balance and entry hub.
-- Runtime source is encoded as GBK by build_pack.py. No player SQL writes.
local M = ModuleBase:createModule('cg71JobSkills')
local D = dofile('lua/Modules/cg71JobSkillsData.lua')
local specs, techs = {}, {}
for _, s in ipairs(D.skills) do
  specs[s.id] = s
  for lv, id in ipairs(s.techs) do techs[id] = {spec=s,level=lv} end
end
local function C(name)
  local value=CONST[name]; assert(value,'Missing native constant: '..name); return value
end
local function get(p, name) return Char.GetData(p, C(name)) end
local function set(p, name, v) return Char.SetData(p, C(name), v) end
local function contains(xs, n) for _, v in ipairs(xs) do if v==n then return true end end return false end
local function job(p) return get(p,'CHAR_职业') end
local function family(p) return math.floor(job(p)/10)*10 end
local function level(p, id)
  if p<0 or not Char.IsPlayer(p) then return 0 end
  local s = specs[id]
  if s and not contains(s.families,family(p)) then return 0 end
  local slot = Char.HaveSkill(p,id)
  if slot<0 then return 0 end
  local lv = Char.GetSkillLevel(p,slot)
  local cap = Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(id),job(p))
  return math.max(0,math.min(lv,cap))
end
local function tell(p,msg) NLG.SystemMessage(p,msg) end

function M:prerequisite(p,s)
  local f=family(p)
  if s.effect=='gather' then return ({[450]=225,[460]=226,[470]=227,[1010]=2000})[f] end
  if s.effect=='packing' then return f==350 and 215 or 216 end
  if s.effect=='refine' then
    if f>=1020 then return 2100+(f-1020)/10 end
    return 200+(f-200)/10
  end
  return s.prerequisite
end

function M:giveRecipes(p,id)
  local lv=level(p,id)
  for _,r in ipairs(D.recipes) do
    if r.skill==id and r.level<=lv and Recipe.HasRecipe(p,r.id)~=1 then Recipe.GiveRecipe(p,r.id) end
  end
end

function M:learn(p,id)
  local s=specs[id]
  if not s then return false,'技能不存在。' end
  if Char.GetBattleIndex(p)>=0 then return false,'请先结束战斗。' end
  if Char.HaveSkill(p,id)>=0 then self:giveRecipes(p,id); return false,'你已经学会这个技能。' end
  if s.kind~='trial' and not contains(s.families,family(p)) then return false,'当前职业不能学习这个专属技能。' end
  local cap=Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(id),job(p))
  if cap<=0 then return false,'当前职阶尚未开放此技能。' end
  if get(p,'CHAR_等级')<s.min_character_level then return false,'需要人物等级 '..s.min_character_level..'。' end
  if s.prerequisite and s.prerequisite>0 then
    local req=self:prerequisite(p,s)
    if level(p,req)<s.prerequisite_level then return false,'前置技能 '..req..' 需要 '..s.prerequisite_level..' 级。' end
  end
  local cost=s.kind=='trial' and 0 or (id<2200 and 1000 or 10000)
  if Char.GetGold(p)<cost then return false,'金币不足，需要 '..cost..'。' end
  local slot=Char.AddSkill(p,id,0,1)
  if slot<0 then return false,'技能栏不足，学习失败，未扣金币。' end
  Char.AddGold(p,-cost); self:giveRecipes(p,id); NLG.UpChar(p)
  return true,'已经学会 '..s.name..'。'
end

function M:join(p,f)
  if Char.GetBattleIndex(p)>=0 then return false,'请先结束战斗。' end
  if job(p)~=1 then return false,'就职限游民；现有职业请按原流程离职。' end
  if Char.GetGold(p)<5000 then return false,'就职需要 5000 金币。' end
  local trial=Char.HaveSkill(p,2105)
  if trial<0 then return false,'请先学习宠装锻造体验，并制作一件练习宠饰。' end
  if Char.ItemNum(p,700075)<1 then return false,'请提交一件练习宠饰R1。' end
  if Char.DelItem(p,700075,1)~=1 then return false,'提交练习作品失败。' end
  Char.AddGold(p,-5000)
  set(p,'CHAR_职类ID',f); set(p,'CHAR_职业',f+1); set(p,'CHAR_职阶',0)
  Char.DelSkill(p,2105,1)
  NLG.UpChar(p)
  return true,'就职成功；可以学习本职业制造及宠物饰品制作。'
end

function M:promote(p,f)
  if Char.GetBattleIndex(p)>=0 or family(p)~=f then return false,'需要本职业且处于非战斗状态。' end
  local rank=job(p)%10
  if rank>=7 then return false,'已经达到最高职阶。' end
  local s=2100+(f-1020)/10
  local caps={4,6,8,10,12,15}
  local minlv={20,40,60,80,100,140}
  local fame={500,2500,10000,20000,40000,60000}
  local price={5000,10000,20000,40000,80000,120000}
  if level(p,s)<caps[rank] or get(p,'CHAR_等级')<minlv[rank] or get(p,'CHAR_声望')<fame[rank] then
    return false,'晋阶需要制造技能 '..caps[rank]..'、人物等级 '..minlv[rank]..'、声望 '..fame[rank]..'。'
  end
  if Char.GetGold(p)<price[rank] then return false,'晋阶需要 '..price[rank]..' 金币。' end
  Char.AddGold(p,-price[rank]); set(p,'CHAR_职业',f+rank+1); set(p,'CHAR_职阶',rank); NLG.UpChar(p)
  return true,'晋阶完成，制造上限已更新。'
end

function M:eligible(p)
  local ids={}
  for _,s in ipairs(D.skills) do
    if s.id>=2200 and contains(s.families,family(p)) then ids[#ids+1]=s.id end
  end
  return ids
end

function M:near(npc,p)
  return get(p,'CHAR_地图')==get(npc,'CHAR_地图') and get(p,'CHAR_地图类型')==get(npc,'CHAR_地图类型')
     and math.abs(get(p,'CHAR_X')-get(npc,'CHAR_X'))<=3 and math.abs(get(p,'CHAR_Y')-get(npc,'CHAR_Y'))<=3
     and Char.GetBattleIndex(p)<0
end

function M:menu(npc,p,f)
  if not self:near(npc,p) then return end
  local options
  if f then options={'就职（提交练习宠饰，5000金）','晋阶','学习本职制造（1000金）','学习宠物饰品制作（1000金）','学习宠装锻造体验（免费）','补领已达等级的配方','查看规则'}
  else
    options={}; for _,id in ipairs(self:eligible(p)) do options[#options+1]=specs[id].name..'（10000金）' end
    if #options==0 then tell(p,'本职业没有新增进阶技能。'); return end
  end
  self.sessions[p]={npc=npc,family=f,ids=f and nil or self:eligible(p),expires=os.time()+60}
  NLG.ShowWindowTalked(p,npc,2,2,7101,self:NPC_buildSelectionText(f and '宠装制造公会' or '职业进阶导师',options))
end

function M:answer(npc,p,seq,select,data)
  local a=self.sessions[p]; self.sessions[p]=nil
  if not a or a.npc~=npc or seq~=7101 or a.expires<os.time() or not self:near(npc,p) then return end
  local choice=tonumber(data)
  if not choice then return end
  local ok,msg=false,'无效选择。'
  if not a.family then local id=a.ids[choice]; if id then ok,msg=self:learn(p,id) end
  elseif choice==1 then ok,msg=self:join(p,a.family)
  elseif choice==2 then ok,msg=self:promote(p,a.family)
  elseif choice==3 then ok,msg=self:learn(p,2100+(a.family-1020)/10)
  elseif choice==4 then ok,msg=self:learn(p,2104)
  elseif choice==5 then ok,msg=self:learn(p,2105)
  elseif choice==6 then
    for _,s in ipairs(D.skills) do if s.kind=='craft' or s.kind=='trial' then self:giveRecipes(p,s.id) end end
    msg='已补领当前技能等级可用的配方。'
  elseif choice==7 then msg='专属制造及饰品最高15级，进阶技能最高5级。这里采用本服定制试炼和晋阶规则。' end
  tell(p,msg)
end

function M:state(b,p)
  self.effects[b]=self.effects[b] or {}; self.effects[b][p]=self.effects[b][p] or {}
  return self.effects[b][p]
end
function M:buff(b,p,key)
  local rows=self.effects[b] and self.effects[b][p]
  local e=rows and rows[key]
  if e and e.expires>Battle.GetTurn(b) then return e.level end
  return 0
end
function M:addBuff(b,p,key,lv)
  self:state(b,p)[key]={level=lv,expires=Battle.GetTurn(b)+3}
end

function M:luaSkill(b,p,skl,act,msg)
  local use=techs[get(p,'CHAR_BattleCom3')]
  if not use or use.spec.kind~='buff' then return end
  local s,lv=use.spec,use.level
  if level(p,s.id)<lv then return end
  local key=s.effect
  local targets={p}
  if key=='curse' or key=='barrier' or key=='adrenaline' or key=='nonlethal' then
    local target=Battle.GetPlayer(b,get(p,'CHAR_BattleCom2'))
    if target<0 or get(target,'CHAR_血')<=0 then return end
    local same=get(target,'CHAR_战斗Side')==get(p,'CHAR_战斗Side')
    local hostile=key=='curse' or key=='nonlethal'
    if (hostile and same) or (not hostile and not same) then return end
    targets={target}
  elseif key=='party_attack' then
    targets={}; local pos=Battle.GetPos(b,p); local first=pos<10 and 0 or 10
    for n=first,first+9 do local target=Battle.GetPlayer(b,n); if target>=0 and get(target,'CHAR_血')>0 then targets[#targets+1]=target end end
  end
  local fp=Tech.GetData(Tech.GetTechIndex(get(p,'CHAR_BattleCom3')),CONST.TECH_FORCEPOINT)
  if get(p,'CHAR_魔')<fp then return end
  set(p,'CHAR_魔',get(p,'CHAR_魔')-fp);self:train(p,s.id,30);NLG.UpChar(p)
  if key=='nonlethal' then
    local target=targets[1]
    local damage=math.max(0,math.min(math.floor(math.max(1,get(p,'CHAR_攻击力')-get(target,'CHAR_防御力')*0.5)*(0.5+lv*0.1)),get(target,'CHAR_血')-1))
    set(target,'CHAR_血',get(target,'CHAR_血')-damage)
    skl(309); act(CONST.TechLua_ACT_DAMAGE,Battle.GetPos(b,target),1,damage)
    return
  end
  skl(809)
  for _,target in ipairs(targets) do
    self:addBuff(b,target,key,lv)
    act(CONST.TechLua_ACT_EFFECT,Battle.GetPos(b,target),0)
  end
  if msg then msg(Battle.GetPos(b,p),s.name..'：持续3回合') end
end

function M:damage(p,q,ori,dmg,b,c1,c2,c3,dc1,dc2,dc3,flag)
  if dmg<=0 or flag==CONST.DamageFlags.Miss or flag==CONST.DamageFlags.Dodge then return dmg end
  local magic=flag==CONST.DamageFlags.Magic
  local increase=self:buff(b,p,'party_attack')*0.03+self:buff(b,p,'adrenaline')*0.04
  if magic then increase=increase+self:buff(b,p,'magic')*0.08
  else increase=increase+self:buff(b,p,'physical')*0.05+self:buff(b,p,'reckless')*0.10 end
  local use=techs[c3]
  if c3>=200200 and c3<=200209 then increase=increase+self:buff(b,p,'bomb')*0.08 end
  local value=math.max(1,math.floor(dmg*(1+increase)*(1+self:buff(b,q,'curse')*0.06+self:buff(b,q,'reckless')*0.04)*(1-math.min(0.90,self:buff(b,q,'barrier')*0.05))))
  if use and use.spec.effect=='nonlethal' then return math.max(0,math.min(value,get(q,'CHAR_血')-1)) end
  return value
end
function M:heal(p,q,ori,dmg,b)
  return math.max(0,math.floor(dmg*(1+self:buff(b,p,'healing')*0.10)*(1-self:buff(b,q,'curse')*0.05)))
end
function M:dodge(b,p,q,rate)
  return math.max(0,math.min(100,rate+self:buff(b,q,'dodge')*4-self:buff(b,p,'accuracy')*5))
end
function M:critical(p,q,rate)
  local b=Char.GetBattleIndex(p)
  return math.max(0,math.min(100,rate+self:buff(b,p,'critical')*5))
end

function M:train(p,id,xp)
  local lv=level(p,id); if lv<=0 then return end
  local slot=Char.HaveSkill(p,id)
  -- The library applies explicit level transitions using native thresholds.
  local library=getModule('skillLibrary')
  if library then library:gainExperience(p,id,xp) else Char.SetSkillExp(p,slot,Char.GetSkillExp(p,slot)+xp,0) end
end
function M:merge(p,sid,slv,item,jewel)
  self:giveRecipes(p,sid)
  local typ=Item.GetData(item,C('道具_类型'))
  local refine=level(p,2226)
  if refine>0 and (typ<=14 or (typ>=56 and typ<=60)) then
    local field=(typ<=6 or typ==58) and C('道具_攻击') or C('道具_防御')
    local old=Item.GetData(item,field)
    Item.SetData(item,field,old+math.max(1,math.floor(math.max(old,10)*refine*0.02)))
    self:train(p,2226,40)
  end
  local packing=level(p,2225)
  if packing>0 and (sid==215 or sid==216) then
    if NLG.Rand(1,100)<=packing*10 then
      local id=Item.GetData(item,C('道具_ID'))
      if Char.GetEmptyItemSlot(p)>=0 then Char.GiveItem(p,id,1) end
    end
    self:train(p,2225,40)
  end
end
function M:gather(p,sid,slv,item)
  local lv=level(p,2224)
  if lv>0 and (sid==225 or sid==226 or sid==227 or sid==2000) then
    self:train(p,2224,20)
    if (not item or item<=0) and NLG.Rand(1,100)<=lv*10 then
      return ({[225]=10000,[226]=12000,[227]=9600,[2000]=40738})[sid]
    end
  end
  return item
end
function M:identify(p,sid,slv,item,prob,success)
  local lv=level(p,2223)
  if success==1 and prob>=0 and lv>0 then
    self:train(p,2223,40)
    if NLG.Rand(1,100)<=lv*10 then Char.AddGold(p,lv*5); NLG.UpChar(p) end
  end
  return success
end
function M:petBehaviour(b,pet,kind)
  if kind==0 or kind==1 then return kind end
  for pos=0,19 do
    local owner=Battle.GetPlayer(b,pos)
    if owner>=0 and Char.IsPlayer(owner) then
      for slot=0,4 do
        if Char.GetPet(owner,slot)==pet and self:buff(b,owner,'loyalty')>0 then return 0 end
      end
    end
  end
  return kind
end
function M:repair(p,sid,slv,item,prob,success)
  if sid==2221 or sid==2222 then
    if prob>=0 and success==0 and NLG.Rand(1,100)<=slv*10 then return 1 end
  end
  return success
end

function M:onLoad()
  self.effects={}; self.sessions={}
  for _,event in ipairs({'BattleStartEvent','BattleOverEvent'}) do
    self:regCallback(event,function(b) self.effects[b]=nil; return 0 end)
  end
  self:regCallback('BattleLuaSkillEvent',Func.bind(self.luaSkill,self))
  self:regCallback('DamageCalculateEvent',Func.bind(self.damage,self))
  self:regCallback('BattleHealCalculateEvent',Func.bind(self.heal,self))
  self:regCallback('BattleDodgeRateEvent',Func.bind(self.dodge,self))
  self:regCallback('CalcCriticalRateEvent',Func.bind(self.critical,self))
  self:regCallback('MergeItemEvent',Func.bind(self.merge,self))
  self:regCallback('GatherItemEvent',Func.bind(self.gather,self))
  self:regCallback('JudgeItemEvent',Func.bind(self.identify,self))
  self:regCallback('RepairItemEvent',Func.bind(self.repair,self))
  self:regCallback('BattlePetLeaveCheckEvent',Func.bind(self.petBehaviour,self))
  self:regCallback('LoginEvent',function(p)
    for _,s in ipairs(D.skills) do if s.kind=='craft' or s.kind=='trial' then self:giveRecipes(p,s.id) end end
  end)
  self:regCallback('LogoutEvent',function(p) self.sessions[p]=nil end)
  self:regCallback('ProductSkillExpEvent',function(p,sid,xp) self:giveRecipes(p,sid); return xp end)
  -- Native pet equipment slots: body=0, collar=1, crystal=2, accessories=3/4.
  for typ=56,60 do
    for place=0,4 do Item.SetPetEquipPlace(typ,place,false) end
    Item.SetPetEquipPlace(typ,typ<=57 and 0 or typ-57,true)
    if typ==60 then Item.SetPetEquipPlace(typ,4,true) end
  end
  for n,j in ipairs(D.jobs) do
    local f=j.family
    local npc=self:NPC_createNormal(j.name,14073,{mapType=0,map=1000,x=149+(n-1)*2,y=105,direction=4})
    assert(npc>=0,'Failed to create profession master')
    self:NPC_regTalkedEvent(npc,function(n,p) self:menu(n,p,f) end)
    self:NPC_regWindowTalkedEvent(npc,Func.bind(self.answer,self))
  end
  local npc=self:NPC_createNormal('职业进阶导师',14058,{mapType=0,map=1000,x=153,y=108,direction=4})
  assert(npc>=0,'Failed to create advanced-skill tutor')
  self:NPC_regTalkedEvent(npc,function(n,p) self:menu(n,p,nil) end)
  self:NPC_regWindowTalkedEvent(npc,Func.bind(self.answer,self))
  self:logInfo('Loaded 4 professions, 33 skills and 28 extended skills')
end
function M:onUnload() self.effects={}; self.sessions={} end
return M
