local EM,FB=...

function EM.setDate(str)
  local function tn(str,v) return tonumber(str) or v end
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

EM.EMEvents('started',function(ev) -- Intercept QA created and add viewLayout and uiCallbacks
    if EM.startTime then EM.setDate(EM.startTime) end
    EM._info.started = EM.osTime()
  end)
