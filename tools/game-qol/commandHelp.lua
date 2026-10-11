-- Shared command catalog. Keep names, usage, and README.md together.
local H={groups={}}
local function entry(names,usage,description)
 return {names=names,usage=usage,description=description}
end
H.groups={
 {module='gameQoL',title='帮助与状态',entries={
  entry({'help'},'/help [命令名|gm]','查看玩家命令用法列表；命令名查看完整说明；gm 查看管理员命令；长说明分行显示，重载 gameQoL 或重启生效'),
  entry({'where'},'/where','查看地图、类型和坐标'),
  entry({'qol'},'/qol','查看自动功能开关及剩余卡时'),
  entry({'heal'},'/heal','不带参数；免费补满人物及所有携带宠物生命、魔力并清除受伤；战斗、摆摊或五宠结算期间不能使用'),
  entry({'clock'},'/clock [on|off|full]','查看或开关打卡；full 按 fevermax 补满卡时（当前6小时）并立即开始打卡，例如 /clock full；战斗或摆摊时不可用；off 同时关闭自动打卡；GM 重载 gameQoL 或重启生效'),
 }},
 {module='gameQoL',title='背包与道具',entries={
  entry({'backpack','bag'},'/backpack [页码] 或 /bag [页码]','查看或切换背包；页码 0~'..CONST.EXTBAGPAGE),
  entry({'sort'},'/sort [all]','整理当前背包；all 整理全部背包'),
  entry({'stack'},'/stack [all]','合并当前背包堆叠；all 处理全部背包'),
  entry({'identify'},'/identify','免费鉴定所有背包道具'),
  entry({'sellstones'},'/sellstones','出售全部背包内已鉴定的普通魔石，包含鉴定前名为魔石？的战斗掉落；金币容量不足时保留，任务魔石不出售'),
 }},
 {module='gameQoL',title='宠物档位',entries={
  entry({'petbp'},'/petbp 0~4|all','查看携带宠物档位；0 是第一只宠物'),
  entry({'petmax'},'/petmax 0~4|all','补满宠物成长档位，保留等级和已加点'),
 }},
 {module='gameQoL',title='自动功能',entries={
  entry({'autostack'},'/autostack on|off','自动合并堆叠，默认开启'),
  entry({'autosort'},'/autosort on|off','自动整理全部背包，战后执行 sort all，默认开启'),
  entry({'autoidentify'},'/autoidentify on|off','自动免费鉴定，默认开启'),
  entry({'autosell'},'/autosell on|off','自动出售全部背包内已鉴定的普通魔石，默认开启；战后及每2秒检查，战斗或摆摊时暂停；自动鉴定开启时先鉴定再出售，金币容量不足时保留，任务魔石不出售；例如 /autosell on；此次魔石识别修复需 GM 重载 gameQoL 或重启生效'),
  entry({'autoclock'},'/autoclock on|off','有卡时时自动打卡，默认开启'),
  entry({'autorepair'},'/autorepair on|off','战后装备耐久低于 85% 自动免费修满，默认开启'),
 }},
 {module='fight',title='战斗',entries={
  entry({'fight'},'/fight [1~10]','当前位置原地遇敌；数字指定敌人数，例如 /fight 10，省略则按地图正常随机遇敌；怪物种类和等级来自当前位置；需存活且不在战斗中，组队由队长使用，地图须允许遇敌；GM 重载 fight 和 gameQoL 或重启生效'),
 }},
 {module='fivePet',title='五宠',entries={
  entry({'fivepet'},'/fivepet on|off','默认开启；单人携带1~5只存活宠物并选好主宠后自动启动，宠物固定前排、人物后排；人物倒下立即结束战斗，恢复后自动启动；主宠手动，其余宠物到圣殿16,34配置优先技能与BOSS合击优先；低血防御是独立开关，可与技能优先同时开启，血量30%及以下先防御，恢复后按原模式行动；默认攻击优先属性克制，同为克制或无克制时选当前血量最低的可攻击敌人；护卫仅保护血量低于50%的其他存活队友，优先低血主角，否则选当前血量最低的低血宠物，无护卫目标时可到指挥官配置备用攻击技能，缺魔或未配置时普攻；攻击技能目标若保守预估普攻可击杀则改普攻；off 保存关闭；此次 Lua 修复结束战斗后由 GM 重载 fivePet 或重启生效'),
 }},
 {module='skillLibrary',title='技能库',entries={
  entry({'skillbook','技能库'},'/skillbook 或 /技能库','打开永久技能库；人物禁学宠物技能；职业导师直接在圣殿内按生产／物理／法系各排一行，中间空一格，BOSS导师28,18每页10项；魔剑士181~187可学全职业及BOSS人物版本；费用照常、战前装配最多15个，DATA修改重启生效'),
 }},
 {module='gameDifficulty',title='难度',entries={
  entry({'difficulty','难度'},'/difficulty [1~6|help] 或 /难度 [1~6|help]','省略参数显示当前生效难度编号和名称，战斗中显示本场档位；1 正常/2 困难/3 极难/4 地狱/5 炼狱/6 深渊；例如 /difficulty 6，怪物生命×6、伤害×4、防御×4、敏捷×1.5'),
  entry({},'难度生效规则','默认 6 深渊；已保存档位保留，角色分别保存，组队用队长难度，下场 PvE 生效，战斗中不能切换；GM 重载 gameDifficulty 和 gameQoL 或重启生效'),
 }},
 {module='autoUnlock',title='账号',entries={
  entry({'selfKickOut'},'/selfKickOut 账号 密码','校验账号密码后断开该账号已在线的角色'),
 }},
}
H.gm={
 module=entry({'module'},'/module reload 模块名|all；/module load|unload 模块名','重载、加载或卸载 Lua 模块'),
 dofile=entry({'dofile'},'/dofile Lua文件路径','执行 Lua 文件'),
 addGold=entry({'addGold'},'/addGold 数量','增加金币'),
 giveItem=entry({'giveItem'},'/giveItem 道具ID 数量 [显示消息] [鉴定状态]','给予道具；显示消息 0 为否，鉴定状态 1/0'),
 delItem=entry({'delItem'},'/delItem 道具ID 数量 [显示消息]','按 ID 删除道具；显示消息 0 为否'),
 delItemBySlot=entry({'delItemBySlot'},'/delItemBySlot 栏位','删除指定栏位的道具'),
 warp=entry({'warp'},'/warp 地图类型 地图ID X Y','传送角色'),
 getPet=entry({'getPet'},'/getPet Enemy编号','生成宠物'),
 upPet=entry({'upPet'},'/upPet 栏位 等级','设置宠物等级并更新信息'),
 recipe=entry({'recipe'},'/recipe add|del|get 配方ID','给予、删除或查看配方'),
 joinParty=entry({'joinParty'},'/joinParty [成员角色索引] 队长角色索引','指定成员加入队伍；省略成员时使用自己'),
 setAction=entry({'setAction'},'/setAction 角色索引 指令 目标 招式 [第二指令 第二目标 第二招式]','设置角色战斗行动'),
 createDummy=entry({'createDummy'},'/createDummy','在身边创建测试角色并加入队伍'),
 setCharData=entry({'setCharData'},'/setCharData 角色索引 字段编号 值','修改角色字段'),
 getCharData=entry({'getCharData'},'/getCharData 角色索引 字段编号','读取角色字段'),
 autoBattle=entry({'autoBattle'},'/autoBattle on','发送跳过战斗指令并执行测试攻击'),
 delDummy=entry({'delDummy'},'/delDummy 角色索引','删除测试角色'),
 moveChar=entry({'moveChar'},'/moveChar 角色索引 方向编号...','按 0~7 方向序列移动角色'),
 changeJob=entry({'changeJob'},'/changeJob [职类ID] 职业ID [职阶]','1 参数设职业，2 参数设职类及职业，3 参数同时设职阶'),
 calcFp=entry({'calcFp'},'/calcFp 招式ID','查看招式消耗魔力'),
 dolua=entry({'dolua'},'/dolua Lua文件路径 [参数...]','执行文件返回的函数并传入当前角色及参数'),
 walkTest=entry({'walkTest'},'/walkTest','启用移动回调测试'),
 walkTestOff=entry({'walkTestOff'},'/walkTestOff','关闭移动回调测试'),
}

