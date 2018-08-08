function day(times)
  local pos = 1
  return function ()      -- iterator function
    local t = times[pos]
    pos = (pos % #times)+1
    return t
  end
end

for time in day({"10:00","12:00"}) do
  print(time)
end