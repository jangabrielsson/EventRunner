# EventRunner
Scene event framework for Fibaro HC2

Scenes on the Fibaro HC2 is invoked by declaring device triggers in the header.</br>
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
When the state of the declared devices changes state the scene is invoked:</br>
-the 'value' property of device 55 changes</br>
-the 'value' property of device 44 changes</br>
-the 'power' property of device 65 changes</br>
-the global Fibaro variable 'TimeOfDay' changes</br>
-the device 362 emits a 'CentralSceneEvent'</br>
The '%% autostart' tells the scene to respond to triggers</br>
</br>
Every time a scene is triggered, a new instance of the scene is spawned which makes it difficult to "remember" state between scene invocations. There are global Fibaro variables that can be set and retrieved but they are a bit cumbersome use.

The framework takes care of transforming a new scene instances to 'timer threads' in the intial scene instances. The model is based on events being posted to user defined 'event handlers'

Handlers are defined with Event:event. Ex:
```
function main()
   Event.event({type='property', deviceID=55, value='$>0'}, function(e) fibaro:call(44,'turnOn') end)
   
   Event.event({type='property', deviceID=65, propertyName='power', value='$<10'}, function(e) Log(LOG.LOG,"Power less than 10") end)
   
   Event.event({type='global', name='TimeOfDay', value='Day'}, function(e) Log(LOG.LOG,"It's daytime!") end)
end
```
Handlers are defined in a 'main()' function. The above example register a handler for an incoming event for a device (i.e. sensor) that if the value is above 0, will call the action that turns on device 44 (i.e. light)
The magic is that all event handlers are invoked in the same initial scene instance which allows for local variables to be used. Ex.
```
function main()
   local counter = 0
   Event.event({type='property', deviceID=55, value='$>0'}, 
         function(e) counter=counter+1; Log(LOG.LOG,"Light turned on %s times",counter) fibaro:call(44,'turnOn'))
end
```
Something that would be impossible in the normal model as each 'handler' would be called in a new instance.

Events are table structures with a 'type' key, which is true for Fibaro's own events. However, the framework allows for posting user defined events with 'Event:post(event[,time])'
The optional 'time' parameter specifies a time in the future that the event should be posted (if omitted it is posted imediatly). This turn the framework into a programming model. Ex. (main() is omitted in the examples from now)
```
Event.event({type='loop'},
            function(e) Log(LOG.LOG,"Ding!") Event:post({type='loop'},"+/00:10") end)
Event.post({type='loop'})
```
This will print "Ding!" imediatly, and then print "Ding!" every 10 minutes.
The framework has a lot of additional features and examples documented in the [Wiki](../../wiki/Home).
