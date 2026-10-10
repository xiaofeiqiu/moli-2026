"""Author explicit compatible profiles for assets absent from the submitted pack.

These are custom additions, never described as recovered official data. Every
record includes its source use and inherited native profile in the audit cache.
"""
import collections,json,re
from pathlib import Path

def complete(b):
 from integrate_shared_tasks import OUT,SPECS,label,core
 old=json.loads((OUT/'unresolved.json').read_text(encoding='utf-8'))
 cache=OUT/'custom_generated_assets.json'
 saved=json.loads(cache.read_text(encoding='utf-8')) if cache.exists() else []
 by=collections.defaultdict(list)
 for u in b.units:
  for kind,rs in u['tables'].items():
   if kind not in SPECS:continue
   for r in rs:
    id=core.number(r['columns'][SPECS[kind][0]])
    if id is not None:by[(kind,id)].append((u['id'],r))
 roots={u['root']:u['id'] for u in b.units}
 alias_path=OUT/'custom_reference_aliases.json'
 aliases=json.loads(alias_path.read_text(encoding='utf-8')) if alias_path.exists() else []
 alias_keys={(r['root'],r['table'],r['id']) for r in aliases}
 pending=collections.defaultdict(list)
 for e in old:
  if e['kind']=='unresolved_reference' and e['unit'] in b.unit_by_id and e['id']>=100000 and e['id']%10==1:
   k,id=e['table'],e['id'];target=id//10
   if k in SPECS and (target in b.base[k] or by.get((k,target))):pending[(e['unit'],k)].append(e)
 for (uid,k),es in pending.items():
  # A consistent family suffix, rather than a single coincidental number match.
  if len({e['id'] for e in es})<3:continue
  for e in es:
   identity=(b.unit_by_id[uid]['root'],k,e['id'])
   if identity not in alias_keys:
    aliases.append(dict(root=identity[0],table=k,id=e['id'],target=e['id']//10,context=e['context'],reason='Custom adapter for a consistently appended family suffix in at least three supplied references'))
    alias_keys.add(identity)
 for r in aliases:
  uid=roots.get(r['root']);k=r['table']
  if uid is not None and (r['target'] in b.base[k] or by.get((k,r['target']))):
   b.reference_aliases[(uid,k,r['id'])]=r['target']
   b.notes.append(dict(kind='custom_reference_family_suffix_adapter',unit=uid,table=k,source_id=r['id'],target=r['target'],reason=r['reason']))
 alias_path.write_text(json.dumps(aliases,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 def exists(k,id):return id in b.base[k] or bool(by.get((k,id)))
 def add(uid,k,id,c,reason,profile=None,context='',persist=True):
  if (uid,k,id) in b.reference_aliases:return
  if exists(k,id):return
  c=c.copy();c[SPECS[k][0]]=str(id).encode()
  r={'columns':c,'path':b.unit_by_id[uid]['root']+'/[custom-asset-'+k+']','line':0}
  b.unit_by_id[uid]['tables'][k].append(r);by[(k,id)].append((uid,r))
  note={'kind':'custom_missing_asset_profile','unit':uid,'table':k,'source_id':id,'reason':reason,'inherited_native_profile':profile,'context':context}
  b.notes.append(note)
  if persist:saved.append(dict(root=b.unit_by_id[uid]['root'],table=k,id=id,columns=[label(x) for x in c],reason=reason,profile=profile,context=context))
 for r in saved.copy():
  if r['root'] in roots:add(roots[r['root']],r['table'],r['id'],[s.encode('gbk') for s in r['columns']],r['reason'],r['profile'],r['context'],False)
 errors=collections.defaultdict(list)
 active={r['path']+':'+str(r['line']):r['columns'] for u in b.units for rs in u['tables'].values() for r in rs}
 for e in old:
  if e['kind']=='unresolved_reference' and e['unit'] in b.unit_by_id and e['table'] in SPECS:
   errors[(e['table'],e['id'])].append(e)
 def caption(uid):return re.sub(r'^\d+[.、]','',Path(b.unit_by_id[uid]['root']).name)[:10]
 # A resource with a known submitted name can inherit a real native profile.
 # Its new name and provenance explicitly distinguish this custom variant.
 for (k,id),uses in sorted(errors.items()):
  if id<=0 or exists(k,id):continue
  e=uses[0];uid=e['unit'];ctx=e['context'];row=active.get(ctx,[])
  if (uid,k,id) in b.reference_aliases:continue
  if k=='itemset':
   token=next(c for n,c in b.base[k].items() if n>0 and c[14]==b'26' and core.number(c[24]) in {0,1})
   profile=int(token[11]);c=token.copy();name=caption(uid)+'遗落凭证'
   shop=False
   if len(row)>=25 and row[0].lower()==b'itemshop2':
    shop=True;title=label(row[1]);types=set(range(0,9)) if '武器' in title else set(range(9,15)) if any(n in title for n in ['防具','衣','甲']) else {23} if any(n in title for n in ['饮品','食','料理']) else {22}
    candidates=[(n,c) for n,c in b.base[k].items() if n>0 and core.number(c[14]) in types]
    if not candidates:raise ValueError('no installed shop item prototype '+title)
    profile,c=min(candidates,key=lambda x:abs(x[0]-id));c=c.copy();name='工坊'+label(c[1]).strip()[:12]
   if id==7899876:name='金卡'
   elif id==999999:name='神器强化晶砂'
   elif id==652104:name='博彩筹码'
   elif id==800550:name='宠物训练许可'
   elif id==90630:name='宠物潜能结晶'
   elif id==591463:name='远征补给券'
   elif 'dungeonconf' in ctx:
    candidates=[(n,c) for n,c in b.base[k].items() if n>0 and core.number(c[14]) in {29,30,31,32,33,34,35,36,37}]
    if candidates:
     profile,c=min(candidates,key=lambda x:abs(x[0]-id));c=c.copy();name=label(c[1])+'（秘境）'
   elif len(row)>=48 and 'enemy' in ctx:name=label(row[0]).strip()[:10]+'战利品'
   c[0]=c[1]=name.encode('gbk',errors='replace')
   if not shop:
    c[2:11]=[b'']*9;c[15]=b''
    c[13]=b'0';c[18]=c[19]=b'0';c[84:87]=[b'']*3;c[94:96]=[b'']*2
   if id==7899876:c[22]=b'20'
   add(uid,k,id,c,'Custom shop equipment/consumable inherits installed effects' if shop else 'Custom quest credential or dungeon resource; the absent original appearance/effect is not claimed restored',profile,ctx)
  elif k=='msg':
   c=[str(id).encode(),b'']
   if len(row)>=102:
    name=label(row[1]).strip();typ=core.number(row[14])
    if typ==38:text='镶嵌宝石。不同装备类别的镶嵌效果不同，请交给相应制作师加工。'
    elif typ in range(0,15):text=name+'。装备等级达到要求后可使用；请查看装备属性。'
    else:text=name+'。用于相应任务或交易，请妥善保管。'
   elif len(row)==15:text=label(row[0])+'：消耗魔力施展，效果与当前技能等级有关。'
   elif len(row)==19:text=label(row[0])+'：通过相应指导员学习，技能等级受职业限制。'
   elif len(row)>=25 and row[0].lower() in {b'skillmaster',b'techshop'}:text='请确认学习费用、技能格数和职业要求，条件满足后可在这里学习。'
   elif len(row)>=25:text=(label(row[1]).strip() or caption(uid))+'：请先准备任务需要的道具、等级和背包空间，再继续冒险。'
   else:text=caption(uid)+'：请按接待员的提示继续任务，并确认道具和背包空间。'
   c[1]=text.encode('gbk');add(uid,k,id,c,'Custom contextual dialogue or item explanation for an absent message',None,ctx)
  elif k=='itemmaterial':
   name=label(row[1]) if len(row)>=102 else caption(uid)+'晶石'
   lvl=max(1,min(10,core.number(row[24]) or 1)) if len(row)>=102 else 1
   slot=next((pos for pos in [84,85,86] if len(row)>pos and core.number(row[pos])==id),84)
   suffix={84:'武器',85:'防具',86:'饰品'}[slot]
   choices=[(n,c) for n,c in b.base[k].items() if 0<=n<1000 and (suffix in label(c[0]) or (slot==85 and '防具' in label(c[0])))]
   if not choices:choices=list(b.base[k].items())
   profile,c=min(choices,key=lambda x:(abs(x[0]%10-(lvl-1)),x[0]));c=c.copy();c[0]=(name+'('+suffix+')').encode('gbk')
   add(uid,k,id,c,'Custom gem effect inherits an installed gem profile of the matching level/equipment category',profile,ctx)
  elif k=='titlename':
   number=1+sum(r['table']=='titlename' and r['root']==b.unit_by_id[uid]['root'] for r in saved)
   c=[str(id).encode(),(caption(uid)+'远征者·'+str(number)).encode('gbk')]
   add(uid,k,id,c,'Custom achievement title; original unlock conditions are retained',None,ctx)
  elif k=='tech':
   family=id//100*100 if id>=1000 else id//100*100
   choices=[(n,c) for n,c in b.base[k].items() if family<=n<family+100 and 0<int(c[6] or b'0')<=10]
   if not choices:choices=[(7300,b.base[k][7300])]
   profile,c=max(choices,key=lambda x:int(x[1][6] or b'0'));c=c.copy()
   add(uid,k,id,c,'Custom unsupported monster technique uses an installed technique from its ID family, or basic attack',profile,ctx)
  elif k=='group':
   # First preserve obvious extra-zero references; the main resolver rewrites them.
   fixes={int(str(id)[:i]+str(id)[i+1:]) for i,ch in enumerate(str(id)) if ch=='0' and len(str(id))>1}
   if any(any(owner==uid for owner,r in by.get((k,n),[])) for n in fixes):continue
   own=[r['columns'] for r in b.unit_by_id[uid]['tables'].get(k,[]) if len(r['columns'])>=35]
   if not own:own=list(b.base[k].values())
   c=min(own,key=lambda c:abs(int(c[2])-id)).copy();profile=int(c[2]);c[0]=(caption(uid)+'守卫战').encode('gbk')
   add(uid,k,id,c,'Custom missing battle group inherits the closest supplied group with actual opponents',profile,ctx)
  elif k=='encount':
   own=[r['columns'] for r in b.unit_by_id[uid]['tables'].get(k,[]) if len(r['columns'])>=34]
   if own:
    c=min(own,key=lambda c:abs(int(c[0])-id)).copy();profile=int(c[0])
   else:
    c=b.base[k][1].copy();profile=1
    gs=b.unit_by_id[uid]['tables'].get('group',[])
    if gs:c[14:24]=[gs[0]['columns'][2]]+[b'']*9;c[24:34]=[b'1']+[b'']*9
   c[2]=b'0';c[3]=b'777'
   add(uid,k,id,c,'Custom missing encounter distribution inherits a supplied battle distribution',profile,ctx)
  elif k=='itemrecipe':
   if id!=333:raise ValueError('Missing recipe needs an explicit design '+str(id))
   profile=next((n for n,c in b.base[k].items() if int(c[3])==215 and 280<=int(c[2])<=289),next(n for n,c in b.base[k].items() if int(c[3])==215))
   c=b.base[k][profile].copy();c[0]=(caption(uid)+'特制料理').encode('gbk')
   add(uid,k,id,c,'Custom sea-demon cooking lesson uses a real installed cooking recipe, ingredients and MP cost',profile,ctx)
 cache.write_text(json.dumps(saved,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
