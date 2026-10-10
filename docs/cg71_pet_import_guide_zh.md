# CrossGate 7.1 宠物导入服务端操作指南

适用于当前 `D:\Games\CrossGate` 中的 CGMSV DATA 格式，以及所提供的 7.1 客户端。本文包括本次 403 只宠物的迁移方法和以后增加宠物的步骤。

**当前安装已经完成导入，用户已确认新增编号可以使用，不必再次追加。** 新增编号为 **30001–30403**；原先验证通过的单只为 **30000／外观 104866**。

## 1. 宠物编号和外观编号

| 编号 | 用途 | 本批第一只 |
| --- | --- | ---: |
| Enemy 编号 | 战斗敌人定义；本批 makepet 使用的编号 | 30001 |
| EnemyBase 编号 | 基础属性、技能和外观定义 | 30001 |
| 外观／动画编号 | 客户端查找动作和图像资源 | 104353 |

本批 Enemy 与 EnemyBase 采用相同编号，生成后 PETID 也按该编号核对。外观编号属于另一套编号。

```text
[nr makepet 30001]
    → enemy.txt：Enemy 30001 引用 EnemyBase 30001
    → enemybase.txt：EnemyBase 30001 使用外观 104353
    → 客户端动画索引、动作帧、图档索引、像素和调色板
```

`[nr makepet 104353]` 不是这只宠物的生成命令。PNG 是给人查看的预览；游戏仍读取客户端原有的二进制资源，把 PNG 放到服务端不会增加宠物。

## 2. 本次涉及的文件

| 文件或目录 | 用途 |
| --- | --- |
| `D:\Games\CrossGate\gmsv\data\enemybase.txt` | 基础编号、成长、元素、技能栏、外观及初始技能 |
| `D:\Games\CrossGate\gmsv\data\enemy.txt` | Enemy 编号、EnemyBase 引用、AI 和掉落等 |
| `D:\Games\CrossGate\docs\cg71_pet_batch.json` | 403 个编号／外观对应和文件哈希 |
| `D:\Games\CrossGate\docs\cg71_pet_candidates.md` | 全部新增编号清单 |
| `D:\Games\CrossGate\exports\cg71_pets\index.html` | 可搜索的宠物相册 |
| `D:\Games\CrossGate\gmsv\lua\tests\cg71_pet_poc` | 四个测试 Lua 和 README，全部集中存放 |

本次只需添加服务端两份 DATA 中的记录，因为这些外观和调色板依赖已经在这份 7.1 客户端里。换其他客户端时，要重新确认资源存在。服务端定义本身不能补齐客户端缺失的图像。

## 3. 单只宠物如何添加

下面用实际 `30001 → 104353` 举例。当前表已经有这两行，这是结构说明，不要重复追加相同编号。

### enemybase.txt

复制已验证的 EnemyBase **30000** 整行，只改三列：

| 文本列号 | 含义 | 模板 | 新行 |
| ---: | --- | --- | --- |
| 1 | 名称 | 异界兽 | 异界兽104353 |
| 2 | EnemyBase 编号 | 30000 | 30001 |
| 31 | 外观／动画编号 | 104866 | 104353 |

列号从 **1** 开始，以实际 **Tab** 分隔。连续 Tab 中的空字段也算一列；本安装模板行共 **46 列**，尾部空列须保留。其余内容原样复制。

模板主要数值如下。这些是本安装的默认参数，并非对官方物种的原版属性恢复。

| 文本列号 | 配置 | 默认值 |
| --- | --- | --- |
| 3、4 | 初始点数、升级点数 | 20、5 |
| 6–10 | 体力、力量、强度、速度、魔法参数 | 20、24、15、17、14 |
| 16–19 | 地、水、火、风表内原值 | 30、0、0、70 |
| 30 | 技能栏数量 | 8 |
| 34 | 图鉴编号 | 1，沿用模板 |
| 37、38 | 初始技能 ID | 7300 攻击、7400 防御 |

### enemy.txt

复制已验证的 Enemy **30000** 整行，只改三列：

| 文本列号 | 含义 | 模板 | 新行 |
| ---: | --- | --- | --- |
| 1 | 名称 | 异界兽 | 异界兽104353 |
| 3 | Enemy 编号 | 30000 | 30001 |
| 4 | 引用的 EnemyBase 编号 | 30000 | 30001 |

