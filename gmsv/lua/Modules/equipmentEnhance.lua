-- Native item fields retain base stats and pity across saves and item transfers.
local M=ModuleBase:createModule('equipmentEnhance')
local STONES=dofile('lua/Modules/gameQoLData.lua').stoneIds
M.rules=dofile('lua/Modules/equipmentEnhanceData.lua')
local STATS={'道具_攻击','道具_防御','道具_敏捷','道具_精神','道具_回复','道具_生命','道具_魔力','道具_魔攻'}
local PREFIX='EQ13v1:'
local KEY='EquipmentEnhanceV1'
local function data(i,k) return Item.GetData(i,CONST[k]) end
local function say(p,s) NLG.SystemMessage(p,s) end
local function integer(v) return v and v==math.floor(v) end
function M:state(i)
 local raw=tostring(Item.GetExtData(i,KEY) or '')
 local state={level=0,failures=0,base={}}
 if raw=='' then
  if tostring(data(i,'道具_名字')):match('%+%d+$') then return nil,'已有强化标记，请先由管理员确认兼容性。' end
  for n,key in ipairs(STATS) do state.base[n]=data(i,key) end
  return state
 end
 if raw:sub(1,#PREFIX)~=PREFIX then return nil,'强化数据异常，魔石未消耗。' end
 local values={}
 local body=raw:sub(#PREFIX+1)
 for v in body:gmatch('[^,]+') do
  local n=tonumber(v);if not integer(n) then return nil,'强化数据异常，魔石未消耗。' end
  values[#values+1]=n
 end
 if #values~=10 or body~=table.concat(values,',') then return nil,'强化数据异常，魔石未消耗。' end
 state.level,state.failures=values[1],values[2]
 if state.level<0 or state.level>self.rules.maxLevel or state.failures<0 or state.failures>self.rules.pityFailures then
  return nil,'强化数据异常，魔石未消耗。'
 end
 for n=1,#STATS do state.base[n]=values[n+2] end
 return state
end
function M:level(i)
 local s=self:state(i);return s and s.level or nil
end
function M:encode(s)
 local values={s.level,s.failures}
 for _,v in ipairs(s.base) do values[#values+1]=v end
 return PREFIX..table.concat(values,',')
end
function M:stat(base,level)
 if base<=0 then return base end
 return math.floor(base*(100+self.rules.bonusPercent*level)/100)
end
function M:roll() return math.random(1,100) end
function M:outcome(s)
 local target=s.level+1
 local pity=s.failures>=self.rules.pityFailures
 local success=pity or self:roll()<=self.rules.successRates[target]
 local nextState={level=s.level,failures=s.failures,base=s.base}
 if success then nextState.level=target;nextState.failures=0
 else
  nextState.failures=math.min(self.rules.pityFailures,s.failures+1)
  local chance=self.rules.downgradeRates[target]
  if chance>0 and self:roll()<=chance then nextState.level=math.max(0,s.level-1) end
 end
 return nextState,success,pity
end
function M:overlap(p,stone,equip)
 if stone<0 or equip<0 or stone==equip or not STONES[data(stone,'道具_ID')] then return 0 end
 local typ=data(equip,'道具_类型')
 if not ((typ>=0 and typ<=14) or (typ>=56 and typ<=60)) then return 0 end
 -- Block the native swap/merge on every enhancement gesture.
 if not Char.IsValidCharIndex(p) or not Char.IsPlayer(p) then return 1 end
 local source,target=Char.GetItemSlot(p,stone),Char.GetItemSlot(p,equip)
 if source<8 or target<8 or Char.GetItemIndex(p,source)~=stone or Char.GetItemIndex(p,target)~=equip then return 1 end
 local qol=getModule('gameQoL')
 if Char.GetData(p,CONST.CHAR_BattleMode)~=0 or Char.GetBattleIndex(p)~=-1 or (qol and not qol:ready(p,true)) then
  say(p,'战斗或摆摊期间不能强化装备。');return 1
 end
 if data(equip,'道具_已鉴定')~=1 or data(equip,'道具_耐久')<=0 then
  say(p,'请先鉴定并修理装备再强化。');return 1
 end
 local state,err=self:state(equip)
 if not state then say(p,err);return 1 end
 if state.level>=self.rules.maxLevel then say(p,'装备已达到强化上限 +13，魔石未消耗。');return 1 end
 local nextState,success,pity=self:outcome(state)
 local oldName=data(equip,'道具_名字')
 local name=oldName:gsub('%+%d+$','')
 if nextState.level>0 then name=name..'+'..nextState.level end
 local oldState=Item.GetExtData(equip,KEY)
 local changes={{key='道具_名字',old=oldName,new=name}}
 for n,key in ipairs(STATS) do
  -- Retain adjustments from gems/other systems made since the previous attempt.
  local old=data(equip,key)
  local new=old+self:stat(state.base[n],nextState.level)-self:stat(state.base[n],state.level)
  changes[#changes+1]={key=key,old=old,new=new}
 end
 local function rollback()
  for _,c in ipairs(changes) do Item.SetData(equip,CONST[c.key],c.old) end
  Item.SetExtData(equip,KEY,oldState or '')
  Item.UpItem(p,target)
 end
 -- Read back all fields before spending material; native limits can truncate.
 for _,c in ipairs(changes) do
  Item.SetData(equip,CONST[c.key],c.new)
  if data(equip,c.key)~=c.new then rollback();say(p,'强化保存失败，魔石未消耗。');return 1 end
 end
 local encoded=self:encode(nextState)
 Item.SetExtData(equip,KEY,encoded)
 if Item.GetExtData(equip,KEY)~=encoded then rollback();say(p,'强化保存失败，魔石未消耗。');return 1 end
 local count=data(stone,'道具_堆叠数')
 if count>1 then
  Item.SetData(stone,CONST['道具_堆叠数'],count-1)
  if data(stone,'道具_堆叠数')~=count-1 then rollback();return 1 end
  Item.UpItem(p,source)
 elseif Item.Kill(p,stone,source)~=1 then
  rollback();say(p,'魔石扣除失败，强化已取消。');return 1
 end
 Item.UpItem(p,target)
 if success then say(p,(pity and '失败保护触发，强化成功：' or '强化成功：')..name..'（消耗1颗魔石）。')
 else
  local result=nextState.level<state.level and ('降至 +'..nextState.level) or ('保持 +'..nextState.level)
  local protection=nextState.failures>=self.rules.pityFailures and '下次强化必定成功。'
   or ('连续失败 '..nextState.failures..'/'..self.rules.pityFailures..' 次。')
  say(p,'强化失败，'..result..'（消耗1颗魔石）；'..protection)
 end
 return 1
end
function M:onLoad()
 self:regCallback('ItemOverLapEvent',OrderedCallback(Func.bind(self.overlap,self),100))
end
return M
