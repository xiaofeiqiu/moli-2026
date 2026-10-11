-- Native pet skill deletion; tools source is UTF-8, runtime is GBK.
local M=ModuleBase:createModule('petSkillTutor')
local D=dofile('lua/Modules/skillTrainingData.lua')
local lessons={};for _,s in ipairs(D.pets) do lessons[s.id]=s end
local SEQ=7320
local CONFIRM_SEQ=7321
local LEARN_SEQ=7322
local YES,NO=4,8 -- Native message-window buttons; 12 displays both.
local function get(p,k) local field=assert(CONST[k],k);return Char.GetData(p,field) end
local function say(p,msg) NLG.SystemMessage(p,msg) end
local function integer(v,lo,hi) return type(v)=='number' and v==math.floor(v) and v>=lo and v<=hi end
local function skillName(id)
 local ix=Tech.GetTechIndex(id)
 return ix>=0 and Tech.GetData(ix,CONST.TECH_NAME) or ('未知技能 ['..id..']')
end
function M:ready(n,p)
 if n~=self.npc or not Char.IsValidCharIndex(n) or not Char.IsPlayer(p) then return false end
 if get(n,'CHAR_地图类型')~=get(p,'CHAR_地图类型') or get(n,'CHAR_地图')~=get(p,'CHAR_地图')
  or math.max(math.abs(get(n,'CHAR_X')-get(p,'CHAR_X')),math.abs(get(n,'CHAR_Y')-get(p,'CHAR_Y')))>2 then return false end
 if Char.GetBattleIndex(p)>=0 or get(p,'CHAR_BattleMode')~=0 then say(p,'请在战斗结束后遗忘宠物技能。');return false end
 local qol=getModule('gameQoL')
 if qol and qol.stalls and qol.stalls[p] then say(p,'请先结束摆摊再遗忘宠物技能。');return false end
 local five=getModule('fivePet');local squad=five and five.active[p]
 if squad and squad.battle then say(p,'五宠战斗结算尚未完成，请稍后再操作。');return false end
 return true
end
function M:pet(p,slot,uuid)
 if not integer(slot,0,4) then return nil,'无效的宠物栏位。' end
 local q=Char.GetPet(p,slot)
 if q<0 or not Char.IsValidCharIndex(q) or not Char.IsPet(q) or Pet.GetOwner(q)~=p then return nil,'该栏位没有携带宠物。' end
 if uuid and Pet.GetUUID(q)~=uuid then return nil,'携带宠物已改变，请重新选择。' end
 local b=Char.GetBattleIndex(q)
 if b>=0 and Battle.GetPos(b,q)>=0 then return nil,'这只宠物仍在战斗中，请稍后操作。' end
 return q
