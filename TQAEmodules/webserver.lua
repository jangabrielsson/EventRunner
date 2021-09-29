--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Module for external web API - used for Web UI and callbacks from HC3

--]]
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

local function coprocess(ms,fun,tag,...)  -- Just use timer?
  local args = {...}
  local p = coroutine.create(function() fun(table.unpack(args)) end)
  local function process()
    local _,err = coroutine.resume(p)
    local stat = coroutine.status(p) -- run every ms
    if stat~="dead" then EM.systemTimer(process,ms,tag) end 
    if stat == 'dead' and err then
      LOG(EM.LOGERR,"Webserver error %s",err)
      LOG(EM.LOGERR,"Webserver error %s",debug.traceback(p))
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
  LOG(EM.LOGALLW,"Created %s at %s:%s",name,IPAddress,port)
end

local function clientAsyncHandler(client,handler)
  local headers,referer = {}
  while true do
    local l,_,_ = client:receive()
    --if _debugFlags.webServer or _debugFlags.webServerReq then Log(LOG.SYS,"WS: Request:%s",l) end
    if l then
      local body,header,e,b
      local method,call = l:match("^(%w+) (.*) HTTP/1.1")
      repeat
        header,e,b = client:receive()
        if header then
          local key,val = header:match("^(.-):%s*(.*)")
          referer = key and key:match("^[Rr]eferer") and val or referer
          if key then headers[key:lower()] = val
            --if _debugFlags.webServer then Log(LOG.SYS,"WS: Header:%s",header) end
          elseif header~="" and _debugFlags.webServer then
            --Log(LOG.SYS,"WS: Unknown request data:%s",header or "nil") 
          end
        end
        if header=="" then
          if headers['content-length'] and tonumber(headers['content-length'])>0 then
            body = client:receive(tonumber(headers['content-length']))
            --if _debugFlags.webServer then Log(LOG.SYS,"WS: Body:%s",body) end
          end
          header=nil
        end
      until header == nil or e == 'closed'
      --if _debugFlags.webServer or _debugFlags.webServerReq then Log(LOG.SYS,"WS: Request served:%s",l) end
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
    if not EM.noweb then
      if EM.copas then
        createAsyncServer(name,port,GUIhandler)
      else
        createSyncServer(name,port,GUIhandler)
      end
      addPagePath("GET/web/#rest",ARGS.web or EM.modPath.."web/")
    end
  end,true)

EM.createWebServer,EM.IPAddress,EM.PORT = createSyncServer,IPAddress,port
EM.lookupPath = lookupPath
EM.processPathMap = processPathMap
EM.addPath = addPath
EM.addPagePath = addPagePath

local htmlTab= { [' '] = "&nbsp;", ['\r'] = "</br>" }
function string.htmlEsc(str) return str:gsub("([\r%s])",function(c) return htmlTab[c] or c end) end

------
-- From Egor Skriptunoff, https://stackoverflow.com/a/41859181
local char, byte, pairs, floor = string.char, string.byte, pairs, math.floor
local table_insert, table_concat = table.insert, table.concat
local unpack = table.unpack or unpack

