--[[
  Toolbox triggers.
  
  Functions to receive triggers from the system - like sourceTrigger in Scenes.
  
  function QuickApp:registerTriggerHandler(handler)   -- Register handler for trigger callback (function(event) ... end)
  function QuickApp:enableTriggerType(trs)            -- Enable trigger type. <string> or table of <strings>
  function QuickApp:enableTriggerPolling(bool)        -- Enable/disable trigger polling loop
  function QuickApp:setTriggerInterval(ms)            -- Set polling interval. Default 1000ms

  Supported events:
  {type='alarm', property='armed', id=<id>, value=<value>}
  {type='alarm', property='breached', id=<id>, value=<value>}
  {type='alarm', property='homeArmed', value=<value>}
  {type='alarm', property='homeBreached', value=<value>}
  {type='weather', property=<prop>, value=<value>, old=<value>}
  {type='global-variable', property=<name>, value=<value>, old=<value>}
  {type='device', id=<id>, property=<property>, value=<value>, old=<value>}
  {type='device', id=<id>, property='centralSceneEvent', value={keyId=<value>, keyAttribute=<value>}}
  {type='device', id=<id>, property='accessControlEvent', value=<value>}
  {type='device', id=<id>, property='sceneActivationEvent', value=<value>}
  {type='profile', property='activeProfile', value=<value>, old=<value>}
  {type='custom-event', name=<name>}
  {type='UpdateReadyEvent', value=_}
  {type='deviceEvent', id=<id>, value='removed'}
  {type='deviceEvent', id=<id>, value='changedRoom'}
  {type='deviceEvent', id=<id>, value='created'}
  {type='deviceEvent', id=<id>, value='modified'}
  {type='deviceEvent', id=<id>, value='crashed', error=<string>}
  {type='sceneEvent',  id=<id>, value='started'}
  {type='sceneEvent',  id=<id>, value='finished'}
  {type='sceneEvent',  id=<id>, value='instance', instance=d}
  {type='sceneEvent',  id=<id>, value='removed'}
  {type='onlineEvent', value=<bool>}
--]]

Toolbox_Module = Toolbox_Module or {}

