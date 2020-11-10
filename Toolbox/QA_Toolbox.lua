if not (not hc3_emulator or hc3_emulator.name=="QA_toolbox") then return end
if dofile and not hc3_emulator then
  hc3_emulator = {
    name="QA_toolbox",
    type="com.fibaro.genericDevice",
    poll=1000,
    --offline=true,
    proxy=true,
    --deploy=true,
  }
  dofile("fibaroapiHC3.lua")
end

hc3_emulator.FILE("Toolbox/Toolbox_basic.lua","Toolbox")
hc3_emulator.FILE("Toolbox/Toolbox_child.lua","Toolbox_child")
hc3_emulator.FILE("Toolbox/Toolbox_events.lua","Toolbox_events")
hc3_emulator.FILE("Toolbox/Toolbox_triggers.lua","Toolbox_triggers")
hc3_emulator.FILE("Toolbox/Toolbox_files.lua","Toolbox_files")
hc3_emulator.FILE("Toolbox/Toolbox_rpc.lua","Toolbox_rpc")
hc3_emulator.FILE("Toolbox/Toolbox_pubsub.lua","Toolbox_pubsub")
hc3_emulator.FILE("Toolbox/Toolbox_ui.lua","Toolbox_ui")
hc3_emulator.FILE("Toolbox/Toolbox_luaparser.lua","Toolbox_luaparser")
hc3_emulator.FILE("Toolbox/Toolbox_luacompiler.lua","Toolbox_luacompiler")
----------- Code -----------------------------------------------------------
----------- QA toolbox functions -------------------------------------------
--[[
function QuickApp:setView(elm,prop,fmt,...)         -- Like updateView but with format
function QuickApp:getView(elm,prop)                 -- Get value of view element
function QuickApp:setName(name)                     -- Change name of QA
--function QuickApp:setType(typ)                      -- Change type of QA
function QuickApp:setIconMessage(msg,timeout)       -- Show text under icon, optional timeout to remove message
function QuickApp:setEnabled(bool)                  -- Enable/disable QA
function QuickApp:setVisible(bool)                  -- Hide/show QA
function QuickApp:addInterfaces(interfaces)         -- Add interfaces to QA
function QuickApp:notify(priority, title, text)     -- Create notification
function QuickApp:debugf(fmt,...)                   -- Like self:debug but with format
function QuickApp:tracef(fmt,...)                   -- Like self:trace but with format
function QuickApp:errorf(fmt,...)                   -- Like self:error but with format
function QuickApp:warningf(fmt,...)                 -- Like self:warning but with format
function QuickApp:encodeBase64(data)                -- Base 64 encoder
function QuickApp:basicAuthorization(user,password) -- Create basic authorization data (for http requests)
function QuickApp:version(<string>)                 -- Return/optional check HC3 version
function QuickApp:pushYesNo(mobileId,title,message,callback,timeout)
function QuickApp:prettyJsonStruct(expr)            -- Creates indented json string for expr
function QuickApp:getHC3IPaddress()                 -- Returns first enabled ip interface, ex. eth0 ip address
-- Module "childs"
function QuickApp:createChild(args)                 -- Create child device, see code below...
function QuickApp:numberOfChildren()                -- Returns number of existing children
function QuickApp:removeAllChildren()               -- Remove all child devices
function QuickApp:callChildren(method,...)          -- Call all child devices with method. 
function QuickApp:setChildIconPath(childId,path)
-- Module "events"
function QuickApp:post(ev,t)                        -- Post event 'ev' at time 't'
function QuickApp:cancel(ref)                       -- Cancel post in the future
function QuickApp:event(pattern,fun)                -- Create event handler for posted events
function QuickApp:HTTPEvent(args)                   -- Asynchronous http requests
function QuickApp:RECIEVE_EVENT(ev)                 -- QA method for recieving events from outside...
-- Module "triggers"
function QuickApp:registerTriggerHandler(handler)   -- Register handler for trigger callback (function(event) ... end)
function QuickApp:enableTriggerType(trs)            -- Enable trigger type. <string> or table of <strings>
function QuickApp:enableTriggerPolling(bool)        -- Enable/disable trigger polling loop
function QuickApp:setTriggerInterval(ms)            -- Set polling interval. Default 1000ms
-- Module "File"
function QuickApp:copyFileFromTo(fileName,deviceFrom,deviceTo) -- Copies file from one QA to another
function QuickApp:addFileTo(fileContent,device)     -- Creates a new file for a QA
-- Module "rpc"
function QuickApp:importRPC(deviceId,timeout,env)   -- Import remote functions from QA with deviceId
-- Module "pubsub"
function QuickApp:publish(event)                    -- Publish event to subscribing QAs
function QuickApp:subscribe(event)                  -- Subscribe to events from publishing QAs
-- Module "ui"
function QuickApp:updateViewLayout(id,UI,height,forceUpdate)
function QuickApp:insertLabel(name,text,pos)
function QuickApp:removeLabel(name)
--]]

