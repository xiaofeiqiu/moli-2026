local R={status='RUNNING',checks={},production_accounts_used=false}
local p=-1
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local ok,err=xpcall(function()
 local M=assert(getModule('autoStat'))
 p=Char.CreateDummy({mapType=0,floor=1000,x=223,y=86,image=100002,name='AUTO_STAT_RESTART'});check(p>=0,'isolated restart character')
 Char.SetData(p,CONST['CHAR_账号'],'AUTO_STAT_PERSIST_WITNESS');Char.SetData(p,CONST['对象_RegistNumber'],0)
 local cfg=M:settings(p)
 check(cfg and cfg.player.enabled and cfg.player.weights[1]==1 and cfg.player.weights[2]==2 and cfg.player.weights[4]==1,'player custom ratio survives process restart')
 local f=assert(io.open('__OUTPUT__/auto_stat_test.json','rb'));local old=JSON.decode(f:read('*a'));f:close()
 check(cfg.pets[old.petUUIDs[1]] and not cfg.pets[old.petUUIDs[1]].enabled,'disabled pet scheme survives process restart')
 for i=2,5 do check(cfg.pets[old.petUUIDs[i]] and cfg.pets[old.petUUIDs[i]].weights[i]==1,'independent pet ratio survives restart '..i) end
 check(#M.npcList==1 and Char.GetData(M.npc,CONST['CHAR_X'])==223,'NPC automatically created on restart')
 -- A fresh owner's slot does not inherit a different pet's old plan.
 local pet=Char.GivePet(p,3004,0);check(pet>=0,'new pet after restart')
 check(not cfg.pets[tostring(Pet.GetUUID(pet))],'new pet in reused slot defaults to manual allocation')
 R.status='PASS'
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err) end
if p>=0 then pcall(Char.DelDummy,p) end
local f=assert(io.open('__OUTPUT__/auto_stat_restart.json','wb'));f:write(JSON.encode(R));f:close()
