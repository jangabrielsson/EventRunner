--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Module for external web API - used for Web UI and callbacks from HC3

--]]
local EM,FB,ARGS=...

local lfs = require("lfs")
local LOG,DEBUG,port,name = EM.LOG,EM.DEBUG,ARGS.port or 8976, ARGS.name or "WebAPI"
local socket = require("socket")
local fmt = string.format

LOG.register("webserver","Log webserver API related events")

local IPAddress
do
  local someRandomIP = "192.168.1.122" --This address you make up
  local someRandomPort = "3102" --This port you make up
  local mySocket = socket.udp() --Create a UDP socket like normal
  mySocket:setpeername(someRandomIP,someRandomPort) 
  local myDevicesIpAddress,_ = mySocket:getsockname()-- returns IP and Port
  IPAddress = myDevicesIpAddress == "0.0.0.0" and "127.0.0.1" or myDevicesIpAddress
end

local function coprocess(ms,fun,tag,...)  -- Just use timer?
  local args = {...}
  local p = coroutine.create(function() fun(table.unpack(args)) end)
  local function process()
    local _,err = coroutine.resume(p)
    local stat = coroutine.status(p) -- run every ms
    if stat~="dead" then EM.systemTimer(process,ms,tag) end 
    if stat == 'dead' and err then
      LOG.error("Webserver error %s",err)
      LOG.error("Webserver error %s",debug.traceback(p))
    end
  end
  process()
end

local function clientSyncHandler(client,handler)
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
      handler(method,client,call,body,referer)
      --client:flush()
      client:close()
      return  -- if handler then handler(method,client,call,body,headers) end
    end
    coroutine.yield()
  end
end

local function socketSyncServer(server,handler)
  while true do
    local client,err
    repeat
      client, err = server:accept()
      if err == 'timeout' then coroutine.yield() end
    until err ~= 'timeout'
    coprocess(100,clientSyncHandler,"Web:client",client,handler)
  end
end

local function createSyncServer(name,port,handler)
  local server,c,err=socket.bind("*", port)
  --print(err,c,server)
  local i, p = server:getsockname()
  assert(i, p)
  --printf("http://%s:%s/test",ipAdress,port)
  server:settimeout(0,'b')
  server:setoption('keepalive',true)
  coprocess(250,socketSyncServer,"Web:server",server,handler)
  LOG.sys("Created %s at http://%s:%s/web",name,IPAddress,port)
end

local function clientAsyncHandler(client,handler)
  local headers,referer = {}
  while true do
    local l,_,_ = client:receive()
    DEBUG("webserver","trace","WS: Request:%s",l)
    if l then
      local body,header,e,b
      local method,call = l:match("^(%w+) (.*) HTTP/1.1")
      repeat
        header,e,b = client:receive()
        if header then
          local key,val = header:match("^(.-):%s*(.*)")
          referer = key and key:match("^[Rr]eferer") and val or referer
          if key then headers[key:lower()] = val
            DEBUG("webserver","trace","WS: Header:%s",header)
          elseif header~="" then
            DEBUG("webserver","trace","WS: Unknown request data:%s",header or "nil") 
          end
        end
        if header=="" then
          if headers['content-length'] and tonumber(headers['content-length'])>0 then
            body = client:receive(tonumber(headers['content-length']))
            DEBUG("webserver","trace","WS: Body:%s",body) 
          end
          header=nil
        end
      until header == nil or e == 'closed'
      DEBUG("webserver","trace","WS: Request served:%s",l)
      if call:match("/REDIRECTHC3/") then
        --redirect(method,client,call,body,headers)
      end
      if handler then handler(method,client,call,body,referer,headers) end
      client:close()
      return
    end
  end
end

local function createAsyncServer(name,port,handler)
  local server,msg = socket.bind("*", port)
  assert(server,(msg or "").." ,port "..port)
  local i, msg2 = server:getsockname()
  assert(i, msg2)
  EM.copas.addserver(server,
    function(sock)
      clientAsyncHandler(EM.copas.wrap(sock),handler)
    end)
  LOG.sys("Created %s at http://%s:%s/web",name,IPAddress,port)
