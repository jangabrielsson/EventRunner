----------------------------------------------------------------------------------------------------
-- Library  : tools
-- Author   : Christophe DRIGET
-- Version  : 2.12
-- Date     : May 2021
----------------------------------------------------------------------------------------------------


if tools then
	fibaro.error(__TAG or tag, "<b>tools</b> already exists : " .. type(tools))
end

tools = tools or {}

tools.version  = 2.12
tools._VERSION = "2.12"
tools.isdebug  = false
tools.optimise = true


--
-- Print debug messages
--
local function _print(color, f, ...)
	(type(f) == "function" and f or fibaro.debug)(__TAG or tag, tools:color(color, table.unpack({...})))
end
function tools:print(color, ...) _print(color,     fibaro.debug,   table.unpack({...})) end
function tools:debug(...)        _print("#30cc5b", fibaro.debug,   table.unpack({...})) end
function tools:trace(...)        _print("#f9e900", fibaro.trace,   table.unpack({...})) end
function tools:warning(...)      _print("#ff7800", fibaro.warning, table.unpack({...})) end
function tools:error(...)        _print("red",     fibaro.error,   table.unpack({...})) end


--
-- Display function arguments for debugging purpose
--
-- Usage :
-- tools:printargs("color", "myFunction", arg1, arg2, arg3)
--
function tools:printargs(color, name, ...)
	tools:print(color, tools:args(name, table.unpack({...})))
end


--
-- Return string formatted in HTML color
--
-- Usage :
-- self:debug(tools:color("blue", "Display", 1, "blue number"))
--
function tools:color(color, ...)
	if type(color) == "string" and color ~= "" then
		return "<font color=" .. color .. ">" .. tools:concat(" ", true, false, table.unpack({...})) .. "</font>"
	else
		return tools:concat(" ", true, false, table.unpack({...}))
	end
end


--
-- Return function arguments for debugging purpose
--
-- Usage :
-- self:debug(tools:args("myFunction", arg1, arg2, arg3))
--
function tools:args(name, ...)
	return (name or "function") .. "(" .. tools:concat(", ", true, true, table.unpack({...})) .. ")"
end


--
-- Concatenates table items together into a string
--
-- Usage :
-- self:debug(tools:concat(" ", true, true, "Display", 1, "number and a", nil, "value"))
--
function tools:concat(separator, html, types, ...)
	local t = {}
	for i = 1, select('#', ...) do
		t[i] = tools:tostring(select(i, ...), html, types)
	end
	return table.concat(t, separator)
end



--
-- Print table recursively
--
function tools:deepPrint(value)
	tools:print(nil, tools:htmlTree(tools:browseTable(value)))
end


--
-- Prepare HTML formatting
--
function tools:htmlTree(t)
	local result = ""
	if type(t) == "table" then
		if t.deep then
			local spacer = string.rep("&nbsp;&nbsp;", t.deep)
			if type(t.value) == "table" then
				local c = 0
				for _ in pairs(t.value) do
					c = c + 1
				end
				result = spacer .. "<i>table[" .. tostring(c) .. "]</i>"
				result = result .. tools:htmlTree(t.value)
			else
				result = spacer .. tools:tostring(t.value, true, true)
			end
		else
			for _, v in pairs(t) do
				local spacer = string.rep("&nbsp;&nbsp;", v.deep)
				if type(v.value) == "table" then
					local c = 0
					for _ in pairs(v.value) do
						c = c + 1
					end
					result = result .. "<br/>" .. spacer .. tools:tostring(v.key, true, true) .. " = <i>table[" .. tostring(c) .. "]</i>"
					result = result .. tools:htmlTree(v.value)
				else
					result = result .. "<br/>" .. spacer .. tools:tostring(v.key, true, true) .. " = " .. tools:tostring(v.value, true, true)
				end
			end
		end
	end
	return result
end