-- Example
_version = "1.3"  -- Version of our app, will be logged at startup
modules = {"childs","events","triggers","rpc", "file","pubsub","ui"} -- Modules we want to load (the files need to be copied to our QA)

-- main() if available, will be called after onInit. Everything is setup after we exit onInit() so this is a safer place to start running your main code...
function QuickApp:main()   

  -- These are the types of triggers we are interested in from our trigger module
  self:enableTriggerType({
      "device","global-variable","alarm","weather","profile","custom-event","deviceEvent","sceneEvent","onlineEvent"
    })

  -- We want to log all triggers arriving
  self.debugFlags.triggers = true -- Log all incoming (enabled) triggers

  -- Example of eventhandler for http request
  self:event({type='HTTPEvent',status=200,data='$res',tag="refresh"},
    function(env)
      env.p.res=json.decode(env.p.res)
      self:tracef("HTTP:%s",env.p.res.serialNumber)
    end)

  -- Example. Call our own API to retrieve info
  self:HTTPEvent{
    tag="refresh",
    url="http://127.0.0.1:11111/api/settings/info",
    basicAuthorization={user="admin",password="admin"}
  }

--[[
-- Create an infoCenter post every 5s with the current time
  setInterval(function()
      self:notify("info","Test",os.date("%c"),true)
    end,5000)

-- Subscribe to test events from other QAs
  self:subscribe({type='test'})
-- Trigger on text event
  self:event({type='test'},function(env)
      self:debug("Incoming test event")
    end)
--]]

end

-- To copy Toolbox files to your own QA. 
function QuickApp:copyToolbox(a,b)local c=api.get(("/quickApp/%s/files/%s"):format(a,b))assert(c,"File doesn't exists")local d=api.get(("/quickApp/%s/files/%s"):format(self.id,b))if not d then local e,f=api.post(("/quickApp/%s/files"):format(self.id),c)if f==200 then self:debug("File '",b,"' added")else self:error("Error:",f)end elseif d.content~=c.content then local e,f=api.put(("/quickApp/%s/files/%s"):format(self.id,b),c)if f==200 then self:debug("File '",b,"' updated")else self:error("Error:",f)end else self:debug("File '",b,"' up to date")end end

-- This is our minimal onInit(). Most stuff our handled by the Toolbox, or you should do it in main()
-- Here we setup some Toolbox flags and load Toolbox files
function QuickApp:onInit()
  self._NOTIFY = true
  self.debugFlags.trigger=true
--  Here is a good place to copy over the Toolbox files to your QA. 'Toolbox' is needed by all modules.
--  Assume QA_Toolbox has deviceId 1333
--  local toolbox = 1333
--  self:copyToolbox(toolbox,"Toolbox")
--  self:copyToolbox(toolbox,"Toolbox_child")
--  self:copyToolbox(toolbox,"Toolbox_events")
--  self:copyToolbox(toolbox,"Toolbox_trigger")
--  self:copyToolbox(toolbox,"Toolbox_files")
--  self:copyToolbox(toolbox,"Toolbox_rpc")
--  self:copyToolbox(toolbox,"Toolbox_pubsub")
end

