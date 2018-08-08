--[[ 
%% properties 
442 value
463 value
%% globals
--]]

local s = "ffff.%id.%bar"
print(s:gsub("%id","BAR"))
local toiletSpot     	= 408;  	-- ToiletSpot
local motionSensor    = 442; 		-- Motion Sensor Toilet
local doorSensor      = 463; 		-- Door Sensor Toilet
local timeOut         = 2*60;   -- Time before turning of light (in seconds)
local doorCloseDelay  = 3;      -- Time in s from Sensor breached to Door closed to consider inside...
local function pr(msg,...) fibaro:debug(string.format(msg,...)) end

local trigger = fibaro:getSourceTrigger().type
if trigger ~= 'property' then fibaro:abort() end
trigger = trigger.deviceID

local doorOpen      = tonumber(fibaro:getValue(doorSensor, "value")) > 0
local lightOn      = tonumber(fibaro:getValue(toiletSpot, "value")) > 0
local motionBreached 	= tonumber(fibaro:getValue(motionSensor, "value")) > 0
local waiting = fibaro:countScenes() > 1

-- Sensor breached, turn on light
if trigger == motionSensor and motionBreached then
  if not lightOn then
    pr("Motion sensor breached, turning on light")
    fibaro:call(toiletSpot,'turnOn') 
  end
  if not doorOpen then -- else kill all eventual 'waits' 
    pr("Door closed and motion breached, someone inside")
    fibaro:killScenes(__fibaroSelfId)
  end

-- Door opened, start timer to turn off light
elseif trigger == doorSensor and doorOpen and lightOn and not waiting then
  pr("Door open, turning off light after %s seconds",timeOut)
  fibaro:wait(1000*timeOut)
  fibaro:call(toiletSpot,'turnOff')

-- Door breached and motion breached within 2sec, consider people inside bathroom and kill ev. 'waits'
elseif trigger == doorSensor and (not doorOpen) and waiting then
  if math.abs(osTime()-fibaro:getModificationTime(motionSensor,'value')) < doorCloseDelay then
    pr("Door and motion breached within %s seconds, someone inside the bathroom",doorCloseDelay)
    fibaro:killScenes(__fibaroSelfId)
  end
end
