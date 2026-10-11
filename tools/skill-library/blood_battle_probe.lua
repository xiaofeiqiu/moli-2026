-- Native Lua casts with wire capture; only disposable dummy characters.
local R={status='RUNNING',checks={},npcs={},cases={},production_accounts_used=false,client_verified=false}
local T=ModuleBase:createModule('bloodBattleProbe'):new();T:load()
local M=assert(getModule('skillLibrary'));local D=dofile('lua/Modules/skillLibraryData.lua')
local specs={};for _,s in ipairs(D.skills) do specs[s.id]=s end
local active;local finished=false;local original=M.customCast;local serial=0
local entries={{81,1},{81,30},{4325,30},{4326,30},{4395,30},{4363,30}}
local function get(p,k) return Char.GetData(p,CONST[k]) end
local function set(p,k,v) Char.SetData(p,CONST[k],v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function write() local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close() end
local function finish(err)
 if finished then return end;finished=true
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 if active then pcall(Battle.ExitBattle,active.p);pcall(Char.DelDummy,active.p) end
 M.customCast=original;write()
end
local function capture(c)
 R.capture_requested=c.label;write();local stop=os.clock()+3
 repeat
  local f=io.open(('__REPORT__'):gsub('blood_battle_native_result.json','blood_capture_ack.json'),'rb')
  if f then
   local raw=f:read('*a');f:close();local ok,v=pcall(JSON.decode,raw)
   if ok and v.capture==c.label then c.packet=v.buffers.main..v.buffers.extra;return end
  end
 until os.clock()>stop
 error('capture timeout '..c.label)
end
M.customCast=function(self,b,p,use,skl,act)
 local c=active
 if not c or c.p~=p then return original(self,b,p,use,skl,act) end
 local ok,err=xpcall(function()
  c.beforeHP=get(p,'CHAR_血');c.beforeMaxHP=get(p,'CHAR_最大血');c.beforeMP=get(p,'CHAR_魔');c.beforeEnemyHP=get(c.q,'CHAR_血')
  c.beforeExp=Char.GetSkillExp(p,c.slot)
  c.animations={};c.actions={}
  original(self,b,p,use,function(...)
   c.animations[#c.animations+1]={...};return skl(...)
  end,function(...)
   c.actions[#c.actions+1]={...};return act(...)
  end)
  c.afterHP=get(p,'CHAR_血');c.afterMP=get(p,'CHAR_魔');c.afterEnemyHP=get(c.q,'CHAR_血')
  c.afterExp=Char.GetSkillExp(p,c.slot)
  c.damage=c.beforeEnemyHP-c.afterEnemyHP;c.heal=c.afterHP-c.beforeHP
  capture(c);c.cast=true
 end,debug.traceback)
 if not ok then finish(err) end
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('DamageCalculateEvent',function(a,d,o,damage,b) if active and active.b==b then return 0 end;return damage end)
T:regCallback('BattleEscapeEvent',function(b,q,r) if active and active.b==b then return 0 end;return r end)
local function nextCase()
 serial=serial+1;local entry=entries[serial];if not entry then finish();return end
 local c={id=entry[1],level=entry[2],label=entry[1]..'_'..entry[2]};active=c;R.cases[#R.cases+1]=c
 c.p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='BLOOD_CAST_TEST'})
 check(c.p>=0,'isolated character '..c.label)
 set(c.p,'CHAR_职业',187);set(c.p,'CHAR_职类ID',180);set(c.p,'CHAR_职阶',6);set(c.p,'CHAR_等级',200);set(c.p,'CHAR_技能栏',15)
 set(c.p,'CHAR_体力',10000);set(c.p,'CHAR_魔法',10000);NLG.UpChar(c.p)
 c.slot=Char.AddSkill(c.p,c.id,0,0);check(c.slot>=0,'learned skill '..c.label);Char.SetSkillLevel(c.p,c.slot,c.level,0)
 c.tech=specs[c.id].techs[c.level];c.fp=Tech.GetData(Tech.GetTechIndex(c.tech),CONST.TECH_FORCEPOINT)
 c.b=Battle.PVE(c.p,c.p,nil,{1},{1},{0});check(c.b>=0,'native battle '..c.label)
 for pos=10,19 do local q=Battle.GetPlayer(c.b,pos);if q>=0 then c.q=q;c.target=pos;break end end
 check(c.q~=nil,'native enemy '..c.label)
 set(c.q,'CHAR_最大血',1000000);set(c.q,'CHAR_血',1000000)
 set(c.p,'CHAR_最大血',10000);set(c.p,'CHAR_血',1000);set(c.p,'CHAR_最大魔',10000);set(c.p,'CHAR_魔',10000)
 if serial==1 then
  local emitted=0;local function output() emitted=emitted+1 end
  local use={id=c.id,level=c.level,behavior='blood',options=''}
  set(c.p,'CHAR_BattleCom3',c.tech);set(c.p,'CHAR_BattleCom2',Battle.GetPos(c.b,c.p))
  local hp,mp=get(c.p,'CHAR_血'),get(c.p,'CHAR_魔')
  original(M,c.b,c.p,use,output,output)
  check(emitted==0 and get(c.p,'CHAR_血')==hp and get(c.p,'CHAR_魔')==mp,'friendly target does not cast or charge MP')
  set(c.p,'CHAR_BattleCom2',c.target);set(c.p,'CHAR_魔',0)
  local enemyHP=get(c.q,'CHAR_血');original(M,c.b,c.p,use,output,output)
  check(emitted==0 and get(c.q,'CHAR_血')==enemyHP and get(c.p,'CHAR_魔')==0,'insufficient MP does not cast or damage')
  set(c.p,'CHAR_魔',mp)
 end
 c.start=os.time()
end
T:regCallback('AfterBattleTurnEvent',function(b)
 local c=active;if not c or c.b~=b or not c.cast or finished then return end
 local ok,err=xpcall(function()
  check(c.beforeMP-c.afterMP==c.fp,'MP charged exactly once '..c.label)
  if specs[c.id].behavior=='blood' then
   check(c.damage>0,'actual enemy damage '..c.label)
   check(c.heal==math.min(c.beforeMaxHP-c.beforeHP,math.floor(c.damage*0.3)),'actual capped blood healing '..c.label)
   check(c.heal>0,'positive blood healing '..c.label)
   if c.id==81 and c.level==30 then check(c.heal==1,'blood healing caps at missing HP') end
   if c.level==1 then check(c.afterExp>c.beforeExp,'blood skill experience increases') end
   check(c.animations[1][1]==309,'attack animation for damage '..c.label)
   check(c.packet:find('SKL|s135|',1,true)~=nil,'attack animation on wire '..c.label)
   check(c.packet:find('SKL|s329|',1,true)==nil,'buff animation absent '..c.label)
  elseif specs[c.id].behavior=='summon' then
   check(c.animations[1][1]==809,'summon retains effect animation '..c.label)
   check(M.auras[b][c.p].summon.level==30,'summon remains active '..c.label)
  else check(c.damage>0,'death still damages '..c.label) end
  check(Char.GetSkillID(c.p,c.slot)==c.id and Char.GetSkillLevel(c.p,c.slot)==c.level,'learned skill retained '..c.label)
  Battle.ExitBattle(c.p);Char.DelDummy(c.p);active=nil;nextCase();write()
 end,debug.traceback)
 if not ok then finish(err) end
end)
T:regCallback('BeforeBattleTurnStartEvent',function(b)
 local c=active;if not c or c.b~=b then return end
 NLG.UpChar(c.p)
 set(c.p,'CHAR_攻击力',200);set(c.q,'CHAR_防御力',0)
 set(c.p,'CHAR_血',c.id==81 and c.level==30 and get(c.p,'CHAR_最大血')-1 or 100)
 set(c.q,'CHAR_最大血',1000000);set(c.q,'CHAR_血',1000000)
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  nextCase()
  T:AddInterval(100,function()
   if finished then return end
   local ok,e=xpcall(function()
    local c=active;if not c then return end
    if os.time()-c.start>20 then error('cast timeout '..c.label) end
    if Battle.IsWaitingCommand(c.p)==1 then
     set(c.p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_LUA)
     set(c.p,'CHAR_BattleCom2',specs[c.id].behavior=='summon' and Battle.GetPos(c.b,c.p) or c.target)
     set(c.p,'CHAR_BattleCom3',c.tech);set(c.p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(c.p,'CHAR_BattleMode',3)
    end
   end,debug.traceback)
   if not ok then finish(e) end
  end,1);write()
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
