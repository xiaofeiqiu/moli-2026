local R={status='RUNNING',checks={}}
local Q=assert(getModule('gameQoL'))
local F=assert(getModule('fivePet'))
local p,other=-1,-1
local pets={}
local originalMessage=NLG.SystemMessage
local messages={}
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function get(q,key) return Char.GetData(q,CONST[key]) end
local function set(q,key,value) return Char.SetData(q,CONST[key],value) end
local function command(msg)
 messages={};check(TalkEvent(p,msg,0,0,0)==0,'consumed '..msg)
 return table.concat(messages,'\n')
end
local function wound(q)
 set(q,'CHAR_受伤',25);Char.UpCharStatus(q)
 set(q,'CHAR_血',0);set(q,'CHAR_魔',0)
end
local function recovered(q,label)
 check(get(q,'CHAR_血')==get(q,'CHAR_最大血') and get(q,'CHAR_血')>0,'full HP '..label)
 check(get(q,'CHAR_魔')==get(q,'CHAR_最大魔'),'full MP '..label)
 check(get(q,'CHAR_受伤')==0,'injury cleared '..label)
end
local function unchanged(label)
 check(get(p,'CHAR_血')==0 and get(p,'CHAR_魔')==0 and get(p,'CHAR_受伤')==25,'owner unchanged '..label)
 for n,pet in ipairs(pets) do
  check(get(pet,'CHAR_血')==0 and get(pet,'CHAR_魔')==0 and get(pet,'CHAR_受伤')==25,'pet unchanged '..label..'/'..n)
 end
