VERSION = "0.7"

local idech3 = ID("HC3.copyHC3")
local idech31 = ID("HC3.sdkHC3")
local idech33 = ID("HC3.uploadHC3")
local idech33b = ID("HC3.backupHC3")
local idech33d = ID("HC3.downloadRsrcHC3")
local ide_deploy = ID("HC3.deployQA")
local idem = ID("HC3.web")
local idet = ID("HC3.templ")

local lfs = require("lfs")
local sdkFile = "fibaroapiHC3.lua"

local urlEmu = "http://127.0.0.1:6872/web/main"
local urlHC3Help = "https://forum.fibaro.com/topic/49488-sdk-for-remote-and-offline-hc3-development/"
local urlHC3QAHelp = "https://manuals.fibaro.com/home-center-3-quick-apps/"
local urlHC3ScHelp = "https://manuals.fibaro.com/home-center-3-lua-scenes/"
local urlHC3MQTTHelp = "https://manuals.fibaro.com/knowledge-base-browse/hc3-quick-apps-mqtt-client/"
local urlHC3WSHelp = "https://manuals.fibaro.com/knowledge-base-browse/hc3-quick-apps-websocket-client/"
local urlHC3ChildHelp = "https://manuals.fibaro.com/knowledge-base-browse/hc3-quick-apps-managing-child-devices/"

local function launchEmulator() wx.wxLaunchDefaultBrowser(urlEmu, 0) end
local function openURL(url) wx.wxLaunchDefaultBrowser(url, 0) end

ide:Print("Fibaro plugin version: "..VERSION)
sdkFile = ide.config.hc3api or sdkFile
ide:Print("Fibaro api file:"..sdkFile)

local function printf(fmt,...) ide:Print(string.format(fmt,...)) end
local ps  = ide.osname == "Windows" and "\\" or "/"
local assetDir  = os.getenv("HC3EMU")
if not assetDir then
  assetDir = (os.getenv('HOME')  or '')..ps..".zbstudio"..ps.."hc3emu"..ps
end
printf("Asset directory set to '%s'",assetDir)

local function readLuaFile(name)
  local p = assetDir..name
  local f = io.open(p,"r")
  if f then 
    local stat,res = pcall(function() 
        local d = f:read("*all")
        f:close()
        return load(d)()
      end)
    if stat then return res 
    else printf("Error reading %s - %s",p,res) end
  else print("Missing '%s', ignoring",name) end
end

local function checkAndReport(t,name)
  local n = 0;
  for _,_ in pairs(t or {}) do n=n+1 end
  printf("%s %s",n,name)
end

local codeTemplates = readLuaFile("hc3CodeTemplates.lua")
local downLoads = readLuaFile("hc3Downloads.lua")
if codeTemplates then checkAndReport(codeTemplates.templates,"code templates") end
if downLoads then checkAndReport((downLoads or {}).files,"download links") end

local function exePath(self, version)
  local version = tostring(version or ""):gsub('%.','')
  local mainpath = ide:GetRootPath()
  local macExe = mainpath..([[bin/lua.app/Contents/MacOS/lua%s]]):format(version)
  return (ide.config.path['lua'..version]
    or (ide.osname == "Windows" and mainpath..([[bin\lua%s.exe]]):format(version))
    or (ide.osname == "Unix" and mainpath..([[bin/linux/%s/lua%s]]):format(ide.osarch, version))
    or (wx.wxFileExists(macExe) and macExe or mainpath..([[bin/lua%s]]):format(version))),
  ide.config.path['lua'..version] ~= nil
end

