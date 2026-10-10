-- One-pet CG7.1 POC. Loaded only by the existing administrator /dolua command.
-- Supplied pet fields: image=4, base=5, PETID=72. EnemyBaseId=61 is not the pet identity.
local APPEARANCE, SPECIES = 104866, 30000
local PET_ID_FIELD = 72
local BACKUP_KEY = 'CG71PocOriginalAppearance'
-- Species 30000 is retained as a permanent custom pet.
local PERMANENT_NAME = '\210\236\189\231\202\222'

local function notify(player, message)
  print('[CG71_POC] ' .. message)
  if type(player) == 'number' and player >= 0 then
    NLG.SystemMessage(player, '[CG71_POC] ' .. message)
  end
end

local function checkDefinitions()
  local enemy = Data.EnemyGetDataIndex(SPECIES)
  local base = Data.EnemyBaseGetDataIndex(SPECIES)
  assert(type(enemy) == 'number' and enemy >= 0, 'Enemy 30000 is not loaded; restart the server.')
  assert(type(base) == 'number' and base >= 0, 'EnemyBase 30000 is not loaded; restart the server.')
  assert(Data.EnemyGetData(enemy, 1) == SPECIES, 'Enemy-to-base mapping differs from 30000.')
  assert(Data.EnemyBaseGetData(base, 29) == APPEARANCE, 'Base appearance differs from 104866.')
  return enemy, base
end

local function getPet(player, value)
  local slot = tonumber(value)
  assert(slot and slot == math.floor(slot) and slot >= 0 and slot <= 4, 'Pet slot must be 0..4.')
  local pet = Char.GetPet(player, slot)
  assert(type(pet) == 'number' and pet >= 0, 'Selected pet slot is empty.')
  return pet, slot
end

local function refresh(player, pet)
  Pet.UpPet(player, pet)
  NLG.UpChar(player)
end

local function applyImages(pet, image, base)
  local oldImage, oldBase = Char.GetData(pet, 4), Char.GetData(pet, 5)
  if Char.SetData(pet, 4, image) ~= 1 or Char.SetData(pet, 5, base) ~= 1 then
    Char.SetData(pet, 4, oldImage)
    Char.SetData(pet, 5, oldBase)
    error('Appearance update failed; original appearance restored.')
  end
end

