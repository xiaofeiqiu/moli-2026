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
local function services()
 local d
 local m=getModule('sharedTaskAdapters');local n=m.services;reach(n)
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
  p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='SERVICE_INDEX_TEST'})
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
  services()
 end,debug.traceback)
 NLG.ShowWindowTalked=originalWindow
 if p>=0 then
  for slot=0,4 do if Char.GetPet(p,slot)>=0 then pcall(Char.DelSlotPet,p,slot) end end
  pcall(Char.DelDummy,p)
 end
 R.status=ok and 'PASS' or 'FAIL';R.error=not ok and tostring(err) or nil
 local out=assert(io.open('__REPORT__','wb'));out:write(JSON.encode(R));out:close()
end,0)
