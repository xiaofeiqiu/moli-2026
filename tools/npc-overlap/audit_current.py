"""Audit current custom NPCs using the actual server and an isolated database."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding='utf-8')
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
RUN = ROOT / 'backups/npc_current_20261010/native_runtime/gmsv'
OUT = ROOT / 'docs/npc_overlap_fix'


def write_directory(report):
    core = [n for n in report['npcs'] if n['name'] != '共享通路']
    local = sorted((n for n in report['npcs'] if n['name'] == '共享通路'), key=lambda n: (n['floor'], n['x'], n['y']))
    def clean(value):
        return str(value).replace('|', '／').replace('\r', ' ').replace('\n', ' ')
    lines = ['# 当前新增 NPC 坐标与复核记录', '',
             '2026-10-11：使用当前完整模块组合和实际 CGMSV 程序，在独立数据库及测试端口中完成检查。'
             f"共 {len(report['npcs'])} 个模块新增 NPC，{len(report['checks'])} 项检查通过，无同格 NPC 重叠；"
             '每个 NPC 所在格可走，并有可接近的邻格。正式玩家数据库未复制或修改。', '',
             '验证包括正常启动、全部共享通路 NPC 的实际接近与对话菜单，以及重载共享模块后再次检查；'
             '还覆盖延迟创建前再次重载，以确认旧创建任务会取消。', '',
             '此表记录当前工作区的原生加载结果。装备店在当前本地魔剑扩展中名为“魔剑装备”，'
             '早期版本前缀为“骑士装备”；两者的坐标和等级档一致。任务包的剧情 NPC 随任务章节进入，'
             '章节入口请使用共享任务向导。', '', '## 玩法入口（圣殿与法兰城）', '',
             '| NPC | 地图 | 坐标 | 可接近坐标 | 模块 |', '| --- | --- | --- | --- | --- |']
    for n in core:
        a = n['approaches'][0]
        lines.append(f"| {clean(n['name'])} | {n['floor']} | {n['x']},{n['y']} | {a['x']},{a['y']} | `{n['module']}` |")
    lines += ['', '## 各场景共享通路', '',
              '这些 NPC 提供当前场景的出口选择。也可以到法兰城 `155,114` 的共享通路向导，从通路目录选择目的地。', '',
              '| 通路编号 | 地图 | NPC 坐标 | 可接近坐标 | 可选目的地 |', '| --- | --- | --- | --- | --- |']
    for n in local:
        a = n['approaches'][0]
        lines.append(f"| {n['route']} | {n['floor']} | {n['x']},{n['y']} | {a['x']},{a['y']} | {clean('、'.join(n['destinations']))} |")
    lines += ['', '## 位置修复与复查', '',
              '- 65位职业技能导师全部设于圣殿（60003）同一房间，生产系y=10、物理战斗系y=14、法系y=18，每排从x=16起，中间空一格，无内部传送石；BOSS导师34,18每页10项，宠物导师36,18负责学习与遗忘，十间装备店及成长服务仍在圣殿；宠物装备商人36,26、血瓶商人40,26、料理商人44,26、宠装管理员48,26、属性水晶商人32,26；东门医院旁 `223,85` 为圣殿传送石，圣殿 `32,34` 为法兰返程石。',
              '- 远征后勤官从 `158,112` 移到 `151,114`；共享通路向导从 `161,112` 移到 `155,114`，解决旧位置无法接近的问题。',
              '- 旧本地共享通路检查只判断地形可走，存在重复选中同一格的情况。现在等静态 NPC 加载完成后创建，选址同时检查地图对象占用和对话接近空间。',
              '- 运行 `python tools/npc-overlap/audit_current.py` 可用当前配置重新验证并更新本目录。', '',
              '原生完整报告为同目录下的 `current_npc_audit.json`，附正式来源文件 SHA-256。生成报告、日志和隔离运行目录不进入 Git。', '']
    (OUT / '当前新增NPC目录.md').write_text('\n'.join(lines), 'utf-8')


def copy_changed(source, dest):
    source, dest = Path(source), Path(dest)
    if not dest.exists() or (source.stat().st_size, source.stat().st_mtime_ns) != (dest.stat().st_size, dest.stat().st_mtime_ns):
        shutil.copy2(source, dest)
    return str(dest)


def main():
    RUN.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for rel in ('cgmsv.exe', 'setup.cf', 'cgmsv.cf', 'log/log.cf'):
        dest = RUN / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'gmsv' / rel, dest)
    for rel in ('lua', 'data'):
        shutil.copytree(ROOT / 'gmsv' / rel, RUN / rel, dirs_exist_ok=True, copy_function=copy_changed)
    for rel in ('store/itemcount', 'store/dungeon', 'store/house', 'log', 'Dengon', 'GMLog', 'dump', 'house'):
        (RUN / rel).mkdir(parents=True, exist_ok=True)
    setup = (RUN / 'setup.cf').read_bytes()
    for key, value in (('port', 19073), ('dbengine', 1), ('dummynum', 100)):
        setup = re.sub(rb'(?m)^' + key.encode() + rb'=\d+', f'{key}={value}'.encode(), setup)
    (RUN / 'setup.cf').write_bytes(setup)
    http = RUN / 'lua/Modules/http.lua'
    http.write_bytes(http.read_bytes().replace(b'Http.Start("0.0.0.0", 10086)', b'Http.Start("127.0.0.1", 19173)'))
    config = (ROOT / 'gmsv/lua/ModuleConfig.lua').read_bytes()
    (RUN / 'lua/ModuleConfig.lua').write_bytes(config + b"\r\ndofile('lua/npc_current_probe.lua')\r\n")
    source = (HERE / 'audit_current.lua').read_text('utf-8').replace('__OUTPUT__', OUT.as_posix())
    (RUN / 'lua/npc_current_probe.lua').write_bytes(source.encode('gbk'))
    result = OUT / 'current_npc_audit.json'
    result.unlink(missing_ok=True)
    with (OUT / 'current_npc_audit.log').open('wb') as log:
        process = subprocess.Popen([str(RUN / 'cgmsv.exe')], cwd=RUN, stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + 100
            report = None
            while time.monotonic() < deadline and process.poll() is None:
                if result.exists():
                    raw = result.read_bytes()
                    try:
                        try:
                            report = json.loads(raw.decode('utf-8'))
                        except UnicodeDecodeError:
                            report = json.loads(raw.decode('gbk'))
                    except json.JSONDecodeError:
                        pass
                    else:
                        break
                time.sleep(.25)
            if report is None:
                raise RuntimeError(f'No report; exit={process.poll()}; see {log.name}')
            files = ['cgmsv.exe', 'data/npc.txt', 'lua/ModuleConfig.lua']
            files += ['lua/Modules/' + name + '.lua' for name in sorted({n['module'] for n in report['npcs']})]
            files += [rel[:-4] + 'Data.lua' for rel in files if rel.startswith('lua/Modules/') and (ROOT / 'gmsv' / (rel[:-4] + 'Data.lua')).exists()]
            hashes = {}
            for rel in files:
                current = (ROOT / 'gmsv' / rel).read_bytes()
                tested = config if rel == 'lua/ModuleConfig.lua' else (RUN / rel).read_bytes()
                assert current == tested, 'Source changed during native audit: ' + rel
                hashes[rel] = hashlib.sha256(tested).hexdigest()
            report['source_sha256'] = hashes
            result.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', 'utf-8')
            print(json.dumps({'status': report['status'], 'npcs': len(report['npcs']), 'checks': len(report['checks']),
                              'overlaps': len(report['overlaps']), 'error': report.get('error'), 'report': str(result)}, ensure_ascii=False))
            if report['status'] != 'PASS':
                raise SystemExit(1)
            write_directory(report)
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)


if __name__ == '__main__':
    main()
