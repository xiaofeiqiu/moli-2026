# moli-2026 服务端

本仓库保存 CrossGate 服务端及其维护工具。

- `gmsv/`：服务端程序、GBK 控制台适配器、Lua 模块、NPC 脚本和静态地图/游戏数据。
- `tools/`：服务端内容整合、修复和验证工具。
- `docs/`、`lua参考/`：服务端说明及 Lua API 参考。

客户端程序、图像、音效、客户端地图缓存、显示/语言工具，以及备份、日志、玩家数据库和运行存档不纳入版本控制。根目录采用白名单，避免后续 `git add .` 误加入客户端。

## 目录

- [在新机器准备服务端](#在新机器准备服务端)
- [客户端连接与账号注册](#客户端连接与账号注册)
- [玩家命令](#玩家命令)
- [GM 常用命令](#gm-常用命令)
- [技能与职业配置](#技能与职业配置)
- [物品和宠物存档问题排查](#物品和宠物存档问题排查)
- [维护工具与详细文档](#维护工具与详细文档)

## 在新机器准备服务端

1. 将 `gmsv/setup.cf.example` 复制为 `gmsv/setup.cf`，填写数据库、GM 和服务间登录口令；模板保留原文件的 GBK 编码。
2. 将 `gmsv/data/debugger.txt.example` 复制为 `gmsv/data/debugger.txt`，按需要填写允许的 GM 账号。
3. SQLite 初始化结构在 `gmsv/sql/sqlite.sql`，仅包含表结构和服务端迁移版本记录，不含账号、角色、道具或宠物存档。仅在没有 `gmsv/data.db3` 的新环境中执行：

   ```powershell
   if (Test-Path gmsv/data.db3) { throw '数据库已存在，请保留现有数据。' }
   python -c "import sqlite3; from pathlib import Path; c=sqlite3.connect('gmsv/data.db3'); c.executescript(Path('gmsv/sql/sqlite.sql').read_text(encoding='utf-8')); c.close()"
   ```

   MySQL 的初始化脚本为 `gmsv/sql/mysql.sql`，切换数据库时同步修改 `setup.cf`。
4. 在 `gmsv` 下创建运行目录 `store`、`store/dungeon`、`store/house`、`store/itemcount`、`Dengon`、`dump`、`GMLog` 和 `house`。迁移已有服务器时，另行复制数据库和运行存档。
5. 从 `gmsv` 目录启动 `cgmsv-gbk.exe`；该适配器会启动同目录的 `cgmsv.exe`。

   ```powershell
   Set-Location gmsv
   .\cgmsv-gbk.exe
   ```

原有文件不转换编码或换行。服务端地图虽然是二进制文件，仍属于服务端必需的静态资源。

## 客户端连接与账号注册

1. 另行准备兼容的游戏客户端、资源及登录器；这些文件不包含在本仓库中。7.1 客户端资源对应关系见[宠物导入指南](docs/cg71_pet_import_guide_zh.md)。
2. 启动服务端后，将登录器的服务器地址指向本机 `127.0.0.1`；在其他电脑上连接时填写服务端所在电脑的地址。游戏端口以 `gmsv/setup.cf` 的 `port` 为准，模板为 `9030`。
3. 在服务端电脑打开[账号注册页面](http://127.0.0.1:10086/)，注册账号和密码，然后通过登录器进入游戏。HTTP 注册服务由 `http` 模块提供，当前监听端口为 `10086`。

默认加载的模块见 [ModuleConfig.lua](gmsv/lua/ModuleConfig.lua)。下列玩家命令以其中加载的 `gameQoL`、`fight` 和 `skillLibrary` 模块为准。

## 玩家命令

在游戏聊天窗口输入命令。`gameQoL` 和 `/fight` 的英文命令不区分大小写；技能库命令按示例输入。背包页和宠物栏位从 **0** 开始编号；当前配置有 **4 页背包（0～3）**，每页 20 格，宠物栏位为 **0～4**。

### 角色与战斗

| 命令 | 作用 | 用法示例 |
| --- | --- | --- |
| `/where` | 查看自己的地图、地图类型和坐标 | `/where` |
| `/fight` | 在当前位置触发一次原生遇敌；需有生命值且不在战斗中，组队时由队长使用 | `/fight` |
| `/clock` | 查看打卡状态和剩余卡时 | `/clock` |
| `/clock on` | 开启原生卡时双倍经验，需要剩余卡时 | `/clock on` |
| `/clock off` | 关闭打卡，同时关闭自动打卡 | `/clock off` |
| `/qol` | 查看自动功能开关及卡时 | `/qol` |
| `/help` | 显示便捷功能命令帮助 | `/help` |

`/fight` 需要当前地图允许遇敌。在城镇等无法遇敌的位置使用会显示失败提示。

### 背包与道具

| 命令 | 作用 | 用法示例 |
| --- | --- | --- |
| `/backpack` 或 `/bag` | 查看当前背包页及各页占用情况 | `/backpack` |
| `/backpack 页码` 或 `/bag 页码` | 切换背包页 | `/backpack 1` |
| `/sort [all]` | 合并可堆叠道具，再按类型和 ID 整理；省略 `all` 时只整理当前页 | `/sort`、`/sort all` |
| `/stack [all]` | 合并可堆叠道具；省略 `all` 时只处理当前页 | `/stack all` |
| `/identify` | 免费鉴定所有背包页内的未鉴定道具 | `/identify` |
| `/sellstones` | 按道具价格出售已鉴定魔石并获得金币；金币容量不足时保留对应魔石 | `/sellstones` |

背包整理、鉴定、卖魔石和宠物档位操作在战斗或摆摊期间不能使用。堆叠会检查耐久、价格、印记、任务参数等属性，属性不同的道具不会合并。

### 宠物

| 命令 | 作用 | 用法示例 |
| --- | --- | --- |
| `/petbp 栏位` | 查看该宠物体、力、强、敏、魔的当前档位、满档值及总掉档 | `/petbp 0` |
| `/petbp all` | 查看所有已携带宠物的档位 | `/petbp all` |
| `/petmax 栏位` | 将该宠物缺失的成长档位补至种族满档 | `/petmax 0` |
| `/petmax all` | 为所有已携带宠物补档 | `/petmax all` |

补档保留当前等级和已分配的属性点，不限制宠物必须为 1 级；调整影响后续升级成长。命令不执行转生或重置等级。

### 自动功能

每项命令接受 `on` 或 `off`，开关按账号和角色保存。当前默认值如下：

| 命令 | 功能 | 默认状态 | 示例 |
| --- | --- | --- | --- |
| `/autostack` | 自动合并可堆叠道具 | 开启 | `/autostack off` |
| `/autosort` | 自动整理所有背包页 | 关闭 | `/autosort on` |
| `/autoidentify` | 自动免费鉴定 | 开启 | `/autoidentify off` |
| `/autosell` | 自动出售已鉴定魔石 | 开启 | `/autosell off` |
| `/autoclock` | 有剩余卡时时自动开启打卡 | 开启 | `/autoclock off` |

自动任务每 2 秒检查一次；战斗或摆摊期间暂停自动处理。

### 永久技能库

在非战斗状态下输入 `/skillbook` 或 `/技能库`，也可找法兰城地图 `1000`、坐标 `153,110` 的「永久技能库管理员」。

- 学过的技能永久保存，卸下时保留等级和经验；出战装配最多 **15 个技能**。
- 可以保存和加载整套技能配装，战斗中不能切换。
- 按当前职业许可学习，首次学习按配置扣费，重复学习不重复收费。
- 当前技能库的玩家技能上限为 **30 级**；具体职业许可仍由配置决定。

详见[永久技能库说明](docs/skill_library/README_zh.md)。

## GM 常用命令

### Lua 管理命令

在聊天窗口输入。`admin` 模块根据角色 GM 标志或管理员账号名单检查权限；命令名区分大小写。

| 命令 | 作用 | 用法示例 |
| --- | --- | --- |
| `/addGold 数量` | 增加金币 | `/addGold 5000` |
| `/giveItem 道具ID 数量` | 给予指定道具 | `/giveItem 2100 1` |
| `/getPet Enemy编号` | 生成宠物 | `/getPet 905` |
| `/upPet 栏位 等级` | 设置携带宠物等级并更新宠物信息 | `/upPet 0 100` |
| `/warp 地图类型 地图ID X Y` | 传送角色 | `/warp 0 11011 23 17` |
| `/changeJob 职类ID 职业ID 职阶` | 设置职业相关字段并更新角色信息 | `/changeJob 10 12 2` |
| `/module reload 模块名` | 重新加载指定 Lua 模块 | `/module reload gameQoL` |
| `/module reload all` | 重载当前已加载的全部 Lua 模块 | `/module reload all` |

模块名由脚本中的 `ModuleBase:createModule(...)` 定义，不一定等于文件名。全部重载会先检查脚本语法，重载结果显示在聊天框，详细错误写入服务端日志。修改 `skill.txt`、`tech.txt`、`skilllv.txt`、`jobs.txt` 等 DATA 后，需要正常重启服务端才能加载；Lua 模块热重载不代替 DATA 加载。

实现见 [admin.lua](gmsv/lua/Modules/admin.lua)、[adminCommands.lua](gmsv/lua/Modules/adminCommands.lua) 和[模块热重载说明](docs/module_reload_all/README_zh.md)。

### 原生 GM 命令

原生命令使用 `[GM口令 命令 参数]` 格式；方括号也要输入。口令由 `gmsv/setup.cf` 的 `chatmagicpasswd` 配置，账号权限检查由 `chatmagiccdkeycheck` 和 `debuggerfile` 配置。以下 `GM口令` 是占位符，使用时替换为自己的配置值。

| 命令 | 作用或参数含义 |
| --- | --- |
| `[GM口令 makepet 905]` | 按 Enemy 编号生成宠物；`905` 对应圣龙的原生记录 |
| `[GM口令 setpettech 0 3 8659]` | 将宠物栏位 `0` 的技能栏位 `3` 改为 Tech 编号 `8659`（超强即死 ES） |
| `[GM口令 setpettech 0 3 451]` | 将宠物栏位 `0` 的技能栏位 `3` 改为 Tech 编号 `451`（气功弹 EX） |
| `[GM口令 checkoinum]` | 查看当前形象 ID |
| `[GM口令 metamo 形象ID]` | 更改角色形象 |
| `[GM口令 setallskilllv 2]` | 将已学技能等级设置为 `2` |
| `[GM口令 setskillslot 15]` | 设置技能栏数量；当前技能库最多装配 15 个技能 |
| `[GM口令 warp 0 11011 23 17]` | 传送到地图类型 `0`、地图 `11011`、坐标 `23,17` |
| `[GM口令 gold 5000]` | 增加金币 |
| `[GM口令 additem 道具ID]` | 生成道具 |
| `[GM口令 dungeonlist]` | 查看迷宫列表 |
| `[GM口令 setjob 职业ID]` | 修改职业 |
| `[GM口令 vital 100]` | 修改体力属性 |
| `[GM口令 str 100]` | 修改力量属性 |
| `[GM口令 tgh 100]` | 修改强度属性 |
| `[GM口令 quick 100]` | 修改速度属性 |
| `[GM口令 stamina 100]` | 修改耐力属性 |
| `[GM口令 magic 100]` | 修改魔法属性 |
| `[GM口令 petexp 0 100]` | 修改宠物栏位 `0` 的经验 |
| `[GM口令 exp 100]` | 修改人物经验 |
| `[GM口令 level 100]` | 修改人物等级 |

查编号时使用当前仓库中的文件：

- 宠物生成编号：[enemy.txt](gmsv/data/enemy.txt) 的实际第 **3** 列；第 4 列关联 [enemybase.txt](gmsv/data/enemybase.txt) 的种族编号。Enemy 编号、种族编号和形象 ID 不能互换。
- 宠物技能编号：[tech.txt](gmsv/data/tech.txt) 的实际第 **4** 列。
- 道具编号：[itemset.txt](gmsv/data/itemset.txt) 的实际第 **12** 列。
- 地图名称与编号：[MapTransName.txt](gmsv/data/MapTransName.txt)。
- 职业编号：[jobs.txt](gmsv/data/jobs.txt) 的实际第 **3** 列。

## 技能与职业配置

以下技能与职业配置文件使用 **GBK 编码、Tab 分隔**。下文列号均从 **1** 开始，并计入空列；编辑时必须保留空列，不能用空格拆分后重新拼接。Lua API 的 `CONST.TECH_*` 等索引是内存字段索引，不能直接当作文本文件列号。

### skill.txt：技能基础定义

以下是当前 `乾坤一掷`（技能 ID `3`）的主要字段：

| 实际列号 | 字段 | 当前值 | 说明 |
| --- | --- | --- | --- |
| 1 | 名称 | 乾坤一掷 | 技能名称 |
| 2 | Skill ID | 3 | 技能定义编号，供 `tech.txt`、`skilllv.txt` 关联 |
| 3 | 说明编号 | 130003 | 说明资源编号，不是招式的 Tech ID |
| 4 | 技能类别 | 1 | 沿用对应技能的原生类别 |
| 5 | 基础等级上限 | 30 | 当前配置已扩展至 30 级；职业许可另看 `skilllv.txt` |
| 7 | 学习费用 | 100 | 技能库使用此字段作为普通技能的学习费用 |
| 9 | 武器限制 | 159 | 原生武器限制掩码，修改时参考同类技能 |
| 10 | 经验表编号 | 2 | 关联 `skillexp.txt` 的经验表 |
| 11 | 技能栏占用 | 1 | 装配时占用的技能栏数 |

其他字段和空列应从现有模板保留。以下示例用 `\t` 表示一个真实 Tab（包括末尾空列）；写回 DATA 时需还原为 Tab。当前记录示例：

```text
乾坤一掷\t3\t130003\t1\t30\t1\t100\t100\t159\t2\t1\t\t1000\t\t\t\t0\t\t
```

### tech.txt：招式与实际效果

同一个 Skill 可以关联多个等级的 Tech。当前表每条记录有 **15 列**；以乾坤一掷 LV1 为例：

| 实际列号 | 字段 | 示例值 |
| --- | --- | --- |
| 1 | 招式名称 | 乾坤一掷LV1 |
| 2 | 效果处理器 | `TECH_Parameter` |
| 3 | 效果参数 | `AS:0,HR:-2,DD:10,` |
| 4 | Tech ID | 300 |
| 5 | 说明编号 | 130003 |
| 6 | 关联的 Skill ID | 3 |
| 7 | 技能等级或原生宠物/BOSS 标记 | 1 |
| 8 | 使用场景类别 | 1 |
| 9 | 目标范围码 | 1141 |
| 10 | COST 字段 | 空 |
| 11 | DRESSAGE 字段 | 空 |
| 12 | 魔力消耗 | 10 |
| 13 | 使用者标志 | 1（人类）；0 表示宠物 |
| 14、15 | 配方相关字段 | 空 |

```text
乾坤一掷LV1\tTECH_Parameter\tAS:0,HR:-2,DD:10,\t300\t130003\t3\t1\t1\t1141\t\t\t10\t1\t\t
```

第 7 列中，原生记录的 `30`、`50` 可分别作为宠物、BOSS 技能标记。本服另外建立了玩家 1～30 级的招式记录，因此应结合第 13 列及关联的 Skill 判断，不能只凭 `30` 就认定是宠物技能。

技能 ID、Tech ID、说明编号是不同字段。新增技能要给 Skill 和 Tech 分别选取未占用的编号，再通过 Tech 的第 6 列关联 Skill。动画表现需结合原生处理器和客户端资源验证。

### 技能效果示例

`TECH_ContinuationAttack` 的参数示例：

```text
AS:0,AN:2,AM:2,DD:80,
```

以下是常用参数的含义；实际支持哪些参数取决于处理器：

| 参数 | 含义 |
| --- | --- |
| `AN`、`AM` | 连续攻击次数相关参数 |
| `DD` | 伤害修正；`DD:80` 为增加 80% 的伤害修正 |
| `HR` | 命中修正 |
| `TR` | 攻击力修正，与伤害修正 `DD` 不同 |
| `AV` | 闪避修正 |
| `CR` | 必杀修正 |
| `AR` | 回复量相关参数，例如 `TECH_Revive` 的 `AR:6000` |

不能保证增加一个参数就能对所有处理器生效，也不能将攻击次数等同于必定攻击不同目标。当前定制技能的实现与验证方法见[职业技能包](docs/jobskill_pack/README_zh.md)。

### skilllv.txt：职业技能等级

| 实际列号 | 字段 | 当前记录示例 |
| --- | --- | --- |
| 1 | 记录编号 | 5860 |
| 2 | Skill ID | 64 |
| 3 | 具体职业 ID | 74 |
| 4 | 最高可学等级 | 30 |

```text
5860	64	74	30
```

这里的 `74` 是 `jobs.txt` 中某一职阶的具体职业 ID，不是整个职业体系的职类 ID。需要为目标职阶配置对应记录。

### jobs.txt：职业与职类

| 实际列号 | 字段 | 剑士示例 |
| --- | --- | --- |
| 1 | 职业名称 | 剑士 |
| 2 | 空列 | 保留 |
| 3 | 职业 ID | 12 |
| 4 | 职业类别 | 1 |
| 5 | 晋升金币需求 | 5000 |
| 6 | 晋升声望需求 | 10000 |

后续列也含职业相关配置，修改时应保留现有格式。职业 ID 表示具体职阶，职类 ID 表示同一职业体系：

| 职业体系 | 见习职业 ID | 职类 ID | 当前进阶示例 |
| --- | --- | --- | --- |
| 剑士 | 11 | 10 | 11 见习剑士、12 剑士、13 王宫剑士、14 剑术师范、15 剑术大师、16 武士、17 剑圣 |
| 弓箭手 | 41 | 40 | 41 起的弓箭手职阶 |

这些职业体系的职类 ID 为见习职业 ID 减 1。具体存在的职阶和晋升条件以 `jobs.txt` 为准，不应假设每个职业都有相同数量的职阶。

## 物品和宠物存档问题排查

若保存时出现 `Column count doesn't match value count` 或列数不匹配错误，先确认服务端使用的数据库类型以及数据库结构是否与当前程序匹配。

1. 查看 `gmsv/setup.cf` 的 `dbengine`：`1` 为 SQLite，`0` 为 MySQL。
2. 对照当前版本表结构检查报错表。SQLite 参考 [sqlite.sql](gmsv/sql/sqlite.sql)，MySQL 参考 [mysql.sql](gmsv/sql/mysql.sql)。初始化脚本用于新数据库，已有存档不能重新初始化。
3. SQLite 可通过以下查询查看字段及顺序，再与初始化结构对照；按实际缺少或错位的字段制定迁移。

   ```sql
   PRAGMA table_info(tbl_item);
   PRAGMA table_info(tbl_pet);
   ```

4. 修改已有数据库前正常关闭服务端并备份存档。修复后验证道具和宠物在正常保存、退出、重启后仍能恢复。

数据库账号、密码和库名以 `setup.cf` 为准。当前仓库提供 HTTP 账号注册页，不包含数据库管理网页。

## 维护工具与详细文档

| 工具或说明 | 用途 |
| --- | --- |
| [tools/skill-library/build.py](tools/skill-library/build.py) | 生成与校验技能 DATA 和永久技能库配置 |
| [tools/jobskill-pack/build_pack.py](tools/jobskill-pack/build_pack.py) | 构建职业技能包及关联配置 |
| [tools/cg71-pets/scan.py](tools/cg71-pets/scan.py) | 扫描宠物及客户端资源对应关系 |
| [tools/game-qol/run.py](tools/game-qol/run.py) | 构建、安装和在隔离服务端验证便捷功能 |
| [tools/content-audit/README.md](tools/content-audit/README.md) | 内容与依赖审计工具说明 |
| [永久技能库](docs/skill_library/README_zh.md) | 技能学习、15 栏装配、保存和等级规则 |
| [职业技能包](docs/jobskill_pack/README_zh.md) | 职业技能实现与配置 |
| [骑士装备](docs/knight_hybrid_gear/README_zh.md) | 骑士装备配置 |
| [宠物导入指南](docs/cg71_pet_import_guide_zh.md) | Enemy、种族与客户端形象编号的关系 |
| [Lua API 参考](lua参考/) | 服务端 Lua 接口说明 |
