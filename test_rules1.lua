local tHouse = false
local tEarth = false
local tTest1 = true
local tTest2 = false

local function post(e,t) Event.post(e,t) end
local function prop(id,state,prop) return {type='property', deviceID=id, propertyName=prop, value=state} end
local function glob(id,state) return {type='global', name=id, value=state} end  

-- Read in devicetable
local conf = json.decode(fibaro:getGlobalValue(_deviceTable))
dev = conf.dev
Util.reverseMapDef(dev) -- Make device names availble for debugging

-- Set up short variables for use in rules
for k,v in pairs({ 
    td=dev.toilet_down,kt=dev.kitchen,ha=dev.hall,
    lr=dev.livingroom,ba=dev.back,gr=dev.game,
    ti=dev.tim,ma=dev.max,bd=dev.bedroom}) 
do Util.defvar(k,v) end

if tEarth then
  Rule.eval("lights={td.lamp_roof,lr.lamp_roof_sofa}",true)
  Rule.eval("earthDates={2019/3/30/20:30,2020/3/28/20:30}",true)
  Rule.eval("dolist(v,earthDates,post(#earthHour,v))",true)
  Rule.eval([[#earthHour{} =>
              states={};
              dolist(v,lights,add(states,{id=v,value=v:value}));
              lights:off;
              post(#earthHourOff,+/01:00)]])
  Rule.eval("#earthHourOff => dolist(v,states,v.id:value=v.value))")
  Rule.eval("post(#earthHour,+/00:10)")
end

if tHouse then
  _setClock("t/08:00") -- Start simulation at 08:00
  _setMaxTime(48)      -- and run for 48 hours

  -- collect garbage every night
  Event.schedule("n/00:00",function() collectgarbage("collect") end,{name='GC'})
  -- define macro that is true 08:00-12:00 on weekdays and 00:00-04:49 all days
  Rule.macro('LIGHTTIME',"(wday('mon-fri')&hour('8-12')|hour('0-4'))")

  Rule.load([[
-- Kitchen
      for(00:10,kt.movement:safe&$LIGHTTIME$) => kt.lamp_table:off=true

      for(00:10,{kt.movement,lr.movement,ha.movement}:safe&$LIGHTTIME$) =>
        {kt.lamp_stove,kt.lamp_sink,ha.lamp_hall}:isOn&
        {kt.lamp_stove,kt.lamp_sink,ha.lamp_hall}:off&
        log('Turning off kitchen spots after 10 min inactivity')

-- Kitchen
      daily(sunset-00:10) => press(kt.sink_led,1);log('Turn on kitchen sink light')
      daily(sunrise+00:10) => press(kt.sink_led,2);log('Turn off kitchen sink light')
      daily(sunset-00:10) => kt.lamp_table:on;log('Evening, turn on kitchen table light')

-- Living room
      daily(sunset-00:10) => lr.lamp_window:on;log('Turn on livingroom light')
      daily(00:00) => lr.lamp_window:off;log('Turn off livingroom light')

-- Front
      daily(sunset-00:10) => ha.lamp_entrance:on;log('Turn on lights entr.')
      daily(sunset) => ha.lamp_entrance:off;log('Turn off lights entr.')

-- Back
      daily(sunset-00:10) => ba.lamp:on;log('Turn on lights back')
      daily(sunset) => ba.lamp:off;log('Turn off lights back')

-- Game room
      daily(sunset-00:10) => gr.lamp_window:on;log('Turn on gaming room light')
      daily(23:00) => gr.lamp_window:off;log('Turn off gaming room light')

-- Tim
      daily(sunset-00:10) => {ti.bed_led,ti.lamp_window}:on;log('Turn on lights for Tim')
      daily(00:00) => {ti.bed_led,ti.lamp_window}:off;log('Turn off lights for Tim')

-- Max
      daily(sunset-00:10) => ma.lamp_window:on;log('Turn on lights for Max')
      daily(00:00) => ma.lamp_window:off;log('Turn off lights for Max')

-- Bedroom
      daily(sunset) => {bd.lamp_window,bd.lamp_table,bd.bed_led}:on;log('Turn on bedroom light')
      daily(23:00) => {bd.lamp_window,bd.lamp_table,bd.bed_led}:off;log('Turn off bedroom light')
    ]])

  -- test daily light rules
  fibaro:call(dev.kitchen.lamp_stove, 'turnOn') -- turn on light
  Event.post({type='property', deviceID=dev.kitchen.movement, value=0}, "n09:00") -- and turn off sensor

-- Bathroom
  Rule.eval("for(00:10,td.movement:safe&td.door:value) => not(inBathroom)&td.lamp_roof:off")
  Rule.eval("td.movement:breached => || td.door:safe >> inBathroom=true ;;td.lamp_roof:on")
  Rule.eval("td.door:breached => inBathroom=false")
  Rule.eval("td.door:safe & td.movement:last<3 => inBathroom=true")

  -- Test bathroom rules
  local breach,safe=prop(dev.toilet_down.movement,1),prop(dev.toilet_down.movement,0)
  local open,close=prop(dev.toilet_down.door,1),prop(dev.toilet_down.door,0)
  fibaro:call(dev.toilet_down.movement,'setValue',0)
  fibaro:call(dev.toilet_down.lamp_roof,'setValue',0)
  -- Simulate events
  post(open,"t/10:00") -- open door
  post(breach,"t/10:00:02") -- breach sensor
  post(close,"t/10:00:04") -- close door, $inBathroom will be set to true
  post(safe,"t/10:00:32") -- sensor safe after 30s
  post(breach,"t/10:00:45") -- sensor breached again
  post(safe,"t/10:01:15") -- sensor safe, light not turned off because $inBathroom==true
  post(open,"t/10:20") -- door opens, light will be turned off in 10min

-- SceneActivation events
  Rule.load([[
      lr.lamp_roof_holk:scene==S2.click =>
        toggle(lr.lamp_roof_sofa);log('Toggling lamp downstairs')
      bd.lamp_roof:scene==S2.click =>
        toggle({bd.lamp_window, bd.bed_led});log('Toggling bedroom lights')
      ti.lamp_roof:scene==S2.click =>
        toggle(ti.bed_led);log('Toggling Tim bedroom lights')
      ti.lamp_roof:scene==S2.double =>
        toggle(ti.lamp_window);log('Toggling Tim window lights')
      ma.lamp_roof:scene==S2.click =>
        toggle(ma.lamp_window);log('Toggling Max bedroom lights')
      gr.lamp_roof:scene==S2.click =>
        toggle(gr.lamp_window);log('Toggling Gameroom window lights')
      kt.lamp_table:scene==S2.click =>
        || label(kt.sonos,'lblState')=='Playing' >> press(kt.sonos,8) || true >> press(kt.sonos,7);;
        log('Toggling Sonos %s',label(kt.sonos,'lblState'))
      #property{deviceID=lr.lamp_window} => 
        || lr.lamp_window:isOn >> press(lr.lamp_tv,1); press(lr.lamp_globe,1) || true >> press(lr.lamp_tv,2); press(lr.lamp_globe,2)
    ]])
    --Rule.eval("trace(true)")
  -- test scene activations
  --post(prop(dev.livingroom.lamp_roof_holk,Util.S2.click,'sceneActivation'),"n/09:10")
  --post(prop(dev.livingroom.lamp_roof_holk,Util.S2.click,'sceneActivation'),"n/09:20")
end -- houseRules
-- #foo => || t >> print(x) ;; 
if tTest1 then
  d = {
    garage = {door = 10, lamp = 9},
    bed = {window = 11, sensor = 12, lamp = 13},
    kitchen = {window = 14, lamp = 15, sensor = 16, door = 17, temp=34, switch=41},
    hall = {door = 33},
    livingroom = {window = 18, sensor = 19, lamp = 20},
    wc = {lamp= 21, sensor = 22},
    stairs = {lamp = 23, sensor = 24},
    user = {jan = {phone = 120 }}
  }

  for k,j in pairs(d) do Util.defvar(k,j) end -- define variables from device table
  Util.reverseMapDef(d)

  _setClock("t/08:00")
  _setMaxTime(300)

  Rule.eval("sunsetLamps={bed.lamp,garage.lamp}")
  Rule.eval("sunriseLamps={garage.lamp,bed.lamp}")
  Rule.eval("lampsDownstairs={kitchen.lamp}")
  Rule.eval("sensorsDownstairs={livingroom.sensor,kitchen.sensor}")
  
  Rule.eval([[$Presence==true => 
      || 06:00..08:00 >> log('alarm off1')
      || 08:00..12:00 >> log('alarm on1')
      || 12:00..15:00 >> log('alarm off2')
      || 18:00..20:00 >> log('alarm on2')]])
  
  Rule.eval("$Presence=true")

  Rule.eval("{b=2,c={d=3}}.c.d",true)

  --y=Rule.eval("dolist(v,{2,4,6,8,10},SP(); log('V:%s',$v))")
  --printRule(y)
  --Rule.eval("post(#foo{val=1})")

  Rule.eval("for(00:10,hall.door:breached) => send(user.jan.phone,log('Door open %s min',repeat(5)*10))")
  post(prop(d.hall.door,0),"+/00:15")
  post(prop(d.hall.door,1),"+/00:20")

  Rule.eval([[
      once(kitchen.temp:temp>10) => 
      user.jan.phone:msg=log('Temp too high: %s',kitchen.temp:temp)
    ]])

  Rule.eval("for(00:15,sensorsDownstairs:safe) => 00:00..05:00 & lampsDownstairs:off")

  Rule.eval("daily(sunset-00:45) => log('Sunset');sunsetLamps:on")
  Rule.eval("daily(sunrise+00:15) => log('Sunrise');sunriseLamps:off")

  Rule.eval("$homeStatus=='away' => post(#simulate{action='start'})")
  Rule.eval("$homeStatus=='home' => post(#simulate{action='stop'})")

  Rule.eval("#simulate{action='start'} => log('Starting simulation')")
  Rule.eval("#simulate{action='stop'} => log('Stopping simulation')")

  post(glob('homeStatus','away'),"n/05:11")
  post(glob('homeStatus','home'),"n/07:11")

  post(prop(d.kitchen.temp,22),"+/00:10")

  post(prop(d.kitchen.sensor,0),"n/01:10")
  post(prop(d.livingroom.sensor,0),"n/01:11")

  Rule.eval("kitchen.switch:scene==S1.click => log('S1 switch clicked')")
  Rule.eval("post(#property{deviceID=kitchen.switch,propertyName='sceneActivation',value=S1.click},n/09:10)")

  -- 2-ways to catch a cs event...
  Rule.eval("csEvent(56).keyId==4 => log('HELLO1 key=4')")
  Rule.eval("#CentralSceneEvent{data={deviceId=56,keyId='$k',keyAttribute='Pressed'}} => log('HELLO2 key=%s',k)")

  Rule.eval("weather('*') => log('HELLO %s',weather().newValue)")

  -- Test cs and weather event
  Rule.eval("post(#event{event=#CentralSceneEvent{data={deviceId=56, keyId=4,keyAttribute='Pressed'}}},n/08:10)")
  Rule.eval("post(#event{event=#WeatherChangedEvent{data={newValue= -2.2,change='Temperature'}}},n/08:20)")

  Rule.eval("daily(10:00)&day('1-7')&wday('mon') => log('10 oclock first Monday of the month!')")
  Rule.eval("daily(10:00)&day('lastw-last')&wday('mon') => log('10 oclock last Monday of the month!')")

--{"event":{"type":"WeatherChangedEvent","data":{"newValue":-2.2,"change":"Temperature","oldValue":-4}},"type":"event"}
--{"type":"event","event":{"type":"CentralSceneEvent","data":{"deviceId":362,"keyId":4,"keyAttribute":"Pressed","icon":{"path":"fibaro\/icons\/com.fibaro.FGKF601\/com.fibaro.FGKF601-4Pressed.png","source":"HC"}}}}
end -- ruleTests

if tTest2 then 
  d = {
    garage = {door = 10, lamp = 9},
    bed = {window = 11, sensor = 12, lamp = 13},
    kitchen = {window = 14, lamp = 15, sensor = 16, door = 17, temp=34, switch=41},
    hall = {door = 33},
    livingroom = {window = 18, sensor = 19, lamp = 20},
    wc = {lamp= 21, sensor = 22},
    stairs = {lamp = 23, sensor = 24},
    user = {jan = {phone = 120 }}
  }

  for k,j in pairs(d) do Util.defvar(k,j) end -- define variables from device table
  Util.reverseMapDef(d)

  _setClock("t/08:00")
  _setMaxTime(300)

  Rule.eval("{2,3,4}[2]=5",true) -- {2,5,4}
  Rule.eval("foo={}",true)  
  Rule.eval("foo['bar']=42",true) -- {bar=42}
  Rule.eval("$foo=5",true) -- fibaro:setGlobal('foo',5)
  Rule.eval("label(42,'foo')='bar'",true) -- fibaro:call(42,'setProperty', 'ui.foo.value', 'bar')
  
  y=Rule.eval("#test{i='$i<=10'} => wait(00:10); log('i=%d',i); post(#test{i=i+1})") -- Print i every 10min
  Rule.eval("post(#test{i=1})")

  Rule.eval("bed.sensor:breached & bed.lamp:isOff &manual(bed.lamp)>10*60 => bed.lamp:on;log('ON.Manual=%s',manual(bed.lamp))")
  Rule.eval("for(00:10,bed.sensor:safe&bed.lamp:isOn) => || manual(bed.lamp)>10*60 >> bed.lamp:off ;repeat();log('OFF.Manual=%s',manual(bed.lamp)")
  Rule.eval("bed.sensor:breached&bed.lamp:isOff => bed.lamp:on;auto='aon';log('Auto.ON')")
  Rule.eval("for(00:10,bed.sensor:safe&bed.lamp:isOn) => bed.lamp:off;auto='aoff';log('Auto.OFF')")
  Rule.eval("bed.lamp:isOn => || auto~='aon' >> auto='m';log('Man.ON')")
  Rule.eval("bed.lamp:isOff => || auto~='aoff' >> auto='m';log('Man.ON')")

  post(prop(d.bed.sensor,1),"+/00:10") 
  post(prop(d.bed.sensor,0),"+/00:10:40")
  post(prop(d.bed.lamp,1),"+/00:25")

end -- ruleTests2

Event.event({type='error'},function(env) local e = env.event -- catch errors and print them out
    Log(LOG.ERROR,"Runtime error %s for '%s' receiving event %s",e.err,e.rule,e.event) 
  end)