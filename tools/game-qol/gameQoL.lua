---@class GameQoL:ModuleType
local M=ModuleBase:createModule('gameQoL')
local D=dofile('lua/Modules/gameQoLData.lua')
local SIZE=20
local PREF='GameQoL_v1_'
local CONFIG_KEY='GameQoLConfigV1'
local DEFAULT={autostack=true,autosort=false,autoidentify=true,autosell=true,autoclock=true}
local COMMANDS={backpack=true,bag=true,sort=true,stack=true,identify=true,sellstones=true,
 autostack=true,autosort=true,autoidentify=true,autosell=true,autoclock=true,clock=true,
 petmax=true,petbp=true,where=true,qol=true,help=true}
local ART={CONST['宠档_体成'],CONST['宠档_力成'],CONST['宠档_强成'],CONST['宠档_敏成'],CONST['宠档_魔成']}

local function num(p,key) return tonumber(Char.GetData(p,CONST[key])) or 0 end
local function idata(i,key) return Item.GetData(i,CONST[key]) end
local function valid(p) return type(p)=='number' and p>=0 and Char.IsValidCharIndex(p) and Char.IsPlayer(p) end
local function message(p,text) NLG.SystemMessage(p,text) end
local function integer(s,lo,hi)
 if not s or not s:match('^%d+$') then return nil end
 local n=tonumber(s);if n and n>=lo and n<=hi then return n end
end
local function pageRange(p,page)
 local first=8+page*SIZE
 return first,math.min(first+SIZE-1,num(p,'CHAR_道具栏')-1)
end

function M:settings(p)
 local account=Char.GetData(p,CONST['CHAR_账号'])
 local reg=Char.GetData(p,CONST['对象_RegistNumber'])
 local identity=tostring(account)..':'..tostring(reg)
 local cached=self.configs[p]
 if cached and cached.identity==identity then return cached.values end
 local result={}
 for key,default in pairs(DEFAULT) do
  local value=Char.GetExtData(p,PREF..key)
  result[key]=value==nil and default or tostring(value)=='1'
 end
 if account and account~='' then
  local sql=SQL.QueryEx('SELECT val FROM hook_charaext WHERE cdKey=? AND regNo=? AND sKey=?',account,reg,CONFIG_KEY)
  if sql.status~=0 then return nil end
  if sql.rows and sql.rows[1] then
   local ok,saved=pcall(JSON.decode,sql.rows[1].val)
   if not ok or type(saved)~='table' or saved.version~=1 then return nil end
   for key in pairs(DEFAULT) do if type(saved[key])=='boolean' then result[key]=saved[key] end end
  end
 end
 self.configs[p]={identity=identity,values=result}
 return result
end

function M:saveSettings(p,values)
 local account=Char.GetData(p,CONST['CHAR_账号'])
 local reg=Char.GetData(p,CONST['对象_RegistNumber'])
 local saved={version=1};for key in pairs(DEFAULT) do saved[key]=values[key] end
 local raw=JSON.encode(saved)
 if account and account~='' then
  local sql=SQL.QueryEx('REPLACE INTO hook_charaext(cdKey,regNo,sKey,val,valType) VALUES(?,?,?,?,?)',account,reg,CONFIG_KEY,raw,0)
  if sql.status~=0 or sql.effectRows<1 then return false end
 end
 Char.SetExtData(p,CONFIG_KEY,raw)
 for key in pairs(DEFAULT) do Char.SetExtData(p,PREF..key,values[key] and 1 or 0) end
 self.configs[p]={identity=tostring(account)..':'..tostring(reg),values=values}
 return true
end

function M:setSetting(p,key,value)
 local cfg=self:settings(p)
 if not cfg then message(p,'自动功能设置暂时无法读取，请稍后重试。');return false end
 local updated={};for k,v in pairs(cfg) do updated[k]=v end;updated[key]=value
 if not self:saveSettings(p,updated) then message(p,'自动功能设置保存失败，请稍后重试。');return false end
 return true
end

function M:ready(p,quiet)
 if not valid(p) then return false end
 if num(p,'CHAR_BattleMode')~=0 or Char.GetBattleIndex(p)~=-1 or self.stalls[p] then
  if not quiet then message(p,'战斗或摆摊期间无法操作背包和宠物。') end
  return false
 end
 return true
end

function M:expandBags(p)
 local capacity=8+(CONST.EXTBAGPAGE+1)*SIZE
 local old=num(p,'CHAR_道具栏')
 if old>=28 and old<capacity then Char.SetData(p,CONST['CHAR_道具栏'],capacity) end
end

function M:normalize(i)
 if D.stackIds[idata(i,'道具_ID')] then
  if idata(i,'道具_最大堆叠数')<D.stackLimit then Item.SetData(i,CONST['道具_最大堆叠数'],D.stackLimit) end
 end
