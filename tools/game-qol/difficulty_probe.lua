-- Compare real enemy stat calculations in a disposable native server.
local R={status='RUNNING',enemies={},controls={}}
local p=-1
local stats={'CHAR_最大血','CHAR_最大魔','CHAR_攻击力','CHAR_防御力','CHAR_敏捷','CHAR_精神','CHAR_回复'}
local bp={'CHAR_体力','CHAR_力量','CHAR_强度','CHAR_速度','CHAR_魔法'}
local function set(q,k,v) assert(CONST[k],k);Char.SetData(q,CONST[k],v) end
local function snapshot(q)
  local r={}
  for _,k in ipairs(stats) do assert(CONST[k],k);r[k]=Char.GetData(q,CONST[k]) end
  return r
end
local function normalize(q,scale)
  for i,k in ipairs(bp) do set(q,k,(10+i*3)*scale*100) end
  Char.UpCharStatus(q)
  return snapshot(q)
end
local ok,err=xpcall(function()
  p=Char.CreateDummy({mapType=0,floor=1000,x=150,y=111,image=100002,name='DIFFICULTY_CHECK'})
  assert(p>=0,'create dummy')
  set(p,'CHAR_等级',100)
  R.controls.player=normalize(p,4)
  set(p,'CHAR_血',Char.GetData(p,CONST['CHAR_最大血']))
  set(p,'CHAR_魔',Char.GetData(p,CONST['CHAR_最大魔']))
  local pet=Char.GivePet(p,3004,1);assert(pet>=0,'create pet')
  R.controls.pet=normalize(pet,4)
  Char.DelSlotPet(p,0)
  for _,id in ipairs({1,11,21}) do
    for _,lv in ipairs({30,80,150}) do
      local b=Battle.PVE(p,p,nil,{id},{lv},{0});assert(b>=0,'create battle')
      local q=-1
      for pos=10,19 do local enemy=Battle.GetPlayer(b,pos);if enemy>=0 then q=enemy;break end end
      assert(q>=0 and Char.IsEnemy(q),'native enemy')
      local row={id=id,level=lv,native=snapshot(q)}
      row.normalized=normalize(q,lv/10)
      R.enemies[#R.enemies+1]=row
      Battle.ExitBattle(p)
      set(p,'CHAR_BattleIndex',-1);set(p,'CHAR_BattleMode',0)
    end
  end
end,debug.traceback)
if p>=0 then
  if Char.GetBattleIndex(p)>=0 then pcall(Battle.ExitBattle,p) end
  pcall(Char.DelDummy,p)
end
R.status=ok and 'PASS' or 'FAIL';R.error=ok and '' or tostring(err)
local f=assert(io.open('__REPORT__','wb'));f:write(JSON.encode(R));f:close()