本安装模板行共 **48 列**。第 2 列的 AI 字符串及其余捕捉、掉落字段均保留。本批没有新增公众地图遇敌、NPC 发放、商店或独立图鉴条目，获取使用已有 GM 命令。

### 编码和保存

新增中文名称使用 **GBK／代码页 936**，按本次已验证的限制控制在 **16 字节以内**；“异界兽104353”占 12 字节。名称是自定义别名，官方物种名称尚未确认。

新增行使用 CRLF，保留 Tab、空字段及尾部空列。原表含不同来源的名称字节，本次按字节追加，没有重编码整个文件。不要用 Excel 导入再另存这些 DATA；迁移时也建议按字节处理。

## 4. 将这 403 只迁移到另一份服务端

建议只追加目标缺失的记录，保留目标已有定义。直接覆盖整个 enemy／enemybase 表会覆盖目标原来的宠物和自定义配置。

### 迁移前

1. 确认目标采用相同 CGMSV DATA 格式，目标客户端也包含这批外观。
2. 退出角色，按正常流程关闭目标服务端，保留角色数据库备份。
3. 设置目标安装根目录：根目录下面应包含 `gmsv\data`。
4. 预先检查编号冲突；目标已使用不同内容的 30001–30403 时，必须另外分配编号，并同步修改两表及 Lua 清单。

下面的代码可将本安装的 403 组记录迁移到目标。它先检查所有编号：整行相同则跳过，同编号不同内容或重复编号则停止；两张表均通过后备份并追加。代码保持原有字节。它不能自动判定其他引擎版本的字段语义，相同格式是前提。

**代码仅写在本文供手动执行，写文档时没有运行导入。** 修改第一行的目标目录；Python 路径是本电脑已有运行库，换电脑后改为该电脑的 Python 3 路径。

```powershell
$cg71TargetRoot = '请改成目标安装根目录'
$cg71Python = 'C:\Users\xqiu3\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$cg71TargetRoot = [IO.Path]::GetFullPath($cg71TargetRoot)
if (-not (Test-Path -LiteralPath (Join-Path $cg71TargetRoot 'gmsv\data\enemybase.txt'))) {
    throw '目标目录错误：未找到 gmsv\data\enemybase.txt'
}
$cg71Engine = Join-Path $cg71TargetRoot 'gmsv\cgmsv.exe'
$cg71Wrapper = Join-Path $cg71TargetRoot 'gmsv\cgmsv-gbk.exe'
$cg71Running = Get-CimInstance Win32_Process | Where-Object {
    $_.ExecutablePath -eq $cg71Engine -or $_.ExecutablePath -eq $cg71Wrapper
}
if ($cg71Running) { throw '请先正常关闭目标服务端。' }
$env:CG71_IMPORT_TARGET = $cg71TargetRoot
@'
from pathlib import Path
import collections, datetime, hashlib, json, os, uuid
source = Path(r'D:\Games\CrossGate')
target = Path(os.environ['CG71_IMPORT_TARGET']).resolve()
manifest = json.loads((source/'docs/cg71_pet_batch.json').read_text('utf-8'))
pets = manifest['pets']
assert len(pets) == 403 and len({p['species_id'] for p in pets}) == 403

def rows(raw, column):
    found = collections.defaultdict(list)
    for line in raw.splitlines():
        fields = line.split(b'\t')
        if len(fields) <= column:
            continue
        try:
            key = int(fields[column])
        except ValueError:
            continue
        found[key].append((line, fields))
    return found

plans = []
for stem, id_column, width in [('enemybase', 1, 46), ('enemy', 2, 48)]:
    path = target/f'gmsv/data/{stem}.txt'
    old = path.read_bytes()
    destination = rows(old, id_column)
    donor = rows((source/f'gmsv/data/{stem}.txt').read_bytes(), id_column)
    additions = []
    for pet in pets:
        number = pet['species_id']
        assert len(donor[number]) == 1, f'来源编号缺失或重复：{stem} {number}'
        line, fields = donor[number][0]
        assert len(fields) == width, f'来源列数不符：{stem} {number}'
        assert fields[0].decode('gbk') == pet['name']
        if stem == 'enemybase':
            assert int(fields[30]) == pet['appearance_id']
        else:
            assert int(fields[3]) == pet['enemy_base_id'] == number
        existing = destination.get(number, [])
        if existing:
            assert len(existing) == 1 and existing[0][1] == fields, \
                f'目标编号冲突：{stem} {number}，请先人工处理'
        else:
            additions.append(line)
    separator = b'' if not old or old.endswith(b'\n') else b'\r\n'
    new = old + separator + b'\r\n'.join(additions) + b'\r\n' if additions else old
    plans.append((path, old, new, len(additions)))

if not any(count for _, _, _, count in plans):
    print('全部记录已经存在且一致，无需导入。')
    raise SystemExit(0)

stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup = target/'backups'/f'cg71_import_{stamp}_{uuid.uuid4().hex[:8]}'
backup.mkdir(parents=True)
for path, old, new, count in plans:
    assert path.read_bytes() == old, '目标表发生变化，停止。'
    (backup/path.name).write_bytes(old)
changed = []
try:
    for path, old, new, count in plans:
        if not count:
            continue
        assert path.read_bytes() == old, '目标表发生变化，停止。'
        temp = path.with_name(path.name + '.cg71-import.tmp')
        temp.write_bytes(new)
        os.replace(temp, path)
        changed.append((path, old))
except BaseException:
    for path, old in changed:
        temp = path.with_name(path.name + '.cg71-restore.tmp')
        temp.write_bytes(old)
        os.replace(temp, path)
    raise
record = {'backup': str(backup), 'files': [
    {'file': str(path), 'added_rows': count,
     'before_sha256': hashlib.sha256(old).hexdigest(),
     'after_sha256': hashlib.sha256(new).hexdigest()}
    for path, old, new, count in plans]}
(backup/'manifest.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(record, ensure_ascii=False, indent=2))
print('导入完成，请正常启动目标服务端并使用 GM 命令验证。')
'@ | & $cg71Python -X utf8 -
```

