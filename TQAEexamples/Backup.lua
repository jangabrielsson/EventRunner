_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  modPath = "TQAEmodules/",
  temp = "temp/",
  startTime="12/24/2024-07:00",
}

--%%name="Backup"

--Example of downloading and backuping up QuickApps on the HC3

local backupdir = "backup/"
local io = hc3_emulator.io
local function member(e1,t) for  _,e2 in ipairs(t) do if e1==e2 then return true end end end

local devices = api.get("/devices") -- Get all devices

for _,device in ipairs(devices) do
  if member("quickApp",device.interfaces or {}) then
    local fqa = api.get("/quickApp/export/"..device.id)
    local fname = "QA_"..device.id..fqa.name:gsub("[_/]","_")..".fqa"
    local f = io.open(backupdir..fname,"w+")
    if f then 
      print("Writing",fname,fqa.name,device.id)
      f:write((json.encode(fqa)))
      f:close()
    else
      fibaro.error(__TAG,"Can't open "..backupdir..fname)
    end
  end
end
