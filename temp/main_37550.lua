print("Start")
--%%name='TestQA1'
function QuickApp:onInit()
    if not fibaro.getValue(self.id,"value") then
        self:updateProperty("value",true)
      api.post("/plugins/restart",{deviceId=self.id})
    end
    function self:debugf(...) self:debug(string.format(...)) end
    self:debugf("%s - %s",self.name,self.id)
    self:debugf("Name1:%s",fibaro.getName(self.id))
    self:debugf("Name2:%s",api.get("/devices/"..self.id).name)
    self:debugf("Name3:%s",__fibaro_get_device(self.id).name)
    hc3_emulator.installQA{name="MuQA",code=testQA} -- install another QA and run it
end