function H:commandSet(moduleName)
 local names={}
 for _,group in ipairs(self.groups) do if group.module==moduleName then
  for _,row in ipairs(group.entries) do for _,name in ipairs(row.names) do names[name:lower()]=true end end
 end end
 return names
end

function H:isAdmin(p)
 local admin=getModule('admin')
 return admin and admin:isAdmin(p) or false
end

function H:playerGroups()
 local groups={}
 for _,group in ipairs(self.groups) do if getModule(group.module) then groups[#groups+1]=group end end
 return groups
end

function H:gmGroups()
 local groups={}
 for _,moduleName in ipairs({'admin','adminCommands'}) do
  local module=getModule(moduleName)
  if module then
   local names,seen={},{}
   for name in pairs(module.commandHandlers or {}) do names[#names+1]=name;seen[name]=true end
   for name in pairs(module.extraHelpCommands or {}) do if not seen[name] then names[#names+1]=name end end
   table.sort(names)
   local rows={}
   for _,name in ipairs(names) do
    rows[#rows+1]=self.gm[name] or entry({name},'/'..name..' [参数...]','管理员扩展命令')
   end
   groups[#groups+1]={title=moduleName,entries=rows}
  end
 end
 return groups
end

-- Runtime text is GBK. Keep each chat history entry short and never split a
-- two-byte character; the client also reads these entries when scrolling.
local function sendText(p,text)
 local first,pos=1,1
 while pos<=#text do
  local width=text:byte(pos)>=128 and 2 or 1
  if pos-first+width>120 then
   NLG.SystemMessage(p,text:sub(first,pos-1));first=pos
  end
  pos=pos+width
 end
 if first<=#text then NLG.SystemMessage(p,text:sub(first)) end
end

local function showGroup(p,group)
 sendText(p,'【'..group.title..'】')
 local line=''
 for _,row in ipairs(group.entries) do
  local text=row.usage
  if line~='' and #line+#text+2>120 then sendText(p,line);line='' end
  line=line..(line~='' and '；' or '')..text
 end
 if line~='' then sendText(p,line) end
end

function H:show(p,query)
 query=(query or ''):gsub('^/',''):lower()
 if query=='gm' then
  if not self:isAdmin(p) then NLG.SystemMessage(p,'GM 命令需要管理员权限。');return end
  for _,group in ipairs(self:gmGroups()) do showGroup(p,group) end
  return
 end
 local groups=self:playerGroups()
 if query=='' then
  for _,group in ipairs(groups) do showGroup(p,group) end
  sendText(p,'输入 /help 命令名 查看完整说明，例如 /help fivepet。')
  sendText(p,'背包页、宠物栏位从 0 开始；背包和宠物操作在战斗或摆摊期间暂停。')
  if self:isAdmin(p) then NLG.SystemMessage(p,'管理员输入 /help gm 查看 GM 命令和参数。') end
  return
 end
 if self:isAdmin(p) then for _,group in ipairs(self:gmGroups()) do groups[#groups+1]=group end end
 for _,group in ipairs(groups) do for _,row in ipairs(group.entries) do for _,name in ipairs(row.names) do
  if name:lower()==query then
   sendText(p,row.usage..'：'..row.description..'。')
   if group.module=='gameDifficulty' then sendText(p,group.entries[2].description..'。') end
   return
  end
 end end end
 NLG.SystemMessage(p,'未找到此命令的帮助；输入 /help 查看已加载的玩家命令。')
end
return H
