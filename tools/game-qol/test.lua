local R={status='RUNNING',checks={},messages={},constants={}}
local p=-1
local oldMessage=NLG.SystemMessage
local oldPlayers=NLG.GetPlayer
local oldDummy=Char.IsDummy
local M
local function check(ok,label)
 R.checks[#R.checks+1]={name=label,pass=ok and true or false};assert(ok,label)
end
local function send(msg) check(TalkEvent(p,msg,0,0,0)==0,'chat consumed '..msg) end
local function n(i,key) return Item.GetData(i,CONST[key]) end
local function c(key) return Char.GetData(p,CONST[key]) end
local function item(id,slot,count,price)
 local i=Item.MakeItem(id);check(i>=0,'make '..id..' at '..slot)
 Char.SetItemIndex(p,slot,i);check(Char.GetItemIndex(p,slot)==i,'attach at '..slot)
 if count then Item.SetData(i,CONST['道具_堆叠数'],count) end
 if price then Item.SetData(i,CONST['道具_价格'],price) end
 return i
end
local function clear()
 for slot=8,87 do local i=Char.GetItemIndex(p,slot);if i>=0 then check(Item.Kill(p,i,slot)==1,'clear '..slot) end end
end
local function total(page,id)
 local t=0;for slot=8+20*page,27+20*page do local i=Char.GetItemIndex(p,slot)
  if i>=0 and n(i,'道具_ID')==id then t=t+n(i,'道具_堆叠数') end end;return t
end
local function write()
 NLG.SystemMessage=oldMessage;NLG.GetPlayer=oldPlayers;Char.IsDummy=oldDummy
 if p>=0 then pcall(Char.DelDummy,p) end
 local f=assert(io.open('__OUTPUT__/test_result.json','wb'));f:write(JSON.encode(R));f:close()
end
NLG.SystemMessage=function(player,text,...)
 R.messages[#R.messages+1]=text
 return oldMessage(player,text,...)
end
local ok,err=xpcall(function()
 M=assert(getModule('gameQoL'))
 check(M.signatures~=nil,'module onLoad completes')
 check(getModule('fivePet')~=nil and getModule('skillLibrary')~=nil and getModule('knightHybridGear')~=nil,'coexists with current gameplay modules')
 for key,v in pairs(CONST) do if key:match('Trade') or key:match('交易') or key:match('Window') or key:match('Work') or key:match('Stall') then R.constants[key]=v end end
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='QOL_NATIVE_TEST'})
 check(p>=0,'isolated test player created')
 check(CONST.EXTBAGPAGE==3 and c('CHAR_道具栏')==88,'four native backpacks each with twenty slots')
 Char.SetData(p,CONST['CHAR_道具栏'],28)
 M:expandBags(p);check(c('CHAR_道具栏')==88,'old twenty-slot character expands to all four backpacks')
 check(M:settings(p).autoidentify and M:settings(p).autosell and M:settings(p).autoclock and M:settings(p).autostack,'requested automatic features enabled by default')
 for _,key in ipairs({'autoidentify','autosell','autoclock','autostack'}) do send('/'..key..' off');check(not M:settings(p)[key],'toggle disables '..key) end
 local D=dofile('lua/Modules/gameQoLData.lua')
 local ids={};for id in pairs(D.stackIds) do ids[#ids+1]=id end;table.sort(ids)
 local material
 for _,id in ipairs(ids) do local idx=Data.ItemsetGetIndex(id)
  if idx>=0 and Data.ItemsetGetData(idx,CONST.ITEMSET_TYPE)==29 then material=id;break end end
 check(material~=nil,'native material fixture found')
 R.material=material
 for page=0,3 do
  send('/backpack '..page);check(Char.GetBagPage(p)==page,'page '..page..' selected')
  local i=Char.GiveItem(p,material+0,1,false);check(i>=0,'native item acquisition on page '..page)
  local exists=false;for s=8+20*page,27+20*page do if Char.GetItemIndex(p,s)==i then exists=true end end
  check(exists,'new item stored in selected page '..page)
 end
 send('/backpack 3')
 for _,msg in ipairs({'/backpack -1','/backpack 4','/backpack 1.5','/backpack 1 extra','/backpack nope'}) do
  send(msg);check(Char.GetBagPage(p)==3,'invalid input preserves page '..msg)
 end
 send('/backpack');check(TalkEvent(p,'ordinary chat',0,0,0)==1,'ordinary chat preserved')
 check(TalkEvent(p,'/backpack!',0,0,0)==1,'malformed unrelated command preserved')
 clear()
 local a=item(material,68,600);local b=item(material,75,500)
 check(n(a,'道具_最大堆叠数')==999,'new native material stack limit 999')
 Item.SetData(a,CONST['道具_最大堆叠数'],20);M:normalize(a)
 check(n(a,'道具_最大堆叠数')==999,'old instance upgraded to new stack limit')
 send('/stack');check(total(3,material)==1100,'page three stack preserves all 1100 units')
 check(n(a,'道具_堆叠数')==999 and n(b,'道具_堆叠数')==101,'native stack cap and overflow respected on page three')
 local equip=item(2001,70);local equip2=item(2001,72)
 check(n(equip,'道具_最大堆叠数')==1 and not M:sameStack(equip,equip2),'equipment remains individual')
 Item.SetData(equip2,CONST['道具_耐久'],100)
 local eqStat=n(equip,'道具_攻击');local eqDura=n(equip2,'道具_耐久')
 local diff=item(material,74,10,501)
 check(not M:sameStack(a,diff),'differently priced items are never merged')
 Item.SetData(diff,CONST['道具_刻印'],'QOL_UNIQUE')
 check(not M:sameStack(a,diff),'stamped instance never merged')
 send('/sort')
 check(total(3,material)==1110,'sort preserves counted material including different price')
 check(n(equip,'道具_攻击')==eqStat and n(equip2,'道具_耐久')==eqDura,'sort preserves equipment stats and durability')
 check(Char.GetItemIndex(p,68)==equip and Char.GetItemIndex(p,69)==equip2,'sort uses type order and compacts gaps')
 local spare=item(material,8,2)
 send('/sort');check(Char.GetItemIndex(p,8)==spare,'sort current page leaves other pages alone')
 send('/sort all');check(total(0,material)==2 and total(3,material)==1110,'sort all retains page boundaries')
 check(Char.GetBagPage(p)==3,'sort all retains active page')
 Item.SetData(equip,CONST['道具_已鉴定'],0);Item.SetData(spare,CONST['道具_已鉴定'],0)
 send('/identify');check(n(equip,'道具_已鉴定')==1 and n(spare,'道具_已鉴定')==1,'manual identify reaches inactive backpacks')
 Item.SetData(equip,CONST['道具_已鉴定'],0)
 M:maintain(p);check(n(equip,'道具_已鉴定')==0,'automatic identification disabled')
 send('/autoidentify on');check(n(equip,'道具_已鉴定')==1,'automatic identify handles existing inventory')
 clear()
 local stone=item(123020,68,4,120)
 local fake=item(material,8,2,120);Item.SetData(fake,CONST['道具_名字'],'魔石')
 local before=Char.GetGold(p)
 send('/sellstones');check(Char.GetGold(p)==before+480,'stone sale pays exact unit value times quantity')
 check(Char.GetItemIndex(p,68)<0 and Char.GetItemIndex(p,8)==fake,'sale removes only genuine native magic stone')
 stone=item(123020,68,3,100)
 Char.SetData(p,CONST['对象_金币'],D.goldLimit-250)
 send('/sellstones');check(Char.GetGold(p)==D.goldLimit-250 and Char.GetItemIndex(p,68)==stone,'insufficient gold capacity retains entire stack')
 Char.SetData(p,CONST['对象_金币'],0)
 Item.SetData(stone,CONST['道具_价格'],0);send('/sellstones')
 check(Char.GetItemIndex(p,68)==stone,'unpriced stone retained')
 Item.SetData(stone,CONST['道具_价格'],100);M:maintain(p)
 check(Char.GetItemIndex(p,68)==stone,'automatic selling disabled')
 send('/autosell on');check(Char.GetItemIndex(p,68)<0 and Char.GetGold(p)==300,'automatic sale enabled and pays player')
 stone=item(123020,68,2,100)
 M.stalls[p]=true;M:maintain(p);send('/sellstones')
 check(Char.GetItemIndex(p,68)==stone,'automatic and manual sale blocked during stall')
 M.stalls[p]=nil;Char.SetData(p,CONST.CHAR_BattleMode,1);M:maintain(p);send('/sort');send('/backpack 0')
 check(Char.GetItemIndex(p,68)==stone and Char.GetBagPage(p)==3,'inventory blocked during combat')
 Char.SetData(p,CONST.CHAR_BattleMode,0);Char.SetData(p,CONST.CHAR_BattleIndex,-1)
 local pet=Char.GivePet(p,3004,0);check(pet>=0,'native pet fixture created')
 Char.SetData(pet,CONST['CHAR_等级'],25);Pet.UpPet(p,pet)
 Char.SetData(pet,CONST['CHAR_升级点'],7)
 local bp={};for _,key in ipairs({'CHAR_体力','CHAR_力量','CHAR_强度','CHAR_速度','CHAR_魔法','CHAR_升级点','CHAR_经验'}) do bp[key]=Char.GetData(pet,CONST[key]) end
 send('/petbp 0');send('/petmax 0')
 for art=1,5 do check(Pet.GetArtRank(pet,art)>=Pet.FullArtRank(pet,art),'species growth at maximum '..art) end
 check(Char.GetData(pet,CONST['CHAR_等级'])==25,'pet maximum preserves level')
 for key,value in pairs(bp) do check(Char.GetData(pet,CONST[key])==value,'pet maximum preserves '..key) end
 send('/petmax all');send('/petmax 5');send('/petmax -1');send('/petmax 1');send('/petbp all')
 Char.SetData(p,CONST['CHAR_卡时'],3600);send('/autoclock on')
 check(Char.IsFeverTime(p)==1,'automatic clock enables native fever double XP state')
 send('/autoclock off');check(Char.IsFeverTime(p)==0,'automatic clock off stops fever')
 send('/clock on');check(Char.IsFeverTime(p)==1,'manual native clock')
 send('/clock off');M:maintain(p);check(Char.IsFeverTime(p)==0,'manual clock off persists through maintenance')
 Char.SetData(p,CONST['CHAR_卡时'],0);send('/clock on');check(Char.IsFeverTime(p)==0,'no fever activation without card time')
 send('/qol');send('/help');send('/where')
 check(TalkEvent(p,'/fight extra',0,0,0)==0,'existing fight command remains functional')
 local persisted=M:settings(p)
 reloadModule('gameQoL');M=assert(getModule('gameQoL'))
 local cfg=M:settings(p)
 check(cfg.autosell==persisted.autosell and cfg.autoidentify==persisted.autoidentify and cfg.autoclock==persisted.autoclock,'toggles persist across module reload')
 check(TalkEvent(p,'/qol',0,0,0)==0,'commands continue after module reload')
 Char.SetData(p,CONST['CHAR_账号'],'QOL_PERSIST_WITNESS')
 Char.SetData(p,CONST['对象_RegistNumber'],0)
 check(M:saveSettings(p,persisted),'settings saved for actual test account identity')
 Char.SaveToDb(p)
 local sql=SQL.QueryEx('SELECT sKey,val,valType FROM hook_charaext WHERE cdKey=? AND regNo=0','QOL_PERSIST_WITNESS')
 check(sql.status==0 and sql.rows and #sql.rows>=1,'automatic toggles written through native SQL to isolated database')
 R.saved=sql.rows
 -- Exercise the real scheduler with only this isolated player exposed to it.
 NLG.GetPlayer=function() return {p} end;Char.IsDummy=function(x) if x==p then return false end;return oldDummy(x) end
 clear();Char.SetData(p,CONST['对象_金币'],0)
 stone=item(123020,68,3,150)
 local unid=item(2001,8);Item.SetData(unid,CONST['道具_已鉴定'],0)
 local done=false
 M:AddInterval(2600,function()
  if done then return end;done=true
  local success,error=xpcall(function()
   check(Char.GetItemIndex(p,68)<0 and Char.GetGold(p)==450,'real periodic automatic stone selling')
   check(n(unid,'道具_已鉴定')==1,'real periodic automatic identification')
   R.status='PASS'
  end,debug.traceback)
  if not success then R.status='FAIL';R.error=tostring(error) end
  write()
 end,0)
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err);write() end
