---@class AutoStat:ModuleType
local M=ModuleBase:createModule('autoStat')
local KEY='AutoStatConfigV1'
local MENU,INPUT=7310,7311
local FIELDS={'CHAR_体力','CHAR_力量','CHAR_强度','CHAR_速度','CHAR_魔法'}
local NAMES={'体力','力量','强度','速度','魔法'}
local POSITION={mapType=0,map=1000,x=223,y=85,direction=4}

local function get(c,key) local field=assert(CONST[key],key);return Char.GetData(c,field) end
local function valid(p)
 return type(p)=='number' and p>=0 and Char.IsValidCharIndex(p) and Char.IsPlayer(p)
end
local function identity(p) return tostring(get(p,'CHAR_账号'))..':'..tostring(get(p,'对象_RegistNumber')) end
local function uuid(c) return tostring(Char.GetUUID(c)) end
local function copy(value) return JSON.decode(JSON.encode(value)) end
local function safeName(c) return tostring(get(c,'CHAR_名字')):gsub('[\r\n|\\]',' ') end
local function weightsOK(w)
 if type(w)~='table' or #w~=5 then return false end
 local total=0
 for i=1,5 do
  if type(w[i])~='number' or w[i]~=math.floor(w[i]) or w[i]<0 or w[i]>100 then return false end
  total=total+w[i]
 end
 return total>0 and total<=100
end
local function planOK(plan)
 if type(plan)~='table' or type(plan.enabled)~='boolean' or not weightsOK(plan.weights) or type(plan.credit)~='table' or #plan.credit~=5 then return false end
 for i=1,5 do
  local c=plan.credit[i]
  if type(c)~='number' or c~=math.floor(c) or math.abs(c)>500 then return false end
 end
 return true
end
local function configOK(cfg)
 if type(cfg)~='table' or cfg.version~=1 or type(cfg.pets)~='table' then return false end
 if cfg.player and not planOK(cfg.player) then return false end
 for id,plan in pairs(cfg.pets) do if type(id)~='string' or not planOK(plan) then return false end end
 return true
end
local function newPlan(w) return {enabled=true,weights=w,credit={0,0,0,0,0}} end
local function summary(plan)
 if not plan then return '未配置（关闭）' end
 return (plan.enabled and '开启 ' or '关闭 ')..table.concat(plan.weights,':')
end

function M:settings(p)
 if not valid(p) then return nil end
 local id=identity(p)
 local cached=self.configs[p]
 if cached and cached.identity==id then return cached.value end
 local raw=Char.GetExtData(p,KEY)
 local account=get(p,'CHAR_账号')
 if account and account~='' then
  local result=SQL.QueryEx('SELECT val FROM hook_charaext WHERE cdKey=? AND regNo=? AND sKey=?',account,get(p,'对象_RegistNumber'),KEY)
  if result.status~=0 then return nil end
  if result.rows and result.rows[1] then raw=result.rows[1].val end
 end
 local cfg={version=1,pets={}}
 if raw~=nil then
  local ok,value=pcall(JSON.decode,raw)
  if not ok or not configOK(value) then return nil end
  cfg=value
 end
 self.configs[p]={identity=id,value=cfg}
 return cfg
end

function M:saveSettings(p,cfg)
 if not valid(p) or not configOK(cfg) then return false end
 local raw=JSON.encode(cfg)
 local account=get(p,'CHAR_账号')
 if account and account~='' then
  local result=SQL.QueryEx('REPLACE INTO hook_charaext(cdKey,regNo,sKey,val,valType) VALUES(?,?,?,?,?)',account,get(p,'对象_RegistNumber'),KEY,raw,0)
  if result.status~=0 or (result.effectRows or 0)<1 then return false end
 end
 Char.SetExtData(p,KEY,raw)
 self.configs[p]={identity=identity(p),value=cfg}
 return true
end

function M:target(p,ref)
 if not valid(p) then return nil end
 if ref=='player' then return p end
 for slot=0,4 do
  local pet=Char.GetPoolPet(p,slot)
  if pet>=0 and Char.IsValidCharIndex(pet) and Char.IsPet(pet) and uuid(pet)==ref then return pet end
 end
 for slot=0,4 do
  local pet=Char.GetPet(p,slot)
  if pet>=0 and Char.IsPet(pet) and uuid(pet)==ref then return pet end
 end
