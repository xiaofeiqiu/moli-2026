from validate_shared_tasks_native import RUN,OUT,start,stop
import json,collections
probe=r'''local r={sizes={},images={}}
for _,f in ipairs({55,60050,27961,18007,4461,6005,60264,1000}) do
 local z={}; r.sizes[tostring(f)]=z
 for _,t in ipairs({0,1,2,3,4,5,6,7,8,9,10,11,12,13}) do
  local ok,w,h=pcall(Map.GetMapSize,t,f)
  z[tostring(t)]={ok=ok,w=w,h=h}
 end
 local p={}; r.images[tostring(f)]=p
 for _,c in ipairs({{0,0},{1,0},{0,1},{10,10},{50,50}}) do
  local ok,a,b=pcall(Map.GetImage,0,f,c[1],c[2])
  p[#p+1]={x=c[1],y=c[2],ok=ok,a=a,b=b}
 end
end
local f=assert(io.open('../../../../../docs/cg71_content_audit/shared_integration/map_format_native.json','w')); f:write(JSON.encode(r));f:close()
'''
(RUN/'lua/shared_map_probe.lua').write_text(probe,encoding='ascii')
(RUN/'lua/ModuleConfig.lua').write_text("moduleInitial()\ndofile('lua/shared_map_probe.lua')\n",encoding='ascii')
start()
