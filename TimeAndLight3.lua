if true then
  local mapAnd = Util.mapAnd
  local conf = json.decode(fibaro:getGlobalValue(_deviceTable))
  local dev = conf.dev

  local dvs = {
    td = dev.toilet_down,
    k = dev.kitchen,
    h = dev.hall,
    l = dev.livingroom,
    b = dev.back,
    g = dev.game,
    t = dev.tim,
    m = dev.max,
    bd = dev.bedroom
  }

  for k,v in pairs(dvs) do Util.defvar(k,v) end

  Util.reverseMapDef(dev)

  local d  = dev
  local td = dev.toilet_down
  local k  = dev.kitchen
  local h  = dev.hall
  local l  = dev.livingroom
  local b  = dev.back
  local g  = dev.game
  local t  = dev.tim
  local m  = dev.max
  local bd = dev.bedroom

  Event.event({type='global', name='deviceTable'},
    function(env) -- restart if updated
      local data = json.decode(fibaro:getGlobalValue("deviceTable"))
      if not Util.equal(dev,conf.dev) then
        Event.remote(conf.scenes.configurator.id,{type='startMeUp'})
        fibaro:abort()
      end
    end)

  local sched = {
    mon={{"07:00",'Morning'}, {"09:00",'Day'}, {"19:00",'Evening'}, {"23:00",'Night'}, {"24:00",'Midnight'}},
    tue={{"07:00",'Morning'}, {"09:00",'Day'}, {"19:00",'Evening'}, {"23:00",'Night'}, {"24:00",'Midnight'}},
    wed={{"07:00",'Morning'}, {"09:00",'Day'}, {"19:00",'Evening'}, {"23:00",'Night'}, {"24:00",'Midnight'}},
    thu={{"07:00",'Morning'}, {"09:00",'Day'}, {"19:00",'Evening'}, {"23:00",'Night'}, {"24:00",'Midnight'}},
    fri={{"07:00",'Morning'}, {"09:00",'Day'}, {"19:00",'Evening'}, {"24:00",'Night'}, {"24:00",'Midnight'}},
    sat={{"08:00",'Morning'}, {"10:00",'Day'}, {"19:00",'Evening'}, {"24:00",'Night'}, {"24:00",'Midnight'}},
    sun={{"08:00",'Morning'}, {"10:00",'Day'}, {"19:00",'Evening'}, {"23:00",'Night'}, {"24:00",'Midnight'}},
  }

  local evnts = {
    {'Sunset','max','on'} ,
    {'Midnight','max','off'} ,
    {'Sunset','tim','on'},
    {'Midnight','tim','off'},
    {'Sunset','bedroom','on'},
    {'Night','bedroom','off'},
    {'Sunset','game','on'},
    {'Midnight','game','off'},
    {'Sunset','livingroom','on'},
    {'Midnight','livingroom','off'},
    {'Sunset','kitchen','on'},
    {'Sunrise','kitchen','off'},
    {'Sunset','back','on'},
    {'Sunrise','back','off'},
    {'Sunset','hall','on'},
    {'Sunrise','hall','off'}
  }

  for _,e in ipairs(evnts) do
    Event.event({type=e[1]},{'post',{'quote',{type=e[2],value=e[3]}}})
  end

  function now()
    return osDate("%H:%M")
  end
  function past(t)
    return toTime(t) < osTime() 
  end

  Event.event({type='start'},
    function(env)
      Event.schedule("n/00:10",{type='daily_init'} ) -- Run daily setup 10min past midnight
      if now() > "00:10" then
        Event.post({type='daily_init'})
      end -- Run at startup
    end)

  Event.event({type='daily_init'},
    function(env)
      Log(LOG_COLOR,"Sunrise at %s",fibaro:getValue(1,"sunriseHour"))
      Log(LOG_COLOR,"Sunset at %s",fibaro:getValue(1,"sunsetHour"))
      Event.post({type='Sunrise'},"t/sunrise")
      Event.post({type='Sunset'},"t/sunset")

      local d = {'sun','mon','tue','wed','thu','fri','sat'}
      local t = os.date("*t",osTime())
      local ne,evs = nil,sched[d[t.wday ] ]
      local ff = function(a,b) return a[1 ] < b[1 ] end
      table.sort(evs,ff)
      for _,e in ipairs(evs) do
        if past("t/"..e[1]) then 
          ne = e[2] 
        else 
          Event.post({type=e[2 ] },"t/"..e[1]) 
        end
      end
      if (ne) then Event.post({type = ne}) end --latest 'past' event posted, i.e. to set time of day
    end)

-- Bathroom downstairs
-- check if someone is in bathroom (in practice an unsolvable problem)

  Rule.eval("for(00:10,td.movement:safe & td.door:value) => not(inBathroom) & td.lamp_roof:off")
  Rule.eval("td.movement:breached => || td.door:safe >> inBathroom=true ;; td.lamp_roof:on")
  Rule.eval("td.door:breached => inBathroom=false")
  Rule.eval("td.door:safe & td.movement:last<3 => inBathroom=true")

-- Kitchen

  Rule.eval([[for(00:10,k.movement:safe & k.lamp_table:isOn) & (wday('mon-fri')& 08:00..12:00 | 00:00..04:00) => 
  k.lamp_table:off; log('Turning off kitchen lamp after 10 min inactivity')]])
  
  Rule.eval([[for(00:10,{k.movement,l.movement,h.movement}:safe & {k.lamp_stove,k.lamp_sink,h.lamp_hall}:isOn) &
    (wday('mon-fri') & 08:00..12:00 | 00:00..04:00) => 
       {k.lamp_stove,k.lamp_sink,h.lamp_hall}:off ; log('Turning off kitchen spots after 5 min inactivity')]])
       
