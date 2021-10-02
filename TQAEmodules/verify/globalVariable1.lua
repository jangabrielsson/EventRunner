--%%name="GlobalVariable1"

hc3_emulator.EM.debugFlags.refreshStates=true

api.get("/devices/3")

local function printf(...) print(string.format(...)) end

local testVar = "GGGG89898"

printf("Creating globalVariable %s on HC3 with value 'X'",testVar)
local v = api.post("/globalVariables",{name=testVar,value="X"})

printf("Accessing variable on HC3")
printf("%s=%s",testVar,fibaro.getGlobalVariable(testVar))

printf("Creating shadowing globalVariable %s locally with value 'Y'",testVar)
hc3_emulator.create.globalVariable{name=testVar,value="Y"}

printf("Accessing local variable")
printf("Local %s=%s",testVar,fibaro.getGlobalVariable(testVar))

printf("Changing local variable to 'Z'")
fibaro.setGlobalVariable(testVar,"Z")

printf("Accessing local variable")
printf("Local %s=%s",testVar,fibaro.getGlobalVariable(testVar))

printf("Deleting local variable")
api.delete("/globalVariables/"..testVar)

printf("Accessing variable on HC3 again")
printf("%s=%s",testVar,fibaro.getGlobalVariable(testVar))

printf("Deleting variable on HC3")
api.delete("/globalVariables/"..testVar)

os.exit()