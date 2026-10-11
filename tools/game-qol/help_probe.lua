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
 text=send('/help petbp')
 check(contains(text,'/petbp bank 0~4|all'),'bank petbp usage visible in detail')
 check(contains(text:gsub('\n',''),'/petbp bank all 仅查看银行'),'bank-only example visible in detail')
 text=send('/help fivepet')
 check(contains(text:gsub('\n',''),'人物倒下立即结束战斗'),'long five-pet detail preserved')
 local petDetail=text:gsub('\n','')
 check(contains(petDetail,'主宠、随身参战伙伴及银行参战伙伴'),'pet strengthening covers every participating pet in help')
 check(contains(petDetail,'LV10加40%、LV30加80%'),'pet strengthening DATA levels visible in help')
 check(contains(petDetail,'仅收录技能库不生效，卸下后停止，人物经验不加成'),'pet strengthening activation limits visible in help')
 R.samples.pet_strengthening=petDetail:match('装配宠物强化.-正常一人一宠也生效；')
 check(contains(petDetail,'所有自动参战的随身宠物与银行伙伴默认开启智能战斗'),'default intelligent combat visible in help')
 check(contains(petDetail,'假人替身每回合只行动一次') and contains(petDetail,'不追加第二行动'),'single-action proxy rule visible in GBK help')
 check(not contains(petDetail,'第二行动回复或防御') and not contains(petDetail,'普通护卫第二行动'),'obsolete double-action guard help removed')
 check(contains(petDetail,'最近两回合') and contains(petDetail,'本回合及下一回合结束生命'),'actual damage forecast visible in GBK help')
 check(contains(petDetail,'Boss 遮挡只用于保护安全目标') and contains(petDetail,'不强制前排防御'),'adaptive Boss safety visible in help')
 check(contains(petDetail,'Boss战也不接管主宠') and not contains(petDetail,'主宠自动防御') and not contains(petDetail,'含主宠'),'main pet remains manual even in Boss defense help')
 check(contains(petDetail,'能撑过两回合时优先降低敌方生命') and contains(petDetail,'避免让会倒下的宠物护卫别人'),'survival first and damage priority visible in help')
 check(contains(petDetail,'圣殿38,18宠物技能升级师') and contains(petDetail,'每技能每提升一级1000魔币'),'paid pet upgrade service and price visible in help')
 check(contains(petDetail,'菜单第一项升级所有宠物（随身＋银行）') and contains(petDetail,'随身五栏和银行五栏'),'all-pets bulk option and full ten-slot scope visible in help')
 check(contains(petDetail,'一次扣费并保存') and contains(petDetail,'恢复全部宠物原技能并退还总费用'),'bulk one payment/save and complete rollback visible in help')
 check(contains(petDetail,'宠物诸刃与乾坤一掷普通Ⅰ~Ⅹ') and contains(petDetail,'补齐Ⅵ~Ⅹ'),'complete pet physical ranks visible in GBK help')
 check(contains(petDetail,'耗魔110/130/150/170/190') and contains(petDetail,'Ⅴ升Ⅹ收5000魔币'),'pet physical MP and upgrade fee visible in help')
 check(contains(petDetail,'新增DATA须保存角色并正常重启服务端'),'pet physical DATA activation visible in help')
 check(not contains(petDetail,'/strategy'),'automatic tactics do not advertise a manual command')
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
