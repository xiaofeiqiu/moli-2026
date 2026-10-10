-- Extend the current module registry without reinitializing the Lua framework.
local function registry()
  for index=1,20 do
    local name,value=debug.getupvalue(getModule,index)
    if not name then break end
    if name=='Modules' and type(value)=='table' then return value end
  end
  error('Module registry unavailable; reload all was not started')
end

local function plan(modules)
  local names,seen={},{}
  local function add(name)
    if modules[name] and not seen[name] then
      seen[name]=true
      names[#names+1]=name
    end
  end
  -- Use startup configuration order for dependencies, then include dynamically
  -- loaded modules too. Reading the config does not execute its initialization.
  for _,path in ipairs({'lua/ModuleConfig.lua','lua/Modules/Private/Config.lua'}) do
    local file=io.open(path,'r')
    if file then
      for line in file:lines() do
        local name=line:match('^%s*loadModule%s*%(%s*[\'\"]([^\'\"]+)')
          or line:match('^%s*loadSimpleModule%s*%(%s*[\'\"]([^\'\"]+)')
          or line:match('^%s*useModule%s*%(%s*[\'\"]([^\'\"]+)')
        if name then add(name) end
      end
      file:close()
    end
  end
  local remaining={}
  for name in pairs(modules) do if not seen[name] then remaining[#remaining+1]=name end end
  table.sort(remaining)
  for _,name in ipairs(remaining) do add(name) end
  return names
end

function _G.reloadAllModules()
  if _G._moduleReloadAllBusy then error('A module reload is already running') end
  local modules=registry()
  local names=plan(modules)
  local result={total=#names,succeeded=0,failed={},aborted=false,order=names}
  local entries={}
  -- Check every file before unloading anything. Keep exact paths and legacy
  -- flags, so custom and dynamically loaded modules retain their load options.
  for _,name in ipairs(names) do
    local module=modules[name]
    local compiled,err=loadfile(module.___aPath,'bt')
    if not compiled then
      result.failed[#result.failed+1]={name=name,error=tostring(err)}
      logError('ModuleSystem','reload all preflight failed: '..name,err)
    end
    entries[#entries+1]={name=name,path=module.___path,
      absolutePath=module.___absolutePath,simpleModule=module.___isSimpleModule}
  end
  if #result.failed>0 then result.aborted=true;return result end
  _G._moduleReloadAllBusy=true
  local baseLoad=ModuleBase.load
  local legacyOnLoad=LegacyModule.onLoad
  local httpStop=Http.Stop
  local ok,err=xpcall(function()
    for _,entry in ipairs(entries) do
      local loadError
      -- The existing loadModule logs onLoad errors and returns the instance.
      -- Capture these errors as failures rather than reporting false success.
      ModuleBase.load=function(self,...)
        local loaded,message=pcall(baseLoad,self,...)
        if not loaded then loadError=tostring(message);error(message,0) end
      end
      -- LegacyModule catches its own errors, so observe its error log too.
      LegacyModule.onLoad=function(self,...)
        local previous=rawget(self,'logError')
        local reportError=self.logError
        self.logError=function(object,message,...)
          loadError=tostring(message)
          return reportError(object,message,...)
        end
        local legacyLoaded,message=pcall(legacyOnLoad,self,...)
        self.logError=previous
        if not legacyLoaded then error(message,0) end
      end
      -- Retain the listener even when the running HTTP module is an older
      -- version. Http.Stop is asynchronous, so stop/start cannot be immediate.
      if entry.name=='http' and Http.GetStatus()==2 then Http.Stop=function() return 1 end end
      local loaded,module=pcall(loadModule,entry.name,{path=entry.path,
        absolutePath=entry.absolutePath,simpleModule=entry.simpleModule,forceReload=true})
      ModuleBase.load=baseLoad
      LegacyModule.onLoad=legacyOnLoad
      Http.Stop=httpStop
      if loaded and module and not loadError then
        result.succeeded=result.succeeded+1
      else
        local message=loadError or (not loaded and tostring(module)) or 'Module file failed to load'
        result.failed[#result.failed+1]={name=entry.name,error=message}
        logError('ModuleSystem','reload all failed: '..entry.name,message)
        if loadError then pcall(unloadModule,entry.name) end
      end
    end
  end,debug.traceback)
  ModuleBase.load=baseLoad
  LegacyModule.onLoad=legacyOnLoad
  Http.Stop=httpStop
  _G._moduleReloadAllBusy=false
  if not ok then error(err,0) end
  logInfo('ModuleSystem',string.format('reload all finished: %d/%d',result.succeeded,result.total))
  return result
end
