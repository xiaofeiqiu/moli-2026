"""Stage all-player level-30 DATA and a persistent, transactional skill library."""
from pathlib import Path
from collections import defaultdict, Counter
from datetime import datetime, timezone
import argparse, hashlib, json, re, sys
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools/jobskill-pack'))
from build_pack import rows, decode, encoded, append, digest
BATCH=ROOT/'backups/skill_library_20261004'
STAGE=BATCH/'staged'
OUT=ROOT/'docs/skill_library'
def fingerprint(m): return digest(json.dumps(m['files'],sort_keys=True,separators=(',',':')).encode())
def loader_extensions(actual,expected):
    """Preserve modules appended by other work after this pack was installed."""
    if not actual.startswith(expected):return None
    tail=actual[len(expected):]
    if not re.fullmatch(rb"(?:\s|loadModule\('[A-Za-z][A-Za-z0-9_]*'\))*",tail):return None
    return [s.decode('ascii') for s in re.findall(rb"loadModule\('([A-Za-z][A-Za-z0-9_]*)'\)",tail)]
def lua(v):
    if isinstance(v,dict): return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in v.items())+'}'
    if isinstance(v,list): return '{'+','.join(map(lua,v))+'}'
    if isinstance(v,str): return json.dumps(v,ensure_ascii=False)
    if isinstance(v,bool): return 'true' if v else 'false'
    if v is None: return 'nil'
    return str(v)
