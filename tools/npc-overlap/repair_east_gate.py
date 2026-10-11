"""Separate the two Falan NPCs at 278,82 using an isolated native server."""
from pathlib import Path
import json
import sys
import repair_sign_stone as common
import run_probe
from magic_tasks import lua

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE = ROOT / 'backups/npc_overlap_fix_20261010/east_gate'
STAGE = BASE / 'staged'
OUT = ROOT / 'docs/npc_overlap_fix/east_gate'
NPC = 'gmsv/data/npc.txt'
HOTFIX = 'gmsv/lua/npcOverlapFix.lua'
GUIDE = 'gmsv/lua/Modules/sharedTaskGuideData.lua'
CATALOG = 'docs/cg71_content_audit/shared_integration/task_guide_catalog.json'
NEW = [
    {'id':11110000,'name':'光之勇士','image':100450,'before':[278,82],
     'after':[276,82],'approach':[276,83]},
    {'id':10000299,'name':'法兰消息员','image':14041,'before':[218,83],
     'after':[218,85],'approach':[218,86]},
]


def prepare():
    common.RUN = BASE / 'native_runtime/gmsv'
    common.prepare_runtime()
    run_probe.RUN, run_probe.OUT = common.RUN, OUT


def scan():
    prepare()
    result = run_probe.run('east_gate_scan', config=(ROOT/'gmsv/lua/ModuleConfig.lua').read_bytes().decode('gbk')+'\n')
    assert result['status'] == 'PASS', result.get('error')
    result['npc_sha256'] = common.sha((ROOT/NPC).read_bytes())
    common.save(OUT/'scan.json', result)
    for t in result['tiles']:
        if t['objects'] or [t['x'],t['y']] in [p[k] for p in NEW for k in ('after','approach')]:
            print(json.dumps(t, ensure_ascii=False))


def stage():
    result = json.loads((OUT/'scan.json').read_text('utf-8'))
    original = (ROOT/NPC).read_bytes()
    assert result['npc_sha256'] == common.sha(original), 'Stale position scan'
    tiles = {(t['x'],t['y']): t for t in result['tiles']}
    for plan in NEW:
        for xy in (plan['after'],plan['approach']):
            t = tiles[tuple(xy)]
            assert t['walkable'] == 1 and t['image'] == 0 and not t['objects'], ('Unavailable tile',xy)
    rows, count = [], 0
    by_id = {str(p['id']).encode(): p for p in NEW}
    for line in original.splitlines(keepends=True):
        row = line.rstrip(b'\r\n').split(b'\t')
        if len(row)>=25 and row[3] in by_id and not row[0].startswith(b'#'):
            plan = by_id[row[3]]
            assert row[0] == b'Event' and row[1] == plan['name'].encode('gbk') and int(row[20]) == plan['image'] and row[8] == b'1000'
            for i in (9,11,13,15):
                assert [int(row[i]),int(row[i+1])] == plan['before']
                row[i:i+2] = [str(v).encode() for v in plan['after']]
            newline = line[len(line.rstrip(b'\r\n')):]
            line = b'\t'.join(row)+newline
            count += 1
        rows.append(line)
    assert count == len(NEW)
    plans = json.loads((HERE/'plans.json').read_text('utf-8'))
    assert not any(p['id'] in {n['id'] for n in NEW} for p in plans)
    plans.extend(NEW)
    guide = (ROOT/GUIDE).read_bytes()
    catalog_raw = (ROOT/CATALOG).read_bytes()
    catalog = json.loads(catalog_raw.decode('utf-8'))
    updated=[]
    for plan in NEW:
        before = dict(name=plan['name'],floor=1000,x=plan['before'][0],y=plan['before'][1])
        after = dict(before,x=plan['after'][0],y=plan['after'][1])
        matching = [t for t in catalog if t.get('entry') == before]
        assert guide.count(lua(before).encode('gbk')) == len(matching)
        guide=guide.replace(lua(before).encode('gbk'),lua(after).encode('gbk'))
        for task in matching:task['entry']=after;updated.append(task['name'])
    files = {NPC:b''.join(rows),HOTFIX:(HERE/'hotfix.lua').read_bytes().decode('utf-8').replace('__PLANS__',lua(plans)).encode('gbk'),
             'tools/npc-overlap/plans.json':(json.dumps(plans,ensure_ascii=False,indent=2)+'\n').encode('utf-8')}
    if updated:
        files[GUIDE] = guide
        newline='\r\n' if b'\r\n' in catalog_raw else '\n'
        files[CATALOG] = (json.dumps(catalog,ensure_ascii=False,indent=2)+'\n').replace('\n',newline).encode('utf-8')
    manifest={'new_plans':NEW,'plans':plans,'guide_entries_updated':updated,'files':{}}
    for rel,data in files.items():
        source=(ROOT/rel).read_bytes()
        backup=BASE/'original'/rel;backup.parent.mkdir(parents=True,exist_ok=True)
        if backup.exists():assert backup.read_bytes()==source
        else:backup.write_bytes(source)
        dest=STAGE/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
        manifest['files'][rel]={'before':common.sha(source),'after':common.sha(data)}
    common.save(OUT/'manifest.json',manifest)
    print(json.dumps({'staged':True,'guide_entries_updated':updated},ensure_ascii=False))


def probe(mode):
    prepare()
    manifest=json.loads((OUT/'manifest.json').read_text('utf-8'))
    files={rel.removeprefix('gmsv/'):(STAGE/rel).read_bytes() for rel in manifest['files'] if rel.startswith('gmsv/') and rel!=NPC}
    files['lua/east_gate_test_data.lua']=('return '+lua({'mode':mode,'new':NEW,'plans':manifest['plans']})).encode('gbk')
    source=BASE/'original'/NPC if mode=='hot' else STAGE/NPC
    result=run_probe.run('east_gate_verify',source,files,config=(ROOT/'gmsv/lua/ModuleConfig.lua').read_bytes().decode('gbk')+'\n')
    assert result['status']=='PASS',result.get('error')
    result['files']={rel:v['after'] for rel,v in manifest['files'].items()}
    common.save(OUT/(mode+'_test.json'),result)


def install():
    manifest=json.loads((OUT/'manifest.json').read_text('utf-8'))
    hashes={rel:v['after'] for rel,v in manifest['files'].items()}
    for mode in ('hot','restart'):
        result=json.loads((OUT/(mode+'_test.json')).read_text('utf-8'))
        assert result['status']=='PASS' and result['files']==hashes
    for rel,v in manifest['files'].items():
        assert common.sha((ROOT/rel).read_bytes())==v['before'], 'Concurrent edit: '+rel
        assert common.sha((STAGE/rel).read_bytes())==v['after']
    written=[]
    try:
        for rel in manifest['files']:
            written.append(rel);(ROOT/rel).write_bytes((STAGE/rel).read_bytes())
    except BaseException:
        for rel in written:(ROOT/rel).write_bytes((BASE/'original'/rel).read_bytes())
        raise
    manifest.update(installed=True,live_server_updated=False,activate_command='/dofile lua/npcOverlapFix.lua')
    common.save(OUT/'installed.json',manifest)
    print('PASS: installed; apply /dofile lua/npcOverlapFix.lua or restart normally.')


if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    action=sys.argv[1]
    if action=='all':scan();stage();probe('hot');probe('restart');install()
    elif action in ('hot','restart'):probe(action)
    else:globals()[action]()
