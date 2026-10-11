# 命令维护规则

- 每次新增命令、别名、子命令或修改参数，必须同步更新游戏内 `/help` 和根目录 `README.md` 的命令用法、参数、示例及生效限制。
- 帮助目录维护在 `tools/game-qol/commandHelp.lua`（UTF-8），同步生成 `gmsv/lua/Modules/commandHelp.lua`（GBK）。`gameQoL` 命令识别从此目录生成，不另写一份命令名单。
- 修改有 `tools/` 源码副本的 Lua 模块时，同步更新源码与 `gmsv/` 的 GBK 运行文件；保留原文件换行。
- GM 命令从模块的 `commandHandlers` / `extraHelpCommands` 动态列出；新增命令仍必须在帮助目录填写完整用法，并在 README 添加使用示例。
- 运行 `python tools/game-qol/verify_help.py` 检查已配置模块的命令、帮助、README 及 UTF-8/GBK 副本是否一致。修改帮助显示或解析行为时，用隔离服务端验证，不改玩家数据库。
