--[[

  These are example rules that can be enabled and run for testing.
  Only works in emulator (HC2.lua)

--]]
local tExpr = false
local tRules = false
local tShell = false
local tEarth = false
local tTest1 = false
local tTest2 = false
local tPresence = false
local tHouse = false
local tScheduler = false
local tTimes = true
local tTriggerTuturial = false

local function post(e,t) Event.post(e,t) end
local function prop(id,state,prop) return {type='property', deviceID=id, propertyName=prop, value=state} end
local function glob(id,state) return {type='global', name=id, value=state} end  

_options.SUBFILE="example_rules3.lua"
_options.DEVICEAUTOACTION=true
_System.speed(true)      

local configData = 
{
  dev = {
    hall = {
      dryer = 1, door = 2,lamp_hall = 3,door_bell = 4, siren = 5,
      lux = 6,temp = 7,movement = 8, washing_machine = 9,lamp_entrance = 10,
      switch = 11
    },
    bedroom = {
      lamp_window = 21,lux = 22,lamp_table = 23,temp = 24,movement = 25,bed_led = 26,lamp_roof = 27
    },
    kitchen = {
      sonos = 41,lamp_sink = 42,dish_washer = 43,lamp_stove = 44,lux = 45,lamp_table = 46,
      dog = 47,sink_led = 48,temp = 49,movement = 50, switch=51
    },
    game = {
      lamp_window = 61,temp = 62,heat_alarm = 63,fire = 64,lamp_roof = 65
    },
    remote = 80,
    tim = {
      lamp_window = 101,lux = 102,computer = 103,temp = 104,movement = 105,
      bed_led = 106,lamp_roof = 107
    },
    back = {
      door = 121,lamp = 122,power_socket = 123
    },
    toilet_up = {
      temp = 141,movement = 142,lux = 143
    },
    max = {
      lamp_window = 161,lux = 162,temp = 163,movement = 164,bed_led = 165,lamp_roof = 166
    },
    toilet_down = {
      lux = 181,temp = 182,movement = 183,door = 184,lamp_roof = 185
    },
    livingroom = {
      lamp_globe = 201,heat_alarm = 202,light_window = 203,fire = 204,lamp_window = 205,
      lux = 206,lamp_roof_holk = 207,temp = 208,movement = 209,lamp_roof_sofa = 210,lamp_tv = 211
    },
    phone = {jan = 221, max = 222, daniela = 223, tim = 224},
  },
  users = {
    max = {phone = 222,name = 'Max'},
    daniela = {phone = 223,name = 'Daniela'},
    tim = {phone = 224,name = 'Tim'},
    jan = {phone = 221,name = 'Jan'}
  }
}
configData = Util.transform(configData,function(v) return tonumber(v) and 4000+v or v end)
function registerSceneTriggers(t,dev)
  if type(dev)=='number' then _System.registerSceneTrigger(prop(dev,nil,t),__fibaroSceneId)
  elseif type(dev)=='table' then
    for _,v in pairs(dev) do registerSceneTriggers(t,v) end
  end
end

registerSceneTriggers('value',configData.dev)


-- Read in devicetable
conf = configData
--local conf = json.decode(fibaro:getGlobalValue(_deviceTable))
dev = conf.dev
Util.reverseMapDef(dev) -- Make device names availble for debugging
Util.defvars(dev)       -- Make device names availble for debugging
local rule = Rule.eval

-- Set up short variables for use in rules
for k,v in pairs({ 
    td=dev.toilet_down,
    kt=dev.kitchen,
    ha=dev.hall,
    lr=dev.livingroom,
    ba=dev.back,
    gr=dev.game,
    ti=dev.tim,
    ma=dev.max,
    bd=dev.bedroom
  }) 
do Util.defvar(k,v) end

