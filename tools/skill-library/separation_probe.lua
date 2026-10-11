-- Verify occupation NPCs, ten-row BOSS menus, and separate pet teaching.
local R={status='RUNNING',checks={},npcs={},windows=0,production_accounts_used=false}
local D=dofile('lua/Modules/skillTrainingData.lua');local J=dofile('lua/Modules/jobTutorData.lua')
local p,pet=-1,-1;local window
local original=NLG.ShowWindowTalked
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function set(q,k,v) return Char.SetData(q,assert(CONST[k],k),v) end
local function check(v,name) R.checks[#R.checks+1]={name=name,pass=not not v};assert(v,name) end
NLG.ShowWindowTalked=function(q,n,kind,buttons,seq,data,...)
 if q==p then window={npc=n,kind=kind,buttons=buttons,seq=seq,data=data};R.windows=R.windows+1 end
 return original(q,n,kind,buttons,seq,data,...)
end
local function rows(limit)
 check(window and window.kind==2,'selection window')
 local lines={};for line in (window.data:gsub('\\n','\n')..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
 local header=assert(tonumber(lines[1]));local out={}
 for i=header+2,#lines do if lines[i]~='' then out[#out+1]=lines[i] end end
 check(#out<=limit,'selection count within '..limit);return out
end
local function click(m,index,button,text)
 local w=assert(window);window=nil
 _G[m.name..'_npc_'..w.npc..'_WindowTalkedEvent'](w.npc,p,w.seq,button or 0,text or tostring(index))
end
local function reach(n) check(Char.Warp(p,0,get(n,'CHAR_地图'),get(n,'CHAR_X'),get(n,'CHAR_Y')+1),'reach tutor') end
local function occupied(n)
 local _,objects=Obj.GetObject(0,get(n,'CHAR_地图'),get(n,'CHAR_X'),get(n,'CHAR_Y'));local count=0
 for _,o in ipairs(objects or {}) do if Obj.GetType(o)==1 then count=count+1 end end
 return count
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  local M=assert(getModule('skillTraining'));local L=assert(getModule('skillLibrary'));local P=assert(getModule('petSkillTutor'))
  check(#J.tutors==65 and #M.npcList==#J.tutors+1,'65 occupation tutors and one BOSS tutor, no internal portals')
  check(M.learnPet==nil,'player tutors have no pet teaching API')
  p=Char.CreateDummy({mapType=0,floor=60003,x=24,y=15,image=100002,name='TUTOR_SEPARATION_TEST'})
  check(p>=0,'isolated dummy character');set(p,'CHAR_等级',200);set(p,'CHAR_技能栏',15);Char.AddGold(p,500000)
  check(M.entrance==nil and M.exit==nil and M.travel==nil,'internal tutor portals removed')
  local rowY={production=10,physical=14,magic=18};local counts={}
  for _,t in ipairs(J.tutors) do
   local i=counts[t.group] or 0;counts[t.group]=i+1
   check(t.map==60003 and t.y==rowY[t.group] and t.x==16+i*2,'group row and one empty tile '..t.name)
  end
  check(counts.production==35 and counts.physical==21 and counts.magic==9,'all occupations assigned to three rows')
  local blocked={};local families={};local tutorCount=0
  for n,t in pairs(M.categories) do
   check(occupied(n)==1,'no overlap '..t.name);check(Map.IsWalkable(0,get(n,'CHAR_地图'),get(n,'CHAR_X'),get(n,'CHAR_Y'))==1,'walkable tutor '..t.name)
   R.npcs[#R.npcs+1]={name=t.name,module=M.name,floor=get(n,'CHAR_地图'),x=get(n,'CHAR_X'),y=get(n,'CHAR_Y')}
   if t.kind=='job' then
    tutorCount=tutorCount+1;check(not families[t.family],'one NPC for occupation '..t.family);families[t.family]=true
    check(get(n,'CHAR_地图')==J.floor,'occupation tutor in sanctuary');blocked[t.x..','..t.y]=true
    set(p,'CHAR_职业',t.jobs[1]);set(p,'CHAR_职类ID',t.family);reach(n)
    M:show(n,p,'home');local labels=rows(8)
    check(#labels==6 and labels[1]=='本职业：全部技能','occupation-only home '..t.name)
    for _,label in ipairs(labels) do check(not label:find('宠物',1,true),'no pet action on occupation tutor') end
    click(M,1);local list=M:list(p,t.id,'all','player')
    for _,s in ipairs(list) do
     check(s.source~='pet' and s.source~='boss','occupation list excludes pet and BOSS '..s.id)
     local licensed=false
     for _,job in ipairs(t.jobs) do if Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(s.id),job)>0 then licensed=true;break end end
     check(licensed,'listed skill belongs to occupation '..t.family..'/'..s.id)
    end
    local visible={};for _,s in ipairs(list) do visible[s.id]=true end
    for _,s in ipairs(D.players) do
     if s.source~='pet' and s.source~='boss' then
      local licensed=false;for _,job in ipairs(t.jobs) do if Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(s.id),job)>0 then licensed=true;break end end
      check(not not visible[s.id]==licensed,'complete occupation catalog '..t.family..'/'..s.id)
     end
    end
   end
  end
  check(tutorCount==#J.tutors,'every occupation has its own NPC')
  -- Prove routes from the landing point while treating NPCs as occupied.
  blocked['34,18']=true;blocked['36,18']=true
  local queue={J.arrival};local seen={[J.arrival.x..','..J.arrival.y]=true};local at=1
  while queue[at] do local point=queue[at];at=at+1
   for _,dir in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do local x,y=point.x+dir[1],point.y+dir[2];local key=x..','..y
    if not seen[key] and not blocked[key] and Map.IsWalkable(0,J.floor,x,y)==1 then seen[key]=true;queue[#queue+1]={x=x,y=y} end
   end
  end
  for _,t in ipairs(J.tutors) do check(seen[t.x..','..(t.y+1)],'connected route to '..t.name) end
  set(p,'CHAR_职业',181);set(p,'CHAR_职类ID',180)
  local jobTutor
  for n,t in pairs(M.categories) do if t.family==180 then jobTutor=n end end
  local rejected=0;reach(jobTutor);local gold=Char.GetGold(p)
  local book=L:ready(p);local before=JSON.encode(book)
  for _,s in ipairs(D.players) do if s.source=='pet' then
   rejected=rejected+1
   check(not L:allowed(p,s.id),'archive excludes pet '..s.id)
   check(not L:learn(p,s.id) and not M:learnPlayer(jobTutor,p,s.id),'both human learning APIs reject pet '..s.id)
   for _,t in ipairs(J.tutors) do for _,job in ipairs(t.jobs) do
    check(Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(s.id),job)==0,'native pet exclusion '..job..'/'..s.id)
   end end
  end end
  check(rejected==308 and Char.GetGold(p)==gold and JSON.encode(L:ready(p))==before,'all pet-source records rejected without gold or archive mutation')
  -- Existing archived pet copies are retained but cannot be equipped or loaded.
  book.skills['4000']={id=4000,level=1,exp=0}
  check(not L:equip(p,4000,1) and not L:loadout(p,{4000}),'legacy pet copies cannot bypass equipment restrictions')
  book.skills['4000']=nil
  reach(M.boss);M:show(M.boss,p,'home');local boss=M:list(p,'boss','all','player');local labels=rows(10)
  check(#boss==139 and #labels==10 and #M.sessions[p].actions==10,'BOSS first page contains exactly ten skill options')
  check(window.buttons==34,'BOSS first page exposes native next and close buttons')
  local id=M.sessions[p].actions[10].id;check(id==boss[10].id,'tenth displayed skill has tenth action')
  click(M,10);check(window.kind==0 and window.seq==7311 and M.sessions[p].id==id,'tenth BOSS option opens its own confirmation')
  click(M,nil,8,'');check(#rows(10)==10 and M.sessions[p].page==1,'BOSS cancel returns to same ten-row page')
  click(M,nil,32,'');check(M.sessions[p].page==2 and #rows(10)==10,'BOSS native next button')
  click(M,nil,16,'');check(M.sessions[p].page==1 and #rows(10)==10,'BOSS native previous button')
  M:show(M.boss,p,'player',14,'all');check(#rows(10)==9 and window.buttons==18,'last BOSS page has nine remaining skills and previous button')
  M:show(M.boss,p,'player',1,'all');click(M,10);click(M,nil,4,'')
  check(L:ready(p).skills[tostring(id)]~=nil and Char.GetGold(p)==gold-boss[10].cost,'tenth BOSS confirmation learns correct skill with exact fee '..id..' gold '..Char.GetGold(p)..' expected '..(gold-boss[10].cost)..' archived '..tostring(L:ready(p).skills[tostring(id)]~=nil))
  reach(jobTutor);check(not M:learnPlayer(jobTutor,p,boss[11].id),'BOSS skills are unavailable from occupation tutors')
  reach(M.boss);check(not M:learnPlayer(M.boss,p,196),'BOSS tutor rejects ordinary player skills')
  pet=Char.GivePet(p,3004,1);check(pet>=0,'native pet for separated teaching')
  for i=9,0,-1 do if Pet.GetSkill(pet,i)>=0 then Pet.DelSkill(pet,i) end end
  reach(P.npc);P:show(P.npc,p,'pets');click(P,1);local petLabels=rows(8)
  check(#petLabels==7 and petLabels[1]=='学习物理技能' and petLabels[6]=='遗忘宠物技能','pet tutor has five lesson categories plus forgetting')
  click(P,1);local lesson=P.sessions[p].actions[1].id;click(P,1)
  check(window.kind==0 and window.seq==7322,'pet lesson uses native confirmation')
  local cost=Char.GetGold(p);click(P,nil,8,'');check(Char.GetGold(p)==cost and #P:skills(pet)==0,'pet learning cancel does not mutate')
  click(P,1);click(P,nil,4,'')
  check(Pet.GetSkill(pet,0)==lesson and Char.GetGold(p)==cost-1000,'separate pet tutor teaches native ID at ordinary fee')
  check(not P:learnPet(P.npc,p,0,Pet.GetUUID(pet),lesson) and Char.GetGold(p)==cost-1000,'duplicate pet learning is free')
  check(not P:learnPet(M.boss,p,0,Pet.GetUUID(pet),lesson),'pet API cannot use a human NPC')
  reloadModule('skillTraining');M=getModule('skillTraining')
  check(#M.npcList==#J.tutors+1 and M.sessions[p]==nil,'occupation module reload preserves exact NPC count and discards sessions')
  for _,n in ipairs(M.npcList) do check(occupied(n)==1,'no duplicate after reload') end
 end,debug.traceback)
 NLG.ShowWindowTalked=original
 if p>=0 then for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end;pcall(Char.DelDummy,p) end
 R.status=ok and 'PASS' or 'FAIL';R.error=not ok and tostring(err) or nil
 local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
end,0)
