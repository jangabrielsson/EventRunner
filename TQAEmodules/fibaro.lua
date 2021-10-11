-- Local module, loaded into each QA's environment
fibaro = {}

function string.split(str, sep)
  local fields,s = {},sep or "%s"
  str:gsub("([^"..s.."]+)", function(c) fields[#fields + 1] = c end)
  return fields
end

function fibaro.alarm(arg1, action)
  if type(arg1) == "string" then fibaro.__houseAlarm(arg1)
  else
    __assert_type(arg1, "number") __assert_type(action, "string")
    local url = "/alarms/v1/partitions/"..arg1.."/actions/arm"
    if action == "arm" then api.post(url)
    elseif action == "disarm" then api.delete(url)
    else error("Wrong parameter: "..action..". Available parameters: arm, disarm", 2) end     
  end
end

function fibaro.__houseAlarm(action)
  __assert_type(action, "string")
  local url = "/alarms/v1/partitions/actions/arm"
  if action == "arm" then api.post(url)
  elseif action == "disarm" then api.delete(url)
  else error("Wrong parameter: '" .. action .. "'. Available parameters: arm, disarm", 3) end
end

function fibaro.alert(alertType, ids, notification)
  __assert_type(alertType, "string") __assert_type(ids, "table") __assert_type(notification, "string")
  local isDefined = "false"
  local actions = { 
    email = "sendGlobalEmailNotifications",
    push = "sendGlobalPushNotifications" 
  }
  if actions[alertType] == nil then
    error("Wrong parameter: '" .. alertType .. "'. Available parameters: email, push", 2) 
  end
  for _, id in ipairs(ids) do __assert_type(id, "number") end      
  for _, id in ipairs(ids) do 
    fibaro.call(id, actions[alertType], notification, isDefined)
  end
end

function fibaro.emitCustomEvent(name)
  __assert_type(name, "string")
  api.post("/customEvents/" .. name)
end

function fibaro.call(deviceId, actionName, ...)
  __assert_type(actionName, "string")
  if type(deviceId) == "table" then
    for _, id in pairs(deviceId) do __assert_type(id, "number") end      
    for _, id in pairs(deviceId) do fibaro.call(id, actionName, ...) end 
    return
  end
  __assert_type(deviceId, "number")
  local arg= {...}; --arg = #arg > 0 and arg or nil
  api.post("/devices/"..deviceId.."/action/"..actionName, { args = arg })
end

function fibaro.callGroupAction(actionName, actionData)
  __assert_type(actionName, "string") __assert_type(actionData, "table")
  local response, status = api.post("/devices/groupAction/" .. actionName, actionData)
  if status ~= 202 then return nil
  else return response["devices"] end
end

function fibaro.get(deviceId, propertyName)
  __assert_type(deviceId, "number") __assert_type(propertyName, "string")
  local property = __fibaro_get_device_property(deviceId, propertyName)
  if property then return property.value, property.modified end
end

function fibaro.getValue(deviceId, propertyName)
  __assert_type(deviceId, "number") __assert_type(propertyName, "string")
  local property = __fibaro_get_device_property(deviceId, propertyName)
  if property then return property.value end
end

function fibaro.getType(deviceId)
  __assert_type(deviceId, "number")
  return (__fibaro_get_device(deviceId) or {}).type
end

function fibaro.getName(deviceId)
  __assert_type(deviceId, 'number')
  return (__fibaro_get_device(deviceId) or {}).name
end

function fibaro.getRoomID(deviceId)
  __assert_type(deviceId, 'number')
  return (__fibaro_get_device(deviceId) or {}).roomID
end

function fibaro.getSectionID(deviceId)
  __assert_type(deviceId, 'number')
  local dev = __fibaro_get_device(deviceId)
  if dev ~= nil then return __fibaro_get_room(dev.roomID).sectionID end
end

function fibaro.getRoomName(roomId)
  __assert_type(roomId, 'number')
  return (__fibaro_get_room(roomId) or {}).name
end

function fibaro.getRoomNameByDeviceID(deviceId)
  __assert_type(deviceId, 'number')
  local dev = __fibaro_get_device(deviceId)
  return dev and fibaro.getRoomName(dev.roomID) or nil
end

function fibaro.getDevicesID(filter)
  if type(filter) ~= 'table' or (type(filter) == 'table' and next(filter) == nil) then
    return fibaro.getIds(__fibaro_get_devices())
  end
  local buff={}
  local function out(s) buff[#buff+1]=s end
  out('/?')
  for c, d in pairs(filter) do
    if c == 'properties' and d ~= nil and type(d) == 'table' then
      for a, b in pairs(d) do
        if b == "nil" then out('property='..tostring(a))
        else out('property=['.. tostring(a)..','..tostring(b)..']') end
      end
    elseif c == 'interfaces' and d ~= nil and type(d) == 'table' then
      for _,b in pairs(d) do out('interface='..tostring(b)) end
    else out(tostring(c).."="..tostring(d)) end
  end
  local args = table.concat(buff,'&')
  return fibaro.getIds(api.get('/devices'..args))
end

function fibaro.getIds(devices)
  local ids = {}
  for _, a in pairs(devices) do
    if a ~= nil and type(a) == 'table' and a['id'] ~= nil and a['id'] > 3 then
      table.insert(ids, a['id'])
    end
  end
  return ids
end

function fibaro.getGlobalVariable(name)
  __assert_type(name, 'string')
  local g = __fibaro_get_global_variable(name)
  if g then return g.value, g.modified end
end

function fibaro.setGlobalVariable (name, value)
  __assert_type(name, 'string') __assert_type(value, 'string')
  api.put("/globalVariables/" .. name, {["value"]=tostring(value), ["invokeScenes"]=true})
end

function fibaro.scene(action, ids)
  __assert_type(action, "string") __assert_type(ids, "table")
  local availableActions = { execute = true , kill = true}
  assert(availableActions[action],"Wrong parameter: " .. action .. ". Available actions: execute, kill") 
  for _, id in ipairs(ids) do __assert_type(id, "number") end      
  for _, id in ipairs(ids) do api.post("/scenes/"..id.."/"..action) end
end

function fibaro.profile(action, profileId)
  __assert_type(profileId, "number") __assert_type(action, "string")
  local availableActions = { activateProfile = "activeProfile"} 
  assert(availableActions[action],"Wrong parameter: "..action..". Available actions: activateProfile") 
  api.post("/profiles/"..availableActions[action].."/"..profileId)
end

function getPartition(id) 
  __assert_type(id, "number")
  return __fibaro_get_partition(id)
end

function fibaro.setTimeout(timeout, action)
  __assert_type(timeout, "number") __assert_type(action, "function")
  return setTimeout(action, timeout)
end

function fibaro.clearTimeout(timeoutId)
  __assert_type(timeoutId, "table")
  clearTimeout(timeoutId)
end

function fibaro.wakeUpDeadDevice(deviceID)
  __assert_type(deviceID, 'number')
  fibaro.call(1, 'wakeUpDeadDevice', deviceID)
end

function fibaro.sleep(ms)
  __assert_type(ms, "number")
  __fibaroSleep(ms)
end

local function d2str(...) local r,s={...},{} for i=1,#r do if r[i]~=nil then s[#s+1]=tostring(r[i]) end end return table.concat(s," ") end
function fibaro.debug(tag,...)  __assert_type(tag,"string") __fibaro_add_debug_message(tag,d2str(...),"DEBUG") end
function fibaro.warning(tag,...) __assert_type(tag,"string") __fibaro_add_debug_message(tag,d2str(...),"WARNING") end
function fibaro.trace(tag,...) __assert_type(tag,"string") __fibaro_add_debug_message(tag,d2str(...),"TRACE") end
function fibaro.error(tag,...) __assert_type(tag,"string") __fibaro_add_debug_message(tag,d2str(...),"ERROR") end

function fibaro.useAsyncHandler(value)
  __assert_type(value, "boolean")
  __fibaroUseAsyncHandler(value) 
end