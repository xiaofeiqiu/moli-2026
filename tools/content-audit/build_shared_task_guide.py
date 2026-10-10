import json,re,collections
from pathlib import Path

def build(b):
    from integrate_shared_tasks import ROOT,OUT,label,core
    tasks=[]
    for u in b.units:
        entry=None
        candidates=[]
        for e in b.entities['npc']:
            if u['id'] not in e['units']:continue
            c=b.transformed.get(('npc',e['new_id']))
            if not c or core.number(c[7])!=0 or core.number(c[8]) in {None,0,777}:continue
            if c[0].lower() not in {b'event',b'bus',b'jobsmaster',b'skillmaster',b'brushman'}:continue
            x,y=core.number(c[9]),core.number(c[10])
            if x is None or y is None:continue
            name=label(c[1]).strip() or '任务接待员'
            score=0 if re.search('接待|村长|向导|开[启始]|导游|长老',name) else 1
            candidates.append((score,e['line'],{'name':name,'floor':int(c[8]),'x':x,'y':y}))
        if candidates:entry=min(candidates,key=lambda x:x[:2])[2]
        scenes=[];seen=set()
        for m in u['maps']:
            if m['new_id'] in seen:continue
            seen.add(m['new_id'])
            scenes.append({'name':m['name'].split('|')[0],'floor':m['new_id']})
        if not entry and not scenes:continue
        name=re.sub(r'^\d+[.、]','',Path(u['root']).name)
        if name.casefold() in {'data','地图','map','npc'}:
            name=Path(u['root']).parent.name
        tasks.append({'name':name,'unit':u['id'],'entry':entry,'scenes':scenes})
    def lua(v):
        if v is None:return 'nil'
        if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
        if isinstance(v,int):return str(v)
        if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
        return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in v.items())+'}'
    b.files['gmsv/lua/Modules/sharedTaskGuideData.lua']=('return '+lua({'tasks':tasks})+'\n').encode('gbk',errors='replace')
    path=Path(__file__).parent/'templates/sharedTaskGuide.lua'
    b.files['gmsv/lua/Modules/sharedTaskGuide.lua']=path.read_text(encoding='utf-8').encode('gbk')
    cfg=(ROOT/'gmsv/lua/ModuleConfig.lua').read_bytes()
    if b"loadModule('sharedTaskAdapters')" not in cfg:cfg+=b"\r\nloadModule('sharedTaskAdapters')\r\n"
    if b"loadModule('sharedTaskRoutes')" not in cfg:cfg+=b"\r\nloadModule('sharedTaskRoutes')\r\n"
    if b"loadModule('sharedTaskGuide')" not in cfg:cfg+=b"\r\nloadModule('sharedTaskGuide')\r\n"
    b.files['gmsv/lua/ModuleConfig.lua']=cfg
    (OUT/'task_guide_catalog.json').write_text(json.dumps(tasks,ensure_ascii=False,indent=2),encoding='utf-8')
