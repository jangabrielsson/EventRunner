if dofile and not hc3_emulator then
  hc3_emulator = {
    name = "My QA",    -- Name of QA
    poll = 2000,       -- Poll HC3 for triggers every 2000ms
    --offline = true,
  }
  dofile("fibaroapiHC3.lua")
end--hc3

function QuickApp:onInit()
  self:debug(self.name, self.id)
  api.post("/scenes/26/execute",(json.encode({
      alexaProhibited = true,
      args = {{mtest=42}}
    })))
end

