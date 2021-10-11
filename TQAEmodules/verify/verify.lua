local EM,FB=...

local testFiles = {
  "test1.lua",
  "test2.lua",
  "sleep1.lua",
  "sleep2.lua",
  "http1.lua",
  "api1.lua",
  "coro1.lua", -- not completly happy with the timing order...
  "restart1.lua",
  "err1.lua",
  "globalVariable1.lua",
}

local function test(n)
  if n <= #testFiles then
    EM.installQA({file=EM.cfg.modPath.."verify/"..testFiles[n]},
      function() test(n+1) end)
  else 
    os.exit() 
  end
end

EM.startEmulator(function() 
    EM.LOG.sys("Running verification tests")
    test(1) 
  end)
