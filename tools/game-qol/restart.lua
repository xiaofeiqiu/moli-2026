local R={status='RUNNING',checks={}}
local p=-1
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=ok and true or false};assert(ok,label) end
local ok,err=xpcall(function()
 local M=assert(getModule('gameQoL'))
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='QOL_RESTART_TEST'})
 check(p>=0,'isolated restart player')
 Char.SetData(p,CONST['CHAR_账号'],'QOL_PERSIST_WITNESS');Char.SetData(p,CONST['对象_RegistNumber'],0)
 local cfg=M:settings(p)
 check(cfg.autoidentify==true,'autoidentify enabled after process restart')
 check(cfg.autosell==true,'autosell enabled after process restart')
 check(cfg.autostack==false,'autostack disabled after process restart')
 check(cfg.autoclock==false,'autoclock disabled after process restart')
 check(Char.IsFeverTime(p)==0,'disabled clock stays off after process restart')
 check(Char.GetBagPage(p)==0 and CONST.EXTBAGPAGE==3,'four backpacks configured after restart')
 R.status='PASS'
end,debug.traceback)
if p>=0 then pcall(Char.DelDummy,p) end
if not ok then R.status='FAIL';R.error=tostring(err) end
local f=assert(io.open('__OUTPUT__/restart_result.json','wb'));f:write(JSON.encode(R));f:close()
