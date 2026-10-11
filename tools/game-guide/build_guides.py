"""Build local player guides from current installed DATA, without running scripts.

Every catalog unit is retained, including scene-only units. Branch transcripts
preserve control flow and unresolved commands rather than inventing a route.
"""
from __future__ import annotations

import collections
import hashlib
import json
import re
from functools import lru_cache
from urllib.parse import quote
from pathlib import Path

import inspect_sources as src

ROOT = src.ROOT
OUT = ROOT / '攻略'
REPORTS = ROOT / 'docs/cg71_content_audit/shared_integration'
USED = {}
WARNINGS = []
DETAILS = {}


def read(path):
    USED[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return src.text(path)


class LuaData:
    """Strict reader for generated literal-only Lua tables; never execute Lua."""
    def __init__(self, value):
        value = re.sub(r'^\s*return\s+', '', value)
        self.tokens = re.findall(r'"(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?|nil|true|false|[{}\[\]=,]', value)
        remainder = re.sub(r'"(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?|nil|true|false|[{}\[\]=,]|\s+', '', value)
        if remainder:
            raise ValueError('Unexpected Lua syntax: ' + remainder[:80])
        self.pos = 0

    def take(self):
        token = self.tokens[self.pos]
        self.pos += 1
        return token

    def value(self):
        token = self.take()
        if token == '{':
            seq, obj = [], {}
            while self.tokens[self.pos] != '}':
                if self.tokens[self.pos] == '[':
                    self.take()
                    key = self.value()
                    assert self.take() == ']'
                    assert self.take() == '='
                    obj[key] = self.value()
                else:
                    seq.append(self.value())
                if self.tokens[self.pos] == ',':
                    self.take()
            self.take()
            if obj:
                assert not seq
                return obj
            return seq
        if token.startswith('"'):
            return json.loads(token)
        if token == 'nil':
            return None
        if token in ('true', 'false'):
            return token == 'true'
        return float(token) if '.' in token else int(token)

    def parse(self):
        result = self.value()
        assert self.pos == len(self.tokens)
        return result


def data_lua(name):
    return LuaData(read(ROOT / 'gmsv/lua/Modules' / name)).parse()


CATALOG = data_lua('sharedTaskGuideData.lua')['tasks']
ADAPTERS = {c['key']: c for c in data_lua('sharedTaskAdaptersData.lua')}
MAGIC = data_lua('magicTaskJobsData.lua')
MAPPING = json.loads(read(REPORTS / 'id_mapping.json'))
UNITS = {c['id']: c for c in json.loads(read(REPORTS / 'source_units.json'))}
NPC_BY_ID = collections.defaultdict(list)
NPC_BY_SCRIPT = collections.defaultdict(list)
for n in src.NPCS:
    NPC_BY_ID[n['id']].append(n)
    if n['kind'] == 'event':
        NPC_BY_SCRIPT[n['payload'].casefold()].append(n)


def fields(name, key):
    read(src.DATA / name)
    return {src.number(c[key]): c for ln, c in src.rows(name) if len(c) > key}


ITEM_ROWS = fields('itemset.txt', 11)
ITEMS = {k: c[1] or c[0] for k, c in ITEM_ROWS.items()}
JOBS = {k: c[0] for k, c in fields('jobs.txt', 2).items()}
ENEMIES = fields('enemy.txt', 2)
SPECIES = fields('enemybase.txt', 1)
GROUPS = fields('group.txt', 2)
ENCOUNTERS = fields('encount.txt', 0)
TITLES = {k: c[1] for k, c in fields('titlename.txt', 0).items() if len(c) > 1}
RECIPES = {k: c[0] for k, c in fields('itemrecipe.txt', 1).items()}
read(src.DATA / 'npc.txt')
read(src.DATA / 'msg.txt')
read(src.DATA / 'warp.txt')
WARPS = [dict(floor=int(c[1]), x=int(c[2]), y=int(c[3]), to=int(c[4]), tx=int(c[5]), ty=int(c[6]), line=ln)
         for ln, c in src.rows('warp.txt') if len(c) == 7 and all(src.number(x) is not None for x in c)]
UNIT_NPCS = collections.defaultdict(list)
IMPORTED_NPC_IDS = {e['new_id'] for e in MAPPING['entities'] if e['kind']=='npc'}
for e in MAPPING['entities']:
    if e['kind'] == 'npc':
        for unit in e['units']:
            UNIT_NPCS[unit].extend(NPC_BY_ID.get(e['new_id'], []))


def unique(values, key=lambda v: v):
    seen = set()
    result = []
    for v in values:
        k = key(v)
        if k not in seen:
            seen.add(k)
            result.append(v)
    return result


def escape(value):
    return str(value).replace('|', '／').replace('\n', ' ').replace('\r', '')


def mapname(floor):
    if floor == 777:
        return '随机地图 NPC 模板'
    path = src.MAP_PATHS.get(floor)
    if path and path.relative_to(ROOT).as_posix() not in USED:
        read(path)
    return src.MAPS.get(floor, '地图 ' + str(floor)).split('|')[0].strip()


def location(n):
    kind = n.get('mapType', 0)
    return f"{mapname(n['floor'])}（地图 {n['floor']}，类型 {kind}）{n['x']},{n['y']}"


def item(value):
    n = src.number(value)
    return f"{ITEMS.get(n, '未命名道具')}〔{value}〕"


def enemy(value):
    n = src.number(value)
    c = ENEMIES.get(n)
    if not c:
        return '敌人〔' + str(value) + '〕'
    base = SPECIES.get(src.number(c[3]), [])
    name = c[0]
    if re.search('[ぁ-ヺ]', name) and base:
        name = base[0]
    return f'{name}〔{value}〕'


def quantity(value):
    if not value:
        return '（数量按原生命令默认值）'
    return ' ×' + str(value)


def condition(value):
    # Inline comments occur after a condition in several native files.
    value = value.split('#', 1)[0]
    def lua_condition(m):
        key = m[1]
        if key in MAGIC:
            c = MAGIC[key]
            return '职业条件【' + condition(c['source']) + '；魔剑士按同职阶剑士或魔法师兼容规则检查】'
        c = ADAPTERS.get(key)
        if c and c.get('kind') == 'legacy' and c.get('value') is None:
            target = {'player': '人物', 'pet': f"第{c.get('slot',0)+1}只宠物", 'item': f"背包指定栏位{c.get('slot',0)}道具"}.get(c.get('target'), '对象')
            if c.get('jobRangeJobs'):
                return '职业在【' + '、'.join(JOBS.get(n, str(n)) for n in c['jobRangeJobs']) + '】时返回1'
            return target + c.get('field', '').removeprefix('CHAR_')
        return '扩展条件〔' + key + '〕'
    value = re.sub(r'(?i)Luac\s+(\S+)', lua_condition, value)
    value = re.sub(r'(?i)\b(Item|Leak0Item|Leak1Item|HaveItem|EquipItem)[ _]*(\d+)',
                   lambda m: {'item': '持有 ', 'leak0item': '未鉴定持有 ', 'leak1item': '鉴定持有 ', 'haveitem': '持有编号 ', 'equipitem': '装备 '}[m[1].lower()] + item(m[2]), value)
    value = re.sub(r'(?i)\b(?:HaveTitle|Title)[ _]*(\d+)', lambda m: '称号 ' + TITLES.get(int(m[1]), '〔'+m[1]+'〕'), value)
    value = re.sub(r'(?i)\b(EndEvent|NowEvent|GlobalFlag|LocalFlag|LocalCount)[ _]*(\d+)',
                   lambda m: {'endevent': '完成记录', 'nowevent': '进行记录', 'globalflag': '全局标记', 'localflag': '局部标记', 'localcount': '局部计数'}[m[1].lower()] + ' ' + m[2], value)
    replacements = {'ItemSpace': '物品空位数', 'PetSpace': '宠物空位数', 'Level': '人物等级', 'Gold': '魔币',
                    'Group': '队伍人数', 'JobAncestry': '职业系列编号', 'JobRank': '职阶', 'Job': '职业编号',
                    'Rank': '职阶', 'NowTime': '游戏时段', 'Fame': '声望', 'LP': '生命', 'FP': '魔力',
                    'StrCmpChat': '聊天完全匹配', 'StrStrChat': '聊天包含', 'Trialflg': '出生试炼标记'}
    for k in sorted(replacements, key=len, reverse=True):
        value = re.sub(r'(?i)\b' + k + r'\b', replacements[k], value)
    return value.replace('&&', ' 且 ').replace('||', ' 或 ').replace('==', '＝').replace('!=', '≠').strip() or '无额外条件'


def clean_dialog(value):
    return re.sub(r'@[cnb]|\\[nrt]', ' ', value).strip().replace('　', ' ')


def dialogue(value):
    q = re.match(r'\s*"((?:\\.|[^"\\])*)"', value)
    if q:
        message = q[1].replace('\\"', '"')
        rest = value[q.end():]
    else:
        m = re.match(r'\s*(\d+)', value)
        if not m:
            return value
        message = src.MESSAGES.get(int(m[1]), '对话编号 ' + m[1])
        rest = value[m.end():]
    buttons = unique(re.findall(r'(?i)\b(yes|no|ok|next|cancel|prev)\b', rest))
    labels = {'yes': '是', 'no': '否', 'ok': '确定', 'next': '下一页', 'cancel': '取消', 'prev': '上一页'}
    return '“' + clean_dialog(message) + '”' + ('；选项：' + '、'.join(labels[b.lower()] for b in buttons) if buttons else '')


def pairs(values):
    return '、'.join(item(r[0]) + quantity(r[1]) for r in values)


def adapter_description(c):
    kind = c.get('kind')
    if kind == 'legacy':
        who = {'player': '人物', 'pet': f"第{c.get('slot',0)+1}只宠物", 'item': '指定背包栏位道具'}.get(c.get('target'), '对象')
        field = c.get('field', '').removeprefix('CHAR_')
        if c.get('value') is None:
            return '读取' + who + field + '作为条件值'
        v = c['value']
        suffix = JOBS.get(v, str(v)) if field == '职业' else str(v)
        return who + field + ('增加 ' if c.get('mode') == 1 else '设为 ') + suffix + (f"，上限 {c['limit']}" if c.get('mode') == 1 and c.get('limit', -1) >= 0 else '')
    if kind in ('exchange', 'battle'):
        info = []
        if c.get('level'):
            info.append(f"人物至少 {c['level']} 级")
        if c.get('cost'):
            info.append(f"支付 {c['cost']} 魔币")
        if c.get('need'):
            info.append(('持有并保留 ' if c.get('retainNeeds') else '提交并消耗 ') + pairs(c['need']))
        if c.get('needDone'):
            info.append('需要前置调查记录 ' + c['needDone'])
        if kind == 'battle':
            rounds = c.get('rounds', [])
            info.append(f'单人连续挑战 {len(rounds)} 轮')
            for i, group in enumerate(rounds, 1):
                info.append(f"第{i}轮：" + '、'.join(enemy(r[0]) + f' 等级{r[1]}' for r in group))
            info.append('必须实际胜利，逃跑或中止不给奖；满包时保留待领取胜利记录')
        if c.get('give'):
            info.append('获得 ' + pairs(c['give']))
        if c.get('once'):
            info.append('该奖励只能领取一次')
        if c.get('cooldown'):
            info.append(f"领取后冷却 {c['cooldown']} 秒")
        if c.get('setDone'):
            info.append('写入后续章节所需调查记录 ' + c['setDone'])
        if c.get('warp'):
            v = c['warp'];info.append(f'传送至 {mapname(v[1])}（{v[1]}）{v[2]},{v[3]}，类型{v[0]}')
        return '；'.join(info)
    if kind == 'marker':
        return '记录本段调查完成，供后续章节检查'
    if kind == 'item':
        return '使用扩展道具，效果类型 ' + str(c.get('itemMode'))
    if kind == 'petTeacher':
        return '为第一只宠物学习宗师技能，需要空技能格并支付 ' + str(c.get('cost', 0)) + ' 魔币'
    return '执行扩展服务，具体菜单见当前 NPC 提示'


def encounter(value):
    p = value.split('|')
    enc = src.number(p[9]) if len(p) > 9 else None
    names = []
    drops = []
    c = ENCOUNTERS.get(enc, [])
    for gid in c[14:24]:
        g = GROUPS.get(src.number(gid), [])
        for eid in g[5:15]:
            e = ENEMIES.get(src.number(eid))
            if e:
                names.append(enemy(eid) + (f'，基础等级范围 {e[4]}～{e[5]}' if e[4] and e[5] else ''))
        for v in g[3:5]:
            if src.number(v) in ITEMS:
                drops.append(item(v))
    description = '触发战斗'
    if enc is not None:
        description += f'（战斗配置 {enc}）'
    if names:
        description += '；候选敌组包含：' + '、'.join(unique(names))
    if len(p) > 1 and re.fullmatch(r'\d+,-?\d+,-?\d+,-?\d+', p[1]):
        t, f, x, y = map(int, p[1].split(','))
        if f:
            description += f'；配置的战后传送目标：{mapname(f)}（{f}）{x},{y}，类型{t}'
        else:
            description += '；战后传送字段未指定有效地图，不能据此把地图 0 当成任务目的地'
    if len(p) > 2 and src.number(p[2]) in ITEMS:
        description += '；战斗参数关联道具：' + item(p[2]) + '（是否消耗按原生战斗规则）'
    if drops:
        description += '；敌组数据关联物品：' + '、'.join(unique(drops)) + '（不是保证掉落或最终奖励）'
    return description


KNOWN = {'block', 'window_yes', 'window_no', 'window_ok', 'if', 'else', 'endif', 'endblock', 'window',
         'endwindow', 'message', 'systemmessage', 'warp', 'leavegroup', 'giveitem', 'giveleak0item',
         'giveleak1item', 'givestackitem', 'killitem', 'killitemall', 'killleak0item', 'killleak1item',
         'addgold', 'givepet', 'giverecipe', 'encount', 'luac', 'endevent', 'nowevent', 'globalflag',
         'localflag', 'localcount', 'gotof', 'gotob', 'checktitle', 'setlp', 'setfp', 'setdur',
         'playse', 'play_se', 'setobject', 'metamo'}


def split_command(line):
    # Longest recognized prefix handles Window"...", Item123, and Warp,....
    m = re.match(r'((?:giveleak[01]item|killleak[01]item)|[A-Za-z_]+)(.*)', line, re.I)
    if not m:
        return '', line
    command = m[1].lower()
    command = {'windowyes':'window_yes','windowno':'window_no','windowok':'window_ok'}.get(command, command)
    return command, m[2].strip()


def instruction(command, value):
    if command == 'block':
        return '交谈分支条件：' + condition(value)
    if command.startswith('window_'):
        label = {'window_yes': '是', 'window_no': '否', 'window_ok': '确定'}.get(command, command)
        return f'点击“{label}”后，检查：' + condition(value)
    if command == 'if':
        return '若满足：' + condition(value) + '，执行下列对应分支'
    if command == 'else':
        return '否则，执行下面的另一分支'
    if command == 'endif':
        return '结束上述条件分支'
    if command == 'endblock':
        return '结束本交谈分支'
    if command in ('window', 'endwindow', 'message', 'systemmessage', 'gawindow', 'gaendwindow'):
        return ('显示结束对话：' if command in ('endwindow','gaendwindow') else '对话提示：') + dialogue(value) + ('（GA 系列原生窗口）' if command.startswith('ga') else '')
    if command == 'warp':
        a = [src.number(x.strip()) for x in value.lstrip(',').split(',')[:4]]
        if len(a) == 3:
            a.insert(0, 0)
        if len(a) == 4 and all(x is not None for x in a):
            t, f, x, y = a
            return f'传送至 {mapname(f)}（地图 {f}，类型 {t}）{x},{y}'
        return '传送参数需按原生格式核对：`' + value + '`'
    if command == 'leavegroup':
        return '离开队伍，再执行后续个人步骤'
    if command in ('giveitem', 'giveitemex', 'giveleak0item', 'giveleak1item', 'givestackitem', 'killitem', 'killitemall', 'killleak0item', 'killleak1item'):
        verb = '消耗或删除 ' if command.startswith('kill') else '获得 '
        if command == 'killitemall':
            verb = '删除全部同编号道具 '
        if '%' in value or '$' in value:
            options = re.findall(r'(\d+)\s*%\s*(\d+)(?:\$(\d+))?', value)
            return verb + '随机候选：' + '、'.join(item(i) + f'（权重参数 {w}' + (f'，数量参数 {q}' if q else '') + '）' for i, w, q in options) + '；概率按原生命令解释，不合并成必得奖励'
        a = value.split(',')
        if a and re.fullmatch(r'\d+', a[0].strip()):
            return verb + item(a[0].strip()) + quantity(a[1].strip() if len(a) > 1 else '')
        return verb + '按原生参数：`' + value + '`'
    if command == 'addgold':
        n = src.number(value)
        return (f'支付 {-n} 魔币' if n is not None and n < 0 else f'获得 {n} 魔币') if n is not None else '魔币变化参数：`' + value + '`'
    if command == 'givepet':
        ids = re.findall(r'\d+(?=%)|^\d+', value)
        return '获得宠物，候选：' + '、'.join((SPECIES.get(int(i), ['宠物'])[0] + '〔'+i+'〕') for i in ids) + ('；按脚本的随机权重选择' if '%' in value else '')
    if command == 'giverecipe':
        ids = re.findall(r'\d+', value)
        return '领取配方：' + '、'.join(RECIPES.get(int(i), '配方〔'+i+'〕') for i in ids)
    if command == 'encount':
        return encounter(value)
    if command == 'luac':
        c = ADAPTERS.get(value)
        return adapter_description(c) if c else '扩展调用：`' + value + '`（见扩展适配器）'
    if command in ('endevent', 'nowevent', 'globalflag', 'gaglobalflag', 'localflag', 'localcount'):
        return '更新任务状态：' + condition(command.removeprefix('ga') + ' ' + value)
    if command in ('gotof', 'gotob'):
        return '跳转到交谈节点 `' + value + '`，继续该节点的步骤'
    if command == 'checktitle':
        return '重新检查并更新称号资格'
    if command in ('setlp', 'setfp'):
        return ('设置生命：' if command == 'setlp' else '设置魔力：') + value
    if command == 'setdur':
        return '改变道具耐久，原生参数：`' + value + '`'
    if command in ('playse', 'play_se', 'setobject', 'metamo'):
        return {'playse': '播放音效', 'play_se': '播放音效', 'setobject': '改变场景对象', 'metamo': '变化外观'}[command] + '；参数 `' + value + '`'
    if command == 'addstampcount':
        return '改变道具的印记计数；原生参数 `' + value + '`，不能把计数增加当成直接发放物品'
    if command == 'setvisitor':
        return '更新访客计数；原生参数 `' + value + '`'
    if command == 'changepal':
        return '改变场景色调；原生参数 `' + value + '`'
    if command == 'shapenext':
        return '改变 NPC 外观；原生参数 `' + value + '`'
    if command in ('shipchardown','shipchartake'):
        return ('下船' if command=='shipchardown' else '登船') + '；航线参数 `' + value + '`'
    if command == 'setloginpoint':
        return '改变登录地点设置；原生参数 `' + value + '`'
    if command in ('globaltimera','globaltimerb'):
        return '更新全局计时器；原生参数 `' + value + '`'
    if command == 'setaction':
        return '设置角色动作；原生参数 `' + value + '`'
    if command == 'addskillslot':
        return '执行技能栏位增加指令；是否已领取及上限由该分支检查'
    return None


@lru_cache(maxsize=None)
def script_lines(filename):
    p = src.DATA / 'npc' / filename
    if not p.is_file():
        return []
    return read(p).replace('\r\r\n', '\n').replace('\r\n', '\n').split('\n')


def detail(filename):
    name = filename.casefold()
    if name in DETAILS:
        return DETAILS[name]
    lines = script_lines(filename)
    stem = safe_filename(Path(filename).stem) or '未命名脚本'
    path = OUT / '任务步骤' / (stem + '.md')
    locations = unique(NPC_BY_SCRIPT.get(name, []), key=lambda n: (n['name'], n['mapType'], n['floor'], n['x'], n['y']))
    title = locations[0]['name'] if locations else stem
    if not lines:
        WARNINGS.append({'kind': 'missing_script', 'script': filename})
    result = [f'# {title} 对话与操作步骤', '',
              '按自己的道具、任务进度和所点选项读取相应分支。下面保留脚本的检查、选项、跳转和条件顺序；“否则”与“若满足”属于不同路径，不能把所有条目连续执行。', '',
              '条件中的完成记录和进行记录用于定位前置；玩家不能直接设置它们。名称后的方括号数字是物品或战斗数据编号，遇到同名物品时用于核对。', '',
              '## NPC 所在位置', '', '| NPC | 场景与坐标 |', '| --- | --- |']
    result += ['| ' + escape(n['name']) + ' | ' + escape(location(n)) + ' |' for n in locations]
    result += ['', '地图 777 是随机地图 NPC 模板，列出的模板坐标不是每次生成后的实际坐标；地图 999 等测试场景不会被当作正常任务起点。', '', '## 对话分支和操作', '']
    for ln, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith(('#', '//')):
            continue
        if line.startswith('*') or line.endswith(':'):
            result += ['', '### 交谈节点 ' + line.strip('*:'), '']
            continue
        command, value = split_command(line)
        rendered = instruction(command, value)
        if command == 'block':
            result += ['', f'### 交谈分支 第 {ln} 行', '']
        if rendered is None:
            rendered = '此步骤需核对原生指令：`' + line.replace('`', '') + '`'
            WARNINGS.append({'kind': 'untranslated_command', 'script': filename, 'line': ln, 'command': command, 'source': line})
        result.append(f'- {rendered}。〔源码第 {ln} 行〕')
    if not lines:
        result += ['该 NPC 引用的脚本在当前目录中未找到，不能据此提供完整通关步骤。']
    result += ['', '## 代码来源', '', f'[当前运行脚本](../../gmsv/data/npc/{quote(filename,safe="._-/")})；[NPC 位置表](../../gmsv/data/npc.txt)；[对话表](../../gmsv/data/msg.txt)。', '',
               '本页为代码条件与操作的逐步整理，未用客户端逐条重走。编号行号按 CRCRLF 归一后的文本计算；原文件编码和换行没有改变。', '']
    write(path, '\n'.join(result))
    records = analyze(filename)
    DETAILS[name] = dict(path=path, facts=records, lines=len(lines))
    return DETAILS[name]


@lru_cache(maxsize=None)
def analyze(filename):
    facts = {'give': [], 'need': [], 'take': [], 'warp': [], 'battle': [], 'adapters': [], 'conditions': []}
    for ln, raw in enumerate(script_lines(filename), 1):
        line = raw.strip()
        if not line or line.startswith(('#', '//')):
            continue
        cmd, value = split_command(line)
        if cmd in ('block', 'if', 'window_yes', 'window_ok', 'window_no'):
            facts['conditions'].append((ln, condition(value)))
            for n in re.findall(r'(?i)\b(?:Item|Leak0Item|Leak1Item|HaveItem|EquipItem)[ _]*(\d+)', value):
                facts['need'].append(int(n))
        if cmd.startswith('give') and 'item' in cmd:
            facts['give'] += [int(n) for n in re.findall(r'\d+(?=%)|^\d+', value)]
        if cmd.startswith('kill') and 'item' in cmd:
            facts['take'] += [int(n) for n in re.findall(r'^\d+', value)]
        if cmd == 'warp':
            vals = [src.number(v.strip()) for v in value.lstrip(',').split(',')[:4]]
            if len(vals) == 3:
                vals.insert(0, 0)
            if len(vals) == 4 and all(v is not None for v in vals):
                facts['warp'].append(vals)
        if cmd == 'encount':
            facts['battle'].append((ln, encounter(value)))
        if cmd == 'luac' and value in ADAPTERS:
            c = ADAPTERS[value]
            facts['adapters'].append(value)
            facts['give'] += [r[0] for r in c.get('give', [])]
            facts['take'] += [r[0] for r in c.get('need', []) if not c.get('retainNeeds')]
            facts['need'] += [r[0] for r in c.get('need', [])]
            if c.get('warp'):
                facts['warp'].append(c['warp'])
    return facts


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix == '.md' and '\ufffd' in value:
        WARNINGS.append(dict(kind='source_encoding',page=path.relative_to(OUT).as_posix(),
                             note='部分原始名称、对话或指令不能按 UTF-8/GBK 完整解码；页面标为原文编码不明'))
        value = re.sub('\ufffd+', '〔原文编码不明〕', value)
    path.write_text(value.rstrip() + '\n', encoding='utf-8', newline='\n')


def relative(path, base):
    import os
    return quote(Path(os.path.relpath(path, base)).as_posix(), safe='/._-')


def npc_action(n, base):
    if n['kind'] == 'event':
        if not n['payload'].lower().endswith('.txt'):
            return '该 Event 行使用非文件参数：`' + escape(n['payload']) + '`；需核对原生处理方式，不能据此编造对话步骤'
        d = detail(n['payload'])
        f = d['facts']
        pieces = []
        if f['give']:
            pieces.append('发放：' + '、'.join(item(i) for i in unique(f['give'])))
        if f['take']:
            pieces.append('提交或消耗：' + '、'.join(item(i) for i in unique(f['take'])))
        if f['battle']:
            pieces.append('有战斗分支')
        if f['warp']:
            pieces.append('有传送分支')
        pieces.append(f"[对话步骤]({relative(d['path'],base)})")
        return '；'.join(pieces)
    if n['kind'] == 'standenemy':
        return encounter(n['payload'])
    if n['kind'] == 'warp':
        return '条件传送 NPC，当前参数：`' + escape(n['payload']) + '`'
    if n['kind'] == 'jobsmaster':
        return '就职或晋阶服务，推荐信、费用、声望和职阶由原生菜单检查'
    if n['kind'] == 'skillmaster':
        return '学习或遗忘技能，检查职业许可、费用和技能格'
    if n['kind'] == 'brushman':
        return '商店或兑换服务，查看当前菜单的物品和价格'
    if n['kind'] == 'townpeople':
        msgs = [src.MESSAGES.get(int(i), '') for i in n['payload'].split('|') if i.isdigit()]
        return '剧情提示：' + ' ／ '.join(clean_dialog(m) for m in msgs if m)
    return '场景服务或互动对象；类型 ' + n['kind']


def story_page(path, title, npcs, entry=None, scenes=(), intro='', origin='共享任务', ordering=''):
    npcs = unique(npcs, key=lambda n: (n['kind'],n['name'],n['mapType'],n['floor'],n['x'],n['y'],n['payload']))
    base = path.parent
    body = [f'# {title}', '', intro or '进入本任务区域后，按所持任务道具和 NPC 对话提示推进。下文列出当前地图、任务物品交接、传送和各 NPC 的对话分支。', '',
            f'内容类别：{origin}。核对日期：2026 年 10 月 10 日。', '',
            '## 进入与准备', '']
    if entry:
        body += [f"在法兰城 `155,112` 找共享任务向导，选择“{title}”。当前目录的传送目标是 **{entry['name']}** 所在的 **{mapname(entry['floor'])}**（地图 `{entry['floor']}`）附近 `{entry['x']},{entry['y']}`。", '',
                 '**这是目录接待位置，不保证是剧情第一步。** 当前目录采用自动选取的接待 NPC；若对话要求你已持有某件道具，先查下文的物品交接表找到发放人。传送前需解散队伍，抵达后按具体任务重新组队。', '']
    elif origin == '共享任务':
        body += ['当前目录未设置接待 NPC。可用场景目录查看或传送到已安装场景；这类资料不一定具有完整的接取、通关和领奖链，不能把进入场景视为已接任务。', '']
    elif npcs:
        body += ['从下面路线说明与 NPC 表定位起点，使用 `/where` 核对地图编号。不会提供 GM 跳图或生成道具作为通关步骤。', '']
    body += ['出发前补满人物和宠物状态，留出物品空位；逐人领取任务道具。收费、等级、职业、声望、昼夜、聊天口令和人数检查分别见相应 NPC 的“对话步骤”。同名道具可能有不同编号，按表中编号核对。', '',
             '## 任务推进方式', '', ordering or '先在入口与接待 NPC 对话；如果提示缺少道具，从“任务道具交接”找到获得该物品的 NPC。进入对应场景，完成该 NPC 的选项、战斗或交换，再带着新得到的道具到检查它的 NPC。人物有不同任务进度时，读取对应分支，不重复执行已经完成的路径。', '',
             '随机迷宫楼梯与 NPC 实际坐标会随生成变化；不要把固定模板当成每次相同的行走路线。遇到一个出口对应多个目的地时，寻找当地“共享通路”，或回法兰城 `155,114` 使用共享通路向导。', '',
             '## NPC 与具体操作', '', '| NPC | 地图与坐标 | 操作与分支 |', '| --- | --- | --- |']
    for n in npcs:
        body.append('| ' + escape(n['name']) + ' | ' + escape(location(n)) + ' | ' + escape(npc_action(n, base)) + ' |')
    if not npcs:
        body += ['| 未找到属于此资料单元的已安装 NPC 行 | 查看下面场景 | 不能据目录名称推断完整任务步骤 |']
    producer, consumer = collections.defaultdict(list), collections.defaultdict(list)
    battles = []
    adapters = []
    for n in npcs:
        if n['kind'] != 'event' or not n['payload'].lower().endswith('.txt'):
            if n['kind'] == 'standenemy':
                battles.append((n, encounter(n['payload'])))
            continue
        d = detail(n['payload'])
        f = d['facts']
        for i in unique(f['give']):
            producer[i].append(n)
        for i in unique(f['need'] + f['take']):
            consumer[i].append(n)
        battles += [(n, v) for ln, v in f['battle']]
        adapters += [(n, ADAPTERS[k]) for k in unique(f['adapters']) if ADAPTERS[k]['kind'] != 'legacy']
    body += ['', '## 任务道具交接', '',
             '同一 NPC 的领取与提交可能属于不同进度、不同职业或拒绝分支。表中“发放”表示代码存在这一操作，不能当成所有物品同时必得；点击具体 NPC 的对话步骤查看数量、随机选择和前置。', '',
             '| 道具 | 本任务中的发放 NPC | 检查或收取 NPC |', '| --- | --- | --- |']
    for i in sorted(set(producer) | set(consumer)):
        def refs(values):
            return '；'.join(unique(f"[{n['name']}]({relative(detail(n['payload'])['path'],base)})" for n in values)) or '本页未发现直接发放；可能为战斗掉落、道具使用、前章或其他来源'
        body.append(f"| {escape(item(i))} | {refs(producer[i])} | {refs(consumer[i]) if consumer[i] else '本页没有直接提交检查'} |")
    if not producer and not consumer:
        body += ['| 未发现直接的物品交接 | 请按对话或场景服务推进 | 不据此认定任务没有奖励 |']
    if battles or adapters:
        body += ['', '## 战斗与本服适配流程', '',
                 '敌组表中的候选敌人、基础等级和关联物品不等于一次战斗的完整实测阵容或保证掉落。当前难度会进一步调整怪物属性；完成一次战斗后，继续读取获胜后的 NPC 分支确认交付或领取。', '']
        for n, v in unique(battles, key=lambda x: (x[0]['id'], x[1])):
            body.append('- **' + n['name'] + '**：' + v + '。')
        for n, c in unique(adapters, key=lambda x: (x[0]['id'], x[1]['key'])):
            body.append('- **' + n['name'] + '**：' + adapter_description(c) + '。')
    floors = unique([s['floor'] for s in scenes] + [n['floor'] for n in npcs if n['mapType'] == 0 and n['floor'] not in (777, 999)])
    body += ['', '## 场景与静态出口', '', '| 地图 | 名称 |', '| --- | --- |']
    for floor in floors:
        body.append(f'| {floor} | {escape(mapname(floor))} |')
    edges = [w for w in WARPS if w['floor'] in floors and w['to'] in floors]
    if edges:
        body += ['', '以下仅列本任务场景之间的静态自动出口；NPC 条件传送见上文，随机迷宫不据此画固定路线。', '',
                 '| 从哪里进入 | 到哪里落地 |', '| --- | --- |']
        for w in unique(edges, key=lambda w: (w['floor'], w['x'], w['y'], w['to'], w['tx'], w['ty'])):
            body.append(f"| {mapname(w['floor'])}〔{w['floor']}〕 {w['x']},{w['y']} | {mapname(w['to'])}〔{w['to']}〕 {w['tx']},{w['ty']} |")
    body += ['', '## 卡点排查与完成判断', '',
             '- 对话只说前置未完成：查看该 NPC 的第一个匹配条件，回到前章或道具发放处；共享目录不设置个人任务标记。',
             '- 对话要求逐人进行或脚本包含离开队伍：按个人分支完成后再集合，队长操作不会替成员领取。',
             '- 提交后没有奖励：检查空位、金币、职业及领取记录。自制适配挑战要实际获胜，逃跑和中止不计完成。',
             '- 同名 NPC 或地图对不上：对照地图编号；原生场景与共享包场景可能同时存在。',
             '- 判断本段完成：以相应 NPC 的道具交换、完成记录、称号或传送结果为准，不能仅凭进入最后一张地图判断。', '',
             '## 来源与验证状态', '',
             f"[NPC 表]({relative(src.DATA/'npc.txt',base)})、[道具表]({relative(src.DATA/'itemset.txt',base)})、[对话表]({relative(src.DATA/'msg.txt',base)})、[自动出口]({relative(src.DATA/'warp.txt',base)})。各 NPC 步骤页链接当前运行脚本。", '',
             '这是按当前代码整理的条件与操作攻略，尚未逐条客户端通关。无法解释的原生命令原样保留在步骤页，并列入核对记录；涉及这些分支时不能把它们当成已经验证的操作。', '',
             f"[返回攻略目录]({relative(OUT/'README.md',base)})。", '']
    write(path, '\n'.join(body))
    return dict(title=title, path=path.relative_to(OUT).as_posix(), npcs=len(npcs), scripts=len({n['payload'] for n in npcs if n['kind']=='event'}), origin=origin)


NATIVE = [
    ('经典剧情/01_国民任务.md', '国民任务', r'EV_ijk_start',
     '从王宫召唤士的出生考验开始，通过灵堂测试者取得死者的戒指，返回后交国王换赏赐状，最后向堡内士兵领取初始物品与宠物。老手试炼使用死者之眼，读取不同提交分支。'),
    ('经典剧情/02_受诅咒者与黑之祈祷.md', '受诅咒者与黑之祈祷', r'EV_mag_63(?:0\d|1[01])\.txt',
     '从雷欧尼与亚莉耶鲁的调查对话获取线索，进入黑之祈祷，找到两名巫师；再按获得的证明进入冯奴家中的后续分支。职业检查与逐人传送在各 NPC 页保留。'),
    ('经典剧情/03_时空石盘与解咒之书.md', '时空石盘与解咒之书', r'EV_mag_63(?:1[5-9]|2[0-69])\.txt',
     '通过古代人民与连接时空的石盘进入历史场景。在帝都阿斯法地下向勇者里雍领取解咒之书，穿过研究塔，到最上层找耶卡交付；战后继续查看石盘与墓前分支。'),
    ('经典剧情/04_挑战神兽与开启者试炼.md', '挑战神兽与开启者试炼', r'EV_mag_63(?:3[0-57]|4[1-6])\.txt',
     '向神官比尔班了解试炼，从莎莲娜入口进入迷宫。阿克尼的两人规则与神官葛雷森的证明检查分别读取，击败神兽后继续处理小爱、吉娜和梅鲁的后续，不把全部分支当作同一条就职线。'),
    ('经典剧情/05_海贼指挥部.md', '海贼指挥部', r'EV_mag_63(?:4[7-9]|[56]\d|7[0-5])\.txt',
     '在酒吧与柯鲁妮对话进入海贼相关剧情，按楼层与鱼蛋、虫虾、炉鱼克等互动，取得道具后继续与咸鱼和小由对话。楼层对象可能改变通行状态，逐项查对应分支。'),
    ('经典剧情/06_圣诏与犹大.md', '圣诏与犹大', r'EV_mag_63(?:7[89]|8\d|9[01])\.txt',
     '莎莲娜的阿斯提亚神官检查开启者完成记录，进入后向祭司领取圣坛所用道具，按烛台颜色和位置完成各圣坛分支；通过犹大后与开启者之间的布鲁梅尔对话，确认本段完成记录。'),
    ('经典剧情/07_历史学家与过去的勇者.md', '历史学家与过去的勇者', r'EV_mag_63(?:9[2-9])\.txt|EV_mag_640[07]\.txt',
     '在民家调查历史学家、地下石盘与过去的里雍、帕鲁凯斯和阿夏芙。先取得进入时空所需物品，再根据当前地图版本找对应 NPC；原生民家地下的几张版本地图不能互换。'),
    ('经典剧情/08_诅咒的迷宫.md', '诅咒的迷宫', r'EV_mag_64(?:0[1-6]|1[0-2]|0[89]|49|50)\.txt',
     '从诅咒的迷宫神官处调查，依次处理五个难关，最后到第六个难关查看封印石与神官贝米乌斯的分支。各难关前后版本分别列出，战斗后的传送和道具判断以当前页为准。'),
    ('经典剧情/09_被封闭的祭坛与冰雪牢城.md', '被封闭的祭坛与冰雪牢城', r'EV_mag_64(?:5[1-9]|6\d|7[02])\.txt',
     '从酒吧神官的线索前往莎莲娜东方洞窟，与布鲁梅尔对话后处理被封闭的祭坛，继续进入冰雪牢城；完成露比与佛利波罗相关战斗和旗标交互，再查看女神与神殿的后续。'),
    ('经典剧情/10_六曜之塔与最终决战.md', '六曜之塔与最终决战', r'EV_mag_64(?:7[3-9]|[89]\d)\.txt',
     '伊尔村渔夫提供老龙相关线索。进入六曜之塔，按龙魂道具、南北护龙神和石像的分支前进，到月之神殿和天地之门继续与布鲁梅尔、女神卡莲及李贝留斯交互；胜利后仍需完成后续对话。'),
    ('经典剧情/11_兰国与艾尔巴尼亚勋章.md', '兰国与艾尔巴尼亚勋章', r'EV_mag_305\d+\.txt',
     '本服保留两国的勋章、委托与个人进度分支。先按 NPC 对话选择国家路线，再沿该国的物品与完成记录推进；两国分支并非需要在一轮内同时完成。'),
    ('资料片剧情/01_勋章续章与特使.md', '勋章续章与特使', r'EV_rk_7odr\d+\.txt',
     '与特使忠吉及当前国家路线相关人物交谈，按已经完成的国家勋章记录接受后续调查。爵位和道具条件逐人检查，不因队长有勋章就跳过成员的前置。'),
    ('资料片剧情/02_外务与国家调查.md', '外务与国家调查', r'EV_rk_6odr\d+\.txt',
     '向外务副长官史达及相关调查 NPC 交接委托与证明，根据个人完成记录继续国家剧情；先查任务物品的发放人，再找到收取该物品的 NPC。'),
    ('资料片剧情/03_坎那贝拉与米特拉.md', '坎那贝拉与米特拉', r'EV_rk_5odr\d+\.txt',
     '从坎那贝拉卫兵和当前调查记录进入城内剧情，收集能洗清嫌疑的证明，推进米特拉将军战斗及战后交付。相同将军在战前战后地图分别存在。'),
    ('资料片剧情/04_哥拉尔调查.md', '哥拉尔调查', r'EV_rk_4odr\d+\.txt',
     '调查哥拉尔兵舍与岛上事件，按士兵雷欧的报告与其他 NPC 的物品条件前进。获得报告后找实际收取报告的角色，不只读取背景对话。'),
    ('资料片剧情/05_席琳与病院.md', '席琳与病院', r'EV_rk_3odr\d+\.txt',
     '从捐献受款处与席琳相关 NPC 查找线索，按人物进度进入病院、密室与后续历史场景，完成指定交接后再返回相应 NPC。'),
    ('资料片剧情/06_天帝之证.md', '天帝之证', r'EV_rk_2odr\d+\.txt',
     '本段围绕席琳的秘密住所与天帝之证交接。先检查此前国家线完成记录和任务道具，选择当前对应的 NPC 分支，归还证明后继续读后续。'),
    ('资料片剧情/07_七罪与露比.md', '七罪与露比', r'EV_rk_1odr\d+\.txt',
     '持有国家路线所需证明后到米内葛尔岛被诅咒的古木，进入遗迹。逐层处理七名罪之守门者，保留各罪证，最后与露比和石像交互。石像存在清除勋章的选项，选择前逐条阅读对话。'),
    ('资料片剧情/08_亡灵与反抗军.md', '亡灵与反抗军', r'EV_rk_ghost\d+\.txt',
     '调查牢房、占星者、耶卡与反抗军，按道具和国家完成记录进入过去的勇者相关场景。战士帕鲁凯斯及亡灵版本分别处理，确认战后物品再继续。'),
    ('资料片剧情/09_雷克塔尔与黑暗剧情.md', '雷克塔尔与黑暗剧情', r'EV_rk_black\d+\.txt',
     '从雷克塔尔的井及相关人物调查进入后续，与勇者里雍等角色按当前任务进度交互。战前战后地图的里雍不是同一个交互分支。'),
    ('资料片剧情/10_天界启程与重生.md', '天界启程与重生', r'EV_tane_(?:rebth|ruins)_',
     '本段收录天界启程、重生及遗迹的原生前置 NPC。根据自己的出生与剧情记录从可达入口出发，先完成调查和交接，再进入主线序章；页面中带测试场景的 NPC 不能作为普通起点。'),
    ('资料片剧情/11_天界主线序章.md', '天界主线序章', r'EV_(?:tane|machida)_main0_',
     '到约尔克神庙调查神秘声音，结合查尔博士、助手与酒吧人物的线索寻找后续人物。时间、道具和对话选项分别在 NPC 页核对。'),
    ('资料片剧情/12_天界主线神官与遗迹.md', '天界主线神官与遗迹', r'EV_tane_main1_',
     '调查梅布尔隘地、法兰城遗迹与神殿，给神官所需物品时先确认没有装备在身上；条件分支分别处理不同道具，不需要把所有候选都交一遍。'),
    ('资料片剧情/13_天界主线安洁可.md', '天界主线安洁可', r'EV_tane_main2_',
     '从马汀斯和冒险者旅馆的安洁可继续调查，沿物品与传送找到纳塞、荷特普和神域守护者；取得本段证明后核对后续人物的条件。'),
    ('资料片剧情/14_天界主线祭坛与昏神.md', '天界主线祭坛与昏神', r'EV_tane_main4_',
     '调查梅布尔隘地祭坛守卫，进入对应区域，按荷特普、场景障碍及昏神祭司的交互推进。守墓员的测试地图行单独标明，不作为可直接抵达的任务起点。'),
    ('资料片剧情/15_天界主线撕裂空间.md', '天界主线撕裂空间', r'EV_(?:suto|nemoto)_main6_',
     '从冒险者旅馆的克罗查线索，按安洁可和神殿扭曲空间的条件进入撕裂空间，逐层完成组员与纳塞的交互。最终区域的撤离分支与任务推进分支分别读取。'),
    ('资料片剧情/16_神域主线托尔邱.md', '神域主线托尔邱', r'EV_suto_puk3m1_',
     '先到杂货屋与杰拉兹尼交谈，再根据提示找支撑辛梅尔大地的托尔邱，沿其委托前往后续场景；各传送与道具检查见步骤页。'),
    ('资料片剧情/17_神域主线雪蕾洁.md', '神域主线雪蕾洁', r'EV_suto_puk3m2_',
     '从可疑男子的调查分支与雪蕾洁继续剧情，核对上章证明、个人记录和区域传送条件，再完成本章调查与战斗。'),
    ('资料片剧情/18_神域主线雪拉威森塔.md', '神域主线雪拉威森塔', r'EV_suto_puk3m3_',
     '到国民会馆与神官交谈。入口脚本检查所需物品与前章完成记录；进入塔后按神官、荷特普等的分支继续，保留战后道具并完成个人交付。'),
]


def safe_filename(name):
    return re.sub(r'[<>:"/\\|?*\x00-\x1f]', ' ', name).strip(' .')[:95]


def main():
    OUT.mkdir(exist_ok=True)
    for f in ['gmsv/lua/ModuleConfig.lua', 'gmsv/cgmsv.cf', 'tools/sanctuary/sanctuaryData.lua',
              'tools/game-qol/commandHelp.lua', 'tools/game-qol/gameDifficulty.lua',
              'tools/content-audit/templates/sharedTaskAdapters.lua', 'gmsv/lua/Modules/sanctuaryData.lua']:
        read(ROOT / f)
    for module in re.findall(r"loadModule\('([^']+)'\)", src.text(ROOT/'gmsv/lua/ModuleConfig.lua')):
        path = ROOT/'gmsv/lua/Modules'/(module+'.lua')
        if path.is_file():
            read(path)
    native = []
    for rel, title, pattern, ordering in NATIVE:
        npcs = [n for n in src.NPCS if n['kind']=='event' and re.search(pattern,n['payload'],re.I)]
        # Include explicit battles in these story scenes, excluding testing slots.
        floors = {n['floor'] for n in npcs if n['mapType']==0 and n['floor'] not in (777,999)}
        for n in npcs:
            if n['payload'].lower().endswith('.txt'):
                for v in analyze(n['payload'])['warp']:
                    if v[0]==0: floors.add(v[1])
        # Shared overworld locations contain unrelated fights. Only attach
        # native, pre-import static enemies in small story rooms or named core
        # bosses, not every enemy that happens to stand on the same continent.
        core_names={'犹大','神兽史雷普尼尔','北方护龙神','南方护龙神'}
        npcs += [n for n in src.NPCS if n['kind']=='standenemy' and n['floor'] in floors and n['mapType']==0
                 and n['id'] not in IMPORTED_NPC_IDS
                 and n['floor'] not in (777,999,100,200,300,400,401,402,1000,33000,43100,43700)
                 and (n['name'] in core_names or max(src.MAP_SIZES.get(n['floor'],(999,999)))<=100)]
        native.append(story_page(OUT/'主线任务'/rel, title, npcs, origin='原生剧情', ordering=ordering))
    # Side scripts can carry unnamed chapters. Keep all current sky-scene events,
    # rather than infer a chapter is missing because its filename lacks "main".
    sky = [n for n in src.NPCS if 59500 <= (n['floor'] or 0) <= 59999 and n['kind'] in ('event','standenemy')]
    native.append(story_page(OUT/'主线任务/资料片剧情/19_天界其他剧情与前置.md','天界其他剧情与前置',sky,
                             origin='原生剧情补充',ordering='天界的部分任务没有使用 main 文件名。此页按地图收录其他原生剧情和前置 NPC；不能按表格顺序把支线拼成主线。找不到前置道具的玩家，可在这里按 NPC 名、地图或物品名查找。'))
    shared = []
    for t in CATALOG:
        unit = t['unit'];title = t['name']
        category = '自制与共享任务'
        if re.search('节|跨年|新年|圣诞|活动|嘉年华|会员|GM|强化|兑换|兜售|传送|在线时间|铸造|制作首饰',title,re.I):
            category = '活动支线与服务'
        elif re.search('资料片|系列|危险游戏|天空之城|失落的文明|尼伯龙根|神罚|骑士系列|魔珠系列',title):
            category = '共享剧情与资料片'
        path = OUT/'主线任务'/category/(f'{unit:03d}_'+safe_filename(title)+'.md')
        page = story_page(path,title,UNIT_NPCS[unit],entry=t.get('entry'),scenes=t.get('scenes',[]))
        page.update(unit=unit, category=category, entry=t.get('entry'), scenes=len(t.get('scenes',[])))
        shared.append(page)
    # Item-invoked scripts and data-only units are outside the teleport catalog.
    snapshots = {u['id']:u for u in json.loads(read(REPORTS/'source_authoring_snapshot.json'))}
    supplements = []
    for unit, u in UNITS.items():
        if unit in {t['unit'] for t in CATALOG}:
            continue
        path = OUT/'主线任务/附属资料'/(f'{unit:03d}_'+safe_filename(u['name'].split('/')[-1])+'.md')
        base = path.parent
        body = ['# '+u['name'].split('/')[-1], '',
                '本单元未列入共享任务向导的传送目录。下文用于查找当前关联道具、NPC 与脚本；没有可确认的接取点时，不把原包任务名称写成可直接开始的流程。', '', '## 当前关联 NPC', '']
        for n in UNIT_NPCS[unit]:
            body.append('- '+n['name']+'：'+location(n)+'；'+npc_action(n,base))
        if not UNIT_NPCS[unit]: body.append('当前安装单元没有独立 NPC 接待数据。')
        body += ['', '## 当前关联道具', '']
        ids = [e['new_id'] for e in MAPPING['entities'] if e['kind']=='itemset' and unit in e['units']]
        body += ['- '+item(i) for i in ids]
        if not ids: body.append('没有本单元独立导入的道具记录。')
        body += ['', '## 可读取的安装脚本', '']
        aliases = []
        for script in snapshots.get(unit,{}).get('scripts',[]):
            alias = 'stp_'+hashlib.sha256(script['path'].encode('utf8')).hexdigest()[:18]+'.txt'
            if (src.DATA/'npc'/alias).is_file():
                d = detail(alias)
                aliases.append(alias)
                body.append('- ['+script['name']+']('+relative(d['path'],base)+')')
        if not aliases: body.append('没有从来源快照匹配到可读取的当前安装脚本；不提供虚构步骤。')
        body += ['', '若物品触发脚本，使用资格仍受物品原生效果与脚本分支检查。单有脚本文件不能证明普通玩家可从某个 NPC 接取；没有入口的任务需要后续补全接取方式才能按完整攻略推进。', '', '[返回任务目录](../README.md)。']
        write(path,'\n'.join(body))
        supplements.append(dict(unit=unit,title=u['name'],path=path.relative_to(OUT).as_posix(),scripts=aliases))
    native_body = ['# 主线任务与自制任务目录','','先从[新手攻略](../新手攻略.md)完成角色准备，再选择下列任务。经典剧情、资料片和共享包各自有前置记录；目录排列用于查找，不能代替 NPC 条件所定义的实际顺序。','','## 经典剧情与原生资料片','']
    for rel,title,pattern,ordering in NATIVE:
        native_body.append(f'- [{title}]({rel})')
    native_body += ['- [天界其他剧情与前置](资料片剧情/19_天界其他剧情与前置.md)','','## 共享剧情 自制任务 活动与服务','','共享内容包含原作者自制故事、资料片、活动与服务。本服安装时有重编号和适配，不能因为名称含“资料片”就认定它属于官方原版。以下收录当前共享任务向导全部目录项，场景资料和服务另作标注。','', '| 分类 | 任务 | NPC 数 | 脚本数 |', '| --- | --- | ---: | ---: |']
    native_body[1:1] = ['', '本服新增流程：[宠装制造就职试炼](本服定制/宠装制造就职试炼.md)；[远征后勤职业与材料挑战](本服定制/远征后勤职业与材料挑战.md)。']
    for p in shared:
        native_body.append(f"| {p['category']} | [{escape(p['title'])}]({quote(p['path'].removeprefix('主线任务/'),safe='/._-')}) | {p['npcs']} | {p['scripts']} |")
    native_body += ['', '## 不在传送目录中的自制与附属资料', '', '以下单元也已收录。缺少接待点的内容标明入口缺失，物品触发与纯数据内容按实际资料阅读。', '']
    for p in supplements:
        native_body.append(f"- [{escape(p['title'])}]({quote(p['path'].removeprefix('主线任务/'),safe='/._-')})")
    native_body += ['','## 系列阅读顺序','','危险游戏：序章与第一章 → 第二章 → 第三章 → 第四章 → 第五章；失落的文明：病毒 → 解毒之法 → 盗墓贼 → 遗迹；尼伯龙根：莱茵的黄金 → 女武神 → 传说中的矮人族 → 命运女神；骑士系列：消失的圣殿骑士 → 誓言 → 圣剑传说。章名顺序只提供导航，是否可以开始下一章仍由本服脚本检查。','','同名目录项保留各自安装单元，不合并入口和道具。童话王国、一千零一夜等重复项目可能共享地图或有不同来源，先选定一条目录项，按它自己的步骤推进。','','[阅读条件和验证范围](../阅读说明.md)；[返回攻略目录](../README.md)。']
    write(OUT/'主线任务/README.md','\n'.join(native_body))
    index = ['# 本服游戏攻略','','这里集中保存本服攻略。先读新手攻略，完成出生任务、技能装配、装备和宠物准备，再按主线目录选择剧情。自制任务和共享资料片也在同一目录中查找。','','## 攻略入口','','- [新手攻略](新手攻略.md)：从出生到圣殿、职业、技能、装备、五宠和任务准备。','- [主线与全部共享任务目录](主线任务/README.md)：经典剧情、原生资料片与全部共享目录项。','- [阅读说明](阅读说明.md)：地图编号、分支、随机迷宫和验证状态。','- [代码覆盖与核对记录](维护/覆盖与核对.md)：收录数量、来源与需要核对的指令。','','## 当前覆盖','',f'原生剧情与天界补充共 {len(native)} 篇；共享任务向导目录 {len(shared)} 项全部有独立任务或场景页。任务 NPC 的条件、对话选项、物品交换和扩展战斗另有 {len(DETAILS)} 份步骤页，供具体操作和卡点查找。','','“目录项全覆盖”不等于每一条任务已经用客户端通关。步骤页保留原生分支，未解释指令明确显示，场景资料不会冒充完整任务。经典主线范围按本地剧情脚本组与任务地点整理，完整清单见覆盖记录。','','攻略以 2026 年 10 月 10 日的当前服务端文件为依据。旧说明、共享包原编号和一般服攻略可能与本服不同，尤其是圣殿坐标、装备许可和共享地图。']
    write(OUT/'README.md','\n'.join(index))
    readme = ['# 攻略阅读说明','','## 分支与实际顺序','','任务页先给进入方式，再列 NPC、任务道具交接和传送。NPC 表不是固定通关顺序；每个 NPC 的步骤页保留分支、选项、条件和跳转。先找到自己当前符合的分支，再执行其中的操作。条件“且”要求同时满足，“或”表示满足其中路径；复杂条件保留原先组合，不把拒绝条件当成接取要求。','','步骤页中的“若满足”“否则”和点击“是”“否”“确定”对应不同路径。源码后续节点可能由跳转进入，不要逐行执行整份页面。未解释指令保留原文，涉及该指令的路径仍需要按代码或隔离环境核对。','','## 地图和坐标','','同名场景可能有多个地图编号，前后剧情和共享重编号还可能各不相同。用 `/where` 看地图编号和类型。固定地图通常是类型 0；地图 777 是随机 NPC 模板，坐标不保证对应生成后的实际位置；999 等测试区域不能当作普通玩家可直接到达的入口。','','静态出口表只显示对应坐标与落点，不证明途中全部可行走，也不包括所有 NPC 条件传送。随机迷宫不提供虚构的固定楼梯坐标。共享出口冲突使用当地共享通路或法兰城 155,114 的通路向导。','','## 道具与奖励','','道具名称后的编号用于区分同名不同物品。交接表列代码中出现的发放、检查和收取，不代表同时领取或必定掉落。随机候选保留权重参数，数量省略时注明按原生命令默认值，不推算未证实概率。','','敌组的关联物品可能是掉落、任务奖励或其他原生字段；只有具体发放分支、胜利回调或领取对话才能确定奖励。本服扩展单人试炼逐轮检查真实胜利，逃跑或中止不给奖。人物经验和难度按当前模块配置，不假设提高难度就有额外奖励。','','## 共享目录入口','','法兰城 155,112 的共享任务向导从安装单元自动选择接待点，有些目标已经处于剧情中段。抵达后若要求某项前章物品，先按该任务的交接表查来源。目录传送先解散队伍，不自动完成前置。共享包内的待修复目录名是历史来源名，不能据此判断当前安装失败。','','## 验证状态','','本次读取当前运行目录的静态文件和模块，不读取玩家数据库，不启动正式服务端，不热重载游戏脚本。攻略描述代码可确认的条件与操作，尚未逐条用客户端完整通关。现有共享整合的隔离验证确认入口、通路和选定改编流程，并未逐条通关原作者全部任务链。','','原生 main 命名的剧情脚本、经典阿斯提亚剧情、国家勋章与续章已列入目录；天界场景中的其他事件另作补充，避免单靠文件名丢失未命名章节。自制共享目录全量收录，原包中只含数据表而没有任务入口的单元列在覆盖记录，不伪造接取地点。','','[返回攻略目录](README.md)。']
    write(OUT/'阅读说明.md','\n'.join(readme))
    service = ADAPTERS['stp:services']
    read(ROOT/'gmsv/lua/Modules/sharedTaskAdapters.lua')
    read(ROOT/'gmsv/lua/Modules/cg71JobSkills.lua')
    data_lua('cg71JobSkillsData.lua')
    service_body = ['# 远征后勤职业与材料挑战', '',
        '这是本服定制入口，接待人为法兰城地图 1000 的远征后勤官 `151,114`。靠近 NPC 并结束战斗后打开菜单。', '',
        '## 职业登记', '',
        '1. 人物达到 20 级，准备 5000 魔币。',
        '2. 选择“自制职业登记”，翻页找到目标职业。',
        '3. 阅读确认页再登记。当前实现会直接改为目标职业第一职阶，保留现有技能，技能上限随新职业调整；这会改变现有职业。已经属于该职业系列时拒绝重复登记。', '',
        '## 职业与晋阶条件', '',
        '登记后返回后勤菜单选择晋阶，人物等级、声望、每项专属技能与魔币必须同时达标。职阶按该职业实际配置逐级晋升。', '']
    for job in service['jobs']:
        service_body += ['### '+job['name'], '', '| 晋阶目标 | 人物等级 | 声望 | 魔币 | 专属技能要求 |', '| --- | ---: | ---: | ---: | --- |']
        for idx, rank in enumerate(job['ranks'][1:]):
            req = '、'.join(f'技能〔{s[0]}〕 {s[1]}级' for s in rank['need']) or '无额外技能检查'
            service_body.append(f"| {rank['name']}〔{rank['id']}〕 | {[20,40,60,80,100,140][idx]} | {rank['fame']} | {rank['cost']} | {req} |")
        service_body.append('')
    service_body += ['## 寻回遗失材料', '',
        '1. 选择“寻回遗失材料”，找到需要的材料。',
        '2. 按下表准备等级、队伍状态、金币、道具和空位。五宠是否可以启动，还受五宠模块与挑战人数检查约束。',
        '3. 完成挑战的全部轮次并实际获胜。逃跑、中止或退出不会获得奖励；领奖冷却按每项配置计算。', '',
        '| 材料挑战 | 条件、战斗与奖励 |', '| --- | --- |']
    for material in service['materials']:
        c = ADAPTERS[material['key']]
        service_body.append('| '+escape(material['name'])+' | '+escape(adapter_description(c))+' |')
    service_body += ['', '## 配方与卡点', '',
        '“学习可用配方”按现有技能等级解锁；获得配方后仍需材料与魔力，从原生技能窗口制作。菜单过期或离 NPC 太远时重新交谈。背包不足、条件未满足或冷却中时先处理提示再挑战。', '',
        '[运行模块](../../../gmsv/lua/Modules/sharedTaskAdapters.lua)；[当前服务数据](../../../gmsv/lua/Modules/sharedTaskAdaptersData.lua)。本文根据当前代码整理，未逐项客户端通关。', '', '[返回总目录](../README.md)。']
    write(OUT/'主线任务/本服定制/远征后勤职业与材料挑战.md', '\n'.join(service_body))
    audit = ['# 攻略覆盖与核对记录','','本记录用于复查攻略范围，原生与共享任务是否可完整通关仍以客户端或隔离服务端验证为准。','','## 收录范围','',f'- 原生剧情与天界补充：{len(native)} 篇。',f'- 当前共享任务目录：{len(CATALOG)} 项，全部生成独立页面。',f'- 对话与操作步骤：{len(DETAILS)} 个不同脚本。',f'- 当前目录无接待点的项：{sum(not t.get("entry") for t in CATALOG)} 项。','','## 原生剧情匹配范围','','| 攻略 | 使用的脚本组 |','| --- | --- |']
    for rel,title,pattern,ordering in NATIVE:
        audit.append(f'| {title} | `{pattern}` |')
    audit += ['| 天界其他剧情与前置 | 当前 NPC 地图编号 59500～59999，Event 与 StandEnemy |','','## 未进入共享任务目录的资料单元','','以下单元在来源清单中存在，但当前目录没有单独接待条目。它们可能是纯物品、职业、技能、兑换或其他附属数据，不会按名称虚构任务入口。','', '| 单元 | 名称 | NPC 数据行 | 脚本数 |', '| --- | --- | ---: | ---: |']
    in_catalog = {t['unit'] for t in CATALOG}
    for unit,u in UNITS.items():
        if unit not in in_catalog:
            audit.append(f"| {unit} | {escape(u['name'])} | {u['tables'].get('npc',0)} | {u['scripts']} |")
    missing = [w for w in WARNINGS if w['kind']=='missing_script']
    unknown = [w for w in WARNINGS if w['kind']=='untranslated_command']
    counter = collections.Counter(w['command'] for w in unknown)
    audit += ['', '## 未解释指令与缺失脚本','', f'缺失脚本 {len(missing)} 个。未解释指令出现 {len(unknown)} 次，共 {len(counter)} 种命令前缀。它们全部保留在步骤页；对应路径没有被标为实测通过。', '',
              '| 命令前缀 | 出现次数 |', '| --- | ---: |']
    audit += [f'| `{escape(k)}` | {v} |' for k,v in counter.most_common()]
    audit += ['', '## 原文编码异常', '',
              '部分原生名称和对话混有不能按 UTF-8/GBK 解码的字节，页面以“原文编码不明”标注。保留物品、敌人、地图编号和原始文件链接，不猜测损坏的名称。受影响页面：', '']
    audit += ['- ['+w['page']+']('+relative(OUT/w['page'],OUT/'维护')+')' for w in WARNINGS if w['kind']=='source_encoding']
    audit += ['', '逐条位置、原文与类型见[核对清单 JSON](核对清单.json)。输入文件哈希见[来源清单](来源清单.json)，运行工具可检查攻略是否对应当前文件。','','## 更新与检查','','在仓库根目录运行 `tools/game-guide/build_guides.py` 重新整理自动生成的任务页；新手攻略为人工维护，不会被生成工具覆盖。运行 `tools/game-guide/verify_guides.py` 检查目录项覆盖、链接、来源哈希和关键新手配置。生成过程只读游戏 DATA 与 Lua，并只写攻略目录。']
    write(OUT/'维护/覆盖与核对.md','\n'.join(audit))
    write(OUT/'维护/核对清单.json',json.dumps(WARNINGS,ensure_ascii=False,indent=2))
    write(OUT/'维护/来源清单.json',json.dumps({'date':'2026-10-10','sources':USED,'native':native,'shared':shared,
                                             'supplements':supplements,
                                             'steps':{k: {'path':v['path'].relative_to(OUT).as_posix(),'lines':v['lines']} for k,v in DETAILS.items()}},ensure_ascii=False,indent=2))
    # This proves the generator did not mutate any input while running.
    for name,digest in USED.items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest, 'Input changed: '+name
    print(json.dumps({'native':len(native),'catalog':len(shared),'steps':len(DETAILS),'missing':len(missing),
                      'untranslated':len(unknown),'command_kinds':len(counter),'output':str(OUT)},ensure_ascii=False))


if __name__ == '__main__':
    main()
