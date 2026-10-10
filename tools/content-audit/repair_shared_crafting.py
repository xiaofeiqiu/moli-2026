"""Fix provable output/skill transpositions in submitted recipe rows."""
def repair(b):
    from integrate_shared_tasks import label,core
    items={int(r['columns'][11]):r['columns'][1] for u in b.units for r in u['tables'].get('itemset',[])}
    skills=set(b.base['skill'])|{int(r['columns'][1]) for u in b.units for r in u['tables'].get('skill',[])}
    for u in b.units:
        for r in u['tables'].get('itemrecipe',[]):
            c=r['columns'];a,d=core.number(c[2]),core.number(c[3])
            baseline=b.base['itemrecipe'].get(int(c[1]))
            if d not in skills and items.get(d)==c[0] and baseline and c[2]==baseline[2] and c[5:]==baseline[5:]:
                c[2],c[3]=c[3],baseline[3]
                a=int(c[3])
                b.notes.append({'kind':'recipe_output_skill_transposition_repaired','unit':u['id'],'path':r['path'],'line':r['line'],'output':d,'skill':a,'name':label(c[0])})
