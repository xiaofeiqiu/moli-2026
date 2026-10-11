-- Native packet regression: old type 8 emits PNO; the production fix preserves skills without PNO.
local R={status='RUNNING',checks={},cases={},production_database_modified=false,client_render_verified=false}
local T=ModuleBase:createModule('petAnimationProbe'):new();T:load()
local byPet={};local byBattle={};local done=0;local finished=false;local started=os.time()
local function g(q,k) return Char.GetData(q,CONST[k]) end
local function s(q,k,v) return Char.SetData(q,CONST[k],v) end
local function write()local f=assert(io.open('__OUTPUT__/pet_animation_native.json','wb'));f:write(JSON.encode(R));f:close()end
local function check(ok,label)R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label)end
local function finish(err)
 if finished then return end;finished=true;R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 for _,c in ipairs(R.cases) do if c.owner then pcall(Battle.ExitBattle,c.owner);pcall(Char.DelDummy,c.owner)end end;write()
end
local function capturePacket(c)
 R.capture_requested=c.label..':'..(c.rounds+1);write()
 local stop=os.clock()+3;local capture
 repeat
  local f=io.open('__OUTPUT__/pet_animation_capture_ack.json','rb')
  if f then local raw=f:read('*a');f:close();local success,value=pcall(JSON.decode,raw);if success and value.capture==R.capture_requested then capture=value;break end end
 until os.clock()>stop
 check(capture~=nil,'captured native output '..R.capture_requested)
 c.packets[#c.packets+1]=capture.buffers
 local packet=capture.buffers.main..capture.buffers.extra
 check(packet:find('SKL|s'..string.format('%X',c.tech)..'|',1,true)~=nil,'selected technique in native output '..R.capture_requested)
 check((packet:find('PNO|',1,true)~=nil)==c.expect_animation,'native disobedience packet '..R.capture_requested)
end
T:regCallback('BattleSurpriseEvent',function()return 0 end)
T:regCallback('DamageCalculateEvent',function(a,d,orig,damage,b)
 local c=byBattle[b];if c then if a==c.pet then
  c.hits=c.hits+1
  if not finished then local ok,err=xpcall(function()capturePacket(c)end,debug.traceback);if not ok then finish(err)end end
 end;return 0 end;return damage
end)
T:regCallback('BattleDodgeRateEvent',function(b,a,d,r)if byBattle[b]then return 0 end;return r end)
T:regCallback('BeforeBattleTurnStartEvent',function(b)
 if not byBattle[b]then return end
 for pos=10,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then s(q,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);s(q,'CHAR_BattleCom2',pos);s(q,'CHAR_BattleCom3',7400)end end
end)
T:regCallback('BattlePetLeaveCheckEvent',OrderedCallback(function(b,q,kind,c1,c2,c3)
 local c=byPet[q];if c then c.decisions[#c.decisions+1]={kind=kind,c1=c1,c2=c2,c3=c3,current=g(q,'CHAR_BattleCom1')}end;return kind
end,10000))
T:regCallback('BattlePetLeaveCheckEvent',OrderedCallback(function(b,q,kind,c1,c2,c3)
 local c=byPet[q];if not c then return kind end
 if not c.override then check(kind==6,'production normal native branch '..c.label)end
 -- Only the control case overrides production behavior, to reproduce the old bug.
 return c.override or kind
end,-20000))
T:regCallback('AfterBattleTurnEvent',function(b)
 local c=byBattle[b];if not c or c.complete or finished then return end
 local ok,err=xpcall(function()
  c.rounds=c.rounds+1
  c.mp=g(c.pet,'CHAR_魔');c.command=g(c.pet,'CHAR_BattleCom1')
  check(Battle.GetPos(b,c.pet)>=0,'pet retained '..R.capture_requested)
  check(c.hits>=c.rounds,'selected action executes '..R.capture_requested)
  check(c.command==(c.tech==1930 and CONST.BATTLE_COM.BATTLE_COM_P_MAGIC or CONST.BATTLE_COM.BATTLE_COM_ATTACK),'selected command preserved '..c.label)
  if c.tech==1930 then check(c.mp==c.mp_before-10,'selected magic consumes its MP cost')end
  if c.rounds>=2 then c.complete=true;done=done+1 end
  if done==#R.cases then finish()else write()end
 end,debug.traceback)
 if not ok then finish(err)end
end)
local function add(label,override,restore,tech,animation)
 local c={label=label,override=override,restore=restore,tech=tech,expect_animation=animation,decisions={},packets={},rounds=0,hits=0}
 R.cases[#R.cases+1]=c
 c.owner=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='PET_ANIMATION_TEST'});check(c.owner>=0,'isolated owner '..label)
 local p=c.owner;s(p,'CHAR_账号','PET_ANIMATION_TEST');s(p,'对象_RegistNumber',0);s(p,'CHAR_等级',1);s(p,'CHAR_体力',50000);NLG.UpChar(p);s(p,'CHAR_血',g(p,'CHAR_最大血'))
 c.pet=Char.GivePet(p,3004,1);check(c.pet>=0,'isolated pet '..label);local q=c.pet
 if tech==1930 then check(Pet.AddSkill(q,tech)==1,'learned magic')end
 Pet.UpPet(p,q);s(q,'CHAR_血',g(q,'CHAR_最大血'));s(q,'CHAR_最大魔',10000);s(q,'CHAR_魔',10000)
 check(Char.SetPetDepartureState(p,0,2)==1,'main pet '..label)
 c.battle=Battle.PVE(p,p,nil,{1},{20},{0});check(c.battle>=0,'battle '..label);byPet[q]=c;byBattle[c.battle]=c
end
local ok,err=xpcall(function()
 add('old8_attack',8,false,7300,true)
 add('fixed_attack',nil,false,7300,false)
 add('fixed_magic',nil,false,1930,false)
 T:AddInterval(100,function()
  if finished then return end
  local success,error=xpcall(function()
   if os.time()-started>45 then error('animation probe timeout')end
   for _,c in ipairs(R.cases)do if not c.complete then local p=c.owner
    if Battle.IsWaitingCommand(p)==1 then
     s(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);s(p,'CHAR_BattleCom2',-1);s(p,'CHAR_BattleCom3',7400)
     s(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);s(p,'CHAR_Battle2Com2',-1);s(p,'CHAR_Battle2Com3',-1);s(p,'CHAR_BattleMode',3)
    end
    if Battle.IsWaitingCommand(c.pet)==1 then c.mp_before=g(c.pet,'CHAR_魔');Battle.ActionSelect(c.pet,c.tech==1930 and CONST.BATTLE_COM.BATTLE_COM_P_MAGIC or CONST.BATTLE_COM.BATTLE_COM_ATTACK,10,c.tech)end
   end end
  end,debug.traceback)
  if not success then finish(error)end
 end,1);write()
end,debug.traceback)
if not ok then finish(err)end
