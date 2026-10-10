# moli-2026 服务端

本仓库保存 CrossGate 服务端及其维护工具。

- `gmsv/`：服务端程序、GBK 控制台适配器、Lua 模块、NPC 脚本和静态地图/游戏数据。
- `tools/`：服务端内容整合、修复和验证工具。
- `docs/`、`lua参考/`：服务端说明及 Lua API 参考。

客户端程序、图像、音效、客户端地图缓存、显示/语言工具，以及备份、日志、玩家数据库和运行存档不纳入版本控制。根目录采用白名单，避免后续 `git add .` 误加入客户端。

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
5. 旧式 `question.lua` 和 `nofix/EasyGM.lua` 含内置 GM 口令，仓库保存为同目录下的 `.lua.example` 脱敏模板；使用这些模块时，先复制回 `.lua` 文件并填写自己的口令。
6. 从 `gmsv` 目录启动 `cgmsv-gbk.exe`；该适配器会启动同目录的 `cgmsv.exe`。客户端需另行准备。

原有文件不转换编码或换行。服务端地图虽然是二进制文件，仍属于服务端必需的静态资源。
