local R={status='RUNNING',checks={}}
local p=-1
local originalMessage=NLG.SystemMessage
local messages={}
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};assert(ok,label) end
NLG.SystemMessage=function(q,text,...) if q==p then messages[#messages+1]=text end;return originalMessage(q,text,...) end
local function send(msg)
 messages={};check(TalkEvent(p,msg,0,0,0)==0,'consumed '..msg)
 return table.concat(messages,'\n')
end
local ok,err=xpcall(function()
 p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='FAME_NATIVE_TEST'})
 check(p>=0,'isolated player created')
 Char.SetData(p,CONST['对象_GM'],0)
 local key=assert(CONST['CHAR_声望'])
 for _,value in ipairs({0,10000,60000}) do
  Char.SetData(p,key,value)
  for _,cmd in ipairs({'/fame','/FAME','/声望'}) do
   check(send(cmd)=='当前声望：'..value..'。','native fame '..cmd..'/'..value)
   check(Char.GetData(p,key)==value,'fame unchanged '..cmd)
  end
 end
 for _,cmd in ipairs({'/fame 1','/声望 extra'}) do check(send(cmd):find('用法',1,true)~=nil,'reject parameters '..cmd) end
 for _,cmd in ipairs({'/fame!','/famex','/声望!','/声望值','ordinary chat','/help!'}) do check(TalkEvent(p,cmd,0,0,0)==1,'unrelated chat '..cmd) end
 for _,cmd in ipairs({'/help fame','/help 声望'}) do check(send(cmd):find('maxfame',1,true)~=nil,'help '..cmd) end
 Char.SetData(p,CONST['CHAR_BattleMode'],1)
 check(send('/声望')=='当前声望：60000。','query in battle mode')
 Char.SetData(p,CONST['CHAR_BattleMode'],0)
 CharaStallStartEvent(p)
 check(send('/fame')=='当前声望：60000。','query during stall')
 CharaStallEndEvent(p)
 check(reloadModule('gameQoL')~=nil,'hot reload')
 check(send('/声望')=='当前声望：60000。','alias after hot reload')
 local originalOpen=io.open
 local function withConfig(content,body)
  io.open=function(path,mode)
   if path=='cgmsv.cf' then
    if content==false then return nil end
    return {lines=function() return content:gmatch('[^\n]+') end,close=function() end}
   end
   return originalOpen(path,mode)
  end
  local success,failure=xpcall(body,debug.traceback)
  io.open=originalOpen
  assert(success,failure)
 end
 local file=assert(io.open('cgmsv.cf','rb'));local maximum
 for line in file:lines() do local value=line:match('^%s*maxfame%s*=%s*(%d+)%s*$');if value then maximum=tonumber(value);break end end
 file:close();check(maximum~=nil,'native maxfame config')
 for _,cmd in ipairs({'/fame max','/声望 max','/FAME MAX'}) do
  Char.SetData(p,key,123)
  check(send(cmd)=='声望已设为配置上限：'..maximum..'。','set configured max '..cmd)
  check(Char.GetData(p,key)==maximum,'native max readback '..cmd)
 end
 withConfig('maxfame=12345\r\n',function()
  send('/fame max');check(Char.GetData(p,key)==12345,'reads changed configuration without reload')
 end)
 for _,config in ipairs({false,'minfame=-2000\n','maxfame=oops\n','maxfame=-1\n','maxfame=0\n','maxfame=2147483648\n'}) do
  withConfig(config,function()
   check(send('/fame max'):find('无法读取声望上限',1,true)~=nil,'invalid config explained '..tostring(config))
   check(Char.GetData(p,key)==12345,'invalid config leaves fame unchanged')
  end)
 end
 for _,cmd in ipairs({'/fame 999','/fame max 1','/声望 max extra'}) do
  check(send(cmd):find('用法',1,true)~=nil,'invalid max parameters '..cmd)
  check(Char.GetData(p,key)==12345,'invalid parameters leave fame unchanged')
 end
 R.status='PASS'
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err) end
NLG.SystemMessage=originalMessage
if p>=0 then pcall(Char.DelDummy,p) end
local f=assert(io.open('__OUTPUT__/fame_native.json','wb'));f:write(JSON.encode(R));f:close()
