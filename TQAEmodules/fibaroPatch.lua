
do
  local oldGet = fibaro.get
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
end