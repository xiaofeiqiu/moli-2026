"""Build an individual tutor for every installed occupation in the sanctuary by production, physical and magic rows."""
from pathlib import Path
from collections import defaultdict, Counter
import json
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
from build import lua
from pet_skill_policy import install as install_policy


def install():
    install_policy()
    occupations = defaultdict(list)
    for line in (ROOT / 'gmsv/data/jobs.txt').read_bytes().decode('gbk').splitlines():
        fields = line.split('\t')
        if len(fields) > 2 and fields[2].isdigit():
            job = int(fields[2]);occupations[job // 10 * 10].append((job, fields[0]))
    names = {}
    for family, ranks in sorted(occupations.items()):
        name = min(ranks)[1]
        name = re.sub(r'^(见习|初级|实习)', '', name)
        name = re.sub(r'学徒$', '', name)
        names[family] = name
    counts = Counter(names.values());tutors = []
    row_counts = Counter()
    magic = {60, 70, 80, 90, 100, 110, 130, 900, 6010}
    production = set(range(200, 480, 10)) | {500, 1000, 1010, 1020, 1030, 1040, 1050}
    row_y = {"production": 10, "physical": 14, "magic": 18}
    for index, (family, ranks) in enumerate(sorted(occupations.items())):
        name = names[family]
        if counts[name] > 1:
            name += f'（{family}）'
        group = 'production' if family in production else 'magic' if family in magic else 'physical'
        column = row_counts[group];row_counts[group] += 1
        tutors.append({'id': f'job{family}', 'family': family, 'kind': 'job', 'name': name + '技能导师',
                       'image': 100005, 'jobs': sorted(job for job, _ in ranks),
                       'group': group, 'mapType': 0, 'map': 60003, 'x': 16 + column * 2, 'y': row_y[group], 'direction': 4})
    assert max(t['x'] for t in tutors) < 85, 'Sanctuary row is full'
    data = {'floor': 60003, 'arrival': {'x': 24, 'y': 36}, 'tutors': tutors, 'rows': dict(row_counts)}
    source = HERE / 'jobTutorData.lua'
    newline = '\r\n' if source.exists() and b'\r\n' in source.read_bytes() else '\n'
    source.write_bytes(('return ' + lua(data) + newline).encode('utf-8'))
    (ROOT / 'gmsv/lua/Modules/jobTutorData.lua').write_bytes(source.read_bytes().decode('utf-8').encode('gbk'))
    out = ROOT / 'docs/skill_training/职业导师坐标.md';out.parent.mkdir(parents=True, exist_ok=True)
    lines = ['# 职业技能导师', '', '全部导师直接位于圣殿（60003）同一房间，无内部传送石。生产系一排（y=10），物理战斗系一排（y=14），法系一排（y=18）；每排从 x=16 起，NPC 中间空一格。封印、饲养、驯兽和回复／辅助职业归法系，医疗、鉴定等生活职业归生产系；游民及混合近战职业归物理战斗系。每个职业独立 NPC，技能名单来自该职业各职阶的原生许可；实际学习仍检查玩家当前职业。宠物来源技能及 BOSS 人物版本不在职业导师目录中。', '',
             'BOSS 人物版本由圣殿 `34,18` 的单个 BOSS 技能导师教授，每页 10 项。宠物学习与遗忘在圣殿 `36,18` 的宠物技能导师办理。', '',
             '| 职业导师 | 职业系列 | 圣殿坐标 |', '| --- | --- | --- |']
    lines += [f"| {t['name']} | {t['family']} | {t['x']},{t['y']} |" for t in tutors]
    lines += ['', '房间加宽后需正常重启服务端加载地图与全部新坐标；法兰与圣殿原有出入口保留。', '']
    out.write_text('\n'.join(lines), 'utf-8')
    print(json.dumps({'occupation_tutors': len(tutors), 'map': data['floor'], 'restart_required': True}))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8');install()
