local M=ModuleBase:createModule('sharedTaskAdapters')
local D=dofile('lua/Modules/sharedTaskAdaptersData.lua')
local TaskJobs=dofile('lua/Modules/magicTaskJobs.lua')
local by={};for _,v in ipairs(D) do by[v.key]=v end
local function get(p,k) local field=assert(CONST[k],k);return Char.GetData(p,field) end
local function set(p,k,v) local field=assert(CONST[k],k);return Char.SetData(p,field,v) end
local function tell(p,s) NLG.SystemMessage(p,s) end
local function flag(p,k) return tonumber(Char.GetExtData(p,'sharedTasks:v1:'..k)) or 0 end
local function mark(p,k,v) Char.SetExtData(p,'sharedTasks:v1:'..k,v or 1) end
local function empty(p)
 local count=0
 for s=8,CONST.EXTITEMMAX-1 do
  if Char.GetItemIndex(p,s)==-2 then count=count+1 end
 end
 return count
end
local function give(p,id,qty)
 local before=Char.ItemNum(p,id)
 for attempt=1,qty do
  local missing=before+qty-Char.ItemNum(p,id)
  if missing<=0 then return true end
  if Char.GiveItem(p,id,missing,false)<0 then break end
 end
 return Char.ItemNum(p,id)>=before+qty
end
local function near(n,p)
 return n>=0 and get(p,'CHAR_地图')==get(n,'CHAR_地图') and get(p,'CHAR_地图类型')==get(n,'CHAR_地图类型')
  and math.abs(get(p,'CHAR_X')-get(n,'CHAR_X'))<=3 and math.abs(get(p,'CHAR_Y')-get(n,'CHAR_Y'))<=3
end
function M:allowed(n,p,c)
 if not Char.IsPlayer(p) or Char.GetBattleIndex(p)>=0 then return false end
 if c.useItem then return Char.ItemNum(p,c.useItem)>=1 end
 for _,id in ipairs(c.useItems or {}) do if Char.ItemNum(p,id)>=1 then return true end end
 if not near(n,p) then return false end
 for _,r in ipairs(c.roles or {}) do
  if get(n,'CHAR_名字')==r.name and ((get(n,'CHAR_地图')==r.floor and get(n,'CHAR_地图类型')==r.mapType) or (r.floor==777 and get(n,'CHAR_地图类型')>0)) then return true end
 end
 return false
end
function M:requirements(p,c)
 if (c.level or 0)>get(p,'CHAR_等级') then return false,'请达到 '..c.level..' 级后再来。' end
 if (c.cost or 0)>get(p,'CHAR_金币') then return false,'魔币不足，需要 '..c.cost..' 魔币。' end
 if c.needDone and flag(p,c.needDone)<1 then return false,'请先完成本章节的前置调查或挑战。' end
 for _,r in ipairs(c.need or {}) do
  if Char.ItemNum(p,r[1])<r[2] then return false,'缺少任务道具，请按接待员的提示收集。' end
 end
 local slots=0;for _,r in ipairs(c.give or {}) do slots=slots+r[2] end
 if empty(p)<slots then return false,'请先清理背包，留出奖励所需的空位。' end
 return true
end
function M:destination(p,v)
 if not v then return nil,true end
 if Char.PartyNum(p)>1 then tell(p,'请先解散队伍。');return nil,false end
 local x,y=v[3],v[4]
 if Map.IsWalkable(v[1],v[2],x,y)~=1 then
  local found=false;local w,h=Map.GetMapSize(v[1],v[2])
  for radius=1,8 do
   for dx=-radius,radius do for dy=-radius,radius do
    local a,b=x+dx,y+dy
    if not found and a>=0 and b>=0 and a<w and b<h and Map.IsWalkable(v[1],v[2],a,b)==1 then x,y,found=a,b,true end
   end end
   if found then break end
  end
  if not found then
   local a,b=Map.GetAvailablePos(v[1],v[2])
   if a and a>=0 and Map.IsWalkable(v[1],v[2],a,b)==1 then x,y,found=a,b,true end
  end
  if not found then tell(p,'无法找到安全的落脚位置。');return nil,false end
 end
 return {v[1],v[2],x,y},true
