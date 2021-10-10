-- Misc. patches to the Lua environment for QAs/Scenes 
do
  local oldGet = fibaro.get    -- Return emulated sunrise/sunset
  function fibaro.get(id,prop)
    if id==1 then
      if prop=='sunriseHour' then
        return hc3_emulator.EM.sunriseHour
      elseif prop=='sunsetHour' then
        return hc3_emulator.EM.sunsetHour
      end
    end 
    return oldGet(id,prop)
  end

  if hc3_emulator.EM.cfg.tableSort then -- patch table.sort with pure Lua version (ToDo gsub)
    table.sort = hc3_emulator.EM.utilities.tableSort
  end
end