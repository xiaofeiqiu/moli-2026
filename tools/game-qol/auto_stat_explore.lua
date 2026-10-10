local R={status='RUNNING',events={},tiles={},api={}}
local p=-1
local T=ModuleBase:createModule('autoStatExplore'):new();T:load()
local function snapshot(c)
 local out={}
 for _,key in ipairs({'CHAR_等级','CHAR_经验','CHAR_升级点','CHAR_体力','CHAR_力量','CHAR_强度','CHAR_速度','CHAR_魔法'}) do out[key]=Char.GetData(c,CONST[key]) end
 return out
end
local ok,err=xpcall(function()
 for _,event in ipairs({'LevelUpEvent','PetLevelUpEvent','CharaAfterUpLevelEvent'}) do
  T:regCallback(event,function(...)
   local args={...};R.events[#R.events+1]={event=event,args=args,first=snapshot(args[1]),second=args[2] and Char.IsPet(args[2]) and snapshot(args[2]) or nil}
  end)
 end
 for key,value in pairs(Char) do if type(value)=='function' and (key:lower():match('exp') or key:lower():match('level') or key:lower():match('pet')) then R.api[#R.api+1]=key end end
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='AUTO_STAT_EXPLORE'});assert(p>=0)
 local pet=Char.GivePet(p,3004,0);assert(pet>=0)
 R.petUUID=Pet.GetUUID(pet);R.charUUID=Char.GetUUID(p);R.owner=Pet.GetOwner(pet)
 R.before={player=snapshot(p),pet=snapshot(pet)}
 Char.SetData(p,CONST['CHAR_经验'],2000);NLG.UpChar(p)
 Char.SetData(pet,CONST['CHAR_经验'],2000);Pet.UpPet(p,pet)
 R.after={player=snapshot(p),pet=snapshot(pet)}
 for y=83,93 do for x=220,235 do
  local _,objects=Obj.GetObject(0,1000,x,y)
  local tile={x=x,y=y,walkable=Map.IsWalkable(0,1000,x,y),objects={}}
  for _,obj in ipairs(objects or {}) do
   local c=Obj.GetCharIndex(obj)
   tile.objects[#tile.objects+1]={type=Obj.GetType(obj),char=c,name=c>=0 and Char.GetData(c,CONST['CHAR_名字']) or ''}
  end
  R.tiles[#R.tiles+1]=tile
 end end
 R.status='PASS'
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err) end
if p>=0 then pcall(Char.DelDummy,p) end
local f=assert(io.open('__OUTPUT__/auto_stat_explore.json','wb'));f:write(JSON.encode(R));f:close()
