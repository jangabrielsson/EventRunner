local EM,FB=...

local testFiles = {
  "test1.lua",
  "test2.lua",
  "sleep1.lua",
  "http1.lua",
  "api1.lua",
  "coro1.lua", -- not completly happy with the order of times...
  "restart1.lua",
  "err1.lua"
}

local function test(n)
  if n <= #testFiles then
    EM.installQA({file=EM.modPath.."verify/"..testFiles[n]},
      function() test(n+1) end)
  else os.exit() end
end

EM.startEmulator(function() test(1) end)
