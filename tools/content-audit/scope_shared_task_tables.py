"""Separate unrelated full-table exports from actual supplied quest dependencies."""
import re,collections

def scope(b):
    from integrate_shared_tasks import core
    for u in b.units:
        floors={m['floor'] for m in u['maps']}
        called=set()
        groups=set()
        def battle(raw):
            p=raw.split(b'|')
            if len(p)>9 and core.number(p[9]) is not None:
                called.add(int(p[9]));groups.add(int(p[9]))
        for r in u['tables'].get('npc',[]):
            c=r['columns']
            if len(c)<25:continue
            if core.number(c[7])==0 and core.number(c[8]) is not None:floors.add(int(c[8]))
            if c[0].lower()==b'standenemy':battle(c[24])
            if c[0].lower()==b'warp':
                p=c[24].split(b'|')
                if len(p)>1 and core.number(p[0])==0 and core.number(p[1]) is not None:floors.add(int(p[1]))
        for r in u['tables'].get('warp',[]):
            c=r['columns']
            floors.update([int(c[1]),int(c[4])])
        for r in u['tables'].get('dungeonconf',[]):
            if len(r['columns'])>49 and core.number(r['columns'][49]) is not None:called.add(int(r['columns'][49]))
        for s in u['scripts']:
            for m in re.finditer(rb'\bWarp\s*,?\s*0\s*,\s*(\d+)',s['data'],re.I):floors.add(int(m[1]))
            for m in re.finditer(rb'(?im)^\s*Encount\s+([^\r\n]+)',s['data']):battle(m[1])
        kept=[];removed=[]
        rows=u['tables'].get('encount',[])
        for r in rows:
            c=r['columns']
            if len(c)<24:kept.append(r);continue
            id,mt,f=core.number(c[0]),core.number(c[2]),core.number(c[3])
            if f==777 or mt!=0 or f in floors or id in called or len(rows)<20:
                kept.append(r)
                groups.update(int(v) for v in c[14:24] if core.number(v) is not None and int(v)>0)
            else:removed.append(r)
        u['tables']['encount']=kept
        gr=u['tables'].get('group',[])
        # A supplied group may be called by a misspelled encounter number or
        # another chapter. Keep every group so later reference repair can bind it.
        discarded=[]
        if removed or discarded:
            b.notes.append({'kind':'unreferenced_full_table_export_scoped','unit':u['id'],
                            'encount_rows':[{'path':r['path'],'line':r['line'],'id':core.number(r['columns'][0])} for r in removed],
                            'group_rows':[{'path':r['path'],'line':r['line'],'id':core.number(r['columns'][2])} for r in discarded],
                            'reason':'Rows have no supplied map, NPC, script battle or transport dependency in this quest unit'})
