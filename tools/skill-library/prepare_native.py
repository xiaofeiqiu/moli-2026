"""Copy only server resources into an isolated local SQLite test server."""
import shutil,re,json
from build import ROOT,BATCH,STAGE,OUT,fingerprint
RUN=BATCH/'native_runtime/gmsv'
RUN.mkdir(parents=True,exist_ok=True)
for name in ['cgmsv.exe','setup.cf','cgmsv.cf']:
    if name=='cgmsv.exe' and (RUN/name).exists():
        assert (RUN/name).read_bytes()==(ROOT/'gmsv'/name).read_bytes();continue
    shutil.copy2(ROOT/'gmsv'/name,RUN/name)
for name in ['lua','data']:shutil.copytree(ROOT/'gmsv'/name,RUN/name,dirs_exist_ok=True)
for name in ['store','log','Dengon','GMLog','dump','house']:(RUN/name).mkdir(exist_ok=True)
shutil.copy2(ROOT/'gmsv/log/log.cf',RUN/'log/log.cf')
for p in (STAGE/'gmsv').rglob('*'):
    if p.is_file():
        dest=RUN/p.relative_to(STAGE/'gmsv');dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
cf=(RUN/'setup.cf').read_bytes()
for key,val in [('port',19033),('dummynum',100)]:cf=re.sub(rb'(?m)^'+key.encode()+rb'=\d+',(key+'='+str(val)).encode(),cf)
(RUN/'setup.cf').write_bytes(cf)
config=b"moduleInitial()\r\nloadModule('cg71JobSkills')\r\nloadModule('skillLibrary')\r\ndofile('lua/library_probe.lua')\r\ndofile('lua/library_battle_probe.lua')\r\n"
(RUN/'lua/ModuleConfig.lua').write_bytes(config)
source=(ROOT/'tools/skill-library/native_probe.lua').read_text(encoding='utf-8')
manifest=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'))
source=source.replace('__PACK_SHA256__',fingerprint(manifest))
(RUN/'lua/library_probe.lua').write_bytes(source.encode('gbk'))
battle=(ROOT/'tools/skill-library/native_battle_probe.lua').read_text(encoding='utf-8')
earth=next(s['skill'] for s in manifest['monster_sources'] if s['source_tech']==9700)
battle=battle.replace('__PACK_SHA256__',fingerprint(manifest)).replace('__EARTH_SKILL__',str(earth))
for marker,fn in [('__SUMMON_SKILL__','TECH_Summon'),('__DEATH_SKILL__','TECH_Death')]:
    sid=next(s['id'] for s in manifest['player_skills'] if s.get('source_tech') and s.get('source_function',s['function'])==fn)
    battle=battle.replace(marker,str(sid))
(RUN/'lua/library_battle_probe.lua').write_bytes(battle.encode('gbk'))
restart=(ROOT/'tools/skill-library/native_restart_probe.lua').read_text(encoding='utf-8').replace('__PACK_SHA256__',fingerprint(manifest))
(RUN/'lua/library_restart_probe.lua').write_bytes(restart.encode('gbk'))
print(json.dumps({'runtime':str(RUN),'port':19033,'database':'independent; production DB never copied'}))
