"""Stage native knight shops and additive physical/magic equipment, preserving DATA bytes."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE = ROOT / 'backups/knight_hybrid_gear_20261004'
STAGE = BASE / 'staged'
RUN = BASE / 'native_runtime/gmsv'
OUT = ROOT / 'docs/knight_hybrid_gear'
STAT_PAIRS = list(range(31, 76, 2)) + [91, 99]
LABELS = {31:'攻击',33:'防御',35:'敏捷',37:'精神',39:'回复',41:'必杀',43:'反击',45:'命中',47:'闪躲',49:'生命',51:'魔力',91:'魔抗',99:'魔攻'}
KINDS = [(2,'枪',3),(7,'盾',None),(8,'盔',9),(10,'甲',12),(13,'靴',14)]

def digest(data):
    return hashlib.sha256(data).hexdigest()

def number(value):
    return int(value or b'0')

def records(data):
    return [r.split(b'\t') for r in data.splitlines() if r.strip() and not r.lstrip().startswith((b'#',b'//'))]

def lua(value):
    if isinstance(value,dict):
        return '{'+','.join('['+lua(k)+']='+lua(v) for k,v in value.items())+'}'
    if isinstance(value,list):
        return '{'+','.join(lua(v) for v in value)+'}'
    if isinstance(value,str):
        return json.dumps(value,ensure_ascii=False)
    if isinstance(value,bool):
        return 'true' if value else 'false'
    return str(value)

def source_row(items, crafted, typ, rank):
    candidates=[r for i,r in items.items() if i in crafted and number(r[14])==typ
        and number(r[23])==rank and 1000<=i<700000 and number(r[13])>0]
    assert candidates, f'No ordinary crafted type {typ} rank {rank}'
    # Staffs prioritize casting attributes; other pieces prioritize their native role.
    main={2:31,3:37,7:33,8:33,9:37,10:33,12:51,13:33,14:35}[typ]
    secondary=99 if typ==3 else 33
    return max(candidates,key=lambda r:(number(r[main])+number(r[main+1]),
        number(r[secondary])+number(r[secondary+1]),-number(r[11])))

def scaled(row, tier):
    result=list(row)
    # Original equipment stops at R11. Higher character bands are variants of R11,
    # with 8% growth per band, while the native item rank stays R11.
    factor=1+max(0,tier-11)*0.08
    for col in STAT_PAIRS:
        for index in (col,col+1):
            if number(result[index])>0:
                result[index]=str(round(number(result[index])*factor)).encode()
    return result

def add_pair(row, col, lo, hi=None):
    hi=lo if hi is None else hi
    row[col]=str(number(row[col])+max(0,lo)).encode()
    row[col+1]=str(number(row[col+1])+max(0,hi)).encode()

def merge_positive(row, donor, columns):
    for col in columns:
        add_pair(row,col,number(donor[col]),number(donor[col+1]))

def stage(max_level, shop_span=20):
    assert max_level>=20 and max_level<=800 and max_level%10==0
    assert shop_span in (10,20,30)
    OUT.mkdir(parents=True,exist_ok=True)
    if (BASE/'installed.json').exists():
        raise RuntimeError('Already installed; use the saved manifest for subsequent edits')
    paths=['gmsv/data/itemset.txt','gmsv/lua/ModuleConfig.lua',
        'gmsv/lua/Modules/knightHybridGear.lua','gmsv/lua/Modules/knightHybridGearData.lua']
    originals={}
    for path in paths:
        dest=BASE/'original'/path
        current=ROOT/path
        if not (BASE/'manifest.json').exists():
            if current.exists():
                dest.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(current,dest)
        originals[path]=dest.read_bytes() if dest.exists() else None
        assert (current.read_bytes() if current.exists() else None)==originals[path], 'Concurrent change: '+path
    raw=originals['gmsv/data/itemset.txt']
    items={number(r[11]):r for r in records(raw)}
    crafted={number(r[2]) for r in records((ROOT/'gmsv/data/itemrecipe.txt').read_bytes())}
    definitions=[];specs=[];bands=[];shops=[];previous={}
    for tier in range(1,max_level//10+1):
        rank=min(tier,11);low=(tier-1)*10+1;high=tier*10
        staff=scaled(source_row(items,crafted,3,rank),tier)
        robe=scaled(source_row(items,crafted,12,rank),tier)
        stock=[]
        for kind_index,(typ,title,donor_type) in enumerate(KINDS):
            source=source_row(items,crafted,typ,rank)
            row=scaled(source,tier)
            assert len(row)==102,'Unexpected native item schema'
            donor=scaled(source_row(items,crafted,donor_type,rank),tier) if donor_type else None
            if typ==2:
                merge_positive(row,staff,[37,51,99])
            elif typ==7:
                add_pair(row,37,math.ceil(number(staff[37])/4),math.ceil(number(staff[38])/4))
                add_pair(row,51,math.ceil(number(robe[51])/4),math.ceil(number(robe[52])/4))
            else:
                merge_positive(row,donor,STAT_PAIRS)
                if typ==8 and number(donor[37])==0:
                    add_pair(row,37,math.ceil(number(staff[37])/2),math.ceil(number(staff[38])/2))
                if typ==13:
                    add_pair(row,51,math.ceil(number(robe[51])/4),math.ceil(number(robe[52])/4))
            # Keep progression useful when native crafting templates change tradeoffs.
            if tier>1:
                for col in STAT_PAIRS:
                    for index in (col,col+1):
                        prev=number(previous[typ][index])
                        if prev>0:
                            row[index]=str(max(number(row[index]),prev)).encode()
            item_id=721000+(tier-1)*10+kind_index
            assert item_id not in items
            name=f'魔骑{title}·{low}级'
            assert len(name.encode('gbk'))<=30
            row[0]=row[1]=name.encode('gbk')
            row[2]=f'骑士{low}级，物理与魔法属性融合'.encode('gbk')
            for col in range(3,11): row[col]=b''
            row[11]=str(item_id).encode()
            # Use source prices plus the magical donor price, with a modest hybrid premium.
            donor_cost=number(staff[13]) if typ==2 else (number(donor[13]) if donor else number(robe[13])//4)
            price=math.ceil((number(source[13])+donor_cost)*1.25*(1+max(0,tier-11)*0.08))
            row[13]=str(price).encode()
            row[16]=b'0' # Single-handed gun permits the knight's shield.
            row[20]=row[21]=row[22]=b'1'
            row[23]=str(rank).encode()
            row[24]=b'0';row[25]=row[26]=b'300'
            row[77:88]=[b'']*11 # No quest/rare-item special handlers or craft jewels.
            row[88]=row[89]=b'0';row[90]=b'1'
            row[93]=b'1';row[94]=b'140000';row[95]=b'170000'
            row[96]=b'100';row[97]=row[98]=row[101]=b'0'
            definitions.append(row);previous[typ]=row;stock.append(item_id)
            stats={LABELS.get(col,f'column_{col}'):[number(row[col]),number(row[col+1])]
                for col in STAT_PAIRS if number(row[col]) or number(row[col+1])}
            specs.append(dict(id=item_id,name=name,type=typ,native_rank=rank,min_level=low,
                character_band=[low,high],price=price,source_item=number(source[11]),
                donor_item=number(donor[11]) if donor else None,staff_item=number(staff[11]),stats=stats,
                native_pairs={str(col):[number(row[col]),number(row[col+1])] for col in STAT_PAIRS}))
        bands.append(dict(min_level=low,max_level=high,items=stock))
    for first in range(0,len(bands),shop_span//10):
        group=bands[first:first+shop_span//10]
        low,high=group[0]['min_level'],group[-1]['max_level']
        shops.append(dict(name=f'骑士装备{low}-{high}',min_level=low,max_level=high,
            items=[i for band in group for i in band['items']]))
    appended=b''.join(b'\t'.join(row)+b'\r\n' for row in definitions)
    files={'gmsv/data/itemset.txt':raw+(b'' if raw.endswith(b'\n') else b'\r\n')+appended,
        'gmsv/lua/Modules/knightHybridGear.lua':(HERE/'knightHybridGear.lua').read_text('utf-8').encode('gbk'),
        'gmsv/lua/Modules/knightHybridGearData.lua':('return '+lua(dict(items=specs,shops=shops))+'\n').encode('gbk')}
    loader=originals['gmsv/lua/ModuleConfig.lua']
    assert not re.search(rb"loadModule\(['\"]knightHybridGear",loader)
    files['gmsv/lua/ModuleConfig.lua']=loader.rstrip()+b"\r\n\r\nloadModule('knightHybridGear')\r\n"
    manifest=dict(created_utc=datetime.now(timezone.utc).isoformat(),max_character_level=max_level,shop_span=shop_span,
        center=[153,139],items=specs,shops=shops,files={},client_verified=False)
    for path,data in files.items():
        dest=STAGE/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
        manifest['files'][path]={'before':digest(originals[path]) if originals[path] else None,'after':digest(data)}
    (BASE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n','utf-8')
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n','utf-8')
    with (OUT/'equipment.csv').open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.writer(f);w.writerow(['名称','适用人物等级','装备等级','售价','属性'])
        for item in specs:w.writerow([item['name'],f"{item['character_band'][0]}-{item['character_band'][1]}",item['native_rank'],item['price'],json.dumps(item['stats'],ensure_ascii=False)])
    verify()
    print(json.dumps({'staged':True,'shops':len(shops),'items':len(specs),'max_level':max_level}))

def verify():
    manifest=json.loads((BASE/'manifest.json').read_text('utf-8'))
    for path,hashes in manifest['files'].items():
        assert digest((STAGE/path).read_bytes())==hashes['after'],path
    original=(BASE/'original/gmsv/data/itemset.txt').read_bytes()
    current=(STAGE/'gmsv/data/itemset.txt').read_bytes()
    assert current.startswith(original),'Original equipment bytes changed'
    rows=records(current);ids=[number(r[11]) for r in rows]
    assert len(ids)==len(set(ids)),'Duplicate item ID'
    by_id={number(r[11]):r for r in rows}
    for item in manifest['items']:
        row=by_id[item['id']]
        assert len(row)==102 and number(row[14])==item['type']
        assert number(row[23])==item['native_rank'] and number(row[13])==item['price']>0
        assert row[16]==b'0' and row[22]==b'1' and row[93]==b'1'
        assert number(row[25])==number(row[26])==300
        assert row[96]==b'100','Native identification probability must be 100%'
        for col,limits in item['native_pairs'].items():
            assert [number(row[int(col)]),number(row[int(col)+1])]==limits
        if item['type']==2: assert number(row[37])>0 and number(row[99])>0
        if item['type'] in (7,10,13): assert number(row[51])>0
        if item['type']==8: assert number(row[37])>0
    assert all(5<=len(s['items'])<=15 for s in manifest['shops'])
    return manifest

def prepare():
    manifest=verify();RUN.mkdir(parents=True,exist_ok=True)
    for name in ('cgmsv.exe','setup.cf','cgmsv.cf'):
        if name=='cgmsv.exe' and (RUN/name).exists():
            assert digest((RUN/name).read_bytes())==digest((ROOT/'gmsv'/name).read_bytes())
            continue
        shutil.copy2(ROOT/'gmsv'/name,RUN/name)
    for name in ('lua','data'):shutil.copytree(ROOT/'gmsv'/name,RUN/name,dirs_exist_ok=True)
    for name in ('store/itemcount','log','Dengon','GMLog','dump','house'):(RUN/name).mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/'gmsv/log/log.cf',RUN/'log/log.cf')
    shutil.copytree(STAGE/'gmsv',RUN,dirs_exist_ok=True)
    setup=(RUN/'setup.cf').read_bytes()
    for key,value in [('port',19042),('dummynum',100),('dbengine',1)]:
        setup=re.sub(rb'(?m)^'+key.encode()+rb'=\d+',f'{key}={value}'.encode(),setup)
    (RUN/'setup.cf').write_bytes(setup)
    # Exercise all game feature modules together, excluding network/admin services.
    (RUN/'lua/ModuleConfig.lua').write_bytes(b"moduleInitial()\r\nloadModule('cg71JobSkills')\r\nloadModule('skillLibrary')\r\nloadModule('fivePet')\r\nloadModule('fight')\r\nloadModule('knightHybridGear')\r\ndofile('lua/knight_gear_probe.lua')\r\n")
    source=(HERE/'native_probe.lua').read_text('utf-8').replace('__OUTPUT__',OUT.as_posix())
    source=source.replace('__ITEMSET_SHA256__',manifest['files']['gmsv/data/itemset.txt']['after'])
    (RUN/'lua/knight_gear_probe.lua').write_bytes(source.encode('gbk'))
    print(json.dumps({'runtime':str(RUN),'port':19042,'database':'isolated; production DB not copied'}))

def install():
    manifest=verify();raw_result=(OUT/'native_result.json').read_bytes()
    try: result=json.loads(raw_result.decode('utf-8'))
    except UnicodeDecodeError: result=json.loads(raw_result.decode('gbk'))
    assert result['status']=='PASS' and len(result['shops'])==len(manifest['shops'])
    assert result['itemset_sha256']==manifest['files']['gmsv/data/itemset.txt']['after']
    for path,hashes in manifest['files'].items():
        if path!='gmsv/lua/ModuleConfig.lua':
            assert digest((RUN/path.removeprefix('gmsv/')).read_bytes())==hashes['after'],'Runtime differs: '+path
    assert digest((RUN/'cgmsv.exe').read_bytes())==digest((ROOT/'gmsv/cgmsv.exe').read_bytes())
    for path,hashes in manifest['files'].items():
        src=ROOT/path
        assert (digest(src.read_bytes()) if src.exists() else None)==hashes['before'],'Concurrent change: '+path
    for path in manifest['files']:
        dest=ROOT/path;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(STAGE/path,dest)
    for path,hashes in manifest['files'].items():assert digest((ROOT/path).read_bytes())==hashes['after']
    installed=dict(shops=result['shops'],items=len(manifest['items']),native_checks=len(result['checks']),
        requires_server_restart=True,client_verified=False,backup=str(BASE/'original'),files=manifest['files'])
    (BASE/'installed.json').write_text(json.dumps(installed,ensure_ascii=False,indent=2)+'\n','utf-8')
    (OUT/'installed.json').write_text(json.dumps(installed,ensure_ascii=False,indent=2)+'\n','utf-8')
    print(json.dumps({'installed':True,'shops':len(installed['shops']),'items':installed['items'],'requires_restart':True}))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['stage','verify','prepare','install'])
    parser.add_argument('--max-level',type=int,default=200)
    parser.add_argument('--shop-span',type=int,default=20)
    args=parser.parse_args()
    if args.action=='stage':stage(args.max_level,args.shop_span)
    elif args.action=='verify':verify();print('PASS')
    elif args.action=='prepare':prepare()
    else:install()
