-- Character preference; the party leader chooses the next PvE battle's tier.
local M=ModuleBase:createModule('gameDifficulty')
local KEY='GameDifficultyV1'
local DEFAULT=6
local TIERS={
 {name='正常',hp=1,damage=1,defense=1,agility=1},
 {name='困难',hp=1.30,damage=1.20,defense=1.15,agility=1.10},
 {name='极难',hp=1.80,damage=1.50,defense=1.30,agility=1.15},
 {name='地狱',hp=2.50,damage=2,defense=1.50,agility=1.20},
 {name='炼狱',hp=4,damage=3,defense=2,agility=1.30},
 {name='深渊',hp=6,damage=4,defense=4,agility=1.50},
}
M.tiers=TIERS
local function get(p,k) local field=assert(CONST[k],k);return Char.GetData(p,field) end
local function set(p,k,v) local field=assert(CONST[k],k);return Char.SetData(p,field,v) end
local function valid(p) return type(p)=='number' and p>=0 and Char.IsValidCharIndex(p) and Char.IsPlayer(p) end
local function identity(p) return tostring(get(p,'CHAR_账号') or ''),tonumber(get(p,'对象_RegistNumber')) or 0 end
local function tierId(n) n=tonumber(n);return n and n==math.floor(n) and TIERS[n] and n or nil end
local function round(n) return math.floor(n+0.5) end
local function describe(n)
 local t=TIERS[n]
 return string.format('%d %s：怪物生命 ×%g，伤害 ×%g，防御 ×%g，敏捷 ×%g。',n,t.name,t.hp,t.damage,t.defense,t.agility)
end

function M:preference(p)
 local account,reg=identity(p);local id=account..':'..reg
 local cached=self.configs[p];if cached and cached.identity==id then return cached.tier end
 local raw=Char.GetExtData(p,KEY)
 if account~='' then
  local result=SQL.QueryEx('SELECT val FROM hook_charaext WHERE cdKey=? AND regNo=? AND sKey=?',account,reg,KEY)
  if result.status~=0 then self:logError('Difficulty preference read failed');return nil end
  raw=result.rows and result.rows[1] and result.rows[1].val or nil
 end
 local tier=DEFAULT
 if raw then local ok,saved=pcall(JSON.decode,raw)
  if ok and type(saved)=='table' and saved.version==1 then tier=tierId(saved.tier) or DEFAULT end
 end
 self.configs[p]={identity=id,tier=tier};return tier
end

function M:savePreference(p,tier)
 tier=tierId(tier);if not tier then return false end
 local account,reg=identity(p);local raw=JSON.encode({version=1,tier=tier})
 if account~='' then
  local result=SQL.QueryEx('REPLACE INTO hook_charaext(cdKey,regNo,sKey,val,valType) VALUES(?,?,?,?,?)',account,reg,KEY,raw,0)
  if result.status~=0 or result.effectRows<1 then return false end
 end
 Char.SetExtData(p,KEY,raw);self.configs[p]={identity=account..':'..reg,tier=tier};return true
end

function M:leader(p)
 if Char.PartyNum(p)>0 then local leader=Char.GetPartyMember(p,0);if valid(leader) then return leader end end
 return p
end

function M:talk(p,msg)
 if type(msg)~='string' then return 1 end
 local command,args=msg:match('^/([^%s]+)(.*)$')
 if not command or (command:lower()~='difficulty' and command~='难度') then return 1 end
 if not valid(p) then return 0 end
 args=args:match('^%s*(.-)%s*$')
 if args=='' or args:lower()=='help' then
  local mine=self:preference(p)
  if not mine then NLG.SystemMessage(p,'难度设置暂时无法读取，请稍后重试。');return 0 end
  local leader=self:leader(p);local effective=self:preference(leader) or DEFAULT
  local state=self.battles[Char.GetBattleIndex(p)]
  local current=state and state.tier or effective
  NLG.SystemMessage(p,'当前难度：'..current..' '..TIERS[current].name..'（'..(state and '本场战斗' or '下场 PvE')..'）。')
  NLG.SystemMessage(p,'个人难度：'..mine..' '..TIERS[mine].name..'。'..(leader~=p and '组队跟随队长：'..effective..' '..TIERS[effective].name..'。' or ''))
  NLG.SystemMessage(p,'用法：/difficulty 1～6；1 正常，2 困难，3 极难，4 地狱，5 炼狱，6 深渊（默认、最难）。')
  for n in ipairs(TIERS) do NLG.SystemMessage(p,describe(n)) end
  return 0
 end
 local selected=args:match('^[1-6]$') and tonumber(args)
 if not selected then NLG.SystemMessage(p,'请输入 /difficulty 1～6；1 正常，6 深渊（默认、最难）。');return 0 end
 if get(p,'CHAR_BattleMode')~=0 or Char.GetBattleIndex(p)>=0 then
  NLG.SystemMessage(p,'请结束当前战斗后再切换难度。');return 0
 end
 if not self:savePreference(p,selected) then NLG.SystemMessage(p,'难度保存失败，原设置保留，请稍后重试。');return 0 end
 NLG.SystemMessage(p,'个人难度已设为【'..selected..' '..TIERS[selected].name..'】，从下一场战斗生效。')
 NLG.SystemMessage(p,describe(selected))
 if self:leader(p)~=p then NLG.SystemMessage(p,'组队时跟随队长难度；离队后使用你的个人设置。') end
 return 0
end

