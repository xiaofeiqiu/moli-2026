-- Source UTF-8; build.py writes GBK for the native Lua loader.
local M=ModuleBase:createModule('fivePet')
local KEY='FivePetAI_v1'
local ATTR={'CHAR_最大血','CHAR_最大魔','CHAR_攻击力','CHAR_防御力','CHAR_敏捷',
 'CHAR_精神','CHAR_回复','CHAR_地属性','CHAR_水属性','CHAR_火属性','CHAR_风属性',
 'CHAR_抗毒','CHAR_抗睡','CHAR_抗石','CHAR_抗醉','CHAR_抗乱','CHAR_抗忘',
 'CHAR_必杀','CHAR_反击','CHAR_命中','CHAR_闪躲','CHAR_种族','CHAR_魔攻','CHAR_魔抗'}
local COMMAND={TECH_NormalAttack='BATTLE_COM_ATTACK',TECH_NormalGuard='BATTLE_COM_GUARD',
 TECH_ContinuationAttack='BATTLE_COM_P_RENZOKU',TECH_Parameter='BATTLE_COM_P_PARAMETER',
 TECH_SpiracleShot='BATTLE_COM_P_SPIRACLESHOT',TECH_Cutting='BATTLE_COM_P_EDGE',
 TECH_GuardBreak='BATTLE_COM_P_GUARDBREAK',TECH_Forcecut='BATTLE_COM_P_FORCECUT',
 TECH_RandomShot='BATTLE_COM_P_RANDOMSHOT',TECH_PanicAttack='BATTLE_COM_P_PANIC',
 TECH_Attack_Magic='BATTLE_COM_P_MAGIC',TECH_Heal_Magic='BATTLE_COM_P_HEAL',
 TECH_Revive='BATTLE_COM_P_REVIVE',TECH_LpRecovery='BATTLE_COM_P_LP_RECOVERY',
 TECH_StatusRecover='BATTLE_COM_P_STATUSRECOVER',TECH_StatusAttack='BATTLE_COM_M_STATUSATTACK',
 TECH_StatusChange='BATTLE_COM_P_STATUSCHANGE',TECH_MagicGuard='BATTLE_COM_P_MAGICGARD',
 TECH_SpecialGuard='BATTLE_COM_P_SPECIALGARD',TECH_Mikawashi='BATTLE_COM_P_DODGE',
 TECH_CrossCounter='BATTLE_COM_P_CROSSCOUNTER',TECH_Reflection_Physics='BATTLE_COM_P_REFLECTION_PHYSICS',
 TECH_Reflection_Magic='BATTLE_COM_P_REFLECTION_MAGIC',TECH_Absorb_Physics='BATTLE_COM_P_ABSORB_PHYSICS',
 TECH_Absorb_Magic='BATTLE_COM_P_ABSORB_MAGIC',TECH_Ineffective_Physics='BATTLE_COM_P_INEFFECTIVE_PHYSICS',
 TECH_Ineffective_Magic='BATTLE_COM_P_INEFFECTIVE_MAGIC',TECH_BloodAttack='BATTLE_COM_M_BLOODATTACK',
 TECH_Death='BATTLE_COM_M_DEATH',TECH_EnergyDrain='BATTLE_COM_M_ENERGYDRAIN',
 TECH_BodyGuard='BATTLE_COM_P_BODYGUARD',TECH_Assassin='BATTLE_COM_P_ASSASSIN',
 TECH_EquipBreakAttack='BATTLE_COM_M_BREAKATTACK',TECH_GoldAttack='BATTLE_COM_M_GOLDATTACK',
 TECH_EarthQuake='BATTLE_COM_M_EARTHQUAKE',TECH_Treat_Type='BATTLE_COM_P_TREAT_TYPE',
 TECH_AttackAll='BATTLE_COM_ATTACKALL',TECH_Ranbu='BATTLE_COM_RANBU',TECH_Consentration='BATTLE_COM_P_CONSENTRATION'}
local SELF={TECH_NormalGuard=true,TECH_MagicGuard=true,TECH_SpecialGuard=true,
 TECH_Mikawashi=true,TECH_CrossCounter=true,TECH_Reflection_Physics=true,
 TECH_Reflection_Magic=true,TECH_Absorb_Physics=true,TECH_Absorb_Magic=true,
 TECH_Ineffective_Physics=true,TECH_Ineffective_Magic=true,TECH_Consentration=true}
local OFFENSIVE={TECH_NormalAttack=true,TECH_ContinuationAttack=true,TECH_Parameter=true,
 TECH_SpiracleShot=true,TECH_Cutting=true,TECH_GuardBreak=true,TECH_Forcecut=true,
 TECH_RandomShot=true,TECH_PanicAttack=true,TECH_Attack_Magic=true,TECH_StatusAttack=true,
 TECH_BloodAttack=true,TECH_Death=true,TECH_EnergyDrain=true,TECH_Assassin=true,
 TECH_EquipBreakAttack=true,TECH_GoldAttack=true,TECH_EarthQuake=true,TECH_AttackAll=true,TECH_Ranbu=true}
