-- Native shops for character-level bands; hybrid items keep normal item types.
local M = ModuleBase:createModule('knightHybridGear')
local D = dofile('lua/Modules/knightHybridGearData.lua')
local items = {}
for _, item in ipairs(D.items) do items[item.id] = item end

function M:canEquip(player, itemIndex)
  local item = items[Item.GetData(itemIndex, CONST['道具_ID'])]
  if not item then return 0 end
  local job = Char.GetData(player, CONST['CHAR_职业'])
  if not ((job >= 11 and job <= 17) or (job >= 31 and job <= 37) or (job >= 181 and job <= 187)) then
    NLG.SystemMessage(player, '这套装备需要剑士、骑士或魔剑士职业。')
    return -1
  end
  if Char.GetData(player, CONST['CHAR_等级']) < item.min_level then
    NLG.SystemMessage(player, '这件装备需要人物 '..item.min_level..' 级。')
    return -1
  end
  return 0
end

local function empty(x, y)
  local count = Obj.GetObject(0, 1000, x, y)
  return Map.IsWalkable(0, 1000, x, y) == 1 and count == 0
end

function M:findPositions()
  -- Follow the road's map-X direction, two tiles apart on one side of it.
  -- Move the whole row together if obstructed, preserving the level order.
  local offsets={{x=0,y=0}}
  for radius=1,3 do
    for dy=-radius,radius do for dx=-radius,radius do
      if math.max(math.abs(dx),math.abs(dy))==radius then
        offsets[#offsets+1]={x=dx,y=dy}
      end
    end end
  end
  local half=#D.shops-1
  for _,offset in ipairs(offsets) do
    for _,side in ipairs({1,-1}) do
      local positions={}
      for n=1,#D.shops do
        local x=153-half+(n-1)*2+offset.x
        local y=136+offset.y
        local approach={x=x,y=y+side}
        if not empty(x,y) or not empty(approach.x,approach.y) then break end
        positions[#positions+1]={x=x,y=y,approach=approach}
      end
      if #positions==#D.shops then
        local clear=true
        for x=positions[1].x,positions[#positions].x do
          if not empty(x,positions[1].y+side) then clear=false;break end
        end
        if clear then return positions end
      end
    end
  end
  error('No unobstructed roadside shop row near 153,139')
end

function M:onLoad()
  self.shops={}
  local positions=self:findPositions()
  for n,shop in ipairs(D.shops) do
    for _,id in ipairs(shop.items) do
      assert(Data.ItemsetGetIndex(id)>=0,'Missing hybrid item '..id)
    end
    local p=positions[n]
    local npc=self:NPC_createShop(shop.name,14058,
      {mapType=0,map=1000,x=p.x,y=p.y,direction=4},
      {buyRate=100,sellRate=20,shopType=CONST.SHOP_TYPE_SELL,sellTypes={}},shop.items)
    assert(npc>=0,'Could not create '..shop.name)
    -- Placement may be redirected to the sanctuary by NPCPart.
    p={x=Char.GetData(npc,CONST.CHAR_X),y=Char.GetData(npc,CONST.CHAR_Y)}
    p.approach={x=p.x,y=p.y+1}
    self.shops[#self.shops+1]={npc=npc,name=shop.name,min_level=shop.min_level,
      max_level=shop.max_level,x=p.x,y=p.y,approach=p.approach,items=shop.items}
  end
  self:regCallback('ItemAttachEvent',Func.bind(self.canEquip,self))
  self:logInfo('Loaded '..#self.shops..' equipment shops in sanctuary placement')
end

return M
