--[[
%%LibDevice
properties: {
"name": "Test device2",
"type":"com.fibaro.binarySensor",
"variables":{
   "myVar":"This is a test"
   },
"UI":[
  {"button":"button1","text":"B1"},
  [{"button":"button2","text":"B2"},{"button":"button3","text":"B3"}],
  {"slider":"slider1","text":"","min":0,"max":100},
  {"label":"label1","text":"L1"}
  ]
}
--]]

function QuickApp:onInit()
   self:debug("Device2")
end
