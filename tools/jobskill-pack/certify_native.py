"""Bind isolated native test results to the exact staged configuration bytes."""
import json
from datetime import datetime, timezone
from build_pack import ROOT, BATCH, OUT, STAGE, digest, pack_digest

m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'))
runtime=BATCH/'native_runtime'
tested={}
for path,row in m['files'].items():
    assert digest((STAGE/path).read_bytes())==row['after'],path
    if path=='gmsv/lua/ModuleConfig.lua':
        assert (runtime/path).read_bytes().count(b"loadModule('cg71JobSkills')")==1
        continue
    assert digest((runtime/path).read_bytes())==row['after'],'Native runtime mismatch: '+path
    tested[path]=row['after']
for source in ['native_probe.lua','native_battle_probe.lua']:
    expected=(ROOT/'tools/jobskill-pack'/source).read_text(encoding='utf-8').encode('gbk')
    assert (runtime/'gmsv/lua'/source).read_bytes()==expected,'Probe mismatch: '+source
    assert (OUT/('native_battle_result.json' if 'battle' in source else 'native_result.json')).stat().st_mtime >= (runtime/'gmsv/lua'/source).stat().st_mtime
results={name:json.loads((OUT/name).read_text(encoding='utf-8')) for name in ['staged_static.json','native_result.json','native_battle_result.json']}
assert all(r['result']=='PASS' for r in results.values()),'All validations must pass'
result={'result':'PASS','verified_utc':datetime.now(timezone.utc).isoformat(),'pack_sha256':pack_digest(m),'tested_files':tested,'module_config':'isolated loader; same content module, test probes, no production HTTP/account modules','native_checks':results['native_result.json']['counts']['checks'],'actual_battle_callback_calls':results['native_battle_result.json']['native_callback_calls'],'client_verified':False}
(OUT/'native_certification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='tested_files'},ensure_ascii=False))
