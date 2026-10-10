"""Run the remaining native probes sequentially and require fresh matching results."""
import json,subprocess,sys,time
from pathlib import Path
from validate_shared_tasks_native import OUT,ROOT,fingerprint
here=Path(__file__).parent
for script,report in [('probe_shared_adapters.py','native_adapters_result.json'),('probe_shared_services.py','native_services_result.json'),('probe_shared_access.py','native_access_result.json')]:
 target=OUT/report
 if target.exists():target.unlink()
 subprocess.run([sys.executable,'-X','utf8',str(here/script)],cwd=ROOT,check=True)
 deadline=time.monotonic()+120
 while time.monotonic()<deadline:
  try:r=json.loads(target.read_text(encoding='gbk'))
  except (FileNotFoundError,UnicodeDecodeError,json.JSONDecodeError):r={}
  if r.get('state') in {'PASS','FAIL'}:
   assert r.get('state')=='PASS',(report,r.get('exception'),r.get('failures'))
   assert r.get('manifest_sha256')==fingerprint(),'stale result '+report
   if report=='native_access_result.json':assert not r.get('placements'),'unrepaired inaccessible NPCs'
   print(report+': PASS',flush=True);break
  time.sleep(.25)
 else:raise TimeoutError(report)
print('Remaining native validation suite: PASS',flush=True)
