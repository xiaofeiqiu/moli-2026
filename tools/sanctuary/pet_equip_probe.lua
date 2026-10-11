local R={status='RUNNING',checks={},npcs={},production_accounts_used=false,real_account_relogin_verified=false}
local p,q,other=-1,-1,-1
local window
local old={window=NLG.ShowWindowTalked,dummy=Char.IsDummy,save=Char.SaveToDb,move=Pet.MoveItem}
local function get(c,k) local f=assert(CONST[k],k);return Char.GetData(c,f) end
local function set(c,k,v) local f=assert(CONST[k],k);return Char.SetData(c,f,v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
NLG.ShowWindowTalked=function(player,n,kind,buttons,seq,data,...)
 if player==p then window={npc=n,kind=kind,buttons=buttons,seq=seq,data=data} end
 return old.window(player,n,kind,buttons,seq,data,...)
end
local function rows()
 check(window and window.kind==2,'native selection window')
 local s=window.data:gsub('\r\n','\n'):gsub('\\n','\n');local lines={}
 for line in (s..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
 local header=assert(tonumber(lines[1]));local out={}
 for k=header+2,#lines do if lines[k]~='' then out[#out+1]=lines[k] end end
 check(#out<=8,'native eight-row limit');return out
end
local function click(m,label,button)
 local w=assert(window);local index
 if w.kind==0 then
  check(w.buttons==12,'native yes/no buttons')
  window=nil;m:answer(w.npc,p,w.seq,button or (label=='是' and 4 or 8),'');return w
 end
 for k,s in ipairs(rows()) do if s==label or s:sub(1,#label)==label then index=k;break end end
 check(index~=nil,'visible option '..label)
 window=nil;m:answer(w.npc,p,w.seq,button or 0,tostring(index));return w
end
local function home(m)
 window=nil;_G[m.name..'_npc_'..m.npc..'_TalkedEvent'](m.npc,p)
end
local function petHome(m)
 home(m);click(m,'宠物1：')
end
local function choose(m,i,place)
 local bag=Char.GetItemSlot(p,i)
 petHome(m);click(m,'穿上背包里的宠装')
 while true do
  local found=false
  for _,label in ipairs(rows()) do if label:match('^背包'..(bag-7)..'：') then found=true;break end end
  if found then break end
  click(m,'下一页')
 end
 click(m,'背包'..(bag-7)..'：');click(m,'穿到'..place)
 check(m.sessions[p] and m.sessions[p].kind=='confirm','second confirmation required')
end
local function give(id)
 local i=Char.GiveItem(p,id,1,false);check(i>=0,'owned item created '..id)
 Item.SetData(i,CONST['道具_已鉴定'],1);return i
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  local m=assert(getModule('petEquipment'));local n=m.npc
  R.npcs={{name=get(n,'CHAR_名字'),floor=get(n,'CHAR_地图'),x=get(n,'CHAR_X'),y=get(n,'CHAR_Y')}}
  check(get(n,'CHAR_地图')==60003 and get(n,'CHAR_X')==48 and get(n,'CHAR_Y')==26,'manager at sanctuary 48,26')
  check(Map.IsWalkable(0,60003,48,26)==1 and Map.IsWalkable(0,60003,48,27)==1,'walkable manager and south approach')
  p=Char.CreateDummy({mapType=0,floor=60003,x=48,y=27,image=100002,name='PET_EQUIPMENT_TEST'})
  check(p>=0,'isolated player');home(m);check(#rows()==2,'empty pet list offers rules and close')
  q=Char.GivePet(p,3004,1);other=Char.GivePet(p,3004,1)
  R.item_level_constants={}
  for key,value in pairs(CONST) do if type(key)=='string' and key:find('道具_',1,true) and key:find('等级',1,true) then R.item_level_constants[key]=value end end
  check(q>=0 and other>=0,'two owned pets');set(q,'CHAR_等级',200);NLG.UpChar(q)
  local base=get(q,'CHAR_防御力');local gold=Char.GetGold(p)
  local r15=Char.GiveItem(p,700014,1,false);check(r15>=0,'raw shop R15 item created')
  R.raw_r15={identified=Item.GetData(r15,CONST['道具_已鉴定']),rank=Item.GetData(r15,CONST['道具_等级']),durability=Item.GetData(r15,CONST['道具_耐久'])}
  Item.SetData(r15,CONST['道具_已鉴定'],1)
  local fourR15={r15,give(700044),give(700059),give(700074)}
  local r15bag=Char.GetItemSlot(p,r15)
  set(q,'CHAR_等级',20);NLG.UpChar(q)
  Pet.MoveItem(p,0,r15bag,1,0)
  check(Char.GetItemIndex(q,0)<0 and Char.GetItemSlot(p,r15)==r15bag,'native engine refuses R15 at pet level 20')
  local equipped,msg=m:autoEquip(n,p,0,Pet.GetUUID(q))
  check(not equipped and msg:find('背包有4件宠装',1,true) and msg:find('需要宠物140级',1,true) and msg:find('当前宠物20级',1,true),'four R15 items at level 20 report exact pet level requirement')
  for _,i in ipairs(fourR15) do check(Char.GetItemSlot(p,i)>=8,'ineligible R15 remains in inventory') end
  petHome(m);click(m,'穿上背包里的宠装')
  local advertised=false;for _,label in ipairs(rows()) do if label:find('宠服R15（需宠物140级）',1,true) then advertised=true end end
  check(advertised,'inventory lists required pet level on R15')
  set(q,'CHAR_等级',139);NLG.UpChar(q);Pet.MoveItem(p,0,r15bag,1,0)
  check(Char.GetItemIndex(q,0)<0 and Char.GetItemSlot(p,r15)==r15bag,'native engine refuses R15 below level 140')
  set(q,'CHAR_等级',140);NLG.UpChar(q);Pet.MoveItem(p,0,r15bag,1,0)
  check(Char.GetItemIndex(q,0)==r15,'native engine accepts R15 at level 140')
  Pet.MoveItem(p,1,0,0,r15bag);Char.DelItemBySlot(p,r15bag)
  for k=2,4 do Char.DelItemBySlot(p,Char.GetItemSlot(p,fourR15[k])) end
  set(q,'CHAR_等级',200);NLG.UpChar(q)
  petHome(m);click(m,'身体：')
  check(m.sessions[p].kind=='items','empty slot opens the wear inventory')
  local automatic={give(700000),give(700015),give(700030),give(700045),give(700060),give(700064)}
  R.auto_input={}
  for _,a in ipairs(m:bagItems(p)) do
   local allowed={};for place=0,4 do allowed[place+1]=Item.GetPetEquipPlace(a.type,place) end
   R.auto_input[#R.auto_input+1]={bag=a.bag,index=a.index,id=a.id,type=a.type,allowed=allowed}
  end
  petHome(m);check(rows()[1]=='一键装备背包宠装','one-click equip is the first option')
  local originalMove=m.move;R.auto_moves={}
  m.move=function(self,npc,player,a)
   local ok,msg,reason=originalMove(self,npc,player,a);local slots={}
   for place=0,4 do slots[place+1]=Char.GetItemIndex(q,place) end
   R.auto_moves[#R.auto_moves+1]={id=a.id,place=a.place,bag=a.bag,ok=ok,msg=msg,reason=reason,slots=slots}
   return ok,msg,reason
  end
  click(m,'一键装备背包宠装')
  m.move=originalMove
  R.auto_actual={};for place=0,4 do local i=Char.GetItemIndex(q,place);R.auto_actual[place+1]={index=i,id=i>=0 and Item.GetData(i,CONST['道具_ID']) or -1} end
  check(m.sessions[p].kind=='home','automatic equipment returns to current equipment display')
  local slotNames={'身体','项圈','晶石','饰品1','饰品2'}
  local chosen={automatic[1],automatic[3],automatic[4],automatic[5],-1}
  R.auto_equipment={}
  for place=0,4 do
   local i=chosen[place+1];local name=i>=0 and Item.GetData(i,CONST['道具_名字']) or '空（点击选择穿装）'
   check(i>=0 and Char.GetItemIndex(q,place)==i or i<0 and Char.GetItemIndex(q,place)<0,'automatic native equipment in '..slotNames[place+1])
   local displayed=false
   for _,label in ipairs(rows()) do if label==slotNames[place+1]..'：'..name then displayed=true end end
   check(displayed,'fresh actual equipped name '..slotNames[place+1])
   R.auto_equipment[place+1]={slot=slotNames[place+1],name=name}
  end
  check(Char.GetItemSlot(p,automatic[2])>=8,'automatic clothing wins body slot by inventory order')
  check(Char.GetItemSlot(p,automatic[6])>=8,'second same-type accessory remains in inventory')
  click(m,'一键装备背包宠装')
  for place=0,4 do local i=chosen[place+1];check(i>=0 and Char.GetItemIndex(q,place)==i or i<0 and Char.GetItemIndex(q,place)<0,'automatic repeat preserves equipped item '..place) end
  check(Char.GetGold(p)==gold,'automatic equipment is free')
  for k=1,4 do click(m,slotNames[k]..'：');click(m,'是') end
  for _,i in ipairs(automatic) do Char.DelItemBySlot(p,Char.GetItemSlot(p,i)) end
  local unidentified=give(700000);local broken=give(700004);local eligible=give(700015)
  Item.SetData(unidentified,CONST['道具_已鉴定'],0);Item.SetData(broken,CONST['道具_耐久'],0)
  petHome(m);click(m,'一键装备背包宠装')
  check(Char.GetItemIndex(q,0)==eligible,'automatic skips unidentified and broken earlier candidates')
  check(Char.GetItemSlot(p,unidentified)>=8 and Char.GetItemSlot(p,broken)>=8,'automatic preserves skipped candidates')
  click(m,'身体：');click(m,'是')
  for _,i in ipairs({unidentified,broken,eligible}) do Char.DelItemBySlot(p,Char.GetItemSlot(p,i)) end
  local clothing=give(700000);local armor=give(700015);local collar=give(700030)
  local crystal=give(700045);local accessory=give(700060);local accessory2=give(700064)
  local bag=Char.GetItemSlot(p,clothing)
  choose(m,clothing,'身体');click(m,'否')
  check(Char.GetItemIndex(p,bag)==clothing and Char.GetItemIndex(q,0)<0,'cancel preserves clothing and empty pet slot')
  choose(m,clothing,'身体');local stale=click(m,'是')
  check(Char.GetItemIndex(q,0)==clothing and Char.GetItemIndex(p,bag)<0,'actual native wear removes same item from bag')
  check(get(q,'CHAR_防御力')>base,'worn clothing increases actual pet defense')
  m:answer(n,p,stale.seq,4,'');check(Char.GetItemIndex(q,0)==clothing,'duplicate confirmation cannot move item again')
  petHome(m);click(m,'穿上背包里的宠装');click(m,'背包'..(Char.GetItemSlot(p,armor)-7)..'：')
  check(#rows()==1,'occupied body slot offers only return')
  check(Char.GetItemIndex(q,0)==clothing and Char.GetItemSlot(p,armor)>=8,'armor does not overwrite clothing')
  petHome(m);click(m,'身体：');click(m,'是')
  check(Char.GetItemIndex(q,0)<0 and Char.GetItemSlot(p,clothing)>=8,'native removal returns same item')
  check(get(q,'CHAR_防御力')==base,'removal restores actual defense')
  for _,t in ipairs({{armor,'身体',0},{collar,'项圈',1},{crystal,'晶石',2},{accessory,'饰品1',3}}) do
   choose(m,t[1],t[2]);click(m,'是');check(Char.GetItemIndex(q,t[3])==t[1],'native equipment in '..t[2])
  end
  petHome(m);click(m,'穿上背包里的宠装');click(m,'背包'..(Char.GetItemSlot(p,accessory2)-7)..'：')
  check(#rows()==1,'manual wear cannot displace accessory in the other slot')
  check(Char.GetItemIndex(q,3)==accessory and Char.GetItemSlot(p,accessory2)>=8,'original same-type accessory preserved')
  click(m,'返回背包列表');petHome(m);click(m,'饰品1：');click(m,'是')
  choose(m,accessory2,'饰品2');click(m,'是')
  check(Char.GetItemIndex(q,4)==accessory2 and Char.GetItemSlot(p,accessory)>=8,'explicit accessory replacement preserves both owned items')
  check(Char.GetGold(p)==gold,'all wear and removal operations are free')
  petHome(m);click(m,'身体：');click(m,'是')
  -- Old window sequence cannot confirm a later selection, even after another confirmation opens.
  choose(m,clothing,'身体');local previous=window
  home(m);choose(m,armor,'身体');m:answer(n,p,previous.seq,4,'')
  check(Char.GetItemIndex(q,0)<0 and Char.GetItemSlot(p,armor)>=8,'old confirmation cannot confirm new armor')
  choose(m,clothing,'身体');m.sessions[p].expires=os.time()-1;click(m,'是')
  check(Char.GetItemSlot(p,clothing)>=8,'expired confirmation rejected')
  choose(m,clothing,'身体');m.sessions[p].player='different';click(m,'是')
  check(Char.GetItemSlot(p,clothing)>=8,'reused player identity rejected')
  choose(m,clothing,'身体');Char.MovePet(p,0,1);click(m,'是')
  check(Char.GetItemSlot(p,clothing)>=8 and Char.GetItemIndex(q,0)<0 and Char.GetItemIndex(other,0)<0,'changed pet slot rejects wear')
  Char.MovePet(p,0,1)
  choose(m,clothing,'身体');local oldBag=Char.GetItemSlot(p,clothing)
  check(Char.MoveItem(p,oldBag,27,1)==1,'native fixture inventory move');click(m,'是')
  check(Char.GetItemIndex(p,27)==clothing and Char.GetItemIndex(q,0)<0,'moved inventory item rejects stale selection')
  check(Char.MoveItem(p,27,oldBag,1)==1,'restore inventory fixture')
  choose(m,clothing,'身体');Char.Warp(p,0,60003,60,38);click(m,'是')
  check(Char.GetItemSlot(p,clothing)>=8,'remote confirmation rejected');Char.Warp(p,0,60003,48,27)
  choose(m,clothing,'身体');set(p,'CHAR_BattleMode',3);click(m,'是')
  check(Char.GetItemSlot(p,clothing)>=8,'battle mode rejects wear');set(p,'CHAR_BattleMode',0)
  choose(m,clothing,'身体');getModule('gameQoL').stalls[p]=true;click(m,'是')
  check(Char.GetItemSlot(p,clothing)>=8,'stall rejects wear');getModule('gameQoL').stalls[p]=nil
  choose(m,clothing,'身体');getModule('fivePet').active[p]={battle=123};click(m,'是')
  check(Char.GetItemSlot(p,clothing)>=8,'pending five-pet settlement rejects wear');getModule('fivePet').active[p]=nil
  local a={slot=0,uuid=Pet.GetUUID(q),bag=Char.GetItemSlot(p,clothing),index=clothing,id=700000,place=0,mode='wear'}
  Item.SetData(clothing,CONST['道具_已鉴定'],0)
  check(not m:move(n,p,a) and Char.GetItemSlot(p,clothing)>=8,'unidentified clothing rejected');Item.SetData(clothing,CONST['道具_已鉴定'],1)
  Item.SetData(clothing,CONST['道具_耐久'],0)
  check(not m:move(n,p,a) and Char.GetItemSlot(p,clothing)>=8,'broken clothing rejected');Item.SetData(clothing,CONST['道具_耐久'],300)
  a.place=1;check(not m:move(n,p,a),'wrong equipment slot rejected');a.place=0
  a.slot=99;check(not m:move(n,p,a),'invalid pet slot rejected');a.slot=0
  Pet.MoveItem=function() return 0 end
  check(not m:move(n,p,a) and Char.GetItemSlot(p,clothing)>=8,'native move refusal preserves item');Pet.MoveItem=old.move
  Char.IsDummy=function(player) if player==p then return false end;return old.dummy(player) end
  Char.SaveToDb=function(player) if player==p then return -3 end;return old.save(player) end
  check(not m:move(n,p,a),'save failure is reported')
  check(Char.GetItemIndex(p,a.bag)==clothing and Char.GetItemIndex(q,0)<0,'save failure rolls native wear back')
  local saveAttempts=0
  Char.SaveToDb=function(player) if player==p then saveAttempts=saveAttempts+1;return -3 end;return old.save(player) end
  check(not m:autoEquip(n,p,0,Pet.GetUUID(q)),'automatic equipment reports save failure')
  check(saveAttempts==1,'automatic equipment stops after save failure')
  check(Char.GetItemIndex(q,0)<0 and Char.GetItemSlot(p,clothing)>=8 and Char.GetItemSlot(p,armor)>=8,'automatic save failure preserves body and candidates')
  Char.SaveToDb=function(player) if player==p then return 0 end;return old.save(player) end
  check(m:move(n,p,a),'successful save branch (injected for dummy)')
  local remove={slot=0,uuid=Pet.GetUUID(q),bag=a.bag,index=clothing,id=700000,place=0,mode='remove'}
  Char.SaveToDb=function(player) if player==p then return -3 end;return old.save(player) end
  check(not m:move(n,p,remove) and Char.GetItemIndex(q,0)==clothing,'save failure rolls native removal back')
  Char.IsDummy=old.dummy;Char.SaveToDb=old.save
  -- Fill only the visible main bag. Removal must not overwrite its contents.
  local fillers={}
  for k=8,27 do if Char.GetItemIndex(p,k)<0 then local i=give(700004);fillers[#fillers+1]=i end end
  petHome(m);click(m,'身体：')
  check(m.sessions[p].kind=='home' and Char.GetItemIndex(q,0)==clothing,'full main bag blocks removal before confirmation')
  petHome(m);click(m,'穿上背包里的宠装');click(m,'下一页');check(m.sessions[p].page==2,'inventory next page')
  click(m,'上一页');check(m.sessions[p].page==1,'inventory previous page')
  for _,i in ipairs(fillers) do Char.DelItemBySlot(p,Char.GetItemSlot(p,i)) end
  petHome(m);click(m,'身体：');local pending=window
  reloadModule('petEquipment');m=assert(getModule('petEquipment'));n=m.npc
  check(#m.npcList==1 and m.sessions[p]==nil,'reload discards pending confirmation')
  local count,objects=Obj.GetObject(0,60003,48,26);check(count==1 and #objects==1,'reload leaves one manager')
  petHome(m);click(m,'身体：');local fresh=window
  check(fresh.seq~=pending.seq,'window sequences survive module reload')
  m:answer(n,p,pending.seq,4,'')
  check(Char.GetItemIndex(q,0)==clothing,'old pre-reload confirmation rejected')
  petHome(m);click(m,'身体：');click(m,'是')
  check(Char.GetItemIndex(q,0)<0 and Char.GetItemSlot(p,clothing)>=8,'manager remains functional after reload')
  choose(m,clothing,'身体');click(m,'是',0)
  check(Char.GetItemSlot(p,clothing)>=8,'selection reply cannot confirm message window')
  choose(m,clothing,'身体');click(m,'是',2)
  check(Char.GetItemSlot(p,clothing)>=8,'window close cannot confirm wear')
  home(m);click(m,'查看穿卸规则');check(m.sessions[p].kind=='pets','rules return to pet selection')
  home(m);click(m,'关闭');check(m.sessions[p]==nil,'close clears session')
  if Char.SwitchBag(p,1)==1 then
   home(m);check(m.sessions[p]==nil,'other backpack page requires return to main bag');Char.SwitchBag(p,0)
  end
  R.native_slots_verified=true;R.attribute_effect_verified=true

 end,debug.traceback)
 NLG.ShowWindowTalked=old.window;Char.IsDummy=old.dummy;Char.SaveToDb=old.save;Pet.MoveItem=old.move
 if p>=0 then
  local qol=getModule('gameQoL');if qol then qol.stalls[p]=nil end
  local five=getModule('fivePet');if five then five.active[p]=nil end
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end;pcall(Char.DelDummy,p)
 end
 R.status=ok and 'PASS' or 'FAIL';R.error=not ok and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end,0)
