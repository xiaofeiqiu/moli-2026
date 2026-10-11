local R={status='RUNNING',checks={}}
local M=assert(getModule('fivePet'))
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=ok and true or false};assert(ok,label) end
local p=-1
local originalGetPlayer=M.nativeGetPlayer;local originalGetPlayIndex=M.nativeGetPlayIndex
local ok,err=xpcall(function()
 for count=1,5 do
  p=Char.CreateDummy({mapType=0,floor=1000,x=151,y=113,image=100002,name='PARTIAL_PET_TEST'})
  check(p>=0,'owner '..count)
  for n=1,count do check(Char.GivePet(p,3004,1)>=0,'pet '..count..':'..n) end
  check(Char.SetPetDepartureState(p,count==5 and 4 or 0,2)==1,'main selected '..count)
  check(M:enable(p),'enable '..count)
  check(#M.active[p].rows==count-1,'proxy count '..count)
  local b=Battle.PVE(p,p,nil,{1},{100},{0})
  check(b>=0,'battle '..count)
  M:tick()
  local s=M.active[p];local main=Battle.GetPos(b,s.normal)
  R['positions'..count]={main=main,owner=Battle.GetPos(b,p),pets={}}
  check(main==5 and Battle.GetPos(b,p)==0 and Battle.GetEntryData(b,p,CONST.BATTLE_ENTRY_POSITION)==1,'fixed main front and owner rear '..count)
  for i,r in ipairs(s.rows) do
   local pos=Battle.GetPos(b,r.proxy)
   R['positions'..count].pets[#R['positions'..count].pets+1]={pos=pos,entry=Battle.GetEntryData(b,r.proxy,CONST.BATTLE_ENTRY_POSITION)}
   check(pos==5+i and Battle.GetEntryData(b,r.proxy,CONST.BATTLE_ENTRY_POSITION)==0 and Battle.GetPlayer(b,i)<0,'actual front slot '..count..':'..r.slot)
   check(Battle.GetPlayer(b,pos)==r.proxy,'native roster and command ID agree '..count..':'..r.slot)
  end
  if count==5 then
   Battle.SetEntryData(b,p,CONST.BATTLE_ENTRY_BID,5);Battle.SetEntryData(b,s.normal,CONST.BATTLE_ENTRY_BID,0)
   Battle.SetEntryData(b,p,CONST.BATTLE_ENTRY_POSITION,0);Battle.SetEntryData(b,s.normal,CONST.BATTLE_ENTRY_POSITION,1)
   M:formation(b,s)
   check(Battle.GetPos(b,p)==0 and Battle.GetPos(b,s.normal)==5,'fixed formation restores a reversed owner and main pet')
  end
  M:disable(p);Battle.ExitBattle(p)
  for n=0,4 do if Char.GetPet(p,n)>=0 then Char.DelSlotPet(p,n) end end
  Char.DelDummy(p);p=-1
 end
 unloadModule('fivePet');check(getModule('fivePet')==nil,'module unload succeeds')
 check(Battle.GetPlayer==originalGetPlayer and Battle.GetPlayIndex==originalGetPlayIndex,'module unload restores both native roster queries')
 check(loadModule('fivePet'),'module load succeeds')
 M=assert(getModule('fivePet'))
 check(M.nativeGetPlayer==originalGetPlayer and M.nativeGetPlayIndex==originalGetPlayIndex,'module reload preserves one mapping layer')
 check(Char.GetData(M.npc,CONST.CHAR_地图)==60003,'reloaded commander remains in sanctuary')
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err) else R.status='PASS' end
if p>=0 then pcall(M.disable,M,p);pcall(Battle.ExitBattle,p);pcall(Char.DelDummy,p) end
local f=assert(io.open('__OUTPUT__/fivepet_partial_native.json','wb'));f:write(JSON.encode(R));f:close()
