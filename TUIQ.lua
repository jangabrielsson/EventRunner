_=loadfile and loadfile("TQAE.lua"){
logLevel=5
  } 

--%%name="MyQA" 
--%%noterminate=true
--%%u1={label='info',text=""}
--%%u2={{button='b1',text="On", f="MyTurnOn"},{button='b2',text="Off", f="MyTurnOff"}}
--%%u3={slider='s1',value="50", f="MySlide"}

version = 0.2

function QuickApp:MyTurnOn()
  self:debug("On")
end

function QuickApp:MyTurnOff()
  self:debug("Off")
end

function QuickApp:MySlide(ev)
  self:debug("Value",ev.values[1])
end

function QuickApp:onInit()
  self:debug(self.name,self.id)
  self:updateView("info","text","Version v"..version)
  self:updateView("s1","value","67")
end