function Toolbox_Module.triggers(self)
  local version = "0.2"
  self:debugf("Setup: Trigger manager (%s)",version)
  self.TR = { central={}, access={}, activation={} }
  local ENABLEDTRIGGERS={}
  local INTERVAL = 1000 -- every second, could do more often...

  local function post(ev)
    if ENABLEDTRIGGERS[ev.type] then
      if self.debugFlags.triggers then self:debugf("Incoming event:%s",ev) end
      ev._trigger=true
      ev.__tostring = _eventPrint
      if self._eventHandler then self._eventHandler(ev) end
    end
  end

  local EventTypes = { -- There are more, but these are what I seen so far...
    AlarmPartitionArmedEvent = function(d) post({type='alarm', property='armed', id = d.partitionId, value=d.armed}) end,
    AlarmPartitionBreachedEvent = function(d) post({type='alarm', property='breached', id = d.partitionId, value=d.breached}) end,
    HomeArmStateChangedEvent = function(d) post({type='alarm', property='homeArmed', value=d.newValue}) end,
    HomeBreachedEvent = function(d) post({type='alarm', property='homeBreached', value=d.breached}) end,
    WeatherChangedEvent = function(d) post({type='weather',property=d.change, value=d.newValue, old=d.oldValue}) end,
    GlobalVariableChangedEvent = function(d) 
      if d.variableName=="ERTICK" then return end
      post({type='global-variable', name=d.variableName, value=d.newValue, old=d.oldValue}) 
    end,
    DevicePropertyUpdatedEvent = function(d)
      if d.property=='quickAppVariables' then 
        local old={}; for _,v in ipairs(d.oldValue) do old[v.name] = v.value end -- Todo: optimize
        for _,v in ipairs(d.newValue) do
          if v.value ~= old[v.name] then
            post({type='quickvar', name=v.name, value=v.value, old=old[v.name]})
          end
        end
      else
        if d.property == "icon" then return end
        post({type='device', id=d.id, property=d.property, value=d.newValue, old=d.oldValue})
      end
    end,
    CentralSceneEvent = function(d) 
      self.TR.central[d.deviceId]=d;d.icon=nil 
      post({type='device', property='centralSceneEvent', id=d.deviceId, value={keyId=d.keyId, keyAttribute=d.keyAttribute}}) 
    end,
    SceneActivationEvent = function(d) 
      self.TR.activation[d.deviceId]={scene=d.sceneId, name=d.name}; 
      post({type='device', property='sceneActivationEvent', id=d.deviceId, value={sceneId=d.sceneId}})     
    end,
    AccessControlEvent = function(d) 
      self.TR.access[d.id]=d; 
      post({type='device', property='accessControlEvent', id=d.id, value=d}) 
    end,
    CustomEvent = function(d) 
      local value = api.get("/customEvents/"..d.name) 
      post({type='custom-event', name=d.name, value=value and value.userDescription}) 
    end,
    PluginChangedViewEvent = function(d) post({type='PluginChangedViewEvent', value=d}) end,
    WizardStepStateChangedEvent = function(d) post({type='WizardStepStateChangedEvent', value=d})  end,
    UpdateReadyEvent = function(d) post({type='updateReadyEvent', value=d}) end,
    DeviceRemovedEvent = function(d)  post({type='deviceEvent', id=d.id, value='removed'}) end,
    DeviceChangedRoomEvent = function(d)  post({type='deviceEvent', id=d.id, value='changedRoom'}) end,
    DeviceCreatedEvent = function(d)  post({type='deviceEvent', id=d.id, value='created'}) end,
    DeviceModifiedEvent = function(d) post({type='deviceEvent', id=d.id, value='modified'}) end,
    PluginProcessCrashedEvent = function(d) post({type='deviceEvent', id=d.deviceId, value='crashed', error=d.error}) end,
    SceneStartedEvent = function(d)   post({type='sceneEvent', id=d.id, value='started'}) end,
    SceneFinishedEvent = function(d)  post({type='sceneEvent', id=d.id, value='finished'})end,
    SceneRunningInstancesEvent = function(d) post({type='sceneEvent', id=d.id, value='instance', instance=d}) end,
    SceneRemovedEvent = function(d)  post({type='sceneEvent', id=d.id, value='removed'}) end,
    SceneCreatedEvent = function(d)  post({type='sceneEvent', id=d.id, value='created'}) end,
    OnlineStatusUpdatedEvent = function(d) post({type='onlineEvent', value=d.online}) end,
    --onUIEvent = function(d) post({type='uievent', deviceID=d.deviceId, name=d.elementName}) end,
    ActiveProfileChangedEvent = function(d) 
      post({type='profile',property='activeProfile',value=d.newActiveProfile, old=d.oldActiveProfile}) 
    end,
    NotificationCreatedEvent = function(_) end,
    NotificationRemovedEvent = function(_) end,
    NotificationUpdatedEvent = function(_) end,
    RoomCreatedEvent = function(_) end,
    RoomRemovedEvent = function(_) end,
    RoomModifiedEvent = function(_) end,
    SectionCreatedEvent = function(_) end,
    SectionRemovedEvent = function(_) end,
    SectionModifiedEvent = function(_) end,
    DeviceActionRanEvent = function(_) end,
    QuickAppFilesChangedEvent = function(_) end,
    ZwaveDeviceParametersChangedEvent = function(_) end,
    ZwaveNodeAddedEvent = function(_) end,
    RefreshRequiredEvent = function(_) end,
  }

  local lastRefresh,enabled = 0,true
  local http = net.HTTPClient()
  local function loop()
    local stat,res = http:request("http://127.0.0.1:11111/api/refreshStates?last=" .. lastRefresh,{
        success=function(res) 
          local states = json.decode(res.data)
          if states then
            lastRefresh=states.last
            if states.events and #states.events>0 then 
              for _,e in ipairs(states.events) do
                local handler = EventTypes[e.type]
                if handler then handler(e.data)
              elseif handler==nil and self._UNHANDLED_EVENTS then 
                self:debugf("[Note] Unhandled event:%s -- please report",e) 
              end
              end
            end
            setTimeout(loop,INTERVAL)
          end  
        end,
        error=function(res) 
          self:errorf("refreshStates:%s",res)
          setTimeout(loop,1000)
        end,
      })
  end
  loop()
  function self:enableTriggerType(trs,enable) 
    if enable ~= false then enable = true end
    if type(trs)=='table' then 
      for _,t in ipairs(trs) do self:enableTriggerType(t) end
    else ENABLEDTRIGGERS[trs]=enable end
  end
  function self:enableTriggerPolling(bool) if bool ~= enabled then enabled = bool end end -- ToDo
  function self:setTriggerInterval(ms) INTERVAL = ms end
end