---模块类
---@class Welcome: ModuleType
local Welcome = ModuleBase:createModule('welcome')
---迁移定义
Welcome:addMigration(1, 'initial module', function()
  print('run migration version: 1');
end);

local announceflg = true;  --对首次进入游戏玩家全副公告
local WelcomeMessage = {}; --欢迎词
table.insert(WelcomeMessage, "欢迎使用cgmsv引擎");
table.insert(WelcomeMessage, "自定义欢迎信息,请在gmsv\\lua\\Modules\\welcome.lua内修改!");

function Welcome:onLogin(player)
  if (WelcomeMessage ~= nil) then   --欢迎词
    for _, text in ipairs(WelcomeMessage) do
      NLG.TalkToCli(player, -1, text, CONST.颜色_黄色, CONST.字体_中);
    end
    if (announceflg == true and Char.GetData(player, CONST.对象_登陆次数) == 1) then
      NLG.SystemMessage(-1, "欢迎[" .. Char.GetData(player, CONST.对象_原名) .. "]来到了游戏.")
    end
  end
end

--- 加载模块钩子
function Welcome:onLoad()
  self:regCallback('LoginEvent', Func.bind(self.onLogin, self));
  self:logInfo('load');
end

--- 卸载模块钩子
function Welcome:onUnload()
  self:logInfo('unload');
end

return Welcome;
