if dofile and not hc3_emulator then
  hc3_emulator = {
    name = "My QA",    -- Name of QA
    poll = 2000,       -- Poll HC3 for triggers every 2000ms
    offline = true,
  }
  dofile("fibaroapiHC3.lua")
end--hc3

local data = [[{"shadeIds":[50173,40999,7342],"shadeData":[{"id":50173,"type":55,"capabilities":4,"batteryKind":1,"smartPowerSupply":{"status":0,"id":0,"port":0},"batteryStatus":0,"batteryStrength":0,"roomId":59205,"firmware":{"revision":1,"subRevision":8,"build":1944},"name":"U3R1ZSBMYW1lbA==","signalStrength":0,"motor":{"revision":50,"subRevision":48,"build":11826},"positions":{"posKind1":1,"position1":65483,"posKind2":3,"position2":400},"groupId":11973},{"id":40999,"type":54,"capabilities":4,"batteryKind":1,"smartPowerSupply":{"status":0,"id":0,"port":0},"batteryStatus":0,"batteryStrength":0,"roomId":36806,"firmware":{"revision":1,"subRevision":8,"build":1944},"name":"S0EgQWxrb3Zl","signalStrength":0,"groupId":6735,"motor":{"revision":50,"subRevision":48,"build":11826},"positions":{"posKind1":1,"position1":65534,"posKind2":3,"position2":58360}},{"id":7342,"type":55,"capabilities":4,"batteryKind":1,"smartPowerSupply":{"status":0,"id":0,"port":0},"batteryStatus":0,"batteryStrength":0,"roomId":36806,"firmware":{"revision":1,"subRevision":8,"build":1944},"name":"S0EgTlkgVsOmZw==","positions":{"posKind1":1,"position1":65535,"posKind2":3,"position2":20},"signalStrength":4,"groupId":45116,"motor":{"revision":50,"subRevision":48,"build":11826}}]}]]

local function saveData(data)
  data = json.decode(data)
  for _,s in ipairs(data.shadeData) do
    print(s.id,s.positions.position1)
  end
end

function QuickApp:onInit()
  self:debug(self.name, self.id)
  saveData(data)
end

