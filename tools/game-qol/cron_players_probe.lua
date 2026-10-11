local R={status='RUNNING',checks={},maps={}}
local M=assert(getModule('gameQoL'))
local originalPlayers=NLG.GetPlayer
local originalMaintain=M.maintain
local originalDummy=Char.IsDummy
local originalInterval=M.AddInterval
local tick
local p=-1
local function check(ok,label)
 R.checks[#R.checks+1]={name=label,pass=ok and true or false};assert(ok,label)
end
local ok,err=xpcall(function()
 -- Capture the actual registered two-second callback on a fresh module instance.
 local captured
 M.AddInterval=function(self,ms,fn,...)
  if ms==2000 then captured=fn end
 end
 M:onLoad()
 M.AddInterval=originalInterval
 tick=assert(captured)
 R.native_players={kind=type(originalPlayers()),value=originalPlayers()}
 for _,value in ipairs({-1,0,1,false,{}}) do
  NLG.GetPlayer=function() return value end
  check(pcall(tick),'callback accepts '..type(value)..'/'..tostring(value))
 end
 NLG.GetPlayer=function() return nil end
 check(pcall(tick),'callback accepts nil')
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='CRON_PLAYERS_TEST'})
 check(p>=0,'isolated fixture created')
 local calls=0
 Char.IsDummy=function(q) if q==p then return false end;return originalDummy(q) end
 M.maintain=function(self,q) check(q==p,'callback targets listed player');calls=calls+1 end
 NLG.GetPlayer=function() return {p} end
 tick();check(calls==1,'table result maintains valid player')
 M.maintain=function() error('fixture failure') end
 check(pcall(tick),'individual maintenance failure contained')
 Char.IsDummy=originalDummy
 M.maintain=function() calls=calls+1 end
 tick();check(calls==1,'dummy player skipped')
 M.maintain=originalMaintain;NLG.GetPlayer=originalPlayers
 for _,point in ipairs({{27102,16,22},{57464,26,44},{30001,445,484}}) do
  local floor,x,y=unpack(point)
  local w,h=Map.GetMapSize(0,floor)
  local ground,image=Map.GetImage(0,floor,x,y)
  local count,objects=Obj.GetObject(0,floor,x,y)
  local row={floor=floor,x=x,y=y,width=w,height=h,ground=ground,image=image,walkable=Map.IsWalkable(0,floor,x,y),count=count,objects={},nearby={}}
  for _,o in ipairs(type(objects)=='table' and objects or {}) do
   local item={index=o,kind=Obj.GetType(o)}
   if item.kind==4 then item.toFloor=Obj.GetWarpFloor(o);item.toX=Obj.GetWarpX(o);item.toY=Obj.GetWarpY(o) end
   row.objects[#row.objects+1]=item
  end
  for yy=y-2,y+2 do for xx=x-2,x+2 do
   local a,b=Map.GetImage(0,floor,xx,yy)
   row.nearby[#row.nearby+1]={x=xx,y=yy,ground=a,image=b,walkable=Map.IsWalkable(0,floor,xx,yy)}
  end end
  R.maps[#R.maps+1]=row
 end
 for _,point in ipairs({{27102,16,21},{57464,26,43},{30001,444,484}}) do
  local floor,x,y=unpack(point)
  check(Map.IsWalkable(0,floor,x,y)==1,'replacement tile walkable '..floor)
  local count,objects=Obj.GetObject(0,floor,x,y)
  check(count==0,'replacement tile unoccupied '..floor)
  local warp=Obj.AddWarp(0,floor,x,y,0,1000,225,75)
  check(type(warp)=='number' and warp>=0,'native warp creation '..floor)
  check(Obj.GetType(warp)==4 and Obj.GetWarpFloor(warp)==1000,'created warp destination '..floor)
  Obj.RemoveObject(warp)
 end
end,debug.traceback)
M.AddInterval=originalInterval;M.maintain=originalMaintain
NLG.GetPlayer=originalPlayers;Char.IsDummy=originalDummy
if p>=0 then Char.DelDummy(p) end
if not ok then R.status='FAIL';R.error=tostring(err) else R.status='PASS' end
Cron.AddInterval(5000,function()
 local f=assert(io.open('__OUTPUT__/cron_players_native.json','wb'));f:write(JSON.encode(R));f:close()
end,0)
