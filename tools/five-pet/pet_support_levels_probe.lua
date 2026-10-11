-- All 60 lessons, then native LV10 healing/recovery in six ranges and both pet modes.
local R={status='RUNNING',checks={},npcs={},production_accounts_used=false,heals={}}
local M=assert(getModule('fivePet'));local tutor=assert(getModule('petSkillTutor'))
local T=ModuleBase:createModule('petSupportLevelsProbe'):new();T:load()
local bases={6100,6200,6300,6400,6500,6600};local casts={6109,6209,6309,6409,6509,6609,6109,6409}
local p,b=-1,-1;local pets,rows,allies={}, {}, {};local row;local round=1;local finished=false;local start=os.time();local beforeMP;local beforeHP={};local executed=false
local function get(q,k) return Char.GetData(q,assert(CONST[k])) end
local function set(q,k,v) return Char.SetData(q,assert(CONST[k]),v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function actor() return round<=6 and row.proxy or pets[1] end
local function regen() return casts[round]>=6400 end
local function finish(err)
 if finished then return end;finished=true
 if p>=0 then pcall(M.disable,M,p);pcall(Battle.ExitBattle,p)
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end
  pcall(Char.DelDummy,p)
 end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end
local function setup()
 executed=false
 for _,pet in ipairs(pets) do
  for i=9,0,-1 do if Pet.GetSkill(pet,i)>=0 then Pet.DelSkill(pet,i) end end
  set(pet,'CHAR_魔',get(pet,'CHAR_最大魔'));set(pet,'CHAR_血',math.max(1,math.floor(get(pet,'CHAR_最大血')/4)))
 end
 local learned=round<=6 and row.pet or pets[1];check(Pet.AddSkill(learned,casts[round])==1,'learn native cast '..casts[round]..' round '..round)
 M:saveAI(p,row.pet,{mode=round<=6 and 'attack' or 'guard'})
 for _,r in ipairs(rows) do M:attributes(r);set(r.proxy,'CHAR_魔',get(r.pet,'CHAR_最大魔')) end
 for _,q in ipairs(allies) do
  set(q,'CHAR_血',math.max(1,math.floor(get(q,'CHAR_最大血')/4)))
  Battle.SetBattleCharacterStatus(q,CONST['战属_恢复回合'],0)
 end
 if round<=6 then local cmd=M:choose(b,row);R.decisions=R.decisions or {};R.decisions[#R.decisions+1]={round=round,command=cmd,mp=get(row.proxy,'CHAR_魔'),maxMP=get(row.pet,'CHAR_最大魔'),ai=M:ai(p,row.pet),skills=M:skills(row.pet)};check(cmd[3]==casts[round],'AI recognizes learned support level '..casts[round]) end
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleEscapeEvent',function(bi,q,rate) if bi==b then return 0 end;return rate end)
T:regCallback('BattleHealCalculateEvent',function(a,d,ori,heal,bi,c1,c2,c3)
 if bi==b and a==actor() then R.heals[#R.heals+1]={round=round,defender=d,heal=heal,tech=c3} end
 return heal
end)
T:regCallback('BeforeBattleTurnStartEvent',function(bi)
 if bi~=b then return false end
 beforeMP=get(actor(),'CHAR_魔');for _,q in ipairs(allies) do beforeHP[q]=get(q,'CHAR_血') end
 local e=Battle.GetPlayer(b,10);set(e,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(e,'CHAR_BattleCom2',10);set(e,'CHAR_BattleCom3',7400)
 return false
end)
T:regCallback('BattleAfterActionEvent',function(bi,q)
 if bi==b and q==actor() and get(q,'CHAR_BattleCom3')==casts[round] then executed=true end
 return 0
end)
T:regCallback('AfterBattleTurnEvent',function(bi)
 if bi~=b or finished then return end
 local ok,err=xpcall(function()
  check(executed,'native support action executed round '..round)
  check(get(actor(),'CHAR_魔')==beforeMP-M:tech(casts[round]).cost,'native support MP charged once round '..round)
  local expected=round>6 and 1 or ({1,4,6,1,4,6})[round];local n=0
  if regen() then
   for _,q in ipairs(allies) do if Battle.GetBattleCharacterStatus(q,CONST['战属_恢复回合'])>0 then n=n+1 end end
   check(n==expected,'native recovery range/status round '..round)
  else
   for _,q in ipairs(allies) do if get(q,'CHAR_血')>beforeHP[q] then n=n+1 end end
   check(n==expected,'actual native HP healed in range round '..round)
  end
  round=round+1;if round<=#casts then setup() end
 end,debug.traceback)
 if not ok or round>#casts then finish(not ok and err or nil) end
end)
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=60003,x=36,y=19,image=100002,name='PET_SUPPORT_LEVELS'});check(p>=0,'isolated owner')
  set(p,'CHAR_等级',50);set(p,'CHAR_体力',50000);NLG.UpChar(p)
  for slot=0,4 do local pet=Char.GivePet(p,3004,1);pets[slot+1]=pet;check(pet>=0,'isolated pet '..slot)
   for i=9,0,-1 do if Pet.GetSkill(pet,i)>=0 then Pet.DelSkill(pet,i) end end
   set(pet,'CHAR_体力',50000);set(pet,'CHAR_魔法',50000);Pet.UpPet(p,pet)
   M:saveAI(p,pet,{mode='guard'})
  end
  Char.AddGold(p,100000)
  local lessons={};for _,s in ipairs(tutor:lessons('healing')) do lessons[s.id]=s end
  for _,base in ipairs(bases) do for level=1,10 do
   local id=base+level-1;local gold=Char.GetGold(p);local tech=M:tech(id)
   check(lessons[id] and lessons[id].name:find('LV'..level,1,true),'tutor exposes explicit level '..id)
   check(tutor:learnPet(tutor.npc,p,1,Pet.GetUUID(pets[2]),id),'teach native support '..id)
   check(Pet.GetSkill(pets[2],0)==id and Char.GetGold(p)==gold-1000,'correct native ID and lesson fee '..id)
   check(not tutor:learnPet(tutor.npc,p,1,Pet.GetUUID(pets[2]),id) and Char.GetGold(p)==gold-1000,'duplicate support lesson not charged '..id)
   check(tech.cost==({30,36,48})[(base/100-61)%3+1]*level,'native level MP progression '..id)
   check(tutor:forget(tutor.npc,p,1,Pet.GetUUID(pets[2]),0,id),'native lesson can be forgotten '..id)
  end end
  check(Char.SetPetDepartureState(p,0,2)==1,'main pet selected');check(M:enable(p),'squad enabled')
  rows=M.active[p].rows;row=rows[1]
  b=Battle.PVE(p,p,nil,{1},{100},{0});check(b>=0,'native battle');M:formation(b,M.active[p])
  allies={p,pets[1]};for _,r in ipairs(rows) do allies[#allies+1]=r.proxy end
  setup()
  T:AddInterval(100,function()
   if finished then return end
   local good,e=xpcall(function()
    if os.time()-start>48 then error('pet support levels timeout') end
    if Battle.IsWaitingCommand(p)==1 then set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',Battle.GetPos(b,p));set(p,'CHAR_BattleCom3',7400);set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3) end
    if Battle.IsWaitingCommand(pets[1])==1 then local manual=round>6;Battle.ActionSelect(pets[1],manual and M:tech(casts[round]).command or CONST.BATTLE_COM.BATTLE_COM_GUARD,manual and Battle.GetPos(b,p) or Battle.GetPos(b,pets[1]),manual and casts[round] or 7400) end
    M:tick()
   end,debug.traceback);if not good then finish(e) end
  end)
 end,debug.traceback);if not ok then finish(err) end
end,0)
