--%%name="Sleep1"

function QuickApp:onInit()
  setTimeout(function() self:debug("C") os.exit() end, 1000)
  self:debug("A")
  fibaro.sleep(3000)
  self:debug("B")
end