if tExpr then -- test some standard expression
  local function test(expr) Log(LOG.LOG,"Eval %s = %s",expr,tojson(Rule.eval(expr,{print=false}))) end
  --_System.setTime("06:00",24*36)
  test("5+(-3)")
  test("10/5+6*3")
  test("-3")
  test("! true")
  test("! 7>8")
  test("! false & true")
  test("!(false & true)")
  test("a={}; a.b = {c=42}; a.b.c")
  test("a = {b=7+9, c=8/2}")
  test("a['c']=3; a")
  test("a = {1,2,3}")
  test("add(a,4)")
  test("a = {back.lamp,kitchen.lamp_stove}; a:on")
  test("11:30+05:40==17:10")
  test("a=back.lamp")
  test("a:isOn")
  test("a:isOff")
  test("{88,99}:msg=fmt('%s+%s=%s',6,8,6+8)")
  Util.defvar('f1',function(a,b,c) return a+b*c end)
  test("4+f1(1,2,3)+2")
--  test("a=fn(a,b) return(a+b) end; a(7,9)")
--  test("(fn(a,b)return(a+b) end)(7,9)")
  test("label(45,'test')='hello'")
  test("|| 11:00..12:00 & day('1-7') & wday('mon') >> log('Noon first Monday of the month!')")
  test("|| 11:00..12:00 & day('lastw-last') & wday('mon') >> log('Noon last Monday of the month!')")
  test("log('Week number is %s and week is %s',wnum,wnum % 2 == 1 & 'odd' | 'even')")
  test([[
    || 05:00..11:00 >> log('Morning at %s',osdate('%X')) 
    || 11:00..15:00 >> log('Day at %s',osdate('%X'))
    || 15:00..22:00 >> log('Evening at %s',osdate('%X'))
    || 22:00..05:00 >> log('Night at %s',osdate('%X'))
    ]])
  test("log(osdate('Sunset at %X',t/sunrise)); || sunrise-10..sunrise+10 >> log('Its close to sunset at %s',osdate('%X'))")
end

if tRules then
  rule("kitchen.lamp_table:isOn => log('Kitchen lamp turned on')")
  rule("kitchen.lamp_table:on") -- turn on lamp triggers previous rule

  rule("lights={kitchen.lamp_table,livingroom.lamp_window}")
  rule("hall.switch:value => lights:value=hall.switch:value") -- link switch to lights
  rule("hall.switch:on") -- turn on switch to trigger previous rule
  rule("trueFor(00:10,hall.door:breached) => phone.jan:msg=log('Door open for %s min',again(5)*10)")
  rule("hall.door:on") -- Simulate breach
end

if tShell then -- run an interactive shell to try out commands
  Event.event({type='shell'},function(env)
      io.write("Eval> ") expr = io.read()
      if expr ~= 'exit' then
        print(string.format("=> %s",tojson(Rule.eval(expr,{print=false}))))
        Event.post({type='shell', _sh=true},'+/00:10')
      end
    end)

  Event.post({type='shell', _sh=true})
end

