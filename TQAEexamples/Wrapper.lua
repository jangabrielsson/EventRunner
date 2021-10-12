_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  modPath = "TQAEmodules/",
  temp = "temp/",
  startTime="12/24/2024-07:00",
}

--%%name="Wrapper"

--Example of loading and running another QA
hc3_emulator.installQA{id=88,file='TQAEexamples/Pong.lua'}