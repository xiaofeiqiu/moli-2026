-- Source UTF-8; build.py writes GBK for the native Lua loader.
local M=ModuleBase:createModule('fivePet')
local KEY='FivePetAI_v1'
local ATTR={'CHAR_最大血','CHAR_最大魔','CHAR_攻击力','CHAR_防御力','CHAR_敏捷',
 'CHAR_精神','CHAR_回复','CHAR_地属性','CHAR_水属性','CHAR_火属性','CHAR_风属性',
 'CHAR_抗毒','CHAR_抗睡','CHAR_抗石','CHAR_抗醉','CHAR_抗乱','CHAR_抗忘',
 'CHAR_必杀','CHAR_反击','CHAR_命中','CHAR_闪躲','CHAR_种族','CHAR_魔攻','CHAR_魔抗'}
local GROWTH={'CHAR_等级','CHAR_经验','CHAR_升级点','CHAR_体力','CHAR_力量','CHAR_强度','CHAR_速度','CHAR_魔法','宠物_获取时等级'}
local RANKS={'宠档_体成','宠档_力成','宠档_强成','宠档_敏成','宠档_魔成'}
local SkillAI=dofile('lua/Modules/petSkillAI.lua')
local function strongGuard(id)
 local tutor=getModule('petSkillTutor')
 return tutor and tutor.strongGuardTech and tutor:strongGuardTech(id)
end
local STATUS={poison='战属_毒',sleep='战属_睡',stone='战属_石',drunk='战属_醉',forget='战属_忘',confuse='战属_乱'}
local MODES={attack='智能战斗',skill='智能战斗',guard='全程防御'}
local function get(p,k) local c=CONST[k];if c==nil then return nil end;return Char.GetData(p,c) end
local function num(p,k) return tonumber(get(p,k)) or 0 end
local function set(p,k,v) local c=CONST[k];if c~=nil and v~=nil then return Char.SetData(p,c,v) end end
local function valid(p) return type(p)=='number' and p>=0 and Char.IsValidCharIndex(p) end
local function tell(p,s) if valid(p) then NLG.SystemMessage(p,s) end end
local function petkey(pet) return tostring(Pet.GetUUID(pet)) end
local function default() return {mode='attack'} end
function M:proxyAlive(row)
 local q=row.proxy
 if row.bankSlot~=nil then
  return valid(q) and Char.IsPet(q) and valid(row.carrier)
   and Char.GetPet(row.carrier,0)==q and Pet.GetOwner(q)==row.carrier
   and Char.GetTempData(q,'FivePetProxy_v1')==row.token
 end
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
 -- Old skill/attack/cautious settings all become automatic; explicit full defense survives.
 return {mode=a.mode=='guard' and 'guard' or 'attack',target='weak'}
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
   local signature=self:rosterSignature(p)
   if not attempt or attempt.uid~=uid or attempt.signature~=signature or (not attempt.blocked and now>=attempt.next) then
    local ok,reason=self:enable(p)
    if ok then self.autoAttempts[p]=nil
    elseif self.autoAttempts[p] and self.autoAttempts[p].blocked then tell(p,reason)
    else self.autoAttempts[p]={uid=uid,signature=signature,next=now+2} end
   end
  end
 end
end
function M:saveAI(p,pet,a)
 if not self:hasPet(p,pet) then return false end
 local d=self:config(p);d.pets[petkey(pet)]=a
 Char.SetExtData(p,KEY,JSON.encode(d))
 if not Char.IsDummy(p) then Char.SaveToDb(p) end
 return true
end
-- Read-only damage observation includes the owner/main pet. Commands still target proxies only.
-- Capture HP before damage and settle after the native action, so healing, guards,
-- zero damage and later callback adjustments cannot become invented damage samples.
function M:watchDamage(b,a,d,damage,command,id)
 local s=self.battleOwners[b]
 if not s or s.battle~=b or not valid(a) or not valid(d) or Battle.GetPos(b,d)<0
  or Battle.GetPos(b,a)<0 or (Battle.GetPos(b,a)<10)==(Battle.GetPos(b,s.owner)<10)
  or (Battle.GetPos(b,d)<10)~=(Battle.GetPos(b,s.owner)<10) then return end
 local t=self:tech(id);local kind=t and t.command==command and t.category=='magic' and 'magic' or 'physical'
 s.damagePending=s.damagePending or {};local pending=s.damagePending[d]
 if not pending then pending={hp=num(d,'CHAR_血'),sources={}};s.damagePending[d]=pending end
 local key=a..':'..kind;local hit=pending.sources[key]
 if not hit then
  local stance=self:tech(num(d,'CHAR_BattleCom3'))
  local masked=not self:safeTarget(d,kind=='magic') or (stance and stance.effect=='defend' and stance.fn~='TECH_NormalGuard')
  hit={attacker=a,kind=kind,tech=not masked and id or nil,amount=0,guarded=kind=='physical' and num(d,'CHAR_BattleCom1')==CONST.BATTLE_COM.BATTLE_COM_GUARD};pending.sources[key]=hit
 end
 hit.amount=hit.amount+math.max(0,tonumber(damage) or 0)
end
function M:settleDamage(b)
 local s=self.battleOwners[b];if not s or not s.damagePending then return end
 local pending=s.damagePending;s.damagePending=nil;s.damageHistory=s.damageHistory or {}
 local turn=Battle.GetTurn(b)
 for d,sample in pairs(pending) do if valid(d) then
  local loss=math.max(0,sample.hp-math.max(0,num(d,'CHAR_血')));local total,count=0,0
  for _,hit in pairs(sample.sources) do total=total+hit.amount;count=count+1 end
  local history=s.damageHistory[d] or {};s.damageHistory[d]=history
  for _,hit in pairs(sample.sources) do
   local row=history[hit.attacker]
   if not row then row={};history[hit.attacker]=row end;row.turn=turn
    local stamp=hit.kind..'Turn';if row[stamp]~=turn then row[hit.kind]=0 end;row[stamp]=turn
   local actual=loss*(total>0 and hit.amount/total or 1/math.max(1,count))
   -- Remember the unguarded equivalent; successful defense must not look like a harmless enemy.
   row[hit.kind]=(row[hit.kind] or 0)+actual*(hit.guarded and 2 or 1);row[hit.kind..'Tech']=hit.tech
  end
 end end
end
function M:forecast(b,q)
 local f={physical=0,magic=0,maxPhysical=0,maxMagic=0,remainingPhysical=0,remainingMagic=0,hp=num(q,'CHAR_血'),max=math.max(1,num(q,'CHAR_最大血')),sources={}}
 local pos=Battle.GetPos(b,q);if pos<0 then f.ending=f.hp;f.nextEnding=f.hp;return f end
 local s=self.battleOwners[b];local history=s and s.damageHistory and s.damageHistory[q] or {}
 local first=pos<10 and 10 or 0;local turn=Battle.GetTurn(b)
 local difficulty=getModule('gameDifficulty');local state=difficulty and difficulty.battles[b]
 local scale=state and difficulty.tiers[state.tier].damage or 1
 for n=first,first+9 do local a=Battle.GetPlayer(b,n)
  if valid(a) and num(a,'CHAR_血')>0 and not self:hasStatus(a,'战属_睡') and not self:hasStatus(a,'战属_石') then
   local t=self:tech(num(a,'CHAR_BattleCom3'))
   if not t or t.command~=num(a,'CHAR_BattleCom1') then t=self:tech(7300) end
   if t and t.canEnemy and (t.category=='physical' or t.category=='magic') and t.effect~='control' then
    if t.cost>num(a,'CHAR_魔') or self:hasStatus(a,'战属_忘') then t=self:tech(7300) end
    local kind=t.category=='magic' and 'magic' or 'physical'
    if (t.ranged or self:meleeReachable(b,a,pos)) and self:safeTarget(q,kind=='magic') then
     local observed=history[a];local amount
     local stamp=observed and (observed[kind..'Turn'] or observed.turn)
     if stamp and turn-stamp>=0 and turn-stamp<=2 and observed[kind]~=nil and observed[kind..'Tech']==t.id then
      amount=observed[kind]
     else
      amount=kind=='magic' and self:magicDamage(a,q,t) or math.max(1,self:normalDamage(b,a,q))
      if kind=='physical' then
       if num(q,'CHAR_BattleCom1')==CONST.BATTLE_COM.BATTLE_COM_GUARD then amount=amount*2 end
       amount=amount*math.max(0.1,t.damageFactor)*(t.repeatHits and t.minHits or 1)
      end
      amount=amount*scale
     end
     amount=math.max(0,amount);f[kind]=f[kind]+amount
     local maxKey=kind=='magic' and 'maxMagic' or 'maxPhysical';f[maxKey]=math.max(f[maxKey],amount)
     local acted=s and s.enemyActed and s.enemyActed[a]==turn
     if not acted then local key=kind=='magic' and 'remainingMagic' or 'remainingPhysical';f[key]=f[key]+amount end
     f.sources[a]={kind=kind,amount=amount,acted=acted}
    end
   end
  end
 end
 f.damage=f.remainingPhysical+f.remainingMagic;f.nextDamage=f.physical+f.magic
 f.ending=f.hp-f.damage;f.nextEnding=f.ending-f.nextDamage
 return f
