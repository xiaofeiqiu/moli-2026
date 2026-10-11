---@class GameQoL:ModuleType
local M=ModuleBase:createModule('gameQoL')
local D=dofile('lua/Modules/gameQoLData.lua')
local SIZE=20
local PREF='GameQoL_v1_'
local CONFIG_KEY='GameQoLConfigV1'
local DEFAULT={autostack=true,autosort=true,autoidentify=true,autosell=true,autoclock=true,autorepair=true}
local Help=dofile('lua/Modules/commandHelp.lua')
local COMMANDS=Help:commandSet('gameQoL')
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

-- Lock both the saved base value and the engine's calculated loyalty.
-- Do not recalculate status here: this also runs inside the status callback.
function M:lockPetLoyalty(pet)
 if type(pet)~='number' or pet<0 or not Char.IsValidCharIndex(pet) or not Char.IsPet(pet) then return false end
 local changed=false
 for _,key in ipairs({'宠物_基础忠诚','宠物_忠诚'}) do
  if num(pet,key)~=100 then Char.SetData(pet,CONST[key],100);changed=true end
 end
 return changed
end

function M:maintainPetLoyalty(p)
 if not valid(p) then return end
 for slot=0,4 do
  local pet=Char.GetPet(p,slot)
  if pet>=0 and Char.IsValidCharIndex(pet) and Char.IsPet(pet) and Pet.GetOwner(pet)==p then
   if self:lockPetLoyalty(pet) then Pet.UpPet(p,pet) end
  end
 end
end

function M:battlePetLoyalty(b)
 for pos=0,19 do
  local q=Battle.GetPlayer(b,pos)
  if q>=0 and Char.IsValidCharIndex(q) then
   if Char.IsPet(q) then self:lockPetLoyalty(q)
   elseif Char.IsPlayer(q) then self:maintainPetLoyalty(q) end
  end
 end
end

