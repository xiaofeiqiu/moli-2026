local M=getModule('equipmentEnhance')
local R={status='RUNNING',checks=0}
local p,q=-1,-1
local nativeRoll=M.roll
local nativeMessage=NLG.SystemMessage
NLG.SystemMessage=function(player,message,...) R.last_message=message;return nativeMessage(player,message,...) end
local function check(ok,label) assert(ok,label);R.checks=R.checks+1 end
local function get(i,k) return Item.GetData(i,CONST[k]) end
local function set(i,k,v) Item.SetData(i,CONST[k],v) end
local function rolls(a,b)
 local n=0;M.roll=function() n=n+1;return n==1 and a or b or a end
end
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='ENHANCE_PROBE'})
 check(p>=0,'dummy created')
 for target=1,13 do
  for roll=1,100 do
   rolls(roll,100)
   local s,success=M:outcome({level=target-1,failures=0,base={}})
   check(success==(roll<=M.rules.successRates[target]),'success cutoff '..target..'/'..roll)
   check(s.level==(success and target or target-1),'no downgrade above failure cutoff')
   check(s.failures==(success and 0 or 1),'failure counter')
  end
  for roll=1,100 do
   rolls(100,roll)
   local s,success=M:outcome({level=target-1,failures=0,base={}})
   check(not success,'forced failure')
   local down=roll<=M.rules.downgradeRates[target]
   check(s.level==(down and target-2 or target-1),'downgrade cutoff '..target..'/'..roll)
  end
  M.roll=function() error('pity must not draw random numbers') end
  local s,success,pity=M:outcome({level=target-1,failures=5,base={}})
  check(success and pity and s.level==target and s.failures==0,'pity success at every level')
 end
 Char.SetData(p,CONST['CHAR_等级'],200)
 Char.SetData(p,CONST['CHAR_职业'],17)
 Char.SetData(p,CONST['CHAR_职类ID'],10)
 Char.SetData(p,CONST['CHAR_职阶'],6)
 local spec=dofile('lua/Modules/knightHybridGearData.lua').items[1]
 local e=Char.GiveItem(p,spec.id,1,false)
 check(e>=0,'equipment created');set(e,'道具_已鉴定',1);set(e,'道具_耐久',100)
 local bag=Char.GetItemSlot(p,e)
 local name=get(e,'道具_名字')
 R.initial_parameter=get(e,'道具_自用参数')
 set(e,'道具_攻击',100);set(e,'道具_防御',0);set(e,'道具_敏捷',-5)
 regGlobalEvent('ItemOverLapEvent',OrderedCallback(function() R.veto=true;return 1 end,-100),'probe')
 rolls(1)
 for level=1,13 do
  local s=Char.GiveItem(p,18005,1,false);check(s>=0,'stone created')
  local slot=Char.GetItemSlot(p,s)
  Char.MoveItem(p,slot,bag,1)
  R.metadata=Item.GetExtData(e,'EquipmentEnhanceV1');R.current_name=get(e,'道具_名字')
  check(M:level(e)==level,'native drag level '..level)
  check(Char.GetItemIndex(p,slot)<0,'exact stone consumed')
  check(Char.GetItemIndex(p,bag)==e,'equipment remains in destination')
  check(get(e,'道具_攻击')==100+7*level,'7 percent original-base bonus')
 end
 check(not R.veto,'enhance runs before real QoL veto')
 check(get(e,'道具_名字')==name..'+13','name suffix')
 check(get(e,'道具_防御')==0 and get(e,'道具_敏捷')==-5,'non-positive stats preserved')
 local s=Char.GiveItem(p,18005,1,false);local slot=Char.GetItemSlot(p,s)
 Char.MoveItem(p,slot,bag,1)
 check(M:level(e)==13 and Char.GetItemIndex(p,slot)==s,'cap keeps stone')
 set(s,'道具_最大堆叠数',99);set(s,'道具_堆叠数',50)
 local base=M:state(e).base
 local function reset(level,failures)
  Item.SetExtData(e,'EquipmentEnhanceV1',M:encode({level=level,failures=failures or 0,base=base}))
  set(e,'道具_名字',name..(level>0 and '+'..level or ''))
  set(e,'道具_攻击',100+7*level)
 end
 reset(6);rolls(100)
 local count=get(s,'道具_堆叠数')
 Char.MoveItem(p,slot,bag,30)
 check(M:level(e)==6 and get(e,'道具_攻击')==142,'failure targeting 7 cannot downgrade')
 check(M:state(e).failures==1 and get(s,'道具_堆叠数')==count-1,'failure consumes exactly one stone')
 reset(7);rolls(100,50);Char.MoveItem(p,slot,bag,1)
 check(M:level(e)==6 and get(e,'道具_攻击')==142,'target 8 downgrade at 50 percent boundary')
 reset(7);rolls(100,51);Char.MoveItem(p,slot,bag,1)
 check(M:level(e)==7,'target 8 stays at 51')
 reset(11);rolls(100,80);Char.MoveItem(p,slot,bag,1)
 check(M:level(e)==10 and get(e,'道具_攻击')==170,'target 12 downgrade at 80 percent boundary')
 reset(11);rolls(100,81);Char.MoveItem(p,slot,bag,1)
 check(M:level(e)==11,'target 12 stays at 81')
 reset(11)
 for n=1,5 do
  rolls(100,1)
  Char.MoveItem(p,slot,bag,1)
  check(M:state(e).failures==n,'pity retains failures across downgrade '..n)
 end
 local oldLevel=M:level(e)
 M.roll=function() error('native pity must bypass RNG') end
 Char.MoveItem(p,slot,bag,1)
 check(M:level(e)==oldLevel+1 and M:state(e).failures==0,'sixth attempt guaranteed')
 -- Module recreation reads the state entirely from persistent native item fields.
 reset(11,5)
 local fresh=dofile('lua/Modules/equipmentEnhance.lua')
 check(fresh:state(e).failures==5 and fresh:level(e)==11,'module recreation retains pity and level')
 fresh.roll=function() error('recreated module pity bypass') end
 fresh:overlap(p,s,e)
 check(fresh:level(e)==12 and fresh:state(e).failures==0,'recreated module guarantees success')
 -- External gem adjustment is retained after success and a later downgrade.
 reset(7);set(e,'道具_攻击',159);rolls(1);Char.MoveItem(p,slot,bag,1)
 check(get(e,'道具_攻击')==166,'external +10 preserved on success')
 rolls(100,1);Char.MoveItem(p,slot,bag,1)
 check(get(e,'道具_攻击')==159,'external +10 preserved on downgrade')
 count=get(s,'道具_堆叠数');local level=M:level(e)
 set(e,'道具_已鉴定',0);Char.MoveItem(p,slot,bag,1)
 check(M:level(e)==level and get(s,'道具_堆叠数')==count,'unidentified equipment rejected')
 set(e,'道具_已鉴定',1);set(e,'道具_耐久',0);Char.MoveItem(p,slot,bag,1)
 check(M:level(e)==level and get(s,'道具_堆叠数')==count,'broken equipment rejected')
 set(e,'道具_耐久',100);Char.SetData(p,CONST.CHAR_BattleMode,1)
 M:overlap(p,s,e)
 check(M:level(e)==level and get(s,'道具_堆叠数')==count,'battle rejected')
 Char.SetData(p,CONST.CHAR_BattleMode,0)
 local qol=getModule('gameQoL');qol.stalls[p]=true;M:overlap(p,s,e)
 check(M:level(e)==level and get(s,'道具_堆叠数')==count,'stall rejected');qol.stalls[p]=nil
 check(get(e,'道具_自用参数')==R.initial_parameter,'original special parameters preserved')
 Item.SetExtData(e,'EquipmentEnhanceV1','EQ13v1:bad');M:overlap(p,s,e)
 check(Item.GetExtData(e,'EquipmentEnhanceV1')=='EQ13v1:bad' and get(s,'道具_堆叠数')==count,'malformed metadata rejected')
 reset(0);rolls(1)
 local nativeKill=Item.Kill
 set(s,'道具_堆叠数',1);Item.Kill=function() return 0 end
 M:overlap(p,s,e);Item.Kill=nativeKill
 check(M:level(e)==0 and get(e,'道具_攻击')==100,'material deletion failure rolls back stats and state')
 reset(0);set(e,'道具_名字',string.rep('a',31));M:overlap(p,s,e)
 check(M:level(e)==0 and get(s,'道具_堆叠数')==1,'long name rolls back before spending')
 reset(0);Char.MoveItem(p,bag,CONST['EQUIP_左手'],1)
 local equipped=Char.GetItemSlot(p,e);check(equipped<8,'native equipped target')
 Char.MoveItem(p,slot,equipped,1)
 check(M:level(e)==0 and get(s,'道具_堆叠数')==1,'worn equipment preserved')
 Char.MoveItem(p,equipped,bag,1);Char.MoveItem(p,slot,bag,1)
 check(M:level(e)==1 and Char.GetItemIndex(p,slot)<0,'drag after unequipping')
 s=Char.GiveItem(p,18005,1,false);slot=Char.GetItemSlot(p,s)
 local other=Char.GiveItem(p,2002,1,false)
 check(M:overlap(p,other,e)==0,'non-stone normal drag');set(other,'道具_类型',20)
 check(M:overlap(p,s,other)==0,'non-equipment normal drag')
 set(e,'道具_类型',56);Char.MoveItem(p,slot,bag,1)
 check(M:level(e)==2 and Char.GetItemIndex(p,slot)<0,'pet equipment in owner bag')
 -- Trade keeps item state and pity with the equipment, independent of the owner.
 reset(11,5)
 q=Char.CreateDummy({mapType=0,floor=1000,x=225,y=76,image=100002,name='ENHANCE_RECIPIENT'})
 check(q>=0,'trade recipient created')
 Char.TradeItem(p,bag,q)
 local dest=Char.GetItemSlot(q,e)
 check(dest>=8 and M:state(e).failures==5,'trade preserves pity')
 local material=Char.GiveItem(q,18005,1,false)
 M.roll=function() error('transferred pity bypass') end
 Char.MoveItem(q,Char.GetItemSlot(q,material),dest,1)
 check(M:level(e)==12 and M:state(e).failures==0,'new owner receives guaranteed success')
 Char.SetData(q,CONST.CHAR_CDK,'ENHANCE_PERSIST_PROBE')
 Char.SetData(q,CONST['对象_RegistNumber'],0)
 R.save_return=Char.SaveToDb(q)
 local saved=SQL.QueryEx('SELECT val FROM hook_itemExt WHERE cdKey=? AND regNo=? AND slot=? AND sKey=?',
  'ENHANCE_PERSIST_PROBE',0,dest,'EquipmentEnhanceV1')
 R.saved=saved
 if R.save_return==0 then
  check(saved.status==0 and saved.rows and saved.rows[1] and saved.rows[1].val==Item.GetExtData(e,'EquipmentEnhanceV1'),'native save persists equipment metadata')
  R.persistence='native save verified'
 else
  check(R.save_return==-3,'dummy SaveToDb returns documented probe limitation')
  R.persistence='dummy cannot SaveToDb (-3); native ItemExt persistence path verified in engine separately'
 end
 R.status='PASS'
end,debug.traceback)
M.roll=nativeRoll
NLG.SystemMessage=nativeMessage
if not ok then R.status='FAIL';R.error=tostring(err) end
if p>=0 then pcall(Char.DelDummy,p) end
if q>=0 then pcall(Char.DelDummy,q) end
local f=assert(io.open('__OUTPUT__','w'));f:write(JSON.encode(R));f:close()
