-- Real native pets and upgrade callbacks; only the bank inventory lookup is
-- substituted because the public Lua API cannot deposit pets into bank slots.
local R={status='RUNNING',checks={},npcs={},windows=0,production_accounts_used=false,bank_inventory_fixture=true}
local p=-1
local A=assert(getModule('autoStat'))
local S=assert(getModule('petSkillTutor'))
local originalPet,originalPool,originalWindow=Char.GetPet,Char.GetPoolPet,NLG.ShowWindowTalked
local bank,hidden={},true
local window
Char.GetPet=function(c,slot) if c==p and hidden then return -1 end;return originalPet(c,slot) end
Char.GetPoolPet=function(c,slot) if c==p then return bank[slot] or -1 end;return originalPool(c,slot) end
NLG.ShowWindowTalked=function(c,n,kind,buttons,seq,data,...)
 if c==p then window={npc=n,kind=kind,seq=seq,data=data};R.windows=R.windows+1 end
 return originalWindow(c,n,kind,buttons,seq,data,...)
end
local function get(c,k) local field=assert(CONST[k],k);return Char.GetData(c,field) end
local function set(c,k,v) return Char.SetData(c,assert(CONST[k],k),v) end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function reach(n)
 Char.Warp(p,get(n,'CHAR_地图类型'),get(n,'CHAR_地图'),get(n,'CHAR_X'),get(n,'CHAR_Y')+1)