end

function M:plan(cfg,ref) return ref=='player' and cfg.player or cfg.pets[ref] end

function M:setPlan(p,ref,weights,enabled)
 self:flushOwner(p)
 if not self:target(p,ref) then return false,'宠物已离开携带栏或银行，请重新选择。' end
 local cfg=self:settings(p)
 if not cfg then return false,'自动加点设置读取失败，请稍后重试。' end
 local updated=copy(cfg)
 local plan
 if weights then
  if not weightsOK(weights) then return false,'请输入五个非负整数，合计须为 1 至 100。' end
  plan=newPlan(copy(weights))
 else
  plan=self:plan(updated,ref)
  if not plan then return false,'请先选择或输入加点比例。' end
  plan.enabled=enabled and true or false
 end
 if ref=='player' then updated.player=plan else updated.pets[ref]=plan end
 if not self:saveSettings(p,updated) then return false,'自动加点设置保存失败，请稍后重试。' end
 return true
end

-- Native callbacks fire BEFORE BP is awarded (and pet growth is applied).
-- Record the old balance, then spend only the new award after native calculation.
function M:queue(p,c,levels)
 if not valid(p) or type(levels)~='number' or levels<=0 then return end
 local ref=c==p and 'player' or uuid(c)
 if self:target(p,ref)~=c then return end
 local cfg=self:settings(p)
 local plan=cfg and self:plan(cfg,ref)
 if not plan or not plan.enabled then return end
 local list=self.pending[p]
 if not list or list.identity~=identity(p) then list={identity=identity(p),entries={}};self.pending[p]=list end
 if not list.entries[ref] then list.entries[ref]={targetUUID=uuid(c),before=get(c,'CHAR_升级点')} end
end

