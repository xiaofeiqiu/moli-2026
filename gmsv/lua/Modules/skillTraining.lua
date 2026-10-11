-- Individual occupation tutors, one BOSS tutor; pets have their own module.
local M=ModuleBase:createModule('skillTraining')
local D=dofile('lua/Modules/skillTrainingData.lua')
local J=dofile('lua/Modules/jobTutorData.lua')
local players={};for _,s in ipairs(D.players) do players[s.id]=s end
local SEQ,CONFIRM_SEQ=7310,7311
local function get(p,k) local field=assert(CONST[k],k);return Char.GetData(p,field) end
local function say(p,msg) NLG.SystemMessage(p,msg) end
local function near(n,p)
 return Char.IsPlayer(p) and Char.IsValidCharIndex(n)
  and get(n,'CHAR_地图类型')==get(p,'CHAR_地图类型') and get(n,'CHAR_地图')==get(p,'CHAR_地图')
  and math.max(math.abs(get(n,'CHAR_X')-get(p,'CHAR_X')),math.abs(get(n,'CHAR_Y')-get(p,'CHAR_Y')))<=2
end
function M:ready(n,p)
 if not self.categories[n] or not near(n,p) then return false end
 if Char.GetBattleIndex(p)>=0 or get(p,'CHAR_BattleMode')~=0 then say(p,'请在战斗结束后学习技能。');return false end
 local qol=getModule('gameQoL')
 if qol and qol.stalls and qol.stalls[p] then say(p,'请先结束摆摊再学习技能。');return false end
 return true
end
function M:teaches(t,id)
 local s=players[id]
 if not s or s.source=='pet' then return false end
 if t.kind=='boss' then return s.source=='boss' end
 return s.source~='boss' and t.skillSet[id] or false
end
function M:learnPlayer(n,p,id)
 if not self:ready(n,p) then return false,'请走近导师后重新操作。' end
 local s=players[id]
 if s and s.source=='pet' then return false,'宠物专用技能不能由人物学习，请找宠物技能导师。' end
 if not self:teaches(self.categories[n],id) then return false,'这位导师不教授此技能。' end
 if s.unavailable then return false,s.unavailable end
 local lib=getModule('skillLibrary');if not lib then return false,'技能库暂时不可用。' end
 return lib:learn(p,id)