end

local GUI_MAP = { GET={}, PUT={}, POST={}, DELETE={}}
local function GUIhandler(method,client,call,body,ref)
  local fun,args,opts,path = EM.lookupPath(method,call,GUI_MAP)
  if type(fun)=='function' then
    local stat,res = pcall(fun,path,client,ref,body,opts,table.unpack(args))
    if not stat then
      LOG.error("Bad API call:%s",res)
    end
  elseif fun==nil then
    client:send("HTTP/1.1 501 Not Implemented\nLocation: "..(ref or call).."\n")
  else 
    LOG.error("Bad API call:%s",fun)
  end
end

local htmlfuns = {}
function htmlfuns.call(out,id,fun,...)
  local args = "" 
  for i,v in  ipairs ({...})  do args = args.. '&arg'..tostring(i)..'='..FB.urlencode(tostring(v)) end 
  out("http://%s:%s/api/callAction?deviceID=%s&name=%s?%s",IPAddress,port,id,fun,args)
end
function htmlfuns.home(out)
  out('<a href="http://%s:%s/web/main">Main</a>',IPAddress,port)
end
htmlfuns.milliStr = EM.milliStr

local escTab = { ['<'] = "&lt;", ['"'] = "&quot;" }
function htmlfuns.escape(str) return str:gsub('[\"<]',function(s) return escTab[s] end) end

function htmlfuns.navbar(out,item)
  out(string.gsub([[  <div class="container">
    <header class="d-flex flex-wrap justify-content-center py-3 mb-4 border-bottom">
      <a href="/web/main" class="d-flex align-items-center mb-3 mb-md-0 me-md-auto text-dark text-decoration-none">
        <span class="fs-4">TQAE</span>
      </a>

      <ul class="nav nav-pills">
        <li class="nav-item"><a href="/web/main" class="nav-link" aria-current="page">QA/Scene</a></li>
        <li class="nav-item"><a href="/web/timers" class="nav-link">Timers</a></li>        
        <li class="nav-item"><a href="/web/globals" class="nav-link">Globals</a></li>
        <li class="nav-item"><a href="/web/triggers" class="nav-link">Triggers & Events</a></li>
        <li class="nav-item"><a href="/web/settings" class="nav-link">Settings</a></li>
        <li class="nav-item dropdown">
          <a class="nav-link dropdown-toggle" href="#" id="navbarDropdown" role="button" data-bs-toggle="dropdown" aria-expanded="false">
            HC3
          </a>
          <ul class="dropdown-menu" aria-labelledby="navbarDropdown">
            <li><a class="dropdown-item" href="/web/types">Device types</a></li>
            <li><a class="dropdown-item" href="/web/quickApps">QuickApps</a></li>
          </ul>
         </li>
        <li class="nav-item"><a href="/web/docs" class="nav-link">Docs</a></li>
        <li class="nav-item"><a href="/web/about" class="nav-link">About</a></li>
      </ul>
    </header>
  </div>
]],item..[[" class="nav%-link"]],item..[[" class="nav-link active"]]))
end

function htmlfuns.footer(out)
  out([[<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.2/dist/js/bootstrap.bundle.min.js" integrity="sha384-kQtW33rZJAHjgefvhyyzcGF3C5TFyBQBA13V1RKPf4uH+bwyzQxZ6CmMZHmNBEfJ" crossorigin="anonymous"></script>
]])
end

