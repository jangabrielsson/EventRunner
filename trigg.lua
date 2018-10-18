In a previous post we described how to write scheduling rules (daily) rules using the script language. Those rules were invoked at specifed times and we could add extra conditions if their actions should be carried out or not.

However, we also want rules that are run when devices are triggered or any other event that the HC2 scenes support, and that is declared in the header of the scenes

--[[
%% properties
55 value
66 value
77 value
78 sceneActivation 
88 ui.Slider1.value
88 ui.Label1.value
%% events
100 CentralSceneEvent
%% globals
Home
%% autostart
--]]

myLightSensor = 55
myLight1 = 66
myLight2 = 67
myDoorSensor = 77
mySwitch = 78
myVD=88
myKeyFob = 100

function main()
  Rule.eval("myLightSensor:lux > 200 => myLight1:on")       -- Turn on light1 if lux value goes above 200
  Rule.eval("myLight1:isOn  => myLight2:on")                  -- Turn on light2 if light1 is turned on
  Rule.eval("myDoorSensor:breached  => myLight1:on")        -- Turn on light1 if door sensor is breached
  Rule.eval("mySwitch:scene == S2.click => myLight1:on")    -- Turn on light1 if S2 is clicked once
  Rule.eval("slider(myVD,'Slider1') == 50 => myLight1:on")  -- Turn on light1 if slider is set to 50
  Rule.eval("label(myVD,'Label1') == 'ON' => myLight1:on")  -- Turn on light1 if label is set to 'ON'
  Rule.eval("csEvent(myKeyFob).keyId==4 => myLight1:on")    -- Turn on light1 if key 4 is pressed on keyFob
  Rule.eval("$Home == 'AWAY' => myLight1:on")               -- Turn on light1 if fibaro global variabiale *Home' is set to 'AWAY'
end


This is pretty simple examples. Events need to be declared in the scene header (or the EventRunner scene will never be informed about the events). After that, rules reacting on events can be written relatively straight forward in the script syntax supported.
A trigger rule has the syntax
<expression involving scene triggers> => <actions>

When the script is "compiled" we look through the left hand expression looking for any device/global or other event and register the rule to be called whenever those devices/globals or other events are triggered.

So when 'myLightSensor's value changes in the above example, the scene is triggered and the EventRunner framework make sure to call the rule. The left-hand side is then evaluated, 'myLightSensor:lux > 200', and if it returns true the right-hand side is evaluated which turns on 'myLight1'.
  
The left-hand side can contain several events, and the rule is called whenever any changes state

Rule.eval("myDoorSensor:breached & $Home=='AWAY' => myLight1:on") -- Turn on light if sensor breached and 'Home' is 'AWAY'

This rule is called whenever myDoorSensor changes state or fibaro global 'Home' is set. The left is evaluated so the sensor must be breached and the global set to 'AWAY' for the expression to be true and the light turned on.
This can be quite useful. Assume we have a set of fibaro motion and light sensors

Rule.eval("sensors={41,43,46,48}")
Rule.eval("phones={101,102}")
Rule.eval("sensors:breached => d=env.event.deviceID; phones:msg=log('Sensor %s in room %s breached',d:name,d:roomName')")
Rule.eval("max(sensors:lux) < 200 => myLight1:on")
Rule.eval("sum(sensors:lux)/size(sensors) < 200 => myLight1:on")

The first rule is called whenever a sensor changes state. ':breached' called on a set of devices will return true if any of the devices in the set is breached. The sourceTrigger that caused the rule to be triggered is available in the script variable 'env.event'. We pick out the deviceID that caused the trigger and assign it to a script variable 'd'. Then we apply the ':msg' operator on the set of phone IDs we want to send a message to. The message is created with the 'log()' function that writes the message to the log but also return the message string to the ':msg' operator so that it is sent to the phone devices. There are ':name' and ':roomName' operator we can use on a device to get the device name and room name.

The second rule is also called whenever a sensor changes state and but here we take out the max value from the set of lux values returned. If that max lux value is lower than 200 we turn on the light.

