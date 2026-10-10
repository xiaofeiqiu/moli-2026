# 7.1 宠物最小验证：30000 → 104866

安装目录：`D:\Games\CrossGate`。

**当前状态：**编号 30000 已保留为正式自定义宠物“异界兽”。本文早期 `remove` 和 DATA 回退步骤为历史记录，当前测试删除功能已禁用。正式配置及当前操作见 [cg71_pet_30000.md](D:/Games/CrossGate/docs/cg71_pet_30000.md)。

已新增两条服务端定义：EnemyBase 30000、Enemy 30000，名称 `CG71_POC_104866`，外观 104866。属性、AI、技能、捕捉规则沿用原来的虎人模板。客户端图档、动画、启动配置和主数据库没有改动。

在隔离的服务端副本中，原生引擎已加载新增定义和 Lua 测试脚本，读取结果：

```text
PASS enemyIndex=4433 baseIndex=1587 baseId=30000 appearance=104866
```

这仅证明服务端加载成功。后续用户已通过原生 `nr makepet 30000` 命令生成测试宠物，并确认外观可用。宠物生成、7.1 客户端实际显示及后续战斗测试均已通过用户验证；用户也明确确认重登和重启服务端后宠物仍保留且外观正常。窗口控制工具初始化失败，游戏内操作由用户完成。本次启动日志还出现 skillexp/tech 数据警告；这些表在临时副本和主目录中的字节一致，本次没有修改。早期测试副本的警告记录不同，完整详情保存在验证记录中。

## 游戏内步骤

1. 正常运行一键启动，用已有 GM 角色登录。若服务端已在运行，关闭这一份服务端后重新启动，让新 DATA 生效。
2. 在聊天框执行：

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_poc.lua check
```

应看到 `DEFINITIONS_OK enemy=30000 base=30000 image=104866`。若报未加载，请确认启动的是 `D:\Games\CrossGate` 这一份服务端。

3. 先用一只可用于测试的旧宠物验证外观。以下的 `0` 是第一只宠物的位置；可换成 `0..4`。宠物原外观会保存在该宠物的扩展数据中，重新登录后仍可恢复。

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_poc.lua swap 0
```

正常让宠物出现在地图或战斗中，观察八个方向、行走、攻击、施法、受击、防御、死亡动作与颜色。若没有可用的旧宠物，可以先用现有 `/getPet 1` 获取原版虎人，再确认它所在的宠物位置。不要用重要宠物测试。

4. 恢复刚才的旧宠物：

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_poc.lua restore 0
```

5. 外观验证通过后，留一个空宠物位置，再生成新宠物：

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_poc.lua grant
```

应出现 `GRANT_OK`，且 petId、image、baseImage 分别为 `30000`、`104866`、`104866`。脚本会阻止同一角色重复生成这只测试宠物。

6. 根据宠物所在位置检查，例如第一只为 `0`：

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_poc.lua status 0
```

再重新登录并执行一次 `status`，确认物种与外观未改变。重复检查行走、战斗和颜色。成功前不要扩展到遇敌表、商店、图鉴或骑乘功能。

## 清理和回退

恢复所有执行过 `swap` 的旧宠物。删除新测试宠物时，先确认位置，再执行：

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_poc.lua remove 0
```

`remove` 使用宠物 PETID 字段 72 检查编号 30000，并要求当前外观和原形均为 104866；它会拒绝普通宠物、仅换过外观的旧宠物，以及原形不匹配的宠物。