end
function M:list(p,role,source,mode)
 local out={};local tutor=self.catalog[role]
 if not tutor or mode=='pet' then return out end
 for _,s in ipairs(D.players) do
  if self:teaches(tutor,s.id) and (source=='all' or s.source==source) then out[#out+1]=s end
 end
 return out
end
function M:show(n,p,kind,page,source,slot,uuid,selected)
 self.sessions[p]=nil
 if not self:ready(n,p) then return end
 local t=self.categories[n];page=page or 1;source=source or 'all'
 if kind=='home' and t.kind=='boss' then kind='player';source='all' end
 local options,actions={},{}
 local function add(label,action) options[#options+1]=label;actions[#actions+1]=action end
 local title=t.name;local pages=1;local buttons=2
 if kind=='home' then
  add('本职业：全部技能',{kind='list',source='all'})
  add('本职业：普通技能',{kind='list',source='normal'})
  add('本职业：任务技能',{kind='list',source='quest'})
  add('打开永久技能库／配装',{kind='library'})
  add('补领当前技能的生产配方',{kind='recipes'})
  add('查看学习规则',{kind='rules'})
 elseif kind=='player' then
  local lib=getModule('skillLibrary');if not lib then say(p,'技能库暂时不可用。');return end
  local archive,err=lib:ready(p);if not archive then say(p,err);return end
  local list=self:list(p,t.id,source,'player');local size=t.kind=='boss' and 10 or 5
  pages=math.max(1,math.ceil(#list/size));page=math.max(1,math.min(page,pages))
  title=(t.kind=='boss' and 'BOSS技能' or t.name)..' '..page..'/'..pages
  for i=(page-1)*size+1,math.min(#list,page*size) do
   local s=list[i];local suffix=''
   if s.unavailable then suffix='／暂不可学'
   elseif archive.skills[tostring(s.id)] then suffix='／已学'
   elseif not lib:allowed(p,s.id) then suffix='／职业受限' end
   add(s.name..suffix,{kind='detail',id=s.id})
  end
  if t.kind=='boss' then
   -- Keep all ten rows for skills. Previous/next are native window buttons.
   if page>1 then buttons=buttons+16 end
   if page<pages then buttons=buttons+32 end
  else
   if page>1 then add('上一页',{kind='page',page=page-1}) end
   if page<pages then add('下一页',{kind='page',page=page+1}) end
   add('返回主菜单',{kind='home'})
  end
  if #list==0 then title=title..'\n本职业没有此来源的可学人物技能。' end
 elseif kind=='detail' then
  if not self:teaches(t,selected) then return end
  local s=players[selected]
  title='是否学习人物技能？\n'..s.name..' ['..s.id..']\n费用：'..s.cost..' 魔币\n学习后到永久技能库装配。'
  if s.unavailable then title=title..'\n'..s.unavailable end
 else return end
 self.sessions[p]={npc=n,player=Char.GetUUID(p),kind=kind,page=page,pages=pages,source=source,id=selected,actions=actions,expires=os.time()+120}
 if kind=='detail' then NLG.ShowWindowTalked(p,n,0,12,CONFIRM_SEQ,title);return end
 local limit=t.kind=='boss' and 10 or 8
 assert(#options<=limit,'selection limit')
 NLG.ShowWindowTalked(p,n,2,buttons,SEQ,self:NPC_buildSelectionText(title,options,limit))
end
function M:recipes(n,p)
 if not self:ready(n,p) then return end
 local tutor=self.categories[n];local count=0
 for _,r in ipairs(D.recipes) do
  local slot=Char.HaveSkill(p,r.skill)
  if self:teaches(tutor,r.skill) and slot>=0 and Char.GetSkillLevel(p,slot)>=r.level and Recipe.HasRecipe(p,r.id)~=1 and Recipe.GiveRecipe(p,r.id)==1 then count=count+1 end
 end
 local old=getModule('cg71JobSkills')
 if old then for _,s in ipairs(D.players) do if self:teaches(tutor,s.id) and Char.HaveSkill(p,s.id)>=0 then old:giveRecipes(p,s.id) end end end
 say(p,'已补领当前装配技能等级可用的配方：'..count..'份。制作仍需对应材料和魔力。')
end
function M:answer(n,p,seq,button,text)
 local a=self.sessions[p];self.sessions[p]=nil
 if not a or a.npc~=n or a.player~=Char.GetUUID(p) or a.expires<os.time() or not self:ready(n,p) then return end
 if a.kind=='detail' then
  if seq~=CONFIRM_SEQ then return end
  if button==4 then local ok,msg=self:learnPlayer(n,p,a.id);say(p,msg)
  elseif button~=8 then return end
  self:show(n,p,'player',a.page,a.source);return
 end
 if seq~=SEQ then return end
 if self.categories[n].kind=='boss' and a.kind=='player' then
  if button==16 and a.page>1 then self:show(n,p,'player',a.page-1,a.source);return end
  if button==32 and a.page<a.pages then self:show(n,p,'player',a.page+1,a.source);return end
 end
 if button~=0 then return end
 local choice=tonumber(text)
 if not choice or choice~=math.floor(choice) then return end
 local action=a.actions[choice];if not action then return end
 if action.kind=='home' then self:show(n,p,'home')
 elseif action.kind=='list' then self:show(n,p,'player',1,action.source)
 elseif action.kind=='page' then self:show(n,p,'player',action.page,a.source)
 elseif action.kind=='detail' then self:show(n,p,'detail',a.page,a.source,nil,nil,action.id)
 elseif action.kind=='library' then local lib=getModule('skillLibrary');if lib then lib:show(p,'home') end
 elseif action.kind=='recipes' then self:recipes(n,p);self:show(n,p,'home')
 elseif action.kind=='rules' then
  say(p,'圣殿同一房间内，生产系、物理战斗系、法系各排一行，导师之间空一格；每个职业有独立技能导师，名单来自本职业各职阶许可；学习仍检查人物当前职业与费用。BOSS人物技能由圣殿34,18的BOSS技能导师教授，每页10项。人物不能学习或装配宠物来源技能；宠物学习和遗忘由圣殿36,18的宠物技能导师办理。')
  self:show(n,p,'home')
 end
end
function M:onLoad()
 self.sessions={};self.categories={};self.catalog={};self.positions={}
 local w,h=Map.GetMapSize(0,J.floor);assert(w==100 and h==50,'Restart after widening the sanctuary')
 local function create(t)
  t.skillSet={}
  if t.kind=='job' then
   for _,s in ipairs(D.players) do if s.source~='pet' and s.source~='boss' then
    local ix=Skill.GetSkillIndex(s.id)
    for _,job in ipairs(t.jobs) do
     if ix>=0 and Skill.GetMaxSkillLevelOfJob(ix,job)>0 then t.skillSet[s.id]=true;break end
    end
   end end
  end
  local n=self:NPC_createNormal(t.name,t.image,t);assert(n>=0,'skill tutor creation failed')
  self.categories[n]=t;self.catalog[t.id]=t;self.positions[n]=t
  self:NPC_regTalkedEvent(n,function(n,p) self:show(n,p,'home') end)
  self:NPC_regWindowTalkedEvent(n,Func.bind(self.answer,self));return n
 end
 self.boss=create({id='boss',kind='boss',name='BOSS技能导师',image=100003,mapType=0,map=60003,x=34,y=18,direction=4})
 for _,t in ipairs(J.tutors) do create(t) end
 for _,event in ipairs({'LogoutEvent','DropEvent'}) do self:regCallback(event,function(p) self.sessions[p]=nil;return 0 end) end
 self:logInfo('Occupation tutors '..#J.tutors..'; one BOSS tutor; pets taught separately')
end
function M:onUnload() self.sessions={};self.categories={};self.catalog={};self.positions={} end
return M
