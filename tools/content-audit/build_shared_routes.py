"""Keep existing automatic exits; expose colliding imported exits as NPC routes."""
import collections,json
from pathlib import Path

def build(b):
 from integrate_shared_tasks import core,label,OUT,save
 origins=collections.defaultdict(set)
 for _,c in core.records(b.stage_originals['warp.txt']):
  if len(c)>=7 and all(core.number(v) is not None for v in c[:7]):origins[tuple(int(v) for v in c[1:4])].add(tuple(int(v) for v in c[4:7]))
 kept=[];routes={};duplicates=0
 for c in b.additions['warp']:
  origin=tuple(int(v) for v in c[1:4]);dest=tuple(int(v) for v in c[4:7])
  if dest in origins[origin]:duplicates+=1;continue
  if origins[origin]:routes.setdefault(origin,set()).update(origins[origin]|{dest})
  else:kept.append(c)
  origins[origin].add(dest)
 b.additions['warp']=kept
 data=[]
 for origin,dests in sorted(routes.items()):
  choices=[]
  for floor,x,y in sorted(dests):
   scene=b.base_maps.get(floor) or next((m for m in b.map_entities if m['new_id']==floor),{})
   choices.append(dict(floor=floor,x=x,y=y,name=scene.get('name','区域 '+str(floor)).split('|')[0]))
  data.append(dict(floor=origin[0],x=origin[1],y=origin[2],destinations=choices))
 def lua(v):
  if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
  if isinstance(v,int):return str(v)
  if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
  return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in v.items())+'}'
 b.files['gmsv/lua/Modules/sharedTaskRoutesData.lua']=('return '+lua(data)).encode('gbk',errors='replace')
 b.files['gmsv/lua/Modules/sharedTaskRoutes.lua']=(Path(__file__).parent/'templates/sharedTaskRoutes.lua').read_text(encoding='utf-8').encode('gbk')
 b.notes.append(dict(kind='shared_route_collisions_adapted',duplicate_routes_merged=duplicates,selection_points=len(data),automatic_routes_added=len(kept)))
 save(OUT/'shared_route_selections.json',data)
