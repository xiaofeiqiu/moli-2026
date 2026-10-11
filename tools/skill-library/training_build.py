"""Build six categorized tutors from installed DATA without changing skill IDs."""
from pathlib import Path
from collections import defaultdict, Counter
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'docs/skill_training'
sys.path.insert(0, str(HERE))
from build import lua
from pet_support_install import PET_SUPPORT_NATIVE, lesson_name
from pet_elemental_install import PET_ELEMENTAL_NATIVE, lesson_name as elemental_lesson_name


def rows(name):
    return [r.split('\t') for r in (ROOT / 'gmsv/data' / name).read_text('gbk', errors='replace').splitlines()
            if r.strip() and not r.lstrip().startswith(('#', '//'))]


PRODUCTION = {'TECH_MergeItem', 'TECH_RepairItem', 'TECH_JudgeItem', 'TECH_MarkItem', 'TECH_Lumb',
              'TECH_Cutting', 'TECH_Hunting', 'TECH_Mining', 'TECH_Fishing', 'TECH_AppendJewel',
              'TECH_MedicalTreatment', 'TECH_Allowance'}
CONTROL = {'TECH_StatusChange', 'TECH_StatusAttack', 'TECH_StatusResistance', 'TECH_StatusRecover',
           'TECH_Reverse_Type', 'TECH_Reflection_Physics', 'TECH_Reflection_Magic', 'TECH_Absorb_Physics',
           'TECH_Absorb_Magic', 'TECH_Ineffective_Physics', 'TECH_Ineffective_Magic', 'TECH_Taunt',
           'TECH_DefUp', 'TECH_DefDown', 'TECH_AtkUp', 'TECH_AtkDown', 'TECH_AglUp',
           'TECH_AglDown', 'TECH_MagicGuard', 'TECH_SpecialGuard', 'TECH_Seal', 'TECH_Dance',
           'TECH_Train', 'TECH_Breed', 'TECH_Metamorphosis', 'TECH_MonWind', 'TECH_Barrier', 'TECH_LvSet'}
MAGIC = {'TECH_Attack_Magic', 'TECH_Heal_Magic', 'TECH_LpRecovery', 'TECH_Revive', 'TECH_Dorain',
         'TECH_MagicMissile', 'TECH_EarthQuake', 'TECH_Treat_Type', 'TECH_Acid'}
HEALING = {'TECH_Heal_Magic', 'TECH_LpRecovery', 'TECH_Revive', 'TECH_StatusRecover',
           'TECH_MedicalTreatment', 'TECH_Allowance', 'TECH_Consentration', 'TECH_Sacrifice'}
OVERRIDES = {2100: 'production', 2101: 'production', 2102: 'production', 2103: 'production',
             2104: 'production', 2105: 'production', 2213: 'production', 2219: 'production',
             2220: 'production', 2221: 'production', 2222: 'production', 2225: 'production',
             2226: 'production', 2204: 'magic', 2205: 'magic', 2218: 'healing', 2200: 'control',
             2201: 'control', 2202: 'control', 2203: 'control', 2206: 'control', 2207: 'control',
             2209: 'control', 2210: 'control', 2211: 'control', 2215: 'control', 2217: 'control',
             2223: 'control', 2224: 'control'}


def category(sid, fn, marker=None):
    if fn in HEALING or sid == 2218:
        return 'healing'
    if marker == 50:
        return 'boss'
    if sid in OVERRIDES:
        return OVERRIDES[sid]
    if fn in PRODUCTION:
        return 'production'
    if fn in CONTROL:
        return 'control'
    if fn in MAGIC:
        return 'magic'
    return 'physical'


