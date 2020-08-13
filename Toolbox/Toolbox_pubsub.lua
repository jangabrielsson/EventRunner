--[[
  Toolbox pubsub.
  
  QuickApp:publish(events)   -- event is of table {type='<type>', <key1>=.., <keyn>=...}
  QuickApp:subscribe(events)
  
  Requires Toolbox_basic
  Requires Toolbox_triggers

--]]

Toolbox_Module = Toolbox_Module or {}
Toolbox_Module.pubsub ={
  name = "PubSub manager",
  author = "jan@gabrielsson.com",
  version = "0.1"
}


function Toolbox_Module.pubsub.init(self)
  local SUB_VAR = "TPUBSUB"
  local function DEBUG(...) if self.debugFlags.pubsub then self:debugf(...) end end
  local mySubscriptions = {}
  local subList = {}
  local peers = {}

  local function isEvent(event) return type(event)=='table' and event.type end

  local function equal(e1,e2)
    if type(e1)~=type(e2) then return false
    elseif type(e1) == 'table' then
      local seen={}
      for k,v in pairs(e1) do if not equal(v,e2[k]) then return false else seen[k]=true end end
      for k,v in pairs(e2) do if not seen[k] then return false end end
      return true
    else return e1==e2 end
  end

  local function partialEqual(e1,e2) -- partial: {a=9} == {a=9, b=19}
    if type(e1)~=type(e2) then return false
    elseif type(e1) == 'table' then
      for k,v in pairs(e1) do if not equal(v,e2[k]) then return false end end
      return true
    else return e1==e2 end
  end

  local function member(elm,list) for _,e in ipairs(list) do if equal(elm,e) then return true end end return false end
  local function remove(elm,list) for i=1,#list do if equal(elm,list[i]) then table.remove(list,i) return end end end

  local match = partialEqual
  local function compile(expr) return expr end
  if self.EM then
    match = self.EM.match
    compile = self.EM.compilePattern
  end

  local function getSubscribers(event)
    local subs = {}
    local subSub = subList[event.type]
    if subSub then
      for _,e in ipairs(subSub) do
        if match(e.pattern,event) then 
          for _,id in ipairs(e.ids) do subs[id]=true end
        end
      end
    end
    return subs
  end

  local function clearSubscriptions(id)
    for _,subs in pairs(subList) do
      for _,e in ipairs(subs) do remove(id,e.ids) end
    end
    DEBUG("Clearing subscriptions for %s",id)
  end

  local function addSubscriber(id,event)
    local subSub = subList[event.type]
    if subSub then
      for _,e in ipairs(subSub) do
        if equal(event,e.event) then
          if not member(id,e.ids) then e.ids[#e.ids+1]=id  end
          return
        end
      end
      subSub[#subSub+1]={event=event,pattern=compile(event),ids={id}}
    else 
      subList[event.type] = {{event=event,pattern=compile(event),ids={id}}}
    end
  end

  function self:publish(event,t)
    assertf(isEvent(event),"Published event %s is missing .type",event==nil and "nil" or event)
    local subs = getSubscribers(event)
    if next(subs)==nil then DEBUG("No subscriber for %s",event) return end
    setTimeout(function() 
        for id,_ in pairs(subs) do   -- Send to all subscribers of this type of event
          fibaro.call(id,"SUBSCRIBEDEVENT",event)
          DEBUG("Sending event '%s' to %d",event,id)
        end
      end,t or 0)
  end

  function self:subscribe(sub)                    -- Tell everyone that I'm subscribing to this event (too)
    assertf(isEvent(sub),"Subscribed event %s is missing .type",sub==nil and "nil" or sub)
    for _,s in ipairs(mySubscriptions) do          -- check for duplicates
      if equal(s,sub) then DEBUG("Subscription already exist") return end 
    end 
    mySubscriptions[#mySubscriptions+1]=sub
    self:setVariable(SUB_VAR,mySubscriptions)
    for id,_ in pairs(peers) do
      fibaro.call(id,"SYNCPUBSUB",self.id,sub)
    end
    DEBUG("Subscribed to '%s'",sub)
  end

  function self:broadcast(event)                  -- Publish to everyone
    for id,_ in pairs(peers) do
      fibaro.call(id,"SUBSCRIBEDEVENT",event)
    end
  end

  function self:SUBSCRIBEDEVENT(events)            -- Someone sent me event(s) that I have subscribed for
    events = (next(events)==nil or events[1]) and events or {events}
    for _,e in ipairs(events) do
      DEBUG("Incoming event: %s",e)
      self._Events.postEvent(e)
    end
  end

  function self:SYNCPUBSUB(id, subs)              -- Someone tells me about its subscriptions
    if id==self.id then return end
    subs = (next(subs)==nil or subs[1]) and subs or {subs}
    for _,s in ipairs(subs) do addSubscriber(id,s) end
    DEBUG("Got subscriptions (%s) from %s",subs,id)
    peers[id]=true
  end

  local function handleEvent(ev)
    if ev.type=='deviceEvent' and peers[ev.id] then
      if ev.value == 'removed' or ev.value == 'crashed' then
        clearSubscriptions(ev.id)
        peers[ev.id]=nil
      end
    end
  end

  local function getOthersSubscriptions()
    local devs,code = api.get("/devices/?property=[model,"..(self._MODEL or "ToolboxUser").."]")
    for _,d in ipairs(devs or {}) do
      peers[d.id]=true
      for _,v in ipairs(d.properties.quickAppVariables or {}) do
        if v.name == SUB_VAR then
          local stat,subs = pcall(function()
              local r = {}
              if type(v.value)=='string' then r = json.decode(v.value)
              elseif type(v.value) == 'table' then r = v.value end
              return r
            end)
          if stat then 
            for _,s in ipairs(subs) do addSubscriber(d.id,s) end 
            DEBUG("Adding subscriptions fromn %d - %s",d.id,subs)
            end
        end
        break
      end -- for vars
    end -- for devices
  end --function

  self:setVariable(SUB_VAR,{})
  getOthersSubscriptions() -- Ask for subscriptions when we start up / restarts
  if self.enableTriggerType then self:enableTriggerType({"deviceEvent"}) end

  self._Events.addEventHandler(handleEvent,true)
end
