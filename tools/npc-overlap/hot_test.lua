local R={status='RUNNING',checks={},production_accounts_used=false,original_indices={}}
local standers={}
local function cleanup() for _,n in ipairs(standers) do Char.DelDummy(n) end end
local function write()
 local f=assert(io.open('__OUTPUT__','w'));f:write(JSON.encode(R));f:close()
end
Cron.AddInterval(1000,function()
 local ok,err=xpcall(function()
  for _,p in ipairs(dofile('lua/npc_overlap_plans.lua')) do
   local _,objects=Obj.GetObject(0,1000,p.before[1],p.before[2])
   for _,o in ipairs(objects or {}) do
    local n=Obj.GetCharIndex(o)
    if n>=0 and Char.GetData(n,CONST.CHAR_名字)==p.name then R.original_indices[p.name]=n end
   end
   assert(R.original_indices[p.name],'original NPC not loaded '..p.name)
  end
  local blocker=NL.CreateArgNpc('Event','stp_c052a74aae08594f14.txt','LAYOUT_BLOCKER',106479,0,1000,233,85,4)
  assert(blocker>=0,'blocker NPC creation failed')
  local blocked,why=pcall(dofile,'lua/npcOverlapFix.lua')
  R.blocker_error=tostring(why)
  NL.DelNpc(blocker)
  assert(not blocked and tostring(why):find('another NPC blocks',1,true),'fixed NPC collision was not rejected')
  for _,p in ipairs(dofile('lua/npc_overlap_plans.lua')) do
   local n=R.original_indices[p.name]
   assert(Char.GetData(n,CONST.CHAR_X)==p.before[1] and Char.GetData(n,CONST.CHAR_Y)==p.before[2],
    'failed preflight moved an NPC '..p.name)
   local player=Char.CreateDummy({mapType=0,floor=1000,x=p.after[1],y=p.after[2],image=100002,name='STANDING_PLAYER'})
   assert(player>=0,'standing player creation failed');standers[#standers+1]=player
  end
  R.fixed_NPC_blocker_rejected_without_moves=true
  R.players_on_all_targets=#standers
  R.hotfix=dofile('lua/npcOverlapFix.lua')
  assert(R.hotfix.status=='PASS' and R.hotfix.moved==#standers and R.hotfix.guide_reloaded,'hotfix did not move all NPCs')
  for i,p in ipairs(dofile('lua/npc_overlap_plans.lua')) do
   assert(Char.GetData(standers[i],CONST.CHAR_X)==p.after[1] and Char.GetData(standers[i],CONST.CHAR_Y)==p.after[2],
    'hotfix moved a standing player')
  end
  R.standing_players_unchanged=true
 end,debug.traceback)
 if not ok then R.status='FAIL';R.error=tostring(err);cleanup();write();return end
 Cron.AddInterval(2000,function()
  local ok,err=xpcall(function() dofile('lua/npc_overlap_verify.lua')(R) end,debug.traceback)
  R.status=ok and 'PASS' or 'FAIL';if not ok then R.error=tostring(err) end;cleanup();write()
 end,0)
end,0)
