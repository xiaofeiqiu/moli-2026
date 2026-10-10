-- Verify native NPC sprites and an accessible, ascending roadside row.
local M=getModule('knightHybridGear')
local D=dofile('lua/Modules/knightHybridGearData.lua')
local R={status='RUNNING',checks={},shops={},client_verified=false}
local function check(ok,label)
  R.checks[#R.checks+1]={name=label,pass=ok and true or false}
  assert(ok,label)
end
local function get(p,key) return Char.GetData(p,CONST[key]) end
local ok,err=xpcall(function()
  check(M~=nil and #M.shops==#D.shops,'all shopkeepers loaded')
  for n,shop in ipairs(M.shops) do
    check(shop.name==D.shops[n].name,'shop order '..n)
    check(get(shop.npc,'CHAR_名字')==shop.name,'native name '..n)
    check(get(shop.npc,'CHAR_形象')==14058,'soldier sprite '..n)
    check(get(shop.npc,'CHAR_原形')==14058,'original soldier sprite '..n)
    check(get(shop.npc,'CHAR_X')==shop.x and get(shop.npc,'CHAR_Y')==shop.y,'native coordinates '..n)
    check(Map.IsWalkable(0,1000,shop.x,shop.y)==1,'walkable shop tile '..n)
    check(Map.IsWalkable(0,1000,shop.approach.x,shop.approach.y)==1,'walkable approach '..n)
    local count=Obj.GetObject(0,1000,shop.approach.x,shop.approach.y)
    check(count==0,'unoccupied approach '..n)
    check(#shop.items==#D.shops[n].items,'inventory count '..n)
    for j,id in ipairs(shop.items) do
      check(id==D.shops[n].items[j] and Data.ItemsetGetIndex(id)>=0,'inventory item '..n..'/'..j)
    end
    if n>1 then
      local previous=M.shops[n-1]
      check(shop.x==previous.x+2 and shop.y==previous.y,'roadside spacing '..n)
      check(shop.min_level==previous.max_level+1,'ascending level band '..n)
    end
    local copy={}
    for k,v in pairs(shop) do copy[k]=v end
    copy.image=get(shop.npc,'CHAR_形象')
    R.shops[#R.shops+1]=copy
  end
  for x=M.shops[1].x,M.shops[#M.shops].x do
    local y=M.shops[1].approach.y
    check(Map.IsWalkable(0,1000,x,y)==1,'continuous approach lane '..x)
    local count=Obj.GetObject(0,1000,x,y)
    check(count==0,'continuous lane unoccupied '..x)
  end
  R.status='PASS'
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err) end
local f=assert(io.open('__OUTPUT__/layout_result.json','w'))
f:write(JSON.encode(R));f:close()
