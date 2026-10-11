-- Read-only diagnostics, invoked with the existing GM /dofile command.
local lines={}
local function add(s) lines[#lines+1]=s;print('[SanctuaryDiag] '..s) end
local function get(p,k) local field=assert(CONST[k],k);return Char.GetData(p,field) end
local modules={'skillTraining','cg71JobSkills','fivePet','skillLibrary','knightHybridGear','autoStat','sanctuary','petSkillTutor','petSkillUpgrade','sanctuaryShops','petEquipment'}
add('圣殿对话诊断：只读取状态，不修改NPC、角色或存档。')
local total,missing=0,0
local npcs={}
for _,name in ipairs(modules) do
 local m=getModule(name)
 if not m then add(name..'：未加载')
 else
  local count,bad=0,0
  for _,n in ipairs(m.npcList or {}) do
   local ok,floor=pcall(get,n,'CHAR_地图')
   if ok and floor==60003 then
    count=count+1;total=total+1;npcs[#npcs+1]=n
    -- These two modules use C merchants, without a Lua Talked handler.
    if name~='sanctuaryShops' and name~='knightHybridGear' then
     local key=name..'_npc_'..n..'_TalkedEvent'
     if type(_G[key])~='function' then
      bad=bad+1;missing=missing+1
      add('缺少Lua对话回调：'..get(n,'CHAR_名字')..' '..key)
     end
    end
   end
  end
  add(name..'：圣殿NPC='..count..'，缺失Lua回调='..bad)
 end
end
add('总计NPC='..total..'，缺失Lua回调='..missing..'；原生商店C指针未检查。')
local players,list=NLG.GetMapPlayer(0,60003)
if type(players)~='table' then players=list end
players=type(players)=='table' and players or {}
add('圣殿在线角色='..#players)
local qol=getModule('gameQoL')
local five=getModule('fivePet')
for i,p in ipairs(players) do
 local x,y=get(p,'CHAR_X'),get(p,'CHAR_Y')
 local near,allowed=0,0
 for _,n in ipairs(npcs) do
  if math.abs(x-get(n,'CHAR_X'))<=2 and math.abs(y-get(n,'CHAR_Y'))<=2 then
   near=near+1
   local ok,result=pcall(NLG.CanTalk,n,p)
   if ok and (result==true or result==1) then allowed=allowed+1 end
  end
 end
 add(string.format('角色%d：位置=%d,%d，方向=%d，战斗编号=%d，战斗模式=%d，摆摊=%s，附近NPC=%d，可对话=%d',
  i,x,y,get(p,'CHAR_方向'),Char.GetBattleIndex(p),get(p,'CHAR_BattleMode'),
  tostring(not not (qol and qol.stalls and qol.stalls[p])),near,allowed))
 if five and five.active then add('角色'..i..'：五宠会话='..tostring(five.active[p]~=nil)) end
end
local path='dump/sanctuary_dialog_diagnosis.txt'
local f=io.open(path,'wb')
if f then f:write(table.concat(lines,'\r\n')..'\r\n');f:close();print('[SanctuaryDiag] report='..path) end
return {npcs=total,missing=missing,players=#players,lines=lines}
