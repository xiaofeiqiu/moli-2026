"""Read-only scan of supplied client creature animations absent from enemybase.
Binary layout checked against CGTool Anime/GraphicInfo/GraphicData primary sources.
This script never edits client assets or server DATA.
"""
import argparse, collections, hashlib, json, mmap, struct, time
from pathlib import Path
BANKS = [
 ('base','bin/AnimeInfo_4.bin','bin/Anime_4.bin','bin/GraphicInfo_66.bin','bin/Graphic_66.bin'),
 ('ex','bin/AnimeInfoEx_1.Bin','bin/AnimeEx_1.Bin','bin/GraphicInfoEx_5.bin','bin/GraphicEx_5.bin'),
 ('v3','bin/AnimeInfoV3_8.bin','bin/AnimeV3_8.bin','bin/GraphicInfoV3_19.bin','bin/GraphicV3_19.bin'),
 ('puk2','bin/Puk2/AnimeInfo_PUK2_4.bin','bin/Puk2/Anime_PUK2_4.bin','bin/Puk2/GraphicInfo_PUK2_2.bin','bin/Puk2/Graphic_PUK2_2.bin'),
 ('puk3','bin/Puk3/AnimeInfo_PUK3_2.bin','bin/Puk3/Anime_PUK3_2.bin','bin/Puk3/GraphicInfo_PUK3_1.bin','bin/Puk3/Graphic_PUK3_1.bin'),
 ('joy','bin/AnimeInfo_Joy_91.bin','bin/Anime_Joy_91.bin','bin/GraphicInfo_Joy_125.bin','bin/Graphic_Joy_125.bin'),
 ('joy_ch','bin/AnimeInfo_Joy_CH1.Bin','bin/Anime_Joy_CH1.bin','bin/GraphicInfo_Joy_CH1.bin','bin/Graphic_Joy_CH1.bin'),
 ('joy_ex','bin/AnimeInfo_Joy_EX_9.bin','bin/Anime_Joy_EX_9.bin','bin/GraphicInfo_Joy_EX_9.bin','bin/Graphic_Joy_EX_9.bin'),
]
CORE={(d,a) for d in range(8) for a in (0,1,3,5,6,8,9,10)}
def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for chunk in iter(lambda:f.read(4*1024*1024),b''):h.update(chunk)
 return h.hexdigest()
def unpack_rd(data, metadata):
 index,offset,length,ox,oy,w,h,serial=metadata
 if offset+length>len(data) or length<16:raise ValueError('graphic bounds')
 b=data[offset:offset+length]
 if b[:2]!=b'RD':raise ValueError('not plain RD')
 ver=b[2];rw,rh,size=struct.unpack_from('<III',b,4)
 head=20 if ver>=2 else 16
 if ver>3 or size<head or size>length or (rw,rh)!=(w,h) or not(0<w<=4096 and 0<h<=4096):raise ValueError('RD header')
 plen=struct.unpack_from('<I',b,16)[0] if ver>=2 else 0
 if plen>768 or plen%3:raise ValueError('internal palette length')
 expected=w*h+plen;payload=b[head:size]
 if not(ver&1):
  if len(payload)<expected:raise ValueError('uncompressed pixels truncated')
  pixels=payload[:expected]
 else:
  pixels=bytearray();i=0
  def take():
   nonlocal i
   if i>=len(payload):raise ValueError('compressed stream truncated')
   v=payload[i];i+=1;return v
  while i<len(payload):
   c=take()
   if c<0x80:
    if c<0x10:n=c
    elif c<0x20:n=(c&15)*256+take()
    else:n=(c&31)*65536+take()*256+take()
    if i+n>len(payload):raise ValueError('literal bounds')
    pixels.extend(payload[i:i+n]);i+=n
   elif c<0xc0:
    value=take()
    if c<0x90:n=c&15
    elif c<0xa0:n=(c&15)*256+take()
    else:n=(c&31)*65536+take()*256+take()
    pixels.extend(bytes([value])*n)
   else:
    if c<0xd0:n=c&15
    elif c<0xe0:n=(c&15)*256+take()
    else:n=(c&31)*65536+take()*256+take()
    pixels.extend(b'\x00'*n)
   if len(pixels)>expected:
    if len(pixels)==expected+1 and pixels[-1]==0 and i==len(payload):pixels=pixels[:expected]
    else:raise ValueError('decompression overflow')
  if len(pixels)!=expected:raise ValueError('decompressed size mismatch')
 return {'version':ver,'width':w,'height':h,'palette_bytes':plen,'pixel_count':w*h,'nonzero_pixel_count':w*h-pixels[:w*h].count(0)},bytes(pixels)