end

-- Never merge different durability, prices, stamps, quest parameters, or expiry.
-- Creation time alone does not make otherwise identical consumables different.
function M:sameStack(a,b)
 if a<0 or b<0 or idata(a,'道具_最大堆叠数')<=1 or idata(b,'道具_最大堆叠数')<=1 then return false end
 for k=0,78 do
  if k~=9 and k~=67 and Item.GetData(a,k)~=Item.GetData(b,k) then return false end
 end
 for _,key in ipairs({'道具_鉴前名','道具_名字','道具_刻印','道具_自用参数','道具_刻印玩家',
  '道具_INITFUNC','道具_WATCHFUNC','道具_USEFUNC','道具_ATTACHFUNC','道具_DETACHFUNC',
  '道具_DROPFUNC','道具_PREPICKUPFUNC','道具_PICKUPFUNC'}) do
  if CONST[key] and idata(a,key)~=idata(b,key) then return false end
 end
 return true
end

function M:mergePage(p,page)
 local first,last=pageRange(p,page)
 local merged=0
 for target=first,last do
  local a=Char.GetItemIndex(p,target)
  if a>=0 then
   self:normalize(a)
   for source=target+1,last do
    local b=Char.GetItemIndex(p,source)
    if b>=0 then
     self:normalize(b)
     if self:sameStack(a,b) then
      local count=idata(a,'道具_堆叠数')
      local amount=math.min(idata(a,'道具_最大堆叠数')-count,idata(b,'道具_堆叠数'))
      if amount>0 and Char.MoveItem(p,source,target,amount)==1 then merged=merged+amount end
     end
    end
   end
  end
 end
 return merged
end

