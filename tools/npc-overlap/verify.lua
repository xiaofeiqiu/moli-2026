return function(R)
 local plans=dofile('lua/npc_overlap_plans.lua')
 local function check(ok,label)
  R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label)
 end
 R.positions={}
 for _,p in ipairs(plans) do
  local x,y=p.after[1],p.after[2]
  local count,objects=Obj.GetObject(0,1000,x,y)
  local npcs={}
  for _,o in ipairs(objects or {}) do
   local n=Obj.GetCharIndex(o)
   if n>=0 and not Char.IsPlayer(n) and not Char.IsPet(n) then npcs[#npcs+1]=n end
  end
  check(#npcs==1,'one NPC at '..p.name)
  local n=npcs[1]
  check(Char.GetData(n,CONST.CHAR_名字)==p.name,'name preserved '..p.name)
  check(Char.GetData(n,CONST.CHAR_形象)==p.image,'image preserved '..p.name)
  check(Char.GetData(n,CONST.CHAR_X)==x and Char.GetData(n,CONST.CHAR_Y)==y,'coordinates '..p.name)
  check(Map.IsWalkable(0,1000,x,y)==1,'walkable NPC tile '..p.name)
  local approach=p.approach or {x,y+1}
  check(Map.IsWalkable(0,1000,approach[1],approach[2])==1 and Obj.GetObject(0,1000,approach[1],approach[2])==0,
   'clear approach '..p.name)
  if R.original_indices then check(n==R.original_indices[p.name],'same native NPC object '..p.name) end
  R.positions[#R.positions+1]={name=p.name,x=x,y=y,npc=n,total_objects=count}
 end
 for _,x in ipairs({229,233,234}) do
  check(Obj.GetObject(0,1000,x,83)==1,'overlap removed at '..x..',83')
 end
 if #plans>5 then
  check(Obj.GetObject(0,1000,223,83)==1,'hospital sign no longer hides NPCs')
  check(Obj.GetObject(0,1000,235,116)==1,'overlap removed at 235,116')
 end
 for x=225,233 do
  check(Map.IsWalkable(0,1000,x,86)==1 and Obj.GetObject(0,1000,x,86)==0,'continuous approach lane '..x)
 end
 local again=dofile('lua/npcOverlapFix.lua')
 check(again.status=='PASS' and again.moved==0 and again.already_correct==#plans,'repeated repair is harmless')
 local m=assert(getModule('sharedTaskGuide'))
 local guide=m.guide
 local count=Obj.GetObject(0,1000,155,112)
 check(count==1,'one task guide after repair')
 local data=dofile('lua/Modules/sharedTaskGuideData.lua')
 local wanted={}
 for _,name in ipairs(dofile('lua/npc_overlap_guide_tasks.lua')) do wanted[name]=true end
 local dummy=Char.CreateDummy({mapType=0,floor=1000,x=155,y=111,image=100002,name='NPC_LAYOUT_VALIDATOR'})
 check(dummy>=0,'dummy creation')
 local tested=0
 local ok,err=pcall(function()
  for i,t in ipairs(data.tasks) do
   for _,p in ipairs(plans) do
    if wanted[t.name] and t.entry and t.entry.name==p.name and t.entry.floor==1000 then
     check(t.entry.x==p.after[1] and t.entry.y==p.after[2],'guide coordinates '..p.name)
     Char.Warp(dummy,0,1000,155,111)
     m:show(guide,dummy,math.ceil(i/6),i,1)
     check(m.sessions[dummy]~=nil,'guide menu '..p.name)
     m:answer(guide,dummy,7291,0,'1')
     check(Char.GetData(dummy,CONST.CHAR_地图)==1000
      and math.abs(Char.GetData(dummy,CONST.CHAR_X)-p.after[1])<=3
      and math.abs(Char.GetData(dummy,CONST.CHAR_Y)-p.after[2])<=3,'guide warp reaches '..p.name)
     tested=tested+1
    end
   end
  end
 end)
 Char.DelDummy(dummy)
 assert(ok,err)
 check(tested==#dofile('lua/npc_overlap_guide_tasks.lua'),'all changed guide entries tested')
 R.guide_warps=tested
end