local function callFibaroAPIHC3(cmd,endMessage)
  local version = "5.3"
  -- modify LUA_CPATH and LUA_PATH to work with other Lua versions
  local envcpath = "LUA_CPATH"
  local envlpath = "LUA_PATH"
  if version then
    local env = "PATH_"..string.gsub(version, '%.', '_')
    if os.getenv("LUA_C"..env) then envcpath = "LUA_C"..env end
    if os.getenv("LUA_"..env) then envlpath = "LUA_"..env end
  end

  local cpath = os.getenv(envcpath)

  if version and cpath then
    -- adjust references to /clibs/ folders to point to version-specific ones
    local cpath = os.getenv(envcpath)
    local clibs = string.format('/clibs%s/', version):gsub('%.','')
    if not cpath:find(clibs, 1, true) then cpath = cpath:gsub('/clibs/', clibs) end
    wx.wxSetEnv(envcpath, cpath)
  end

  local lpath = version and (not iscustom) and os.getenv(envlpath)
  if lpath then
    -- add oslibs libraries when LUA_PATH_5_x variables are set to allow debugging to work
    wx.wxSetEnv(envlpath, lpath..';'..ide.oslibs)
  end

  local wfilename = ide:MergePath(ide.config.path.projectdir, sdkFile)
  local ep = exePath(nil,version)
  local pid = CommandLineRun( --tooutput,nohide,stringcallback,uid,endcallback)
    ep.." "..wfilename.." "..cmd,    -- command
    ide.config.path.projectdir,      -- working dir
    true,                            -- nohide
    false,                           --
    nil,                             -- stringcallback
    nil,                             -- uid
    function() ide:Print(endMessage) end
  )
  if (rundebug or version) and cpath then wx.wxSetEnv(envcpath, cpath) end
  if lpath then wx.wxSetEnv(envlpath, lpath) end
  return pid
end

-------- Commandline commands ---------

local function launchHC3Copy()
  ide:Print("Copying and creating DB from HC3...") 
  callFibaroAPIHC3("-downloaddb","Copying done!")
end 

local function downloadFile(file)
  ide:Print("Downloading latest "..file) 
  callFibaroAPIHC3("-downloadfile "..file,"Download done! - "..file)
end

local function uploadResource()
  ide:Print("Uploading to HC3...") 
  local ed = ide:GetEditor()
  if not ed then return end -- all editor tabs are closed
  local file = ide:GetDocument(ed):GetFilePath()
  callFibaroAPIHC3("-push "..file,"Upload done!")
end

local function downloadResource()
  ide:Print("Downloading from HC3...") 
  local editor = ide:GetEditor()
  local length, curpos = editor:GetLength(), editor:GetCurrentPos()
  local ssel, esel = editor:GetSelection()
  local rsrc = editor:GetTextRange(ssel, esel)
  if rsrc and rsrc~="" then
    callFibaroAPIHC3("-pull "..rsrc,"Download done!")
  end
end

local function deployQA()
  ide:Print("Deploying QuickApp...") 
  local ed = ide:GetEditor()
  if not ed then return end -- all editor tabs are closed
  local file = ide:GetDocument(ed):GetFilePath()
  callFibaroAPIHC3("-deploy "..file,"Deploy done!")
end

local function backupResources()
  ide:Print("Backing up resources from HC3...") 
  callFibaroAPIHC3("-backup","Backup done!")
end

---------- API completion and tooltips --------------

