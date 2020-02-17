--[[
%%LibDevice
properties: {
"name": "Crash notifier",
"type":"com.fibaro.binarySensor",
"variables":{
   "pushID":"0"
   },
"UI":[
  {"button":"enable","text":"Push error -enabled"},
  {"label":"label1","text":""},
  {"label":"label2","text":""},
  {"label":"label3","text":""}
  ]
}
--]]

function startPolling(self)
  local INTERVAL = 3000 -- every second, could do more often...
  local tickEvent = "TICK"
  local function Log(_,...) 
    local a = {...}
    for i=1,#a do local e=a[i]; a[i] = type(e)=='table' and json.encode(e) or tostring(e) end
    self:debug("[L] "..string.format(table.unpack(a))) 
  end
  local LOG = {LOG=""}

  local function post(event) self:event(event) end
  api.post("/customEvents",{name=tickEvent,userDescription="Tock!"})

  local EventTypes = { -- There are more, but these are what I seen so far...
    WeatherChangedEvent = function(self,d) Log(LOG.LOG,"%s, %s -> %s",d.change,d.oldValue,d.newValue) end,
    GlobalVariableChangedEvent = function(self,d)
      --Log(LOG.LOG,"Global %s, %s -> %s",d.variableName,d.oldValue,d.newValue)
      post({type='global', name=d.variableName, value=d.newValue, old=d.oldValue, _sh=true})
    end,
    DevicePropertyUpdatedEvent = function(self,d)
      if d.property=='quickAppVariables' then 
        local old={}; for _,v in ipairs(d.oldValue) do old[v.name] = v.value end -- Todo: optimize
        for _,v in ipairs(d.newValue) do
          if v.value ~= old[v.name] then
            --Log(LOG.LOG,"QuickVar:%s,  %s -> %s",v.name,old[v.name],v.value )
            post({type='quickvar', name=v.name, value=v.value, old=old[v.name], _sh=true})
          end
        end
      else
        if d.property:match("^ui%.") then return end
        --Log(LOG.LOG,"Device:%s:%s, %s -> %s",d.id,d.property,d.oldValue,d.newValue) 
        post({type='property', deviceID=d.id, propertyName=d.property, value=d.newValue, old=d.oldValue, _sh=true})
      end
    end,
    CustomEvent = function(self,d) 
      if d.name == tickEvent then return end
      --Log(LOG.LOG,"CustomEvent:%s",d.name)
      post({type='customevent', name=d.name, _sh=true})
    end,
    PluginChangedViewEvent = function(self,d) end,
    WizardStepStateChangedEvent = function(self,d) end,
    UpdateReadyEvent = function(self,d) end,
    SceneRunningInstancesEvent = function(self,d) end,
    DeviceRemovedEvent = function(self,d) Log(LOG.LOG,"Device %s removed",d.id) end,
    DeviceCreatedEvent = function(self,d) --Log(LOG.LOG,"Device %s created",d.id) 
    end,
    DeviceModifiedEvent = function(self,d) --Log(LOG.LOG,"Device %s modified",d.id) 
    end,
    SceneStartedEvent = function(self,d) Log(LOG.LOG,"Scene %s started",d.id) end,
    SceneFinishedEvent = function(self,d) Log(LOG.LOG,"Scene %s finished",d.id) end,
    SceneRemovedEvent = function(self,d) Log(LOG.LOG,"Scene %s removed (%s)",d.id,d.name) end,
    PluginProcessCrashedEvent = function(self,d) 
          post({type='deviceCrash', deviceID=d.deviceId, error=d.error})
          Log(LOG.LOG,"Device %s crashed",d.deviceId) 
    end,
    onUIEvent = function(self,d) 
      --Log(LOG.LOG,"Device %s %s (UI)",d.deviceId,d.elementName) 
      post({type='uievent', deviceID=d.deviceId, name=d.elementName})
    end,
  }

  local function checkEvents(events)
    for _,e in ipairs(events) do
      --Log(LOG.LOG,e)
      if EventTypes[e.type] then EventTypes[e.type](self,e.data)
      else Log(LOG.LOG,"Unhandled event:%s -- please report",json.encode(e)) end
    end
  end

  local function pollEvents()
    local lastRefresh = 0
    local function pollRefresh()
      local states = api.get("/refreshStates?last=" .. lastRefresh)
      if states then
        lastRefresh=states.last
        if states.events and #states.events>0 then checkEvents(states.events) end
      end
      setTimeout(pollRefresh,INTERVAL)
      fibaro.emitCustomEvent(tickEvent)  -- hack because refreshState hang if no events...
    end
    setTimeout(pollRefresh,INTERVAL)
  end

  pollEvents()
end

------------ main program ------------------
local fmt = string.format
local enabled = true
local messages = {"","",""}
local ID = 0

function QuickApp:enableClicked() 
     enabled=not enabled; 
     setTimeout(function() -- I imagine this sometimes works better...
     self:updateView("enable","text",fmt("Push errors -%s",enabled and "enabled" or "disabled"))
     end,1)
end

function QuickApp:event(sourceTrigger) -- Do whatever at incoming events
   local event = sourceTrigger
   if event.type=='deviceCrash' then
        self:debug("Event:"..json.encode(event))
        table.insert(messages,1,fmt("%s, ID:%s, %s",os.date("%a %b %d %X"),event.deviceID,event.error))
        table.remove(messages,4)
        for i=1,#messages do self:updateView("label"..i,"text",messages[i]) end
        if enabled then fibaro.call(ID,"sendPush",messages[1]) end
   end
end
 
function QuickApp:onInit()
    self:debug("onInit")
    ID = tonumber(self:getVariable("pushID")) or 0
    self:enableClicked()
    startPolling(self)
end