--[[
%% properties
%% events
%% globals
%% autostart
--]]

--[[
-- EventRunnerLite. Single scene instance framework
-- Copyright 2018 Jan Gabrielsson. All Rights Reserved.
-- Email: jan@gabrielsson.com
--]]

_version = "1.14" 
osTime = os.time
osDate = os.date
_SPEEDTIME=false
_debugFlags = { post=false,invoke=false,triggers=false,timers=false,fibaro=true,fibaroGet=false }
if dofile then dofile("EventRunnerDebug.lua") end -- Support for running off-line on PC/Mac

_deviceTable = "HomeTable"         -- name of HomeTable global

local _test = true                -- use local HomeTable variable instead of fibaro global
local homeLatitude,homeLongitude  -- set to first place in HomeTable.places list

HomeTable = [[
{"scenes":{
    "iOSLocator":{"id":11,"send":["iOSClient"]},
    "iOSClient":{"id":9,"send":{}},
  },
"places":[
    {"longitude":17.9876023512,"dist":0.6,"latitude":60.7879477,"name":"Home"},
    {"longitude":17.955049,"dist":0.8,"latitude":59.405818,"name":"Ericsson"},
    {"longitude":18.080638,"dist":0.8,"latitude":59.52869,"name":"Vallentuna"},
    {"longitude":17.648488,"dist":0.8,"latitude":59.840704,"name":"Polacksbacken"},
    {"longitude":17.5951,"dist":0.8,"latitude":59.850153,"name":"Flogsta"},
    {"longitude":18.120588,"dist":0.5,"latitude":59.303781,"name":"Rytmus"}
  ],
"users":{
    "daniela":{"phone":777,"icloud":{"pwd":"XXXX","user":"XXX@XXX.com"},"name":"Daniela"},
    "jan":{"phone":411,"icloud":{"pwd":"XXXX","user":"XXX@XXX.com"},"name":"Jan"},
    "tim":{"phone":888,"icloud":{"pwd":"XXXXX","user":"XXX@XXX.com"},"name":"Tim"},
    "max":{"phone":888,"icloud":{"pwd":"XXXXX","user":"XXX@XXX.com"},"name":"Max"}
  },
}
]]
if dofile then dofile("iOScredentials.lua") end

INTERVAL = 90 -- check every 90s
local nameOfHome = "Home"
local whereIsUser = {}
local devicePattern = "iPhone"
local extrapolling = 4000
local conf
locations = {}
homeFlag = false

function distance(lat1, lon1, lat2, lon2)
  local dlat = math.rad(lat2-lat1)
  local dlon = math.rad(lon2-lon1)
  local sin_dlat = math.sin(dlat/2)
  local sin_dlon = math.sin(dlon/2)
  local a = sin_dlat * sin_dlat + math.cos(math.rad(lat1)) * math.cos(math.rad(lat2)) * sin_dlon * sin_dlon
  local c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
  local d = 6378 * c
  return d
end

