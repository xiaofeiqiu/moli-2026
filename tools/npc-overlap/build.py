"""Stage, verify, and install the five reported Falan NPC overlap repairs."""
from pathlib import Path
import hashlib
import json
import sys
from run_probe import ROOT, HERE, OUT, run

BASE = ROOT / 'backups/npc_overlap_fix_20261004'
STAGE = BASE / 'staged'
PLANS = [
    {'id':10001965,'name':'佣兵升级卡','image':14156,'before':[229,83],'after':[225,85]},
    {'id':10003359,'name':'爱说话的汉克','image':14546,'before':[229,83],'after':[227,85]},
    {'id':90000,'name':'法兰消息员','image':231105,'before':[229,83],'after':[229,85]},
    {'id':10003399,'name':'强化系统','image':14206,'before':[233,83],'after':[231,85]},
    {'id':9000018,'name':'流星会员之家','image':106479,'before':[234,83],'after':[233,85]},
]
NPC = 'gmsv/data/npc.txt'
GUIDE = 'gmsv/lua/Modules/sharedTaskGuideData.lua'
CATALOG = 'docs/cg71_content_audit/shared_integration/task_guide_catalog.json'
HOTFIX = 'gmsv/lua/npcOverlapFix.lua'

def sha(data):
    return hashlib.sha256(data).hexdigest()

def lua(value):
    if value is None:return 'nil'
    if isinstance(value,str):return json.dumps(value,ensure_ascii=False)
    if isinstance(value,int):return str(value)
    if isinstance(value,list):return '{'+','.join(lua(v) for v in value)+'}'
    return '{'+','.join('['+lua(k)+']='+lua(v) for k,v in value.items())+'}'