def stage():
    OUT.mkdir(parents=True,exist_ok=True)
    if (BATCH/'manifest.json').exists():
        prior=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'))
        for p,r in prior['files'].items():
            assert (digest((ROOT/p).read_bytes()) if (ROOT/p).exists() else None)==r['before'],'Installed/concurrent change: '+p
    raw={n:(ROOT/'gmsv/data'/n).read_bytes() for n in ['skill.txt','skilllv.txt','tech.txt','skillexp.txt']}
    skills={int(r[1]):r for r in rows(raw['skill.txt'])}
    limits=rows(raw['skilllv.txt']); jobs={int(r[2]) for r in rows((ROOT/'gmsv/data/jobs.txt').read_bytes())}
    previous_eligible={int(r[1]) for r in limits if r[1].isdigit() and r[2].isdigit() and r[3].isdigit() and int(r[2]) in jobs and int(r[3])>0 and int(r[1]) in skills}
    eligible=set(skills)
    mage={int(r[1]) for r in limits if r[1].isdigit() and r[2].isdigit() and r[3].isdigit() and 71<=int(r[2])<=77 and int(r[3])>0}
    tech=rows(raw['tech.txt']); by=defaultdict(list)
    for r in tech:
        if r[5].isdigit(): by[int(r[5])].append(r)
    oldpack=json.loads((ROOT/'docs/jobskill_pack/manifest.json').read_text(encoding='utf-8'))
    names={i:decode(s[0]) for i,s in skills.items()}
    names.update({s['id']:s['name'] for s in oldpack['skills']})
    monster_sources=[r for r in tech if int(r[6]) in (30,50) or int(r[5]) in (257,258,259)]
    pet_boss_ids={int(r[5]) for r in monster_sources}
    knight_extra=pet_boss_ids | (eligible-previous_eligible)
    newtech=[]; defs=[]; nextid=800000; used={int(r[3]) for r in tech}
    wrapped={'TECH_Death':'death','TECH_Summon':'summon','TECH_StatusAttack':'status','TECH_EquipBreakAttack':'break','TECH_GoldAttack':'gold','TECH_EnergyDrain':'energy','TECH_BloodAttack':'blood','TECH_MonWind':'dispel','TECH_Acid':'acid','TECH_Barrier':'barrier'}
    # Explicit 1..30 player variants coexist with untouched enemy/legacy Techs.
    for sid in sorted(eligible):
        candidates=[r for r in by[sid] if r[6].isdigit() and 1<=int(r[6])<=15]
        if candidates:
            # Empty future manufacturing rows are not useful product templates.
            good=[r for r in candidates if r[1]!=b'TECH_MergeItem' or (len(r)>14 and r[13] and r[14])]
            base=max(good or candidates,key=lambda r:int(r[6])); start=int(base[6])
        elif by[sid]: base=by[sid][0]; start=1
        else:
            # Reserved Lion Roar is made playable as a native targeted taunt.
            assert sid==112,'No handler for player skill '+str(sid)
            base=next(r for r in by[2202] if int(r[6])==1); start=1
        existing={int(r[6]):r for r in candidates}
        source_function=base[1].decode('ascii',errors='replace');source_options=base[2].decode('ascii',errors='replace')
        behavior=wrapped.get(source_function,'rest' if not source_function else None)
        if behavior:
            existing={};base=list(base);base[1]=b'TECH_Lua';base[7]=b'1'
            if behavior in ('summon','barrier','rest'):base[8]=b'72'
        if sid not in previous_eligible:
            existing={} # explicit player variants; original monster variants remain unchanged
            base=list(base);base[9]=b'';base[12]=b'1'
            if sid==262:base[1]=b'TECH_Lua';base[2]=b'';base[4]=b'130008';base[8]=b'97'
        if int(base[7] or 0)==1:base=list(base);base[9]=b'';base[12]=b'1'
        ids=[]
        for lv in range(1,31):
            # Low-level native variants are still used; do not duplicate them.
            if lv in existing and not (base[1]==b'TECH_MergeItem' and not existing[lv][13]) and not (int(base[7] or 0)==1 and (existing[lv][12]!=b'1' or existing[lv][9])):
                ids.append(int(existing[lv][3])); continue
            r=list(base)+[b'']*max(0,15-len(base))
            while nextid in used: nextid+=1
            tid=nextid;nextid+=1;used.add(tid)
            r[0]=(names[sid]+'LV'+str(lv)).encode('gbk');r[3]=str(tid).encode();r[5]=str(sid).encode();r[6]=str(lv).encode()
            if sid==112:r[4]=b'130008'
            factor=1+max(0,lv-start)*0.05
            fn=base[1].decode('ascii',errors='replace')
            def scale(match):
                k,v=match[1],int(match[2]);value=v
                if k in ('AR','RR') and v>0: value=round(v*factor)
                elif k=='DD': value=round((100+v)*factor)-100
                elif fn=='TECH_StatusResistance' and k in ('PO','SL','ST','YO','CN','AA') and v>0:value=min(95,round(v*factor))
                elif k in ('D1','D2') and fn in ('TECH_Dorain','TECH_Consentration','TECH_EarthQuake') and v>0: value=round(v*factor)
                return f'{k}:{max(-10000,min(1000000,value))}'
            r[2]=re.sub(r'([A-Z][A-Z0-9]*):(-?\d+)',scale,base[2].decode('ascii',errors='replace')).encode('ascii')
            if base[11].isdigit():r[11]=str(min(100000,round(int(base[11])*factor))).encode()
            if base[1]==b'TECH_MergeItem':
                valid=[x for x in candidates if len(x)>14 and x[13].isdigit() and x[14].isdigit()]
                if valid:r[13]=str(min(int(x[13]) for x in valid)).encode();r[14]=str(max(int(x[14]) for x in valid)).encode()
            newtech.append(r);ids.append(tid)
        defs.append({'id':sid,'name':names[sid],'techs':ids,'template_level':start,'function':base[1].decode('ascii',errors='replace'),'source_function':source_function,'source_options':source_options,'behavior':behavior})
    # Each original pet/BOSS variant remains a separate learnable skill, so its
    # exact effect/range is available instead of disappearing into a shared ID.
    skill_additions=[];cap_additions=[];source_mapping=[]
    next_skill=4000
    for source in monster_sources:
        while next_skill in skills:next_skill+=1
        sid=next_skill;next_skill+=1
        source_lv=int(source[6]);tag='宠物' if source_lv==30 else ('BOSS' if source_lv==50 else '怪物')
        title=source[0].decode('gbk',errors='replace')
        name=tag+'·'+title
        if not source[1]:name+='（休息版）'
        while len(name.encode('gbk'))>30:name=name[:-1]
        names[sid]=name
        s=[name.encode('gbk'),str(sid).encode(),source[4] or b'130019',b'1',b'30',b'1',b'1000',b'100',b'255',b'2',b'1',b'',b'1000',b'',b'',b'',b'0',b'',b'']
        skill_additions.append(s);skills[sid]=s;eligible.add(sid);knight_extra.add(sid)
        for jid in range(31,38):cap_additions.append([name,sid,jid,30])
        ids=[]
        for lv in range(1,31):
            r=list(source)+[b'']*max(0,15-len(source))
            while nextid in used:nextid+=1
            tid=nextid;nextid+=1;used.add(tid);ids.append(tid)
            r[0]=(name+'L'+str(lv)).encode('gbk');r[3]=str(tid).encode();r[5]=str(sid).encode();r[6]=str(lv).encode()
            r[9]=b'';r[12]=b'1' # human variant, not the pet experience gate
            if not r[4]:r[4]=b'130019'
            if not r[1]:r[1]=b'TECH_Lua';r[8]=b'72';r[7]=b'1'
            if source[1].decode('ascii',errors='replace') in wrapped:
                r[1]=b'TECH_Lua'
                if source[1] in (b'TECH_Summon',b'TECH_Barrier'):r[8]=b'72'
            factor=1+(lv-1)*0.05
            fn=r[1].decode('ascii')
            def monster_scale(match):
                key,val=match[1],int(match[2]);v=val
                if key in ('AR','RR') and val>0:v=round(val*factor)
                elif key=='DD':v=round((100+val)*factor)-100
                elif fn=='TECH_StatusResistance' and key in ('PO','SL','ST','YO','CN','AA') and val>0:v=min(95,round(val*factor))
                elif key in ('D1','D2') and fn in ('TECH_EarthQuake','TECH_Consentration') and val>0:v=round(val*factor)
                return f'{key}:{max(-10000,min(1000000,v))}'
            r[2]=re.sub(r'([A-Z][A-Z0-9]*):(-?\d+)',monster_scale,r[2].decode('ascii',errors='replace')).encode('ascii')
            original_mp=int(source[11] or 0)
            r[11]=str(round(max(10,original_mp)*factor) if int(source[7])==1 else original_mp).encode()
            newtech.append(r)
        defs.append({'id':sid,'name':name,'techs':ids,'template_level':1,'function':r[1].decode('ascii'),'source_function':source[1].decode('ascii',errors='replace'),'behavior':wrapped.get(source[1].decode('ascii',errors='replace'),'rest' if not source[1] else None),'source_tech':int(source[3]),'source_marker':source_lv,'source_options':source[2].decode('ascii',errors='replace')})
        source_mapping.append({'skill':sid,'source_tech':int(source[3]),'source_skill':int(source[5]),'source_marker':source_lv,'name':name})
    # Native character technique lists hold at most 30 entries per skill.
    # Put exactly one canonical player variant per level first, otherwise old
    # enemy level-30 variants can crowd the real player level-30 entry out.
    canonical={tid for d in defs for tid in d['techs']}
    oldlines=raw['tech.txt'].splitlines(keepends=True)
    priority=[];extras=[]
    for line in oldlines:
        r=line.rstrip(b'\r\n').split(b'\t')
        (priority if len(r)>3 and r[3].isdigit() and int(r[3]) in canonical else extras).append(line)
    techbytes=b''.join(priority)+b''.join(b'\t'.join(r)+b'\r\n' for r in newtech)+b''.join(extras)
    # Only rows belonging to actual jobs are opened; zero means forbidden.
    changed=0; outlimit=[]
    for line in raw['skilllv.txt'].splitlines(keepends=True):
        r=line.rstrip(b'\r\n').split(b'\t')
        if len(r)>=4 and r[1].isdigit() and r[2].isdigit() and r[3].isdigit() and int(r[2]) in jobs:
            sid,jid,cap=int(r[1]),int(r[2]),int(r[3])
            if sid in eligible and (cap>0 or (31<=jid<=37 and sid in mage | knight_extra)):
                r[3]=b'30';changed+=int(cap!=30);line=b'\t'.join(r)+(b'\r\n' if line.endswith(b'\r\n') else b'\n')
        outlimit.append(line)
    outlimit.extend(encoded(r) for r in cap_additions)
    limit_pairs={(int(r[1]),int(r[2])) for r in limits if r[1].isdigit() and r[2].isdigit()}
    for sid in knight_extra:
        if sid in {int(s[1]) for s in skill_additions}:continue
        for jid in range(31,38):
            if (sid,jid) not in limit_pairs:outlimit.append(encoded([names[sid],sid,jid,30]))
    outskill=[]
    for line in raw['skill.txt'].splitlines(keepends=True):
        r=line.rstrip(b'\r\n').split(b'\t')
        if len(r)>18 and r[1].isdigit() and int(r[1]) in eligible:
            r[4]=b'30';r[10]=b'1' # one skill per active slot
            line=b'\t'.join(r)+(b'\r\n' if line.endswith(b'\r\n') else b'\n')
        outskill.append(line)
    outskill.extend(b'\t'.join(r)+b'\r\n' for r in skill_additions)
    ex=[]
    for r in rows(raw['skillexp.txt']):
        v=[int(x) for x in r]; v=v[:-1] # remove previous level-16 sentinel
        delta=max(100,v[-1]-v[-2])
        while len(v)<31: # table ID + levels 1..30
            delta=round(delta*1.10);v.append(v[-1]+delta)
        assert v[-1]<2147483647
        ex.append(v+[2147483647])
    cf=(ROOT/'gmsv/cgmsv.cf').read_bytes()
    for key,val in [('maxskilllevel',30),('maxtechlevel',30),('maxcraftskilllevel',30),('maxskillnum',15),('initcharskillslot',15)]:
        cf=re.sub(rb'(?m)^'+key.encode()+rb'=\d+',(key+'='+str(val)).encode(),cf)
    dpath=ROOT/'gmsv/lua/Modules/cg71JobSkillsData.lua'
    # Reconstruct the existing declarative data, preserving every recipe/item.
    olddata={k:oldpack[k] for k in ['jobs','skills','extended_skills','recipes','items']}
    dmap={d['id']:d for d in defs}
    for s in olddata['skills']:
        s['max_level']=30;s['techs']=dmap[s['id']]['techs']
        if s['id']==2204:s['families']=[70,30]
    for j in olddata['jobs']:j['caps']=[30]*7
    cg=(ROOT/'gmsv/lua/Modules/cg71JobSkills.lua').read_bytes().decode('gbk')
    # Prevent level-30 barrier coefficients becoming negative damage factors.
    cg=cg.replace("*(1-self:buff(b,q,'barrier')*0.05)","*(1-math.min(0.90,self:buff(b,q,'barrier')*0.05))")
    cg=cg.replace('专属制造及精品加工最高15级，进阶技能最高5级。','专属制造、精品加工及进阶技能最高30级。')
    cg=cg.replace('-- SetSkillExp uses the native experience tables and profession cap.','-- The library applies explicit level transitions using native thresholds.')
    cg=cg.replace("  if key=='nonlethal' then", "  local fp=Tech.GetData(Tech.GetTechIndex(get(p,'CHAR_BattleCom3')),CONST.TECH_FORCEPOINT)\n  if get(p,'CHAR_魔')<fp then return end\n  set(p,'CHAR_魔',get(p,'CHAR_魔')-fp);self:train(p,s.id,30);NLG.UpChar(p)\n  if key=='nonlethal' then")
    cg=cg.replace("  Char.SetSkillExp(p,slot,Char.GetSkillExp(p,slot)+xp,0)","  local library=getModule('skillLibrary')\n  if library then library:gainExperience(p,id,xp) else Char.SetSkillExp(p,slot,Char.GetSkillExp(p,slot)+xp,0) end")
    module_config=(ROOT/'gmsv/lua/ModuleConfig.lua').read_bytes()
    if b"loadModule('skillLibrary')" not in module_config:module_config+=b"\r\nloadModule('skillLibrary')\r\n"
    libdata={'skills':[{'id':d['id'],'name':d['name'],'cost':0 if d['id']==2105 else (1000 if 2100<=d['id']<=2104 else int(skills[d['id']][6] or 0)),'tech30':d['techs'][29],'techs':d['techs'],'xp_mode':'monster' if d.get('source_tech') else ('lua' if d['function']=='TECH_Lua' else 'native'),'behavior':'weaken' if d['id']==262 else None} for d in defs], 'mage_skills':sorted(mage),'monster_skills':[s['skill'] for s in source_mapping],'knight_extra':sorted(knight_extra),'active_slots':15,'maximum_level':30,'experience':{r[0]:r[1:-1] for r in ex}}
    libdata['passive_resistance']=[{'id':d['id'],'types':{key:int(value) for key,value in re.findall(r'(PO|SL|ST|YO|CN|AA):(-?\d+)',d.get('source_options',''))}} for d in defs if d.get('source_tech') and d['function']=='TECH_StatusResistance']
    for s,d in zip(libdata['skills'],defs):
        if d.get('behavior'):s['behavior']=d['behavior'];s['xp_mode']='lua';s['source_options']=d.get('source_options','')
    updates={'gmsv/data/skill.txt':b''.join(outskill),'gmsv/data/skilllv.txt':b''.join(outlimit),'gmsv/data/tech.txt':techbytes,'gmsv/data/skillexp.txt':b''.join(encoded(r) for r in ex),'gmsv/cgmsv.cf':cf,'gmsv/lua/ModuleConfig.lua':module_config,'gmsv/lua/Modules/cg71JobSkills.lua':cg.encode('gbk'),'gmsv/lua/Modules/cg71JobSkillsData.lua':('return '+lua(olddata)+'\n').encode('gbk'),'gmsv/lua/Modules/skillLibrary.lua':(HERE/'skillLibrary.lua').read_text(encoding='utf-8').encode('gbk'),'gmsv/lua/Modules/skillLibraryData.lua':('return '+lua(libdata)+'\n').encode('gbk')}
    m={'created_utc':datetime.now(timezone.utc).isoformat(),'player_skills':defs,'mage_skills':sorted(mage),'monster_sources':source_mapping,'knight_extra':sorted(knight_extra),'changed_limit_rows':changed,'new_techs':len(newtech),'active_slots':15,'maximum_level':30,'files':{},'policy':'all skill definitions + independent human copies of every pet/BOSS technique; original monster records preserved; original equipment/character requirements still apply'}
    for p,value in updates.items():
        old=(ROOT/p).read_bytes() if (ROOT/p).exists() else None
        dest=BATCH/'before'/p;dest.parent.mkdir(parents=True,exist_ok=True)
        if old is not None:
            if dest.exists():assert dest.read_bytes()==old,p
            else:dest.write_bytes(old)
        dest=STAGE/p;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(value)
        m['files'][p]={'before':digest(old) if old is not None else None,'after':digest(value),'size':len(value)}
    for p in [BATCH/'manifest.json',OUT/'manifest.json']:p.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'skills':len(defs),'new_techs':len(newtech),'changed_caps':changed,'mage_skills':len(mage)}))
