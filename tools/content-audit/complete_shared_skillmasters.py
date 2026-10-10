"""Custom native skill variants for instructors whose skill rows are absent."""
import re
def complete(b):
 from integrate_shared_tasks import core,label
 present=set(b.base['skill'])|{int(r['columns'][1]) for u in b.units for r in u['tables'].get('skill',[])}
 techids=set(b.base['tech'])|{int(r['columns'][3]) for u in b.units for r in u['tables'].get('tech',[])}
 caps=[c for _,c in core.records(b.stage_originals['skilllv.txt']) if len(c)>=4 and all(core.number(x) is not None for x in c[:4])]
 choices={'霸气轰炸':1004,'连射狙击':95,'祭献':83,'空手道':5,'强行崩击':5,'圣光笼罩':67,'圣光天幕':63,'光神降临':68,
          '诸刃碎玉':1,'阿修罗破天舞':3,'修罗爆击':3,'天魔降临':36,'单体即死魔法':86,'金钱镖':87,'牧神祈祷':64,
          '星红之刃':0,'飞燕无双':105,'闪电手里剑':257,'冥界冲击波':4,'魔能肆虐':27,'神の?':56}
 for u in b.units:
  for r in u['tables'].get('npc',[]):
   c=r['columns']
   if len(c)<25 or c[0].lower()!=b'skillmaster':continue
   p=c[24].split(b'|');sid=core.number(p[0])
   if sid is None or sid in present:continue
   name=label(c[1]).strip();prototype=choices.get(name,4)
   if prototype not in b.base['skill']:raise ValueError('missing native skill prototype '+str(prototype))
   s=b.base['skill'][prototype].copy();s[0]=name.encode('gbk');s[1]=str(sid).encode();s[2]=b'0'
   path=u['root']+'/[custom-instructor-skill]'
   u['tables']['skill'].append({'columns':s,'path':path,'line':sid});present.add(sid)
   ts=[]
   candidates=[(id,t) for id,t in sorted(b.base['tech'].items()) if core.number(t[5])==prototype and 1<=int(t[6] or b'0')<=10]
   if not candidates:
    # These supplied instructors teach native monster techniques. The first
    # ten authored variants have real functions/options, but use level 50 as
    # the monster-only sentinel. Make explicit player levels for this custom
    # instructor, keeping the native effects instead of replacing the skill.
    candidates=[(id,t) for id,t in sorted(b.base['tech'].items()) if core.number(t[5])==prototype and int(t[6] or b'0')==50][:10]
   repeated=len({int(t[6]) for _,t in candidates})!=len(candidates)
   for ordinal,(id,t) in enumerate(candidates,1):
    level=ordinal if repeated or int(t[6])>10 else int(t[6])
    new=51000000+sid*100+level*2
    while new in techids:new+=1
    techids.add(new);t=t.copy();t[0]=(name+'Lv'+str(level)).encode('gbk');t[3]=str(new).encode();t[5]=str(sid).encode();t[6]=str(level).encode()
    u['tables']['tech'].append({'columns':t,'path':path,'line':new});ts.append(new)
   if not ts:raise ValueError('native prototype has no usable techniques '+str(prototype))
   count=0
   for cap in caps:
    if int(cap[1])!=prototype:continue
    v=cap.copy();v[0]=str(59000000+sid*1000+count).encode();v[1]=str(sid).encode()
    u['tables']['skilllv'].append({'columns':v,'path':path,'line':count});count+=1
   if count==0:
    for cap in caps:
     if int(cap[1])!=4 or int(cap[3])<1:continue
     v=cap.copy();v[0]=str(59000000+sid*1000+count).encode();v[1]=str(sid).encode();v[3]=str(min(10,int(cap[3]))).encode()
     u['tables']['skilllv'].append({'columns':v,'path':path,'line':count});count+=1
   b.notes.append({'kind':'custom_missing_instructor_skill','unit':u['id'],'source_skill':sid,'name':name,'inherited_native_skill':prototype,'techniques':ts,'job_caps':count})
