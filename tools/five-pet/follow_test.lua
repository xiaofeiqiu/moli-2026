local M=getModule('fivePet')
local T=ModuleBase:createModule('fivePetFollowTest')
local OUT='__OUTPUT__/follow_result.json'
local R={status='RUNNING',checks={},warps={},events={}}
local function write() local f=assert(io.open(OUT,'w'));f:write(JSON.encode(R));f:close() end
local function g(p,k) return Char.GetData(p,CONST[k]) end
local function set(p,k,v) Char.SetData(p,CONST[k],v) end
local function check(ok,name) R.checks[#R.checks+1]={name=name,pass=ok and true or false};write();assert(ok,name) end
local p=-1
local nativeWarp=Char.Warp
Char.Warp=function(q,...) R.warps[#R.warps+1]={actor=q,args={...}};return nativeWarp(q,...) end
T:regCallback('AfterWarpEvent',function(q,...) R.events[#R.events+1]={actor=q,args={...}} end)
local function clean()
 Char.Warp=nativeWarp
 if p<0 then return end
 M:disable(p)
 if Char.GetBattleIndex(p)>=0 then Battle.ExitBattle(p) end
 for slot=0,4 do if Char.GetPet(p,slot)>=0 then Char.DelSlotPet(p,slot) end end
 Char.DelDummy(p);p=-1
end
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=151,y=113,image=100002,name='FIVE_PET_FOLLOW_TEST'})
 assert(p>=0)
 for slot=0,4 do assert(Char.GivePet(p,3004,1)>=0) end
 Char.SetPetDepartureState(p,0,2)
 check(M:enable(p),'five-pet mode enabled')
 R.owner=p
 -- Model a stationary dummy falling behind a walking connected leader.
 local x,y=g(p,'CHAR_X'),g(p,'CHAR_Y')
 for step=1,20 do set(p,'CHAR_X',x+step);M:tick() end
 R.walk_warps=#R.warps;R.walk_events=#R.events
 check(#R.warps==0,'twenty walking steps do not invoke party teleport')
 check(#R.events==0,'twenty walking steps cause no warp callbacks')
 check(M.active[p]~=nil and Char.PartyNum(p)==5,'walking keeps all companions in the party')
 Char.Warp(p,0,100,472,193)
 local w,e=#R.warps,#R.events
 for _,row in ipairs(M.active[p].rows) do
  check(g(row.proxy,'CHAR_地图')==100,'native leader warp carries companion to new map')
 end
 M:tick()
 check(#R.warps==w and #R.events==e,'map transition does not trigger additional companion warps')
 for step=1,20 do set(p,'CHAR_X',472+step);M:tick() end
 check(#R.warps==w and #R.events==e,'walking after map transition causes no extra teleport')
 local b=Battle.PVE(p,p,nil,{1},{1},{0});assert(b>=0)
 local count=0;for pos=0,19 do if Battle.GetPlayer(b,pos)>=0 then count=count+1 end end
 check(count==7,'battle after walking includes owner and five companions')
 clean();R.status='PASS';write()
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err);write();pcall(clean) end
