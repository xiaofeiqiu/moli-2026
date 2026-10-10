"""Adapt missing scripts from submitted routes, neighbours and quest objects."""
import collections,json,re,copy
from pathlib import Path

def complete(b):
 from integrate_shared_tasks import OUT,label,sha,core
 b.custom_actions=[]
 roles=json.loads((OUT/'missing_script_roles.json').read_text(encoding='utf-8'))
 def script(u,name,text,reason):
  path=u['root']+'/[custom-script]/'+name
  record={'path':path,'alias':'stp_'+sha(path.encode())[:18]+'.txt','data':text.replace('\n','\r\n').encode('gbk'),'unit':u['id']}
  u['scripts'].append(record);b.script_local[(u['id'],name.casefold())].append(record);b.script_global[name.casefold()].append(record)
  b.notes.append({'kind':'custom_missing_script_adaptation','unit':u['id'],'script':name,'reason':reason,'path':path})
  return record
 def replace(u,name,text,reason):
  candidates=b.script_local.get((u['id'],name.casefold()),[])
  for s in candidates:s['data']=text.replace('\n','\r\n').encode('gbk')
  if candidates:b.notes.append({'kind':'custom_incomplete_script_completion','unit':u['id'],'script':name,'reason':reason})
  else:script(u,name,text,reason)
 def row(u,k,id,c):
  c=c.copy();from integrate_shared_tasks import SPECS
  c[SPECS[k][0]]=str(id).encode();u['tables'][k].append({'columns':c,'path':u['root']+'/[custom-script-asset]','line':id})
 def token(u,id,name):
  template=next(c for n,c in b.base['itemset'].items() if n>0 and c[14]==b'26' and core.number(c[24]) in {0,1}).copy()
  template[0]=template[1]=name.encode('gbk');template[2:11]=[b'']*9;template[13]=b'0';template[15]=b'';template[84:87]=[b'']*3;template[94:96]=[b'']*2
  row(u,'itemset',id,template)
 def exchange(need,give,text,cost=0,extra=''):
  tests=['itemSpace >= 1','gold >= '+str(cost)]+['item '+str(i)+' >= '+str(n) for i,n in need]
  guard=' && '.join(tests)
  consume='\n'.join('KillItem '+str(i)+','+str(n) for i,n in need)
  gifts='\n'.join('GiveItem '+str(i)+','+str(n) for i,n in give)
  return 'Block\nWindow "'+text+'",YES,NO\nWindow_NO\nEndWindow "需要时再来吧。"\nWindow_YES '+guard+'\n'+consume+'\nAddGold -'+str(cost)+'\n'+gifts+'\n'+extra+'\nEndWindow "已经办妥，请按提示继续旅程。"\nWindow_YES\nEndWindow "请确认任务道具、魔币和背包空位。"'
 def action(u,name,rows,config,text):
  key='stp:'+sha((u['root']+'/'+name).encode())[:20]
  config=dict(config,key=key,unit=u['id'],name=label(rows[0]['columns'][1]) if rows else name,
              roles=[{'name':label(r['columns'][1]),'floor':int(r['columns'][8]),'mapType':int(r['columns'][7])} for r in rows])
  b.custom_actions.append(config)
  script(u,name,'Block\nWindow "'+text+'",YES,NO\nWindow_NO\nEndWindow "准备好再来。"\nWindow_YES\nLuac '+key,
         'Custom quest interaction with checked prerequisites, native battle victory and persistent claim state')
 def opponents(u,words=None):
  enemies=u['tables'].get('enemy',[])
  if not enemies:return [[1,30]]
  selected=[r['columns'] for r in enemies if words and any(w in label(r['columns'][0]) for w in words)]
  if not selected:selected=[r['columns'] for r in enemies]
  selected.sort(key=lambda c:-(int(c[4] or b'1')))
  return [[int(c[2]),max(1,min(180,int(c[4] or b'60')))] for c in selected[:3]]
 for entry in roles:
  name=entry['script'];uid=entry['roles'][0]['unit']
  if uid not in b.unit_by_id:continue
  u=b.unit_by_id[uid]
  previous=len(b.missing)
  resolved=b.filename(uid,name.encode('gbk'),'custom-source-script-lookup')
  if resolved!=name.encode('gbk'):
   del b.missing[previous:];continue
  del b.missing[previous:]
  if b.script_local.get((uid,name.casefold())) or b.script_global.get(name.casefold()):continue
  npcs=[r for r in u['tables'].get('npc',[]) if len(r['columns'])>=25 and name.casefold().encode('gbk') in r['columns'][24].lower()]
  items=[r for r in u['tables'].get('itemset',[]) if any(name.casefold().encode('gbk') in v.lower() for v in r['columns'][:16])]
  # Missing city scripts have explicit reciprocal NPC endpoints in the pack.
  m=re.fullmatch(r'EV_LG_(8000[1-8])\.txt',name,re.I)
  if m and npcs:
   index=int(m[1]);partner=index+1 if index%2 else index-1
   other=next(r for r in u['tables']['npc'] if ('ev_lg_'+str(partner)+'.txt').encode() in r['columns'][24].lower())
   c=other['columns'];dest=','.join(label(v) for v in [c[7],c[8],c[9],str(int(c[10])+1).encode()])
   script(u,name,'Block\nWindow "要前往'+label(c[1]).split('-')[0]+'吗？",YES,NO\nWindow_NO\nEndWindow "旅途平安。"\nWindow_YES\nLeaveGroup\nWarp '+dest,'Reciprocal city transport reconstructed from the supplied paired NPC coordinates')
   continue
  # The three unprovided fruit tree variants use exactly the same neighbouring
  # authored gathering mechanic; retain its visitor/cooldown and battle chance.
  if re.search(r'senlinshu2[234]\.txt$',name,re.I):
   original=next((s for s in u['scripts'] if s['path'].lower().endswith('senlinshu21.txt')),None)
   if original:script(u,name,label(original['data']),'Copy supplied adjacent tree gathering mechanic');continue
  if name=='XY_ZZP_shanhu_zjsj04.txt':
   script(u,name,'Block item 1002005 >= 1\nEndWindow "种下的树精需要时间成长。请带浇灌用的水回到种植地点；成熟后可按原种植流程收获。"\nBlock\nEndWindow "这份笔记记录了树精的种植方法。"','Planting journal describes the supplied timed planting/harvest scripts without skipping their timer');continue
  if name in {'Get_yaoshi1.txt','Get_yaoshi2.txt'}:
   target=589104 if name.endswith('1.txt') else 589105
   script(u,name,exchange([(589103 if name.endswith('1.txt') else 589102,1)],[(target,1)],'要使用钥匙开启遗迹宝箱吗？'),'Custom key/chest exchange; consumes the submitted key and gives an audited custom treasure');continue
  if name=='Get_gaizao_shu.txt':
   script(u,name,exchange([(591389,1)],[(591390,1)],'要整理残破的书，读出其中的改造线索吗？'),'Custom damaged-book clue exchange');continue
  if name=='an_XingLing060.txt':
   script(u,name,'Block item 81039 >= 1\nWindow "空灵耳饰中传来星云的声音，要回到她身边吗？",YES,NO\nWindow_NO\nWindow_YES item 81039 >= 1\nLeaveGroup\nWarp 0,44245,11,12','Reusable earned quest item returns to the supplied Starcloud NPC');continue
  if name=='修罗传送.txt':
   script(u,name,exchange([(39744,1)],[],'使用修罗卷轴前往试炼入口吗？',extra='LeaveGroup\nWarp 0,12540,10,10'),'Custom consumable scroll leads to the supplied final trial area');continue
  if name in {'混沌水晶.txt','XY_ZZP_shanhu_zjsj04.txt'}:
   script(u,name,'Block\nEndWindow "这枚始源水晶可交给制作师镶嵌到装备中，不同装备会产生不同效果。"','Gem retains its real material effect and shows usage instructions');continue
  if items:
   itemid=int(items[0]['columns'][11]);title=label(items[0]['columns'][1])
   config={'kind':'item','useItem':itemid,'itemMode':'experience'}
   if name=='jybz.txt':pass
   elif name=='jybzcw.txt':config['itemMode']='petExperience'
   elif name=='转生药水.txt':config['itemMode']='rebirth'
   elif name=='XX_pet109.txt':config.update(itemMode='pet',petName='翼龙')
   elif re.fullmatch(r'宠物12[1-5]\.txt',name):
    config.update(itemMode='petSkill',tech={'宠物121.txt':2009,'宠物122.txt':2309,'宠物123.txt':26209,'宠物124.txt':25709,'宠物125.txt':40009}[name])
   elif '传送' in name:config.update(itemMode='warp',warp=[0,1000,153,100])
   else:raise ValueError('Unclassified missing item script '+name)
   action(u,name,[],config,'要使用'+title+'吗？消耗后效果不可撤销。');continue
  if not npcs:continue
  if name=='回到曙光骑士营地.txt':
   target=next(v for v in b.units if Path(v['root']).name.endswith('曙光系列'))
   action(u,name,npcs,dict(kind='exchange',warp=[0,27001,47,66],warpUnit=target['id']),
          '要返回曙光骑士团营地吗？请先解散队伍。')
   continue
  if name=='挑战幻想乡.txt':
   tokenid=1890000+uid*100+len(b.custom_actions)
   token(u,tokenid,'幻想乡挑战勋章')
   action(u,name,npcs,dict(kind='battle',level=30,once=True,rounds=[opponents(u,['灵梦'])],give=[[tokenid,1]]),
          '接受幻想乡的单人入门挑战，胜利后可领取挑战勋章；连战试炼请向北侧各级接待员报名。')
   continue
  # Huilai 2-9 form a new side story that uses the existing dragon-bone lead.
  hm=re.fullmatch(r'huilai([2-9])\.txt',name,re.I)
  if hm:
   n=int(hm[1]);base=1893000
   if n<9:token(u,base+n,'追龙调查·'+['','', '小凯的证言','小秋的线索','武士的手札','杰特的情报','看守的许可','加图的证据','尼微尔的委托'][n])
   if n==2:
    action(u,name,npcs,{'kind':'exchange','need':[[52268,1]],'retainNeeds':True,'give':[[base+n,1]],'once':True,'warp':[0,560,10,10]},'你带来了追击暗龙的龙骨。小凯会把证言交给你，请到村里继续调查。')
   elif n<9:
    action(u,name,npcs,{'kind':'exchange','need':[[base+n-1,1]],'give':[[base+n,1]],'once':True},'将上一位村民的线索交给我，我会帮你核实，并给你下一份调查凭证。')
   else:
    action(u,name,npcs,{'kind':'battle','need':[[base+8,1]],'give':[[59912,1]],'once':True,'rounds':[opponents(u,['暗龙王','龙王'])]},'线索已经齐全。战胜龙王的残影后，我会用调查凭证为你换取圣剑。')
   continue
  if name.startswith('an_XingLing05'):
   configs={
    'an_XingLing054.txt':dict(kind='exchange',needDone='star_letter',give=[[81036,1]],once=True),
    'an_XingLing055.txt':dict(kind='exchange',need=[[81036,1]],give=[[81037,1]],once=True,warp=[0,44245,11,12]),
    'an_XingLing056.txt':dict(kind='exchange',need=[[81037,1]],retainNeeds=True,give=[[81038,1]],once=True),
    'an_XingLing057.txt':dict(kind='exchange',need=[[81038,1]],retainNeeds=True,setDone='star_tomb_access'),
    'an_XingLing058.txt':dict(kind='battle',need=[[81038,1]],retainNeeds=True,once=True,rounds=[opponents(u,['魔族守卫'])],warp=[0,44237,89,12],setDone='star_tomb_victory'),
    'an_XingLing059.txt':dict(kind='exchange',need=[[81038,1]],needDone='star_tomb_victory',give=[[81039,1],[81040,1]],once=True)
   }
   config=configs.get(name)
   if config:
    if name=='an_XingLing058.txt':config['entranceFloor']=44218;config['entranceWarp']=[0,44238,26,5];config['needDone']='star_tomb_access'
    action(u,name,npcs,config,{'an_XingLing054.txt':'界神已经收到镇长急件。请将这封信交给星云，她会协助你调查古墓。','an_XingLing055.txt':'你带来了界神的信。我将精灵之羽交给你，请进入内殿继续交谈。','an_XingLing056.txt':'请把这条线索带给长老穆拉，再调查老界神的古墓。','an_XingLing057.txt':'空灵耳饰的线索指向古墓。我允许你继续调查，务必小心古墓之巫。','an_XingLing058.txt':'进入古墓，接受守护者的试炼。胜利后才能进入老界神墓葬。','an_XingLing059.txt':'你通过了古墓试炼。这两件信物是星灵对勇士的谢礼。'}[name]);continue
  if name in {'zll_百人_兑奖助手.txt','zll_百人_水晶助手.txt'}:
   script(u,name,exchange([(661044 if '兑奖' in name else 661047,10)],[(661048 if '兑奖' in name else 661051,1)],'收集十枚相应元素碎片后，可以在这里合成一枚元素石。'),'Custom dojo fragment exchange consumes victory-earned fragments');continue
  if '幻想次元竞技场' in name:
   match=re.search(r'(\d+)\.txt$',name);n=int(match[1]) if match else 1
   tier=(n-1)%7+1
   if n>=8:
    key='arena_tier_'+str(n-7)
    config=dict(kind='exchange',needDone=key,give=[[60557 if n<10 else 60558 if n<12 else 60559,3]],once=True)
   elif n==7:
    config=dict(kind='petTeacher',techs=[2009,2309,6259,40009],cost=50000)
   else:
    es=opponents(u,['王','灵梦','魔女','龙'])
    target={1:30,2:60,3:90,4:80,5:120,6:100}.get(n,30)
    # Scale the actual supplied opponents to the advertised bracket; do not
    # put the level-30 entrance against a level-180 profile by accident.
    es=[[enemy,target] for enemy,_ in es]
    rounds=[es[i%len(es):i%len(es)+1] for i in range({1:3,2:5,3:7,4:5,5:10,6:7}.get(n,3))]
    config=dict(kind='battle',rounds=rounds,level={1:30,2:60,3:90,4:80,5:120,6:100}.get(n,30),setDone='arena_tier_'+str(tier),once=True,warp=[0,{1:75,2:76,3:77,4:78,5:79,6:81}.get(n,75),10,10])
   action(u,name,npcs,config,'这里是幻想次元竞技场。挑战按等级分组，逃跑或战败不会获得通关奖励；兑奖员会核对你的胜利记录。');continue
  # Known adjacent scripts supply proof of the missing branch's intended trade.
  # Inspect the next numbered script for an input and the previous for output.
  numbers=re.findall(r'\d+',name);incoming=[];outgoing=[]
  if numbers:
   last=numbers[-1];idx=name.rfind(last);prefix=name[:idx].casefold();value=int(last)
   for s in u['scripts']:
    other=Path(s['path']).name.casefold();ns=re.findall(r'\d+',other)
    if not ns or other[:other.rfind(ns[-1])]!=prefix:continue
    diff=int(ns[-1])-value
    if diff==-1:incoming=[int(m[1]) for m in re.finditer(rb'(?im)^\s*GiveItem\s+(\d+)',s['data'])]
    if diff==1:outgoing=[int(m[1]) for m in re.finditer(rb'\bItem\s+(\d+)\s*(?:==|>=)\s*1',s['data'],re.I)]
  supplied={int(r['columns'][11]) for r in u['tables'].get('itemset',[])}|set(b.base['itemset'])
  incoming=[x for x in incoming if x in supplied];outgoing=[x for x in outgoing if x in supplied and x not in incoming]
  if name=='XY_ZZP_yldll01.txt':incoming=[1002008];outgoing=[1002015]
  if name=='XY_ZZP_yldll02.txt':incoming=[1002015];outgoing=[1002013]
  if name=='XY_ZZP_shanhu_boli03.txt':incoming=[];outgoing=[1002007]
  if name=='XY_ZZP_shanhu_boli06.txt':incoming=[1002027];outgoing=[1002028]
  boss=bool(re.search('boss|式神|树根|古宅|蜡像|狮子|陨帝|古墓',name+' '+label(npcs[0]['columns'][1]),re.I))
  config={'kind':'battle' if boss else 'exchange','once':True}
  if incoming:config['need']=[[incoming[-1],1]]
  elif not boss:config['need']=[[18255,10]]
  if outgoing:config['give']=[[outgoing[0],1]]
  elif boss:
   tokenid=1890000+uid*100+len(b.custom_actions);token(u,tokenid,label(npcs[0]['columns'][1])[:12]+'试炼勋章');config['give']=[[tokenid,1]]
  else:
   tokenid=1890000+uid*100+len(b.custom_actions);token(u,tokenid,label(npcs[0]['columns'][1])[:12]+'调查信物');config['give']=[[tokenid,1]]
  if boss:config['rounds']=[opponents(u,[label(npcs[0]['columns'][1])])]
  names={int(r['columns'][11]):label(r['columns'][1]) for r in u['tables'].get('itemset',[])}
  names.update({id:label(c[1]) for id,c in b.base['itemset'].items() if id not in names})
  needs='、'.join(names.get(id,'调查凭证')+'×'+str(qty) for id,qty in config.get('need',[]))
  text=(label(npcs[0]['columns'][1]) or '调查员')+'：'+('请通过我的试炼，胜利后领取调查信物。' if boss else '请带来'+needs+'，我会交给你下一步的调查资料。')
  action(u,name,npcs,config,text)
 # Complete the existing empty return branch, and connect the consumed letter
 # to the custom Starcloud chapter using a persistent namespaced marker.
 for u in b.units:
  if '星灵资料片' in u['root']:
   replace(u,'an_XingLing053.txt',exchange([],[],'返回星灵镇需要1500魔币，要传送吗？',1500,'LeaveGroup\nWarp 0,44218,458,110'),'Complete the supplied empty paid return branch')
   s=b.script_local.get((u['id'],'an_xingling051.txt'),[])
   for r in s:r['data']=r['data'].replace(b'killitem 81035,1',b'killitem 81035,1\r\nLuac stp:star_letter')
   b.custom_actions.append(dict(key='stp:star_letter',unit=u['id'],kind='marker',setDone='star_letter',roles=[{'floor':int(r['columns'][8]),'mapType':int(r['columns'][7]),'name':label(r['columns'][1])} for r in u['tables'].get('npc',[]) if b'an_XingLing051.txt'.lower() in r['columns'][24].lower()]))

