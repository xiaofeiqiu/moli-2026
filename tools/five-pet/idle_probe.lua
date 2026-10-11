-- Native idle lifecycle reproduction. Only bank lookup and online discovery use fixtures.
local R={status='RUNNING',checks={},trace={},production_database_modified=false,bank_lookup_injected=true}
local M=assert(getModule('fivePet'))
local p,bankOwner=-1,-1
local bank={};local finished=false
local nativePool,nativePlayers,nativeDummy=Char.GetPoolPet,NLG.GetPlayer,Char.IsDummy
local nativeJoin,nativeLeave=Char.JoinParty,Char.LeaveParty
local nativeGive,nativeTime=Char.GivePet,os.time
local joins,leaves=0,0
Char.GetPoolPet=function(q,slot) if q==p then return bank[slot] or -1 end;return nativePool(q,slot) end
NLG.GetPlayer=function() return p>=0 and {p} or {} end
Char.IsDummy=function(q) if q==p then return false end;return nativeDummy(q) end
Char.JoinParty=function(q,owner,...) if owner==p then joins=joins+1 end;return nativeJoin(q,owner,...) end
Char.LeaveParty=function(q,...) if M.proxies[q] or Char.GetPartyMember(q,0)==p then leaves=leaves+1 end;return nativeLeave(q,...) end
local function g(q,k) return Char.GetData(q,CONST[k]) end
local function s(q,k,v) return Char.SetData(q,CONST[k],v) end
local function write() local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close() end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};write();assert(ok,label) end
local function clean(q)
 if q<0 then return end
 for slot=0,4 do if Char.GetPet(q,slot)>=0 then pcall(Char.DelSlotPet,q,slot) end end
 pcall(Char.DelDummy,q)
