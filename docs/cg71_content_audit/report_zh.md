# CrossGate 内容盘点结果

此报告检查本地依赖，不代表已补齐官方 7.1。详细编号、文件和哈希见同目录 JSON 与 CSV。

## 基线

- native_map_files: 2663
- unique_map_floors: 2663
- extended_map_files: 358
- client_map_cache_files: 4
- npc_records: 10164
- npc_script_files: 6797
- referenced_script_files: 5209
- npc_referenced_script_files: 4165
- item_referenced_script_files: 1045
- missing_referenced_scripts: 35
- unresolved_referenced_map_floors: 1
- skills: {'records': 647, 'unique_ids': 647}
- techniques: {'records': 19915, 'unique_ids': 19915}
- skill_job_limits: {'records': 71103, 'unique_ids': 67883}
- jobs: {'records': 352, 'unique_ids': 352}
- items: {'records': 8842, 'unique_ids': 8842}

## 待核查地图

地图引用未解析时，可能缺少固定地图，也可能属于未识别的动态或条件路径，需要逐项确认。

- 地图 200：2 处引用。

## 缺少参数脚本

- dinwmtest.txt：1 个 NPC、0 个道具、0 处脚本引用。
- ev_miz_col36.txt：1 个 NPC、0 个道具、0 处脚本引用。
- eve_6026.txt：1 个 NPC、0 个道具、0 处脚本引用。
- goodertest.txt：1 个 NPC、0 个道具、0 处脚本引用。
- guleewmtest.txt：1 个 NPC、0 个道具、0 处脚本引用。
- item_rk_18997.txt：0 个 NPC、1 个道具、0 处脚本引用。
- item_rk_18998.txt：0 个 NPC、1 个道具、0 处脚本引用。
- item_rk_18999.txt：0 个 NPC、1 个道具、0 处脚本引用。
- item_tane_607652.txt：0 个 NPC、1 个道具、0 处脚本引用。
- mayko_gm_1102364.txt：1 个 NPC、0 个道具、0 处脚本引用。
- mayko_item_41028.txt：0 个 NPC、1 个道具、0 处脚本引用。
- mayko_item_41219.txt：0 个 NPC、1 个道具、0 处脚本引用。
- mayko_item_41220.txt：0 个 NPC、1 个道具、0 处脚本引用。
- mystery.txt：0 个 NPC、1 个道具、0 处脚本引用。
- mystery2.txt：0 个 NPC、1 个道具、0 处脚本引用。
- pons_test_kato_0001.txt：1 个 NPC、0 个道具、0 处脚本引用。
- pons_test_kato_0002.txt：1 个 NPC、0 个道具、0 处脚本引用。
- pons_test_kato_0003.txt：1 个 NPC、0 个道具、0 处脚本引用。
- pons_test_kato_0004.txt：1 个 NPC、0 个道具、0 处脚本引用。
- pons_test_kato_0005.txt：1 个 NPC、0 个道具、0 处脚本引用。
- te_item_41336.txt：0 个 NPC、1 个道具、0 处脚本引用。
- te_item_41337.txt：0 个 NPC、1 个道具、0 处脚本引用。
- te_item_41338.txt：0 个 NPC、1 个道具、0 处脚本引用。
- te_item_41339.txt：0 个 NPC、1 个道具、0 处脚本引用。
- te_item_41340.txt：0 个 NPC、1 个道具、0 处脚本引用。
- te_item_41341.txt：0 个 NPC、1 个道具、0 处脚本引用。
- te_item_41342.txt：0 个 NPC、1 个道具、0 处脚本引用。
- te_item_41343.txt：0 个 NPC、1 个道具、0 处脚本引用。
- te_item_41344.txt：0 个 NPC、1 个道具、0 处脚本引用。
- te_item_41345.txt：0 个 NPC、1 个道具、0 处脚本引用。
- te_item_41346.txt：0 个 NPC、1 个道具、0 处脚本引用。
- te_item_41347.txt：0 个 NPC、1 个道具、0 处脚本引用。
- vespa_gm_1101823.txt：1 个 NPC、0 个道具、0 处脚本引用。
- viviwmtest.txt：1 个 NPC、0 个道具、0 处脚本引用。
- watcheventtest.txt：1 个 NPC、0 个道具、0 处脚本引用。

## 使用限制

启动日志是磁盘快照，不证明当前进程已加载后续改动。地图层完整性检查不证明通行、出口或图档渲染正确。任务脚本存在不等于整个任务链可完成。怪物专用或定制 Tech 不会自动转为人物技能。
