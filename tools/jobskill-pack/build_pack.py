"""Build a byte-preserving, staged Taiwan-7.1-inspired playable content pack.

Official names/scope are sourced; unverified balance, recipes and entry points
are deliberately marked custom. Never touches character or pet databases.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'docs/jobskill_pack'
BATCH = ROOT / 'backups/jobskill_pack_20261004'
STAGE = BATCH / 'staged'
TABLES = ['jobs.txt', 'jobsancestry.txt', 'skill.txt', 'tech.txt', 'skilllv.txt', 'skillexp.txt', 'itemset.txt', 'itemrecipe.txt']
FOCUS = [0, 3, 8, *range(19, 31), *range(61, 69), 95, 1005, 1007, 1010, 2005]


def digest(b):
    return hashlib.sha256(b).hexdigest()


def pack_digest(manifest):
    return digest(json.dumps(manifest['files'],sort_keys=True,separators=(',',':')).encode('utf-8'))


def decode(b):
    try:
        return b.decode('utf-8')
    except UnicodeDecodeError:
        return b.decode('gbk', errors='replace')


def rows(b):
    return [line.split(b'\t') for line in b.splitlines() if line.strip() and not line.lstrip().startswith((b'#', b'//'))]


def encoded(r):
    return '\t'.join(str(x) for x in r).encode('gbk') + b'\r\n'


def append(original, new):
    return original + (b'' if original.endswith(b'\n') else b'\r\n') + b''.join(encoded(r) for r in new)


# (name, families, prerequisite skill, kind, template skill, effect)
ADVANCED = [
    ('集中', [10], 1006, 'buff', 8, 'physical'),
    ('鲁莽', [20], 1001, 'buff', 8, 'reckless'),
    ('挑衅', [30], 1005, 'taunt', 8, 'taunt'),
    ('鹰眼', [40], 95, 'buff', 8, 'accuracy'),
    ('元素增幅', [70], 19, 'buff', 8, 'magic'),
    ('祝福', [60], 61, 'buff', 8, 'healing'),
    ('防御结界', [130], 64, 'buff', 8, 'barrier'),
    ('巫毒诅咒', [80], 32, 'buff', 8, 'curse'),
    ('短击', [140], 4, 'native', 3, 'short_attack'),
    ('战斗号令', [50], 0, 'buff', 8, 'party_attack'),
    ('独舞', [160], 98, 'buff', 8, 'dodge'),
    ('伺机而动', [150], 96, 'buff', 8, 'critical'),
    ('暗影之手', [120], 72, 'native', 72, 'steal'),
    ('炸弹精炼', [1000], 2002, 'buff', 8, 'bomb'),
    ('手下留情', [90], 69, 'buff', 3, 'nonlethal'),
    ('高等调教', [110], 71, 'buff', 8, 'loyalty'),
    ('因果轮回', [100], 70, 'native', 1010, 'karma'),
    ('肾上腺素', [440], 224, 'buff', 8, 'adrenaline'),
    ('紧急输血', [430], 223, 'native', 61, 'transfusion'),
    ('变身卡制造', [420], 222, 'craft', 210, 'cards'),
    ('变身卷轴制造', [410], 221, 'craft', 210, 'scrolls'),
    ('武器精修', [370], 217, 'native', 217, 'repair_weapon'),
    ('防具精修', [380], 218, 'native', 218, 'repair_armour'),
    ('意外之财', [390], 219, 'passive', 71, 'identify_bonus'),
    ('绝处逢生', [450, 460, 470, 1010], 225, 'passive', 71, 'gather'),
    ('打包', [350, 360], 215, 'passive', 71, 'packing'),
    ('精炼', list(range(200, 341, 10)) + [1020, 1030, 1040, 1050], 200, 'passive', 71, 'refine'),
]


def stage():
    if (BATCH/'manifest.json').exists():
        prior=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'))
        for path,row in prior['files'].items():
            p=ROOT/path
            current=digest(p.read_bytes()) if p.exists() else None
            if current!=row['before']: raise SystemExit('Cannot rebuild after install or concurrent modification: '+path)
    OUT.mkdir(parents=True, exist_ok=True)
    original = {f: (ROOT/'gmsv/data'/f).read_bytes() for f in TABLES}
    data = {f: rows(b) for f, b in original.items()}
    skills = {int(r[1]): [decode(v) for v in r] for r in data['skill.txt']}
    techs = [[decode(v) for v in r] for r in data['tech.txt']]
    jobs = {int(r[2]): [decode(v) for v in r] for r in data['jobs.txt']}
    items = {int(r[11]): [decode(v) for v in r] for r in data['itemset.txt']}
    existing_tech_ids = {int(t[3]) for t in techs}
    extra = {f: [] for f in TABLES}
    manifest = {'format': 1, 'created_utc': datetime.now(timezone.utc).isoformat(), 'policy': 'official_scope_custom_unverified_rules',
                'jobs': [], 'skills': [], 'extended_skills': [], 'recipes': [], 'items': [], 'files': {},
                'sources': ['https://km.softstar.com.tw/topic.aspx?tid=705', 'https://www.cgmsv.com/', 'https://forum.gamer.com.tw/listG.php?bsn=2577'],
                'custom': ['All new IDs, rank titles/requirements, learning hub, skill balance/experience, recipes and item stats are local custom rules.',
                           'Advanced skill names outside the first eight are later-version candidates, supplied as optional custom content.',
                           'Original Angel-continent quest maps are absent; local learning replaces those quests.'],
                'runtime_verified': False, 'client_verified': False}
    family_names = ['宠物服装制造师', '宠物装甲制造师', '宠物项圈制造师', '宠物晶石制造师']
    skill_names = ['宠物轻装制造', '宠物装甲制造', '宠物项圈制造', '宠物晶石制造', '宠物饰品制作', '宠装锻造体验']
    caps = [4, 6, 8, 10, 12, 15, 15]
    for n, name in enumerate(family_names):
        family = 1020 + n*10
        assert all(family+r not in jobs for r in range(1, 8))
        short = ['宠服', '宠甲', '宠圈', '宠晶'][n]
        titles = [short+'学徒', '正职'+short+'师', '资深'+short+'师', '御用'+short+'师', short+'名师', short+'巨匠', short+'神匠']
        for rank in range(1, 8):
            t = jobs[300+rank].copy()
            t[0], t[2], t[6] = titles[rank-1], str(family+rank), str(2100+n)
            # Preserve the existing production-class equipment restrictions.
            extra['jobs.txt'].append(t)
        ancestry = [name, family, *[family+r for r in range(1, 8)], *[10000]*4, 100, 50, 10, 600]
        extra['jobsancestry.txt'].append(ancestry)
        manifest['jobs'].append({'family': family, 'name': name, 'skill': 2100+n, 'ranks': titles, 'caps': caps})

    def template(sid, level=1):
        return next(t.copy() for t in techs if int(t[5] or -1)==sid and int(t[6] or 0)==level)

    def new_skill(name, sid, source, families, kind, maxlv, effect='', prereq=0):
        assert sid not in skills
        t = skills[source].copy()
        t[0], t[1], t[4], t[6], t[8], t[10], t[16], t[17], t[18] = name, str(sid), str(maxlv), '10000', '255', '3' if kind in ('craft','trial') else '1', '0', str(families[0] if len(families)==1 else 0), '100'
        if kind in ('buff', 'taunt'):
            t[3], t[5], t[9], t[11] = '1', '1', '2', ''
        elif kind=='passive':
            t[3], t[5], t[9], t[11] = '0', '1', '2', ''
        extra['skill.txt'].append(t)
        spec = {'id': sid, 'name': name, 'families': families, 'kind': kind, 'max_level': maxlv, 'effect': effect,
                'prerequisite': prereq, 'min_character_level': 140 if len(manifest['skills'])>=6 and len(manifest['skills'])<14 else 100,
                'techs': []}
        manifest['skills'].append(spec)
        return spec

    # Native manufacturing with one distinct product at every rank.
    base_items = {56: next(r for r in items.values() if r[14]=='11'),
                  57: next(r for r in items.values() if r[14]=='10'),
                  58: next(r for r in items.values() if r[14]=='21'),
                  59: next(r for r in items.values() if r[14]=='22'),
                  60: next(r for r in items.values() if r[14]=='21')}
    material_ids = [9611, 9612, 9613, 9614, 9615, 9616, 9617, 9618, 9619, 9620]
    material_ids = [i for i in material_ids if i in items]

    def recipe(spec, level, product, item_type=None, native_item=None):
        rid = 6200 + len(manifest['recipes'])
        iid = 700000 + len(manifest['items'])
        assert iid not in items and rid not in {int(r[1]) for r in data['itemrecipe.txt']}
        item = (native_item or base_items[item_type]).copy()
        item += [''] * max(0, 104-len(item))
        item[0], item[1], item[11], item[13], item[22], item[23] = product, product, str(iid), '0', '1', str(level)
        item[94], item[95] = '0', '0'
        if item_type is not None:
            for col in range(2, 11): item[col]=''
            item[14], item[17], item[18], item[19], item[24], item[25], item[26] = str(item_type), '1', '2', '0', '0', '300', '300'
            for col in range(27, 88): item[col]=''
            # itemset has paired minimum/maximum modifiers.
            stats = {56: {33: 8*level, 37: 3*level}, 57: {33: 12*level, 37: 2*level, 47: -level},
                     58: {31: 8*level}, 59: {41: level, 43: level, 45: level, 47: level}, 60: {49: 8*level, 51: 4*level}}[item_type]
            for col, value in stats.items(): item[col]=item[col+1]=str(value)
            item[88], item[89], item[90], item[93], item[101], item[102], item[103] = '0', '0', '1', '0', '0', str(level), str(level)
        extra['itemset.txt'].append(item)
        mat = material_ids[min(level-1, len(material_ids)-1)]
        wood = 10000 + min(level-1, 9)
        if wood not in items: wood=10000
        rr = [product, rid, iid, spec['id'], 120, mat, wood, '', '', '', 2+level, 5+level, '', '', '']
        extra['itemrecipe.txt'].append(rr)
        manifest['items'].append({'id': iid, 'name': product, 'type': item_type or int(item[14]), 'level': level})
        manifest['recipes'].append({'id': rid, 'skill': spec['id'], 'level': level, 'item': iid, 'materials': [[mat,2+level],[wood,5+level]]})
        return rid

    for n, name in enumerate(skill_names):
        sid = 2100+n
        families = [1020+n*10] if n<4 else [1020,1030,1040,1050]
        if n==5: families=[0]
        spec = new_skill(name, sid, 210 if n<5 else 252, families, 'craft' if n<5 else 'trial', 15 if n<5 else 1)
        spec['min_character_level']=1
        first = None
        for lv in range(1, spec['max_level']+1):
            rid = recipe(spec, lv, (['宠服','宠甲','宠圈','宠晶','宠饰','练习宠饰'][n])+'R'+str(lv), 56+min(n,4))
            if first is None: first=rid
            t = template(210)
            tid = 610000+n*100+lv-1
            t[0], t[3], t[4], t[5], t[6], t[11], t[13], t[14] = name+'LV'+str(lv), str(tid), '130210', str(sid), str(lv), str(10+10*lv), str(first), str(rid)
            extra['tech.txt'].append(t); spec['techs'].append(tid)

    for n, (name, families, prereq, kind, source, effect) in enumerate(ADVANCED):
        sid = 2200+n
        spec = new_skill(name, sid, source, families, kind, 5, effect, prereq)
        spec['min_character_level']=140 if n<8 else 100
        spec['prerequisite_level']=15 if n<8 and prereq in FOCUS else 10
        first = None
        for lv in range(1, 6):
            t = template(source)
            tid = 611000+n*10+lv-1
            t[0], t[3], t[5], t[6], t[11], t[13], t[14] = name+'LV'+str(lv), str(tid), str(sid), str(lv), str(15+5*lv), '', ''
            if kind=='buff':
                t[1], t[2], t[4], t[8], t[7] = 'TECH_Lua', '', '130008', '72', '1'
                if effect in ('barrier','adrenaline'): t[8]='93'
                if effect in ('curse','nonlethal'): t[8]='125'
            elif kind=='taunt':
                t = next(x.copy() for x in techs if x[1]=='TECH_Taunt')
                t += [''] * max(0,15-len(t))
                t[0], t[3], t[4], t[5], t[6], t[11] = name+'LV'+str(lv), str(tid), '130008', str(sid), str(lv), str(15+5*lv)
                t[2]='DD:1,DD2:95,SR:10000,SR2:'+str(3000+lv*500)+',CH:3,'
            elif effect in ('short_attack','nonlethal'):
                t[1], t[2], t[4], t[8] = 'TECH_Parameter', 'AS:0,HR:10,DD:'+str(10+lv*10)+',', '130003', '1141'
            elif effect=='karma':
                t = next(x.copy() for x in techs if x[1]=='TECH_MadmaxEx')
                t[0],t[3],t[4],t[5],t[6],t[11] = name+'LV'+str(lv),str(tid),'3007201',str(sid),str(lv),str(15+5*lv)
                t[2]='DD:'+str(120+lv*10)+',AR:10,MIN:1000,MAX:6000,'
            elif effect=='transfusion': t[2]='AR:'+str(100+80*lv)+','
            elif kind=='passive': t[1],t[2],t[11]='TECH_Train','AR:250,CH:100,','0'
            elif effect.startswith('repair_'):
                # Native repair levels 1..5 retain native equipment checks.
                t[7], t[8] = '2', '65'
            elif kind=='craft':
                cards = [r for r in items.values() if r[5]=='IuCM']
                product_template = cards[(lv-1) if effect=='cards' else (lv+4)]
                rid=recipe(spec,lv,('变身卡' if effect=='cards' else '变身卷轴')+'R'+str(lv), native_item=product_template)
                if first is None: first=rid
                t[1],t[4],t[13],t[14],t[7],t[8]='TECH_MergeItem','130210',str(first),str(rid),'2','65'
            extra['tech.txt'].append(t); spec['techs'].append(tid)

    # Extend only the declared 28 skills, preserving all original levels/animations.
    for sid in FOCUS:
        t9, t10 = template(sid,9), template(sid,10)
        levels = {int(t[6]) for t in techs if int(t[5] or -1)==sid}
        assert not levels.intersection(range(11,16))
        opt9 = {k:int(v) for k,v in re.findall(r'([A-Z][A-Z0-9]*):(-?\d+)', t9[2])}
        opt10 = {k:int(v) for k,v in re.findall(r'([A-Z][A-Z0-9]*):(-?\d+)', t10[2])}
        ids=[]
        for lv in range(11,16):
            t=t10.copy(); tid=600000+FOCUS.index(sid)*5+lv-11
            assert tid not in existing_tech_ids
            options=opt10.copy()
            for k, value in options.items():
                if k in ('AR','RR','DD','HR','SR','DR','RS','RE','AN','AM'):
                    options[k]=value+(value-opt9.get(k,value))*(lv-10)
                if k in ('SR','DR','RS','RE'): options[k]=min(100, max(0, options[k]))
                if k in ('AN','AM'): options[k]=min(20,max(1,options[k]))
            if sid==0:
                options['AN']=options['AM']=6+(lv-10)//2
                options['DD']=round(100/options['AN'])-100
            if sid==8: options['RS']=min(95,options['RS'])
            t[0],t[3],t[6],t[11],t[2] = skills[sid][0]+'LV'+str(lv), str(tid),str(lv),str(int(t10[11])+(int(t10[11])-int(t9[11]))*(lv-10)), ''.join(f'{k}:{v},' for k,v in options.items())
            extra['tech.txt'].append(t); ids.append(tid)
        manifest['extended_skills'].append({'id':sid,'name':skills[sid][0],'levels':[11,12,13,14,15],'techs':ids})

    # Keep old rank restrictions; only professions already capped at ten unlock
    # 11..15 at fifth promotion (rank 6+) on the local server.
    limit_lines=[]
    for line in original['skilllv.txt'].splitlines(keepends=True):
        r=line.rstrip(b'\r\n').split(b'\t')
        if len(r)>=4 and r[1].isdigit() and int(r[1]) in FOCUS and int(r[3] or 0)==10 and int(r[2])%10>=6:
            r[3]=b'15'; line=b'\t'.join(r)+ (b'\r\n' if line.endswith(b'\r\n') else b'\n')
        limit_lines.append(line)
    max_limit_id=max(int(r[0]) for r in data['skilllv.txt'])
    all_jobs=list(jobs)+[f+r for f in (1020,1030,1040,1050) for r in range(1,8)]
    for spec in manifest['skills']:
        for jid in all_jobs:
            family=jid//10*10; rank=jid%10
            cap=0
            if spec['kind']=='trial': cap=1
            elif spec['id'] in range(2100,2105) and family in spec['families']: cap=caps[rank-1]
            elif family in spec['families'] and rank>=4: cap=spec['max_level']
            max_limit_id+=1
            extra['skilllv.txt'].append([max_limit_id,spec['id'],jid,cap])
    for jid in [f+r for f in (1020,1030,1040,1050) for r in range(1,8)]:
        rank=jid%10
        for sid in skills:
            max_limit_id+=1
            # Copy existing tailor limits exactly, avoiding universal access.
            old=next((r for r in data['skilllv.txt'] if int(r[1])==sid and int(r[2])==300+rank),None)
            extra['skilllv.txt'].append([max_limit_id,sid,jid,int(old[3]) if old else 0])
    updated={f:append(original[f],extra[f]) for f in TABLES}
    updated['skilllv.txt']=append(b''.join(limit_lines),extra['skilllv.txt'])
    # Seven finite tables, levels 14/15 and a level-16 terminator. Existing
    # level-1..13 thresholds retain their exact values.
    ex=[]
    for r in data['skillexp.txt']:
        values=[int(v) for v in r]
        base=values[:-1]
        delta=base[-1]-base[-2]
        ex.append(base+[base[-1]+2*delta,base[-1]+5*delta,99999999])
    updated['skillexp.txt']=b''.join(encoded(r) for r in ex)
    config=(ROOT/'gmsv/cgmsv.cf').read_bytes()
    config=re.sub(rb'(?m)^maxlevel=\d+',b'maxlevel=200',config)
    module_config=(ROOT/'gmsv/lua/ModuleConfig.lua').read_bytes()
    if b"loadModule('cg71JobSkills')" not in module_config: module_config+=b"\r\nloadModule('cg71JobSkills')\r\n"
    updated_paths={'gmsv/data/'+f:b for f,b in updated.items()}
    updated_paths['gmsv/cgmsv.cf']=config
    updated_paths['gmsv/lua/ModuleConfig.lua']=module_config
    module=(HERE/'cg71JobSkills.lua').read_text(encoding='utf-8').encode('gbk')
    updated_paths['gmsv/lua/Modules/cg71JobSkills.lua']=module
    def lua_value(v):
        if isinstance(v,dict): return '{'+','.join('['+lua_value(k)+']='+lua_value(x) for k,x in v.items())+'}'
        if isinstance(v,list): return '{'+','.join(lua_value(x) for x in v)+'}'
        if isinstance(v,str): return '"'+v.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n')+'"'
        if v is None: return 'nil'
        if isinstance(v,bool): return 'true' if v else 'false'
        return str(v)
    updated_paths['gmsv/lua/Modules/cg71JobSkillsData.lua']=('return '+lua_value({k:manifest[k] for k in ['jobs','skills','extended_skills','recipes','items']})+'\n').encode('gbk')
    for path, value in updated_paths.items():
        existing=ROOT/path
        before=existing.read_bytes() if existing.exists() else None
        if before is not None:
            dest=BATCH/'before'/path; dest.parent.mkdir(parents=True,exist_ok=True)
            if dest.exists(): assert dest.read_bytes()==before, 'Baseline changed: '+path
            else: dest.write_bytes(before)
        dest=STAGE/path; dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes(value)
        manifest['files'][path]={'before':digest(before) if before is not None else None,'after':digest(value),'size':len(value)}
    (BATCH/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'staged':str(STAGE),'jobs':28,'new_skills':len(manifest['skills']),'extended_skills':len(FOCUS),'new_techs':len(extra['tech.txt']),'recipes':len(manifest['recipes'])}))


def apply():
    m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'))
    # Check every input before any write; stop on concurrent changes.
    for path, row in m['files'].items():
        p=ROOT/path
        before=digest(p.read_bytes()) if p.exists() else None
        if before not in (row['before'],row['after']): raise SystemExit('Concurrent modification: '+path)
        if digest((STAGE/path).read_bytes())!=row['after']: raise SystemExit('Stage was modified: '+path)
    validation=OUT/'native_certification.json'
    if not validation.exists(): raise SystemExit('Certify the isolated native validation before apply.')
    certified=json.loads(validation.read_text(encoding='utf-8'))
    if certified['result']!='PASS' or certified['pack_sha256']!=pack_digest(m):
        raise SystemExit('Native validation is stale or did not pass for this exact pack.')
    for path in m['files']:
        dest=ROOT/path; dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes((STAGE/path).read_bytes())
    m.update(runtime_verified=True,runtime_verified_scope='isolated_native_server',installed_utc=datetime.now(timezone.utc).isoformat(),production_reload_pending=True)
    for p in [BATCH/'manifest.json',OUT/'manifest.json']:
        p.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('APPLIED '+str(len(m['files']))+' files; character/pet databases untouched')


if __name__=='__main__':
    action=argparse.ArgumentParser(); action.add_argument('action',choices=['stage','apply']); a=action.parse_args()
    stage() if a.action=='stage' else apply()
