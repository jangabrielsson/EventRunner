# EventRunner
Scene event framework for Fibaro HC2 (visit [Wiki](../../wiki/Home) or [Fibaro Forum thread](https://forum.fibaro.com/topic/31180-tutorial-single-scene-instance-event-model/) for more details)   
There is also an [EventRunnerLite](../../wiki/Lite) framework with all the bells and whistles scaled down that may be a gentler introduction to the single-instance/event model of coding scenes.   

This framework is a way to combine schedulers and trigger rules within a single scene instance. It is an 'event' based model where rules can be written in either Lua or a homemade "script language", or a mix of both. The framework allows the programmer to work within a single scene instance and not bother about multiple scene instances being triggered. This means that a scene can keep state in local Lua variables and not having to rely on Fibaro globals to remember things between scene invocations. This also means that the scene is always running while active, however it is very conservative on systems resources. Things that need to be remembered between restart of the scene/HC2 need of course to be stored somewhere permanently e.g. using Fibaro globals.

The goal with the script syntax has been to be able to concisely express typical scheduling/triggering logic needed in my own home automation system; Things that need to happen at specific times. Things that need to be done because of triggers in the systems. And things that should happen if some conditions are true for a given time.
Rules also need to be able to take into considerations additional conditions like day of week, values of global or local variables etc. More about the script language [here](https://github.com/jangabrielsson/EventRunner/wiki/Script-expressions)

The repository also contains a HC2 scene emulator so the framework can be debugged offline.

## The problem
Scenes on the Fibaro HC2 is typically invoked by declaring device triggers in the header.
Ex
```
--[[
%% properties
55 value
44 value
65 power
%% globals
TimeOfDay
%% events
362 CentralSceneEvent
%% autostart
--]]
```
When the state of the declared devices changes state the scene is invoked:
* the 'value' property of device 55 changes
* the 'value' property of device 44 changes
* the 'power' property of device 65 changes
* the global Fibaro variable 'TimeOfDay' changes
* the device 362 emits a 'CentralSceneEvent'  
The '%% autostart' tells the scene to respond to triggers

Every time a scene is triggered, a new instance of the scene is spawned, something that makes it difficult to "remember" state between scene invocations. There are global Fibaro variables that can be set and retrieved but they are a bit cumbersome to use.

## The solution
This framework takes care of transforming a new spawned scene instance to a 'timer thread' in the initial scene instance. The model is based on events being posted to user defined 'event handlers'

![](https://github.com/jangabrielsson/EventRunner/blob/master/Events_101.png)
Handlers are defined with Event.event. Ex:
```
function main()
   Event.event({type='property', deviceID=55, value='$>0'}, function(e) fibaro:call(44,'turnOn') end)
   
   Event.event({type='property', deviceID=65, propertyName='power', value='$<10'}, function(e) Log(LOG.LOG,"Power less than 10") end)
   
   Event.event({type='global', name='TimeOfDay', value='Day'}, function(e) Log(LOG.LOG,"It's daytime!") end)
end
```
Handlers are defined in a 'main()' function. The above example registers a handler for an incoming event for a device (i.e. sensor) that if the value is above 0, will call the action that turns on device 44 (i.e. light) The magic is that all event handlers are invoked in the same initial scene instance which allows for local variables to be used. Ex.
```
function main()
   local counter = 0
   Event.event({type='property', deviceID=55, value='$>0'}, 
         function(e) counter=counter+1; Log(LOG.LOG,"Light turned on %s times",counter) fibaro:call(44,'turnOn'))
end
```
Something that would be impossible in the normal model as each 'handler' would be called in a new instance.

Events are table structures with a 'type' key, which is true for Fibaro's own events. However, the framework allows for posting user defined events with 'Event.post(event[,time])' The optional 'time' parameter specifies a time in the future that the event should be posted (if omitted it is posted immediately). This turn the framework into a programming model. Ex. (main() is omitted in the examples from now)
```
Event.event({type='loop'},
            function(e) Log(LOG.LOG,"Ding!") Event:post({type='loop'},"+/00:10") end)
Event.post({type='loop'})
```
This will print "Ding!" immediately, and then print "Ding!" every 10 minutes.  

```
Event.event({type='loop'},
            function(e) Log(LOG.LOG,"Dong!") Event:post({type='loop'},"n/15:45") end)
Event.post({type='loop'},"n/15:45")
```
This will print "Dong!" at 15:45 every day.  

The other advantage with `post` is that if a 'simulated' fibaro event is posted the handlers will react as if a real event was triggered. This is great for debugging the logic of your script. Ex.
```Lua
Event.post({type='property', deviceID=55, value='1'},"t/11:00")
```
This will send a property trigger for device 55 at 11:00 today. The eventhandler in the previous example will react and log that the light was turned on.   

## The Script
To make it even more convenient, a script language is provided that can be used to define rules. Scripts are lua strings that are interpreted by Rule.eval(). The above event examples written with script rules would look like;
```Lua
Rule.eval("55:value>0 => 44:on")
Rule.eval("65:power<10 => log('Power less than 10')")
Rule.eval("$TimeOfDay=='Day' => log('It's daytime!')")

Util.defvar('counter',0)
Rule.eval("55:value>0 => counter=counter+1; log('Light turned on %s times',counter); 44:on")

Rule.eval("@@00:10 => log('Ding!')") -- Log 'Ding!' every 10 minute
Rule.eval("@15:45 => log('Dong!')") -- Log 'Dong!' 15:45 every day

Rule.eval("wait(t/11:00); 55:on") -- turn on light at 11:00 today
```

