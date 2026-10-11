-- Task-only job checks: each magic swordsman rank can use sword or mage tasks.
local D=dofile('lua/Modules/magicTaskJobsData.lua')
local M={}
function M.isMagic(job) return job>=181 and job<=187 end
function M.range(job,jobs)
 local sword,mage=job-170,job-110
 for _,id in ipairs(jobs) do
  if id==job or (M.isMagic(job) and (id==sword or id==mage)) then return 1 end
 end
 return 0
end
local function compare(value,op,target)
 if op=='==' then return value==target elseif op=='!=' then return value~=target
 elseif op=='>=' then return value>=target elseif op=='<=' then return value<=target
 elseif op=='>' then return value>target elseif op=='<' then return value<target end
 error('Unknown task job comparison: '..tostring(op))
end
local function evaluate(value,c)
 -- Native Event conditions use AND before OR.
 local result,group=false,compare(value,c.tests[1][1],c.tests[1][2])
 for i=2,#c.tests do
  local test=compare(value,c.tests[i][1],c.tests[i][2])
  if c.joins[i-1]=='&&' then group=group and test
  else result=result or group;group=test end
 end
 return result or group
end
function M.has(key) return D[key]~=nil end
function M.check(job,key,family)
 local c=assert(D[key],'Unknown task job check: '..tostring(key))
 local value=c.field=='family' and (family or math.floor(job/10)*10) or job
 if not M.isMagic(job) or c.nativeMagic then return evaluate(value,c) and 1 or 0 end
 local swordValue,mageValue=job-170,job-110
 if c.field=='family' then swordValue,mageValue=10,70 end
 local sword,mage=evaluate(swordValue,c),evaluate(mageValue,c)
 local result
 if c.reject then result=sword and mage else result=sword or mage end
 return result and 1 or 0
end
function M.promotedJob(current,target)
 if M.isMagic(current) then
  if target>=11 and target<=17 then return target+170 end
  if target>=71 and target<=77 then return target+110 end
 end
 return target
end
return M