来源固定为当前 `D:\Games\CrossGate`，目标是你设置的根目录。新增两张表的行数通常各为 403；目标若已有部分完全相同的行，追加数量会减少。编号冲突时不要直接覆盖：另定空号后，必须同步 Enemy 编号、EnemyBase 编号、EnemyBase 引用和检查清单。

### 可选迁移 GM 检查工具

原生 `[nr makepet 编号]` 不依赖这些 Lua。要使用批量检查、查询、领取或战斗工具，则将以下两个文件复制到目标相同的相对目录：

```text
gmsv/lua/tests/cg71_pet_poc/cg71_pet_batch.lua
gmsv/lua/tests/cg71_pet_poc/cg71_pet_batch_manifest.lua
```

工具需要目标已有 `admin` 模块和 `/dolua` 支持，以及目标账号的 GM 权限。本安装账号 `test` 已有权限，复制 Lua 不会自动给另一份服务端的账号授权。工具按次加载，无需开机注册。

## 5. 重启加载与验证

**添加 DATA 后需要正常重启服务端。重新加载 Lua 不能替代 DATA 加载。** 此前“只有 30000 能用、其他没有反应”，就是旧服务端进程仍使用添加前的数据。

启动目标服务端并登录 GM 后，先执行：

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua check
```

本批正确返回：

```text
[CG71_BATCH] ALL_OK count=403 ids=30001..30403
```

查询第一页、末页，以及原生生成：

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua list 1
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua list 41
[nr makepet 30001]
[nr makepet 30403]
```

每页 10 条，共 41 页。先确认宠物栏有空位。以下 `grant` 为 GM 生成一只 1 级宠物，已有同编号宠物时返回原宠物，不重复发放，满栏拒绝：

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua grant 30001
```

原地生成一只相应的 1 级敌人；战斗中会拒绝再次执行：

```text
/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua battle 30001
```

实际验收应确认名称、外观、出战及主要动作正常，退出重登后保留，正常重启服务端后仍保留。图片导出和表格检查不能替代存档测试。

本批 403 只已在隔离原生引擎通过定义、真实宠物创建、技能和 PVE 敌人构建检查。用户随后确认新增编号可以用；没有记录全部 403 只的逐只客户端验收。原单只 30000 已由用户完成外观、战斗、重登和重启存档测试。

## 6. 以后如何添加新一批

1. 确认目标外观在客户端中存在；资源缺失时先做客户端资源导入及验证。
2. 用现有 `scan.py` 找出当前客户端未被 EnemyBase 引用且具备完整核心动作的外观，扫描结果另存新文件。
3. 查 `enemy.txt` 第 3 列和 `enemybase.txt` 第 2 列，选择两表都未占用的编号，并查外观是否已添加。
4. 本安装已占用 30000–30403。可以从 30404 起寻找空号，但必须实际查表；本批编号不超过 32767，不能将本次验证当作更大编号的边界证明。
5. 按第 3 节复制模板，改名称、编号、引用和外观，其余参数保留；以 GBK 字节追加并做好备份。
6. 先在独立副本验证原生加载、宠物生成和战斗，再应用到正式 DATA，正常重启并游戏内验收。
7. 新批次建立自己的编号清单。本批 Lua 清单固定是 403 只，`grant`／`battle` 只接受 30001–30403，不会自动包含后来新加的宠物。

重新扫描示例，**只生成结果，不修改 DATA**：

```powershell
& 'C:\Users\xqiu3\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -X utf8 `
  'D:\Games\CrossGate\tools\cg71-pets\scan.py' `
  --root 'D:\Games\CrossGate' `
  --output 'D:\Games\CrossGate\docs\cg71_pet_candidates_next.json'