end
local function woundAll() wound(p);for _,pet in ipairs(pets) do wound(pet) end end
NLG.SystemMessage=function(q,text,...) if q==p then messages[#messages+1]=text end;return originalMessage(q,text,...) end
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='HEAL_NATIVE_TEST'})
 check(p>=0,'isolated native player')
 check(get(p,'CHAR_BattleMode')==0 and Char.GetBattleIndex(p)==-1,'initial out-of-combat state')
 wound(p);command('/heal');recovered(p,'no pets')
 for slot=0,4 do
  local pet=Char.GivePet(p,3004,1);check(pet>=0,'native pet fixture '..slot)
  pets[#pets+1]=pet
 end
 local control={}
 for _,q in ipairs({p,table.unpack(pets)}) do
  control[q]={}
  for _,key in ipairs({'CHAR_等级','CHAR_经验','CHAR_升级点','CHAR_体力','CHAR_力量','CHAR_强度','CHAR_速度','CHAR_魔法'}) do control[q][key]=get(q,key) end
 end
 local gold=Char.GetGold(p)
 local weapon=Item.MakeItem(2001);check(weapon>=0,'equipped durability fixture')
 Char.SetItemIndex(p,0,weapon);Item.SetData(weapon,CONST['道具_耐久'],10)
 woundAll()
 for _,msg in ipairs({'/heal extra','/heal 1'}) do
  check(command(msg):find('用法',1,true)~=nil,'invalid parameters explained '..msg);unchanged(msg)
 end
 for _,msg in ipairs({'/heal!','/healing','/healx','/治疗','/治疗 1','ordinary chat'}) do
  check(TalkEvent(p,msg,0,0,0)==1,'unrelated command untouched '..msg);unchanged(msg)
 end
 check(command('/help heal'):find('清除受伤',1,true)~=nil,'English heal help');unchanged('help query')
 set(p,'CHAR_BattleMode',1);command('/heal');unchanged('battle mode');set(p,'CHAR_BattleMode',0)
 set(p,'CHAR_血',1);set(pets[1],'CHAR_血',get(pets[1],'CHAR_最大血'))
 check(Char.SetPetDepartureState(p,0,2)==1,'normal pet for actual combat fixture')
 local battle=Battle.PVE(p,p,nil,{1},{1},{0});check(battle>=0,'actual native battle fixture')
 woundAll();set(p,'CHAR_BattleMode',0)
 check(Char.GetBattleIndex(p)==battle,'active roster retains battle index with idle mode')
 command('/heal');unchanged('actual battle index')
 check(Battle.GetPos(battle,pets[1])>=0 and Char.GetBattleIndex(pets[1])==battle,'native pet actually participates')
 set(p,'CHAR_BattleIndex',-1)
 check(command('/heal'):find('宠物仍在战斗',1,true)~=nil,'actual pet roster blocks healing after owner state clears');unchanged('actual pet roster')
 set(p,'CHAR_BattleIndex',battle)
 Battle.ExitBattle(p);set(p,'CHAR_BattleIndex',-1);set(p,'CHAR_BattleMode',0)
 for _,pet in ipairs(pets) do set(pet,'CHAR_BattleIndex',-1);set(pet,'CHAR_BattleMode',0) end
 woundAll()
 CharaStallStartEvent(p);check(Q.stalls[p]==true,'native stall callback tracked');command('/heal');unchanged('stall');CharaStallEndEvent(p)
 for _,fixture in ipairs({{mode=0,index=0},{mode=1,index=-1},{mode=3,index=999999}}) do
  woundAll();set(pets[5],'CHAR_BattleMode',fixture.mode);set(pets[5],'CHAR_BattleIndex',fixture.index)
  command('/heal');recovered(p,'orphaned pet battle state/'..fixture.mode..'/'..fixture.index)
  for n,pet in ipairs(pets) do recovered(pet,'orphaned pet state/'..n) end
  set(pets[5],'CHAR_BattleMode',0);set(pets[5],'CHAR_BattleIndex',-1)
 end
 command('/HEAL');recovered(p,'uppercase English')
 for n,pet in ipairs(pets) do recovered(pet,'all five pets/'..n) end
 check(Char.GetGold(p)==gold,'no gold charged')
 check(Item.GetData(weapon,CONST['道具_耐久'])==10,'equipment durability unchanged')
 for q,values in pairs(control) do for key,value in pairs(values) do check(get(q,key)==value,'progress unchanged '..q..'/'..key) end end
 command('/heal');recovered(p,'repeat full-state heal')
 other=Char.CreateDummy({mapType=0,floor=1000,x=226,y=75,image=100002,name='HEAL_OTHER_PLAYER'})
 check(other>=0 and Char.JoinParty(other,p,true)==0,'ordinary teammate fixture')
 local otherPet=Char.GivePet(other,3004,1);check(otherPet>=0,'teammate pet fixture')
 wound(other);wound(otherPet);woundAll();command('/heal')
 recovered(p,'party self');recovered(pets[1],'party own pet')
 check(get(other,'CHAR_血')==0 and get(otherPet,'CHAR_血')==0 and get(other,'CHAR_受伤')==25,'teammate and their pet unchanged')
 Char.LeaveParty(other);Char.LeaveParty(p)
 set(other,'CHAR_血',1)
 local foreign=Battle.PVE(other,other,nil,{1},{1},{0});check(foreign>=0,'unrelated native battle fixture')
 woundAll();set(pets[5],'CHAR_BattleIndex',foreign);set(pets[5],'CHAR_BattleMode',3)
 command('/heal');recovered(p,'pet stale index points to other battle');recovered(pets[5],'stale index pet')
 check(Char.GetBattleIndex(other)==foreign,'unrelated battle stays active')
 set(pets[5],'CHAR_BattleIndex',-1);set(pets[5],'CHAR_BattleMode',0)
 Battle.ExitBattle(other);set(other,'CHAR_BattleIndex',-1);set(other,'CHAR_BattleMode',0)
 check(Char.SetPetDepartureState(p,0,2)==1,'normal battle pet selected')
 check(F:enable(p),'five-pet mode enabled')
 local squad=assert(F.active[p]);check(#squad.rows==4,'four native five-pet proxies')
 woundAll();squad.battle=0
 check(command('/heal'):find('结算',1,true)~=nil,'pending five-pet settlement explained');unchanged('five-pet settlement')
 squad.battle=nil
 command('/heal');recovered(p,'five-pet owner')
 for n,row in ipairs(squad.rows) do recovered(row.pet,'five-pet original/'..n);recovered(row.proxy,'five-pet proxy/'..n) end
 F:tick()
 for n,pet in ipairs(pets) do recovered(pet,'five-pet tick preserves healing/'..n) end
 F:disable(p)
 Char.DelSlotPet(p,1);Char.DelSlotPet(p,3)
 check(Char.GetPet(p,1)<0 and Char.GetPet(p,3)<0,'sparse pet slots fixture')
 wound(p)
 for slot=0,4 do local pet=Char.GetPet(p,slot);if pet>=0 then wound(pet) end end
 check(reloadModule('gameQoL')~=nil,'hot reload succeeds');Q=assert(getModule('gameQoL'))
 command('/heal');recovered(p,'hot reload owner')
 for slot=0,4 do local pet=Char.GetPet(p,slot);if pet>=0 then recovered(pet,'sparse slot/'..slot) end end
 R.status='PASS'
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err) end
if p>=0 then pcall(F.disable,F,p);pcall(Char.DelDummy,p) end
if other>=0 then pcall(Char.DelDummy,other) end
NLG.SystemMessage=originalMessage
local f=assert(io.open('__OUTPUT__/heal_native.json','wb'));f:write(JSON.encode(R));f:close()
