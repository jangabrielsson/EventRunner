--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Module Settings

--]]
local EM,FB = ...

local LOG,DEBUG,json = EM.LOG,EM.DEBUG,FB.json
local luaFormated = EM.utilities.luaFormated

local configParams = {
  { cfp='user', name="User ID", type='str', descr="Account used to interact with the HC3 via REST api"},
  { cfp='pwd', name="Password", type='str', descr="Password for account used to interact with the HC3 via REST api"},
  { cfp='host', name="IP address", type='str', descr="IP address of HC3 - Ex. 192.168.x.y"},
  { cfp='pin', name="PIN code", type='str', descr="PIN code to set/unset alarms etc"},
  { cfp='modPath', name="Module path", type='str', descr="Path to TQAE modules. Default \"TQAEmodules\""},
  { cfp='temp', name="Temp path", type='str', descr="Path to temp directory. Default \"temp\""},
  { cfp='startTime', name="Start time", type='str', 
    descr=[[Start date for the emulator. Ex. "12/24/2024-07:00" to start emulator at X-mas morning 07:00 2024.
  Default, current local time]]},
  { cfp='copas', name="Copas asynchronous timers", type='bool', descr="If true will use the copas scheduler. Default true"},
  { cfp='noweb', name="No web interface", type='bool', descr="If true will not start up local web interface. Default false"},
  { cfp='compat', name="Yield safe functions", type='bool', descr="Use yield compatibe sort/gsub functions. Default false"},
}

local function save(_,client,ref,_,opts)
  local configFile = opts.cf
  local stat,res = pcall(function()
      assert(type(configFile)=="string","Missing file name")
      local configs = EM.configFileValues
      configs.debug = configs.debug or {}
      for fl,_ in pairs(LOG.flags) do 
        configs.debug[fl] = opts[fl]=='on'
      end
      for _,c in ipairs(configParams) do 
        configs[c.cfp] = opts[c.cfp] ~= "" and opts[c.cfp] or nil
      end
      LOG.sys("Saving configuration file: %s",configFile)
      LOG.sys("\n%s",luaFormated(configs))
      local f = io.open(configFile,"w+")
      f:write("return "..luaFormated(configs))
      f:close()
    end)
  if not stat then LOG.error("Failed writing configuration file %s - %s",tostring(configFile),res) 
  else
    EM.readConfigFile = configFile
    LOG.sys("Saved configuration file:%s",configFile) 
  end
  client:send("HTTP/1.1 302 Found\nLocation: "..ref.."\n\n")
  return true
end

local function assertf(test,fmt,...) if not test then error(string.format(fmt,...),2) end end

local function read(_,client,ref,_,opts)
  local configFile = opts.cf
  local stat,res = pcall(function()
      local cf,res = loadfile(configFile)
      assertf(cf,"Failed reading %s - %s",tostring(configFile),res)
      res,cf = pcall(cf)
      assertf(res,"Failed reading %s - %s",tostring(configFile),cf)
      assertf(type(cf)=="table","Bad format - expected table %s",tostring(configFile))
      LOG.sys("Reading configuration file:%s",configFile)
      LOG.sys("%s",json.encode(cf))
      EM.configFileValues = cf
    end)
  if not stat then LOG.error("Failed reading configuration file %s - %s",tostring(configFile),res) 
  else
    EM.readConfigFile = configFile
  end
  client:send("HTTP/1.1 302 Found\nLocation: "..ref.."\n\n")
  return true
end

local function setup()
  EM.addPath("GET/TQAE/saveConfigFile",save)
  EM.addPath("GET/TQAE/readConfigFile",read)
  EM.configParams = configParams
end

EM.EMEvents('start',setup)