function htmlfuns.header(out)
  out([[<head lang="en">
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <!-- Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.2/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-uWxY/CJNBR+1zjPWmfnSnVxwRheevXITnMqoEIeG1LJrdI0GlVs/9cVSyPYXdcSF" crossorigin="anonymous">
</head>
]])
end

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
          return fmt("Error: Page %s - %s<br><code>%s</code>",fname,err,string.htmlEsc(src))
        end
      end
      code,err = code()
      res2[#res2+1]=function(em,fb,opts)
        local r = {}
        local function out(fm,...) r[#r+1] =  #({...})==0 and fm or fmt(fm,...) end
        code(em,fb,opts,out,htmlfuns)
        return table.concat(r)
      end
      source[#res2]=src
      if rest~="" then res2[#res2+1]=function() return rest end end
    else 
      local c = res[i] 
      res2[#res2+1]=function() return c end
    end
  end
  return function(em,fb,opts)
    local res,i = {},1
    local stat,err = pcall(function()
        while i<=#res2 do res[#res+1] = res2[i](em,fb,opts) i=i+1 end
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

local function renderPage(path,dir,client,opts,ref)
  if path:sub(1,1)=="/" then path = path:sub(2) end
  if path=="" or path=="/" then path="main.html" end
  if not path:match("%.%w+$") then path=path..".html" end
  local fname = dir..path
  local page = getPage(fname)
  if page then
    page = page(EM,FB,opts)
    client:send(
[[HTTP/1.1 200 OK
Access-Control-Allow-Origin: *
Access-Control-Allow-Headers: Origin
Content-Type: text/html

]])
    client:send(page)
    return true
  end
end

local function addPagePath(path,dir)
  local wpath = path:match("GET(/.*)")
  wpath = (#wpath:match("(.-)/#rest") or #wpath)+1
  EM.addPath(path,
    function(path,client,ref,body,opts)
      return renderPage(path:sub(wpath),dir,client,opts,ref)
    end,
    GUI_MAP)
end

local var = {["#id"]=true,["#name"]=true}
local function addPath(p,f,map)
  local t,sp0,t0 = map or GUI_MAP
  for _,sp in ipairs(p:split("/")) do
    if t[sp]==nil or var[sp] then t[sp] = t[sp] or {} end 
    sp0,t0,t=sp,t,t[sp]
  end
  if sp0=="#rest" then t0["#rest"]=f else t["#fun"]=f end
end

local function processPathMap(pmap,map)
  for p,f in pairs(pmap) do addPath(p,f,map or GUI_MAP) end
end

local function lookup(method,path,map)
  local t,args = map[method],{}
  local opts,pa,op = {},path:match("(.*)%?(.*)")
  if pa then
    path = pa
    op:gsub("([^&]-)=([^&]+)",function(k,v) opts[k]=tonumber(v) or (v=='true' and true) or (v=='false' and false) or FB.urldecode(v) end)
  end
  for _,p in ipairs(path:split("/")) do
    if t[p] then t=t[p]
    elseif tonumber(p) then t=t["#id"] args[#args+1]=tonumber(p)
    elseif t["#name"] then t=t["#name"] args[#args+1]=p
    elseif not t["#rest"] then
      return nil
      --error("Bad path: "..path)
    end
  end
  return t["#fun"] or t["#rest"],args,opts,path
end
local function lookupPath(method,path,map) 
  local stat,f,a,o,p = pcall(lookup,method,path,map) 
  if stat then return f,a,o,p else return f end 
end

EM.EMEvents('start',function(e)
    if not EM.cfg.noweb then
      if EM.cfg.copas then
        createAsyncServer(name,port,GUIhandler)
      else
        createSyncServer(name,port,GUIhandler)
      end
      addPagePath("GET/web/#rest",ARGS.web or EM.cfg.modPath.."web/")
    end
  end,true)

local htmlTab= { [' '] = "&nbsp;", ['\r'] = "</br>" }
function string.htmlEsc(str) return str:gsub("([\r%s])",function(c) return htmlTab[c] or c end) end

EM.createWebServer,EM.IPAddress,EM.PORT = createSyncServer,IPAddress,port
EM.lookupPath = lookupPath
EM.processPathMap = processPathMap
EM.addPath = addPath
EM.addPagePath = addPagePath
