local R={events={}}
regGlobalEvent('ItemOverLapEvent',function(p,a,b,n) R.events[#R.events+1]={p,a,b,n};return 1 end,'enhanceProbe')
local p=Char.CreateDummy({mapType=0,floor=1000,x=225,y=75,image=100002,name='ENHANCE_PROBE'})
local ok,err=xpcall(function()
 local a=Char.GiveItem(p,18005,1,false)
 local b=Char.GiveItem(p,700100,1,false)
 R.items={a,b};R.slots={Char.GetItemSlot(p,a),Char.GetItemSlot(p,b)}
 R.move=Char.MoveItem(p,R.slots[1],R.slots[2],1)
 R.after={Char.GetItemSlot(p,a),Char.GetItemSlot(p,b)}
 R.constants={};for k,v in pairs(CONST) do if k:find('道具_') then R.constants[k]=v end end
end,debug.traceback)
R.error=not ok and err or nil
Char.DelDummy(p)
local f=assert(io.open('__OUTPUT__','w'));f:write(JSON.encode(R));f:close()