local api = {
  fibaro = {
    type = "lib",
    childs = {
      call = {
        description = 
[[Executes an action on the device.
Parameters:
id – identifier of the device on which we want to execute the action. id can be a list of identifiers.
action_name – the name of the action we want to execute.
arguments – list of arguments that the action accepts.
Examples:
Execute “turnOn” action on device with id 30.]],
        type = "function",args = "(id,action_name,...)",returns = "()",
      },
      get = {
        description = 
[[Gets value of device property and the date it was last modified.
Parameters:
id – device ID for which we want to retrieve the property value.
property_name – name of the property which value we want to retrieve.
Action returns: {value, last modification time}.
Examples:
Get the value and the date of the last modification for the value property for device 54
local value, modificationTime = fibaro.get(54, "value")]],
        type = "function",args = "(id,property_name)",returns = "(value,last modification time)",
      },
      debug = {
        description = 
[[Displaying debug level text message in the debugging console.
Parameters:
tag – message tag, can be used to filter messages
message – the content of the message which shows up in the debug window
Examples:
Display “Test message” in a debug window with the tag “TestTag”:
fibaro.debug("TestTag", "Test message")]],
        type = "function", args= "(tag,message)",returns = "()",
      },
      warning = {
        description =
[[Displaying warning level text message in the debugging console. Parameters:
tag – message tag, can be used to filter messages
message – the content of the message which shows up in the debug window
Examples:
Display “Test message” in a debug window with the tag “TestTag”:
fibaro.warning("TestTag", "Test message")]],
        type = "function", args= "(tag,message)",returns = "()",
      },
      trace = {
        description = 
[[Displaying trace level text message in the debugging console.
Parameters:
tag – message tag, can be used to filter messages
message – the content of the message which shows up in the debug window
Examples:
Display “Test message” in a debug window with the tag “TestTag”:
fibaro.trace("TestTag", "Test message")]],
        type = "function", args= "(tag,message)",returns = "()",
      }, 
      error = {
        description = 
[[Displaying error level text message in the debugging console.
Parameters:
tag – message tag, can be used to filter messages
message – the content of the message which shows up in the debug window
Examples:
Display “Test message” in a debug window with the tag “TestTag”:
fibaro.error("TestTag", "Test message")]],
        type = "function", args= "(tag,message)",returns = "()",
      },
      getType = {
        description = 
[[Gets the device type.
Parameters:
id – device ID for which we want to retrieve its type.
The action returns the device type.
Examples:
Retrive type of device 54
local type = fibaro.getType(54)]],
        type = "function", args= "(id)",returns = "(string)",
      },
      getValue = {
        description = 
[[Gets the value of the given property.
Parameters:
id – device ID for which we want to retrieve the property value.
property_name – name of the property which value we want to retrieve.
Action returns only value of the property.
Examples:
Retrieving the value of the value property for device id 54
local value = fibaro.getValue(54, "value")]],
        type = "function", args= "(id,property_name)",returns = "(value)",
      },
      getName = {
        description = 
[[Gets the device name.
Parameters:
id – device ID for which we want to retrieve its name.
The action returns the device name.
Examples:
Retrive name of device 54
local name = fibaro.getName(54)]],
        type = "function", args= "(id)",returns = "(string)",
      },
      getGlobalVariable = {
        description = 
[[Get the value of the global variable.
Parameters:
variable_name – name of variable to get the value of
Examples:
Get the value of variable testVariable.
local value = fibaro.getGlobalVariable("testVariable")]],
        type = "function", args= "(variable_name)",returns = "(string)",
      },
      setGlobalVariable = {
        description = 
[[Set the value of the global variable.
Parameters:
variable_name – the name of the variable we want to update
variable_value – the new value for the variable
Examples:
Change the value of testVariable to testValue.
fibaro.setGlobalVariable("testVariable", "testValue")]],
        type = "function", args= "(variable_name,variable_value)",returns = "()",
      },
      getRoomName = {
        description = 
[[Gets the room name.
Parameters:
id – room ID for which we want to retrieve name.
The action returns room name.
Examples:
Retrive name for room 219
local roomName = fibaro.getRoomName(219)]],
        type = "function", args= "(id)",returns = "(string)",
      },
      getRoomID = {
        description = 
[[Gets the ID of the room to which the device is assigned.
Parameters:
id – device ID for which we want to retrieve its room ID.
The action returns the ID of the room to which the device is assigned.
Examples:
Retrieve ID of the room for device 54
local roomId = fibaro.getRoomID(54)]],
        type = "function", args= "(id)",returns = "(number)",
      },
      getRoomNameByDeviceID = {
        description = 
[[Gets the name of the room to which the device is assigned.
Parameters:
id – device ID for which we want to retrieve its room name.
The action returns room name.
Examples:
Retrieve name of the room for device 54
local roomName = fibaro.getRoomNameByDeviceID(54)]],
        type = "function", args= "(id)",returns = "(string)",
      },
      getSectionID = {
        description = 
[[Gets the ID of the section to which the device is assigned.
Parameters:
id – device ID for which we want to retrieve its section ID.
The action returns the ID of the section to which the device is assigned.
Examples:
Retrieve ID of the section for device 54
local sectionId = fibaro.getSectionID(54)]],
        type = "function", args= "(id)",returns = "(number)",
      },
      getIds = {
        description =
[[Returns a list of device IDs for given devices.
devices – accepts list of device objects.
Examples:
local devices = fibaro.getAllDeviceIds()
local devicesId = fibaro.getIds(devices)]],
        type = "function", args= "(devices)",
      },
      getAllDeviceIds = {
        description = 
[[Returns a list of objects of all devices.
Examples:
local devices = fibaro.getAllDeviceIds()]],
        type = "function", args= "()",returns = "(table)",
      },
      getDevicesID = {
        description = 
[[Returns a list of device IDs that match the given filters.
Parameters:
filter – the way we want to filter the devices]],
        type = "function", args= "(filter)",returns = "(table)",
      },
      scene = {
        description = 
[[Executes given action on a scene.
Parameters:
action – the action we want to perform on scenes, one of the following:
"execute" – uruchomienie sceny
"kill" – zatrzymanie sceny
scenes_ids – list of scenes IDs to perform the action on
Examples:
Execute scenes with IDs 1, 2, 3.
fibaro.scene("execute", {1, 2, 3})
Stop scenes with IDs 1, 2, 3
fibaro.scene("kill", {1, 2, 3})]],
        type = "function", args= "(action,scenes_ids)",returns = "()",
      },
      profile = {
        description = 
[[Executes specified action on the user profile.
Parameters:
profile_id – ID of the profile on which we want to perform the action
action – the action we want to execute on the profile. Currently, only "activateProfile" action is available (activating the profile)
Examples:
Activate profile with ID 1.
fibaro.profile(1, "activateProfile")]],
        type = "function", args= "(profile_id,action)",returns = "()",
      },
      callGroupAction = {
        description = 
[[Executes an action on the devices.
Parameters:
action_name – the name of the action we want to execute.
arguments – list of arguments that the function accepts and device filter.
The action returns a list of devices on which it was performed.]],
        type = "function", args= "(action_name,arguments)",returns = "(table)",
      },
      alert = {
        description =
[[Send custom notification.
alert_type – one of the notification types: “email”, “sms” or “push”
user_ids – list of user identifiers to send the notification to
notification_content – content of the notification to send
Examples:
Send notification with “Test notification” content using email to users with id 2, 3 and 4.
fibaro.alert("email", {2,3,4}, "Test notification")]],
        type = "function", args= "(alert_type,user_ids,notification_content)",returns = "()",
      },
      alarm = {
        description = 
[[Executes specified action on one partition.
Parameters:
partition_id – partition on which we want to execute the action (optional),
action – the action we want to execute. Available actions: “arm”, “disarm”
Examples:
Arm partition no. 1:
fibaro.alarm(1, "arm")]],
        type = "function", args= "(partition_id,action)",returns = "()",
      },
      setTimeout = {
        description = 
[[Performs the function asynchronously with a delay. Parameters:
delay – delay in milliseconds after which the specified function will be performed,
function – function, which will be executed with the delay.
Examples:
Execute function with 30s delay which turns on the device (ID 40) and sets profile 1 as active.
fibaro.setTimeout(30000, function()
    fibaro.call(40, "turnOn")
    fibaro.profile("activateProfile", 1)
end)]],
        type = "function", args= "(delay,function)",returns = "()",
      },
      emitCustomEvent = {
        description =
[[Emitting Custom Event with the specified name.
Parameters:
event_name – the name of the event we want to emit
Examples:
Emitting the event with the name “TestEvent”.
fibaro.emitCustomEvent("TestEvent")]],
        type = "function", args= "(event_name)",returns = "()",
      },
      wakeUpDeadDevice = {
        description = 
[[Wake up a device.
Parameters:
id – device ID to wake up.
Examples:
Wake up device 54
fibaro.wakeUpDeadDevice(54)]],
        type = "function", args= "(id)",returns = "()",
      },
      sleep = {
        description = "Pause the scene/QuickApp for <milliseconds>",
        type = "function", args= "(milliseconds)",returns = "()",
      },
    }   
  },
  api = {
    type = "lib",
    childs = {
      get = {
        description = "Get resource using geteway API",
        type = "function", args= "(uri)",returns="(response data, response HTTP code)",
      },
      put = {
        description = "Send PUT method request to the geteway API",
        type = "function", args= "(uri,data)",returns="(response data, response HTTP code)",
      },
      post = {
        description = "Send POST method request to the geteway API",
        type = "function", args= "(uri,data)",returns="(response data, response HTTP code)",
      },
      delete = {
        description = "Delete resource using geteway API",
        type = "function", args= "(uri)",returns="(response data, response HTTP code)",
      },
    }
  },
  json = {
    type = "lib",
    childs = {
      encode = {
        description =
[[Convert Lua table to the text represented in JSON format.
Parameters:
table – Lua table
Examples:
Display sourceTrigger in the debug console.
fibaro.debug("", json.encode(sourceTrigger))]],
        type = "function", args= "(table)",returns="(string)",
      },
      decode = {
        description = 
[[Convert the text represented in JSON format to Lua table.
Parameters:
text – data in JSON format
Examples:
local tmp = "{\"test\":11}"
local array = json.decode(tmp)]],
        type = "function", args= "(text)",returns="(table)",
      },
    }
  },
  net = {
    type = "lib",
    childs = {
      HTTPClient = {
        description =[[...]],
        type = "function", args= "(url,options)",returns="(http object). QuickApp only.",
      },
      TCPSocket = {
        description = [[....]],
        type = "function", args= "(ipaddress)",returns="(socket object). QuickApp only.",
      },
    }
  },
  setTimeout = {
    type = "function",args="(function,milliseconds)",returns="(reference)",
    description = "Schedules a function to run <milliseconds> from now. QuickApp only.",
  },
  clearTimeout = {
    type = "function",args="(reference)",returns="()",
    description = "Cancels a function scheduled with setTimeout. QuickApp only.",
  },
  setInterval = {
    type = "function",args="(function,milliseconds)",returns="(reference)",
    description = "Schedules a function to run every <milliseconds> interval. QuickApp only.",
  },
  clearInterval = {
    type = "function",args="(reference)",returns="(reference)",
    description = "Cancels a function scheduled with setInterval. QuickApp only.",
  },
  QuickApp = {
    type = "class",
    childs = {
      onInit = {
        type="method",args="()",returns="()",
        description="",
      }
    }
  },
  self = {
    type = "class",
    childs = {  
      setVariable = { 
        type="method",args="(variable,value)",returns="()",
        description="QuickApp only.",
      },
      getVariable = { 
        type="method",args="(variable)",returns="(value)",
        description="QuickApp only.",
      },
      debug = { 
        type="method",args="(strings)",returns="()",
        description="QuickApp only.",
      },
      updateView = { 
        type="method",args="(element,type,value)",returns="()",
        description="QuickApp only.",
      },
      updateProperty = { 
        type="method",args="(property,value)",returns="()",
        description="QuickApp only.",
      },
    }
  }
}

