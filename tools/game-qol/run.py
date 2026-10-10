"""Stage and verify quality-of-life commands in an isolated native server."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, subprocess, time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE = ROOT / 'backups/game_qol_20261004'
RUN = BASE / 'native_runtime/gmsv'
STAGE = BASE / 'staged/gmsv'
OUT = ROOT / 'docs/game_qol'

def prepare(probe):
    OUT.mkdir(parents=True, exist_ok=True)
    RUN.mkdir(parents=True, exist_ok=True)
    for name in ('cgmsv.exe', 'setup.cf', 'cgmsv.cf'):
        shutil.copy2(ROOT/'gmsv'/name, RUN/name)
    for name in ('lua', 'data'):
        shutil.copytree(ROOT/'gmsv'/name, RUN/name, dirs_exist_ok=True)
    for name in ('store/itemcount','log','Dengon','GMLog','dump','house'):
        (RUN/name).mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT/'gmsv/log/log.cf', RUN/'log/log.cf')
    setup = (RUN/'setup.cf').read_bytes()
    for key,value in [('port',19053),('dbengine',1),('dummynum',100)]:
        setup = re.sub(rb'(?m)^'+key.encode()+rb'=\d+',f'{key}={value}'.encode(),setup)
    (RUN/'setup.cf').write_bytes(setup)
    cf = (RUN/'cgmsv.cf').read_bytes()
    cf = re.sub(rb'(?m)^extbagpage=\d+', b'extbagpage=3', cf)
    cf = re.sub(rb'(?m)^defaultbagsize=\d+', b'defaultbagsize=88', cf)
    (RUN/'cgmsv.cf').write_bytes(cf)
    if probe != 'explore':
        shutil.copytree(STAGE, RUN, dirs_exist_ok=True)
    source = (HERE/(probe+'.lua')).read_text('utf-8').replace('__OUTPUT__',OUT.as_posix())
    (RUN/'lua/qol_probe.lua').write_bytes(source.encode('gbk'))
    config = "moduleInitial()\n"
    if probe != 'explore':
        config += "loadModule('cg71JobSkills')\nloadModule('skillLibrary')\nloadModule('fivePet')\nloadModule('fight')\nloadModule('knightHybridGear')\nloadModule('gameQoL')\n"
    (RUN/'lua/ModuleConfig.lua').write_bytes((config+"dofile('lua/qol_probe.lua')\n").encode('ascii'))

def run(probe):
    result=OUT/(probe+'_result.json')
    if result.exists(): result.unlink()
    with (OUT/(probe+'_stdout.log')).open('wb') as log:
        p = subprocess.Popen([str(RUN/'cgmsv.exe')],cwd=RUN,stdout=log,stderr=subprocess.STDOUT,
                             creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline=time.monotonic()+100
            while time.monotonic()<deadline and not result.exists() and p.poll() is None:
                time.sleep(.25)
            if not result.exists():
                raise RuntimeError(f'No probe report; process exit={p.poll()}; inspect {log.name}')
            raw=result.read_bytes()
            try: report=json.loads(raw.decode('utf-8'))
            except UnicodeDecodeError: report=json.loads(raw.decode('gbk'))
            result.write_text(json.dumps(report,ensure_ascii=False,indent=2),'utf-8')
            print(json.dumps(report if probe=='explore' else {'status':report['status'],'checks':len(report.get('checks',[])),'error':report.get('error'),'report':str(result)},ensure_ascii=False))
        finally:
            if p.poll() is None: p.terminate()
            p.wait(timeout=10)

def stage():
    OUT.mkdir(parents=True,exist_ok=True)
    originals=BASE/'original/gmsv'
    paths=('cgmsv.cf','data/itemset.txt','lua/ModuleConfig.lua','lua/Modules/gameQoL.lua','lua/Modules/gameQoLData.lua')
    for rel in paths:
        src=ROOT/'gmsv'/rel;dest=originals/rel
        if src.exists() and not dest.exists():
            dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
    stack_ids=[];stone_ids=[];changes=[];output=[]
    consumables={23,29,30,31,32,33,34,35,36,37,39,40,42,43}
    raw=(ROOT/'gmsv/data/itemset.txt').read_bytes()
    for line in raw.splitlines(keepends=True):
        newline=b'\r\n' if line.endswith(b'\r\n') else b'\n' if line.endswith(b'\n') else b''
        row=line.rstrip(b'\r\n').split(b'\t')
        if len(row)==102 and not line.lstrip().startswith((b'#',b'//')):
            item_id=int(row[11]);typ=int(row[14] or b'0');old=int(row[22] or b'1')
            stone=row[0]=='魔石'.encode('gbk') and row[1]=='魔石'.encode('gbk')
            if stone:stone_ids.append(item_id)
            # Retain equipment, furniture, unique scripted quest objects.
            ordinary=typ in consumables and not any(row[2:11]) and int(row[16] or b'0')==0
            if typ>=23 and typ<55 and (old>1 or ordinary or stone):
                stack_ids.append(item_id)
                if old<999:
                    row[22]=b'999';changes.append({'id':item_id,'before':old,'after':999,'type':typ})
                    line=b'\t'.join(row)+newline
        output.append(line)
    itemset=b''.join(output)
    cf=(ROOT/'gmsv/cgmsv.cf').read_bytes()
    cf=re.sub(rb'(?m)^extbagpage=\d+',b'extbagpage=3',cf)
    cf=re.sub(rb'(?m)^defaultbagsize=\d+',b'defaultbagsize=88',cf)
    limit=re.search(rb'(?m)^maxgoldhave=(\d+)',cf);assert limit
    data='return {stackLimit=999,goldLimit='+str(int(limit[1])*10000)+',stackIds={'
    data+=','.join(f'[{i}]=true' for i in stack_ids)+'},stoneIds={'
    data+=','.join(f'[{i}]=true' for i in stone_ids)+'}}\n'
    config=(ROOT/'gmsv/lua/ModuleConfig.lua').read_bytes()
    if not re.search(rb"(?m)^\s*loadModule\(['\"]gameQoL['\"]",config):
        config=config.rstrip()+b"\r\n\r\nloadModule('gameQoL')\r\n"
    files={'data/itemset.txt':itemset,'cgmsv.cf':cf,'lua/ModuleConfig.lua':config,
           'lua/Modules/gameQoL.lua':(HERE/'gameQoL.lua').read_text('utf-8').encode('gbk'),
           'lua/Modules/gameQoLData.lua':data.encode('ascii')}
    manifest={'stack_limit':999,'stack_definitions':len(stack_ids),'changed':changes,
              'stone_ids':stone_ids,'pages':4,'gold_limit':int(limit[1])*10000,'files':{}}
    for rel,content in files.items():
        src=ROOT/'gmsv'/rel;dest=STAGE/rel;dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(content)
        manifest['files'][rel]={'before':hashlib.sha256(src.read_bytes()).hexdigest() if src.exists() else None,
                                'after':hashlib.sha256(content).hexdigest()}
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),'utf-8')
    print(json.dumps({'staged':True,'stacks':len(stack_ids),'changes':len(changes),'stones':stone_ids}))

def install():
    report=json.loads((OUT/'test_result.json').read_text('utf-8'))
    assert report['status']=='PASS' and all(c['pass'] for c in report['checks'])
    for probe in ('restart','battle'):
        other=json.loads((OUT/(probe+'_result.json')).read_text('utf-8'))
        assert other['status']=='PASS' and all(c['pass'] for c in other['checks']),probe
    manifest=json.loads((OUT/'manifest.json').read_text('utf-8'))
    for rel,hashes in manifest['files'].items():
        src=ROOT/'gmsv'/rel
        assert (hashlib.sha256(src.read_bytes()).hexdigest() if src.exists() else None)==hashes['before'],'Concurrent change '+rel
        assert hashlib.sha256((STAGE/rel).read_bytes()).hexdigest()==hashes['after'],'Staging mismatch '+rel
        if rel!='lua/ModuleConfig.lua':
            assert hashlib.sha256((RUN/rel).read_bytes()).hexdigest()==hashes['after'],'Untested runtime '+rel
    assert hashlib.sha256((RUN/'cgmsv.exe').read_bytes()).digest()==hashlib.sha256((ROOT/'gmsv/cgmsv.exe').read_bytes()).digest()
    for rel in manifest['files']:
        dest=ROOT/'gmsv'/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(STAGE/rel,dest)
    manifest.update(installed=True,native_checks=len(report['checks']),requires_restart=True,
                    client_verified=False,backup=str(BASE/'original'),database_modified=False)
    (OUT/'installed.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),'utf-8')
    print(json.dumps({'installed':True,'checks':len(report['checks']),'requires_restart':True,'backup':str(BASE/'original')}))

if __name__ == '__main__':
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['explore','test','restart','battle','stage','install'])
    args=ap.parse_args()
    if args.action=='stage':stage()
    elif args.action=='install':install()
    else:prepare(args.action);run(args.action)