function M:scaleEnemy(b,q)
 local state=self.battles[b]
 if not state or type(q)~='number' or q<0 or not Char.IsValidCharIndex(q) or not Char.IsEnemy(q) then return end
 local pos=Battle.GetPos(b,q);if pos<10 or pos>19 or state.enemies[q] then return end
 local t=TIERS[state.tier]
 local base={hp=get(q,'CHAR_最大血'),defense=get(q,'CHAR_防御力'),agility=get(q,'CHAR_敏捷')}
 state.enemies[q]=base
 set(q,'CHAR_最大血',math.max(1,round(base.hp*t.hp)))
 set(q,'CHAR_血',math.max(0,math.min(get(q,'CHAR_最大血'),round(get(q,'CHAR_血')*t.hp))))
 set(q,'CHAR_防御力',round(base.defense*t.defense));set(q,'CHAR_敏捷',round(base.agility*t.agility))
 base.lastHP=get(q,'CHAR_血')
end

-- The native engine recalculates enemy attributes between turns. Reapply to
-- fresh native values, preserving health already lost during this battle.
function M:recalculate(q)
 if not Char.IsEnemy(q) then return end
 local b=Char.GetBattleIndex(q);local state=self.battles[b];local old=state and state.enemies[q]
 if not old or Battle.GetPos(b,q)<10 then return end
 local t=TIERS[state.tier];local hp=get(q,'CHAR_血')
 local base={hp=get(q,'CHAR_最大血'),defense=get(q,'CHAR_防御力'),agility=get(q,'CHAR_敏捷')}
 if hp==base.hp and old.lastHP and old.lastHP>base.hp then hp=old.lastHP end
 state.enemies[q]=base
 set(q,'CHAR_最大血',math.max(1,round(base.hp*t.hp)))
 set(q,'CHAR_血',math.max(0,math.min(get(q,'CHAR_最大血'),hp)))
 set(q,'CHAR_防御力',round(base.defense*t.defense));set(q,'CHAR_敏捷',round(base.agility*t.agility))
 base.lastHP=get(q,'CHAR_血')
end

function M:scan(b)
 if not self.battles[b] then self:start(b);return end
 for pos=10,19 do self:scaleEnemy(b,Battle.GetPlayer(b,pos)) end
end

function M:start(b)
 if self.battles[b] then return end
 if Battle.GetType(b)==CONST['战斗_PVP'] then return end
 local owner
 for pos=0,9 do local p=Battle.GetPlayer(b,pos);if valid(p) then owner=self:leader(p);break end end
 if not owner then return end
 self.battles[b]={leader=owner,tier=self:preference(owner) or DEFAULT,enemies={}}
 self:scan(b)
end

function M:damage(a,d,ori,damage,b)
 if not self.battles[b] then self:start(b) end
 local state=self.battles[b]
 local target=state and state.enemies[d]
 if target and damage>0 then target.lastHP=math.max(0,get(d,'CHAR_血')-damage) end
 if state and damage>0 and Char.IsEnemy(a) and Battle.GetPos(b,a)>=10 then
  return math.max(1,round(damage*TIERS[state.tier].damage))
 end
 return damage
end

function M:seal(p,q,result)
 local state=self.battles[Char.GetBattleIndex(p)];local base=state and state.enemies[q]
 if result>0 and base then
  local hp=get(q,'CHAR_血')/TIERS[state.tier].hp
  set(q,'CHAR_最大血',base.hp);set(q,'CHAR_血',math.max(0,math.min(base.hp,round(hp))))
  set(q,'CHAR_防御力',base.defense);set(q,'CHAR_敏捷',base.agility)
  state.enemies[q]=nil
 end
 return result
end

function M:onLoad()
 self.configs={}
 _G.GameDifficultyBattlesV1=_G.GameDifficultyBattlesV1 or {};self.battles=_G.GameDifficultyBattlesV1
 self:regCallback('TalkEvent',Func.bind(self.talk,self))
 self:regCallback('BattleStartEvent',Func.bind(self.start,self))
 self:regCallback('DamageCalculateEvent',OrderedCallback(Func.bind(self.damage,self),-20))
 self:regCallback('SealEvent',Func.bind(self.seal,self))
 self:regCallback('AfterCalcCharaStatusEvent',OrderedCallback(Func.bind(self.recalculate,self),-20))
 self:regCallback('AfterBattleTurnEvent',function(b)
  local state=self.battles[b];if not state then return end
  for q,base in pairs(state.enemies) do if Char.IsValidCharIndex(q) and Char.IsEnemy(q) then base.lastHP=get(q,'CHAR_血') end end
 end)
 self:regCallback('BeforeBattleTurnStartEvent',Func.bind(self.scan,self))
 self:regCallback('BeforeBattleTurnEvent',function(b) self:scan(b);return false end)
 self:regCallback('BattleSummonedEnemyEvent',function(b,a,q)
  local state=self.battles[b];if state then state.enemies[q]=nil;self:scaleEnemy(b,q) end
 end)
 self:regCallback('BattleNextEnemyInitEvent',function(b)
  local state=self.battles[b];if state then state.enemies={};self:scan(b) end
 end)
 self:regCallback('BattleOverEvent',function(b) self.battles[b]=nil end)
 self:regCallback('BattleExitEvent',function(p,b)
  local remains=false
  for pos=0,9 do local q=Battle.GetPlayer(b,pos)
   if q~=p and valid(q) and Char.GetBattleIndex(q)==b then remains=true;break end
  end
  if not remains then self.battles[b]=nil end
 end)
 for _,event in ipairs({'LoginEvent','LogoutEvent'}) do self:regCallback(event,function(p) self.configs[p]=nil end) end
 self:logInfo('Six difficulty tiers ready; default is abyss (tier 6); no NPC added')
end

function M:onUnload() self.configs={} end
return M