end
local function rows(session)
 local lines={};local text=window.data:gsub('\\n','\n'):gsub('\r\n','\n')
 for line in (text..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
 local headers=assert(tonumber(lines[1]));local total=#lines-headers-1
 if lines[#lines]=='' then total=total-1 end
 check(total==#session.actions and total<=8,'displayed menu rows match actionable selections')
end
local function skillClick(kind)
 local a=S.sessions[p];rows(a)
 for i,v in ipairs(a.actions) do if v.kind==kind then S:answer(S.npc,p,7320,0,tostring(i));return end end
 error('missing action '..kind)
end
local function finish(err)
 Char.GetPet=originalPet;Char.GetPoolPet=originalPool;NLG.ShowWindowTalked=originalWindow
 if p>=0 then Char.DelDummy(p) end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=1000,x=223,y=86,image=100002,name='BANK_SERVICES_TEST'})
  check(p>=0,'isolated native player');set(p,'CHAR_账号','BANK_SERVICES_TEST');set(p,'对象_RegistNumber',0)
  set(p,'CHAR_等级',50);Char.AddGold(p,100000)
  for slot=0,4 do
   local q=Char.GivePet(p,3004,1);check(q>=0,'native bank fixture '..slot);bank[slot]=q
   set(q,'CHAR_名字','BANK_'..slot)
   for i=9,0,-1 do if Pet.GetSkill(q,i)>=0 then Pet.DelSkill(q,i) end end
  end
  reach(A.npc);A:show(A.npc,p);rows(A.sessions[p])
  A:answer(A.npc,p,7310,0,'7');rows(A.sessions[p])
  check(A.sessions[p].bank and #A.sessions[p].actions==6,'all five bank slots and return entry shown')
  for slot=0,4 do
   A:show(A.npc,p,nil,true);A:answer(A.npc,p,7310,0,tostring(slot+1))
   check(A.sessions[p].ref==tostring(Pet.GetUUID(bank[slot])),'bank selection resolves UUID '..slot)
   A:answer(A.npc,p,7310,0,'2')
   check(A:settings(p).pets[tostring(Pet.GetUUID(bank[slot]))].weights[2]==1,'bank full-strength plan saved '..slot)
   local q=bank[slot];set(q,'CHAR_升级点',3);set(q,'CHAR_经验',Char.GetNextExp(q))
   getModule('fivePet'):updatePet(p,{bankSlot=slot,pet=q})
   check(A.pending[p] and A.pending[p].entries[tostring(Pet.GetUUID(q))],'native bank upgrade queued '..slot)
   local strength=get(q,'CHAR_力量');A:flushOwner(p)
   check(get(q,'CHAR_力量')==strength+200 and get(q,'CHAR_升级点')==3,'bank award allocated preserving old BP '..slot)
  end
  A:show(A.npc,p,nil,true);A:answer(A.npc,p,7310,0,'5');A:answer(A.npc,p,7310,0,'6')
  local last=bank[4];bank[4]=nil
  A:answer(A.npc,p,7311,CONST['按钮_确定'],'0 0 0 1 0')
  check(A:settings(p).pets[tostring(Pet.GetUUID(last))].weights[2]==1,'stale bank stat input rejected')
  bank[4]=last;local first=bank[0];bank[0],bank[4]=last,first
  check(A:target(p,tostring(Pet.GetUUID(first)))==first,'stat plan follows UUID after bank slot swap')
  hidden=false;bank[4]=nil
  check(A:target(p,tostring(Pet.GetUUID(first)))==first,'same stat plan found after bank withdrawal')
  hidden=true;bank[4]=first
  reloadModule('autoStat');A=assert(getModule('autoStat'))
  check(A:settings(p).pets[tostring(Pet.GetUUID(first))].weights[2]==1,'bank stat configuration survives reload')
  check(A:setPlan(p,tostring(Pet.GetUUID(first)),nil,false),'bank stat plan independently disabled')
  reach(S.npc);S:show(S.npc,p);skillClick('bankPets');rows(S.sessions[p])
  check(#S.sessions[p].actions==6,'skill tutor lists all five bank pets and return')
  S:answer(S.npc,p,7320,0,'5');skillClick('learning');skillClick('learnConfirm')
  local a=S.sessions[p];local id=a.id;local gold=Char.GetGold(p)
  check(a.slot==9 and a.uuid==Pet.GetUUID(first),'skill confirmation retains fifth bank slot and UUID')
  S:answer(S.npc,p,7322,8,'')
  check(Char.GetGold(p)==gold and Pet.GetSkill(first,0)<0,'bank learning cancellation does not charge or learn')
  skillClick('learnConfirm');S:answer(S.npc,p,7322,4,'')
  check(Pet.GetSkill(first,0)==id and Char.GetGold(p)==gold-1000,'native bank learning teaches original and charges player once')
  local learned,msg=S:learnPet(S.npc,p,9,Pet.GetUUID(first),id)
  check(not learned and Char.GetGold(p)==gold-1000,'duplicate bank learning never charges again')
  S:show(S.npc,p,'petHome',1,9,Pet.GetUUID(first));skillClick('skills');skillClick('confirm')
  S:answer(S.npc,p,7321,8,'');check(Pet.GetSkill(first,0)==id,'bank forget cancellation preserves skill')
  skillClick('confirm');S:answer(S.npc,p,7321,4,'')
  check(Pet.GetSkill(first,0)<0 and Char.GetGold(p)==gold-1000,'native bank forgetting removes original skill for free')
  S:show(S.npc,p,'petHome',1,9,Pet.GetUUID(first));skillClick('learning');skillClick('learnConfirm')
  bank[4]=last;S:answer(S.npc,p,7322,4,'')
  check(Pet.GetSkill(first,0)<0 and Pet.GetSkill(last,0)<0 and Char.GetGold(p)==gold-1000,'bank replacement rejects stale learning and charge')
  bank[4]=nil;S:show(S.npc,p,'bankPets');rows(S.sessions[p])
  check(#S.sessions[p].actions==5,'empty bank slot omitted safely')
  local foreign=Char.CreateDummy({mapType=0,floor=1000,x=223,y=86,image=100002,name='BANK_FOREIGN'})
  local alien=Char.GivePet(foreign,3004,1)
  check(not S:learnPet(S.npc,p,9,Pet.GetUUID(alien),id),'foreign UUID cannot resolve an empty bank slot')
  Char.DelDummy(foreign)
  R.npcs={{module='autoStat'},{module='petSkillTutor'}}
 end,debug.traceback)
 finish(not ok and err or nil)
end,0)
