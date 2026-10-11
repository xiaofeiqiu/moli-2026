local R={status='RUNNING',checks={},messages={},pets={},production_database_modified=false}
local Q=assert(getModule('gameQoL'))
local p=-1
local oldMessage=NLG.SystemMessage
local arts={CONST['宠档_体成'],CONST['宠档_力成'],CONST['宠档_强成'],CONST['宠档_敏成'],CONST['宠档_魔成']}
local function check(ok,label)
 R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label)
end
local function snapshot(pet)
 local t={level=Char.GetData(pet,CONST['CHAR_等级']),ranks={},stats={}}
 for _,art in ipairs(arts) do t.ranks[#t.ranks+1]={current=Pet.GetArtRank(pet,art),full=Pet.FullArtRank(pet,art)} end
 for _,key in ipairs({'CHAR_体力','CHAR_力量','CHAR_强度','CHAR_速度','CHAR_魔法','CHAR_升级点'}) do t.stats[key]=Char.GetData(pet,CONST[key]) end
 return t
end
NLG.SystemMessage=function(player,text,...)
 R.messages[#R.messages+1]=text;return oldMessage(player,text,...)
end
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='PETMAX_PROBE'})
 check(p>=0,'isolated dummy created')
 for slot,full in ipairs({0,1}) do
  local pet=Char.GivePet(p,3004,full)
  check(pet>=0,'native pet created '..full)
  R.pets[slot]={creation_full_flag=full,before=snapshot(pet)}
 end
 local pet=Char.GetPet(p,0)
 for _,art in ipairs(arts) do check(Pet.SetArtRank(pet,art,Pet.FullArtRank(pet,art)-2)==0,'set two lost ranks '..art) end
 R.pets[1].lowered=snapshot(pet)
 local preserved=snapshot(pet)
 check(Q:handleTalk(p,'/petmax all')==0,'all command consumed')
 for slot=0,1 do
  local after=snapshot(Char.GetPet(p,slot));R.pets[slot+1].after=after
  for _,rank in ipairs(after.ranks) do check(rank.current==rank.full,'rank filled slot '..slot) end
 end
 check(R.messages[#R.messages-1]:find('补回 10 档',1,true)~=nil,'all fills ten missing ranks')
 check(R.messages[#R.messages]:find('补回 0 档',1,true)~=nil,'all reports zero for full pet')
 local after=R.pets[1].after
 check(after.level==preserved.level,'level preserved')
 for key,value in pairs(preserved.stats) do check(after.stats[key]==value,'BP preserved '..key) end
 check(Q:handleTalk(p,'/petmax all')==0,'repeat consumed')
 check(R.messages[#R.messages]:find('补回 0 档',1,true)~=nil and R.messages[#R.messages-1]:find('补回 0 档',1,true)~=nil,'repeat reports zero for both')
end,debug.traceback)
NLG.SystemMessage=oldMessage
if p>=0 then pcall(Char.DelDummy,p) end
R.status=ok and 'PASS' or 'FAIL';if not ok then R.error=tostring(err) end
local f=assert(io.open('__OUTPUT__/petmax_native.json','wb'));f:write(JSON.encode(R));f:close()
