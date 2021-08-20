local EM,FB,ARGS=...

local lfs = require("lfs")
local LOG,port,name = EM.LOG, ARGS.port or 8976, ARGS.name or "WebAPI"
local socket = require("socket")
local fmt,json = string.format,FB.json

local IPAddress
do
  local someRandomIP = "192.168.1.122" --This address you make up
  local someRandomPort = "3102" --This port you make up  
  local mySocket = socket.udp() --Create a UDP socket like normal
  mySocket:setpeername(someRandomIP,someRandomPort) 
  local myDevicesIpAddress,_ = mySocket:getsockname()-- returns IP and Port
  IPAddress = myDevicesIpAddress == "0.0.0.0" and "127.0.0.1" or myDevicesIpAddress
end

local function coprocess(ms,fun,tag,...)
  local args = {...}
  local p = coroutine.create(function() fun(table.unpack(args)) end)
  local function process()
    local _,err = coroutine.resume(p)
    local stat = coroutine.status(p) -- run every ms
    if stat~="dead" then FB.setTimeout(process,ms,tag) end 
    if stat == 'dead' and err then
      LOG("Webserver error %s",err)
      LOG("Webserver error %s",debug.traceback(p))
    end
  end
  process()
end

local function clientHandler(client,handlers)
  client:settimeout(0,'b')
  client:setoption('keepalive',true)
  --local ip=client:getpeername()
  --printf("IP:%s",ip)
  while true do
    local l,e,j = client:receive()
    --print(format("L:%s, E:%s, J:%s",l or "nil", e or "nil", j or "nil"))
    if l then
      local body,referer,header,e,b
      local method,call = l:match("^(%w+) (.*) HTTP/1.1")
      repeat
        header,e,b = client:receive()
        --print(format("H:%s, E:%s, B:%s",header or "nil", e or "nil", b or "nil"))
        if b and b~="" then body=b end
        referer = header and header:match("^[Rr]eferer:%s*(.*)") or referer
      until header == nil or e == 'closed'
      if handlers[method] then handlers[method](method,client,call,body,referer) end
      --client:flush()
      client:close()
      return
    end
    coroutine.yield()
  end
end

local function socketServer(server,handlers)
  while true do
    local client,err
    repeat
      client, err = server:accept()
      if err == 'timeout' then coroutine.yield() end
    until err ~= 'timeout'
    coprocess(10,clientHandler,"Web:client",client,handlers)
  end
end

local function createServer(name,port,handlers)
  local server,c,err=socket.bind("*", port)
  --print(err,c,server)
  local i, p = server:getsockname()
  assert(i, p)
  --printf("http://%s:%s/test",ipAdress,port)
  server:settimeout(0,'b')
  server:setoption('keepalive',true)
  coprocess(10,socketServer,"Web:server",server,handlers)
  LOG("Created %s at %s:%s",name,IPAddress,port)
end

local GUI_HANDLERS = {
  ["GET"] = {
    ["/api/callAction%?deviceID=(%d+)&name=(%w+)(.*)"] = function(client,ref,body,id,action,arg)
      local args = {}
      if arg and arg:sub(1,1)=='?' then
        arg=arg:sub(2)
        arg = arg:split("&")
        for _,a in ipairs(arg) do
          local i,v = a:match("^arg(%d+)=(.*)")
          args[tonumber(i)]=json.decode(FB.urldecode(v))
        end
      end
      id = tonumber(id) ---id,name,path,data)
      local stat,err=pcall(FB.__fibaro_call,id,action,"",{args=args})
      if not stat then LOG("Bad callAction:%s",err) end --\nLocation: "..(headers['referer'] or "/web/main").."\n")
      -- client:send("HTTP/1.1 201 Created\nETag: \"c180de84f991g8\"\nLocation: "..ref.."\n\n")
      client:send("HTTP/1.1 302 Found\nLocation: "..ref.."\n\n")
      return true
    end,
    ["/TQAE/method%?(.*)"] = function(client,ref,body,args)
      args = args:split("&")
      local keys = {}
      for _,a in ipairs(args) do k,v = a:match("(.-)=(.*)") keys[k]=FB.urldecode(v) end
      local arg = keys.Args
      local stat,res = pcall(function()
          arg = json.decode("["..arg.."]")
          local QA = EM.getQA(tonumber(keys.qaID))
          local res = {QA[keys.method](QA,table.unpack(arg))}
          LOG("Web call: QA(%s):%s%s = %s",keys.qaID,keys.method,json.encode(arg),json.encode(res))
        end)
      if not stat then 
        LOG("Error: Web call: QA(%s):%s%s - %s",keys.qaID,keys.method,json.encode(arg),res)
      end
      client:send("HTTP/1.1 302 Found\nLocation: "..ref.."\n\n")
      return true
    end,
    ["/TQAE/lua%?(.*)"] = function(client,ref,body,code)
      EM.QAs[99].env.plugin.restart()
      code = load(code,nil,"t",{EM=EM,FB=FB})
      code()
      client:send("HTTP/1.1 302 Found\nLocation: "..ref.."\n\n")
      return true
    end,
  },
  ["POST"] = {
    ["/TQAE/action/(.+)$"] = function(client,ref,body,id) onAction(json.decode(body)) end,
    ["/TQAE/ui/(.+)$"] = function(client,ref,body,id) onUIEvent(json.decode(body)) end,
  }
}

