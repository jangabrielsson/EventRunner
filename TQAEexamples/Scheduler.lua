_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  verbose=false,
  modPath = "TQAEmodules/",
  temp = "temp/",
  startTime="12/24/2024-07:00:50",
}

--%%name="Scheduler"
--%%type="com.fibaro.binarySwitch"
--%%noterminate = true

local _version = "0.1"
--QA adaption of https://forum.fibaro.com/topic/49608-hc3-scenes-schedule-actions-on-times/

dayMap={"Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"}

local lamp = 114
local motion = 117

-- The function 'clock' is called every minute, define your tests and actions inside the function
--- Variable 'time' is the current time as a string, ex. "17:42"
--- Variable 'sunset' is today's sunset time as a string ex. "21:33"
--- Variable 'sunrise' is today's sunrise time as a string ex. "06:35"
--- Variable 'day' is name of day ex. "Monday"
--- Variable 'weekend' is true if it's weekend (Saturday,Sunday)
function clock(time,sunrise,sunset,day,weekend) -- called every minute, on the minute

  quickApp:debug("Time:"..time)

  -- Add your Lua tests here

  if time=="21:31" and fibaro.getGlobal("Home_Away")=="Away" then -- at 21:31 if global variable is set to 'Away'
    fibaro.call(lamp,"turnOn")
  end

  if time=="21:45" and day=="Monday" then -- at 21:45 if it's Monday
    fibaro.call(lamp,"turnOff")
  end

  if time=="21:00" and weekend then -- at 21:00 on weekends
    fibaro.call(lamp,"turnOff")
  end

  if time==sunrise and not weekend then  -- at sunrise on weekdays
    fibaro.call(lamp,"turnOff")
  end

  if time>sunrise and time<sunset and time:match("00$") then -- every hour between sunrise and sunset
    fibaro.call(lamp,"turnOff")
  end

  if (time>sunset or time<sunrise) and time:match("00$") then  -- every hour between sunset and sunrise
    fibaro.call(lamp,"turnOff")
  end

  if tonumber(time)==tonumber(sunrise)-tonumber("00:10") and weekend then -- at 10min before sunrise on weekend
    fibaro.call(lamp,"turnOff")
  end

  if time>sunrise and time<sunset and       -- Between sunrise and sunset
  fibaro.getValue(lamp,"state") and       -- and lamp is on
  not fibaro.getValue(motion,"state") and -- and motion sensor is safe
  lastChanged(motion,'state') > 5*60      -- and the last time the motion sensor changed state was (more than) 5min ago
  then  
    fibaro.call(lamp,"turnOff")            -- then turn off lamp
  end   

end

--------- Helper functions, don't touch----------------
function lastChanged(id,prop) return os.time()-select(2,fibaro.get(id,prop)) end
tonumber,oldTonumber=function(str) 
  local h,m,s=str:match("(%d%d):(%d%d):?(%d*)")
  return h and m and h*3600+m*60+(s~="" and s or 0) or oldTonumber(str)
end,tonumber

local function scheduler()
  local d = os.date("*t").wday
  local ss,sr = fibaro.getValue(1,"sunsetHour"),fibaro.getValue(1,"sunriseHour")
  clock(os.date("%H:%M"),sr,ss,dayMap[d],d==1 or d==7)
end

function QuickApp:onInit()
  self:debug("Scheduler",_version)
  local time = (os.time() // 60 +1)*60
  local function loop()
    scheduler()
    time = time+60
    setTimeout(loop,1000*(time-os.time()))
  end
  self:debug("Starting at next even minute...") -- e.g. 07:01
  setTimeout(loop,1000*(time-os.time()))
end