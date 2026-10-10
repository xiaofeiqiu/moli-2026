"""Prepare/start/stop an isolated native server; never use production accounts."""
from __future__ import annotations
import argparse
import ctypes
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path
from integrate_shared_tasks import ROOT, BATCH, OUT, STAGE

RUN = BATCH / "native_runtime/gmsv"

def probe_config(filename):
    # Load the actual staged production module set, with only the HTTP listen
    # port isolated from the running production server.
    return ("local nativeHttpStart=Http.Start\r\nHttp.Start=function(ip,port) if port==10086 then ip='127.0.0.1';port=19046 end;return nativeHttpStart(ip,port) end\r\ndofile('lua/shared_production_config.lua')\r\ndofile('lua/"+filename+"')\r\n").encode('ascii')

def fingerprint():
    manifest=json.loads((BATCH/'manifest.json').read_text(encoding='utf-8'))
    return hashlib.sha256(json.dumps({p:r['after'] for p,r in manifest['files'].items()},sort_keys=True,separators=(',',':')).encode()).hexdigest()


def prepare():
    RUN.mkdir(parents=True, exist_ok=True)
    for name in ["cgmsv.exe", "setup.cf", "cgmsv.cf"]:
        shutil.copyfile(ROOT / "gmsv" / name, RUN / name)
    for name in ["data", "lua"]:
        shutil.copytree(ROOT / "gmsv" / name, RUN / name, dirs_exist_ok=True)
    for name in ["store", "log", "Dengon", "GMLog", "dump", "house"]:
        (RUN / name).mkdir(exist_ok=True)
    shutil.copyfile(ROOT / "gmsv/log/log.cf", RUN / "log/log.cf")
    manifest = json.loads((BATCH / "manifest.json").read_text(encoding="utf-8"))
    current_maps = {Path(p).name for p in manifest["files"] if p.startswith("gmsv/data/map/")}
    for p in (RUN / "data/map").glob("stp_*"):
        if p.name not in current_maps:
            p.unlink()
    for relative in manifest["files"]:
        p = STAGE / relative
        target = RUN / Path(relative).relative_to("gmsv")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(p, target)
    shutil.copyfile(STAGE/'gmsv/lua/ModuleConfig.lua',RUN/'lua/shared_production_config.lua')
    setup = (RUN / "setup.cf").read_bytes()
    for name, value in [("port", 19043), ("acservport", 19044), ("mlservport", 19045), ("dummynum", 100),
                        ("othercharnum", 100000), ("npccreatenum", 120000), ("objnum", 180000),
                        ("encountmemorynum", 16000), ("techareamemorynum", 10000), ("filesearchnum", 25000)]:
        setup = re.sub(rb"(?m)^" + name.encode() + rb"=\d+", name.encode() + b"=" + str(value).encode(), setup)
    (RUN / "setup.cf").write_bytes(setup)
    cf = (RUN / "cgmsv.cf").read_bytes()
    # Keep the embedded MLSV on the isolated port; disabling it prevents this
    # engine build from booting with no external mail server.
    cf = re.sub(rb"(?m)^embeddedmlsv=\d+", b"embeddedmlsv=1", cf)
    (RUN / "cgmsv.cf").write_bytes(cf)
    mapping = json.loads((OUT / "id_mapping.json").read_text(encoding="utf-8"))
    kinds = {}
    for entity in mapping["entities"]:
        kinds.setdefault(entity["kind"], []).append(entity["new_id"])
    text = "return {\nmanifest_sha256='"+fingerprint()+"',\n"
    all_jobs=[]
    for raw in (RUN/'data/jobs.txt').read_bytes().splitlines():
        c=raw.split(b'\t')
        if len(c)>=39 and c[2].isdigit():all_jobs.append(int(c[2]))
    text += 'allJobs={'+','.join(str(v) for v in all_jobs)+'},\n'
    for kind, ids in kinds.items():
        text += kind + "={" + ",".join(str(v) for v in sorted(set(ids))) + "},\n"
    text += "maps={" + ",".join("{%d,%d,%d}" % (m["new_id"], m["width"], m["height"]) for m in mapping["maps"]) + "},\n"
    rows = (RUN / "data/itemrecipe.txt").read_bytes().splitlines()
    recipe_skills = {}
    for raw in rows:
        c = raw.split(b"\t")
        if len(c) == 15 and c[1].isdigit() and c[3].isdigit():
            recipe_skills[int(c[1])] = int(c[3])
    text += "recipeSkills={" + ",".join("[%d]=%d" % (r, s) for r, s in recipe_skills.items()) + "},\n}\n"
    (RUN / "lua/shared_native_data.lua").write_text(text, encoding="ascii")
    probe = r'''local D=dofile('lua/shared_native_data.lua')
local constants={}
for k,v in pairs(CONST) do
 if true then
  if type(v)=='number' or type(v)=='string' then constants[k]=v
  elseif type(v)=='table' then
   local t={};for a,b in pairs(v) do if type(b)=='number' or type(b)=='string' then t[a]=b end end
   constants[k]=t
  end
 end
end
local f=assert(io.open('../../../../../docs/cg71_content_audit/shared_integration/native_constants.json','w'));f:write(JSON.encode(constants));f:close()
local result={state='RUNNING',counts={},failures={},production_accounts_used=false,manifest_sha256=D.manifest_sha256}
local path='../../../../../docs/cg71_content_audit/shared_integration/native_result.json'
local function write() local f=assert(io.open(path,'w'));f:write(JSON.encode(result));f:close() end
write()
local function failure(kind,id,detail)
 if #result.failures<10000 then table.insert(result.failures,{kind=kind,id=id,detail=tostring(detail)}) end
end
local ok,why=pcall(function()
 local getters={itemset=Data.ItemsetGetIndex,enemybase=Data.EnemyBaseGetDataIndex,enemy=Data.EnemyGetDataIndex,
   encount=Data.GetEncountIndex,group=Data.GetEncountGroupIndex,jobs=Data.GetJobIndex,
   jobsancestry=Data.GetJobAncestryIndex,skill=Skill.GetSkillIndex,tech=Tech.GetTechIndex}
 for kind,get in pairs(getters) do
  result.counts[kind]=0
  for _,id in ipairs(D[kind] or {}) do
   local ix=get(id)
   if type(ix)~='number' or ix<0 then failure(kind,id,ix) end
   result.counts[kind]=result.counts[kind]+1
  end
 end
 result.counts.maps=0
 for _,m in ipairs(D.maps) do
  local w,h=Map.GetMapSize(0,m[1])
  if w~=m[2] or h~=m[3] then failure('map',m[1],tostring(w)..'x'..tostring(h)) end
  result.counts.maps=result.counts.maps+1
 end
 local p=Char.CreateDummy({mapType=0,floor=1000,x=150,y=111,image=100002,name='SHARED_TASK_VALIDATOR'})
 assert(p>=0,'dummy creation')
 result.dummy={isPlayer=Char.IsPlayer(p),isDummy=Char.IsDummy(p),hp=Char.GetData(p,CONST.CHAR_血),maxhp=Char.GetData(p,CONST.CHAR_最大血)}
 Char.SetData(p,CONST.CHAR_血,1000);Char.SetData(p,CONST.CHAR_最大血,1000);Char.SetData(p,13,1000)
 result.counts.recipes=0
 for _,id in ipairs(D.itemrecipe or {}) do
  local x=Recipe.GiveRecipe(p,id)
  local sid=D.recipeSkills[id]
  if sid and Char.HaveSkill(p,sid)<0 then Char.AddSkill(p,sid,0,0) end
  Recipe.GiveRecipe(p,id)
  if Recipe.HasRecipe(p,id)~=1 then failure('recipe',id,'give='..tostring(x)..',has='..tostring(Recipe.HasRecipe(p,id))) end
  result.counts.recipes=result.counts.recipes+1
 end
 result.flags={}
 result.jobSkillCaps={}
 for _,job in ipairs(D.jobs or {}) do
  local caps={};result.jobSkillCaps[tostring(job)]=caps
  for _,sid in ipairs({0,1,2,3,50,100}) do
   caps[tostring(sid)]=Skill.GetMaxSkillLevelOfJob(Skill.GetSkillIndex(sid),job)
  end
 end
 result.battleParameterProbe={}
 for _,gid in ipairs(D.group or {}) do
  if Data.GetEncountGroupIndex(gid)>=0 and Data.GetEncountIndex(gid)<0 then
   for _,mode in ipairs({0,3}) do
    local arg='3|0,1000,150,111||0|||||'..mode..'|'..gid..'|6|0|'
    local n=NL.CreateArgNpc('StandEnemy',arg,'PARAMETER_VALIDATOR',14073,0,1000,150,110,4)
    local battle=Battle.Encount(p,n,arg)
    local x={group=gid,mode=mode,battle=battle,npc=n,enemies={},slotResults={}}
    if battle>=0 then
     for s=10,19 do
      local enemy=Battle.GetPlayer(battle,s)
      x.slotResults[#x.slotResults+1]=enemy
      if enemy>=0 then x.enemies[#x.enemies+1]=Char.GetData(enemy,CONST.CHAR_名字) end
     end
     Battle.ExitBattle(p)
    end
    if n>=0 then NL.DelNpc(n) end
    result.battleParameterProbe[#result.battleParameterProbe+1]=x
   end
   break
  end
 end
 for _,id in ipairs({256,512,768,1023}) do
  local old=Char.EndEvent(p,id);Char.EndEvent(p,id,1)
  result.flags['end'..id]=Char.EndEvent(p,id)
  if result.flags['end'..id]~=1 then failure('endflag',id,result.flags['end'..id]) end
  Char.EndEvent(p,id,old)
  old=Char.NowEvent(p,id);Char.NowEvent(p,id,1)
  result.flags['now'..id]=Char.NowEvent(p,id)
  if result.flags['now'..id]~=1 then failure('nowflag',id,result.flags['now'..id]) end
  Char.NowEvent(p,id,old)
 end
 assert(Char.DelDummy(p)==0,'dummy cleanup')
end)
if not ok then result.exception=tostring(why) end
result.state=ok and #result.failures==0 and 'PASS' or 'FAIL'
write()
Cron.AddInterval(1000,function()
 local p=Char.CreateDummy({mapType=0,floor=1000,x=150,y=111,image=100002,name='DELAYED_BATTLE_VALIDATOR'})
 local t={dummy=p}
 result.delayedBattleProbe=t
 local ok,why=pcall(function()
  Char.SetData(p,CONST.CHAR_血,1000);Char.SetData(p,CONST.CHAR_最大血,1000);Char.SetData(p,13,1000)
  for _,pos in ipairs({14,15,16,17,18}) do Char.SetData(p,pos,10000) end
  t.before={state=Char.GetData(p,CONST.CHAR_BattleMode),index=Char.GetData(p,CONST.CHAR_BattleIndex),hp=Char.GetData(p,CONST.CHAR_血),maxhp=Char.GetData(p,CONST.CHAR_最大血)}
  t.enemy=D.enemy[1]
  t.returned=Battle.PVE(p,p,nil,{t.enemy},{60},{0})
  t.after={state=Char.GetData(p,CONST.CHAR_BattleMode),index=Char.GetData(p,CONST.CHAR_BattleIndex)}
 end)
 if not ok then t.exception=tostring(why) end
 write()
 Cron.AddInterval(1000,function()
  t.later={state=Char.GetData(p,CONST.CHAR_BattleMode),index=Char.GetData(p,CONST.CHAR_BattleIndex)}
  t.slots={}
  for s=0,19 do t.slots[#t.slots+1]=Battle.GetPlayer(Char.GetData(p,CONST.CHAR_BattleIndex),s) end
  Battle.ExitBattle(p);t.cleaned=Char.DelDummy(p)
  write()
 end,0)
end,0)
'''
    (RUN / "lua/shared_native_probe.lua").write_bytes(probe.encode('gbk'))
    (RUN / "lua/ModuleConfig.lua").write_bytes(probe_config('shared_native_probe.lua'))
    print(json.dumps({"runtime": str(RUN), "port": 19043, "database": "fresh local SQLite; production data.db3 was not copied"}))