删除前先执行只读列表命令：

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_poc.lua list
```

以输出的 `SLOT` 为准，找到 `petId=30000 image=104866 baseImage=104866` 的行，再把其 SLOT 数字填入 `remove`。SLOT 范围是 0–4。用户反馈宠物在位置 1 和 2，仍需通过这份运行时列表确认脚本编号。

关闭这份服务端后，运行备份目录中的 `Restore-CG71PetPoc.ps1`。它会检查修改后的文件和原备份哈希，再恢复两份 DATA 并移除测试 Lua；如果文件存在后续编辑，会停止，避免覆盖其他修改。备份、报告和验证记录会保留。

备份目录：`D:\Games\CrossGate\backups\cg71_pet_poc_b3b51de9`

回退脚本：`D:\Games\CrossGate\backups\cg71_pet_poc_b3b51de9\Restore-CG71PetPoc.ps1`

验证记录：`D:\Games\CrossGate\docs\cg71_pet_poc_validation.json`

测试脚本按需由 GM 命令执行，没有加入开机自动执行，也没有开放新的网络接口。根据用户后续要求，已有账号 `test`（CdKey 同为 `test`）已加入 `D:\Games\CrossGate\gmsv\lua\Modules\admin.lua` 的 GM 列表。正常退出角色、关闭一键启动并重新启动后生效。GM 配置原文件备份：`D:\Games\CrossGate\backups\gm_account_test_443f0f1c\admin.lua`。

## 后续验证记录

用户提供的游戏截图已显示 `DEFINITIONS_OK enemy=30000 base=30000 image=104866 indexes=4433,1587`，确认账号 `test` 的 GM 命令和服务端定义均已生效。

继续验证时可直接用 `grant` 生成独立、可清理的测试宠物，再检查画面和战斗；这样无需先调整已有宠物。后续用户直接执行 `nr makepet 30000`，已验证宠物生成及实际外观可用。此成功证据来自原生 makepet 命令；Lua `grant` 路径、完整战斗动作及重新登录后的保存效果尚未单独验证。

## 已通过：原生生成与外观

用户确认使用 `nr makepet 30000` 生成宠物并验证外观可用。当前最小 POC 已证明：新增服务端定义可创建宠物，所提供的 7.1 客户端能显示外观 104866。客户端资产没有增加或重写。原型属性仍沿用虎人模板，不代表该外观的官方物种数据。

## 清理字段修正

旧版脚本错误地用对象 EnemyBaseId 字段 61 判断宠物身份。已改用文档定义的 `宠物_PETID = 72`，同步修正生成去重、状态显示和清理检查，并加入只读 `list` 命令。失败的清理命令没有执行删除。脚本通过 `/dolua` 按次加载，使用新命令即可读取新文件，无需为该修改重启服务端。

Cleanup guard safety tests passed under the native Lua runtime using simulated pets: ordinary pets, cosmetic donors, mismatched appearances and empty slots were protected; only PETID 30000 with both appearances 104866 was accepted. No live pets were deleted by the assistant.

用户在修正 PETID 字段并获得 list/remove 操作步骤后回复 done，确认本轮清理完成。未单独提供战斗动作及重新登录保存的验证结果。

## 已通过：战斗、重登和服务端重启

用户已确认战斗测试通过，并明确确认退出重登及重启服务端后，宠物仍保留、外观正常。加上此前通过的原生生成及外观验证，单宠物最小兼容性验证已完成。上述游戏内结果由用户操作并报告；助手未独立观察全部 72 个动画条目的逐项覆盖。

原地战斗测试脚本：`D:\Games\CrossGate\gmsv\lua\tests\cg71_pet_poc\gm_encount.lua`，由已有 GM `/dolua` 按次加载，无需重启或重载 Lua。

```text
/dolua lua/tests/cg71_pet_poc/gm_encount.lua poc
```

生成一只 1 级 Enemy 30000 用于战斗测试。`here` 模式按当前位置配置触发普通遇敌，无遇敌配置的位置可能失败。

下一阶段需确定正式名称、成长／属性、技能和获取方式。当前编号 30000 及外观 104866 保留，属性和行为仍沿用虎人模板；不能视为已复刻该外观的官方物种数据。早期“尚未验证”段落属于当时状态，以本节和验证 JSON 的最新确认结果为准。

## 测试脚本集中存放

本轮两个 Lua 已移到 `D:\Games\CrossGate\gmsv\lua\tests\cg71_pet_poc`；本文命令已同步更新，无需重载 Lua。目录内 [README.md](D:/Games/CrossGate/gmsv/lua/tests/cg71_pet_poc/README.md) 记录全部入口和清理步骤。完整回退脚本已同步处理两个 Lua 及说明文件，并仅删除空的目录；本次只整理路径，未执行回退。

## 正式配置后续记录

用户选择默认方案：正式自定义名称“异界兽”，保留 Enemy／EnemyBase 30000、外观 104866，以及全部虎人模板数值、AI 和技能；仅修改两份 DATA 的名称列，并保留 GBK 编码和其他行的原始字节。获取继续使用 `[nr makepet 30000]`。未新增公众遇敌或 NPC 发放。

隔离原生服务端验证已通过：中文名称加载、名称字段 4000 的即时更新、成长／元素／技能原值保持、禁止测试删除、部分名称更新失败后的恢复。主服务端未中断，可执行 `/dolua lua/tests/cg71_pet_poc/cg71_pet_poc.lua activate`，或正常重启读取正式名称；已有宠物个人名称保留。

测试 `remove` 已禁用，旧 POC DATA 回退入口已停用；此前相关命令仅为历史记录。新 [Cleanup-CG71Tests.ps1](D:/Games/CrossGate/tools/Cleanup-CG71Tests.ps1) 仅清理校验通过的测试文件，保留正式 DATA 和宠物存档。正式说明：[cg71_pet_30000.md](D:/Games/CrossGate/docs/cg71_pet_30000.md)；完整配置记录：[cg71_pet_30000.json](D:/Games/CrossGate/docs/cg71_pet_30000.json)。
