local D=dofile('lua/Modules/skillLibraryData.lua')
local M=getModule('skillLibrary')
local old=getModule('cg71JobSkills')
local checks=0;local owner=-1
local counts={skills=0,tech30=0,library=0}
local path='../../../../docs/skill_library/native_result.json'
local function C(k) local v=CONST[k];assert(v,k);return v end
local function check(v,msg) assert(v,msg);checks=checks+1 end
local function get(p,k) return Char.GetData(p,C(k)) end
local function set(p,k,v) Char.SetData(p,C(k),v) end
local function make(jid)
  local p=Char.CreateDummy({mapType=0,floor=1000,x=153,y=111,image=100002,name='LIBRARY_TEST_ONLY'})
  check(p>=0,'native dummy')
  set(p,'CHAR_职业',jid);set(p,'CHAR_职类ID',math.floor(jid/10)*10);set(p,'CHAR_职阶',jid%10-1)
  set(p,'CHAR_等级',200);set(p,'CHAR_技能栏',15)
  Char.AddGold(p,1000000);NLG.UpChar(p)
  Char.SetExtData(p,'SkillLibraryV1',nil);M.cache[p]=nil
  SQL.QueryEx('DELETE FROM hook_charaext WHERE cdKey=? AND regNo=? AND sKey=?',get(p,'CHAR_账号'),Char.GetData(p,CONST.对象_RegistNumber),'SkillLibraryV1')
  return p
end
local function cleanup()
  if owner>=0 then
    if Char.GetBattleIndex(owner)>=0 then Battle.ExitBattle(owner) end
    Char.SetExtData(owner,'SkillLibraryV1',nil);M.cache[owner]=nil
    SQL.QueryEx('DELETE FROM hook_charaext WHERE cdKey=? AND regNo=? AND sKey=?',get(owner,'CHAR_账号'),Char.GetData(owner,CONST.对象_RegistNumber),'SkillLibraryV1')
    for slot=0,4 do if Char.GetPet(owner,slot)>=0 then Char.DelSlotPet(owner,slot) end end
    Char.DelDummy(owner);owner=-1
  end
