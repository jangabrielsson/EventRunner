--[[
%% properties
175 value
%% events
%% globals
%% autostart
--]]

if dofile and not _EMULATED then _EMULATED={name="Test",id=10,maxtime=24} dofile("HC2.lua") end


local startSource = fibaro:getSourceTrigger();
if fibaro:countScenes() > 1 then fibaro:abort() end 

if (tonumber(fibaro:getValue(175, "value")) < 1) then

  local WarningBrightness = 255
  local WarningHueValue = 65535

  local HueDevices = {249,431,432,433,434}
  local HueArray={}
  -- Store state of the lights(ON/OFF, Color, Saturation, Brrightness) into a nested table
  for k,v in ipairs(HueDevices) do
    local ID = (HueDevices[k])
    local On = fibaro:getValue(v, "on")
    local Hue = fibaro:getValue(v, "hue")
    local Saturation = fibaro:getValue(v, "ui.saturation.value")
    local Brightness = fibaro:getValue(v, "ui.brightness.value")
    table.insert(HueArray,{ID, On, Hue, Saturation, Brightness})

  end

  for k,v in pairs(HueArray) do

    for k,v in pairs(HueArray[k]) do
      if tonumber(fibaro:getValue(v, "on")) == 0 then
        fibaro:call(v, "turnOn");
        fibaro:call(v, "changeHue", WarningHueValue );
        fibaro:call(v, "changeBrightness", 254);
        fibaro:call(v, "changeSaturation", 255);
      elseif tonumber(fibaro:getValue(v, "on")) == 1 then
        fibaro:call(v, "changeHue", WarningHueValue);
        fibaro:call(v, "changeBrightness", 254);
        fibaro:call(v, "changeSaturation", 254);        
      end 
    end
  end 

  fibaro:sleep(6*1000)

  for i = 1, #HueArray do
    local ID = tonumber(HueArray[i][1])
    local On = tonumber(HueArray[i][2])
    local Hue = tonumber(HueArray[i][3])
    local Saturation = tonumber(HueArray[i][4])
    local Brightness = tonumber(HueArray[i][5])

    if On == 1 then
      fibaro:call(ID,"changeHue",Hue);
      fibaro:call(ID, "changeBrightness", Brightness);
      fibaro:call(ID, "changeSaturation", Saturation);             
    elseif On == 0 then
      fibaro:call(ID,"changeHue",Hue)
      fibaro:call(ID, "changeBrightness", Brightness);
      fibaro:call(ID, "changeSaturation", Saturation);
      fibaro:call(ID,"turnOff");
    end
  end

  HueDevices = nil
  HueArray= nil

end