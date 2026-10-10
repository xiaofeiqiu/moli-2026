local R={status='RUNNING',constants={},items={},pages={},pet={},fever={}}
local p=-1
local function data(i,fields)
 local t={};for _,key in ipairs(fields) do local k=CONST[key];if k then t[key]=Char.GetData(i,k) end end;return t
end
local function slots()
 local t={};for s=8,87 do local i=Char.GetItemIndex(p,s);if i>=0 then t[tostring(s)]={index=i,id=Item.GetData(i,CONST['道具_ID']),count=Item.GetData(i,CONST['道具_堆叠数'])} end end;return t
end
local function item(id,slot)
 local i=Item.MakeItem(id);assert(i>=0,'make '..id);R.items[tostring(id)]={}
 for k=0,78 do R.items[tostring(id)][tostring(k)]=Item.GetData(i,k) end
 Char.SetItemIndex(p,slot,i);return i
end
local ok,err=xpcall(function()
 for key,v in pairs(CONST) do if key=='EXTBAGPAGE' or key:match('宠档') or key:match('卡时') or key:match('打卡') or key:match('交易') or key:match('Trade') or key:match('Work') or key:match('Window') or key:match('Stall') or key:match('Gold') or key:match('GOLD') or key:match('道具栏') or key:match('道具_.*名') then R.constants[key]=v end end
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='QOL_EXPLORE'});assert(p>=0)
 R.bagSize=Char.GetData(p,CONST['CHAR_道具栏']);R.page=Char.GetBagPage(p)
 local a=item(2001,8);local b=item(2001,9);Item.SetData(a,CONST['道具_最大堆叠数'],999);Item.SetData(b,CONST['道具_最大堆叠数'],999)
 Item.SetData(a,CONST['道具_堆叠数'],600);Item.SetData(b,CONST['道具_堆叠数'],500)
 R.sort=NLG.SortItem(p);R.afterSort=slots()
 item(123020,12);R.pages.before=slots();R.pages.switch=Char.SwitchBag(p,1);R.pages.after=slots()
 R.pages.give=Char.GiveItem(p,2002,1,false);R.pages.given=slots();R.pages.move=Char.MoveItem(p,8,9,-1);R.pages.moved=slots()
 R.pages.switch0=Char.SwitchBag(p,0);R.pages.restored=slots()
 R.fever.before=Char.IsFeverTime(p);R.fever.time=Char.GetData(p,CONST['对象_卡时']);Char.SetData(p,CONST['对象_卡时'],3600);R.fever.start=Char.FeverStart(p);R.fever.after=Char.IsFeverTime(p);R.fever.stop=Char.FeverStop(p)
 local pet=Char.GivePet(p,3004,0);assert(pet>=0)
 R.pet.before=data(pet,{'CHAR_等级','CHAR_体力','CHAR_力量','CHAR_强度','CHAR_速度','CHAR_魔法','CHAR_升级点','CHAR_经验'})
 R.pet.ranks={};for k=1,5 do R.pet.ranks[k]={before=Pet.GetArtRank(pet,k),full=Pet.FullArtRank(pet,k)};R.pet.ranks[k].set=Pet.SetArtRank(pet,k,Pet.FullArtRank(pet,k)) end
 Pet.UpPet(p,pet);R.pet.after=data(pet,{'CHAR_等级','CHAR_体力','CHAR_力量','CHAR_强度','CHAR_速度','CHAR_魔法','CHAR_升级点','CHAR_经验'})
 R.pet.rebirth=Pet.ReBirth(p,pet);R.pet.reborn=data(pet,{'CHAR_等级','CHAR_体力','CHAR_力量','CHAR_强度','CHAR_速度','CHAR_魔法','CHAR_升级点','CHAR_经验'})
 R.status='PASS'
end,debug.traceback)
if p>=0 then pcall(Char.DelDummy,p) end
if not ok then R.status='FAIL';R.error=tostring(err) end
local f=assert(io.open('__OUTPUT__/explore_result.json','wb'));f:write(JSON.encode(R));f:close()
