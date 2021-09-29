--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Class support, mimicking LuaBind's class implementation

--]]
local setmetatable = hc3_emulator.setmetatable
local rawset = hc3_emulator.rawset
local rawget = hc3_emulator.rawget

local metas = {}
for _,m in ipairs({
    "__add","__sub","__mul","__div","__mod","__pow","__unm","__idiv","__band","__bor",
    "__bxor","__bnot","__shl","__shr","__concat","__len","__eq","__lt","__le","__call",
    "__tostring"
    }) do
  metas[m]=true
end

function property(get,set)
  assert(type(get)=='function' and type(set)=="function","Property need function set and get")
  return {['%CLASSPROP%']=true, get=get, set=set}
end

local function trapIndex(props,cmt,obj)
  function cmt.__index(_,key)
    if props[key] then return props[key].get(obj) else return rawget(obj,key) end
  end
  function cmt.__newindex(_,key,val)
    if props[key] then return props[key].set(obj,val) else return rawset(obj,key,val) end
  end
end

function class(name)    -- Version that tries to avoid __index & __newindex to make debugging easier
  local cl,mt,cmt,props,parent= {['_TYPE']='userdata'},{},{},{}  -- We still try to be Luabind class compatible
  function cl.__copyObject(clo,obj)
    for k,v in pairs(clo) do if metas[k] then cmt[k]=v else obj[k]=v end end
    return obj
  end
  function mt.__call(tab,...)        -- Instantiation  <name>(...)
    local obj = tab.__copyObject(tab,tab.__obj or {}) tab.__obj = nil
    if not tab.__init then error("Class "..name.." missing initialiser") end
    tab.__init(obj,...)
    local trapF = false
    for k,v in pairs(obj) do
      if type(v)=='table' and v['%CLASSPROP%'] then obj[k],props[k]=nil,v; trapF = true end
    end
    if trapF then trapIndex(props,cmt,obj) end
    local str = "Object "..name..":"..tostring(obj):match("%s(.*)")
    setmetatable(obj,cmt)
    if not obj.__tostring then 
      function obj:__tostring() local _=self return str end
    end
    return obj
  end
  function mt:__tostring() local _=self return "class "..name end
  setmetatable(cl,mt)
  _ENV[name] = cl
  return function(p) -- Class creation -- class <name>
    parent = p 
    if parent then parent.__copyObject(parent,cl) end
  end 
end