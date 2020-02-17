--[[
%%LibScene
properties: {
"name": "Wait for sensor example",
"mode":"automatic",
"maxRunningInstances": 2,
"restart": false
}
conditions: {
  conditions = { {
      id = 32,
      isTrigger = true,
      operator = "==",
      property = "value",
      type = "device",
      value = true
    } },
  operator = "all"
}
--]]

local fd=fibaro.debug; function fibaro.debug(...) fd("",...) end -- Get back to old style debug without useless tag ;-)

local light = 55
local motion = 32

function loopUntil(fun,cont,secs)
  local function loop() 
     if not fun() then 
         fibaro.setTimeout(1000*secs,loop) 
     else if cont then cont() end end 
  end
  fibaro.setTimeout(1000*secs,loop)
end

fibaro.call(light,"turnOn")    

local safeTime = 0

loopUntil(
 
 function()                                     -- Loop function
  if safeTime >= maxTime then return true end                
  safeTime=safeTime+sleepTime                   -- count up safeTime
  fibaro.debug("Counting up safeTime ",safeTime,maxTime) 
  if fibaro.getValue(motion,'value') > '0' then -- motion breached
     safeTime=0                                 -- reset safeTime
     fibaro.debug("Reset")
  end
 end,
  
 function()                                     -- Stuff to do after loop finished
   fibaro.debug("Turning off")
   fibaro.call(light,"turnOff")    
 end,
  
 sleepTime                                      -- Time to sleep between loops (in seconds)
)           