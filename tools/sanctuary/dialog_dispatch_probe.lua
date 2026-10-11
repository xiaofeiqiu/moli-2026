-- Exercise native NPC dispatch, rather than calling Lua menu handlers directly.
local R={status='RUNNING',checks={},npcs={},production_accounts_used=false,client_click_verified=false}
local p=-1
local function write() local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close() end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
local function get(n,k) return Char.GetData(n,CONST[k]) end
local windows={}
local show=NLG.ShowWindowTalked
NLG.ShowWindowTalked=function(player,npc,kind,buttons,seq,data)
 windows[#windows+1]={player=player,npc=npc,kind=kind,seq=seq,data=data}
 return show(player,npc,kind,buttons,seq,data)
end
local function inspect(stage)
 for _,name in ipairs({'skillTraining','cg71JobSkills','fivePet','skillLibrary','knightHybridGear','autoStat','sanctuary','petSkillTutor','petSkillUpgrade','sanctuaryShops','petEquipment','equipmentEnhance'}) do
  local m=assert(getModule(name),name)
  for _,n in ipairs(m.npcList) do if get(n,'CHAR_地图')==60003 then
   local label=stage..' '..get(n,'CHAR_名字')
   check(Char.Warp(p,0,60003,get(n,'CHAR_X'),get(n,'CHAR_Y')+1),'approach '..label)
   local allowed=false
   for d=0,7 do
    Char.SetData(p,CONST.CHAR_方向,d)
    local ret=NLG.CanTalk(n,p)
    if ret==true or ret==1 then allowed=true;break end
   end
   check(allowed,'native talk range '..label)
   windows={}
   -- ShowTalked supplies only two C arguments and cannot safely call the
   -- five-argument Lua Talked trampoline in this server build.
   local ret
   local handler=_G[name..'_npc_'..n..'_TalkedEvent']
   if type(handler)=='function' then
    handler(n,p,'',0,0);ret=1
   else
    check(NLG.GetArgNpc(n)~='','native argument NPC '..label)
    ret=NLG.ShowTalked(n,p)
   end
   R.npcs[#R.npcs+1]={stage=stage,name=get(n,'CHAR_名字'),module=name,index=n,result=ret,windows=#windows}
   check(ret==1,'dialogue dispatch succeeds '..label..' result='..tostring(ret))
   if type(handler)=='function' then check(#windows>0 or get(p,'CHAR_地图')~=60003,'Lua callback opens dialogue or portal '..label) end
  end end
 end
end
Cron.AddInterval(1500,function()
 local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=60003,x=30,y=38,image=100002,name='DIALOG_DISPATCH_PROBE'})
  check(p>=0,'isolated player')
  local oldMapPlayer=NLG.GetMapPlayer
  NLG.GetMapPlayer=function() return {p} end
  local x,y,battle=get(p,'CHAR_X'),get(p,'CHAR_Y'),Char.GetBattleIndex(p)
  local diagnosed,diagnosis=pcall(dofile,'lua/sanctuaryDiagnose.lua')
  NLG.GetMapPlayer=oldMapPlayer
  check(diagnosed,'diagnostic script executes '..tostring(diagnosis))
  check(diagnosis.npcs==93 and diagnosis.missing==0 and diagnosis.players==1,'diagnostic finds current callbacks and player')
  check(get(p,'CHAR_X')==x and get(p,'CHAR_Y')==y and Char.GetBattleIndex(p)==battle,'diagnostic preserves player state')
  inspect('startup')
  for i=1,3 do
   check(reloadModule('sanctuaryShops')~=nil,'merchant reload '..i)
   inspect('merchant reload '..i)
  end
  local all=reloadAllModules()
  check(not all.aborted and #all.failed==0 and all.succeeded==all.total,'full reload succeeds')
  inspect('full reload')
 end,debug.traceback)
 NLG.ShowWindowTalked=show
 if p>=0 then Char.DelDummy(p) end
 R.status=ok and 'PASS' or 'FAIL';R.error=not ok and tostring(err) or nil;write()
end,0)
