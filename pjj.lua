if dofile then
  dofile("fibaroapiHC3.lua")
  local cr = loadfile("credentials.lua"); if cr then cr() end
end

A = "{\n\"name\": \"Crash notifier\",\n\"type\":\"com.fibaro.binarySensor\",\n\"variables\":{\n   \"pushID\":\"0\"\n   },\n\"UI\":[\n  {\"button\":\"enable\",\"text\":\"Push error -enabled\"},\n  {\"label\":\"label1\",\"text\":\"\"},\n  {\"label\":\"label2\",\"text\":\"\"},\n  {\"label\":\"label3\",\"text\":\"\"}\n  ]\n}"

B = "{\n\"name\": \"Profile scheduler\",\n\"type\":\"com.fibaro.binarySensor\",\n\"variables\":{},\n\"UI\":[\n  [{\"button\":\"time\",\"text\":\"07:00\"},{\"button\":\"profile\",\"text\":\"Home\"}],\n  [{\"button\":\"hour1\",\"text\":\"0\"},{\"button\":\"hour2\",\"text\":\"7\"},{\"button\":\"min1\",\"text\":\"0\"},{\"button\":\"min2\",\"text\":\"0\"}],\n  [{\"button\":\"save\",\"text\":\"Save\"},{\"button\":\"enabled\",\"text\":\"Enabled\"}]  \n  ]\n}"

A = json.decode(A)
B = json.decode(B)