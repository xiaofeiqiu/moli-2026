---@class Admin:ModuleBase|ModuleType
local Admin = ModuleBase:createModule('admin')
-- gm命令
local commands = {}
--GM账号列表
local gmList = { '123456', 'test' };
local gmDict = {};
table.forEach(gmList, function(e)
  if e != nil then
    gmDict[e] = true
  end
end)

function commands.module(charIndex, args)
  if args[1] == 'reload' then
    if args[2] == 'all' then
      local ok, result = pcall(reloadAllModules);
      if not ok then
        NLG.SystemMessage(charIndex, '全部重载失败：' .. tostring(result));
      elseif result.aborted then
        NLG.SystemMessage(charIndex, '未执行重载：' .. result.failed[1].name .. ' 脚本检查失败，详见服务端日志。');
      else
        NLG.SystemMessage(charIndex, string.format('模块重载完成：成功 %d/%d 个。', result.succeeded, result.total));
        for _, failure in ipairs(result.failed) do
          NLG.SystemMessage(charIndex, '模块重载失败：' .. failure.name .. '，详见服务端日志。');
        end
      end
    elseif args[2] then
      reloadModule(args[2]);
    else
      NLG.SystemMessage(charIndex, '用法：/module reload 模块名 或 /module reload all');
    end
  elseif args[1] == 'unload' then
    unloadModule(args[2]);
  elseif args[1] == 'load' then
    loadModule(args[2]);
  end
end

function commands.dofile(charIndex, args)
  local r, msg = pcall(dofile, args[1]);
  if not r then
    NLG.TalkToCli(charIndex, -1, tostring(msg));
  end
end

---是否管理员
---@param charIndex number
---@return boolean
function Admin:isAdmin(charIndex)
  local cdKey = Char.GetData(charIndex, CONST.CHAR_CDK)
  if not gmDict[cdKey] && Char.GetData(charIndex, CONST.对象_GM) ~= 1 then
    return false
  end
  return true;
end

function Admin:handleChat(charIndex, msg, color, range, size)
  if not self:isAdmin(charIndex) then
    return 1
  end
  local command = msg:match('^/([%w]+)')
  if commands[command] then
    local arg = msg:match('^/[%w]+ +(.+)$')
    arg = arg and string.split(arg, ' ') or {}
    commands[command](charIndex, arg);
    return 0
  end
  return 1
end

function Admin:onLoad()
  -- Also enables the new command on a running server via /module reload admin.
  dofile('lua/libs/Module/ReloadAll.lua');
  self:logInfo('load')
  self:regCallback('TalkEvent', Func.bind(Admin.handleChat, self))
end

function Admin:onUnload()
  self:logInfo('unload')
end

return Admin;
