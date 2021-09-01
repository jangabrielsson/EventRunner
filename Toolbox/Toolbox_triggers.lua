--[[
  Toolbox triggers.
  
  Functions to receive triggers from the system - like sourceTrigger in Scenes.
  
  function QuickApp:registerTriggerHandler(handler)   -- Register handler for trigger callback (function(event) ... end)
  function QuickApp:enableTriggerType(trs)            -- Enable trigger type. <string> or table of <strings>
  function QuickApp:enableTriggerPolling(bool)        -- Enable/disable trigger polling loop
  function QuickApp:setTriggerInterval(ms)            -- Set polling interval. Default 1000ms

  Supported events:
  {type='alarm',       id=<id>, property='armed',                value=<value>}
  {type='alarm',       id=<id>, property='breached',             value=<value>}
  {type='alarm',                property='homeArmed',            value=<value>}
  {type='alarm',                property='homeBreached',         value=<value>}
  {type='weather',              property=<prop>,                 value=<value>, old=<value>}
  {type='global-variable',      property=<name>,                 value=<value>, old=<value>}
  {type='quickvar',    id=<id>, name=<name>,                     value=_,       old=_}
  {type='device',      id=<id>, property=<property>,             value=<value>, old=<value>}
  {type='device',      id=<id>, property='centralSceneEvent',    value={keyId=<value>, keyAttribute=<value>}}
  {type='device',      id=<id>, property='accessControlEvent',   value=<value>}
  {type='device',      id=<id>, property='sceneActivationEvent', value=<value>}
  {type='profile',              property='activeProfile',        value=<value>, old=<value>}
  {type='location',    id=<uid>,property=<locationId>,           value=<geofenceAction>, timestamp=<timestamp>}
  {type='custom-event',         name=<name>}
  {type='UpdateReadyEvent',     value=_}
  {type='deviceEvent', id=<id>, value='removed'}
  {type='deviceEvent', id=<id>, value='changedRoom'}
  {type='deviceEvent', id=<id>, value='created'}
  {type='deviceEvent', id=<id>, value='modified'}
  {type='deviceEvent', id=<id>, value='crashed', error=<string>}
  {type='sceneEvent',  id=<id>, value='created'}
  {type='sceneEvent',  id=<id>, value='started'}
  {type='sceneEvent',  id=<id>, value='finished'}
  {type='sceneEvent',  id=<id>, value='instance', instance=d}
  {type='sceneEvent',  id=<id>, value='removed'}
  {type='onlineEvent',           value=<bool>}
--]]

Toolbox_Module = Toolbox_Module or {}
Toolbox_Module.triggers ={
  name = "Trigger manager",
  author = "jan@gabrielsson.com",
  version = "0.4"
}

