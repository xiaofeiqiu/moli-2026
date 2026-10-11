from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
source=ROOT/'tools/equipment-enhance/equipmentEnhance.lua'
(ROOT/'gmsv/lua/Modules/equipmentEnhance.lua').write_bytes(source.read_bytes().decode('utf-8').encode('gbk'))
data=ROOT/'tools/equipment-enhance/equipmentEnhanceData.lua'
(ROOT/'gmsv/lua/Modules/equipmentEnhanceData.lua').write_bytes(data.read_bytes().decode('utf-8').encode('gbk'))
help_source=ROOT/'tools/game-qol/commandHelp.lua'
help_runtime=ROOT/'gmsv/lua/Modules/commandHelp.lua'
help_text=help_source.read_bytes().decode('utf-8')
existing=help_runtime.read_bytes()
help_text=help_text.replace('\r\n','\n')
if b'\r\n' in existing: help_text=help_text.replace('\n','\r\n')
help_runtime.write_bytes(help_text.encode('gbk'))
config=ROOT/'gmsv/lua/ModuleConfig.lua'
raw=config.read_bytes()
nl=b'\r\n' if b'\r\n' in raw else b'\n'
line=b"loadModule('equipmentEnhance')"
if line not in raw: config.write_bytes(raw+nl+line+nl)