end
-- Compare survival first; when everyone can survive two rounds, damage wins.
-- This is an estimate from recent actual hits plus skill/range data, not a promise about RNG.
function M:survivalPlan(b,row,skills,attack)
 local q=row.proxy;local forecasts={};local first=Battle.GetPos(b,q)<10 and 0 or 10
 local risk=false;local immediate=false
 for pos=first,first+9 do local p=Battle.GetPlayer(b,pos)
  if valid(p) and num(p,'CHAR_血')>0 then
   local f=self:forecast(b,p);forecasts[p]=f
   if f.nextEnding<=0 then risk=true end;if f.ending<=0 then immediate=true end
  end
 end
 if not risk then
  if attack[3]==7400 then return self:automaticSupport(b,row,skills,{skipGuard=true}) or attack end
  return attack
 end
 local function evaluate(cmd,changes,cost,enemyDamage)
  local v={cmd=cmd,deaths=0,nextDeaths=0,hp=0,nextHP=0,cost=cost or 0,damage=enemyDamage or 0}
  for p,f in pairs(forecasts) do
   local c=changes[p] or {};local hp=math.min(f.max,f.hp+(c.heal or 0))
   local prevented=math.min(f.remainingPhysical,c.physical or 0)+math.min(f.remainingMagic,c.magic or 0)
   local remaining=hp-f.damage+prevented-(c.extra or 0)
   if not c.instant then
    local early=0;for enemy,hit in pairs(f.sources) do
     if not hit.acted and num(q,'CHAR_敏捷')<=num(enemy,'CHAR_敏捷')*1.5 then early=early+hit.amount end
    end
    if early>=f.hp and (c.heal or c.physical or c.magic) then remaining=math.min(0,f.hp-early) end
   end
   local future=remaining-f.nextDamage+(c.future or 0)
   local weight=p==row.owner and 10 or 1
   if remaining<=0 then v.deaths=v.deaths+weight end
   if future<=0 then v.nextDeaths=v.nextDeaths+weight end
   v.hp=v.hp+math.max(0,remaining);v.nextHP=v.nextHP+math.max(0,future)
  end
  return v
 end
 local function better(a,c)
  if a.deaths~=c.deaths then return a.deaths<c.deaths end
  if a.nextDeaths~=c.nextDeaths then return a.nextDeaths<c.nextDeaths end
  if a.deaths>0 or a.nextDeaths>0 or immediate then
   if math.abs(a.hp-c.hp)>0.01 then return a.hp>c.hp end
   if math.abs(a.nextHP-c.nextHP)>0.01 then return a.nextHP>c.nextHP end
  end
  if a.damage~=c.damage then return a.damage>c.damage end
  if math.abs(a.hp-c.hp)>0.01 then return a.hp>c.hp end
  return a.cost<c.cost
 end
 local own=forecasts[q];if not own then return attack end
 local blockers=self:bossBlockers(b,row.owner)
 local function finishingChanges(offensive,target)
  local changes={}
  if offensive.effect=='control' or offensive.effect=='death' then return changes end
  -- A reliable faster finishing hit can be safer than an attack that deals more total damage.
  for _,pos in ipairs(self:affected(b,target,offensive)) do local enemy=Battle.GetPlayer(b,pos)
   if valid(enemy) and num(enemy,'CHAR_血')>0 and num(q,'CHAR_敏捷')>num(enemy,'CHAR_敏捷')*1.5
    and self:hitChance(b,q,enemy,offensive)>=0.9 then
    local damage=offensive.category=='magic' and self:magicDamage(q,enemy,offensive)
     or self:normalDamage(b,q,enemy)*offensive.damageFactor*(offensive.repeatHits and offensive.minHits or 1)
    if damage>=num(enemy,'CHAR_血') and not offensive.spread then
     for p,f in pairs(forecasts) do local incoming=f.sources[enemy]
      if incoming then local c=changes[p] or {};changes[p]=c;c[incoming.kind]=(c[incoming.kind] or 0)+incoming.amount;c.future=(c.future or 0)+incoming.amount end
     end
    end
   end
  end
  return changes
 end
 local target=attack[2];if target>=20 and target<40 then target=target-20 elseif target>=40 then target=target==40 and 0 or 10 end
 local offensive=self:tech(attack[3]);local score=offensive and offensive.canEnemy and self:attackScore(b,row,offensive,target,blockers,true) or 0
 local best=evaluate(attack,offensive and offensive.canEnemy and finishingChanges(offensive,target) or {},offensive and offensive.cost or 0,score or 0)
 local function consider(cmd,cost,change,damage) local v=evaluate(cmd,change,cost,damage);if better(v,best) then best=v end end
 -- Compare alternative finishing targets too: maximizing area damage can leave the lethal attacker alive.
 local attacks={self:tech(7300)}
 if not self:hasStatus(q,'战属_忘') then
  for _,t in ipairs(skills) do if (t.category=='physical' or t.category=='magic') and t.canEnemy and t.cost<=num(q,'CHAR_魔') then attacks[#attacks+1]=t end end
 end
 for _,t in ipairs(attacks) do for pos=10-first,19-first do local enemy=Battle.GetPlayer(b,pos)
  if valid(enemy) and num(enemy,'CHAR_血')>0 and (t.ranged or self:meleeReachable(b,q,pos)) then
   local damage=self:attackScore(b,row,t,pos,blockers,true)
   if damage then local change=finishingChanges(t,pos)
    if next(change) then consider({t.command,self:encodeTarget(pos,t),t.id},t.cost,change,damage) end
   end
  end
 end end
 consider({CONST.BATTLE_COM.BATTLE_COM_GUARD,Battle.GetPos(b,q),7400},0,{[q]={physical=own.remainingPhysical*0.5,instant=true}})
 if not self:hasStatus(q,'战属_忘') then
  for _,t in ipairs(skills) do if t.category=='support' and t.cost<=num(q,'CHAR_魔') then
   if t.effect=='heal' or t.effect=='barrier' then
    for pos=first,first+9 do local target=Battle.GetPlayer(b,pos)
     if forecasts[target] and (target~=q or t.canSelf) then
      local change={}
      for _,affected in ipairs(self:affected(b,pos,t)) do local p=Battle.GetPlayer(b,affected);local f=forecasts[p]
       if f then
        if t.effect=='heal' then change[p]={heal=(t.power.AR or 60)*math.max(0.5,num(q,'CHAR_回复')/100)}
        elseif self:safeTarget(p,t.barrier=='magic') then
         change[p]={[t.barrier]=t.barrier=='magic' and f.maxMagic or f.maxPhysical}
        end
       end
      end
      consider({t.command,self:encodeTarget(pos,t),t.id},t.cost,change)
     end
    end
   elseif t.effect=='defend' and (t.fn=='TECH_SpecialGuard' or t.fn=='TECH_MagicGuard') then
    local reduction=math.min(math.abs(t.power.RS or 0),math.abs(t.power.RE or 0))/100
    reduction=math.min(1,reduction)
    consider({t.command,Battle.GetPos(b,q),t.id},t.cost,{[q]={physical=t.fn=='TECH_SpecialGuard' and own.remainingPhysical*reduction or 0,magic=own.remainingMagic*reduction,instant=true}})
   elseif t.effect=='self_heal' then
    consider({t.command,Battle.GetPos(b,q),t.id},t.cost,{[q]={heal=own.max*(t.power.D1 or 5)/100}})
   elseif t.effect=='protect' then
    local tutor=getModule('petSkillTutor');local strong=strongGuard(t.id)
    for pos=first,first+9 do local p=Battle.GetPlayer(b,pos);local f=forecasts[p]
     if f and p~=q and f.nextEnding<=0 and f.remainingPhysical>0 and not self:protected(b,p) then
      local targets=strong and tutor:strongGuardTargets(b,q,pos) or {pos};local change={};local transferred=0
      for _,target in ipairs(targets) do local ally=Battle.GetPlayer(b,target);local incoming=forecasts[ally]
       if incoming and ally~=q and not self:protected(b,ally) then
        change[ally]={physical=incoming.remainingPhysical,instant=strong~=nil};transferred=transferred+incoming.remainingPhysical*math.max(1,1-(t.power.DR or 0)/100)
       end
      end
      -- Never trade a healthy guardian for a teammate, or add damage to a dying guardian.
      if own.ending-transferred>0 then
       change[q]={extra=transferred};consider({t.command,pos,t.id},t.cost,change)
      end
     end
    end
   end
  end end
 end
 return best.cmd
end
-- A declared ranged attack defeats the screen; support/guard actions do not.
function M:screenedBoss(b,q)
 if Battle.GetEntryData(b,q,CONST.BATTLE_ENTRY_POSITION)~=1 then return false end
 local t=self:tech(num(q,'CHAR_BattleCom3'))
 if t and t.command==num(q,'CHAR_BattleCom1') and t.canEnemy
  and (t.category=='physical' or t.category=='magic') and t.ranged then return false end
 return true
end
-- Keep the screen in front of a rear Boss while both fronts shield a rear player.
-- Never identify a Boss by its name, species or HP; use the native per-enemy flag.
function M:bossBlockers(b,p)
 local protected={};if Battle.IsBossBattle(b)~=1 or not valid(p) or Battle.GetPos(b,p)<0 then return protected end
 if Battle.GetEntryData(b,p,CONST.BATTLE_ENTRY_POSITION)~=1 then return protected end
 local first=Battle.GetPos(b,p)<10 and 0 or 10;local allyFront=false;local rearBoss=false
 for pos=first,first+9 do local ally=Battle.GetPlayer(b,pos)
  if valid(ally) and num(ally,'CHAR_血')>0 and Battle.GetEntryData(b,ally,CONST.BATTLE_ENTRY_POSITION)==0 then allyFront=true end
 end
 if not allyFront then return protected end
 for pos=10-first,19-first do local enemy=Battle.GetPlayer(b,pos)
  if valid(enemy) and num(enemy,'CHAR_血')>0 and num(enemy,'对象_ENEMY_BossFlg')>0
   and self:screenedBoss(b,enemy) then rearBoss=true end
 end
 if not rearBoss then return protected end
 for pos=10-first,19-first do local enemy=Battle.GetPlayer(b,pos)
  if valid(enemy) and num(enemy,'CHAR_血')>0 and num(enemy,'对象_ENEMY_BossFlg')==0
   and Battle.GetEntryData(b,enemy,CONST.BATTLE_ENTRY_POSITION)==0 then protected[pos]=true end
 end
 return protected
end
function M:tech(id)
 local ix=Tech.GetTechIndex(id);if ix<0 then return nil end
 return SkillAI.describe({id=id,fn=Tech.GetData(ix,CONST.TECH_FUNCNAME),name=Tech.GetData(ix,CONST.TECH_NAME),
  cost=math.max(0,tonumber(Tech.GetData(ix,CONST.TECH_FORCEPOINT)) or 0),
  target=tonumber(Tech.GetData(ix,CONST.TECH_TARGET)) or 0,
  skill=tonumber(Tech.GetData(ix,CONST.TECH_SKILLID)) or 0,
  family=tonumber(Tech.GetData(ix,CONST.TECH_COMMENT)),
  option=tostring(Tech.GetData(ix,CONST.TECH_OPTION) or '')})
end
-- Skill 70 is the engine's owner passive; only currently equipped slots count.
function M:petExperienceBonus(p)
 if not valid(p) then return 0 end
 local slot=Char.HaveSkill(p,70);if slot<0 then return 0 end
 local level=Char.GetSkillLevel(p,slot)
 if not self.breedTechIds then
  local path='data/tech.txt';local config=io.open('setup.cf','rb')
  if config then
   for line in config:lines() do local value=line:match('^techfile=(.-)\r?$');if value then path=value;break end end
   config:close()
  end
  self.breedTechIds={};local file=assert(io.open(path,'rb'),'无法读取宠物强化数据。')
  for line in file:lines() do
   local id=tonumber(line:match('^[^\t]*\tTECH_Breed\t[^\t]*\t(%d+)\t'))
   if id then self.breedTechIds[#self.breedTechIds+1]=id end
  end
  file:close()
 end
 local best,bonus=0,0
 for _,id in ipairs(self.breedTechIds) do local ix=Tech.GetTechIndex(id)
  if ix>=0 and Tech.GetData(ix,CONST.TECH_SKILLID)==70 and Tech.GetData(ix,CONST.TECH_FUNCNAME)=='TECH_Breed' then
   local required=tonumber(Tech.GetData(ix,CONST.TECH_NECESSARYLV)) or 0
   if required>best and required<=level then
    best=required;bonus=math.max(0,tonumber(tostring(Tech.GetData(ix,CONST.TECH_OPTION)):match('AR:([%d%.]+)')) or 0)
   end
  end
 end
 return bonus
end
function M:petExperience(p,xp)
 local base=math.max(0,tonumber(xp) or 0)
 return math.min(2147483647,math.floor(base*(100+self:petExperienceBonus(p))/100))
end
function M:skills(pet)
 local result,seen={},{}
 for slot=0,9 do
  local id=Pet.GetSkill(pet,slot);local t=id>=0 and self:tech(id)
  if t and not seen[id] then
   result[#result+1]=t;seen[id]=true
  end
 end
 table.sort(result,function(x,y) if x.cost~=y.cost then return x.cost<y.cost end;return x.id<y.id end)
 return result
end
-- Read actual growth ranks from the original pet, including bank originals.
-- Losing ranks or filling them later changes this tendency on the next decision.
function M:petProfile(pet)
 local ranks={}
 for i,key in ipairs({'宠档_体成','宠档_力成','宠档_强成','宠档_敏成','宠档_魔成'}) do
  ranks[i]=math.max(0,tonumber(Pet.GetArtRank(pet,CONST[key])) or 0)
 end
 local vigor,force,tough,speed,magic=ranks[1],ranks[2],ranks[3],ranks[4],ranks[5]
 local types={{kind='physical',label='物理型',score=force},{kind='magic',label='法术型',score=magic},
  {kind='defensive',label='防御型',score=(vigor+tough)/2},{kind='agile',label='敏捷型',score=speed}}
 table.sort(types,function(a,c) return a.score>c.score end)
 local best=types[1];local kind,label='balanced','均衡型'
 if best.score>0 and best.score>types[2].score*1.15 then kind,label=best.kind,best.label end
 local scale=math.max(1,force,magic)
 return {kind=kind,label=label,ranks=ranks,physical=1+0.2*(force-magic)/scale,
  magic=1+0.2*(magic-force)/scale,control=kind=='agile' and 1.15 or 1,
  barrierThreshold=kind=='defensive' and 0.7 or 0.6}
end
function M:learned(pet,id)
 for n=0,9 do if Pet.GetSkill(pet,n)==id then return true end end
 return false
end
function M:owned(p,row)
 if not valid(p) or not valid(row.pet) or petkey(row.pet)~=row.uuid then return false end
 if row.bankSlot~=nil then return Char.GetPoolPet(p,row.bankSlot)==row.pet end
 if Pet.GetOwner(row.pet)~=p then return false end
 for slot=0,4 do if Char.GetPet(p,slot)==row.pet then row.slot=slot;return true end end
 return false
end
function M:hasPet(p,pet)
 if not valid(p) or not valid(pet) or not Char.IsPet(pet) then return false end
 for slot=0,4 do if Char.GetPet(p,slot)==pet then return true end end
 for slot=0,3 do if Char.GetPoolPet(p,slot)==pet then return true end end
 return false
end
function M:actors(s) return s.actors or s.rows end
function M:bankSignature(p)
 local slots={}
 for slot=0,3 do local pet=Char.GetPoolPet(p,slot)
  slots[#slots+1]=valid(pet) and Char.IsPet(pet) and petkey(pet) or '-'
 end
 return table.concat(slots,':')
end
function M:rosterSignature(p)
 local slots={tostring(num(p,'CHAR_战宠')),num(p,'CHAR_血')>0 and 'alive' or 'dead'}
 local function append(pet)
  if not valid(pet) or not Char.IsPet(pet) then slots[#slots+1]='-';return end
  slots[#slots+1]=petkey(pet);slots[#slots+1]=tostring(num(pet,'宠物_PETID'))
  slots[#slots+1]=num(pet,'CHAR_血')>0 and 'alive' or 'dead'
  for n=0,9 do slots[#slots+1]=tostring(Pet.GetSkill(pet,n)) end
 end
 for slot=0,4 do append(Char.GetPet(p,slot)) end
 for slot=0,3 do append(Char.GetPoolPet(p,slot)) end
 return table.concat(slots,':')
end
function M:petEnemyId(pet)
 -- PETID is an enemy-base ID. GivePet takes an enemy ID; e.g. base 2049
 -- is created by enemy 2019. Validate against the loaded native table.
 local base=num(pet,'宠物_PETID')
 local function matches(enemy)
  local ix=enemy and Data.EnemyGetDataIndex(enemy) or -1
  return ix>=0 and Data.EnemyGetData(ix,CONST.DATA_ENEMY_TEMPNO)==base
 end
 if matches(base) then return base end
 if not self.petEnemyIds then
  self.petEnemyIds={};local path='data/enemy.txt'
  local config=io.open('setup.cf','rb')
  if config then
   for line in config:lines() do local value=line:match('^enemyfile=(.-)\r?$');if value then path=value;break end end
   config:close()
  end
  local file=assert(io.open(path,'rb'),'无法读取宠物种类对应表。')
  for line in file:lines() do
   local id=tonumber(line:match('^[^\t]*\t[^\t]*\t(%d+)\t'))
   local ix=id and Data.EnemyGetDataIndex(id) or -1
   if ix>=0 then
    local kind=Data.EnemyGetData(ix,CONST.DATA_ENEMY_TEMPNO)
    if kind and kind>=0 and not self.petEnemyIds[kind] then self.petEnemyIds[kind]=id end
   end
  end
  file:close()
 end
 local enemy=self.petEnemyIds[base]
 assert(matches(enemy),'找不到银行宠物的创建编号：'..base)
 return enemy
end
function M:updatePet(p,row)
 if row.bankSlot==nil then return Pet.UpPet(p,row.pet) end
 local owner=Pet.GetOwner(row.pet)
 if valid(owner) then
  for slot=0,4 do
   if Char.GetPet(owner,slot)==row.pet then return Pet.UpPet(owner,row.pet) end
  end
 end
 -- UpPet rejects bank originals (-5). Run native growth on the disposable
 -- battle pet using the original's complete growth state, then copy it back.
 assert(self:proxyAlive(row),'银行宠物升级替身已失效。')
 local level=num(row.pet,'CHAR_等级');local carrierLevel=num(row.carrier,'CHAR_等级')
 row.growingBank=true
 local ok,result=pcall(function()
  for _,key in ipairs(GROWTH) do set(row.proxy,key,get(row.pet,key)) end
  for _,key in ipairs(RANKS) do
   assert(Pet.SetArtRank(row.proxy,CONST[key],Pet.GetArtRank(row.pet,CONST[key]))==0,'银行宠物成长档同步失败。')
  end
  set(row.carrier,'CHAR_等级',num(p,'CHAR_等级'))
  return Pet.UpPet(row.carrier,row.proxy)
 end)
 row.growingBank=nil;set(row.carrier,'CHAR_等级',carrierLevel)
 assert(ok,result);assert(result==0,'银行宠物原生升级失败：'..tostring(result))
 local levels=num(row.proxy,'CHAR_等级')-level
 set(row.pet,'CHAR_等级',num(row.proxy,'CHAR_等级'))
 -- Native upgrade listeners observe the old unallocated balance before growth.
 if levels>0 then PetLevelUpEvent(p,row.pet,levels) end
 for _,key in ipairs(GROWTH) do set(row.pet,key,get(row.proxy,key)) end
 Char.UpCharStatus(row.pet)
 return 0
end
function M:copyBankSkills(row)
 local ids={}
 for slot=0,9 do ids[#ids+1]=tostring(Pet.GetSkill(row.pet,slot)) end
 local signature=table.concat(ids,':')
 if signature==row.skillSignature then return end
 -- Native skill edits can synchronously recalculate status and reenter here.
 row.skillSignature=signature
 for slot=9,0,-1 do if Pet.GetSkill(row.proxy,slot)>=0 then Pet.DelSkill(row.proxy,slot) end end
 for slot=0,9 do local id=Pet.GetSkill(row.pet,slot)
  if id>=0 then assert(Pet.AddSkill(row.proxy,id)==1,'银行宠物技能同步失败。') end
 end
end
function M:attributes(row)
 if row.growingBank or not self:proxyAlive(row) or not valid(row.pet) then return end
 for _,k in ipairs(ATTR) do set(row.proxy,k,get(row.pet,k)) end
 set(row.proxy,'CHAR_等级',num(row.pet,'CHAR_等级'))
 set(row.proxy,'CHAR_形象',get(row.pet,'CHAR_形象'))
 set(row.proxy,'CHAR_原形',get(row.pet,'CHAR_原形'))
 set(row.proxy,'CHAR_原始图档',get(row.pet,'CHAR_原始图档'))
 if row.bankSlot~=nil then
  set(row.proxy,'CHAR_名字',get(row.pet,'CHAR_名字'))
  set(row.proxy,'宠物_基础忠诚',100);set(row.proxy,'宠物_忠诚',100)
  set(row.proxy,'宠物_技能栏',get(row.pet,'宠物_技能栏'))
  self:copyBankSkills(row)
 end
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
 if update and row.bankSlot==nil then Pet.UpPet(p,row.pet) end
 return true
end
function M:finish(s)
 if not s.battle then return end
 local bankAwarded=false
 for i,row in ipairs(self:actors(s)) do
  local synced=self:sync(s.owner,row,false)
  if synced then
   local earned=not row.dead and math.max(0,row.xp or 0) or 0
   if earned>0 then set(row.pet,'CHAR_经验',math.min(2147483647,num(row.pet,'CHAR_经验')+earned)) end
   row.xp=0;self:updatePet(s.owner,row);self:refresh(row)
   if earned>0 and row.bankSlot~=nil then
    bankAwarded=true;tell(s.owner,'银行宠物'..(row.bankSlot+1)..' '..tostring(get(row.pet,'CHAR_名字'))..' 获得经验：'..earned..'。')
   end
  end
  row.lastTurn=nil;row.command=nil;row.secondCommand=nil;row.reactiveCommand=nil;row.actionCount=nil;row.guardTurn=nil;row.guardTargets=nil;row.executingCommand=nil
 end
 s.damagePending=nil;s.damageHistory=nil;s.enemyActed=nil
 if self.battleOwners[s.battle]==s then self.battleOwners[s.battle]=nil end
 s.battle=nil
 if bankAwarded and valid(s.owner) and not Char.IsDummy(s.owner) then Char.SaveToDb(s.owner) end
end
function M:endOnOwnerDeath(b,s)
 if not s or s.battle~=b or s.endingDeath or not valid(s.owner) or num(s.owner,'CHAR_血')>0 then return false end
 s.endingDeath=true
 -- Exit native entries immediately, but delete dummies on the next tick:
 -- an action callback may still be using the current actor's character.
 for _,row in ipairs(self:actors(s)) do
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
 for _,row in ipairs(s.companions or {}) do
  self.proxies[row.proxy]=nil
  if self:proxyAlive(row) then
   if Char.GetBattleIndex(row.proxy)>=0 then Battle.ExitBattle(row.proxy) end
   Char.DelSlotPet(row.carrier,0)
  end
 end
 for _,row in ipairs(s.rows) do
  self.proxies[row.proxy]=nil
  if self:proxyAlive(row) then
   if Char.GetBattleIndex(row.proxy)>=0 then Battle.ExitBattle(row.proxy) end
   if row.joined then Char.LeaveParty(row.proxy) end
   Char.DelDummy(row.proxy)
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
 local s={owner=p,uid=Char.GetUUID(p),normal=native,rows={},companions={},actors={},bankSignature=self:bankSignature(p)};self.active[p]=s
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
    s.rows[#s.rows+1]=row;s.actors[#s.actors+1]=row;self.proxies[q]=row
    self:refresh(row)
    local bankSlot=#s.rows-1;local bank=Char.GetPoolPet(p,bankSlot)
    if valid(bank) and Char.IsPet(bank) and num(bank,'CHAR_血')>0 then
     local extra=Char.GivePet(q,self:petEnemyId(bank),1)
     assert(valid(extra),'无法创建银行宠物战斗替身。')
     assert(num(extra,'宠物_PETID')==num(bank,'宠物_PETID'),'银行宠物替身种类不一致。')
     local companion={proxy=extra,pet=bank,bankSlot=bankSlot,carrier=q,uuid=petkey(bank),owner=p,xp=0,token=s.uid..':bank:'..petkey(bank)}
     Char.SetTempData(extra,'FivePetProxy_v1',companion.token)
     s.companions[#s.companions+1]=companion;s.actors[#s.actors+1]=companion;self.proxies[extra]=companion
     self:refresh(companion)
     assert(Char.SetPetDepartureState(q,0,2)==1,'无法设置银行宠物替身为战宠。')
    end
   end
  end
  -- Complete every actor before visible party changes. A creation failure
  -- must not produce partial join/leave announcements or their sound effects.
  for _,row in ipairs(s.rows) do
   assert(Char.JoinParty(row.proxy,p,true)==0,'无法加入宠物小队。');row.joined=true
  end
 end)
 if not ok then
  self:disable(p)
  self.autoAttempts[p]={uid=Char.GetUUID(p),signature=self:rosterSignature(p),blocked=true}
  return false,tostring(err):gsub('^.-:%d+:%s*','')..'自动重试已暂停，调整宠物后自动恢复，或输入 /fivepet on 重试。'
 end
 self.autoAttempts[p]=nil
 NLG.UpdateParty(p)
 return true,'宠物小队已开启，共'..(1+#s.actors)..'只宠物参战（银行'..#s.companions..'只）。人物和主宠仍由你操作，其他宠物按AI行动。'
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
  local target=#(s.companions or {})>0 and i or 5+i
  local current=Battle.GetPos(b,r.proxy)
  if current>=0 then
   local result=Battle.SetEntryData(b,r.proxy,CONST.BATTLE_ENTRY_BID,target)
   if result~=0 or Battle.GetPlayer(b,side+target)~=r.proxy then
    error('宠物站位修正失败：'..tostring(result)..'，位置'..Battle.GetPos(b,r.proxy)..'，队列'..Battle.GetPlayer(b,side+target))
   end
  end
 end
 Battle.SetEntryData(b,s.owner,CONST.BATTLE_ENTRY_POSITION,1)
 Battle.SetEntryData(b,s.normal,CONST.BATTLE_ENTRY_POSITION,0)
 for _,r in ipairs(s.rows) do
  Battle.SetEntryData(b,r.proxy,CONST.BATTLE_ENTRY_POSITION,#(s.companions or {})>0 and 1 or 0)
 end
 for _,r in ipairs(s.companions or {}) do
  local target=6+r.bankSlot
  if Battle.GetPos(b,r.proxy)>=0 then
   assert(Battle.SetEntryData(b,r.proxy,CONST.BATTLE_ENTRY_BID,target)==0,'银行宠物战斗位置设置失败。')
   Battle.SetEntryData(b,r.proxy,CONST.BATTLE_ENTRY_POSITION,0)
   assert(Battle.GetPlayer(b,side+target)==r.proxy,'银行宠物战斗位置与查询不一致。')
  end
 end
end
local function elements(p)
 return {num(p,'CHAR_地属性'),num(p,'CHAR_水属性'),num(p,'CHAR_火属性'),num(p,'CHAR_风属性')}
end
function M:target(b,q,a,kind,exclude,live)
 local pos=Battle.GetPos(b,q);local first=pos<10 and 0 or 10
 local ally=kind=='heal' or kind=='revive' or kind=='recover' or kind=='protect'
 local begin=ally and first or (10-first);local list={}
 local owner=kind=='protect' and self.proxies[q] and self.proxies[q].owner
 local elemental=not ally and kind~='combo' and a.target~='random' and a.target~='front'
 local attackElements=elemental and elements(q)
 for n=begin,begin+9 do
  local p=Battle.GetPlayer(b,n)
  if valid(p) and (kind~='protect' or (p~=q and n~=exclude)) then
   local hp=num(p,'CHAR_血');local max=math.max(1,num(p,'CHAR_最大血'))
   if ((kind=='revive' and hp<=0) or (kind~='revive' and hp>0))
    and (kind~='protect' or (hp*2<max and (not live or not self:protected(b,p)))) then
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
function M:meleeReachable(b,q,target)
 local first=Battle.GetPos(b,q)<10 and 10 or 0
 if target<first or target>first+9 then return false end
 local p=Battle.GetPlayer(b,target)
 if not valid(p) or num(p,'CHAR_血')<=0 then return false end
 if Battle.GetEntryData(b,p,CONST.BATTLE_ENTRY_POSITION)==0 then return true end
 for pos=first,first+9 do
  local enemy=Battle.GetPlayer(b,pos)
  if valid(enemy) and num(enemy,'CHAR_血')>0 and Battle.GetEntryData(b,enemy,CONST.BATTLE_ENTRY_POSITION)==0 then return false end
 end
 return true
end
function M:normalCanKill(b,q,target)
 if not self:meleeReachable(b,q,target) then return false end
 local p=Battle.GetPlayer(b,target)
 return num(p,'CHAR_血')<=self:normalDamage(b,q,p)
end
-- Native area magic uses a cross; BID order is center, left, right, far left, far right.
local RECOVERY_AREA={
 [0]={0,1,2,5},[1]={1,0,3,6},[2]={2,0,4,7},[3]={3,1,8},[4]={4,2,9},
 [5]={5,6,7,0},[6]={6,5,8,1},[7]={7,5,9,2},[8]={8,6,3},[9]={9,7,4}
}
function M:protected(b,p)
 local tutor=getModule('petSkillTutor')
 if tutor and tutor.stronglyProtected and tutor:stronglyProtected(b,Battle.GetPos(b,p)) then return true end
 local guardian=Battle.GetEntryData(b,p,CONST.BATTLE_ENTRY_GUARDIAN)
 if guardian==p or not valid(guardian) or num(guardian,'CHAR_血')<=0 or Char.GetBattleIndex(guardian)~=b then return false end
 local actor=self.proxies[guardian]
 -- Native guardian entries survive turn boundaries. Only a guard executed this turn
 -- suppresses another AI guard; last turn must not prevent a fresh first action.
 if actor then return actor.guardTurn==Battle.GetTurn(b) and actor.guardTargets and actor.guardTargets[Battle.GetPos(b,p)] or false end
 local t=self:tech(num(guardian,'CHAR_BattleCom3'))
 return t and t.effect=='protect' and t.command==num(guardian,'CHAR_BattleCom1') and num(guardian,'CHAR_BattleCom2')==Battle.GetPos(b,p) or false
end
function M:affected(b,target,t)
 local first=target<10 and 0 or 10;local list={}
 if t.scope=='all' or t.spread then
  for pos=first,first+9 do list[#list+1]=pos end
 elseif t.scope=='cross' then
  for _,offset in ipairs(RECOVERY_AREA[target-first] or {}) do list[#list+1]=first+offset end
 else list[1]=target end
 return list
end
function M:encodeTarget(target,t)
 if t.scope=='all' then return target<10 and 40 or 41 end
 if t.scope=='cross' then return target+20 end
 return target
end
function M:hasStatus(p,key)
 return CONST[key] and Battle.GetBattleCharacterStatus(p,CONST[key])>0 or false
end
-- Evaluate actual need inside the native area, never only the selected center.
function M:recoveryScore(b,row,t,target)
 local kind=t.effect;local score,benefit=0,0;local power=t.power or {}
 for _,pos in ipairs(self:affected(b,target,t)) do
  local p=Battle.GetPlayer(b,pos)
  if valid(p) then
   local hp=num(p,'CHAR_血');local max=math.max(1,num(p,'CHAR_最大血'));local need
   if kind=='revive' and hp<=0 then
    need=math.max(1,max*0.3);local amount=math.min(need,power.AR or 60)
    score=score+2*amount/need;benefit=benefit+amount
   elseif kind=='heal' and hp>0 and hp*100<max*60 then
    need=math.max(1,max*0.6-hp)
    -- AR is only a relative tier estimate; native calculations still determine healing.
    local amount=math.min(need,(power.AR or 60)*math.max(0.5,num(row.proxy,'CHAR_回复')/100))
    local urgency=hp*100<=max*30 and 2 or 1
    score=score+urgency*amount/need;benefit=benefit+amount
   elseif kind=='cleanse' and hp>0 then
    local count=0;for _,key in pairs(STATUS) do if self:hasStatus(p,key) then count=count+1 end end
    if count>0 then score=score+math.min(100,power.SR or 50)/100;benefit=benefit+count end
   elseif kind=='regen' and hp>0 then
    if not self:hasStatus(p,'战属_恢复回合') then
     score=score+1;benefit=benefit+(power.RR or 10)*(power.CH or 1)
    else score=score-0.25 end
   end
  end
 end
 return score,benefit
end
function M:recoveryTarget(b,row,rule,t)
 local first=Battle.GetPos(b,row.proxy)<10 and 0 or 10;local best
 for _,offset in ipairs({5,0,6,7,1,2,8,9,3,4}) do
  local pos=first+offset;local p=Battle.GetPlayer(b,pos)
  if valid(p) and (p~=row.proxy or t.canSelf) and (t.effect=='revive' or num(p,'CHAR_血')>0) then
   local score,benefit=self:recoveryScore(b,row,t,pos)
   if score>0 and (not best or score>best.score or (score==best.score and benefit>best.benefit)) then
    best={pos=pos,score=score,benefit=benefit}
   end
  end
 end
 return best and best.pos
end
-- No opening/refresh buffs when every remaining enemy is already a safe normal kill.
function M:finishing(b,q)
 local first=Battle.GetPos(b,q)<10 and 10 or 0;local count=0
 for pos=first,first+9 do local p=Battle.GetPlayer(b,pos)
  if valid(p) and num(p,'CHAR_血')>0 then
   count=count+1;if count>1 or not self:normalCanKill(b,q,pos) then return false end
  end
 end
 return count==1
end
function M:automaticSupport(b,row,skills,options)
 local q=row.proxy;options=options or {};local mp=options.mp or num(q,'CHAR_魔')
 if self:hasStatus(q,'战属_忘') then return nil end
 -- Guarding a vulnerable ally takes precedence over every recovery skill.
 local guards,strong,ordinary={},{},{}
 for _,t in ipairs(skills) do if t.effect=='protect' then
  if strongGuard(t.id) then strong[#strong+1]=t else ordinary[#ordinary+1]=t end
 end end
 table.sort(strong,function(a,c) return strongGuard(a.id).level>strongGuard(c.id).level end)
 for _,t in ipairs(strong) do guards[#guards+1]=t end
 for _,t in ipairs(ordinary) do guards[#guards+1]=t end
 for _,t in ipairs(guards) do
  if not options.skipGuard and t.cost<=mp then
   local pos=self:target(b,q,{target='weak'},'protect',options.exclude,options.live)
   if pos then return {t.command,pos,t.id} end
  end
 end
 for _,kind in ipairs({'revive','heal','cleanse','regen'}) do
  local best
  for _,t in ipairs(skills) do
   if t.category=='support' and t.effect==kind and t.cost<=mp and (kind~='regen' or not self:finishing(b,q)) then
    local pos=self:recoveryTarget(b,row,{kind=kind},t)
    if pos then
     local score,benefit=self:recoveryScore(b,row,t,pos)
     -- Favor stabilization and useful coverage; equivalent results favor cheaper casts.
     score=score/(1+t.cost*0.002)
     if score>0 and (not best or score>best.score or (score==best.score and benefit>best.benefit)) then
      best={tech=t,pos=pos,score=score,benefit=benefit}
     end
    end
   end
  end
  if best then return {best.tech.command,self:encodeTarget(best.pos,best.tech),best.tech.id} end
 end
 return self:automaticBarrier(b,row,skills,mp)
end
function M:safeTarget(p,magic)
 local keys=magic and {'战属_魔反','战属_魔吸','战属_魔无'} or {'战属_攻反','战属_攻吸','战属_攻无'}
 for _,key in ipairs(keys) do if self:hasStatus(p,key) then return false end end
 return true
end
-- Barriers are useful only against a matching threat, on vulnerable living allies.
function M:automaticBarrier(b,row,skills,mp)
 local q=row.proxy;if self:finishing(b,q) then return nil end
 local threshold=self:petProfile(row.pet).barrierThreshold
 local first=Battle.GetPos(b,q)<10 and 0 or 10;local threats={physical=0,magic=0}
 for pos=10-first,19-first do local p=Battle.GetPlayer(b,pos)
  if valid(p) and num(p,'CHAR_血')>0 then
   local attack=self:tech(num(p,'CHAR_BattleCom3'))
   if attack and attack.command~=num(p,'CHAR_BattleCom1') then attack=nil end
   local kind=attack and attack.category or 'physical'
   if threats[kind] and (not attack or attack.effect~='control') then threats[kind]=threats[kind]+1 end
  end
 end
 local best
 for _,t in ipairs(skills) do if t.effect=='barrier' and t.cost<=mp and threats[t.barrier]>0 then
  for pos=first,first+9 do local p=Battle.GetPlayer(b,pos)
   if valid(p) and num(p,'CHAR_血')>0 and num(p,'CHAR_血')<num(p,'CHAR_最大血')*threshold
    and (p~=q or t.canSelf) then
    local score=0
    for _,target in ipairs(self:affected(b,pos,t)) do local ally=Battle.GetPlayer(b,target)
     if valid(ally) and num(ally,'CHAR_血')>0 and self:safeTarget(ally,t.barrier=='magic') then
      local ratio=num(ally,'CHAR_血')/math.max(1,num(ally,'CHAR_最大血'))
      if ratio<threshold then score=score+(1-ratio)*threats[t.barrier] end
     end
    end
    score=score/(1+t.cost*0.01)
    if score>0 and (not best or score>best.score) then best={tech=t,pos=pos,score=score} end
   end
  end
 end end
 if best then return {best.tech.command,self:encodeTarget(best.pos,best.tech),best.tech.id} end
end
function M:hitChance(b,q,p,t)
 local risk=math.max(0,num(p,'CHAR_闪躲')-num(q,'CHAR_命中'))
 if num(p,'CHAR_BattleCom1')==CONST.BATTLE_COM.BATTLE_COM_P_DODGE then
  local dodge=self:tech(num(p,'CHAR_BattleCom3'))
  risk=risk+math.max(0,dodge and dodge.power.AV or 0)
 end
 return math.max(0.05,math.min(0.95,0.9-risk/100+(t.power.HR or 0)/100))
end
function M:magicDamage(q,p,t)
 -- Relative estimates for planning; native code remains the effect authority.
 local spirit=math.max(0.5,math.min(1.5,math.sqrt(math.max(1,num(q,'CHAR_精神'))/math.max(1,num(p,'CHAR_精神')))))
 local prop={0,0,0,0};if t.element then prop[t.element]=100 end
 local element=t.element and Battle.CalcPropScore(prop,elements(p),1) or 1
 return math.max(1,(t.power.AR or 60)*spirit+math.max(0,num(q,'CHAR_魔攻')-num(p,'CHAR_魔抗'))*0.2)*element
end
function M:attackScore(b,row,t,pos,blockers,damageOnly)
 local q=row.proxy;local power=t.power or {};local magic=t.category=='magic'
 local score,count=0,0;local targets=self:affected(b,pos,t);local randomCount=0
 if t.spread=='random' then
  for _,target in ipairs(targets) do local enemy=Battle.GetPlayer(b,target)
   if valid(enemy) and num(enemy,'CHAR_血')>0 and (t.ranged or self:meleeReachable(b,q,target)) then randomCount=randomCount+1 end
  end
 end
 blockers=blockers or self:bossBlockers(b,row.owner)
 for _,target in ipairs(targets) do
  local p=Battle.GetPlayer(b,target)
  if valid(p) and num(p,'CHAR_血')>0 and (t.ranged or self:meleeReachable(b,q,target)) then
   if blockers[target] then return nil end
   -- A reflected splash is unsafe even if other enemies would take damage.
   if not self:safeTarget(p,magic) then return nil end
   local hp=num(p,'CHAR_血');local amount=magic and self:magicDamage(q,p,t) or math.max(1,self:normalDamage(b,q,p))
   local chance=magic and 1 or self:hitChance(b,q,p,t)
   if t.defensePenalty and num(q,'CHAR_血')*2<num(q,'CHAR_最大血') then return nil end
   if (power.HR or 0)<0 and chance<0.65 then return nil end
   if not magic then amount=amount*math.max(0.1,t.damageFactor)*(t.repeatHits and t.minHits or 1) end
   if randomCount>0 then amount=amount*t.minHits/randomCount end
   local utility=0
   if t.effect=='guard_break' then
    if num(p,'CHAR_BattleCom1')~=CONST.BATTLE_COM.BATTLE_COM_GUARD then return nil end;amount=amount*2
   elseif t.effect=='drain_mp' then
    if num(p,'CHAR_魔')<=0 then return nil end
    utility=math.min(num(p,'CHAR_魔'),amount*(power.FR or 5)/100);amount=amount*0.5
   elseif t.effect=='drain_hp' then
    utility=math.min(math.max(0,num(q,'CHAR_最大血')-num(q,'CHAR_血')),amount*(power.AR or 50)/100)
   elseif t.effect=='status' or t.effect=='control' then
    if not t.statusKey then return nil end
    if not self:hasStatus(p,t.statusKey) then
     local resistance=math.max(0,math.min(100,num(p,t.resistKey)))
     local probability=math.min(100,power.SR or 30)/100*(1-resistance/100)
     -- Control matters when an enemy will survive this turn's ordinary attack.
     utility=math.min(hp,math.max(amount,num(p,'CHAR_攻击力')))*probability
    end
    if t.effect=='control' then amount=0 end
    if utility==0 then return nil end
   elseif t.effect=='death' then
    if Battle.IsBossBattle(b)==1 then return nil end;amount=hp*math.min(20,power.SR or 10)/100
   end
   if damageOnly then utility=0 end
   local damage=math.min(hp,amount)
   -- Capping at HP avoids overkill; reliable finishing receives a small bonus.
   score=score+(damage+utility)*chance+(t.spread~='random' and amount>=hp and chance>=0.85 and damage*(1.15-chance) or 0);count=count+1
  end
 end
 if count==0 then return nil end
 return score
end
-- Same-target normal attacks are the native entry to a combo. Treat coordination
-- as a bounded benefit, never as a reason to override support or target safety.
function M:comboBenefit(b,row,pos,normal,blockers)
 local q=row.proxy;local target=Battle.GetPlayer(b,pos)
 if Battle.IsBossBattle(b)~=1 or not valid(target) or num(target,'对象_ENEMY_BossFlg')<=0
  or blockers[pos] or not self:meleeReachable(b,q,pos) or not self:safeTarget(target,false)
  or self:hasStatus(target,'战属_睡') or self:hitChance(b,q,target,normal)<0.75 then return 0 end
 local own=self:normalDamage(b,q,target);local hp=num(target,'CHAR_血')
 if own<=0 or hp<=own then return 0 end
 local first=Battle.GetPos(b,q)<10 and 0 or 10;local partners,total=0,0
 for n=first,first+9 do local ally=Battle.GetPlayer(b,n)
  local actor=self.proxies[ally]
  local ready=valid(ally) and (actor and actor.commandBattle==b and actor.lastTurn==Battle.GetTurn(b)
   or (not actor and Battle.IsWaitingCommand(ally)~=1))
  if valid(ally) and ally~=q and num(ally,'CHAR_血')>0 and ready
   and self:meleeReachable(b,ally,pos)
   and num(ally,'CHAR_BattleCom1')==CONST.BATTLE_COM.BATTLE_COM_ATTACK
   and num(ally,'CHAR_BattleCom2')==pos and self:hitChance(b,ally,target,normal)>=0.75 then
   partners=partners+1;total=total+self:normalDamage(b,ally,target)
  end
 end
 if partners==0 or total>=hp then return 0 end
 local bonus=math.min(0.15,partners*0.05)
 if total+own>=hp then bonus=bonus+0.1 end
 return math.min(own,hp-total)*bonus
end
function M:automaticAttack(b,row,skills)
 local q=row.proxy;local guard={CONST.BATTLE_COM.BATTLE_COM_GUARD,Battle.GetPos(b,q),7400}
 local mp=num(q,'CHAR_魔');local reserve
 for _,t in ipairs(skills) do
  if t.effect=='heal' or t.effect=='revive' then
   reserve=math.min(reserve or t.cost,t.cost)
  end
 end
 local best;local first=Battle.GetPos(b,q)<10 and 10 or 0
 local blockers=self:bossBlockers(b,row.owner)
 -- A free normal hit competes with every learned skill, using the same scoring.
 local normal=self:tech(7300)
 for pos=first,first+9 do local p=Battle.GetPlayer(b,pos)
  if valid(p) and num(p,'CHAR_血')>0 and self:meleeReachable(b,q,pos) then
   local score=self:attackScore(b,row,normal,pos,blockers,true)
   if score then score=score+self:comboBenefit(b,row,pos,normal,blockers) end
   if score and score>0 and (not best or score>best.score) then best={tech=normal,pos=pos,score=score} end
  end
 end
 if not self:hasStatus(q,'战属_忘') then
  for _,t in ipairs(skills) do
   if (t.category=='physical' or t.category=='magic') and t.canEnemy and t.cost+(reserve or 0)<=mp then
    for pos=first,first+9 do
     local p=Battle.GetPlayer(b,pos)
     if valid(p) and num(p,'CHAR_血')>0 and (t.ranged or self:meleeReachable(b,q,pos)) then
      local score=self:attackScore(b,row,t,pos,blockers,true)
      if score then
       if not best or score>best.score or (score==best.score and t.cost<best.tech.cost) then best={tech=t,pos=pos,score=score} end
      end
     end
    end
   end
  end
 end
 if best then return {best.tech.command,self:encodeTarget(best.pos,best.tech),best.tech.id} end
 return guard
end
function M:choose(b,row,live)
 local q=row.proxy;local guard={CONST.BATTLE_COM.BATTLE_COM_GUARD,Battle.GetPos(b,q),7400}
 if row.dead or num(q,'CHAR_血')<=0 or self:ai(row.owner,row.pet).mode=='guard' then return guard end
 local skills=self:skills(row.pet)
 local attack=self:automaticAttack(b,row,skills)
 return self:survivalPlan(b,row,skills,attack)
end
function M:command(b,row)
 local q=row.proxy;if not self:proxyAlive(row) or Battle.IsWaitingCommand(q)~=1 then return end
 local turn=Battle.GetTurn(b)
 if row.lastTurn==turn and row.commandBattle==b then return end
 self:attributes(row)
 local cmd=self:choose(b,row);row.command=cmd;row.reactiveCommand=cmd;row.lastTurn=turn;row.commandBattle=b;row.actionCount=0;row.guardTargets={};row.guardTurn=nil
 if row.bankSlot~=nil then
  assert(Battle.ActionSelect(q,cmd[1],cmd[2],cmd[3])==0,'银行宠物自动指令失败。')
  return
 end
 set(q,'CHAR_BattleCom1',cmd[1]);set(q,'CHAR_BattleCom2',cmd[2]);set(q,'CHAR_BattleCom3',cmd[3])
 -- Each dummy represents one carried pet: guard and defense also act once.
 row.secondCommand=nil
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
    or (s.bankSignature and s.bankSignature~=self:bankSignature(p))
   for _,r in ipairs(self:actors(s)) do if not self:owned(p,r) or not self:proxyAlive(r) then broken=true end end
   if broken then self:disable(p,'宠物或主战宠已改变，当前五宠小队已暂停。')
   elseif b>=0 then
    if Battle.GetType(b)==CONST.战斗_PVP then self:disable(p,'五宠模式仅用于单人普通战斗，当前小队已暂停。')
    else
     self:formation(b,s)
     s.battle=b
     if not self:endOnOwnerDeath(b,s) then
      for _,r in ipairs(self:actors(s)) do self:command(b,r) end
     end
    end
   else
    self:finish(s)
    for _,r in ipairs(self:actors(s)) do
     if Char.GetBattleIndex(r.proxy)>=0 then Battle.ExitBattle(r.proxy) end
    end
    local members={};for n=0,4 do local q=Char.GetPartyMember(p,n);if valid(q) then members[q]=true end end
    local invalidParty=false;local deadPet=false
    for q in pairs(members) do if q~=p and not self.proxies[q] then invalidParty=true end end
    for _,r in ipairs(s.rows) do if not members[r.proxy] then invalidParty=true end end
    for _,r in ipairs(self:actors(s)) do if num(r.pet,'CHAR_血')<=0 then deadPet=true end end
    local missingBank=false;local bankRows={}
    for _,r in ipairs(s.companions or {}) do bankRows[r.bankSlot]=r end
    for i in ipairs(s.rows) do local pet=Char.GetPoolPet(p,i-1)
     if valid(pet) and Char.IsPet(pet) and num(pet,'CHAR_血')>0 and not bankRows[i-1] then missingBank=true end
    end
    if invalidParty or deadPet or missingBank then self:disable(p,missingBank and '银行宠物已恢复，正在重新组建宠物小队。' or (deadPet and '有宠物倒下，恢复后将自动重启五宠模式。' or '队伍已改变，当前五宠小队已暂停。'))
    else
     -- Native party movement carries the companions, including map transitions.
     -- Warping a member also warps the leader and reloads the connected client's map.
     for _,r in ipairs(self:actors(s)) do self:refresh(r) end
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
function M:show(p,kind,options,pet,page,title,ruleKind)
 if not self:near(p) then return end
 local allOptions,pageCount
 if #options>8 then
  allOptions=options;pageCount=math.ceil((#allOptions-1)/6)
  page=math.max(1,math.min(page or 1,pageCount));options={}
  for i=(page-1)*6+1,math.min(page*6,#allOptions-1) do options[#options+1]=allOptions[i] end
  options[#options+1]={label='下一页 '..page..'/'..pageCount,action='menuPage'}
  options[#options+1]=allOptions[#allOptions]
 end
 self.seq=self.seq+1;local seq=7500+self.seq%20000
 self.menus[p]={kind=kind,pet=pet,uuid=pet and petkey(pet),page=page or 1,seq=seq,expires=os.time()+60,options=options,allOptions=allOptions,pageCount=pageCount,title=title,ruleKind=ruleKind}
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
 for slot=0,3 do local pet=Char.GetPoolPet(p,slot)
  if valid(pet) and Char.IsPet(pet) then
   local a=self:ai(p,pet)
   ops[#ops+1]={label='银行'..(slot+1)..' '..tostring(get(pet,'CHAR_名字'))..'：'..MODES[a.mode],action='pet',pet=pet}
  end
 end
 ops[#ops+1]={label='使用说明',action='help'}
 self:show(p,'main',ops)
end
local AUTO_HELP='智能战斗按存活与伤害收益选行动：用当前生命、敌方已学技能效果和可达范围、最近两回合按实际扣血记录的伤害，保守估算本回合及下一回合结束生命。预计本回合会倒下时优先保命；能撑过两回合时优先降低敌方生命，不因固定血量比例或站位强制补血、防御。危险时比较补血、匹配物理或法术威胁的护盾、护卫、明镜止水和防御，考虑耗魔、有效范围、行动先后及护卫转移后的伤害，避免让会倒下的宠物护卫别人。能可靠先手收尾并消除威胁时仍可进攻。敌人倒下、停止攻击、换招或无法命中时重新判断，回合内已行动的敌人不重复计入剩余攻击。普通防御后的物理掉血还原为未防御估计，避免误判威胁消失；战斗结束清空记录。预测是估算，暴击、闪躲和行动先后仍按原生引擎计算。Boss 遮挡只用于保护安全目标，不强制前排防御：玩家在后排且两边前排遮挡后排近战Boss时，保留敌方挡路宠物，攻击避开会波及它们的十字、全体和随机技能；能安全进攻的前排或后排自动宠物都可用单体远程攻击Boss，预计生命危险时才比较防护行动。Boss能用远程绕过遮挡、挡路宠物倒下或阵型改变后立即重新判断。人物和主宠始终手动操作，Boss战也不接管主宠；AI只控制其他随身宠物和银行伙伴。显式全程防御设置保留。自动随身替身每回合只行动一次，银行伙伴遵守原生宠物行动规则；技能必须已学且魔力可支付，不自动使用金钱攻击或破坏装备。'
function M:petMenu(p,pet)
 if not self:hasPet(p,pet) then return end
 local a=self:ai(p,pet)
 self:show(p,'pet',{{label='智能战斗（自动使用已学技能）',mode='attack'},
  {label='全程防御',mode='guard'},{label='查看自动释放逻辑',action='autoInfo'},
  {label='返回',action='back'}},pet,nil,tostring(get(pet,'CHAR_名字'))..' AI／'..MODES[a.mode]..'／'..self:petProfile(pet).label)
end
function M:answer(npc,p,seq,button,line)
 local s=self.menus[p];self.menus[p]=nil
 if not s or npc~=self.npc or seq~=s.seq or s.expires<os.time() or not self:near(p) then return end
 if tonumber(button)==2 then return end
 if tonumber(button)~=0 and tonumber(button)~=1 then return end
 local choice=tonumber(line);if not choice or choice~=math.floor(choice) then return end
 local o=s.options[choice];if not o then return end
 if s.pet and (not self:hasPet(p,s.pet) or petkey(s.pet)~=s.uuid) then return end
 if o.action=='menuPage' and s.allOptions then
  self:show(p,s.kind,s.allOptions,s.pet,s.page%s.pageCount+1,s.title,s.ruleKind);return
 end
 if s.kind=='main' then
  if o.action=='toggle' then
   if self:enabled(p) then self:setEnabled(p,false)
   elseif self:setEnabled(p,true) then local ok,msg=self:enable(p);tell(p,msg) end
   self:menu(p)
  elseif o.action=='pet' then self:petMenu(p,o.pet)
  elseif o.action=='help' then
   tell(p,'宠物小队默认开启；随身5只加银行前4栏最多9只参战，人物和主宠始终手动操作，Boss战也不接管主宠，其他最多8只自动。每只非主宠随身宠物的替身携带对应银行栏的存活宠物；不足时按实际数量。银行原宠保留，战斗消耗、受伤和经验同步回原宠；银行阵容变化后自动重建。'..AUTO_HELP..'有银行伙伴时主宠和银行伙伴前排，人物和随身宠物替身后排；没有银行伙伴时沿用五宠前排。/heal 同时治疗银行前4栏。仅限单人普通战斗，输入 /fivepet off 关闭。');self:menu(p)
  end
 elseif s.kind=='pet' then
  if o.action=='back' then self:menu(p)
  elseif o.action=='autoInfo' then
   local profile=self:petProfile(s.pet)
   tell(p,'当前成长倾向：'..profile.label..'，体/力/强/敏/魔：'..table.concat(profile.ranks,'/')..'。'..AUTO_HELP);self:petMenu(p,s.pet)
  elseif o.mode=='attack' or o.mode=='guard' then
   if self:saveAI(p,s.pet,{mode=o.mode}) then tell(p,'宠物行动模式已保存。') end
   self:petMenu(p,s.pet)
  end
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
 -- Native bodyguard pays before the action hook; other skills pay afterward.
 self:regCallback('CalcFpConsumeEvent',function(p,id,fp)
  local r=self.proxies[p];local t=r and self:tech(id)
  if t then return t.cost end
  return fp
 end)
 self:regCallback('DamageCalculateEvent',OrderedCallback(function(a,d,ori,damage,b,command,target,id)
  self:watchDamage(b,a,d,damage,command,id);return damage
 end,-1000000))
 -- Recheck live HP, statuses, guardians and MP before each native action.
 self:regCallback('BattleBeforeActionEvent',function(b,q)
  local row=self.proxies[q]
  if row and row.commandBattle==b and self:proxyAlive(row) then
   row.actionCount=(row.actionCount or 0)+1
   -- Native may visit an empty second slot after restoring a reactive stance.
   -- Keep that visit empty; the after-action hook preserves guard/defense effects.
   if row.bankSlot==nil and row.actionCount>1 then return 0 end
   local original=self:tech(num(q,'CHAR_BattleCom3'))
   if original and original.prepaid and num(q,'CHAR_BattleCom1')==original.command then set(q,'CHAR_魔',num(q,'CHAR_魔')+original.cost) end
   local cmd=self:choose(b,row,true);row.command=cmd;row.reactiveCommand=cmd
   local selected=self:tech(cmd[3])
   if selected and selected.prepaid and selected.cost>0 then
    set(q,'CHAR_魔',math.max(0,num(q,'CHAR_魔')-selected.cost))
   end
   row.executingCommand=cmd
   set(q,'CHAR_BattleCom1',cmd[1]);set(q,'CHAR_BattleCom2',cmd[2]);set(q,'CHAR_BattleCom3',cmd[3])
   local t=self:tech(cmd[3])
   if cmd[1]==CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD
    or (row.command[1]~=CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD
     and (cmd[1]==CONST.BATTLE_COM.BATTLE_COM_GUARD or (t and t.stance))) then row.reactiveCommand=cmd end
  end
  return 0
 end)
 self:regCallback('BattleAfterActionEvent',function(b,q)
  self:settleDamage(b)
  local squad=self.battleOwners[b]
  if squad and valid(q) and Battle.GetPos(b,q)>=0 and (Battle.GetPos(b,q)<10)~=(Battle.GetPos(b,squad.owner)<10) then
   squad.enemyActed=squad.enemyActed or {};squad.enemyActed[q]=Battle.GetTurn(b)
  end
  if squad and (squad.endingDeath or self:endOnOwnerDeath(b,squad)) then return 0 end
  local row=self.proxies[q];local cmd=row and row.reactiveCommand
  local action=row and row.executingCommand
  if action and action[1]==CONST.BATTLE_COM.BATTLE_COM_P_BODYGUARD and row.commandBattle==b then
   local target=Battle.GetPlayer(b,action[2])
   if valid(target) and Battle.GetEntryData(b,target,CONST.BATTLE_ENTRY_GUARDIAN)==q then
    row.guardTurn=Battle.GetTurn(b);row.guardTargets=row.guardTargets or {};row.guardTargets[action[2]]=true
   end
  end
  if row then row.executingCommand=nil end
  if cmd and row.commandBattle==b and self:proxyAlive(row) then
   local tech=self:tech(cmd[3])
   if cmd[1]==CONST.BATTLE_COM.BATTLE_COM_GUARD or (tech and tech.stance) then
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
  local r=self.proxies[p];local b=Char.GetBattleIndex(p)
  local battleXP=b>=0 and Battle.GetType(b)~=CONST.战斗_PVP
  if r then
   r.xp=(r.xp or 0)+(battleXP and self:petExperience(r.owner,xp) or math.max(0,xp));return 0
  end
  -- Main pets use the same passive once; items and player rewards are unchanged.
  if battleXP and Char.IsPet(p) then
   local owner=Pet.GetOwner(p)
   if valid(owner) and Char.IsPlayer(owner) and not self.proxies[owner] then return self:petExperience(owner,xp) end
  end
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
  self:settleDamage(b)
  for p,s in pairs(self.active) do if s.battle==b then
   s.enemyActed=nil
   self:formation(b,s)
   for _,r in ipairs(self:actors(s)) do self:sync(p,r,true) end
  end end
 end)
 self:regCallback('ResetCharaBattleStateEvent',function(q)
  local r=self.proxies[q];if r then self:sync(r.owner,r,false) end
 end)
 self:regCallback('BeforeCharaSaveEvent',function(p)
  local s=self.active[p];if s and s.battle then for _,r in ipairs(self:actors(s)) do self:sync(p,r,false) end end
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
   else s.battle=b;for _,r in ipairs(self:actors(s)) do self:refresh(r);r.lastTurn=nil end end
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
