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
  if Toolbox_Module.pubsub.inited then return Toolbox_Module.pubsub.inited end
  Toolbox_Module.pubsub.inited = true
  local SUB_VAR = "TPUBSUB"
  local idSubs = {}
  local function DEBUG(...) if self.debugFlags.pubsub then self:debugf(...) end end

  local function copy(e) -- shallow
    if type(e)=='table' then
      local res = {}
      for k,v in pairs(e) do res[k]=v end
      return res
    end
    return e
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

  local function partialEqual(e1,e2) -- partial: {a=9} == {a=9, b=19}
    if type(e1)~=type(e2) then return false
    elseif type(e1) == 'table' then
      for k,v in pairs(e1) do if not equal(v,e2[k]) then return false end end
      return true
    else return e1==e2 end
  end

  local match = partialEqual
  local function compile(expr) return expr end
  if self.EM then
    match = self.EM.match
    compile = self.EM.compilePattern
  end

  local function member(e,list)
    for _,l in ipairs(list) do if equal(e,l) then return true end end
  end

  function self:publish(event)
    assert(type(event)=='table' and event.type,"Not an event")
    local subs = idSubs[event.type] or {}
    for _,e in ipairs(subs) do
      if match(event,e.pattern) then
        for id,_ in pairs(e.ids) do 
          DEBUG("Sending sub QA:%s",id)
          fibaro.call(id,"SUBSCRIPTION",event)
        end
      end
    end
  end

  function self:SUBSCRIPTION(e)
    self:post(e)
  end

  function self:subscribe(events)
    if not events[1] then events = {events} end
    local subs = self:getVariable(SUB_VAR)
    if subs == "" then subs = {} end
    for _,e in ipairs(events) do
      assert(type(e)=='table' and e.type,"Not an event")
      if not member(e,subs) then subs[#subs+1]=e end
    end
    DEBUG("Setting subscription")
    self:setVariable(SUB_VAR,subs)
  end

--  idSubs = {
--    <type> = { { ids = {... }, event=..., pattern = ... }, ... }
--  }

  local function updateSubscriber(id,events)
    if not idSubs[id] then DEBUG("New subscriber, QA:%s",id) end
    for _,ev in ipairs(events) do
      local subs = idSubs[ev.type] or {}
      for _,s in ipairs(subs) do s.ids[id]=nil end
    end
    for _,ev in ipairs(events) do
      local subs = idSubs[ev.type]
      if subs == nil then
        subs = {}
        idSubs[ev.type]=subs
      end
      for tp,e in ipairs(subs) do
        if equal(ev,e.event) then
          e.ids[id]=true
          goto nxt
        end
      end
      subs[#subs+1] = { ids={[id]=true}, event=copy(ev), pattern=compile(ev) }
      ::nxt::
    end
  end

  local function checkVars(id,vars)
    for _,var in ipairs(vars or {}) do 
      if var.name==SUB_VAR then return updateSubscriber(id,var.value) end
    end
  end

-- At startup, check all QAs for subscriptions
  for _,d in ipairs(api.get("/devices?interface=quickApp") or {}) do
    checkVars(d.id,d.properties.quickAppVariables)
  end

  self:event({type='quickvar',name=SUB_VAR},            -- If some QA changes subscription
    function(env) 
      local id = env.event.id
      DEBUG("QA:%s updated quickvar sub",id)
      updateSubscriber(id,env.event.value)       -- update
      end) 

  self:event({type='deviceEvent',value='removed'},      -- If some QA is removed
    function(env) 
      local id = env.event.id
      if id ~= self.id then
        DEBUG("QA:%s removed",id)
        updateSubscriber(env.event.id,{})               -- update
      end
    end)

  self:event({
      {type='deviceEvent',value='created'},              -- If some QA is added or modified
      {type='deviceEvent',value='modified'}
    },
    function(env)                                             -- update
      local id = env.event.id
      if id ~= self.id then
        DEBUG("QA:%s created/modified",id)
        checkVars(id,api.get("/devices/"..id).properties.quickAppVariables)
      end
    end)
end
