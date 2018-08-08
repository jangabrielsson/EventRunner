f1 =  "Regn. Svalare. Högsta 12ºC. Vindar SSÖ på 15 till 30 km/tim. Sannolikhet regn 100%. Regn omkring 6 mm."
t = {["%"] = " procent", ["/"] = " i ", ["ºC"] = " grader"}
forecast = f1:gsub("(\186?%p?C?)",{["%"] = " procent", ["/"] = " i ", ["ºC"] = " grader"})
forecast = f1:gsub("(\xC2?\xBA?%p?C?)",{["%"] = " procent", ["/"] = " i ", ["ºC"] = " grader"})
--forecast = f1:gsub("([%º%p]C?)",{["%"] = " procent", ["/"] = " i ", ["�"] = " grader"})
print(forecast)
print("-----------------")
f2 = f1:gsub("%ºC", " grader")
forecast_2steps = f2:gsub("%p", {["%"] = " procent", ["/"] = " i ", ["ºC"] = " grader"})
print(forecast_2steps)