function Toolbox_Module.triggers.init(self)
  if Toolbox_Module.triggers.inited then return Toolbox_Module.triggers.inited end
  Toolbox_Module.triggers.inited = true

  local TR = { central={}, access={}, activation={}, stats={triggers=0} }
  self.TR = TR
  local ENABLEDTRIGGERS={}
  local INTERVAL = 1000 -- every second, could do more often...
  local propFilters = {}

  function self:triggerDelta(id,prop,value)
    local d = propFilters[id] or {}
    d[prop] =  {delta = value}
    propFilters[id] = d
  end

  local function filter(id,prop,new)
    local d = (propFilters[id] or {})[prop]
    if d then
      if d.last == nil then 
        d.last = new
        return false
      else
        if math.abs(d.last-new) >= d.delta then
          d.last = new
          return false
        else return true end
      end
    else return false end
  end

  local function post(ev)
    if ENABLEDTRIGGERS[ev.type] then
      TR.stats.triggers = TR.stats.triggers+1
      if self.debugFlags.trigger then self:debugf("Incoming trigger2:%s",ev) end
      ev._trigger=true
      --ev.__tostring = _eventPrint
      if self._Events then self._Events.postEvent(ev) end
    end
  end

  local function equal(e1,e2)
    if e1==e2 then return true
    else
      if type(e1) ~= 'table' or type(e2) ~= 'table' then return false
      else
        for k1,v1 in pairs(e1) do if e2[k1] == nil or not equal(v1,e2[k1]) then return false end end
        for k2,_  in pairs(e2) do if e1[k2] == nil then return false end end
        return true
      end
    end
  end

  local EventTypes = { -- There are more, but these are what I seen so far...
    AlarmPartitionArmedEvent = function(d) post({type='alarm', property='armed', id = d.partitionId, value=d.armed}) end,
    AlarmPartitionBreachedEvent = function(d) post({type='alarm', property='breached', id = d.partitionId, value=d.breached}) end,
    HomeArmStateChangedEvent = function(d) post({type='alarm', property='homeArmed', value=d.newValue}) end,
    HomeBreachedEvent = function(d) post({type='alarm', property='homeBreached', value=d.breached}) end,
    HomeDisarmStateChangedEvent = function(_) end,
    WeatherChangedEvent = function(d) post({type='weather',property=d.change, value=d.newValue, old=d.oldValue}) end,
    GlobalVariableChangedEvent = function(d) 
      if d.variableName=="ERTICK" then return end
      post({type='global-variable', name=d.variableName, value=d.newValue, old=d.oldValue}) 
    end,
    DevicePropertyUpdatedEvent = function(d)
      if d.property=='quickAppVariables' then 
        local old={}; for _,v in ipairs(d.oldValue) do old[v.name] = v.value end -- Todo: optimize
        for _,v in ipairs(d.newValue) do
          if not equal(v.value,old[v.name]) then
              post({type='quickvar', id=d.id, name=v.name, value=v.value, old=old[v.name]})
            end
          end
        else
          if d.property == "icon" or filter(d.id,d.property,d.newValue) then return end
          post({type='device', id=d.id, property=d.property, value=d.newValue, old=d.oldValue})
        end
      end,
      CentralSceneEvent = function(d) 
        d.id = d.id or  d.deviceId
        TR.central[d.id]=d;d.icon=nil 
        post({type='device', property='centralSceneEvent', id=d.id, value={keyId=d.keyId, keyAttribute=d.keyAttribute}}) 
      end,
      SceneActivationEvent = function(d) 
        d.id = d.id or  d.deviceId
        TR.activation[d.id]={scene=d.sceneId, name=d.name}; 
        post({type='device', property='sceneActivationEvent', id=d.id, value={sceneId=d.sceneId}})     
      end,
      AccessControlEvent = function(d) 
        TR.access[d.id]=d; 
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
      ClimateZoneChangedEvent = function(d) d.type = 'ClimateZoneChangedEvent' post(d) end,
      ClimateZoneSetpointChangedEvent = function(d) d.type = 'ClimateZoneSetpointChangedEvent' post(d) end,
      DeviceActionRanEvent = function(_) end,
      NotificationCreatedEvent = function(d) post({type='notification', id=d.id, value='created'}) end,
      NotificationRemovedEvent = function(d) post({type='notification', id=d.id, value='removed'}) end,
      NotificationUpdatedEvent = function(d) post({type='notification', id=d.id, value='updated'}) end,
      RoomCreatedEvent = function(d) post({type='room', id=d.id, value='created'}) end,
      RoomRemovedEvent = function(d) post({type='room', id=d.id, value='removed'}) end,
      RoomModifiedEvent = function(d) post({type='room', id=d.id, value='modified'}) end,
      SectionCreatedEvent = function(d) post({type='section', id=d.id, value='created'}) end,
      SectionRemovedEvent = function(d) post({type='section', id=d.id, value='removede'}) end,
      SectionModifiedEvent = function(d) post({type='section', id=d.id, value='modified'}) end,
      DeviceActionRanEvent = function(_) end,
      QuickAppFilesChangedEvent = function(_) end,
      ZwaveDeviceParametersChangedEvent = function(_) end,
      ZwaveNodeAddedEvent = function(_) end,
      RefreshRequiredEvent = function(_) end,
      DeviceFirmwareUpdateEvent = function(_) end,
      GeofenceEvent = function(d) 
        post({type='location',id=d.userId,property=d.locationId,value=d.geofenceAction,timestamp=d.timestamp})
      end,
    }

    local lastRefresh,enabled,firstRun = 0,true,false
    local http = net.HTTPClient()
    math.randomseed(os.time())
    local urlTail = "&lang=en&rand="..math.random(2000,4000).."&logs=false"
    local function loop()
      local stat,res = http:request("http://127.0.0.1:11111/api/refreshStates?last=" .. lastRefresh..urlTail,{
          success=function(res)
            local states = res.status == 200 and json.decode(res.data)
            if states and not firstRun then
              --print(string.format("Sent:%s, got %s",lastRefresh,states.last))
              lastRefresh=states.last
              if states.events and #states.events>0 then 
                for _,e in ipairs(states.events) do
                  --self:tracef("Last:%s, e:%s",lastRefresh,e)
                  local handler = EventTypes[e.type]
                  if handler then handler(e.data)
                  elseif handler==nil and self._UNHANDLED_EVENTS then 
                    self:debugf("[Note] Unhandled event:%s -- please report",e) 
                  end
                end
              end
            end 
            firstRun = false
            if not hc3_emulator then
              setTimeout(loop,INTERVAL or 0)
            else
              hc3_emulator.os.setTimer(loop,INTERVAL)
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