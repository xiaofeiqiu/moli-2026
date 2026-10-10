local native=dofile('lua/shared_native_data.lua')
local R={state='RUNNING',manifest_sha256=native.manifest_sha256,production_accounts_used=false,jobs={},items={},recipes=0}
local path='../../../../../docs/cg71_content_audit/shared_integration/native_services_result.json'
local function write() local f=assert(io.open(path,'w'));f:write(JSON.encode(R));f:close() end
local function get(p,k) local f=assert(CONST[k],k);return Char.GetData(p,f) end
local function set(p,k,v) local f=assert(CONST[k],k);Char.SetData(p,f,v) end
local function dummy(name)
 local p=Char.CreateDummy({mapType=0,floor=1000,x=158,y=111,image=100002,name=name})
 assert(p>=0);set(p,'CHAR_道具栏',28);set(p,'CHAR_血',10000);set(p,'CHAR_最大血',10000)
 return p
end
local function give(p,id,q)
 local before=Char.ItemNum(p,id)
 for i=1,q do if Char.ItemNum(p,id)<before+q then Char.GiveItem(p,id,before+q-Char.ItemNum(p,id),false) end end
 assert(Char.ItemNum(p,id)>=before+q,'fixture missing item '..id)
end
write()
Cron.AddInterval(1000,function()
 local ok,why=pcall(function()
  local m=assert(loadModule('sharedTaskAdapters'))
  local D=dofile('lua/Modules/sharedTaskAdaptersData.lua')
  local service;for _,c in ipairs(D) do if c.key=='stp:services' then service=c end end
  assert(service and m.services>=0)
  for i,c in ipairs(service.jobs) do
   local p=dummy('PROFESSION_'..i)
   set(p,'CHAR_等级',19);set(p,'CHAR_金币',1000000)
   assert(m:joinJob(p,c)==0,'underlevel job accepted')
   set(p,'CHAR_等级',180);set(p,'CHAR_金币',4999)
   assert(m:joinJob(p,c)==0,'underfunded job accepted')
   set(p,'CHAR_金币',1000000);local before=Char.GetGold(p)
   assert(m:joinJob(p,c)==1 and get(p,'CHAR_职业')==c.ranks[1].id and get(p,'CHAR_职类ID')==c.family,'job registration failed')
   assert(Char.GetGold(p)==before-5000,'wrong registration charge')
   before=Char.GetGold(p);assert(m:joinJob(p,c)==0 and Char.GetGold(p)==before,'duplicate registration charged')
   local r={family=c.family,ranks=1};R.jobs[#R.jobs+1]=r
   for j=2,#c.ranks do
    local next=c.ranks[j];set(p,'CHAR_金币',math.max(1000000,next.cost+5000));set(p,'CHAR_声望',math.max(1000000,next.fame))
    local skills={}
    for _,need in ipairs(next.need) do
     local slot=Char.HaveSkill(p,need[1]);if slot<0 then slot=Char.AddSkill(p,need[1],0,0) end
     assert(slot>=0,'promotion skill not learnable '..need[1])
     Char.SetSkillLevel(p,slot,math.max(1,need[2]),0)
     assert(Char.GetSkillLevel(p,slot)>=need[2],'promotion skill cap below requirement '..need[1])
     skills[#skills+1]=need[1]
    end
    before=Char.GetGold(p)
    R.promotion={target=next,current=get(p,'CHAR_职业'),level=get(p,'CHAR_等级'),fame=get(p,'CHAR_声望'),gold=before};write()
    assert(m:promote(p)==1 and get(p,'CHAR_职业')==next.id and get(p,'CHAR_职阶')==j-1,'promotion failed '..next.id)
    assert(Char.GetGold(p)==before-next.cost,'promotion charge mismatch')
    r.ranks=r.ranks+1;write()
    for _,id in ipairs(skills) do Char.DelSkill(p,id,0) end
   end
   assert(m:promote(p)==0,'promotion past maximum')
   Char.DelDummy(p)
  end
  -- Actual item effects: every adapter must consume one item only on success.
  for _,c in ipairs(D) do if c.kind=='item' then
   local p=dummy('ITEM_EFFECT_'..#R.items);set(p,'CHAR_等级',100)
   local pet=-1
   if c.itemMode=='petSkill' or c.itemMode=='rebirth' or c.itemMode=='petExperience' then
    assert(Char.GivePet(p,1)>=0);pet=Char.GetPet(p,0);assert(pet>=0)
    set(pet,'CHAR_等级',50);set(pet,'CHAR_经验',0)
    if c.itemMode=='petSkill' then for s=9,0,-1 do Pet.DelSkill(pet,s) end end
   end
   give(p,c.useItem,1)
   local qty=Char.ItemNum(p,c.useItem);local who=c.itemMode=='petExperience' and pet or p
   local xp=get(who,'CHAR_经验');local pets=Char.PetNum(p)
   local r={key=c.key,mode=c.itemMode};R.items[#R.items+1]=r
   r.result=m:execute(-1,p,c.key);write()
   assert(r.result==1,'item effect rejected '..c.itemMode)
   assert(Char.ItemNum(p,c.useItem)==qty-1,'item not consumed')
   if c.itemMode=='experience' or c.itemMode=='petExperience' then assert(get(who,'CHAR_经验')==xp+10000,'experience not credited') end
   if c.itemMode=='petSkill' then local found=false;for s=0,9 do if Pet.GetSkill(pet,s)==c.tech then found=true end end;assert(found,'pet skill not installed') end
   if c.itemMode=='rebirth' then assert(get(pet,'CHAR_等级')==1,'pet not reset') end
   if c.itemMode=='pet' then assert(Char.PetNum(p)==pets+1,'egg did not hatch') end
   if c.itemMode=='warp' then assert(get(p,'CHAR_地图')==c.warp[2],'scroll destination wrong') end
   assert(m:execute(-1,p,c.key)==0,'unowned item reused')
   for slot=0,4 do if Char.GetPet(p,slot)>=0 then Char.DelSlotPet(p,slot) end end
   Char.DelDummy(p)
  end end
  -- Exercise the live recipe menu for each imported crafting skill. An
  -- eligible installed job is selected using the native cap query.
  local groups={}
  for _,r in ipairs(service.recipes) do groups[r.skill]=groups[r.skill] or {};table.insert(groups[r.skill],r) end
  for skill,recipes in pairs(groups) do
   local p=dummy('RECIPES_'..skill);set(p,'CHAR_等级',200)
   local wanted=1;for _,r in ipairs(recipes) do wanted=math.max(wanted,r.level) end
   local job,max=1,0
   for _,id in ipairs(native.allJobs) do
    local cap=Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(skill),id)
    if cap>max then job,max=id,cap end
   end
   for _,id in ipairs({217,227,357,367,17,37}) do
    local cap=Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(skill),id)
    if cap>max then job,max=id,cap end
   end
   assert(max>=wanted,'no job can use recipe skill '..skill..' level '..wanted..' cap '..max)
   set(p,'CHAR_职业',job)
   local slot=Char.AddSkill(p,skill,0,0);assert(slot>=0,'recipe skill failed')
   Char.SetSkillLevel(p,slot,wanted,0);assert(Char.GetSkillLevel(p,slot)>=wanted)
   m.serviceSessions[p]={npc=m.services,expires=os.time()+90,actions={{kind='recipes'}}}
   m:serviceAnswer(m.services,p,7292,0,'1')
   for _,r in ipairs(recipes) do assert(Recipe.HasRecipe(p,r.id)==1,'recipe not unlocked '..r.id);R.recipes=R.recipes+1 end
   Char.DelDummy(p);write()
  end
 end)
 R.state=ok and 'PASS' or 'FAIL';if not ok then R.exception=tostring(why) end;write()
end,0)
