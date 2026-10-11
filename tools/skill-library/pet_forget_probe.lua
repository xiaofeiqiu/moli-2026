-- Exercise native NPC windows and pet APIs in the isolated test server only.
local R={status='RUNNING',checks={},npcs={},windows=0,production_accounts_used=false}
local p,pet,other=-1,-1,-1
local window
local originals={window=NLG.ShowWindowTalked,save=Char.SaveToDb,dummy=Char.IsDummy,delete=Pet.DelSkill,message=NLG.SystemMessage}
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function set(q,k,v) return Char.SetData(q,assert(CONST[k],k),v) end
local function check(ok,name) R.checks[#R.checks+1]={name=name,pass=not not ok};assert(ok,name) end
local function snapshot(q)
 local out={};for i=0,9 do out[#out+1]=Pet.GetSkill(q,i) end;return JSON.encode(out)
end
local function rows()
 check(window~=nil,'native selection window shown')
 check(window.kind==2,'only selection windows expose row indices')
 local data=window.data:gsub('\r\n','\n'):gsub('\\n','\n');local lines={}
 for line in (data..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
 local header=assert(tonumber(lines[1]));local out={}
 for i=header+2,#lines do if lines[i]~='' then out[#out+1]=lines[i] end end
 check(#out<=8,'native selection has at most eight rows');return out
end
NLG.ShowWindowTalked=function(player,n,kind,buttons,seq,data,...)
 if player==p then window={npc=n,kind=kind,buttons=buttons,seq=seq,data=data};R.windows=R.windows+1 end
 return originals.window(player,n,kind,buttons,seq,data,...)
end
NLG.SystemMessage=function(player,msg,...)
 if player==p then R.last_message=msg end
 return originals.message(player,msg,...)
end
local function click(m,label,button)
 if window and window.kind==0 then
  check(window.buttons==12 and window.seq==7321,'native yes/no confirmation has separate sequence')
  local value=label=='确认遗忘' and 4 or label=='取消，返回技能列表' and 8
  check(value~=nil,'native confirmation button '..label)
  local w=window;window=nil
  _G[m.name..'_npc_'..w.npc..'_WindowTalkedEvent'](w.npc,p,w.seq,button or value,'')
  return
 end
 local index
 for i,s in ipairs(rows()) do if s==label then index=i end end
 check(index~=nil,'visible row '..label)
 local w=window;window=nil
 _G[m.name..'_npc_'..w.npc..'_WindowTalkedEvent'](w.npc,p,w.seq,button or 0,tostring(index))
end
local function home(m) window=nil;_G[m.name..'_npc_'..m.npc..'_TalkedEvent'](m.npc,p) end
local function select(m,skillSlot)
 home(m);click(m,'宠物1：'..get(pet,'CHAR_名字'));click(m,'遗忘宠物技能')
 if skillSlot>=5 then click(m,'下一页') end
 local label
 for _,s in ipairs(rows()) do if s:match('^技能'..(skillSlot+1)..'：') then label=s end end
 check(label~=nil,'skill slot visible '..skillSlot);click(m,label)
 check(m.sessions[p].kind=='confirm','selection requires second confirmation')
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  local m=assert(getModule('petSkillTutor'));local n=m.npc
  R.npcs={{module=m.name,name=get(n,'CHAR_名字'),floor=get(n,'CHAR_地图'),x=get(n,'CHAR_X'),y=get(n,'CHAR_Y')}}
  check(get(n,'CHAR_地图')==60003 and get(n,'CHAR_X')==36 and get(n,'CHAR_Y')==18,'tutor installed at sanctuary 36,18')
  check(Map.IsWalkable(0,60003,36,18)==1 and Map.IsWalkable(0,60003,36,19)==1,'tutor and approach walkable')
  local _,objects=Obj.GetObject(0,60003,36,18);local npcs=0
  for _,o in ipairs(objects or {}) do if Obj.GetType(o)==1 then npcs=npcs+1 end end
  check(npcs==1,'new tutor does not overlap another NPC')
  p=Char.CreateDummy({mapType=0,floor=60003,x=30,y=19,image=100002,name='PET_FORGET_TEST'})
  check(p>=0,'isolated player created');Char.AddGold(p,100000)
  home(m);check(#rows()==2,'no-pet menu has rules and close')
  pet=Char.GivePet(p,3004,1);other=Char.GivePet(p,3004,1)
  check(pet>=0 and other>=0,'two owned native pets');set(pet,'宠物_技能栏',10)
  for i=0,9 do if Pet.GetSkill(pet,i)>=0 then Pet.DelSkill(pet,i) end end
  local unique,ids={},{}
  for _,s in ipairs(dofile('lua/Modules/skillTrainingData.lua').pets) do
   if #ids<10 and not unique[s.id] and Tech.GetTechIndex(s.id)>=0 then
    check(Pet.AddSkill(pet,s.id)==1,'seed native pet skill '..s.id);unique[s.id]=true;ids[#ids+1]=s.id
   end
  end
  check(#ids==10,'full ten-slot fixture');local uuid=Pet.GetUUID(pet)
  local before=snapshot(pet);local untouched=snapshot(other);local gold=Char.GetGold(p)
  select(m,6);click(m,'取消，返回技能列表')
  check(m.sessions[p].kind=='skills' and m.sessions[p].page==2 and snapshot(pet)==before,'cancel keeps all skills and returns to same page')
  click(m,'上一页');check(m.sessions[p].page==1,'previous-page callback')
  click(m,'返回宠物菜单');check(m.sessions[p].kind=='petHome','return to selected pet menu');click(m,'返回宠物列表');check(m.sessions[p].kind=='pets','return to pet selection')
  select(m,0);click(m,'确认遗忘',2)
  check(snapshot(pet)==before and m.sessions[p]==nil,'window close cannot confirm deletion')
  select(m,0);m:answer(m.npc,p,7321,0,'1')
  check(snapshot(pet)==before and m.sessions[p]==nil,'selection-style reply cannot confirm a message window')
  select(m,0);window=nil
  m:answer(m.npc,p,7320,4,'1')
  check(snapshot(pet)==before and m.sessions[p]==nil,'old selection sequence cannot confirm deletion')
  select(m,0);local a=m.sessions[p];a.expires=os.time()-1;click(m,'确认遗忘')
  check(snapshot(pet)==before,'expired confirmation rejected')
  select(m,0);m.sessions[p].player='stale-player';click(m,'确认遗忘')
  check(snapshot(pet)==before,'reused player index rejected')
  select(m,0);local savedUUID=Pet.GetUUID(pet);Pet.SetUUID(pet,'pet-forget-changed')
  click(m,'确认遗忘');Pet.SetUUID(pet,savedUUID)
  check(snapshot(pet)==before,'changed pet UUID rejected')
  select(m,0);check(Char.MovePet(p,0,1)==0 or Char.GetPet(p,0)~=pet,'move selected pet to another slot')
  click(m,'确认遗忘');check(snapshot(pet)==before and snapshot(other)==untouched,'slot swap cannot delete either pet')
  Char.MovePet(p,1,0);check(Char.GetPet(p,0)==pet,'restore pet placement')
  select(m,0);Pet.DelSkill(pet,0);click(m,'确认遗忘')
  check(#m:skills(pet)==9,'changed skill list cannot delete replacement');Pet.AddSkill(pet,ids[1])
  before=snapshot(pet)
  select(m,0);set(p,'CHAR_BattleMode',1);click(m,'确认遗忘');set(p,'CHAR_BattleMode',0)
  check(snapshot(pet)==before,'battle mode rejects deletion')
  select(m,0);getModule('gameQoL').stalls[p]=true;click(m,'确认遗忘');getModule('gameQoL').stalls[p]=nil
  check(snapshot(pet)==before,'stall rejects deletion')
  select(m,0);getModule('fivePet').active[p]={battle=0};click(m,'确认遗忘');getModule('fivePet').active[p]=nil
  check(snapshot(pet)==before,'five-pet pending settlement rejects deletion')
  select(m,0);Char.Warp(p,0,1000,200,100);click(m,'确认遗忘')
  check(snapshot(pet)==before,'distant confirmation rejected');Char.Warp(p,0,60003,36,19)
  check(not m:forget(n,p,0,'wrong-uuid',0,ids[1]),'direct UUID mismatch rejected')
  check(not m:forget(n,p,0,uuid,0.5,ids[1]),'fractional skill slot rejected')
  check(not m:forget(n,p,5,uuid,0,ids[1]),'out-of-range pet slot rejected')
  check(not m:forget(n,p,0,uuid,0,999999999),'changed skill ID rejected')
  Pet.DelSkill=function() return 0 end
  check(not m:forget(n,p,0,uuid,0,Pet.GetSkill(pet,0)) and snapshot(pet)==before,'native delete failure preserves all skills')
  Pet.DelSkill=originals.delete
  Char.IsDummy=function(q) if q==p then return false end;return originals.dummy(q) end
  for _,failure in ipairs({'return','exception'}) do
   Char.SaveToDb=function() if failure=='exception' then error('injected save failure') end;return -1 end
   local success,msg=m:forget(n,p,0,uuid,0,Pet.GetSkill(pet,0))
   check(not success and msg:find('保存失败',1,true) and snapshot(pet)==before,'failed save restores deleted skill '..failure)
  end
  Char.SaveToDb=function(q) local result=originals.save(q);R.native_save_return=result;return result end
  -- Native SaveToDb rejects dummy players with -3. Exercise its real failure
  -- and rollback, then inject success to verify the ordinary player's branch.
  check(not m:forget(n,p,0,uuid,0,Pet.GetSkill(pet,0)) and snapshot(pet)==before,'native dummy save failure restores deleted skill')
  check(R.native_save_return==-3,'native engine refuses to save a dummy player')
  local saveCalls=0
  Char.SaveToDb=function(q)
   check(q==p and #m:skills(pet)==9,'save called after deleting exactly one skill')
   saveCalls=saveCalls+1;return 0
  end
  select(m,6);local id=Pet.GetSkill(pet,6);click(m,'确认遗忘')
  check(#m:skills(pet)==9 and Pet.GetSkill(pet,6)~=id,'confirmed selection deletes only the chosen skill: '..tostring(R.last_message)..' save='..tostring(R.native_save_return))
  for _,s in ipairs(m:skills(pet)) do check(s.id~=id,'deleted ID absent from native pet slots') end
  check(saveCalls==1,'successful player save branch called once')
  Char.IsDummy=originals.dummy;Char.SaveToDb=originals.save
  check(snapshot(other)==untouched and Char.GetGold(p)==gold,'other pet and player gold unchanged')
  -- The released slot can be used immediately by an existing learning tutor.
  local teaching=getModule('petSkillTutor');local spec
  for _,s in ipairs(dofile('lua/Modules/skillTrainingData.lua').pets) do if s.id==id then spec=s;break end end
  local teacher=teaching.npc
  Char.Warp(p,0,60003,get(teacher,'CHAR_X'),get(teacher,'CHAR_Y')+1)
  check(teaching:learnPet(teacher,p,0,uuid,id),'freed slot accepts normal tutor learning')
  check(#m:skills(pet)==10 and Char.GetGold(p)==gold-spec.cost,'relearning uses ordinary fee')
  Char.Warp(p,0,60003,36,19)
  for i=9,0,-1 do if Pet.GetSkill(pet,i)>=0 then Pet.DelSkill(pet,i) end end
  home(m);click(m,'宠物1：'..get(pet,'CHAR_名字'));click(m,'遗忘宠物技能');check(#rows()==1,'empty skill list offers return only')
  home(m);click(m,'查看学习与遗忘规则');check(m.sessions[p].kind=='pets','rules return to pet list')
  home(m);click(m,'关闭');check(m.sessions[p]==nil,'close clears session')
  home(m);reloadModule('petSkillTutor');m=getModule('petSkillTutor')
  check(m and #m.npcList==1 and m.sessions[p]==nil,'reload creates one tutor and discards old confirmations')
  local _,list=Obj.GetObject(0,60003,36,18);check(#list==1,'reload leaves one NPC at placement')
 end,debug.traceback)
 NLG.ShowWindowTalked=originals.window;NLG.SystemMessage=originals.message;Char.SaveToDb=originals.save;Char.IsDummy=originals.dummy;Pet.DelSkill=originals.delete
 if p>=0 then
  local qol=getModule('gameQoL');if qol then qol.stalls[p]=nil end
  local five=getModule('fivePet');if five then five.active[p]=nil end
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end
  pcall(Char.DelDummy,p)
 end
 R.status=ok and 'PASS' or 'FAIL';R.error=not ok and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end,0)
