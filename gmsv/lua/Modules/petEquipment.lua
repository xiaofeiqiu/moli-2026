-- Native pet equipment service for clients without a pet inventory page.
local M=ModuleBase:createModule('petEquipment')
-- Actual engine slots, verified with Pet.MoveItem (some legacy CONST labels differ).
local SLOTS={'身体','项圈','晶石','饰品1','饰品2'}
local function get(c,k) local field=assert(CONST[k],k);return Char.GetData(c,field) end
local function item(i,k) local field=assert(CONST[k],k);return Item.GetData(i,field) end
local function integer(n,lo,hi) return type(n)=='number' and n==math.floor(n) and n>=lo and n<=hi end
local function say(p,s) NLG.SystemMessage(p,s) end
local function conflictingAccessory(q,i,place)
 if place~=3 and place~=4 then return false end
 local other=Char.GetItemIndex(q,7-place)
 return other>=0 and item(other,'道具_类型')==item(i,'道具_类型')
end
local function requiredLevel(i)
 local rank=item(i,'道具_等级')
 return rank>1 and (rank-1)*10 or math.max(0,rank)
end
local function wearProblem(q,i,place)
 local name=item(i,'道具_名字')
 local required=requiredLevel(i);local level=get(q,'CHAR_等级')
 if level<required then return name..'需要宠物'..required..'级，当前宠物'..level..'级。' end
 if item(i,'道具_已鉴定')~=1 then return name..'未鉴定，请先鉴定。' end
 if item(i,'道具_耐久')<=0 then return name..'已损坏，请先修理。' end
 if conflictingAccessory(q,i,place) then return '同类型饰品只能穿一件；更换时请先卸下原饰品。' end
end
function M:ready(n,p)
 if n~=self.npc or not Char.IsValidCharIndex(n) or not Char.IsPlayer(p) then return false end
 if get(n,'CHAR_地图类型')~=get(p,'CHAR_地图类型') or get(n,'CHAR_地图')~=get(p,'CHAR_地图')
  or math.max(math.abs(get(n,'CHAR_X')-get(p,'CHAR_X')),math.abs(get(n,'CHAR_Y')-get(p,'CHAR_Y')))>2 then return false end
 if Char.GetBattleIndex(p)>=0 or get(p,'CHAR_BattleMode')~=0 then say(p,'请结束战斗后穿卸宠装。');return false end
 local qol=getModule('gameQoL')
 if qol and qol.stalls and qol.stalls[p] then say(p,'请先结束摆摊。');return false end
 local five=getModule('fivePet');local squad=five and five.active[p]
 if squad and squad.battle then say(p,'请等待五宠战斗结算完成。');return false end
 if Char.GetBagPage(p)~=0 then say(p,'请先切换到背包第0页，并把要穿的宠装放在该页。');return false end
 return true
end
function M:pet(p,slot,uuid)
 if not integer(slot,0,4) then return nil end
 local q=Char.GetPet(p,slot)
 if q<0 or not Char.IsValidCharIndex(q) or not Char.IsPet(q) or Pet.GetOwner(q)~=p then return nil end
 if uuid and uuid~=Pet.GetUUID(q) then return nil end
 local b=Char.GetBattleIndex(q)
 if b>=0 and Battle.GetPos(b,q)>=0 then return nil end
 return q