local function getWebContent(url)
  local https = require ("ssl.https")
  local ltn12 = require("ltn12")
  local socket = require("socket")
  local http = require("socket.http")
  local resp = {}
  local req = { method = "GET", url = url, headers = { ["Content-Length"]=0 }, sink = ltn12.sink.table(resp) }
  local res,status,headers = https.request(req)
  if status >= 200 and status < 300 then resp = table.concat(resp) end
  return resp, status
end

local function downloadContent(fdef)
  local ps = ide.osname == "Windows" and "\\" or "/"
  local stat,res = pcall(function()
      if fdef.url then
        printf("Downloading %s",fdef.url)
        local src,code = getWebContent(fdef.url)
        local f = io.open(ide.config.path.projectdir..ps..fdef.path,"w+")
        f:write(src)
        printf("Writing %s",fdef.path)
        f:close()
      elseif fdef.urldir then
        lfs.mkdir(ide.config.path.projectdir..ps..fdef.pathdir)
        for fn,p in pairs(fdef.files) do
          printf("Downloading %s",fn)
          local src,code = getWebContent(fdef.urldir..fn)
          local f = io.open(ide.config.path.projectdir..ps..fdef.pathdir..ps..p,"w+")
          printf("Writing %s",fdef.pathdir..ps..p)
          f:write(src)
          f:close()
        end
      end
    end)
  if not stat then printf("Error downloading %s - %s",fdef.url or fdef.urldir,res) end