-- Kitchen
  Rule.eval("#kitchen{value='on'} => k.sink_led:btn=1 ; log('Turn on kitchen sink light')")
  Rule.eval("#kitchen{value='off'} => k.sink_led:btn=2 ; log('Turn off kitchen sink light')")

  Rule.eval("#kitchen{value='on'} => k.lamp_table:on; log('Evening, turn on kitchen table light')")

-- Living room
  Rule.eval("#livingroom{value='on'} => l.lamp_window:on; log('Turn on livingroom light')")
  Rule.eval("#livingroom{value='off'} => l.lamp_window:off; log('Turn off livingroom light')")

--  Event.post({type='property', deviceID=l.lux, value=100, _sim=true},"17:00")
--  Event.post({type='property', deviceID=l.lux, value=40, _sim=true},"17:30")
-- Front
  Rule.eval("#hall{value='on'} => h.lamp_entrance:on; log('Turn on lights entr.')")
  Rule.eval("#hall{value='off'} => h.lamp_entrance:off; log('Turn off lights entr.')")
-- Back
  Rule.eval("#back{value='on'} => b.lamp:on; log('Turn on lights back')")
  Rule.eval("#back{value='off'} => b.lamp:off; log('Turn off lights back')")

-- Game room
  Rule.eval("#game{value='on'} => g.lamp_window:on; log('Turn on gaming room light')")
  Rule.eval("#game{value='off'} => g.lamp_window:off; log('Turn off gaming room light')")
-- Tim
  Rule.eval("#tim{value='on'} => t.bed_led,t.lamp_window:on; log('Turn on lights for Tim')")
  Rule.eval("#tim{value='off'} => t.bed_led,t.lamp_window:off; log('Turn off lights for Tim')")

-- Max
  Rule.eval("#max{value='on'} => m.lamp_window:on; log('Turn on lights for Max')")
  Rule.eval("#max{value='off'} => m.lamp_window:off; log('Turn off lights for Max')")

-- Bedroom
  Rule.eval("#bedroom{value='on'} => {bd.lamp_window,bd.lamp_table,bd.bed_led}:on; log('Turn on bedroom light')")
  Rule.eval("#bedroom{value='off'} => {bd.lamp_window,bd.lamp_table,bd.bed_led}:off; log('Turn off bedroom light')")
---

  Rule.eval("#Evening => true")

-- Power watcher

  Util.defvar("powerIDs",{d.kitchen.dish_washer, d.hall.washing_machine, d.hall.dryer})
  Rule.eval("powerIDs:value => post(#power{id=env.event.deviceID,power=env.event.value})")


  for _,p in
  ipairs({{id=d.kitchen.dish_washer,e='dishwasher',l='Dishwasher started',max="3.0",min="1.0"},
      {id=d.kitchen.dish_washer,e='washing',l='Washingmachine started',max="3.0",min="1.0"},
      {id=d.kitchen.dish_washer,e='dryer',l='Dryer started',max="3.0",min="1.0"},}) do
    local state = false
    Event.event({type='power', id=p.id, power="$p>"..p.max},function(env) 
        if not state then state=true Event.post({type=p.e, state='on'}) Log(LOG.LOG,p.l) end
      end)
    Event.event({type='power', id=p.id, power="$p<"..p.min},function(env)
        if state then state=false Event.post({type=p.e, state='off'}) Log(LOG.LOG,p.l) end
      end)
  end
  ------------ Triggers --------------------- 

  Rule.eval("#property{propertyName='value', deviceID=137} => true") -- Silence triggers...
  Rule.eval("#property{propertyName='value', deviceID=261} => true")

  Rule.eval("l.lamp_roof_holk:scene==S2.click => l.lamp_roof_sofa:toggle; log('Toggling lamp downstairs')")
  Rule.eval("bd.lamp_roof:scene==S2.click => {bd.lamp_window, bd.bed_led}:toggle; log('Toggling bedroom lights')")
  Rule.eval("t.lamp_roof:scene==S2.click => t.bed_led:toggle; log('Toggling Tim bedroom lights')")
  Rule.eval("t.lamp_roof:scene==S2.double => t.lamp_window:toggle; log('Toggling Tim window lights')")
  Rule.eval("m.lamp_roof:scene==S2.click => m.lamp_window:toggle; log('Toggling Max bedroom lights')")
  Rule.eval("g.lamp_roof:scene==S2.click => g.lamp_window:toggle; log('Toggling Gameroom window lights')")
  Rule.eval("k.lamp_table:scene==S2.click => || label(k.sonos,'lblState')=='Playing' >> k.sonos:btn=8 || true >> k.sonos:btn=8 ;; log('Toggling Sonos %s',label(k.sonos,'lblState'))")

  Rule.eval("#property{deviceID=l.lamp_window} => || l.lamp_window:isOn >> l.lamp_tv:btn=1; l.lamp_globe:btn=1 || true >> l.lamp_tv:btn=2; l.lamp_globe:btn=2 ;; log('Toggling livingroom window lights')")

  -- test rules
    Rule.eval("wait(01:00); k.lamp_sink:on; {k.movement,l.movement,h.movement}:off")
    Rule.eval("wait(01:30); post(#property{deviceID=t.lamp_roof,propertyName='sceneActivation', value=S2.click})")
    Rule.eval("wait(01:40); l.lamp_window:toggle")
    Rule.eval("wait(01:50); l.lamp_window:toggle")
    --Rule.eval("daily(11:00) => foo()")
    Rule.eval("wait(t/11:30); k.movement:off")
    Rule.eval("wait(t/11:30); k.lamp_table:on")
end
