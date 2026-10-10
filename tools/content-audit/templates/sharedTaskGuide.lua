local M=ModuleBase:createModule('sharedTaskGuide')
local D=dofile('lua/Modules/sharedTaskGuideData.lua')
local PAGE=6
local function get(p,key) local field=assert(CONST[key],key);return Char.GetData(p,field) end
function M:near(n,p)
 return Char.IsPlayer(p) and Char.GetBattleIndex(p)<0
  and get(n,'CHAR_地图')==get(p,'CHAR_地图') and get(n,'CHAR_地图类型')==get(p,'CHAR_地图类型')
  and math.abs(get(n,'CHAR_X')-get(p,'CHAR_X'))<=3 and math.abs(get(n,'CHAR_Y')-get(p,'CHAR_Y'))<=3
end
function M:show(n,p,page,task,scenePage)
 if not self:near(n,p) then return end
 local options,actions={},{}
 local function add(text,action) options[#options+1]=text;actions[#actions+1]=action end
 local title='共享任务向导'
 if task then
  local t=D.tasks[task];if not t then return end
  title=t.name
  if t.entry then add('前往任务接待地点',{kind='warp',position=t.entry}) end
  scenePage=scenePage or 1
  local first=(scenePage-1)*4+1
  for i=first,math.min(#t.scenes,first+3) do
   local s=t.scenes[i];add('场景：'..s.name,{kind=t.entry and 'info' or 'warp',position=s})
  end
  if scenePage>1 then add('上一页场景',{kind='task',task=task,page=page,scenePage=scenePage-1}) end
  if first+4<=#t.scenes then add('下一页场景',{kind='task',task=task,page=page,scenePage=scenePage+1}) end
  add('返回任务目录',{kind='list',page=page})
 else
  local start=(page-1)*PAGE+1
  for i=start,math.min(start+PAGE-1,#D.tasks) do add(D.tasks[i].name,{kind='task',task=i,page=page}) end
  if page>1 then add('上一页',{kind='list',page=page-1}) end
  if start+PAGE<=#D.tasks then add('下一页',{kind='list',page=page+1}) end
 end
 self.sessions[p]={npc=n,expires=os.time()+90,actions=actions,page=page}
 NLG.ShowWindowTalked(p,n,2,2,7291,self:NPC_buildSelectionText(title,options))
end
function M:answer(n,p,seq,button,data)
 local s=self.sessions[p];self.sessions[p]=nil
 if not s or s.npc~=n or seq~=7291 or s.expires<os.time() or not self:near(n,p) then return end
 local a=s.actions[tonumber(data) or 0];if not a then return end
 if a.kind=='list' then self:show(n,p,a.page)
 elseif a.kind=='task' then self:show(n,p,a.page,a.task,a.scenePage)
 elseif a.kind=='info' then NLG.SystemMessage(p,'场景：'..a.position.name..'。请通过任务中的 NPC 和传送路线前往。')
 elseif a.kind=='warp' then
  if Char.PartyNum(p)>1 then NLG.SystemMessage(p,'请先解散队伍，再选择任务入口。');return end
  local v=a.position;local w,h=Map.GetMapSize(0,v.floor)
  if not w or w<1 then NLG.SystemMessage(p,'该区域尚未载入，请正常重启服务端后再来。');return end
  local x,y
  if v.x and v.y then
   for radius=1,4 do
    for dx=-radius,radius do for dy=-radius,radius do
     local xx,yy=v.x+dx,v.y+dy
     if not x and xx>=0 and xx<w and yy>=0 and yy<h and Map.IsWalkable(0,v.floor,xx,yy)==1 then x,y=xx,yy end
    end end
    if x then break end
   end
  end
  if not x then x,y=Map.GetAvailablePos(0,v.floor) end
  if not x or x<0 then NLG.SystemMessage(p,'此处没有可用的落脚位置。');return end
  if Char.Warp(p,0,v.floor,x,y) then NLG.SystemMessage(p,'已抵达 '..v.name..'。任务的等级、道具和前置要求由接待 NPC 检查。') end
 end
end
function M:onLoad()
 self.sessions={}
 local n=self:NPC_createNormal('共享任务向导',14058,{mapType=0,map=1000,x=155,y=112,direction=4})
 assert(n>=0,'shared task guide creation failed')
 self.guide=n
 self:NPC_regTalkedEvent(n,function(n,p) self:show(n,p,1) end)
 self:NPC_regWindowTalkedEvent(n,Func.bind(self.answer,self))
 self:regCallback('LogoutEvent',function(p) self.sessions[p]=nil end)
 self:logInfo('Loaded shared task catalogue: '..#D.tasks)
end
function M:onUnload() self.sessions={} end
return M
