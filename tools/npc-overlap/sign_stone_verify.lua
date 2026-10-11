local T=dofile('lua/sign_stone_test_data.lua')
local Jobs=dofile('lua/Modules/magicTaskJobs.lua')
local R={status='RUNNING',mode=T.mode,checks=0,production_accounts_used=false,native_event_dialogue_tested=false}
local player=-1
local standers={}
local function get(c,k) return Char.GetData(c,CONST[k]) end
local function check(ok,label) R.checks=R.checks+1;assert(ok,label) end
local function occupants(x,y)
 local list={};local _,objects=Obj.GetObject(0,1000,x,y)
 for _,o in ipairs(objects or {}) do
  if Obj.GetType(o)==1 then
   local c=Obj.GetCharIndex(o)
   if not Char.IsPlayer(c) and not Char.IsPet(c) then list[#list+1]=c end
  end
 end
 return list
end
local function find(p)
 local list={}
 for _,pos in ipairs({p.before,p.after}) do
  for _,n in ipairs(occupants(pos[1],pos[2])) do
   if get(n,'CHAR_名字')==p.name and get(n,'CHAR_形象')==p.image then list[#list+1]=n end
  end
 end
 check(#list==1,'one original NPC: '..p.name)
 return list[1]
end
local function cleanup()
 for _,p in ipairs(standers) do Char.DelDummy(p) end;standers={}
 if player>=0 then Char.DelDummy(player);player=-1 end
end
local function finish(err)
 cleanup();R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local f=assert(io.open('__OUTPUT__','wb'));f:write(JSON.encode(R));f:close()
end
local function validate()
 local adapter=assert(getModule('sharedTaskAdapters'))
 R.positions={}
 for _,p in ipairs(T.plans) do
  local list=occupants(p.after[1],p.after[2])
  check(#list==1,'one moved NPC: '..p.name)
  local n=list[1];check(n==R.original[p.name].npc,'same original object: '..p.name)
  check(get(n,'CHAR_名字')==p.name and get(n,'CHAR_形象')==p.image,'identity retained: '..p.name)
  check(Map.IsWalkable(0,1000,p.after[1],p.after[2])==1,'walkable NPC: '..p.name)
  local clear=false
  if p.approach then
   local pos=p.approach
   clear=Map.IsWalkable(0,1000,pos[1],pos[2])==1 and Obj.GetObject(0,1000,pos[1],pos[2])==0
  else
   for dx=-1,1 do for dy=-1,1 do
    if dx~=0 or dy~=0 then
     local x,y=p.after[1]+dx,p.after[2]+dy
     if Map.IsWalkable(0,1000,x,y)==1 and Obj.GetObject(0,1000,x,y)==0 then clear=true end
    end
   end end
  end
  check(clear,'clear approach: '..p.name)
  R.positions[#R.positions+1]={name=p.name,x=p.after[1],y=p.after[2]}
 end
 for _,v in ipairs({{163,127,'法兰城观光指南'},{231,83,'世贸中心传送'},{227,83,'极限挑战'}}) do
  local list=occupants(v[1],v[2])
  check(#list==1 and get(list[1],'CHAR_名字')==v[3],'sign or stone remains accessible: '..v[3])
 end
 local again=dofile('lua/npcOverlapFix.lua')
 check(again.moved==0 and again.already_correct==#T.plans and again.adapters_reloaded,'repair is repeatable')
 adapter=assert(getModule('sharedTaskAdapters'))
 player=Char.CreateDummy({mapType=0,floor=1000,x=227,y=84,image=100002,name='SIGN_STONE_JOB_VALIDATOR'})
 check(player>=0,'isolated player creation')
 local definitions=dofile('lua/Modules/magicTaskJobsData.lua')
 local function original(value,c)
  if c.field=='family' then value=math.floor(value/10)*10 end
  local function cmp(op,n)
   if op=='==' then return value==n elseif op=='!=' then return value~=n
   elseif op=='>=' then return value>=n elseif op=='<=' then return value<=n
   elseif op=='>' then return value>n else return value<n end
  end
  local groups={cmp(c.tests[1][1],c.tests[1][2])}
  for i=2,#c.tests do
   if c.joins[i-1]=='&&' then groups[#groups]=groups[#groups] and cmp(c.tests[i][1],c.tests[i][2])
   else groups[#groups+1]=cmp(c.tests[i][1],c.tests[i][2]) end
  end
  for _,yes in ipairs(groups) do if yes then return 1 end end;return 0
 end
 local predicates=0
 for key,c in pairs(definitions) do
  predicates=predicates+1
  for _,job in ipairs(dofile('lua/sign_stone_test_jobs.lua')) do
   if not Jobs.isMagic(job) then
    Char.SetData(player,CONST.CHAR_职业,job)
    Char.SetData(player,CONST.CHAR_职类ID,math.floor(job/10)*10)
    check(adapter:execute(-1,player,key)==original(job,c),'existing profession unchanged: '..job..'/'..key)
   end
  end
  for job=181,187 do
   Char.SetData(player,CONST.CHAR_职业,job)
   Char.SetData(player,CONST.CHAR_职类ID,180)
   check(adapter:execute(-1,player,key)==T.cases[key].expected[tostring(job)],'sword/mage task rank compatibility: '..job..'/'..key)
   check(get(player,'CHAR_职业')==job,'condition does not change profession')
  end
 end
 R.native_predicates=predicates
 local ranges,extensions=0,0
 R.raw_job_reads={}
 for _,c in ipairs(dofile('lua/Modules/sharedTaskAdaptersData.lua')) do
  if c.jobRangeJobs then
   ranges=ranges+1
   local extended=false
   for job=181,187 do
    local expected=0
    for _,id in ipairs(c.jobRangeJobs) do if id==job or id==job-170 or id==job-110 then expected=1 end end
    local present=false;for _,id in ipairs(c.jobRangeJobs) do if id==job then present=true end end
    if expected==1 and not present then extended=true end
    check(Jobs.range(job,c.jobRangeJobs)==expected,'shared task range: '..job..'/'..c.key)
   end
   if extended then extensions=extensions+1 end
  elseif c.target=='player' and c.field=='CHAR_职业' and c.value==nil then
   R.raw_job_reads[#R.raw_job_reads+1]={key=c.key,source=c.source}
  end
 end
 R.shared_ranges=ranges;R.shared_range_extensions=extensions
 for job=181,187 do
  check(Jobs.range(job,{21,22,23,24,25,26,27})==0,'unrelated profession is not admitted')
  check(Jobs.promotedJob(job,16)==186 and Jobs.promotedJob(job,76)==186,'both promotion paths retain magic profession')
 end
 check(Jobs.promotedJob(15,16)==16 and Jobs.promotedJob(75,76)==76,'other profession promotions unchanged')
 -- Exercise the actual promotion writer, including family retention.
 local god=NL.CreateArgNpc('Event','','神邸',14058,0,64035,10,10,4)
 check(god>=0,'promotion fixture NPC')
 check(Char.Warp(player,0,64035,10,11),'promotion fixture position')
 for _,key in ipairs({'stp:legacy:ffa50744ac1a6434b543','stp:legacy:16bf136e0ae301ce1b47'}) do
  Char.SetData(player,CONST.CHAR_职业,185);Char.SetData(player,CONST.CHAR_职类ID,180)
  check(adapter:execute(god,player,key)==1,'native adapter promotion reward executes')
  check(get(player,'CHAR_职业')==186 and get(player,'CHAR_职类ID')==180,'promotion reward remains magic swordsman')
 end
 NL.DelNpc(god)
 -- The extreme challenge uses the installed Event predicate and native map.
 local extreme=occupants(227,83)[1]
 check(Map.IsWalkable(0,60110,16,23)==1,'extreme challenge destination is loaded and walkable')
 for job=181,187 do
  Char.Warp(player,0,1000,227,84);Char.SetData(player,CONST.CHAR_职业,job)
  check(adapter:execute(extreme,player,'stp:legacy:5428088f432a1862570d')==1,'extreme challenge accepts magic rank: '..job)
  check(Char.Warp(player,0,60110,16,23),'extreme challenge native transport: '..job)
  check(get(player,'CHAR_地图')==60110 and get(player,'CHAR_职业')==job,'challenge arrival retains profession')
 end
 Char.Warp(player,0,1000,227,84);Char.SetData(player,CONST.CHAR_职业,1)
 check(adapter:execute(extreme,player,'stp:legacy:5428088f432a1862570d')==0,'original novice restriction retained')
 Char.Warp(player,0,1000,220,84);Char.SetData(player,CONST.CHAR_职业,181)
 check(adapter:execute(extreme,player,'stp:legacy:5428088f432a1862570d')==0,'remote entry condition rejected')
 local stone=occupants(231,83)[1]
 check(NLG.GetArgNpc(stone)=='0|1548|21|31|15||0|0|||||','world trade stone destination preserved')
 check(Map.IsWalkable(0,1548,21,31)==1 and Char.Warp(player,0,1548,21,31),'world trade native destination works')
 local guide=assert(getModule('sharedTaskGuide'))
 local wanted={};for _,name in ipairs(T.guide_tasks) do wanted[name]=true end
 local tested=0
 for i,t in ipairs(dofile('lua/Modules/sharedTaskGuideData.lua').tasks) do
  if wanted[t.name] then
   local p
   for _,plan in ipairs(T.new) do if t.entry.name==plan.name then p=plan end end
   check(p and t.entry.x==p.after[1] and t.entry.y==p.after[2],'updated task guide coordinate: '..t.name)
   Char.Warp(player,0,1000,155,111)
   guide:show(guide.guide,player,math.ceil(i/6),i,1)
   check(guide.sessions[player]~=nil,'task guide menu opens')
   guide:answer(guide.guide,player,7291,0,'1')
   check(get(player,'CHAR_地图')==1000 and math.abs(get(player,'CHAR_X')-p.after[1])<=3
     and math.abs(get(player,'CHAR_Y')-p.after[2])<=3,'guide reaches moved quest NPC')
   tested=tested+1
  end
 end
 check(tested==#T.guide_tasks,'all changed guide entries tested');R.guide_warps=tested
end
Cron.AddInterval(1500,function()
 local ok,err=xpcall(function()
  R.original={}
  for _,p in ipairs(T.plans) do
   local n=find(p);R.original[p.name]={npc=n,x=get(n,'CHAR_X'),y=get(n,'CHAR_Y')}
  end
  if T.mode=='hot' then
   local pos=T.new[1].after
   local blocker=NL.CreateArgNpc('Event','','LAYOUT_BLOCKER',14058,0,1000,pos[1],pos[2],4)
   check(blocker>=0,'fixed blocker created')
   local success,why=pcall(dofile,'lua/npcOverlapFix.lua');NL.DelNpc(blocker)
   check(not success and tostring(why):find('another NPC blocks',1,true),'fixed collision rejected before moves')
   for _,p in ipairs(T.plans) do
    local v=R.original[p.name]
    check(get(v.npc,'CHAR_X')==v.x and get(v.npc,'CHAR_Y')==v.y,'preflight failure leaves positions unchanged')
   end
   for _,p in ipairs(T.new) do
    local n=Char.CreateDummy({mapType=0,floor=1000,x=p.after[1],y=p.after[2],image=100002,name='STANDING_PLAYER'})
    check(n>=0,'player on target fixture');standers[#standers+1]=n
   end
  end
  R.hotfix=dofile('lua/npcOverlapFix.lua')
  check(R.hotfix.status=='PASS' and R.hotfix.moved==T.expected_moves,'expected hotfix move count')
  check(R.hotfix.adapters_reloaded,'task job compatibility loaded by hotfix')
  for i,n in ipairs(standers) do
   check(get(n,'CHAR_X')==T.new[i].after[1] and get(n,'CHAR_Y')==T.new[i].after[2],'standing player was not moved')
  end
  for _,n in ipairs(standers) do Char.DelDummy(n) end;standers={}
  Cron.AddInterval(1500,function()
   local passed,error=xpcall(validate,debug.traceback);finish(not passed and error or nil)
  end,0)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
