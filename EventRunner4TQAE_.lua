_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  logLevel=1,
  modPath = "TQAEmodules/",
  temp = "temp/",
  startTime="12/24/2024-07:00",
  refreshStates = true,
}

--FILE:EventRunner4Engine.lua,EventRunner;
--FILE:Toolbox/Toolbox_basic.lua,Toolbox;
--FILE:Toolbox/Toolbox_events.lua,Toolbox_events;
--FILE:Toolbox/Toolbox_child.lua,Toolbox_child;
--FILE:Toolbox/Toolbox_triggers.lua,Toolbox_triggers;
--FILE:Toolbox/Toolbox_files.lua,Toolbox_files;
--FILE:Toolbox/Toolbox_rpc.lua,Toolbox_rpc;
--FILE:Toolbox/Toolbox_pubsub.lua,Toolbox_pubsub;
--FILE:EventRunnerDoc.lua,EventRunnerDoc;
--FILE:Toolbox/Toolbox_profiler.lua,Toolbox_profiler;

--%%ui1={label='ERname',text="..."}
--%%ui2={button='debugTrigger', text='Triggers:ON'}
--%%ui3={button='debugPost', text='Post:ON'}
--%%ui4={button='debugRule', text='Rules:ON'}

----------- Code -----------------------------------------------------------

_debugFlags.trigger = true -- log incoming triggers
_debugFlags.trigger2 = true -- log incoming triggers
_debugFlags.fcall=true     -- log fibaro.call
_debugFlags.post = true    -- log internal posts
_debugFlags.rule=true      -- log rules being invoked (true or false)
_debugFlags.ruleTrue=true  -- log only rules that are true
_debugFlags.pubsub=true    -- log only rules that are true

------------- Put your rules inside QuickApp:main() -------------------

function QuickApp:main()    -- EventScript version
  local rule = function(...) return self:evalScript(...) end          -- old rule function
  self:enableTriggerType({"device","global-variable","custom-event","profile","alarm","location","quickvar"}) -- types of events we want

  HT = { 
    keyfob = 26, 
    motion= 21,
    temp = 22,
    lux = 23,
  }

  Util.defvars(HT)
  Util.reverseMapDef(HT)

--  rule("log('Current version is %s - %s',E_VERSION,E_FIX)")

--  hc3_emulator.locl.device{type="com.fibaro.binarySwitch",id=26}
--  hc3_emulator.locl.device{type="com.fibaro.multilevelSwitch",id=219}
--  hc3_emulator.locl.device{type="com.fibaro.binarySwitch",id=30}


--  rule("alarms:armed => log('Some alarm armed')")
--  rule("alarms:allArmed => log('All alarm armed')")
--  rule("alarms:disarmed => log('All disarmed')")
--  rule("alarms:anyDisarmed => log('Any disarmed')")
--  rule("alarms:willArm => log('Any will arm')")
--  rule("{1,2}:allArmed => log('1,2 armed')")
--  rule("{1,2}:disarmed => log('1,2 disarmed')")
  --rule("wait(2); 0:alarm=true")

--  rule("0:armed => log('all armed')").print()
--  rule("0:armed==false => log('all disarmed')").print()
--  rule("2:armed => log('2 armed')")
--  rule("2:disarmed => log('2 disarmed')")
--  rule("2:willArm => log('2 will arm')")

--  Phone = {2,107}
--  lights={267,252,65,67,78,111,129,158,292,127,216,210,205,286,297,302,305,410,384,389,392,272,329,276} -- eller hämta värden från HomeTable
--  rule("earthDates={2021/3/27/20:30,2022/3/26/20:30,2023/3/25/20:30}")
--  rule("for _,v in ipairs(earthDates) do log(osdate('Earth hour %c',v)); post(#earthHour,v) end")
--  rule("#earthHour => wait(00:00:10); Phone:msg=log('Earth Hour har inletts, belysningen tänds igen om 1 timme')")
--  rule("#earthHour => states = lights:value; lights:off; wait(01:00); lights:value = states")
--  -- Slut ---
---- Testar Earth hour --------
--  rule("#earthHour2 => states = lights:value; lights:off; wait(00:00:06); lights:value = states")
--  rule("@now+00:00:05 => post(#earthHour2)")

  -- rule("@@00:01 & date('0/5 12-15 *') => log('ping')")
  -- rule("@@00:00:05 => log(now % 2 == 1 & 'Tick' | 'Tock')")
  -- rule("remote(1356,#foo)")
  -- rule("wait(5); publish(#foo)")
  -- rule("motion:value => log('Motion:%s',motion:last)")

--     rule("@{catch,05:00} => Util.checkForUpdates()")
--     rule("#File_update{} => log('New file version:%s - %s',env.event.file,env.event.version)")
--     rule("#File_update{} => Util.updateFile(env.event.file)")

--  rule("keyfob:central => log('Key:%s',env.event.value.keyId)")
--  rule("motion:value => log('Motion:%s',motion:value)")
--  rule("temp:temp => log('Temp:%s',temp:temp)")
--  rule("lux:lux => log('Lux:%s',lux:lux)")

--  rule("wait(3); log('Res:%s',http.get('https://jsonplaceholder.typicode.com/todos/1').data)")

--   Nodered.connect("http://192.168.1.49:1880/ER_HC3")
--   rule("Nodered.post({type='echo1',value='Hello'},true).value")
--  rule("Nodered.post({type='echo1',value=42})")
--  rule("#echo1 => log('ECHO:%s',env.event.value)")

--    rule("log('Synchronous call:%s',Nodered.post({type='echo1',value=42},true).value)")

--  rule("#alarm{property='armed', value=true, id='$id'} => log('Zone %d armed',id)")
--  rule("#alarm{property='armed', value=false, id='$id'} => log('Zone %d disarmed',id)")
--  rule("#alarm{property='homeArmed', value=true} => log('Home armed')")
--  rule("#alarm{property='homeArmed', value=false} => log('Home disarmed')")
--  rule("#alarm{property='homeBreached', value=true} => log('Home breached')")
--  rule("#alarm{property='homeBreached', value=false} => log('Home safe')")

--  rule("#weather{property='$prop', value='$val'} => log('%s = %s',prop,val)")

--  rule("#profile{property='activeProfile', value='$val'} => log('New profile:%s',profile.name(val))")
--  rule("log('Current profile:%s',QA:profileName(QA:activeProfile()))")

--  rule("#customevent{name='$name'} => log('Custom event:%s',name)")
--  rule("#myBroadcast{value='$value'} => log('My broadcast:%s',value)")
--  rule("wait(5); QA:postCustomEvent('myEvent','this is a test')")
--  rule("wait(7); broadcast({type='myBroadcast',value=42})")
--  rule("#deviceEvent{id='$id',value='$value'} => log('Device %s %s',id,value)")
--  rule("#sceneEvent{id='$id',value='$value'} => log('Scene %s %s',id,value)")

--    dofile("verifyHC3scripts.lua")
end