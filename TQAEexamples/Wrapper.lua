_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  logLevel=1,
  modPath = "TQAEmodules/",
  temp = "temp/",
  startTime="12/24/2024-07:00",
}

hc3_emulator.installQA{id=88,file='TQAEexamples/Pong.lua'}