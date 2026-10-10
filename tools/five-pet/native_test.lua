local M=getModule('fivePet')
local T=ModuleBase:createModule('fivePetTest')
local OUT='__OUTPUT__/native_result.json'
local R={status='RUNNING',checks={},errors={},client_verified=false}
local function write() local f=assert(io.open(OUT,'w'));f:write(JSON.encode(R));f:close() end
local function g(p,k) return Char.GetData(p,CONST[k]) end
local function s(p,k,v) return Char.SetData(p,CONST[k],v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=ok and true or false};assert(ok,label);write() end
local function owner(name)
 local p=Char.CreateDummy({mapType=0,floor=1000,x=151,y=113,image=100002,name=name})
 assert(p>=0);s(p,'CHAR_等级',50);s(p,'CHAR_体力',50000);s(p,'CHAR_魔法',50000);NLG.UpChar(p)
 s(p,'CHAR_血',g(p,'CHAR_最大血'));s(p,'CHAR_魔',g(p,'CHAR_最大魔'))
 return p
end
local p,ps,b,session,started,step=-1,{},-1,nil,os.time(),'static'
local actions,damages,consumes,expEvents={},{},{},{}
T:regCallback('BattleSurpriseEvent',function() return CONST.BATTLE_SurpriseFlag.Normal end)
T:regCallback('BattleActionEvent',function(q,c1,c2,c3,n)
 if q==p or M.proxies[q] then actions[#actions+1]={index=q,command=c1,target=c2,tech=c3,number=n,turn=b>=0 and Battle.GetTurn(b) or -1} end
end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi,c1,c2,c3)
 if bi==b then damages[#damages+1]={attacker=a,defender=d,damage=damage,tech=c3,turn=Battle.GetTurn(b)} end
 if bi==b and not M.proxies[a] and a~=p and a~=ps[1] then return 0 end
 if bi==b and (R.turns or 0)>=2 and M.proxies[a] then return 999999 end
 return damage
end)
T:regCallback('CalcFpConsumeEvent',function(q,id,fp)
 if M.proxies[q] then consumes[#consumes+1]={index=q,tech=id,cost=fp} end
 return fp
end)
T:regCallback('GetExpEvent',function(q,xp)
 expEvents[#expEvents+1]={index=q,xp=xp,proxy=M.proxies[q]~=nil};return xp
end)
local function errorout(err) R.status='FAIL';R.error=tostring(err);R.actions=actions;R.damages=damages;R.consumes=consumes;R.exp_events=expEvents;write() end
local function cleanup()
 if p>=0 then M:disable(p);if Char.GetBattleIndex(p)>=0 then Battle.ExitBattle(p) end
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then Char.DelSlotPet(p,slot) end end
  Char.DelDummy(p);p=-1
 end
end
local ok,err=xpcall(function()
 check(M~=nil and M.npc>=0,'module and commander NPC loaded')
 check(Map.IsWalkable(0,1000,151,113)==1,'NPC approach is walkable')
 p=owner('FIVE_PET_FEATURE_TEST')
 for slot=0,4 do local pet=Char.GivePet(p,3004,1);assert(pet>=0);ps[#ps+1]=pet end
 check(Char.SetPetDepartureState(p,0,2)==1,'normal pet selected')
 check(Pet.AddSkill(ps[2],1930)==1,'pet learned meteor I')
 check(Pet.AddSkill(ps[5],330)==1,'pet learned physical skill')
 check(M:saveAI(p,ps[2],{mode='skill',tech=1930,target='weak',threshold=30}),'save magic AI')
 check(M:saveAI(p,ps[3],{mode='guard',tech=0,target='weak',threshold=30}),'save guard AI')
 check(M:saveAI(p,ps[4],{mode='cautious',tech=0,target='weak',threshold=30}),'save cautious AI')
 check(M:saveAI(p,ps[5],{mode='skill',tech=330,target='front',threshold=30}),'save physical AI')
 M.configs[p]=nil;check(M:ai(p,ps[2]).tech==1930,'AI preference read from character extension')
 check(Char.MovePet(p,1,4)==1,'reorder pet slots')
 check(M:ai(p,ps[2]).tech==1930 and M:ai(p,ps[5]).tech==330,'AI remains tied to pet UUID')
 check(Char.MovePet(p,4,1)==1,'restore pet slots')
 M:menu(p);local menu=M.menus[p];check(menu and #menu.options==6,'NPC lists four configurable pets')
 M:answer(M.npc,p,menu.seq+1,1,'1');check(not M.active[p],'stale NPC response rejected')
 M:menu(p);menu=M.menus[p];M:answer(M.npc,p,menu.seq,2,'1');check(not M.active[p],'NPC close does not enable mode')
 M:petMenu(p,ps[3]);menu=M.menus[p];M:answer(M.npc,p,menu.seq,1,'1')
 check(M:ai(p,ps[3]).mode=='attack','NPC AI choice changes configuration')
 M:skillMenu(p,ps[2],1);menu=M.menus[p]
 local selected=nil;for n,o in ipairs(menu.options) do if o.tech==1930 then selected=n end end
 check(selected~=nil,'NPC lists learned meteor spell')
 M:answer(M.npc,p,menu.seq,1,tostring(selected))
 check(M:ai(p,ps[2]).tech==1930 and M:ai(p,ps[2]).mode=='skill','NPC preferred-skill selection saves AI')
 M:saveAI(p,ps[3],{mode='guard',tech=0,target='weak',threshold=30})
 local other=owner('FIVE_PET_PARTY_TEST');Char.JoinParty(other,p,true)
 local enabled=M:enable(p);check(not enabled,'real teammate rejects enabling')
 Char.LeaveParty(other);Char.DelDummy(other)
 s(ps[4],'CHAR_血',math.max(1,math.floor(g(ps[4],'CHAR_最大血')*0.1)))
 enabled,err=M:enable(p);check(enabled,'five-pet mode enabled: '..tostring(err))
 session=M.active[p];check(session and #session.rows==4,'exactly four proxies created')
 local rows={};for _,r in ipairs(session.rows) do rows[r.pet]=r end
 R.rows={};for _,r in ipairs(session.rows) do
  check(g(r.proxy,'CHAR_攻击力')==g(r.pet,'CHAR_攻击力'),'proxy attack matches pet '..r.slot)
  R.rows[#R.rows+1]={proxy=r.proxy,pet=r.pet,slot=r.slot,ai=M:ai(p,r.pet),hp=g(r.pet,'CHAR_血'),mp=g(r.pet,'CHAR_魔')}
 end
 b=Battle.PVE(p,p,nil,{1},{100},{0});check(b>=0,'native battle started')
 R.battle=b;R.roster={}
 for pos=0,19 do local q=Battle.GetPlayer(b,pos);if q>=0 then R.roster[#R.roster+1]={pos=pos,index=q,type=g(q,'CHAR_类型')} end end
 check(#R.roster==7,'one owner, five companions and enemy in roster')
 session.battle=b
 local magic=M:choose(b,rows[ps[2]])
 R.debug={magic=magic,tech=M:tech(1930),learned=M:learned(ps[2],1930),skills={},enemy_hp=g(Battle.GetPlayer(b,10),'CHAR_血'),enemy_use=Char.GetData(Battle.GetPlayer(b,10),0)}
 for n=0,9 do R.debug.skills[#R.debug.skills+1]=Pet.GetSkill(ps[2],n) end
 check(magic[3]==1930 and magic[1]==CONST.BATTLE_COM.BATTLE_COM_P_MAGIC,'magic AI selects learned spell')
 local defend=M:choose(b,rows[ps[3]])
 check(defend[1]==CONST.BATTLE_COM.BATTLE_COM_GUARD,'guard AI selects defense')
 local low=M:choose(b,rows[ps[4]])
 check(low[1]==CONST.BATTLE_COM.BATTLE_COM_GUARD,'low HP AI selects defense')
 local q=rows[ps[2]].proxy;local mp=g(q,'CHAR_魔');s(q,'CHAR_魔',0)
 check(M:choose(b,rows[ps[2]])[1]==CONST.BATTLE_COM.BATTLE_COM_ATTACK,'no MP falls back to attack');s(q,'CHAR_魔',mp)
 local loop=T:regCallback(function()
  local ok,e=xpcall(function()
   if b<0 then return end
   if os.time()-started>45 then error('Battle test timeout') end
   if Char.GetBattleIndex(p)~=b then
    M:tick();check(session.battle==nil,'completed battle finalized')
    check(M.active[p]==session,'normal victory keeps five-pet mode enabled')
    R.post_pets={};for _,r in ipairs(session.rows) do R.post_pets[#R.post_pets+1]={pet=r.pet,hp=g(r.pet,'CHAR_血'),mp=g(r.pet,'CHAR_魔'),xp=g(r.pet,'CHAR_经验')} end
    R.actions=actions;R.damages=damages;R.consumes=consumes;R.exp_events=expEvents
    local rows={};for _,r in ipairs(session.rows) do rows[r.pet]=r end
    local magic=rows[ps[2]];local physical=rows[ps[5]]
    local castTurns={};local physicalTurns={}
    for _,d in ipairs(damages) do
     if d.attacker==magic.proxy and d.tech==1930 then castTurns[d.turn]=(castTurns[d.turn] or 0)+1 end
     if d.attacker==physical.proxy and d.tech==330 then physicalTurns[d.turn]=(physicalTurns[d.turn] or 0)+1 end
    end
    check(castTurns[0]==1 and castTurns[1]==1,'magic executes once per turn')
    check(physicalTurns[0]==1 and physicalTurns[1]==1,'physical skill executes once per turn')
    check(g(ps[2],'CHAR_魔')==R.rows[1].mp-20,'two spell casts consume exactly 20 MP on original pet')
    for _,r in ipairs(session.rows) do check(g(r.pet,'CHAR_经验')>0,'experience forwarded to pet '..r.slot) end
    M:disable(p);check(M.active[p]==nil and next(M.proxies)==nil,'disable deletes every proxy')
    local yes,why=M:enable(p);check(yes,'mode can be enabled again: '..tostring(why))
    DropEvent(p);check(next(M.proxies)==nil and M.active[p]==nil,'disconnect event deletes every proxy')
    check(M:enable(p),'enable before logout test');LogoutEvent(p)
    check(next(M.proxies)==nil,'logout event deletes every proxy')
    check(M:enable(p),'enable before changed-pet test')
    Char.SetPetDepartureStateAll(p,0,2,0,0,0);M:tick()
    check(M.active[p]==nil and next(M.proxies)==nil,'changing normal pet closes five-pet mode')
    Char.SetPetDepartureStateAll(p,2,0,0,0,0)
    check(M:enable(p),'enable before escape test')
    local escaped=Battle.PVE(p,p,nil,{1},{1},{0});check(escaped>=0,'escape test battle created')
    M.active[p].battle=escaped;Battle.ExitBattle(p);BattleExitEvent(p,escaped,1)
    check(M.active[p]==nil and next(M.proxies)==nil,'battle exit callback removes all companions')
    s(p,'CHAR_BattleIndex',-1);s(p,'CHAR_BattleMode',0)
    check(M:enable(p),'enable before dead pet test')
    local dead=M.active[p].rows[1];s(dead.proxy,'CHAR_血',0);s(dead.proxy,'CHAR_受伤',20)
    M.active[p].battle=escaped;M:disable(p)
    check(g(dead.pet,'CHAR_血')==0 and g(dead.pet,'CHAR_受伤')>=20,'death and injury synchronized before proxy deletion')
    local allowed=M:enable(p);check(not allowed,'dead pet rejects enabling')
    s(dead.pet,'CHAR_血',g(dead.pet,'CHAR_最大血'));s(dead.pet,'CHAR_受伤',0);Pet.UpPet(p,dead.pet)
    check(M:enable(p),'enable before unload test');M:onUnload()
    check(next(M.proxies)==nil and next(M.active)==nil,'module unload deletes every proxy')
    check(Char.PartyNum(p)<=1,'no ghost party remains')
    cleanup();b=-1;R.status='PASS';write();return
   end
   if Battle.IsWaitingCommand(p)==1 then
    s(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD)
    s(p,'CHAR_BattleCom2',Battle.GetPos(b,p));s(p,'CHAR_BattleCom3',7400)
    s(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_GUARD)
    s(p,'CHAR_Battle2Com2',Battle.GetPos(b,p));s(p,'CHAR_Battle2Com3',7400);s(p,'CHAR_BattleMode',3)
   end
   local pet=ps[1]
   if Battle.IsWaitingCommand(pet)==1 then Battle.ActionSelect(pet,CONST.BATTLE_COM.BATTLE_COM_GUARD,Battle.GetPos(b,pet),7400) end
   M:tick();write()
  end,debug.traceback)
  if not ok then Char.UnsetLoopEvent(p);errorout(e);cleanup();b=-1 end
 end)
 Char.SetLoopEvent(nil,loop,p,250);step='battle';write()
 T:regCallback('AfterBattleTurnEvent',function(bi)
  if bi~=b then return end
  local ok,e=xpcall(function()
   R.turns=(R.turns or 0)+1
   R.turn_states=R.turn_states or {}
   local states={};for _,r in ipairs(session.rows) do states[#states+1]={proxy=r.proxy,hp=g(r.proxy,'CHAR_血'),mp=g(r.proxy,'CHAR_魔'),pet_hp=g(r.pet,'CHAR_血'),pet_mp=g(r.pet,'CHAR_魔')} end
   R.turn_states[#R.turn_states+1]=states
   for _,r in ipairs(session.rows) do check(g(r.proxy,'CHAR_攻击力')==g(r.pet,'CHAR_攻击力'),'battle stat preservation '..r.slot..' turn '..R.turns) end
   if R.turns==2 then
    for _,r in ipairs(session.rows) do M:saveAI(p,r.pet,{mode='attack',tech=0,target='weak',threshold=30}) end
   end
   R.actions=actions;R.damages=damages;R.consumes=consumes;R.exp_events=expEvents;write()
  end,debug.traceback)
  if not ok then errorout(e);cleanup();b=-1 end
 end)
end,debug.traceback)
if not ok then errorout(err);cleanup() end
