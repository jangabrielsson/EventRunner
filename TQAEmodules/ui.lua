--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Creating UI elements for emulated QA (Web UI) and HC3 procy

--]]
local EM,FB = ...

local json,DEBUG,Devices = FB.json,EM.DEBUG,EM.Devices
local format = string.format
local traverse = EM.utilities.traverse

local function map(f,l) for _,v in ipairs(l) do f(v) end end

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
      if e.button then e.name,e.type,e.onReleased=e.button,'button',e.onReleased or e.f; e.f=nil
      elseif e.slider then e.name,e.type,e.onChanged=e.slider,'slider',e.onChanged or e.f; e.f=nil
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

local customUI = {}
customUI['com.fibaro.binarySwitch'] = 
{{{button='__turnon', text="Turn On",onReleased="turnOn"},{button='__turnoff', text="Turn Off",onReleased="turnOff"}}}
customUI['com.fibaro.multilevelSwitch'] = 
{{{button='__turnon', text="Turn On",onReleased="turnOn"},{button='__turnoff', text="Turn Off",onReleased="turnOff"}},
  {{slider='__value', min=0, max=99, onChanged='setValue'}},
  {
    {button='__sli', text="&#8679;",onReleased="startLevelIncrease"},
    {button='__sld', text="&#8681;",onReleased="startLevelIncrease"},
    {button='__sls', text="&Vert;",onReleased="stopLevelChange"},
  }
}
customUI['com.fibaro.binarySensor']     = customUI['com.fibaro.binarySwitch']      -- For debugging
customUI['com.fibaro.multilevelSensor'] = customUI['com.fibaro.multilevelSwitch']  -- For debugging

local initElm = {
  ['button'] = function(e,qa) qa:updateView(e.button,'text',e.text) end,
  ['slider'] = function(e,qa) qa:updateView(e.slider,'value',e.value or 0) end,
  ['label'] = function(e,qa)  qa:updateView(e.label,'text',e.text) end,
}

function EM.addUI(info)
  local UI,dev = info.UI,info.dev
  if info.UI and next(info.UI)~= nil then
    transformUI(UI)
    dev.properties.viewLayout = mkViewLayout(UI)
    dev.properties.uiCallbacks = uiStruct2uiCallbacks(UI)
  elseif (not dev.viewLayout) and (customUI[dev.type] or customUI[dev.baseType or ""]) then
    info.UI = customUI[dev.type] or customUI[dev.baseType]
    UI = info.UI
    transformUI(UI)
    dev.properties.viewLayout = mkViewLayout(UI)
    dev.properties.uiCallbacks = uiStruct2uiCallbacks(UI)
  elseif not dev.properties.viewLayout then
    info.UI = {}
    dev.properties.viewLayout= json.decode(
[[{"$jason":{"body":{"header":{"style":{"height":"0"},"title":"quickApp_device_403"},"sections":{"items":[]}},"head":{"title":"quickApp_device_403"}}}]]
    )
    dev.properties.uiCallbacks = {}
  end
end

EM.EMEvents('QACreated',function(ev) -- Intercept QA created and add viewLayout and uiCallbacks
    local qa,dev = ev.qa,ev.dev
    local info = Devices[qa.id]
    DEBUG("ui","sys","ui.lua inspecting QA:%s",qa.name)
    if info == nil and dev.parentId and dev.parentId > 0 then
      info = {dev = dev, env = Devices[dev.parentId].env }
      EM.addUI(info)
      EM.installDevice(info)
    end
    for _,r in ipairs(info.UI) do
      r = r[1] and r or {r}
      for _,c in ipairs(r) do
        if initElm[c.type] then initElm[c.type](c,qa) end
      end
    end
    --end,0)
  end,true)

EM.UI = {}
EM.UI.uiStruct2uiCallbacks = uiStruct2uiCallbacks
EM.UI.mkViewLayout = mkViewLayout
