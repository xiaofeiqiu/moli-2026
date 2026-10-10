local R={status='RUNNING',checks={},production_accounts_used=false}
Cron.AddInterval(1000,function()
 local ok,err=xpcall(function()
  R.hotfix=dofile('lua/npcOverlapFix.lua')
  assert(R.hotfix.moved==0 and R.hotfix.already_correct==#dofile('lua/npc_overlap_plans.lua'),'DATA did not persist all positions')
  dofile('lua/npc_overlap_verify.lua')(R)
 end,debug.traceback)
 R.status=ok and 'PASS' or 'FAIL';if not ok then R.error=tostring(err) end
 local f=assert(io.open('__OUTPUT__','w'));f:write(JSON.encode(R));f:close()
end,0)
