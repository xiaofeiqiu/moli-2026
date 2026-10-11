local R={status='RUNNING',checks={},battles={}}
local M=assert(getModule('gameQoL'))
local T=ModuleBase:createModule('afterBattleProbe'):new();T:load()
local p,b=-1,-1
local stage=1
local started=os.time()
local finished=false
local originalDummy=Char.IsDummy
local originalMessage=NLG.SystemMessage
local messages={}
local weapon,fixtures
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=ok and true or false};assert(ok,label) end
local function get(key) return Char.GetData(p,CONST[key]) end
local function set(key,value) Char.SetData(p,CONST[key],value) end
local function itemData(i,key) return Item.GetData(i,CONST[key]) end
local function finish(err)
 if finished then return end;finished=true
 if err then R.status='FAIL';R.error=tostring(err) else R.status='PASS' end
 if p>=0 then
  if Char.GetBattleIndex(p)>=0 then pcall(Battle.ExitBattle,p) end
  pcall(Char.DelDummy,p);p=-1
 end
 Char.IsDummy=originalDummy;NLG.SystemMessage=originalMessage
 local f=assert(io.open('__OUTPUT__/after_battle_native.json','wb'));f:write(JSON.encode(R));f:close()
end
local function command(msg)
 messages={};check(TalkEvent(p,msg,0,0,0)==0,'command consumed '..msg)
 return table.concat(messages,'\n')
end
local function fixture(slot,current,maximum)
 local i=Item.MakeItem(2001);check(i>=0,'equipment fixture '..slot)
 Char.SetItemIndex(p,slot,i)
 Item.SetData(i,CONST['道具_最大耐久'],maximum);Item.SetData(i,CONST['道具_耐久'],current)
 return i
end
local function clear()
 for slot=0,get('CHAR_道具栏')-1 do
  local i=Char.GetItemIndex(p,slot)
  if i>=0 then Item.Kill(p,i,slot) end
 end
end
local function prepareBags()
 for slot=8,get('CHAR_道具栏')-1 do local i=Char.GetItemIndex(p,slot);if i>=0 then Item.Kill(p,i,slot) end end
 fixtures={}
 for page=0,CONST.EXTBAGPAGE do
  local slot=8+page*20+9
  fixtures[page]={index=fixture(slot,10,100),slot=slot}
 end
end
local function verifyBags(sorted,label)
 for page=0,CONST.EXTBAGPAGE do
  local row=fixtures[page]
  local found=false
  local empty=false
  local lastType,lastId
  for slot=8+page*20,27+page*20 do
   local i=Char.GetItemIndex(p,slot)
   if i==row.index then found=true end
   if sorted then
    if i<0 then empty=true
    else
     check(not empty,'no backpack gaps '..label..'/'..page..'/'..slot)
     local typ,id=itemData(i,'道具_类型'),itemData(i,'道具_ID')
     check(not lastType or typ>lastType or (typ==lastType and id>=lastId),'backpack ordering '..label..'/'..page..'/'..slot)
     lastType,lastId=typ,id
    end
   end
  end
  check(found,'fixture remains on original page '..label..'/'..page)
  if not sorted then check(Char.GetItemIndex(p,row.slot)==row.index,'sort disabled preserves slot '..label..'/'..page) end
  check(itemData(row.index,'道具_耐久')==10,'backpack equipment not repaired '..label..'/'..page)
 end
 check(Char.GetBagPage(p)==CONST.EXTBAGPAGE,'active backpack page preserved '..label)
end
local function begin()
 if stage==2 then
  command('/autorepair off');command('/autosort off')
 end
 prepareBags()
 Item.SetData(weapon,CONST['道具_耐久'],84)
 set('CHAR_等级',20);set('CHAR_经验',0);set('CHAR_体力',50000);set('CHAR_力量',50000)
 NLG.UpChar(p);set('CHAR_血',get('CHAR_最大血'));set('CHAR_魔',get('CHAR_最大魔'))
 b=Battle.PVE(p,p,nil,{1},{20},{0})
 check(b>=0,'actual native battle started '..stage)
 M:maintain(p,true);M:flushAfterBattle()
 check(itemData(weapon,'道具_耐久')==84,'equipment not repaired during combat '..stage)
 verifyBags(false,'in combat '..stage)