end
function M:warp(p,v)
 local d,ok=self:destination(p,v);if not ok then return false end
 if d then Char.Warp(p,d[1],d[2],d[3],d[4]) end
 return not d or (get(p,'CHAR_地图')==d[2] and get(p,'CHAR_X')==d[3] and get(p,'CHAR_Y')==d[4])
end
function M:grant(p,c)
 if c.once and flag(p,c.key)>0 then tell(p,'这份调查奖励已经领取过了。');return 0 end
 local ok,why=self:requirements(p,c);if not ok then tell(p,why);return 0 end
 local destination,valid=self:destination(p,c.warp);if not valid then return 0 end
 local given={}
 for _,r in ipairs(c.give or {}) do
  local before=Char.ItemNum(p,r[1])
  if not give(p,r[1],r[2]) then
   local partial=Char.ItemNum(p,r[1])-before;if partial>0 then Char.DelItem(p,r[1],partial,false) end
   for _,old in ipairs(given) do Char.DelItem(p,old[1],old[2],false) end
   tell(p,'背包无法接收奖励，请清理后再来。');return 0
  end
  given[#given+1]=r
 end
 if not c.retainNeeds then
  local consumed={}
  for _,r in ipairs(c.need or {}) do
   local before=Char.ItemNum(p,r[1]);Char.DelItem(p,r[1],r[2],false)
   local removed=before-Char.ItemNum(p,r[1])
   if removed~=r[2] then
    if removed>0 then give(p,r[1],removed) end
    for _,old in ipairs(consumed) do give(p,old[1],old[2]) end
    for _,old in ipairs(given) do Char.DelItem(p,old[1],old[2],false) end
    tell(p,'任务道具发生变化，请重新交谈。');return 0
   end
   consumed[#consumed+1]=r
  end
 end
 if c.cost and c.cost>0 then Char.AddGold(p,-c.cost) end
 if c.cooldown then mark(p,c.key..':claimed_at',os.time()) end
 if c.once then mark(p,c.key) end
 if c.setDone then mark(p,c.setDone) end
 if c.rounds and not c.once then mark(p,c.key..':victory',0) end
 self:warp(p,destination);NLG.UpChar(p);tell(p,'调查已经完成，请继续下一段旅程。')
 return 1
end
function M:startRound(p,n,c,round)
 local enemies,levels,ranges={},{},{}
 for _,v in ipairs(c.rounds[round]) do enemies[#enemies+1]=v[1];levels[#levels+1]=v[2];ranges[#ranges+1]=0 end
 local b=Battle.PVE(p,p,nil,enemies,levels,ranges)
 if b<0 then tell(p,'战斗没有成功开启，请重新交谈。');return 0 end
 self.pending[b]={player=p,npc=n,config=c,round=round,uuid=get(p,'CHAR_名字')}
 if Battle.SetWinEvent(nil,self.winFunction,b)~=1 then
  self.pending[b]=nil;Battle.ExitBattle(p);tell(p,'挑战无法登记，请稍后再试。');return 0
 end
 return 1
end
function M:won(b,p)
 local pending=self.pending[b]
 if not pending or pending.player~=p or pending.uuid~=get(p,'CHAR_名字') then return end
 if Battle.GetWinSide(b)~=0 or get(p,'CHAR_血')<=0 then return end
 local present=false
 for s=0,9 do if Battle.GetPlayer(b,s)==p then present=true end end
 if not present then return end
 for s=10,19 do local enemy=Battle.GetPlayer(b,s);if enemy>=0 and get(enemy,'CHAR_血')>0 then return end end
 self.pending[b]=nil
 local c,round=pending.config,pending.round
 if round<#c.rounds then
  local attempts=0
  local function nextRound()
   attempts=attempts+1
   if not Char.IsPlayer(p) or get(p,'CHAR_名字')~=pending.uuid then return end
   if Char.GetBattleIndex(p)>=0 then
    if attempts<20 then Cron.AddInterval(250,nextRound,0) end
    return
   end
   if not self:allowed(pending.npc,p,c) then tell(p,'挑战因离开接待地点而中止，请重新报名。');return end
   self:startRound(p,pending.npc,c,round+1)
  end
  Cron.AddInterval(250,nextRound,0)
 else
  mark(p,c.key..':victory')
  -- Grant from the victory callback; a full backpack leaves a claimable proof.
  self:grant(p,c)
 end
end
function M:item(p,c)
 local pet=Char.GetPet(p,0);local mode=c.itemMode
 if mode=='pet' then
  if Char.PetNum(p)>=5 then tell(p,'宠物栏已满。');return 0 end
  if Char.GivePet(p,c.pet)<0 then tell(p,'无法孵化宠物。');return 0 end
 elseif mode=='petSkill' then
  if pet<0 then tell(p,'请将要学习技能的宠物放到第一格。');return 0 end
  for s=0,9 do if Pet.GetSkill(pet,s)==c.tech then tell(p,'这只宠物已经掌握该技能。');return 0 end end
  if Pet.AddSkill(pet,c.tech)~=1 then tell(p,'宠物没有可用的技能格。');return 0 end
  Pet.UpPet(p,pet)
 elseif mode=='rebirth' then
  if pet<0 or get(pet,'CHAR_等级')<50 then tell(p,'第一格宠物必须达到50级。');return 0 end
  Pet.ReBirth(p,pet)
  if get(pet,'CHAR_等级')~=1 then tell(p,'宠物回炉失败。');return 0 end
  Pet.UpPet(p,pet)
 elseif mode=='experience' or mode=='petExperience' then
  local who=mode=='petExperience' and pet or p
  if who<0 then tell(p,'请把需要训练的宠物放到第一格。');return 0 end
  local xp=get(who,'CHAR_经验');local amount=10000
  if xp>2147473647 then tell(p,'累计经验已达到当前可用上限。');return 0 end
  set(who,'CHAR_经验',xp+amount);Char.UpCharStatus(who)
  if who==p then NLG.UpChar(p) else Pet.UpPet(p,who) end
 elseif mode=='warp' then
  if Char.PartyNum(p)>1 or not self:warp(p,c.warp) then return 0 end
 else return 0 end
 Char.DelItem(p,c.useItem,1,false);tell(p,'道具已使用。');return 1
end
function M:execute(n,p,text)
 if TaskJobs.has(text) then
  if not Char.IsPlayer(p) then return 0 end
  return TaskJobs.check(get(p,'CHAR_职业'),text,get(p,'CHAR_职类ID'))
 end
 local c=by[text];if not c then return end
 if not self:allowed(n,p,c) then return 0 end
 if c.kind=='legacy' then
  local who=p
  if c.target=='pet' then who=Char.GetPet(p,c.slot or 0);if who<0 then return 0 end end
  if c.target=='item' then who=Char.GetItemIndex(p,8+(c.slot or 0));if who<0 then return 0 end end
  local field=assert(CONST[c.field],c.field)
  local value=c.target=='item' and Item.GetData(who,field) or Char.GetData(who,field)
  if c.target=='item' and c.field=='道具_VAR1' then value=math.max(0,value) end
  if c.jobRangeJobs then return TaskJobs.range(value,c.jobRangeJobs) end
  if c.value==nil then return tonumber(value) or 0 end
  value=c.mode==1 and value+c.value or c.value
  if c.target=='player' and c.field=='CHAR_职业' then
   local promoted=TaskJobs.promotedJob(get(p,'CHAR_职业'),value)
   if promoted~=value then set(p,'CHAR_职类ID',180);value=promoted end
  end
  if c.mode==1 and c.limit and c.limit>=0 then value=math.min(c.limit,value) end
  value=math.max(-2147483647,math.min(2147483647,value))
  if c.target=='item' then Item.SetData(who,field,value);Item.UpItem(p,8+(c.slot or 0))
  else set(who,c.field,value);Char.UpCharStatus(who);if who~=p then Pet.UpPet(p,who) end end
  NLG.UpChar(p);return 1
 end
 if c.kind=='marker' then mark(p,c.setDone);return 1 end
 if c.kind=='item' then return self:item(p,c) end
 if c.once and flag(p,c.key)>0 then tell(p,'这项奖励已经领取过。');return 0 end
 if c.cooldown and flag(p,c.key..':claimed_at')+c.cooldown>os.time() then tell(p,'本次补给已经领取，请稍后再来。');return 0 end
 local ok,why=self:requirements(p,c);if not ok then tell(p,why);return 0 end
 if c.entranceFloor and get(n,'CHAR_地图')==c.entranceFloor then return self:warp(p,c.entranceWarp) and 1 or 0 end
 if c.kind=='battle' then
  if flag(p,c.key..':victory')>0 then
   local result=self:grant(p,c);if result==1 and not c.once then mark(p,c.key..':victory',0) end;return result
  end
  if Char.PartyNum(p)>1 then tell(p,'这项自制试炼需要单人挑战。');return 0 end
  return self:startRound(p,n,c,1)
 elseif c.kind=='petTeacher' then
  local pet=Char.GetPet(p,0);if pet<0 then tell(p,'请把要学习技能的宠物放到第一格。');return 0 end
  for _,tech in ipairs(c.techs) do
   local have=false;for s=0,9 do if Pet.GetSkill(pet,s)==tech then have=true end end
   if not have and Pet.AddSkill(pet,tech)==1 then
    Char.AddGold(p,-c.cost);Pet.UpPet(p,pet);tell(p,'第一格宠物学会了新的宗师技能。');return 1
   end
  end
  tell(p,'已有这些技能，或宠物技能格已满。');return 0
 else return self:grant(p,c) end
end
local function skillLevel(p,id)
 local slot=Char.HaveSkill(p,id);if slot<0 then return 0 end
 return Char.GetSkillLevel(p,slot)
end
function M:serviceMenu(n,p,kind,page)
 if not near(n,p) or Char.GetBattleIndex(p)>=0 then return end
 local data=by['stp:services'];local options,actions={},{}
 local function add(label,a) options[#options+1]=label;actions[#actions+1]=a end
 page=page or 1
 if kind=='jobs' or kind=='materials' then
  local list=data[kind];local first=(page-1)*5+1
  for i=first,math.min(first+4,#list) do
   local c=list[i];add(c.name,{kind=kind=='jobs' and 'confirmJob' or 'material',index=i})
  end
  if page>1 then add('上一页',{kind='page',group=kind,page=page-1}) end
  if first+5<=#list then add('下一页',{kind='page',group=kind,page=page+1}) end
  add('返回',{kind='page'})
 else
  add('自制职业登记（20级，5000魔币）',{kind='page',group='jobs'})
  add('办理本职业晋阶',{kind='promote'})
  add('领取当前技能等级可用的配方',{kind='recipes'})
  add('寻回遗失材料（20级单人试炼）',{kind='page',group='materials'})
 end
 self.serviceSessions[p]={npc=n,actions=actions,expires=os.time()+90}
 NLG.ShowWindowTalked(p,n,2,2,7292,self:NPC_buildSelectionText('远征后勤与自制职业',options))
end
function M:joinJob(p,c)
 if get(p,'CHAR_等级')<20 or Char.GetGold(p)<5000 then tell(p,'登记需要20级和5000魔币。');return 0 end
 local target=c.ranks[1]
 if get(p,'CHAR_职类ID')==c.family then tell(p,'你已经登记在该职业中。');return 0 end
 Char.AddGold(p,-5000);set(p,'CHAR_职业',target.id);set(p,'CHAR_职类ID',c.family);set(p,'CHAR_职阶',0)
 Char.UpCharStatus(p);NLG.UpChar(p);tell(p,'自制职业登记完成。职业技能上限按职业表生效。');return 1
end
function M:promote(p)
 local data=by['stp:services'];local current=get(p,'CHAR_职业')
 for _,c in ipairs(data.jobs) do
  for i,r in ipairs(c.ranks) do
   if r.id==current then
    local next=c.ranks[i+1];if not next then tell(p,'已经达到最高阶级。');return 0 end
    local level=({20,40,60,80,100,140})[i]
    if get(p,'CHAR_等级')<level or get(p,'CHAR_声望')<next.fame or Char.GetGold(p)<next.cost then tell(p,'晋阶需要等级 '..level..'，声望 '..next.fame..'，魔币 '..next.cost..'。');return 0 end
    for _,s in ipairs(next.need) do if skillLevel(p,s[1])<s[2] then tell(p,'职业专属技能尚未达到晋阶要求。');return 0 end end
    Char.AddGold(p,-next.cost);set(p,'CHAR_职业',next.id);set(p,'CHAR_职阶',i)
    Char.UpCharStatus(p);NLG.UpChar(p);tell(p,'晋阶完成：'..next.name);return 1
   end
  end
 end
 tell(p,'这里只办理共享包内职业的晋阶。');return 0
end
function M:serviceAnswer(n,p,seq,button,text)
 local session=self.serviceSessions[p];self.serviceSessions[p]=nil
 if not session or seq~=7292 or session.npc~=n or session.expires<os.time() or not near(n,p) or Char.GetBattleIndex(p)>=0 then return end
 local a=session.actions[tonumber(text) or 0];if not a then return end
 local data=by['stp:services']
 if a.kind=='page' then self:serviceMenu(n,p,a.group,a.page)
 elseif a.kind=='confirmJob' then
  self.serviceSessions[p]={npc=n,expires=os.time()+90,actions={{kind='join',index=a.index},{kind='page',group='jobs',page=math.floor((a.index-1)/5)+1}}}
  -- Keep each title row short: client wrapping would shift selection indices.
  local title='确认转入：\n'..data.jobs[a.index].name..'\n现有技能保留。\n技能上限随职业调整。'
  NLG.ShowWindowTalked(p,n,2,2,7292,self:NPC_buildSelectionText(title,{'确认登记：5000魔币','返回'}))
 elseif a.kind=='join' then self:joinJob(p,data.jobs[a.index])
 elseif a.kind=='promote' then self:promote(p)
 elseif a.kind=='material' then
  local c=data.materials[a.index];self:execute(n,p,c.key)
 elseif a.kind=='recipes' then
  local count=0
  for _,r in ipairs(data.recipes) do if skillLevel(p,r.skill)>=r.level and Recipe.GiveRecipe(p,r.id)==1 then count=count+1 end end
  tell(p,'本次学会 '..count..' 份配方。制作仍需要相应技能、魔力和材料，请从原生技能窗口制作。')
 end
end
function M:onLoad()
 self.pending={}
 self.winFunction=self:regCallback('shared_task_win',Func.bind(self.won,self))
 self:regCallback('ScriptCallEvent',Func.bind(self.execute,self))
 self:regCallback('LogoutEvent',function(p)
  self.serviceSessions[p]=nil
  for b,t in pairs(self.pending) do if t.player==p then self.pending[b]=nil end end
 end)
 self.serviceSessions={}
 if by['stp:services'] then
  local n=self:NPC_createNormal('远征后勤官',14058,{mapType=0,map=1000,x=151,y=114,direction=4})
  assert(n>=0,'shared task services creation failed');self.services=n
  self:NPC_regTalkedEvent(n,function(n,p) self:serviceMenu(n,p) end)
  self:NPC_regWindowTalkedEvent(n,Func.bind(self.serviceAnswer,self))
 end
 self:regCallback('BattleEscapeEvent',function(b,p,rate)
  -- An attempted escape may fail. Clear only after the native exit event.
  return rate
 end)
 self:regCallback('BattleExitEvent',function(p,b,typ)
  local t=self.pending[b]
  if t and t.player==p then self.pending[b]=nil end
 end)
 self:logInfo('Loaded custom quest interactions: '..#D)
end
function M:onUnload() self.pending={} end
return M
