if dofile then
  dofile("fibaroapiHC3.lua")
  local cr = loadfile("credentials.lua"); if cr then cr() end
end

function QuickApp:turnOn() 
  self:debug("ON") 
  self:updateProperty("value",true)
end
function QuickApp:turnOff() 
  self:debug("OFF") 
  self:updateProperty("value",false)
end
function QuickApp:b1Clicked() 
  self:debug("Test clicked")
end
function QuickApp:s1Clicked(val) 
  self:debug("Slider",val)
end

function QuickApp:onInit()
  self:debug("onInit")
end

if dofile then
  local UI = {
    {button='b1', text='Test'},
    {slider='s1', max=100,min=0,text='Slider'}
  }
  DEVICEID = fibaro._createProxy("My First QD",device_type,UI,{})
  fibaro._start(DEVICEID,1000)
end