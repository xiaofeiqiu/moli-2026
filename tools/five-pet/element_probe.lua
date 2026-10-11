-- Native attribute and AI policy regression; disposable characters only.
local R={status='RUNNING',checks={},production_database_modified=false}
local T=ModuleBase:createModule('fivepetElementProbe'):new();T:load()
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function set(q,k,v) return Char.SetData(q,assert(CONST[k],k),v) end
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
Cron.AddInterval(1800,function()
 local p,a,d,b=-1,-1,-1,-1
 local M=assert(getModule('fivePet'))
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=60003,x=16,y=35,image=100002,name='ELEMENT_AI_TEST'})
  assert(p>=0);a=Char.GivePet(p,3004,1);d=Char.GivePet(p,3004,1);assert(a>=0 and d>=0)
  local pet=d
  for i=9,0,-1 do if Pet.GetSkill(pet,i)>=0 then Pet.DelSkill(pet,i) end end
  check(Pet.AddSkill(pet,730)==1 and Pet.AddSkill(pet,1930)==1 and Pet.AddSkill(pet,6100)==1,'bodyguard, attack and healing skills learned')
  M:saveAI(p,pet,{mode='skill',tech=730,target='weak',threshold=30})
  M:petMenu(p,pet);local menu=M.menus[p]
  check(#menu.options==9 and menu.options[8].action=='fallbackSkills','commander exposes fallback attack skill')
  M:answer(M.npc,p,menu.seq,0,'8');menu=M.menus[p]
  check(menu.kind=='fallbackSkills','fallback selector opens')
  local choice
  for i,o in ipairs(menu.options) do
   check(o.fallbackTech~=730 and o.fallbackTech~=6100,'fallback selector excludes support skills '..i)
   if o.fallbackTech==1930 then choice=i end
  end
  check(choice~=nil,'learned attack skill available as fallback')
  M:answer(M.npc,p,menu.seq,0,tostring(choice));M.configs[p]=nil
  local saved=M:ai(p,pet)
  check(saved.tech==730 and saved.fallbackTech==1930 and saved.mode=='skill','fallback persists without replacing primary bodyguard')
  M:petMenu(p,pet);menu=M.menus[p]
  check(menu.options[4].action=='lowHpGuard','low-HP defense is an independent menu toggle')
  M:answer(M.npc,p,menu.seq,0,'4');M.configs[p]=nil
  local combined=M:ai(p,pet)
  check(combined.mode=='skill' and combined.lowHpGuard and combined.tech==730 and combined.fallbackTech==1930,'low-HP defense and skill priority persist together')
  M:petMenu(p,pet);menu=M.menus[p];M:answer(M.npc,p,menu.seq,0,'1')
  check(M:ai(p,pet).mode=='attack' and M:ai(p,pet).lowHpGuard,'switching to attack retains low-HP defense')
  M:skillMenu(p,pet,1);menu=M.menus[p];local guardChoice
  for i,o in ipairs(menu.options) do if o.tech==730 then guardChoice=i end end
  check(guardChoice~=nil,'bodyguard remains available in skill picker')
  M:answer(M.npc,p,menu.seq,0,tostring(guardChoice));M.configs[p]=nil
  check(M:ai(p,pet).mode=='skill' and M:ai(p,pet).lowHpGuard,'selecting preferred skill retains low-HP defense')
  M:petMenu(p,pet);menu=M.menus[p];M:answer(M.npc,p,menu.seq,0,'4');M.configs[p]=nil
  check(M:ai(p,pet).mode=='skill' and not M:ai(p,pet).lowHpGuard and M:ai(p,pet).tech==730,'disabling low-HP defense retains skill priority')
  M:saveAI(p,pet,{mode='cautious',tech=730,target='weak',threshold=30,fallbackTech=1930});M.configs[p]=nil
  check(M:ai(p,pet).mode=='skill' and M:ai(p,pet).lowHpGuard and M:ai(p,pet).fallbackTech==1930,'legacy cautious mode keeps skill and low-HP defense')
  M:saveAI(p,pet,saved)
  M:petMenu(p,pet);menu=M.menus[p];M:answer(M.npc,p,menu.seq,0,'8');menu=M.menus[p]
  M:answer(M.npc,p,menu.seq,0,'1');M.configs[p]=nil
  check(M:ai(p,pet).fallbackTech==0 and M:ai(p,pet).tech==730,'clearing fallback persists without changing primary bodyguard')
  M:saveAI(p,pet,saved)
  assert(Char.SetPetDepartureState(p,0,2)==1)
  assert(M:enable(p))
  b=Battle.PVE(p,p,nil,{1,1,1},{100,100,100},{0,1,2});assert(b>=0)
  a=M.active[p].rows[1].proxy;d=Battle.GetPlayer(b,10);assert(d>=0)
  local fields={'CHAR_地属性','CHAR_水属性','CHAR_火属性','CHAR_风属性'}
  local function element(q,i)
   for n,k in ipairs(fields) do Char.SetData(q,CONST[k],n==i and 100 or 0) end
  end
  R.rates={};R.prop={};R.attrs={}
  for i=0,4 do
   element(a,i);local row={};R.attrs[#R.attrs+1]=Char.GetData(a,CONST.CHAR_地属性)
   local prop={}
   for j=0,4 do
    element(d,j);row[#row+1]=Battle.CalcAttributeDmgRate(a,d)
    local ap,dp={},{};for n,k in ipairs(fields) do ap[n]=Char.GetData(a,CONST[k]);dp[n]=Char.GetData(d,CONST[k]) end
    prop[#prop+1]=Battle.CalcPropScore(ap,dp,0)
   end
   R.rates[#R.rates+1]=row
   R.prop[#R.prop+1]=prop
  end
  local row=M.active[p].rows[1];local main=Char.GetPet(p,0)
  local enemies={};for n=10,19 do local e=Battle.GetPlayer(b,n);if e>=0 then enemies[#enemies+1]=e end end
  check(#enemies==3,'real native battle has three enemies')
  local e1,e2,e3=enemies[1],enemies[2],enemies[3]
  M:formation(b,M.active[p]);element(pet,1);M:attributes(row)
  for i,e in ipairs(enemies) do set(e,'CHAR_血',i==1 and 10 or (i==2 and 100 or 1));Battle.SetEntryData(b,e,CONST.BATTLE_ENTRY_POSITION,i==3 and 1 or 0) end
  element(e1,3);element(e2,2);element(e3,2)
  local function target(kind) return M:target(b,a,{target='weak'},kind) end
  local function isTarget(e,kind,label) check(target(kind)==Battle.GetPos(b,e),label) end
  check(R.prop[2][3]>1,'native earth over water advantage')
  isTarget(e2,'attack','melee favors advantageous enemy over weaker neutral enemy')
  isTarget(e3,'magic','magic chooses advantageous rear enemy with lowest HP')
  element(e1,2);isTarget(e1,'attack','multiple advantageous enemies choose lowest current HP')
  set(e1,'CHAR_血',100);isTarget(e1,'attack','equal HP resolves by battle position')
  element(e1,4);element(e2,3);set(e1,'CHAR_血',10)
  isTarget(e1,'attack','without advantage chooses lowest HP even with disadvantage')
  set(e1,'CHAR_血',0);isTarget(e2,'attack','dead lowest-HP enemy excluded')
  set(e1,'CHAR_血',10);element(pet,0);M:attributes(row)
  isTarget(e1,'attack','no-element pet falls back to lowest HP')
  element(pet,1);set(pet,'CHAR_地属性',50);set(pet,'CHAR_风属性',50);M:attributes(row)
  element(e1,3);element(e2,2);isTarget(e2,'attack','mixed elements use native combined advantage')
  check(M:target(b,a,{target='front'},'attack')==Battle.GetPos(b,e1),'explicit front preference retained')
  for i=1,5 do check(M:target(b,a,{target='random'},'attack')~=Battle.GetPos(b,e3),'random preference excludes rear melee target '..i) end
  set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD)
  check(M:comboTarget(b,row)==Battle.GetPos(b,e1),'BOSS combo fallback retains common lowest-HP target')
  for _,e in ipairs(enemies) do element(e,0);set(e,'CHAR_血',10000);set(e,'CHAR_防御力',0) end
  for _,q in ipairs({p,main,a}) do set(q,'CHAR_血',get(q,'CHAR_最大血')) end
  set(pet,'CHAR_攻击力',1000);element(pet,1);M:attributes(row);set(a,'CHAR_魔',1000)
  check(M:choose(b,row)[3]==1930,'healthy team uses bodyguard fallback attack skill')
  saved.lowHpGuard=true;M:saveAI(p,pet,saved);set(a,'CHAR_最大血',1000);set(a,'CHAR_血',300)
  check(M:choose(b,row)[1]==CONST.BATTLE_COM.BATTLE_COM_GUARD,'exactly 30 percent guards with skill priority enabled')
  set(a,'CHAR_血',301)
  check(M:choose(b,row)[3]==1930,'above threshold resumes bodyguard fallback attack skill')
  set(p,'CHAR_血',1);set(a,'CHAR_血',300)
  check(M:choose(b,row)[1]==CONST.BATTLE_COM.BATTLE_COM_GUARD,'own low-HP defense takes priority over bodyguard')
  set(p,'CHAR_血',get(p,'CHAR_最大血'));set(a,'CHAR_魔',0)
  check(M:choose(b,row)[1]==CONST.BATTLE_COM.BATTLE_COM_GUARD,'low-HP defense needs no MP')
  set(a,'CHAR_魔',1000);saved.mode='attack';M:saveAI(p,pet,saved)
  check(M:choose(b,row)[1]==CONST.BATTLE_COM.BATTLE_COM_GUARD,'low-HP defense also combines with attack mode')
  set(a,'CHAR_血',301)
  check(M:choose(b,row)[1]==CONST.BATTLE_COM.BATTLE_COM_ATTACK,'attack mode resumes above threshold')
  saved.mode='skill';saved.lowHpGuard=false;M:saveAI(p,pet,saved);set(a,'CHAR_血',300)
  check(M:choose(b,row)[3]==1930,'disabled low-HP defense permits skill priority even below threshold')
  set(e1,'CHAR_血',1);local c=M:choose(b,row)
  R.kill={command=c,estimate=M:normalDamage(b,a,e1)}
  check(c[1]==CONST.BATTLE_COM.BATTLE_COM_ATTACK and c[3]==7300 and c[2]==Battle.GetPos(b,e1),'fallback saves MP with a killable target')
  set(p,'CHAR_血',1);c=M:choose(b,row)
  check(c[1]==CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD and c[2]==Battle.GetPos(b,p),'needed bodyguard stays first despite killable enemy')
  set(p,'CHAR_血',get(p,'CHAR_最大血'));saved.tech=1930;M:saveAI(p,pet,saved)
  check(M:choose(b,row)[1]==CONST.BATTLE_COM.BATTLE_COM_ATTACK,'primary attack skill also uses normal finishing hit')
  set(e1,'CHAR_血',10000);set(e3,'CHAR_血',1)
  check(M:choose(b,row)[3]==1930,'blocked rear target keeps magic rather than normal attack')
  set(e3,'CHAR_血',10000)
  set(e1,'CHAR_血',10000);check(M:choose(b,row)[3]==1930,'healthy target retains attack skill')
  set(e1,'CHAR_血',1);Battle.SetBattleCharacterStatus(e1,CONST.战属_攻无,1)
  check(M:choose(b,row)[3]==1930,'physical immunity prevents normal replacement')
  Battle.SetBattleCharacterStatus(e1,CONST.战属_攻无,0);set(e1,'CHAR_防御力',2000)
  check(M:choose(b,row)[3]==1930,'insufficient conservative damage keeps attack skill')
  set(e1,'CHAR_防御力',0);saved.tech=6100;M:saveAI(p,pet,saved);set(p,'CHAR_血',1)
  check(M:choose(b,row)[3]==6100,'healing remains first with killable enemy')
  set(p,'CHAR_血',get(p,'CHAR_最大血'));saved.tech=730;M:saveAI(p,pet,saved)
  set(a,'CHAR_魔',0);check(M:choose(b,row)[1]==CONST.BATTLE_COM.BATTLE_COM_ATTACK,'no MP falls back to normal attack')
  set(a,'CHAR_魔',1000);set(e1,'CHAR_血',10000);saved.fallbackTech=6100;M:saveAI(p,pet,saved)
  check(M:choose(b,row)[1]==CONST.BATTLE_COM.BATTLE_COM_ATTACK,'saved support fallback cannot be cast')
  saved.fallbackTech=1930;M:saveAI(p,pet,saved);Pet.DelSkill(pet,1)
  check(not M:learned(pet,1930) and M:choose(b,row)[1]==CONST.BATTLE_COM.BATTLE_COM_ATTACK,'forgotten fallback skill uses normal attack')
  R.estimate=M:normalDamage(b,a,e1)
 end,debug.traceback)
 if p>=0 then pcall(M.disable,M,p);pcall(Battle.ExitBattle,p);pcall(Char.DelDummy,p) end
 R.status=ok and 'PASS' or 'FAIL';R.error=not ok and err or nil
 local f=assert(io.open('__OUTPUT__/fivepet_element_native.json','wb'));f:write(JSON.encode(R));f:close()
end,0)
