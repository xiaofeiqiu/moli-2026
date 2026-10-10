-- Native loading, randomized item attributes, actual equipment moves and shop placement.
local M=getModule('knightHybridGear')
local D=dofile('lua/Modules/knightHybridGearData.lua')
local T=ModuleBase:createModule('knightHybridGearProbe')
local OUT='__OUTPUT__/native_result.json'
local R={status='RUNNING',checks={},shops={},items={},moves={},client_verified=false,itemset_sha256='__ITEMSET_SHA256__'}
local owner=-1
local function write()
  local f=assert(io.open(OUT,'w'));f:write(JSON.encode(R));f:close()
end
local function check(ok,label)
  R.checks[#R.checks+1]={name=label,pass=ok and true or false}
  assert(ok,label)
end
local function get(p,k) return Char.GetData(p,CONST[k]) end
local function set(p,k,v) return Char.SetData(p,CONST[k],v) end
local stats={['31']='道具_攻击',['33']='道具_防御',['35']='道具_敏捷',
  ['37']='道具_精神',['39']='道具_回复',['41']='道具_必杀',['43']='道具_反击',
  ['45']='道具_命中',['47']='道具_闪躲',['49']='道具_HP',['51']='道具_MP',
  ['91']='道具_魔抗',['99']='道具_魔攻'}
local slots={[2]=CONST['EQUIP_左手'],[7]=CONST['EQUIP_右手'],
  [8]=CONST['EQUIP_头'],[10]=CONST['EQUIP_身'],[13]=CONST['EQUIP_腿']}
for typ,slot in pairs(slots) do assert(type(slot)=='number','Missing equipment slot for type '..typ) end
local made={}
local oldMessage=NLG.SystemMessage
NLG.SystemMessage=function(p,message,...)
  R.messages=R.messages or {};R.messages[#R.messages+1]=message
  return oldMessage(p,message,...)
end
local ok,err=xpcall(function()
  check(M~=nil and #M.shops==#D.shops,'all native shopkeepers loaded')
  check(getModule('skillLibrary')~=nil and getModule('fivePet')~=nil and getModule('fight')~=nil,
    'existing gameplay modules loaded together')
  for _,shop in ipairs(M.shops) do
    check(shop.npc>=0,'shop NPC '..shop.name)
    check(Map.IsWalkable(0,1000,shop.x,shop.y)==1,'shop tile walkable '..shop.name)
    check(Map.IsWalkable(0,1000,shop.approach.x,shop.approach.y)==1,'shop approach walkable '..shop.name)
    check(#shop.items<=20,'shop stays within native 20-item capacity '..shop.name)
    check(get(shop.npc,'CHAR_名字')==shop.name,'shop name round-trip '..shop.name)
    R.shops[#R.shops+1]=shop
  end
  owner=Char.CreateDummy({mapType=0,floor=1000,x=153,y=140,image=100002,name='KNIGHT_HYBRID_PROBE'})
  check(owner>=0,'isolated player created')
  set(owner,'CHAR_职业',37);set(owner,'CHAR_职类ID',30);set(owner,'CHAR_职阶',6)
  set(owner,'CHAR_等级',200);set(owner,'CHAR_体力',10000);set(owner,'CHAR_魔法',10000)
  NLG.UpChar(owner)
  R.diagnostics={job=get(owner,'CHAR_职业'),level=get(owner,'CHAR_等级'),
    is_player=Char.IsPlayer(owner),is_dummy=Char.IsDummy(owner),left=slots[2],right=slots[7]}
  for _,spec in ipairs(D.items) do
    check(Data.ItemsetGetIndex(spec.id)>=0,'item definition '..spec.id)
    for attempt=1,3 do
      local item=Item.MakeItem(spec.id);check(item>=0,'item can be created '..spec.id)
      made[#made+1]=item
      check(Item.GetData(item,CONST['道具_ID'])==spec.id,'item ID '..spec.id)
      check(Item.GetData(item,CONST['道具_类型'])==spec.type,'item type '..spec.id)
      check(Item.GetData(item,CONST['道具_等级'])==spec.native_rank,'native item rank '..spec.id)
      check(Item.GetData(item,CONST['道具_名字'])==spec.name,'GBK name '..spec.id)
      check(Item.GetData(item,CONST['道具_价格'])==spec.price,'native shop price '..spec.id)
      check(Item.GetData(item,CONST['道具_耐久'])==300,'new equipment durability '..spec.id)
      check(Item.GetData(item,CONST['道具_已鉴定'])==1,'shop equipment ready to wear '..spec.id)
      for column,constant in pairs(stats) do
        local limits=spec.native_pairs[column]
        local value=Item.GetData(item,CONST[constant])
        check(value>=limits[1] and value<=limits[2],constant..' native range '..spec.id..' got '..tostring(value))
      end
      check(M:canEquip(owner,item)==0,'eligible knight can equip '..spec.id)
      if spec.min_level>1 then
        set(owner,'CHAR_等级',spec.min_level-1)
        check(M:canEquip(owner,item)<0,'character level gate '..spec.id)
        set(owner,'CHAR_等级',200)
      end
      set(owner,'CHAR_职业',77)
      check(M:canEquip(owner,item)<0,'other profession gate '..spec.id)
      set(owner,'CHAR_职业',37)
      Item.UnlinkItem(item);made[#made]=nil
    end
  end
  for _,tier in ipairs({1,2,10,11,20}) do
    local band={}
    for _,spec in ipairs(D.items) do if spec.min_level==(tier-1)*10+1 then band[#band+1]=spec end end
    if #band>0 then
      for _,spec in ipairs(band) do
        local item=Char.GiveItem(owner,spec.id,1,false)
        check(item>=0,'give equipment '..spec.id)
        local bag=Char.GetItemSlot(owner,item)
        check(bag>=8,'equipment starts in bag '..spec.id)
        local moved=Char.MoveItem(owner,bag,slots[spec.type],1)
        R.moves[#R.moves+1]={id=spec.id,result=moved,bag=bag,slot=slots[spec.type],
          expected=item,actual=Char.GetItemIndex(owner,slots[spec.type]),bag_after=Char.GetItemIndex(owner,bag)}
        check(Char.GetItemIndex(owner,slots[spec.type])==item,
          'native equipment move '..spec.id..' result '..tostring(moved))
      end
      NLG.UpChar(owner)
      check(get(owner,'CHAR_魔攻')>0,'equipped spear adds actual character magic attack tier '..tier)
      R.items[#R.items+1]={tier=tier,magic_attack=get(owner,'CHAR_魔攻'),spirit=get(owner,'CHAR_精神'),defense=get(owner,'CHAR_防御力')}
      for _,slot in pairs(slots) do Char.DelItemBySlot(owner,slot) end
    end
  end
  -- A failed equip must leave the item in the bag, rather than merely hiding a menu.
  local spec=D.items[#D.items]
  if spec then
    local item=Char.GiveItem(owner,spec.id,1,false);check(item>=0,'gated equipment generated')
    local bag=Char.GetItemSlot(owner,item);set(owner,'CHAR_等级',spec.min_level-1)
    Char.MoveItem(owner,bag,slots[spec.type],1)
    check(Char.GetItemIndex(owner,bag)==item,'native equip hook rejects low-level character')
    set(owner,'CHAR_等级',200);Char.DelItemBySlot(owner,bag)
  end
  Char.DelDummy(owner);owner=-1
  R.status='PASS'
end,debug.traceback)
NLG.SystemMessage=oldMessage
if not ok then
  R.status='FAIL';R.error=tostring(err)
  for _,item in ipairs(made) do pcall(Item.UnlinkItem,item) end
  if owner>=0 then pcall(Char.DelDummy,owner) end
end
write()
