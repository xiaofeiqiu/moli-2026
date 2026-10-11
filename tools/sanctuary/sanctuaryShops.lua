-- Native, sell-only merchants; transactions remain in the engine.
local M=ModuleBase:createModule('sanctuaryShops')
local D=dofile('lua/Modules/sanctuaryData.lua')
local petItems={}
for family=0,4 do
 for _,rank in ipairs({1,5,10,15}) do petItems[#petItems+1]=700000+family*15+rank-1 end
end
local potions={}
for id=15606,15615 do potions[#potions+1]=id end
local food={}
for id=15200,15219 do food[#food+1]=id end
M.catalog={
 {name='宠物装备商人',image=14058,items=petItems},
 {name='血瓶商人',image=14089,items=potions},
 {name='料理商人',image=14032,items=food},
 {name='属性水晶商人',image=14058,items={9201,9202,9203,9204,9209,9218,9227,9236},
  prices={1000,1000,1000,1000,400,400,400,400}},
}
function M:onLoad()
 self.shops={}
 for _,shop in ipairs(self.catalog) do
  assert(#shop.items<=20,'Native shop capacity exceeded')
  for index,id in ipairs(shop.items) do
   assert(Data.ItemsetGetIndex(id)>=0,'Missing sanctuary shop item '..id)
   local item=Item.MakeItem(id)
   assert(item>=0,'Cannot create sanctuary shop item '..id)
   local price=shop.prices and shop.prices[index] or Item.GetData(item,CONST['道具_价格'])
   Item.UnlinkItem(item)
   assert(price>0,'Sanctuary shop item must have a positive price: '..id)
  end
  local npc=self:NPC_createShop(shop.name,shop.image,assert(D.positions[shop.name]),
   {buyRate=100,sellRate=20,shopType=CONST.SHOP_TYPE_SELL,sellTypes={}},shop.items)
  assert(npc>=0,'Cannot create '..shop.name)
  if shop.prices then
   -- Itemshop2 opens through the same native path as the other working merchants.
   -- Native purchase pricing reads these stock instances, not DATA templates.
   for index,id in ipairs(shop.items) do
    local stock=Char.GetItemIndex(npc,index-1)
    assert(stock>=0 and Item.GetData(stock,CONST['道具_ID'])==id,'Missing native crystal stock '..id)
    Item.SetData(stock,CONST['道具_价格'],shop.prices[index])
    assert(Item.GetData(stock,CONST['道具_价格'])==shop.prices[index],'Cannot price native crystal stock '..id)
   end
  end
  self.shops[#self.shops+1]={npc=npc,name=shop.name,items=shop.items,prices=shop.prices}
 end
 self:logInfo('Loaded '..#self.shops..' sanctuary merchants')
end
return M