def anime_record(raw, entry):
 serial,offset,count,unknown=entry
 if not(0<count<=256):raise ValueError('action count')
 p=offset;keys=set();refs=set();frames=0;extended=0;palets=set();types=set()
 first=None
 for _ in range(count):
  if p+12>len(raw):raise ValueError('anime header bounds')
  d,a,cycle,n=struct.unpack_from('<HHII',raw,p)
  if d>7 or a>64 or not(0<n<=4096):raise ValueError('action/frame bounds')
  high=p+20<=len(raw) and raw[p+16:p+20]==b'\xff'*4
  header=20 if high else 12
  if high:
   pal,flags=struct.unpack_from('<HH',raw,p+12);palets.add(pal);extended+=1
  if p+header+10*n>len(raw):raise ValueError('frame bounds')
  for i in range(n):
   ref=struct.unpack_from('<I',raw,p+header+10*i)[0];refs.add(ref)
   if first is None and d==4 and a==0:first=ref
  keys.add((d,a));types.add(a);frames+=n;p+=header+10*n
 return {'keys':keys,'refs':refs,'frame_count':frames,'action_count':count,'extended_count':extended,'palet_values':sorted(palets),'action_types':sorted(types),'offset':offset,'end':p,'first_idle_frame':first or min(refs)}
