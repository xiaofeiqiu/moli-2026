-- Shared command catalog. Keep names, usage, and README.md together.
local H={groups={}}
local function entry(names,usage,description)
 return {names=names,usage=usage,description=description}
end
H.groups={
 {module='gameQoL',title='帮助与状态',entries={
  entry({'help'},'/help [命令名|gm]','查看玩家命令用法列表；命令名查看完整说明；gm 查看管理员命令；长说明分行显示，重载 gameQoL 或重启生效'),
  entry({'where'},'/where','查看地图、类型和坐标'),
  entry({'fame','声望'},'/fame [max] 或 /声望 [max]','省略参数查看自己的声望；max 将自己的声望设为 cgmsv.cf 的 maxfame 配置上限（当前200999）并保存，例如 /fame max 或 /声望 max；普通玩家可用，战斗或摆摊时也可使用；GM 重载 gameQoL 或重启生效'),
  entry({'qol'},'/qol','查看自动功能开关及剩余卡时'),
  entry({'heal'},'/heal','不带参数；免费补满人物、所有携带宠物及银行前4栏宠物生命、魔力并清除受伤；银行栏号0~3；战斗、摆摊或五宠结算期间不能使用'),
  entry({'clock'},'/clock [on|off|full]','查看或开关打卡；full 按 fevermax 补满卡时（当前6小时），重设正在运行的原生倒计时并立即开始打卡；按实际时长核对并保存，修改 fevermax 引擎上限须重启，例如 /clock full；战斗或摆摊时不可用；off 同时关闭自动打卡；GM 重载 gameQoL 或重启生效'),
 }},
 {module='gameQoL',title='背包与道具',entries={
  entry({'backpack','bag'},'/backpack [页码] 或 /bag [页码]','查看或切换背包；页码 0~'..CONST.EXTBAGPAGE),
  entry({'sort'},'/sort [all]','整理当前背包；all 整理全部背包'),
  entry({'stack'},'/stack [all]','合并当前背包堆叠；all 处理全部背包'),
  entry({'identify'},'/identify','免费鉴定所有背包道具'),
  entry({'sellstones'},'/sellstones','出售全部背包内已鉴定的普通魔石，包含鉴定前名为魔石？的战斗掉落；金币容量不足时保留，任务魔石不出售'),
  entry({},'魔石强化装备：把魔石拖到背包中的装备上','每次尝试消耗1颗普通魔石，最高+13；已有正数攻击、防御、敏捷、精神、回复、生命、魔力、魔攻按原始值每级累计增加7%并向下取整，+13为原始值的191%；目标+1~+7成功率95/93/91/89/87/85/82%，失败不降级；目标+8~+11成功率79/77/75/72%，失败有50%概率降1级；目标+12~+13成功率62/55%，失败有80%概率降1级；连续失败5次后下一次必成功，降级不清空失败次数，成功后清零，保底跟随装备；装备须已鉴定且未损坏，战斗或摆摊时不可用；支持人物和宠物装备，均需先卸到人物背包；原有说明及特殊参数保留；旧强化标记或异常数据暂不支持，材料保留；先用 /autosell off 保留魔石；例如魔石拖到长剑上成功后变成长剑+1；GM 首次 /module load equipmentEnhance，已加载用 /module reload equipmentEnhance，并重载 gameQoL 或重启生效'),
 }},
 {module='gameQoL',title='宠物档位',entries={
  entry({'petbp'},'/petbp 0~4|all 或 /petbp bank 0~4|all','查看宠物体/力/强/敏/魔的当前档位、满档值和总掉档；0 是第一只宠物，银行栏号0~4；/petbp 0 查看随身第一只，/petbp all 查看随身及银行全部，/petbp bank 0 查看银行第一只，/petbp bank all 仅查看银行；战斗或摆摊期间不能使用；重载 gameQoL 或重启生效'),
  entry({'petmax'},'/petmax 0~4|all','补满宠物成长档位，保留等级和已加点；写入及保存成功后才提示补回，失败撤销；满档不得超过 cgmsv.cf 的 maxallocpoint（当前67），修改此引擎配置须重启；例如 /petmax all 后 /petbp all 核对携带宠物掉档为0'),
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
 {module='fivePet',title='九宠小队',entries={
  entry({'fivepet'},'/fivepet on|off','默认开启；单人随身1~5只存活宠物并选主宠，最多加银行前4栏共9只参战；每只非主宠随身宠物的替身带一个对应银行栏的存活宠物，随身5只加银行4只时达到9只。人物与主宠始终手动操作，Boss战也不接管主宠，其他最多8只自动；有银行伙伴时主宠和银行伙伴前排，人物和随身宠物替身后排，没有银行伙伴时沿用五宠前排。银行原宠保留，属性和已学技能同步到战斗替身，血魔、受伤及经验同步回原宠，原生计算升级；装配宠物强化（技能70）时，主宠、随身参战伙伴及银行参战伙伴分别按当前技能等级的DATA获得一次战后经验加成，向下取整；LV10加40%、LV30加80%，例如原生经验1000在LV30时变成1800；仅收录技能库不生效，卸下后停止，人物经验不加成，正常一人一宠也生效；正常胜利后仅实际参战且存活的银行前4栏获得原生战斗经验，逐只提示并保存，第5栏、未参战或倒下的银行宠物不分经验；银行升级通过战斗替身执行原生计算后回写等级、剩余经验、成长和新增点数，自动加点继续生效，重复结算不重复发经验；经验修复需战后GM重载fivePet、autoStat、gameQoL或正常重启；宠装留在原宠，使用原宠最终属性，不复制或转移实物装备。换银行宠物后自动重建，小队关闭后不召出银行伙伴；替身全部创建成功后才入队，创建失败暂停相同阵容的自动重试，阵容、主宠、技能或存活状态变化后自动恢复，也可 /fivepet on 手动重试；/heal 同时恢复银行前4栏；所有自动参战的随身宠物与银行伙伴默认开启智能战斗，无需配置优先技能或回复阈值；圣殿16,34指挥官可选智能战斗或显式全程防御。智能战斗按存活与伤害收益选行动：用当前生命、敌方已学技能效果和可达范围、最近两回合按实际扣血记录的伤害，保守估算本回合及下一回合结束生命。预计本回合会倒下时优先保命；能撑过两回合时优先降低敌方生命，不因固定血量比例或站位强制补血、防御。危险时比较补血、匹配物理或法术威胁的护盾、护卫、明镜止水和防御，考虑耗魔、有效范围、行动先后及护卫转移后的伤害，避免让会倒下的宠物护卫别人。能可靠先手收尾并消除威胁时仍可进攻。敌人倒下、停止攻击、换招或无法命中时重新判断，回合内已行动的敌人不重复计入剩余攻击。普通防御后的物理掉血还原为未防御估计，避免误判威胁消失；战斗结束清空记录。预测是估算，暴击、闪躲和行动先后仍按原生引擎计算。Boss 遮挡只用于保护安全目标，不强制前排防御：玩家在后排且两边前排遮挡后排近战Boss时，保留敌方挡路宠物，攻击避开会波及它们的十字、全体和随机技能；能安全进攻的前排或后排自动宠物都可用单体远程攻击Boss，预计生命危险时才比较防护行动。Boss能用远程绕过遮挡、挡路宠物倒下或阵型改变后立即重新判断。人物和主宠始终手动操作，Boss战也不接管主宠；AI只控制其他随身宠物和银行伙伴。显式全程防御设置保留。自动随身宠物的假人替身每回合只行动一次，不追加第二行动，银行伙伴遵守原生宠物行动规则；技能必须已学且魔力可支付，不自动使用金钱攻击或破坏装备。宠物诸刃与乾坤一掷普通Ⅰ~Ⅹ可在圣殿36,18学习物理技能，每档1000魔币并占一个技能栏，已有Ⅴ保留，补齐Ⅵ~Ⅹ；Ⅵ~Ⅹ耗魔110/130/150/170/190，原生版与复制版分别升级；圣殿38,18升级师可将已学Ⅴ升Ⅹ收5000魔币，满魔不足190时选可负担档；高档乾坤沿用命中下降，智能战斗按现有命中风险规则决定是否使用；新增DATA须保存角色并正常重启服务端，单独重载Lua不够；圣殿38,18宠物技能升级师可付费升级随身及银行五栏的现有技能，按最大魔力可支付的耗魔选同系列最高档，每技能每提升一级1000魔币；先看逐项及总价，再确认是，支持单项、本宠全部或升级所有宠物；菜单第一项升级所有宠物（随身＋银行）汇总随身五栏和银行五栏的可升级宠物数、技能数和总价，再选确认升级所有宠物并选是，一次扣费并保存；无可升级技能的宠物不收费，例如两只宠物各升5级共10000魔币；整批写入或保存失败恢复全部宠物原技能并退还总费用，确认前任何随身或银行宠物、技能、满魔改变需重新查看整批报价；同系列仅升已学最高档并保留低档，BOSS变体不混升，无后续或已达最高档不收费；取消、钱不足或保存失败不扣费，失败恢复原技能栏；战斗、摆摊、五宠结算期间不可用，报价120秒过期，换宠或技能、满魔变化需重选；首次GM加载petSkillUpgrade，重载gameQoL同步帮助或重启生效。例如生命400、预估每回合受伤200时比较补血或防御，能安全撑过两回合则优先进攻；护卫后本回合不追加第二行动，无需配置；/fivepet off 保存关闭，/fivepet on 恢复开启；人物倒下立即结束战斗，恢复后自动启动，仅限单人普通战斗；结束战斗后 GM 重载 fivePet，重载 gameQoL 同步帮助，或正常重启生效'),
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
 getPet=entry({'getPet'},'/getPet Enemy编号','生成宠物，需空宠物栏；例如 /getPet 800412 生成改造绿巨人（基础档体36/力45/强22/敏25/魔12，/petbp满档每项含原生+2修正，人形系、地10、6技能栏）；新增DATA须正常重启服务端后生效，已有巨人不自动变更'),
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
