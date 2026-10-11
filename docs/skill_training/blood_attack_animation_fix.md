# 人物吸血攻击动画兼容修复

本次客户端转储 `cgmsv.1DD592D93CC9099.crash.dmp` 记录访问违规 `0xC0000005`，故障地址 `0x4329E7`，无效读取地址 `0x7C317C5A`。转储确认客户端崩溃；没有完整战斗报文，不能单凭转储确定唯一触发原因。

隔离服务端捕获到人物吸血攻击（Skill 81）的原输出为 `M|SKL|s329|...|A|f1|d1|`。`s329` 是十六进制 809，对应圣盾之魂的特殊防御动画；吸血攻击的 Lua 处理却随后发送伤害动作。自定义人物吸血和人物 BOSS 吸血版本共用这个处理分支。

`skillLibrary:customCast` 现在仅在 `behavior='blood'` 时使用原生物理攻击动画 309（乾坤一掷，报文 `SKL|s135|`）。技能编号、已学等级、经验、伤害公式、30% 回血比例、回血上限与耗魔保留。动画借用不执行乾坤一掷的 DATA 伤害公式。此次没有修改 DATA、玩家存档或宠物技能，也没有新增游戏命令。回血仍通过现有结算及 `NLG.UpChar` 更新，没有新增未验证的回血动画协议。

UTF-8 源码 `tools/skill-library/skillLibrary.lua` 与 GBK 运行副本 `gmsv/lua/Modules/skillLibrary.lua` 已同步，保留各自原换行。修改前副本在 `backups/skill_library_blood_before.lua` 和 `backups/skill_library_blood_before_gbk.lua`。

生效：结束战斗后由 GM 输入 `/module reload skillLibrary`，然后重新登录客户端使用吸血攻击复测；或正常保存角色、退出游戏并重启服务端。无需遗忘重学。没有对正在运行的正式服务端进行重载或重启。

验证命令：`python tools/skill-library/training_verify.py blood_battle`，67 项检查通过。测试使用隔离服务端、端口 19210/19211 和空 SQLite 数据库，不读取玩家数据库。覆盖人物吸血攻击 1/30 级、BOSS 吸血攻击 E1/李贝留斯版 30 级，检查实际伤害、正数回血、回血上限、一次耗魔、经验及已学技能保留；还覆盖友方目标拒绝、缺魔拒绝，以及召唤和即死分支保持原行为。捕获的四种吸血报文均使用 `SKL|s135|`，没有 `SKL|s329|`。

修复前报文与失败检查保存在 `blood_battle_before_fix.json`；修复后结果见 `blood_battle_native_result.json`。`python tools/game-qol/verify_help.py` 检查游戏帮助、README 与编码副本一致。

验证边界：确认了动画选择修正和服务端结算；尚未用可见客户端完成修复前后动画播放对照，不能断言已排除全部闪退原因。如果更新后仍闪退，应保留新的转储继续定位。