def main(root,output):
 start=time.time();basebytes=(root/'gmsv/data/enemybase.txt').read_bytes();existing=set();existing_ids=set()
 for line in basebytes.splitlines():
  c=line.split(b'\t')
  if len(c)>30:
   try:existing.add(int(c[30]));existing_ids.add(int(c[1]))
   except ValueError:pass
 variants=collections.defaultdict(list);bankstats=[];allids=set();all_files={};validated_unique_sprites=0
 missing_serials=set()
 for _,ai,_,_,_ in BANKS:missing_serials.update(e[0] for e in struct.iter_unpack('<IIHH',(root/ai).read_bytes()))
 missing_serials-=existing
 global_carriers=collections.defaultdict(list)
 for bank,_,_,gi,gd in BANKS:
  g=(root/gi).read_bytes()
  with (root/gd).open('rb') as file,mmap.mmap(file.fileno(),0,access=mmap.ACCESS_READ) as data:
   for pos in range(0,len(g),40):
    serial=struct.unpack_from('<I',g,pos+36)[0]
    if serial not in missing_serials:continue
    mt=struct.unpack_from('<IIIiiII',g,pos)+(serial,)
    if mt[1]+20>len(data) or data[mt[1]:mt[1]+2]!=b'RD' or data[mt[1]+2]<2:continue
    try:
     value=unpack_rd(data,mt)[0]
     if value['palette_bytes']>0:global_carriers[serial].append({'bank':bank,'index':mt[0],'palette_bytes':value['palette_bytes']})
    except (ValueError,struct.error):pass
 assert (root/'bin/pal/palet_00.cgp').is_file()

 for bank,ai,ad,gi,gd in BANKS:
  print('Scanning bank '+bank,flush=True)
  files=[root/x for x in (ai,ad,gi,gd)]
  for file in files:
   assert file.is_file(),str(file)
   all_files[file.relative_to(root).as_posix()]={'bytes':file.stat().st_size,'sha256':digest(file)}
  info=files[0].read_bytes();raw=files[1].read_bytes();graphics=files[2].read_bytes()
  assert len(info)%12==0 and len(graphics)%40==0
  entries=list(struct.iter_unpack('<IIHH',info));serials={e[0] for e in entries};allids|=serials
  needed_serials=serials-existing
  lookup={};palettes=collections.defaultdict(list)
  for pos in range(0,len(graphics),40):
   idx,off,ln=struct.unpack_from('<III',graphics,pos);lookup[idx]=pos
   serial=struct.unpack_from('<I',graphics,pos+36)[0]
   if serial in needed_serials:palettes[serial].append(idx)
  def meta(idx):
   pos=lookup.get(idx)
   if pos is None:raise ValueError('unresolved graphic index '+str(idx))
   idx,off,ln,ox,oy,w,h=struct.unpack_from('<IIIiiII',graphics,pos)
   serial=struct.unpack_from('<I',graphics,pos+36)[0]
   return idx,off,ln,ox,oy,w,h,serial
  sprite_cache={};stats=collections.Counter()
  with files[3].open('rb') as file,mmap.mmap(file.fileno(),0,access=mmap.ACCESS_READ) as data:
   def check_sprite(idx):
    if idx not in sprite_cache:
     try:sprite_cache[idx]=unpack_rd(data,meta(idx))[0]
     except (ValueError,struct.error) as e:sprite_cache[idx]={'error':str(e)}
    value=sprite_cache[idx]
    if 'error' in value:raise ValueError(value['error'])
    return value
   for row,entry in enumerate(entries):
    serial,offset,count,unknown=entry
    if serial in existing:stats['existing_entries']+=1;continue
    result={'bank':bank,'row':row,'appearance':serial,'action_count':count,'offset':offset,'unknown':unknown,'status':'excluded'}
    try:
     parsed=anime_record(raw,entry)
     result.update({k:v for k,v in parsed.items() if k not in ('keys','refs')})
     if not(101000<=serial<120000):raise ValueError('non-creature appearance range')
     if not CORE<=parsed['keys']:raise ValueError('missing 8-direction core movement/combat actions')
     if any(a>10 for a in parsed['action_types']):raise ValueError('player/emote action set')
     for idx in parsed['refs']:check_sprite(idx)
     carriers=[]
     for idx in palettes.get(serial,[]):
      value=check_sprite(idx)
      if value['palette_bytes']>=3:carriers.append(idx)
     result['palette_carriers']=carriers
     result['global_palette_carriers']=global_carriers.get(serial,[])
     frame_palettes=all(check_sprite(idx)['palette_bytes']>0 for idx in parsed['refs'])
     if parsed['extended_count'] and not global_carriers.get(serial) and not frame_palettes:
      raise ValueError('extended animation palette dependency unresolved')
     result['palette_dependency']='global_serial_carrier' if global_carriers.get(serial) else ('frame_internal_palette' if frame_palettes else 'supplied_default_palette')
     if check_sprite(parsed['first_idle_frame'])['nonzero_pixel_count']==0:raise ValueError('blank idle frame')
     result['unique_sprites']=len(parsed['refs'])
     result['status']='eligible';stats['eligible_entries']+=1
    except (ValueError,struct.error) as e:
     result['reason']=str(e);stats['excluded_entries']+=1
    variants[serial].append(result)
   validated_unique_sprites+=sum('error' not in x for x in sprite_cache.values())
  bankstats.append({'bank':bank,'entries':len(entries),'unique_appearances':len(serials),'graphic_entries':len(graphics)//40,'counts':dict(stats),'verified_unique_sprites':sum('error' not in x for x in sprite_cache.values())})
  print(bank+' '+json.dumps(dict(stats)),flush=True)
 candidates=[];excluded=[]
 for serial,vs in sorted(variants.items()):
  good=[v for v in vs if v['status']=='eligible'];bad=[v for v in vs if v['status']!='eligible']
  # Every selectable occurrence must resolve to a complete creature animation.
  if good and not bad:
   representative=good[-1]
   candidates.append({'appearance':serial,'representative_bank':representative['bank'],'banks':sorted({v['bank'] for v in good}),'variants':good,'official_name':None})
  else:
   excluded.append({'appearance':serial,'reasons':sorted({v.get('reason','inconsistent duplicate') for v in bad}),'eligible_variants':len(good),'variants':vs})
 result={'installation':str(root),'scan_seconds':round(time.time()-start,2),'existing_enemybase_sha256':hashlib.sha256(basebytes).hexdigest(),'existing_unique_appearances':len(existing),'all_client_unique_appearances':len(allids),'missing_unique_appearances':len(variants),'eligible_missing_creature_appearances':len(candidates),'excluded_unique_appearances':len(excluded),'validated_unique_sprites':validated_unique_sprites,'classification':'101000 <= appearance < 120000; all occurrences contain eight directions and core actions 0,1,3,5,6,8,9,10; before-run action 2 is optional; no emote actions above 10; frame dependencies decompress to pixel/palette size (one terminal transparent padding pixel allowed); extended palettes resolve across banks; nonblank idle; default/template pet data, not official species recovery.','bank_precedence':'All selectable duplicates must pass; actual packed-client load precedence is not traced.','banks':bankstats,'client_files':all_files,'candidates':candidates,'excluded':excluded}
 output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({k:result[k] for k in ['scan_seconds','all_client_unique_appearances','missing_unique_appearances','eligible_missing_creature_appearances','excluded_unique_appearances','validated_unique_sprites']}),flush=True)
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--root',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();main(a.root,a.output)
