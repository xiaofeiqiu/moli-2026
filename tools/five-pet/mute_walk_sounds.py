"""Mute creature walk/run frame audio; preserve graphics, timing and combat actions.
Format source: https://github.com/HonorLee-cn/CGTool/blob/master/CrossgateToolkit/Anime.cs
Back up each modified client bank before applying changes.
"""
from pathlib import Path
import hashlib, json, struct, sys, shutil
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/cg71-pets'))
from scan import BANKS
BACKUP=ROOT/'backups/five_pet_walk_silent_20261010'

def digest(b): return hashlib.sha256(b).hexdigest()
def main():
    creatures=set()
    for line in (ROOT/'gmsv/data/enemybase.txt').read_bytes().splitlines():
        cols=line.split(b'\t')
        if len(cols)>30:
            try: creatures.add(int(cols[30]))
            except ValueError: pass
    plans=[]
    for bank,info,anime,_,_ in BANKS:
        raw=(ROOT/anime).read_bytes(); patch=bytearray(raw); edits={}; sprites=set(); frames=0
        for serial,offset,count,_ in struct.iter_unpack('<IIHH',(ROOT/info).read_bytes()):
            if serial not in creatures: continue
            pos=offset
            assert 0<count<=256,(bank,serial,count)
            for action in range(count):
                direction,kind,cycle,n=struct.unpack_from('<HHII',raw,pos)
                assert direction<8 and kind<=65535 and 0<n<=4096,(bank,serial,kind,n)
                head=20 if raw[pos+16:pos+20]==b'\xff'*4 else 12
                assert pos+head+n*10<=len(raw)
                if kind in (1,2,3,4):
                    for frame in range(n):
                        addr=pos+head+frame*10+8
                        flag=struct.unpack_from('<h',raw,addr)[0]
                        effect=20000 if flag>20000 else 10000 if flag>10000 else 0
                        if flag>0 and flag!=effect:
                            edits[addr]=(flag,effect);struct.pack_into('<h',patch,addr,effect);sprites.add(serial)
                        frames+=1
                pos+=head+n*10
        if edits:
            changed={i for i,(a,b) in enumerate(zip(raw,patch)) if a!=b}
            allowed={i for addr in edits for i in (addr,addr+1)}
            assert changed<=allowed and len(raw)==len(patch)
            plans.append((anime,raw,bytes(patch),edits,sprites,frames))
    report={'status':'PASS','source':'CGTool Anime.cs','actions':[1,2,3,4],'banks':[],'client_listening_verified':False}
    for anime,raw,patch,edits,sprites,frames in plans:
        backup=BACKUP/anime;backup.parent.mkdir(parents=True,exist_ok=True)
        if not backup.exists(): backup.write_bytes(raw)
        (ROOT/anime).write_bytes(patch)
        assert (ROOT/anime).read_bytes()==patch
        report['banks'].append({'file':anime,'before':digest(raw),'after':digest(patch),'sprites':len(sprites),'muted_frames':len(edits),'walking_frames_checked':frames})
    dest=ROOT/'docs/five_pet/walk_silent_result.json'
    dest.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'PASS','banks':len(plans),'muted_frames':sum(len(p[3]) for p in plans),'backup':str(BACKUP)},ensure_ascii=False))
if __name__=='__main__':main()
