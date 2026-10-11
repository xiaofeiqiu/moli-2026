---@class Fight:ModuleType
local Fight = ModuleBase:createModule('fight')

-- Trigger one normal encounter using the player's current map and position.
function Fight:handleTalk(charIndex, msg)
  if type(msg) ~= 'string' then
    return 1
  end
  local command, args = msg:match('^/([%w]+)(.*)$')
  if not command or command:lower() ~= 'fight' then
    return 1
  end
  if args~='' and not args:match('^%s') then return 1 end
  args=args:match('^%s*(.-)%s*$')
  local count=args~='' and args:match('^%d+$') and tonumber(args) or nil
  if args~='' and (not count or count<1 or count>10) then
    NLG.SystemMessage(charIndex, '用法：/fight [1~10]，不带数字按地图正常遇敌，例如 /fight 10。')
    return 0
  end

  local battleMode = Char.GetData(charIndex, CONST.CHAR_BattleMode)
  if battleMode ~= 0 or Char.GetBattleIndex(charIndex) ~= -1 then
    NLG.SystemMessage(charIndex, '当前正在战斗，无法再次遇敌。')
    return 0
  end
  if Char.GetData(charIndex, CONST['CHAR_血']) <= 0 then
    NLG.SystemMessage(charIndex, '请先恢复生命后再遇敌。')
    return 0
  end
  if Char.PartyNum(charIndex) > 0 and Char.GetPartyMember(charIndex, 0) ~= charIndex then
    NLG.SystemMessage(charIndex, '组队时请由队长输入 /fight。')
    return 0
  end

  self.encounterCounts[charIndex]=count
  local ok, battleIndex = pcall(Battle.Encount, charIndex, charIndex)
  self.encounterCounts[charIndex]=nil
  if not ok or type(battleIndex) ~= 'number' or battleIndex < 0 then
    -- This engine can leave a stale battle index after a failed encounter.
    if Char.GetData(charIndex, CONST.CHAR_BattleMode) == 0 then
      Char.SetData(charIndex, CONST.CHAR_BattleIndex, -1)
    end
    if not ok then
      self:logError('fight encounter failed: ' .. tostring(battleIndex))
      NLG.SystemMessage(charIndex, '遇敌失败，请稍后重试。')
    else
      NLG.SystemMessage(charIndex, '当前位置无法遇敌，请到野外或可遇敌区域使用 /fight。')
    end
  end
  return 0
end

-- Resize only this synchronous command encounter. Reuse native monster IDs.
function Fight:enemyList(charIndex,groupId,enemyNum,enemies)
  local count=self.encounterCounts[charIndex]
  if not count or type(enemies)~='table' or #enemies==0 then return enemies end
  local selected={}
  for _,id in ipairs(enemies) do
    if type(id)=='number' and id>=0 then selected[#selected+1]=id end
  end
  if #selected==0 then return enemies end
  local result={}
  for i=1,10 do result[i]=i<=count and selected[(i-1)%#selected+1] or -1 end
  return result
end

function Fight:onLoad()
  self.encounterCounts={}
  self:regCallback('VSEnemyCreateEvent',Func.bind(self.enemyList,self))
  self:regCallback('TalkEvent', Func.bind(self.handleTalk, self))
  self:logInfo('load')
end

return Fight
