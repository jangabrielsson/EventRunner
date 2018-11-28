--[[

  These are example rules that can be enabled and run for testing.
  It depends on the orginal devicemap.data file being present in the working directory
  (to initoialize the HomeTable)
  
--]]
local tExpr = true
local tRules = true
local tShell = false
local tGEA = false
local tEarth = false
local tTest1 = false
local tTest2 = false
local tPresence = false
local tHouse = false
local tScheduler = false
local tRemoteAsync = false
local tTimes = false
local tTriggerTuturial = false

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

if tExpr then -- test some standard expression
  local function test(expr) Log(LOG.LOG,"Eval %s = %s",expr,tojson(Rule.eval(expr))) end
  _setClock("t/06:00")
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
  test("a = {77,99,100}; a:on")
  test("11:30+05:40==17:10")
  test("a:isOn")
  test("a:isOff")
  test("{88,99}:msg=frm('%s+%s=%s',6,8,6+8)")
  Util.defvar('f1',function(a,b,c) return a+b*c end)
  test("4+f1(1,2,3)+2")
  test("a=fn(a,b) return(a+b) end; a(7,9)")
  test("(fn(a,b)return(a+b) end)(7,9)")
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
  local conf = [[{
   kitchen:{light:20,lamp:21,sensor:22},
   room:{light:23,sensor:24,tableLamp:25},
   hall:{switch:26,door:27},
   phone:{jan:100,dani:101}
  }]]
  local dev = json.decode(conf)
  Util.reverseMapDef(dev) -- Make device names availble for debugging
  Util.defvar('dev',dev) -- Makes dev available as variable in scripts

  Rule.eval("dev.kitchen.lamp:isOn => log('Kitchen lamp turned on')")
  Rule.eval("dev.kitchen.lamp:on") -- turn on lamp triggers previous rule

  Rule.eval("lights={dev.kitchen.light,dev.room.light}")
  Rule.eval("dev.hall.switch:value => lights:value=dev.hall.switch:value") -- link switch to lights
  Rule.eval("dev.hall.switch:on") -- turn on switch to trigger previous rule
  Rule.eval("for(00:10,dev.hall.door:breached) => dev.phone.jan:msg=log('Door open for %s min',repeat(5)*10)")
  Rule.eval("dev.hall.door:on") -- Simulate breach
end

if tShell then -- run an interactive shell to try out commands
  Event.event({type='shell'},function(env)
      io.write("Eval> ") expr = io.read()
      if expr ~= 'exit' then
        print(string.format("=> %s",tojson(Rule.eval(expr))))
        Event.post({type='shell', _sh=true},'+/00:10')
      end
    end)

  Event.post({type='shell', _sh=true})
end

