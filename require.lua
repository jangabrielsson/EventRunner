dofile("apitest.lua")

__fibaroSceneId = 319
_ENV = _G or {}

function foo(a,b) return a*b end 
function pr(a,...) local s = string.format(a,...); print(s) return s end 
function add(a,b) return a+b end
function set(a,b) ENV[a]=b; return b end
fibaro = {}
function fibaro:test(a) return a+10 end

local s = "('fibaro:test',8)"
local s = "('string.format','\\value=%s',6)"

function map(f,l,s) local r={}; for i=s,#l do r[#r+1]=f(l[i]) end return r end

function transform(e)
  if type(e)=='table' then
    loca n = 1
    if e[1]=='%CALL' then
      local tab,d,fun = e[2]:match("^(%w+)[%.:]?(%w*)")
      if d then 
      else n = 3 end
    end
    map(transform,e,n)
  else return e
  end
end

function compile(str)
  repeat
    local s1 = s
    s = s:gsub("%b()",function(m) return #m < 3 and m or string.format("['%%CALL',%s]",m:sub(2,-2)) end)
  until s1 == s
  return transform(json.decode(s))
end

function eval(e)
  if type(e) == 'table' and e[1]=='%CALL' then
    local obj,fun = e[2]:match("^(%w+):?(%w*)")
    return fun=="" and _ENV[obj](table.unpack(map(eval,e,3))) or -- fun(...)
    _ENV[obj][fun](_ENV[obj],table.unpack(map(eval,e,3)))        -- obj:fun(...)
  else
    return type(e) == 'string' and (e:sub(1,1)=='\\' and e or _ENV[e]) or e                  -- constants
  end
end

print(eval(compile(s)))