```

扫描检查八组资源库、八方向核心动作、帧解压及调色板依赖，是保守的可用外观筛选；它不能恢复官方名称和属性，也不保证覆盖手工修复后可能可用的其他资源。`scan.py` 没有自动追加 DATA 的功能。

本次符合条件的 403 个缺失外观已全部添加。客户端资源未变化时，重扫不会再次找到这些缺口。不要覆盖原来的 `cg71_pet_candidates.json` 证据快照。

## 7. 常见问题

| 现象 | 核查方法 |
| --- | --- |
| 只有 30000 能用，新增编号无反应 | 正常重启服务端，确认启动的是修改过 DATA 的目录 |
| 重载 Lua 后仍无反应 | Lua 与 DATA 是不同加载路径，正常重启读取 DATA |
| `Species ... is not loaded` | 核对两表的编号、引用和是否已经重启 |
| GM 指令不执行 | 检查目标账号的 admin 权限和已有指令格式 |
| 外观错误、缺图或颜色异常 | 区分宠物／外观编号，检查客户端动画、帧和调色板 |
| 名称乱码 | 新中文名用 GBK，使用已配置中文兼容启动方式，避免整表重编码 |
| 领取失败 | 检查空栏位和是否已持有同编号宠物 |
| 普通地图遇不到 | 本次没有配置公众遇敌表，默认用 GM 获取 |
| 图鉴仍沿用虎人 | 图鉴编号保留模板值 1，独立图鉴需要额外配置 |

## 8. 备份、回退与测试清理

本次实施前 DATA 备份：

```text
D:\Games\CrossGate\backups\cg71_pet_batch_023123e6\gmsv\data\enemybase.txt
D:\Games\CrossGate\backups\cg71_pet_batch_023123e6\gmsv\data\enemy.txt
```

这些旧表包含单只 30000，不含 30001–30403。已有存档引用新编号后，恢复旧表会缺失定义；先保留定义并处理存档引用，再决定是否回退。删除测试脚本与移除正式宠物定义是两件事。

本安装测试 Lua 全部集中于 `D:\Games\CrossGate\gmsv\lua\tests\cg71_pet_poc`。统一清理先预览：

```powershell
& 'D:\Games\CrossGate\tools\Cleanup-CG71Tests.ps1' -WhatIf
```

需要实际清理时再去掉 `-WhatIf`。工具仅移除哈希匹配的四个已知 Lua 和 README，保留 DATA、数据库、宠物、备份和报告；文件改过则停止。若迁移到另一份安装，清理清单应按目标实际文件重新建立，不能直接套用本安装旧哈希。

原 30000 的测试删除入口和旧 POC DATA 回退入口已停用，不用于删除正式宠物。

## 9. 相关文件

- [403 只完整编号／外观清单](D:/Games/CrossGate/docs/cg71_pet_candidates.md)
- [批次完成记录](D:/Games/CrossGate/docs/cg71_pet_batch.md)
- [批次 JSON 与正式文件哈希](D:/Games/CrossGate/docs/cg71_pet_batch.json)
- [逐只原生验证结果](D:/Games/CrossGate/docs/cg71_pet_batch_native_validation.tsv)
- [中文兼容性分析](D:/Games/CrossGate/docs/cg7_compatibility_zh.md)
- [宠物图片相册](D:/Games/CrossGate/exports/cg71_pets/index.html)

如果以后要将另一份客户端的独有宠物资源搬进来，应另做客户端资源库、索引、动画帧和调色板的合并验证，不能直接套用本次只追加两张服务端 DATA 的步骤。
