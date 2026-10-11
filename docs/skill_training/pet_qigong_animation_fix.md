# 普通宠物气功弹画面卡死修复

症状：主宠使用「宠物气功弹LV1」后游戏画面卡住，服务端继续运行。

原因：宠物专用招式使用编号 910400～910409。原生服务器把这个编号原样写入战斗 `SKL` 报文，例如 LV1 的 `SKL|sDE440|...`。当前 `cg.exe` 以招式编号除以 100 的商选择动画处理器，因此进入未实现的动画类别 9104，动画状态无法继续。原版 400～409 则进入气功弹类别 4。静态解码证据与客户端 SHA256 见 `pet_qigong_client_decoder.txt`。

修复：`petSkillTutor` 在原生回合开始前，将主宠和五宠代理的普通气功弹战斗指令从 910400～910409 映射到 400～409，包含第一和第二行动栏。宠物已学编号和 AI 配置不变，仍可按原来的菜单学习、遗忘。普通气功弹参数和耗魔使用原版等级；人物、EX 与其他战斗命令不受这项映射影响。

文件：`tools/skill-library/petSkillTutor.lua` 为 UTF-8 源码，`gmsv/lua/Modules/petSkillTutor.lua` 为 GBK 运行副本，两份文件保留原来的 LF 换行。修复前备份在 `backups/pet_qigong_client_fix_20261010/before/`。

生效：先结束战斗，由 GM 输入 `/module reload petSkillTutor`，或正常保存角色并重启服务端。已经卡住的客户端需退出后重新登录。已有普通气功弹无需遗忘重学。本次没有修改玩家数据库或正在运行的服务端进程。

验证：`python tools/skill-library/training_verify.py pet_qigong_battle` 使用隔离服务端、独立端口和空 SQLite 数据库。先热重载 `petSkillTutor`，确认导师有效且只注册一个映射回调；再验证 LV1～LV10 的主宠手动和五宠 AI 两种施放方式，每种重复两次，共 20 个场景、40 次气功弹施放，并追加每个场景的零魔力回合，共 542 项检查通过。检查实际伤害回调、弹数范围、每次 5～50 MP、已学技能和 AI 编号保留，以及实际 `SKL` 报文使用 400～409。零魔力时主宠不执行气功弹，五宠伙伴回退普攻，都不会扣成负魔力或修改已学招式。LV1 修复后的报文为 `SKL|s190|...`。原生战斗记录见 `pet_qigong_battle_native_result.json`；修复前对照见 `pet_qigong_main_baseline.json` 和 `pet_qigong_proxy_baseline.json`。

验证边界：已验证原生结算、发出的动画报文和当前客户端的编号解码逻辑，尚未用可见客户端完成动画播放复测。截图中的迷宫出入口警告在正常完成施放的隔离测试中也出现，不能据此判断为这次画面卡死的原因。