end

local function sendCommandToEmulator(cmd)
  local https = require ("ssl.https")
  local ltn12 = require("ltn12")
  local socket = require("socket")
  local http = require("socket.http")
  local url = "http://127.0.0.1:6872/web/"
  local resp = {}
  local req = { method = "GET", url = url, headers = { ["Content-Length"]=0 }, sink = ltn12.sink.table(resp) }
  local res,status,headers = http.request(req)
  return res,status
end

local interpreter = {
  name =  [[HC3 emulator]],
  description = [[Lua 5.3 for HC3]],
  api = {"baselib", "HC3"},
  luaversion = version or '5.3',
  fexepath = exePath, 
  frun = function(self,wfilename,rundebug)
    local exe = self:fexepath(version or "")
    local filepath = wfilename:GetFullPath()
    local fibaroName = sdkFile
    local projectPath = ide:GetProject()
    if projectPath then fibaroName = projectPath..fibaroName end
    local tmplua = wx.wxFileName()
    tmplua:AssignTempFileName(".")
    tmpluafile = tmplua:GetFullPath()
    local flua = io.open(tmpluafile, "w")
    if not flua then
      DisplayOutput("Can't open temporary file '"..filepath.."' for writing\n")
      return
    end
    flua:write("local md = require('mobdebug')\n")
    flua:write("md.basedir([[projectPath]])\n")
    flua:write("md.start()\n")
    flua:write("if dofile and hc3_emulator==nil then\n")   
    flua:write("  hc3_emulator = { loadconfigs=true }\n")    
    flua:write(("  dofile([[%s]])\n"):format(sdkFile))   
    flua:write("end\n")
    flua:write(("hc3_emulator.loadQAScene([[%s]]):install()\n"):format(filepath))
    flua:close()

    if rundebug then
      -- prepare tmp file

      DebuggerAttachDefault({runstart = true})      
      -- update arg to point to the proper file
      rundebug = ('if arg then arg[0] = [[%s]] end '):format(tmpluafile)..rundebug


      -- local tmpfile = wx.wxFileName()
      -- tmpfile:AssignTempFileName(".")
      -- tmpluafile = tmpfile:GetFullPath()
      local f = io.open(tmpluafile, "a")
      if not f then
        DisplayOutput("Can't open temporary file '"..tmpluafile.."' for writing\n")
        return
      end
      f:write(rundebug)
      f:close()
    else	  
      -- if running on Windows and can't open the file, this may mean that
      -- the file path includes unicode characters that need special handling
      local fh = io.open(tmpluafile, "r")
      if fh then fh:close() end
      if ide.osname == 'Windows' and pcall(require, "winapi")
      and wfilename:FileExists() and not fh then
        winapi.set_encoding(winapi.CP_UTF8)
        tmpluafile = winapi.short_path(tmpluafile)
      end
    end
    local params = ide.config.arg.any or ide.config.arg.lua
    local code = ([[-e "io.stdout:setvbuf('no')" "%s"]]):format(tmpluafile)
    local cmd = '"'..exe..'" '..code..(params and " "..params or "")

    -- modify CPATH to work with other Lua versions
    local clibs = ('/clibs%s/'):format(version and tostring(version):gsub('%.','') or '')
    local _, cpath = wx.wxGetEnv("LUA_CPATH")
    if version and cpath and not cpath:find(clibs, 1, true) then
      wx.wxSetEnv("LUA_CPATH", cpath:gsub('/clibs/', clibs)) end

      -- CommandLineRun(cmd,wdir,tooutput,nohide,stringcallback,uid,endcallback)
      local pid = CommandLineRun(cmd,self:fworkdir(wfilename),true,false,nil,nil,
        function() 
          if rundebug then wx.wxRemoveFile(tmpluafile) end 
        end)

      if version and cpath then wx.wxSetEnv("LUA_CPATH", cpath) end
      return pid
    end, 
    fprojdir = function(self,wfilename)
      return wfilename:GetPath(wx.wxPATH_GET_VOLUME)
    end,
    fworkdir = function (self,wfilename)
      return ide.config.path.projectdir or wfilename:GetPath(wx.wxPATH_GET_VOLUME)
    end,
    hasdebugger = true,
    fattachdebug = function(self) DebuggerAttachDefault() end,
  }

  local name = "fibaro"
  return {
    name = "HC3 SDK support",
    description = "Support for HC3 SDK emulator and templates.",
    author = "Jan Gabrielsson",
    version = 0.1,
    dependencies = "1.0",

    onRegister = function()

      --local res,stat = getWebContent("https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/EventRunner4.lua")
      --ide:Print(stat)

      ide:AddInterpreter("HC3", interpreter)

      local menu = ide:FindTopMenu("&View")
      menu:Append(idem, "HC3 Emulator\tCtrl-Alt-E"..KSC(idem))
      ide:GetMainFrame():Connect(idem, wx.wxEVT_COMMAND_MENU_SELECTED, launchEmulator)

      menu = ide:FindTopMenu("&Help")
      menu:AppendSeparator()

      local function addLinkHelp(name,url)
        local id = ID("HC3."..name)
        menu = ide:FindTopMenu("&Help")
        menu:Append(id, name..KSC(id))
        ide:GetMainFrame():Connect(id, wx.wxEVT_COMMAND_MENU_SELECTED, function() openURL(url) end)
      end

      addLinkHelp("HC3 SDK (fibaroapiHC3.lua) help",urlHC3Help)
      addLinkHelp("Fibaro QuickApp manual",urlHC3QAHelp)
      addLinkHelp("Fibaro QuickAppChild manual",urlHC3ChildHelp)
      addLinkHelp("Fibaro Lua Scene manual",urlHC3ScHelp)
      addLinkHelp("Fibaro MQTT Client manual",urlHC3MQTTHelp)
      addLinkHelp("Fibaro WebSocket Client manual",urlHC3WSHelp)

      menu = ide:FindTopMenu("&File")
      menu:AppendSeparator()
      menu:Append(idech3, "Download HC3 local resource file"..KSC(idech3))
      ide:GetMainFrame():Connect(idech3, wx.wxEVT_COMMAND_MENU_SELECTED, launchHC3Copy)

      menu = ide:FindTopMenu("&File")
      templSubMenu2 = ide:MakeMenu()
      templ2 = menu:AppendSubMenu(templSubMenu2, TR("Download files..."))

      if downLoads and downLoads.files then
        local i,tab = 1,{}
        for name,code in pairs((downLoads or {}).files or {}) do tab[#tab+1]=name end
        table.sort(tab)
        for _,name in ipairs(tab) do  
          local id = ID("HC3."..name)
          templSubMenu2:Append(id, name..KSC(id))
          ide:GetMainFrame():Connect(id, wx.wxEVT_COMMAND_MENU_SELECTED, 
            function() downloadContent(downLoads.files[name]) end)  
        end
      end

      menu = ide:FindTopMenu("&Project")
      menu:AppendSeparator()
      menu:Append(ide_deploy, "Deploy QuickApp/Scene"..KSC(ide_deploy))
      ide:GetMainFrame():Connect(ide_deploy, wx.wxEVT_COMMAND_MENU_SELECTED, deployQA)

      menu = ide:FindTopMenu("&Edit")
      templSubMenu = ide:MakeMenu()
      templ = menu:AppendSubMenu(templSubMenu, TR("HC3 SDK templates..."))

      if codeTemplates and codeTemplates.templates then 
        local i,tab = 1,{}
        for name,code in pairs((codeTemplates or {}).templates or {}) do tab[#tab+1]=name end
        table.sort(tab)
        for _,name in ipairs(tab) do
          local id = ID("HC3.temp_ERT"..i); i=i+1
          templSubMenu:Append(id, name..KSC(id))
          ide:GetMainFrame():Connect(id, wx.wxEVT_COMMAND_MENU_SELECTED, 
            function() ide:GetEditor():InsertText(-1, codeTemplates.templates[name]) end)
        end
      end

      -- add API with name "sample" and group "lua"
      table.insert(ide:GetConfig().api, name)
      ide:AddAPI("lua", name, api)
    end,

    onUnRegister = function()  
      ide:RemoveMenuItem(idech3)
      ide:RemoveMenuItem(idech31)
      ide:RemoveMenuItem(idech33)
      ide:RemoveMenuItem(idem)
      ide:RemoveMenuItem(ideh)
      ide:RemoveMenuItem(idet)
      -- remove API with name "sample" from group "lua"
      ide:RemoveAPI("lua", name)
    end,

--  onMenuEditor = function(self, menu, editor, event)
--    menu:AppendSeparator()
--    menu:Append(id, "..."..KSC(id))
--  end

  }