end
local ok,err=pcall(function()
  check(M~=nil and old~=nil,'modules')
  check(Map.IsWalkable(0,1000,153,111)==1,'library approach')
  local jobs={};for id=1,1100 do if Data.GetJobIndex(id)>=0 then jobs[#jobs+1]=id end end
  for _,s in ipairs(D.skills) do
    local ix=Skill.GetSkillIndex(s.id)
    check(ix>=0,'native skill '..s.id)
    check(Skill.GetData(ix,CONST.SKILL_DEFAULTMAXLEVEL)==30,'default level30 '..s.id)
    local tx=Tech.GetTechIndex(s.tech30)
    check(tx>=0 and Tech.GetData(tx,CONST.TECH_SKILLID)==s.id and Tech.GetData(tx,CONST.TECH_NECESSARYLV)==30,'native tech30 '..s.id)
    local job=nil
    for _,jid in ipairs(jobs) do if Skill.GetMaxSkillLevelOfJob(ix,jid)==30 then job=jid;break end end
    check(job~=nil,'permitted job '..s.id)
    owner=make(job)
    local slot=Char.AddSkill(owner,s.id,0,0);check(slot>=0,'add native '..s.id)
    if s.id==0 then
      local trace={}
      for _,lv in ipairs({1,5,10,15,16,20,29,30}) do
        local ret=Char.SetSkillLevel(owner,slot,lv,0)
        trace[#trace+1]={requested=lv,returned=ret,level=Char.GetSkillLevel(owner,slot),exp=Char.GetSkillExp(owner,slot)}
      end
      Char.SetSkillLevel(owner,slot,29,0);Char.SetSkillExp(owner,slot,100000000,0)
      trace[#trace+1]={auto_level=Char.GetSkillLevel(owner,slot),auto_exp=Char.GetSkillExp(owner,slot)}
      local f=assert(io.open('../../../../docs/skill_library/native_trace.json','w'));f:write(JSON.encode(trace));f:close()
    end
    Char.SetSkillLevel(owner,slot,30,0)
    check(Char.GetSkillLevel(owner,slot)==30,'stored level30 '..s.id)
    local xp=Char.GetSkillExp(owner,slot)
    check(xp>=0,'native experience30 '..s.id..' got='..tostring(xp))
    counts.skills=counts.skills+1;counts.tech30=counts.tech30+1
    cleanup()
  end
  for jid=31,37 do for _,id in ipairs(D.mage_skills) do check(Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(id),jid)==30,'knight mage permission '..jid..'/'..id) end end
  for jid=31,37 do for _,id in ipairs(D.knight_extra) do check(Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(id),jid)==30,'knight pet/boss permission '..jid..'/'..id) end end
  owner=make(37)
  local gold=Char.GetGold(owner)
  for _,id in ipairs(D.mage_skills) do
    local learned,why=M:learn(owner,id);check(learned,'archive learn '..id..' '..tostring(why))
  end
  for _,id in ipairs(D.monster_skills) do local learned,why=M:learn(owner,id);check(learned,'pet/boss archive '..id..' '..tostring(why)) end
  local b=M:read(owner);local n=0;for _ in pairs(b.skills) do n=n+1 end
  check(n==#D.mage_skills+#D.monster_skills and n>15,'archive beyond 15')
  check(#M:active(owner)==0,'learning does not overwrite active skills')
  local beforeGold=Char.GetGold(owner)
  check(not M:learn(owner,19),'duplicate learning rejected');check(Char.GetGold(owner)==beforeGold,'duplicate no fee')
  local ids={};for i=1,15 do ids[i]=D.mage_skills[i] end
  check(M:loadout(owner,ids),'15 skill loadout')
  check(#M:active(owner)==15,'all active slots')
  local slot=Char.HaveSkill(owner,19)
  if slot<0 then check(M:equip(owner,19,1),'equip spell');slot=Char.HaveSkill(owner,19) end
  Char.SetSkillLevel(owner,slot,17,0)
  local xp=Char.GetSkillExp(owner,slot)+123;Char.SetSkillExp(owner,slot,xp,0)
  check(M:profile(owner,'SPELLS'),'save profile')
  check(M:unequip(owner,19),'unequip spell')
  check(Char.HaveSkill(owner,19)<0,'spell absent from active list')
  b=M:read(owner);check(b.skills['19'].level==17 and b.skills['19'].exp==xp,'archive exact progression')
  M.cache[owner]=nil;b=M:read(owner)
  check(b.skills['19'].level==17 and b.skills['19'].exp==xp,'native ExtData reload')
  check(M:loadout(owner,b.profiles.SPELLS),'profile reload')
  slot=Char.HaveSkill(owner,19)
  check(slot>=0 and Char.GetSkillLevel(owner,slot)==17 and Char.GetSkillExp(owner,slot)==xp,'restored exact progression')
  b=M:read(owner);b.skills['19'].exp=xp+500
  M:capture(owner,b);check(b.skills['19'].exp==xp,'active progress replaces a stale rollover counter')
  local snapshot=JSON.encode(M:active(owner))
  check(not M:loadout(owner,{19,19}),'duplicate loadout rejected')
  check(JSON.encode(M:active(owner))==snapshot,'preflight no mutation')
  local nativeRestore=M.restore;local failOnce=true
  M.restore=function(self,p,desired) if failOnce then failOnce=false;Char.DelSkill(p,desired[1].id,0);return false end;return nativeRestore(self,p,desired) end
  check(not M:loadout(owner,{19}),'injected partial apply failure')
  M.restore=nativeRestore
  check(JSON.encode(M:active(owner))==snapshot,'rollback restores exact native state')
  failOnce=true
  M.restore=function(self,p,desired) if failOnce then failOnce=false;Char.DelSkill(p,desired[1].id,0);error('injected native exception') end;return nativeRestore(self,p,desired) end
  check(not M:loadout(owner,{19}),'injected partial apply exception')
  M.restore=nativeRestore
  check(JSON.encode(M:active(owner))==snapshot and not M.busy[owner],'exception rollback and busy release')
  -- Simulate interruption after a prepared journal and partially removed set.
  b=M:read(owner);b.journal={before=M:active(owner),wanted={19}};check(M:persist(owner,b,false),'write recovery journal')
  for _,r in ipairs(M:active(owner)) do Char.DelSkill(owner,r.id,0) end
  M.cache[owner]=nil;check(M:ready(owner)~=nil,'recover journal')
  check(JSON.encode(M:active(owner))==snapshot,'journal recovery native state')
  b=M:read(owner);check(b.journal==nil,'journal cleared')
  local save=M.persist
  M.persist=function() return false,'injected persistence failure' end
  check(not M:loadout(owner,{19}),'persistence failure refuses switching')
  check(JSON.encode(M:active(owner))==snapshot,'save failure does not delete active skills')
  M.persist=save
  counts.library=n
  -- Real custom passive training at both ends of the extended experience table.
  check(M:loadout(owner,{2204}),'passive loadout')
  slot=Char.HaveSkill(owner,2204)
  local group=Skill.GetData(Skill.GetSkillIndex(2204),CONST.SKILL_EXPTABLE)
  Char.SetSkillLevel(owner,slot,1,0)
  local required=D.experience[group][2]
  old:train(owner,2204,required+7)
  check(Char.GetSkillLevel(owner,slot)==2 and Char.GetSkillExp(owner,slot)==7,'passive level1 to2')
  Char.SetSkillLevel(owner,slot,29,0)
  local trace={before_level=Char.GetSkillLevel(owner,slot),before_exp=Char.GetSkillExp(owner,slot),required=D.experience[group][30],cap=Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(2204),37),group=group}
  old:train(owner,2204,D.experience[group][30])
  trace.after_level=Char.GetSkillLevel(owner,slot);trace.after_exp=Char.GetSkillExp(owner,slot)
  local tf=assert(io.open('../../../../docs/skill_library/passive_trace.json','w'));tf:write(JSON.encode(trace));tf:close()
  check(Char.GetSkillLevel(owner,slot)==30 and Char.GetSkillExp(owner,slot)==1,'passive level29 to30')
  old:train(owner,2204,100000000)
  check(Char.GetSkillLevel(owner,slot)==30,'passive maximum cap')
  check(M:profile(owner,'PASSIVE30'),'save passive progression')
  -- ExtData uses real native SQL persistence, with an isolated test identity.
  set(owner,'CHAR_账号','SKILL_LIBRARY_SQL_TEST')
  Char.SetData(owner,CONST.对象_RegistNumber,0)
  check(M:persist(owner,M:read(owner),false),'persist archive to test identity')
  local saved=Char.SaveToDb(owner)
  local sql=SQL.QueryEx('SELECT val FROM hook_charaext WHERE cdKey=? AND regNo=? AND sKey=?','SKILL_LIBRARY_SQL_TEST',0,'SkillLibraryV1')
  local sf=assert(io.open('../../../../docs/skill_library/sql_trace.json','w'));sf:write(JSON.encode({save_return=saved,query_status=sql.status,rows=sql.rows and #sql.rows or 0,bytes=sql.rows and sql.rows[1] and #sql.rows[1].val or 0,dummy=Char.IsDummy(owner)}));sf:close()
  check(sql.status==0 and sql.rows and #sql.rows==1,'native database archive row')
  local disk=JSON.decode(sql.rows[1].val)
  check(disk.skills['19'].level==17 and disk.skills['19'].exp==xp and disk.skills['2204'].level==30 and #disk.profiles.SPELLS==15,'SQL persisted exact archive/profile')
  counts.persistence={row=true,save_return=saved,skills=n}
  local witness=JSON.decode(JSON.encode(disk));witness.pack_sha256='__PACK_SHA256__'
  local wr=SQL.QueryEx('REPLACE INTO hook_charaext(cdKey,regNo,sKey,val,valType) VALUES(?,?,?,?,?)','LIBRARY_PERSIST_WITNESS',0,'SkillLibraryV1',JSON.encode(witness),0)
  check(wr.status==0 and wr.effectRows==1,'cross-process persistence witness')
  -- Refuse any switch during native battle.
  local battle=Battle.PVE(owner,owner,nil,{1},{1},{0});check(battle>=0,'native battle')
  check(not M:loadout(owner,{19}),'battle loadout denied')
  Battle.ExitBattle(owner)
  cleanup()
end)
cleanup()
local f=assert(io.open(path,'w'));f:write(JSON.encode({result=ok and 'PASS' or 'FAIL',error=ok and '' or tostring(err),checks=checks,counts=counts,pack_sha256='__PACK_SHA256__',isolated=true,client_verified=false}));f:close()
print('[SKILL_LIBRARY_PROBE] '..(ok and 'PASS' or tostring(err)))
