local foo = 9
local res = loadfile("GTest2.lua")()
function setLocal(name,v)
  local idx,ln,lv = 1,true
  while ln do
    ln, lv = debug.getlocal(2, idx)
    if ln == name then debug.setlocal(2,idx,v) return end
  end
end
for k,v in pairs(res) do setLocal(k,v) end
foo()