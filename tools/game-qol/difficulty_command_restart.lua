local R={status='RUNNING',checks={}}
local actors={}
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local ok,err=xpcall(function()
 local M=assert(getModule('gameDifficulty'))
 for reg=0,1 do
  local p=Char.CreateDummy({mapType=0,floor=1000,x=150+reg,y=111,image=100002,name='DIFFICULTY_RESTART_'..reg})
  check(p>=0,'restart witness '..reg);actors[#actors+1]=p
  Char.SetData(p,CONST['CHAR_账号'],'DIFF_CMD_PERSIST');Char.SetData(p,CONST['对象_RegistNumber'],reg)
  check(M:preference(p)==(reg==0 and 5 or 1),'preference survives full process restart '..reg)
 end
 check(#(M.npcList or {})==0,'no difficulty NPC after restart')
 R.status='PASS'
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err) end
for _,p in ipairs(actors) do pcall(Char.DelDummy,p) end
local f=assert(io.open('__OUTPUT__/command_restart.json','wb'));f:write(JSON.encode(R));f:close()
