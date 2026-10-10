"""Read-only verification of the installed CG71 batch and unchanged client assets."""
from pathlib import Path
import argparse,collections,hashlib,json,datetime

def sha(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for chunk in iter(lambda:f.read(8*1024*1024),b''):h.update(chunk)
 return h.hexdigest()

def numeric_rows(raw,id_column):
 rows=collections.defaultdict(list)
 for line in raw.splitlines():
  cols=line.split(b'\t')
  if len(cols)>id_column:
   try:key=int(cols[id_column])
   except ValueError:continue
   rows[key].append(cols)
 return rows

def verify(root):
 doc=root/'docs';m=json.loads((doc/'cg71_pet_batch.json').read_text('utf-8'));s=json.loads((doc/'cg71_pet_candidates.json').read_text('utf-8'));backup=Path(m['backup_directory'])
 assert m['status']=='installed_native_validated' and m['count']==403
 ids=[p['species_id'] for p in m['pets']];assert ids==list(range(30001,30404))
 appearances={p['appearance_id'] for p in m['pets']};assert len(appearances)==403 and appearances=={c['appearance'] for c in s['candidates']}
 data={};original={}
 for item in m['files']:
  target=root/item['relative_path'];old=backup/item['backup_relative_path'];staged=backup/item['staged_relative_path']
  assert sha(target)==sha(staged)==item['after_sha256'],str(target)+' hash differs'
  assert sha(old)==item['before_sha256'],str(old)+' backup hash differs'
  raw=target.read_bytes();before=old.read_bytes();assert raw.startswith(before)
  appended=raw[len(before):].splitlines();assert len(appended)==403 and all(appended)
  key=target.stem;data[key]=numeric_rows(raw,1 if key=='enemybase' else 2);original[key]=numeric_rows(before,1 if key=='enemybase' else 2)
  assert not set(ids)&set(original[key]),'Allocated ID overlaps prior data'
 before_images={int(row[30]) for rows in original['enemybase'].values() for row in rows if len(row)>30 and row[30].isdigit()}
 assert not appearances&before_images
 for key in data:
  assert len(data[key][30000])==len(original[key][30000])==1 and data[key][30000][0]==original[key][30000][0]
 for pet in m['pets']:
  number=pet['species_id'];image=pet['appearance_id'];name=pet['name'].encode('gbk');assert len(name)<=16
  assert len(data['enemybase'][number])==len(data['enemy'][number])==1
  b=data['enemybase'][number][0];e=data['enemy'][number][0]
  assert b[0]==e[0]==name and int(b[1])==int(e[2])==int(e[3])==number and int(b[30])==image
  expected_base=list(data['enemybase'][30000][0]);expected_base[0]=name;expected_base[1]=str(number).encode();expected_base[30]=str(image).encode();assert b==expected_base
  expected_enemy=list(data['enemy'][30000][0]);expected_enemy[0]=name;expected_enemy[2]=expected_enemy[3]=str(number).encode();assert e==expected_enemy
 for rel,meta in s['client_files'].items():
  path=root/rel;assert path.stat().st_size==meta['bytes'] and sha(path)==meta['sha256'],'Client asset changed: '+rel
 cleanup=m['test_cleanup_files'];assert len(cleanup)==5
 testdir=(root/m['test_directory']).resolve();expectedfiles=set()
 for f in cleanup:
  path=root/f['relative_path'];assert path.resolve().parent==testdir and sha(path)==f['sha256'];expectedfiles.add(path.name)
 assert {p.name for p in testdir.iterdir() if p.is_file()}==expectedfiles
 record=json.loads((doc/'cg71_pet_30000.json').read_text('utf-8'));assert record['test_cleanup_files']==cleanup
 prior=json.loads((root/'backups/cg71_pet_poc_b3b51de9/manifest.json').read_text('utf-8'));assert prior['status']=='promoted_to_permanent_custom_pet' and prior['cleanup_files']==cleanup
 assert json.loads((backup/'manifest.json').read_text('utf-8'))==m
 native=(doc/'cg71_pet_batch_native_validation.tsv').read_text('utf-8').splitlines();assert len(native)==404
 checked=set()
 for line in native[1:]:
  columns=line.split('\t');assert columns[4:]==['PASS','PASS'];checked.add((int(columns[0]),int(columns[1])))
 assert checked=={(p['species_id'],p['appearance_id']) for p in m['pets']}
 assert (backup/'validation/native_result.txt').read_text().startswith('PASS count=403 created=403 battles=403 ')
 assert (backup/'validation/helper_result.txt').read_text().startswith('PASS ')
 result={'result':'PASS','verified_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'installed_species':403,'range':[30001,30403],'eligible_snapshot_missing_after_install':len(appearances-{int(row[30]) for rows in data['enemybase'].values() for row in rows if len(row)>30 and row[30].isdigit()}),'original_data_bytes_preserved':True,'original_30000_unchanged':True,'all_default_fields_identical':True,'gbk_names_max_16_bytes':True,'new_ids_unique_and_previously_unused':True,'client_asset_files_sha256_unchanged':len(s['client_files']),'cleanup_files_sha256_verified':5,'native_per_species_results':'403/403 PASS','gm_helper_validation':'PASS','main_runtime_load_pending':m['main_runtime_load_pending']}
 return result

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--output',type=Path);a=p.parse_args();result=verify(a.root)
 if a.output:a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(result,ensure_ascii=False,indent=2))
