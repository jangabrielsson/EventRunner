_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  modPath = "TQAEmodules/",
  refreshStates = true,
  debug = { refreshStates=true },
  temp = "temp/",
  startTime="12/24/2024-07:00",
}

--FILE:fibaroExtra.lua,fibaroExtra;

--%%name="Test FibaroExtra"
--%%type="com.fibaro.binarySwitch"
--%%quickVars = {['x'] = 17, ['y'] = 42 }

function QuickApp:onInit()
  self:debugf("Name:%s, ID:%s",self.name,self.id)
  fibaro.enableSourceTriggers('ClimateZone')
  self:event({type='ClimateZone'},function(env)
      self:debug(json.encode(env.event))
    end)
end