def build():
    from pet_qigong_install import install_techs
    install_techs()
    from pet_physical_install import install_techs as install_physical_techs
    install_physical_techs()
    skills = {int(r[1]): r for r in rows('skill.txt')}
    techs = rows('tech.txt')
    by = defaultdict(list)
    for r in techs:
        by[int(r[5])].append(r)
    manifest = json.loads((ROOT / 'docs/skill_library/manifest.json').read_text('utf-8'))
    previous = {d['id']: d for d in manifest['player_skills']}
    definitions, players, pets = [], [], []
    # Existing human copies retain their tested archive behavior and experience.
    for sid, r in sorted(skills.items()):
        old = previous.get(sid)
        candidates = [t for t in by[sid] if 1 <= int(t[6] or 0) <= 30 and (t[7] != '1' or t[12] == '1') and t[1]]
        marker = old.get('source_marker') if old else None
        fn = old['source_function'] if old else (candidates[0][1] if candidates else (by[sid][0][1] if by[sid] else ''))
        source = ('boss' if marker == 50 else 'pet') if old and old.get('source_tech') else ('normal' if old else 'quest')
        cat = category(old.get('source_skill', sid) if old else sid, fn, marker)
        cost = 0 if sid == 2105 else (1000 if 2100 <= sid <= 2104 else int(r[6] or 0))
        max_level = 30 if old else max((int(t[6]) for t in candidates), default=0)
        s = {'id': sid, 'name': r[0], 'category': cat, 'source': source, 'cost': cost, 'max_level': max_level}
        if not old:
            # No blank handlers or monster-only sentinels may be equipped by players.
            if not any(int(t[6]) == 1 for t in candidates):
                s['unavailable'] = '此记录只有怪物招式或没有有效的1级人物招式，请学习同名人物版本。'
            else:
                canonical = {}
                for t in candidates:
                    canonical.setdefault(int(t[6]), t)
                defs = {'id': sid, 'name': r[0], 'cost': cost, 'max_level': max_level,
                        'techs': [int(t[3]) for _, t in sorted(canonical.items())], 'xp_mode': 'native'}
                # Shared instructors already contain these native Lua stubs. Reuse
                # the archive's tested effects rather than leave their casts empty.
                if sid in (721, 722, 797):
                    defs.update(behavior='gold' if sid == 797 else 'death', xp_mode='lua', source_options=canonical[1][2])
                definitions.append(defs)
        players.append(s)
    seen = set()
    for t in techs:
        # Native pets need original Tech IDs; never give them human Lua variants.
        support = t[3].isdigit() and int(t[3]) in PET_SUPPORT_NATIVE
        elemental = t[3].isdigit() and int(t[3]) in PET_ELEMENTAL_NATIVE
        if (not (support or elemental) and (t[12] != '0' or t[6] not in ('30', '50'))) or t[7] != '1' or not t[1] or t[1] == 'TECH_Lua':
            continue
        tid, sid = int(t[3]), int(t[5])
        # Shared E1 healing copy uses an unsupported client animation family.
        # Teach native 6350; the tutor normalizes already learned 700826 at cast time.
        if tid == 700826 or tid in seen:
            continue
        seen.add(tid)
        name = lesson_name(tid, t[0]) if support else (elemental_lesson_name(tid, t[0]) if elemental else t[0])
        pets.append({'id': tid, 'name': name, 'category': category(sid, t[1], int(t[6])),
                     'source': 'boss' if t[6] == '50' else 'pet', 'cost': 1000})
    recipes = []
    items = {int(r[0]): r for r in rows('itemset.txt') if r[0].isdigit()}
    for r in rows('itemrecipe.txt'):
        # Native recipe columns: name, ID, product item, skill, success rate.
        # Its learning level is determined by the skill's authored Tech range.
        if len(r) > 3 and r[1].isdigit() and r[3].isdigit():
            rid, sid = int(r[1]), int(r[3])
            levels = [int(t[6]) for t in by[sid] if t[1] == 'TECH_MergeItem'
                      and t[13].isdigit() and t[14].isdigit() and int(t[13]) <= rid <= int(t[14])
                      and 1 <= int(t[6]) <= 30]
            item = items.get(int(r[2]))
            fallback = max(1, min(30, int(item[24] or 1))) if item else 1
            recipes.append({'id': rid, 'skill': sid, 'level': min(levels) if levels else fallback})
    cats = [{'id': k, 'name': name, 'image': image, 'x': x, 'y': 122}
            for k, name, image, x in [('physical', '物理技能导师', 100005, 149),
                                     ('magic', '魔法技能导师', 100004, 151),
                                     ('control', '控制技能导师', 100006, 153),
                                     ('production', '生产技能导师', 14058, 155),
                                     ('boss', 'BOSS技能导师', 100003, 157),
                                     ('healing', '回复技能导师', 100007, 159)]]
    data = {'categories': cats, 'players': players, 'pets': pets, 'library_additions': definitions, 'recipes': recipes}
    OUT.mkdir(parents=True, exist_ok=True)
    (ROOT / 'gmsv/lua/Modules/skillTrainingData.lua').write_bytes(('return ' + lua(data) + '\n').encode('gbk'))
    (ROOT / 'gmsv/lua/Modules/skillTraining.lua').write_bytes((HERE / 'skillTraining.lua').read_text('utf-8').encode('gbk'))
    config = ROOT / 'gmsv/lua/ModuleConfig.lua'
    raw = config.read_bytes()
    if b"loadModule('skillTraining')" not in raw:
        config.write_bytes(raw + b"\r\nloadModule('skillTraining')\r\n")
    report = {'players': len(players), 'pets': len(pets), 'library_additions': len(definitions),
              'player_categories': dict(Counter(s['category'] for s in players)),
              'pet_categories': dict(Counter(s['category'] for s in pets)),
              'unavailable': [s for s in players if s.get('unavailable')], 'recipes': len(recipes)}
    (OUT / 'catalog.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), 'utf-8')
    (OUT / 'build_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
    from pet_skill_install import main as install_separation
    install_separation()
    print(json.dumps({k: v for k, v in report.items() if k != 'unavailable'}, ensure_ascii=False))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    build()
