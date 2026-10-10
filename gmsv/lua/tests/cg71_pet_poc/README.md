# CrossGate 7.1 宠物验证工具

所有四个测试 Lua 均在本目录，使用已有 GM `/dolua` 按次加载，没有开机注册。`cg71_pet_batch_manifest.lua` 只是批次数据，由批量工具读取，不单独执行。

编号 30000 是此前通过外观、战斗、重登和重启测试的正式自定义宠物“异界兽”，外观 104866。新批次为 **30001–30403，共 403 只**，采用同样默认模板。DATA 已写入；正在运行的主服务端需要正常重启一次才能加载新增编号。`activate` 仅更新原有 30000 的名称，不能加载新批次。

## 批量工具

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua check
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua list 1
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua list 41
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua grant 30001
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua battle 30001
[nr makepet 30001]
```

`check` 核对全部 403 个编号、名称和外观；`list` 每页 10 条，共 41 页；`grant` 给当前 GM 生成一只 1 级宠物，已有同编号宠物时返回原宠物，不重复生成，满栏时拒绝；`battle` 原地生成一只对应的 1 级敌人，战斗中拒绝再次触发。

`grant`／`battle` 的编号只接受本批次的 30001–30403；这些工具不提供删除动作。GM 账号仍为已有的 `test`，不修改登录数据。完整编号及外观对应见 `D:\Games\CrossGate\docs\cg71_pet_candidates.md`。

## 原单只验证工具

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_poc.lua check
/dolua lua/tests/cg71_pet_poc/cg71_pet_poc.lua activate
/dolua lua/tests/cg71_pet_poc/cg71_pet_poc.lua list
/dolua lua/tests/cg71_pet_poc/cg71_pet_poc.lua status 0
/dolua lua/tests/cg71_pet_poc/gm_encount.lua poc
/dolua lua/tests/cg71_pet_poc/gm_encount.lua here
[nr makepet 30000]
```

`activate` 为当前服务端同步 30000 的正式名称；`poc` 原地生成一只 1 级 Enemy 30000；`here` 使用当前位置普通遇敌配置。宠物栏位 0–4，以 `list` 的 SLOT 为准。`swap`／`restore` 保留旧宠物临时外观测试及恢复用途。

30000 的 `remove` 已禁用。已有宠物个人名称保留。删除测试文件不会删除正式宠物。

## 统一清理

先预览：

```powershell
& 'D:\Games\CrossGate\tools\Cleanup-CG71Tests.ps1' -WhatIf
```

需要清理时去掉 `-WhatIf`。脚本先核对所有文件 SHA-256，再只移除本目录四个已知 Lua 和本说明；只删除空目录。DATA、数据库、正式宠物、备份和报告均保留。文件有后续编辑时停止，不移除未知文件。本次未执行清理。

旧 `Restore-CG71PetPoc.ps1` 的 DATA 回退入口已停用。新增批次备份位于 `D:\Games\CrossGate\backups\cg71_pet_batch_023123e6`；已有存档引用新编号后，不应直接覆盖回旧表。
