--[[
--]]

-- Librarys functions
function test1(a,b) return a+b end

-------------------------------- Library framework --------------------------------------------------------
if fibaro:getSourceTrigger().type=='other' then
  function urldecode(str) return str:gsub('%%(%x%x)',function (x) return string.char(tonumber(x,16)) end) end
  local function encodeRemoteEvent(e) return {urlencode(json.encode(e)),'%%ER%%'} end
  local function decodeRemoteEvent(e) return (json.decode((urldecode(e[1])))) end
  local function postRemote(sceneID, e) -- Post event to other scenes
    e._from = _EMULATED and -__fibaroSceneId or __fibaroSceneId
    local payload = encodeRemoteEvent(e)
    if not _EMULATED then    -- On HC2
      if sceneID < 0 then    -- call emulator 
        if not _emulator.adress then return end
        local HTTP = net.HTTPClient()
        HTTP:request(_emulator.adress.."trigger/"..sceneID,{options = {
              headers = {['Accept']='application/json',['Content-Type']='application/json'},
              data = json.encode(payload), timeout=2000, method = 'POST'},
            error = function(status) if status~="End of file" then Log(LOG.ERROR,"Emulator error:%s, (%s)",status,tojson(e)) end end,
            success = function(status) end,
          })
      else fibaro:startScene(sceneID,payload) end -- call other scene on HC2
    else fibaro:startScene(math.abs(sceneID),payload) end -- on emulator
  end
  local args = fibaro:args()
  if args then
    local e = decodeRemoteEvent(args)
    if e.type=='%%REMOTECALL%%' then
      local status, res = pcall(function() return {_ENV[e.fun](table.unpack(e.args))} end)
      if status then postRemote(e._from,{type='%%REMOTERESP%%',value=res,tag=e.tag})
      else postRemote(e._from,{type='%%REMOTERESP%%',name=e.fun,error=res,tag=e.tag}) end
    end
  end
end


