local EM=...

function EM.setDate(str)
  local function tn(s,v) return tonumber(s) or v end
  local d,hour,min,sec = str:match("(.-)%-?(%d+):(%d+):?(%d*)")
  local month,day,year=d:match("(%d*)/?(%d*)/?(%d*)")
  local t = os.date("*t")
  t.year,t.month,t.day=tn(year,t.year),tn(month,t.month),tn(day,t.day)
  t.hour,t.min,t.sec=tn(hour,t.hour),tn(min,t.min),tn(sec,0)
  local t1 = os.time(t)
  local t2 = os.date("*t",t1)
  if t.isdst ~= t2.isdst then t.isdst = t2.isdst t1 = os.time(t) end
  EM.setTimeOffset(t1-os.time())
end

EM.EMEvents('start',function(ev) -- Intercept emulator started and check if startTime should be modified
    if EM.startTime then EM.setDate(EM.startTime) end
    EM._info.started = EM.osTime()

--    local st = FB.setTimeout
--    function FB.setTimeout(fun,ms)
--      local f = function()
--        local t = getTime()
--        local stat,res = pcall(fun)
--        setTime(t+ms)
--        if not stat then error(res) end
--      end
--      return st(f,0)
end)
