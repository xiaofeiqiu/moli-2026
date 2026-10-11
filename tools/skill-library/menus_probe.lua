-- Decode displayed native selection rows before invoking registered callbacks.
-- Previous probes used session indices directly and missed title-line offsets.
local R={status='RUNNING',checks={},npcs={},windows=0,production_accounts_used=false}
local p=-1
local originalWindow=NLG.ShowWindowTalked
local window
local function get(c,k) local field=assert(CONST[k],k);return Char.GetData(c,field) end
local function set(c,k,v) return Char.SetData(c,assert(CONST[k],k),v) end
local function check(ok,name)
 R.checks[#R.checks+1]={name=name,pass=not not ok};assert(ok,name)
end
local function normalize(s) return s:gsub('\r\n','\n'):gsub('\r','\n'):gsub('\\n','\n') end
local function split(s)
 local out={};for line in (normalize(s)..'\n'):gmatch('(.-)\n') do out[#out+1]=line end
 return out
end
NLG.ShowWindowTalked=function(player,n,kind,buttons,seq,data,...)
 if player==p then
  R.windows=R.windows+1;window={npc=n,seq=seq,data=data,kind=kind}
 end
 return originalWindow(player,n,kind,buttons,seq,data,...)
end
local function reach(n)
 local mapType,floor,x,y=get(n,'CHAR_地图类型'),get(n,'CHAR_地图'),get(n,'CHAR_X'),get(n,'CHAR_Y')
 for radius=1,2 do
 for dx=-radius,radius do for dy=-radius,radius do if math.max(math.abs(dx),math.abs(dy))==radius then
  local count=Obj.GetObject(mapType,floor,x+dx,y+dy)
  if count==0 and Map.IsWalkable(mapType,floor,x+dx,y+dy)==1 then
   Char.Warp(p,mapType,floor,x+dx,y+dy)
   if get(p,'CHAR_地图')==floor and math.abs(get(p,'CHAR_X')-x)<=2 and math.abs(get(p,'CHAR_Y')-y)<=2 then
    check(true,'reach '..get(n,'CHAR_名字'));window=nil;return
   end
  end
 end end end
 end
 check(false,'reachable NPC '..get(n,'CHAR_名字')..' at '..floor..'/'..x..'/'..y)
end
local function rows(expected,tag,limit)
 check(window~=nil,'selection shown '..tag)
 local lines=split(window.data);local headers=tonumber(lines[1])
 check(headers and headers>=1,'title header '..tag)
 local visible={}
 for i=headers+2,#lines do visible[#visible+1]=lines[i] end
 if visible[#visible]=='' then table.remove(visible) end
 check(#visible==#expected and #visible<=(limit or 8),'visible row count '..tag)
 for i,label in ipairs(expected) do
  check(visible[i]==normalize(label):gsub('\n',' '),'visible index '..i..' '..tag)
 end
 return visible
end
local function click(module,n,label,index)
 local lines=split(window.data);local headers=assert(tonumber(lines[1]));local choice=index
 if index then check(lines[headers+1+index]==label,'clicked displayed row')
 else for i=headers+2,#lines do if lines[i]==label then choice=i-headers-1;break end end end
 check(choice and choice>=1 and choice<=10,'client click '..label)
 local seq=window.seq;window=nil
 local callback=assert(_G[module..'_npc_'..n..'_WindowTalkedEvent'])
 callback(n,p,seq,0,tostring(choice))
end
local function training()
 local m=assert(getModule('skillTraining'));local lib=getModule('skillLibrary')
 for n,t in pairs(m.categories) do
  reach(n);R.npcs[#R.npcs+1]={module=m.name,name=t.name,index=n}
  local size=t.kind=='boss' and 10 or 5
  for _,source in ipairs(t.kind=='boss' and {'all'} or {'all','normal','quest'}) do
   local list=m:list(p,t.id,source,'player');local pages=math.max(1,math.ceil(#list/size))
   for page=1,pages do
    local expected={};local archive=lib:ready(p)
    for i=(page-1)*size+1,math.min(#list,page*size) do
     local s=list[i];local suffix=s.unavailable and '／暂不可学' or (archive.skills[tostring(s.id)] and '／已学' or (not lib:allowed(p,s.id) and '／职业受限' or ''))
     expected[#expected+1]=s.name..suffix
    end
    if t.kind~='boss' then
     if page>1 then expected[#expected+1]='上一页' end
     if page<pages then expected[#expected+1]='下一页' end
     expected[#expected+1]='返回主菜单'
    end
    m:show(n,p,'player',page,source);rows(expected,t.id..' '..source..' '..page,size==10 and 10 or 8)
    local count=math.min(size,#list-(page-1)*size)
    for choice=1,count do
     m:show(n,p,'player',page,source);click(m.name,n,expected[choice],choice)
     check(window.kind==0 and window.seq==7311 and m.sessions[p].id==list[(page-1)*size+choice].id,'correct confirmation '..t.id..'/'..page..'/'..choice)
     _G[m.name..'_npc_'..n..'_WindowTalkedEvent'](n,p,window.seq,8,'')
     check(m.sessions[p].kind=='player' and m.sessions[p].page==page,'confirmation cancel preserves page')
    end
   end
  end
 end
 local pet=Char.GivePet(p,3004,1);check(pet>=0,'native pet created')
 return pet
end
local function otherMenus(pet)
 local m=getModule('autoStat');local n=m.npc;reach(n)
 R.npcs[#R.npcs+1]={module=m.name,name=get(n,'CHAR_名字'),index=n}
 m:show(n,p)
 local session=m.sessions[p];local lines=split(window.data)
 check(tonumber(lines[1])==2,'auto stat two-line title preserved')
 check(#session.actions==8,'auto stat main action count including bank entry')
 click(m.name,n,lines[tonumber(lines[1])+2]);check(m.sessions[p].ref=='player','auto stat player callback')
 rows({'全加体力','全加力量','全加强度','全加速度','全加魔法','自定义五项比例','开启已保存方案','返回人物和宠物列表'},'auto stat player plan')
 check(tonumber(split(window.data)[1])==3,'auto stat three-line title preserved')
 click(m.name,n,'返回人物和宠物列表');check(not m.sessions[p].ref,'auto stat return callback')
 local f=getModule('fivePet');n=f.npc;reach(n)
 R.npcs[#R.npcs+1]={module=f.name,name=get(n,'CHAR_名字'),index=n}
 f:petMenu(p,pet)
 local labels={};for _,o in ipairs(f.menus[p].options) do labels[#labels+1]=o.label end
 rows(labels,'five pet AI');click(f.name,n,labels[5]);check(f.menus[p].kind=='skills','five pet skill callback')
 -- Fill ten valid native techniques so the five-pet skill menu has two pages.
 for i=0,9 do if Pet.GetSkill(pet,i)>=0 then Pet.DelSkill(pet,i) end end
 local d=dofile('lua/Modules/skillTrainingData.lua');local count=0
 for _,s in ipairs(d.pets) do if count<10 and f:tech(s.id) and Pet.AddSkill(pet,s.id)==1 then count=count+1 end end
 check(count==10,'ten native pet skills for AI pagination')
 for page=1,2 do
  f:skillMenu(p,pet,page);labels={};for _,o in ipairs(f.menus[p].options) do labels[#labels+1]=o.label end
  rows(labels,'five pet skills '..page);click(f.name,n,'下一页')
  check(f.menus[p].page==page%2+1,'five pet next-page callback '..page)
 end
 click(f.name,n,'返回');check(f.menus[p].kind=='pet','five pet return callback')
 local lib=getModule('skillLibrary');n=lib.npc;reach(n)
 R.npcs[#R.npcs+1]={module=lib.name,name=get(n,'CHAR_名字'),index=n}
 lib:show(p,'home');rows({'查看已学技能','学习本职技能','装配或替换技能','卸下技能','保存当前配装','加载配装','查看规则'},'library home')
 click(lib.name,n,'学习本职技能');check(lib.sessions[p].kind=='learn','library learn callback')
 local specs={};local total=0;local archive=lib:ready(p)
 for _,skill in ipairs(dofile('lua/Modules/skillLibraryData.lua').skills) do specs[skill.id]=skill end
 for _,skill in ipairs(d.library_additions) do specs[skill.id]=specs[skill.id] or skill end
 for id in pairs(specs) do if lib:allowed(p,id) and not archive.skills[tostring(id)] then total=total+1 end end
 for page=1,math.max(1,math.ceil(total/5)) do
  lib:show(p,'learn',page);local s=lib.sessions[p];labels={}
  -- Check each native row against the named skill ID stored in the session.
  for _,a in ipairs(s.actions) do
   labels[#labels+1]=a.kind=='learn' and specs[a.value].name..'（'..specs[a.value].cost..'金）'
    or a.kind=='back' and '返回主菜单' or a.value<page and '上一页' or '下一页'
  end
  rows(labels,'library learn '..page)
  if page<math.ceil(total/5) then click(lib.name,n,'下一页');check(lib.sessions[p].page==page+1,'library next-page callback') end
 end
 local jobs=getModule('cg71JobSkills')
 for _,npc in ipairs(jobs.npcList) do
  reach(npc);R.npcs[#R.npcs+1]={module=jobs.name,name=get(npc,'CHAR_名字'),index=npc}
  local cb=assert(_G[jobs.name..'_npc_'..npc..'_TalkedEvent']);cb(npc,p)
  local s=jobs.sessions[p]
  if s.family then rows({'就职（提交练习宠饰，5000金）','晋阶','学习本职制造（1000金）','学习宠物饰品制作（1000金）','学习宠装锻造体验（免费）','补领已达等级的配方','查看规则'},'pet craftsman')
  else
   set(p,'CHAR_职业',1);jobs:menu(npc,p,nil)
   rows({'打开永久技能库','查看职业与BOSS导师位置','查看宠装职业就职说明'},'unemployed profession guidance')
   check(tonumber(split(window.data)[1])==2,'profession guidance two-line title preserved')
   click(jobs.name,npc,'打开永久技能库');check(lib.sessions[p].kind=='home','profession guidance library callback')
   set(p,'CHAR_职业',31)
   jobs:menu(npc,p,nil);labels={}
   for _,id in ipairs(jobs.sessions[p].ids or {}) do
    for _,skill in ipairs(dofile('lua/Modules/cg71JobSkillsData.lua').skills) do if skill.id==id then labels[#labels+1]=skill.name..'（10000金）' end end
   end
   rows(labels,'employed advanced profession skills')
  end
 end
end
local function sharedMenus()
 local m=getModule('sharedTaskGuide');local n=m.guide;reach(n)
 R.npcs[#R.npcs+1]={module=m.name,name=get(n,'CHAR_名字'),index=n}
 local d=dofile('lua/Modules/sharedTaskGuideData.lua')
 for page=1,math.ceil(#d.tasks/6) do
  m:show(n,p,page);local labels={}
  for i=(page-1)*6+1,math.min(page*6,#d.tasks) do labels[#labels+1]=d.tasks[i].name end
  if page>1 then labels[#labels+1]='上一页' end
  if page*6<#d.tasks then labels[#labels+1]='下一页' end
  rows(labels,'task guide '..page)
  if page*6<#d.tasks then click(m.name,n,'下一页');check(m.sessions[p].page==page+1,'task guide next-page callback') end
 end
 for task,t in ipairs(d.tasks) do
  for page=1,math.max(1,math.ceil(#t.scenes/4)) do
   m:show(n,p,1,task,page);local labels={}
   if t.entry then labels[#labels+1]='前往任务接待地点' end
   for i=(page-1)*4+1,math.min(page*4,#t.scenes) do labels[#labels+1]='场景：'..t.scenes[i].name end
   if page>1 then labels[#labels+1]='上一页场景' end
   if page*4<#t.scenes then labels[#labels+1]='下一页场景' end
   labels[#labels+1]='返回任务目录';rows(labels,'task scenes '..task..'/'..page)
   click(m.name,n,'返回任务目录');check(m.sessions[p].page==1,'task guide return callback')
  end
 end
 m=getModule('sharedTaskRoutes');n=m.hub;reach(n)
 R.npcs[#R.npcs+1]={module=m.name,name=get(n,'CHAR_名字'),index=n}
 d=dofile('lua/Modules/sharedTaskRoutesData.lua')
 for page=1,math.ceil(#d/5) do
  m:show(n,p,0,page);local labels={}
  for i=(page-1)*5+1,math.min(page*5,#d) do labels[#labels+1]=d[i].destinations[1].name..'的通路' end
  if page>1 then labels[#labels+1]='上一页' end
  if page*5<#d then labels[#labels+1]='下一页' end
  rows(labels,'route catalogue '..page)
  if page*5<#d then click(m.name,n,'下一页');check(m.sessions[p].actions[1].route==page*5+1,'route catalogue next-page callback') end
 end
 for index,route in ipairs(d) do
  local npc=m.npcs[index];reach(npc)
  R.npcs[#R.npcs+1]={module=m.name,name=get(npc,'CHAR_名字'),index=npc}
  for page=1,math.ceil(#route.destinations/6) do
   m:show(npc,p,index,page);local labels={}
   for i=(page-1)*6+1,math.min(page*6,#route.destinations) do local v=route.destinations[i];labels[#labels+1]=v.name..'（'..v.floor..'）' end
   if page>1 then labels[#labels+1]='上一页' end
   if page*6<#route.destinations then labels[#labels+1]='下一页' end
   rows(labels,'route '..index..'/'..page)
  end
 end
 m=getModule('sharedTaskAdapters');n=m.services;reach(n)
 R.npcs[#R.npcs+1]={module=m.name,name=get(n,'CHAR_名字'),index=n}
 for _,v in ipairs(dofile('lua/Modules/sharedTaskAdaptersData.lua')) do if v.key=='stp:services' then d=v end end
 m:serviceMenu(n,p);rows({'自制职业登记（20级，5000魔币）','办理本职业晋阶','领取当前技能等级可用的配方','寻回遗失材料（20级单人试炼）'},'expedition services')
 for _,kind in ipairs({'jobs','materials'}) do
  for page=1,math.max(1,math.ceil(#d[kind]/5)) do
   m:serviceMenu(n,p,kind,page);local labels={}
   for i=(page-1)*5+1,math.min(page*5,#d[kind]) do labels[#labels+1]=d[kind][i].name end
   if page>1 then labels[#labels+1]='上一页' end
   if page*5<#d[kind] then labels[#labels+1]='下一页' end
   labels[#labels+1]='返回';rows(labels,'expedition '..kind..'/'..page)
   if kind=='jobs' then
    for i=(page-1)*5+1,math.min(page*5,#d.jobs) do
     m:serviceMenu(n,p,kind,page)
     click(m.name,n,d.jobs[i].name);rows({'确认登记：5000魔币','返回'},'job confirmation '..i)
     -- The client wraps long titles; protocol-only row decoding missed this.
     local titleLines=split(window.data);check(tonumber(titleLines[1])==4,'explicit confirmation title rows')
     for row=2,5 do check(#titleLines[row]<=24,'confirmation title fits client row '..row) end
     local job,family,gold=get(p,'CHAR_职业'),get(p,'CHAR_职类ID'),Char.GetGold(p)
     click(m.name,n,'返回');rows(labels,'job confirmation return '..i)
     check(m.serviceSessions[p].actions[1].index==(page-1)*5+1,'job confirmation returns to original page')
     check(get(p,'CHAR_职业')==job and get(p,'CHAR_职类ID')==family and Char.GetGold(p)==gold,'return preserves profession and gold')
     click(m.name,n,d.jobs[i].name)
     click(m.name,n,'确认登记：5000魔币')
     check(get(p,'CHAR_职业')==d.jobs[i].ranks[1].id and get(p,'CHAR_职类ID')==d.jobs[i].family,'displayed confirmation registers job '..i)
     check(Char.GetGold(p)==gold-5000 and m.serviceSessions[p]==nil,'confirmation charges once and consumes session')
     local callback=assert(_G[m.name..'_npc_'..n..'_WindowTalkedEvent'])
     callback(n,p,7292,0,'1');check(Char.GetGold(p)==gold-5000,'replayed confirmation does not charge')
    end
   end
  end
 end
end
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='MENU_INDEX_TEST'})
  check(p>=0,'isolated dummy player')
  set(p,'CHAR_职业',31);set(p,'CHAR_职类ID',30);set(p,'CHAR_等级',200);set(p,'CHAR_技能栏',15)
  Char.AddGold(p,1000000)
  -- Exercise the shared builder's accepted newline formats and single-row labels.
  local m=getModule('skillTraining')
  for _,title in ipairs({'one\ntwo','one\\ntwo','one\r\ntwo','one\rtwo','one\ntwo\\nthree'}) do
   window={data=m:NPC_buildSelectionText(title,{'first','fifth','下一页'})}
   rows({'first','fifth','下一页'},'mixed title format')
  end
  window={data=m:NPC_buildSelectionText('title',{'one\ntwo','one\\ntwo'})}
  rows({'one two','one two'},'multiline labels keep one callback index')
  local pet=training();otherMenus(pet);sharedMenus()
 end,debug.traceback)
 NLG.ShowWindowTalked=originalWindow
 if p>=0 then
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end
  pcall(Char.DelDummy,p)
 end
 R.status=ok and 'PASS' or 'FAIL';R.error=not ok and tostring(err) or nil
 local out=assert(io.open('__REPORT__','wb'));out:write(JSON.encode(R));out:close()
end,0)
