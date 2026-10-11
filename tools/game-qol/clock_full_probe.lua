local R={status='RUNNING',checks={},production_database_modified=false}
local p=-1;local captured={};local original=NLG.SystemMessage
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function get(k) return Char.GetData(p,CONST[k]) end
local function set(k,v) Char.SetData(p,CONST[k],v) end
NLG.SystemMessage=function(q,text,...) if q==p then captured[#captured+1]=text end;return original(q,text,...) end
local function send(msg) captured={};check(TalkEvent(p,msg,0,0,0)==0,'consumed '..msg);return table.concat(captured,'\n') end
local ok,err=xpcall(function()
 local M=assert(getModule('gameQoL'))
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='CLOCK_FULL_TEST'});check(p>=0,'isolated player created')
 local hours;local f=assert(io.open('cgmsv.cf','rb'));for line in f:lines() do local n=line:match('^%s*fevermax%s*=%s*(%d+)%s*$');if n then hours=tonumber(n) end end;f:close();check(hours and hours>0,'configured card-time cap read')
 send('/clock off');set('CHAR_卡时',0)
 check(Char.IsFeverTime(p)==0,'clock starts empty and stopped')
 send('/clock full')
 check(get('CHAR_卡时')==hours*3600,'empty card time filled to configured cap')
 check(Char.IsFeverTime(p)==1,'full immediately starts native fever')
 check(not M:settings(p).autoclock,'manual full preserves automatic clock preference')
 send('/clock off');set('CHAR_卡时',2*3600)
 check(Char.FeverStart(p)==1,'start old two-hour native countdown')
 check(Char.IsFeverTime(p)==1 and get('CHAR_卡时')<=2*3600,'old countdown remains two hours')
 send('/clock full')
 check(Char.IsFeverTime(p)==1 and get('CHAR_卡时')==hours*3600,'running two-hour countdown replaced with full six hours')
 local dummy,save=Char.IsDummy,Char.SaveToDb
 local saved=0
 Char.IsDummy=function(q) if q==p then return false end;return dummy(q) end
 Char.SaveToDb=function(q)
  check(q==p,'save only requesting player')
  check(Char.IsFeverTime(q)==1,'save observes running native timer')
  saved=get('CHAR_卡时');return 0
 end
 local called,result=pcall(M.fillClock,M,p)
 Char.IsDummy=dummy;Char.SaveToDb=save
 check(called and result==true and saved==hours*3600,'save synchronized full native countdown')
 Char.IsDummy=function(q) if q==p then return false end;return dummy(q) end
 Char.SaveToDb=function() return -1 end
 called,result=pcall(M.fillClock,M,p)
 Char.IsDummy=dummy;Char.SaveToDb=save
 check(called and result==false,'save failure not reported as success')
 check(captured[#captured]:find('保存失败',1,true)~=nil,'save failure explained')
 set('CHAR_卡时',100);send('/CLOCK FULL')
 check(get('CHAR_卡时')==hours*3600 and Char.IsFeverTime(p)==1,'running clock refills with case-insensitive command')
 set('CHAR_卡时',123)
 for _,msg in ipairs({'/clock full extra','/clock invalid'}) do local text=send(msg);check(text:find('/clock [on|off|full]',1,true)~=nil and get('CHAR_卡时')==123,'invalid parameters rejected '..msg) end
 send('/clock off');set('CHAR_卡时',123);set('CHAR_BattleMode',1)
 send('/clock full');check(get('CHAR_卡时')==123 and Char.IsFeverTime(p)==0,'battle blocks refill and start');set('CHAR_BattleMode',0)
 M.stalls[p]=true;send('/clock full');check(get('CHAR_卡时')==123 and Char.IsFeverTime(p)==0,'stall blocks refill and start');M.stalls[p]=nil
 local help=send('/help clock');check(help:find('/clock [on|off|full]',1,true) and help:find('/clock full',1,true) and help:find('fevermax',1,true),'help documents parameter example and limit')
 check(reloadModule('gameQoL')~=nil,'module reload succeeds');send('/clock full');check(get('CHAR_卡时')==hours*3600 and Char.IsFeverTime(p)==1,'command survives reload')
 R.status='PASS'
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err) end
NLG.SystemMessage=original
if p>=0 then pcall(Char.FeverStop,p);pcall(Char.DelDummy,p) end
local f=assert(io.open('__OUTPUT__/clock_full_native.json','wb'));f:write(JSON.encode(R));f:close()
