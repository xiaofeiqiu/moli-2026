# 台湾 7.1 内容核查工具

本目录的盘点工具只读取游戏 DATA，报告输出到 `D:\Games\CrossGate\docs\cg71_content_audit`。它们不能从客户端图档自动生成服务端任务或地图，也不代表官方 7.1 已补齐。

按顺序刷新报告：

```powershell
& 'C:\Users\xqiu3\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -X utf8 'D:\Games\CrossGate\tools\content-audit\audit_content.py'
& 'C:\Users\xqiu3\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -X utf8 'D:\Games\CrossGate\tools\content-audit\audit_crafting.py'
& 'C:\Users\xqiu3\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -X utf8 'D:\Games\CrossGate\tools\content-audit\compare_target.py'
& 'C:\Users\xqiu3\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -X utf8 'D:\Games\CrossGate\tools\content-audit\audit_candidate_warps.py'
```

上述工具使用 Python 标准库，不需要安装额外依赖。其他机器可以使用 Python 3.10 以上版本替换命令中的解释器路径。

- `audit_content.py`：有效配置路径、LS2MAP 两种格式、缓存地图、传送/NPC 坐标、脚本引用、技能/Tech/职业关系、原字节哈希。
- `audit_crafting.py`：职业系列/晋阶编号、制造 Tech 到配方范围、配方到技能/产物/材料的关系。配方编号可以不连续；名称不同只是复核候选。
- `compare_target.py`：将有来源的版本缺项与本地盘点比较，保留未知的官方编号、公式及地图数据。当前清单覆盖选定的已核实内容，尚不完整。
- `audit_candidate_warps.py`：检查公开天使大陆传送候选的地图依赖、坐标边界、编号和出口冲突。候选数据存于报告目录；工具不导入游戏 DATA，也不证明地图碰撞和任务流程正确。
- `restore_local_script.py`：早期用于写入游戏目录的工具，仅恢复道具 607651 的一个已核实脚本别名；不改表、不改奖励、不改宠物定义。

验证已经应用的脚本修复：

```powershell
& 'C:\Users\xqiu3\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -X utf8 'D:\Games\CrossGate\tools\content-audit\restore_local_script.py' verify
```

`apply` 已经执行；再次执行时只验证相同目标，不覆盖后续修改。只有显式运行 `rollback` 才删除本批新增的别名文件，并且哈希有变化时拒绝删除。原始字节快照和实施记录保留在 `D:\Games\CrossGate\backups\content71\legacy-item607651`。

静态盘点不执行游戏脚本。主服务端没有因本批修改而重启，未进行热加载或游戏内任务验收。报告里的缺失脚本包括旧测试地图和旧活动，不能全部归为新增版本任务。`baseline` 为首次盘点快照，后续运行不会替换它。

另外提供两个只读安装包检查工具：

- `audit_local_archive.py <7z 路径>`：读取完整 Unicode 文件索引，把地图和九个核心表解压至内存哈希流，与当前文件核对 SHA-256 和大小；检查缺失脚本是否可从原包恢复。没有解压到游戏目录或执行包内程序。此可选工具需要本次安装于 `.deps` 的 `py7zr 1.1.3`，没有改动全局 Python 环境。
- `audit_client_installer.py <zip 路径>`：使用标准库读取本次客户端的 InstallShield 20 头部，列出文件目录。只支持已经核实的此格式；没有运行安装器或解压 CAB 内容，不能用文件名检查证明任意程序内不存在嵌入资源。报告保存在 `sources/client_installer_inventory.json`。

用户提供的“全部任务共享”另有两个工具：

- `repair_zip_filenames.py`：依据原 ZIP 名称及内容哈希修复 `D:\BaiduNetdiskDownload\全部任务共享` 内的乱码文件名。限定此目录，校验所有文件，拒绝覆盖、越界路径、链接和未知碰撞；不转换脚本正文。`plan` 准备清单，`apply` 已执行，`verify` 只读校验，只有显式 `rollback` 才按日志恢复原名。操作清单和日志位于报告的 `sources` 目录。应用和回滚会写入游戏工作区之外的用户资料目录，需要相应文件权限。
- `audit_shared_task_pack.py`：只读盘点该包的地图、表文件、选定新增版本名称及缺失脚本；列出相同地图编号的不同内容。内嵌 RAR/ZIP 仅读取目录索引，不执行程序或导入游戏 DATA。此工具使用任务目录 `.deps` 中的 `rarfile 4.5`，没有修改全局 Python 环境。结果写入 `sources/shared_task_pack_inventory.json`。

只读验证已修复的文件名：

```powershell
& 'C:\Users\xqiu3\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -X utf8 'D:\Games\CrossGate\tools\content-audit\repair_zip_filenames.py' verify
```

首次改名后已经完成全部 12723 个文件的内容哈希校验。目录结构和脚本内容保留原包状态，不能根据地图编号缺失或任务名称直接认定属于台湾 7.1。


## 全部共享任务整合（2026-10-04）

共享包已经通过隔离原生验证并安装。准确的安装状态、数量、改编说明、入口坐标及备份见 `docs/cg71_content_audit/shared_integration/installation_report_zh.md`，历史只读盘点不代表本批当前状态。

- `integrate_shared_tasks.py stage` 构建未安装的批次，保留现有行并重编号；已安装批次禁止重建。
- `validate_shared_tasks_native.py` 准备、启动、停止隔离服务。`probe_shared_guide.py`、`run_shared_validation_suite.py` 验证入口、通路、职业、配方、奖励、战斗和可接近性。
- `install_shared_tasks.py apply` 只有静态检查、五项原生结果和实测文件都匹配本批指纹才安装；安装前备份，遇到并发编辑或失败拒绝覆盖并恢复已写文件。
- `install_shared_tasks.py rollback` 核验安装后文件未变后，恢复安装前快照。运行中的主服需正常重启加载安装或回滚结果。

该批覆盖共享包的全部任务资料，包括自制内容；不保证官方 7.1 原版复刻，也未逐条用客户端通关所有原作者任务链。
