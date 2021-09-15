local utils = {}

local function copy(t) local r = {}; for k,v in pairs(t) do r[k]=v end return r end

local function equal(e1,e2)
  if e1==e2 then return true
  else
    if type(e1) ~= 'table' or type(e2) ~= 'table' then return false
    else
      for k1,v1 in pairs(e1) do if e2[k1] == nil or not equal(v1,e2[k1]) then return false end end
      for k2,_  in pairs(e2) do if e1[k2] == nil then return false end end
      return true
    end
  end
end

local function member(e1,t) for _,e2 in ipairs(t) do if e1==e2 then return true end end end
local function merge(dest,src) for k,v in pairs(src) do dest[k]=v end end

local function reduce(f,list)
  local r = {}
  for _,e in ipairs(list) do local v = f(e) if v~=nil then r[#r+1]=v end end 
  return r
end

local function traverse(o,f)
  if type(o) == 'table' and o[1] then
    for _,e in ipairs(o) do traverse(e,f) end
  else f(o) end
end

local ZBCOLORMAP = {
  black="\027[30m",brown="\027[31m",green="\027[32m",orange="\027[33m",
  navy="\027[34m",purple="\027[35m",teal="\027[36m",grey="\027[37m",
  red="\027[31;1m",tomato="\027[31;1m",neon="\027[32;1m",yellow="\027[33;1m",
  blue="\027[34;1m",magenta="\027[35;1m",cyan="\027[36;1m",white="\027[37;1m",
  darkgrey="\027[30;1m",
}

local function html2color(str,startColor)
  local st,p = {startColor or '\027[0m'},1
  return str:gsub("(</?font.->)",function(s)
      if s=="</font>" then
        p=p-1; return st[p]
      else
        local color = s:match("color=(%w+)")
        color=ZBCOLORMAP[color] or ZBCOLORMAP['black']
        p=p+1; st[p]=color
        return color
      end
    end)
end

utils.copy = copy
utils.reduce = reduce
utils.member = member
utils.merge = merge
utils.traverse = traverse
utils.equal = equal
utils.ZBCOLORMAP = ZBCOLORMAP
utils.ZBCOLOREND = '\027[0m'
utils.html2color = html2color
return utils