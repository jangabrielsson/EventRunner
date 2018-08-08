hc2_user           = "jan@gabrielsson.com" -- HC2 credentials, used for api.x/FibaroSceneAPI calls
hc2_pwd            = "Dani0961" 
hc2_ip             = "192.168.1.69" -- IP of HC2
mime = require('mime')
https = require ("ssl.https")
ltn12 = require("ltn12")
json = require("json")
socket = require("socket")
http = require("socket.http")
_format = string.format
net = {} -- An emulation of Fibaro's net.HTTPClient
-- It is synchronous, but synchronous is a speciell case of asynchronous.. :-)
function net.HTTPClient() return _HTTP end
_HTTP = {}
-- Not sure I got all the options right..
function _HTTP:request(url,options)
  local resp = {}
  local req = options.options
  req.url = url
  req.headers = req.headers or {}
  req.sink = ltn12.sink.table(resp)
  if req.data then
    req.headers["Content-Length"] = #req.data
    req.source = ltn12.source.string(req.data)
  end
  local response, status, headers
  if url:lower():match("^https") then
    response, status, headers = https.request(req)
  else 
    response, status, headers = http.request(req)
  end
  if response == 1 then 
    options.success({status=status, headers=headers, data=table.concat(resp)})
  else
    options.error(status)
  end
end

api={} -- Emulation of api.get/put/post
local function apiCall(method,call,data,cType)
  local resp = {}
  local req={ method=method,
    url = "http://"..hc2_ip.."/api"..call,sink = ltn12.sink.table(resp),
    user=hc2_user,
    password=hc2_pwd,
    headers={}
  }
  if data then
    req.headers["Content-Type"] = cType
    req.headers["Content-Length"] = #data
    req.source = ltn12.source.string(data)
  end
  local r, c = http.request(req)
  if not r then
    print(_format("Error connnecting to HC2: '%s' - URL: '%s'.",c,req.url))
    os.exit(1)
  end
  if c>=200 and c<300 then
    return resp[1] and json.decode(table.concat(resp)) or nil
  end
  print(_format("HC2 returned error '%d %s' - URL: '%s'.",c,resp[1],req.url))
  os.exit(1)
end

function api.get(call) return apiCall("GET",call) end
function api.put(call, data) return apiCall("PUT",call,json.encode(data),"application/json") end
function api.post(call, data) return apiCall("POST",call,json.encode(data),"application/json") end