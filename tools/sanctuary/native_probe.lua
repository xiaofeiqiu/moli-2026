local D=dofile('lua/Modules/sanctuaryData.lua')
local R={status='RUNNING',checks={},npcs={},production_accounts_used=false,client_audio_verified=false}
local p,q=-1,-1
local function get(c,k) return Char.GetData(c,CONST[k]) end
local function set(c,k,v) return Char.SetData(c,CONST[k],v) end
local function write() local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close() end
local function check(ok,name) R.checks[#R.checks+1]={name=name,pass=not not ok};assert(ok,name) end
local function occupants(f,x,y)
 local _,objects=Obj.GetObject(0,f,x,y);local npcs={}
 for _,o in ipairs(objects or {}) do if Obj.GetType(o)==1 then
  local c=Obj.GetCharIndex(o)
  if c>=0 and not Char.IsPlayer(c) and not Char.IsPet(c) and not Char.IsEnemy(c) then npcs[#npcs+1]=c end
 end end
 return npcs
end
local function reach(n)
 return Char.Warp(p,get(n,'CHAR_地图类型'),get(n,'CHAR_地图'),get(n,'CHAR_X'),get(n,'CHAR_Y')+1)
end
local function inspect()
 R.npcs={};local blocked={};local count=0
 for _,name in ipairs({'skillTraining','cg71JobSkills','fivePet','skillLibrary','knightHybridGear','autoStat','sanctuary','petSkillTutor','petSkillUpgrade','sanctuaryShops','petEquipment'}) do
  local m=assert(getModule(name),'module '..name)
  for _,n in ipairs(m.npcList) do
   local row={name=get(n,'CHAR_名字'),floor=get(n,'CHAR_地图'),x=get(n,'CHAR_X'),y=get(n,'CHAR_Y'),image=get(n,'CHAR_形象'),module=name,index=n}
   local expected=D.positions[row.name] or (name=='skillTraining' and m.positions[n])
    or (n==getModule('sanctuary').entrance and D.entrance
     or n==getModule('sanctuary').training and D.training or D.exit)
   check(row.floor==expected.map and row.x==expected.x and row.y==expected.y,'placement '..row.name)
   check(Map.IsWalkable(0,row.floor,row.x,row.y)==1,'walkable '..row.name)
   local npcs=occupants(row.floor,row.x,row.y)
   check(#npcs==1 and npcs[1]==n,'no overlap '..row.name)
   R.npcs[#R.npcs+1]=row
   if row.floor==D.floor then blocked[row.x..','..row.y]=true;count=count+1 end
  end
 end
 check(#R.npcs==94 and count==93,'all tutors and services in the same sanctuary')
 -- Paths start at the landing point and treat NPCs as occupied, not just tiles.
 local todo={D.arrival};local seen={[D.arrival.x..','..D.arrival.y]=true};local at=1
 while todo[at] do
  local t=todo[at];at=at+1
  for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
   local x,y=t.x+d[1],t.y+d[2];local key=x..','..y
   if not seen[key] and not blocked[key] and Map.IsWalkable(0,D.floor,x,y)==1 then
    seen[key]=true;todo[#todo+1]={x=x,y=y}
   end
  end
 end
 for _,row in ipairs(R.npcs) do if row.floor==D.floor then
  local accessible=false
  for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
   if seen[(row.x+d[1])..','..(row.y+d[2])] then accessible=true end
  end
  check(accessible,'connected path from arrival '..row.name)
 end end
 check(#occupants(1000,D.return_arrival.x,D.return_arrival.y)==0,'city landing point clear')
 check(not blocked[D.arrival.x..','..D.arrival.y],'sanctuary landing point clear')
end
local function menus()
 local m=getModule('cg71JobSkills')
 local mentor
 for _,n in ipairs(m.npcList) do if get(n,'CHAR_名字')~='职业进阶导师' then
  check(reach(n),'reach pet craftsman')
  _G['cg71JobSkills_npc_'..n..'_TalkedEvent'](n,p)
  check(m.sessions[p] and m.sessions[p].npc==n,'pet craftsman dialog '..get(n,'CHAR_名字'))
 else mentor=n end end
 check(reach(mentor),'reach advanced profession mentor')
 local originalJob=get(p,'CHAR_职业');local gold=Char.GetGold(p)
 set(p,'CHAR_职业',1)
 for choice=1,3 do
  m:menu(mentor,p,nil)
  check(m.sessions[p] and m.sessions[p].kind=='no_advanced','unemployed player gets explanation menu '..choice)
  m:answer(mentor,p,7101,0,tostring(choice))
  check(m.sessions[p]==nil,'beginner selection handled '..choice)
  check(get(p,'CHAR_职业')==1 and Char.GetGold(p)==gold,'beginner guidance preserves job and gold '..choice)
  if choice==1 then check(getModule('skillLibrary').sessions[p]~=nil,'beginner guidance opens permanent library') end
 end
 m:menu(mentor,p,nil)
 Char.Warp(p,0,1000,200,100)
 m:answer(mentor,p,7101,0,'1')
 check(m.sessions[p]==nil,'distant beginner dialog rejected')
 reach(mentor);set(p,'CHAR_职业',11)
 m:menu(mentor,p,nil)
 check(m.sessions[p] and m.sessions[p].ids and #m.sessions[p].ids>0 and not m.sessions[p].kind,'employed swordsman keeps advanced skill menu')
 set(p,'CHAR_职业',originalJob)
 m=getModule('fivePet');check(reach(m.npc),'reach five-pet commander')
 _G['fivePet_npc_'..m.npc..'_TalkedEvent'](m.npc,p)
 check(m.menus[p]~=nil,'five-pet commander opens menu in sanctuary')
 Char.Warp(p,0,1000,151,113);check(not m:near(p),'old commander position cannot answer sanctuary menu')
 m=getModule('skillTraining')
 for n in pairs(m.categories) do
  check(reach(n),'reach skill tutor')
  _G['skillTraining_npc_'..n..'_TalkedEvent'](n,p)
  check(m.sessions[p] and m.sessions[p].npc==n,'skill tutor dialog '..get(n,'CHAR_名字'))
 end
 m=getModule('skillLibrary');check(reach(m.npc),'reach skill library')
 check(m:ready(p)~=nil,'skill library no false battle rejection')
 _G['skillLibrary_npc_'..m.npc..'_TalkedEvent'](m.npc,p)
 check(m.sessions[p]~=nil,'skill library dialog')
end
local function shops()
 local m=assert(getModule('sanctuaryShops'))
 check(#m.shops==4,'four native sanctuary merchants')
 for index,shop in ipairs(m.shops) do
  check(#shop.items==({20,10,20,8})[index],'native stock count '..shop.name)
  check(reach(shop.npc),'reach merchant from south '..shop.name)
  check(get(shop.npc,'CHAR_血')==1,'native merchant is open '..shop.name)
  for stockIndex,id in ipairs(shop.items) do
   local stock=Char.GetItemIndex(shop.npc,stockIndex-1)
   check(stock>=0 and Item.GetData(stock,CONST['道具_ID'])==id,'actual native inventory '..id)
   local item=Item.MakeItem(id)
   check(item>=0,'native merchandise creation '..id)
   local price=Item.GetData(stock,CONST['道具_价格'])
   local typ=Item.GetData(item,CONST['道具_类型'])
   local rank=Item.GetData(item,CONST['道具_等级'])
   Item.UnlinkItem(item)
   check(price>0,'positive native shop price '..id)
   if index==1 then
    check(typ>=56 and typ<=60,'pet equipment type '..id)
    check(price==rank*1000,'pet equipment price by rank '..id)
   elseif index==4 then
    check(typ==22 and rank==1,'native attribute crystal '..id)
    check(price==(stockIndex<=4 and 1000 or 400),'crystal merchant price '..id)
    check(Item.GetData(stock,CONST['道具_已鉴定'])==1,'native crystal stock is identified '..id)
   else check(typ==(index==2 and 43 or 23),'supply item type '..id) end
  end
 end
end
local function automaticTravel(portal)
 -- Use native walking, so this checks event wiring as well as the Lua handler.
 local north
 for direction=0,7 do
  check(Char.Warp(p,0,D.floor,30,38),'walk direction probe placement')
  Char.MoveArray(p,{direction})
  if get(p,'CHAR_X')==30 and get(p,'CHAR_Y')==37 then north=direction end
 end
 check(north~=nil,'native north walk direction found')
 Char.Warp(p,0,1000,D.entrance.x,D.entrance.y+1)
 check(not portal:stepOn(portal.entrance,p),'standing beside entrance does not auto teleport')
 Char.MoveArray(p,{north})
 check(get(p,'CHAR_地图')==D.floor and get(p,'CHAR_X')==D.arrival.x and get(p,'CHAR_Y')==D.arrival.y,'walking onto entrance automatically teleports')
 check(not portal:stepOn(portal.exit,p),'arrival does not immediately return')
 Char.Warp(p,0,D.floor,D.exit.x,D.exit.y+1)
 check(not portal:stepOn(portal.exit,p),'standing beside exit does not auto teleport')
 Char.MoveArray(p,{north})
 check(get(p,'CHAR_地图')==1000 and get(p,'CHAR_X')==D.return_arrival.x and get(p,'CHAR_Y')==D.return_arrival.y,'walking onto return stone automatically teleports')
 check(not portal:stepOn(portal.entrance,p),'city landing does not immediately reenter')
 R.native_step_on_verified=true
end
local function trainingTravel(portal)
 local entry=D.training_destinations[1]
 local dest=assert(portal:trainingDestination(entry),'resolve random training dungeon')
 check(dest.mapType==1 and Map.GetDungeonId(dest.map)==3,'target is native castle underground dungeon')
 local targetName=NLG.GetMapName(1,dest.map);local level=tonumber(targetName:match('地下(%d+)楼'))
 check(level~=nil,'target has underground floor number')
 local area=select(1,Map.GetMapSize(1,dest.map))*select(2,Map.GetMapSize(1,dest.map))
 for floor=0,portal.dungeonLimit-1 do if Map.GetDungeonId(floor)==3 then
  local name=NLG.GetMapName(1,floor);local other=tonumber(name:match('地下(%d+)楼'))
  check(not other or other<=level,'destination is deepest floor '..floor)
  if other==level then local w,h=Map.GetMapSize(1,floor);check(w*h<=area,'choose training maze rather than small end room '..floor) end
 end end
 check(Map.IsWalkable(1,dest.map,dest.x,dest.y)==1,'training arrival walkable')
 local _,objects=Obj.GetObject(1,dest.map,dest.x,dest.y)
 check(not objects or #objects==0,'training arrival clear of stairs and NPCs')
 check(reach(portal.training),'reach training guide')
 check(not portal:stepOn(portal.training,p),'training guide does not use step-on travel')
 local function open()
  _G['sanctuary_npc_'..portal.training..'_TalkedEvent'](portal.training,p,'',0,0)
  check(portal.trainingSessions[p]~=nil and get(p,'CHAR_地图')==D.floor,'talk opens selection without teleporting')
 end
 local function answer(seq,button,data)
  return _G['sanctuary_npc_'..portal.training..'_WindowTalkedEvent'](portal.training,p,seq,button,data)
 end
 open();answer(7302,0,'1');check(get(p,'CHAR_地图')==D.floor,'wrong window cannot teleport')
 open();answer(7301,2,'1');check(get(p,'CHAR_地图')==D.floor,'cancel cannot teleport')
 open();answer(7301,0,'0');check(get(p,'CHAR_地图')==D.floor,'invalid option rejected')
 open();portal.trainingSessions[p].at=os.time()-121;answer(7301,0,'1');check(get(p,'CHAR_地图')==D.floor,'expired menu rejected')
 open();portal.trainingSessions[p].uuid='OLD';answer(7301,0,'1');check(get(p,'CHAR_地图')==D.floor,'stale player identity rejected')
 open();Char.Warp(p,0,1000,200,100);answer(7301,0,'1');check(get(p,'CHAR_地图')==1000,'remote answer rejected')
 reach(portal.training);open();answer(7301,0,'1')
 check(get(p,'CHAR_地图类型')==1 and get(p,'CHAR_地图')==dest.map,'selected menu sends player to deepest native underground maze')
 check(portal.musicPlayed[p]==nil and portal.trainingSessions[p]==nil,'travel clears sanctuary music and consumes menu')
 answer(7301,0,'1');check(get(p,'CHAR_地图')==dest.map,'duplicate response has no effect')
 R.training_destination={mapType=1,floor=dest.map,name=targetName,x=get(p,'CHAR_X'),y=get(p,'CHAR_Y')}
 local bi=Battle.Encount(p,p)
 check(type(bi)=='number' and bi>=0,'native training encounter available at landing point')
 Battle.ExitBattle(p);set(p,'CHAR_BattleMode',0);set(p,'CHAR_BattleIndex',-1)
 check(reach(portal.training),'reach training guide for battle guard');open()
 bi=Battle.PVE(p,p,nil,{1},{100},{0});check(bi>=0,'training guard native battle created')
 answer(7301,0,'1');check(get(p,'CHAR_地图')==D.floor,'training menu rejects actual battle participant')
 Battle.ExitBattle(p);set(p,'CHAR_BattleMode',0);set(p,'CHAR_BattleIndex',-1)
 -- The configured bear boss destination uses the player's requested location.
 local bearEntry=assert(D.training_destinations[2],'configured bear boss destination')
 check(bearEntry.name=='熊男（欧兹那克）','bear boss menu label')
 local bear=portal:trainingDestination(bearEntry)
 check(bear.mapType==0 and bear.map==11004 and bear.x==18 and bear.y==19,'bear boss destination matches requested map and coordinates')
 check(Map.IsWalkable(bear.mapType,bear.map,bear.x,bear.y)==1,'bear boss arrival walkable')
 local _,bearObjects=Obj.GetObject(bear.mapType,bear.map,bear.x,bear.y)
 check(not bearObjects or #bearObjects==0,'bear boss arrival clear of stairs and NPCs')
 local bosses=occupants(11004,17,17)
 check(#bosses==1 and get(bosses[1],'CHAR_名字')=='杀熊者欧兹那克','native bear boss exists near arrival')
 check(reach(portal.training),'reach guide for bear boss travel');open()
 check(#portal.trainingSessions[p].actions==3 and portal.trainingSessions[p].actions[2].destination==portal.trainingCatalog[2],'bear boss is second actual menu option')
 answer(7301,2,'2');check(get(p,'CHAR_地图')==D.floor,'cancel bear boss selection preserves location')
 open();local gold=Char.GetGold(p);answer(7301,0,'2')
 check(get(p,'CHAR_地图类型')==0 and get(p,'CHAR_地图')==11004 and get(p,'CHAR_X')==18 and get(p,'CHAR_Y')==19,'bear boss selection arrives at requested location')
 check(Char.GetGold(p)==gold,'bear boss teleport is free')
 check(Char.GetBattleIndex(p)<0,'bear boss arrival does not start a battle')
 check(portal.trainingSessions[p]==nil and portal.musicPlayed[p]==nil,'bear boss travel consumes menu and clears sanctuary music')
 answer(7301,0,'1');check(get(p,'CHAR_地图')==11004,'duplicate bear boss response has no effect')
 R.bear_destination={mapType=0,floor=11004,name=NLG.GetMapName(0,11004),x=get(p,'CHAR_X'),y=get(p,'CHAR_Y'),boss=get(bosses[1],'CHAR_名字')}
 check(reach(portal.training),'return to guide after bear boss travel')
 -- Resolve the new cave against native generated maps, including after reload.
 local caveEntry=assert(D.training_destinations[3],'configured strange cave destination')
 check(caveEntry.name=='奇怪的洞穴最下层' and caveEntry.dungeonId==2222,'strange cave menu label and dungeon ID')
 local cave=assert(portal:trainingDestination(caveEntry),'resolve native strange cave')
 check(cave.mapType==1 and Map.GetDungeonId(cave.map)==2222,'strange cave uses generated dungeon rather than fixed entrance')
 local caveName=NLG.GetMapName(1,cave.map);local caveDepth=tonumber(caveName:match('地下(%d+)楼'))
 check(caveName:find('奇怪的洞穴',1,true) and caveDepth and caveDepth>=9 and caveDepth<=10,'native strange cave bottom floor name')
 local cw,ch=Map.GetMapSize(1,cave.map)
 for floor=0,portal.dungeonLimit-1 do if Map.GetDungeonId(floor)==2222 then
  local other=tonumber(NLG.GetMapName(1,floor):match('地下(%d+)楼'))
  check(not other or other<=caveDepth,'strange cave destination is deepest floor '..floor)
  if other==caveDepth then local w,h=Map.GetMapSize(1,floor);check(w*h<=cw*ch,'strange cave chooses largest bottom floor '..floor) end
 end end
 check(Map.IsWalkable(1,cave.map,cave.x,cave.y)==1,'strange cave arrival walkable')
 local _,caveObjects=Obj.GetObject(1,cave.map,cave.x,cave.y)
 check(not caveObjects or #caveObjects==0,'strange cave arrival clear of stairs and NPCs')
 open();check(portal.trainingSessions[p].actions[3].destination==portal.trainingCatalog[3],'strange cave is third actual menu option')
 answer(7301,2,'3');check(get(p,'CHAR_地图')==D.floor,'cancel strange cave selection preserves location')
 open();gold=Char.GetGold(p);answer(7301,0,'3')
 check(get(p,'CHAR_地图类型')==1 and get(p,'CHAR_地图')==cave.map and get(p,'CHAR_X')==cave.x and get(p,'CHAR_Y')==cave.y,'strange cave selection arrives at resolved bottom floor')
 check(Char.GetGold(p)==gold,'strange cave teleport is free')
 check(portal.trainingSessions[p]==nil and portal.musicPlayed[p]==nil,'strange cave travel consumes menu and clears sanctuary music')
 answer(7301,0,'2');check(get(p,'CHAR_地图')==cave.map,'duplicate strange cave response has no effect')
 R.strange_cave_destination={mapType=1,dungeonId=2222,floor=cave.map,name=caveName,x=cave.x,y=cave.y}
 bi=Battle.Encount(p,p);check(type(bi)=='number' and bi>=0,'native strange cave encounter available at landing point')
 Battle.ExitBattle(p);set(p,'CHAR_BattleMode',0);set(p,'CHAR_BattleIndex',-1)
 check(reach(portal.training),'return to guide after strange cave travel')
 -- Data-driven pagination and actual fixed-map destinations for future additions.
 local catalog=portal.trainingCatalog
 portal.trainingCatalog={}
 for i=1,13 do portal.trainingCatalog[i]={name='TEST '..i,mapType=0,map=1000,x=223,y=86,music=200} end
 open();local session=portal.trainingSessions[p]
 check(#session.actions==7 and session.actions[7].page==2,'first page six destinations and next')
 answer(7301,0,'7');session=portal.trainingSessions[p]
 check(#session.actions==8 and session.actions[7].page==1 and session.actions[8].page==3,'middle page six destinations and both directions')
 answer(7301,0,'8');session=portal.trainingSessions[p]
 check(#session.actions==2 and session.actions[1].destination==portal.trainingCatalog[13],'last page uses configured thirteenth destination')
 answer(7301,0,'2');check(portal.trainingSessions[p].actions[1].destination==portal.trainingCatalog[7],'previous page opens correct destinations')
 answer(7301,0,'1');check(get(p,'CHAR_地图')==1000,'fixed-map menu addition uses actual configured coordinates')
 portal.trainingCatalog=catalog
 local resolve=portal.trainingDestination
 portal.trainingDestination=function() return nil end
 reach(portal.training);open();answer(7301,0,'1');check(get(p,'CHAR_地图')==D.floor,'missing refreshed dungeon fails safely')
 portal.trainingDestination=resolve
end
local function finish(err)
 if err then R.status='FAIL';R.error=tostring(err) else R.status='PASS' end
 for _,c in ipairs({p,q}) do if c>=0 then
  if Char.GetBattleIndex(c)>=0 then pcall(Battle.ExitBattle,c) end
  set(c,'CHAR_BattleMode',0);set(c,'CHAR_BattleIndex',-1);pcall(Char.DelDummy,c)
 end end
 write()
end
write()
Cron.AddInterval(1800,function()
 if R.status~='RUNNING' then return end
 -- Native dungeons are generated incrementally after startup.
 if Map.GetDungeonExpireAtByDungeonId(D.training_destinations[3].dungeonId)<0 then return end
 local ok,err=xpcall(function()
  local portal=assert(getModule('sanctuary'));local state=assert(getModule('battleState'))
  local w,h=Map.GetMapSize(0,D.floor);check(w==100 and h==50,'100x50 open sanctuary loaded')
  check(NLG.GetMapName(0,D.floor)==D.name..'|0','map displayed as sanctuary')
  for y=8,42 do for x=8,92 do
   local c,d=Map.GetImage(0,D.floor,x,y)
   check(c==3390+(x+y)%3 and d==0,'open hall without arches '..x..','..y)
   check(Map.IsWalkable(0,D.floor,x,y)==1,'open hall walkable '..x..','..y)
  end end
  inspect()
  p=Char.CreateDummy({mapType=0,floor=1000,x=223,y=86,image=100002,name='SANCTUARY_PROBE'})
  q=Char.CreateDummy({mapType=0,floor=1000,x=222,y=86,image=100002,name='BATTLE_STATE_PROBE'})
  check(p>=0 and q>=0,'isolated dummy players')
  local a,b=NLG.GetPlayer();local c,d=NLG.GetMapPlayer(0,1000)
  R.player_api={all_first=type(a),all_second=type(b),map_first=type(c),map_second=type(d)}
  check(Char.GetBattleIndex(p)<0,'normal idle battle state preserved')
  set(p,'CHAR_BattleIndex',0);set(p,'CHAR_BattleMode',0)
  check(Char.GetBattleIndex(p)==-1 and get(p,'CHAR_BattleIndex')==-1,'orphaned idle battle index repaired')
  check(portal:travel(portal.entrance,p),'entrance stone teleports')
  check(get(p,'CHAR_地图')==D.floor and get(p,'CHAR_X')==D.arrival.x and get(p,'CHAR_Y')==D.arrival.y,'sanctuary arrival coordinates')
  check(portal.musicPlayed[p]==Char.GetUUID(p),'shrine music requested on entry')
  automaticTravel(portal)
  trainingTravel(portal)
  menus();shops()
  reach(portal.exit);check(portal:travel(portal.exit,p),'return stone teleports')
  check(get(p,'CHAR_地图')==1000 and get(p,'CHAR_X')==223 and get(p,'CHAR_Y')==86,'return near east hospital')
  Char.Warp(p,0,1000,200,100);check(not portal:travel(portal.entrance,p),'remote portal use rejected')
  set(q,'CHAR_等级',50);set(q,'CHAR_体力',50000);set(q,'CHAR_魔法',50000);NLG.UpChar(q)
  set(q,'CHAR_血',get(q,'CHAR_最大血'));set(q,'CHAR_魔',get(q,'CHAR_最大魔'))
  local bi=Battle.PVE(q,q,nil,{1},{100},{0});check(bi>=0,'real native battle created')
  local mode=get(q,'CHAR_BattleMode')
  check(Char.GetBattleIndex(q)==bi and get(q,'CHAR_BattleMode')==mode,'actual battle participant preserved')
  set(p,'CHAR_BattleIndex',bi);set(p,'CHAR_BattleMode',0)
  check(Char.GetBattleIndex(p)==-1,'idle orphan pointing to another battle repaired')
  check(Char.GetBattleIndex(q)==bi,'other player battle untouched')
  set(q,'CHAR_BattleMode',0)
  check(Char.GetBattleIndex(q)==bi,'battle roster takes precedence over mode zero')
  set(q,'CHAR_BattleMode',mode)
  Char.Warp(q,0,1000,223,86)
  check(not portal:travel(portal.entrance,q),'battle participant cannot teleport')
  Battle.ExitBattle(q);set(q,'CHAR_BattleMode',0);set(q,'CHAR_BattleIndex',-1)
  set(p,'CHAR_BattleIndex',999999);set(p,'CHAR_BattleMode',3)
  check(state:normalize(p)==999999,'nonzero invalid battle gets delayed confirmation')
  state.pending[p].at=os.time()-4
  check(state:normalize(p)==-1 and get(p,'CHAR_BattleMode')==0,'confirmed expired battle state repaired')
  reloadModule('battleState')
  set(p,'CHAR_BattleIndex',0);set(p,'CHAR_BattleMode',0)
  check(Char.GetBattleIndex(p)==-1,'battle state module reload stays functional')
  for _,name in ipairs({'skillTraining','cg71JobSkills','fivePet','skillLibrary','knightHybridGear','autoStat','sanctuary','petSkillTutor','petSkillUpgrade','sanctuaryShops','petEquipment'}) do reloadModule(name) end
  inspect();automaticTravel(getModule('sanctuary'));trainingTravel(getModule('sanctuary'));menus();shops()
 end,debug.traceback)
 finish(not ok and err or nil)
end,1)
