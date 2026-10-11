-- UTF-8 source; the installed runtime is GBK.
local M=ModuleBase:createModule('petSkillUpgrade')
local MENU,CONFIRM=7330,7331
local PRICE=1000
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function integer(v,lo,hi) return type(v)=='number' and v==math.floor(v) and v>=lo and v<=hi end
local function snapshot(q)
 local ids={};for slot=0,9 do ids[slot+1]=Pet.GetSkill(q,slot) end;return ids
end
local function signature(ids) return table.concat(ids,':') end
local ROMAN={'Ⅰ','Ⅱ','Ⅲ','Ⅳ','Ⅴ','Ⅵ','Ⅶ','Ⅷ','Ⅸ','Ⅹ'}
local ASCII={'I','II','III','IV','V','VI','VII','VIII','IX','X'}
local function rankName(name)
 local base,level=name:match('^(.-)%s*LV(%d+)')
 if level then return base:gsub('%s+$',''),tonumber(level),'lv' end
 for rank=10,1,-1 do
  local suffix=ROMAN[rank]
  if name:sub(-#suffix)==suffix then return name:sub(1,-#suffix-1):gsub('[-%s]+$',''),rank,'grade' end
  for _,tail in ipairs({'-'..ASCII[rank],' '..ASCII[rank]}) do
   if name:sub(-#tail)==tail then return name:sub(1,-#tail-1):gsub('%s+$',''),rank,'grade' end
  end
 end
end
function M:catalog()
 self.techs={};self.series={}
 local D=dofile('lua/Modules/skillTrainingData.lua')
 for _,s in ipairs(D.pets) do
  local base,rank,notation=rankName(s.name);local ix=Tech.GetTechIndex(s.id)
  -- BOSS variants (E/EX/ES) are distinct abilities, not higher pet ranks.
  if s.source=='pet' and base and rank and rank>=1 and ix>=0 then
   local key=table.concat({base,Tech.GetData(ix,CONST.TECH_FUNCNAME),Tech.GetData(ix,CONST.TECH_SKILLID),
    Tech.GetData(ix,CONST.TECH_COMMENT),Tech.GetData(ix,CONST.TECH_TARGET),notation,s.id>=700000 and 'copy' or 'native'},':')
   local t={id=s.id,name=s.name,base=base,rank=rank,key=key}
   self.techs[t.id]=t;self.series[key]=self.series[key] or {};table.insert(self.series[key],t)
  end
 end
 for _,list in pairs(self.series) do table.sort(list,function(a,b)
  if a.rank~=b.rank then return a.rank>b.rank end;return a.id<b.id
 end) end
end
function M:ready(n,p)
 if n~=self.npc or not Char.IsValidCharIndex(n) or not Char.IsPlayer(p) then return false end
 if get(n,'CHAR_地图类型')~=get(p,'CHAR_地图类型') or get(n,'CHAR_地图')~=get(p,'CHAR_地图')
  or math.max(math.abs(get(n,'CHAR_X')-get(p,'CHAR_X')),math.abs(get(n,'CHAR_Y')-get(p,'CHAR_Y')))>2 then return false end
 if Char.GetBattleIndex(p)>=0 or get(p,'CHAR_BattleMode')~=0 then return false end
 local qol=getModule('gameQoL');if qol and qol.stalls and qol.stalls[p] then return false end
 local five=getModule('fivePet');local squad=five and five.active[p]
 return not (squad and squad.battle)
end
function M:pet(p,slot,uuid)
 if not integer(slot,0,9) then return nil end
 local q=slot<5 and Char.GetPet(p,slot) or Char.GetPoolPet(p,slot-5)
 if q<0 or not Char.IsValidCharIndex(q) or not Char.IsPet(q) or (slot<5 and Pet.GetOwner(q)~=p)
  or (uuid and Pet.GetUUID(q)~=uuid) then return nil end
 local b=Char.GetBattleIndex(q)
 if b>=0 and Battle.GetPos(b,q)>=0 then return nil end
 return q
end
function M:cost(t)
 local tutor=getModule('petSkillTutor');local guard=tutor and tutor.strongGuardTech and tutor:strongGuardTech(t.id)
 if guard then return guard.cost end
 local ix=Tech.GetTechIndex(t.id)
 return ix>=0 and math.max(0,tonumber(Tech.GetData(ix,CONST.TECH_FORCEPOINT)) or 0) or math.huge
end
function M:quote(p,slot,uuid)
 local q=self:pet(p,slot,uuid);if not q then return nil end
 local ids=snapshot(q);local best={};local mp=math.max(0,get(q,'CHAR_最大魔'))
 for i,id in ipairs(ids) do local t=self.techs[id]
  if t and (not best[t.key] or t.rank>best[t.key].tech.rank) then best[t.key]={tech=t,slot=i-1} end
 end
 local quote={slot=slot,uuid=Pet.GetUUID(q),before=ids,signature=signature(ids),mp=mp,entries={},total=0}
 for _,known in pairs(best) do
  local old=known.tech
  for _,t in ipairs(self.series[old.key]) do
   if t.rank>old.rank and Tech.GetTechIndex(t.id)>=0 and self:cost(t)<=mp then
    local cost=(t.rank-old.rank)*PRICE
    quote.entries[#quote.entries+1]={slot=known.slot,old=old.id,id=t.id,from=old.rank,to=t.rank,base=old.base,cost=cost}
    quote.total=quote.total+cost;break
   end
  end
 end
 table.sort(quote.entries,function(a,b) return a.slot<b.slot end)
 return quote
end
local function sameQuote(current,quoted)
 if not current or not quoted or current.slot~=quoted.slot or current.uuid~=quoted.uuid
  or current.signature~=quoted.signature or current.mp~=quoted.mp or current.total~=quoted.total
  or #current.entries~=#quoted.entries then return false end
 for i,e in ipairs(current.entries) do local old=quoted.entries[i]
  if e.slot~=old.slot or e.old~=old.old or e.id~=old.id or e.cost~=old.cost then return false end
 end
 return true
end
function M:quoteAll(p)
 local quote={pets={},roster={},total=0,count=0,skills=0}
 for slot=0,9 do
  local q=slot<5 and Char.GetPet(p,slot) or Char.GetPoolPet(p,slot-5)
  quote.roster[slot+1]=false
  if q>=0 then
   local one=self:quote(p,slot);if not one then return nil end
   quote.roster[slot+1]=one.uuid;quote.pets[#quote.pets+1]=one
   if #one.entries>0 then
    quote.count=quote.count+1;quote.skills=quote.skills+#one.entries;quote.total=quote.total+one.total
   end
  end
 end
 return quote
end
-- Native AddSkill fills the first empty slot. Fill holes temporarily with a
-- valid no-cost stance, then remove fillers to preserve the exact slot layout.
function M:writeSkills(q,ids)
 local last=0;for i,id in ipairs(ids) do if id>=0 then last=i end end
 assert(last<=math.min(10,math.max(0,get(q,'宠物_技能栏'))),'宠物技能栏异常')
 for slot=9,0,-1 do if Pet.GetSkill(q,slot)>=0 then assert(Pet.DelSkill(q,slot)==1,'删除旧技能失败') end end
 for i=1,last do assert(Pet.AddSkill(q,ids[i]>=0 and ids[i] or 7400)==1,'写入技能失败') end
 for i=last,1,-1 do if ids[i]<0 then assert(Pet.DelSkill(q,i-1)==1,'恢复空技能栏失败') end end
 assert(signature(snapshot(q))==signature(ids),'技能栏校验失败')
end
function M:refresh(p,q,slot)
 Char.UpCharStatus(q)
 if slot<5 then Pet.UpPet(p,q) end -- UpPet rejects bank originals with -5.
 NLG.UpChar(p)
end
function M:upgrade(n,p,quoted,index)
 if not self:ready(n,p) then return false,'请走近升级师，结束战斗、摆摊或五宠结算后重新操作。' end
 if not quoted then return false,'请重新选择宠物。' end
 local q=self:pet(p,quoted.slot,quoted.uuid);local current=q and self:quote(p,quoted.slot,quoted.uuid)
 if not current or current.signature~=quoted.signature or current.mp~=quoted.mp or current.total~=quoted.total
  or #current.entries~=#quoted.entries then return false,'宠物、技能或可用等级已改变，请重新查看报价。' end
 for i,e in ipairs(current.entries) do local old=quoted.entries[i]
  if e.slot~=old.slot or e.old~=old.old or e.id~=old.id or e.cost~=old.cost then
   return false,'升级报价已改变，请重新选择。'
  end
 end
 if index~=nil and not integer(index,1,#current.entries) then return false,'无效的升级选项。' end
 local entries=index and {current.entries[index]} or current.entries
 if #entries==0 then return false,'现有技能已达到可用最高档，或没有可升级的等级；不会收费。' end
 local cost=0;local after={table.unpack(current.before)}
 for _,e in ipairs(entries) do after[e.slot+1]=e.id;cost=cost+e.cost end
 if Char.GetGold(p)<cost then return false,'魔币不足，需要 '..cost..' 魔币；未升级或扣费。' end
 -- Every original must be restorable before beginning the native transaction.
 for _,id in ipairs(current.before) do if id>=0 and Tech.GetTechIndex(id)<0 then
  return false,'原技能数据异常，未升级或扣费，请联系管理员。'
 end end
 local charged=false
 local ok,err=pcall(function()
  self:writeSkills(q,after);Char.AddGold(p,-cost);charged=true
  if not Char.IsDummy(p) then assert(Char.SaveToDb(p)==0,'保存失败') end
 end)
 if not ok then
  local restored,failure=pcall(self.writeSkills,self,q,current.before)
  if charged then Char.AddGold(p,cost) end
  self:refresh(p,q,current.slot)
  if not restored then
   self:logError('Pet upgrade rollback failed for '..tostring(current.uuid)..': '..tostring(failure))
   return false,'升级失败，魔币已退还；技能恢复异常，请立即联系管理员。'
  end
  self:logError('Pet upgrade cancelled: '..tostring(err))
  return false,'升级或保存失败，原技能已恢复，未收取魔币。'
 end
 self:refresh(p,q,current.slot)
 return true,get(q,'CHAR_名字')..' 的 '..#entries..' 项技能升级完成，花费 '..cost..' 魔币。'
end
function M:upgradeAll(n,p,quoted)
 if not self:ready(n,p) then return false,'请走近升级师，结束战斗、摆摊或五宠结算后重新操作。' end
 local current=quoted and self:quoteAll(p)
 if not current or current.total~=quoted.total or current.count~=quoted.count
  or current.skills~=quoted.skills or #current.pets~=#quoted.pets then
  return false,'宠物或升级报价已改变，请重新查看所有宠物报价。'
 end
 for slot=1,10 do if current.roster[slot]~=quoted.roster[slot] then
  return false,'随身或银行宠物已改变，请重新查看所有宠物报价。'
 end end
 for i,one in ipairs(current.pets) do if not sameQuote(one,quoted.pets[i]) then
  return false,'宠物、技能或最大魔力已改变，请重新查看所有宠物报价。'
 end end
 if current.skills==0 then return false,'所有宠物已达可用最高档，或没有可升级的技能；不会收费。' end
 if Char.GetGold(p)<current.total then return false,'魔币不足，需要 '..current.total..' 魔币；全部宠物均未升级或扣费。' end
 local plans={}
 for _,one in ipairs(current.pets) do if #one.entries>0 then
  local q=self:pet(p,one.slot,one.uuid);local after={table.unpack(one.before)};local last=0
  for i,id in ipairs(one.before) do if id>=0 then
   if Tech.GetTechIndex(id)<0 then return false,'原技能数据异常，全部宠物均未升级或扣费，请联系管理员。' end
   last=i
  end end
  if last>math.min(10,math.max(0,get(q,'宠物_技能栏'))) then
   return false,'宠物技能栏异常，全部宠物均未升级或扣费，请联系管理员。'
  end
  for _,e in ipairs(one.entries) do after[e.slot+1]=e.id end
  plans[#plans+1]={pet=q,quote=one,after=after}
 end end
 local touched={};local charged=false
 local ok,err=pcall(function()
  for _,plan in ipairs(plans) do
   touched[#touched+1]=plan;self:writeSkills(plan.pet,plan.after)
  end
  Char.AddGold(p,-current.total);charged=true
  if not Char.IsDummy(p) then assert(Char.SaveToDb(p)==0,'保存失败') end
 end)
 if not ok then
  local restored=true
  for i=#touched,1,-1 do local plan=touched[i]
   local success,failure=pcall(self.writeSkills,self,plan.pet,plan.quote.before)
   if not success then
    restored=false;self:logError('Bulk pet upgrade rollback failed for '..tostring(plan.quote.uuid)..': '..tostring(failure))
   end
  end
  if charged then Char.AddGold(p,current.total) end
  for _,plan in ipairs(touched) do self:refresh(p,plan.pet,plan.quote.slot) end
  self:logError('Bulk pet upgrade cancelled: '..tostring(err))
  if not restored then return false,'全部升级失败，魔币已退还；部分技能恢复异常，请立即联系管理员。' end
  return false,'全部升级或保存失败，原技能已全部恢复，未收取魔币。'
 end
 for _,plan in ipairs(plans) do self:refresh(p,plan.pet,plan.quote.slot) end
 return true,current.count..' 只宠物的 '..current.skills..' 项技能升级完成，共花费 '..current.total..' 魔币。'
end
function M:show(n,p,kind,slot,uuid,page,selected)
 self.sessions[p]=nil
 if not self:ready(n,p) then NLG.SystemMessage(p,'请走近升级师，结束战斗、摆摊或五宠结算后再操作。');return end
 kind=kind or 'pets';page=page or 1
 local labels,actions={},{};local function add(label,action) labels[#labels+1]=label;actions[#actions+1]=action end
 local title='宠物技能升级师';local quote
 if kind=='pets' or kind=='bank' then
  local bank=kind=='bank';title=title..'\n请选择'..(bank and '银行' or '随身')..'宠物；每技能每升一级1000魔币。'
  add('升级所有宠物（随身＋银行）',{kind='allQuote'})
  for i=0,4 do local s=i+(bank and 5 or 0);local q=self:pet(p,s)
   if q then add((bank and '银行宠物' or '宠物')..(i+1)..'：'..get(q,'CHAR_名字'),{kind='quote',slot=s,uuid=Pet.GetUUID(q)}) end
  end
  if #labels==0 then title=title..'\n没有可选择的宠物。' end
  add(bank and '返回随身宠物' or '选择银行宠物',{kind=bank and 'pets' or 'bank'})
  if not bank then add('查看升级规则',{kind='rules'}) end
 elseif kind=='allQuote' or kind=='allConfirm' then
  quote=self:quoteAll(p)
  if not quote then NLG.SystemMessage(p,'宠物状态已改变或仍在战斗中，请稍后重新查看。');self:show(n,p);return end
  if kind=='allQuote' then
   local eligible={};for _,one in ipairs(quote.pets) do if #one.entries>0 then eligible[#eligible+1]=one end end
   local pages=math.max(1,math.ceil(#eligible/4));page=math.max(1,math.min(page,pages))
   title=title..'\n所有宠物（随身五栏＋银行五栏） '..page..'/'..pages
    ..'\n可升级'..quote.count..'只、'..quote.skills..'项，共'..quote.total..'魔币。'
   if quote.count==0 then title=title..'\n没有可升级技能，不会收费。' end
   for i=(page-1)*4+1,math.min(page*4,#eligible) do local one=eligible[i];local q=self:pet(p,one.slot,one.uuid)
    local label=(one.slot>=5 and '银行宠物' or '宠物')..(one.slot%5+1)..'：'..get(q,'CHAR_名字')
     ..'（'..#one.entries..'项/'..one.total..'币）'
    add(label,{kind='quote',slot=one.slot,uuid=one.uuid})
   end
   if page>1 then add('上一页',{kind='allPage',page=page-1}) end
   if page<pages then add('下一页',{kind='allPage',page=page+1}) end
   if quote.count>0 then add('确认升级所有宠物（'..quote.total..'币）',{kind='allConfirm'}) end
   add('返回宠物列表',{kind='pets'})
  else
   if quote.count==0 then self:show(n,p,'allQuote');return end
   title='是否付费升级所有宠物？\n范围：随身五栏＋银行五栏\n可升级：'..quote.count..'只宠物、'..quote.skills..'项技能'
    ..'\n总费用：'..quote.total..' 魔币\n按各宠最大魔力选最高档；无可升级技能不收费。'
    ..'\n一次支付并保存；失败全部恢复。\n选是升级全部，选否返回报价。'
  end
 else
  quote=self:quote(p,slot,uuid)
  if not quote then NLG.SystemMessage(p,'宠物已改变，请重新选择。');self:show(n,p);return end
  local q=self:pet(p,slot,uuid)
  if kind=='quote' then
   local pages=math.max(1,math.ceil(#quote.entries/4));page=math.max(1,math.min(page,pages))
   title=title..'\n'..get(q,'CHAR_名字')..'（满魔'..quote.mp..'） '..page..'/'..pages
    ..'\n可升级'..#quote.entries..'项，共'..quote.total..'魔币；点击技能查看确认。'
   if #quote.entries==0 then title=title..'\n已达可用最高档，或此技能没有后续等级。' end
   for i=(page-1)*4+1,math.min(page*4,#quote.entries) do local e=quote.entries[i]
    add(e.base..' LV'..e.from..'→LV'..e.to..'（'..e.cost..'币）',{kind='confirm',index=i})
   end
   if page>1 then add('上一页',{kind='page',page=page-1}) end
   if page<pages then add('下一页',{kind='page',page=page+1}) end
   if #quote.entries>0 then add('升级本宠全部可升级技能（'..quote.total..'币）',{kind='confirm'}) end
   add('返回宠物列表',{kind=slot>=5 and 'bank' or 'pets'})
  elseif kind=='confirm' then
   local e=selected and quote.entries[selected]
   if selected and not e then return end
   title='是否付费升级宠物技能？\n宠物：'..get(q,'CHAR_名字')
   if e then title=title..'\n'..e.base..' LV'..e.from..' → LV'..e.to..'\n费用：'..e.cost..' 魔币'
   else title=title..'\n升级列表中全部 '..#quote.entries..' 项技能\n总费用：'..quote.total..' 魔币' end
   title=title..'\n只升级现有技能；同系列低档技能保留。\n选是支付，选否返回报价。'
  else return end
 end
 assert(#labels<=8,'native selection limit')
 self.sessions[p]={npc=n,player=Char.GetUUID(p),kind=kind,slot=slot,uuid=uuid,page=page,actions=actions,
  quote=quote,index=selected,expires=os.time()+120}
 if kind=='confirm' or kind=='allConfirm' then NLG.ShowWindowTalked(p,n,0,12,CONFIRM,title)
 else NLG.ShowWindowTalked(p,n,2,2,MENU,self:NPC_buildSelectionText(title,labels)) end
end
function M:answer(n,p,seq,button,data)
 local a=self.sessions[p];self.sessions[p]=nil
 if not a or a.npc~=n or a.player~=Char.GetUUID(p) or a.expires<os.time() or not self:ready(n,p) then return end
 if a.kind=='allConfirm' then
  if seq~=CONFIRM then return end
  if button==4 then local _,msg=self:upgradeAll(n,p,a.quote);NLG.SystemMessage(p,msg)
  elseif button~=8 then return end
  self:show(n,p,'allQuote',nil,nil,a.page);return
 elseif a.kind=='confirm' then
  if seq~=CONFIRM then return end
  if button==4 then local _,msg=self:upgrade(n,p,a.quote,a.index);NLG.SystemMessage(p,msg)
  elseif button~=8 then return end
  self:show(n,p,'quote',a.slot,a.uuid,a.page);return
 end
 if seq~=MENU or button~=0 then return end
 local choice=tonumber(data);if not integer(choice,1,#a.actions) then return end
 local action=a.actions[choice]
 if action.kind=='pets' or action.kind=='bank' then self:show(n,p,action.kind)
 elseif action.kind=='allQuote' then self:show(n,p,'allQuote')
 elseif action.kind=='allPage' then self:show(n,p,'allQuote',nil,nil,action.page)
 elseif action.kind=='allConfirm' then self:show(n,p,'allConfirm',nil,nil,a.page)
 elseif action.kind=='quote' then self:show(n,p,'quote',action.slot,action.uuid)
 elseif action.kind=='page' then self:show(n,p,'quote',a.slot,a.uuid,action.page)
 elseif action.kind=='confirm' then self:show(n,p,'confirm',a.slot,a.uuid,a.page,action.index)
 elseif action.kind=='rules' then
  NLG.SystemMessage(p,'随身五栏和银行五栏均可升级现有技能；第一项升级所有宠物可一次汇总全部十栏，查看总价后确认，一次扣费并保存，写入或保存失败全部恢复；无可升级技能的宠物不收费。每个技能每提升一级1000魔币，先看报价再确认。按满魔可支付的耗魔选同系列最高档，不因当前缺魔降级；单体、强力、超强与BOSS版本不混用。同系列学过多档时只升级已学最高档，低档保留供缺魔回退；已学最高档、无后续等级或无法识别的技能不收费。升级保留技能栏与空栏，也可逐项或升级本宠全部；取消、钱不够或保存失败不收费。战斗、摆摊、五宠结算期间不可用；报价120秒过期，换宠、改技能或满魔变化需重选。')
  self:show(n,p)
 end
end
function M:onLoad()
 self.sessions={};self:catalog()
 local D=dofile('lua/Modules/sanctuaryData.lua')
 self.npc=self:NPC_createNormal('宠物技能升级师',100007,assert(D.positions['宠物技能升级师']))
 assert(self.npc>=0,'Could not create pet skill upgrade tutor')
 self:NPC_regTalkedEvent(self.npc,function(n,p) self:show(n,p) end)
 self:NPC_regWindowTalkedEvent(self.npc,Func.bind(self.answer,self))
 for _,event in ipairs({'LogoutEvent','DropEvent'}) do self:regCallback(event,function(p) self.sessions[p]=nil;return 0 end) end
end
function M:onUnload() self.sessions={} end
return M
