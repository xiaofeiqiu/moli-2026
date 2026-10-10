local R={status='RUNNING',tiles={},production_accounts_used=false}
Cron.AddInterval(1000,function()
local ok,err=xpcall(function()
 for _,bounds in ipairs({{220,242,81,92},{228,242,110,121}}) do
 for y=bounds[3],bounds[4] do for x=bounds[1],bounds[2] do
  local count,objects=Obj.GetObject(0,1000,x,y)
  local tile={x=x,y=y,walkable=Map.IsWalkable(0,1000,x,y),objects={}}
  for _,o in ipairs(objects or {}) do
   local n=Obj.GetCharIndex(o)
   tile.objects[#tile.objects+1]={object=o,type=Obj.GetType(o),char=n,
     name=n>=0 and Char.GetData(n,CONST.CHAR_名字) or '',
     char_type=n>=0 and Char.GetData(n,CONST.CHAR_类型) or -1,
     image=n>=0 and Char.GetData(n,CONST.CHAR_形象) or -1}
  end
  R.tiles[#R.tiles+1]=tile
 end end end
 R.status='PASS'
end,debug.traceback)
if not ok then R.status='FAIL';R.error=tostring(err) end
local f=assert(io.open('__OUTPUT__','w'));f:write(JSON.encode(R));f:close()
end,0)
