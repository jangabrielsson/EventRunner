_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  logLevel=1,
  modPath = "TQAEmodules/",
  temp = "temp/",
  refreshStates=true,
  --startTime="12/24/2024-07:00",
  logLevel=1
}

--%%name="GEA"
--%%noterminate=true
--%%u1={label="labelRunning",    text="Running"}
--%%u2={{button="buttonON", text="ON", onReleased="buttonON_onReleased"},{button="buttonOFF", text="OFF", onReleased="buttonOFF_onReleased"}}
--%%u3={label="labelVersion",    text="Version :"}
--%%u4={label="labelIntervalle", text="Intervalle :"}
--%%u5={label="labelPortables",  text="Portables :"}
--%%u6={label="labelDebug",      text="Debug :"}

--FILE:GEA/Library - tools v2.12.lua,tools;
--FILE:GEA/config.lua,config;
--FILE:GEA/GEA v7.33.lua,main;