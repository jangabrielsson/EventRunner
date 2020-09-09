--[[
  Toolbox UI.
  
  Functions to manipulate UI

--]]

Toolbox_Module = Toolbox_Module or {}
Toolbox_Module.ui = {
  name = "UI functions",
  author = "jan@gabrielsson.com",
  version = "0.1"
}

function Toolbox_Module.ui.init(self)

  local format = string.format
  local function mapf(f,l) for _,e in ipairs(l) do f(e) end; end
  local function map(f,l) local r={}; for _,e in ipairs(l) do r[#r+1]=f(e) end; return r end
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
    image = function(d,w)
      return {name=d.name,style={dynamic="1"},type="image", url=d.url}
    end,
    switch = function(d,w)
      return {name=d.name,style={weight=w or d.weight or "0.50"},type="switch", value=d.value or "true"}
    end,
    option = function(d,w)
      return {name=d.name, type="option", value=d.value or "Hupp"}
    end,
    slider = function(d)
      return {name=d.name,max=tostring(d.max),min=tostring(d.min),style={weight=d.weight or w or "1.2"},text=d.text,type="slider"}
    end,
    label = function(d)
      return {name=d.name,style={weight=d.weight or w or "1.2"},text=d.text,type="label"}
    end,
    space = function(d,w)
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
      comp[#comp+1]={components=c,style={weight="1.2"},type='horizontal'}
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
  end

  local function uiStruct2uiCallbacks(UI)
    local cb = {}
    --- "callback": "self:button1Clicked()",
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

  function self:updateViewLayout(id,UI,height,forceUpdate) --- This may not work anymore....
    if forceUpdate==nil then forceUpdate = true end
    transformUI(UI)
    local cb = api.get("/devices/"..id).properties.uiCallbacks or {}
    local viewLayout = mkViewLayout(UI)
    local newcb = uiStruct2uiCallbacks(UI)
    if forceUpdate then 
      cb = newcb -- just replace uiCallbacks with new elements callbacks
    else
      local mapOrg = {}
      for _,c in ipairs(cb) do mapOrg[c.name]=c.callback end -- existing callbacks, map name->callback
      for _,c in ipairs(newcb) do if mapOrg[c.name] then c.callback=mapOrg[c.name] end end
      cb = newcb -- save exiting elemens callbacks
    end
    if not cb[1] then cb = nil end
    return api.put("/devices/"..id,{
        properties = {
          viewLayout = viewLayout,
          uiCallbacks = cb},
      })
  end

end