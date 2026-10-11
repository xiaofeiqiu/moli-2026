local R={status='RUNNING',checks={},samples={}}
local player=-1
local originalMessage=NLG.SystemMessage
local captured={}
local function check(ok,label)
 R.checks[#R.checks+1]={name=label,pass=ok and true or false};assert(ok,label)
end
local function contains(text,needle) return text:find(needle,1,true)~=nil end
local function send(command)
 captured={}
 check(TalkEvent(player,command,0,0,0)==0,'consumed '..command)
 for _,line in ipairs(captured) do
  check(#line<=120,'bounded chat entry '..command)
  local pos=1
  while pos<=#line do pos=pos+(line:byte(pos)>=128 and 2 or 1) end
  check(pos==#line+1,'complete GBK characters '..command)
 end
 return table.concat(captured,'\n')
end
NLG.SystemMessage=function(p,text,...)
 if p==player then captured[#captured+1]=text end
 return originalMessage(p,text,...)
end
local ok,err=xpcall(function()
 local M=assert(getModule('gameQoL'))
 local H=dofile('lua/Modules/commandHelp.lua')
 check(M.configs~=nil,'QoL onLoad completed')
 player=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='HELP_NATIVE_TEST'})
 check(player>=0 and Char.IsPlayer(player),'native test player created')
 check(getModule('gameDifficulty'):preference(player)==6,'unset character defaults to tier 6')
 Char.SetData(player,CONST.CHAR_CDK,'HELP_NATIVE_TEST')
 Char.SetData(player,CONST['对象_GM'],0)
 check(not H:isAdmin(player),'ordinary player permissions')
 local text=send('/help');R.samples.player=text
 for _,group in ipairs(H:playerGroups()) do for _,row in ipairs(group.entries) do
  check(contains(text,row.usage),'default help usage '..row.usage)
 end end
 check(contains(text,'/skillbook') and contains(text,'/技能库'),'skillbook aliases visible')
 check(contains(text,'/fivepet on|off'),'five pet command visible')
 check(contains(text,'/difficulty') and contains(text,'/难度'),'difficulty aliases visible')
 check(contains(send('/help difficulty'),'默认 6 深渊'),'actual default difficulty visible in detail')
 text=send('/help fivepet')
 check(contains(text:gsub('\n',''),'人物倒下立即结束战斗'),'long five-pet detail preserved')
 check(not contains(text,'/addGold'),'ordinary help excludes GM commands')
 check(contains(send('/help difficulty'),'下场 PvE'),'difficulty details include activation rule')
 check(contains(send('/HELP /BAG'),'背包；页码 0~'..CONST.EXTBAGPAGE),'case-insensitive help and bag alias')
 check(contains(send('/help 技能库'),'/skillbook'),'Chinese alias query works')
 check(contains(send('/help 难度'),'/difficulty'),'Chinese difficulty query works')
 check(contains(send('/help gm'),'管理员权限'),'GM list denied for ordinary player')
 check(not contains(send('/help addGold'),'/addGold'),'GM single command denied for ordinary player')
 check(contains(send('/help missingCommand'),'未找到'),'unknown command explained')
 check(contains(send('/help difficulty extra'),'用法：/help'),'extra help arguments rejected')
 check(TalkEvent(player,'ordinary chat',0,0,0)==1,'ordinary chat unchanged')
 check(TalkEvent(player,'/help!',0,0,0)==1,'invalid command suffix unchanged')
 local page=Char.GetBagPage(player)
 check(contains(send('/help bag'),'/bag') and Char.GetBagPage(player)==page,'help query does not execute bag command')
 Char.SetData(player,CONST['对象_GM'],1)
 check(H:isAdmin(player),'native GM flag respected')
 text=send('/help gm');R.samples.gm=text
 for _,group in ipairs(H:gmGroups()) do for _,row in ipairs(group.entries) do
  check(contains(text,row.usage),'GM help usage '..row.usage)
 end end
 check(contains(send('/help giveItem'),'鉴定状态'),'GM command parameter query works')
 local adminCommands=assert(getModule('adminCommands'))
 adminCommands:regCommand('helpExtensionTest',function() error('help must not execute command') end)
 check(contains(send('/help gm'),'/helpExtensionTest'),'new registered GM command automatically listed')
 check(contains(send('/help helpExtensionTest'),'/helpExtensionTest'),'new registered GM command query works')
 adminCommands:unloadCommand('helpExtensionTest')
 check(not contains(send('/help gm'),'/helpExtensionTest'),'unregistered GM command removed')
 unloadModule('gameDifficulty')
 check(not contains(send('/help'),'/difficulty'),'unloaded module hidden from help')
 check(contains(send('/help difficulty'),'未找到'),'unloaded command query hidden')
 check(loadModule('gameDifficulty')~=nil,'difficulty module reloaded')
 check(contains(send('/help'),'/difficulty'),'reloaded module appears without reloading help')
 check(reloadModule('gameQoL')~=nil,'QoL hot reload succeeds')
 check(contains(send('/help 技能库'),'/skillbook'),'help survives QoL hot reload')
 R.status='PASS'
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err) end
NLG.SystemMessage=originalMessage
if player>=0 then pcall(Char.DelDummy,player) end
local file=assert(io.open('__OUTPUT__/help_native.json','wb'));file:write(JSON.encode(R));file:close()
