-- Misc. patches to the Lua environment for QAs/Scenes 
do
  local oldGet = fibaro.get    -- Return emulated sunrise/sunset
  function fibaro.get(id,prop)
    if id==1 then
      if prop=='sunriseHour' then
        return hc3_emulator.EM.sunriseHour
      elseif prop=='sunsetHour' then
        return hc3_emulator.EM.sunsetHour
      end
    end 
    return oldGet(id,prop)
  end

  if hc3_emulator.EM.cfg.compat then -- patch table.sort with pure Lua version (ToDo gsub)
    table.sort = hc3_emulator.EM.utilities.tableSort
    string.gsub = hc3_emulator.EM.utilities.stringGsub
  end

  local fastJson = hc3_emulator.EM.utilities.encodeFast
  local LOG = hc3_emulator.EM.LOG
  local flags  = hc3_emulator.EM.debugFlags
  
  local function patchFibaro(name)
    local oldF,flag = fibaro[name],"f"..name
    fibaro[name] = function(...)
      local args = {...}
      local res = {oldF(...)}
      if flags.traceFibaro and flags[flag] then
        args = #args==0 and "" or fastJson(args):sub(2,-2)
        LOG.trace("fibaro.%s(%s) => %s",name,args,#res==0 and "nil" or #res==1 and res[1] or fastJson(res))
      end
      return table.unpack(res)
    end
  end

  if hc3_emulator.EM.debugFlags.traceFibaro then
    local funs = {
      "getValue","get","call","sleep","getGlobalVariable","setGlobalVariable","alerm","alert","emitCustomEvent",
      "callGroupAction","getType","getName","getRoomID","getSectionID","getRoomName","getRoomNameByDeviceID",
      "getDevicesID","getIds","scene","profile","setTimeout","clearTimeout","wakeUpDeadDevice"
    }
    for _,name in ipairs(funs) do patchFibaro(name) end
    for _,n in ipairs({"getValue","call","get"}) do
      if hc3_emulator.EM.debugFlags["f"..n] == nil then hc3_emulator.EM.debugFlags["f"..n] = true end
    end
  end
end