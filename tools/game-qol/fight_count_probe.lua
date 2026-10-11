local R={status='RUNNING',checks={},encounters={},production_database_modified=false}
local F=assert(getModule('fight'));local actors={};local captured={};local original=NLG.SystemMessage;local input
local T=ModuleBase:createModule('fightCountProbe'):new();T:load()
local function get(p,k) return Char.GetData(p,CONST[k]) end
local function set(p,k,v) Char.SetData(p,CONST[k],v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
NLG.SystemMessage=function(q,text,...) captured[#captured+1]=text;return original(q,text,...) end
T:regCallback('VSEnemyCreateEvent',OrderedCallback(function(p,group,n,list) input={group=group,n=n,list=list};return list end,100))
local function send(p,msg) captured={};input=nil;check(TalkEvent(p,msg,0,0,0)==0,'consumed '..msg);return table.concat(captured,'\n') end
local function leave(p) if Char.GetBattleIndex(p)>=0 then Battle.ExitBattle(p) end;set(p,'CHAR_BattleIndex',-1);set(p,'CHAR_BattleMode',0) end
local function dummy(floor,x,y)
 local p=Char.CreateDummy({mapType=0,floor=floor,x=x,y=y,image=100002,name='FIGHT_COUNT_TEST'});assert(p>=0);actors[#actors+1]=p
 set(p,'CHAR_等级',50);set(p,'CHAR_体力',50000);NLG.UpChar(p);set(p,'CHAR_血',get(p,'CHAR_最大血'));return p
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
 local p=dummy(100,665,184)
 for _,requested in ipairs({1,3,10,0,10,0}) do
  local cmd=requested==0 and '/fight' or '/fight '..requested
  send(p,cmd);local b=Char.GetBattleIndex(p)
  check(b>=0,'native encounter starts '..cmd)
  local n=0;for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 and Char.IsEnemy(q) then n=n+1 end end
  R.encounters[#R.encounters+1]={command=cmd,count=n,input=input}
  check(requested==0 and input and n==input.n or n==requested,'actual enemy count '..cmd..' got '..n)
  check(F.encounterCounts[p]==nil,'request cleared '..cmd)
  leave(p)
 end
 for _,arg in ipairs({'0','11','-1','1.5','10 extra','abc'}) do
  local text=send(p,'/fight '..arg);check(Char.GetBattleIndex(p)<0 and text:find('/fight [1~10]',1,true),'invalid argument rejected '..arg)
 end
 check(TalkEvent(p,'/fight!',0,0,0)==1,'invalid command suffix remains chat')
 set(p,'CHAR_血',0);send(p,'/fight 10');check(Char.GetBattleIndex(p)<0,'dead player rejected');set(p,'CHAR_血',get(p,'CHAR_最大血'))
 set(p,'CHAR_BattleMode',1);send(p,'/fight 10');check(Char.GetBattleIndex(p)<0,'battle state rejected');set(p,'CHAR_BattleMode',0)
 local member=dummy(100,665,184);check(Char.JoinParty(member,p,true)==0,'party joins')
 send(member,'/fight 10');check(Char.GetBattleIndex(member)<0,'party member rejected')
 send(p,'/fight 10');local b=Char.GetBattleIndex(p);local n=0;for pos=10,19 do if Battle.GetPlayer(b,pos)>=0 then n=n+1 end end
 check(b>=0 and n==10 and Char.GetBattleIndex(member)==b,'leader creates ten-enemy party encounter')
 leave(p);leave(member);Char.LeaveParty(member);Char.LeaveParty(p)
 local city=dummy(1000,225,75);send(city,'/fight 10');check(Char.GetBattleIndex(city)<0 and F.encounterCounts[city]==nil,'non-encounter map rejects and clears count')
 local help=send(p,'/help fight');check(help:find('/fight [1~10]',1,true) and help:find('/fight 10',1,true),'help documents quantity and example')
 check(reloadModule('fight')~=nil,'fight reload succeeds');F=assert(getModule('fight'));send(p,'/FIGHT 10');b=Char.GetBattleIndex(p);n=0;for pos=10,19 do if Battle.GetPlayer(b,pos)>=0 then n=n+1 end end;check(b>=0 and n==10,'uppercase quantity command works after reload');leave(p)
 R.status='PASS'
 end,debug.traceback)
 if not ok then R.status='FAIL';R.error=tostring(err) end
 NLG.SystemMessage=original
 for _,p in ipairs(actors) do pcall(leave,p);pcall(Char.LeaveParty,p);pcall(Char.DelDummy,p) end
 local f=assert(io.open('__OUTPUT__/fight_count_native.json','wb'));f:write(JSON.encode(R));f:close()
end,0)
