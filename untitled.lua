The full blown EventRunner framework has support for more advanced event programming than the EventRunnerLite described in the first post of this tutorial. In this post the script language implemented in the EventRunner framwork will be described. The script language is particularly suitable for writing compact rules handling time scheduling, device triggering of rules, and user defined event rules. 

This first part will describe how script rules can be used to define a flexible scheduler. A scheduler is a scene that runs actions at specific times during the day. A fexible scheduler can adjust its behaviour depending on day of week, month or state of global variables or state of other devices at that time.

In the EventRunner framework, the main() function is used to setup rules and is called before the framework starts. main() can also be used to read in a HomeTable, setup variables etc, things that needs to be done once the framework starts up.

To define a rule the Rule.eval(<string>) function is used. A rule is a lua string of the format "<condition> => <actions>", and is compiled to an efficient represenation that is run when the <condition> is true. If the string doesn't contain a '=>' it is considered to be an expression that is just evaluated and the result is returned. This can be useful to setup variables and other initializations.
Rule.eval("lamp=55") -- define variable 'lamp' to be 55
Rule.eval("lamp:on") -- turn on lamp (with deviceID 55) when scene starts

a scheduler runs actions at a specific times during the day, so we use the 'daily'or '@' rules
The generic form of a daily rule is "@<time> [<option extra tests>] => <actions>"
Rule.eval("lamp=55") -- define variable 'lamp' to be 55
Rule.eval("@15:10 => lamp:on") -- turn on lamp (deviceID 55) every day at 15:10
The rule will be called every day at 15:10, and the left hand expression "@15:10" will evaluate to true (because it's 15:10) and thus the right hand side if the '=>' will be carried out. In this case the lamp with deviceID 55 will be turned on.
However, this means that we can tuck on extra tests on the left hand side that needs to be true for the rule to execute its actions. Any logic expression combining AND (&), OR(|), NOT(!), or comparision operators (==,>=,<=,~=) can be used.
Ex.
Rule.eval("@15:10 & lamp:isOff => lamp:on") -- turn on lamp (deviceID 55) every day at 15:10, if the lamp is off.
Rule.eval("@15:10 & !lamp:isOn => lamp:on") -- equivalent to the previous rule.
This tests if the lamp also is off, and if so the lamp is turned on. It is important that there should be no "side-effects" on the left hand side. No functions that turn on or off devices or set globals etc, only functions that query states.

Here are some examples of types of rules that can be defined
  -- Decalare a script variable 'lamp' to have value 55 (e.g. a deviceID)
  Rule.eval("lamp=55")
  -- Every day at 07:15, turn of lamp, e.g. deviceID 55
  Rule.eval("@07:15 => lamp:off")
  -- Every day at sunrise, turn off lamp
  Rule.eval("@sunrise => lamp:off")
  -- Every day at sunrise + 15min, turn off the lamp
  Rule.eval("@sunrise+00:15 => lamp:off")
  -- Every day at sunset, turn on lamp
  Rule.eval("@sunset => lamp:on")
  -- Every day at sunset-15min, if lamp is on, turn on the lamp
  Rule.eval("@sunset-00:15 & lamp:isOff => lamp:on")
  -- Every day at sunset-15min, turn on the lamp
  Rule.eval("@sunset-00:15 => lamp:on")
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
 -- Every day at sunrise on a Monday in the last week of the month, turn off the lamp 
  Rule.eval("@sunrise & day('lastw-last') & wday('mon') => lamp:off")
 -- Every day at sunrise January to Mars, turn off the lamp 
  Rule.eval("@sunrise & month('jan-mar') => lamp:off")
 -- Every day at sunrise on Mondays at even week numbers, turn off the lamp 
  Rule.eval("@sunrise & wnum%2 == 0 & wday('mon') => lamp:off")
 -- Every day at sunrise on weekdays when fibaro global 'Presence' equals 'Home', turn off the lamp 
  Rule.eval("@sunrise & $Presence=='Home' & wday('mon-fri') => lamp:off")
-- Every day at sunrise on weekdays when fibaro global 'Presence' equals 'Home' or fibaro global 'Simulate' equals 'true', turn off the lamp 
  Rule.eval("@sunrise & ($Presence=='Home' | $Simulate='true') & wday('mon-fri') => lamp:off")

The above rules runs at sunrise every day and we add additional conditions that restrict it to sunrise at specific days and/or if a global variable also is set to a specific value or if a device is in a specific state.

All 'Daily/@' rules are run at midnight and the expression after the '@' character is computed and should return a number being the seconds after midnight the rule should be run. That is why there should be no side-effects in the left hand side of the rule as they would be carried out at midning. When the rule is later run at the specified time, the whole left hand side is computed as a logical expression and if it returns true the right hand side, the action(s), is run.

'sunrise' and 'sunset' are constants that return seconds to sunrise and sunset respectively. Because the '@' expression is computed we can specify expressions like 'sunset+00:15' and it's computed as 15 min after sunset in seconds. Time constants like '04:15' are shorthand for '0+(60*(15+60*4))'. Seconds can also be specified '10:20:30' same as '30+(60*(20+60*10))'
We can use a value from a global variable easily, but if we want to use the time notation we need to convert it to seconds, which the 'time' function does.

Rule.eval("$Morning = '07:00'") -- Set global $Morning to the string "07:00". Could be set by a VD instead
Rule.eval("@time($Morning) => log('It's morning!')")

or if we want to adjust and offset to 'sunrise' with a global variable, maybe controlled from a VD

Rule.eval("@sunrise+time($SunriseOffset) => log('It's morning')")

Remember that the times are calculated at midnight, so if the global is changed during the day it will not take affect until the next day (However, the scene can be restarted for all values to be re-calculated).

A typical case is to turn on a a light in the morning if that time is before sunrise

Rule.eval("@06:00 and now < sunrise+00:30 => lamp:on")

This rule is run 06:00 every morning but the constant 'now', representing the current number of seconds since midnight, must be less than sunrise + 30min for the right hand action to be run.

Maybe a lamp should be turned on in the afternoon at sunset, given that sunset is within a certain time window (here in the north we can have sunset at 2PM)

Rule.eval("@sunset-00:30 & 16:00..23:00 => lamp:on")

The '<time1>..<time2>' operator is true if the current time is between the specified times.

To do something at a random interval every day, the 'rnd' function can be used. 'rnd(x,y)' returns a random number between x and y.
Rule.eval("@sunset+rnd(-00:30,00:30) => lamp:on") -- Turn on lamp at sunset +/- 30min  
  
Assume we have different wake-up times depending on day of week. A short alarm clock could look like this.

Rule.eval("phone=109") -- ID of phone
Rule.eval("wakeUpTime={Mon=07:10,Tue=07:20,Wed=06:55,Thu=07:40,Fri=07:30,Sat=08:00,Sun=09:00}")
Rule.eval("@wakeUpTime[osdate('%a')] & $Presence~='Vacation' => phone:send=log('Time to wakeup')")

'<ID>:send=<string>' send a text string to a phone with id ID. The 'log' commands prints its message to the HC2 debug window but also returns the string which we then use as input to the ':send' command. We also make sure that our global variable 'Presence' is not set to 'Vacation', as we don't want any messages then.

The '@' expression can also return a list of times, and all will be scheduled. 
If we want to do something at every 15min between 10:00 and 14:00, it's easiest to do something like this
Rule.eval("flowerCheck = {10:00,10:15,10:30,10:45,11:00,11:15,11:30,11:45,12:00,12:15,12:30,12:45,13:00,13:15,13:30,13:45,14:00}")
Rule.eval("@flowerCheck => wday('mon-fri') & checkWater()") -- assumes we have a defined function 'checkWater()'
The advantage is that this is done every every 15min between 10:00 and 14:00 every weekday and there is no time drift.

There is another construct that carry out actions at specfic intervals, the '@@' operator.
Rule.eval("@@00:15 => log('Dong!')") -- logs 'Dong!' every 15min 24x7...
This is an efficient way to do things at specified intervals. However, after a while there can be a drift
Rule.eval("@@00:01 => log('Dong!')") -- logs 'Dong!' every min 24x7...
Sat Sep 08 12:08:36 Dong!
Sat Sep 08 12:09:36 Dong!
Sat Sep 08 12:10:36 Dong! 
..
Wed Sep 12 22:36:37 Dong!
Wed Sep 12 22:37:37 Dong!
Wed Sep 12 22:38:37 Dong!
It starts out on the 36th second every minute but after 4 days in this case we end up on the 37th seconds.
Often this is not a huge problem if one needs to run some action at even intervals.

Here is a really short presence simulator
Rule.eval("$Presence='away'")
Rule.eval("lamps={22,33,44,55,66,77,88}")
Rule.eval("@@rnd(00:10,00:30) & $Presence=='away' & sunset..sunrise => lamps[rnd(1,length(lamps))]:toggle")

This runs a random intervals between 10 and 30min turning on lamps, but only when global variable 'Presence' is set to 'away' and it's between sunset and sunrise. We select a random lamp from the 'lamps' table and call the ':toggle' function to turn on or off the lamp.
A more advanced presence simulator would save and restore lamp states before running, but that is another post.



Trigger rules using the script language (I'm calling it eventScript for now)
So, besides definiung scheduler rules, rules that run at specific times during the day, one typically needs rules that react on external triggers; lights and sensors changing state, or fibaro globals being set.

Trigger rules look like 'daily/@' rules; "<expression> => <actions>", but without the '@' operator. In fact, when rules are defined they are scanned for '@' operations. If found they are set up as daily rules and run once a day. If no '@' operator is found, it is assumed to be a trigger rule. The left-hand side of the rule is then scanned for any use of deviceIDs or fibaro globals. If any of these later change state, the rule is called.
Rule.eval("55:breached => 66:on") -- If sensor 55 is breached, turn on light 66
Here we detect that deviceID 55 is used on the left-hand side, so we call the rule whenever 55 change state. However, the left-hand side is evaluated and if sensor 55 is not breached (maybe it become safe), it evaluates to false and the right-hand side is not carried out. The rule is also called when the sensor becomes false, but nothing will happen.
The ':' operator that typically access some device properties can also be used on table of devices.
Rule.eval("{55,45,88,99}:breached => 66:on") -- If any of the sensors is breached, turn on light 66
Of course it can also be a variable
Rule.eval("sensors={55,45,88,99}") -- List of sensr
Rule.eval("sensors:breached => 66:on") -- If any of the sensors is breached, turn on light 66
The ':breached' and ':isOn' applied on tables of deviceIDs returns true if any sensor or light in the table is on. The rationale is that if any light is on in a room there is light in the room. If there is a need to check if all lights are on there is a ':isAllOn' operator.
Similarly, there is a ':isAnyOff' operator to see if any light is off (or any sensor is safe).

So, the left-hand side of a trigger rule can be an arbitrary complex expression return true if the right-hand side should be carried out. And the rule ís called whenever any device or global appearing in the left-hand side expression change state. Left-hand side expression should only do tests and not have any side effects like turning on/off lights. It is also important that any variables used for deviceIDs should be defined before the rule is defined, otherwise the the deviceID will not be detected.
Rule.eval("sensor=55; lamp=66") -- define variables before next rule is defined.
Rule.eval("sensor:isOn => lamp:on")
Also, it is not possible to change a variable used as deviceID later - the rule will use the deviceID it detected when defined
Rule.eval("sensor=55; lamp=66") -- define variables before next rule is defined.
Rule.eval("sensor:isOn => lamp:on")
Rule.eval("sensor=57") -- sensor redefined, but previous rule will still trigger on 55

We can also add additional tests that need to be true
Rule.eval("sensor:breached & wday('mon-fri') & 08:00..13:00 => lamp:on")
If the sensor is breached and it's a weekday and between 08:00 and 13:00, then turn on the lamp.

{"event":{"data":{"icon":{"source":"HC","path":"fibaro\/icons\/com.fibaro.FGKF601\/com.fibaro.FGKF601-1Pressed.png"},"keyAttribute":"Pressed","deviceId":5,"keyId":1},"type":"CentralSceneEvent"},"type":"event"}










