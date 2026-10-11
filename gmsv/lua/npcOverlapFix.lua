-- One-shot repair for an already running server. DATA contains the same layout.
local plans={{["id"]=10001965,["name"]="佣兵升级卡",["image"]=14156,["before"]={229,83},["after"]={225,85}},{["id"]=10003359,["name"]="爱说话的汉克",["image"]=14546,["before"]={229,83},["after"]={227,85}},{["id"]=90000,["name"]="法兰消息员",["image"]=231105,["before"]={229,83},["after"]={229,85}},{["id"]=10003399,["name"]="强化系统",["image"]=14206,["before"]={233,83},["after"]={231,85}},{["id"]=9000018,["name"]="流星会员之家",["image"]=106479,["before"]={234,83},["after"]={233,85}},{["id"]=10000554,["name"]="邱家庄小维",["image"]=14147,["before"]={223,83},["after"]={223,84}},{["id"]=10002660,["name"]="古怪的老头",["image"]=14029,["before"]={223,83},["after"]={221,85}},{["id"]=15383,["name"]="新年特使",["image"]=260023,["before"]={235,116},["after"]={237,116},["approach"]={237,115}},{["id"]=71000,["name"]="活泼的小妹妹",["image"]=14724,["before"]={163,127},["after"]={162,129},["approach"]={162,130}},{["id"]=1051534,["name"]="艾密涅尔",["image"]=14039,["before"]={231,83},["after"]={231,87},["approach"]={231,88}},{["id"]=888888,["name"]="老爷爷",["image"]=14189,["before"]={227,83},["after"]={227,87},["approach"]={227,88},["refreshAdapters"]=true},{["id"]=11110000,["name"]="光之勇士",["image"]=100450,["before"]={278,82},["after"]={276,82},["approach"]={276,83}},{["id"]=10000299,["name"]="法兰消息员",["image"]=14041,["before"]={218,83},["after"]={218,85},["approach"]={218,86}}}
local R={status='RUNNING',moved=0,already_correct=0}
local function occupants(x,y)
 local result={}
 local _,objects=Obj.GetObject(0,1000,x,y)
 for _,o in ipairs(objects or {}) do
  local n=Obj.GetCharIndex(o)
  if n>=0 then result[#result+1]=n end
 end
 return result
end
local function matches(n,p)
 return not Char.IsPlayer(n) and not Char.IsPet(n)
  and Char.GetData(n,CONST.CHAR_名字)==p.name and Char.GetData(n,CONST.CHAR_形象)==p.image
end
local function checkTarget(p,ownNpc)
 local _,objects=Obj.GetObject(0,1000,p.after[1],p.after[2])
 for _,o in ipairs(objects or {}) do
  local kind=Obj.GetType(o)
  if kind==1 then
   local n=Obj.GetCharIndex(o)
   assert(n==ownNpc or Char.IsPlayer(n) or Char.IsPet(n),
    'NPC layout repair: another NPC blocks '..p.name..' at '..p.after[1]..','..p.after[2])
  else
   assert(kind==2 or kind==3,'NPC layout repair: fixed object blocks '..p.name)
  end
 end
end
local moves={}
local refreshAdapters=false
-- Resolve every NPC and validate every target before moving anything.
for _,p in ipairs(plans) do
 if p.refreshAdapters then refreshAdapters=true end
 local found={}
 for _,n in ipairs(occupants(p.before[1],p.before[2])) do
  if matches(n,p) then found[#found+1]={npc=n,old=true} end
 end
 for _,n in ipairs(occupants(p.after[1],p.after[2])) do
  if matches(n,p) then found[#found+1]={npc=n,old=false} end
 end
 assert(#found==1,'NPC layout repair: expected one '..p.name)
 local v=found[1]
 assert(Map.IsWalkable(0,1000,p.after[1],p.after[2])==1,'NPC layout repair: blocked target '..p.name)
 -- Players, pets and dropped items can share a tile temporarily. Only fixed
 -- occupants block this placement; never move a player to make room.
 checkTarget(p,v.old and -1 or v.npc)
 if v.old then moves[#moves+1]={npc=v.npc,plan=p}
 else R.already_correct=R.already_correct+1 end
end
local applied={}
local ok,err=pcall(function()
 for _,v in ipairs(moves) do
  applied[#applied+1]=v
  assert(Char.Warp(v.npc,0,1000,v.plan.after[1],v.plan.after[2]),'NPC layout repair: move failed '..v.plan.name)
  assert(Char.GetData(v.npc,CONST.CHAR_X)==v.plan.after[1] and Char.GetData(v.npc,CONST.CHAR_Y)==v.plan.after[2],
   'NPC layout repair: position mismatch '..v.plan.name)
  R.moved=R.moved+1
 end
end)
if not ok then
 for i=#applied,1,-1 do
  local v=applied[i];Char.Warp(v.npc,0,1000,v.plan.before[1],v.plan.before[2])
 end
 error(err)
end
if R.moved>0 and getModule('sharedTaskGuide') then
 assert(reloadModule('sharedTaskGuide'),'NPC layout repair: guide reload failed')
 R.guide_reloaded=true
end
if refreshAdapters and getModule('sharedTaskAdapters') then
 assert(reloadModule('sharedTaskAdapters'),'NPC layout repair: task adapter reload failed')
 R.adapters_reloaded=true
end
R.status='PASS'
print('NPC layout repair: moved '..R.moved..', already correct '..R.already_correct)
return R