end
Char.IsDummy=function(q) if q==p then return false end;return originalDummy(q) end
NLG.SystemMessage=function(q,text,...) if q==p then messages[#messages+1]=text end;return originalMessage(q,text,...) end
T:regCallback('BattleSurpriseEvent',function() return CONST.BATTLE_SurpriseFlag.Normal end)
T:regCallback('DamageCalculateEvent',function(a,d,original,damage,bi)
 if bi==b then return a==p and 999999 or 0 end;return damage
end)
T:regCallback('BattleExitEvent',function(q,bi)
 if q==p then R.battles[#R.battles+1]={stage=stage,battle=bi,queued=M.pendingBattle[p]==true} end
end)
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='AFTER_BATTLE_TEST'})
 check(p>=0,'isolated native player created')
 set('CHAR_账号','AFTER_BATTLE_'..os.time());set('对象_RegistNumber',0)
 check(M:settings(p).autorepair and M:settings(p).autosort,'repair and sort defaults enabled')
 for _,key in ipairs({'autoidentify','autosell','autostack','autoclock'}) do command('/'..key..' off') end
 check(command('/qol'):find('autorepair=on',1,true)~=nil,'qol includes autorepair state')
 check(command('/help autorepair'):find('85%',1,true)~=nil,'repair help documents threshold')
 local current={84,85,90,0,0,84,85,169}
 local maximum={100,100,100,100,0,99,99,200}
 local expected={100,85,90,100,0,99,85,200}
 local equipment={}
 for slot=0,7 do equipment[slot]=fixture(slot,current[slot+1],maximum[slot+1]) end
 local bag=fixture(8,10,100)
 R.boundaries={}
 for slot=0,7 do R.boundaries[slot+1]={index=equipment[slot],equipped=Char.GetItemIndex(p,slot),
  current=itemData(equipment[slot],'道具_耐久'),maximum=itemData(equipment[slot],'道具_最大耐久')} end
 M:maintain(p)
 check(itemData(equipment[0],'道具_耐久')==84,'routine maintenance does not repair before battle exit')
 R.repaired=M:repairEquipment(p)
 for slot=0,7 do R.boundaries[slot+1].after=itemData(equipment[slot],'道具_耐久') end
 check(R.repaired==4,'only strictly below 85 percent equipment repaired')
 for slot=0,7 do
  check(itemData(equipment[slot],'道具_耐久')==expected[slot+1],'durability boundary slot '..slot)
  check(itemData(equipment[slot],'道具_最大耐久')==maximum[slot+1],'maximum durability preserved slot '..slot)
 end
 check(itemData(bag,'道具_耐久')==10,'spare equipment in backpack excluded')
 clear()
 weapon=fixture(CONST['EQUIP_右手'],84,100)
 Char.SwitchBag(p,CONST.EXTBAGPAGE)
 prepareBags()
 set('CHAR_BattleMode',1)
 BattleExitEvent(p,-1,1)
 M:flushAfterBattle()
 check(M.pendingBattle[p]==true and itemData(weapon,'道具_耐久')==84,'exit callback defers while battle state still active')
 set('CHAR_BattleMode',0);set('CHAR_BattleIndex',-1)
 M:flushAfterBattle()
 check(M.pendingBattle[p]==nil and itemData(weapon,'道具_耐久')==100,'deferred exit performs repair once ready')
 verifyBags(true,'deferred exit')
 prepareBags();M:flushAfterBattle()
 verifyBags(false,'no duplicate exit job')
 begin()
 local ended
 local key=T:regCallback(function()
  if finished then return end
  local success,error=xpcall(function()
   if os.time()-started>45 then error('actual battle test timed out') end
   if Char.GetBattleIndex(p)~=b then
    if not ended then ended=os.time() end
    if os.time()-ended<1 or M.pendingBattle[p] then return end
    local durability=itemData(weapon,'道具_耐久')
    check(stage==1 and durability==100 or stage==2 and durability<85,'actual battle respects autorepair switch '..stage)
    verifyBags(stage==1,'actual battle '..stage)
    check(#R.battles>=stage and R.battles[#R.battles].queued,'actual native exit queued upkeep '..stage)
    b=-1
    if stage==1 then stage=2;ended=nil;begin()
    else
     check(reloadModule('gameQoL')~=nil,'QoL reload with saved switches')
     M=assert(getModule('gameQoL'))
     check(not M:settings(p).autorepair and not M:settings(p).autosort,'switches persist through module reload')
     command('/autorepair on');command('/autosort on')
     check(M:settings(p).autorepair and M:settings(p).autosort,'switches re-enable independently')
     finish()
    end
   elseif Battle.IsWaitingCommand(p)==1 then
    set('CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set('CHAR_BattleCom2',10);set('CHAR_BattleCom3',-1)
    set('CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set('CHAR_Battle2Com2',10);set('CHAR_Battle2Com3',-1)
    set('CHAR_BattleMode',3)
   end
  end,debug.traceback)
  if not success then finish(error) end
 end)
 Char.SetLoopEvent(nil,key,p,200)
end,debug.traceback)
if not ok then finish(err) end
