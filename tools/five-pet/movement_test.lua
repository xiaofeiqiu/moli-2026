local M=getModule('fivePet')
local R={status='RUNNING',checks={}}
local OUT='__OUTPUT__/movement_result.json'
local function write() local f=assert(io.open(OUT,'w'));f:write(JSON.encode(R));f:close() end
local function check(ok,name) R.checks[#R.checks+1]={name=name,pass=ok and true or false};write();assert(ok,name) end
local function g(p,k) return Char.GetData(p,CONST[k]) end
local p=-1
local function clean()
 if p<0 then return end
 M:disable(p)
 if Char.GetBattleIndex(p)>=0 then Battle.ExitBattle(p) end
 for slot=0,4 do if Char.GetPet(p,slot)>=0 then Char.DelSlotPet(p,slot) end end
 Char.DelDummy(p);p=-1
end
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=151,y=113,image=100002,name='FIVE_PET_MOVEMENT_TEST'})
 assert(p>=0)
 for slot=0,4 do assert(Char.GivePet(p,3004,1)>=0) end
 Char.SetPetDepartureState(p,0,2)
 M:setEnabled(p,false)
 M:menu(p);local menu=M.menus[p]
 M:answer(M.npc,p,menu.seq,1,'1')
 check(M.active[p]~=nil,'NPC enable button creates session')
 check(Char.PartyNum(p)==5,'NPC enable joins all four companions')
 Char.Warp(p,0,1000,170,130);M:tick()
 check(M.active[p]~=nil and Char.PartyNum(p)==5,'same-map teleport retains five-pet party')
 local floor,x,y
 for _,v in ipairs({{100,475,196},{100,222,99},{101,100,100},{300,100,100}}) do
  for xx=v[2]-3,v[2]+3 do for yy=v[3]-3,v[3]+3 do
   if not floor and Map.IsWalkable(0,v[1],xx,yy)==1 then floor,x,y=v[1],xx,yy end
  end end
 end
 check(floor~=nil,'alternate map exists')
 R.destination={floor,x,y}
 Char.Warp(p,0,floor,x,y);M:tick()
 check(M.active[p]~=nil and Char.PartyNum(p)==5,'map transition retains five-pet party')
 for _,row in ipairs(M.active[p].rows) do
  check(g(row.proxy,'CHAR_地图')==floor,'companion follows to destination map')
 end
 local b=Battle.PVE(p,p,nil,{1},{1},{0});assert(b>=0)
 local count=0;for pos=0,19 do if Battle.GetPlayer(b,pos)>=0 then count=count+1 end end
 check(count==7,'post-transition battle has owner and all five pets')
 clean();R.status='PASS';write()
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err);write();pcall(clean) end
