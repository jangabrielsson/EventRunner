local _=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  verbose=false,
  refreshStates=true,
  modPath = "TQAEmodules/",
  temp = "temp/",
--  speed=true,
  debug = { refreshStates=true },
--  startTime="12/24/2024-07:00", 
}

--%%name="TestScene"
--%%scene=true
-- %%runAtStart=true
--%%noterminate=true

hc3_emulator.create.binarySwitch(35,"lightlit0")
hc3_emulator.create.binarySwitch(69,"lightlit1")
hc3_emulator.create.binarySwitch(70,"lightlit2")
hc3_emulator.create.binarySensor(170,"motion1")
hc3_emulator.create.binarySensor(190,"motion2")
hc3_emulator.create.multilevelSensor(172,"lux1")
hc3_emulator.create.multilevelSensor(192,"lux2")

api.get("/devices/100")

CONDITIONS = {
  conditions = { {
      id = 170,
      isTrigger = true,
      operator = "anyValue",
      property = "value",
      type = "device",
      value = true
    },
    {
      id = 190,
      isTrigger = true,
      operator = "==",
      property = "value",
      type = "device",
      value = true
    }},
  operator = "any"
}


function ACTION()
  print("STARTED")
  print("Testing fibaro.debug...")
  fibaro.debug(sceneId,"DEBUG")
  fibaro.trace(sceneId,"TRACE")
  fibaro.warning(sceneId,"WARNING")
  fibaro.error(sceneId,"ERROR")
  print("...done")

  local light = {35,69,70} -- ID's of all the lights to turnOn and turnOff
  local mainLight = 35 -- ID of Main light
  local lightlit1 = 69 -- ID's Garage light 
  local lightlit2 = 70 -- ID's Laundry light 
  local motion = {170,190} -- ID's the Motions
  local lux = {172,192} -- ID's the Lux
  local maxTime = 1*60  -- Maximum time to wait to turnOff the lights
  local sleepTime = 5 -- check interval (default = 5)
  local safeTime = 0 -- Default value to count until maxTime is reached
  local debug_TAG = "Lights Timer: " ..sceneId -- Tag for the debug messages
  local lightsOn = false -- Default value for Garage an Laundry lights

  if fibaro.getValue(lightlit1,"value") and fibaro.getValue(lightlit2,"value") then -- Check if the Garage an Laundry lights are allready on
    lightsOn = true
  end

  for i in pairs(light) do -- Turn On all the lights
    fibaro.debug(debug_TAG,"Turning on (ID " ..light[i] ..") " ..fibaro.getName(light[i]) .." for " ..maxTime .." seconds")
    fibaro.call(light[i],"turnOn")
  end

  for i in pairs(lux) do -- Show lux level at this moment
    fibaro.debug(debug_TAG,"Current Lux level " ..lux[i] .." " ..fibaro.getName(lux[i]) ..": " ..fibaro.getValue(lux[i],"value"))
  end

  while safeTime < maxTime do -- Loop until maxTime is reached
    fibaro.sleep(sleepTime*1000)                 
    safeTime=safeTime+sleepTime 
    fibaro.debug(debug_TAG," Counting safe time " ..safeTime .." para maxTime " ..maxTime)
    for i in pairs(motion) do 
      if fibaro.getValue(motion[i],"value") then -- Check se Motion violado(s)
        fibaro.debug(debug_TAG,"Reset o Motion sensor " ..motion[i] .." " ..fibaro.getName(motion[i]))
        safeTime = 0 -- Reset safeTime 
      end
    end
  end 

  if lightsOn then -- Check is the Garage and Laundry lights are on
    fibaro.debug(debug_TAG, "Turning off " ..fibaro.getName(mainLight))
    fibaro.call(mainLight,"turnOff") -- TurnOff only the Main light
  else
    for i in pairs(light) do
      fibaro.debug(debug_TAG, " Turning off  " ..light[i] .." " ..fibaro.getName(light[i]))
      fibaro.call(light[i],"turnOff") -- TurnOff all the lights
    end
  end

end