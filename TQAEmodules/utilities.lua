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

local function partition(arr, p, r, fun)
  local x,i = arr[r],p-1
  for j = p, r - 1 do
    if fun(arr[j],x) then
      i = i + 1
      arr[j],arr[i]=arr[i],arr[j]
    end
  end
  arr[i+1],arr[r]=arr[r],arr[i + 1]
  return i + 1
end

local function quickSort(arr, p, r, fun)
  p,r = p or 1,r or #arr
  if p < r then
    q = partition(arr, p, r, fun)
    quickSort(arr, p, q - 1, fun)
    quickSort(arr, q + 1, r, fun)
  end
end

local function tableSort(array,fun)
  fun = fun or function(a,b) return a <= b end
  return quickSort(array, 1, #array, fun)
end

----------------------------------------------------------------------
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

---------------------------------------------

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