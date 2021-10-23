local EM,FB=...

local LOG,debugFlags=EM.LOG,EM.debugFlags

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

local function sunturnTime(date, rising, latitude, longitude, zenith, local_offset)
  local rad,deg,floor = math.rad,math.deg,math.floor
  local frac = function(n) return n - floor(n) end
  local cos = function(d) return math.cos(rad(d)) end
  local acos = function(d) return deg(math.acos(d)) end
  local sin = function(d) return math.sin(rad(d)) end
  local asin = function(d) return deg(math.asin(d)) end
  local tan = function(d) return math.tan(rad(d)) end
  local atan = function(d) return deg(math.atan(d)) end

  local function day_of_year(date2)
    local n1 = floor(275 * date2.month / 9)
    local n2 = floor((date2.month + 9) / 12)
    local n3 = (1 + floor((date2.year - 4 * floor(date2.year / 4) + 2) / 3))
    return n1 - (n2 * n3) + date2.day - 30
  end

  local function fit_into_range(val, min, max)
    local range,count = max - min
    if val < min then count = floor((min - val) / range) + 1; return val + count * range
    elseif val >= max then count = floor((val - max) / range) + 1; return val - count * range
    else return val end
  end

  -- Convert the longitude to hour value and calculate an approximate time
  local n,lng_hour,t =  day_of_year(date), longitude / 15
  if rising then t = n + ((6 - lng_hour) / 24) -- Rising time is desired
  else t = n + ((18 - lng_hour) / 24) end -- Setting time is desired
  local M = (0.9856 * t) - 3.289 -- Calculate the Sun^s mean anomaly
  -- Calculate the Sun^s true longitude
  local L = fit_into_range(M + (1.916 * sin(M)) + (0.020 * sin(2 * M)) + 282.634, 0, 360)
  -- Calculate the Sun^s right ascension
  local RA = fit_into_range(atan(0.91764 * tan(L)), 0, 360)
  -- Right ascension value needs to be in the same quadrant as L
  local Lquadrant = floor(L / 90) * 90
  local RAquadrant = floor(RA / 90) * 90
  RA = RA + Lquadrant - RAquadrant; RA = RA / 15 -- Right ascension value needs to be converted into hours
  local sinDec = 0.39782 * sin(L) -- Calculate the Sun's declination
  local cosDec = cos(asin(sinDec))
  local cosH = (cos(zenith) - (sinDec * sin(latitude))) / (cosDec * cos(latitude)) -- Calculate the Sun^s local hour angle
  if rising and cosH > 1 then return "N/R" -- The sun never rises on this location on the specified date
  elseif cosH < -1 then return "N/S" end -- The sun never sets on this location on the specified date

  local H -- Finish calculating H and convert into hours
  if rising then H = 360 - acos(cosH)
  else H = acos(cosH) end
  H = H / 15
  local T = H + RA - (0.06571 * t) - 6.622 -- Calculate local mean time of rising/setting
  local UT = fit_into_range(T - lng_hour, 0, 24) -- Adjust back to UTC
  local LT = UT + local_offset -- Convert UT value to local time zone of latitude/longitude
  return os.time({day = date.day,month = date.month,year = date.year,hour = floor(LT),min = math.modf(frac(LT) * 60)})
end

local function getTimezone() local now = EM.osTime() return os.difftime(now, EM.osTime(os.date("!*t", now))) end

local function sunCalc(time)
  local hc3Location = FB.api.get("/settings/location") or {}
  local lat = hc3Location.latitude or 0
  local lon = hc3Location.longitude or 0
  local utc = getTimezone() / 3600
  local zenith,zenith_twilight = 90.83, 96.0 -- sunset/sunrise 90°50′, civil twilight 96°0′

  local date = os.date("*t",time or EM.osTime())
  if date.isdst then utc = utc + 1 end
  local rise_time = os.date("*t", sunturnTime(date, true, lat, lon, zenith, utc))
  local set_time = os.date("*t", sunturnTime(date, false, lat, lon, zenith, utc))
  local rise_time_t = os.date("*t", sunturnTime(date, true, lat, lon, zenith_twilight, utc))
  local set_time_t = os.date("*t", sunturnTime(date, false, lat, lon, zenith_twilight, utc))
  local sunrise = string.format("%.2d:%.2d", rise_time.hour, rise_time.min)
  local sunset = string.format("%.2d:%.2d", set_time.hour, set_time.min)
  local sunrise_t = string.format("%.2d:%.2d", rise_time_t.hour, rise_time_t.min)
  local sunset_t = string.format("%.2d:%.2d", set_time_t.hour, set_time_t.min)
  return sunrise, sunset, sunrise_t, sunset_t