local function GUIhandler(method,client,call,body,ref) 
  local stat,res = pcall(function()
      for p,h in pairs(GUI_HANDLERS[method] or {}) do
        local match = {call:match(p)}
        if match and #match>0 then
          if h(client,ref,body,table.unpack(match)) then return end
        end
      end
      client:send("HTTP/1.1 501 Not Implemented\nLocation: "..(ref or call).."\n")
    end)
  if not stat then 
    LOG("Bad API call:%s",res)
    --local p = Pages.renderError(res)
    --client:send(p) 
  end
end

local htmlfuns = {}
function htmlfuns.call(out,id,fun,...)
  local args = "" 
  for i,v in  ipairs ({...})  do args = args.. '&arg'..tostring(i)..'='..urlencode(tostring(v)) end 
  out("http://%s:%s/api/callAction?deviceID=%s&name=%s?%s",IPAddress,port,id,fun,args)
end
function htmlfuns.home(out)
  out('<a href="http://%s:%s/web/main">Main</a>',IPAddress,port)
end
function htmlfuns.milliStr(t) return os.date("%H:%M:%S",math.floor(t))..string.format(":%03d",math.floor((t%1)*1000+0.5)) end

local startTag,endTag = "{{{","(.*)}}}(.*)"
local function compilePage(html,fname)
  local res,start,err={},1
  while true do
    local i,j = string.find(html, startTag, start)   
    if i == nil then if start < #html then res[#res+1]=html:sub(start) end break end
    if start < i then res[#res+1]=html:sub(start,i-1) end
    start = j+1
  end
  local res2,source={},{}
  for i=1,#res do
    local code,rest,src = res[i]:match(endTag)
    if code then 
      src,code = code,fmt("return function(EM,FB,opts,out,html) %s end",code)
      src = src:gsub("<","&lt;")
      code,err = load(code)
      if err then return 
        function() 
          return fmt("Error: Page %s - %s<br><code>%s</code>",fname,err,src)
        end
      end
      code,err = code()
      res2[#res2+1]=function(EM,FB,opts)
        local r = {}
        local function out(fm,...) r[#r+1] =  #({...})==0 and fm or fmt(fm,...) end
        code(EM,FB,opts,out,htmlfuns)
        return table.concat(r)
      end
      source[#res2]=src
      if rest~="" then res2[#res2+1]=function() return rest end end
    else 
      local c = res[i] 
      res2[#res2+1]=function() return c end
    end
  end
  return function(EM,FB,opts)
    local res,i = {},1
    local stat,err = pcall(function()
        while i<#res2 do res[#res+1] = res2[i](EM,FB,opts) i=i+1 end
      end)
    return stat and table.concat(res) or fmt("Error: Page %s - %s</br><pre>%s</pre>",fname,err,source[i])
  end
end

local pageCache = {}
local function getPage(fname)
  local fa = lfs.attributes(fname)
  if not fa then return end
  if (pageCache[fname] or {}).modified == fa.modification then
    return pageCache[fname].page
  end
  local f = io.open(fname)
  if not f then return end
  local content = f:read("*all")
  f:close()
  local page = compilePage(content,fname)
  local c = { page = page, modified = fa.modification }
  pageCache[fname]=c
  return c.page
end

local function parseOptions(str)
  local res = {}
  str:gsub("([^&]-)=([^&]+)",function(k,v) res[k]=v end)
  return res
end

local function renderPage(path,dir,client,ref)
  local opts,p,o = {},path:match("(.-)%?(.*)")
  if p then path,opts = p,parseOptions(o) end
  if path:sub(1,1)=="/" then path = path:sub(2) end
  if path=="" or path=="/" then path="main.html" end
  if not path:match("%.html?") then path=path..".html" end
  local fname = dir..path
  local page = getPage(fname)
  if page then
    page = page(EM,FB,opts)
    client:send(
[[HTTP/1.1 200 OK
Access-Control-Allow-Origin: *
Access-Control-Allow-Headers: Origin
Content-Type: text/html

<!DOCTYPE html>
]])
    client:send(page)
    return true
  end
end

local function addPath(path,dir)
  GUI_HANDLERS["GET"][path.."(.*)"] = 
  function(client,ref,body,path)
    return renderPage(path,dir,client,ref)
  end
end

EM.EMEvents(function(e) 
    if e.type == 'start' then 
      createServer(name,port,{ ['GET'] = GUIhandler,['POST'] = GUIhandler, ['PUT'] = GUIhandler,})
      addPath("/web",ARGS.web or EM.modPath.."web/")
    end
  end)

EM.createWebServer,EM.IPAddress = createServer,IPAddress