def start():
    state = OUT / "native_process.json"
    if state.exists() and json.loads(state.read_text()).get("running"):
        raise SystemExit("stop the existing isolated process first")
    with (OUT / "native_stdout.log").open("wb") as output, (OUT / "native_stderr.log").open("wb") as error:
        process = subprocess.Popen([str(RUN / "cgmsv.exe")], cwd=RUN, stdin=subprocess.DEVNULL,
                                   stdout=output, stderr=error, creationflags=subprocess.CREATE_NO_WINDOW)
    info = {"pid": process.pid, "path": str(RUN / "cgmsv.exe"), "running": True}
    state.write_text(json.dumps(info, indent=2) + "\n")
    print(json.dumps(info))


def stop():
    state = OUT / "native_process.json"
    info = json.loads(state.read_text())
    if not info.get("running"):
        return
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_bool, ctypes.c_uint32]
    kernel.OpenProcess.restype = ctypes.c_void_p
    kernel.QueryFullProcessImageNameW.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_wchar_p, ctypes.POINTER(ctypes.c_uint32)]
    kernel.TerminateProcess.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    kernel.WaitForSingleObject.argtypes=[ctypes.c_void_p,ctypes.c_uint32]
    kernel.WaitForSingleObject.restype=ctypes.c_uint32
    handle = kernel.OpenProcess(0x1000 | 1 | 0x100000, False, info["pid"])
    if handle:
        try:
            buf = ctypes.create_unicode_buffer(32768); size = ctypes.c_uint32(len(buf))
            if not kernel.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size)):
                raise OSError(ctypes.get_last_error())
            if Path(buf.value).resolve() != (RUN / "cgmsv.exe").resolve():
                raise ValueError("PID no longer belongs to this isolated runtime")
            if not kernel.TerminateProcess(handle, 0):
                raise OSError(ctypes.get_last_error())
            if kernel.WaitForSingleObject(handle,10000)!=0:
                raise RuntimeError('isolated process did not finish terminating')
        finally:
            kernel.CloseHandle(handle)
    info["running"] = False
    state.write_text(json.dumps(info, indent=2) + "\n")
    print(json.dumps(info))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["prepare", "start", "stop"])
    globals()[parser.parse_args().mode]()
