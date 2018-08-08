--[[ 
%% properties 
442 value
463 value
%% globals
--]]

-- User Settings
local debug 	        		= false; 	-- true
local toiletSpot     			= 408;  	-- ToiletSpot

-- function variables
local timeOut         = 2*60;   -- Time before turning of light (in seconds)
local doorCloseDelay  = 3;      -- Time in s from Sensor breached to Door closed to consider inside...
local motionSensor    = 442; 		-- Motion Sensor Toilet
local doorSensor      = 463; 		-- Door Sensor Toilet

local doorOpen      = tonumber(fibaro:getValue(doorSensor, "value")) > 0
local motionBreached 	= tonumber(fibaro:getValue(motionSensor, "value")) > 0
local sleeping= fibaro:countScenes()>1
local trigger = fibaro:getSourceTrigger().type

-- Sensor breached, turn on light
if trigger == motionSensor and motionBreached then
  fibaro:call(toiletSpot,'turnOn')    
  if doorOpen and not sleeping then   -- If door open, start timer to turn off light
    fibaro:sleep(1000*timeOut)
    fibaro:call(toiletSpot,'turnOff')
  else -- else kill all eventual timers  
    fibaro:killScenes(__fibaroSceneId) 
  end
end

-- Door opened, start timer to turn off light
if trigger == doorSensor and doorOpen and not sleeping then
  fibaro:sleep(1000*timeOut)
  fibaro:call(toiletSpot,'turnOff')
end

-- Door closed less than 3s after motion breached, consider people inside bathroom and kill timers.
if trigger == doorSensor and not doorOpen and sleeping then
  if (os.time()-tonumber(fibaro:getModificationTime(motionSensor))) < doorCloseDelay then
    fibaro:killScenes(__fibaroSceneId)
  end
end