if tScheduler then
  _setClock("t/06:00") -- start simulation at 06:00
  _setMaxTime(24*20)     -- run for 20 days
  -- setup data we need
  local conf = [[{
   kitchen:{light:20,lamp:21,sensor:22},
   room:{light:23,sensor:24,tableLamp:25,philipsHue:201},
   hall:{switch:26,door:27,sensor:28,light:33},
   back:{lamp:56,door:57},
   bathroom:{door:47,lamp:48,sensor:49},
   max:{lamp_window:70,lamp_bed:71},
   bed:{lamp_window:80,lamp_bed:81},
   phone:{jan:100,dani:101}
  }]]
  fibaro:setGlobal('jTable',conf)

  -- lets start
  local dev = json.decode(fibaro:getGlobalValue('jTable')) -- Fetch device definitions
  Util.reverseMapDef(dev) -- Make device names availble for debugging
  -- Make variables available in scripts, e.g. kichen.lamp, kitchen.light etc
  Util.defvars(dev) 

  -- setup some groups - could also be part of 'conf'
  Rule.eval("downstairs_move={kitchen.sensor,hall.sensor,room.sensor}")
  Rule.eval("downstairs_lux=downstairs_move") -- combined movement/lux sensors
  Rule.eval("downstairs_spots={room.light,kitchen.light,hall.light}") 
  Rule.eval("evening_lights={room.tableLamp,back.lamp}") 
  Rule.eval("evening_VDs={room.philipsHue}") 

  -- We could support a 'weekly' as this runs once a day just to check if it is monday
  -- Anyway, garbage can out on Monday evening...
  Rule.eval([[daily(19:00) & wday('mon') & $Presence~='away' => 
               phone.jan:msg="Don't forget to take out the garbage!"]])

  -- Salary on the 25th, or the last weekday if it's on a weekend, reminder day before...
  Rule.eval([[daily(21:00) & (day('23')&wday('thu') | day('24')&wday('mon-thu')) & $Presence~='away' =>
               phone.jan:msg='Salary tomorrow!']])

  -- Last day of every month, pay bills...
  Rule.eval([[daily(20:00) & day('last') & $Presence~='away' => 
               phone.jan:msg="Don't forget to pay the monthly bills!"]])

  Rule.eval("for(00:10,hall.door:breached) => phone.jan:msg=log('Door open for %s min',repeat(5)*10)")

  -- Post Sunset/Sunrise events that controll a lot of house lights. 
  -- If away introduce a random jitter of +/- an hour to make it less predictable...
  Rule.eval([[daily(00:00) => sunsetFlag=false;
    || $Presence ~= 'away' >> post(#Sunrise,t/sunrise+00:10); post(#Sunset,t/sunset-00:10)
    || $Presence == 'away' >> post(#Sunrise,t/sunrise+rnd(-01:00,01:00)); post(#Sunset,t/sunset+rnd(-01:00,01:00))]])

  -- This is a trick to only call #Sunset once per day, allows lux sensor to trigger sunset earlier
  Rule.eval("#Sunset => || not(sunsetFlag) >> sunsetFlag=true; post(#doSunset)")

  Rule.eval("#doSunset => evening_lights:on; evening_VDs:btn=1")
  Rule.eval("#doSunrise => evening_lights:off; evening_VDs:btn=2")

  -- Room specific lightning
  -- Max
  Rule.eval("#doSunset => {max.lamp_window, max.lamp_bed}:on")
  Rule.eval("daily(00:00) => {max.lamp_window, max.lamp_bed}:off")
  --Master bedroom
  Rule.eval("#doSunset => {bed.lamp_window, bed.lamp_bed}:on")
  Rule.eval("daily(00:00) => {bed.lamp_window, bed.lamp_bed}:off")

  -- Automatic lightning
  --Kitchen spots
  Rule.eval([[for(00:10,downstairs_move:safe & downstairs_spots:isOn) => 
      downstairs_spots:off; log('Turning off spots after 10min of inactivity downstairs')]])

  --Bathroom, uses a local flag (inBathroom) 
  Rule.eval("for(00:10,bathroom.sensor:safe &bathroom.door:value) => not(inBathroom)&bathroom.lamp:off")
  Rule.eval("bathroom.sensor:breached => bathroom.door:safe & inBathroom=true ; bathroom.lamp:on")
  Rule.eval("bathroom.door:breached => inBathroom=false")
  Rule.eval("bathroom.door:safe & bathroom.sensor:last<=3 => inBathroom=true")

  -- if average lux value is less than 100 one hour from sunset, trigger sunset event...
  -- Because we later set all sensors to 99 this would trigger 3 times, and thus we wrap it in 'once'
  Rule.eval([[once(sum(downstairs_lux:lux)/size(downstairs_lux) < 100 & sunset-01:00..sunset) => 
               post(#Sunset); log('Too dark at %s, posting sunset',osdate('%X'))]])

  -- Simulate and test scene by triggering events...

  -- Test open door warning logic
  Rule.eval("wait(t/08:30); hall.door:value=1") -- open door
  Rule.eval("wait(t/09:55); hall.door:value=0") -- close door

  -- Test auto-off spots logic
  Rule.eval("downstairs_move:value=0") -- all sensor safe
  Rule.eval("downstairs_spots:value=0") -- all spots off
  Rule.eval("wait(t/11:00); hall.sensor:on") -- sensor triggered
  Rule.eval("wait(t/11:00:45); hall.light:on") -- light turned on
  Rule.eval("wait(t/11:05:10); hall.sensor:off") -- sensor safe, lights should turn off in 10min

  -- Test bathroom logic
  Rule.eval("wait(t/15:30); bathroom.door:value=1") -- open door
  Rule.eval("wait(t/15:31); bathroom.sensor:value=1") -- breach sensor
  Rule.eval("wait(t/15:34); bathroom.door:value=0") -- close door
  Rule.eval("wait(t/15:51); bathroom.sensor:value=0") -- sensor safe (20s)
  Rule.eval("wait(t/16:01); bathroom.door:value=1") -- open door after 10min
  Rule.eval("wait(t/16:05); bathroom.door:value=0") -- close door

  -- Test darkness -> Sunset logic
  Rule.eval("downstairs_lux:value=400")
  Rule.eval("wait(t/17:30); downstairs_lux:value=99")

end

if tGEA then
   _setClock("t/06:00") -- start simulation at 06:00
  local devs = {
    Alicia = {Window = 36},
    Oliver = {Dimmer = 267},
    Elliot = {Dimmer = 274, Elliot_Skrivbord = 300},
    BedRoom = {Sonny_Laddare = 37, Erika_Laddare = 288},
    Farstukvist = {Tak = 276},
    Wc = {Tak = 66},
    Laundry_Room = {Tak = 51},
    Kitchen = {KaffeBryggare = 272, Window = 250},
    LivingRoom = {Hemma_Bio = 42, Tv = 43, Wii = 44, Bakom_Tv = 45, Bakom_Soffa = 269},
    SENSORS = {Wc = 202, Laundry_Room = 228},
    VD = {AllmanBelysning = 240, BarnensBelysning = 193, Garaget_Stolpe = 76}}
  Util.defvars(devs)
  Util.reverseMapDef(devs)

--Barnens belysning
--Starta lamporna när globala variablen är 1.3 eller mind och klockan är mellan 13: 00-18: 50 slack vid 19 tiden.
  Rule.eval("$Sun<=1.3 & 13:00..18:50 => VD.BarnensBelysning:btn=1") -- Tryck på knapp 1 på VD 193
  Rule.eval("@19:00 => VD.BarnensBelysning:btn=2") -- Tryck på knapp 2 på VD 193
  Rule.eval("@06:45 => Elliot.Dimmer:off")

  --UteBelysningen
  Rule.eval("$Sun<=0.7 => Farstukvist.Tak:on") 
  Rule.eval("$Sun<=0.7 => VD.Garaget_Stolpe:btn=1")  
  Rule.eval("$Sun>=0.8 => Farstukvist.Tak:off") 
  Rule.eval("$Sun>=0.8 => VD.Garaget_Stolpe:btn=1")  

-- Tänder Wc vid rörelse och Släcker 
  Rule.eval("SENSORS.Wc:isOn & 05:01..22:30 => Wc.Tak:value=99") 
  Rule.eval("SENSORS.Wc:isOn & 22:30..05:00 => Wc.Tak:value=30")   
  Rule.eval("for(00:03,SENSORS.Wc:isOff) => Wc.Tak:off") 

-- Tänder Tvättstugan vid rörelse och Släcker 
  Rule.eval("SENSORS.Laundry_Room:isOn & 00:00..23:59 => Laundry_Room.Tak:on")
  Rule.eval("for(00:05,SENSORS.Laundry_Room:isOff) => Laundry_Room.Tak:off")  

--Vardagsrummet 
--Standby killer Off
  Rule.eval("@06:30 => LivingRoom.Hemma_Bio:on; LivingRoom.Tv:on; LivingRoom.Wii:on")
--Standby killer On
  Rule.eval("@01:30 => LivingRoom.Hemma_Bio:off; LivingRoom.Tv:off; LivingRoom.Wii:off")

--Köket
  Rule.eval("for(00:40,Kitchen.KaffeBryggare:power>=50) => Kitchen.KaffeBryggare:off; phones:msg=log('Stänger av Kaffebryggaren %s',osdate('%X'))")

--Sovrummet
--Starta Laddare
  Rule.eval("@22:00 => BedRoom:on") -- turn on everything in the bedrrom, happens to be only 2 chargers...
--Laddare av
  Rule.eval("@06:00 => BedRoom:off") -- turn on everything in the bedrrom, happens to be only 2 chargers...

--Morgonbelysning om sol är mindre än 1
  Rule.eval("$Sun<=1.0 & 05:30..12:50 & wday('mon-fri') => LivingRoom.Bakom_Soffa:on; LivingRoom.Bakom_Tv:on; Kitchen.Window:on")
  Rule.eval("$Sun<=1.0 & 07:30..12:50 & wday('sat-sun') => LivingRoom.Bakom_Soffa:on; LivingRoom.Bakom_Tv:on; Kitchen.Window:on")
  Rule.eval("$Sun>=1.1 & 05:46..12:52 & wday('sat-sun') => LivingRoom.Bakom_Soffa:off; LivingRoom.Bakom_Tv:off; Kitchen.Window:off")

  Util.defvar('earthHourDate',function() return ("25/03/2017,31/03/2018,30/03/2019,28/03/2020"):match(os.date("%d/%m/%Y"))~=nil end)
-- Earth Hour - Datum fram till 2020.
-- Notis via push och Sonos om att Earth Hour Börjar om 30 min. 25/03/2017,31/03/2018,30/03/2019,28/03/2020
  Rule.eval("@20:00 & $Status=='Hemma' & earthHourDate() => phones:msg='Förbered levande ljus ifall ni vill se något i mörkret :)'")
-- Sätter den globala variabeln till aktivt läge, 1.
  Rule.eval("@20:30 & $Status=='Hemma' & earthHourDate() => $EarthHour=1")
-- Påbörjar Earth Hour. Släcker alla lampor, pushar ut notis pá mobiler och Sonos.
  Rule.eval("$EarthHour==1 & $Status=='Hemma' & earthHourDate() & hour(20:30) =>  phones:msg='Earth Hour påbörjad, Avslutas 21:30.' ; VD.AllmanBelysning:btn=2")
-- Sätter den globala variabeln till inaktivt läge, 0.
  Rule.eval("@21:30 & $Status=='Hemma' & earthHourDate() => $EarthHour=0")
-- Avslutar Earth Hour. Tänder lamporna igen, pushar ut notis to mobilize och Sonos.
  Rule.eval("$EarthHour==0 & $Status=='Hemma' & earthHourDate() & hour(21:30) =>  phones:msg='Earth Hour avslutad Lamporna tnds.' ; VD.AllmanBelysning:btn=1")

  --Test rules by simulating state changes
  Rule.eval("$Sun=0.7")
  Rule.eval("@08:00+rnd(-02:00,02:00) => $Sun=1.0") --Simulate sun up
  Rule.eval("@18:00+rnd(-02:00,02:00) => $Sun=0.3") -- Simulate sun down
  Rule.eval("wait(t/13:00); SENSORS.Wc:on")         -- Simulate Wc sensor on
  Rule.eval("wait(t/13:01); SENSORS.Wc:off")        -- Simulate Wc sensor off
end

if tEarth then -- Earth hour script. Saves values of lamps, turn them off at 20:30, and restore the values at 21:30
  Rule.load([[
    lights={td.lamp_roof,lr.lamp_roof_sofa}
    earthDates={2019/3/30/20:30,2020/3/28/20:30}
    dolist(v,earthDates,post(#earthHour,v))
    #earthHour{} =>
      states={};
      dolist(v,lights,add(states,{id=v,value=v:value}));
      lights:off;
      post(#earthHourOff,+/01:00)
    #earthHourOff => dolist(v,states,v.id:value=v.value)
    ]])
  Rule.eval("post(#earthHour,+/00:10)") -- simulate earthHour...
end

if tPresence then
   _setClock("t/06:00") -- start simulation at 06:00
  local rule = Rule.eval
  rule("sensors={99,98,97}; door=88; home=true")
  rule("lamps={22,33,44,55}")
   
  rule("sensors:breached => || door:safe >> home=true; post(#home)")
  rule("door:breached => home=false; post(#home)")
  rule("for(00:30,sensors:safe & door:safe) => || home==false >> home=true; post(#away)")

  rule("#home => sim=false; log('Stopping presence simulation')")
  rule("#away => || !sim >> sim=true; post(#sim); log('Starting presence simulation')")

  rule("#sim => || sim >> lamp=lamps[rnd(1,4)]; lamp:toggle; post(#sim,ostime()+rnd(00:05,00:30))")
  
  -- Test Presence logic
  --rule("99:off")
  rule("wait(t/13:00); door:on") -- Door open
  rule("wait(t/13:01); door:off") -- Door close, simulation starts in 30min
  rule("wait(t/18:00); door:on")  -- Home again, simulation stopped
  rule("wait(t/18:00:30); 99:on") -- Sensor breached
  rule("wait(t/18:00:10); door:off") -- Door closed
  rule("wait(t/18:01); 99:off") -- Sensor safe
end

if tHouse then
  _setClock("t/08:00") -- Start simulation at 08:00
  _setMaxTime(48)      -- and run for 48 hours

  -- collect garbage every night
  Event.schedule("n/00:00",function() collectgarbage("collect") end,{name='GC'})
  -- define macro that is true 08:00-12:00 on weekdays and 00:00-04:49 all days
  Rule.macro('LIGHTTIME',"(wday('mon-fri')&08:00..12:00|00:00..04:00)")

  Rule.load([[
-- Kitchen
      for(00:10,kt.movement:safe&$LIGHTTIME$) => kt.lamp_table:off
      log("A:%s",{kt.movement,lr.movement,ha.movement}:safe)
      for(00:10,{kt.movement,lr.movement,ha.movement}:safe & $LIGHTTIME$) =>
        {kt.lamp_stove,kt.lamp_sink,ha.lamp_hall}:isOn &
        {kt.lamp_stove,kt.lamp_sink,ha.lamp_hall}:off &
        log('Turning off kitchen spots after 10 min inactivity')

-- Kitchen
      daily(sunset-00:10) => kt.sink_led:btn=1; log('Turn on kitchen sink light')
      daily(sunrise+00:10) => kt.sink_led:btn=2; log('Turn off kitchen sink light')
      daily(sunset-00:10) => kt.lamp_table:on; log('Evening, turn on kitchen table light')

-- Living room
      daily(sunset-00:10) => lr.lamp_window:on; log('Turn on livingroom light')
      daily(00:00) => lr.lamp_window:off; log('Turn off livingroom light')

-- Front
      daily(sunset-00:10) => ha.lamp_entrance:on; log('Turn on lights entr.')
      daily(sunset) => ha.lamp_entrance:off; log('Turn off lights entr.')

-- Back
      daily(sunset-00:10) => ba.lamp:on; log('Turn on lights back')
      daily(sunset) => ba.lamp:off; log('Turn off lights back')

-- Game room
      daily(sunset-00:10) => gr.lamp_window:on; log('Turn on gaming room light')
      daily(23:00) => gr.lamp_window:off; log('Turn off gaming room light')

-- Tim
      daily(sunset-00:10) => {ti.bed_led,ti.lamp_window}:on; log('Turn on lights for Tim')
      daily(00:00) => {ti.bed_led,ti.lamp_window}:off; log('Turn off lights for Tim')

-- Max
      daily(sunset-00:10) => ma.lamp_window:on; log('Turn on lights for Max')
      daily(00:00) => ma.lamp_window:off; log('Turn off lights for Max')

-- Bedroom
      daily(sunset) => {bd.lamp_window,bd.lamp_table,bd.bed_led}:on; log('Turn on bedroom light')
      daily(23:00) => {bd.lamp_window,bd.lamp_table,bd.bed_led}:off; log('Turn off bedroom light')
    ]])

  -- test daily light rules
  fibaro:call(dev.kitchen.lamp_stove, 'turnOn') -- turn on light
  Event.post({type='property', deviceID=dev.kitchen.movement, value=0}, "n/09:00") -- and turn off sensor

-- Bathroom
  Rule.eval("for(00:10,td.movement:safe & td.door:value) => not(inBathroom)&td.lamp_roof:off")
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

  Util.defvars(d)      -- define variables from device table
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


  Rule.eval("{b=2,c={d=3}}.c.d",{log=true})

  --y=Rule.eval("dolist(v,{2,4,6,8,10},SP(); log('V:%s',$v))")
  --printRule(y)
  --Rule.eval("post(#foo{val=1})")

  Rule.eval("for(00:10,hall.door:breached) => user.jan.phone:msg=log('Door open %s min',repeat(5)*10)")
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
  Rule.eval("56:central.keyId==4 => log('HELLO1 key=4')")
  Rule.eval("#event{event=#CentralSceneEvent{data={deviceId=56,keyId='$k',keyAttribute='Pressed'}}} => log('HELLO2 key=%s',k)")

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

  Rule.eval("{2,3,4}[2]=5",{log=true}) -- {2,5,4}
  Rule.eval("foo={}",{log=true})  
  Rule.eval("foo['bar']=42",{log=true}) -- {bar=42}
  Rule.eval("$foo=5",{log=true}) -- fibaro:setGlobal('foo',5)
  Rule.eval("label(42,'foo')='bar'",{log=true}) -- fibaro:call(42,'setProperty', 'ui.foo.value', 'bar')

  y=Rule.eval("#test{i='$i<=10'} => wait(00:10); log('i=%d',i); post(#test{i=i+1})") -- Print i every 10min
  Rule.eval("post(#test{i=1})")

  Rule.eval("bed.sensor:breached & bed.lamp:isOff &bed.lamp:manual>10*60 => bed.lamp:on;log('ON.Manual=%s',bed.lamp:manual)")
  Rule.eval("for(00:10,bed.sensor:safe&bed.lamp:isOn) => || bed.lamp:manual>10*60 >> bed.lamp:off ;repeat();log('OFF.Manual=%s',bed.lamp:manual)")
  Rule.eval("bed.sensor:breached&bed.lamp:isOff => bed.lamp:on;auto='aon';log('Auto.ON')")
  Rule.eval("for(00:10,bed.sensor:safe&bed.lamp:isOn) => bed.lamp:off;auto='aoff';log('Auto.OFF')")
  Rule.eval("bed.lamp:isOn => || auto~='aon' >> auto='m';log('Man.ON')")
  Rule.eval("bed.lamp:isOff => || auto~='aoff' >> auto='m';log('Man.ON')")

  post(prop(d.bed.sensor,1),"+/00:10") 
  post(prop(d.bed.sensor,0),"+/00:10:40")
  post(prop(d.bed.lamp,1),"+/00:25")

end -- ruleTests2

if tRemoteAsync then -- example of doing remote/async calls

  _callbacks={}
  local function callAsync(to,fun,args)
    local id,t = tostring(args),nil
    local callback = function(env,stack,cp,ctx)
      _callbacks[id] = function(res)
        if t then Event.cancel(t) end
        stack.push(res)
        ScriptEngine.eval(env.code,env,stack,cp)
      end
    end
    local addr,timeout = type(to)=='table' and to[1] or to, type(to)=='table' and to[2]
    if timeout then t=Event.post(function() _callbacks[id]=nil end,osTime()+timeout) end
    if tonumber(addr) then Event.postRemote(addr,{type='RPC',id=id,fun=fun,args=args})
    else Event.post({type='RPC',id=id,fun=fun,args=args}) end
    error({type='yield', fun=callback})
  end
  Event.event({type='RPC', id='$id', res='$res'},function(env)
      if _callbacks[env.p.id] then _callbacks[env.p.id](env.p.res) _callbacks[env.p.id] = nil end
    end)

  Util.defvar('callAsync',function(addr,fun,...) callAsync(addr,fun,{...}) end)

  -- Handler waits 10min and does a reply, should propbably have a timeout parameter...
  -- This could trivially be extended to call functions in other scenes...
  Rule.eval("#RPC{id='$id',fun='foo/2',args='$args'} => wait(00:10); post(#RPC{id=id,res=args[1]+args[2]})")

  -- Here we call foo in the middle of an expression, foo suspends for 10min, returns 9 that becomes 14...
  Rule.eval("log('RES=%s',2+callAsync({'local',60*13},'foo/2',4,5)+3)")

end

if tTimes then
  -- Decalare a script variable 'lamp' to have value 55 (e.g. a deviceID)
  Rule.eval("lamp=55")
  -- Every day at 07:15, turn of lamp, e.g. deviceID 55
  Rule.eval("@07:15 => lamp:off")
  -- Every day at sunrise, turn off lamp
  Rule.eval("@sunrise => lamp:off")
  -- Every day at sunrise + 15min, turn off the lamp
  Rule.eval("@sunrise+00:15 => lamp:off")
  -- Every day at sunset, turn on lamp
  Rule.eval("@sunset => lamp:off")
  -- Every day at sunset-15min, turn on the lamp
  Rule.eval("@sunset-00:15 => lamp:off")
  -- Every day at sunrise and if it is Monday, turn off the lamp
  Rule.eval("@sunrise & wday('mon') => lamp:off")
  -- Every day at sunrise and if it is a weekday, turn off the lamp
  Rule.eval("@sunrise & wday('mon-fri') => lamp:off")
  -- Every day at sunrise on Monday,Wednesday,Friday,Saturday,Sunday, turn off the lamp 
  Rule.eval("@sunrise & wday('mon,wed,fri-sun') => lamp:off")
 -- Every day at sunrise the first day of the month, turn off the lamp 
  Rule.eval("@sunrise & day('1') => lamp:off")
 -- Every day at sunrise on the first 15 days of the month, turn off the lamp 
  Rule.eval("@sunrise & day('1-15') => lamp:off")
 -- Every day at sunrise on the last day of the month, turn off the lamp 
  Rule.eval("@sunrise & day('last') => lamp:off")
 -- Every day at sunrise on the first day of the last week of the month, turn off the lamp 
  Rule.eval("@sunrise & day('lastw') => lamp:off")
 -- Every day at sunrise on a Monday on the last week of the month, turn off the lamp 
  Rule.eval("@sunrise & day('lastw-last') & wday('mon') => lamp:off")
 -- Every day at sunrise January to Mars, turn off the lamp 
  Rule.eval("@sunrise & month('jan-mar') => lamp:off")
 -- Every day at sunrise on Mondays at even week numbers, turn off the lamp 
  Rule.eval("@sunrise & wnum%2 == 0 & wday('mon') => lamp:off")
 -- Every day at sunrise on weekdays when fibaro global 'Presence' equals 'Home', turn off the lamp 
  Rule.eval("@sunrise & $Presence=='Home' & wday('mon-fri') => lamp:off")
-- Every day at sunrise on weekdays when fibaro global 'Presence' equals 'Home' or fibaro global 'Simulate' equals 'true', turn off the lamp 
  Rule.eval("@sunrise & ($Presence=='Home' | $Simulate=='true') & wday('mon-fri') => lamp:off")

-- Define a set of lamps
  Rule.eval("lamps={55,66,77}")
  Rule.eval("lamps:on")
  Rule.eval("lamps:isOn => log(8)")
end

if tTriggerTuturial then
  
  
  
  -- Smallest presence simulator?
  Rule.eval("$Presence='away'")
  Rule.eval("lamps={22,33,44,55,66,77,88}")
  Rule.eval("@@rnd(00:10,00:30) & $Presence=='away' & sunset..sunrise => lamps[rnd(1,size(lamps))]:toggle")

end

Event.event({type='error'},function(env) local e = env.event -- catch errors and print them out
    Log(LOG.ERROR,"Runtime error %s for '%s' receiving event %s",e.err,e.rule,e.event) 
  end)