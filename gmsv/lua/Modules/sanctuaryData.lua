-- Shared placement catalog used by NPCPart, so individual module reloads keep
-- all service NPCs in the sanctuary.
local D={floor=60003,mapType=0,name='圣殿',music=230,
  music_file='bin/bgm/puk2_sinden.wav',positions={},
  arrival={x=24,y=36},return_arrival={x=223,y=86},
  entrance={name='圣殿传送石',mapType=0,map=1000,x=223,y=85,direction=4},
  exit={name='法兰返程石',mapType=0,map=60003,x=32,y=34,direction=4}}
local function row(names,xs,y)
 for i,name in ipairs(names) do D.positions[name]={mapType=D.mapType,map=D.floor,x=xs[i],y=y,direction=4} end
end
row({'BOSS技能导师','宠物技能导师'},{34,36},18)
row({'宠物服装制造师','宠物装甲制造师','宠物项圈制造师','宠物晶石制造师'},{16,20,24,28},26)
row({'五宠指挥官','永久技能库管理员','自动加点师','职业进阶导师'},{16,20,24,28},34)
for n=1,10 do
 local lo=(n-1)*20+1;local hi=n*20
 local p={mapType=0,map=D.floor,x=16+((n-1)%5)*4,y=n<=5 and 22 or 30,direction=4}
 D.positions['魔剑装备'..lo..'-'..hi]=p
 D.positions['骑士装备'..lo..'-'..hi]=p
end
return D
