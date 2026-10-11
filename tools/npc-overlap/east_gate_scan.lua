local R={status='RUNNING',tiles={},production_accounts_used=false}
Cron.AddInterval(1500,function()
 local ok,err=xpcall(function()
  for _,bounds in ipairs({{272,284,78,88},{212,222,79,89}}) do
  for y=bounds[3],bounds[4] do for x=bounds[1],bounds[2] do
   local ground,image=Map.GetImage(0,1000,x,y)
   local t={x=x,y=y,ground=ground,image=image,walkable=Map.IsWalkable(0,1000,x,y),objects={}}
   local _,objects=Obj.GetObject(0,1000,x,y)
   for _,o in ipairs(objects or {}) do
    local row={object=o,type=Obj.GetType(o)}
    if row.type==1 then
     local n=Obj.GetCharIndex(o)
     row.name=Char.GetData(n,CONST.CHAR_名字);row.image=Char.GetData(n,CONST.CHAR_形象)
     row.arg=NLG.GetArgNpc(n);row.char=n
    end
    t.objects[#t.objects+1]=row
   end
   R.tiles[#R.tiles+1]=t
  end end end
  R.status='PASS'
 end,debug.traceback)
 if not ok then R.status='FAIL';R.error=tostring(err) end
 local f=assert(io.open('__OUTPUT__','wb'));f:write(JSON.encode(R));f:close()
end,0)
