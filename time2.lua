--[[
%% properties
%% events
%% globals
--]]

function toTime(time)
  local h,m,s,t1,t2 = hmstr:match("(%d+):(%d+):?(%d*)")
  s = h*3600+m*60+(tonumber(s) or 0)
  local t = osDate("*t")
  t.hour,t.min,t.sec = 0,0,0
  t1,t2 = osTime(t)+s,os.time()
  return t1 > t2 and t1 or t1+24*60*60
end

function every2(t,fun) fun() setTimeout(function() every2(t,fun) end,toTime(t)) end
function every(t,fun) setTimeout(function() every2(t,fun()) end,toTime(t)) end
function weekday() return not ("SatSun"):match(os.date("%a")) end

every("06:00",function() if weekday() then fibaro:call(ID,'turnOn') end end)
every("16:00",function() if not weekday() then fibaro:call(ID,'turnOn') end end)
every("08:00",function() if weekday() then fibaro:call(ID,'turnOff') end end)
every("23:59",function() if not weekday() then fibaro:call(ID,'turnOff') end end)