end
local function finish(err)
 if finished then return end;finished=true
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 R.joins=joins;R.leaves=leaves
 pcall(M.disable,M,p);clean(p);clean(bankOwner)
 Char.GetPoolPet=nativePool;NLG.GetPlayer=nativePlayers;Char.IsDummy=nativeDummy
 Char.JoinParty=nativeJoin;Char.LeaveParty=nativeLeave;write()
 Char.GivePet=nativeGive;os.time=nativeTime
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  local function player(name)
   local q=Char.CreateDummy({mapType=0,floor=1000,x=151,y=113,image=100002,name=name})
   assert(q>=0);s(q,'CHAR_等级',50);s(q,'CHAR_体力',5000);NLG.UpChar(q)
   s(q,'CHAR_血',g(q,'CHAR_最大血'));return q
  end
  p=player('PET_IDLE_PROBE');bankOwner=player('PET_IDLE_BANK_FIXTURE')
  -- Species/learned skills reproduce the reported player's roster, without copying saves.
  for _,id in ipairs({905,800400,800401,800404,90913}) do local q=Char.GivePet(p,3004,1);check(q>=0,'create carried species '..id);s(q,'宠物_PETID',id) end
  local specs={{600116,17,{7300,7400,730,6350}},{90914,21,{7300,7400,6350,6550,2131,2531}},{2049,1,{7300,7400,130,630,330}}}
  for slot,spec in ipairs(specs) do
   local q=Char.GivePet(bankOwner,3004,1);check(q>=0,'create bank species '..spec[1]);bank[slot-1]=q;s(q,'宠物_PETID',spec[1])
   s(q,'CHAR_等级',spec[2]);s(q,'宠物_技能栏',15)
   for n=9,0,-1 do if Pet.GetSkill(q,n)>=0 then Pet.DelSkill(q,n) end end
   for _,id in ipairs(spec[3]) do check(Pet.AddSkill(q,id)==1,'source skill '..spec[1]..':'..id) end
  end
  check(Char.SetPetDepartureState(p,0,2)==1,'main pet selected')
  local yes,msg=M:enable(p)
  R.enable={success=yes,message=msg,joins=joins,leaves=leaves};write()
  check(yes,'reported roster enables: '..tostring(msg))
  local session=M.active[p];local initialJoins,initialLeaves=joins,leaves
  check(M:petEnemyId(bank[2])==2019,'bank kind 2049 resolves to native creation ID 2019')
  check(g(session.companions[3].proxy,'宠物_PETID')==2049,'mapped companion retains original species')
  check(#session.companions==3 and #session.rows==4,'partial bank roster creates eight pets')
  for n=1,120 do
   M.nextAutoCheck=0;M:tick()
   R.trace[#R.trace+1]={tick=n,active=M.active[p]==session,joins=joins,leaves=leaves}
   check(M.active[p]==session,'idle tick retains same session '..n)
  end
  check(joins==initialJoins and leaves==initialLeaves,'idle does not rejoin or leave')
  Char.Warp(p,0,100,472,193);M:tick()
  check(M.active[p]==session and joins==initialJoins and leaves==initialLeaves,'native map transition keeps same party without joins')
  -- A resource failure at the third bank pet must happen before any joins,
  -- and repeated automatic scans must not try the same failed roster again.
  M:disable(p);initialJoins=joins;initialLeaves=leaves
  local attempts=0;local now=nativeTime()
  os.time=function(...) if select('#',...)>0 then return nativeTime(...) end;return now end
  Char.GivePet=function(owner,id,...)
   if M.proxies[owner] then attempts=attempts+1;if id==2019 then return -1 end end
   return nativeGive(owner,id,...)
  end
  M.autoAttempts[p]=nil;M.nextAutoCheck=0;M:tick()
  check(not M.active[p] and M.autoAttempts[p] and M.autoAttempts[p].blocked,'failed actor creation suspends automatic retries')
  check(joins==initialJoins and leaves==initialLeaves and Char.PartyNum(p)<=1,'failed actor creation makes no visible joins or leaves')
  check(next(M.proxies)==nil,'failed actor creation disposes every temporary actor')
  local failedAttempts=attempts
  for n=1,120 do now=now+3;M.nextAutoCheck=0;M:tick() end
  check(attempts==failedAttempts and joins==initialJoins and leaves==initialLeaves,'six simulated minutes of unchanged failed roster produce no retries or party sounds')
  Char.GivePet=nativeGive
  -- An explicit on command permits retry after the resource issue is resolved.
  check(TalkEvent(p,'/fivepet on',0,0,0)==0 and M.active[p]~=nil,'explicit on retries and restores the squad')
  session=M.active[p];initialJoins=joins;initialLeaves=leaves
  for n=1,20 do now=now+3;M.nextAutoCheck=0;M:tick() end
  check(M.active[p]==session and joins==initialJoins and leaves==initialLeaves,'successful explicit retry remains stable')
  M:disable(p);initialJoins=joins;initialLeaves=leaves
  Char.GivePet=function(owner,id,...) if M.proxies[owner] and id==2019 then return -1 end;return nativeGive(owner,id,...) end
  M.nextAutoCheck=0;M:tick();check(M.autoAttempts[p] and M.autoAttempts[p].blocked,'second failure blocks same roster')
  Char.GivePet=nativeGive
  bank[3]=Char.GivePet(bankOwner,3004,1);check(bank[3]>=0,'fourth bank original added')
  now=now+3;M.nextAutoCheck=0;M:tick();session=M.active[p]
  check(session and #session.companions==4 and #M:actors(session)==8,'changed roster automatically resumes full nine pets')
  check(joins==initialJoins+4 and leaves==initialLeaves,'changed roster joins exactly once after silent failure')
  os.time=nativeTime;initialJoins=joins;initialLeaves=leaves
  local ticks=0
  Cron.AddInterval(250,function()
   if finished then return end
   local yes,failure=xpcall(function()
    ticks=ticks+1;M.nextAutoCheck=0;M:tick()
    check(M.active[p]==session and joins==initialJoins and leaves==initialLeaves,'real native idle timer keeps nine-pet party '..ticks)
   end,debug.traceback)
   if not yes then finish(failure);return end
   if ticks==40 then R.native_idle_ticks=ticks;finish() end
  end,40)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
