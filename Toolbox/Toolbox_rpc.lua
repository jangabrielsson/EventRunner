--[[
  Toolbox rpc.
  
  Functionality to make synchronous function calls to functions in other QAs.
  Exported functions need to be global (not 'local' declared)
  To export functions:
  
  function foo(a,b) return a+b end
  function bar(a) return 10*a end
  self:exportRPC{{name="foo",doc="Adds its arguments"},{name="bar","Multiplies by 10"}})
  
  
  To import functions:
  
  self:importRPC(deviceId)
  
  This will import and declare foo(a,b) and bar(a) from QA with device id 'deviceId'.
  There is a possibility to add a default timeout value to the imported functions and add them to a table instead of the global environment
  Default timeout is 3s
--]]

Toolbox_Module = Toolbox_Module or {}

function Toolbox_Module.rpc(self)
  local version = "0.1"
  self:debugf("Setup: RPC manager (%s)",version)

  local var,n = "RPC_"..self.id,0
  api.post("/globalVariables",{name=var,value=""})

  local function rpc(id,fun,args,timeout)
    fibaro.setGlobalVariable(var,"")
    n = n + 1
    fibaro.call(id,"RPC_CALL",var,n,fun,args)
    timeout = os.time()+(timeout or 3)
    while os.time() < timeout do
      local r = fibaro.getGlobalVariable(var)
      if r~="" then 
        r = json.decode(r)
        if r[1] == n then
          if not r[2] then error(r[3],3) else return select(3,table.unpack(r)) end
        end
      end
    end
    error(format("RPC timeout %s:%d",fun,id),3)
  end

  function QuickApp:RPC_CALL(var,n,fun,args)
    local res = {n,pcall(_G[fun],table.unpack(args))}
    fibaro.setGlobalVariable(var,json.encode(res))
  end

  function self:defineRPC(id, fun, timeout, tab) tab[fun]=function(...) return rpc(id, fun, {...}, timeout) end end

  function self:exportRPC(funList) self:setVariable("ExportedFuns",json.encode(funList)) end

  function self:importRPC(id,timeout,tab) 
    local d = __fibaro_get_device(id)
    assert(d,"Device does not exist")
    for _,v in ipairs(d.properties.quickAppVariables or {}) do
      if v.name=='RPCexports' then
        for _,e in ipairs(v.value) do
          e = type(e)=='string' and {name=e} or e
          self:debugf("RPC function %d:%s - %s",id,e.name,e.doc or "")
          self:defineRPC(id, e.name, timeout, tab or _G)
        end
      end
    end
  end
end