local MODES={attack='普攻',skill='技能优先',guard='全程防御'}
local TARGETS={weak='属性克制优先',front='前排优先',random='随机敌人'}
local function get(p,k) local c=CONST[k];if c==nil then return nil end;return Char.GetData(p,c) end
local function num(p,k) return tonumber(get(p,k)) or 0 end
local function set(p,k,v) local c=CONST[k];if c~=nil and v~=nil then return Char.SetData(p,c,v) end end
local function valid(p) return type(p)=='number' and p>=0 and Char.IsValidCharIndex(p) end
local function tell(p,s) if valid(p) then NLG.SystemMessage(p,s) end end
local function petkey(pet) return tostring(Pet.GetUUID(pet)) end
local function default() return {mode='attack',tech=0,target='weak',threshold=30,lowHpGuard=false} end
function M:proxyAlive(row)
 local q=row.proxy
 return valid(q) and Char.IsDummy(q)
  and Char.GetTempData(q,'FivePetProxy_v1')==row.token
end
function M:config(p)
 local uid=Char.GetUUID(p);local cache=self.configs[p]
 if cache and cache.uid==uid then return cache.data end
 local data={version=1,pets={}};local raw=Char.GetExtData(p,KEY)
 if type(raw)=='string' then
  local ok,t=pcall(JSON.decode,raw)
  if ok and type(t)=='table' and type(t.pets)=='table' then data=t end
 end
 self.configs[p]={uid=uid,data=data};return data
end
function M:ai(p,pet)
 local a=self:config(p).pets[petkey(pet)] or default()
 -- Read legacy cautious mode as skill priority plus an independent low-HP guard.
 return {mode=a.mode=='cautious' and 'skill' or (MODES[a.mode] and a.mode or 'attack'),tech=tonumber(a.tech) or 0,
  lowHpGuard=a.lowHpGuard==true or (a.lowHpGuard==nil and a.mode=='cautious'),
  target=TARGETS[a.target] and a.target or 'weak',threshold=tonumber(a.threshold) or 30,bossCombo=a.bossCombo==true,fallbackTech=tonumber(a.fallbackTech) or 0}
end
function M:enabled(p)
 return self:config(p).enabled~=false
end
function M:setEnabled(p,enabled)
 if not valid(p) or not Char.IsPlayer(p) or self.proxies[p] then return false end
 local data=self:config(p);data.enabled=enabled
 Char.SetExtData(p,KEY,JSON.encode(data))
 if not Char.IsDummy(p) then Char.SaveToDb(p) end
 self.autoAttempts[p]=nil
 if not enabled then self:disable(p,'五宠模式已关闭。') end
 return true
end
function M:autoEnable()
 local now=os.time()
 if now<self.nextAutoCheck then return end
 self.nextAutoCheck=now+1
 local online=NLG.GetPlayer()
 for _,p in ipairs(type(online)=='table' and online or {}) do
  if valid(p) and Char.IsPlayer(p) and not Char.IsDummy(p) and not self.active[p]
   and Char.GetBattleIndex(p)<0 and num(p,'CHAR_BattleMode')==0 and Char.PartyNum(p)<=1
   and Char.PetNum(p)>=1 and self:enabled(p) then
   local attempt=self.autoAttempts[p]
   local uid=Char.GetUUID(p)
   if not attempt or attempt.uid~=uid or now>=attempt.next then
    local ok=self:enable(p)
    if ok then self.autoAttempts[p]=nil
    else self.autoAttempts[p]={uid=uid,next=now+2} end
   end
  end
 end
end
function M:saveAI(p,pet,a)
 if Pet.GetOwner(pet)~=p then return false end
 local d=self:config(p);d.pets[petkey(pet)]=a
 Char.SetExtData(p,KEY,JSON.encode(d))
 if not Char.IsDummy(p) then Char.SaveToDb(p) end
 return true
end
function M:tech(id)
 local ix=Tech.GetTechIndex(id);if ix<0 then return nil end
 local fn=Tech.GetData(ix,CONST.TECH_FUNCNAME);local key=COMMAND[fn]
 if not key or not CONST.BATTLE_COM[key] then return nil end
 return {id=id,fn=fn,command=CONST.BATTLE_COM[key],name=Tech.GetData(ix,CONST.TECH_NAME),
  cost=math.max(0,tonumber(Tech.GetData(ix,CONST.TECH_FORCEPOINT)) or 0),
  target=tonumber(Tech.GetData(ix,CONST.TECH_TARGET)) or 0}
end
function M:learned(pet,id)
 for n=0,9 do if Pet.GetSkill(pet,n)==id then return true end end
 return false
end
function M:owned(p,row)
 if not valid(p) or not valid(row.pet) or Pet.GetOwner(row.pet)~=p or petkey(row.pet)~=row.uuid then return false end
 for slot=0,4 do if Char.GetPet(p,slot)==row.pet then row.slot=slot;return true end end
 return false
end
function M:attributes(row)
 if not self:proxyAlive(row) or not valid(row.pet) then return end
 for _,k in ipairs(ATTR) do set(row.proxy,k,get(row.pet,k)) end
 set(row.proxy,'CHAR_等级',num(row.pet,'CHAR_等级'))
 set(row.proxy,'CHAR_形象',get(row.pet,'CHAR_形象'))
 set(row.proxy,'CHAR_原形',get(row.pet,'CHAR_原形'))
 set(row.proxy,'CHAR_原始图档',get(row.pet,'CHAR_原始图档'))
end
function M:refresh(row)
 if not self:proxyAlive(row) then return end
 self:attributes(row)
 set(row.proxy,'CHAR_血',num(row.pet,'CHAR_血'))
 set(row.proxy,'CHAR_魔',num(row.pet,'CHAR_魔'))
 set(row.proxy,'CHAR_受伤',num(row.pet,'CHAR_受伤'))
 row.lastHp=num(row.pet,'CHAR_血');row.lastMp=num(row.pet,'CHAR_魔');row.dead=row.lastHp<=0
