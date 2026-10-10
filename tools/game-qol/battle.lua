local R={status='RUNNING',checks={},battles={}}
local p=-1;local b=-1;local stage=1;local started=os.time();local prior=0
local T=ModuleBase:createModule('qolBattleProbe'):new();T:load()
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=ok and true or false};assert(ok,label) end
local function get(key) return Char.GetData(p,CONST[key]) end
local function set(key,value) Char.SetData(p,CONST[key],value) end
local function finish(error)
 if error then R.status='FAIL';R.error=tostring(error) else R.status='PASS' end
 if p>=0 then if b>=0 then pcall(Battle.ExitBattle,p) end;pcall(Char.DelDummy,p);p=-1 end
 local f=assert(io.open('__OUTPUT__/battle_result.json','wb'));f:write(JSON.encode(R));f:close()
end
local function begin(fever)
 set('CHAR_等级',20);set('CHAR_经验',0);set('CHAR_体力',50000);set('CHAR_力量',50000)
 NLG.UpChar(p);set('CHAR_血',get('CHAR_最大血'));set('CHAR_魔',get('CHAR_最大魔'))
 set('CHAR_卡时',3600)
 if fever then check(getModule('gameQoL'):startClock(p),'automatic clock starts before native battle') else Char.FeverStop(p) end
 prior=get('CHAR_经验');b=Battle.PVE(p,p,nil,{1},{20},{0});check(b>=0,'real native battle '..stage)
end
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='QOL_FEVER_BATTLE'})
 check(p>=0,'isolated battle player')
 Char.SetExtData(p,'GameQoL_v1_autoclock',0)
 T:regCallback('BattleSurpriseEvent',function() return CONST.BATTLE_SurpriseFlag.Normal end)
 T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi)
  if bi==b then return a==p and 999999 or 0 end;return damage
 end)
 begin(false)
 local key=T:regCallback(function()
  if p<0 then return end
  local success,error=xpcall(function()
   if os.time()-started>60 then error('native battle timeout') end
   if Char.GetBattleIndex(p)~=b then
    local gain=get('CHAR_经验')-prior
    R.battles[stage]={fever=stage==2,gained=gain,card_time=get('CHAR_卡时')}
    check(gain>0,'actual experience awarded '..stage)
    b=-1
    if stage==1 then stage=2;begin(true)
    else
     check(R.battles[2].gained==R.battles[1].gained*2,'native fever grants exactly double actual battle experience')
     finish()
    end
   elseif Battle.IsWaitingCommand(p)==1 then
    set('CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set('CHAR_BattleCom2',10);set('CHAR_BattleCom3',-1)
    set('CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_ATTACK);set('CHAR_Battle2Com2',10);set('CHAR_Battle2Com3',-1)
    set('CHAR_BattleMode',3)
   end
  end,debug.traceback)
  if not success then finish(error) end
 end)
 Char.SetLoopEvent(nil,key,p,200)
end,debug.traceback)
if not ok then finish(err) end
