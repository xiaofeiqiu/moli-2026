-- Native pets and actual bank slots; no production accounts or database used.
local R={status='RUNNING',checks={},production_accounts_used=false,real_native_bank=true}
local M=assert(getModule('petSkillUpgrade'));local T=ModuleBase:createModule('petUpgradeProbe'):new();T:load()
local p,donor=-1,-1;local bank={};local finished=false;local window;local started=os.time()
local original={window=NLG.ShowWindowTalked,add=Pet.AddSkill,delete=Pet.DelSkill,dummy=Char.IsDummy,save=Char.SaveToDb}
local function get(q,k) return Char.GetData(q,assert(CONST[k])) end
local function set(q,k,v) return Char.SetData(q,assert(CONST[k]),v) end
local function check(ok,name) R.checks[#R.checks+1]={name=name,pass=not not ok};assert(ok,name) end
local function ids(q) local a={};for i=0,9 do a[i+1]=Pet.GetSkill(q,i) end;return table.concat(a,':') end
local function setup(q,list,mp)
 set(q,'宠物_技能栏',10)
 for i=9,0,-1 do if Pet.GetSkill(q,i)>=0 then assert(original.delete(q,i)==1) end end
 for _,id in ipairs(list) do assert(original.add(q,id)==1) end
 set(q,'CHAR_最大魔',mp or 1000)
end
NLG.ShowWindowTalked=function(c,n,kind,buttons,seq,data,...)
 if c==p then window={kind=kind,buttons=buttons,seq=seq,data=data};R.windows=(R.windows or 0)+1 end
 return original.window(c,n,kind,buttons,seq,data,...)
end
local function menu()
 local a=assert(M.sessions[p]);check(window.kind==2 and #a.actions<=8,'native selection row limit')
 local text=window.data:gsub('\\n','\n'):gsub('\r\n','\n');local lines={}
 for line in (text..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
 local headers=assert(tonumber(lines[1]));local count=#lines-headers-1;if lines[#lines]=='' then count=count-1 end
 check(count==#a.actions,'displayed rows match callback choices')
 return a
end
local function click(kind,index)
 local a=menu()
 for i,action in ipairs(a.actions) do if action.kind==kind and (index==nil or action.index==index) then
  M:answer(M.npc,p,7330,0,tostring(i));return
 end end
 error('missing action '..kind)
end
local function confirm(slot)
 local q=assert(M:pet(p,slot));M:show(M.npc,p,'quote',slot,Pet.GetUUID(q));click('confirm',1)
 check(window.kind==0 and window.buttons==12 and window.seq==7331,'native yes/no payment confirmation')
end
local function finish(err)
 if finished then return end;finished=true
 NLG.ShowWindowTalked=original.window;Pet.AddSkill=original.add;Pet.DelSkill=original.delete
 Char.IsDummy=original.dummy;Char.SaveToDb=original.save
 if p>=0 then pcall(Char.DelDummy,p) end;if donor>=0 then pcall(Char.DelDummy,donor) end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end
local function run()
 check(get(M.npc,'CHAR_地图')==60003 and get(M.npc,'CHAR_X')==38 and get(M.npc,'CHAR_Y')==18,'new NPC at sanctuary 38,18')
 check(Map.IsWalkable(0,60003,38,19)==1,'southern approach is walkable')
 local _,objects=Obj.GetObject(0,60003,38,18);local occupants=0
 for _,obj in ipairs(objects or {}) do if Obj.GetType(obj)==1 then occupants=occupants+1 end end
 check(occupants==1,'new NPC does not overlap another object')
 for slot=0,4 do check(Char.GetPoolPet(p,slot)==bank[slot],'real bank slot '..slot) end
 check(Char.PetNum(p)==5 and Char.PetNum(donor)==0,'bank pets are absent from carried inventory')
 Char.AddGold(p,900000)
 local q=Char.GetPet(p,0);local uuid=Pet.GetUUID(q)
 -- Every authored ordinary rank belongs only to its matching native family.
 local seriesCount=0
 for key,series in pairs(M.series) do
  seriesCount=seriesCount+1
  for _,t in ipairs(series) do
   check(t.key==key and t.rank>=1 and t.rank<=10 and Tech.GetTechIndex(t.id)>=0,'valid rank catalog '..t.id)
  end
 end
 R.series=seriesCount;check(seriesCount>60,'original and copied rank series discovered')
 setup(q,{1930,7400},95);local quote=M:quote(p,0,uuid)
 check(#quote.entries==1 and quote.entries[1].id==1938 and quote.total==8000,'MP95 selects magic IX, not unaffordable X')
 set(q,'CHAR_魔',0);check(M:quote(p,0,uuid).total==8000,'current MP depletion does not lower full-MP quote')
 set(q,'CHAR_最大魔',100);check(M:quote(p,0,uuid).entries[1].id==1939,'MP100 selects magic X at exact boundary')
 set(q,'CHAR_等级',1);check(M:quote(p,0,uuid).entries[1].id==1939,'pet skills use full-MP affordability, not human skill-level markers')
 setup(q,{30,731,910400,6100,2700,6350,7300,7400},1000);quote=M:quote(p,0,uuid)
 check(#quote.entries==5 and quote.total==40000,'five distinct families quote exact rank-difference fee')
 check(quote.entries[1].id==38 and quote.entries[2].id==749 and quote.entries[3].id==910409,'physical and custom ranks select proper highest IDs')
 for _,e in ipairs(quote.entries) do check(e.old~=6350 and e.old~=7300 and e.old~=7400,'BOSS and unranked abilities retained') end
 M:show(M.npc,p,'quote',0,uuid);local a=menu();check(#a.actions==7,'five-skill quote paginates with four visible rows')
 click('page');check(M.sessions[p].page==2,'quote next page');menu();click('page');check(M.sessions[p].page==1,'quote previous page')
 local before,gold=ids(q),Char.GetGold(p);confirm(0);M:answer(M.npc,p,7331,8,'')
 check(ids(q)==before and Char.GetGold(p)==gold,'no cancels without skill or money changes')
 for _,reply in ipairs({{7331,2},{7331,0},{7330,4},{7339,4}}) do
  confirm(0);M:answer(M.npc,p,reply[1],reply[2],'1');check(ids(q)==before and Char.GetGold(p)==gold,'wrong or closed confirmation rejected '..reply[1]..'/'..reply[2])
 end
 confirm(0);M.sessions[p].expires=os.time()-1;M:answer(M.npc,p,7331,4,'');check(ids(q)==before and Char.GetGold(p)==gold,'expired payment rejected')
 confirm(0);M.sessions[p].player='stale';M:answer(M.npc,p,7331,4,'');check(ids(q)==before,'reused player index rejected')
 confirm(0);set(q,'CHAR_最大魔',999);M:answer(M.npc,p,7331,4,'');check(ids(q)==before and Char.GetGold(p)==gold,'changed maximum MP invalidates quote');set(q,'CHAR_最大魔',1000)
 confirm(0);Pet.SetUUID(q,'stale-pet');M:answer(M.npc,p,7331,4,'');Pet.SetUUID(q,uuid);check(ids(q)==before and Char.GetGold(p)==gold,'changed pet identity rejected')
 confirm(0);original.delete(q,0);M:answer(M.npc,p,7331,4,'');check(Char.GetGold(p)==gold,'changed skill list never charges');setup(q,{30,731,910400,6100,2700,6350,7300,7400})
 for _,state in ipairs({'battle','stall','settlement','distance'}) do
  confirm(0)
  if state=='battle' then set(p,'CHAR_BattleMode',1)
  elseif state=='stall' then getModule('gameQoL').stalls[p]=true
  elseif state=='settlement' then getModule('fivePet').active[p]={battle=0}
  else Char.Warp(p,0,1000,223,86) end
  before=ids(q);M:answer(M.npc,p,7331,4,'');check(ids(q)==before and Char.GetGold(p)==gold,'state rejects payment '..state)
  set(p,'CHAR_BattleMode',0);getModule('gameQoL').stalls[p]=nil;getModule('fivePet').active[p]=nil;Char.Warp(p,0,60003,38,19)
 end
 Char.AddGold(p,-Char.GetGold(p));quote=M:quote(p,0,uuid);before=ids(q)
 check(not M:upgrade(M.npc,p,quote) and ids(q)==before and Char.GetGold(p)==0,'insufficient money rejects whole upgrade')
 Char.AddGold(p,900000);gold=Char.GetGold(p)
 local failed=false;Pet.AddSkill=function(pet,id) if not failed then failed=true;return 0 end;return original.add(pet,id) end
 check(not M:upgrade(M.npc,p,quote) and ids(q)==before and Char.GetGold(p)==gold,'native write failure restores exact slots and money');Pet.AddSkill=original.add
 Char.IsDummy=function(c) if c==p then return false end;return original.dummy(c) end
 for _,failure in ipairs({'return','exception','native'}) do
  set(q,'CHAR_最大魔',1000);quote=M:quote(p,0,uuid);local attempted=false
  Char.SaveToDb=function(c) attempted=true;if failure=='exception' then error('injected save failure') elseif failure=='native' then return original.save(c) end;return -1 end
  check(not M:upgrade(M.npc,p,quote) and attempted and ids(q)==before and Char.GetGold(p)==gold,'save failure fully rolls back '..failure)
 end
 local saves=0;Char.SaveToDb=function(c) check(c==p,'save owner including bank inventory');saves=saves+1;return 0 end
 set(q,'CHAR_最大魔',1000)
 confirm(0);M:answer(M.npc,p,7331,4,'');check(Pet.GetSkill(q,0)==38 and Char.GetGold(p)==gold-4000 and saves==1,'single skill upgrades and charges only its rank difference')
 local afterGold=Char.GetGold(p);M:answer(M.npc,p,7331,4,'');check(Char.GetGold(p)==afterGold and saves==1,'replayed confirmation cannot charge twice')
 -- Sparse full-capacity skill layout must survive success and rollback.
 setup(q,{7400,30,731,910400,6100,2700,6350,7300,1930,2230});original.delete(q,0);original.delete(q,6)
 quote=M:quote(p,0,uuid);before=ids(q);gold=Char.GetGold(p)
 Char.SaveToDb=function() return -1 end
 check(not M:upgrade(M.npc,p,quote) and ids(q)==before and Char.GetGold(p)==gold,'sparse ten-slot layout restored exactly on save failure')
 Char.SaveToDb=function() saves=saves+1;return 0 end
 set(q,'CHAR_最大魔',1000);quote=M:quote(p,0,uuid)
 check(M:upgrade(M.npc,p,quote),'batch upgrade with holes succeeds')
 check(Pet.GetSkill(q,0)<0 and Pet.GetSkill(q,6)<0 and Pet.GetSkill(q,7)==7300,'original holes and unranked slot positions preserved')
 check(Char.GetGold(p)==gold-quote.total,'batch charged exactly quoted total')
 setup(q,{1930,1932},100);quote=M:quote(p,0,uuid)
 check(#quote.entries==1 and quote.entries[1].slot==1 and quote.total==7000,'same-series low rank retained; charge once from highest learned rank')
 check(M:upgrade(M.npc,p,quote) and Pet.GetSkill(q,0)==1930 and Pet.GetSkill(q,1)==1939,'same-series lower rank remains available for MP fallback')
 gold=Char.GetGold(p);check(#M:quote(p,0,uuid).entries==0 and not M:upgrade(M.npc,p,M:quote(p,0,uuid)) and Char.GetGold(p)==gold,'already learned highest rank never charges')
 Char.IsDummy=original.dummy;Char.SaveToDb=original.save
 for slot=0,9 do
  local pet=assert(M:pet(p,slot));local ref=Pet.GetUUID(pet);setup(pet,{30,7400})
  quote=M:quote(p,slot,ref);gold=Char.GetGold(p)
  check(M:upgrade(M.npc,p,quote) and Pet.GetSkill(pet,0)==38 and Pet.GetSkill(pet,1)==7400,'native carried/bank upgrade slot '..slot)
  check(Char.GetGold(p)==gold-4000 and M:pet(p,slot,ref)==pet,'correct original charged once, identity preserved slot '..slot)
 end
 M:show(M.npc,p);a=menu();check(#a.actions==8 and a.actions[1].kind=='allQuote','all-pets option first plus five carried slots and bank/rules')
 click('bank');a=menu();check(#a.actions==7 and a.actions[1].kind=='allQuote' and a.actions[6].slot==9,'all five actual bank slots and all-pets option exposed')
 local last=bank[4];setup(last,{1930},100);local ref=Pet.GetUUID(last);confirm(9)
 Pet.SetUUID(last,'changed-bank-pet');gold=Char.GetGold(p);M:answer(M.npc,p,7331,4,'');Pet.SetUUID(last,ref)
 check(Pet.GetSkill(last,0)==1930 and Char.GetGold(p)==gold,'bank identity changed after quote rejects charge')
 Char.IsDummy=function(c) if c==p then return false end;return original.dummy(c) end
 Char.SaveToDb=function() return -1 end;quote=M:quote(p,9,ref)
 check(not M:upgrade(M.npc,p,quote) and Pet.GetSkill(last,0)==1930 and Char.GetGold(p)==gold,'bank save failure restores original bank skill and gold')
 Char.IsDummy=original.dummy;Char.SaveToDb=original.save
 -- One owner transaction across real carried and bank inventories.
 local function bulkSetup()
  local before={}
  for slot=0,9 do
   local pet=assert(M:pet(p,slot))
   if slot==0 then setup(pet,{1930,1932,7400},95)
   elseif slot==1 then setup(pet,{1939,7400},100)
   elseif slot==2 then setup(pet,{7400,138},190);original.delete(pet,0)
   elseif slot==3 then setup(pet,{330,7400},170)
   elseif slot==4 then setup(pet,{6350,7400},1000)
   else setup(pet,{1930,7400},100) end
   before[slot+1]=ids(pet)
  end
  return before,Char.GetGold(p)
 end
 local function unchanged(before,gold,label)
  check(Char.GetGold(p)==gold,label..' gold')
  for slot=0,9 do check(ids(assert(M:pet(p,slot)))==before[slot+1],label..' pet '..slot) end
 end
 local function bulkConfirm()
  M:show(M.npc,p);click('allQuote');local state=menu()
  check(state.quote.count==8 and state.quote.skills==8 and state.quote.total==64000,'bulk summary excludes two non-upgradable pets with exact 64000 fee')
  click('allConfirm')
  check(window.kind==0 and window.buttons==12 and window.seq==7331 and M.sessions[p].kind=='allConfirm','one yes/no confirmation for all pets')
 end
 local originals,balance=bulkSetup();local all=M:quoteAll(p)
 check(#all.pets==10 and all.count==8 and all.skills==8 and all.total==64000,'all ten native carried/bank originals included in one quote')
 check(all.pets[1].entries[1].id==1938 and all.pets[3].entries[1].id==148 and all.pets[4].entries[1].id==346,
  'each pet uses its own max MP, physical ranks and highest learned rank')
 M:show(M.npc,p);click('allQuote');a=menu();check(#a.actions==7,'bulk eight-pet quote has four rows plus next/confirm/back')
 click('allPage');a=menu();check(a.page==2 and #a.actions==7,'bulk quote next page respects native row limit')
 click('allPage');check(M.sessions[p].page==1,'bulk quote previous page')
 bulkConfirm();M:answer(M.npc,p,7331,8,'');unchanged(originals,balance,'bulk cancel leaves all originals')
 for _,reply in ipairs({{7331,2},{7331,0},{7330,4},{7339,4}}) do
  bulkConfirm();M:answer(M.npc,p,reply[1],reply[2],'1');unchanged(originals,balance,'invalid bulk confirmation '..reply[1]..'/'..reply[2])
 end
 bulkConfirm();M.sessions[p].expires=os.time()-1;M:answer(M.npc,p,7331,4,'');unchanged(originals,balance,'expired bulk payment')
 bulkConfirm();M.sessions[p].player='stale';M:answer(M.npc,p,7331,4,'');unchanged(originals,balance,'stale bulk player')
 bulkConfirm();set(bank[4],'CHAR_最大魔',99);M:answer(M.npc,p,7331,4,'');set(bank[4],'CHAR_最大魔',100)
 unchanged(originals,balance,'changed last bank MP rejects every upgrade')
 bulkConfirm();local bankRef=Pet.GetUUID(bank[4]);Pet.SetUUID(bank[4],'changed-bank-pet')
 M:answer(M.npc,p,7331,4,'');Pet.SetUUID(bank[4],bankRef);unchanged(originals,balance,'changed last bank identity rejects every upgrade')
 bulkConfirm();original.delete(bank[4],0);local changed={table.unpack(originals)};changed[10]=ids(bank[4])
 M:answer(M.npc,p,7331,4,'');unchanged(changed,balance,'changed bank skill rejects every upgrade');originals,balance=bulkSetup()
 for _,state in ipairs({'battle','stall','settlement','distance'}) do
  bulkConfirm()
  if state=='battle' then set(p,'CHAR_BattleMode',1)
  elseif state=='stall' then getModule('gameQoL').stalls[p]=true
  elseif state=='settlement' then getModule('fivePet').active[p]={battle=0}
  else Char.Warp(p,0,1000,223,86) end
  M:answer(M.npc,p,7331,4,'');unchanged(originals,balance,'bulk unavailable '..state)
  set(p,'CHAR_BattleMode',0);getModule('gameQoL').stalls[p]=nil;getModule('fivePet').active[p]=nil;Char.Warp(p,0,60003,38,19)
 end
 Char.AddGold(p,-Char.GetGold(p));all=M:quoteAll(p)
 check(not M:upgradeAll(M.npc,p,all),'insufficient gold rejects complete transaction');unchanged(originals,0,'bulk insufficient gold')
 Char.AddGold(p,900000);balance=Char.GetGold(p)
 -- Fail only after several carried and bank pets have been rewritten.
 local broken=false;Pet.AddSkill=function(pet,id)
  if pet==bank[3] and not broken then broken=true;return 0 end;return original.add(pet,id)
 end
 check(not M:upgradeAll(M.npc,p,all) and broken,'later bank write failure aborts entire batch');Pet.AddSkill=original.add
 unchanged(originals,balance,'later bank write rollback includes earlier carried and bank pets')
 Char.IsDummy=function(c) if c==p then return false end;return original.dummy(c) end
 for _,failure in ipairs({'return','exception','native'}) do
  originals,balance=bulkSetup();all=M:quoteAll(p);local attempts=0
  Char.SaveToDb=function(c) attempts=attempts+1;if failure=='exception' then error('injected bulk save failure') elseif failure=='native' then return original.save(c) end;return -1 end
  check(not M:upgradeAll(M.npc,p,all) and attempts==1,'single owner save failure aborts bulk '..failure)
  unchanged(originals,balance,'all skill slots and full gold restored after save '..failure)
 end
 originals,balance=bulkSetup();local bulkSaves=0
 Char.SaveToDb=function(c) check(c==p,'bulk saves owner including bank inventory');bulkSaves=bulkSaves+1;return 0 end
 bulkConfirm();M:answer(M.npc,p,7331,4,'')
 check(Char.GetGold(p)==balance-64000 and bulkSaves==1,'bulk exact combined fee and one owner save')
 check(Pet.GetSkill(q,0)==1930 and Pet.GetSkill(q,1)==1938 and Pet.GetSkill(q,2)==7400,'bulk preserves low rank and original skill positions')
 check(Pet.GetSkill(Char.GetPet(p,2),0)<0 and Pet.GetSkill(Char.GetPet(p,2),1)==148,'bulk preserves sparse carried slots')
 check(Pet.GetSkill(Char.GetPet(p,3),0)==346,'bulk physical tier limited by individual max MP')
 check(ids(Char.GetPet(p,1))==originals[2] and ids(Char.GetPet(p,4))==originals[5],'highest rank and BOSS-only pets unchanged and uncharged')
 for i=0,4 do check(Pet.GetSkill(bank[i],0)==1939 and Pet.GetSkill(bank[i],1)==7400,'actual bank original upgraded '..i) end
 balance=Char.GetGold(p);M:answer(M.npc,p,7331,4,'')
 check(Char.GetGold(p)==balance and bulkSaves==1,'replayed bulk yes does not charge or save twice')
 Char.IsDummy=original.dummy;Char.SaveToDb=original.save
 for slot=0,9 do setup(assert(M:pet(p,slot)),{1939,7400},100) end
 all=M:quoteAll(p);check(all.count==0 and all.total==0 and not M:upgradeAll(M.npc,p,all),'all pets already highest never charge')
 check(Char.GetGold(p)==balance,'zero bulk fee leaves gold')
 M:show(M.npc,p);click('allQuote');a=menu();check(#a.actions==1 and a.actions[1].kind=='pets','no-upgrade bulk quote offers only return')
 for slot=0,9 do setup(assert(M:pet(p,slot)),{1930,7400},100) end
 M:show(M.npc,p);click('allQuote');a=menu();check(a.quote.count==10 and #a.actions==7,'ten eligible pets paginate')
 click('allPage');a=menu();check(a.page==2 and #a.actions==8,'middle bulk page has four pets and both page links within eight rows')
 click('allPage');a=menu();check(a.page==1,'middle page previous link works')
 -- Occupancy changes also invalidate a quote, even for an unpriced new pet.
 local complete=M:quoteAll(p);local oldPool=Char.GetPoolPet
 Char.GetPoolPet=function(c,slot) if c==p and slot==4 then return -1 end;return oldPool(c,slot) end
 local missing=M:quoteAll(p);check(#missing.pets==9,'empty bank slots skipped in quote')
 check(not M:upgradeAll(M.npc,p,complete),'removed bank pet invalidates all quote')
 Char.GetPoolPet=oldPool;check(not M:upgradeAll(M.npc,p,missing),'added bank pet invalidates all quote')
 check(Char.GetGold(p)==balance,'occupancy changes never charge')
 M:show(M.npc,p);reloadModule('petSkillUpgrade');M=assert(getModule('petSkillUpgrade'))
 check(M.sessions[p]==nil and #M.npcList==1,'reload discards payment sessions and owns exactly one new NPC')
 check(get(M.npc,'CHAR_X')==38 and get(M.npc,'CHAR_Y')==18,'reload keeps current placement')
 for slot=0,4 do check(Char.GetPoolPet(p,slot)==bank[slot],'reload leaves bank originals in place '..slot) end
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=60003,x=38,y=19,image=100002,name='PET_UPGRADE_TEST'})
  donor=Char.CreateDummy({mapType=0,floor=60003,x=38,y=19,image=100002,name='PET_UPGRADE_BANK'})
  check(p>=0 and donor>=0,'isolated native fixture players')
  set(p,'CHAR_账号','PET_UPGRADE_TEST');set(p,'对象_RegistNumber',0);set(p,'CHAR_等级',100)
  local fixture={player=p,player_pointer=tostring(Char.GetCharPointer(p)),donor=donor,donor_pointer=tostring(Char.GetCharPointer(donor)),pets={}}
  for slot=0,4 do
   check(Char.GivePet(p,3004,1)>=0,'native carried pet '..slot);local pet=Char.GivePet(donor,3004,1);check(pet>=0,'native bank source '..slot)
   bank[slot]=pet;fixture.pets[#fixture.pets+1]={index=pet,pointer=tostring(Char.GetCharPointer(pet))}
  end
  local f=assert(io.open('__OUTPUT__/bank_fixture_request.tmp','wb'));f:write(JSON.encode(fixture));f:close()
  assert(os.rename('__OUTPUT__/bank_fixture_request.tmp','__OUTPUT__/bank_fixture_request.json'))
  T:AddInterval(100,function()
   if finished then return end
   local ready=io.open('__OUTPUT__/bank_fixture_ready','rb')
   if not ready then if os.time()-started>40 then finish('native bank fixture timed out') end;return end
   ready:close();local success,error=xpcall(run,debug.traceback);finish(not success and error or nil)
  end,1)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