return function(player, args)
  args = args or {}
  local action = args[1] or 'check'
  if action == 'check' then
    local enemy, base = checkDefinitions()
    notify(player, 'DEFINITIONS_OK enemy=30000 base=30000 image=104866 indexes=' .. enemy .. ',' .. base)
    return true
  end
  assert(type(player) == 'number' and player >= 0, 'A logged-in test player is required.')
  local admin = getModule('admin')
  assert(admin and admin:isAdmin(player), 'Administrator permission required.')

  local ok, result = pcall(function()
    if action == 'activate' then
      local enemy, base = checkDefinitions()
      local oldEnemy = Data.EnemyGetData(enemy, 4000)
      local oldBase = Data.EnemyBaseGetData(base, 4000)
      local applied, why = pcall(function()
        assert(Data.EnemyBaseSetData(base, 4000, PERMANENT_NAME) == 0, 'Base name update failed.')
        assert(Data.EnemySetData(enemy, 4000, PERMANENT_NAME) == 0, 'Enemy name update failed.')
        assert(Data.EnemyBaseGetData(base, 4000) == PERMANENT_NAME
          and Data.EnemyGetData(enemy, 4000) == PERMANENT_NAME, 'Runtime name verification failed.')
      end)
      if not applied then
        Data.EnemyBaseSetData(base, 4000, oldBase)
        Data.EnemySetData(enemy, 4000, oldEnemy)
        error(why)
      end
      notify(player, 'ACTIVATED species=30000 image=104866; new pets use the permanent name.')
      return true
    elseif action == 'grant' then
      checkDefinitions()
      local free = false
      for slot = 0, 4 do
        local pet = Char.GetPet(player, slot)
        if pet < 0 then free = true
        elseif Char.GetData(pet, PET_ID_FIELD) == SPECIES then
          notify(player, 'Existing POC pet is in slot ' .. slot .. '; use status instead of creating another.')
          return pet
        end
      end
      assert(free, 'All five pet slots are occupied.')
      local pet = Char.GivePet(player, SPECIES, 1)
      assert(type(pet) == 'number' and pet >= 0, 'Char.GivePet failed: ' .. tostring(pet))
      refresh(player, pet)
      local base, image, original = Char.GetData(pet, PET_ID_FIELD), Char.GetData(pet, 4), Char.GetData(pet, 5)
      assert(base == SPECIES and image == APPEARANCE and original == APPEARANCE,
        'Created pet fields differ; inspect status before continuing. pet=' .. pet .. ' petId=' .. base .. ' image=' .. image .. ' baseImage=' .. original)
      notify(player, 'GRANT_OK pet=' .. pet .. ' petId=30000 image=104866 baseImage=104866; rendering is still to be checked.')
      return pet
    elseif action == 'swap' then
      local pet, slot = getPet(player, args[2])
      assert(Char.GetData(pet, PET_ID_FIELD) ~= SPECIES, 'Use swap on a disposable donor pet, not the new POC species.')
      assert(Char.GetExtData(pet, BACKUP_KEY) == nil, 'A saved appearance already exists; restore first.')
      local saved = tostring(Char.GetData(pet, 4)) .. '|' .. tostring(Char.GetData(pet, 5))
      Char.SetExtData(pet, BACKUP_KEY, saved)
      assert(Char.GetExtData(pet, BACKUP_KEY) == saved, 'Cannot persist original appearance; pet not changed.')
      applyImages(pet, APPEARANCE, APPEARANCE)
      refresh(player, pet)
      notify(player, 'SWAP_OK slot=' .. slot .. ' image=104866; restore is available even after relogin.')
      return pet
    elseif action == 'restore' then
      local pet, slot = getPet(player, args[2])
      local saved = Char.GetExtData(pet, BACKUP_KEY)
      assert(type(saved) == 'string', 'No original appearance is saved for this pet.')
      local image, base = saved:match('^(%d+)|(%d+)$')
      assert(image and base, 'Saved appearance is invalid; pet not changed.')
      applyImages(pet, tonumber(image), tonumber(base))
      Char.SetExtData(pet, BACKUP_KEY, nil)
      refresh(player, pet)
      notify(player, 'RESTORE_OK slot=' .. slot .. ' image=' .. image .. ' baseImage=' .. base)
      return pet
    elseif action == 'remove' then
      error('Species 30000 is permanent. Test cleanup cannot delete it.')
    elseif action == 'list' then
      for slot = 0, 4 do
        local pet = Char.GetPet(player, slot)
        if pet >= 0 then
          notify(player, 'SLOT=' .. slot .. ' petId=' .. tostring(Char.GetData(pet, PET_ID_FIELD))
            .. ' image=' .. tostring(Char.GetData(pet, 4)) .. ' baseImage=' .. tostring(Char.GetData(pet, 5)))
        else
          notify(player, 'SLOT=' .. slot .. ' empty')
        end
      end
      return true
    elseif action == 'status' then
      local pet, slot = getPet(player, args[2])
      notify(player, 'STATUS slot=' .. slot .. ' pet=' .. pet .. ' petId=' .. tostring(Char.GetData(pet, PET_ID_FIELD))
        .. ' image=' .. tostring(Char.GetData(pet, 4)) .. ' baseImage=' .. tostring(Char.GetData(pet, 5))
        .. ' saved=' .. tostring(Char.GetExtData(pet, BACKUP_KEY)))
      return pet
    end
    error('Use check, activate, swap <slot>, restore <slot>, grant, list, or status <slot>.')
  end)
  if not ok then notify(player, 'FAILED ' .. tostring(result)); return false end
  return result
end
