local T=dofile('lua/east_gate_test_data.lua')
local R={status='RUNNING',mode=T.mode,checks={},positions={},production_accounts_used=false,client_click_verified=false}
local player=-1
local function get(n,k) return Char.GetData(n,CONST[k]) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function occupants(x,y)
 local npcs={};local _,objects=Obj.GetObject(0,1000,x,y)
 for _,o in ipairs(objects or {}) do if Obj.GetType(o)==1 then
  local c=Obj.GetCharIndex(o)
  if not Char.IsPlayer(c) and not Char.IsPet(c) then npcs[#npcs+1]=c end
 end end
 return npcs
end
local function find(p)
 local ns={}
 for _,xy in ipairs({p.before,p.after}) do for _,n in ipairs(occupants(xy[1],xy[2])) do
  if get(n,'CHAR_名字')==p.name and get(n,'CHAR_形象')==p.image then ns[#ns+1]=n end
 end end
 check(#ns==1,'one matching original NPC '..p.id)
 return ns[1]
end
local function finish(err)
 if player>=0 then Char.DelDummy(player) end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local f=assert(io.open('__OUTPUT__','wb'));f:write(JSON.encode(R));f:close()
end
Cron.AddInterval(1500,function()
 local ok,err=xpcall(function()
  local originals={}
  for _,p in ipairs(T.new) do
   local n=find(p);originals[p.id]={npc=n,arg=NLG.GetArgNpc(n)}
   check(originals[p.id].arg~='','original Event script configured '..p.id)
  end
  local anchors={{x=278,y=82,name='李林',image=106127},{x=218,y=83,name='寻人布告栏',image=11562}}
  for _,a in ipairs(anchors) do
   local match
   for _,n in ipairs(occupants(a.x,a.y)) do if get(n,'CHAR_名字')==a.name and get(n,'CHAR_形象')==a.image then match=n end end
   check(match~=nil,'original anchor exists '..a.name);a.npc=match
  end
  if T.mode=='hot' then
   for _,a in ipairs(anchors) do check(#occupants(a.x,a.y)==2,'reported overlap reproduced '..a.name) end
  end
  R.repair=dofile('lua/npcOverlapFix.lua')
  check(R.repair.moved==(T.mode=='hot' and 2 or 0),'only two new NPCs moved')
  check(R.repair.already_correct==#T.plans-R.repair.moved,'existing repairs retained')
  player=Char.CreateDummy({mapType=0,floor=1000,x=277,y=84,image=100002,name='EAST_GATE_PROBE'})
  check(player>=0,'isolated test player')
  for _,p in ipairs(T.new) do
   local ns=occupants(p.after[1],p.after[2]);check(#ns==1,'one NPC at new position '..p.id)
   local n=ns[1]
   check(n==originals[p.id].npc,'same NPC object retained '..p.id)
   check(get(n,'CHAR_名字')==p.name and get(n,'CHAR_形象')==p.image,'name and appearance retained '..p.id)
   check(NLG.GetArgNpc(n)==originals[p.id].arg,'original dialogue script retained '..p.id)
   check(Map.IsWalkable(0,1000,p.after[1],p.after[2])==1,'new position walkable '..p.id)
   local _,image=Map.GetImage(0,1000,p.after[1],p.after[2]);check(image==0,'no map decoration at new position '..p.id)
   check(Map.IsWalkable(0,1000,p.approach[1],p.approach[2])==1 and Obj.GetObject(0,1000,p.approach[1],p.approach[2])==0,'clear dialogue approach '..p.id)
   check(Char.Warp(player,0,1000,p.approach[1],p.approach[2]),'reach new dialogue approach '..p.id)
   local canTalk=false
   for direction=0,7 do
    Char.SetData(player,CONST.CHAR_方向,direction)
    local allowed=NLG.CanTalk(n,player)
    if allowed==1 or allowed==true then canTalk=true end
   end
   check(canTalk,'native dialogue range permits talking '..p.id)
   R.positions[#R.positions+1]={name=p.name,image=p.image,x=p.after[1],y=p.after[2],arg=NLG.GetArgNpc(n)}
  end
  for _,a in ipairs(anchors) do
   local ns=occupants(a.x,a.y)
   check(#ns==1 and ns[1]==a.npc,'anchor stays alone at original position '..a.name)
  end
  local again=dofile('lua/npcOverlapFix.lua')
  check(again.moved==0 and again.already_correct==#T.plans,'repair is repeatable without creating NPCs')
 end,debug.traceback)
 finish(not ok and err or nil)
end,0)
