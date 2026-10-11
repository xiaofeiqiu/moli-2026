"""Stage, natively verify, then install the sign/stone and magic job repairs."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import sqlite3
import sys
import audit_current
import magic_tasks
import run_probe

sys.stdout.reconfigure(encoding='utf-8')
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE = ROOT / 'backups/npc_overlap_fix_20261004/revision3'
STAGE = BASE / 'staged'
OUT = ROOT / 'docs/npc_overlap_fix/revision3'
RUN = BASE / 'native_runtime/gmsv'
PLANS = json.loads((HERE / 'plans.json').read_text('utf-8'))
NEW = [p for p in PLANS if p['id'] in (71000,1051534,888888)]
NPC = 'gmsv/data/npc.txt'
GUIDE = 'gmsv/lua/Modules/sharedTaskGuideData.lua'
CATALOG = 'docs/cg71_content_audit/shared_integration/task_guide_catalog.json'
HOTFIX = 'gmsv/lua/npcOverlapFix.lua'


def sha(data): return hashlib.sha256(data).hexdigest()


def save(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n','utf-8')


def prepare_runtime():
    RUN.mkdir(parents=True,exist_ok=True)
    for rel in ('cgmsv.exe','setup.cf','cgmsv.cf','log/log.cf'):
        dest=RUN/rel;dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/'gmsv'/rel,dest)
    for rel in ('lua','data'):
        shutil.copytree(ROOT/'gmsv'/rel,RUN/rel,dirs_exist_ok=True,copy_function=audit_current.copy_changed)
    for rel in ('store/itemcount','store/dungeon','store/house','log','Dengon','GMLog','dump','house'):
        (RUN/rel).mkdir(parents=True,exist_ok=True)
    setup=(RUN/'setup.cf').read_bytes()
    for key,value in (('port',19074),('dbengine',1),('dummynum',100)):
        setup=re.sub(rb'(?m)^'+key.encode()+rb'=\d+',f'{key}={value}'.encode(),setup)
    (RUN/'setup.cf').write_bytes(setup)
    http=RUN/'lua/Modules/http.lua'
    http.write_bytes(http.read_bytes().replace(b'Http.Start("0.0.0.0", 10086)',b'Http.Start("127.0.0.1", 19174)'))
    if not (RUN/'data.db3').exists():
        with sqlite3.connect(RUN/'data.db3') as db:
            db.executescript((ROOT/'gmsv/sql/sqlite.sql').read_text('utf-8'))


def scan():
    # Use a dedicated runtime and schema-only database, separate from other audits.
    prepare_runtime()
    run_probe.RUN,run_probe.OUT = RUN,OUT
    r=run_probe.run('sign_stone_scan',config=(ROOT/'gmsv/lua/ModuleConfig.lua').read_bytes().decode('gbk')+'\n')
    assert r['status']=='PASS',r.get('error')
    r['npc_sha256']=sha((ROOT/NPC).read_bytes())
    save(OUT/'sign_stone_scan.json',r)


def stage():
    assert not (OUT/'installed.json').exists(),'Revision three already installed'
    scan=json.loads((OUT/'sign_stone_scan.json').read_text('utf-8'))
    assert scan['status']=='PASS' and scan['npc_sha256']==sha((ROOT/NPC).read_bytes()),'Stale position scan'
    tiles={(t['x'],t['y']):t for t in scan['tiles']}
    for p in NEW:
        for pos in (p['after'],p['approach']):
            t=tiles[tuple(pos)]
            assert t['walkable']==1 and not t['objects'] and t['image']==0,'Unavailable position: '+str(pos)
    files,job_report=magic_tasks.compile_tasks()
    rows=[];used=set();plans={p['id']:p for p in PLANS}
    original_npc=(ROOT/NPC).read_bytes()
    for line in original_npc.splitlines(keepends=True):
        row=line.rstrip(b'\r\n').split(b'\t')
        if len(row)>=25 and row[3].isdigit() and int(row[3]) in plans and not row[0].startswith(b'#'):
            p=plans[int(row[3])]
            assert row[1]==p['name'].encode('gbk') and int(row[20])==p['image'] and row[8]==b'1000'
            for i in (9,11,13,15):
                assert [int(row[i]),int(row[i+1])] in (p['before'],p['after'])
                row[i:i+2]=[str(x).encode() for x in p['after']]
            newline=line[len(line.rstrip(b'\r\n')):]
            line=b'\t'.join(row)+newline;used.add(p['id'])
        rows.append(line)
    assert used==set(plans),'Missing NPC identities'
    files[NPC]=b''.join(rows)
    guide=(ROOT/GUIDE).read_bytes()
    catalog_bytes=(ROOT/CATALOG).read_bytes()
    catalog=json.loads(catalog_bytes.decode('utf-8'))
    updated=[]
    for p in NEW:
        before=dict(name=p['name'],floor=1000,x=p['before'][0],y=p['before'][1])
        after=dict(before,x=p['after'][0],y=p['after'][1])
        matching=[t for t in catalog if t['entry']==before]
        assert guide.count(magic_tasks.lua(before).encode('gbk'))==len(matching)
        guide=guide.replace(magic_tasks.lua(before).encode('gbk'),magic_tasks.lua(after).encode('gbk'))
        for t in matching:t['entry']=after;updated.append(t['name'])
    files[GUIDE]=guide
    newline='\r\n' if b'\r\n' in catalog_bytes else '\n'
    files[CATALOG]=(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n').replace('\n',newline).encode('utf-8')
    template=(HERE/'hotfix.lua').read_bytes().decode('utf-8')
    files[HOTFIX]=template.replace('__PLANS__',magic_tasks.lua(PLANS)).encode('gbk')
    manifest={'plans':PLANS,'new_plans':NEW,'guide_entries_updated':updated,'files':{},'job_audit':job_report}
    for rel,data in files.items():
        path=ROOT/rel;original=path.read_bytes() if path.exists() else None
        backup=BASE/'original'/rel
        if original is not None:
            backup.parent.mkdir(parents=True,exist_ok=True)
            if backup.exists():assert backup.read_bytes()==original,'Concurrent edit: '+rel
            else:backup.write_bytes(original)
        dest=STAGE/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
        manifest['files'][rel]={'before':sha(original) if original is not None else None,'after':sha(data)}
    (BASE/'hot_test_npc.txt').write_bytes(original_npc)
    save(OUT/'manifest.json',manifest)
    save(OUT/'magic_job_audit.json',job_report)
    print(json.dumps({'staged':len(files),'moved_NPCs':len(NEW),'task_script_files':job_report['changed_script_files'],
                      'task_predicates':job_report['changed_runs'],'shared_ranges':job_report['shared_ranges_extended']}))


def probe(kind):
    manifest=json.loads((OUT/'manifest.json').read_text('utf-8'))
    files={rel.removeprefix('gmsv/'):(STAGE/rel).read_bytes() for rel in manifest['files'] if rel.startswith('gmsv/') and rel!=NPC}
    cases=manifest['job_audit']['cases']
    files['lua/sign_stone_test_data.lua']=('return '+magic_tasks.lua(dict(
        plans=PLANS,new=NEW,guide_tasks=manifest['guide_entries_updated'],cases=cases,
        mode=kind,expected_moves=3 if kind=='hot' else 0))).encode('gbk')
    jobs=[]
    for l in (ROOT/'gmsv/data/jobs.txt').read_bytes().splitlines():
        cols=l.split(b'\t')
        if len(cols)>2 and cols[2].isdigit() and not l.startswith(b'#'):jobs.append(int(cols[2]))
    files['lua/sign_stone_test_jobs.lua']=('return '+magic_tasks.lua(sorted(set(jobs)))).encode()
    run_probe.RUN,run_probe.OUT=RUN,OUT
    source=BASE/'hot_test_npc.txt' if kind=='hot' else STAGE/NPC
    result=run_probe.run('sign_stone_verify',source,files,config=(ROOT/'gmsv/lua/ModuleConfig.lua').read_bytes().decode('gbk')+'\n')
    assert result['status']=='PASS',result.get('error')
    result['files']={rel:r['after'] for rel,r in manifest['files'].items()}
    save(OUT/(kind+'_test.json'),result)


def install():
    manifest=json.loads((OUT/'manifest.json').read_text('utf-8'))
    expected={rel:r['after'] for rel,r in manifest['files'].items()}
    for kind in ('hot','restart'):
        r=json.loads((OUT/(kind+'_test.json')).read_text('utf-8'))
        assert r['status']=='PASS' and r['files']==expected,'Missing native validation: '+kind
    for rel,r in manifest['files'].items():
        p=ROOT/rel
        assert (sha(p.read_bytes()) if p.exists() else None)==r['before'],'Concurrent edit: '+rel
        assert sha((STAGE/rel).read_bytes())==r['after'],'Staged content changed: '+rel
    written=[]
    try:
        for rel in manifest['files']:
            p=ROOT/rel;p.parent.mkdir(parents=True,exist_ok=True)
            written.append(rel);p.write_bytes((STAGE/rel).read_bytes())
    except BaseException:
        for rel in reversed(written):
            backup=BASE/'original'/rel
            if backup.exists():(ROOT/rel).write_bytes(backup.read_bytes())
            else:(ROOT/rel).unlink(missing_ok=True)
        raise
    manifest.update(installed=True,live_server_updated=False,client_verified=False,
                    activate_command='/dofile lua/npcOverlapFix.lua',backup=str(BASE/'original'))
    save(OUT/'installed.json',manifest)
    print(json.dumps({'installed':True,'files':len(written),'live_server_updated':False}))


if __name__=='__main__':
    action=sys.argv[1]
    if action=='all':scan();stage();probe('hot');probe('restart');install()
    elif action in ('hot','restart'):probe(action)
    else:globals()[action]()
