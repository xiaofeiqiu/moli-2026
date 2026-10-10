"""Make the submitted nonstandard profession gates reachable as custom jobs."""
import re

def complete(b):
 from integrate_shared_tasks import core,label
 # Names occur in the submitted promotion comments/dialogue. These are
 # custom profiles inherited from installed professions, not official jobs.
 choices={76:{500:('大匠人',350)},118:{180:('魔剑士',10),490:('游侠',40),500:('领主',30),510:('武僧',140)},
          216:{180:('血族',70),190:('黑暗骑士',30),790:('修罗',140),800:('圣剑使',10),900:('神域使者',130)}}
 caps=[c for _,c in core.records(b.stage_originals['skilllv.txt']) if len(c)>=4]
 for u in b.units:
  for r in u['tables'].get('itemset',[]):
   c=r['columns']
   if len(c)>=102 and any(int(c[p] or b'0')<=0 for p in [20,21,23]):
    before=[label(c[p]) for p in [20,21,23]]
    c[20]=str(max(1,int(c[20] or b'0'))).encode()
    c[21]=str(max(int(c[20]),int(c[21] or b'0'))).encode()
    c[23]=str(max(int(c[21]),int(c[23] or b'0'))).encode()
    b.notes.append(dict(kind='native_item_quantity_minimum_repaired',unit=u['id'],path=r['path'],line=r['line'],source_id=int(c[11]),columns=[20,21,23],before=before,after=[label(c[p]) for p in [20,21,23]]))
 for uid,families in choices.items():
  if uid not in b.unit_by_id:continue
  u=b.unit_by_id[uid]
  if uid==76 and '兰国' not in u['root']:raise ValueError('custom profession source unit moved')
  if uid==118 and '洛伊夫' not in u['root']:raise ValueError('custom profession source unit moved')
  if uid==216 and not u['root'].endswith('暗黑'):raise ValueError('custom profession source unit moved')
  for family,(name,prototype) in families.items():
   if any(int(r['columns'][2])//10*10==family for r in u['tables'].get('jobs',[])):continue
   path=u['root']+'/[custom-profession]'
   for rank in range(1,8):
    c=b.base['jobs'][prototype+rank].copy();c[0]=(name+['','学徒','见习','资深','大师','宗师','尊者','传承者'][rank]).encode('gbk');c[2]=str(family+rank).encode()
    u['tables']['jobs'].append(dict(columns=c,path=path,line=rank))
    for cap in caps:
     if core.number(cap[2])==prototype+rank:
      v=cap.copy();v[0]=str(56000000+uid*10000+family*10+rank).encode();v[2]=str(family+rank).encode()
      u['tables']['skilllv'].append(dict(columns=v,path=path,line=rank))
   ancestry=b.base['jobsancestry'][prototype].copy();ancestry[0]=name.encode('gbk');ancestry[1]=str(family).encode()
   ancestry[2:9]=[str(family+rank).encode() for rank in range(1,8)]
   u['tables']['jobsancestry'].append(dict(columns=ancestry,path=path,line=family))
   b.notes.append(dict(kind='custom_missing_profession_profile',unit=uid,family=family,name=name,inherited_profession=prototype))
 # A plainly truncated upper endpoint makes this authored cooking lesson
 # impossible. The neighbouring branch identifies the normal seven ranks.
 for u in b.units:
  for s in u['scripts']:
   if s['path'].endswith('Hello_11JN.txt'):
    s['data']=re.sub(rb'(Job\s*>=\s*351\s*&&\s*Job\s*<=\s*)3\b',rb'\g<1>357',s['data'],flags=re.I)
   if s['path'].endswith('5C7C11AB.txt'):
    s['data']=re.sub(rb'Job\s*>=\s*691\s*&&\s*Job\s*<=\s*701',b'Job >= 201 && Job <= 367',s['data'],flags=re.I)
    b.notes.append(dict(kind='custom_legacy_crafting_profession_gate',unit=u['id'],path=s['path'],reason='Map the submitted absent crafting-job range to installed crafting professions'))
   if s['path'].endswith('RecipeTest.txt'):
    s['data']=re.sub(rb'Job\s*==\s*701',b'Job >= 201 && Job <= 367',s['data'],flags=re.I)
   if s['path'].endswith('随机召唤书.txt'):
    s['data']=re.sub(rb'GivePet\s+0\b',b'GivePet (1%10,11%10,21%10,31%10,111%10,211%10,301%10,401%10,501%20)',s['data'],flags=re.I)
    b.notes.append(dict(kind='custom_empty_random_pet_pool',unit=u['id'],path=s['path'],reason='Replace the submitted GivePet 0 placeholder with installed level-one companions, preserving random reward semantics'))
