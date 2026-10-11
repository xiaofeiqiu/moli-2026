-- Persistent skill archive. Native slots are only the currently equipped set.
local M=ModuleBase:createModule('skillLibrary')
local D=dofile('lua/Modules/skillLibraryData.lua')
-- The categorized tutors extend the archive with installed quest skill IDs.
local training=loadfile('lua/Modules/skillTrainingData.lua')
local petOnly={}
if training then
  local catalog=training()
  for _,s in ipairs(catalog.players) do if s.source=='pet' then petOnly[s.id]=true end end
  local seen={};for _,s in ipairs(D.skills) do seen[s.id]=true end
  for _,s in ipairs(catalog.library_additions) do if not seen[s.id] then D.skills[#D.skills+1]=s;seen[s.id]=true end end
end
local KEY='SkillLibraryV1'
local specs={};for _,s in ipairs(D.skills) do specs[s.id]=s end
local customTechs={};for _,s in ipairs(D.skills) do if s.behavior then for lv,tid in ipairs(s.techs) do customTechs[tid]={id=s.id,level=lv,behavior=s.behavior,options=s.source_options or ''} end end end
local monsterTechs={};for _,s in ipairs(D.skills) do if s.xp_mode=='monster' then for _,tid in ipairs(s.techs) do monsterTechs[tid]=s.id end end end
local resistTypes={PO=6,SL=7,ST=8,YO=9,AA=10,CN=11}
local function c(k) local v=CONST[k];assert(v,k);return v end
local function get(p,k) return Char.GetData(p,c(k)) end
local function say(p,s) NLG.SystemMessage(p,s) end
local function copy(v) return JSON.decode(JSON.encode(v)) end
function M:active(p)
  local out={}
  for slot=0,14 do
    local id=Char.GetSkillID(p,slot)
    if id and id>=0 and Skill.GetSkillIndex(id)>=0 then out[#out+1]={id=id,level=Char.GetSkillLevel(p,slot),exp=Char.GetSkillExp(p,slot)} end
  end
  return out
end
function M:read(p)
  if self.cache[p] then return self.cache[p] end
  local raw=Char.GetExtData(p,KEY)
  if raw==nil or raw=='' then
    local result=SQL.QueryEx('SELECT val FROM hook_charaext WHERE cdKey=? AND regNo=? AND sKey=?',get(p,'CHAR_账号'),Char.GetData(p,CONST.对象_RegistNumber),KEY)
    if result.status~=0 then return nil,'技能库数据库暂时不可用，请稍后重试。' end
    if result.rows and result.rows[1] then raw=result.rows[1].val;Char.SetExtData(p,KEY,raw) end
  end
  local b
  if raw==nil or raw=='' then b={version=1,skills={},profiles={}}
  else
    local ok;ok,b=pcall(JSON.decode,raw)
    if not ok or type(b)~='table' or b.version~=1 or type(b.skills)~='table' or type(b.profiles)~='table' then return nil,'技能库存档异常，已停止操作，请联系管理员。' end
  end
  self.cache[p]=b;return b
end
function M:capture(p,b)
  for _,r in ipairs(self:active(p)) do
    local key=tostring(r.id);local old=b.skills[key]
    if not old or r.level>=old.level then b.skills[key]=r end
  end
end
function M:persist(p,b,saveCharacter)
  local raw=JSON.encode(b)
  Char.SetExtData(p,KEY,raw)
  if Char.GetExtData(p,KEY)~=raw then return false,'技能库保存失败，操作已停止。' end
  -- Write through the native SQL API before changing active slots. Dummy tests
  -- and real characters use the same durable extension row (string type 0).
  local account=get(p,'CHAR_账号');local reg=Char.GetData(p,CONST.对象_RegistNumber)
  local sql=SQL.QueryEx('REPLACE INTO hook_charaext(cdKey,regNo,sKey,val,valType) VALUES(?,?,?,?,?)',account,reg,KEY,raw,0)
  if sql.status~=0 or sql.effectRows<1 then return false,'技能库数据库写入失败，操作已停止。' end
  local disk=SQL.QueryEx('SELECT val FROM hook_charaext WHERE cdKey=? AND regNo=? AND sKey=?',account,reg,KEY)
  if disk.status~=0 or not disk.rows or not disk.rows[1] or disk.rows[1].val~=raw then return false,'技能库数据库校验失败，操作已停止。' end
  if saveCharacter and not Char.IsDummy(p) and Char.SaveToDb(p)~=0 then return false,'角色保存失败，操作已停止。' end
  return true
end
function M:allowed(p,id)
  if petOnly[id] then return false end
  local ix=Skill.GetSkillIndex(id)
  return specs[id]~=nil and ix>=0 and Skill.GetMaxSkillLevelOfJob(ix,get(p,'CHAR_职业'))>0
end
-- Native GetSkillExp is progress within the current level. SetSkillExp alone
-- does not level up; custom passive rewards need an explicit level transition.
function M:gainExperience(p,id,amount)
  local slot=Char.HaveSkill(p,id);if slot<0 or amount<=0 then return end
  local ix=Skill.GetSkillIndex(id);local cap=math.min(specs[id].max_level or 30,Skill.GetMaxSkillLevelOfJob(ix,get(p,'CHAR_职业')))
  local lv=Char.GetSkillLevel(p,slot);if lv>=cap then return end
  local group=Skill.GetData(ix,CONST.SKILL_EXPTABLE)
  local thresholds=D.experience[group];if not thresholds then return end
  local progress=Char.GetSkillExp(p,slot)+amount
  while lv<cap and thresholds[lv+1] and progress>=thresholds[lv+1] do
    progress=progress-thresholds[lv+1];lv=lv+1;Char.SetSkillLevel(p,slot,lv,1)
  end
  if lv>=cap then progress=0 end
  -- This native API rejects zero; a completed level has minimum progress 1.
  Char.SetSkillExp(p,slot,math.max(1,progress),1)
end
function M:resistance(b,p,q,typ,rate)
  if not Char.IsPlayer(q) then return rate end
  local reduction=0
  for _,s in ipairs(D.passive_resistance) do
    local slot=Char.HaveSkill(q,s.id)
    if slot>=0 then
      local lv=Char.GetSkillLevel(q,slot)
      for key,value in pairs(s.types) do if resistTypes[key]==typ then reduction=math.max(reduction,value*(1+(lv-1)*0.05)) end end
    end
  end
  return math.max(0,math.floor(rate*(1-math.min(0.95,reduction/100))))
end
function M:hostileTargets(b,p)
  local pos=get(p,'CHAR_BattleCom2');local out={}
  local function add(n)
    local q=Battle.GetPlayer(b,n)
    if q>=0 and get(q,'CHAR_血')>0 and get(q,'CHAR_战斗Side')~=get(p,'CHAR_战斗Side') then out[#out+1]=q end
  end
  if pos>=0 and pos<20 then add(pos)
  else
    local first=Battle.GetPos(b,p)<10 and 10 or 0
    if pos>=20 and pos<40 then first=math.floor((pos-20)/5)*5;for n=first,first+4 do add(n) end
    else for n=first,first+9 do add(n) end end
  end
  return out
end
function M:customCast(b,p,use,skl,act)
  local slot=Char.HaveSkill(p,use.id);if slot<0 or Char.GetSkillLevel(p,slot)<use.level then return end
  local kind=use.behavior;local lv=use.level
  if kind=='rest' then
    Char.SetData(p,c('CHAR_魔'),math.min(get(p,'CHAR_最大魔'),get(p,'CHAR_魔')+5*lv))
    self:gainExperience(p,use.id,30);skl(809);act(CONST.TechLua_ACT_EFFECT,Battle.GetPos(b,p),0);NLG.UpChar(p);return
  end
  local targets=(kind=='summon' or kind=='barrier') and {p} or self:hostileTargets(b,p)
  if #targets==0 then return end
  local fp=Tech.GetData(Tech.GetTechIndex(get(p,'CHAR_BattleCom3')),CONST.TECH_FORCEPOINT)
  if get(p,'CHAR_魔')<fp then return end
  Char.SetData(p,c('CHAR_魔'),get(p,'CHAR_魔')-fp);self:gainExperience(p,use.id,30)
  self.auras[b]=self.auras[b] or {}
  skl(809)
  if kind=='summon' or kind=='barrier' then
    self.auras[b][p]=self.auras[b][p] or {};self.auras[b][p][kind]={level=lv,expires=Battle.GetTurn(b)+3}
    act(CONST.TechLua_ACT_EFFECT,Battle.GetPos(b,p),0);NLG.UpChar(p);return
  end
  for _,q in ipairs(targets) do
    local damage=math.max(1,math.floor(math.max(1,get(p,'CHAR_攻击力')-get(q,'CHAR_防御力')*0.5)*(0.5+lv*0.05)))
    if kind=='weaken' or kind=='break' then
      self.weakness[b]=self.weakness[b] or {};self.weakness[b][q]={level=lv,expires=Battle.GetTurn(b)+3}
      if kind=='weaken' then damage=0 end
    elseif kind=='death' then
      local rate=tonumber(use.options:match('SR:(%d+)')) or 1000
      local success=NLG.Rand(1,10000)<=math.min(6000,rate+lv*80)
      if success and Char.IsEnemy(q) and Battle.IsBossBattle(b)~=1 then damage=get(q,'CHAR_血')
      else damage=math.min(damage,math.max(1,math.floor(get(q,'CHAR_最大血')*0.60))) end
    elseif kind=='status' then
      damage=0
      for key,value in use.options:gmatch('([A-Z]+):(-?%d+)') do
        if resistTypes[key] and tonumber(value)>0 then
          local rate=self:resistance(b,p,q,resistTypes[key],math.min(10000,1000+lv*200))
          if NLG.Rand(1,10000)<=rate then Battle.SetBattleCharacterStatus(q,resistTypes[key],3) end
        end
      end
    elseif kind=='dispel' then
      damage=0
      for n=0,15 do Battle.SetBattleCharacterStatus(q,n,0) end
      local old=getModule('cg71JobSkills');if old and old.effects[b] then old.effects[b][q]=nil end
      if self.weakness[b] then self.weakness[b][q]=nil end
      self.auras[b][q]=nil
    elseif kind=='acid' then Battle.SetBattleCharacterStatus(q,6,3)
    elseif kind=='energy' then
      local drained=math.min(get(q,'CHAR_魔'),lv*10)
      Char.SetData(q,c('CHAR_魔'),get(q,'CHAR_魔')-drained)
      Char.SetData(p,c('CHAR_魔'),math.min(get(p,'CHAR_最大魔'),get(p,'CHAR_魔')+drained));damage=0
    elseif kind=='gold' then Char.AddGold(p,lv*2) end
    if damage>0 then
      damage=math.min(damage,get(q,'CHAR_血'));Char.SetData(q,c('CHAR_血'),get(q,'CHAR_血')-damage)
      act(CONST.TechLua_ACT_DAMAGE,Battle.GetPos(b,q),1,damage)
      if kind=='blood' then Char.SetData(p,c('CHAR_血'),math.min(get(p,'CHAR_最大血'),get(p,'CHAR_血')+math.floor(damage*0.3))) end
    else act(CONST.TechLua_ACT_EFFECT,Battle.GetPos(b,q),0) end
  end
  NLG.UpChar(p)
end
function M:ready(p)
  if not Char.IsPlayer(p) or Char.GetBattleIndex(p)>=0 then return nil,'请在战斗结束后操作技能库。' end
  if self.busy[p] then return nil,'技能库正在保存，请稍后。' end
  local b,err=self:read(p);if not b then return nil,err end
  if b.journal then
    self.busy[p]=true
    local called,ok=pcall(self.restore,self,p,b.journal.before)
    ok=called and ok
    if ok then b.journal=nil;ok=self:persist(p,b,true) end
    self.busy[p]=nil
    if not ok then return nil,'上次配装未完成，恢复失败；已保留技能库，请联系管理员。' end
  end
  self:capture(p,b);return b
end
function M:learn(p,id)
  if petOnly[id] then return false,'宠物专用技能不能由人物学习，请找宠物技能导师。' end
  local b,err=self:ready(p);if not b then return false,err end
  if not self:allowed(p,id) then return false,'当前职业不能学习这个技能。' end
  local key=tostring(id)
  if b.skills[key] then return false,'技能库中已经学会此技能。' end
  local cost=specs[id].cost
  if Char.GetGold(p)<cost then return false,'金币不足，需要 '..cost..'。' end
  self.busy[p]=true
  b.skills[key]={id=id,level=1,exp=0}
  Char.AddGold(p,-cost)
  local ok,msg=self:persist(p,b,true)
  if not ok then
    Char.AddGold(p,cost);b.skills[key]=nil;self:persist(p,b,true)
  end
  self.busy[p]=nil;NLG.UpChar(p)
  return ok,msg or ('学会 '..specs[id].name..'，已永久保存到技能库，请装配后使用。')
end
function M:restore(p,desired)
  for _,r in ipairs(self:active(p)) do if Char.DelSkill(p,r.id,0)<0 then return false end end
  for _,r in ipairs(desired) do
    local slot=Char.AddSkill(p,r.id,r.exp,0)
    if slot<0 then return false end
    if Char.GetSkillLevel(p,slot)~=r.level then Char.SetSkillLevel(p,slot,r.level,0) end
    if r.exp>0 and Char.GetSkillExp(p,slot)~=r.exp then Char.SetSkillExp(p,slot,r.exp,0) end
    if Char.GetSkillLevel(p,slot)~=r.level or Char.GetSkillExp(p,slot)~=r.exp then return false end
    Char.SetSkillSeqNo(p,slot,slot+1,0)
  end
  local actual=self:active(p)
  if #actual~=#desired then return false end
  for i,r in ipairs(desired) do if actual[i].id~=r.id or actual[i].level~=r.level or actual[i].exp~=r.exp then return false end end
  return true
end
function M:loadout(p,ids)
  local b,err=self:ready(p);if not b then return false,err end
  if #ids>15 then return false,'每套出战配装最多15个技能。' end
  local seen,desired={},{}
  for _,id in ipairs(ids) do
    local r=b.skills[tostring(id)]
    if not r or seen[id] or not self:allowed(p,id) then return false,'配装包含未学、重复或当前职业不能使用的技能。' end
    seen[id]=true;desired[#desired+1]=copy(r)
  end
  local before=self:active(p)
  self.busy[p]=true
  b.journal={before=before,wanted=ids}
  local ok,msg=self:persist(p,b,true)
  if ok then
    Char.SetData(p,c('CHAR_技能栏'),15)
    local called,result=pcall(self.restore,self,p,desired)
    ok=called and result
    if ok then
      local oldJournal=b.journal;b.journal=nil
      ok,msg=self:persist(p,b,true)
      if not ok then b.journal=oldJournal end
    end
    if not ok then
      local recovered,restored=pcall(self.restore,self,p,before)
      restored=recovered and restored
      if restored then b.journal=nil;self:persist(p,b,true) end
      msg=restored and '配装失败，原技能已恢复，技能库仍保留。' or '配装失败，恢复记录已保留，请联系管理员。'
    end
  end
  self.busy[p]=nil;NLG.UpChar(p)
  if ok then
    local old=getModule('cg71JobSkills')
    if old then for _,id in ipairs(ids) do old:giveRecipes(p,id) end end
  end
  return ok,msg or '出战技能已切换，未装配技能的等级和经验仍保存在技能库。'
end
function M:equip(p,id,position)
  local b,err=self:ready(p);if not b then return false,err end
  local ids={};for _,r in ipairs(self:active(p)) do if r.id==id then return false,'这个技能已经装配。' end;ids[#ids+1]=r.id end
  if position<1 or position>math.min(15,#ids+1) then return false,'无效技能位置。' end
  ids[position]=id;return self:loadout(p,ids)
end
function M:unequip(p,id)
  local ids={};for _,r in ipairs(self:active(p)) do if r.id~=id then ids[#ids+1]=r.id end end
  return self:loadout(p,ids)
end
function M:profile(p,name)
  local b,err=self:ready(p);if not b then return false,err end
  if type(name)~='string' or #name<1 or #name>24 or name:find('[%c]') then return false,'配装名称需为1至24字节，不能包含控制字符。' end
  local ids={};for _,r in ipairs(self:active(p)) do ids[#ids+1]=r.id end
  local before=b.profiles[name];b.profiles[name]=ids
  self.busy[p]=true;local ok,msg=self:persist(p,b,true);self.busy[p]=nil
  if not ok then b.profiles[name]=before;self:persist(p,b,false) end
  return ok,msg or '已保存配装 '..name..'。'
end
function M:show(p,kind,page,selected)
  local b,err=self:ready(p);if not b then say(p,err);return end
  page=page or 1;local list={};local labels={};local options={}
  if kind=='home' then
    options={'查看已学技能','学习本职技能','装配或替换技能','卸下技能','保存当前配装','加载配装','查看规则'}
  elseif kind=='learn' then
    for _,s in ipairs(D.skills) do if self:allowed(p,s.id) and not b.skills[tostring(s.id)] then list[#list+1]=s.id;labels[#labels+1]=s.name..'（'..s.cost..'金）' end end
  elseif kind=='view' or kind=='equip' then
    for key,r in pairs(b.skills) do if kind=='view' or self:allowed(p,r.id) then list[#list+1]=r.id end end;table.sort(list)
    for _,id in ipairs(list) do local r=b.skills[tostring(id)];labels[#labels+1]=(specs[id] and specs[id].name or tostring(id))..' Lv'..r.level end
  elseif kind=='remove' then
    for _,r in ipairs(self:active(p)) do list[#list+1]=r.id;labels[#labels+1]=(specs[r.id] and specs[r.id].name or tostring(r.id))..' Lv'..r.level end
  elseif kind=='slot' then
    local active=self:active(p)
    for i=1,math.min(15,#active+1) do list[#list+1]=i;labels[#labels+1]=tostring(i)..'：'..(active[i] and (specs[active[i].id] and specs[active[i].id].name or tostring(active[i].id)) or '空位') end
  elseif kind=='profiles' then
    for name in pairs(b.profiles) do list[#list+1]=name end;table.sort(list)
    for _,name in ipairs(list) do labels[#labels+1]=name..'（'..#b.profiles[name]..'技能）' end
  elseif kind=='save' then
    self.sessions[p]={kind=kind,expires=os.time()+120}
    NLG.ShowWindowTalked(p,self.npc,1,3,7202,'请输入配装名称（最多24字节）');return
  end
  local actions={}
  if kind=='home' then for i in ipairs(options) do actions[i]={kind='home',value=i} end
  else
    local pages=math.max(1,math.ceil(#list/5));page=math.max(1,math.min(page,pages))
    for i=(page-1)*5+1,math.min(#list,page*5) do options[#options+1]=labels[i];actions[#actions+1]={kind=kind,value=list[i]} end
    if page>1 then options[#options+1]='上一页';actions[#actions+1]={kind='page',value=page-1} end
    if page<pages then options[#options+1]='下一页';actions[#actions+1]={kind='page',value=page+1} end
    options[#options+1]='返回主菜单';actions[#actions+1]={kind='back'}
  end
  self.sessions[p]={kind=kind,page=page,selected=selected,actions=actions,expires=os.time()+120}
  NLG.ShowWindowTalked(p,self.npc,2,2,7201,self:NPC_buildSelectionText('永久技能库（战前装配15个技能）',options))
end
function M:answer(npc,p,seq,select,text)
  local a=self.sessions[p];self.sessions[p]=nil
  if not a or npc~=self.npc or a.expires<os.time() or Char.GetBattleIndex(p)>=0 then return end
  if seq==7202 and a.kind=='save' then
    if select~=1 then return end
    local ok,msg=self:profile(p,text);say(p,msg);return
  end
  if seq~=7201 then return end
  local choice=tonumber(text);local action=choice and a.actions[choice];if not action then return end
  local k,v=action.kind,action.value
  if k=='home' then
    if v==7 then say(p,'技能永久保存；每套装配15个，战斗中不能切换。人物不能学习或装配宠物技能。圣殿内生产系、物理战斗系、法系各一排，导师中间空一格；BOSS导师在34,18，每页10项；宠物导师在36,18负责学习与遗忘。魔剑士七职阶可学全部有效人物技能；费用照常，任务技能保留原上限。最高30级；聊天输入 /技能库 可随时打开。')
    else self:show(p,({'view','learn','equip','remove','save','profiles'})[v]) end
  elseif k=='page' then self:show(p,a.kind,v,a.selected)
  elseif k=='back' then self:show(p,'home')
  elseif k=='view' then self:show(p,'view',a.page)
  elseif k=='equip' then self:show(p,'slot',1,v)
  elseif k=='learn' then local ok,msg=self:learn(p,v);say(p,msg);self:show(p,'learn',a.page)
  elseif k=='slot' then local ok,msg=self:equip(p,a.selected,v);say(p,msg)
  elseif k=='remove' then local ok,msg=self:unequip(p,v);say(p,msg)
  elseif k=='profiles' then local b=self:read(p);local ok,msg=self:loadout(p,b.profiles[v]);say(p,msg) end
end
function M:flush(p)
  if self.busy[p] then return 0 end
  local b=self:read(p)
  if b and not b.journal then self:capture(p,b);self:persist(p,b,false) end
  return 0
end
function M:onLoad()
  self.cache={};self.busy={};self.sessions={}
  self.npc=self:NPC_createNormal('永久技能库管理员',14058,{mapType=0,map=1000,x=153,y=110,direction=4})
  assert(self.npc>=0)
  self:NPC_regTalkedEvent(self.npc,function(n,p) self:show(p,'home') end)
  self:NPC_regWindowTalkedEvent(self.npc,Func.bind(self.answer,self))
  self:regCallback('TalkEvent',function(p,msg)
    if msg=='/技能库' or msg=='/skillbook' then self:show(p,'home');return 0 end
    return 1
  end)
  self:regCallback('LoginEvent',function(p)
    self.cache[p]=nil;Char.SetData(p,c('CHAR_技能栏'),15)
    local b,err=self:ready(p);if not b then say(p,err) else self:persist(p,b,false) end
    NLG.UpChar(p);return 0
  end)
  self:regCallback('BeforeCharaSaveEvent',Func.bind(self.flush,self))
  for _,event in ipairs({'BattleSkillExpEvent','ProductSkillExpEvent'}) do
    self:regCallback(event,function(p,id,xp)
      if Char.IsPlayer(p) and specs[id] then
        if specs[id].xp_mode=='native' then self:gainExperience(p,id,xp) end
        return 0
      end
      return xp
    end)
  end
  self.weakness={}
  self.auras={};self.executedMonsterSkills={}
  -- Native commands are cleared before AfterBattleTurnEvent. Remember the
  -- selected player Tech IDs before executing the turn, then award once.
  self:regCallback('BeforeBattleTurnEvent',function(b)
    local selected={}
    for pos=0,19 do
      local p=Battle.GetPlayer(b,pos)
      if p>=0 and Char.IsPlayer(p) then
        local id=monsterTechs[get(p,'CHAR_BattleCom3')]
        if id then selected[p]=id end
      end
    end
    self.executedMonsterSkills[b]=selected
    return false
  end)
  for _,event in ipairs({'BattleStartEvent','BattleOverEvent'}) do
    self:regCallback(event,function(b) self.executedMonsterSkills[b]=nil;return 0 end)
  end
  self:regCallback('BattleStatusResistanceEvent',Func.bind(self.resistance,self))
  self:regCallback('AfterBattleTurnEvent',function(b)
    for pos=0,19 do
      local p=Battle.GetPlayer(b,pos)
      if p>=0 and Char.IsPlayer(p) then
        local id=self.executedMonsterSkills[b] and self.executedMonsterSkills[b][p]
        if id then self:gainExperience(p,id,30) end
        for _,s in ipairs(D.passive_resistance) do if Char.HaveSkill(p,s.id)>=0 and id~=s.id then self:gainExperience(p,s.id,30) end end
      end
    end
    self.executedMonsterSkills[b]=nil
  end)
  self:regCallback('BattleLuaSkillEvent',function(b,p,skl,act)
    local use=customTechs[get(p,'CHAR_BattleCom3')];if use then self:customCast(b,p,use,skl,act) end
  end)
  self:regCallback('DamageCalculateEvent',function(p,q,ori,dmg,b)
    local w=self.weakness[b] and self.weakness[b][p]
    if w and w.expires>Battle.GetTurn(b) and dmg>0 then dmg=math.max(1,math.floor(dmg*(1-math.min(0.8,w.level*0.02)))) end
    local a=self.auras[b] or {};local summon=a[p] and a[p].summon;local barrier=a[q] and a[q].barrier
    if summon and summon.expires>Battle.GetTurn(b) then dmg=math.floor(dmg*(1+summon.level*0.03)) end
    if barrier and barrier.expires>Battle.GetTurn(b) then dmg=math.floor(dmg*(1-math.min(0.8,barrier.level*0.02))) end
    return dmg
  end)
  self:regCallback('BattleOverEvent',function(b) self.weakness[b]=nil;self.auras[b]=nil end)
  for _,event in ipairs({'LogoutEvent','DropEvent'}) do
    self:regCallback(event,function(p) self:flush(p);self.cache[p]=nil;self.sessions[p]=nil;return 0 end)
  end
  self:logInfo('Persistent skill archive loaded; active slots 15; maximum level 30')
end
function M:onUnload() self.cache={};self.busy={};self.sessions={} end
return M
