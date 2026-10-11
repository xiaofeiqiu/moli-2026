-- Verify ordinary pet ranks through real native tutor menus and pet APIs.
local R={status='RUNNING',checks={},npcs={},production_accounts_used=false}
local p,pet=-1,-1
local function check(ok,name) R.checks[#R.checks+1]={name=name,pass=not not ok};assert(ok,name) end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  local M=assert(getModule('petSkillTutor'));local n=M.npc
  p=Char.CreateDummy({mapType=0,floor=60003,x=30,y=19,image=100002,name='PET_QIGONG_TEST'})
  check(p>=0,'isolated dummy');Char.AddGold(p,100000)
  pet=Char.GivePet(p,3004,1);check(pet>=0,'native pet')
  for i=9,0,-1 do if Pet.GetSkill(pet,i)>=0 then Pet.DelSkill(pet,i) end end
  local uuid=Pet.GetUUID(pet);local list=M:lessons('physical');local found={}
  for _,s in ipairs(list) do found[s.id]=s end
  for rank=1,10 do
   local id=910399+rank;local tx=Tech.GetTechIndex(id);local source=Tech.GetTechIndex(399+rank)
   check(tx>=0 and source>=0,'native rank '..rank)
   check(Tech.GetData(tx,CONST.TECH_FUNCNAME)=='TECH_SpiracleShot','native handler '..rank)
   check(Tech.GetData(tx,CONST.TECH_FORCEPOINT)==rank*5,'ordinary MP '..rank)
   check(Tech.GetData(tx,CONST.TECH_NECESSARYLV)==30,'pet marker '..rank)
   check(found[id] and found[id].cost==1000,'physical tutor catalog '..rank)
   local position;for i,s in ipairs(list) do if s.id==id then position=i end end
   M:show(n,p,'learning',math.ceil(position/5),0,uuid,nil,'physical')
   local action;for i,a in ipairs(M.sessions[p].actions) do if a.id==id then action=i end end
   check(action~=nil,'rank selectable '..rank)
   M:answer(n,p,7320,0,tostring(action))
   check(M.sessions[p].kind=='learnConfirm' and M.sessions[p].id==id,'rank confirmation '..rank)
   local gold=Char.GetGold(p);M:answer(n,p,7322,4,'')
   check(Pet.GetSkill(pet,0)==id and Char.GetGold(p)==gold-1000,'rank learned with exact fee '..rank)
   check(not M:learnPet(n,p,0,uuid,id) and Char.GetGold(p)==gold-1000,'duplicate free '..rank)
   check(M:forget(n,p,0,uuid,0,id) and Pet.GetSkill(pet,0)<0,'rank forgotten '..rank)
  end
  local five=assert(getModule('fivePet'))
  check(five~=nil,'five pet module loaded')
 end,debug.traceback)
 if p>=0 then for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end;pcall(Char.DelDummy,p) end
 R.status=ok and 'PASS' or 'FAIL';R.error=not ok and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end,0)