function enc(data)
  local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((data:gsub('.', function(x) 
          local r,b='',x:byte()
          for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
          return r;
        end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
      end)..({ '', '==', '=' })[#data%3+1])
end

function getIOSDeviceNextStage(nextStage,username,headers,pollingextra)
  pollingextra = pollingextra or 0
  HTTP:request("https://" .. nextStage .. "/fmipservice/device/" .. username .."/initClient",{
      options = { headers = headers, data = '', method = 'POST', timeout = 20000 },
      error = function(status)
        Debug(true,"Error getting NextStage data:"..status)
      end,
      success = function(status)
        local output = json.decode(status.data,{statusCode=="444"})
        --Debug("iCloud Response:"..status.data)
        if (output.statusCode=="200") then			
          if (pollingextra==0) then
            listDevices(output.content)
          else
            Debug(2,"Waiting for NextStage extra polling")
            fibaro:sleep(extrapolling)	
            getIOSDeviceNextStage(nextStage,username,headers,0)
          end
        end
        Debug(true,"Bad response from NextStage:" .. json.encode(status) )	
      end})
end

_format = string.format

---- Single scene instance, all fibaro triggers call main(sourceTrigger) ------------

function main(sourceTrigger)
  local event = sourceTrigger

  if event.type=='global' and event.name == _deviceTable then
    iUsers = {}
    local gname = _test and HomeTable or fibaro:getGlobalValue(_deviceTable)
    if gname  == nil or gname == "" then 
      Debug(true,"Missing configuration data, HomeTable='%s'",_deviceTable or "")
      fibaro:abort()
    end
    conf = json.decode(gname)
    homeLatitude=conf.places[1].latitude
    homeLongitude=conf.places[1].longitude
    for _,v in pairs(conf.users) do if v.icloud then v.icloud.name = v.name iUsers[#iUsers+1] = v.icloud end end
    Debug(true,"Configuration data:")
    for _,p in ipairs(iUsers) do Debug(true,"User:%s",p.name) end
    for _,p in ipairs(conf.places) do 
      Debug(true,"Place:%s",p.name) 
      if p.name==nameOfHome then 
        homeLatitude=p.latitude
        homeLongitude=p.longitude
      end
    end
  end

  if event.type=='location_upd' then 
    local loc = event.result.location
    if not loc then return end
    for _,v in ipairs(conf.places) do
      local d = distance(loc.latitude,loc.longitude,v.latitude,v.longitude)
      if d < v.dist then 
        post({type='checkPresence', user=event.user, place=v.name, dist=d, _sh=true})
        return
      end
    end
    post({type='checkPresence', user=event.user, place='away', dist=event.result.distance, _sh=true})
  end

  if event.type == 'deviceMap' then
    local dm = event.data  
    if dm ==nil then return end
    -- Get the list of all iDevices in the iCloud account
    local result = {}
    for key,value in pairs(dm) do
      local loc = value.location
      if value.name:match(devicePattern) and loc and type(loc) == 'table' then
        local d = distance(loc.latitude,loc.longitude,homeLatitude,homeLongitude)
        result[#result+1] = {device=value.name, distance=d, location=loc}
      end
    end
    if #result == 1 then result = result[1] end
    --Log(LOG.LOG,"%s LOC:%s",env.p.user,json.encode(result))
    post({type='location_upd', user=event.user, result=result, _sh=true})
  end

  if event.type=='getIOSdevices' then --, user='$user', name = '$name', pwd='$pwd'},
    --Debug(true,"getIOSdevices for:%s",event.user)
    pollingextra = event.polling or 0

    HTTP = net.HTTPClient()

    local headers = {
      ["Authorization"]="Basic ".. enc(event.user..":"..event.pwd), 
      ["Content-Type"] = "application/json; charset=utf-8",
      ["X-Apple-Find-Api-Ver"] = "2.0",
      ["X-Apple-Authscheme"] = "UserIdGuest",
      ["X-Apple-Realm-Support"] = "1.0",
      ["User-agent"] = "Find iPhone/1.3 MeKit (iPad: iPhone OS/4.2.1)",
      ["X-Client-Name"]= "iPad",
      ["X-Client-UUID"]= "0cf3dc501ff812adb0b202baed4f37274b210853",
      ["Accept-Language"]= "en-us",
      ["Connection"]= "keep-alive"}

    HTTP:request("https://fmipmobile.icloud.com/fmipservice/device/" .. event.user .."/initClient",{
        options = {
          headers = headers,
          data = '',
          method = 'POST', 
          timeout = 20000
        },
        error = function(status) 
          post({type='error', msg=_format("Failed calling FindMyiPhone service for %s",event.user)})
        end,
        success = function(status)
          if (status.status==330) then
            local nextStage="fmipmobile.icloud.com" --status.headers["x-apple-mme-host"]
            Debug(2,"NextStage")
            getIOSDeviceNextStage(nextStage,event.user,headers,pollingextra)
          elseif (status.status==200) then
            --Debug(true,"Data:%s",json.encode(status.data))
            post({type='deviceMap', user=event.name, data=json.decode(status.data).content, _sh=true})
          else
            post({type='error', msg=_format("Access denied for %s :%s",event.user,json.encode(status))})
          end
        end})
  end

  if event.type == 'checkPresence' then
    if whereIsUser[event.user] ~= event.place then  -- user at new place
      whereIsUser[event.user] = event.place
      Debug(true,"%s is at %s",event.user,event.place)
      local ev = {type='location', user=event.user, place=event.place, dist=event.dist, ios=true}
      local evs = json.encode(ev)
      for _,v in pairs(conf.scenes.iOSLocator.send) do
        Debug(true,"Sending %s to scene %s",evs,conf.scenes[v].id)
        postRemote(conf.scenes[v].id,ev)
      end
    end

    local user,place,ev=event.user,event.place 
    locations[user]=place
    local home = false
    local who = {}
    for w,p in pairs(locations) do 
      if p == nameOfHome then home=true; who[#who+1]=w end
    end
    if home and homeFlag ~= true then 
      homeFlag = true
      ev={type='presence', state='home', who=table.concat(who,','), ios=true}
    elseif #locations == #iUsers then
      if homeFlag ~= false then
        homeFlag = false
        ev={type='presence', state='allaway', ios=true}
      end
    end
    if ev then
      local evs = json.encode(ev)
      for _,v in pairs(conf.scenes.iOSLocator.send) do
        Debug(true,"Sending %s to scene %s",evs,conf.scenes[v].id)
        postRemote(conf.scenes[v].id,ev)
      end
    end
  end

  if event.type == 'getLocations' then -- Resend all locations if scene asks for it
    Debug(true,"Got remote location request from scene:%s",event._from)
    for u,p in pairs(whereIsUser) do
      if u and p then
        Debug(true,"User:%s Position:%s",u,p)
        postRemote(event._from,{type='location', user=u, place=p, ios=true})
      end
    end
  end

  if event.type=='poll' then
    local index = event.index
    local user = iUsers[(index % #iUsers)+1]
    post({type='getIOSdevices', user=user.user, pwd=user.pwd, name=user.name})
    post({type='poll',index=index+1},math.floor(0.5+INTERVAL/#iUsers)) -- INTERVAL=60 => check every minute
  end

  if event.type == 'error' then 
    Debug(true,"Error %s",event.msg)
  end

  if event.type == 'autostart' or event.type == 'other' then 
    post({type='global', name=_deviceTable})
    post({type='poll',index=1})
  end

  if event.type == '%%PING%%' then event.type='%%PONG%%' postRemote(event._from,event) end

end -- main()

------------------------ Framework, do not change ---------------------------  
-- Spawned scene instances post triggers back to starting scene instance ----
local _trigger = fibaro:getSourceTrigger()
local _type, _source = _trigger.type, _trigger
local _MAILBOX = "MAILBOX"..__fibaroSceneId 
function urldecode(str) return str:gsub('%%(%x%x)',function (x) return string.char(tonumber(x,16)) end) end
if _type == 'other' and fibaro:args() then
  _trigger,_type = urldecode(fibaro:args()[1]),'remote'
end
gEventRunnerKey="6w8562395ue734r437fg3"

function _midnight() local t=osDate("*t"); t.min,t.hour,t.sec=0,0,0; return osTime(t) end
function _now() local t=osDate("*t"); return 60*(t.min+60*t.hour)+t.sec end

function hm2sec(hmstr)
  local sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
  if sun and (sun == 'sunset' or sun == 'sunrise') then
    hmstr,offs = fibaro:getValue(1,sun.."Hour"), tonumber(offs) or 0
  end
  local h,m,s = hmstr:match("(%d+):(%d+):?(%d*)")
  return h*3600+m*60+(tonumber(s) or 0)+(offs or 0)*60
end

function toTime(time)
  if type(time) == 'number' then return time end
  local p = time:sub(1,2)
  if p == '+/' then return hm2sec(time:sub(3)) -- Plus now
  elseif p == 'n/' then
    local t1 = hm2sec(time:sub(3))      -- Next
    return t1 > _now() and t1 or t1+24*60*60
  elseif p == 't/' then return  hm2sec(time:sub(3))-_now()  -- Today
  else return hm2sec(time) end
end

if not Debug then function Debug(flag,message,...) if flag then fibaro:debug(string.format(message,...)) end end end

function post(event, time) 
  if type(time)=='string' then time=toTime(time) else time = time or 0 end
  if _debugFlags.post then Debug(true,"Posting {type=%s,...} for %s",event.type,osDate("%X",time+osTime())) end
  return setTimeout(function() 
      if _OFFLINE and not _REMOTE then if _simFuns[ event.type ] then _simFuns[ event.type ](event)  end end
      main(event) 
    end,
    time*1000) 
end
function cancel(ref) if ref then clearTimeout(ref) end return nil end
function postRemote(sceneID,event) event._from=__fibaroSceneId; fibaro:startScene(sceneID,{urlencode(json.encode(event))}) end

---------- Producer(s) - Handing over incoming triggers to consumer --------------------
if ({property=true,global=true,event=true,remote=true})[_type] then
  if fibaro:countScenes() == 1 then fibaro:debug("Aborting: Server not started yet"); fibaro:abort() end
  local event = type(_trigger) ~= 'string' and json.encode(_trigger) or _trigger
  local ticket = string.format('<@>%s%s',tostring(_source),event)
  repeat 
    while(fibaro:getGlobal(_MAILBOX) ~= "") do fibaro:sleep(100) end -- try again in 100ms
    fibaro:setGlobal(_MAILBOX,ticket) -- try to acquire lock
  until fibaro:getGlobal(_MAILBOX) == ticket -- got lock
  fibaro:setGlobal(_MAILBOX,event) -- write msg
  fibaro:abort() -- and exit
end

---------- Consumer - Handing over incoming triggers to main() --------------------
local function _poll()
  local l = fibaro:getGlobal(_MAILBOX)
  if l and l ~= "" and l:sub(1,3) ~= '<@>' then -- Something in the mailbox
    fibaro:setGlobal(_MAILBOX,"") -- clear mailbox
    Debug(_debugFlags.triggers,"Incoming event %s",l)
    post(json.decode(l)) -- and "post" it to our "main()" in new "thread"
  end
  setTimeout(_poll,250) -- check every 250ms
end

-- Logging of fibaro:* calls -------------
function interceptFib(name,flag,spec,mf)
  local fun,fstr = fibaro[name],name:match("^get") and "fibaro:%s(%s%s%s) = %s" or "fibaro:%s(%s%s%s)"
  if spec then 
    fibaro[name] = function(obj,...) if _debugFlags[flag] then return spec(obj,fun,...) else return fun(obj,...) end end 
  else 
    fibaro[name] = function(obj,id,...)
      local id2,args = type(id) == 'number' and Util.reverseVar(id) or '"'..id..'"',{...}
      local status,res,r2 = pcall(function() return fun(obj,id,table.unpack(args)) end)
      if status and _debugFlags[flag] then
        fibaro:debug(string.format(fstr,name,id2,(#args>0 and "," or ""),json.encode(args):sub(2,-2),json.encode(res)))
      elseif not status then
        error(string.format("Err:fibaro:%s(%s%s%s), %s",name,id2,(#args>0 and "," or ""),json.encode(args):sub(2,-2),res),3)
      end
      if mf then return res,r2 else return res end
    end
  end
end
interceptFib("call","fibaro")
interceptFib("setGlobal","fibaroSet")
interceptFib("getGlobal","fibaroGet",nil,true)
interceptFib("getGlobalValue","fibaroGet")
interceptFib("get","fibaroGet",nil,true)
interceptFib("getValue","fibaroGet")
interceptFib("killScenes","fibaro")
interceptFib("startScene","fibaroStart",
  function(obj,fun,id,args) 
    local a = args and #args==1 and type(args[1])=='string' and (json.encode({(urldecode(args[1]))})) or ""
    fibaro:debug(string.format("fibaro:start(%s,%s)",id,a))
    fun(obj,id, args) 
  end)

---------- Startup --------------------
if _type == 'autostart' or _type == 'other' then
  fibaro:debug("Starting iOS Locator service")
  if not _OFFLINE then 
    if not string.find(json.encode((api.get("/globalVariables/"))),"\"".._MAILBOX.."\"") then
      api.post("/globalVariables/",{name=_MAILBOX}) 
    end
    fibaro:setGlobal(_MAILBOX,"") 
    _poll()  -- start polling mailbox
    main(_trigger)
  else
    collectgarbage("collect") GC=collectgarbage("count")
    _System.runOffline(function() main(_trigger) end) 
  end
end