end
function M:sync(p,row,update)
 if not self:owned(p,row) or not self:proxyAlive(row) then return false end
 local hp=num(row.proxy,'CHAR_血');local mp=num(row.proxy,'CHAR_魔')
 if row.revivePending and hp>0 then row.dead=false;row.revivePending=nil end
 if hp<=0 then row.dead=true end
 if row.dead then hp=0 end
 set(row.pet,'CHAR_血',math.max(0,math.min(hp,num(row.pet,'CHAR_最大血'))))
 set(row.pet,'CHAR_魔',math.max(0,math.min(mp,num(row.pet,'CHAR_最大魔'))))
 set(row.pet,'CHAR_受伤',math.max(num(row.pet,'CHAR_受伤'),num(row.proxy,'CHAR_受伤')))
 row.lastHp=hp;row.lastMp=mp
 if update then Pet.UpPet(p,row.pet) end
 return true
end
function M:finish(s)
 if not s.battle then return end
 for i,row in ipairs(s.rows) do
  local synced=self:sync(s.owner,row,false)
  if synced then
   if (row.xp or 0)>0 and not row.dead then
    set(row.pet,'CHAR_经验',math.min(2147483647,num(row.pet,'CHAR_经验')+row.xp))
   end
   row.xp=0;Pet.UpPet(s.owner,row.pet);self:refresh(row)
  end
  row.lastTurn=nil;row.command=nil
 end
 if self.battleOwners[s.battle]==s then self.battleOwners[s.battle]=nil end
 s.battle=nil
end
function M:endOnOwnerDeath(b,s)
 if not s or s.battle~=b or s.endingDeath or not valid(s.owner) or num(s.owner,'CHAR_血')>0 then return false end
 s.endingDeath=true
 -- Exit native entries immediately, but delete dummies on the next tick:
 -- an action callback may still be using the current actor's character.
 for _,row in ipairs(s.rows) do
  row.xp=0
  self:sync(s.owner,row,true)
  if self:proxyAlive(row) and Char.GetBattleIndex(row.proxy)==b then Battle.ExitBattle(row.proxy) end
 end
 if Char.GetBattleIndex(s.owner)==b then Battle.ExitBattle(s.owner) end
 return true
end
function M:disable(p,reason)
 local s=self.active[p];if not s then return true end
 self.active[p]=nil;s.closing=true
 self:finish(s)
 for _,row in ipairs(s.rows) do
  self.proxies[row.proxy]=nil
  if self:proxyAlive(row) then
   if Char.GetBattleIndex(row.proxy)>=0 then Battle.ExitBattle(row.proxy) end
   Char.LeaveParty(row.proxy);Char.DelDummy(row.proxy)
  end
 end
 if valid(p) then NLG.UpdateParty(p);if reason then tell(p,reason) end end
 return true
