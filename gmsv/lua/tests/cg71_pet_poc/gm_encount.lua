-- On-demand GM encounter helper. No startup registration or DATA changes.
-- /dolua lua/tests/cg71_pet_poc/gm_encount.lua here : normal encounter at the current position.
-- /dolua lua/tests/cg71_pet_poc/gm_encount.lua poc  : one level-1 POC enemy (enemy ID 30000).
local function notify(player, message)
  print('[GM_ENCOUNT] ' .. message)
  if type(player) == 'number' and player >= 0 then
    NLG.SystemMessage(player, '[GM_ENCOUNT] ' .. message)
  end
end

return function(player, args)
  args = args or {}
  local ok, result = pcall(function()
    assert(type(player) == 'number' and player >= 0, 'A logged-in player is required.')
    local admin = getModule('admin')
    assert(admin and admin:isAdmin(player), 'Administrator permission required.')
    local mode = args[1] or 'here'
    assert(mode == 'here' or mode == 'poc', 'Usage: /dolua lua/tests/cg71_pet_poc/gm_encount.lua here|poc')
    local current = Char.GetData(player, 442)
    assert(type(current) == 'number' and current == 0, 'Already in battle or battle state is unavailable.')
    local battle
    if mode == 'here' then
      battle = Battle.Encount(player, player)
    else
      local enemy = Data.EnemyGetDataIndex(30000)
      assert(type(enemy) == 'number' and enemy >= 0, 'Enemy 30000 is not loaded; restart the server.')
      battle = Battle.PVE(player, player, nil, {30000}, {1}, {0})
    end
    assert(type(battle) == 'number' and battle >= 0,
      'Encounter failed (' .. tostring(battle) .. '). For here mode, move to a normal encounter area or use poc mode.')
    notify(player, 'STARTED mode=' .. mode .. ' battle=' .. battle)
    return battle
  end)
  if not ok then
    notify(player, 'FAILED ' .. tostring(result))
    return false
  end
  return result
end
