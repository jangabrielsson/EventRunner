--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Proxy support - responsible for creating a proxy of the emulated QA on the HC3

--]]
local EM,FB=...

local LOG,json,api = EM.LOG,FB.json,FB.api
local createQuickApp, updateHC3QAFiles
local format = string.format
local function copy(t) local r ={}; for k,v in pairs(t) do r[k]=v end return r end
local function map(f,t) for _,v in ipairs(t) do f(v) end end

local function createProxy(device)
  local pdevice,id
  local name = device.name
  local typ = device.type
  local properties = copy(device.properties or {})
  local quickVars = properties.quickAppVariables
  local interfaces = device.interfaces
  name = "TProxy "..name
  local d,_ = api.get("/devices?name="..FB.urlencode(name))
  if d and #d>0 then
    table.sort(d,function(a,b) return a.id >= b.id end)
    pdevice = d[1]
    LOG.sys("Proxy: '%s' found, ID:%s",name,pdevice.id)
    if pdevice.type ~= typ then
      LOG.sys("Proxy: Type changed from '%s' to %s",typ,pdevice.type)
      api.delete("/devices/"..pdevice.id)
    else id = pdevice.id end
  end
  local code = {}
  code[#code+1] = [[
  local function urlencode (str)
  return str and string.gsub(str ,"([^% w])",function(c) return string.format("%%% 02X",string.byte(c))  end)
end
local function POST2IDE(path,payload)
    url = "http://"..IP..path
    net.HTTPClient():request(url,{options={method='POST',data=json.encode(payload)}})
end
local IGNORE={updateView=true,setVariable=true,updateProperty=true,APIPOST=true,APIPUT=true,APIGET=true} -- Rewrite!!!!
function QuickApp:actionHandler(action)
      if IGNORE[action.actionName] then
        return self:callAction(action.actionName, table.unpack(action.args))
      end
      POST2IDE("/TQAE/action/"..self.id,action)
end
function QuickApp:UIHandler(UIEvent) POST2IDE("/TQAE/ui/"..self.id,UIEvent) end
function QuickApp:CREATECHILD(id) self.childDevices[id]=QuickAppChild({id=id}) end
function QuickApp:APIGET(url) api.get(url) end
function QuickApp:APIPOST(url,data) api.post(url,data) end -- to get around some access restrictions
function QuickApp:APIPUT(url,data) api.put(url,data) end
]]
  code[#code+1]= "function QuickApp:onInit()"
  code[#code+1]= " self:debug('"..name.."',' deviceId:',self.id)"
  code[#code+1]= " IP = self:getVariable('PROXYIP')"
  code[#code+1]= " function QuickApp:initChildDevices() end"
  code[#code+1]= "end"

  code = table.concat(code,"\n")

  LOG.sys(id and "Proxy: Reusing QuickApp proxy" or "Proxy: Creating new proxy")

  table.insert(quickVars,{name="PROXYIP", value = EM.IPAddress..":"..EM.PORT})
  return createQuickApp{id=id,name=name,type=typ,code=code,initialProperties=properties,initialInterfaces=interfaces}
end

local function traverse(o,f)
  if type(o) == 'table' and o[1] then
    for _,e in ipairs(o) do traverse(e,f) end
  else f(o) end
end

local ELMS = {
  button = function(d,w)
    return {name=d.name,style={weight=d.weight or w or "0.50"},text=d.text,type="button"}
  end,
  select = function(d,w)
    if d.options then map(function(e) e.type='option' end,d.options) end
    return {name=d.name,style={weight=d.weight or w or "0.50"},text=d.text,type="select", selectionType='single',
      options = d.options or {{value="1", type="option", text="option1"}, {value = "2", type="option", text="option2"}},
      values = d.values or { "option1" }
    }
  end,
  multi = function(d,w)
    if d.options then map(function(e) e.type='option' end,d.options) end
    return {name=d.name,style={weight=d.weight or w or "0.50"},text=d.text,type="select", selectionType='multi',
      options = d.options or {{value="1", type="option", text="option2"}, {value = "2", type="option", text="option3"}},
      values = d.values or { "option3" }
    }
  end,
  image = function(d,_)
    return {name=d.name,style={dynamic="1"},type="image", url=d.url}
  end,
  switch = function(d,w)
    return {name=d.name,style={weight=w or d.weight or "0.50"},type="switch", value=d.value or "true"}
  end,
  option = function(d,_)
    return {name=d.name, type="option", value=d.value or "Hupp"}
  end,
  slider = function(d,w)
    return {name=d.name,step=tostring(d.step),value=tostring(d.value),max=tostring(d.max),min=tostring(d.min),style={weight=d.weight or w or "1.2"},text=d.text,type="slider"}
  end,
  label = function(d,w)
    return {name=d.name,style={weight=d.weight or w or "1.2"},text=d.text,type="label"}
  end,
  space = function(_,w)
    return {style={weight=w or "0.50"},type="space"}
  end
}

local function mkRow(elms,weight)
  local comp = {}
  if elms[1] then
    local c = {}
    local width = format("%.2f",1/#elms)
    if width:match("%.00") then width=width:match("^(%d+)") end
    for _,e in ipairs(elms) do c[#c+1]=ELMS[e.type](e,width) end
    if #elms > 1 then comp[#comp+1]={components=c,style={weight="1.2"},type='horizontal'}
    else comp[#comp+1]=c[1] end
    comp[#comp+1]=ELMS['space']({},"0.5")
  else
    comp[#comp+1]=ELMS[elms.type](elms,"1.2")
    comp[#comp+1]=ELMS['space']({},"0.5")
  end
  return {components=comp,style={weight=weight or "1.2"},type="vertical"}
end

local function mkViewLayout(list,height)
  local items = {}
  for _,i in ipairs(list) do items[#items+1]=mkRow(i) end
--    if #items == 0 then  return nil end
  return
  { ['$jason'] = {
      body = {
        header = {
          style = {height = tostring(height or #list*50)},
          title = "quickApp_device_23"
        },
        sections = {
          items = items
        }
      },
      head = {
        title = "quickApp_device_23"
      }
    }
  }
end

local function transformUI(UI) -- { button=<text> } => {type="button", name=<text>}
  traverse(UI,
    function(e)
      if e.button then e.name,e.type=e.button,'button'
      elseif e.slider then e.name,e.type=e.slider,'slider'
      elseif e.select then e.name,e.type=e.select,'select'
      elseif e.switch then e.name,e.type=e.switch,'switch'
      elseif e.multi then e.name,e.type=e.multi,'multi'
      elseif e.option then e.name,e.type=e.option,'option'
      elseif e.image then e.name,e.type=e.image,'image'
      elseif e.label then e.name,e.type=e.label,'label'
      elseif e.space then e.weight,e.type=e.space,'space' end
    end)
  return UI
end

local function uiStruct2uiCallbacks(UI)
  local cb = {}
  traverse(UI,
    function(e)
      if e.name then
        -- {callback="foo",name="foo",eventType="onReleased"}
        local defu = e.button and "Clicked" or e.slider and "Change" or (e.switch or e.select) and "Toggle" or ""
        local deff = e.button and "onReleased" or e.slider and "onChanged" or (e.switch or e.select) and "onToggled" or ""
        local cbt = e.name..defu
        if e.onReleased then
          cbt = e.onReleased
        elseif e.onChanged then
          cbt = e.onChanged
        elseif e.onToggled then
          cbt = e.onToggled
        end
        if e.button or e.slider or e.switch or e.select then
          cb[#cb+1]={callback=cbt,eventType=deff,name=e.name}
        end
      end
    end)
  return cb
end

local function makeInitialProperties(UI,vars,height)
  local ip = {}
  vars = vars or {}
  transformUI(UI)
  ip.viewLayout = mkViewLayout(UI,height)
  ip.uiCallbacks = uiStruct2uiCallbacks(UI)
  ip.apiVersion = "1.2"
  local varList = {}
  for n,v in pairs(vars) do varList[#varList+1]={name=n,value=v} end
  ip.quickAppVariables = varList
  ip.typeTemplateInitialized=true
  return ip
end

function createQuickApp(args)
  local d = {} -- Our device
  d.name = args.name or "QuickApp"
  d.type = args.type or "com.fibaro.binarySensor"
  local files = args.code or ""
  local UI = args.UI or {}
  local variables = args.initialProperties.quickAppVariabels or {}
  local dryRun = args.dryrun or false
  d.apiVersion = "1.2"
  if not args.initialProperties then
    d.initialProperties = makeInitialProperties(UI,variables,args.height)
  else
    d.initialProperties = args.initialProperties
  end
  d.initialInterfaces =  args.initialInterfaces 
  if d.initialProperties.uiCallbacks and not d.initialProperties.uiCallbacks[1] then
    d.initialProperties.uiCallbacks = nil
  end
  d.initialProperties.apiVersion = "1.2"

  if type(files)=='string' then files = {{name='main',type='lua',isMain=true,isOpen=false,content=files}} end
  d.files  = {}

  for _,f in ipairs(files) do f.isOpen=false; d.files[#d.files+1]=f end

  if dryRun then return d end

  local what,d1,res="updated"
  if args.id and api.get("/devices/"..args.id) then
    d1,res = api.put("/devices/"..args.id,{
        properties={
          quickAppVariables = d.initialProperties.quickAppVariables,
          viewLayout= d.initialProperties.viewLayout,
          uiCallbacks = d.initialProperties.uiCallbacks,
        }
      })
    if res <= 201 then
      local _,_ = updateHC3QAFiles(files,args.id)
    end
  else
    --print(json.encode(d))
    d1,res = api.post("/quickApp/",d)
    what = "created"
  end

  if type(res)=='string' or res > 201 then
    LOG.error("Proxy: D:%s,RES:%s",json.encode(d1),json.encode(res))
    return nil
  else
    LOG.sys("Proxy: Device %s %s",d1.id or "",what)
    return d1
  end
end

function updateHC3QAFiles(newFiles,id)
  local oldFiles = api.get("/quickApp/"..id.."/files")
  local oldFilesMap = {}
  local updateFiles,createFiles = {},{}
  for _,f in ipairs(oldFiles) do oldFilesMap[f.name]=f end
  for _,f in ipairs(newFiles) do
    if oldFilesMap[f.name] then
      updateFiles[#updateFiles+1]=f
      oldFilesMap[f.name] = nil
    else createFiles[#createFiles+1]=f end
  end
  local _,res = api.put("/quickApp/"..id.."/files",updateFiles)  -- Update existing files
  if res > 201 then return nil,res end
  for _,f in ipairs(createFiles) do
    _,res = api.post("/quickApp/"..id.."/files",f)
    if res > 201 then return nil,res end
  end
  for _,f in pairs(oldFilesMap) do
    _,res = api.delete("/quickApp/"..id.."/files/"..f.name)
    if res > 201 then return nil,res end
  end
  return newFiles,200
end

EM.createProxy = createProxy