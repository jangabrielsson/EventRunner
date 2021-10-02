--%%name="Sleep2"

function QuickApp:onInit()
  hc3_emulator.EM.cfg.lateTimers=0.5
  a = setTimeout(function() self:debug("C") hc3_emulator.EM.cfg.lateTimers=nil os.exit() end, 1000)
  self:debug("Timer will report late")
  fibaro.sleep(3000)
  self:debug("A")
end