local function unicode_to_utf8(code)
  -- converts numeric UTF code (U+code) to UTF-8 string
  local t, h = {}, 128
  while code >= h do
    t[#t+1] = 128 + code%64
    code = floor(code/64)
    h = h > 32 and 32 or h/2
  end
  t[#t+1] = 256 - 2*h + code
  return char(unpack(t)):reverse()
end

local function utf8_to_unicode(utf8str, pos)
  -- pos = starting byte position inside input string (default 1)
  pos = pos or 1
  local code, size = utf8str:byte(pos), 1
  if code >= 0xC0 and code < 0xFE then
    local mask = 64
    code = code - 128
    repeat
      local next_byte = utf8str:byte(pos + size) or 0
      if next_byte >= 0x80 and next_byte < 0xC0 then
        code, size = (code - mask - 2) * 64 + next_byte, size + 1
      else
        code, size = utf8str:byte(pos), 1
      end
      mask = mask * 32
    until code < mask
  end
  -- returns code, number of bytes in this utf8 char
  return code, size
end

local map_1252_to_unicode = {
  [0x80] = 0x20AC,
  [0x81] = 0x81,
  [0x82] = 0x201A,
  [0x83] = 0x0192,
  [0x84] = 0x201E,
  [0x85] = 0x2026,
  [0x86] = 0x2020,
  [0x87] = 0x2021,
  [0x88] = 0x02C6,
  [0x89] = 0x2030,
  [0x8A] = 0x0160,
  [0x8B] = 0x2039,
  [0x8C] = 0x0152,
  [0x8D] = 0x8D,
  [0x8E] = 0x017D,
  [0x8F] = 0x8F,
  [0x90] = 0x90,
  [0x91] = 0x2018,
  [0x92] = 0x2019,
  [0x93] = 0x201C,
  [0x94] = 0x201D,
  [0x95] = 0x2022,
  [0x96] = 0x2013,
  [0x97] = 0x2014,
  [0x98] = 0x02DC,
  [0x99] = 0x2122,
  [0x9A] = 0x0161,
  [0x9B] = 0x203A,
  [0x9C] = 0x0153,
  [0x9D] = 0x9D,
  [0x9E] = 0x017E,
  [0x9F] = 0x0178,
  [0xA0] = 0x00A0,
  [0xA1] = 0x00A1,
  [0xA2] = 0x00A2,
  [0xA3] = 0x00A3,
  [0xA4] = 0x00A4,
  [0xA5] = 0x00A5,
  [0xA6] = 0x00A6,
  [0xA7] = 0x00A7,
  [0xA8] = 0x00A8,
  [0xA9] = 0x00A9,
  [0xAA] = 0x00AA,
  [0xAB] = 0x00AB,
  [0xAC] = 0x00AC,
  [0xAD] = 0x00AD,
  [0xAE] = 0x00AE,
  [0xAF] = 0x00AF,
  [0xB0] = 0x00B0,
  [0xB1] = 0x00B1,
  [0xB2] = 0x00B2,
  [0xB3] = 0x00B3,
  [0xB4] = 0x00B4,
  [0xB5] = 0x00B5,
  [0xB6] = 0x00B6,
  [0xB7] = 0x00B7,
  [0xB8] = 0x00B8,
  [0xB9] = 0x00B9,
  [0xBA] = 0x00BA,
  [0xBB] = 0x00BB,
  [0xBC] = 0x00BC,
  [0xBD] = 0x00BD,
  [0xBE] = 0x00BE,
  [0xBF] = 0x00BF,
  [0xC0] = 0x00C0,
  [0xC1] = 0x00C1,
  [0xC2] = 0x00C2,
  [0xC3] = 0x00C3,
  [0xC4] = 0x00C4,
  [0xC5] = 0x00C5,
  [0xC6] = 0x00C6,
  [0xC7] = 0x00C7,
  [0xC8] = 0x00C8,
  [0xC9] = 0x00C9,
  [0xCA] = 0x00CA,
  [0xCB] = 0x00CB,
  [0xCC] = 0x00CC,
  [0xCD] = 0x00CD,
  [0xCE] = 0x00CE,
  [0xCF] = 0x00CF,
  [0xD0] = 0x00D0,
  [0xD1] = 0x00D1,
  [0xD2] = 0x00D2,
  [0xD3] = 0x00D3,
  [0xD4] = 0x00D4,
  [0xD5] = 0x00D5,
  [0xD6] = 0x00D6,
  [0xD7] = 0x00D7,
  [0xD8] = 0x00D8,
  [0xD9] = 0x00D9,
  [0xDA] = 0x00DA,
  [0xDB] = 0x00DB,
  [0xDC] = 0x00DC,
  [0xDD] = 0x00DD,
  [0xDE] = 0x00DE,
  [0xDF] = 0x00DF,
  [0xE0] = 0x00E0,
  [0xE1] = 0x00E1,
  [0xE2] = 0x00E2,
  [0xE3] = 0x00E3,
  [0xE4] = 0x00E4,
  [0xE5] = 0x00E5,
  [0xE6] = 0x00E6,
  [0xE7] = 0x00E7,
  [0xE8] = 0x00E8,
  [0xE9] = 0x00E9,
  [0xEA] = 0x00EA,
  [0xEB] = 0x00EB,
  [0xEC] = 0x00EC,
  [0xED] = 0x00ED,
  [0xEE] = 0x00EE,
  [0xEF] = 0x00EF,
  [0xF0] = 0x00F0,
  [0xF1] = 0x00F1,
  [0xF2] = 0x00F2,
  [0xF3] = 0x00F3,
  [0xF4] = 0x00F4,
  [0xF5] = 0x00F5,
  [0xF6] = 0x00F6,
  [0xF7] = 0x00F7,
  [0xF8] = 0x00F8,
  [0xF9] = 0x00F9,
  [0xFA] = 0x00FA,
  [0xFB] = 0x00FB,
  [0xFC] = 0x00FC,
  [0xFD] = 0x00FD,
  [0xFE] = 0x00FE,
  [0xFF] = 0x00FF,
}
local map_unicode_to_1252 = {}
for code1252, code in pairs(map_1252_to_unicode) do
  map_unicode_to_1252[code] = code1252
end

function string.fromutf8(utf8str)
  local pos, result_1252 = 1, {}
  while pos <= #utf8str do
    local code, size = utf8_to_unicode(utf8str, pos)
    pos = pos + size
    code = code < 128 and code or map_unicode_to_1252[code] or ('?'):byte()
    table_insert(result_1252, char(code))
  end
  return table_concat(result_1252)
end

function string.toutf8(str1252)
  local result_utf8 = {}
  for pos = 1, #str1252 do
    local code = str1252:byte(pos)
    table_insert(result_utf8, unicode_to_utf8(map_1252_to_unicode[code] or code))
  end
  return table_concat(result_utf8)
end