function M:allocate(p,ref,entry)
 local c=self:target(p,ref)
 if not c or uuid(c)~=entry.targetUUID then return end
 local cfg=self:settings(p)
 local oldPlan=cfg and self:plan(cfg,ref)
 if not oldPlan or not oldPlan.enabled then return end
 local points=get(c,'CHAR_升级点')
 local award=math.max(0,points-entry.before)
 if award<1 then return end
 local updated=copy(cfg)
 local plan=self:plan(updated,ref)
 local before,after,added={},{},{0,0,0,0,0}
 for i,key in ipairs(FIELDS) do before[i]=get(c,key);after[i]=before[i] end
 local cap=c==p and ((get(c,'CHAR_等级')-1)*2+15)*100 or math.huge
 local spent=0
 for point=1,award do
  local total,chosen=0,nil
  for i=1,5 do
   if plan.weights[i]>0 and after[i]+100<=cap then total=total+plan.weights[i] end
  end
  if total==0 then break end
  for i=1,5 do
   if plan.weights[i]>0 and after[i]+100<=cap then
    plan.credit[i]=plan.credit[i]+plan.weights[i]
    if not chosen or plan.credit[i]>plan.credit[chosen] then chosen=i end
   end
  end
  plan.credit[chosen]=plan.credit[chosen]-total
  after[chosen]=after[chosen]+100;added[chosen]=added[chosen]+1;spent=spent+1
 end
 if spent==0 then NLG.SystemMessage(p,'自动加点：所选属性已到等级上限，新增点数已保留。');return end
 -- Persist the fractional distribution before modifying native BP. Failed writes
 -- leave every point available for manual allocation.
 if not self:saveSettings(p,updated) then NLG.SystemMessage(p,'自动加点保存失败，升级点数已保留。');return end
 local ok=true
 for i,key in ipairs(FIELDS) do if after[i]~=before[i] then ok=Char.SetData(c,CONST[key],after[i])==1 and ok end end
 ok=Char.SetData(c,CONST['CHAR_升级点'],points-spent)==1 and ok
 if not ok then
  for i,key in ipairs(FIELDS) do Char.SetData(c,CONST[key],before[i]) end
  Char.SetData(c,CONST['CHAR_升级点'],points);self:saveSettings(p,cfg)
  NLG.SystemMessage(p,'自动加点未完成，升级点数已保留。');return
 end
 if c==p then NLG.UpChar(p)
 elseif Pet.UpPet(p,c)==-5 then Char.UpCharStatus(c) end
 local detail={}
 for i=1,5 do if added[i]>0 then detail[#detail+1]=NAMES[i]..'+'..added[i] end end
 NLG.SystemMessage(p,(c==p and '人物' or '宠物 '..safeName(c))..'自动加点：'..table.concat(detail,' ')..'。')
 if spent<award then NLG.SystemMessage(p,'部分属性已到等级上限，剩余新增点数已保留。') end
end

function M:flushOwner(p)
 local list=self.pending[p];self.pending[p]=nil
 if not list or not valid(p) or list.identity~=identity(p) then return end
 for ref,entry in pairs(list.entries) do self:allocate(p,ref,entry) end
end

function M:near(n,p)
 return n==self.npc and valid(p) and Char.GetBattleIndex(p)<0 and get(p,'CHAR_BattleMode')==0
  and get(n,'CHAR_地图')==get(p,'CHAR_地图') and get(n,'CHAR_地图类型')==get(p,'CHAR_地图类型')
  and math.abs(get(n,'CHAR_X')-get(p,'CHAR_X'))<=3 and math.abs(get(n,'CHAR_Y')-get(p,'CHAR_Y'))<=3
end

function M:show(n,p,ref,bank)
 if not self:near(n,p) then return end
 self:flushOwner(p)
 local cfg=self:settings(p)
 if not cfg then NLG.SystemMessage(p,'自动加点设置读取失败，请稍后重试。');return end
 local options,actions={},{}
 local function add(text,action) options[#options+1]=text;actions[#actions+1]=action end
 local title='自动加点师\\n升级新增点数按比例分配'
 if ref then
  local c=self:target(p,ref)
  if not c then NLG.SystemMessage(p,'宠物已离开携带栏或银行，请重新选择。');return self:show(n,p) end
  local plan=self:plan(cfg,ref)
  title=(ref=='player' and '人物自动加点' or '宠物：'..safeName(c))..'\\n'..summary(plan)..'\\n顺序：体 / 力 / 强 / 速 / 魔'
  for i=1,5 do local w={0,0,0,0,0};w[i]=1;add('全加'..NAMES[i],{kind='set',weights=w}) end
  add('自定义五项比例',{kind='input'})
  add(plan and plan.enabled and '关闭自动加点' or '开启已保存方案',{kind='toggle',enabled=not (plan and plan.enabled)})
  add('返回人物和宠物列表',{kind='main'})
 elseif bank then
  title='银行宠物自动加点\\n选择银行中的宠物'
  for slot=0,4 do
   local pet=Char.GetPoolPet(p,slot)
   if pet>=0 and Char.IsValidCharIndex(pet) and Char.IsPet(pet) then
    local id=uuid(pet);local plan=cfg.pets[id]
    add('银行宠物'..(slot+1)..' '..safeName(pet)..' ['..(plan and plan.enabled and '开启' or '关闭')..']',{kind='target',ref=id})
   else add('银行宠物'..(slot+1)..'（空）',{kind='empty'}) end
  end
  add('返回人物和随身宠物列表',{kind='main'})
 else
  add('人物：'..summary(cfg.player),{kind='target',ref='player'})
  for slot=0,4 do
   local pet=Char.GetPet(p,slot)
   if pet>=0 and Char.IsPet(pet) then
    local id=uuid(pet);local plan=cfg.pets[id]
    add('宠物'..(slot+1)..' '..safeName(pet)..' ['..(plan and plan.enabled and '开启' or '关闭')..']',{kind='target',ref=id})
   else add('宠物'..(slot+1)..'（空）',{kind='empty'}) end
  end
  add('配置银行宠物',{kind='bank'})
  add('查看使用说明',{kind='help'})
 end
 self.sessions[p]={npc=n,identity=identity(p),expires=os.time()+120,seq=MENU,ref=ref,bank=bank,actions=actions}
 NLG.ShowWindowTalked(p,n,CONST['窗口_选择框'],CONST['按钮_关闭'],MENU,self:NPC_buildSelectionText(title,options))
end

function M:answer(n,p,seq,button,data)
 local session=self.sessions[p];self.sessions[p]=nil
 if not session or not self:near(n,p) or session.npc~=n or session.identity~=identity(p) or session.seq~=seq or session.expires<os.time() then return end
 if button==CONST['按钮_关闭'] then return end
 if seq==INPUT then
  if button~=CONST['按钮_确定'] or type(data)~='string' or #data>80 then return self:show(n,p,session.ref,session.bank) end
  local a,b,c,d,e=data:match('^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s*$')
  local w=a and {tonumber(a),tonumber(b),tonumber(c),tonumber(d),tonumber(e)} or nil
  if not w or not weightsOK(w) then NLG.SystemMessage(p,'格式：体 力 强 速 魔，例如 1 2 0 1 0；合计 1 至 100。')
  else
   local ok,err=self:setPlan(p,session.ref,w)
   NLG.SystemMessage(p,ok and '已保存并开启自动加点方案。' or err)
  end
  return self:show(n,p,session.ref,session.bank)
 end
 if type(data)~='string' or not data:match('^[1-8]$') then return end
 local action=session.actions[tonumber(data)];if not action then return end
 if action.kind=='target' then return self:show(n,p,action.ref,session.bank)
 elseif action.kind=='bank' then return self:show(n,p,nil,true)
 elseif action.kind=='main' then return self:show(n,p,nil,session.ref and session.bank or false)
 elseif action.kind=='empty' then NLG.SystemMessage(p,'这个宠物栏没有宠物。');return self:show(n,p,nil,session.bank)
 elseif action.kind=='help' then
  NLG.SystemMessage(p,'顺序为体力、力量、强度、速度、魔法。自定义输入如 1 2 0 1 0，代表按 1:2:0:1:0 分配。')
  NLG.SystemMessage(p,'仅分配启用后升级新增的点数；原有剩余点数保留。人物遵守单项等级上限，宠物天生成长照常。')
  NLG.SystemMessage(p,'随身五栏和银行五栏宠物可分别配置；主菜单选择配置银行宠物。方案随本角色的宠物唯一编号保存，换栏位、重登和重启后保留。')
  return self:show(n,p)
 elseif action.kind=='input' then
  session.seq=INPUT;session.actions=nil;session.expires=os.time()+120;self.sessions[p]=session
  return NLG.ShowWindowTalked(p,n,CONST['窗口_输入框'],CONST['按钮_确定关闭'],INPUT,
   '自定义自动加点比例\\n按 体 力 强 速 魔 输入五个整数\\n用空格分隔，合计 1 至 100\\n例：1 2 0 1 0\\n保存后自动开启，仅分配升级新增点数')
 elseif action.kind=='set' or action.kind=='toggle' then
  local ok,err=self:setPlan(p,session.ref,action.weights,action.enabled)
  NLG.SystemMessage(p,ok and '自动加点设置已保存。' or err)
  return self:show(n,p,session.ref,session.bank)
 end
end

function M:onLoad()
 self.configs={};self.sessions={};self.pending={}
 self.npc=self:NPC_createNormal('自动加点师',14722,POSITION)
 assert(self.npc>=0,'autoStat NPC creation failed')
 self:NPC_regTalkedEvent(self.npc,function(n,p) self:show(n,p) end)
 self:NPC_regWindowTalkedEvent(self.npc,Func.bind(self.answer,self))
 self:regCallback('LevelUpEvent',function(p,levels) self:queue(p,p,levels) end)
 self:regCallback('PetLevelUpEvent',function(p,pet,levels) self:queue(p,pet,levels) end)
 self:regCallback('BattleExitEvent',function(p) self:flushOwner(p) end)
 self:regCallback('BeforeCharaSaveEvent',function(p) self:flushOwner(p) end)
 self:regCallback('LogoutEvent',function(p) self:flushOwner(p);self.configs[p]=nil;self.sessions[p]=nil end)
 self:AddInterval(250,function()
  local players={};for p in pairs(self.pending) do players[#players+1]=p end
  for _,p in ipairs(players) do self:flushOwner(p) end
 end,1)
 self:logInfo('Automatic stat NPC at Falan (223,85)')
end

function M:onUnload()
 local players={};for p in pairs(self.pending or {}) do players[#players+1]=p end
 for _,p in ipairs(players) do self:flushOwner(p) end
 self.configs={};self.sessions={};self.pending={}
end
return M
