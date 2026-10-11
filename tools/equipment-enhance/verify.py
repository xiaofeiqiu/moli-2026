"""Run equipment probes against an isolated native server; never copy player stores."""
from pathlib import Path
import json, re, shutil, subprocess, sys, time
ROOT = Path(__file__).resolve().parents[2]
RUN = ROOT / 'backups/equipment_enhance_validation/gmsv'
OUT = ROOT / 'docs/equipment_enhance/result.json'
def main():
    probe = sys.argv[1] if len(sys.argv)>1 else 'native_probe.lua'
    source=ROOT/'tools/equipment-enhance/equipmentEnhance.lua'
    runtime=ROOT/'gmsv/lua/Modules/equipmentEnhance.lua'
    if probe!='explore.lua':
        for name in ('equipmentEnhance','equipmentEnhanceData'):
            source=ROOT/f'tools/equipment-enhance/{name}.lua'
            runtime=ROOT/f'gmsv/lua/Modules/{name}.lua'
            assert source.read_bytes().decode('utf-8')==runtime.read_bytes().decode('gbk'),'UTF-8/GBK mismatch: '+name
        # The bundled engine implements item extension persistence during normal saves.
        engine=(ROOT/'gmsv/cgmsv.exe').read_bytes()
        for statement in (
            b'insert into hook_itemExt (cdKey, regNo, slot, sKey, val, valType) values (?,?,?,?,?,?)',
            b'select slot, sKey, val, valType from hook_itemExt where cdKey = ? and regNo = ?',
        ):
            assert statement in engine, 'Engine missing native item extension persistence'
    RUN.mkdir(parents=True, exist_ok=True)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    for name in ('cgmsv.exe', 'setup.cf', 'cgmsv.cf'):
        shutil.copy2(ROOT/'gmsv'/name, RUN/name)
    for name in ('lua','data'):
        shutil.copytree(ROOT/'gmsv'/name, RUN/name, dirs_exist_ok=True)
    for name in ('store/itemcount','log','Dengon','GMLog','dump','house'):
        (RUN/name).mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT/'gmsv/log/log.cf',RUN/'log/log.cf')
    setup=(RUN/'setup.cf').read_bytes()
    for key,value in [('port',19063),('dummynum',100),('dbengine',1)]:
        setup=re.sub(rb'(?m)^'+key.encode()+rb'=\d+',f'{key}={value}'.encode(),setup)
    (RUN/'setup.cf').write_bytes(setup)
    modules="loadModule('gameQoL')\nloadModule('equipmentEnhance')\n" if probe!='explore.lua' else ''
    (RUN/'lua/ModuleConfig.lua').write_bytes(("moduleInitial()\n"+modules+"dofile('lua/enhance_probe.lua')\n").encode('gbk'))
    source=(ROOT/'tools/equipment-enhance'/probe).read_text('utf-8')
    (RUN/'lua/enhance_probe.lua').write_bytes(source.replace('__OUTPUT__',OUT.as_posix()).encode('gbk'))
    OUT.unlink(missing_ok=True)
    with (OUT.parent/'native.log').open('wb') as log:
        process=subprocess.Popen([str(RUN/'cgmsv.exe')],cwd=RUN,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline=time.monotonic()+100
            while time.monotonic()<deadline and process.poll() is None:
                if OUT.exists():
                    try: result=json.loads(OUT.read_bytes().decode('gbk'))
                    except (ValueError,UnicodeDecodeError): time.sleep(.25);continue
                    OUT.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n','utf-8')
                    print(json.dumps(result,ensure_ascii=False))
                    assert not result.get('error'),result.get('error')
                    return
                time.sleep(.25)
            raise RuntimeError('Probe did not finish; inspect docs/equipment_enhance/native.log')
        finally:
            if process.poll() is None: process.terminate()
            process.wait(timeout=10)
if __name__=='__main__': main()