function M:heal(p)
 if not self:ready(p,true) then
  if valid(p) then message(p,'战斗或摆摊期间无法治疗。') end
  return false
 end
 local five=getModule('fivePet');local squad=five and five.active[p]
 if squad and squad.battle then message(p,'五宠战斗结算尚未完成，请稍后再治疗。');return false end
 local pets={};local bankPets={};local seen={}
 for slot=0,4 do
  local pet=Char.GetPet(p,slot)
  if pet>=0 and Char.IsValidCharIndex(pet) and Char.IsPet(pet) and Pet.GetOwner(pet)==p then
   -- Pets can retain an old battle index/mode after combat. Only an
   -- actual roster entry proves this pet is still participating.
   local battle=Char.GetBattleIndex(pet)
   if battle>=0 then for pos=0,19 do
    if Battle.GetPlayer(battle,pos)==pet then
     message(p,'宠物仍在战斗中，请结束战斗后再治疗。');return false
    end
   end end
   pets[#pets+1]=pet;seen[pet]=true
  end
 end
 for slot=0,3 do local pet=Char.GetPoolPet(p,slot)
  if pet>=0 and Char.IsValidCharIndex(pet) and Char.IsPet(pet) and not seen[pet] then
   pets[#pets+1]=pet;bankPets[pet]=true;seen[pet]=true
  end
 end
 -- Clear injury before recalculating maxima, then restore the resulting HP/MP.
 local function restore(q)
  Char.SetData(q,CONST['CHAR_受伤'],0)
  Char.UpCharStatus(q)
  Char.SetData(q,CONST['CHAR_血'],num(q,'CHAR_最大血'))
  Char.SetData(q,CONST['CHAR_魔'],num(q,'CHAR_最大魔'))
 end
 restore(p);NLG.UpChar(p)
 for _,pet in ipairs(pets) do restore(pet);if not bankPets[pet] then Pet.UpPet(p,pet) end end
 if squad then for _,row in ipairs(five:actors(squad)) do if five:owned(p,row) then five:refresh(row) end end end
 message(p,'治疗完成：人物及 '..#pets..' 只宠物（含银行前4栏）已恢复满生命、满魔力，受伤已清除（免费）。')
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

function M:fillClock(p)
 local file=io.open('cgmsv.cf','rb')
 local hours
 if file then
  for line in file:lines() do
   local value=line:match('^%s*fevermax%s*=%s*(%d+)%s*$')
   if value then hours=tonumber(value);break end
  end
  file:close()
 end
 if not hours or hours<=0 then message(p,'无法读取卡时上限，请检查 fevermax 配置。');return false end
 -- Fever uses an absolute end time while running. Merely changing CHAR_卡时
 -- leaves that old deadline active; the next status refresh/save overwrites it.
 if Char.IsFeverTime(p)==1 and Char.FeverStop(p)~=1 then
  message(p,'无法停止旧打卡计时，卡时未补满，请稍后重试。');return false
 end
 Char.SetData(p,CONST['CHAR_卡时'],hours*3600)
 local started=self:startClock(p)
 -- Synchronize the remaining value from the new native deadline before saving.
 local active=Char.IsFeverTime(p)==1
 local actual=num(p,'CHAR_卡时')
 if not Char.IsDummy(p) then
  local ok,result=pcall(Char.SaveToDb,p)
  if not ok or result~=0 then message(p,'卡时保存失败，请稍后重试 /clock full。');return false end
 end
 if started and active and actual+2<hours*3600 then
  message(p,'实际卡时只有 '..math.floor(actual/60)..' 分钟；请保存角色后重启服务端，加载 cgmsv.cf 的 fevermax='..hours..' 配置，再执行 /clock full。')
  return false
 end
 message(p,started and ('卡时已补满至 '..hours..' 小时，打卡已开启，使用原生卡时双倍经验。') or '卡时已补满，但打卡开启失败，请重试 /clock on。')
 return started
end

function M:repairEquipment(p)
 local repaired=0
 -- Equipment occupies slots 0-7; backpack items must not be repaired.
 for slot=0,7 do
  local i=Char.GetItemIndex(p,slot)
  if i>=0 then
   local current=tonumber(idata(i,'道具_耐久'))
   local maximum=tonumber(idata(i,'道具_最大耐久'))
   -- Strictly below 85%: exactly 85% is left alone. Preserve maximum durability.
   if current and maximum and maximum>0 and current>=0 and current*100<maximum*85 then
    Item.SetData(i,CONST['道具_耐久'],maximum)
    if tonumber(idata(i,'道具_耐久'))==maximum then
     repaired=repaired+1;Item.UpItem(p,slot)
    end
   end
  end
 end
 if repaired>0 then NLG.UpChar(p);message(p,'战后自动修理完成：'..repaired..' 件装备已恢复满耐久。') end
 return repaired
end

function M:maintain(p,afterBattle)
 self:maintainPetLoyalty(p)
 if not self:ready(p,true) then return end
 self:expandBags(p)
 local cfg=self:settings(p)
 if not cfg then return end
 if afterBattle and cfg.autorepair then self:repairEquipment(p) end
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
 if afterBattle or self.signatures[p]~=signature then
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
 return true
end

function M:flushAfterBattle()
 for p in pairs(self.pendingBattle) do
  if not valid(p) then self.pendingBattle[p]=nil
  elseif self:ready(p,true) then
   local ok,done=pcall(self.maintain,self,p,true)
   if ok and done then self.pendingBattle[p]=nil
   elseif not ok then self:logError('after-battle upkeep: '..tostring(done)) end
  end
 end
end

function M:petRanks(p,slot,fill,bank)
 local pet=bank and Char.GetPoolPet(p,slot) or Char.GetPet(p,slot)
 local label=(bank and '银行宠物栏 ' or '宠物栏 ')..slot
 if pet<0 or not Char.IsPet(pet) then message(p,label..' 没有宠物。');return false end
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
 end
 if fill then
  local changed={}
  local function rollback()
   for _,r in ipairs(changed) do Pet.SetArtRank(pet,r.art,r.current) end
   Pet.UpPet(p,pet)
  end
  for n,r in ipairs(ranks) do if r.current<r.full then
   changed[#changed+1]=r
   local ok,result=pcall(Pet.SetArtRank,pet,r.art,r.full)
   if not ok or result~=0 or Pet.GetArtRank(pet,r.art)~=r.full then
    rollback()
    message(p,'宠物栏 '..slot..' 补档失败：原生引擎未写入'..({'体','力','强','敏','魔'})[n]..'档 '..r.full..'（返回 '..tostring(result)..'），已撤销本次补档。')
    if result==-4 then message(p,'请检查 cgmsv.cf 的 maxallocpoint 上限；修改后须重启服务端，单独重载 Lua 不会更新引擎上限。') end
    return false
   end
  end end
  Pet.UpPet(p,pet)
  for _,r in ipairs(ranks) do if Pet.GetArtRank(pet,r.art)<r.full then
   rollback();message(p,'宠物栏 '..slot..' 刷新后仍有掉档，已撤销本次补档。');return false
  end end
  if loss>0 and not Char.IsDummy(p) then
   local ok,result=pcall(Char.SaveToDb,p)
   if not ok or result~=0 then
    rollback();message(p,'宠物栏 '..slot..' 补档保存失败，已撤销本次补档，请稍后重试。');return false
   end
  end
  message(p,'宠物栏 '..slot..' 已补满成长档数（补回 '..loss..' 档），等级和已加点保留，后续升级按满档成长。')
 else
  local text={};for _,r in ipairs(ranks) do text[#text+1]=r.current..'/'..r.full end
  message(p,label..'：体/力/强/敏/魔 '..table.concat(text,' ')..'，总掉档 '..loss..'。')
 end
 return true
end

function M:help(p,query)
 Help:show(p,query)
end

function M:handleTalk(p,msg)
 if type(msg)~='string' then return 1 end
 local command,tail=msg:match('^/(%S+)(.*)$')
 command=command and command:lower()
 if not COMMANDS[command] then return 1 end
 if tail~='' and not tail:match('^%s') then return 1 end
 local args={};for arg in tail:gmatch('%S+') do args[#args+1]=arg:lower() end
 if not valid(p) then return 0 end
 self:expandBags(p)
 if command=='help' then
  if #args>1 then message(p,'用法：/help [命令名|gm]') else self:help(p,args[1]) end
  return 0
 end
 if command=='qol' then
  local cfg=self:settings(p);local list={}
  if not cfg then message(p,'自动功能设置暂时无法读取，请稍后重试。');return 0 end
  for _,key in ipairs({'autostack','autosort','autoidentify','autosell','autoclock','autorepair'}) do list[#list+1]=key..'='..(cfg[key] and 'on' or 'off') end
  message(p,table.concat(list,' '));message(p,'打卡='..(Char.IsFeverTime(p)==1 and 'on' or 'off')..'，剩余卡时 '..math.floor(num(p,'CHAR_卡时')/60)..' 分钟。');return 0
 end
 if command=='fame' or command=='声望' then
  if #args>1 or (args[1] and args[1]~='max') then message(p,'用法：/fame [max] 或 /声望 [max]');return 0 end
  if args[1]=='max' then
   local file=io.open('cgmsv.cf','rb')
   local maximum
   if file then
    for line in file:lines() do
     local value=line:match('^%s*maxfame%s*=%s*(%d+)%s*$')
     if value then maximum=tonumber(value);break end
    end
    file:close()
   end
   if not maximum or maximum<=0 or maximum>2147483647 then message(p,'无法读取声望上限，请检查 maxfame 配置。');return 0 end
   Char.SetData(p,CONST['CHAR_声望'],maximum)
   if num(p,'CHAR_声望')~=maximum then message(p,'声望设置失败，请检查 maxfame 配置。');return 0 end
   if not Char.IsDummy(p) then Char.SaveToDb(p) end
   message(p,'声望已设为配置上限：'..maximum..'。');return 0
  end
  message(p,'当前声望：'..num(p,'CHAR_声望')..'。');return 0
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
 if command=='heal' then
  if #args>0 then message(p,'用法：/heal（不带参数）');return 0 end
  self:heal(p);return 0
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
  if #args>1 or (args[1] and args[1]~='on' and args[1]~='off' and args[1]~='full') then message(p,'用法：/clock [on|off|full]');return 0 end
  if args[1]=='off' then
   if self:setSetting(p,'autoclock',false) then Char.FeverStop(p);message(p,'打卡和自动打卡已关闭。') end
  elseif args[1]=='full' then self:fillClock(p)
  elseif args[1]=='on' then message(p,self:startClock(p) and '打卡已开启，使用原生卡时双倍经验。' or '卡时不足，无法打卡。')
  else message(p,'打卡='..(Char.IsFeverTime(p)==1 and 'on' or 'off')..'，卡时 '..math.floor(num(p,'CHAR_卡时')/60)..' 分钟。') end
 elseif command=='petbp' then
  local bank=args[1]=='bank'
  local target=bank and args[2] or args[1]
  if #args~=(bank and 2 or 1) or (target~='all' and not integer(target,0,4)) then
   message(p,'用法：/petbp 0~4|all 或 /petbp bank 0~4|all（0 是第一只宠物；all 含随身和银行，bank all 仅银行）');return 0
  end
  if target=='all' then
   if not bank then for slot=0,4 do if Char.GetPet(p,slot)>=0 then self:petRanks(p,slot,false) end end end
   for slot=0,4 do if Char.GetPoolPet(p,slot)>=0 then self:petRanks(p,slot,false,true) end end
  else self:petRanks(p,tonumber(target),false,bank) end
 elseif command=='petmax' then
  if #args~=1 or (args[1]~='all' and not integer(args[1],0,4)) then message(p,'用法：/'..command..' 0~4|all（0 是第一只宠物）');return 0 end
  if args[1]=='all' then for slot=0,4 do if Char.GetPet(p,slot)>=0 then self:petRanks(p,slot,command=='petmax') end end
  else self:petRanks(p,tonumber(args[1]),command=='petmax') end
 end
 return 0
end

function M:onLoad()
 self.signatures={};self.goldFull={};self.stalls={};self.configs={};self.pendingBattle={}
 self:regCallback('AfterCalcCharaStatusEvent',function(q) self:lockPetLoyalty(q) end)
 self:regCallback('BeforeCharaSaveEvent',Func.bind(self.maintainPetLoyalty,self))
 self:regCallback('BattleStartEvent',function(b) self:battlePetLoyalty(b);return 0 end)
 self:regCallback('BeforeBattleTurnEvent',function(b) self:battlePetLoyalty(b) end)
 self:regCallback('AfterBattleTurnEvent',function(b) self:battlePetLoyalty(b) end)
 self:regCallback('ResetCharaBattleStateEvent',function(q)
  self:lockPetLoyalty(q);self:maintainPetLoyalty(q)
 end)
 self:regCallback('BattlePetLeaveCheckEvent',function(b,pet,kind,com1,com2,com3)
  if Char.IsValidCharIndex(pet) and Char.IsPet(pet) then
   self:lockPetLoyalty(pet)
   -- In this native build, type 6 skips PNO (disobedience) and pet departure.
   -- The engine changes the command before this callback; restore its inputs.
   -- Type 8 still emits PNO. Leave the existing type 1 branch unchanged.
   if kind==0 or (kind>=2 and kind<=7) then
    Char.SetData(pet,CONST.CHAR_BattleCom1,com1)
    Char.SetData(pet,CONST.CHAR_BattleCom2,com2)
    Char.SetData(pet,CONST.CHAR_BattleCom3,com3)
    return 6
   end
  end
  return kind
 end)
 self:regCallback('TalkEvent',Func.bind(self.handleTalk,self))
 self:regCallback('LoginEvent',function(p) self.signatures[p]=nil;self.configs[p]=nil;self:maintain(p) end)
 for _,event in ipairs({'LogoutEvent','DropEvent'}) do self:regCallback(event,function(p)
  self.signatures[p]=nil;self.goldFull[p]=nil;self.stalls[p]=nil;self.configs[p]=nil;self.pendingBattle[p]=nil
 end) end
 self:regCallback('CharaStallStartEvent',function(p) self.stalls[p]=true end)
 self:regCallback('CharaStallEndEvent',function(p) self.stalls[p]=nil end)
 self:regCallback('ItemInitEvent',function(p,i) if i>=0 then self:normalize(i) end end)
 self:regCallback('ItemOverLapEvent',function(p,a,b) return self:sameStack(a,b) and 0 or 1 end)
 self:regCallback('BattleExitEvent',function(p)
  self:lockPetLoyalty(p);self:maintainPetLoyalty(p)
  if valid(p) and not Char.IsDummy(p) then self.pendingBattle[p]=true end
 end)
 -- BattleExitEvent can run before the engine clears battle state. Defer until
 -- the player is really out of combat, then apply /sort all and repair once.
 self:AddInterval(250,Func.bind(self.flushAfterBattle,self),1)
 self:AddInterval(2000,function()
  local online=NLG.GetPlayer()
  -- The native API returns a numeric sentinel when no players are online.
  for _,p in ipairs(type(online)=='table' and online or {}) do
   if valid(p) and not Char.IsDummy(p) then
    local ok,err=pcall(self.maintain,self,p)
    if not ok then self:logError('automatic inventory task: '..tostring(err)) end
   end
  end
 end,1)
 self:logInfo('QoL commands ready; stack limit '..D.stackLimit..'; backpacks 0-'..CONST.EXTBAGPAGE)
end

return M
