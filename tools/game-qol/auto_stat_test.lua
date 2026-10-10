local R={status='RUNNING',checks={},messages={},windows={},petUUIDs={},production_accounts_used=false,client_verified=false}
local p,q=-1,-1
local M=assert(getModule('autoStat'))
local oldMessage,oldWindow=NLG.SystemMessage,NLG.ShowWindowTalked
local fields={'CHAR_体力','CHAR_力量','CHAR_强度','CHAR_速度','CHAR_魔法'}
local function get(c,k) return Char.GetData(c,CONST[k]) end
local function set(c,k,v) return Char.SetData(c,CONST[k],v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function stats(c) local r={};for i,k in ipairs(fields) do r[i]=get(c,k) end;return r end
local function equal(a,b) for i=1,5 do if a[i]~=b[i] then return false end end;return true end
local function grow(c)
 local level=get(c,'CHAR_等级');set(c,'CHAR_经验',Char.GetNextExp(c))
 if c==p or c==q then NLG.UpChar(c) else Pet.UpPet(p,c) end
 check(get(c,'CHAR_等级')==level+1,'native level advancement '..c)
end
local function menu(option)
 local fn=_G['autoStat_npc_'..M.npc..'_WindowTalkedEvent'];assert(fn)
 fn(M.npc,p,7310,0,tostring(option))
end
local function talk() _G['autoStat_npc_'..M.npc..'_TalkedEvent'](M.npc,p) end
local function finish(err)
 if err then R.status='FAIL';R.error=tostring(err) else R.status='PASS' end
 NLG.SystemMessage=oldMessage;NLG.ShowWindowTalked=oldWindow
 if p>=0 then pcall(Char.DelDummy,p) end
 if q>=0 then pcall(Char.DelDummy,q) end
 local f=assert(io.open('__OUTPUT__/auto_stat_test.json','wb'));f:write(JSON.encode(R));f:close()
end
NLG.SystemMessage=function(c,msg,...) R.messages[#R.messages+1]=msg;return oldMessage(c,msg,...) end
NLG.ShowWindowTalked=function(c,n,typ,button,seq,data)
 R.windows[#R.windows+1]={type=typ,button=button,seq=seq,data=data}
 return oldWindow(c,n,typ,button,seq,data)
end
local ok,err=xpcall(function()
 check(M.npc>=0 and #M.npcList==1,'one module-owned automatic stat NPC')
 check(get(M.npc,'CHAR_地图')==1000 and get(M.npc,'CHAR_X')==223 and get(M.npc,'CHAR_Y')==85,'NPC at east hospital (223,85)')
 check(Map.IsWalkable(0,1000,223,85)==1,'NPC tile is walkable')
 p=Char.CreateDummy({mapType=0,floor=1000,x=223,y=86,image=100002,name='AUTO_STAT_TEST'});check(p>=0,'isolated native player')
 set(p,'CHAR_账号','AUTO_STAT_PERSIST_WITNESS');set(p,'对象_RegistNumber',0)
 q=Char.CreateDummy({mapType=0,floor=1000,x=224,y=86,image=100002,name='AUTO_STAT_OTHER'});check(q>=0,'second isolated native player')
 check(not M:settings(p).player and next(M:settings(p).pets)==nil,'new character defaults to manual allocation')
 talk();check(M.sessions[p] and #M.sessions[p].actions==7,'actual NPC talked callback offers character plus all five pet slots')
 menu(2);check(R.messages[#R.messages]:match('没有宠物')~=nil,'empty pet option handled')
 talk();menu(1);menu(6)
 check(M.sessions[p].seq==7311 and R.windows[#R.windows].type==CONST['窗口_输入框'],'custom ratio opens native input dialog')
 for _,data in ipairs({'0 0 0 0 0','1 2 3 4','-1 2 0 1 0','1.5 2 0 1 0','100 100 100 100 100','1 2 0 1 0 junk'}) do
  talk();menu(1);menu(6);M:answer(M.npc,p,7311,CONST['按钮_确定'],data)
  check(not M:settings(p).player,'reject invalid ratio '..data)
 end
 talk();menu(1);menu(6)
 M:answer(M.npc,p,7311,CONST['按钮_关闭'],'1 2 0 1 0')
 check(not M:settings(p).player,'cancelled input does not save a plan')
 talk();menu(1);menu(6)
 M:answer(M.npc,p,7311,CONST['按钮_确定'],'1 2 0 1 0')
 check(M:settings(p).player.enabled and M:settings(p).player.weights[2]==2,'valid custom NPC ratio saved and enabled')
 set(p,'CHAR_升级点',7);set(p,'CHAR_经验',2000);NLG.UpChar(p)
 check(get(p,'CHAR_等级')==6 and get(p,'CHAR_升级点')==57,'native multi-level award is fifty points and keeps seven old points')
 check(M.pending[p] and M.pending[p].entries.player.before==7,'pre-award callback records existing balance')
 M:flushOwner(p)
 check(get(p,'CHAR_升级点')==7,'automatic allocation preserves existing unspent BP')
 local v=stats(p)
 check(v[1]==1300 and v[2]==2500 and v[3]==0 and v[4]==1200 and v[5]==0,'fifty actual points follow 1:2:0:1:0 ratio')
 M:flushOwner(p);check(equal(v,stats(p)) and get(p,'CHAR_升级点')==7,'repeated drain never spends points twice')
 local cap=((get(p,'CHAR_等级')-1)*2+15)*100
 check(M:setPlan(p,'player',{0,1,0,0,0}),'single-stat player plan saved')
 set(p,'CHAR_力量',cap);grow(p);M:flushOwner(p)
 check(get(p,'CHAR_力量')==cap+200 and get(p,'CHAR_升级点')==15,'player cap permits two new strength points and retains excess')
 check(M:setPlan(p,'player',nil,false),'player automation disabled without forgetting ratio')
 local before=stats(p);local bp=get(p,'CHAR_升级点');grow(p);M:flushOwner(p)
 check(equal(before,stats(p)) and get(p,'CHAR_升级点')==bp+10,'disabled plan leaves all upgrade points for manual allocation')
 check(M:setPlan(p,'player',nil,true),'stored player plan can be re-enabled')
 local pets={}
 for i=1,5 do
  pets[i]=Char.GivePet(p,3004,0);check(pets[i]>=0,'native pet fixture '..i)
  local id=tostring(Pet.GetUUID(pets[i]));R.petUUIDs[i]=id
  local w={0,0,0,0,0};w[i]=1
  check(M:setPlan(p,id,w),'independent plan saved for pet '..i)
  set(pets[i],'CHAR_升级点',3)
 end
 -- Use an unconfigured second owner's pet as a native-growth control.
 local control=Char.GivePet(q,3004,0);check(control>=0,'native pet growth control')
 for art=1,5 do
  Pet.SetArtRank(control,art,Pet.FullArtRank(control,art))
  for i=1,5 do Pet.SetArtRank(pets[i],art,Pet.FullArtRank(pets[i],art)) end
 end
 local baseline={}
 for i=1,5 do baseline[i]=stats(pets[i]);set(pets[i],'CHAR_经验',Char.GetNextExp(pets[i]));Pet.UpPet(p,pets[i]) end
 local controlBefore=stats(control);set(control,'CHAR_经验',Char.GetNextExp(control));Pet.UpPet(q,control)
 local controlAfter=stats(control)
 M:flushOwner(p)
 for i=1,5 do
  local after=stats(pets[i]);local manual=0
  -- Growth rolls are random; compare BP just before the module applies it below.
  for j=1,5 do check(after[j]>=baseline[i][j]+(i==j and 200 or 0),'pet native growth plus allocated BP '..i..'/'..j) end
  check(get(pets[i],'CHAR_升级点')==3,'old points preserved for pet '..i)
 end
 check(not M:settings(q).pets[tostring(Pet.GetUUID(control))] and get(control,'CHAR_升级点')==2,'unconfigured pet remains manual')
 local petBefore=stats(pets[1]);grow(pets[1]);local grown=stats(pets[1]);M:flushOwner(p);local petAfter=stats(pets[1])
 check(petAfter[1]==grown[1]+200,'pet automatic allocation adds exactly 100 native BP units per point')
 for i=2,5 do check(petAfter[i]==grown[i],'pet automatic allocation preserves native growth for unselected stat '..i) end
 check(Char.MovePet(p,0,4)==1,'native pet slot swap')
 check(Char.GetPet(p,4)==pets[1] and Char.GetPet(p,0)==pets[5],'pets moved to different slots')
 grow(pets[1]);grown=stats(pets[1]);M:flushOwner(p)
 check(stats(pets[1])[1]==grown[1]+200 and M:settings(p).pets[R.petUUIDs[1]].weights[1]==1,'pet plan follows unique ID after changing slots')
 check(M:setPlan(p,R.petUUIDs[1],{1,1,0,0,0}),'pet mixed ratio')
 set(pets[1],'CHAR_升级点',3)
 for pass=1,2 do grow(pets[1]);M:flushOwner(p) end
 check(get(pets[1],'CHAR_升级点')==3,'mixed pet plan preserves old point balance')
 -- Uneven custom ratios must retain fractional credit across one-point awards.
 local saved=M:settings(p)
 saved.player={enabled=true,weights={1,2,0,0,0},credit={1,-1,0,0,0}}
 check(M:saveSettings(p,saved),'fractional allocation credit saved')
 local credits=JSON.encode(M:settings(p).player.credit)
 reloadModule('autoStat');M=assert(getModule('autoStat'))
 check(JSON.encode(M:settings(p).player.credit)==credits,'fractional allocation credit survives module reload')
 check(#M.npcList==1 and get(M.npc,'CHAR_X')==223,'reload owns one NPC')
 talk();menu(2);menu(6)
 local session=M.sessions[p]
 check(session.ref==R.petUUIDs[5],'pet menu resolves current slot to unique ID')
 check(Char.TradePet(p,0,q)==1,'native trade removes the selected pet from owner')
 M:answer(M.npc,p,7311,CONST['按钮_确定'],'0 1 0 0 0')
 check(M:settings(p).pets[R.petUUIDs[5]].weights[5]==1,'stale pet input cannot reconfigure a traded pet')
 check(not M:settings(q).pets[R.petUUIDs[5]],'new owner does not inherit previous owner automatic preferences')
 talk();menu(1);menu(6);set(p,'CHAR_X',230)
 M:answer(M.npc,p,7311,CONST['按钮_确定'],'0 0 1 0 0')
 check(M:settings(p).player.weights[2]==2,'remote NPC response is rejected')
 set(p,'CHAR_X',223)
 talk();menu(1);menu(6);M.sessions[p].expires=os.time()-1
 M:answer(M.npc,p,7311,CONST['按钮_确定'],'0 0 1 0 0')
 check(M:settings(p).player.weights[2]==2,'expired NPC response is rejected')
 talk();menu(1);menu(6)
 M:answer(M.npc,p,7310,CONST['按钮_确定'],'0 0 1 0 0')
 check(M:settings(p).player.weights[2]==2,'wrong window sequence is rejected')
 talk();set(p,'CHAR_BattleMode',1);menu(1);check(M.sessions[p]==nil,'battle blocks NPC configuration');set(p,'CHAR_BattleMode',0)
 -- A database failure must preserve both native stats and the BP balance.
 check(M:setPlan(p,'player',{1,0,0,0,0}),'plan for failed-write regression')
 grow(p);local failedStats=stats(p);local failedBP=get(p,'CHAR_升级点')
 local oldSQL=SQL.QueryEx
 SQL.QueryEx=function(sql,...) if sql:match('^REPLACE INTO hook_charaext') then return {status=99,effectRows=0} end;return oldSQL(sql,...) end
 M:flushOwner(p);SQL.QueryEx=oldSQL
 check(equal(failedStats,stats(p)) and get(p,'CHAR_升级点')==failedBP,'database write failure never consumes awarded points')
 check(M:setPlan(p,'player',{1,2,0,1,0}),'final persisted player plan')
 check(M:setPlan(p,R.petUUIDs[1],nil,false),'final persisted disabled pet plan')
 local sql=SQL.QueryEx('SELECT val FROM hook_charaext WHERE cdKey=? AND regNo=0 AND sKey=?','AUTO_STAT_PERSIST_WITNESS','AutoStatConfigV1')
 check(sql.status==0 and sql.rows and #sql.rows==1,'configuration durably written to isolated SQLite')
 R.persisted=JSON.decode(sql.rows[1].val)
 check(R.persisted.player.weights[2]==2 and not R.persisted.pets[R.petUUIDs[1]].enabled,'saved player and pet plans retain distinct settings')
 -- Use the actual Cron interval, rather than an explicit manual drain.
 grow(p);local timerBP=get(p,'CHAR_升级点')
 M:AddInterval(600,function()
  local success,error=xpcall(function()
   check(get(p,'CHAR_升级点')==timerBP-10,'actual scheduled drain distributes a native upgrade award')
   local _,objects=Obj.GetObject(0,1000,223,85);local count=0
   for _,obj in ipairs(objects or {}) do if Obj.GetType(obj)==1 then local c=Obj.GetCharIndex(obj);if c>=0 and get(c,'CHAR_名字')=='自动加点师' then count=count+1 else error('NPC tile overlaps '..tostring(c)) end end end
   check(count==1,'fully loaded native map has one NPC and no overlap at hospital tile')
  end,debug.traceback)
  finish(not success and error or nil)
 end,0)
end,debug.traceback)
if not ok then finish(err) end
