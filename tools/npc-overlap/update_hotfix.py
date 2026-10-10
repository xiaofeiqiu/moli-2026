"""Repair the live-script occupancy guard, retaining revision-one evidence."""
import json
import sys
import build
import run_probe

OLD_BASE=build.BASE
BASE=OLD_BASE/'revision2'
OUT=build.OUT/'revision2'
STAGE=BASE/'staged'
build.BASE=BASE
build.OUT=OUT
build.STAGE=STAGE
run_probe.OUT=OUT
build.PLANS=build.PLANS+[
    {'id':10000554,'name':'邱家庄小维','image':14147,'before':[223,83],'after':[223,84]},
    {'id':10002660,'name':'古怪的老头','image':14029,'before':[223,83],'after':[221,85]},
    {'id':15383,'name':'新年特使','image':260023,'before':[235,116],'after':[237,116],'approach':[237,115]},
]

def stage():
    assert not (OUT/'installed.json').exists(),'Revision two already installed'
    prior=json.loads((OUT.parent/'installed.json').read_text('utf-8'))
    files={rel:(build.ROOT/rel).read_bytes() for rel in prior['files']}
    evidence=json.loads((OUT.parent/'scan.json').read_text('utf-8'))
    assert evidence['status']=='PASS'
    tiles={(t['x'],t['y']):t for t in evidence['tiles']}
    for p in build.PLANS:
        tile=tiles[tuple(p['after'])]
        assert tile['walkable']==1
        assert all(o['name']==p['name'] and o['image']==p['image'] for o in tile['objects'])
        approach=p.get('approach',[p['after'][0],p['after'][1]+1])
        tile=tiles[tuple(approach)]
        assert tile['walkable']==1 and not tile['objects']
    by_id={p['id']:p for p in build.PLANS}
    rows=[];used=set()
    for line in files[build.NPC].splitlines(keepends=True):
        row=line.rstrip(b'\r\n').split(b'\t')
        if len(row)>=25 and row[3].isdigit() and int(row[3]) in by_id:
            p=by_id[int(row[3])]
            assert row[1]==p['name'].encode('gbk') and int(row[20])==p['image'] and row[8]==b'1000'
            for index in [9,11,13,15]:
                assert [int(row[index]),int(row[index+1])] in [p['before'],p['after']]
                row[index],row[index+1]=[str(v).encode() for v in p['after']]
            newline=b'\r\n' if line.endswith(b'\r\n') else b'\n' if line.endswith(b'\n') else b''
            line=b'\t'.join(row)+newline;used.add(p['id'])
        rows.append(line)
    assert used==set(by_id)
    files[build.NPC]=b''.join(rows)
    guide=files[build.GUIDE]
    tasks=json.loads(files[build.CATALOG].decode('utf-8'))
    changed=list(prior['guide_entries_updated'])
    for p in build.PLANS:
        before={'name':p['name'],'floor':1000,'x':p['before'][0],'y':p['before'][1]}
        after=dict(before,x=p['after'][0],y=p['after'][1])
        matching=[t for t in tasks if t['entry']==before]
        assert guide.count(build.lua(before).encode('gbk'))==len(matching)
        guide=guide.replace(build.lua(before).encode('gbk'),build.lua(after).encode('gbk'))
        for t in matching:t['entry']=after;changed.append(t['name'])
    files[build.GUIDE]=guide
    files[build.CATALOG]=(json.dumps(tasks,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    files[build.HOTFIX]=(build.HERE/'hotfix.lua').read_text('utf-8').replace('__PLANS__',build.lua(build.PLANS)).encode('gbk')
    manifest={'plans':build.PLANS,'guide_entries_updated':changed,
              'reason':'Repair temporary occupant check and separate NPCs at 223,83 and 235,116', 'files':{}}
    for rel,data in files.items():
        original=(build.ROOT/rel).read_bytes()
        assert build.sha(original)==prior['files'][rel]['after'],'Concurrent edit: '+rel
        backup=BASE/'original'/rel
        backup.parent.mkdir(parents=True,exist_ok=True)
        if backup.exists():assert backup.read_bytes()==original
        else:backup.write_bytes(original)
        target=STAGE/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
        manifest['files'][rel]={'before':build.sha(original),'after':build.sha(data)}
    (BASE/'hot_test_npc.txt').write_bytes((OLD_BASE/'original'/build.NPC).read_bytes())
    build.save(OUT/'manifest.json',manifest)
    print(json.dumps({'staged':True,'total_NPC_plans':len(build.PLANS),'additional_NPC_moves':3}))

if __name__=='__main__':
    action=sys.argv[1]
    if action=='stage':stage()
    elif action in ['hot_test','restart_test']:build.probe(action)
    elif action=='install':build.install()
    else:raise ValueError(action)
