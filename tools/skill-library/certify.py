"""Bind isolated native, real battle and cross-process storage checks to this pack."""
import json,sqlite3
from build import ROOT,BATCH,STAGE,OUT,digest,fingerprint,verify
verify(STAGE)
m=json.loads((BATCH/'manifest.json').read_text('utf-8'));fp=fingerprint(m)
proofs={}
for name in ['native_result','native_battle_result','native_restart_result']:
    value=json.loads((OUT/(name+'.json')).read_text('utf-8'))
    assert value['result']=='PASS' and value['pack_sha256']==fp,name+' stale/failed'
    proofs[name]=value
assert proofs['native_result']['counts']['skills']==len(m['player_skills'])
assert len(proofs['native_battle_result']['cases'])>=7
run=BATCH/'native_runtime/gmsv'
runtime_hashes={}
for path,row in m['files'].items():
    if path=='gmsv/lua/ModuleConfig.lua':continue
    actual=digest((run/path.removeprefix('gmsv/')).read_bytes())
    assert actual==row['after'],path
    runtime_hashes[path]=actual
exe_hash=digest((run/'cgmsv.exe').read_bytes())
assert exe_hash==digest((ROOT/'gmsv/cgmsv.exe').read_bytes())
db=sqlite3.connect('file:'+str((run/'data.db3').absolute().as_posix())+'?mode=ro',uri=True)
row=db.execute('SELECT val,valType FROM hook_charaext WHERE cdKey=? AND regNo=0 AND sKey=?',('LIBRARY_PERSIST_WITNESS','SkillLibraryV1')).fetchone()
assert row and row[1]==0
b=json.loads(row[0]);assert b['pack_sha256']==fp and len(b['skills'])==559
assert b['skills']['19']['level']==17 and b['skills']['19']['exp']==123
assert b['skills']['2204']['level']==30 and len(b['profiles']['SPELLS'])==15
db.close()
cert={'result':'PASS','pack_sha256':fp,'native_exe_sha256':exe_hash,'runtime_hashes':runtime_hashes,'proofs':proofs,'disk_persistence':{'result':'PASS','archive_skills':559,'profile_slots':15},'client_verified':False,'production_restart_pending':True}
(OUT/'native_certification.json').write_text(json.dumps(cert,ensure_ascii=False,indent=2)+'\n','utf-8')
print(json.dumps({'result':'PASS','skills':len(m['player_skills']),'native_checks':proofs['native_result']['checks'],'actual_battles':len(proofs['native_battle_result']['cases']),'disk_archive':559}))
