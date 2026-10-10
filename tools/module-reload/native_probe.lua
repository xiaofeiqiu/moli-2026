local R={status='RUNNING',checks={},reports={},messages={}}
local owner=-1
local oldMessage=NLG.SystemMessage
local function check(ok,label)
  R.checks[#R.checks+1]={name=label,pass=ok and true or false}
  assert(ok,label)
end
local function writeFile(path,content)
  local f=assert(io.open(path,'wb'));f:write(content);f:close()
end
local function readFile(path)
  local f=assert(io.open(path,'rb'));local content=f:read('*a');f:close();return content
end
local function upvalue(fn,wanted)
  for index=1,30 do
    local name,value=debug.getupvalue(fn,index)
    if not name then break end
    if name==wanted then return value end
  end
end
local modules=assert(upvalue(getModule,'Modules'))
local callbacks=assert(upvalue(assert(upvalue(regGlobalEvent,'takeCallbacks')),'eventCallbacks'))
local function snapshot()
  local result={modules={},events={}}
  for name,module in pairs(modules) do result.modules[name]=module end
  for name,list in pairs(callbacks) do
    -- NPC indices can change when their modules recreate them.
    local key=name:gsub('_npc_%d+','_npc_*')
    result.events[key]=(result.events[key] or 0)+#list
  end
  return result
end
local function shops()
  local module=assert(getModule('knightHybridGear'))
  check(#module.shops==10 and #module.npcList==10,'exactly ten owned shops')
  local count=0
  for x=138,168 do for y=129,148 do
    local _,objects=Obj.GetObject(0,1000,x,y)
    for _,object in ipairs(objects or {}) do
      if Obj.GetType(object)==1 then
        local char=Obj.GetCharIndex(object)
        if char>=0 and Char.GetData(char,CONST['CHAR_名字']):match('^骑士装备') then count=count+1 end
      end
    end
  end end
  check(count==10,'no duplicate shop NPCs on map')
  for n,shop in ipairs(module.shops) do
    check(Char.GetData(shop.npc,CONST['CHAR_形象'])==14058,'soldier model '..n)
    if n>1 then
      local previous=module.shops[n-1]
      check(shop.x==previous.x+2 and shop.y==previous.y,'roadside shop order '..n)
    end
  end
end
local function invoke()
  local run=reloadAllModules
  local result
  _G.reloadAllModules=function(...)
    result=run(...);return result
  end
  check(TalkEvent(owner,'/module reload all',0,0,0)==0,'GM command consumed')
  if not result then _G.reloadAllModules=run end
  check(result~=nil,'GM command calls reload all')
  R.reports[#R.reports+1]=result
  return result
end
NLG.SystemMessage=function(player,message,...)
  R.messages[#R.messages+1]=message
  return oldMessage(player,message,...)
end
local ok,err=xpcall(function()
  check(reloadAllModules==nil,'running old admin has no reload-all extension')
  owner=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='MODULE_RELOAD_PROBE'})
  check(owner>=0,'isolated GM created')
  Char.SetData(owner,CONST['对象_GM'],1)
  check(getModule('admin'):isAdmin(owner),'dummy has native GM permission')
  local before=snapshot()
  writeFile('lua/Modules/admin.lua',readFile('lua/Modules/adminReloadCandidate.lua'))
  check(TalkEvent(owner,'/module reload admin',0,0,0)==0,'existing command enables new admin')
  check(type(reloadAllModules)=='function','extension available without framework restart')
  check(getModule('admin')~=before.modules.admin,'admin replaced')
  for name,module in pairs(before.modules) do
    if name~='admin' then check(getModule(name)==module,'activation preserves '..name) end
  end
  local active=snapshot()
  Char.SetData(owner,CONST['对象_GM'],0)
  Char.SetData(owner,CONST['CHAR_CDK'],'NON_ADMIN_PROBE')
  check(TalkEvent(owner,'/module reload all',0,0,0)==1,'non-GM command rejected')
  check(getModule('fight')==active.modules.fight,'non-GM cannot reload gameplay')
  Char.SetData(owner,CONST['对象_GM'],1)
  for attempt=1,2 do
    local prior=snapshot();local result=invoke()
    check(not result.aborted and #result.failed==0 and result.succeeded==result.total,'all modules reload successfully '..attempt)
    check(result.order[1]=='admin' and result.order[2]=='adminCommands','configuration order preserved '..attempt)
    for name,module in pairs(prior.modules) do check(getModule(name)~=module,'new module instance '..name..'/'..attempt) end
    local after=snapshot()
    for name,count in pairs(prior.events) do check(after.events[name]==count,'stable callback count '..name..'/'..attempt) end
    shops()
    check(Http.GetStatus()==2,'HTTP restarted on isolated port '..attempt)
  end
  local fixture='lua/Modules/reloadFixture.lua'
  local good="local M=ModuleBase:createModule('reloadFixture');return M"
  writeFile(fixture,good);check(loadModule('reloadFixture')~=nil,'dynamic fixture loaded')
  local prior=snapshot();writeFile(fixture,'local broken = )')
  local result=invoke()
  check(result.aborted and result.succeeded==0 and result.failed[1].name=='reloadFixture','syntax error aborts before any unload')
  for name,module in pairs(prior.modules) do check(getModule(name)==module,'syntax error preserves '..name) end
  writeFile(fixture,"local M=ModuleBase:createModule('reloadFixture');function M:onLoad() error('intentional probe failure') end;return M")
  result=invoke()
  check(not result.aborted and #result.failed==1 and result.failed[1].name=='reloadFixture','onLoad failure reported')
  check(getModule('reloadFixture')==nil,'failed partial module cleaned up')
  check(getModule('fight')~=nil and getModule('admin')~=nil,'other modules remain loaded after failure')
  writeFile(fixture,good);check(loadModule('reloadFixture')~=nil,'dynamic fixture restored')
  result=invoke()
  check(#result.failed==0 and result.succeeded==result.total,'reload can recover after a failure')
  check(result.order[#result.order]=='reloadFixture','dynamically loaded module included')
  unloadModule('reloadFixture');shops()
  local legacy='lua/reload_legacy_fixture.lua'
  writeFile(legacy,'return')
  check(loadModule('reloadLegacyFixture',{path=legacy,absolutePath=true,simpleModule=true})~=nil,'legacy fixture loaded')
  writeFile(legacy,"error('intentional legacy probe failure')")
  result=invoke()
  check(#result.failed==1 and result.failed[1].name=='reloadLegacyFixture','legacy onLoad failure reported')
  check(getModule('reloadLegacyFixture')==nil,'failed legacy module cleaned up')
  writeFile(legacy,'return');shops()
  R.status='PASS'
end,debug.traceback)
NLG.SystemMessage=oldMessage
if owner>=0 then pcall(Char.DelDummy,owner) end
if not ok then R.status='FAIL';R.error=tostring(err) end
writeFile('__OUTPUT__/native_result.json',JSON.encode(R))