def verify(root):
    m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'))
    extensions=[]
    for p,r in m['files'].items():
        actual=(root/p).read_bytes()
        if digest(actual)!=r['after']:
            assert root==ROOT and p=='gmsv/lua/ModuleConfig.lua',p
            expected=(STAGE/p).read_bytes();assert digest(expected)==r['after'],p
            extensions=loader_extensions(actual,expected);assert extensions is not None,p
            for name in extensions:assert (root/('gmsv/lua/Modules/'+name+'.lua')).exists(),name
    ts=rows((root/'gmsv/data/tech.txt').read_bytes());td={int(r[3]):r for r in ts}
    assert len(td)==len(ts),'duplicate Tech IDs'
    for d in m['player_skills']:
        assert len(d['techs'])==30
        for lv,tid in enumerate(d['techs'],1):assert int(td[tid][5])==d['id'] and int(td[tid][6])==lv
    caps={(int(r[1]),int(r[2])):int(r[3] or 0) for r in rows((root/'gmsv/data/skilllv.txt').read_bytes()) if r[1].isdigit() and r[2].isdigit()}
    for sid in m['mage_skills']:
        for jid in range(31,38):assert caps[sid,jid]==30
    for sid in m['knight_extra']:
        for jid in range(31,38):assert caps[sid,jid]==30
    original=Counter((BATCH/'before/gmsv/data/tech.txt').read_bytes().splitlines())
    current=Counter((root/'gmsv/data/tech.txt').read_bytes().splitlines())
    assert not (original-current),'Original technique records were altered/removed'
    for d in m['player_skills']:
        first=[int(r[3]) for r in ts if int(r[5])==d['id']][:30]
        assert set(first)==set(d['techs']),'Native player technique list would truncate '+str(d['id'])
    for r in rows((root/'gmsv/data/skillexp.txt').read_bytes()):
        v=[int(x) for x in r];assert len(v)==32 and all(x<y for x,y in zip(v[1:],v[2:]));assert v[-1]==2147483647
    result={'result':'PASS','root':str(root),'skills':len(m['player_skills']),'new_techs':m['new_techs'],'pack_sha256':fingerprint(m),'additional_modules':extensions,'additional_modules_native_verified':False if extensions else None,'installed_loader_sha256':digest((root/'gmsv/lua/ModuleConfig.lua').read_bytes())}
    (OUT/('installed_static.json' if root==ROOT else 'staged_static.json')).write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps(result))
def apply():
    m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'));proof=json.loads((OUT/'native_certification.json').read_text())
    assert proof['result']=='PASS' and proof['pack_sha256']==fingerprint(m),'Native proof stale/failed'
    assert proof['native_exe_sha256']==digest((ROOT/'gmsv/cgmsv.exe').read_bytes()),'Native executable changed'
    assert proof['disk_persistence']['result']=='PASS' and all(p['result']=='PASS' for p in proof['proofs'].values()),'Incomplete validation'
    for p,r in m['files'].items():
        assert (digest((ROOT/p).read_bytes()) if (ROOT/p).exists() else None) in [r['before'],r['after']],p
        assert digest((STAGE/p).read_bytes())==r['after'],p
    for p in m['files']:
        dest=ROOT/p;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes((STAGE/p).read_bytes())
    print('APPLIED '+str(len(m['files']))+' files; production restart pending')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['stage','verify','verify-installed','apply']);a=p.parse_args()
    {'stage':stage,'verify':lambda:verify(STAGE),'verify-installed':lambda:verify(ROOT),'apply':apply}[a.action]()