end

local function midnight() local d = os.date("*t",EM.osTime()) d.min,d.hour,d.sec=0,0,0; return os.time(d) end

local function timerQueue() -- A sorted timer queue...
  local tq,pcounter,ptr = {},{}

  function tq.queue(v)    -- Insert timer
    v.tag = v.tag or "user"; pcounter[v.tag] = (pcounter[v.tag] or 0)+1
    if ptr == nil then ptr = v 
    elseif v.time < ptr.time then v.next=ptr; ptr.prev = v; ptr = v
    else
      local p = ptr
      while p.next and p.next.time <= v.time do p = p.next end   
      if p.next then p.next,v.next,p.next.prev,v.prev=v,p.next,v,p 
      else p.next,v.prev = v,p end
    end
    return v
  end

  function tq.dequeue(v) -- remove a timer
    assert(v.dead==nil,"Dead ptr")
    local n = v.next
    pcounter[v.tag]=pcounter[v.tag]-1
    if v==ptr then 
      ptr = v.next 
    else 
      if v.next then v.next.prev=v.prev end 
      v.prev.next = v.next 
    end
    v.dead = true
    v.next,v.prev=nil,nil
    return n
  end

  function tq.clearTimers(id) -- Clear all timers belonging to QA with id
    local p = ptr
    while p do if p.ctx and p.ctx.dev.id == id then p=tq.dequeue(p) else p=p.next end end
  end

  function tq.peek() -- Return next unlocked timer
    local p = ptr
    while p do if not tq.locked(p) then return p,p.time,p.co,p.ctx end p=p.next end 
  end

  function tq.lock(t,b) if t.ctx then t.ctx.env.LOCKED = b and t.co or nil end end
  function tq.locked(t) local l = t.ctx and t.ctx.env.LOCKED; return l and l~=t.co end
  function tq.tags(tag) return pcounter[tag] or 0 end
  function tq.reset() ptr=nil; for k,_ in pairs(pcounter) do pcounter[k]=0 end end
  function tq.get() return ptr end
  tq.milliStr = EM.milliStr
  function tq.dump() local p = ptr while(p) do LOG.sys("%s,%s,%s",p,tq.milliStr(p.time),p.tag) p=p.next end end
  return tq
end

EM.utilities.timerQueue = timerQueue

EM.EMEvents('start',function(_) -- Intercept emulator started and check if startTime should be modified
    if EM.cfg.startTime then EM.setDate(EM.cfg.startTime) end
    EM._info.started = EM.osTime()
    local m,start=midnight(),true
    local function loop()
      EM.sunriseHour,EM.sunsetHour = sunCalc()
      m=m+24*60*60
      if start then 
        LOG.sys("sunrise %s, sunset %s",EM.sunriseHour,EM.sunsetHour)
        start=false
      end
      FB.setTimeout(loop,1000*(m-EM.osTime()),"Sunset updater")
    end
    loop()

    if EM.cfg.speed then
      local procs = EM.procs
      local timers = timerQueue()

      local function killTimers() timers.reset() end

      local function checkForExit(cf,co,stat,res,...)
        local ctx = EM.procs[co]
        if not stat then 
          if type(res)=='table' then
            killTimers()
            if ctx.cont then ctx.cont() end
            if cf then coroutine.yield(co) end
          else 
            EM.checkErr(ctx.env.__TAG,false,res)
          end
        end
        return stat,res,...
      end

      local function timerCall(t,args)
        local co,ctx = table.unpack(args)
        if debugFlags.lateTimer then EM.timerCheckFun(t) end
        local stat,res = coroutine.resume(co)
        ctx.timers[t]=nil
        checkForExit(false,co,stat,res)
      end

      function FB.setTimeout(fun,ms,tag,ctx)
        ctx = ctx or procs[coroutine.running()]
        local co = coroutine.create(fun)
        local v = EM.makeTimer(ms/1000+EM.clock(),co,ctx,tag,timerCall,{co,ctx}) 
        ctx.timers[v] = true
        procs[co] = ctx
        return timers.queue(v) 
      end

      function FB.clearTimeout(ref) timers.dequeue(ref) end

      local function speedScheduler()
        local t,time = timers.peek()     -- Look at first enabled/unlocked task in queue
        if time ~= nil then 
          EM.setTimeOffset(time-EM.socket.gettime())
          timers.dequeue(t)                -- Remove task from queue
          t.fun(t,t.args)                  -- ...and run it 
        end
        EM.systemTimer(speedScheduler,1)
      end
      EM.systemTimer(speedScheduler,0)
    end
  end)
