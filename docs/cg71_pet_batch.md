# CrossGate 7.1 宠物批量添加完成记录

已将全部 **403 个满足本次可用外观条件的未添加编号**写入服务端。新增 Enemy／EnemyBase／PETID 编号为 **30001–30403**，每个编号对应一个唯一外观。原宠物 30000／104866 保持原配置。

## 使用

主服务端保持运行，新增文件等待下一次正常重启加载。退出角色后，按原流程关闭并重新启动服务端，再登录 GM 账号 `test`。单只工具的 `activate` 只同步 30000 的名称，不会载入新增 403 个编号；重载测试 Lua 也不能代替 DATA 加载。

重启后先检查：

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua check
```

应返回 `ALL_OK count=403 ids=30001..30403`。然后可用原生命令：

```text
[nr makepet 30001]
[nr makepet 30403]
```

第一页和末页查询、单只领取以及原地遇敌：

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua list 1
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua list 41
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua grant 30001
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua battle 30001
```

把例子中的编号替换成清单里的任一新增编号。`grant` 不重复发放已持有的同编号宠物，满栏拒绝；`battle` 在当前角色非战斗状态时创建单只 1 级敌人。

完整 [编号／外观对应表](D:/Games/CrossGate/docs/cg71_pet_candidates.md)、[CSV](D:/Games/CrossGate/docs/cg71_pet_batch.csv)、[配置及哈希 JSON](D:/Games/CrossGate/docs/cg71_pet_batch.json)。

## 默认方案

名称使用自定义“异界兽 + 外观编号”，以便区分；官方名称未知，没有把这个名称标为官方。每个名称以 GBK 保存，不超过 16 字节。

全部继承此前通过验收的 30000 默认模板；只改名称、物种编号、EnemyBase 引用及外观。初始／升级点数为 20／5，体力／力量／强度／速度／魔法参数为 20／24／15／17／14，元素表内原值地 30／水 0／火 0／风 70，8 个技能栏，初始攻击 7300、防御 7400。AI、捕捉、掉落和图鉴字段原样保留，图鉴仍共用模板编号 1。

获取继续使用 GM 命令；没有新增公众遇敌、NPC、商店或独立图鉴配置。客户端资源、已有 DATA 行和角色数据库均未改动。

## 验证证据

添加前扫描 8 组资源库、32 个文件，解析并解压帧依赖，最终得到 403 个符合条件的缺失外观。跨库调色板及多个同编号版本均完成结构检查；完整方法见编号清单。

隔离原生服务端逐只完成：

- 403 个 Enemy／EnemyBase 编号和映射、GBK 名称及继承数值核对。
- 403 次真实原生 `Char.GivePet`，核对 PETID 72、当前及基础外观、名称字段 4000、技能栏和初始技能；随后清理临时宠物。
- 403 次 `Battle.PVE` 构建，核对战斗敌人外观，请求退出并清理独立假人。
- GM 工具全部编号查询、权限、登录、编号范围、重复领取、分页、禁用删除入口及战斗状态保护验证。

[逐只验证 TSV](D:/Games/CrossGate/docs/cg71_pet_batch_native_validation.tsv) 有 403 条 PASS。临时服务端已经停止，主服务端没有重启，助手没有写入真实玩家数据库。

此批验证覆盖原生创建和敌人构建，未逐只在游戏客户端走完整战斗回合或检查存档重登。客户端逐项显示和所有动作的实测不应标成已经完成；此前用户完成的外观、战斗、重登、重启验收属于 30000 单只概念验证。

## 文件、备份及清理

正式新增：`D:\Games\CrossGate\gmsv\data\enemybase.txt` 和 `D:\Games\CrossGate\gmsv\data\enemy.txt`，各追加 403 行。原文件全部字节作为前缀保留，既有行没有重编码。正式文件 SHA-256 在配置 JSON 中。

完整实施前 DATA 备份：`D:\Games\CrossGate\backups\cg71_pet_batch_023123e6`。该目录同时保留暂存后的 DATA、逐只验证结果以及不可自动执行的验证源码文本。已有宠物存档引用新编号后，直接恢复旧 DATA 会导致缺失定义，因此批次未提供自动回退到旧表的入口。

全部四个测试 Lua 与说明统一位于 `D:\Games\CrossGate\gmsv\lua\tests\cg71_pet_poc`。没有开机注册，按次调用。之后清理可先预览：

```powershell
& 'D:\Games\CrossGate\tools\Cleanup-CG71Tests.ps1' -WhatIf
```

去掉 `-WhatIf` 才实际清理；工具只删除哈希匹配的四个已知 Lua 和 README，并且仅删除空目录，保留正式 DATA、数据库、宠物和文档。本次仅验证预览，没有执行删除。

## 再次扫描

扫描工具：`D:\Games\CrossGate\tools\cg71-pets\scan.py`。它检查当前 EnemyBase 中仍未添加的外观，所以实施后符合本批条件的新增缺口应为空。再次扫描请使用不同输出文件名，保留添加前扫描 JSON。`--root D:\Games\CrossGate --output <新结果文件>` 为工具参数。

## 最终文件验收

[最终校验 JSON](D:/Games/CrossGate/docs/cg71_pet_batch_final_verification.json) 结果为 PASS：本次筛选的缺失外观已全部补齐，剩余 0；两份 DATA 的全部原字节及 30000 行不变；403 条新增记录所有默认字段一致；32 个客户端资源文件的 SHA-256 与扫描快照相同；五个测试文件清理哈希一致。清理 `-WhatIf` 与 PowerShell 语法检查通过，实际删除未执行。主服务端 PID 33104／39328 保持运行，隔离端口 19031 已关闭。

## 图片导出及运行状态更新

用户在重启说明后确认新增编号“可以用了”；未提供具体编号，不将此反馈记录为全部 403 只的逐只客户端验收。此前“等待正常重启”属于实施时状态。

已导出 403 张客户端静止首帧 PNG，集中于 `D:\Games\CrossGate\exports\cg71_pets\png`。双击 [本地相册](D:/Games/CrossGate/exports/cg71_pets/index.html) 可搜索编号并查看原图；7 张总览位于 `overview` 子目录。每张图保留透明背景和原始尺寸，文件名标明物种编号与外观编号。像素存储方向、调色板及动画反转标识已处理，所有 PNG 重读校验通过。资源解析依据见导出 manifest 中的原始源码链接。
