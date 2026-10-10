"""Write the installed shop locations, stat policy and examples from verified output."""
import json
import re
from build import BASE, OUT, ROOT, STAGE, digest, records, number

manifest=json.loads((BASE/'manifest.json').read_text('utf-8'))
installed=json.loads((OUT/'installed.json').read_text('utf-8'))
raw=(OUT/'native_result.json').read_bytes()
try: result=json.loads(raw.decode('utf-8'))
except UnicodeDecodeError:
    result=json.loads(raw.decode('gbk'))
    (OUT/'native_result.json.gbk').write_bytes(raw)
    (OUT/'native_result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n','utf-8')
assert result['status']=='PASS'
later_changes=[]
observed_hashes={}
for path,row in installed['files'].items():
    raw=(ROOT/path).read_bytes()
    observed_hashes[path]=digest(raw)
    if observed_hashes[path]==row['after']:continue
    # Other authorized tasks may append DATA or add modules after this install.
    # Verify our own equipment entries and loader independently of those edits.
    if path=='gmsv/data/itemset.txt':
        expected={number(r[11]):r for r in records((STAGE/path).read_bytes())}
        current={number(r[11]):r for r in records(raw)}
        for item in manifest['items']:assert current[item['id']]==expected[item['id']],item['id']
    elif path=='gmsv/lua/ModuleConfig.lua':
        assert re.search(rb"(?m)^\s*loadModule\(['\"]knightHybridGear['\"]\)",raw),path
    else:raise AssertionError(path)
    later_changes.append(path)

lines=['# 魔骑装备店','',
    '已安装：每20个人物等级一家店，覆盖1～200级，共10家商店、100件装备。',
    '首次安装新增 itemset.txt 装备时，需要让服务端加载新的物品数据。',
    '物品数据已加载后，仅修改本模块的 NPC 位置、模型或 Lua 逻辑，可以使用 GM 角色在游戏聊天框输入 `/module reload knightHybridGear` 热重载，无需重启服务端。',
    '当前配置已加载 admin 模块；命令要求管理员权限。模块卸载会自动删除旧 NPC 并移除回调，再创建新的10家商店。',
    '安装过程未修改角色数据库，也未中断正式服务端。','',
    '## 商店位置','',
    '法兰城（地图1000），中心（153，139）附近。每店出售两档装备，每档包含枪、盾、头盔、铠甲、长靴。',
    '所有店都使用游戏原生购买窗口。店名表示装备适用的人物等级；玩家可以提前购买，穿戴时检查人物等级和骑士职业。',
    '店员统一使用士兵模型（14058），沿道路方向排列，人物等级依次递增，间隔两格。',
    '以下坐标已在隔离服务端实测；相邻店员坐标为X+2、Y不变。整排前方留出连续的可走空位；若整排受阻，会整体平移到附近空位，保持顺序和间距。','',
    '| NPC | 坐标 | 可接近坐标 |','|---|---|---|']
for shop in installed['shops']:
    lines.append(f"| {shop['name']} | {shop['x']}，{shop['y']} | {shop['approach']['x']}，{shop['approach']['y']} |")
lines+=['','## 属性和装备要求','',
    '- 枪保留原枪的攻击、命中、反击等属性，追加同档法杖的精神、魔攻，以及模板存在的魔力属性。枪为单手，可同时装备盾。',
    '- 头盔保留原属性，叠加同档帽子的正向属性；帽子模板没有精神时，另增加同档法杖精神的一半。',
    '- 铠甲保留原属性，叠加同档法袍的正向属性，包括魔力、回复及模板带有的其他加成。',
    '- 长靴保留原属性，叠加同档鞋子的正向属性，再增加同档法袍魔力的四分之一。',
    '- 盾保留原属性，再增加同档法杖精神、法袍魔力各四分之一。',
    '- 使用本地正常制造装备作为模板，保留骑士装备原有的减益；新增法师属性只叠加正向数值。同部位装备的正向数值随人物档次保持不下降。',
    '- 全系列默认已鉴定、耐久300。只有骑士职阶31～37能够装备，人物等级至少达到物品名标明的等级。原生骑士职业的装备职阶限制仍然生效。',
    '- 1～110级按每10级对应原生R1～R11。111～200级使用R11类型模板，每10级增加8%的正向模板属性，并由模块检查人物最低等级；没有新增R12～R20装备类别。',
    '- 售价按骑士原模板与法师属性模板的价格之和加25%；111级以上另按同档8%系数增长。购买使用金币。','',
    '## 例子','',
    '| 装备 | 最低人物等级 | 售价 | 属性范围 |','|---|---:|---:|---|']
for low in (1,11,91,191):
    for item in manifest['items']:
        if item['min_level']==low and item['type'] in (2,10):
            chosen=['攻击','防御','精神','命中','反击','魔力','魔攻']
            parts=[]
            for name in chosen:
                if name in item['stats']:
                    a,b=item['stats'][name]
                    parts.append(f'{name} {a}' if a==b else f'{name} {a}～{b}')
            lines.append(f"| {item['name']} | {low} | {item['price']} | {'；'.join(parts)} |")
lines+=['','全部100件装备的数值和售价见 [equipment.csv](equipment.csv)。','',
    '## 验证与备份','',
    f"装备首次安装时，同一版本的原生服务端通过{len(result['checks'])}项检查：10个原生商店生成、所有物品的ID/等级/售价/耐久/鉴定状态、300次随机物品生成及属性读取、五个等级档完整五件套的真实穿戴、角色魔攻生效、人物等级限制、其他职业限制。原有技能库、五宠和战斗模块在同一隔离实例中加载。",
    f"本次排布修改另通过{installed.get('layout_checks',0)}项原生服务端检查，覆盖士兵模型、原形、实际坐标、道路方向间距、等级顺序、所有购买物品及连续通行空间；结果见 `layout_result.json`。装备定义和穿戴检查逻辑保持首次安装版本。",
    '原生属性检查包括精神、魔攻、魔抗的实际读取；191级档套装已由200级骑士完整穿戴。',
    '未连接游戏客户端验收购买窗口和动画；验证结果不代表完成客户端操作测试。',
    '装备模块和装备数据模块的SHA-256与已验证暂存文件一致；物品表中的100件魔骑装备与首次验证的定义相同。其他任务后续对物品表和加载配置的更新单独记录在 `final_verification.json`。',
    f'备份：`{BASE.as_posix()}/original`；安装前后哈希及物品清单：`manifest.json`。',
    f"排布修改前的模块备份：`{installed.get('layout_backup','')}/original`。",
    '运行模块：`gmsv/lua/Modules/knightHybridGear.lua`，由 `gmsv/lua/ModuleConfig.lua` 加载。',
    '构建与测试源：`tools/knight-gear`；测试服务端使用独立SQLite数据库及端口19042，已关闭。','']
(OUT/'README_zh.md').write_text('\n'.join(lines),'utf-8')
summary={k:installed[k] for k in ('items','native_checks','requires_server_restart','client_verified')}
summary['shops']=len(installed['shops']);summary['installed_hashes_verified']=not later_changes
summary['layout_checks']=installed.get('layout_checks',0)
summary['gear_definition_records_verified']=True
summary['later_changes']=later_changes
summary['observed_hashes']=observed_hashes
(OUT/'final_verification.json').write_text(json.dumps(summary,indent=2)+'\n','utf-8')
print(json.dumps(summary))
