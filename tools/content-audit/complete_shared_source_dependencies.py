"""Complete source-supported battle dependencies before assigning new IDs.

Every adapted row is recorded as custom content. This module never rewrites the
original download or production DATA, and does not fabricate missing scripts.
"""
import collections,json,re
from pathlib import Path


def complete(b):
    from integrate_shared_tasks import OUT,SPECS,label
    path=OUT/'unresolved.json'
    if not path.exists(): return
    errors=json.loads(path.read_text(encoding='utf-8'))
    cache_path=OUT/'custom_generated_battle_dependencies.json'
    saved=json.loads(cache_path.read_text(encoding='utf-8')) if cache_path.exists() else []
    active={r['path']+':'+str(r['line']) for u in b.units for rows in u['tables'].values() for r in rows}
    script_paths={s['path'] for u in b.units for s in u['scripts']}
    errors=[e for e in errors if e.get('context') in active or e.get('context','').rsplit(':',1)[0] in script_paths]
    by=collections.defaultdict(list)
    pet_alias_path=OUT/'custom_existing_pet_aliases.json'
    pet_aliases=json.loads(pet_alias_path.read_text(encoding='utf-8')) if pet_alias_path.exists() else []
    roots={u['root']:u['id'] for u in b.units}
    for alias in pet_aliases:
        if alias['root'] in roots:b.reference_aliases[(roots[alias['root']],'enemy',alias['id'])]=alias['target']
    for u in b.units:
        for k,rs in u['tables'].items():
            if k not in SPECS: continue
            key=SPECS[k][0]
            for r in rs:
                if len(r['columns'])>key:
                    try: by[(u['id'],k,int(r['columns'][key]))].append(r)
                    except ValueError: pass
    def exists(uid,k,id):
        return (uid,k,id) in by or id in b.base[k] or any(a[1:]==(k,id) for a in by)
    def row(uid,k,id,c,reason,origin,persist=True):
        if exists(uid,k,id): return
        c=c.copy(); c[SPECS[k][0]]=str(id).encode()
        r={'columns':c,'path':b.unit_by_id[uid]['root']+'/[custom-dependency-'+k+']','line':0}
        b.unit_by_id[uid]['tables'][k].append(r); by[(uid,k,id)].append(r)
        b.notes.append({'kind':'custom_battle_dependency_completed','unit':uid,'table':k,'id':id,'reason':reason,'copied_profile':origin})
        if persist:
            saved.append({'root':b.unit_by_id[uid]['root'],'table':k,'id':id,'columns':[label(x) for x in c],
                          'reason':reason,'copied_profile':origin})
    for record in saved.copy():
        owner=next((u['id'] for u in b.units if u['root']==record['root']),None)
        if owner is not None:
            row(owner,record['table'],record['id'],[v.encode('gbk') for v in record['columns']],record['reason'],record['copied_profile'],False)
    missing=sorted({(e['unit'],e.get('table'),e.get('id')) for e in errors if e['kind']=='unresolved_reference' and e.get('table') in {'enemy','enemyai','group','encount'}})
    for uid,k,id in missing:
        if uid not in b.unit_by_id or exists(uid,k,id) or id<=0: continue
        if k=='enemyai':
            c=b.base['enemyai'][1].copy()
            row(uid,k,id,c,'Use installed basic attack AI where the supplied AI row is absent',1)
        elif k=='enemy':
            own=[r for u,kind,old in by if u==uid and kind=='enemy' for r in by[(u,kind,old)]]
            own.sort(key=lambda r:abs(int(r['columns'][2])-id))
            template=own[0]['columns'].copy() if own else b.base['enemy'][1].copy()
            bases=by.get((uid,'enemybase',id),[])
            if not bases:
                candidates=[r for (u,kind,old),rs in by.items() if kind=='enemybase' and old==id for r in rs]
                bases=b.related([{'units':[b.owner.get(Path(r['path']),uid)],'path':r['path'],'row':r} for r in candidates],uid)
                bases=[r['row'] for r in bases]
            if bases:
                base=bases[0]['columns']; template[0]=base[0]; template[3]=str(id).encode()
                why='Use the supplied species statistics and the closest encounter level profile'
            elif id in b.base['enemybase']:
                template[0]=b.base['enemybase'][id][0]; template[3]=str(id).encode()
                why='Use the installed species and the closest supplied encounter profile'
            else:
                roles=[]
                for r in b.unit_by_id[uid]['tables'].get('group',[]):
                    c=r['columns']
                    if str(id).encode() in c[5:15]:roles.append(label(c[0]).strip())
                summon_roles=[r['columns'] for r in b.unit_by_id[uid]['tables'].get('enemy',[]) if str(id).encode() in r['columns'][45:47]]
                if not roles and summon_roles:roles=[label(c[0]).strip()+'召唤守卫' for c in summon_roles]
                if not roles:
                    # Pet content belongs to the separate pet work. Bind the
                    # absent reward to an existing level-one species, with an
                    # explicit custom adapter, rather than adding pet stats.
                    contexts=[e.get('context','') for e in errors if e.get('unit')==uid and e.get('table')=='enemy' and e.get('id')==id]
                    texts=[label(s['data']) for s in b.unit_by_id[uid]['scripts'] if any(ctx.rsplit(':',1)[0]==s['path'] for ctx in contexts)]
                    text='\n'.join(texts)
                    candidates=[]
                    for other in b.units:
                        for r in other['tables'].get('enemy',[]):
                            c=r['columns'];name=label(c[0]).strip()
                            if len(name)>=2 and name in text and c[4:6]==[b'1',b'1'] and int(c[2])!=id:candidates.append((len(name),int(c[2])))
                    # The source can omit all names for a weighted egg. Use an
                    # installed level-one companion pool; preserve the stated
                    # chances and consumption, never promise the missing breed.
                    target=max(candidates)[1] if candidates else [1,11,21,31,111,211,301,401,501][id%9]
                    b.reference_aliases[(uid,'enemy',id)]=target
                    if not any(a['root']==b.unit_by_id[uid]['root'] and a['id']==id for a in pet_aliases):pet_aliases.append(dict(root=b.unit_by_id[uid]['root'],id=id,target=target))
                    b.notes.append(dict(kind='custom_missing_pet_reward_existing_species_adapter',unit=uid,source_id=id,target=target,reason='Absent reward breed uses an already installed/provided level-one species; pet definitions are not modified'))
                    continue
                name=next((x for x in roles if re.search(r'[\u4e00-\u9fff]',x)),None)
                name=re.sub(r'[-_]\d+$','',name or '')
                campaign_name=b.unit_by_id[uid]['name']
                if not name or '?' in name:
                    name=('深渊守卫' if '暗黑' in campaign_name else '秘境守卫')
                local_bases=[r['columns'] for (u,kind,old),rs in by.items() if u==uid and kind=='enemybase' for r in rs]
                if not local_bases:local_bases=list(b.base['enemybase'].values())
                local_bases.sort(key=lambda c:abs(int(c[1])-id))
                profile=local_bases[0].copy();profile[0]=name.encode('gbk')
                for pos in range(36,46):
                    if profile[pos] and profile[pos].isdigit() and not exists(uid,'tech',int(profile[pos])):profile[pos]=b''
                row(uid,'enemybase',id,profile,'Custom encounter role reconstructed from the closest supplied creature statistics',int(local_bases[0][1]))
                template[0]=profile[0];template[3]=str(id).encode()
                why='Custom battle role uses a supplied creature profile; the absent original species is not claimed restored'
            for pos in list(range(13,23))+list(range(33,38))+[11,45,46]: template[pos]=b'0'
            template[8]=b'1'
            if not own: template[4]=template[5]=b'60'
            row(uid,k,id,template,why,label(template[0]))
    for uid,k,id in missing:
        if uid not in b.unit_by_id or exists(uid,k,id) or id<=0: continue
        if k=='group' and exists(uid,'enemy',id):
            c=b.base['group'][1].copy(); c[0]='资料包补全战斗'.encode('gbk');c[1]=b'';c[3]=c[4]=b'-1'
            c[5:15]=[str(id).encode()]+[b'0']*9;c[15:25]=[b'1']+[b'0']*9;c[25:35]=[b'0']*10
            row(uid,k,id,c,'The provided enemy row identifies this missing single-opponent group',id)
        elif k=='encount' and exists(uid,'group',id):
            c=b.base['encount'][1].copy();c[3]=b'777';c[14:24]=[str(id).encode()]+[b'']*9;c[24:34]=[b'1']+[b'']*9
            row(uid,k,id,c,'Bind the provided battle group with the same source ID',id)
    cache_path.write_text(json.dumps(saved,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    pet_alias_path.write_text(json.dumps(pet_aliases,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