def build(b):
 from integrate_shared_tasks import OUT,label,save
 resolved=[]
 legacy_roles={};legacy_items={}
 for e in b.entities['npc']:
  r=b.transformed.get(('npc',e['new_id']))
  if r:
   for alias in re.findall(rb'stp_[a-f0-9]+\.txt',r[24]):legacy_roles.setdefault(alias,[]).append(dict(name=label(r[1]),floor=int(r[8]),mapType=int(r[7])))
 for e in b.entities['itemset']:
  r=b.transformed.get(('itemset',e['new_id']),[])
  for alias in re.findall(rb'stp_[a-f0-9]+\.txt',b'|'.join(r[:16])):legacy_items.setdefault(alias,set()).add(e['new_id'])
 for c in b.custom_actions:
  c=copy.deepcopy(c);uid=c.pop('unit');ctx='custom-action:'+c['key']
  if c.get('kind')=='legacy':
   if 'jobRange' in c:
    lo,a,hi,z=c.pop('jobRange')
    def within(id):return (id>=a if lo=='>=' else id>a) and (id<=z if hi=='<=' else id<z)
    ids={id for id in b.base['jobs'] if within(id)}
    for (kind,old),rows in b.pool.items():
     if kind=='jobs' and within(old):ids.add(int(b.resolve(uid,'jobs',str(old).encode(),ctx)))
    if a<=11 and 170<=z<=200:
     ids.update(id for id,r in b.base['jobs'].items() if int(r[3] or b'0')==1)
     ids.update(e['new_id'] for e in b.entities['jobs'] if int(e['columns'][3] or b'0')==1)
    c['jobRangeJobs']=sorted(ids)
   if 'jobValue' in c:c['value']=int(b.resolve(uid,'jobs',str(c.pop('jobValue')).encode(),ctx))
   if 'familyValue' in c:c['value']=b.job_families.get((uid,c.pop('familyValue')),c['value'])
   alias=c.pop('sourceAlias').encode()
   c['roles']=legacy_roles.get(alias,[]);c['useItems']=sorted(legacy_items.get(alias,set()))
  for name in ['need','give']:
   for r in c.get(name,[]):r[0]=int(b.resolve(uid,'itemset',str(r[0]).encode(),ctx))
  for name in ['useItem']:
   if name in c:c[name]=int(b.resolve(uid,'itemset',str(c[name]).encode(),ctx))
  for name in ['tech']:
   if name in c:c[name]=int(b.resolve(uid,'tech',str(c[name]).encode(),ctx))
  if 'techs' in c:c['techs']=[int(b.resolve(uid,'tech',str(v).encode(),ctx)) for v in c['techs']]
  if not c.pop('nativeEnemies',False):
   for battle in c.get('rounds',[]):
    for r in battle:r[0]=int(b.resolve(uid,'enemy',str(r[0]).encode(),ctx))
  if c.get('kind')!='legacy' and not c.pop('nativeRoles',False):
   for role in c['roles']:role['floor']=int(b.floor(uid,str(role['floor']).encode(),role['mapType'],ctx))
  if 'entranceFloor' in c:c['entranceFloor']=int(b.floor(uid,str(c['entranceFloor']).encode(),0,ctx))
  for name in ['warp','entranceWarp']:
   if name in c:
    p=c[name];p[1]=int(b.floor(c.get('warpUnit',uid),str(p[1]).encode(),p[0],ctx));p[2:4]=[int(x) for x in b.fit_position(str(p[1]).encode(),str(p[2]).encode(),str(p[3]).encode(),p[0],ctx)]
  c.pop('warpUnit',None)
  if c.get('petName'):
   choices=[e for e in b.entities['enemy'] if c['petName'] in label(e['columns'][0])]
   choices.sort(key=lambda e:(uid not in e['units'],len(label(e['columns'][0])),e['new_id']))
   c['pet']=choices[0]['new_id'] if choices else 16
  resolved.append(c)
 def lua(v):
  if v is None:return 'nil'
  if isinstance(v,bool):return 'true' if v else 'false'
  if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
  if isinstance(v,(int,float)):return str(v)
  if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
  return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in v.items())+'}'
 b.files['gmsv/lua/Modules/sharedTaskAdaptersData.lua']=('return '+lua(resolved)).encode('gbk',errors='replace')
 b.files['gmsv/lua/Modules/sharedTaskAdapters.lua']=(Path(__file__).parent/'templates/sharedTaskAdapters.lua').read_text(encoding='utf-8').encode('gbk')
 save(OUT/'custom_script_designs.json',resolved)
