do -- support for sync fibaro.call, net.HTTPClient, and non-blocking fibaro.sleep
  local dir,timeout = {},60*1000  -- One minute default?
  local oldCall = fibaro.call
  local function coprotect(stat,res) if not stat then fibaro.error(__TAG,res) end end
  function fibaro.setCallTimeout(ms) timeout = ms end
  
  function fibaro.sleep(ms) -- sleep that doesn't block other threads
    local co = coroutine.running(); setTimeout(function() coprotect(coroutine.resume(co)) end,ms); coroutine.yield()
  end

  function netFHttp(method,url) -- synchronous http call
    local co = coroutine.running()
    net.HTTPClient():request(url,
      { options = { method = method },
        success = function(res) coprotect(coroutine.resume(co,res)) end,
        error = function(res) coprotect(coroutine.resume(co,res)) end
      })
    return coroutine.yield()
  end

  local function returnHandler(tag,vals)
    if dir[tag] then local co = dir[tag]; dir[tag]=nil; coprotect(coroutine.resume(co,vals)) end
  end

  function fibaro.call(id,method,...)
    local tag = tostring({}):match("%s(.*)")
    oldCall(id,"SYNC_CALL",method,plugin.mainDeviceId,tag,...)
    dir[tag]=coroutine.running()
    local timer = setTimeout(function() 
        if dir[tag] then returnHandler(tag,{false,'timeout'}) end
      end
      ,timeout)
    local res = coroutine.yield()
    clearTimeout(timer)
    if res[1] then return select(2,table.unpack(res))
    else fibaro.error(__TAG,res[2]) error(res) end -- Should do a print(debug.traceback()) here
  end

  function QuickApp:SYNC_RETURN(tag,vals) returnHandler(tag,vals) end
end

--------- Here is QA200 -----------
function QuickApp:onInit()
  quickApp=self
  self:debug("onInit",self.name,self.id)
  setTimeout(function() fibaro.sleep(2000); self:debug("Ping") end,1000) -- do other stuff
  local data = netFHttp("GET","http://worldtimeapi.org/api/timezone/Europe/Stockholm")
  if data.data then
    self:debug("Local time in Stockholm:",json.decode(data.data).datetime)
  else 
   self:error(data)
  end
  --fibaro.setCallTimeout(2000) -- test timeout behaviour
  self:debug("Calling other QA: test(17,42)")
  local res = fibaro.call(100,"test",17,42)
  self:debug("Result ",tostring(res))
end