The third rule is similar but a more complex expression that sums the lux values and devide with the number of sensor to get a average lux value to check against.

The EventRunner framework calls rules immediatly when an event comes in (it doesn't poll every x seconds) so it is suitable for writing rules that need to react quickly, like turning on lights when sensors are breached. Rules can also share local variables and states as they run in the same scene instance which further helps in writing rules.

Rule.eval("sensors:safe & door:safe => away=true")
Rule.eval("sensors:breached | door:breached => away=false")
Rule.eval("@@rnd(00:05,00:20) & away => lights[rnd(size(lights))]:toggle")

Here, whenever all sensors are safe and also the door sensor is safe we set a local script variable 'away' to true.
The we have a schedule rule that runs at random intervalls betwen 5 and 20min toggling lights, but only if away is true.

It is easy to limit rules to time intervalls using the '..' operator

Rule.eval("sensor:breached & 06:00..08:00 => text2speech('God morning!')")

Assuming we have a text2speech() function, if the sensor is breached and the time is between 06:00 and 08:00, the message plays.
This rule is called whenever the sensor changes state but also at 06:00 and 08:01. The reason is that the sensor can be breached at 05:59, which would make the left-hand side condition false and the action not invoked. However, at 06:00 the sensor is still breached but not changing state so the rule would not be run. Therefore rules containing '..' intervalls are called at entery and exit of the intervalls.

Of course all kinds of tests can be added to a trigger rule, like day of week, month, weeknumber etc. but they don't trigger the rule.

Rule("sensor:breached & 06:00..08:00  & wday('mon-fri') => text2speech('God morning!')")
This will trigger on sensor and time intervall, but the wday test also needs to be true too for the action to be invoked.

In the example above, if the intention is to play the message once in the morning, the problem is that it will play every time the sensor is breached between 06:00 and 08:00. We could solve that with setting a flag first time the sensor is breached and clear it outside the intervall, However, it is easier with the 'once' function.

Rule("sensor:breached & once(06:00..08:00)  & wday('mon-fri') => text2speech('God morning!')")

'once' takes an expression and return true if the expression returns true. However, the expression needs to return false and then return true before 'once' will return true again. In this case it will return true the first time we are between 06:00 and 08:00 but then it will not be true until we exit the intervall and enter it the next time, e.g. the next day. So, 'once' keeps state, similar to what we would have done with a flag, and would not have been possible to implmenet without rules running in the same scene instance.

Another useful function is 'for' that allow us to write tests that need to be true for a period of time.

Rule("for(00:05,light1:isOn & sensor:safe) & wday('mon-fri') => light1:off)")

The 'for' function always return false the first time it is called, but if the expression is true it starts a timer for the time specified and if the expression is still true then it returns true and continue with the rule. If the expression turns false during the time the timer will be cleared.
The result is that we can easily write rules that check if something is true for a certain time, like windows left open etc.

Rule.eval("sensors={41,43,46,48}") -- window sensors
Rule.eval("phones={101,102}")
Rule.eval("for(00:10,sensors:breached) & month('dec-feb') => d=env.event.deviceID; phones:msg=log('Window %s in room %s open',d:name,d:roomName')")
If any window is open for more than 10min a message is sent to the phones (during winter months)

Like 'once', 'for' will not re-trigger before the expression has turned false. In the above example, someone have to close all windows and then open one  before the rule will trigger again. However, with 'repeat()' we can re-trigger the 'for' expression.

Rule.eval("for(00:10,sensors:breached) & month('dec-feb') => d=env.event.deviceID; phones:msg=log('Window %s in room %s open',d:name,d:roomName'); repeat()")

This will make the rule trigger, and messages sent, every 10min the windows continue to be open. i.e. keep reminding us.
'repeat' can take an argument being the number of times the 'for' should be re-triggered. 'repeat' also return how many times it has currently repeated, e.g. re-triggered.

Rule.eval("for(00:10,sensors:breached) => d=env.event.deviceID; phones:msg=log('Window %s in room %s open for %smin',d:name,d:roomName',10*repeat(5))")
This will remind us 5 times that the windows are open, '...open for 10min', to '...open for 50min', 