--
-- Browse table recursively
--
function tools:browseTable(t, deep)
	if type(t) == "table" then
		if deep then
			local deep = deep
			local result = {}
			for k, v in pairs(t) do
				if type(v) == "table" then
					result[#result+1] = {deep = deep, key = k, value = tools:browseTable(v, deep+1)}
				else
					result[#result+1] = {deep = deep, key = k, value = v}
				end
			end
			return result
		else
			return {deep = 0, value = tools:browseTable(t, 1)}
		end
	else
		return {deep = 0, value = t}
	end
end


--
-- Convert any given variable type to string
--
function tools:tostring(value, html, types)
	if type(value) == "string" then
		return types and ('"' .. value .. '"') or value
	elseif type(value) == "number" or type(value) == "integer" or type(value) == "boolean" then
		return tostring(value)
	elseif type(value) == "table" then
		local status, res = pcall(function()
			return json.encode(value)
		end)
		if not status then
			local c
			if types then
				c = 0
				for _ in pairs(value) do
					c = c + 1
				end
			end
			return (html and "<i>" or "") .. "table" .. (types and ("[" .. tostring(c) .. "]") or "") .. (html and "</i>" or "")
		end
		return (html and "<i>" or "") .. res .. (html and "</i>" or "")
	elseif type(value) == "function" then
		return (html and "<i>" or "") .. ("function" .. (types and "()" or "")) .. (html and "</i>" or "")
	elseif type(value) == "nil" then
		return html and "<i>nil</i>" or "nil"
	else -- Unknown type
		return (html and "<i>" or "") .. tostring(value) .. (html and "</i>" or "")
	end
end


--
-- Recursive compare of 2 tables
--
function tools:deepCompare(t1, t2)
	local typ1 = type(t1)
	local typ2 = type(t2)
	if typ1 ~= typ2 then return false end
	if typ1 ~= "table" and typ2 ~= "table" then return t1 == t2 end
	for k1, v1 in pairs(t1) do
		local v2 = t2[k1]
		if v2 == nil or not tools:deepCompare(v1, v2) then return false end
	end
	for k2, v2 in pairs(t2) do
		local v1 = t1[k2]
		if v1 == nil or not tools:deepCompare(v1, v2) then return false end
	end
	return true
end


--
-- Recursive search of all t2 fields into t1 table
--
function tools:deepFilter(t1, t2)
	local typ1 = type(t1)
	local typ2 = type(t2)
	if typ1 ~= typ2 then return false end
	if typ1 ~= "table" and typ2 ~= "table" then return t1 == t2 end
	for k2, v2 in pairs(t2) do
		local v1 = t1[k2]
		if v1 == nil or not tools:deepFilter(v1, v2) then return false end
	end
	return true
end


--
-- Recursive copy of a table
--
-- Usage :
-- local newTable = tools:deepCopy(originalTable)
--
function tools:deepCopy(t)
	if type(t) == "table" then
		local t2 = {}
		for k, v in pairs(t) do
			t2[k] = tools:deepCopy(v)
		end
		return t2
	else
		return t
	end
end


--
-- Round number to specified decimal
--
-- Usage :
-- local entier = tools:round(123.456, 0)
-- local decimal = tools:round(123.456, 1)
--
function tools:round(num, idp)
	local mult = 10 ^ (idp or 0)
	return math.floor(num * mult + 0.5) / mult
end


--
-- Convert seconds to human readable time
--
-- Usage :
-- print(tools:getDurationInString(3910)) --> 1h 5m 10s
--
function tools:getDurationInString(sSeconds)
	local nHours = math.floor(sSeconds/3600)
	local nMins = math.floor(sSeconds/60 - nHours*60)
	local nSecs = math.floor(sSeconds - nHours*3600 - nMins*60)
	return (nHours > 0 and nHours .. "h " or "") .. ((nMins > 0 or (nHours > 0 and nSecs > 0)) and nMins .. "m " or "") .. ((nSecs > 0 or (nHours == 0 and nMins == 0)) and nSecs .. "s" or "")
end


--
-- URL Percent-encoding
--
function tools:urlencode(str)
	if str then
		str = string.gsub(str, "\n", "\r\n")
		str = string.gsub(str, "([^%w %-%_%.%~])", function(c) return string.format("%%%02X", string.byte(c)) end)
		str = string.gsub(str, " ", "+")
	end
	return str	
end


--
-- Base64 encoding
--
-- Usage :
-- local auth = tools:base64("user:password")
--
function tools:base64(s)
	-- http://lua-users.org/wiki/BaseSixtyFour
	local bs = { [0] =
		'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
		'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','/',
	}
	local byte, rep = string.byte, string.rep
	local pad = 2 - ((#s-1) % 3)
	s = (s..rep('\0', pad)):gsub("...", function(cs)
		local a, b, c = byte(cs, 1, 3)
		return bs[a>>2] .. bs[(a&3)<<4|b>>4] .. bs[(b&15)<<2|c>>6] .. bs[c&63]
	end)
	return s:sub(1, #s-pad) .. rep('=', pad)
end


--
-- Split string to table
--
-- Usage :
-- local tableau = tools:split("Texte,séparé,par,des,virgules", ",")
--
function tools:split(text, sep)
	local sep, fields = sep or ":", {}
	local pattern = string.format("([^%s]+)", sep)
	if type(text) == "string" then
		text:gsub(pattern, function(c) fields[#fields+1] = c end)
	else
		tools:error("tools:split() : invalid text :", type(text), tostring(text))
	end
	return fields
end


--
-- Display log message below device icon
--
-- Usage :
-- tools.log(self, "Error", 3000)
-- tools.log(self, "Transfer_was_OK", 2000)
-- tools.log(self, "ZWave_Send_Failed", 2000)
--
function tools.log(self, message, delay)
	local status, err = pcall(function()
		local id = type(self) == "userdata" and self ~= tools and self.id or type(self) == "number" and self > 0 and self
		if id then
			if type(self) == "userdata" then
				self:updateProperty("log", message or "")
				if type(delay) == "number" and delay > 0 then
					fibaro.setTimeout(delay, function() self:updateProperty("log", "") end)
				end
			else
				fibaro.call(self, "updateProperty", "log", message or "")
				if type(delay) == "number" and delay > 0 then
					fibaro.setTimeout(delay, function() fibaro.call(self, "updateProperty", "log", "") end)
				end
			end
			return true
		else
			tools:error("tools:log() : invalid self device :", type(self), tostring(self))
			return false
		end
	end)
	if not status then
		tools:error(err or "Can't update log property")
		return false
	end
	return err
end


--
-- Return device id matching given name
--
-- Usage :
-- tools:getDeviceIdByName("/devices", "Device")
-- tools:getDeviceIdByName("/devices?interface=quickApp", "QuickApp")
--
function tools:getDeviceIdByName(url, name)
	local response, status = api.get(url)
	if type(status) == "number" and (status == 200 or status == 201) and type(response) == "table" then
		for _, device in ipairs(response) do
			if device.id and device.name and device.name == name then
				return device.id
			end
		end
	else
		tools:error("Can't get devices API, error #" .. tostring(status) .. " : " .. json.encode(response))
	end
end


--
-- Get QuickApp view value (label, slider, ...)
--
-- Usage :
-- local label = tools.getView(self, "LabelName", "text")
-- local slider = tools.getView(1234, "SliderName", "value")
--
function tools.getView(self, name, typ)
	local function find(s)
		if type(s) == 'table' then
			if s.name == name then
				return s[typ]
			else
				for _,v in pairs(s) do
					local r = find(v)
					if r then
						return r
					end
				end
			end
		end
	end
	local id = type(self) == "userdata" and self ~= tools and self.id or type(self) == "number" and self > 0 and self
	if id then
		return find(api.get("/plugins/getView?id="..tostring(id))["$jason"].body.sections)
	else
		tools:error("tools:getView() : invalid self device :", type(self), tostring(self))
	end
end


--
-- Get label value
--
-- Usage :
-- local label = tools.getLabel(self, "LabelName")
-- local label = tools.getLabel(1234, "LabelName")
--
function tools.getLabel(self, name)
	local id = type(self) == "userdata" and self ~= tools and self.id or type(self) == "number" and self > 0 and self
	if id then
		if type(name) == "string" and name ~= "" then
			return tools.getView(id, name, "text")
		else
			tools:error("tools:getLabel() : invalid label name :", type(name), tostring(name))
		end
	else
		tools:error("tools:getLabel() : invalid self device :", type(self), tostring(self))
	end
end


--
-- Update label value only if different from current value
--
-- Usage :
-- tools.updateLabel(self, "LabelName", "Hello World")
-- tools.updateLabel(1234, "LabelName", "Hello World")
--
function tools.updateLabel(self, name, value)
	local id = type(self) == "userdata" and self ~= tools and self.id or type(self) == "number" and self > 0 and self
	if id then
		if type(name) == "string" and name ~= "" then
			local oldValue = tools.getLabel(id, name)
			if type(oldValue) == "string" then
				if oldValue ~= value then
					if tools.isdebug then
						tools:trace('Update label "<b>' .. name .. '</b>" to "<b>' .. (value or "") .. '</b>"')
					end
					if type(self) == "userdata" then
						self:updateView(name, "text", value)
					else
						fibaro.call(self, "updateView", name, "text", value)
					end
				end
				return true
			else
				tools:warning('Label "<b>' .. name .. '</b>" not found')
			end
		else
			tools:error("tools:updateLabel() : invalid label name :", type(name), tostring(name))
		end
	else
		tools:error("tools:updateLabel() : invalid self device :", type(self), tostring(self))
	end
	return false
end


--
-- Get slider value
--
-- Usage :
-- local slider = tools.getSlider(self, "SliderName")
-- local slider = tools.getSlider(1234, "SliderName")
--
function tools.getSlider(self, name)
	local id = type(self) == "userdata" and self ~= tools and self.id or type(self) == "number" and self > 0 and self
	if id then
		if type(name) == "string" and name ~= "" then
			return tools.getView(id, name, "value")
		else
			tools:error("tools:getSlider() : invalid slider name :", type(name), tostring(name))
		end
	else
		tools:error("tools:getSlider() : invalid self device :", type(self), tostring(self))
	end
end


--
-- Update slider value only if different from current value
--
-- Usage :
-- tools.updateSlider(self, "SliderName", "50")
-- tools.updateSlider(1234, "SliderName", "50")
--
function tools.updateSlider(self, name, value)
	local id = type(self) == "userdata" and self ~= tools and self.id or type(self) == "number" and self > 0 and self
	if id then
		if type(name) == "string" and name ~= "" then
			local oldValue = tools.getSlider(id, name)
			if type(oldValue) == "string" then
				if oldValue ~= value then
					if tools.isdebug then
						tools:trace('Update slider "<b>' .. name .. '</b>" to "<b>' .. (value or "") .. '</b>"')
					end
					if type(self) == "userdata" then
						self:updateView(name, "value", value)
					else
						fibaro.call(self, "updateView", name, "value", value)
					end
				end
				return true
			else
				tools:warning("Slider " .. (name or "???") .. " not found")
			end
		else
			tools:error("tools:updateSlider() : invalid slider name :", type(name), tostring(name))
		end
	else
		tools:error("tools:updateSlider() : invalid self device :", type(self), tostring(self))
	end
	return false
end


--
-- Get QuickApp variable silently without showing warning message in case variable does not exist
--
-- Usage :
-- local mavariable = tools.getVariable(self, "debug")
-- local mavariable = tools.getVariable(1234, "debug")
--
function tools.getVariable(self, variable)
	local id = type(self) == "userdata" and self ~= tools and self.id or type(self) == "number" and self > 0 and self
	if id then
		if type(variable) == "string" and name ~= "" then
			local device
			if type(self) == "userdata" then
				device = self
			else
				device = api.get('/devices/' .. tostring(id))
			end
			if device then
				if type(device.properties) == "table" and type(device.properties.quickAppVariables) == "table" then
					for _, v in ipairs(device.properties.quickAppVariables) do
						if v.name == variable then
							return v.value
						end
					end
				else
					tools:warning("tools:getVariable() : can't get QuickApp variables")
				end
			else
				tools:error("tools:getVariable() : can't find device", type(self), tostring(self))
			end
		else
			tools:error("tools:getVariable() : invalid variable name :", type(variable), tostring(variable))
		end
	else
		tools:error("tools:getVariable() : invalid self device :", type(self), tostring(self))
	end
end


--
-- Delete QuickApp variable(s)
--
-- Usage :
-- tools.deleteVariable(self, "myVariable")
-- tools.deleteVariable(child, "myVariable")
-- tools.deleteVariable(123, {"myVariable", "anotherVariable"})
--
function tools.deleteVariable(self, params)
	local status, err = pcall(function()
		local id = type(self) == "userdata" and self ~= tools and self.id or type(self) == "number" and self > 0 and self
		if id then
			local device
			if type(self) == "userdata" then
				device = self
			else
				device = api.get("/devices/" .. tostring(id))
			end
			if device then
				if type(device.properties) == "table" and type(device.properties.quickAppVariables) == "table" then
					if type(params) ~= "table" then
						params = {params}
					end
					local quickAppVariables = device.properties.quickAppVariables
					local newVariables = {}
					for i = 1, #quickAppVariables do
						local found = false
						for _, variable in ipairs(params) do
							if type(variable) == "string" and variable ~= "" then
								if quickAppVariables[i].name == variable then
									found = true
									break
								end
							else
								tools:error("tools:deleteVariable() : invalid variable name :", tools:tostring(variable, true, true))
							end
						end
						if not found then
							newVariables[#newVariables+1] = quickAppVariables[i]
						end
					end
					if #quickAppVariables ~= #newVariables then
						if tools.isdebug then
							tools:deepPrint({properties = {quickAppVariables = newVariables}})
						end
						api.put("/devices/" .. tostring(id), {properties = {quickAppVariables = newVariables}})
						return true
					else
						tools:warning("tools:deleteVariable() : no QuickApp variable to delete")
					end
				else
					tools:warning("tools:deleteVariable() : can't get QuickApp variables")
				end
			else
				tools:error("tools:deleteVariable() : can't find device", type(self), tostring(self))
			end
		else
			tools:error("tools:deleteVariable() : invalid self device :", type(self), tostring(self))
		end
		return false
	end)
	if not status then
		tools:error(err or "Can't delete QuickApp variable")
		return false
	end
	return err
end


--
-- Check global variable existence
--
-- Usage :
-- if not tools:checkVG("VariableName") then
--  tools:createVG("VariableName", "Default value", nil)
--  tools:createVG("EnumVariable", "Yes", {"Yes", "No"})
-- end
--
function tools:checkVG(vg)
	if type(vg) == "string" and vg ~= "" then
		if tools.isdebug then
			tools:print(nil, 'Check if global variable "<b>' .. vg .. '</b>" exists...')
		end
		local response, status = api.get("/globalVariables/" .. vg)
		if type(status) == "number" and (status == 200 or status == 201) and type(response) == "table" then
			if not response.name or response.name ~= vg then
				if tools.isdebug then
					tools:warning('Response OK but global variable "</b>' .. vg .. '</b>" does not exist')
				end
				return false
			end
		else
			if tools.isdebug then
				tools:warning('Global variable "<b>' .. vg .. '</b>" does not exist')
			end
			return false
		end
		return true
	else
		tools:error("tools:checkVG() : invalid global variable name :", type(vg), tostring(vg))
		return false
	end
end


--
-- Create global variable
--
-- Usage :
--  tools:createVG("VariableName", "Default value", nil)
--  tools:createVG("EnumVariable", "Yes", {"Yes", "No"})
--
function tools:createVG(varName, varValue, varEnum)
	if type(varName) == "string" and varName ~= "" then
		if tools.isdebug then
			tools:print(nil, 'Create global variable "<b>' .. varName .. '</b>"...')
		end
		local payload = {name = varName, value = varValue or ""}
		local response, status = api.post("/globalVariables", payload)
		if type(status) == "number" and (status == 200 or status == 201) and type(response) == "table" then
			tools:debug('Global variable "<b>' .. varName .. '</b>" created')
			if type(varEnum) == "table" and #varEnum > 0 then
				local payload = {name = varName, value = varValue or "", isEnum = true, enumValues = varEnum}
				local response, status = api.put("/globalVariables/"..varName, payload)
				if type(status) == "number" and (status == 200 or status == 201) and type(response) == "table" then
					tools:debug('Global variable "<b>' .. varName .. '</b>" modified with enum values')
				else
					tools:error("Error : Can't add enum values to global \"<b>" .. varName .. "</b>\" variable, status =", status, "/ payload :", json.encode(payload), "=>", json.encode(response))
					return false
				end
			end
		else
			tools:error("Error : Can't create global variable \"<b>" .. varName .. "</b>\", status =", status, "/ payload :", json.encode(payload), "=>", json.encode(response))
			return false
		end
	else
		tools:error("tools:createVG() : invalid global variable name :", type(varName), tostring(varName))
		return false
	end
	return true
end


--
-- Change global variable value
--
-- Usage :
--  tools:setVG("VariableName", Value)
--
function tools:setVG(vg, value)
	if type(vg) == "string" and vg ~= "" then
		local oldvalue = fibaro.getGlobalVariable(vg)
		if oldvalue ~= value then
			if tools.isdebug then
				tools:debug('Global variable "<b>' .. vg .. '</b>" value change from "<b>' .. tostring(oldvalue) .. '</b>" to "<b>' .. tostring(value) .. '</b>"')
			end
			fibaro.setGlobalVariable(vg, value)
			return true
		end
	else
		tools:error("tools:setVG() : invalid global variable name :", type(vg), tostring(vg))
	end
	return false
end


--
-- Check is device has given interface(s)
--
-- Usage :
-- tools.hasInterface(self, "battery")          -- Return true if self device has "battery" interface
-- tools.hasInterface(child, "battery")         -- Return true if child device has "battery" interface
-- tools.hasInterface(123, {"power", "energy"}) -- Return true if device ID 123 has both "power" and "energy" interfaces
--
function tools.hasInterface(self, params)

	local function getInterface(device, param)
		if type(device.interfaces) == "table" then
			for _, interface in ipairs(device.interfaces) do
				if interface == param then
					return true
				end
			end
		end
		return false
	end

	local status, err = pcall(function()
		local id = type(self) == "userdata" and self ~= tools and self.id or type(self) == "number" and self > 0 and self
		if id then
			local device = api.get('/devices/' .. tostring(id))
			if device then
				if type(params) ~= "table" then
					params = {params}
				end
				if #params > 0 then
					local found = true
					for _, param in ipairs(params) do
						found = found and getInterface(device, param)
					end
					return found
				else
					tools:error("tools:hasInterface() : no interface given")
				end
			else
				tools:error("tools:hasInterface() : device #<b>" .. tostring(id) .. "</b> does not exist")
			end
		else
			tools:error("tools:hasInterface() : invalid self device :", type(self), tostring(self))
		end
		return false
	end)
	if not status then
		tools:error(err or "Can't get interface")
		return false
	end
	return err

end


--
-- Add interface(s) to device
--
-- Usage :
-- tools.addInterface(self, "battery")          -- Add "battery" interface to self device
-- tools.addInterface(child, "battery")         -- Add "battery" interface to child device
-- tools.addInterface(123, {"power", "energy"}) -- Add "power" and "energy" interfaces to device ID 123
--
function tools.addInterface(self, params)
	local status, err = pcall(function()
		local id = type(self) == "userdata" and self ~= tools and self.id or type(self) == "number" and self > 0 and self
		if id then
			local device = api.get('/devices/' .. tostring(id))
			if device then
				if type(params) ~= "table" then
					params = {params}
				end
				local interfaces = {}
				for _, param in ipairs(params) do
					if not tools.hasInterface(id, param) then
						if tools.isdebug then
							tools:debug('Add "<b>' .. param .. '</b>" interface to device #<b>' .. tostring(device.id) .. ' ' .. (device.name or "<i>nil</i>") .. '</b>')
						end
						interfaces[#interfaces+1] = param
					end
				end
				if type(self) == "userdata" then
					self:addInterfaces(interfaces)
				else
					fibaro.call(self, "addInterfaces", interfaces)
				end
				return true
			else
				tools:error("tools:addInterface() : device #<b>" .. tostring(id) .. "</b> does not exist")
			end
		else
			tools:error("tools:addInterface() : invalid self device :", type(self), tostring(self))
		end
		return false
	end)
	if not status then
		tools:error(err or "Can't add interface")
		return false
	end
	return err
end


--
-- Delete interface(s) from device
--
-- Usage :
-- tools.deleteInterface(self, "battery")          -- Delete "battery" interface from self device
-- tools.deleteInterface(child, "battery")         -- Delete "battery" interface from child device
-- tools.deleteInterface(123, {"power", "energy"}) -- Delete "power" and "energy" interfaces from device ID 123
--
function tools.deleteInterface(self, params)
	local status, err = pcall(function()
		local id = type(self) == "userdata" and self ~= tools and self.id or type(self) == "number" and self > 0 and self
		if id then
			local device = api.get('/devices/' .. tostring(id))
			if device then
				if type(params) ~= "table" then
					params = {params}
				end
				local interfaces = {}
				for _, param in ipairs(params) do
					if tools.hasInterface(id, param) then
						if tools.isdebug then
							tools:debug('Delete "<b>' .. param .. '</b>" interface from device #<b>' .. tostring(device.id) .. ' ' .. (device.name or "<i>nil</i>") .. '</b>')
						end
						interfaces[#interfaces+1] = param
					end
				end
				if type(self) == "userdata" then
					self:deleteInterfaces(interfaces)
				else
					fibaro.call(self, "deleteInterfaces", interfaces)
				end
				return true
			else
				tools:error("tools:deleteInterfaces() : device #<b>" .. tostring(id) .. "</b> does not exist")
			end
		else
			tools:error("tools:deleteInterfaces() : invalid self device :", type(self), tostring(self))
		end
		return false
	end)
	if not status then
		tools:error(err or "Can't delete interface")
		return false
	end
	return err
end


--
-- Create child device
--
-- Usage :
--	local child = {
--		name = "Name",                                               -- required !
--		type = "com.fibaro.multilevelSensor",                        -- required !
--		properties = {                                               -- optional
--			deviceIcon = 127,
--			icon = { path="plugins/com.fibaro.denonHeos/img/icon.png"},﻿
--			deviceControlType = 20,
--			categories = {"other"},
--		},
--		class = MyChild,                                             -- required !
--		unit = "V",                                                  -- optional
--		variables = {{name = "MyVariable", value = "Hello World"}},  -- optional
--		interfaces = {"power", "energy"},                            -- optional
--	}
--	if not tools.createChild(self, child) then
--		tools:error("Error : child creation failed")
--	end
--
function tools.createChild(self, param)
	local status, err = pcall(function()
		if self ~= tools then
			-- Prepare child device properties
			local childName       = param.name or "Child"
			local childType       = param.type
			local childClass      = param.class
			local childRoom       = param.room
			local childProperties = tools:deepCopy(param.properties)
			local childUnit       = param.unit
			local childVariables  = param.variables
			local childInterfaces = tools:deepCopy(param.interfaces)
			if tools.isdebug then
				tools:print(nil, "New child device name '<b>" .. (childName or "<i>nil</i>") .. "</b>' - type '<b>" .. (childType or "<i>nil</i>") .. "</b>' - class '<b>" .. (tostring(childClass):match("class (%a+)") or "<i>nil</i>") .. "</b>'")
			end
			-- Add child device unit
			if type(childUnit) == "string" and childUnit ~= "" then
				if tools.isdebug then
					tools:print("gray", 'Add "<b>' .. childUnit .. '</b>" unit to child')
				end
				childProperties.unit = childUnit
			end
			-- Add child device variables
			childProperties.quickAppVariables = childProperties.quickAppVariables or {}
			if type(childVariables) == "table" then
				for _, variable in ipairs(childVariables) do
					if type(variable.name) == "string" and variable.name ~= "" then
						if tools.isdebug then
							tools:print("gray", 'Add child variable "<b>' .. variable.name .. '</b>" = <b>' .. tools:tostring(variable.value or "", true, true) .. '</b>')
						end
						table.insert(childProperties.quickAppVariables, {name = variable.name, value = variable.value or ""})
					else
						tools:warning("Attention : missing variable name")
					end
				end
			elseif type(childVariables) ~= "nil" then
				tools:warning("Invalid variables type")
			end
			-- Child device interfaces
			if type(childInterfaces) == "string" then
				childInterfaces = {childInterfaces}
			end
			if type(childInterfaces) == "table" then
				if tools.isdebug then
					for _, interface in ipairs(childInterfaces) do
						tools:print("gray", 'Add child interface "<b>' .. interface .. '<b>"')
					end
				end
			elseif type(childInterfaces) ~= "nil" then
				tools:warning("Invalid interfaces type :", type(childInterfaces))
			end
			-- Create child device
			local child = self:createChildDevice({
					name   = childName,
					type   = childType,
					initialProperties = childProperties,
					initialInterfaces = childInterfaces,
				},
				childClass
			)
			if child then
				-- Set child device room
				if type(childRoom) == "number" then
					if tools.isdebug then
						tools:print("gray", "Set child device room ID ", childRoom)
					end
					api.put("/devices/"..tostring(child.id), {roomID = childRoom})
				else
					local childRoom = fibaro.getRoomID(self.id)
					if childRoom then
						if tools.isdebug then
							tools:print("gray", "Set child device room ID ", childRoom)
						end
						api.put("/devices/"..tostring(child.id), {roomID = childRoom})
					else
						tools:warning("Attention : parent room not found")
					end
				end
				-- Child device interfaces
				if type(childInterfaces) == "table" then
					-- Remove extra interfaces
					local device = api.get('/devices/' .. tostring(child.id))
					if type(device.interfaces) == "table" then
						for _, existingInterface in ipairs(device.interfaces) do
							local found = false
							for _, interface in ipairs(childInterfaces) do
								if existingInterface == interface then
									found = true
									break
								end
							end
							if not found and existingInterface ~= "quickAppChild" then
								if tools.isdebug then
									tools:print("gray", 'Remove default child interface "<b>' .. existingInterface .. '<b>"')
								end
								tools.deleteInterface(child, existingInterface)
							end
						end
					end
				elseif type(childInterfaces) ~= "nil" then
					tools:warning("Invalid interfaces type")
				end
				tools:debug('QuickApp child device #<b>' .. tostring(child.id) .. '</b> "' .. child.name .. '</b>" of type "<b>' .. child.type .. '</b>" created successfully')
				return true
			else
				tools:error("Can't create child device '" .. childName .. "' of type '" .. childType .. "' !")
			end
		else
			tools:error("tools:createChild() : invalid self device")
		end
		return false
	end)
	if not status then
		tools:error(err or "Can't create child device")
		return false
	end
	return err
end


--
-- Send Wake-On-LAN magic packet to specified MAC Address
--
-- Usage :
-- tools:WOL("00:00:00:00:00:00", {
-- 	success = function()
-- 	end,
-- 	error = function(response)
-- 	end,
-- })
--
function tools:WOL(mac, callback)
	-- Check MAC address format : "01:23:45:67:89:ab" or "01-23-45-67-89-ab" or "0123456789ab"
	if type(mac) ~= "string" then
		local message = "Wake-on-LAN failed : invalid MAC address type : " .. type(mac)
		if type(callback) == "table" and type(callback.error) == "function" then fibaro.setTimeout(0, function() callback.error(message) end) end
		return false, message
	end
	mac = tools:trim(mac)
	if not (string.match(mac, "^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") or string.match(mac, "^%x%x-%x%x-%x%x-%x%x-%x%x-%x%x$") or string.match(mac, "^%x%x%x%x%x%x%x%x%x%x%x%x$")) then
		local message = "Wake-on-LAN failed : invalid MAC address format : " .. tools:tostring(mac, true, true)
		if type(callback) == "table" and type(callback.error) == "function" then fibaro.setTimeout(0, function() callback.error(message) end) end
		return false, message
	end
	-- Convert MAC address, every 2 Chars (7-bit ASCII), to one Byte Char (8-bits) -- (c) JC Vermandé 2013
	local s = string.gsub(mac, ":", ""):gsub("-", "")
	local _macAddress = "" -- will contain converted MAC
	for i=1, 12, 2 do
		_macAddress = _macAddress .. string.char(tonumber(string.sub(s, i, i+1), 16))
	end
	local _magicPacket = string.char(0xff, 0xff, 0xff, 0xff, 0xff, 0xff) -- Create Magic Packet 6 x FF
	local _broadcastAddress = "255.255.255.255" -- Broadcast Address
	local _wakeOnLanPort = 9 -- Default port used
	for i = 1, 16 do
		_magicPacket = _magicPacket .. _macAddress
	end
	-- Send data to UDP socket
	local udpSocket = net.UDPSocket({
		broadcast = true,
		timeout = 5000,
	})
	local status, err = pcall(function()
		udpSocket:sendTo(_magicPacket, _broadcastAddress, _wakeOnLanPort, {
			success = function()
				udpSocket:close()
				if type(callback) == "table" and type(callback.success) == "function" then fibaro.setTimeout(0, function() callback.success() end) end
			end,
			error = function(response)
				udpSocket:close()
				if type(callback) == "table" and type(callback.error) == "function" then fibaro.setTimeout(0, function() callback.error("Wake-on-LAN transfer failed : " .. (response or "<i>nil</i>")) end) end
			end,
		})
	end)
	if not status then
		udpSocket:close()
		local message = "Can't send Wake-on-LAN data to UDP socket : " .. (err or "<i>nil</i>")
		if type(callback) == "table" and type(callback.error) == "function" then fibaro.setTimeout(0, function() callback.error(message) end) end
		return false, message
	end
	return true
end


--
-- Remove leading and trailing spaces
--
function tools:trim(s)
	return s:gsub("^%s*(.-)%s*$", "%1")
end


--
-- Display LUA memory consumption every 5 minutes
--
-- Usage :
-- tools:garbage()
--
function tools:garbage(interval)
	if not self.garbageExecTime then
		self.garbageExecTime = os.time()
		self.garbageValues = {}
		if self.optimise and type(tools.optimize) == "function" then
			tools:optimize()
		end
		self.nbCPUs = #(api.get("/diagnostics").cpuLoad or {{}})
		if self.nbCPUs < 1 then self.nbCPUs = 1 end
		self.cpuConsumed = os.clock()
	else
		local garbageExecTime = os.time()
		local elapsedTime = os.difftime(garbageExecTime, self.garbageExecTime or 0)
		if tools.isdebug or elapsedTime >= (tonumber(interval) or 300) then
			local garbage = collectgarbage("count")
			self.garbageExecTime = garbageExecTime
			local cpuConsumed = os.clock()
			local cpuDelta = cpuConsumed - self.cpuConsumed
			self.cpuConsumed = cpuConsumed
			tools:print("gray", string.format("Total memory in use by Lua : %.2f KB, CPU consumed : %.2f ms ( %.3f %% )", collectgarbage("count"), cpuDelta*1000, cpuDelta/elapsedTime*100/self.nbCPUs))
			self.garbageValues[#self.garbageValues+1] = garbage
			if #self.garbageValues >= 10 then
				local up = true
				local previous = 0
				for _, v in ipairs(self.garbageValues) do
					if previous == 0 then
						previous = v
					end
					if v < previous then
						up = false
						break
					end
					previous = v
				end
				if up then
					tools:warning("LUA memory usage is increasing :", string.format("%.2f", previous), "KB")
				end
				table.remove(self.garbageValues, 1)
			end
		end
	end
end


--
-- Remove unused functions
--
-- Usage :
-- tools:optimize()
--
function tools:optimize()

	local functions = {
		version = true,
		_VERSION = true,
		--print = true,
		--debug = true,
		--trace = true,
		--warning = true,
		--error = true,
		--color = true,
		printargs = {
			args = true,
		},
		args = true,
		--concat = true,
		--tostring = true,
		deepPrint = {
			htmlTree = true,
			browseTable = true,
		},
		htmlTree = true,
		browseTable = true,
		deepCompare = true,
		deepFilter = true,
		deepCopy = true,
		round = true,
		getDurationInString = true,
		urlencode = true,
		base64 = true,
		split = true,
		log = true,
		getDeviceIdByName = true,
		getView = true,
		getLabel = {
			getView = true,
		},
		updateLabel = {
			getLabel = true,
		},
		getSlider = {
			getView = true,
		},
		updateSlider = {
			getSlider = true,
		},
		getVariable = true,
		deleteVariable = {
			deepPrint = true,
		},
		checkVG = true,
		createVG = true,
		setVG = true,
		hasInterface = true,
		addInterface = {
			hasInterface = true,
		},
		deleteInterface = {
			hasInterface = true,
		},
		createChild = {
			deleteInterface = true,
			deepCopy = true,
		},
		WOL = {
			trim = true,
		},
		trim = true,
		garbage = true,
		--optimize = true,
		iif = true,
		isNumber = true,
		isNil = true,
		isNotNil = true,
	}

	local function deleteFunction(fonction)
		if type(functions[fonction]) == "table" then
			for func, _ in pairs(functions[fonction]) do
				deleteFunction(func)
			end
		end
		if functions[fonction] then
			functions[fonction] = false
		end
	end

	local id = tostring(plugin.mainDeviceId)
	local files, status = api.get("/quickApp/"..id.."/files")
	if status == 200 and type(files) == "table" then
		for _, file in ipairs(files) do
			if file.name ~= "tools" then
				local f, status = api.get("/quickApp/"..id.."/files/"..file.name)
				if status == 200 and type(f) == "table" then
					local content = string.gsub(f.content, "%-%-.-\n", "") -- Remove comments
					for k, v in pairs(functions) do
						if v then
							if string.match(content, "tools[:%.]"..k.."[%(\n%s]") then
								deleteFunction(k)
							end
						end
					end
				else
					tools:error("Can't get QuickApp file", file.name)
				end
			end
		end
	else
		tools:error("Can't get QuickApp files")
	end

	for k, v in pairs(functions) do
		if v then
			if tools.isdebug then
				tools:print("gray", "Optimize tools:" .. tools:tostring(k) .. "()")
			end
			tools[k] = nil
		end
	end
	if tools.isdebug then
		tools:print("gray", "Optimize tools:optimize()")
	end
	tools.optimise = nil
	fibaro.setTimeout(0, function() tools.optimize = nil end)

end


--
-- Test condition
--
function tools:iif(q, r, s)
	if q then
		return r
	else
		return s
	end
end


--
-- Test if number
--
function tools:isNumber(v)
	if type(v) == "number" then
		return true
	end
	if type(v) == "string" then
		return type(tonumber(v)) == "number"
	end
	return false
end


--
-- Test if nil
--
function tools:isNil(C)
	return type(C) == "nil"
end


--
-- Test if not nil
--
function tools:isNotNil(C)
	--return not tools:isNil(C)
	return type(C) ~= "nil"
end
