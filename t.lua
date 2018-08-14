ltn12 = require("ltn12")
json = require("json")

function printf(...) print(string.format(...)) end
local t = {}
for i=1,200 do t[#t+1]=tostring("VAR"..i) end


function f1(name)
  for i,v in ipairs(t) do if v==name then return true end end
  return false
end

function f2(name)
  return string.find(json.encode(t),"\""..name.."\"")
end

tab = json.encode(t)
function f3(name)
  return string.find(tab,"\""..name.."\"")
end

function time(f,v,n)
  local t0 = os.time()
  for i=1,n do f(v) end
  return v,(os.time()-t0)/n
end

n=10000
evar = "VAR50"
nvar = "VAR51"
printf("f1(%s) => %s ms",time(f1,evar,n))
printf("f1(%s) => %s ms",time(f1,nvar,n))
printf("f2(%s) => %s ms",time(f2,evar,n))
printf("f2(%s) => %s ms",time(f2,nvar,n))
printf("f3(%s) => %s ms",time(f3,evar,n))
printf("f3(%s) => %s ms",time(f3,nvar,n))
