-- Runs an actual native battle turn; unlike the static probe this supplies
-- the engine's packet callbacks to TECH_Lua.
local M=getModule('cg71JobSkills')
local owner=Char.CreateDummy({mapType=0,floor=1000,x=150,y=111,image=100002,name='CG71_BATTLE_VALIDATOR'})
local path='../../../../docs/jobskill_pack/native_battle_result.json'
local function write(data) local f=assert(io.open(path,'w'));f:write(JSON.encode(data));f:close() end
local function c(key) return CONST[key] end
local function set(key,value) Char.SetData(owner,c(key),value) end
set('CHAR_职业',17);set('CHAR_职类ID',10);set('CHAR_职阶',6);set('CHAR_等级',200)
set('CHAR_血',10000);set('CHAR_魔',10000)
set('CHAR_体力',100000);set('CHAR_魔法',100000)
NLG.UpChar(owner)
local slot=Char.AddSkill(owner,2200,0,0)
assert(slot>=0)
Char.SetSkillLevel(owner,slot,5,0)
local battle=Battle.PVE(owner,owner,nil,{1},{1},{0})
assert(battle>=0)
set('CHAR_最大魔',10000);set('CHAR_魔',10000)
set('CHAR_最大血',10000);set('CHAR_血',10000)
local called=0
local started=os.time()
local loopKey=M:regCallback(function(p)
  if battle<0 then return end
  set('CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_LUA)
  set('CHAR_BattleCom2',Battle.GetPos(battle,owner))
  set('CHAR_BattleCom3',611004)
  set('CHAR_BattleMode',3)
  write({result='RUNNING',battle=battle,owner=owner,turn=Battle.GetTurn(battle),mode=Char.GetData(owner,c('CHAR_BattleMode')),called=called,elapsed=os.time()-started})
end)
Char.SetLoopEvent(nil,loopKey,owner,500)
M:regCallback('BattleLuaSkillEvent',function(b,p,skl,act,msg) if p==owner then called=called+1 end end)
M:regCallback('AfterBattleTurnEvent',function(b)
  if b~=battle then return end
  local buff=M:buff(b,owner,'physical')
  write({result=called>0 and buff==5 and 'PASS' or 'FAIL',native_callback_calls=called,buff_level=buff,turn=Battle.GetTurn(b),magic_points=Char.GetData(owner,c('CHAR_魔')),client_verified=false})
  Char.UnsetLoopEvent(owner)
  Battle.ExitBattle(owner);Char.DelDummy(owner);battle=-1
end)
set('CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_LUA)
set('CHAR_BattleCom2',Battle.GetPos(battle,owner))
set('CHAR_BattleCom3',611004)
set('CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_GUARD)
set('CHAR_Battle2Com2',Battle.GetPos(battle,owner))
set('CHAR_Battle2Com3',7400)
set('CHAR_BattleMode',3)
write({result='RUNNING',battle=battle,owner=owner})
