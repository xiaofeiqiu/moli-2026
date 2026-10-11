-- One-shot repair for an already running server. DATA contains the same layout.
local plans=__PLANS__
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
