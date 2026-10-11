local R={status='RUNNING',checks={},npcs={},moves={},masks={},production_accounts_used=false}
local p=-1
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function check(ok,name) R.checks[#R.checks+1]={pass=not not ok,name=name};assert(ok,name) end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=60003,x=48,y=27,image=100002,name='PET_EQUIP_EXPLORE'})
  check(p>=0,'dummy created')
  local q=Char.GivePet(p,3004,1);check(q>=0,'owned pet created')
  Char.SetData(q,CONST['CHAR_等级'],200);NLG.UpChar(q)
  for typ=56,60 do
   local mask={type=typ,places={}}
   for slot=0,4 do mask.places[#mask.places+1]=Item.GetPetEquipPlace(typ,slot) end
   R.masks[#R.masks+1]=mask
  end
  for family=0,4 do
   local id=700000+family*15
   for slot=0,4 do
    local item=Char.GiveItem(p,id,1,false);check(item>=0,'give pet equipment')
    Item.SetData(item,CONST['道具_已鉴定'],1)
    local bag=Char.GetItemSlot(p,item)
    local call,result=pcall(Pet.MoveItem,p,0,bag,1,slot)
    local actual=Char.GetItemIndex(q,slot)
    local equipped=actual==item
    local row={id=id,slot=slot,bag=bag,call=call,result=tostring(result),equipped=equipped,
     actual=actual,attack=get(q,'CHAR_攻击力'),defense=get(q,'CHAR_防御力')}
    R.moves[#R.moves+1]=row
    if equipped then
     Pet.MoveItem(p,1,slot,0,bag)
     check(Char.GetItemIndex(p,bag)==item,'unequip restores same item')
    end
    local now=Char.GetItemSlot(p,item)
    check(now>=8,'test item remains owned');Char.DelItemBySlot(p,now)
   end
  end
 end,debug.traceback)
 if p>=0 then for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end;pcall(Char.DelDummy,p) end
 R.status=ok and 'PASS' or 'FAIL';R.error=not ok and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end,0)
