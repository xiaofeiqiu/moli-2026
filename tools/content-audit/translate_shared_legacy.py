"""Compile unsupported GA/Moonboy statements into checked native Lua calls.

The original statements remain in the download and are recorded in provenance.
Numeric fields are translated by meaning, never passed to native raw offsets.
"""
import re

CHAR={3:'CHAR_形象',9:'CHAR_等级',10:'CHAR_血',11:'CHAR_魔',12:'CHAR_体力',13:'CHAR_力量',14:'CHAR_强度',15:'CHAR_速度',16:'CHAR_魔法',
      23:'CHAR_抗毒',24:'CHAR_抗睡',25:'CHAR_抗石',26:'CHAR_抗醉',27:'CHAR_抗乱',28:'CHAR_抗忘',29:'CHAR_必杀',30:'CHAR_反击',31:'CHAR_命中',32:'CHAR_闪躲',
      35:'CHAR_死亡数',39:'CHAR_受伤',42:'CHAR_经验',43:'CHAR_升级点',45:'CHAR_技能栏',46:'CHAR_ALLOCPOINT',50:'CHAR_职业',51:'CHAR_职阶',52:'CHAR_职类ID',53:'CHAR_脸',60:'CHAR_魅力',81:'CHAR_OtherFlg',159:'CHAR_形象'}
ITEM={0:'道具_ID',1:'道具_图',18:'道具_攻击',19:'道具_防御',20:'道具_敏捷',21:'道具_精神',22:'道具_回复',27:'道具_HP',28:'道具_MP',70:'道具_VAR1'}

def complete(b):
 from integrate_shared_tasks import label,sha
 b.legacy_item_conditions=set()
 species=set(b.base['enemybase'])|{int(r['columns'][1]) for u in b.units for r in u['tables'].get('enemybase',[])}
 def action(u,s,ln,original,target,field,value=None,mode=0,limit=-1,slot=0):
  if field not in (ITEM if target=='item' else CHAR):raise ValueError('Unmapped legacy field '+str((target,field,original)))
  key='stp:legacy:'+sha((s['path']+':'+str(ln)+':'+original).encode())[:20]
  c=dict(key=key,unit=u['id'],kind='legacy',target=target,field=(ITEM if target=='item' else CHAR)[field],value=value,mode=mode,limit=limit,slot=slot,
         sourceAlias=s['alias'],roles=[],source=original)
  if target=='player' and field==50 and value is not None:c['jobValue']=value
  if target=='player' and field==52 and value is not None:c['familyValue']=value
  if target=='item' and field==0 and value is None:b.legacy_item_conditions.add(key)
  b.custom_actions.append(c)
  b.notes.append(dict(kind='legacy_script_native_translation',unit=u['id'],path=s['path'],line=ln,before=original,field=c['field']))
  return 'Luac '+key
 for u in b.units:
  for s in u['scripts']:
   lines=[]
   for ln,line in enumerate(label(s['data']).splitlines(),1):
    if line.lstrip().startswith(('#','//')):lines.append(line);continue
    pieces=re.split(r'("(?:[^"\\]|\\.)*")',line)
    for i in range(0,len(pieces),2):
     text=pieces[i]
     def job_range(m):
      key=action(u,s,ln,m[0],'player',50)
      b.custom_actions[-1]['jobRange']=[m[1],int(m[2]),m[3],int(m[4])]
      return key+' >= 1'
     text=re.sub(r'\bJob\s*(>=|>)\s*(\d+)\s*&&\s*Job\s*(<=|<)\s*(\d+)',job_range,text,flags=re.I)
     m=re.match(r'^\s*(setmoonboydb|setplayerdb|mysetplayer|mysetpet|setpetdb|mbitem)\s+([-\d, ]+)\s*$',text,re.I)
     if m:
      nums=[int(n) for n in re.findall(r'-?\d+',m[2])];cmd=m[1].lower();slot=0
      if cmd=='mbitem':
       field,lo,hi,slot=nums
       if lo!=hi:raise ValueError('legacy item random range requires explicit adaptation '+text)
       target='item';value=lo;mode=1;limit=-1
      elif cmd in {'mysetpet','setpetdb'}:
       slot,mode,limit,field,value=nums;target='pet'
      else:mode,limit,field,value=nums;target='player'
      text=action(u,s,ln,text,target,field,value,mode,limit,slot)
     def condition(m):
      cmd=m[1].lower();nums=[int(n) for n in re.findall(r'-?\d+',m[2])]
      target='item' if cmd in {'moonitem','myitem'} else 'pet' if cmd in {'mypet','getpetdb'} else 'player'
      slot=nums[0] if len(nums)>1 else 0;field=nums[-1]
      return action(u,s,ln,m[0],target,field,slot=slot)+' '
     text=re.sub(r'\b(myplayer|getplayerdb|mypet|getpetdb|moonitem|myitem)\s*(\d+(?:\s*,\s*\d+)?)\s*(?=[<>!=])',condition,text,flags=re.I)
     def missing_pet_level(m):
      if int(m[1]) in species:return m[0]
      # These legacy selectors refer to breeds absent from the submission.
      # The custom eligibility check uses the player's first owned pet, so a
      # high-level pet can actually enter the supplied training branch.
      return action(u,s,ln,m[0],'pet',9,slot=0)+' '
     text=re.sub(r'\bPetLevel\s+(\d+)\s*(?=[<>!=])',missing_pet_level,text,flags=re.I)
     text=re.sub(r'^\s*(enfwindow|endwindwo)\b','EndWindow',text,flags=re.I)
     text=re.sub(r'^\s*Play_se\b','PlaySE',text,flags=re.I)
     text=re.sub(r'^\s*lock\s+','Block ',text,flags=re.I)
     text=re.sub(r'([<>!=])\s+=',r'\1=',text)
     text=re.sub(r'^\s*localcount\s+(\d+)\s*==\s*random',r'LocalCount\1 = Random',text,flags=re.I)
     pieces[i]=text
    lines.append(''.join(pieces))
   s['data']='\r\n'.join(lines).encode('gbk')
