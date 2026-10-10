-- On-demand batch tools; no registration and no pet deletion action.
local pets = dofile('lua/tests/cg71_pet_poc/cg71_pet_batch_manifest.lua')
local byId = {}
for _, pet in ipairs(pets) do byId[pet.id] = pet end
local function notify(player, text)
  print('[CG71_BATCH] ' .. text)
  if type(player) == 'number' and player >= 0 then NLG.SystemMessage(player, '[CG71_BATCH] ' .. text) end
end
local function verify(pet)
  local e,b = Data.EnemyGetDataIndex(pet.id),Data.EnemyBaseGetDataIndex(pet.id)
  assert(e >= 0 and b >= 0, 'Species ' .. pet.id .. ' is not loaded; restart this server.')
  assert(Data.EnemyGetData(e,1)==pet.id and Data.EnemyBaseGetData(b,29)==pet.image, 'ID/image mismatch: ' .. pet.id)
  assert(Data.EnemyGetData(e,4000)==pet.name and Data.EnemyBaseGetData(b,4000)==pet.name, 'Name mismatch: ' .. pet.id)
  return e,b
end
return function(player,args)
  args=args or {}
  local action=args[1] or 'check'
  local ok,result=pcall(function()
    assert(type(player)=='number' and player>=0,'A logged-in GM is required.')
    local admin=getModule('admin')
    assert(admin and admin:isAdmin(player),'Administrator permission required.')
    if action=='check' then
      for _,pet in ipairs(pets) do verify(pet) end
      notify(player,'ALL_OK count=' .. #pets .. ' ids=' .. pets[1].id .. '..' .. pets[#pets].id)
      return true
    elseif action=='list' then
      local page=tonumber(args[2]) or 1
      assert(page==math.floor(page) and page>=1 and page<=math.ceil(#pets/10),'Invalid page.')
      for i=(page-1)*10+1,math.min(page*10,#pets) do
        local pet=pets[i];notify(player,'ID=' .. pet.id .. ' image=' .. pet.image .. ' name=' .. pet.name)
      end
      return true
    elseif action=='grant' or action=='battle' then
      local pet=byId[tonumber(args[2])]
      assert(pet,'Specify a species ID from this batch.')
      verify(pet)
      if action=='battle' then
        assert(Char.GetData(player,442)==0,'Already in battle.')
        local battle=Battle.PVE(player,player,nil,{pet.id},{1},{0})
        assert(type(battle)=='number' and battle>=0,'Battle creation failed.')
        notify(player,'BATTLE_OK id=' .. pet.id .. ' battle=' .. battle)
        return battle
      end
      local free=false
      for slot=0,4 do
        local p=Char.GetPet(player,slot)
        if p<0 then free=true
        elseif Char.GetData(p,72)==pet.id then notify(player,'Already owned in SLOT=' .. slot);return p end
      end
      assert(free,'All pet slots are occupied.')
      local p=Char.GivePet(player,pet.id,1)
      assert(type(p)=='number' and p>=0,'Pet creation failed.')
      assert(Char.GetData(p,72)==pet.id and Char.GetData(p,4)==pet.image and Char.GetData(p,5)==pet.image,'Created pet fields differ.')
      Pet.UpPet(player,p);NLG.UpChar(player)
      notify(player,'GRANT_OK id=' .. pet.id .. ' image=' .. pet.image)
      return p
    end
    error('Use check, list <page>, grant <species>, or battle <species>.')
  end)
  if not ok then notify(player,'FAILED ' .. tostring(result));return false end
  return result
end
