local EM,FB,ARGS=...

local lfs = require("lfs")
local LOG,port,name = EM.LOG, ARGS.port or 8976, ARGS.name or "WebAPI"
local socket = require("socket")
local fmt = string.format

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
      LOG(EM.LOGERR,"Webserver error %s",err)
      LOG(EM.LOGERR,"Webserver error %s",debug.traceback(p))
    end
  end
  process()
end

local function clientHandler(client,handler)
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
      return
    end
    coroutine.yield()
  end
end

local function socketServer(server,handler)
  while true do
    local client,err
    repeat
      client, err = server:accept()
      if err == 'timeout' then coroutine.yield() end
    until err ~= 'timeout'
    coprocess(10,clientHandler,"Web:client",client,handler)
  end
end

local function createServer(name,port,handler)
  local server,c,err=socket.bind("*", port)
  --print(err,c,server)
  local i, p = server:getsockname()
  assert(i, p)
  --printf("http://%s:%s/test",ipAdress,port)
  server:settimeout(0,'b')
  server:setoption('keepalive',true)
  coprocess(10,socketServer,"Web:server",server,handler)
  LOG(EM.LOGALLW,"Created %s at %s:%s",name,IPAddress,port)
end

local GUI_MAP = { GET={}, PUT={}, POST={}, DELETE={}}
local function GUIhandler(method,client,call,body,ref)
  local fun,args,opts,path = EM.lookupPath(method,call,GUI_MAP)
  if type(fun)=='function' then
    local stat,res = pcall(fun,path,client,ref,body,opts,table.unpack(args))
    if not stat then
      LOG(EM.LOGERR,"Bad API call:%s",res)
    end
  elseif fun==nil then
    client:send("HTTP/1.1 501 Not Implemented\nLocation: "..(ref or call).."\n")
  else 
    LOG(EM.LOGERR,"Bad API call:%s",fun)
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
        while i<#res2 do res[#res+1] = res2[i](em,fb,opts) i=i+1 end
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
  local t,sp0,t0 = map
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
local function lookupPath(method,path,map) local stat,f,a,o,p = pcall(lookup,method,path,map) if stat then return f,a,o,p else return f end end

EM.EMEvents('start',function(e) 
    createServer(name,port,GUIhandler)
    addPagePath("GET/web/#rest",ARGS.web or EM.modPath.."web/")
  end,true)

EM.createWebServer,EM.IPAddress,EM.PORT = createServer,IPAddress,port
EM.lookupPath = lookupPath
EM.processPathMap = processPathMap
EM.addPath = addPath
EM.addPagePath = addPagePath