if tScheduler then
  --_System.setTime("06:00",24*20) -- start simulation at 06:00, run for 20 days

  -- setup some groups - could also be part of 'conf'
  rule("downstairs_move={kitchen.movement,hall.movement,livingroom.movement}")
  rule("downstairs_lux=downstairs_move") -- combined movement/lux sensors
  rule("downstairs_spots={livingroom.lamp_roof_sofa,kitchen.lamp_table,hall.lamp_hall}") 
  rule("evening_lights={hall.lamp_entrance,back.lamp}") 
  rule("evening_VDs={livingroom.lamp_roof_holk}") 

  -- We could support a 'weekly' as this runs once a day just to check if it is monday
  -- Anyway, garbage can out on Monday evening...
  rule([[@19:00 & wday('mon') & $Presence~='away' => 
               phone.jan:msg="Don't forget to take out the garbage!"]])

  -- Salary on the 25th, or the last weekday if it's on a weekend, reminder day before...
  rule([[@21:00 & (day('23')&wday('thu') | day('24')&wday('mon-thu')) & $Presence~='away' =>
               phone.jan:msg='Salary tomorrow!']])

  -- Last day of every month, pay bills...
  rule([[@20:00 & day('last') & $Presence~='away' => 
               phone.jan:msg="Don't forget to pay the monthly bills!"]])

  rule("trueFor(00:10,hall.door:breached) => phone.jan:msg=log('Door open for %s min',again(5)*10)")

  -- Post Sunset/Sunrise events that controll a lot of house lights. 
  -- If away introduce a random jitter of +/- an hour to make it less predictable...
  rule([[@00:00 => sunsetFlag=false;
    || $Presence ~= 'away' >> post(#Sunrise,t/sunrise+00:10); post(#Sunset,t/sunset-00:10)
    || $Presence == 'away' >> post(#Sunrise,t/sunrise+rnd(-01:00,01:00)); post(#Sunset,t/sunset+rnd(-01:00,01:00))]])

  -- This is a trick to only call #Sunset once per day, allows lux sensor to trigger sunset earlier
  rule("#Sunset => || !sunsetFlag >> sunsetFlag=true; post(#doSunset)")

  rule("#doSunset => evening_lights:on; evening_VDs:btn=1")
  rule("#doSunrise => evening_lights:off; evening_VDs:btn=2")

  -- Room specific lightning
  -- Max
  rule("#doSunset => {max.lamp_window, max.lamp_bed}:on")
  rule("@00:00 => {max.lamp_window, max.lamp_bed}:off")
  --Master bedroom
  rule("#doSunset => {bedroom.lamp_window, bedroom.lamp_bed}:on")
  rule("@00:00 => {bedroom.lamp_window, bedroom.lamp_bed}:off")

  -- Automatic lightning
  --Kitchen spots
  rule([[trueFor(00:10,downstairs_move:safe & downstairs_spots:isOn) => 
      downstairs_spots:off; log('Turning off spots after 10min of inactivity downstairs')]])

  --Bathroom, uses a local flag (inBathroom) 
  rule("trueFor(00:10,toilet_down.movement:safe & toilet_down.door:value) => !inBathroom & toilet_down.lamp_roof:off")
  rule("toilet_down.movement:breached => toilet_down.door:safe & inBathroom=true ; toilet_down.lamp_roof:on")
  rule("toilet_down.door:breached => inBathroom=false")
  rule("toilet_down.door:safe & toilet_down.movement:last<=3 => inBathroom=true")

  -- if average lux value is less than 100 one hour from sunset, trigger sunset event...
  -- Because we later set all sensors to 99 this would trigger 3 times, and thus we wrap it in 'once'
  Rule.eval([[once(sum(downstairs_lux:lux)/size(downstairs_lux) < 100 & sunset-01:00..sunset) => 
               post(#Sunset); log('Too dark at %s, posting sunset',osdate('%X'))]])

  -- Simulate and test scene by triggering events...

  -- Test open door warning logic
  rule("wait(t/08:30); hall.door:value=1") -- open door
  rule("wait(t/09:55); hall.door:value=0") -- close door

  -- Test auto-off spots logic
  rule("downstairs_move:value=0") -- all sensor safe
  rule("downstairs_spots:value=0") -- all spots off
  rule("wait(t/11:00); hall.movement:on") -- sensor triggered
  rule("wait(t/11:00:45); hall.lamp_hall:on") -- light turned on
  rule("wait(t/11:05:10); hall.movement:off") -- sensor safe, lights should turn off in 10min

  -- Test bathroom logic
  rule("wait(t/15:30); toilet_down.door:value=1") -- open door
  rule("wait(t/15:31); toilet_down.movement:value=1") -- breach sensor
  rule("wait(t/15:34); toilet_down.door:value=0") -- close door
  rule("wait(t/15:51); toilet_down.movement:value=0") -- sensor safe (20s)
  rule("wait(t/16:01); toilet_down.door:value=1") -- open door after 10min
  rule("wait(t/16:05); toilet_down.door:value=0") -- close door

  -- Test darkness -> Sunset logic
  rule("downstairs_lux:value=400")
  rule("wait(t/17:30); downstairs_lux:value=99")

end

if tEarth then -- Earth hour script. Saves values of lamps, turn them off at 20:30, and restore the values at 21:30
  Rule.load([[
    lights={td.lamp_roof,lr.lamp_roof_sofa}
    earthDates={2019/3/30/20:30,2020/3/28/20:30}
    familyPhones={phone.jan, phone.daniela}
    i=1; repeat post(#earthHour,earthDates[i]); i+=1 until i > size(earthDates)
    #earthHour =>
      familyPhones:msg=log('Earth hour started');
      states={};
      i = 1; repeat add(states,{id=lights[i],value=lights[i]:value}); i+=1 until i > size(lights);
      lights:off;
      post(#earthHourOff,+/01:00)
    #earthHourOff => 
      familyPhones:msg=log('Earth hour ended');
      i=1; repeat states[i].id:value=states[i].value; i+= 1 until i > size(states)
    ]])
  Rule.eval("post(#earthHour,+/00:10)") -- simulate earthHour...
end

if tPresence then
  --_System.setTime("06:00",24*20) -- start simulation at 06:00
  rule("sensors={bedroom.movement,livingroom.movement,hall.movement}; home=true")
  rule("lamps={bedroom.lamp_window,livingroom.lamp_roof_sofa,hall.lamp_hall}")

  rule("sensors:breached => || hall.door:safe >> home=true; post(#home)")
  rule("hall.door:breached => home=false; post(#home)")
  rule("trueFor(00:30,sensors:safe & hall.door:safe) => || home==false >> home=true; post(#away)")

  rule("#home => sim=false; log('Stopping presence simulation')")
  rule("#away => || !sim >> sim=true; post(#sim); log('Starting presence simulation')")

  rule("#sim => || sim >> lamp=lamps[rnd(1,size(lamps))]; lamp:toggle; post(#sim,ostime()+rnd(00:05,00:30))")

  -- Test Presence logic
  --rule("99:off")
  rule("wait(n/13:00); hall.door:on") -- Door open
  rule("wait(n/13:01); hall.door:off") -- Door close, simulation starts in 30min
  rule("wait(n/18:00); hall.door:on")  -- Home again, simulation stopped
  rule("wait(n/18:00:30); hall.movement:on") -- Sensor breached
  rule("wait(n/18:00:10); hall.door:off") -- Door closed
  rule("wait(n/18:01); hall.movement:off") -- Sensor safe
end

if tHouse then
  --_System.setTime("08:00",48) -- Start simulation at 08:00, and run for 48 hours

  -- collect garbage every night
  Event.schedule("n/00:00",function() collectgarbage("collect") end,{name='GC'})
  -- define macro that is true 08:00-12:00 on weekdays and 00:00-04:49 all days
  Rule.macro('LIGHTTIME',"(wday('mon-fri')&08:00..12:00|00:00..04:00)")

  Rule.load([[
-- Kitchen
      trueFor(00:10,kt.movement:safe&$LIGHTTIME$) => kt.lamp_table:off
      --log("A:%s",{kt.movement,lr.movement,ha.movement}:safe)
      trueFor(00:10,{kt.movement,lr.movement,ha.movement}:safe & $LIGHTTIME$) =>
        {kt.lamp_stove,kt.lamp_sink,ha.lamp_hall}:isOn &
        {kt.lamp_stove,kt.lamp_sink,ha.lamp_hall}:off &
        log('Turning off kitchen spots after 10 min inactivity')

-- Kitchen
      @sunset-00:10 => kt.sink_led:btn=1; log('Turn on kitchen sink light')
      @sunrise+00:10 => kt.sink_led:btn=2; log('Turn off kitchen sink light')
      @sunset-00:10 => kt.lamp_table:on; log('Evening, turn on kitchen table light')

-- Living room
      @sunset-00:10 => lr.lamp_window:on; log('Turn on livingroom light')
      @00:00 => lr.lamp_window:off; log('Turn off livingroom light')

-- Front
      @sunset-00:10 => ha.lamp_entrance:on; log('Turn on lights entr.')
      @sunset => ha.lamp_entrance:off; log('Turn off lights entr.')

-- Back
      @sunset-00:10 => ba.lamp:on; log('Turn on lights back')
      @sunset => ba.lamp:off; log('Turn off lights back')

-- Game room
      @sunset-00:10 => gr.lamp_window:on; log('Turn on gaming room light')
      @23:00 => gr.lamp_window:off; log('Turn off gaming room light')

-- Tim
      @sunset-00:10 => {ti.bed_led,ti.lamp_window}:on; log('Turn on lights for Tim')
      @00:00 => {ti.bed_led,ti.lamp_window}:off; log('Turn off lights for Tim')

-- Max
      @sunset-00:10 => ma.lamp_window:on; log('Turn on lights for Max')
      @00:00 => ma.lamp_window:off; log('Turn off lights for Max')

-- Bedroom
      @sunset => {bd.lamp_window,bd.lamp_table,bd.bed_led}:on; log('Turn on bedroom light')
      @23:00 => {bd.lamp_window,bd.lamp_table,bd.bed_led}:off; log('Turn off bedroom light')
    ]])

  -- test daily light rules
  fibaro:call(dev.kitchen.lamp_stove, 'turnOn') -- turn on light
  Event.post({type='property', deviceID=dev.kitchen.movement, value=0}, "n/09:00") -- and turn off sensor

-- Bathroom
  Rule.eval("trueFor(00:10,td.movement:safe & td.door:value) => !inBathroom & td.lamp_roof:off")
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
        lr.lamp_roof_sofa:toggle; log('Toggling lamp downstairs')
      bd.lamp_roof:scene==S2.click =>
        {bd.lamp_window, bd.bed_led}:toggle; log('Toggling bedroom lights')
      ti.lamp_roof:scene==S2.click =>
        ti.bed_led:toggle; log('Toggling Tim bedroom lights')
      ti.lamp_roof:scene==S2.double =>
        ti.lamp_window:toggle; log('Toggling Tim window lights')
      ma.lamp_roof:scene==S2.click =>
        ma.lamp_window:toggle; log('Toggling Max bedroom lights')
      gr.lamp_roof:scene==S2.click =>
        gr.lamp_window:toggle; log('Toggling Gameroom window lights')
      kt.lamp_table:scene==S2.click =>
        || label(kt.sonos,'lblState')=='Playing' >> kt.sonos:btn=8 || true >> kt.sonos:btn=7;;
        log('Toggling Sonos %s',label(kt.sonos,'lblState'))
      #property{deviceID=lr.lamp_window} => 
        || lr.lamp_window:isOn >> lr.lamp_tv:btn=1; lr.lamp_globe:btn=1 || true >> lr.lamp_tv:btn=2; lr.lamp_globe:btn=2
    ]])
  --Rule.eval("trace(true)")
  -- test scene activations
  post(prop(dev.livingroom.lamp_roof_holk,Util.S2.click,'sceneActivation'),"n/09:10")
  post(prop(dev.livingroom.lamp_roof_holk,Util.S2.click,'sceneActivation'),"n/09:20")
end -- houseRules


if tTest1 then
  --_System.setTime("08:00",300)

  rule("sunsetLamps={bedroom.lamp_window,livingroom.light_window}")
  rule("sunriseLamps={bedroom.lamp_window,livingroom.light_window}")
  rule("lampsDownstairs={kitchen.lamp_table}")
  rule("sensorsDownstairs={livingroom.movement,kitchen.movement}")

  rule([[$Presence==true => 
      || 06:00..08:00 >> log('alarm off1')
      || 08:00..12:00 >> log('alarm on1')
      || 12:00..15:00 >> log('alarm off2')
      || 18:00..20:00 >> log('alarm on2')]])
  rule("$Presence=true")

  rule("trueFor(00:10,hall.door:breached) => phone.jan:msg=log('Door open %s min',again(5)*10)")
  post(prop(dev.hall.door,0),"+/00:15")
  post(prop(dev.hall.door,1),"+/00:20") 

  rule([[
      once(kitchen.temp:temp>10) => 
      phone.jan:msg=log('Temp too high: %s',kitchen.temp:temp)
    ]])

  rule("trueFor(00:15,sensorsDownstairs:safe) => 00:00..05:00 & lampsDownstairs:off")

  rule("@sunset-00:45 => log('Sunset');sunsetLamps:on")
  rule("@sunrise+00:15 => log('Sunrise');sunriseLamps:off")

  rule("$homeStatus=='away' => post(#simulate{action='start'})")
  rule("$homeStatus=='home' => post(#simulate{action='stop'})")

  rule("#simulate{action='start'} => log('Starting simulation')")
  rule("#simulate{action='stop'} => log('Stopping simulation')")

  post(glob('homeStatus','away'),"n/05:11")
  post(glob('homeStatus','home'),"n/07:11")

  post(prop(dev.kitchen.temp,22),"+/00:10")

  post(prop(dev.kitchen.movement,0),"n/01:10")
  post(prop(dev.livingroom.movement,0),"n/01:11")

  rule("kitchen.switch:scene==S1.click => log('S1 switch clicked')")
  rule("post(#property{deviceID=kitchen.switch,propertyName='sceneActivation',value=S1.click},n/09:10)")

  -- 2-ways to catch a cs event...
  rule("remote:central.keyId==4 => log('HELLO1 key=4')")
  rule("#event{event=#CentralSceneEvent{data={deviceId=remote,keyId='$k',keyAttribute='Pressed'}}} => log('HELLO2 key=%s',k)")

  rule("weather('*') => log('HELLO %s',weather().newValue)")

  -- Test cs and weather event
  rule("post(#event{event=#CentralSceneEvent{data={deviceId=remote, keyId=4,keyAttribute='Pressed'}}},n/08:10)")
  rule("post(#event{event=#WeatherChangedEvent{data={newValue= -2.2,change='Temperature'}}},n/08:20)")

  rule("@10:00 &day('1-7')&wday('mon') => log('10 oclock first Monday of the month!')")
  rule("@10:00 &day('lastw-last')&wday('mon') => log('10 oclock last Monday of the month!')")

--{"event":{"type":"WeatherChangedEvent","data":{"newValue":-2.2,"change":"Temperature","oldValue":-4}},"type":"event"}
--{"type":"event","event":{"type":"CentralSceneEvent","data":{"deviceId":362,"keyId":4,"keyAttribute":"Pressed","icon":{"path":"fibaro\/icons\/com.fibaro.FGKF601\/com.fibaro.FGKF601-4Pressed.png","source":"HC"}}}}
end -- ruleTests

if tTest2 then 
--_System.setTime("08:00",300)

  rule("{2,3,4}[2]=5") -- {2,5,4}
  rule("foo={}")  
  rule("foo['bar']=42") -- {bar=42}
  rule("$foo=5") -- fibaro:setGlobal('foo',5)
  rule("label(142,'foo')='bar'") -- fibaro:call(42,'setProperty', 'ui.foo.value', 'bar')

  y=rule("#test{i='$i<=10'} => wait(00:10); log('i=%d',i); post(#test{i=i+1})") -- Print i every 10min
  rule("post(#test{i=1})")

  rule([[bedroom.movement:breached & bedroom.lamp_table:isOff &bedroom.lamp_table:manual>10*60 =>
      bedroom.lamp_table:on;
      log('ON.Manual=%s',bedroom.lamp_table:manual)]])
  rule([[trueFor(00:10,bedroom.movement:safe & bedroom.lamp_table:isOn) => 
      || bedroom.lamp_table:manual>10*60 >> bedroom.lamp_table:off ;
      again();
      log('OFF.Manual=%s',bedroom.lamp_table:manual)]])
  rule("bedroom.movement:breached & bedroom.lamp_table:isOff => bedroom.lamp_table:on;auto='aon';log('Auto.ON')")
  rule([[trueFor(00:10,bedroom.movement:safe & bedroom.lamp_table:isOn) =>
      bedroom.lamp_table:off;auto='aoff';log('Auto.OFF')]])
  rule("bedroom.lamp_table:isOn => || auto~='aon' >> auto='m';log('Man.ON')")
  rule("bedroom.lamp_table:isOff => || auto~='aoff' >> auto='m';log('Man.ON')")

--  post(prop(dev.bedroom.movement,1),"+/00:10") 
--  post(prop(dev.bedroom.movement,0),"+/00:10:40")
  post(prop(dev.bedroom.lamp_table,1),"+/00:25")

end -- ruleTests2


if tTimes then
  -- Decalare a script variable 'lamp' to have value 55 (e.g. a deviceID)
  rule("lamp=back.lamp")
  -- Every day at 07:15, turn of lamp, e.g. deviceID 55
  rule("@07:15 => lamp:off")
  -- Every day at sunrise, turn off lamp
  rule("@sunrise => lamp:off")
  -- Every day at sunrise + 15min, turn off the lamp
  rule("@sunrise+00:15 => lamp:off")
  -- Every day at sunset, turn on lamp
  rule("@sunset => lamp:off")
  -- Every day at sunset-15min, turn on the lamp
  rule("@sunset-00:15 => lamp:off")
  -- Every day at sunrise and if it is Monday, turn off the lamp
  rule("@sunrise & wday('mon') => lamp:off")
  -- Every day at sunrise and if it is a weekday, turn off the lamp
  rule("@sunrise & wday('mon-fri') => lamp:off")
  -- Every day at sunrise on Monday,Wednesday,Friday,Saturday,Sunday, turn off the lamp 
  rule("@sunrise & wday('mon,wed,fri-sun') => lamp:off")
  -- Every day at sunrise the first day of the month, turn off the lamp 
  rule("@sunrise & day('1') => lamp:off")
  -- Every day at sunrise on the first 15 days of the month, turn off the lamp 
  rule("@sunrise & day('1-15') => lamp:off")
  -- Every day at sunrise on the last day of the month, turn off the lamp 
  rule("@sunrise & day('last') => lamp:off")
  -- Every day at sunrise on the first day of the last week of the month, turn off the lamp 
  rule("@sunrise & day('lastw') => lamp:off")
  -- Every day at sunrise on a Monday on the last week of the month, turn off the lamp 
  rule("@sunrise & day('lastw-last') & wday('mon') => lamp:off")
  -- Every day at sunrise January to Mars, turn off the lamp 
  rule("@sunrise & month('jan-mar') => lamp:off")
  -- Every day at sunrise on Mondays at even week numbers, turn off the lamp 
  rule("@sunrise & wnum%2 == 0 & wday('mon') => lamp:off")
  -- Every day at sunrise on weekdays when fibaro global 'Presence' equals 'Home', turn off the lamp 
  rule("@sunrise & $Presence=='Home' & wday('mon-fri') => lamp:off")
-- Every day at sunrise on weekdays when fibaro global 'Presence' equals 'Home' or fibaro global 'Simulate' equals 'true', turn off the lamp 
  rule("@sunrise & ($Presence=='Home' | $Simulate=='true') & wday('mon-fri') => lamp:off")

-- Define a set of lamps
  rule("lamps={back.lamp,kitchen.lamp_roof,max.lamp_roof}")
  rule("lamps:on")
  rule("lamps:isOn => log(8)")
end

if tTriggerTuturial then

  -- Smallest presence simulator?
  rule("$Presence='away'")
  rule("lamps={hall.lamp_roof,back.lamp,bedroom.lamp_roof}")
  rule("@@rnd(00:10,00:30) & $Presence=='away' & sunset..sunrise => lamps[rnd(1,size(lamps))]:toggle")

end

Event.event({type='error'},function(env) local e = env.event -- catch errors and print them out
    Log(LOG.ERROR,"Runtime error %s for '%s' receiving event %s",e.err,e.rule,e.event) 
  end)