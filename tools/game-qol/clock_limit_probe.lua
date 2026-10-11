-- The disposable server starts with fevermax=2, then the file changes to 6.
local R={status='RUNNING',checks={},engine_hours_at_start=2,production_database_modified=false}
local p=-1;local captured={};local original=NLG.SystemMessage
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
NLG.SystemMessage=function(q,text,...) if q==p then captured[#captured+1]=text end;return original(q,text,...) end
local path='cgmsv.cf';local f=assert(io.open(path,'rb'));local before=f:read('*a');f:close()
local ok,err=xpcall(function()
 check(before:find('fevermax=2',1,true)~=nil,'isolated engine starts with two-hour cap')
 local after,count=before:gsub('fevermax=2','fevermax=6');check(count==1,'change only isolated file cap')
 f=assert(io.open(path,'wb'));f:write(after);f:close()
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='CLOCK_OLD_CAP_TEST'});check(p>=0,'isolated player')
 local M=assert(getModule('gameQoL'))
 check(M:fillClock(p)==false,'old engine cap does not falsely report six hours')
 check(Char.IsFeverTime(p)==1 and Char.GetData(p,CONST['CHAR_卡时'])==7200,'native timer reflects actual two-hour cap')
 R.messages=captured
 local text=table.concat(captured,'\n')
 check(text:find('120 分钟',1,true) and text:find('重启服务端',1,true),'actual duration and restart guidance')
 check(not text:find('已补满至 6 小时',1,true),'no false six-hour success')
end,debug.traceback)
f=assert(io.open(path,'wb'));f:write(before);f:close()
NLG.SystemMessage=original
if p>=0 then pcall(Char.FeverStop,p);pcall(Char.DelDummy,p) end
R.status=ok and 'PASS' or 'FAIL';R.error=not ok and tostring(err) or nil
f=assert(io.open('__OUTPUT__/clock_limit_native.json','wb'));f:write(JSON.encode(R));f:close()
