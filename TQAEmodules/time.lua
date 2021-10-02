local EM,FB=...

local LOG=EM.LOG

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
  local hc3Location = FB.api.get("/settings/location")
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

EM.EMEvents('start',function(ev) -- Intercept emulator started and check if startTime should be modified
    if EM.cfg.startTime then EM.setDate(EM.cfg.startTime) end
    EM._info.started = EM.osTime()
    local m,start=midnight(),true
    local function loop()
      EM.sunriseHour,EM.sunsetHour = sunCalc()
      m=m+24*60*60
      if start then 
        LOG.sys("sunrise %s, sunset %s",EM.sunriseHour,EM.sunsetHour)
        stsrt=false
      end
      EM.systemTimer(loop,1000*(m-EM.osTime()),"Sunset updater")
    end
    loop()
    
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
