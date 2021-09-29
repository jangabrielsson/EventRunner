--%%name="Http1"

function QuickApp:onInit()
  setTimeout(function() self:debug("Async") end,0)
  self:debug("A")
  net.HTTPClient():request("http://worldtimeapi.org/api/timezone/Europe/Stockholm",{
      success=function(resp) self:debug("Success") os.exit() end,
      error=function(resp) self:debug("Error") end
    })
  self:debug("B")
end
