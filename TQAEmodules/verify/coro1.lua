--%%name="Coro1"

local function coprotect(stat,...) if not stat then fibaro.error(__TAG,json.encode(...)) end end

function netFHttp(method,url) -- synchronous http call
  local co = coroutine.running()
  net.HTTPClient():request(url,
    { options = { method = method },
      success = function(res) coprotect(coroutine.resume(co,res)) end,
      error = function(res) coprotect(coroutine.resume(co,res)) end
    })
  return coroutine.yield()
end

function QuickApp:onInit()
  setTimeout(function() self:debug("Async") end,0)
  self:debug("A")
  self:debug(json.decode(netFHttp("GET","http://worldtimeapi.org/api/timezone/Europe/Stockholm").data).datetime)
  self:debug("B")
  os.exit()
end