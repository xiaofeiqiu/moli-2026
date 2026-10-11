-- Run only in an isolated server with a dummy character; no player DB access.
local M=getModule('knightHybridGear')
local D=dofile('lua/Modules/knightHybridGearData.lua')
local R={status='RUNNING',checks=0,moves=0,rank_rejections=0,jobs=7,items=#D.items}
local owner=-1
local slots={[0]=CONST['EQUIP_左手'],[7]=CONST['EQUIP_右手'],
  [8]=CONST['EQUIP_头'],[10]=CONST['EQUIP_身'],[13]=CONST['EQUIP_腿']}
local function check(ok,label)
  assert(ok,label);R.checks=R.checks+1
end
local function set(k,v) Char.SetData(owner,CONST[k],v) end
local ok,err=xpcall(function()
  check(M~=nil and #M.shops==10,'all ten shops loaded')
  local sold={}
  for _,shop in ipairs(M.shops) do
    for _,id in ipairs(shop.items) do sold[id]=true end
  end
  owner=Char.CreateDummy({mapType=0,floor=60003,x=24,y=36,image=100002,name='MAGIC_GEAR_PROBE'})
  check(owner>=0,'isolated dummy created')
  set('CHAR_等级',200);set('CHAR_体力',10000);set('CHAR_魔法',10000)
  for job=181,187 do
    set('CHAR_职业',job);set('CHAR_职类ID',180);set('CHAR_职阶',job-181)
    for _,spec in ipairs(D.items) do
      check(sold[spec.id],'shop sells '..spec.id)
      local item=Char.GiveItem(owner,spec.id,1,false)
      check(item>=0,'create '..spec.id)
      local bag=Char.GetItemSlot(owner,item)
      check(M:canEquip(owner,item)==0,'magic job gate '..job..'/'..spec.id)
      Char.MoveItem(owner,bag,slots[spec.type],1)
      local rankLimit=math.min(11,(job-181)*2+4)
      if spec.native_rank<=rankLimit then
        check(Char.GetItemIndex(owner,slots[spec.type])==item,'actual equip '..job..'/'..spec.id)
        R.moves=R.moves+1
        Char.DelItemBySlot(owner,slots[spec.type])
      else
        check(Char.GetItemIndex(owner,bag)==item,'native rank gate '..job..'/'..spec.id)
        R.rank_rejections=R.rank_rejections+1
        Char.DelItemBySlot(owner,bag)
      end
    end
  end
  for _,spec in ipairs(D.items) do
    local item=Char.GiveItem(owner,spec.id,1,false)
    check(item>=0,'gate item '..spec.id)
    local bag=Char.GetItemSlot(owner,item)
    for _,job in ipairs({11,17,31,37}) do
      set('CHAR_职业',job)
      check(M:canEquip(owner,item)==0,'existing job '..job..'/'..spec.id)
    end
    for _,job in ipairs({77,180,188}) do
      set('CHAR_职业',job)
      check(M:canEquip(owner,item)<0,'excluded job '..job..'/'..spec.id)
    end
    set('CHAR_职业',187);set('CHAR_职阶',6)
    if spec.min_level>1 then
      set('CHAR_等级',spec.min_level-1)
      Char.MoveItem(owner,bag,slots[spec.type],1)
      check(Char.GetItemIndex(owner,bag)==item,'low level rejected '..spec.id)
      set('CHAR_等级',200)
    end
    Char.DelItemBySlot(owner,bag)
  end
  R.status='PASS'
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err) end
if owner>=0 then pcall(Char.DelDummy,owner) end
local f=assert(io.open('__OUTPUT__','w'));f:write(JSON.encode(R));f:close()
