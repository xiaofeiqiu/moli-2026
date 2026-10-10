"""Publish the installed batch's factual Chinese handover and retained history."""
import json,collections
from pathlib import Path
from integrate_shared_tasks import ROOT,BATCH,OUT,core,SPECS,save
m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'));assert m['status']=='applied'
installation=json.loads((OUT/'installation.json').read_text(encoding='utf-8'))
runtime_path=OUT/'production_runtime_status.json'
runtime=json.loads(runtime_path.read_text(encoding='utf-8')) if runtime_path.exists() else None
if runtime:
 assert runtime['manifest_sha256']==m['validated_manifest_sha256']
mapping=json.loads((OUT/'id_mapping.json').read_text(encoding='utf-8'))
notes=json.loads((OUT/'source_repairs.json').read_text(encoding='utf-8'))
units=json.loads((OUT/'source_units.json').read_text(encoding='utf-8'))
tasks=json.loads((OUT/'task_guide_catalog.json').read_text(encoding='utf-8'))
counts=collections.Counter(e['kind'] for e in mapping['entities'])
reports={n:json.loads((OUT/n).read_text(encoding='gbk')) for n in ['native_result.json','native_guide_result.json','native_adapters_result.json','native_services_result.json','native_access_result.json']}
assert all(r['state']=='PASS' and r['manifest_sha256']==m['validated_manifest_sha256'] for r in reports.values())
route=next(n for n in notes if n['kind']=='shared_route_collisions_adapted')
adapters=reports['native_adapters_result.json'];guide=reports['native_guide_result.json'];services=reports['native_services_result.json']
text=f'''# 共享任务整合安装报告

状态：已经安装到正式服务端文件。共写入 {installation['files']} 个文件，安装后全部 SHA-256 与已验证整合包一致。主服务端尚未由本任务重启，运行中的实例需要正常重启后加载新增 DATA 与模块。

范围覆盖下载包和嵌套压缩包内的 {len(units)} 个资料单元，包括自制任务、资料片、地图、NPC、物品、战斗、职业、技能和配方。目录提供 {len(tasks)} 项，{guide['entryWarps']} 项有接待入口，其余为场景资料；没有入口的纯技能、物品、战斗等资料仍已导入数据表。

| 新增内容 | 数量 |
| --- | ---: |
| 固定地图文件 | {len(mapping['maps'])} |
| NPC 数据行 | {counts['npc']} |
| 技能 | {counts['skill']} |
| 技能明细 Tech | {counts['tech']} |
| 职业系列 | {counts['jobsancestry']} |
| 职业阶级 | {counts['jobs']} |
| 道具 | {counts['itemset']} |
| 配方 | {counts['itemrecipe']} |
| 自动出口 | {route['automatic_routes_added']} |
| 冲突出口选择点 | {route['selection_points']} |

## 游戏入口

正常重启后，在法兰城寻找：

- **共享任务向导：155,112**。分页目录传送到接待地点，章节内前置、道具、等级、战斗条件由任务脚本检查。
- **远征后勤官：158,112**。办理共享包职业登记和晋阶、学习现有技能等级可用的配方，以及完成单人试炼后寻回缺少原获取渠道的自制材料。登记需要 20 级和 5000 魔币。
- **共享通路向导：161,112**。选择发生空间冲突的通路；有安全位置的区域也设置了本地“共享通路” NPC。

进入游戏的下一步：先正常退出角色保存，再按现有启动方式关闭并重新启动服务端，随后重新登录，到上述坐标接任务。本任务没有强行断开正在连接的角色。当前进程的启动时间和安装时间核对记录见 `production_runtime_status.json`。

## 兼容修复和改编

所有现有 DATA 行保留字节前缀，既有宠物、职业、技能和装备改动保留。安装前还合并了另一任务刚新增的 100 件魔骑装备及其模块配置，没有 ID 冲突。

各类数据使用引擎自己的 ID 空间，同类新增 ID 不与已有记录或其他新增记录冲突，引用同步改写。完整对应表见 `id_mapping.json`。原 ZIP、已修复名称的下载目录、原任务正文与导入来源均保留。

旧 GA/Moonboy 专用指令已经适配当前引擎。共补全 78 个缺失脚本、10 组缺失职业，缺图采用有记录的补建场景；部分战斗、物品和奖励依赖根据现有资料作自制改编。还修复 30 条零数量道具、31 个无法接近的 NPC，以及 5 张没有可通行地面的微型场景。{route['duplicate_routes_merged']} 条完全相同的出口已合并，不同目的地保留为可选通路。

这些改编是可玩的共享包适配，不能视作官方 7.1 内容、地图布局、技能公式和奖励的完整复刻。所有改编理由、原编号和来源保存在 `source_repairs.json`、`custom_script_designs.json` 和地图记录中。

## 验证

静态检查与五项原生验证全部通过，匹配同一个安装包指纹：`{m['validated_manifest_sha256']}`。

- 新增核心记录和全部地图由原生服务端读取，缺失引用清单为零。
- {guide['entryWarps']} 个接待入口、{guide['routeDestinations']} 个支路目的地实际传送成功，全部目录分页没有超过窗口选项上限。
- {len(services['jobs'])} 组职业的全部阶级完成就职、晋阶、费用及拒绝条件检查；{services['recipes']} 份配方通过技能等级菜单学习；{len(services['items'])} 类补全道具验证效果和消耗。
- {len(adapters['cases'])} 个补全提交/兑奖流程通过实际物品检查；真实原生战斗胜利、三轮连续挑战、重复领奖、满包、远距离、冷却和退出战斗不给奖分支通过。
- {reports['native_access_result.json']['checked']} 个非占位 NPC 位置的可接近性检查通过，剩余位置修复清单为零。

测试加载了正式模块组合，包括现有技能图书馆、五宠、职业技能、战斗命令和魔骑装备模块，仅把服务与 HTTP 端口改到隔离端口。使用独立 SQLite 与测试角色，没有使用正式账号或角色存档。尚未逐条用客户端通关所有原作者任务链。

## 备份和回滚

安装前快照：`{installation['backup']}`。安装清单：`{BATCH / 'manifest.json'}`。

执行 `tools/content-audit/install_shared_tasks.py rollback` 可以恢复本批安装前文件，并删除本批新增文件；它先核验所有目标仍匹配安装后哈希，后续文件被其他任务修改时会拒绝覆盖。回滚后同样需要正常重启。不要重新执行 `stage` 覆盖已经安装的批次。

原生接口参考：[战斗胜利回调](https://lua.cgmsv.com/battle.setwinevent.html)、[宠物学习技能](https://lua.cgmsv.com/pet.addskill.html)、[宠物回炉](https://lua.cgmsv.com/pet.rebirth.html)。
'''
(OUT/'installation_report_zh.md').write_text(text,encoding='utf-8')
save(OUT/'completion_metrics.json',dict(state='INSTALLED_RESTART_PENDING',units=len(units),catalogue=len(tasks),maps=len(mapping['maps']),added_entities=dict(counts),files=installation['files'],validation_reports=list(reports),production_runtime=runtime))
progress=ROOT/'docs/cg71_content_audit/progress_zh.md'
old=progress.read_text(encoding='utf-8')
prefix='本轮共享任务整合已经安装：300 个资料单元、281 项目录、3878 张地图、13 组职业（91 个阶级）、214 个技能、701 份配方。静态及五项隔离原生验证通过；主服需要正常重启加载。本轮采用用户允许的自制改编，详细状态见 shared_integration/installation_report_zh.md。下文保留此前版本资料核查和其他任务的历史记录。\n\n'
if not old.startswith(prefix):progress.write_text(prefix+old,encoding='utf-8')
readme=ROOT/'tools/content-audit/README.md';old=readme.read_text(encoding='utf-8').replace('唯一会写入游戏目录的工具','早期用于写入游戏目录的工具')
section='''\n\n## 全部共享任务整合（2026-10-04）

共享包已经通过隔离原生验证并安装。准确的安装状态、数量、改编说明、入口坐标及备份见 `docs/cg71_content_audit/shared_integration/installation_report_zh.md`，历史只读盘点不代表本批当前状态。

- `integrate_shared_tasks.py stage` 构建未安装的批次，保留现有行并重编号；已安装批次禁止重建。
- `validate_shared_tasks_native.py` 准备、启动、停止隔离服务。`probe_shared_guide.py`、`run_shared_validation_suite.py` 验证入口、通路、职业、配方、奖励、战斗和可接近性。
- `install_shared_tasks.py apply` 只有静态检查、五项原生结果和实测文件都匹配本批指纹才安装；安装前备份，遇到并发编辑或失败拒绝覆盖并恢复已写文件。
- `install_shared_tasks.py rollback` 核验安装后文件未变后，恢复安装前快照。运行中的主服需正常重启加载安装或回滚结果。

该批覆盖共享包的全部任务资料，包括自制内容；不保证官方 7.1 原版复刻，也未逐条用客户端通关所有原作者任务链。
'''
if '## 全部共享任务整合（2026-10-04）' not in old:readme.write_text(old+section,encoding='utf-8')
print(str(OUT/'installation_report_zh.md'))
