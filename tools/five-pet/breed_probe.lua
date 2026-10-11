-- Native pet-strengthening experience comparison; real disposable bank inventory.
local M=assert(getModule('fivePet'))
local T=ModuleBase:createModule('breedProbe'):new();T:load()
local R={status='RUNNING',checks={},awards={},cases={},native_bank_inventory=true,production_database_modified=false}
local p,donor,b=-1,-1,-1;local session;local phase=1;local finished=false;local originals={}
local levels={0,1,10,30,0,0,30}
local function get(q,k) local field=assert(CONST[k],k);return Char.GetData(q,field) end
local function set(q,k,v) local field=assert(CONST[k],k);return Char.SetData(q,field,v) end
local function write() local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close() end
local function check(ok,label) R.checks[#R.checks+1]={name=label,pass=not not ok};write();assert(ok,label) end
local function finish(err)
 if finished then return end;finished=true
 if p>=0 then pcall(Battle.ExitBattle,p);pcall(M.disable,M,p) end
 R.status=err and 'FAIL' or 'PASS';R.error=err and tostring(err) or nil;write()
end
local function prepare()
 local slot=Char.HaveSkill(p,70);if slot>=0 then Char.DelSkill(p,70,0) end
 if levels[phase]>0 then
  slot=Char.AddSkill(p,70,0,0);check(slot>=0,'learn active strengthening phase '..phase)
  Char.SetSkillLevel(p,slot,levels[phase],0);check(Char.GetSkillLevel(p,slot)==levels[phase],'active strengthening level '..levels[phase])
 end
 if phase==6 then
  Char.SetExtData(p,'SkillLibraryV1',JSON.encode({version=1,skills={['70']={id=70,level=30,exp=0}},profiles={}}))
 end
 set(p,'CHAR_等级',20);set(p,'CHAR_经验',0);NLG.UpChar(p)
 if phase==7 then M:disable(p);check(not M.active[p] and Char.PartyNum(p)<=1,'standalone main pet without five-pet mode') end
 for _,q in ipairs(originals) do
  set(q,'CHAR_等级',20);set(q,'CHAR_经验',0);set(q,'CHAR_血',get(q,'CHAR_最大血'))
 end
 for _,row in ipairs(M:actors(session)) do M:refresh(row) end
 for _,row in ipairs(session.rows) do set(row.proxy,'CHAR_经验',0) end
 R.cases[phase]={skill_level=levels[phase],archive_only=phase==6}
 b=Battle.PVE(p,p,nil,{1},{20},{0});check(b>=0,'victory battle phase '..phase)
end
T:regCallback('BattleSurpriseEvent',function() return 0 end)
T:regCallback('BattleDodgeRateEvent',function(bi,a,d,rate) if bi==b then return 0 end;return rate end)
T:regCallback('DamageCalculateEvent',function(a,d,ori,damage,bi)
 if bi==b then return Char.IsEnemy(d) and 999999 or 0 end;return damage
end)
T:regCallback('GetExpEvent',OrderedCallback(function(q,xp)
 if session then
  local row=M.proxies[q]
  if q==session.normal or row or q==p then
   R.awards[#R.awards+1]={phase=phase,kind=q==p and 'player' or q==session.normal and 'main' or row.bankSlot~=nil and 'bank' or 'carried',actor=q,source=row and row.pet or q,native_xp=xp,battle=Char.GetBattleIndex(q)}
  end
 end
 return xp
end,30000))
T:regCallback('GetExpEvent',OrderedCallback(function(q,xp)
 local row=M.proxies[q]
 if row or (session and (q==session.normal or q==p)) then
  for i=#R.awards,1,-1 do local a=R.awards[i]
   if a.actor==q and a.phase==phase then a.credited_xp=row and row.xp or xp;a.native_after=xp;break end
  end
 end
 return xp
end,-30000))
Cron.AddInterval(1800,function()
 local ok,err=xpcall(function()
  local function player(name)
   local q=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name=name});assert(q>=0)
   set(q,'CHAR_等级',20);set(q,'CHAR_体力',50000);NLG.UpChar(q);set(q,'CHAR_血',get(q,'CHAR_最大血'));return q
  end
  player('BREED_RESERVED')
  p=player('BREED_PLAYER');set(p,'CHAR_职业',510);donor=player('BREED_DONOR')
  local fixture={player=p,donor=donor,player_pointer=tostring(Char.GetCharPointer(p)),donor_pointer=tostring(Char.GetCharPointer(donor)),pets={}}
  for _,owner in ipairs({p,donor}) do for slot=0,owner==p and 4 or 3 do
   local q=Char.GivePet(owner,3004,1);check(q>=0,'native source pet '..owner..':'..slot);originals[#originals+1]=q
   for n=9,0,-1 do if Pet.GetSkill(q,n)>=0 then Pet.DelSkill(q,n) end end
   check(Pet.AddSkill(q,7300)==1,'source normal attack '..q)
   set(q,'CHAR_血',get(q,'CHAR_最大血'))
   if owner==donor then fixture.pets[#fixture.pets+1]={index=q,pointer=tostring(Char.GetCharPointer(q))} end
  end end
  local f=assert(io.open('__OUTPUT__/bank_fixture_request.tmp','wb'));f:write(JSON.encode(fixture));f:close()
  assert(os.rename('__OUTPUT__/bank_fixture_request.tmp','__OUTPUT__/bank_fixture_request.json'))
  local ready=false
  T:AddInterval(100,function()
   if finished then return end
   local yes,error=xpcall(function()
    if not ready then
     local f=io.open('__OUTPUT__/bank_fixture_ready','rb');if not f then return end;f:close();ready=true
     for slot=0,3 do check(Char.GetPoolPet(p,slot)==originals[6+slot],'real bank source '..slot) end
     check(Char.SetPetDepartureState(p,0,2)==1,'main pet selected')
     check(M:enable(p),'nine-pet squad enabled');session=M.active[p];prepare()
    end
    if Char.GetBattleIndex(p)<0 then
     M:tick()
     local count=0;for _,a in ipairs(R.awards) do if a.phase==phase then count=count+1 end end
     check(count==(phase==7 and 2 or 10),'only participating units receive experience phase '..phase)
     local percent=({0,4,40,80,0,0,80})[phase]
     check(M:petExperienceBonus(p)==percent,'DATA-derived strengthening percentage phase '..phase)
     for _,a in ipairs(R.awards) do if a.phase==phase then
      if a.kind=='player' then check(a.native_after==a.native_xp,'player experience is unchanged phase '..phase)
      else
       local expected=math.floor(a.native_xp*(100+percent)/100)
       check(a.credited_xp==expected,'one strengthening bonus '..a.kind..' phase '..phase)
       if percent>0 then check(a.credited_xp>a.native_xp,'positive strengthening bonus '..a.kind..' phase '..phase) end
      end
     end end
     R.cases[phase].main_xp=get(session.normal,'CHAR_经验');R.cases[phase].main_level=get(session.normal,'CHAR_等级')
     R.cases[phase].original_xp={}
     for _,q in ipairs(originals) do R.cases[phase].original_xp[#R.cases[phase].original_xp+1]=get(q,'CHAR_经验') end
     for _,a in ipairs(R.awards) do if a.phase==phase and a.kind~='player' then
      check(get(a.source,'CHAR_等级')==20 and get(a.source,'CHAR_经验')==a.credited_xp,'actual original receives exactly one award '..a.kind..' phase '..phase)
     end end
     local xp=get(session.normal,'CHAR_经验');M:finish(session)
     check(get(session.normal,'CHAR_经验')==xp,'repeat settlement keeps main award phase '..phase)
     phase=phase+1
     if phase>7 then
      local old=Char.HaveSkill(p,70);if old>=0 then Char.DelSkill(p,70,0) end
      local slot=Char.AddSkill(p,70,0,0);Char.SetSkillLevel(p,slot,30,0)
      for level=1,30 do
       Char.SetSkillLevel(p,slot,level,0)
       check(M:petExperienceBonus(p)==(level<=10 and level*4 or 40+(level-10)*2),'native DATA ratio at level '..level)
      end
      Char.SetSkillLevel(p,slot,1,0)
      local ix=Tech.GetTechIndex(7000);local option=Tech.GetData(ix,CONST.TECH_OPTION)
      Tech.SetData(ix,CONST.TECH_OPTION,'AR:9,')
      check(M:petExperienceBonus(p)==9,'live DATA ratio instead of a fixed level formula')
      Tech.SetData(ix,CONST.TECH_OPTION,option);Char.SetSkillLevel(p,slot,30,0)
      R.outside_battle={native_pipeline=GetExpEvent(session.normal,1000)}
      check(R.outside_battle.native_pipeline==1000,'non-battle experience is unchanged')
      check(M:petExperience(p,123)==221,'fractional bonus truncates once')
      check(M:petExperience(p,2147483647)==2147483647,'bonus respects native integer range')
      check(M:petExperience(p,0)==0 and M:petExperience(p,-10)==0,'zero and negative awards cannot create experience')
      finish();return
     end
     prepare()
    end
    if Battle.IsWaitingCommand(p)==1 then
     set(p,'CHAR_BattleCom1',CONST.BATTLE_COM.BATTLE_COM_GUARD);set(p,'CHAR_BattleCom2',0);set(p,'CHAR_BattleCom3',7400)
     set(p,'CHAR_Battle2Com1',CONST.BATTLE_COM.BATTLE_COM_NONE);set(p,'CHAR_BattleMode',3)
    end
    local enemy
    for pos=10,19 do if Battle.GetPlayer(b,pos)>=0 then enemy=pos;break end end
    if enemy and Battle.IsWaitingCommand(session.normal)==1 then Battle.ActionSelect(session.normal,CONST.BATTLE_COM.BATTLE_COM_ATTACK,enemy,7300) end
    M:tick()
   end,debug.traceback)
   if not yes then finish(error) end
  end,1)
 end,debug.traceback)
 if not ok then finish(err) end
end,0)
