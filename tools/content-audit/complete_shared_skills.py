"""Make missing skill groups usable using the supplied native techniques."""
import collections,re

def complete(b):
    from integrate_shared_tasks import label,core
    supplied={int(r['columns'][1]) for u in b.units for r in u['tables'].get('skill',[])}|set(b.base['skill'])
    templates=collections.defaultdict(list)
    for id,t in b.base['tech'].items():
        if core.number(t[5]) in b.base['skill']:templates[t[1]].append(b.base['skill'][int(t[5])])
    for u in b.units:
        groups=collections.defaultdict(list)
        for r in u['tables'].get('tech',[]):
            c=r['columns']
            if len(c)>=15 and core.number(c[5]) is not None and int(c[5]) not in supplied and not c[1].startswith((b'TECH_Mon',b'TECH_Enemy')):
                groups[int(c[5])].append(c)
        for sid,ts in groups.items():
            prototype=templates.get(ts[0][1],[])
            if not prototype:continue
            c=prototype[0].copy();name=re.sub(r'\s*(?:LV\s*\d+|Lv\s*\d+|[．.-][ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ]+).*$', '',label(ts[0][0]),flags=re.I)
            c[0]=name.encode('gbk');c[1]=str(sid).encode();c[2]=b'0'
            u['tables']['skill'].append({'columns':c,'path':u['root']+'/[derived-native-skill-group]','line':0})
            b.notes.append({'kind':'custom_skill_group_from_supplied_techniques','unit':u['id'],'skill':sid,'name':name,'function':label(ts[0][1]),'techniques':[int(t[3]) for t in ts]})