end
function M:skills(q)
 local out={}
 for i=0,9 do local id=Pet.GetSkill(q,i);if id>=0 then out[#out+1]={slot=i,id=id,name=skillName(id)} end end
 return out
end
function M:lessons(category)
 local out={};for _,s in ipairs(D.pets) do if s.category==category then out[#out+1]=s end end;return out
end
function M:learnPet(n,p,slot,uuid,id)
 if not self:ready(n,p) then return false,'请走近宠物技能导师后重新操作。' end
 local s=lessons[id]
 if not s or Tech.GetTechIndex(id)<0 then return false,'无效的宠物技能。' end
 local q,err=self:pet(p,slot,uuid);if not q then return false,err end
 local capacity=math.min(10,math.max(0,get(q,'宠物_技能栏')));local free=false
 for i=0,capacity-1 do
  local known=Pet.GetSkill(q,i)
  if known==id then return false,'这只宠物已经学会此技能，不会重复收费。' end
  if known<0 then free=true end
 end
 if not free then return false,'宠物技能栏已满，请先遗忘一个技能。' end
 if Char.GetGold(p)<s.cost then return false,'魔币不足，需要 '..s.cost..'。' end
 if Pet.AddSkill(q,id)~=1 then return false,'宠物学习失败，未扣除魔币。' end
 local added=-1;for i=0,capacity-1 do if Pet.GetSkill(q,i)==id then added=i;break end end
 if added<0 then return false,'宠物技能校验失败，未扣除魔币。' end
 Char.AddGold(p,-s.cost)
 if not Char.IsDummy(p) then
  local saved,value=pcall(Char.SaveToDb,p)
  if not saved or value~=0 then
   Pet.DelSkill(q,added);Char.AddGold(p,s.cost);Pet.UpPet(p,q);NLG.UpChar(p)
   return false,'保存失败，已撤销本次学习并退还魔币。'
  end
 end
 Pet.UpPet(p,q);NLG.UpChar(p)
 return true,get(q,'CHAR_名字')..' 学会了 '..s.name..'。'
end
local function count(q,id)
 local total=0;for i=0,9 do if Pet.GetSkill(q,i)==id then total=total+1 end end;return total
end
function M:forget(n,p,slot,uuid,skillSlot,id)
 if not self:ready(n,p) then return false,'请走近导师，在非战斗状态下重新操作。' end
 local q,err=self:pet(p,slot,uuid);if not q then return false,err end
 if not uuid or not integer(skillSlot,0,9) or not integer(id,0,2147483647) or Pet.GetSkill(q,skillSlot)~=id then
  return false,'宠物技能已改变，请重新选择。'
 end
 -- A valid native technique is also required to restore it on a save failure.
 if Tech.GetTechIndex(id)<0 then return false,'此技能的招式数据异常，请联系管理员。' end
 local before=count(q,id)
 local ok,result=pcall(Pet.DelSkill,q,skillSlot)
 local removed=count(q,id)==before-1
 local function restore(message)
  if removed then
   local restored,value=pcall(Pet.AddSkill,q,id)
   if not restored or value~=1 or count(q,id)~=before then
    self:logError('Could not restore pet skill '..id..' for pet '..tostring(uuid))
    Pet.UpPet(p,q)
    return false,'宠物技能恢复失败，请立即联系管理员。'
   end
  end
  Pet.UpPet(p,q);return false,message
 end
 if not ok or result~=1 or not removed then return restore('遗忘失败，原技能已保留。') end
 if not Char.IsDummy(p) then
  local saved,value=pcall(Char.SaveToDb,p)
  if not saved or value~=0 then return restore('保存失败，已恢复原技能，请稍后重试。') end
 end
 Pet.UpPet(p,q)
 return true,get(q,'CHAR_名字')..' 已遗忘 '..skillName(id)..'，空技能栏可重新学习。'
end
function M:show(n,p,kind,page,slot,uuid,selected,category)
 self.sessions[p]=nil
 if not self:ready(n,p) then return end
 kind=kind or 'pets';page=page or 1
 local options,actions={},{}
 local function add(label,action) options[#options+1]=label;actions[#actions+1]=action end
 local title='宠物技能导师'
 if kind=='pets' then
  title=title..'\n宠物技能学习与遗忘；先选择携带宠物。'
  for i=0,4 do local q=self:pet(p,i);if q then
   add('宠物'..(i+1)..'：'..get(q,'CHAR_名字'),{kind='petHome',slot=i,uuid=Pet.GetUUID(q)})
  end end
  if #options==0 then title=title..'\n请先携带宠物。' end
  add('查看学习与遗忘规则',{kind='rules'})
  add('关闭',{kind='close'})
 else
  local q,msg=self:pet(p,slot,uuid)
  if not q then say(p,msg);self:show(n,p,'pets');return end
  local list=self:skills(q)
  if kind=='petHome' then
   title=title..'\n所选宠物：'..get(q,'CHAR_名字')
   for _,cat in ipairs(D.categories) do if #self:lessons(cat.id)>0 then
    add('学习'..cat.name:gsub('导师',''),{kind='learning',category=cat.id})
   end end
   add('遗忘宠物技能',{kind='skills'})
   add('返回宠物列表',{kind='pets'})
  elseif kind=='learning' then
   local list=self:lessons(category);local pages=math.max(1,math.ceil(#list/5));page=math.max(1,math.min(page,pages))
   title=title..'\n宠物可学技能 '..page..'/'..pages
   for i=(page-1)*5+1,math.min(page*5,#list) do local s=list[i]
    add(s.name..' ['..s.id..']',{kind='learnConfirm',id=s.id})
   end
   if page>1 then add('上一页',{kind='learnPage',page=page-1}) end
   if page<pages then add('下一页',{kind='learnPage',page=page+1}) end
   add('返回宠物菜单',{kind='petHome'})
  elseif kind=='learnConfirm' then
   local s=selected and lessons[selected.id]
   if not s or s.category~=category then return end
   title='是否为这只宠物学习技能？\n宠物：'..get(q,'CHAR_名字')..'\n技能：'..s.name
    ..'\n费用：'..s.cost..' 魔币\n需要空技能栏；重复学习不收费。'
  elseif kind=='skills' then
   local pages=math.max(1,math.ceil(#list/5));page=math.max(1,math.min(page,pages))
   title=title..'\n'..get(q,'CHAR_名字')..'：选择要遗忘的技能 '..page..'/'..pages
   if #list==0 then title=title..'\n这只宠物没有可遗忘的技能。' end
   for i=(page-1)*5+1,math.min(page*5,#list) do local s=list[i]
    add('技能'..(s.slot+1)..'：'..s.name,{kind='confirm',skillSlot=s.slot,id=s.id})
   end
   if page>1 then add('上一页',{kind='page',page=page-1}) end
   if page<pages then add('下一页',{kind='page',page=page+1}) end
   add('返回宠物菜单',{kind='petHome'})
  elseif kind=='confirm' then
   if not selected or Pet.GetSkill(q,selected.skillSlot)~=selected.id then
    say(p,'宠物技能已改变，请重新选择。');self:show(n,p,'skills',page,slot,uuid);return
   end
   title='是否遗忘以下宠物技能？\n宠物：'..get(q,'CHAR_名字')..'\n技能'..(selected.skillSlot+1)..'：'..skillName(selected.id)
    ..'\n免费遗忘，不能直接撤销。\n重新学习需按导师收费。'
  else return end
 end
 assert(#options<=8,'native selection limit')
 self.sessions[p]={npc=n,player=Char.GetUUID(p),kind=kind,page=page,slot=slot,uuid=uuid,category=category,actions=actions,
  skillSlot=selected and selected.skillSlot,id=selected and selected.id,expires=os.time()+120}
 if kind=='confirm' or kind=='learnConfirm' then
  -- Message windows confirm via a button value, independent of title wrapping
  -- and selection-row offsets. Never interpret their Data as an option index.
  NLG.ShowWindowTalked(p,n,0,YES+NO,kind=='confirm' and CONFIRM_SEQ or LEARN_SEQ,title)
  return
 end
 NLG.ShowWindowTalked(p,n,2,2,SEQ,self:NPC_buildSelectionText(title,options))
end
function M:answer(n,p,seq,button,text)
 local a=self.sessions[p];self.sessions[p]=nil
 if not a or a.npc~=n or a.player~=Char.GetUUID(p) or a.expires<os.time() or not self:ready(n,p) then return end
 if a.kind=='confirm' or a.kind=='learnConfirm' then
  local learning=a.kind=='learnConfirm'
  if seq~=(learning and LEARN_SEQ or CONFIRM_SEQ) then return end
  if button==YES then
   local ok,msg
   if learning then ok,msg=self:learnPet(n,p,a.slot,a.uuid,a.id)
   else ok,msg=self:forget(n,p,a.slot,a.uuid,a.skillSlot,a.id) end
   say(p,msg)
  elseif button~=NO then return end
  self:show(n,p,learning and 'learning' or 'skills',a.page,a.slot,a.uuid,nil,a.category)
  return
 end
 -- Native selection replies use button 0. Cancel/close must never confirm.
 if seq~=SEQ or button~=0 then return end
 local choice=tonumber(text)
 if not integer(choice,1,#a.actions) then return end
 local action=a.actions[choice]
 if action.kind=='pets' then self:show(n,p,'pets')
 elseif action.kind=='petHome' then self:show(n,p,'petHome',1,action.slot or a.slot,action.uuid or a.uuid)
 elseif action.kind=='skills' then self:show(n,p,'skills',1,a.slot,a.uuid)
 elseif action.kind=='learning' then self:show(n,p,'learning',1,a.slot,a.uuid,nil,action.category)
 elseif action.kind=='learnPage' then self:show(n,p,'learning',action.page,a.slot,a.uuid,nil,a.category)
 elseif action.kind=='learnConfirm' then self:show(n,p,'learnConfirm',a.page,a.slot,a.uuid,action,a.category)
 elseif action.kind=='page' then self:show(n,p,'skills',action.page,a.slot,a.uuid)
 elseif action.kind=='confirm' then self:show(n,p,'confirm',a.page,a.slot,a.uuid,action)
 elseif action.kind=='rules' then
  say(p,'这里只教授携带宠物的原生技能，每项1000魔币，需要空技能栏，重复学习不收费。遗忘单个技能免费，学习和遗忘均用是／否确认；遗忘不退还旧费用。人物不能学习宠物来源技能，请找六位人物导师。战斗、摆摊或五宠结算期间不可操作，换宠或技能改变需重新选择。')
  self:show(n,p,'pets')
 end
end
-- The client decodes SKL's technique ID as animation family = ID / 100.
-- Keep the pet-only learned IDs, but execute their identical native ranks.
-- Otherwise family 9104 has no client handler and the animation never ends.
function M:normalizeBattleTechs(b)
 local five=getModule('fivePet')
 for pos=0,19 do
  local q=Battle.GetPlayer(b,pos)
  if q>=0 and (Char.IsPet(q) or (five and five.proxies[q])) then
   for _,prefix in ipairs({'CHAR_Battle','CHAR_Battle2'}) do
    local command=Char.GetData(q,CONST[prefix..'Com1'])
    local id=Char.GetData(q,CONST[prefix..'Com3'])
    if command==CONST.BATTLE_COM.BATTLE_COM_P_SPIRACLESHOT and id>=910400 and id<=910409 then
     Char.SetData(q,CONST[prefix..'Com3'],400+id-910400)
    end
   end
  end
 end
end
function M:onLoad()
 self.sessions={}
 local D=dofile('lua/Modules/sanctuaryData.lua')
 self.npc=self:NPC_createNormal('宠物技能导师',100008,assert(D.positions['宠物技能导师']))
 assert(self.npc>=0,'pet skill tutor creation failed')
 self:NPC_regTalkedEvent(self.npc,function(n,p) self:show(n,p,'pets') end)
 self:NPC_regWindowTalkedEvent(self.npc,Func.bind(self.answer,self))
 self:regCallback('BeforeBattleTurnStartEvent',OrderedCallback(function(b)
  self:normalizeBattleTechs(b);return false
 end,-10000))
 for _,event in ipairs({'LogoutEvent','DropEvent'}) do self:regCallback(event,function(p) self.sessions[p]=nil;return 0 end) end
end
function M:onUnload() self.sessions={} end
return M
