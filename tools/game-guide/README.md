# 本服攻略维护

攻略保存在根目录的[攻略文件夹](../../攻略/README.md)。工具只读当前 DATA、Lua 运行文件和已有整合来源记录，不操作玩家存档、不启动或重载服务端。

在仓库根目录使用可用的 Python 3：

```powershell
python -X utf8 tools/game-guide/build_guides.py
python -X utf8 tools/game-guide/verify_guides.py
```

`build_guides.py` 重建任务索引、原生剧情页、全部共享目录页、目录外附属资料、NPC 对话分支页和来源核对记录。`新手攻略.md` 与宠装制造就职试炼为人工维护，不会被覆盖。修改生成页的写作方式应改工具，以免下次生成丢失。

`verify_guides.py` 检查本服目录项与附属资料覆盖、全部本地文件链接、UTF-8 文本、当前输入哈希，以及新手攻略依赖的等级倍率和圣殿位置。它不证明玩家客户端可以完整通关；未解释指令及缺少入口的内容在攻略核对记录中标明。

`inspect_sources.py` 提供只读搜索，例如 `python -X utf8 tools/game-guide/inspect_sources.py EV_ijk_start`。工具按当前表字段和地图头读取本服编号，不将共享原包编号直接用于玩家路线。
