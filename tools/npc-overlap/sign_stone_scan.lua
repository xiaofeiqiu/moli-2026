local R={status='RUNNING',tiles={},production_accounts_used=false}
Cron.AddInterval(1500,function()
 local ok,err=xpcall(function()
  for _,bounds in ipairs({{159,169,124,132},{221,239,79,89}}) do
   for y=bounds[3],bounds[4] do for x=bounds[1],bounds[2] do
    local _,objects=Obj.GetObject(0,1000,x,y)
    local ground,image=Map.GetImage(0,1000,x,y)
    local tile={x=x,y=y,walkable=Map.IsWalkable(0,1000,x,y),ground=ground,image=image,objects={}}
    for _,o in ipairs(objects or {}) do
     local kind=Obj.GetType(o)
     local row={object=o,type=kind}
     if kind==1 then
      local n=Obj.GetCharIndex(o)
      row.char=n;row.name=Char.GetData(n,CONST.CHAR_名字)
      row.char_type=Char.GetData(n,CONST.CHAR_类型)
      row.image=Char.GetData(n,CONST.CHAR_形象)
      row.arg=NLG.GetArgNpc(n)
     elseif kind==4 then
      row.toMap=Obj.GetWarpMap(o);row.toFloor=Obj.GetWarpFloor(o)
      row.toX=Obj.GetWarpX(o);row.toY=Obj.GetWarpY(o)
     end
     tile.objects[#tile.objects+1]=row
    end
    R.tiles[#R.tiles+1]=tile
   end end
  end
  R.modules={}
  for _,name in ipairs({'autoStat','sharedTaskGuide','sharedTaskAdapters','skillTraining'}) do
   local m=getModule(name);local row={name=name,loaded=m~=nil,npcs={}}
   for _,n in ipairs(m and m.npcList or {}) do
    row.npcs[#row.npcs+1]={name=Char.GetData(n,CONST.CHAR_名字),x=Char.GetData(n,CONST.CHAR_X),y=Char.GetData(n,CONST.CHAR_Y)}
   end
   R.modules[#R.modules+1]=row
  end
  R.status='PASS'
 end,debug.traceback)
 if not ok then R.status='FAIL';R.error=tostring(err) end
 local f=assert(io.open('__OUTPUT__','wb'));f:write(JSON.encode(R));f:close()
end,0)
