local R={status='RUNNING',checks={},messages={},pets={},production_database_modified=false}
local Q=assert(getModule('gameQoL'))
local p,bankOwner=-1,-1
local nativePool=Char.GetPoolPet
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
 local high=Char.GivePet(p,90913,0)
 check(high>=0,'native slayer with strength full rank 67')
 local values={38,3,22,22,7}
 for i,art in ipairs(arts) do check(Pet.SetArtRank(high,art,values[i])==0,'reproduce screenshot rank '..i) end
 local before=snapshot(high);R.high_before=before
 check(before.ranks[2].current==3 and before.ranks[2].full==67,'screenshot strength 3/67')
 check(Q:handleTalk(p,'/petmax all')==0,'high-rank all command consumed')
 local highAfter=snapshot(high);R.high_after=highAfter
 for _,r in ipairs(highAfter.ranks) do check(r.current>=r.full,'high-rank species filled') end
 check(Q:handleTalk(p,'/petbp 2')==0,'high-rank petbp consumed')
 check(R.messages[#R.messages]:find('总掉档 0',1,true)~=nil,'high-rank petbp confirms zero loss')
 check(Pet.SetArtRank(high,arts[1],30)==0 and Pet.SetArtRank(high,arts[2],3)==0,'prepare partial-write rollback')
 local failedBefore=snapshot(high)
 local setter=Pet.SetArtRank
 Pet.SetArtRank=function(q,art,value)
  if q==high and art==arts[2] and value==67 then return -4 end
  return setter(q,art,value)
 end
 local called,result=pcall(Q.petRanks,Q,p,2,true)
 Pet.SetArtRank=setter
 check(called and result==false,'native limit rejection does not report success')
 local failedAfter=snapshot(high)
 for i,r in ipairs(failedBefore.ranks) do check(failedAfter.ranks[i].current==r.current,'partial write rolled back '..i) end
 check(R.messages[#R.messages]:find('重启服务端',1,true)~=nil,'limit rejection explains restart requirement')
 local dummy,save=Char.IsDummy,Char.SaveToDb
 Char.IsDummy=function(q) if q==p then return false end;return dummy(q) end
 Char.SaveToDb=function(q) if q==p then return -1 end;error('unexpected save target') end
 called,result=pcall(Q.petRanks,Q,p,2,true)
 Char.IsDummy=dummy;Char.SaveToDb=save
 check(called and result==false,'save failure does not report success')
 failedAfter=snapshot(high)
 for i,r in ipairs(failedBefore.ranks) do check(failedAfter.ranks[i].current==r.current,'save failure rolled back '..i) end
 check(R.messages[#R.messages]:find('保存失败',1,true)~=nil,'save failure explained')
 local saved=0
 Char.IsDummy=function(q) if q==p then return false end;return dummy(q) end
 Char.SaveToDb=function(q) check(q==p,'save only owner');saved=saved+1;return 0 end
 called,result=pcall(Q.petRanks,Q,p,2,true)
 Char.IsDummy=dummy;Char.SaveToDb=save
 check(called and result==true and saved==1,'confirmed successful save branch')
 for _,r in ipairs(snapshot(high).ranks) do check(r.current>=r.full,'confirmed save retains full ranks') end
 -- Native pets on a separate dummy provide bank fixtures without player data.
 bankOwner=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='PETBP_BANK_FIXTURE'})
 check(bankOwner>=0,'isolated bank fixture owner created')
 local bank={}
 for _,slot in ipairs({0,4}) do
  bank[slot]=Char.GivePet(bankOwner,3004,1)
  check(bank[slot]>=0,'native bank fixture created '..slot)
  check(Pet.SetArtRank(bank[slot],arts[1],Pet.FullArtRank(bank[slot],arts[1])-2)==0,'bank fixture loses two ranks '..slot)
 end
 Char.GetPoolPet=function(q,slot) if q==p then return bank[slot] or -1 end;return nativePool(q,slot) end
 local function send(command)
  local first=#R.messages+1
  check(Q:handleTalk(p,command)==0,'consumed '..command)
  local lines={};for i=first,#R.messages do lines[#lines+1]=R.messages[i] end
  return lines
 end
 local lines=send('/petbp bank 0')
 check(#lines==1 and lines[1]:find('银行宠物栏 0：',1,true) and lines[1]:find('总掉档 2',1,true),'bank first slot ranks and loss')
 lines=send('/petbp bank 4')
 check(#lines==1 and lines[1]:find('银行宠物栏 4：',1,true),'bank last slot supported')
 lines=send('/petbp bank all')
 check(#lines==2 and lines[1]:find('银行宠物栏 0：',1,true) and lines[2]:find('银行宠物栏 4：',1,true),'bank all skips empty slots')
 lines=send('/petbp all')
 check(#lines==5 and lines[1]:find('宠物栏 0：',1,true) and lines[4]:find('银行宠物栏 0：',1,true),'all includes carried and bank pets')
 lines=send('/petbp 0')
 check(#lines==1 and lines[1]:find('^宠物栏 0：'),'numeric argument remains carried slot')
 lines=send('/petbp bank 1')
 check(#lines==1 and lines[1]:find('银行宠物栏 1 没有宠物',1,true),'empty bank slot explained')
 for _,command in ipairs({'/petbp','/petbp bank','/petbp bank 5','/petbp bank -1','/petbp bank 0 extra','/petbp all extra','/petmax bank 0'}) do
  lines=send(command)
  check(#lines==1 and lines[1]:find('用法：',1,true),'invalid arguments rejected '..command)
 end
 Q.stalls[p]=true;lines=send('/petbp bank all');Q.stalls[p]=nil
 check(#lines==1 and lines[1]:find('摆摊期间',1,true),'bank query obeys stall gate')
 Char.SetData(p,CONST.CHAR_BattleMode,1);lines=send('/petbp bank all');Char.SetData(p,CONST.CHAR_BattleMode,0)
 check(#lines==1 and lines[1]:find('战斗',1,true),'bank query obeys battle gate')
 send('/petmax all')
 for slot,pet in pairs(bank) do check(Pet.GetArtRank(pet,arts[1])==Pet.FullArtRank(pet,arts[1])-2,'bank ranks unchanged by queries and petmax '..slot) end
 Char.GetPoolPet=function(q,slot) if q==p then return -1 end;return nativePool(q,slot) end
 check(#send('/petbp bank all')==0,'empty bank all remains safe')
 check(#send('/petbp all')==3,'all works with empty bank')
end,debug.traceback)
NLG.SystemMessage=oldMessage
Char.GetPoolPet=nativePool
if bankOwner>=0 then pcall(Char.DelDummy,bankOwner) end
if p>=0 then pcall(Char.DelDummy,p) end
R.status=ok and 'PASS' or 'FAIL';if not ok then R.error=tostring(err) end
local f=assert(io.open('__OUTPUT__/petmax_native.json','wb'));f:write(JSON.encode(R));f:close()
