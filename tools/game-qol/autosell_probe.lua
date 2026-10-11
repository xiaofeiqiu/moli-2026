local R={status='RUNNING',checks={},messages={},production_database_modified=false}
local M=assert(getModule('gameQoL'))
local p=-1
local oldMessage=NLG.SystemMessage
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function create(id,slot,amount)
 local i=Item.MakeItem(id);check(i>=0,'create '..id)
 Char.SetItemIndex(p,slot,i)
 Item.SetData(i,CONST['道具_堆叠数'],amount or 1)
 return i
end
local function gold(value) Char.AddGold(p,value-Char.GetGold(p)) end
local function clear()
 for slot=8,87 do local i=Char.GetItemIndex(p,slot);if i>=0 then Item.Kill(p,i,slot) end end
end
NLG.SystemMessage=function(q,text,...) if q==p then R.messages[#R.messages+1]=text end;return oldMessage(q,text,...) end
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='AUTOSELL_PROBE'})
 check(p>=0,'isolated dummy created')
 Char.SetData(p,CONST['CHAR_账号'],'AUTOSELL_PROBE_'..os.time())
 Char.SetData(p,CONST['对象_RegistNumber'],0)
 Char.SetData(p,CONST['CHAR_道具栏'],88)
 local cfg=assert(M:settings(p))
 check(cfg.autosort and cfg.autosell and cfg.autoidentify,'sort sell identify default on')
 cfg.autosort=false;cfg.autostack=false;cfg.autoclock=false;cfg.autorepair=false
 local definitions=dofile('lua/Modules/gameQoLData.lua')
 local count=0;for _ in pairs(definitions.stoneIds) do count=count+1 end
 check(count==101,'all 101 ordinary stone definitions included')
 check(not definitions.stoneIds[60458] and not definitions.stoneIds[950073],'quest stones excluded')
 for _,id in ipairs({18005,18006,45140,123020}) do
  check(definitions.stoneIds[id],'stone whitelist '..id)
  clear();local item=create(id,8,1)
  Item.SetData(item,CONST['道具_已鉴定'],1)
  Item.SetData(item,CONST['道具_价格'],12)
  gold(0)
  local sold,earned=M:sellStones(p)
  check(sold==1 and earned==12 and Char.GetGold(p)==12 and Char.GetItemIndex(p,8)<0,'manual sale '..id)
 end
 clear();gold(0)
 local stone=create(18006,28,3);Item.SetData(stone,CONST['道具_已鉴定'],0)
 local unit=Item.GetData(stone,CONST['道具_价格'])
 local quest=create(60458,8);Item.SetData(quest,CONST['道具_已鉴定'],1)
 Char.SetData(p,CONST['CHAR_BattleMode'],1)
 M.pendingBattle[p]=true;M:flushAfterBattle()
 check(Char.GetItemIndex(p,28)==stone and Char.GetGold(p)==0 and M.pendingBattle[p],'sale deferred during battle')
 Char.SetData(p,CONST['CHAR_BattleMode'],0);Char.SetData(p,CONST['CHAR_BattleIndex'],-1)
 M:flushAfterBattle()
 check(Char.GetItemIndex(p,28)<0 and Char.GetGold(p)==unit*3 and not M.pendingBattle[p],'after battle identifies and sells normal stones across bags')
 check(Char.GetItemIndex(p,8)==quest,'quest stone retained')
 clear();stone=create(18006,8)
 Item.SetData(stone,CONST['道具_已鉴定'],1)
 gold(definitions.goldLimit)
 local sold,earned,full=M:sellStones(p)
 check(sold==0 and earned==0 and full and Char.GetItemIndex(p,8)==stone,'gold cap retains stone')
 gold(0);cfg.autosell=false
 M:maintain(p,true)
 check(Char.GetItemIndex(p,8)==stone and Char.GetGold(p)==0,'autosell off respected')
 cfg.autosell=true;cfg.autoidentify=false;Item.SetData(stone,CONST['道具_已鉴定'],0)
 M:maintain(p,true)
 check(Char.GetItemIndex(p,8)==stone and Char.GetGold(p)==0,'unidentified stone retained when identify off')
 check(M:handleTalk(p,'/autosort on')==0 and M:settings(p).autosort,'autosort on command saves enabled')
 M.configs[p]=nil
 check(M:settings(p).autosort,'autosort enabled persists after cache reset')
end,debug.traceback)
NLG.SystemMessage=oldMessage
if p>=0 then M.pendingBattle[p]=nil;pcall(Char.DelDummy,p) end
R.status=ok and 'PASS' or 'FAIL';if not ok then R.error=tostring(err) end
local f=assert(io.open('__OUTPUT__/autosell_native.json','wb'));f:write(JSON.encode(R));f:close()