function M:sortPage(p,page)
 self:mergePage(p,page)
 local first,last=pageRange(p,page)
 local list={}
 for slot=first,last do
  local i=Char.GetItemIndex(p,slot)
  if i>=0 then list[#list+1]={index=i,type=idata(i,'道具_类型'),id=idata(i,'道具_ID'),slot=slot} end
 end
 table.sort(list,function(a,b)
  if a.type~=b.type then return a.type<b.type end
  if a.id~=b.id then return a.id<b.id end
  return a.slot<b.slot
 end)
 for pos,row in ipairs(list) do
  local target=first+pos-1
  if Char.GetItemIndex(p,target)~=row.index then
   local source=-1
   for slot=target+1,last do if Char.GetItemIndex(p,slot)==row.index then source=slot;break end end
   if source>=0 then
    -- Full stacks of the same ID must swap, not merge and destroy list indices.
    -- SetItemIndex only changes slot references; preserve both original objects.
    local other=Char.GetItemIndex(p,target)
    Char.SetItemIndex(p,source,-1);Char.SetItemIndex(p,target,-1)
    Char.SetItemIndex(p,target,row.index)
    if other>=0 then Char.SetItemIndex(p,source,other) end
   end
  end
 end
 Item.UpItem(p,-1)
 return #list
end

function M:identify(p)
 local count=0
 for slot=8,num(p,'CHAR_道具栏')-1 do
  local i=Char.GetItemIndex(p,slot)
  if i>=0 and idata(i,'道具_已鉴定')==0 then
   if Item.SetData(i,CONST['道具_已鉴定'],1)==1 then count=count+1 end
  end
 end
 if count>0 then Item.UpItem(p,-1) end
 return count
end

function M:sellStones(p)
 local count,gold,full=0,0,false
 for slot=8,num(p,'CHAR_道具栏')-1 do
  local i=Char.GetItemIndex(p,slot)
  -- Exact native magic-stone ID: similarly named gems and quest items stay put.
  if i>=0 and D.stoneIds[idata(i,'道具_ID')] and idata(i,'道具_已鉴定')==1 then
   local unit=math.floor(tonumber(idata(i,'道具_价格')) or 0)
   local amount=idata(i,'道具_堆叠数')
   local price=unit*amount
   if price>0 and amount>0 then
    if Char.GetGold(p)+price>D.goldLimit then full=true
    else
     local before=Char.GetGold(p)
     Char.AddGold(p,price)
     local credited=Char.GetGold(p)-before
     if credited==price and Item.Kill(p,i,slot)==1 then count=count+amount;gold=gold+price
     elseif credited~=0 then Char.AddGold(p,-credited) end
    end
   end
  end
 end
 return count,gold,full
end

function M:startClock(p)
 if Char.IsFeverTime(p)==1 then return true end
 if num(p,'CHAR_卡时')<=0 then return false end
 return Char.FeverStart(p)==1
end

function M:maintain(p)
 if not self:ready(p,true) then return end
 self:expandBags(p)
 local cfg=self:settings(p)
 if not cfg then return end
 local identified=cfg.autoidentify and self:identify(p) or 0
 local sold,gold,full=0,0,false
 if cfg.autosell then sold,gold,full=self:sellStones(p) end
 -- Inventory signatures keep the periodic task from reordering unchanged bags.
 local parts={}
 for slot=8,num(p,'CHAR_道具栏')-1 do
  local i=Char.GetItemIndex(p,slot)
  if i>=0 then self:normalize(i);parts[#parts+1]=slot..':'..i..':'..idata(i,'道具_堆叠数') end
 end
 local signature=table.concat(parts,';')
 if self.signatures[p]~=signature then
  for page=0,CONST.EXTBAGPAGE do
   if cfg.autosort then self:sortPage(p,page)
   elseif cfg.autostack then self:mergePage(p,page) end
  end
  self.signatures[p]=signature
 end
 if cfg.autoclock then self:startClock(p) end
 if identified>0 then message(p,'自动鉴定完成：'..identified..' 件。') end
 if sold>0 then message(p,'自动出售魔石 '..sold..' 个，获得 '..gold..' 金币。') end
 if full and not self.goldFull[p] then message(p,'金币接近携带上限，剩余魔石已保留。') end
 self.goldFull[p]=full
end

function M:petRanks(p,slot,fill)
 local pet=Char.GetPet(p,slot)
 if pet<0 or not Char.IsPet(pet) then message(p,'宠物栏 '..slot..' 没有宠物。');return false end
 local ranks={}
 -- Validate all five species values before making the first change.
 for n,art in ipairs(ART) do
  local current,full=Pet.GetArtRank(pet,art),Pet.FullArtRank(pet,art)
  if type(full)~='number' or full<=0 or type(current)~='number' or current<0 then
   message(p,'此宠物没有有效的种族成长数据，无法处理。');return false
  end
  ranks[n]={current=current,full=full,art=art}
 end
 local loss=0
 for _,r in ipairs(ranks) do
  loss=loss+math.max(0,r.full-r.current)
  if fill and r.current<r.full then Pet.SetArtRank(pet,r.art,r.full) end
 end
 if fill then
  Pet.UpPet(p,pet)
  message(p,'宠物栏 '..slot..' 已补满成长档数（补回 '..loss..' 档），等级和已加点保留，后续升级按满档成长。')
 else
  local text={};for _,r in ipairs(ranks) do text[#text+1]=r.current..'/'..r.full end
  message(p,'宠物栏 '..slot..'：体/力/强/敏/魔 '..table.concat(text,' ')..'，总掉档 '..loss..'。')
 end
 return true
end

function M:help(p)
 message(p,'/backpack 0~3 切换背包；/backpack 查看各页；/sort [all] 整理；/stack [all] 合并。')
 message(p,'/identify 鉴定所有背包；/sellstones 卖魔石；/petmax 0~4|all 满档；/petbp 0~4|all 查看档数。')
 message(p,'/autoidentify、/autosell、/autostack、/autosort、/autoclock on|off 开关；/clock on|off 打卡。')
 message(p,'/qol 查看自动功能；/where 查看位置；/fight 原地遇敌；背包和宠物编号均从 0 开始。')
end

function M:handleTalk(p,msg)
 if type(msg)~='string' then return 1 end
 local command,tail=msg:match('^/([%w]+)(.*)$')
 command=command and command:lower()
 if not COMMANDS[command] then return 1 end
 if tail~='' and not tail:match('^%s') then return 1 end
 local args={};for arg in tail:gmatch('%S+') do args[#args+1]=arg:lower() end
 if not valid(p) then return 0 end
 self:expandBags(p)
 if command=='help' then self:help(p);return 0 end
 if command=='qol' then
  local cfg=self:settings(p);local list={}
  if not cfg then message(p,'自动功能设置暂时无法读取，请稍后重试。');return 0 end
  for _,key in ipairs({'autostack','autosort','autoidentify','autosell','autoclock'}) do list[#list+1]=key..'='..(cfg[key] and 'on' or 'off') end
  message(p,table.concat(list,' '));message(p,'打卡='..(Char.IsFeverTime(p)==1 and 'on' or 'off')..'，剩余卡时 '..math.floor(num(p,'CHAR_卡时')/60)..' 分钟。');return 0
 end
 if command=='where' then
  message(p,'地图 '..num(p,'CHAR_地图')..'，类型 '..num(p,'CHAR_地图类型')..'，坐标 '..num(p,'CHAR_X')..','..num(p,'CHAR_Y'));return 0
 end
 if DEFAULT[command]~=nil then
  if #args~=1 or (args[1]~='on' and args[1]~='off') then message(p,'用法：/'..command..' on|off');return 0 end
  if not self:setSetting(p,command,args[1]=='on') then return 0 end
  self.signatures[p]=nil
  if command=='autoclock' and args[1]=='off' then Char.FeverStop(p) end
  message(p,command..' 已'..(args[1]=='on' and '开启。' or '关闭。'))
  if args[1]=='on' then self:maintain(p) end
  return 0
 end
 if not self:ready(p,false) then return 0 end
 if command=='backpack' or command=='bag' then
  if #args==0 then
   local list={};for page=0,CONST.EXTBAGPAGE do
    local used=0;local first,last=pageRange(p,page)
    for slot=first,last do if Char.GetItemIndex(p,slot)>=0 then used=used+1 end end
    list[#list+1]=page..'号 '..used..'/'..SIZE
   end
   message(p,'当前背包 '..Char.GetBagPage(p)..'；'..table.concat(list,'；'))
  else
   local page=#args==1 and integer(args[1],0,CONST.EXTBAGPAGE)
   if not page then message(p,'用法：/backpack 0~'..CONST.EXTBAGPAGE)
   elseif Char.GetBagPage(p)==page or Char.SwitchBag(p,page)==1 then message(p,'当前使用背包 '..page..'。')
   else message(p,'背包切换失败，请稍后重试。') end
  end
 elseif command=='sort' or command=='stack' then
  if #args>1 or (args[1] and args[1]~='all') then message(p,'用法：/'..command..' [all]');return 0 end
  local first,last=Char.GetBagPage(p),Char.GetBagPage(p)
  if args[1]=='all' then first,last=0,CONST.EXTBAGPAGE end
  for page=first,last do if command=='sort' then self:sortPage(p,page) else self:mergePage(p,page) end end
  Item.UpItem(p,-1);self.signatures[p]=nil
  message(p,(args[1]=='all' and '所有背包' or '当前背包')..(command=='sort' and '整理完成。' or '堆叠完成。'))
 elseif command=='identify' then
  if #args>0 then message(p,'用法：/identify');return 0 end
  message(p,'鉴定完成：'..self:identify(p)..' 件。')
 elseif command=='sellstones' then
  if #args>0 then message(p,'用法：/sellstones');return 0 end
  local count,gold,full=self:sellStones(p)
  message(p,'出售魔石 '..count..' 个，获得 '..gold..' 金币。'..(full and '金币上限不足，剩余魔石已保留。' or ''))
 elseif command=='clock' then
  if #args>1 or (args[1] and args[1]~='on' and args[1]~='off') then message(p,'用法：/clock on|off');return 0 end
  if args[1]=='off' then
   if self:setSetting(p,'autoclock',false) then Char.FeverStop(p);message(p,'打卡和自动打卡已关闭。') end
  elseif args[1]=='on' then message(p,self:startClock(p) and '打卡已开启，使用原生卡时双倍经验。' or '卡时不足，无法打卡。')
  else message(p,'打卡='..(Char.IsFeverTime(p)==1 and 'on' or 'off')..'，卡时 '..math.floor(num(p,'CHAR_卡时')/60)..' 分钟。') end
 elseif command=='petmax' or command=='petbp' then
  if #args~=1 or (args[1]~='all' and not integer(args[1],0,4)) then message(p,'用法：/'..command..' 0~4|all（0 是第一只宠物）');return 0 end
  if args[1]=='all' then for slot=0,4 do if Char.GetPet(p,slot)>=0 then self:petRanks(p,slot,command=='petmax') end end
  else self:petRanks(p,tonumber(args[1]),command=='petmax') end
 end
 return 0
end

function M:onLoad()
 self.signatures={};self.goldFull={};self.stalls={};self.configs={}
 self:regCallback('TalkEvent',Func.bind(self.handleTalk,self))
 self:regCallback('LoginEvent',function(p) self.signatures[p]=nil;self.configs[p]=nil;self:maintain(p) end)
 for _,event in ipairs({'LogoutEvent','DropEvent'}) do self:regCallback(event,function(p)
  self.signatures[p]=nil;self.goldFull[p]=nil;self.stalls[p]=nil;self.configs[p]=nil
 end) end
 self:regCallback('CharaStallStartEvent',function(p) self.stalls[p]=true end)
 self:regCallback('CharaStallEndEvent',function(p) self.stalls[p]=nil end)
 self:regCallback('ItemInitEvent',function(p,i) if i>=0 then self:normalize(i) end end)
 self:regCallback('ItemOverLapEvent',function(p,a,b) return self:sameStack(a,b) and 0 or 1 end)
 self:AddInterval(2000,function()
  for _,p in ipairs(NLG.GetPlayer() or {}) do
   if valid(p) and not Char.IsDummy(p) then
    local ok,err=pcall(self.maintain,self,p)
    if not ok then self:logError('automatic inventory task: '..tostring(err)) end
   end
  end
 end,1)
 self:logInfo('QoL commands ready; stack limit '..D.stackLimit..'; backpacks 0-'..CONST.EXTBAGPAGE)
end

return M