end
function M:bagItems(p)
 local list={}
 for slot=8,27 do
  local i=Char.GetItemIndex(p,slot)
  if i>=0 then
   local typ=item(i,'道具_类型')
   if typ>=56 and typ<=60 then list[#list+1]={bag=slot,index=i,id=item(i,'道具_ID'),name=item(i,'道具_名字'),type=typ} end
  end
 end
 return list
end
function M:move(n,p,a)
 if not self:ready(n,p) then return false,'请在管理员身边、非战斗状态重新操作。' end
 local q=self:pet(p,a.slot,a.uuid)
 if not q then return false,'携带宠物已改变，请重新选择。' end
 if not integer(a.place,0,4) or not integer(a.bag,8,27) then return false,'无效的道具栏位。' end
 local wearing=a.mode=='wear'
 if not wearing and a.mode~='remove' then return false,'无效的操作。' end
 local source=wearing and p or q;local sourceSlot=wearing and a.bag or a.place
 local dest=wearing and q or p;local destSlot=wearing and a.place or a.bag
 local i=Char.GetItemIndex(source,sourceSlot)
 if i<0 or i~=a.index or item(i,'道具_ID')~=a.id then return false,'道具已移动或改变，请重新选择。' end
 if Char.GetItemIndex(dest,destSlot)>=0 then
  return false,wearing and '这个装备槽已有道具，请先卸下旧装备。' or '背包空位已被占用，请重新操作。'
 end
 local typ=item(i,'道具_类型')
 if typ<56 or typ>60 or Item.GetPetEquipPlace(typ,a.place)~=1 then return false,'道具与宠物装备槽不匹配。' end
 if wearing then
  local problem=wearProblem(q,i,a.place)
  if problem then return false,problem end
 end
 local fromPet,toPet=wearing and 0 or a.slot+1,wearing and a.slot+1 or 0
 local ok=pcall(Pet.MoveItem,p,fromPet,sourceSlot,toPet,destSlot)
 if not ok or Char.GetItemIndex(dest,destSlot)~=i or Char.GetItemIndex(source,sourceSlot)>=0 then
  return false,'原生穿卸未成功，请检查装备条件后重试。'
 end
 if not Char.IsDummy(p) then
  local saved,value=pcall(Char.SaveToDb,p)
  if not saved or value~=0 then
   pcall(Pet.MoveItem,p,toPet,destSlot,fromPet,sourceSlot)
   Pet.UpPet(p,q);NLG.UpChar(p)
   if Char.GetItemIndex(source,sourceSlot)~=i then return false,'保存失败，装备仍在当前栏位，请联系管理员。','save' end
   return false,'保存失败，已撤销本次穿卸。','save'
  end
 end
 Pet.UpPet(p,q);NLG.UpChar(p)
 return true,(wearing and '已穿上：' or '已卸下：')..item(i,'道具_名字')..'。'
end
function M:autoEquip(n,p,slot,uuid)
 if not self:ready(n,p) then return false,'请在管理员身边、非战斗状态重新操作。' end
 local q=self:pet(p,slot,uuid)
 if not q then return false,'携带宠物已改变，请重新选择。' end
 local list=self:bagItems(p);local count=0;local empty=0;local firstProblem
 for place=0,4 do
  if Char.GetItemIndex(q,place)<0 then
   empty=empty+1
   for _,a in ipairs(list) do
    if Char.GetItemIndex(p,a.bag)==a.index and Item.GetPetEquipPlace(a.type,place)==1 then
     local problem=wearProblem(q,a.index,place)
     if problem then firstProblem=firstProblem or problem
     else
      local ok,msg,reason=self:move(n,p,{mode='wear',slot=slot,uuid=uuid,place=place,bag=a.bag,index=a.index,id=a.id})
      if ok then count=count+1;break end
      if reason=='save' then return false,'一键装备已停止；此前已穿上'..count..'件。'..msg end
      firstProblem=firstProblem or (a.name..'：'..msg)
     end
    end
   end
  end
 end
 if count>0 then return true,'已一键穿上'..count..'件宠装，当前装备已刷新。' end
 if empty==0 then return false,'五个装备槽均已装备；更换时请先卸下旧装备。' end
 if #list==0 then return false,'背包第0页没有宠装，请把装备放到该页。' end
 return false,'背包有'..#list..'件宠装，未能穿上：'..(firstProblem or '对应槽位已有装备，请先卸下旧装备。')
end
function M:show(n,p,kind,slot,uuid,page,selected)
 self.sessions[p]=nil
 if not self:ready(n,p) then return end
 kind=kind or 'pets';page=page or 1
 local options,actions={},{}
 local function add(label,a) options[#options+1]=label;actions[#actions+1]=a end
 local title='宠装管理员'
 local q
 if kind=='pets' then
  title=title..'\n免费穿卸；装备放在背包第0页。'
  for k=0,4 do local pet=self:pet(p,k);if pet then
   add('宠物'..(k+1)..'：'..get(pet,'CHAR_名字'),{kind='home',slot=k,uuid=Pet.GetUUID(pet)})
  end end
  add('查看穿卸规则',{kind='rules'});add('关闭',{kind='close'})
 else
  q=self:pet(p,slot,uuid)
  if not q then say(p,'宠物已改变，请重新选择。');self:show(n,p,'pets');return end
  title=title..'\n'..get(q,'CHAR_名字')..'（'..get(q,'CHAR_等级')..'级）'
  if kind=='home' then
   title=title..'\n当前已装备；点击装备可卸下。'
   add('一键装备背包宠装',{kind='auto'})
   add('穿上背包里的宠装',{kind='items'})
   for place=0,4 do
    local i=Char.GetItemIndex(q,place)
    add(SLOTS[place+1]..'：'..(i>=0 and item(i,'道具_名字') or '空（点击选择穿装）'),
     {kind=i>=0 and 'remove' or 'items',place=place,index=i,id=i>=0 and item(i,'道具_ID') or -1})
   end
   add('返回宠物列表',{kind='pets'})
  elseif kind=='items' then
   local list=self:bagItems(p);local pages=math.max(1,math.ceil(#list/5));page=math.max(1,math.min(page,pages))
   title=title..'\n背包第0页宠装 '..page..'/'..pages
   if #list==0 then title=title..'\n该页没有宠装，请先购买或移入。' end
   for k=(page-1)*5+1,math.min(page*5,#list) do local a=list[k];a.kind='places'
    add('背包'..(a.bag-7)..'：'..a.name..'（需宠物'..requiredLevel(a.index)..'级）',a)
   end
   if page>1 then add('上一页',{kind='items',page=page-1}) end
   if page<pages then add('下一页',{kind='items',page=page+1}) end
   add('返回装备菜单',{kind='home'})
  elseif kind=='places' then
   if not selected then return end
   local i=Char.GetItemIndex(p,selected.bag)
   if i<0 or i~=selected.index or item(i,'道具_ID')~=selected.id then say(p,'道具已移动，请重新选择。');self:show(n,p,'items',slot,uuid);return end
   title=title..'\n'..item(i,'道具_名字')..'：选择空装备槽'
   for place=0,4 do if Item.GetPetEquipPlace(item(i,'道具_类型'),place)==1 and Char.GetItemIndex(q,place)<0 and not conflictingAccessory(q,i,place) then
    add('穿到'..SLOTS[place+1],{kind='confirm',mode='wear',place=place,bag=selected.bag,index=i,id=selected.id})
   end end
   if #options==0 then title=title..'\n合适的槽位或同类饰品已占用，请先卸下旧装备。' end
   add('返回背包列表',{kind='items'})
  elseif kind=='confirm' then
   if not selected then return end
   local i=Char.GetItemIndex(selected.mode=='wear' and p or q,selected.mode=='wear' and selected.bag or selected.place)
   if i<0 or i~=selected.index or item(i,'道具_ID')~=selected.id then say(p,'道具已移动，请重新选择。');self:show(n,p,'home',slot,uuid);return end
   title='是否'..(selected.mode=='wear' and '穿上' or '卸下')..'这件宠装？\n宠物：'..get(q,'CHAR_名字')
    ..'\n装备：'..item(i,'道具_名字')..'\n槽位：'..SLOTS[selected.place+1]..'\n免费操作；旧装备需先卸下。'
  else return end
 end
 _G.__petEquipmentWindowSeq=(_G.__petEquipmentWindowSeq or 73400)+1
 local seq=_G.__petEquipmentWindowSeq
 self.sessions[p]={seq=seq,npc=n,player=Char.GetUUID(p),kind=kind,slot=slot,uuid=uuid,page=page,selected=selected,actions=actions,expires=os.time()+120}
 if kind=='confirm' then NLG.ShowWindowTalked(p,n,0,12,seq,title)
 else NLG.ShowWindowTalked(p,n,2,2,seq,self:NPC_buildSelectionText(title,options)) end
end
function M:answer(n,p,seq,button,text)
 local a=self.sessions[p];self.sessions[p]=nil
 if not a or seq~=a.seq or a.npc~=n or a.player~=Char.GetUUID(p) or a.expires<os.time() or not self:ready(n,p) then return end
 if a.kind=='confirm' then
  if button==4 then
   local selected=a.selected;selected.slot=a.slot;selected.uuid=a.uuid
   local _,msg=self:move(n,p,selected);say(p,msg)
  elseif button~=8 then return end
  self:show(n,p,'home',a.slot,a.uuid);return
 end
 if button~=0 then return end
 local choice=tonumber(text);if not integer(choice,1,#a.actions) then return end
 local action=a.actions[choice]
 if action.kind=='close' then return end
 if action.kind=='auto' then
  local _,msg=self:autoEquip(n,p,a.slot,a.uuid);say(p,msg)
  self:show(n,p,'home',a.slot,a.uuid);return
 end
 if action.kind=='rules' then
  say(p,'一键装备按背包第0页顺序填充空槽，保留已穿装备。宠服和宠甲共用身体槽；项圈、晶石各一个槽，饰品两个槽但同类型只能穿一件。免费穿卸，卸下需背包空位；宠装须已鉴定且未损坏，实际条件由原生引擎检查。旧装备先卸下，战斗、摆摊或五宠结算期间不能操作。');self:show(n,p,'pets');return
 end
 if action.kind=='remove' then
  if action.index<0 then say(p,'这个槽位没有装备。');self:show(n,p,'home',a.slot,a.uuid);return end
  local bag
  for k=8,27 do if Char.GetItemIndex(p,k)<0 then bag=k;break end end
  if not bag then say(p,'背包第0页已满，请先留出一个空位。');self:show(n,p,'home',a.slot,a.uuid);return end
  action.kind='confirm';action.mode='remove';action.bag=bag
 end
 self:show(n,p,action.kind,action.slot or a.slot,action.uuid or a.uuid,action.page or 1,action)
end
function M:onLoad()
 self.sessions={}
 local D=dofile('lua/Modules/sanctuaryData.lua')
 self.npc=self:NPC_createNormal('宠装管理员',14019,assert(D.positions['宠装管理员']))
 assert(self.npc>=0,'Pet equipment manager creation failed')
 self:NPC_regTalkedEvent(self.npc,function(n,p) self:show(n,p,'pets') end)
 self:NPC_regWindowTalkedEvent(self.npc,Func.bind(self.answer,self))
 for _,event in ipairs({'LogoutEvent','DropEvent'}) do self:regCallback(event,function(p) self.sessions[p]=nil;return 0 end) end
end
function M:onUnload() self.sessions={} end
return M