end
function M:enable(p)
 if not valid(p) or not Char.IsPlayer(p) or self.proxies[p] then return false,'角色无效。' end
 if self.active[p] then return true,'五宠模式已经开启。' end
 if Char.GetBattleIndex(p)>=0 then return false,'请先结束战斗。' end
 if num(p,'CHAR_血')<=0 then return false,'人物已经倒下，请先恢复。' end
 if Char.PartyNum(p)>1 then return false,'请先离开其他玩家的队伍。' end
 if Char.PetNum(p)<1 then return false,'请携带宠物，并选好一只正常战宠。' end
 local normal=num(p,'CHAR_战宠')
 if normal<0 or normal>4 then return false,'请先将一只宠物设为战斗状态。' end
 local native=Char.GetPet(p,normal)
 if not valid(native) or num(native,'CHAR_血')<=0 then return false,'正常战宠需要有生命值。' end
 for slot=0,4 do
  local pet=Char.GetPet(p,slot)
  if valid(pet) and num(pet,'CHAR_血')<=0 then return false,'有宠物已经倒下，请先恢复。' end
 end
 local s={owner=p,uid=Char.GetUUID(p),normal=native,rows={}};self.active[p]=s
 local ok,err=pcall(function()
  for slot=0,4 do
   local pet=Char.GetPet(p,slot)
   if slot~=normal and valid(pet) then
    assert(num(pet,'CHAR_血')>0,'有宠物已经倒下，请先恢复。')
    local q=Char.CreateDummy({mapType=num(p,'CHAR_地图类型'),floor=num(p,'CHAR_地图'),
     x=num(p,'CHAR_X'),y=num(p,'CHAR_Y'),image=num(pet,'CHAR_形象'),name=tostring(get(pet,'CHAR_名字'))})
    assert(q>=0,'当前替身容量已满，请稍后再试。')
    local row={proxy=q,pet=pet,uuid=petkey(pet),slot=slot,owner=p,xp=0,token=s.uid..':'..petkey(pet)}
    Char.SetTempData(q,'FivePetProxy_v1',row.token)
    s.rows[#s.rows+1]=row;self.proxies[q]=row
    self:refresh(row)
    assert(Char.JoinParty(q,p,true)==0,'无法加入宠物小队。')
   end
  end
 end)
 if not ok then self:disable(p);return false,tostring(err):match('[^:]+$') or '开启失败。' end
 NLG.UpdateParty(p)
 return true,'五宠模式已开启。人物和主宠仍由你操作，其他'..#s.rows..'只宠物按AI行动；宠物固定前排，人物后排。'
end
function M:formation(b,s)
 s.battle=b;self.battleOwners[b]=s
 if Battle.GetPos(b,s.normal)<0 then return end
 -- Native position changes retain the entry storage and change its battle ID.
 -- Resolve Lua roster queries by that ID, as the native target resolver does.
 local side=Battle.GetPos(b,s.owner)<10 and 0 or 10
 Battle.SetEntryData(b,s.owner,CONST.BATTLE_ENTRY_BID,0)
 Battle.SetEntryData(b,s.normal,CONST.BATTLE_ENTRY_BID,5)
 for i,r in ipairs(s.rows) do
  local target=5+i
  local current=Battle.GetPos(b,r.proxy)
  if current>=0 then
   local result=Battle.SetEntryData(b,r.proxy,CONST.BATTLE_ENTRY_BID,target)
   if result~=0 or Battle.GetPlayer(b,side+target)~=r.proxy then
    error('五宠前排站位修正失败：'..tostring(result)..'，位置'..Battle.GetPos(b,r.proxy)..'，队列'..Battle.GetPlayer(b,side+target))
   end
  end
 end
 Battle.SetEntryData(b,s.owner,CONST.BATTLE_ENTRY_POSITION,1)
 Battle.SetEntryData(b,s.normal,CONST.BATTLE_ENTRY_POSITION,0)
 for _,r in ipairs(s.rows) do
  Battle.SetEntryData(b,r.proxy,CONST.BATTLE_ENTRY_POSITION,0)
 end
end
local function elements(p)
 return {num(p,'CHAR_地属性'),num(p,'CHAR_水属性'),num(p,'CHAR_火属性'),num(p,'CHAR_风属性')}
end
function M:target(b,q,a,kind)
 local pos=Battle.GetPos(b,q);local first=pos<10 and 0 or 10
 local ally=kind=='heal' or kind=='revive' or kind=='recover' or kind=='protect'
 local begin=ally and first or (10-first);local list={}
 local owner=kind=='protect' and self.proxies[q] and self.proxies[q].owner
 local elemental=not ally and kind~='combo' and a.target~='random' and a.target~='front'
 local attackElements=elemental and elements(q)
 for n=begin,begin+9 do
  local p=Battle.GetPlayer(b,n)
  if valid(p) and (kind~='protect' or p~=q) then
   local hp=num(p,'CHAR_血');local max=math.max(1,num(p,'CHAR_最大血'))
   if ((kind=='revive' and hp<=0) or (kind~='revive' and hp>0))
    and (kind~='protect' or hp*2<max) then
    list[#list+1]={pos=Battle.GetPos(b,p),hp=hp,ratio=hp/max,owner=p==owner,
     front=Battle.GetEntryData(b,p,CONST.BATTLE_ENTRY_POSITION)==0,
     advantage=elemental and Battle.CalcPropScore(attackElements,elements(p),0)>1 or false}
   end
  end
 end
 if #list==0 then return nil end
 if kind=='attack' or kind=='combo' then
  local front={};for _,v in ipairs(list) do if v.front then front[#front+1]=v end end
  if #front>0 then list=front end
 end
 if kind=='protect' then
  table.sort(list,function(x,y)
   if x.owner~=y.owner then return x.owner end
   if x.hp~=y.hp then return x.hp<y.hp end;return x.pos<y.pos end)
 elseif kind=='heal' or kind=='recover' then
  table.sort(list,function(x,y)return x.ratio<y.ratio end)
  if kind=='heal' and list[1].ratio>=0.7 then return nil end
 elseif a.target=='random' then return list[NLG.Rand(1,#list)].pos
 elseif a.target=='front' then
  table.sort(list,function(x,y) if x.front~=y.front then return x.front end;return x.hp<y.hp end)
 else table.sort(list,function(x,y)
  if x.advantage~=y.advantage then return x.advantage end
  if x.hp~=y.hp then return x.hp<y.hp end;return x.pos<y.pos end) end
 return list[1].pos
end
-- Conservative normal-hit estimate, without assuming critical hits or combo damage.
function M:normalDamage(b,q,p)
 if not valid(p) then return 0 end
 local attack=num(q,'CHAR_攻击力');local defense=math.max(0,num(p,'CHAR_防御力'))
 if attack<=defense then return 0 end
 if Battle.GetBattleFieldAttribute(b)~=0 then return 0 end
 for _,k in ipairs({'战属_攻吸','战属_攻反','战属_攻无','战属_防增','战属_石'}) do
  if CONST[k] and Battle.GetBattleCharacterStatus(p,CONST[k])>0 then return 0 end
 end
 local rate=Battle.CalcAttributeDmgRate(q,p)*math.max(0,1+Battle.CalcTribeDmgRate(q,p))
 if num(p,'CHAR_BattleCom1')==CONST.BATTLE_COM.BATTLE_COM_GUARD then rate=rate*0.5 end
 return math.max(0,math.floor((attack-defense)*rate*0.75))
end
function M:normalCanKill(b,q,target)
 local p=Battle.GetPlayer(b,target)
 if not valid(p) then return false end
 local first=Battle.GetPos(b,q)<10 and 10 or 0
 if target<first or target>first+9 then return false end
 -- Use the same melee frontage rule as normal attack targeting.
 if Battle.GetEntryData(b,p,CONST.BATTLE_ENTRY_POSITION)~=0 then
  for n=first,first+9 do local enemy=Battle.GetPlayer(b,n)
   if valid(enemy) and num(enemy,'CHAR_血')>0
    and Battle.GetEntryData(b,enemy,CONST.BATTLE_ENTRY_POSITION)==0 then return false end
  end
 end
 return valid(p) and num(p,'CHAR_血')>0 and num(p,'CHAR_血')<=self:normalDamage(b,q,p)
end
function M:skillCommand(b,row,a,id,attackOnly)
 local q=row.proxy
 if id<=0 or not self:learned(row.pet,id) then return nil end
 local t=self:tech(id)
 if not t or num(q,'CHAR_魔')<t.cost or (attackOnly and not OFFENSIVE[t.fn]) then return nil end
 local kind='magic'
 if t.fn=='TECH_Heal_Magic' or t.fn=='TECH_LpRecovery' then kind='heal'
 elseif t.fn=='TECH_Revive' then kind='revive'
 elseif t.fn=='TECH_StatusRecover' or t.fn=='TECH_Treat_Type' then kind='recover'
 elseif t.fn=='TECH_BodyGuard' then kind='protect'
 elseif t.command~=CONST.BATTLE_COM.BATTLE_COM_P_MAGIC then kind='attack' end
 local target=SELF[t.fn] and Battle.GetPos(b,q) or self:target(b,q,a,kind)
 if not target then return nil end
 if OFFENSIVE[t.fn] and self:normalCanKill(b,q,target) then
  return {CONST.BATTLE_COM.BATTLE_COM_ATTACK,target,7300}
 end
 if math.floor(t.target/256)%2==1 then target=target<10 and 40 or 41
 elseif math.floor(t.target/128)%2==1 then target=target+20 end
 return {t.command,target,t.id}
end
function M:choose(b,row)
 local q=row.proxy;local a=self:ai(row.owner,row.pet);local selfpos=Battle.GetPos(b,q)
 local guard={CONST.BATTLE_COM.BATTLE_COM_GUARD,selfpos,7400}
 if row.dead or a.mode=='guard' or (a.lowHpGuard and num(q,'CHAR_血')*100<=math.max(1,num(q,'CHAR_最大血'))*a.threshold) then return guard end
 if a.bossCombo and Battle.IsBossBattle(b)==1 then
  local target=self:comboTarget(b,row)
  return target and {CONST.BATTLE_COM.BATTLE_COM_ATTACK,target,7300} or guard
 end
 if a.mode=='skill' then
  local cmd=self:skillCommand(b,row,a,a.tech)
  if cmd then return cmd end
  local t=self:tech(a.tech)
  if t and t.fn=='TECH_BodyGuard' then
   cmd=self:skillCommand(b,row,a,a.fallbackTech,true)
   if cmd then return cmd end
  end
 end
 local target=self:target(b,q,a,'attack')
 return target and {CONST.BATTLE_COM.BATTLE_COM_ATTACK,target,7300} or guard
end
function M:comboTarget(b,row)
 local owner=row.owner;local pos=Battle.GetPos(b,row.proxy)
 local chosen=num(owner,'CHAR_BattleCom2')
 if num(owner,'CHAR_BattleCom1')==CONST.BATTLE_COM.BATTLE_COM_ATTACK and chosen>=0 and chosen<=19 then
  local target=Battle.GetPlayer(b,chosen)
  if valid(target) and num(target,'CHAR_血')>0 and math.floor(chosen/10)~=math.floor(pos/10)
   and Battle.PositionCheck(row.proxy,chosen)==1 then return chosen end
 end
 return self:target(b,row.proxy,{target='weak'},'combo')
end
function M:command(b,row)
 local q=row.proxy;if not self:proxyAlive(row) or Battle.IsWaitingCommand(q)~=1 then return end
 if self:ai(row.owner,row.pet).bossCombo and Battle.IsBossBattle(b)==1 and Battle.IsWaitingCommand(row.owner)==1 then return end
 local turn=Battle.GetTurn(b)
 if row.lastTurn==turn and row.commandBattle==b then return end
 self:attributes(row)
 local cmd=self:choose(b,row);row.command=cmd;row.lastTurn=turn;row.commandBattle=b
 set(q,'CHAR_BattleCom1',cmd[1]);set(q,'CHAR_BattleCom2',cmd[2]);set(q,'CHAR_BattleCom3',cmd[3])
 set(q,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE)
 set(q,'CHAR_Battle2Com2',-1);set(q,'CHAR_Battle2Com3',-1)
 set(q,'CHAR_BattleMode',3)
end
function M:tick()
 local owners={};for p in pairs(self.active) do owners[#owners+1]=p end
 for _,p in ipairs(owners) do
  local s=self.active[p]
  if s.endingDeath then self:disable(p,'人物倒下，五宠战斗已结束。')
  elseif not valid(p) or Char.GetUUID(p)~=s.uid then self:disable(p)
  else
   local b=Char.GetBattleIndex(p)
   local broken=Char.GetPet(p,num(p,'CHAR_战宠'))~=s.normal or Char.PetNum(p)~=#s.rows+1
   for _,r in ipairs(s.rows) do if not self:owned(p,r) or not self:proxyAlive(r) then broken=true end end
   if broken then self:disable(p,'宠物或主战宠已改变，当前五宠小队已暂停。')
   elseif b>=0 then
    if Battle.GetType(b)==CONST.战斗_PVP then self:disable(p,'五宠模式仅用于单人普通战斗，当前小队已暂停。')
    else
     self:formation(b,s)
     s.battle=b
     if not self:endOnOwnerDeath(b,s) then
      for _,r in ipairs(s.rows) do self:command(b,r) end
     end
    end
   else
    self:finish(s)
    for _,r in ipairs(s.rows) do
     if Char.GetBattleIndex(r.proxy)>=0 then Battle.ExitBattle(r.proxy) end
    end
    local members={};for n=0,4 do local q=Char.GetPartyMember(p,n);if valid(q) then members[q]=true end end
    local invalidParty=false;local deadPet=false
    for q in pairs(members) do if q~=p and not self.proxies[q] then invalidParty=true end end
    for _,r in ipairs(s.rows) do if not members[r.proxy] then invalidParty=true end end
    for _,r in ipairs(s.rows) do if num(r.pet,'CHAR_血')<=0 then deadPet=true end end
    if invalidParty or deadPet then self:disable(p,deadPet and '有宠物倒下，恢复后将自动重启五宠模式。' or '队伍已改变，当前五宠小队已暂停。')
    else
     -- Native party movement carries the companions, including map transitions.
     -- Warping a member also warps the leader and reloads the connected client's map.
     for _,r in ipairs(s.rows) do self:refresh(r) end
    end
   end
  end
 end
 self:autoEnable()
end
function M:near(p)
 return valid(p) and valid(self.npc) and Char.GetBattleIndex(p)<0
  and num(p,'CHAR_地图')==num(self.npc,'CHAR_地图') and num(p,'CHAR_地图类型')==num(self.npc,'CHAR_地图类型')
  and math.abs(num(p,'CHAR_X')-num(self.npc,'CHAR_X'))<=3 and math.abs(num(p,'CHAR_Y')-num(self.npc,'CHAR_Y'))<=3
end
function M:show(p,kind,options,pet,page,title)
 if not self:near(p) then return end
 self.seq=self.seq+1;local seq=7500+self.seq%20000
 self.menus[p]={kind=kind,pet=pet,uuid=pet and petkey(pet),page=page or 1,seq=seq,expires=os.time()+60,options=options}
 local lines={};for _,o in ipairs(options) do lines[#lines+1]=o.label end
 NLG.ShowWindowTalked(p,self.npc,2,2,seq,self:NPC_buildSelectionText(title or '五宠指挥官',lines))
end
function M:menu(p)
 local ops={{label=self:enabled(p) and '关闭五宠模式' or '开启单人五宠模式',action='toggle'}}
 local normal=num(p,'CHAR_战宠')
 for slot=0,4 do
  local pet=Char.GetPet(p,slot)
  if valid(pet) and slot~=normal then
   local a=self:ai(p,pet)
   ops[#ops+1]={label=tostring(get(pet,'CHAR_名字'))..'：'..MODES[a.mode],action='pet',pet=pet}
  end
 end
 ops[#ops+1]={label='使用说明',action='help'}
 self:show(p,'main',ops)
end
function M:petMenu(p,pet)
 if Pet.GetOwner(pet)~=p then return end
 local a=self:ai(p,pet)
 local t=self:tech(a.tech);local fallback=self:tech(a.fallbackTech)
 self:show(p,'pet',{{label='普攻',mode='attack'},{label='技能优先',mode='skill'},
  {label='全程防御',mode='guard'},{label='低血防御（'..a.threshold..'%及以下）：'..(a.lowHpGuard and '开启' or '关闭'),action='lowHpGuard'},
  {label='优先技能：'..(t and t.name or '未选择'),action='skills'},
  {label='攻击目标：'..TARGETS[a.target],action='targets'},
  {label='BOSS合击优先：'..(a.bossCombo and '开启' or '关闭'),action='bossCombo'},
  {label='护卫备用攻击技能：'..(fallback and fallback.name or '普攻'),action='fallbackSkills'},
  {label='返回',action='back'}},pet,nil,tostring(get(pet,'CHAR_名字'))..' AI／'..MODES[a.mode])
end
function M:skillMenu(p,pet,page,fallback)
 local all=fallback and {{label='不使用技能（普攻）',fallbackTech=0}} or {}
 for n=0,9 do local id=Pet.GetSkill(pet,n);local t=id>=0 and self:tech(id)
  if t and (not fallback or OFFENSIVE[t.fn]) then
   local option={label=t.name..'（耗魔'..t.cost..'）'}
   if fallback then option.fallbackTech=id else option.tech=id end;all[#all+1]=option
  elseif not fallback and id>=0 and Tech.GetTechIndex(id)>=0 then
   all[#all+1]={label=Tech.GetData(Tech.GetTechIndex(id),CONST.TECH_NAME)..'（不能自动施放）',action='unsupported'}
  end end
 local count=math.max(1,math.ceil(#all/6));page=math.min(page or 1,count);local ops={}
 for n=(page-1)*6+1,math.min(page*6,#all) do ops[#ops+1]=all[n] end
 ops[#ops+1]={label=count>1 and '下一页' or '没有更多技能',action='next',count=count}
 ops[#ops+1]={label='返回',action='back'}
 self:show(p,fallback and 'fallbackSkills' or 'skills',ops,pet,page,(fallback and '选择护卫备用攻击技能 ' or '选择已学会的技能 ')..page..'/'..count)
end
function M:answer(npc,p,seq,button,line)
 local s=self.menus[p];self.menus[p]=nil
 if not s or npc~=self.npc or seq~=s.seq or s.expires<os.time() or not self:near(p) then return end
 if tonumber(button)==2 then return end
 if tonumber(button)~=0 and tonumber(button)~=1 then return end
 local choice=tonumber(line);if not choice or choice~=math.floor(choice) then return end
 local o=s.options[choice]
 if not o then return end
 if s.pet and (not valid(s.pet) or Pet.GetOwner(s.pet)~=p or petkey(s.pet)~=s.uuid) then return end
 if s.kind=='main' then
  if o.action=='toggle' then
   if self:enabled(p) then self:setEnabled(p,false)
   elseif self:setEnabled(p,true) then local ok,msg=self:enable(p);tell(p,msg) end
   self:menu(p)
  elseif o.action=='pet' then self:petMenu(p,o.pet)
  else tell(p,'五宠默认开启；携带1至5只存活宠物并选好主宠后，单人自动启动。人物和主宠手动操作，其他宠物分别配置AI与优先技能；低血防御为独立开关，可与技能优先同时开启，血量达到或低于30%时先防御，恢复后沿用原行动配置；默认攻击优先属性克制，同为克制或无克制时选当前血量最低的敌人；护卫仅对血量低于50%的其他存活队友使用，优先主角，否则选择当前血量最低的宠物，无护卫目标时使用已配置的备用攻击技能，未配置或缺魔时普攻；攻击技能的目标若保守预估普攻可击杀则改普攻，BOSS合击优先改用同目标普攻。宠物固定前排，人物后排；缺魔时普攻。仅限单人，开关与AI配置会保存；输入 /fivepet off 关闭。');self:menu(p) end
 elseif o.action=='back' then if s.kind=='pet' then self:menu(p) else self:petMenu(p,s.pet) end
 elseif o.action=='skills' then self:skillMenu(p,s.pet,1)
 elseif o.action=='fallbackSkills' then self:skillMenu(p,s.pet,1,true)
 elseif o.action=='targets' then self:show(p,'targets',{{label=TARGETS.weak,target='weak'},{label=TARGETS.front,target='front'},{label=TARGETS.random,target='random'},{label='返回',action='back'}},s.pet)
 elseif o.action=='next' then self:skillMenu(p,s.pet,s.page%o.count+1,s.kind=='fallbackSkills')
 elseif o.action=='unsupported' then tell(p,'此技能是被动技能或尚不支持自动施放，请选择其他主动技能。');self:skillMenu(p,s.pet,s.page)
 else
  local a=self:ai(p,s.pet)
  if o.mode=='skill' and (not self:learned(s.pet,a.tech) or not self:tech(a.tech)) then
   tell(p,'请先选择这只宠物要使用的已学主动技能。');self:skillMenu(p,s.pet,1);return
  end
  if o.mode then a.mode=o.mode end
  if o.action=='bossCombo' then a.bossCombo=not a.bossCombo end
  if o.action=='lowHpGuard' then a.lowHpGuard=not a.lowHpGuard end
  if o.target then a.target=o.target end
  if o.tech then if not self:learned(s.pet,o.tech) or not self:tech(o.tech) then return end;a.tech=o.tech;a.mode='skill' end
  if o.fallbackTech~=nil then
   local t=self:tech(o.fallbackTech)
   if o.fallbackTech~=0 and (not t or not OFFENSIVE[t.fn] or not self:learned(s.pet,o.fallbackTech)) then return end
   a.fallbackTech=o.fallbackTech
  end
  if self:saveAI(p,s.pet,a) then tell(p,'宠物AI配置已保存。') end
  self:petMenu(p,s.pet)
 end
end
function M:onLoad()
 self.active={};self.proxies={};self.configs={};self.menus={};self.seq=0;self.autoAttempts={};self.nextAutoCheck=0;self.battleOwners={}
 self.nativeGetPlayer=Battle.GetPlayer
 self.nativeGetPlayIndex=Battle.GetPlayIndex
 self.rosterWrapper=function(b,pos)
  local s=self.battleOwners[b]
  if not s or self.active[s.owner]~=s or s.battle~=b or type(pos)~='number' or pos~=math.floor(pos) or pos<0 or pos>19 then return self.nativeGetPlayer(b,pos) end
  for physical=0,19 do
   local q=self.nativeGetPlayer(b,physical)
   if valid(q) and Battle.GetPos(b,q)==pos then return q end
  end
  return -1
 end
 Battle.GetPlayer=self.rosterWrapper
 Battle.GetPlayIndex=self.rosterWrapper
 self.npc=self:NPC_createNormal('五宠指挥官',14073,{mapType=0,map=1000,x=151,y=112,direction=4})
 assert(self.npc>=0,'Five-pet commander NPC creation failed')
 self:NPC_regTalkedEvent(self.npc,function(n,p) self:menu(p) end)
 self:NPC_regWindowTalkedEvent(self.npc,Func.bind(self.answer,self))
 self:AddInterval(250,function()
  local ok,err=pcall(self.tick,self)
  if not ok then
   self:logError('fivePet tick: '..tostring(err))
   local ps={};for p in pairs(self.active) do ps[#ps+1]=p end
   for _,p in ipairs(ps) do pcall(self.disable,self,p,'宠物AI遇到异常，五宠模式已关闭。') end
  end
 end,1)
 self:regCallback('TalkEvent',function(p,msg)
  if msg=='/fivepet off' then self:setEnabled(p,false);return 0 end
  if msg=='/fivepet on' then
   if self:setEnabled(p,true) then local ok,s=self:enable(p);tell(p,s) end
   return 0
  end
  return 1
 end)
 self:regCallback('PartyEvent',function(p,target,kind)
  if kind==0 and not self.proxies[p] and (self.active[p] or self.active[target] or self.proxies[target]) then
   tell(p,'请先关闭五宠模式再与其他玩家组队。');return 0
  end
  return 1
 end)
 self:regCallback('AfterCalcCharaStatusEvent',function(p) local r=self.proxies[p];if r then self:attributes(r) end end)
 self:regCallback('AfterCalcCharaBpEvent',function(p) local r=self.proxies[p];if r then self:attributes(r) end end)
 self:regCallback('CalcFpConsumeEvent',function(p,id,fp)
  local r=self.proxies[p];local t=r and self:tech(id)
  if t then return t.cost end;return fp
 end)
 -- Companions use native player entries. Their unused second action clears
 -- the current command, which otherwise disables reactive guard/bodyguard.
 self:regCallback('BattleAfterActionEvent',function(b,q)
  local squad=self.battleOwners[b]
  if squad and (squad.endingDeath or self:endOnOwnerDeath(b,squad)) then return 0 end
  local row=self.proxies[q];local cmd=row and row.command
  if cmd and row.commandBattle==b and self:proxyAlive(row) then
   local tech=self:tech(cmd[3])
   if cmd[1]==CONST.BATTLE_COM.BATTLE_COM_GUARD or (tech and (SELF[tech.fn] or tech.fn=='TECH_BodyGuard')) then
    set(q,'CHAR_BattleCom1',cmd[1]);set(q,'CHAR_BattleCom2',cmd[2]);set(q,'CHAR_BattleCom3',cmd[3])
   end
  end
  return 0
 end)
 self:regCallback('BattleHealCalculateEvent',function(p,q,ori,heal,b,cmd)
  local r=self.proxies[q]
  if r and heal>0 and cmd==CONST.BATTLE_COM.BATTLE_COM_P_REVIVE then r.revivePending=true end
  return heal
 end)
 self:regCallback('GetExpEvent',function(p,xp)
  local r=self.proxies[p]
  if r then r.xp=(r.xp or 0)+math.max(0,xp);return 0 end
  return xp
 end)
 self:regCallback('BattleGetProfitEvent',function(b,side,pos,p,kind,reward)
  if self.proxies[p] then
   if kind==-2 then return 0 end
   if kind>=0 then return -1 end
  end
  return reward
 end)
 self:regCallback('AfterBattleTurnEvent',function(b)
  for p,s in pairs(self.active) do if s.battle==b then
   self:formation(b,s)
   for _,r in ipairs(s.rows) do self:sync(p,r,true) end
  end end
 end)
 self:regCallback('ResetCharaBattleStateEvent',function(q)
  local r=self.proxies[q];if r then self:sync(r.owner,r,false) end
 end)
 self:regCallback('BeforeCharaSaveEvent',function(p)
  local s=self.active[p];if s and s.battle then for _,r in ipairs(s.rows) do self:sync(p,r,false) end end
 end)
 for _,event in ipairs({'LogoutEvent','DropEvent'}) do self:regCallback(event,function(p)
  self:disable(p);self.configs[p]=nil;self.menus[p]=nil;self.autoAttempts[p]=nil;return 0
 end) end
 self:regCallback('LoginEvent',function(p)
  self.configs[p]=nil;self.autoAttempts[p]=nil;self.nextAutoCheck=0
  return 0
 end)
 self:regCallback('BattleExitEvent',function(p,b,kind)
  local row=self.proxies[p]
  if row and self:proxyAlive(row) then
   if kind==2 or num(p,'CHAR_血')<=0 then row.dead=true end
   self:sync(row.owner,row,false)
   return
  end
  if self.active[p] then
   if self.active[p].endingDeath then return end
   local aliveEnemy=false
   for pos=0,19 do local q=Battle.GetPlayer(b,pos)
    if valid(q) and Char.IsEnemy(q) and num(q,'CHAR_血')>0 then aliveEnemy=true end
   end
   if kind==2 or aliveEnemy then self:disable(p,'战斗已退出，当前五宠小队已暂停。') end
  end
 end)
 self:regCallback('BattleEscapeEvent',function(b,p,rate)
  if rate==1 and self.active[p] then self:disable(p,'逃跑成功，当前五宠小队已暂停。') end
  return rate
 end)
 self:regCallback('ShutDownEvent',function() self:onUnload();return 0 end)
 -- BattleStartEvent runs before entries are fully initialized. Apply the row
 -- after initialization and before the first roster packet reaches the client.
 self:regCallback('BattlePreEvent',OrderedCallback(function(b)
  for p,s in pairs(self.active) do
   if Battle.GetPos(b,p)>=0 then self:formation(b,s) end
  end
  return 0
 end,10000))
 self:regCallback('BattleStartEvent',function(b)
  for p,s in pairs(self.active) do if Battle.GetPos(b,p)>=0 then
   if Battle.GetType(b)==CONST.战斗_PVP then self:disable(p,'五宠模式仅用于单人普通战斗。')
   else s.battle=b;for _,r in ipairs(s.rows) do self:refresh(r);r.lastTurn=nil end end
  end end
  return 0
 end)
 self:logInfo('Five-pet AI ready; enabled by default; commander at Falan 151,112')
end
function M:onUnload()
 local ps={};for p in pairs(self.active or {}) do ps[#ps+1]=p end
 for _,p in ipairs(ps) do self:disable(p) end
 if Battle.GetPlayer==self.rosterWrapper then Battle.GetPlayer=self.nativeGetPlayer end
 if Battle.GetPlayIndex==self.rosterWrapper then Battle.GetPlayIndex=self.nativeGetPlayIndex end
 self.configs={};self.menus={};self.autoAttempts={}
end
return M
