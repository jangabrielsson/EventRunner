do 
  -- This is a PoC showing that we can get synchronous fibaro.call with return values if 
  -- we have access to coroutines -- Note TQAE supports coroutine for QAs...
  -- Support for synchronous actionHandler and fibaro.call
  -- support for sync net.HTTPClient, and non-blocking fibaro.sleep
  
  local dir,timeout = {},60*1000  -- One minute default?
  local oldCall = fibaro.call
  local function coprotect(stat,res) if not stat then fibaro.error(__TAG,res) end end
  
  function QuickApp:callAction(name,...)      -- Redefine callAction to return value
    if self[name] then return self[name](self,...) end
  end

  function QuickApp:actionHandler(event)
    if event.actionName == 'SYNC_CALL' then
      local name,from,tag = event.args[1],event.args[2],event.args[3]
      local vals = {pcall(self.callAction,self,name,select(4,table.unpack(event.args)))}
      orgCall(from,"SYNC_RETURN",tag,vals)
    else
      self:callAction(event.actionName,table.unpack(event.args))
    end
  end

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