def save(path, data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n','utf-8')

def stage():
    assert not (OUT/'installed.json').exists(),'Repair already installed'
    evidence=json.loads((OUT/'scan.json').read_text('utf-8'))
    assert evidence['status']=='PASS'
    tiles={(t['x'],t['y']):t for t in evidence['tiles']}
    for p in PLANS:
        for pos in [p['after'],[p['after'][0],p['after'][1]+1]]:
            tile=tiles[tuple(pos)]
            assert tile['walkable']==1 and not tile['objects'],f'Unavailable tile: {pos}'
    old=(ROOT/NPC).read_bytes()
    output=[];used=set()
    by_id={p['id']:p for p in PLANS}
    for line in old.splitlines(keepends=True):
        row=line.rstrip(b'\r\n').split(b'\t')
        if len(row)>=25 and row[3].isdigit() and int(row[3]) in by_id:
            p=by_id[int(row[3])]
            assert row[1]==p['name'].encode('gbk') and int(row[20])==p['image'] and row[8]==b'1000'
            for index in [9,11,13,15]:
                assert [int(row[index]),int(row[index+1])]==p['before']
                row[index],row[index+1]=[str(v).encode() for v in p['after']]
            newline=b'\r\n' if line.endswith(b'\r\n') else b'\n' if line.endswith(b'\n') else b''
            line=b'\t'.join(row)+newline;used.add(p['id'])
        output.append(line)
    assert used==set(by_id)
    guide=(ROOT/GUIDE).read_bytes()
    tasks=json.loads((ROOT/CATALOG).read_text('utf-8'))
    changed=[]
    for p in PLANS:
        before={'name':p['name'],'floor':1000,'x':p['before'][0],'y':p['before'][1]}
        after=dict(before,x=p['after'][0],y=p['after'][1])
        count=guide.count(lua(before).encode('gbk'))
        matching=[t for t in tasks if t['entry']==before]
        assert count==len(matching)
        guide=guide.replace(lua(before).encode('gbk'),lua(after).encode('gbk'))
        for t in matching:t['entry']=after;changed.append(t['name'])
    files={NPC:b''.join(output),GUIDE:guide,
           CATALOG:(json.dumps(tasks,ensure_ascii=False,indent=2)+'\n').encode('utf-8'),
           HOTFIX:(HERE/'hotfix.lua').read_text('utf-8').replace('__PLANS__',lua(PLANS)).encode('gbk')}
    manifest={'plans':PLANS,'guide_entries_updated':changed,'files':{}}
    for rel,data in files.items():
        src=ROOT/rel;original=src.read_bytes() if src.exists() else None
        if original is not None:
            backup=BASE/'original'/rel;backup.parent.mkdir(parents=True,exist_ok=True)
            if backup.exists():assert backup.read_bytes()==original,'Backup does not match current source'
            else:backup.write_bytes(original)
        target=STAGE/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
        manifest['files'][rel]={'before':sha(original) if original is not None else None,'after':sha(data)}
    save(OUT/'manifest.json',manifest)
    save(HERE/'plans.json',PLANS)
    print(json.dumps({'staged':True,'NPCs_moved':len(PLANS),'guide_entries_updated':len(changed)},ensure_ascii=False))

def probe(name):
    m=json.loads((OUT/'manifest.json').read_text('utf-8'))
    files={
        'lua/npcOverlapFix.lua':(STAGE/HOTFIX).read_bytes(),
        'lua/Modules/sharedTaskGuideData.lua':(STAGE/GUIDE).read_bytes(),
        'lua/Modules/sharedTaskGuide.lua':(ROOT/'gmsv/lua/Modules/sharedTaskGuide.lua').read_bytes(),
        'lua/npc_overlap_plans.lua':('return '+lua(PLANS)).encode('gbk'),
        'lua/npc_overlap_verify.lua':(HERE/'verify.lua').read_text('utf-8').encode('gbk'),
        'lua/npc_overlap_guide_tasks.lua':('return '+lua(m['guide_entries_updated'])).encode('gbk'),
    }
    old_test_source=BASE/'hot_test_npc.txt'
    source=(old_test_source if old_test_source.exists() else ROOT/NPC) if name=='hot_test' else STAGE/NPC
    report=run(name,source,files,config="moduleInitial()\nloadModule('sharedTaskGuide')\n")
    assert report['status']=='PASS',report.get('error')
    report['files']={rel:r['after'] for rel,r in m['files'].items()}
    save(OUT/(name+'.json'),report)

def install():
    m=json.loads((OUT/'manifest.json').read_text('utf-8'))
    expected={rel:r['after'] for rel,r in m['files'].items()}
    for name in ['hot_test','restart_test']:
        report=json.loads((OUT/(name+'.json')).read_text('utf-8'))
        assert report['status']=='PASS' and report['files']==expected,'Missing or stale native verification'
    for rel,r in m['files'].items():
        dest=ROOT/rel
        assert (sha(dest.read_bytes()) if dest.exists() else None)==r['before'],'Concurrent edit: '+rel
        assert sha((STAGE/rel).read_bytes())==r['after'],'Staged content changed: '+rel
    written=[]
    try:
        for rel in m['files']:
            dest=ROOT/rel;dest.parent.mkdir(parents=True,exist_ok=True)
            written.append(rel);dest.write_bytes((STAGE/rel).read_bytes())
    except BaseException:
        for rel in reversed(written):
            original=BASE/'original'/rel
            if original.exists():(ROOT/rel).write_bytes(original.read_bytes())
            else:(ROOT/rel).unlink(missing_ok=True)
        raise
    for rel,r in m['files'].items():assert sha((ROOT/rel).read_bytes())==r['after']
    m.update(installed=True,live_server_updated=False,client_verified=False,
             activate_command='/dofile lua/npcOverlapFix.lua',backup=str(BASE/'original'))
    save(OUT/'installed.json',m)
    print(json.dumps({'installed':True,'live_server_updated':False,'activate_command':m['activate_command']},ensure_ascii=False))

if __name__=='__main__':
    action=sys.argv[1]
    if action in ['hot_test','restart_test']:probe(action)
    else:globals()[action]()
