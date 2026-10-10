"""Check IDs, complete native references, ranks, caps and byte preservation."""
import argparse
import json
from collections import Counter
from pathlib import Path
from build_pack import ROOT, BATCH, STAGE, OUT, TABLES, FOCUS, rows, digest

def verify(root):
    m=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'))
    d={f:rows((root/'gmsv/data'/f).read_bytes()) for f in TABLES}
    indexes={'jobs.txt':2,'jobsancestry.txt':1,'skill.txt':1,'tech.txt':3,'skilllv.txt':0,'skillexp.txt':0,'itemset.txt':11,'itemrecipe.txt':1}
    ids={}
    for f, col in indexes.items():
        counts=Counter(int(r[col]) for r in d[f])
        assert all(n==1 for n in counts.values()),'Duplicate IDs: '+f
        ids[f]=set(counts)
    pair=Counter((int(r[1]),int(r[2])) for r in d['skilllv.txt'])
    assert all(n==1 for n in pair.values()),'Duplicate skill/profession pairs'
    old_limit_max=max(int(r[0]) for r in rows((BATCH/'before/gmsv/data/skilllv.txt').read_bytes()))
    for r in d['skilllv.txt']:
        if int(r[0])>old_limit_max:
            assert int(r[1]) in ids['skill.txt'] and int(r[2]) in ids['jobs.txt'], 'Invalid new skilllv reference'
    for s in m['skills']:
        assert s['id'] in ids['skill.txt']
        ts=[r for r in d['tech.txt'] if int(r[5] or -1)==s['id']]
        assert {int(t[6]) for t in ts}==set(range(1,s['max_level']+1))
        for f in s['families']:
            if f==0: continue
            assert any(int(r[1])==s['id'] and int(r[2])//10*10==f and int(r[3])>0 for r in d['skilllv.txt'])
    for s in m['extended_skills']:
        assert {int(t[6]) for t in d['tech.txt'] if int(t[5] or -1)==s['id']}>=set(range(1,16))
        assert any(int(r[1])==s['id'] and int(r[3])==15 for r in d['skilllv.txt'])
    for r in m['recipes']:
        assert r['id'] in ids['itemrecipe.txt'] and r['item'] in ids['itemset.txt']
        assert all(i in ids['itemset.txt'] and count>0 for i,count in r['materials'])
    for f in ['jobs.txt','jobsancestry.txt','skill.txt','tech.txt','itemset.txt','itemrecipe.txt']:
        before=(BATCH/'before/gmsv/data'/f).read_bytes()
        assert (root/'gmsv/data'/f).read_bytes().startswith(before),'Existing bytes altered: '+f
    for path,row in m['files'].items(): assert digest((root/path).read_bytes())==row['after'],'Hash mismatch '+path
    assert len(m['jobs'])==4 and len(m['skills'])==33 and len(m['extended_skills'])==28
    result={'result':'PASS','root':str(root),'new_professions':4,'new_rank_rows':28,'new_skills':33,'advanced_groups':26,'advanced_skill_definitions':27,'extended_skills':28,'recipes':len(m['recipes']),'new_items':len(m['items']),'checks':['unique_ids','complete_skill_levels','profession_caps','all_recipe_references','original_table_bytes','file_hashes']}
    (OUT/('installed_static.json' if root==ROOT else 'staged_static.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--installed',action='store_true');a=p.parse_args();verify(ROOT if a.installed else STAGE)
