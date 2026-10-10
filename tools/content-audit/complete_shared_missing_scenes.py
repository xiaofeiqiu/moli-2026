"""Custom scenes for missing maps, preserving all provided task coordinates."""
import collections,struct,re
from pathlib import Path

def complete(b):
    from integrate_shared_tasks import core,label,sha
    points=collections.defaultdict(set)
    captions={}
    def add(u,f,x,y,t=0,name=None):
        try: f,x,y,t=int(f),int(x),int(y),int(t)
        except (ValueError,TypeError): return
        if t or f<=0 or f==777 or not(0<=x<2000 and 0<=y<2000): return
        points[(u,f)].add((x,y))
        if name: captions.setdefault((u,f),name)
    for u in b.units:
        uid=u['id']
        for k,rows in u['tables'].items():
            for r in rows:
                c=r['columns']
                if k=='npc' and len(c)>=25:
                    for i in range(9,17,2): add(uid,c[8],c[i],c[i+1],c[7],label(c[1]))
                    p=c[24].split(b'|')
                    if c[0].lower()==b'warp' and len(p)>=4:
                        add(uid,p[1],p[2],p[3],p[0])
                        if len(p)>11: add(uid,p[9],p[10],p[11],p[0])
                    if c[0].lower()==b'standenemy' and len(p)>1:
                        q=p[1].split(b',')
                        if len(q)>=4: add(uid,q[1],q[2],q[3],q[0])
                elif k=='warp' and len(c)==7:
                    add(uid,c[1],c[2],c[3]);add(uid,c[4],c[5],c[6])
                elif k=='dungeonconf' and len(c)>=20:
                    for i in [9,15]:
                        add(uid,c[i],c[i+1],c[i+2],c[i-1]);add(uid,c[i],c[i+3],c[i+4],c[i-1])
                elif k=='encount' and len(c)>=8:
                    add(uid,c[3],c[4],c[5],c[2]);add(uid,c[3],c[6],c[7],c[2])
                elif k=='techarea' and len(c)>=11:
                    add(uid,c[6],c[7],c[8],c[5]);add(uid,c[6],c[9],c[10],c[5])
        for s in u['scripts']:
            for m in re.finditer(rb'\bWarp\s*,?\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)',s['data'],re.I):
                add(uid,m[2],m[3],m[4],m[1])
            for m in re.finditer(rb'(?im)^\s*Encount\s+([^\r\n]+)',s['data']):
                p=m[1].split(b'|')
                if len(p)>1:
                    q=p[1].split(b',')
                    if len(q)>=4:add(uid,q[1],q[2],q[3],q[0])
        for s in u['other_files']:
            if s['kind']=='bus':
                for m in re.finditer(rb'(?im)^\s*routeto\d+\s*:\s*([^\r\n]+)',s['data']):
                    for q in m[1].split(b';'):
                        a=q.split(b',')
                        if len(a)==3: add(uid,*a)
    shared=collections.defaultdict(set)
    for (uid,f),ps in points.items(): shared[(b.campaign(uid),f)] |= ps
    supplied={m['floor'] for u in b.units for m in u['maps']} | set(b.base_maps)
    for (uid,f),ps in sorted(points.items()):
        if f in supplied: continue
        u=b.unit_by_id[uid]; all_points=shared[(b.campaign(uid),f)]
        w=max(40,max(x for x,y in all_points)+8);h=max(40,max(y for x,y in all_points)+8)
        title=(captions.get((uid,f)) or re.sub(r'^\d+[.、]','',Path(u['root']).name))
        title=(title+'补建区域').encode('gbk',errors='replace')[:31]
        while True:
            try: title.decode('gbk');break
            except UnicodeDecodeError: title=title[:-1]
        header=b'LS2MAP'+struct.pack('>H',f if f<65535 else 0)+title.ljust(32,b'\0')+struct.pack('>HH',w,h)
        ground=[1003]*(w*h);obj=[0]*(w*h)
        for y in range(h):
            for x in range(w):
                if x in {0,w-1} or y in {0,h-1}:obj[(h-1-y)*w+x]=13081
        for x,y in all_points:
            for xx in range(max(0,x-1),min(w,x+2)):
                for yy in range(max(0,y-1),min(h,y+2)): obj[(h-1-yy)*w+xx]=0
        data=header+struct.pack('>'+str(w*h)+'H',*ground)+struct.pack('>'+str(w*h)+'H',*obj)
        m=core.native_map(data)
        m['floor']=f
        m.update(unit=uid,source=u['root']+'/[custom-scene-'+str(f)+']',data=data,geometry=sha(struct.pack('>HH',w,h)+data[44:]),custom_reconstructed_scene=True)
        u['maps'].append(m)
        b.notes.append({'kind':'custom_missing_scene_reconstruction','unit':uid,'floor':f,'width':w,'height':h,'provided_coordinates':sorted(all_points),'original_layout_available':False})
