  local library=getModule('skillLibrary')
  local skills=dofile('lua/Modules/skillLibraryData.lua').skills
  for jid=11,17 do
    set(owner,'CHAR_职业',jid)
    for _,s in ipairs(skills) do
      check(Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(s.id),jid)==30,'swordsman native permission '..jid..'/'..s.id)
      check(library:allowed(owner,s.id),'swordsman library permission '..jid..'/'..s.id)
    end
  end
  set(owner,'CHAR_职业',17)
  set(owner,'CHAR_职类ID',10)
  set(owner,'CHAR_职阶',6)
  set(owner,'CHAR_账号','SWORDSMAN_ISOLATED_PROBE')
  Char.SetData(owner,CONST.对象_RegistNumber,0)
  set(owner,'CHAR_金币',100000000)
  Char.SetExtData(owner,'SkillLibraryV1','')
  library.cache[owner]=nil
  SQL.QueryEx('DELETE FROM hook_charaext WHERE cdKey=? AND regNo=? AND sKey=?','SWORDSMAN_ISOLATED_PROBE',0,'SkillLibraryV1')
  for _,s in ipairs(skills) do
    local ok,message=library:learn(owner,s.id)
    check(ok,'swordsman actual learning '..s.id..': '..tostring(message))
  end
  -- Exercise a profession-specific recipe skill through its actual Lua handler.
  local slot=Char.AddSkill(owner,2226,0,0)
  check(slot>=0,'swordsman equips refinement skill')
  Char.SetSkillLevel(owner,slot,2,0)
  local before=Char.GetSkillExp(owner,slot)
  getModule('cg71JobSkills'):train(owner,2226,40)
  check(Char.GetSkillExp(owner,slot)>before,'swordsman profession skill is usable and earns experience')
  R.swordsman_skills=#skills
  R.swordsman_jobs=7
  library.cache[owner]=nil
  Char.SetExtData(owner,'SkillLibraryV1',nil)
  SQL.QueryEx('DELETE FROM hook_charaext WHERE cdKey=? AND regNo=? AND sKey=?','SWORDSMAN_ISOLATED_PROBE',0,'SkillLibraryV1')
