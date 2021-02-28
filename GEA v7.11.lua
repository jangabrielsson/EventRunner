-- =================================================================================================
-- QuickApp      : GEA : Gestionnaire d'Evénements Automatique
-- Auteur        : Steven en collaboration avec Pepite et Thibaut
--                 Lazer : QuickApp pour HC3
-- Version       : 7.11
-- Date          : Décembre 2020
-- Remerciements : Tous les utilisateurs/testeurs/apporteurs d'idées du forum domotique-fibaro.fr
-- =================================================================================================
--
-- Changements version HC3 par rapport à HC2 :
--
-- Supprimé :
--  "VirtualDevice", "VD"   => remplacé par "QuickApp" et "QA"
--  "SetrunConfigScenario"  => remplacé par "SetRunModeScenario" et "RunModeScene"
--  "RebootHC2"             => remplacé par "RebootHC3"
--  "ShutdownHC2"           => remplacé par "ShutdownHC3"
--  "Alarm"                 => en attendant le développement du QuickApp Alarm
--  "multiAlarm"            => en attendant le développement du QuickApp multiAlarm
--  "setMode"               => remplacé par "ThermostatMode"
--  "setThermostatSetpoint" => remplacé par "CoolingThermostatSetpoint" et "HeatingThermostatSetpoint"
--  "ThermostatLevel"
--  "ThermostatTime"
--  "DebugMessage"
--  "PluginScenario"
--
-- Ajouté :
--  "QuickApp"       (alias identique "QA")                 : {"QuickApp", <id_module>, <méthode>, [paramètres]}
--  "DeviceIcon"     (alias identique "CurrentIcon")        : {"CurrentIcon", <id_module>, <no_icon>}
--  "Color"          (alias identique "RGB")                : {"Color", <id_module>, <intensité_rouge>, <intensité_vert>, <intensité_bleu>, <intensité_blanc>}
--  "RunModeScene"   (alias identique "SetRunModeScenario") : {"RunModeScene", <id_scene>} | {"SetRunModeScenario", <id_scene>, <run_valeur>} - <run_valeur> : "manual" | "automatic"
--  "isSceneRunning" (alias identique "RunningScene")       : {"isSceneRunning", <id_scene>}
--  "ThermostatMode"                                        : {"ThermostatMode", <id_thermostat>, <mode>}
--  "ThermostatFanMode"                                     : {"ThermostatFanMode", <id_thermostat>, <fan>}
--  "CoolingThermostatSetpoint"                             : {"CoolingThermostatSetpoint", <id_thermostat>, <valeur>}
--  "HeatingThermostatSetpoint"                             : {"HeatingThermostatSetpoint", <id_thermostat>, <valeur>}
--  "Profile"                                               : {"Profile", <id_profil>}
--  "RebootHC3"                                             : {"RebootHC3"}
--  "SuspendHC3"                                            : {"SuspendHC3"}
--  "ShutdownHC3"                                           : {"ShutdownHC3"}
--
-- Modifié :
--  "Armed", "Disarmed", "setArmed", "setDisarmed" => Utilise l'ID de la zone
--
-- Amélioré :
--  GEA.portables = {123, "Nokia 3310"} : ID du mobile, ou nom du mobile
--  "Email" : ID du mobile, ou nom de l'utilisateur : {"Email", <id_user>, <"Message du mail">, <"Sujet du mail">} | {"Email", <id_user>, <"Message du mail">}


-- ================================================================================
-- Tous ce que GEA sait faire est ici
-- ================================================================================

__TAG = "QA_GEA_" .. plugin.mainDeviceId

tools = {
	version = "3.00",
	isdebug = false,
	--addstyle = "padding-left: 125px; display:inline-block; width:80%; margin-top:-18px; padding-top:-18px;"
	--log = function(a,b,c)a=tools.tostring(a)for d,e in string.gmatch(a,"(#spaces(%d+)#)")do local f=""for g=1,e do f=f.."."end;a=string.gsub(a,d,"<span style=\"color:black;\">"..f.."</span>")end;if tools.isdebug or c then fibaro.debug(__TAG, a)end end,
	log = function(a, b, c, f)
		a = tools.tostring(a)
		--for d, e in string.gmatch(a, "(#spaces(%d+)#)") do
			--local f = ""
			--for g = 1, e do
				--f = f .. "."
			--end
			--a = string.gsub(a, d, "<span style=\"color:black;"..tools.addstyle.."\">"..f.."</span>")
			--a = string.gsub(a, d, "&nbsp;")
		--end
		if (tools.isdebug or c) and type(f) == "function" then
			--fibaro.debug(__TAG, "<span style=\"color:"..(b or"white")..";"..tools.addstyle.."\">"..a.."</span>")
			if b then
				f(__TAG, "<font color=" .. b .. ">" .. a .. "</font>")
			else
				f(__TAG, a)
			end
		end
	end,
	--error = function(a,b)tools.log(a,b or"red",true)end,
	error = function(a,b)tools.log(a,b,true,fibaro.error)end,
	--warning = function(a,b)tools.log(a,b or"orange",true)end,
	warning = function(a,b)tools.log(a,b,true,fibaro.warning)end,
	--info = function(a,b)tools.log(a,b or"white",true)end,
	info = function(a,b)tools.log(a,b,true,fibaro.trace)end,
	--debug = function(a,b)tools.log(a,b or"gray",false)end,
	debug = function(a,b)tools.log(a,b,false,fibaro.debug)end,
	tostring = function(h)if type(h)=="boolean"then if h then return"true"else return"false"end elseif type(h)=="table"then if json then return json.encode(h)else return"table found"end else return tostring(h)end end,
	split = function(i,j)local j,k=j or":",{}local l=string.format("([^%s]+)",j)i:gsub(l,function(m)k[#k+1]=m end)return k end,
	trim = function(n)return n:gsub("^%s*(.-)%s*$","%1")end,
	deep_print = function(o)for g,p in pairs(o)do if type(p)=="table"then deep_print(p)else print(g,p)end end end,
	iif = function(q,r,s)if q then return r else return s end end,
	cut = function(t,u)u=u or 10;if u<t:len()then return t:sub(1,u-3).."..."end;return t end,
	isNumber = function(v)if type(v)=="number"then return true end;if type(v)=="string"then return type(tonumber(v))=="number"end;return false end,
	getStringTime = function(w)if w then return os.date("%H:%M:%S")end;return os.date("%H:%M")end,
	toTime = function(x)local y,z=string.match(x,"(%d+):(%d+)")local A=os.date("*t")local B=os.time{year=A.year,month=A.month,day=A.day,hour=y,min=z,sec=0}if B<os.time()then B=os.time{year=A.year,month=A.month,day=A.day+1,hour=y,min=z,sec=0}end;return B end,
	getStringDate = function()return os.date("%d/%m/%Y")end,
	isNil = function(C)return type(C)=="nil"end,
	isNotNil = function(C)return not tools.isNil(C)end,
	convertToString = function(value)
		if type(value) == 'boolean' then
			if value then return '1' else return '0' end
		elseif type(value) == 'number' then
			return tostring(value)
		elseif type(value) == 'table' then
			return json.encode(value)
		end
		return value
	end,
	getView = function(id, name, typ)
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
		return find(api.get("/plugins/getView?id="..id)["$jason"].body.sections)
	end,
	filterEvent = function(t1, t2)
		local ty1 = type(t1)
		local ty2 = type(t2)
		if ty1 ~= ty2 then return false end
		if ty1 ~= 'table' and ty2 ~= 'table' then return t1 == t2 end
		for k2,v2 in pairs(t2) do
			local v1 = t1[k2]
			if v1 == nil or not tools.filterEvent(v1, v2) then return false end
		end
		return true
	end,
}



-- ================================================================================
-- GEA Class Constructor
-- ================================================================================

class "GEA"

function GEA:__init(source)
	--tools.info("GEA:__init("..type(source)..") => " .. json.encode(source)) -- DEBUG

	self.globalvariables  = "GEA_Tasks"
	self.pluginsvariables = "GEA_Plugins"
	self.control          = true
	self.version          = "7.11"
	self.checkEvery       = 30                      -- durée en secondes
	self.debug            = false                   -- mode d'affiche debug on/off
	self.secureAction     = self.catchError or true -- utilise pcall() ou pas
	self.source           = source
	self.auto             = self.source.type == "autostart"
	self.language         = nil
	self.running          = nil
	self.globalvalue      = nil
	self.globalhisto      = nil
	self.runAt            = nil
	--self.firmware         = api.get("/settings/info").currentVersion.version
	self.varenum          = false
	self.suspendvar       = "SuspendreGEA"
	self.refreshInterval  = 100 -- durée en millisecondes

	self.portables = {}
	self.moduleNames = {}
	self.moduleRooms = {}
	self.variables = {}
	self.plugins = {}
	self.output = nil
	self.stoppedTasks = {}
	self.history = {}
	self.historyvariable = "GEA_History"
	self.historymax = 5
	self.pluginsreturn = {}
	self.pluginretry = 500
	self.pluginmax = 5
	self.garbagevalues = {}
	self.usedoptions = {}
	self.event = {}
	self.declared = {}
	self.forceRefreshValues = false
	self.showRoomNames = true
	self.batteriesWithRoom = self.showRoomNames
	self.buttonIds = {}
	self.nameToId = {}

	self.traduction = {
		en = {
			id_missing          = "ID : %s doesn't exists",
			global_missing      = "Global : %s doesn't exists",
			label_missing       = "Label : [%d] %s doesn't exists",
			slider_missing      = "Slider : [%d] %s doesn't exists",
			not_number          = "%s must be a number",
			not_string          = "%s must be a string",
			from_missing        = "&lt;from&gt; is mandatory",
			varCacheInstant     = "VariableCache doesn't work with event instance",
			central_instant     = "CentralSceneEvent works only with event instance",
			central_missing     = "id, key et attribute are mandatory",
			property_missing    = "Property : %s can't be found",
			option_missing      = "Option : %s is missing",
			not_an_action       = "Option : %s can't be used as an action",
			not_a_trigger       = "Option : %s can't be used as a trigger",
			not_math_op         = "Option : %s doesn't allow + or - operations",
			hour                = "hour",
			hours               = "hours",
			andet               = "and",
			minute              = "minute",
			minutes             = "minutes",
			second              = "second",
			seconds             = "seconds",
			err_cond_missing    = "Error : condition(s) required",
			err_dur_missing     = "Error : duration required",
			err_msg_missing     = "message required, empty string is allowed",
			not_an_condition    = "Option : %s can't be used as a condition",
			no_action           = "< no action >",
			repeated            = "repeat",
			stopped             = "stopped",
			maxtime             = "MaxTime",
			add_event           = "Add immediately :",
			add_auto            = "Add auto :",
			gea_failed          = "GEA ... STOPPED",
			validate            = "Validation",
			action              = "action",
			err_check           = "Error, check : ",
			date_format         = "%d.%m.%y",
			hour_format         = "%X",
			input_date_format   = "dd/mm/yyyy",
			quit                = "Quit",
			gea_run_since       = "GEA run since %s",
			gea_check_nbr       = "... check running #%d @%ds...",
			gea_start           = "Started automatically of GEA %s (mode %s)",
			gea_start_event     = "Started by event of GEA %s (mode %s [%s])",
			gea_minifier        = "Use minifiertools v. %s",
			gea_check_every     = "Check automatic every %s seconds",
			gea_global_create   = "GEA QuickApp variable : %s",
			gea_load_usercode   = "Loading user code setEvents() ...",
			gea_nothing         = "No entry to check",
			gea_start_time      = "GEA started on %s at %s ...",
			gea_stopped_auto    = "GEA has stopped running in automatic mode",
			week_short          = {"mo", "tu", "we", "th", "fr", "sa", "su"},
			week                = {"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"},
			months              = {"january", "febuary", "march", "april", "may", "juin", "july", "august", "september", "october", "november", "december"},
			weekend             = "Weekend",
			weekdays            = "Weekdays",
			weather             = {"clear", "cloudy", "rain", "snow", "storm", "fog"},
			search_plugins      = "Searching plugins, ...",
			plugins_none        = "Found any",
			plugin_not_found    = "Plugin not found",
			popupinfo           = "Information",
			popupsuccess        = "Success",
			popupwarning        = "Warning",
			popupcritical       = "Critical",
			memoryused          = "Memory used: ",
			optimization        = "Optimization...",
			removeuseless       = "Removing useless option: ",
			removeuselesstrad   = "Removing useless traduction: ",
			start_entry         = "Started",
			no_entry_for_event  = "No entry for this event %s, please remove it from header",
			locale              = "en-US",
			execute             = "Démarrer",
			name_is_missing     = "Name isn't specified",
			room_is_missing     = "Room isn't specified",
			device_is_missing   = "Device \"<b>%s</b>\" unknown",
			scene_is_missing    = "Scene \"<b>%s</b>\" unknown",
			partition_missing   = "Alarm partition \"<b>%s</b>\" unknown",
			user_missing        = "User \"<b>%s</b>\" unknown",
			profile_missing     = "Profile \"<b>%s</b>\" unknown",
			instant_trigger     = "Event trigger: ",
			gea_suspended       = "GEA suspended (variable : %s) ...",
			yes                 = "yes",
			no                  = "no",
		},
		fr = {
			id_missing          = "ID : %s n'existe(nt) pas",
			global_missing      = "Global : %s n'existe(nt) pas",
			label_missing       = "Label : [%d] %s n'existe pas",
			slider_missing      = "Slider : [%d] %s n'existe pas",
			not_number          = "%s doit être un numéro",
			not_string          = "%s doit être une chaîne de caractères",
			from_missing        = "&lt;from&gt; est obligatoire",
			varCacheInstant     = "VariableCache ne fonctionne pas avec les déclenchements instantanés",
			central_instant     = "CentralSceneEvent ne fonctionne qu'avec des déclenchements instantanés",
			central_missing     = "id, key et attribute sont obligatoires",
			property_missing    = "Propriété: %s introuvable",
			option_missing      = "Option : %s n'existe pas",
			not_an_action       = "Option : %s ne peut pas être utilisé comme action",
			not_a_trigger       = "Option : %s ne peut pas être utilisé comme trigger",
			not_math_op         = "Option : %s n'autorise pas les + ou -",
			hour                = "heure",
			hours               = "heures",
			andet               = "et",
			minute              = "minute",
			minutes             = "minutes",
			second              = "seconde",
			seconds             = "secondes",
			err_cond_missing    = "Erreur : condition(s) requise(s)",
			err_dur_missing     = "Erreur : durée requise",
			err_msg_missing     = "message requis, chaîne vide autorisée",
			not_an_condition    = "Option : %s ne peut pas être utilisé comme une condition",
			no_action           = "< pas d'action >",
			repeated            = "répété",
			stopped             = "stoppé",
			maxtime             = "MaxTime",
			add_event           = "Ajout immédiat :",
			add_auto            = "Ajout auto :",
			gea_failed          = "GEA ... ARRETE",
			validate            = "Validation",
			action              = "action",
			err_check           = "Erreur, vérifier : ",
			date_format         = "%d.%m.%y",
			hour_format         = "%X",
			input_date_format   = "dd/mm/yyyy",
			quit                = "Quitter",
			gea_run_since       = "GEA fonctionne depuis %s",
			gea_check_nbr       = "... vérification en cours #%d @%ds...",
			gea_start           = "Démarrage automatique de GEA %s (mode %s)",
			gea_start_event     = "Démarrage par événement de GEA %s (mode %s [%s])",
			gea_minifier        = "Utilisation de minifiertools v. %s",
			gea_check_every     = "Vérification automatique toutes les %s secondes",
			gea_global_create   = "Variable QuickApp GEA : %s",
			gea_load_usercode   = "Chargement du code utilisateur setEvents() ...",
			gea_nothing         = "Aucun traitement à effectuer",
			gea_start_time      = "GEA a démarré le %s à %s ...",
			gea_stopped_auto    = "GEA est arrêté en mode automatique",
			week_short          = {"lu", "ma", "me", "je", "ve", "sa", "di"},
			week                = {"lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"},
			months              = {"janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"},
			weekend             = "Weekend",
			weekdays            = "Semaine",
			weather             = {"dégagé", "nuageux", "pluvieux", "neigeux", "orageux", "brouillard"},
			search_plugins      = "Recherche de plugins, ...",
			plugins_none        = "Aucun plugin trouvé",
			plugin_not_found    = "Plugin inexistant",
			popupinfo           = "Information",
			popupsuccess        = "Succès",
			popupwarning        = "Attention appelée",
			popupcritical       = "Erreur Critique",
			memoryused          = "Mémoire utilisée : ",
			optimization        = "Optimisation en cours ...",
			removeuseless       = "Suppression d'option inutile : ",
			removeuselesstrad   = "Suppression de traduction inutile : ",
			start_entry         = "Démarrage",
			no_entry_for_event  = "Aucune entrée pour l'événement %s, supprimer le de l'entête",
			locale              = "fr-FR",
			execute             = "Execute",
			name_is_missing     = "Nom inconnu",
			room_is_missing     = "Pièce inconnue",
			device_is_missing   = "Module \"<b>%s</b>\" inconnu",
			scene_is_missing    = "Scène \"<b>%s</b>\" inconnue",
			partition_missing   = "Partition d'alarme \"<b>%s</b>\" inconnue",
			user_missing        = "Utilisateur \"<b>%s</b>\" inconnu",
			profile_missing     = "Profil \"<b>%s</b>\" inconnu",
			instant_trigger     = "Déclencheur instantané : ",
			gea_suspended       = "GEA suspendu (variable : %s) ...",
			yes                 = "oui",
			no                  = "non",
		}
	}

	-- --------------------------------------------------------------------------------
	-- Déclaration de toutes les fonctions de GEA
	--   f    = {name = "Nouvelle fonction",
	--                math       = true, -- autorise les + et -
	--                keepValues = true, -- ne traduit pas les sous-table {"TurnOn", 73} reste ainsi et non pas true ou false
	--                control    = function(name,value) if (...) then return true else return false, "Message d'erreur" end end,
	--                getValue   = function(name) return <la valeur> end,
	--                action     = function(name,value) <effectuer l'action> end,
	--                trigger    = function(id) return {event = {}, filter = {}} end,
	--                isBoolean  = true, -- ne compare pas le résultat
	--          },
	-- --------------------------------------------------------------------------------
	self.options = {
		number    = {name = "ID",
										control  = function(id) if type(id) ~= "table" then id = {id} end local res, msg = true, "" for i=1, #id do if not self:getName(self:findDeviceId(id[i]), self.showRoomNames) then res = false msg = msg .. self:findDeviceId(id[i]) .. " " end end return res, string.format(self.trad.id_missing, msg) end,
										--getValue = function(id) return tonumber(fibaro.getValue(self:findDeviceId(id), "value")) end,
										getValue = function(id) return fibaro.getValue(self:findDeviceId(id), "value") end, -- Lazer : suppression du tonumber()
										trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value"}, sourceType = "system"}} end,
		},
		boolean   = {name = "Boolean",
										getValue = function(bool) return bool end,
		},
		global    = {name = "Global",
										optimize = true,
										math     = true, -- autorise les Global+ et Global-
										control  = function(name) if type(name) ~= "table" then name = {name} end local res, msg = true, "" for i=1, #name do if not self:getGlobalValue(name[i]) then res = false msg = msg .. name[i] .. " " end end return res, string.format(self.trad.global_missing, msg) end,
										getValue = function(name) return self:getGlobalValue(name) end,
										action   = function(name, value) if type(name) ~= "table" then name = {name} end for i=1, #name do fibaro.setGlobalVariable(name[i], self:getMessage(self:incdec(value, self.options.global.getValue(name[i])))) end end,
										trigger  = function(name) return {event = {type = "global-variable", name = name}, filter = {type = "GlobalVariableChangedEvent", data = {variableName = name}}} end,
		},
		value     = {name = "Value",
										optimize = true,
										math     = true, -- autorise les Value+ et Value-
										control  = function(id) return self.options.number.control(id) end,
										getValue = function(id) if not id then id = self.currentMainId end return fibaro.getValue(self:findDeviceId(id), "value") end,
										action   = function(id, value) if not value then value = id id = self.currentMainId end if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]),"setValue",self:incdec(value, self.options.value.getValue(self:findDeviceId(id[i])))) end end,
										trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value"}, sourceType = "system"}} end,
		},
		value2    = {name = "Value2",
										optimize = true,
										math     = true,
										control  = function(id) return self.options.value.control(id) end,
										getValue = function(id) if not id then id = self.currentMainId end return fibaro.getValue(id, "value2") end,
										action   = function(id, value) if not value then value = id id = self.currentMainId end if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]),"setValue2",self:incdec(value, self.options.value2.getValue(self:findDeviceId(id[i])))) end end,
										trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value2"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value2"}, sourceType = "system"}} end,
		},
		property  = {name = "Property",
										optimize = true,
										math     = true,
										control  = function(id) return self.options.number.control(id) end,
										getValue = function(id, property) return fibaro.getValue(self:findDeviceId(id), property) end,
										action   = function(id, property, value) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), "setProperty", property, self:getMessage(self:incdec(value, self.options.property.getValue(self:findDeviceId(id[i]), property)))) end end,
										trigger  = function(id, property) return {event = {type = "device", id = self:findDeviceId(id), property = property}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = property}, sourceType = "system"}} end,
		},
		turnon    = {name = "TurnOn",
										optimize  = true,
										control   = function(id) if not id then id = self.currentMainId end return self.options.number.control(id) end,
										--getValue = function(id) if (not id) then id = self.currentMainId end  return tonumber(fibaro.getValue(self:findDeviceId(id), "value"))>0 end,
										getValue  = function(id) if not id then id = self.currentMainId end local val = fibaro.getValue(self:findDeviceId(id), "value") return type(val)=="boolean" and val or type(val)=="number" and val>0 or type(val)=="string" and val~="" or false end, -- Lazer : suppression tonumber
										action    = function(id, duree) if not id then id = self.currentMainId end if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]),"turnOn") end if duree then setTimeout(function() for i=1, #id do fibaro.call(self:findDeviceId(id[i]),"turnOff") end end, self:getDuree(duree) * 1000) end end,
										trigger   = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value"}, sourceType = "system"}} end,
										isBoolean = true,
		},
		turnoff   = {name = "TurnOff",
										optimize  = true,
										control   = function(id) if not id then id = self.currentMainId end return self.options.number.control(id) end,
										--getValue = function(id) if (not id) then id = self.currentMainId end return tonumber(fibaro.getValue(self:findDeviceId(id), "value"))==0 end,
										getValue  = function(id) if not id then id = self.currentMainId end local val = fibaro.getValue(self:findDeviceId(id), "value") return not(type(val)=="boolean" and val or type(val)=="number" and val>0 or type(val)=="string" and val~="" or false) end, -- Lazer : suppression tonumber
										action    = function(id, duree) if not id then id = self.currentMainId end if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]),"turnOff") end if duree then setTimeout(function() for i=1, #id do fibaro.call(self:findDeviceId(id[i]),"turnOn") end end, self:getDuree(duree) * 1000) end end,
										trigger   = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value"}, sourceType = "system"}} end,
										isBoolean = true,
		},
		switch    = {name = "Switch",
										optimize = true,
										control  = function(id) if not id then id = self.currentMainId end return self.options.number.control(id) end,
										--action=function(id) if (not id) then id = self.currentMainId end if type(id) ~= "table" then id = {id} end for i=1, #id do if (tonumber(fibaro.getValue(self:findDeviceId(id[i]), "value"))>0) then fibaro.call(self:findDeviceId(id[i]),"turnOff") else fibaro.call(self:findDeviceId(id[i]),"turnOn") end end end
										action   = function(id) if not id then id = self.currentMainId end if type(id) ~= "table" then id = {id} end for i=1, #id do local val = fibaro.getValue(self:findDeviceId(id[i]), "value") if type(val)=="boolean" and val or type(val)=="number" and val>0 or false then fibaro.call(self:findDeviceId(id[i]),"turnOff") else fibaro.call(self:findDeviceId(id[i]),"turnOn") end end end, -- Lazer : suppression tonumber
		},
--[[
    armed     = {name="Armed",
                    optimize = true,
                    control = function(id) if (not id) then id = self.currentMainId end return self.options.number.control(id) end,
                    getValue = function(id) if (not id) then id = self.currentMainId end return tonumber(fibaro.getValue(self:findDeviceId(id), "armed"))==1 end,
                },
    disarmed  = {name="Disarmed",
                    optimize = true,
                    control = function(id) if (not id) then id = self.currentMainId end return self.options.number.control(id) end,
                    getValue = function(id) if (not id) then id = self.currentMainId end return tonumber(fibaro.getValue(self:findDeviceId(id), "armed"))==0 end,
                },
    setarmed     = {name="setArmed",
                    optimize = true,
                    control = function(id) if (not id) then id = self.currentMainId end return self.options.number.control(id) end,
                    getValue = function(id) if (not id) then id = self.currentMainId end return tonumber(fibaro.getValue(self:findDeviceId(id), "armed"))==1 end,
                    action=function(id) if (not id) then id = self.currentMainId end if (type(id) ~= "table") then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]),"setArmed", 1) end end
                },
    setdisarmed  = {name="setDisarmed",
                    optimize = true,
                    control = function(id) if (not id) then id = self.currentMainId end return self.options.number.control(id) end,
                    getValue = function(id) if (not id) then id = self.currentMainId end return tonumber(fibaro.getValue(self:findDeviceId(id), "armed"))==0 end,
                    action=function(id) if (not id) then id = self.currentMainId end if (type(id) ~= "table") then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]),"setArmed", 0) end end
                },
--]]
		armed     = {name = "Armed",
										optimize  = true,
										--control   = function(id) return api.get("/alarms/v1/partitions/" .. self:findAlarmId(id)) and true or false, string.format(self.trad.partition_missing, tostring(id)) end,
										--getValue  = function(id) return api.get("/alarms/v1/partitions/" .. self:findAlarmId(id)).armed end,
										--trigger   = function(id) return {event = {type = "alarm", id = self:findAlarmId(id), property = "armed"}, filter = {type = "AlarmPartitionArmedEvent", data = {partitionId = self:findAlarmId(id), armed = true}}} end,
										control   = function(id) return api.get("/alarms/v1/partitions/" .. tostring(id)) and true or false, string.format(self.trad.partition_missing, tostring(id)) end,
										getValue  = function(id) return api.get("/alarms/v1/partitions/" .. id).armed end,
										trigger   = function(id) return {event = {type = "alarm", id = tonumber(id), property = "armed"}, filter = {type = "AlarmPartitionArmedEvent", data = {partitionId = tonumber(id), armed = true}}} end,
										isBoolean = true,
		},
		disarmed  = {name = "Disarmed",
										optimize  = true,
										control   = function(id) return api.get("/alarms/v1/partitions/" .. tostring(id)) and true or false, string.format(self.trad.partition_missing, tostring(id)) end,
										getValue  = function(id) return not api.get("/alarms/v1/partitions/" .. id).armed end,
										trigger   = function(id) return {event = {type = "alarm", id = tonumber(id), property = "armed"}, filter = {type = "AlarmPartitionArmedEvent", data = {partitionId = tonumber(id), armed = false}}} end,
										isBoolean = true,
		},
		setarmed  = {name = "setArmed",
										optimize = true,
										control  = function(id) if type(id) ~= "table" then id = {id} end local res, msg = true, "" for i=1, #id do if not api.get("/alarms/v1/partitions/" .. id) then res = false msg = msg .. tostring(id[i]) .. " " end end return res, string.format(self.trad.partition_missing, msg) end,
										action   = function(id) if type(id) ~= "table" then id = {id} end for i=1, #id do api.post("/alarms/v1/partitions/" .. id[i] .. "/actions/arm") end end,
		},
		setdisarmed = {name = "setDisarmed",
										optimize = true,
										control  = function(id) if type(id) ~= "table" then id = {id} end local res, msg = true, "" for i=1, #id do if not api.get("/alarms/v1/partitions/" .. id) then res = false msg = msg .. tostring(id[i]) .. " " end end return res, string.format(self.trad.partition_missing, msg) end,
										action   = function(id) if type(id) ~= "table" then id = {id} end for i=1, #id do api.delete("/alarms/v1/partitions/" .. id[i] .. "/actions/arm") end end,
		},
		sensor    = {name = "Sensor",
										optimize = true,
										math     = true,
										control  = function(id) if not id then id = self.currentMainId end return self.options.number.control(id) end,
										getValue = function(id) if not id then id = self.currentMainId end return fibaro.getValue(self:findDeviceId(id), "power") end,
										trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "power"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "power"}, sourceType = "system"}} end,
		},
    --virtualdevice = {name="VirtualDevice",
                    --optimize = true,
                    --control = function(id, button) if (type(id) ~= "table") then id = {id} end for i=1, #id do local check, message = self.options.number.control(self:findButtonId(self:findDeviceId(id[i]), button)) if (check) then return tools.isNumber(self:findButtonId(self:findDeviceId(id[i]), button)), string.format(self.trad.not_number, button) else return check, message end end end,
                    --action=function(id, button) if (type(id) ~= "table") then id = {id} end for i=1, #id do local currId = self:findDeviceId(id[i]) fibaro.call(currId, "pressButton", tostring(self:findButtonId(currId, button))) end end
                --},
		quickapp  = {name = "QuickApp",
										optimize = true,
										control  = function(id, method) if type(id) ~= "table" then id = {id} end for i=1, #id do local check, message = self.options.number.control(self:findDeviceId(id[i])) if check then return type(method) == "string", string.format(self.trad.not_string, method) else return check, message end end end,
										action   = function(id, method, ...) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), method, table.unpack({...})) end end,
		},
		label     = {name = "Label",
										optimize = true,
										math     = true,
										control  = function(id, property) if not self.options.checklabel.getValue(id, property) then return false, string.format(self.trad.label_missing, id, property) else return true end end,
										--getValue = function(id, property) return fibaro.getValue(self:findDeviceId(id), "ui."..property:gsub("ui.", ""):gsub(".value", "")..".value") end,
										getValue = function(id, property) return tools.getView(self:findDeviceId(id), property, "text") end, -- Lazer
										--action=function(id, property, value) if (type(id) ~= "table") then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), "setProperty", "ui."..property..".value", self:getMessage(self:incdec(value, self.options.label.getValue(self:findDeviceId(id[i]), property)))) end end
										action   = function(id, property, value) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), "updateView", property, "text", self:getMessage(self:incdec(value, self.options.label.getValue(self:findDeviceId(id[i]), property)))) end end,
										trigger  = function(id, property) return {event = {type = "device", id = self:findDeviceId(id), propertyName = "text", componentName = property}, filter = {type = "PluginChangedViewEvent", data = {deviceId = self:findDeviceId(id), propertyName = "text", componentName = property}}} end,
		},
		time      = {name = "Time",
										control   = function(from) if from and from:len()>0 then return true else return false, self.trad.from_missing end end,
										getValue  = function(from, to) if not to then to = from end if not to then return os.date(self.trad.hour_format, self.runAt) end return self:checkTime(from, to) end,
										isBoolean = true,
		},
		days      = {name = "Days",
										optimize  = true,
										getValue  = function(days) return self:checkDays(days) end,
										isBoolean = true,
		},
		dates     = {name = "Dates",
										optimize  = true,
										control   = function(from) if from and from:len()>0 then return true else return false, self.trad.from_missing end end,
										getValue  = function(from, to) return self:checkDates(from, to) end,
										isBoolean = true,
		},
		dst       = {name = "DST",
										optimize  = true,
										getValue  = function() return os.date("*t", self.runAt).isdst end,
										isBoolean = true,
		},
		nodst     = {name = "NODST",
										optimize  = true,
										getValue  = function() return not os.date("*t", self.runAt).isdst end,
										isBoolean = true,
		},
		weather   = {name = "Weather",
										optimize = true,
										math     = true,
										getValue = function(property, value) if not value then value = property property = nil if not property or property=="" then property = "WeatherCondition" end end return fibaro.getValue(3, property) end,
		},
		weatherlocal = {name = "WeatherLocal",
										optimize = true,
										math     = true,
										depends  = {"weather"},
										getValue = function(property) return self:translatetrad("weather", self:getOption({"Weather", property}).getValue()) end,
		},
		battery   = {name = "Battery",
										optimize = true,
										math     = true,
										control  = function(id) return self.options.number.control(id) end,
										getValue = function(id) return fibaro.getValue(self:findDeviceId(id), 'batteryLevel') end,
										trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "batteryLevel"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "batteryLevel"}, sourceType = "system"}} end,
		},
		batteries = {name = "Batteries",
										optimize  = true,
										getValue  = function(value) return self:batteries(value) end,
										getName   = function(value) local _, names, _ = self:batteries(value, self.batteriesWithRoom) return names end,
										getRoom   = function(value) local _, _, rooms = self:batteries(value, self.batteriesWithRoom) return rooms end,
										isBoolean = true,
		},
		dead      = {name = "Dead",
										optimize  = true,
										control   = function(id) return self.options.number.control(id) end,
										getValue  = function(id) return fibaro.getValue(self:findDeviceId(id), "dead") end,
										action    = function(id) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(1, "wakeUpAllDevices", self:findDeviceId(id[i])) end end,
										trigger   = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "dead"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "dead"}, sourceType = "system"}} end,
										isBoolean = true,
		},
		deads     = {name = "Deads",
										optimize  = true,
										getValue  = function() local devices = api.get("/devices?property=[dead,true]&enabled=true") return #devices>0, #devices end,
										action    = function() local devices = api.get("/devices?property=[dead,true]&enabled=true") for _, v in pairs(devices) do fibaro.call(1, "wakeUpAllDevices", v.id) end end,
										getName   = function() return "" end,
										getRoom   = function() return "" end,
										isBoolean = true,
		},
		sceneactivation = {name = "SceneActivation",
										optimize  = true,
										getValue  = function(id, value) return tonumber(fibaro.getValue(self:findDeviceId(id), "sceneActivation")) == tonumber(value) end,
										trigger   = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "sceneActivation"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "sceneActivation"}}} end,
										isBoolean = true,
		},
		fonction  = {name = "Function",
										optimize  = true,
										getValue  = function(func) return func() end,
										action    = function(func) self.forceRefreshValues = true func() end,
										isBoolean = true,
		},
		copyglobal = {name = "CopyGlobal",
										optimize = true,
										control  = function(source, destination) return self.options.global.control({source, destination}) end,
										action   = function(source, destination) fibaro.setGlobalVariable(destination, self:getGlobalValue(source)) end,
		},
		portable  = {name = "Portable",
										action = function(id, message) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findMobileId(id[i]), "sendPush", self:getMessage(message)) end end,
		},
		email     = {name = "Email",
										optimize = true,
										action   = function(id, message, sujet) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findUserId(id[i]), "sendEmail", sujet or ("GEA " .. self.version), self:getMessage(message)) end end,
		},
		currenticon = {name = "CurrentIcon",
										optimize = true,
										control  = function(id) return self.options.number.control(id) end,
										getValue = function(id) return fibaro.getValue(self:findDeviceId(id), "deviceIcon") end,
										action   = function(id, value) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), "setProperty", "deviceIcon", value) end end,
		},
		scenario  = {name = "Scenario",
										keepValues = true,
										--control = function(id) return type(fibaro:isSceneEnabled(self:findScenarioId(id))) ~= nil end,
										control    = function(id) return api.get("/scenes/"..self:findScenarioId(id)) and true or false end, -- Lazer
										--action=function(id, args) if (type(id) ~= "table") then id = {id} end
											--for i=1, #id do
												--if (type(args) == "table") then
													----print("Arguments : ", json.encode(args))
													----local arguments = json.encode(args)
													----print("GetMessage : ", self:getMessage(arguments))
													--fibaro.startScene(self:findScenarioId(id[i]), args)
												--else
													--fibaro:startScene(self:findScenarioId(id[i]))
												--end
											--end
										--end
										action = function(id)
											if type(id) ~= "table" then id = {id} end
											for i=1, #id do
												fibaro.scene("execute", {self:findScenarioId(id[i])})
											end
										end, -- Lazer
		},
		kill      = {name = "Kill",
										optimize = true,
										control  = function(id) return self.options.scenario.control(id) end,
										--action=function(id) if (type(id) ~= "table") then id = {id} end for i=1, #id do fibaro:killScenes(self:findScenarioId(id[i])) end end
										action   = function(id) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.scene("kill", {self:findScenarioId(id[i])}) end end, -- Lazer
		},
		picture   = {name = "Picture",
										optimize   = true,
										keepValues = true,
										action     = function(id, destinataire) if type(id) ~= "table" then id = {id} end if type(destinataire) ~= "table" then destinataire = {destinataire} end for i=1, #id do for j =1, #destinataire do fibaro.call(self:findDeviceId(id[i]), "sendPhotoToUser", destinataire[j]) end end end
		},
		picturetoemail = {name = "PictureToEmail",
										optimize   = true,
										keepValues = true,
										action     = function(id, destinataire) if type(id) ~= "table" then id = {id} end if type(destinataire) ~= "table" then destinataire = {destinataire} end for i=1, #id do for j =1, #destinataire do fibaro.call(self:findDeviceId(id[i]), "sendPhotoToEmail", destinataire[j]) end end end
		},
		open      = {name = "Open",
										optimize = true,
										math     = true,
										depends  = {"value"},
										control  = function(id) return self.options.number.control(id) end,
										getValue = function(id) return math.abs(-100+tonumber(self.options.value.getValue(self:findDeviceId(id)))) end,
										action   = function(id, value) if not id then id = self.currentMainId end if type(id) ~= "table" then id = {id} end if not value then value = 100 end for i=1, #id do self.options.value.action(self:findDeviceId(id[i]), value) end  end,
										trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value"}, sourceType = "system"}} end,
		},
		close     = {name = "Close",
										optimize = true,
										math     = true,
										depends  = {"value"},
										control  = function(id) return self.options.number.control(id) end,
										getValue = function(id) return self.options.value.getValue(self:findDeviceId(id)) end,
										action   = function(id, value) if not id then id = self.currentMainId end if type(id) ~= "table" then id = {id} end if not value then value = 100 end for i=1, #id do self.options.value.action(self:findDeviceId(id[i]), math.abs(-100+value)) end end,
										trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value"}, sourceType = "system"}} end,
		},
		stop      = {name = "Stop",
										optimize = true,
										control  = function(id) return self.options.number.control(id) end,
										action   = function(id) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), "stop") end end,
		},
		apipost   = {name = "ApiPost",
										optimize = true,
										getValue = function(url, data) __assert_type(data, "table") return api.post(url, data) end,
										action   = function(url, data) __assert_type(data, "table") api.post(url, data) end,
		},
		apiput    = {name = "ApiPost",
										optimize = true,
										getValue = function(url, data) __assert_type(data, "table") return api.put(url, data) end,
										action   = function(url, data) __assert_type(data, "table") api.put(url, data) end,
		},
		apiget    = {name = "ApiGet",
										optimize = true,
										math     = true,
										getValue = function(url) return api.get(url) end,
										action   = function(url) api.get(url) end,
		},
		program   = {name = "Program",
										optimize = true,
										math     = true,
										getValue = function(id) return fibaro.getValue(self:findDeviceId(id), "currentProgram") end,
										action   = function(id, prog) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), "startProgram", prog) end end,
		},
--[[
		thermostatlevel = {name = "ThermostatLevel",
										optimize = true,
										control  = function(id) return self.options.number.control(id) end,
										getValue = function(id) return fibaro.getValue(self:findDeviceId(id), "value") end,
										action   = function(id, value) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), "setTargetLevel", tostring(self:incdec(value, self.options.thermostatlevel.getValue(self:findDeviceId(id[i]))))) end end,
		},
		thermostattime = {name = "ThermostatTime",
										optimize = true,
										control  = function(id) return self.options.thermostatlevel.control(id) end,
										getValue = function(id) return fibaro.getValue(self:findDeviceId(id), "timestamp") end,
										action   = function(id, value) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), "setTime", tonumber(os.time()) + value) end end,
		},
		setmode   = {name = "setMode",
										optimize = true,
										control  = function(id) return self.options.number.control(id) end,
										action   = function(id, mode) return fibaro.call(self:findDeviceId(id), "setMode", mode) end,
		},
		setthermostatsetpoint = {name = "setThermostatSetpoint",
										optimize = true,
										control  = function(id) return self.options.number.control(id) end,
										action   = function(id, mode, value) return fibaro.call(self:findDeviceId(id), "setThermostatSetpoint", mode, value) end,
		},
--]]
		thermostatmode = {name = "ThermostatMode", -- Lazer
										optimize = true,
										control  = function(id) return self.options.number.control(id) end,
										getValue = function(id) return fibaro.getValue(self:findDeviceId(id), "thermostatMode") end,
										action   = function(id, mode) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), "setThermostatMode", mode) end end,
										trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "thermostatMode"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "thermostatMode"}, sourceType = "system"}} end,
		},
		thermostatfanmode = {name = "ThermostatFanMode", -- Lazer
										optimize = true,
										control  = function(id) return self.options.number.control(id) end,
										getValue = function(id) return fibaro.getValue(self:findDeviceId(id), "thermostatFanMode") end,
										action   = function(id, fan) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), "setThermostatFanMode", fan) end end,
										trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "thermostatFanMode"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "thermostatFanMode"}, sourceType = "system"}} end,
		},
		coolingthermostatsetpoint = {name = "CoolingThermostatSetpoint", -- Lazer
										optimize = true,
										math     = true,
										control  = function(id) return self.options.number.control(id) end,
										getValue = function(id) return fibaro.getValue(self:findDeviceId(id), "coolingThermostatSetpoint") end,
										action   = function(id, value) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), "setCoolingThermostatSetpoint", self:incdec(value, self.options.coolingthermostatsetpoint.getValue(self:findDeviceId(id[i])))) end end,
										trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "coolingThermostatSetpoint"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "coolingThermostatSetpoint"}, sourceType = "system"}} end,
		},
		heatingthermostatsetpoint = {name = "HeatingThermostatSetpoint", -- Lazer
										optimize = true,
										math     = true,
										control  = function(id) return self.options.number.control(id) end,
										getValue = function(id) return fibaro.getValue(self:findDeviceId(id), "heatingThermostatSetpoint") end,
										action   = function(id, value) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), "setHeatingThermostatSetpoint", self:incdec(value, self.options.heatingthermostatsetpoint.getValue(self:findDeviceId(id[i])))) end end,
										trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "heatingThermostatSetpoint"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "heatingThermostatSetpoint"}, sourceType = "system"}} end,
		},
		--  "SetThermostat" : {"SetThermostat", <id_thermostat>, <mode>, <valeur>, <fan>}
		setthermostat = {name = "SetThermostat",
										optimize = true,
										depends  = {"thermostatmode", "thermostatfanmode", "coolingthermostatsetpoint", "heatingthermostatsetpoint"},
										control  = function(id) return self.options.number.control(id) end,
										action   = function(id, mode, value, fan)
											self.options.thermostatmode.action(id, mode)
											if mode == "Off" then
												return
											end
											if mode == "Heat" then
												self.options.heatingthermostatsetpoint.action(id, value)
											elseif mode == "Cool" then
												self.options.coolingthermostatsetpoint.action(id, value)
											elseif mode == "Auto" then
												self.options.heatingthermostatsetpoint.action(id, value)
												self.options.coolingthermostatsetpoint.action(id, value)
											elseif mode == "Resume" then
											elseif mode == "Fan" then
											elseif mode == "Dry" then
											end
											if fan then
												self.options.thermostatfanmode.action(id, fan)
											end
										end,
		},
		ask       = {name = "Ask",
										optimize = true,
										action   = function(id, message, scene)
											if type(id) ~= "table" then id = {id} end
											if not scene then scene = message message = self:getMessage() end
											api.post('/mobile/push', {["mobileDevices"]=id,["message"]=self:getMessage(message),["title"]='HC3 Fibaro',["category"]='YES_NO',["data"]={["sceneId"]=scene}})
										end,
		},
		repe_t    = {name = "Repeat",
										getValue = function() return true end,
		},
		notstart  = {name = "NotStart",
										optimize = true,
										getValue = function() return true end,
		},
		inverse   = {name = "Inverse",
										optimize = true,
										getValue = function() return true end,
		},
		maxtime   = {name = "Maxtime",
										getValue = function(taskid) return self.globalvalue:match("|M_" .. taskid .. "{(%d+)}|") end,
										action   = function(taskid, number) if number == 0 then self.options.stoptask.action(taskid) else self.globalvalue = self.globalvalue:gsub("|M_" .. taskid .. "{(%d+)}|", "") .. "|M_" .. taskid .. "{"..number.."}|" end end,
		},
		restarttask = {name = "RestartTask",
										getValue = function(taskid) return self.globalvalue:find("|R_" .. taskid.."|") end,
										action   = function(taskid) if type(taskid) ~= "table" then taskid = {taskid} end for i=1, #taskid do if taskid[i]=="self" then taskid[i]=self.currentEntry.id end self.globalvalue = self.globalvalue:gsub("|R_" .. taskid[i].."|", ""):gsub("|M_" .. taskid[i] .. "{(%d+)}|", ""):gsub("|S_" .. taskid[i].."|", "") .. "|R_" .. taskid[i].."|" end end,
		},
		stoptask  = {name = "StopTask",
										getValue = function(taskid) return self.globalvalue:find("|S_" .. taskid) end,
										action   = function(taskid) if type(taskid) ~= "table" then taskid = {taskid} end for i=1, #taskid do if taskid[i]=="self" then taskid[i]=self.currentEntry.id end self.globalvalue = self.globalvalue:gsub("|S_" .. taskid[i].."|", ""):gsub("|M_" .. taskid[i] .. "{(%d+)}|", ""):gsub("|R_" .. taskid[i].."|", "") .. "|S_" .. taskid[i].."|" end end,
		},
		depend    = {name = "Depend",
										optimize  = true,
										control   = function(entryId) return type(self:findEntry(entryId)) ~= "nil" end,
										getValue  = function(entryId) return not self.currentEntry.isWaiting[entryId] end,
										isBoolean = true,
		},
		test      = {name = "Test",
										optimize = true,
										getValue = function(name1, name2, name3) print("test getValue() ") return name1 .. name2 .. name3, name1 end,
										action   = function(name) print("test action() " .. self:getMessage(name)) end,
		},
		sleep     = {name = "Sleep",
										control    = function(duree, option) return type(duree)=="number" and type(self:getOption(option, true)~="nil") end,
										keepValues = true,
										action     = function(duree, option) local o = self:getOption(option) if duree and o then setTimeout(function() self.currentAction.name = o.name o.action(true) end, self:getDuree(duree)*1000) end end,
		},
		variablecache = {name = "VariableCache",
										optimize = true,
										math     = true,
										control  = function() return self.currentEntry.getDuration() >= 0, self.trad.varCacheInstant end,
										getValue = function(var) return self.variables[var] end,
										action   = function(var, value) self.variables[var] = self:getMessage(self:incdec(value, self.variables[var])) end,
		},
		enablescenario = {name = "EnableScenario",
										optimize  = true,
										control   = function(id) return self.options.scenario.control(id) end,
										--getValue = function(id) return fibaro:isSceneEnabled(self:findScenarioId(id)) end,
										getValue  = function(id) return api.get("/scenes/"..self:findScenarioId(id)).enabled end, -- Lazer
										--action=function(id) if (type(id) ~= "table") then id = {id} end for i=1, #id do fibaro:setSceneEnabled(self:findScenarioId(id[i]), true) end end
										action    = function(id) -- Lazer
											if type(id) ~= "table" then id = {id} end
											for i=1, #id do
												local url = "/scenes/"..self:findScenarioId(id[i])
												local scene = api.get(url)
												scene.enabled = true
												api.put(url, scene)
											end
										end,
										isBoolean = true,
		},
		disablescenario = {name = "DisableScenario",
										optimize  = true,
										control   = function(id) return self.options.scenario.control(id) end,
										--getValue = function(id) return not fibaro:isSceneEnabled(self:findScenarioId(id)) end,
										getValue  = function(id) return not api.get("/scenes/"..self:findScenarioId(id)).enabled end, -- Lazer
										--action=function(id) if (type(id) ~= "table") then id = {id} end for i=1, #id do fibaro:setSceneEnabled(self:findScenarioId(id[i]), false) end end
										action    = function(id) -- Lazer
											if type(id) ~= "table" then id = {id} end
											for i=1, #id do
												local url = "/scenes/"..self:findScenarioId(id[i])
												local scene = api.get(url)
												scene.enabled = false
												api.put(url, scene)
											end
										end,
										isBoolean = true,
		},
		setrunmodescenario = {name = "SetRunModeScenario", -- Lazer
										optimize = true,
										control  = function(id) return self.options.scenario.control(id) end,
										getValue = function(id) return api.get("/scenes/"..self:findScenarioId(id)).mode end,
										action   = function(id, runmode)
											if type(id) ~= "table" then id = {id} end
											for i=1, #id do
												local url = "/scenes/"..self:findScenarioId(id[i])
												local scene = api.get(url)
												scene.mode = runmode
												api.put(url, scene)
											end
										end,
		},
--[[
    setrunconfigscenario = {name="SetrunConfigScenario",
                    optimize = true,
                    control = function(id) return self.options.scenario.control(id) end,
                    getValue = function(id) return fibaro:getSceneRunConfig(self:findScenarioId(id)) end,
                    action=function(id, runconfig) if (type(id) ~= "table") then id = {id} end for i=1, #id do fibaro:setSceneRunConfig(self:findScenarioId(id[i]), runconfig) end end
                },
--]]								
		countscenes = {name = "CountScenes",
										optimize = true,
										control  = function(id) return self.options.scenario.control(id) end,
										getValue = function(id) if api.get("/scenes/"..self:findScenarioId(id)).isRunning == true then return 1 else return 0 end end,
		},
		runningscene = {name = "RunningScene",
										optimize  = true,
										control   = function(id) return self.options.scenario.control(id) end,
										getValue  = function(id) return api.get("/scenes/"..self:findScenarioId(id)).isRunning end,
										isBoolean = true,
		},
		popup     = {name = "Popup",
										optimize = true,
										action   = function(typepopup, titlepopup, msgpopup, sceneID)
											local content = tools.tostring(self.trad.popupinfo)
											local scene = sceneID or 0
											if typepopup=="Success" then content = tools.tostring(self.trad.popupsuccess) elseif typepopup=="Warning" then content = tools.tostring(self.trad.popupwarning) elseif typepopup=="Critical" then content = tools.tostring(self.trad.popupcritical) end
											local boutons = {{caption=self.trad.quit,sceneId=0}}
											if scene ~= 0 then
												table.insert(boutons, 1, {caption=self.trad.execute, sceneId=scene})
											end
											HomeCenter.PopupService.publish({title="GEA - "..titlepopup,subtitle = os.date(self.trad.date_format .. " - " .. self.trad.hour_format),contentTitle = tools.tostring(content),contentBody=self:getMessage(msgpopup),img="..img/topDashboard/info.png",type=tools.tostring(typepopup),buttons=boutons})
										end,
		},
    --debugmessage = {name="DebugMessage",
                    --optimize = true,
                    --control = function(id) return self.options.number.control(id) end,
                    --action=function(id, elementid, msgdebug, typedebug) if (type(id) ~= "table") then id = {id} end for i=1, #id do fibaro.call(id[i], "addDebugMessage", elementid, self:getMessage(msgdebug), typedebug or debug) end end
                --}, -- /api/debugMessages
		filters   = {name = "Filters",
										optimize = true,
										--control = function(id) return self.options.number.control(id) end,
										action   = function(typefilter,choicefilter) if typefilter:lower() == "lights" then for _,v in ipairs(fibaro.getDevicesID({properties = {isLight = true}})) do fibaro.call(v, choicefilter) end elseif typefilter:lower() =="blinds" then for _,v in ipairs(fibaro.getDevicesID({type = tools.tostring("com.fibaro.FGRM222")})) do fibaro.call(v, choicefilter) end end end,
		},
		rgb       = {name = "RGB",
										optimize = true,
										control  = function(id) return self.options.number.control(id) end,
										action   = function(id, r, g, b, w) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findDeviceId(id[i]), "setColor", r or 0, g or 0, b or 0, w or 0) end end,
		},
		centralsceneevent = {name = "CentralSceneEvent",
										optimize  = true,
										control   = function(id, key, attribute)
											if self.currentEntry.getDuration() > -1 then return false, self.trad.central_instant end
											return self.options.number.control(id) and type(key)~="nil" and type(attribute)~="nil", self.trad.central_missing
										end,
										--getValue = function(id, key, attribute) return (self.source.event.data.deviceId==tonumber(self:findDeviceId(id)) and tostring(self.source.event.data.keyId)==tostring(key) and tostring(self.source.event.data.keyAttribute)==tostring(attribute)) end,
										getValue  = function(id, key, attribute) return self.source.id==tonumber(self:findDeviceId(id)) and tostring(self.source.value.keyId)==tostring(key) and tostring(self.source.value.keyAttribute)==tostring(attribute) end,
										trigger   = function(id, key, attribute) return {event = {type = "device", id = self:findDeviceId(id), property = "centralSceneEvent", value = {keyId = key, keyAttribute = attribute}}, filter = {type = "CentralSceneEvent", data = {id = self:findDeviceId(id), keyId = key, keyAttribute = attribute}, sourceType = "system"}} end,
										isBoolean = true,
		},
		frequency = {name = "Frequency",
										optimize  = true,
										getValue  = function(freqday, freqnumber) return self:getFrequency(freqday,freqnumber) end,
										isBoolean = true,
		},
		-- TODO : ne fonctionne plus sur firmware 5.050.13 => https://www.domotique-fibaro.fr/topic/14130-hc3-commande-shutdown/
		reboothc3 = {name = "RebootHC3",
										optimize = true,
										--action = function() fibaro.homeCenter.systemService.reboot() end
										action   = function() api.post("/service/reboot") end,
										--action = function() print(api.post("/service/reboot")) end
										--[[
										action = function()
											local http = net.HTTPClient()
											http:request("http://localhost/api/service/reboot", {
												success = function(response)
													tools.info("success() : " .. json.encode(response))
												end,
												error = function(err)
													tools.error("error() : " .. json.encode(err))
												end,
												options = {
													method = "POST",
													headers = {
														["X-Fibaro-Version"] = "2",
														["Content-Type"] = "application/json",
													},
													data = "",
												}
											})
										end
										--]]
		},
		suspendhc3 = {name = "SuspendHC3",
										optimize = true,
										--action = function() fibaro.homeCenter.systemService.suspend() end
										--action = function() api.post("/service/suspend") end
										action   = function()
											local http = net.HTTPClient()
											http:request("http://localhost/api/service/suspend", {
												success = function(response)
													tools.info("success() : " .. json.encode(response))
												end,
												error = function(err)
													tools.error("error() : " .. json.encode(err))
												end,
												options = {
													method = "POST",
													headers = {["X-Fibaro-Version"] = "2"}
												}
											})
										end,
		},
		shutdownhc3 = {name = "ShutdownHC3",
										optimize = true,
										--action = function() fibaro.homeCenter.systemService.shutdown() end
										--action = function() api.post("/service/shutdown") end
										action   = function()
											local http = net.HTTPClient()
											http:request("http://localhost/api/service/shutdown", {
												success = function(response)
													tools.info("success() : " .. json.encode(response))
												end,
												error = function(err)
													tools.error("error() : " .. json.encode(err))
												end,
												options = {
													method = "POST",
													headers = {["X-Fibaro-Version"] = "2"}
												}
											})
										end,
		},
--[[
		alarm     = {name = "Alarm", -- TODO avec le QuickApp à la place du VD
										optimize = true,
										control = function(id) return self.options.number.control(id) end,
										getValue = function(id)
											if os.date("%H:%M", self.runAt) == fibaro.getValue(self:findDeviceId(id), "ui.lblAlarme.value") then
												local days = fibaro.getValue(self:findDeviceId(id), "ui.lblJours.value")
												days = days:lower()
												selected = tools.split(days, " ")
												for i = 1, #selected do
													for j = 1, #self.trad.week_short do
														if self.trad.week_short[j] == selected[i] then
															if self.traduction.en.week[j]:lower() == os.date("%A"):lower() then
																return true
															end
														end
													end
												end
											end
											return false
										end,
		},
--]]
		info      = {name = "Info",
										optimize = true,
										math     = true,
										control  = function(property) if type(api.get("/settings/info")[property])=="nil" then return false, string.format(self.trad.property_missing, property) else return true end end,
										getValue = function(property) return api.get("/settings/info")[property] end,
		},
--[[
    pluginscenario = {name = "PluginScenario",
										control = function() if (self.currentAction and self.plugins[self.currentAction.name]) or (self.currentCondition and self.plugins[self.currentCondition.name]) then return true else return false, self.trad.plugin_not_found end end,
										getValue = function(...)
											local line = self.currentEntry.id.."@"..self.currentCondition.option_id
											local args = {...}
											local params = {{geaid = __fibaroSceneId}, {gealine = line}, {geamode = "value"}}
											for i, v in ipairs(args) do table.insert(params, {["param"..i] = self:getMessage(v)}) end
											local id = self.plugins[self.currentCondition.name]
											fibaro:startScene(id, params) -- fibaro.scene("execute", id)
											return self:waitWithTimeout(function()
												local vgplugins = self:getGlobalValue(self.pluginsvariables)
												if vgplugins and vgplugins ~= "" and vgplugins ~= "NaN" then self.plugins = json.decode(vgplugins) end
												if self.plugins.retour and self.plugins.retour[line] then return true, self.plugins.retour[line] end
											end, self.pluginretry, self.pluginmax)
										end,
										action = function(...)
											local args = {...}
											local params = {{geaid = __fibaroSceneId}, {gealine = self.currentEntry.id.."@"..self.currentAction.option_id}, {geamode = "action"}}
											for i, v in ipairs(args) do table.insert(params, {["param"..i] = self:getMessage(v)}) end
											local id = self.plugins[self.currentAction.name]
											fibaro:startScene(id, params) -- fibaro.scene("execute", id)
										end
    			},
--]]
		doorlock  = {name = "DoorLock",
										optimize  = true,
										depends   = {"value"},
										control   = function(id) return self.options.number.control(id) end,
										getValue  = function(id) self.options.value.getValue(id) end,
										action    = function(id, value) if not id then id = self.currentMainId end if type(id) ~= "table" then id = {id} end for i=1, #id do if value == tools.tostring("secure") then fibaro.call(self:findDeviceId(id[i]),"secure") else fibaro.call(self:findDeviceId(id[i]),"unsecure") end end end,
										isBoolean = true,
		},
		o_r       = {name = "Or",
										optimize   = true,
										keepValues = true,
										control    = function(...) local args = {...} for i = 1, #args do if type(self:getOption(args[i]))=="nil" then return false end end return true end,
										getValue   = function(...) local args = {...} for i = 1, #args do if self:getOption(args[i]).check() then return true end end return false end,
										getName    = function(...)
											local args = {...}
											local name = ""
											for i = 1, #args do if self:getOption(args[i]).check() then name = name .. " " .. self:getOption(args[i]).getModuleName() end end
											return tools.trim(name)
										end,
										isBoolean  = true,
		},
		xor       = {name = "XOr",
										optimize   = true,
										keepValues = true,
										control    = function(...) local args = {...} for i = 1, #args do if type(self:getOption(args[i]))=="nil" then return false end end return true end,
										getValue   = function(...) local args = {...} local nb = 0 for i = 1, #args do if self:getOption(args[i]).check() then nb = nb+1 end end return nb == 1 end,
										getName    = function(...)
											local args = {...}
											local name = ""
											for i = 1, #args do if self:getOption(args[i]).check() then name = name .. " " .. self:getOption(args[i]).getModuleName() end end
											return tools.trim(name)
										end,
										isBoolean  = true,
		},
		hue       = {name = "Hue",
										optimize = true,
										math     = true,
										control  = function(id) return self.options.number.control(id) end,
										getValue = function(id, property) if not id then id = self.currentMainId end return fibaro.getValue(self:findDeviceId(id), property) end,
										getHubParam=function(id)
											local device = api.get("/devices/"..self:findDeviceId(id))
											local lightid = device.properties.lightId
											if device.parentId > 0 then device = api.get("/devices/"..device.parentId) end
											return lightid, device.properties.ip, device.properties.userName
										end,
										action   = function(id, property, value) if type(id) ~= "table" then id = {id} end
											for i=1, #id do
												local lightid, ip, username = self.options.hue.getHubParam(self:findDeviceId(id[i]))
												local datas = "{\""..property.."\":"..tools.iif(type(value)=="boolean", tostring(value), value).."}"
												local http = net.HTTPClient()
												http:request("http://"..ip.."/api/"..username.."/lights/"..lightid.."/state",  { options =  { method =  "PUT", data = datas }, success = function(response) end, error  = function(err) tools.error(err, "red") end })
											end
										end,
		},
		transpose = {name = "Transpose",
										getValue  = function(table1, table2, value) return self:translate(value, table1, table2) end,
										action    = function(table1, table2, value) return self:translate(value, table1, table2) end,
										isBoolean = true,
		},
		roomlights = {name = "RoomLights",
										optimize = true,
										action   = function(roomName, action)
											local rooms = api.get("/rooms")
											for _, room in pairs(rooms) do
												if room.name:lower() == roomName:lower() then
													for _, device in pairs(api.get("/devices?type=com.fibaro.philipsHueLight&roomID="..room.id)) do fibaro.call(device.id, action) end
													for _, device in pairs(api.get("/devices?property=[isLight,true]&roomID="..room.id)) do fibaro.call(device.id, action) end
												end
											end
										end,
		},
		sectionlights = {name = "SectionLights",
										optimize = true,
										depends  = {"roomlights"},
										action   = function(sectionName, action)
											local sections = api.get("/sections")
											for _, section in pairs(sections) do
												if section.name:lower() == sectionName:lower() then
													for _, room in pairs(api.get("/rooms")) do
														if room.sectionID == section.id then self.options.roomlights.action(room.name, action) end
													end
												end
											end
										end,
		},
		onoff     = {name = "OnOff",
										optimize  = true,
										depends   = {"transpose"},
										getValue  = function(id) return self:getOption({"Transpose", {true, false}, {"ON", "OFF"}, {"TurnOn", id}}).getValue() end,
										action    = function(id) self:getOption({"Switch", id}).action() end,
										isBoolean = true,
		},
		result    = {name = "Result", math = true, getValue = function(position) if not position then position = 1 end return self.currentEntry.conditions[position].lastDisplayValue end },
		name      = {name = "Name", getValue = function(position) if not position then position = 1 end return self.currentEntry.conditions[position].getModuleName() end },
		room      = {name = "Room", getValue = function(position) if not position then position = 1 end return self.currentEntry.conditions[position].getModuleRoom() end },
		runs      = {name = "Runs", math = true, getValue = function() return self.nbRun end },
		seconds   = {name = "Seconds", math = true, getValue = function() return self.checkEvery end },
		duration  = {name = "Duration", math = true, getValue = function() local d, _ = self:getDureeInString(os.difftime(self.runAt, self.currentEntry.firstvalid)) return d end },
		durationfull = {name = "DurationFull", getValue = function() local _, d = self:getDureeInString(os.difftime(self.runAt, self.currentEntry.firstvalid)) return d end },
		sunrise   = {name = "Sunrise", getValue = function() return fibaro.getValue(1, "sunriseHour"):gsub(":", " " .. self.trad.hour .. " ") end },
		sunset    = {name = "Sunset", getValue = function() return fibaro.getValue(1, "sunsetHour"):gsub(":", " " .. self.trad.hour .. " ") end },
		date      = {name = "Date", getValue = function() return os.date(self.trad.date_format, self.runAt) end },
		trigger   = {name = "Trigger",
										getValue = function()
											--tools.debug('"Trigger" : options.trigger.getValue() self.source.type='..tostring(self.source.type)..' self.source.propertyName='..tostring(self.source.propertyName)..' self.source.deviceID='..tostring(self.source.deviceID)) -- DEBUG
											if self.source.type == "autostart" then
												return "autostart"
											elseif self.source.type == "device" then
												if self.source.propertyName then
													return "Device[" .. self.source.id .. " - " .. self.source.propertyName .. "]"
												end
												return "Device[" .. self.source.id .. "]"
											elseif self.source.type == "global-variable" then
												return "Global[" .. self.source.name .. "]"
											elseif self.source.type == "alarm" then
												return "Alarm[" .. self.source.id .. "]"
											elseif self.source.type == "profile" then
												return "Profile[" .. self.source.id .. "]"
											end
											return "manual"
										end,
		},
		datefull  = {name = "DateFull",
										getValue = function()
											local jour = tonumber(os.date("%w", self.runAt))
											if jour == 0 then jour = 6 else jour = jour-1 end
											return self.trad.week[jour+1] .. " " .. os.date("%d", self.runAt).. " " .. self.trad.months[tonumber(os.date("%m", self.runAt))].. " " .. os.date("%Y", self.runAt)
										end,
		},
		translate = {name = "Translate",
										getValue = function(key, word)
											word = self:getMessage(word)
											return self:translatetrad(tools.trim(key), tools.trim(word))
										end,
		},
		sonosmp3  = {name = "Sonos MP3",
										action = function(vd_id, button_id, filepath, volume)
											if not volume then volume = 30 end
											local _f = fibaro
											local _x ={root="x_sonos_object",load=function(b)local c=_f:getGlobalValue(b.root)if string.len(c)>0 then local d=json.decode(c)if d and type(d)=="table"then return d else _f:debug("Unable to process data, check variable")end else _f:debug("No data found!")end end,set=function(b,e,d)local f=b:load()if f[e]then for g,h in pairs(d)do f[e][g]=h end else f[e]=d end;_f:setGlobal(b.root,json.encode(f))end,get=function(b,e)local f=b:load()if f and type(f)=="table"then for g,h in pairs(f)do if tostring(g)==tostring(e or"")then return h end end end;return nil end}
											_x:set(tostring(self:findDeviceId(vd_id)), { stream = {stream=filepath, source="local", duration="auto", volume=volume} })
											_f:call(self:findDeviceId(vd_id), "pressButton", button_id)
										end,
		},
		sonostts  = {name = "Sonos TTS",
										action = function(vd_id, button_id, message, volume)
											local message = self:getMessage(message)
											if not volume then volume = 30 end
											local _f = fibaro
											local _x ={root="x_sonos_object",load=function(b)local c=_f:getGlobalValue(b.root)if string.len(c)>0 then local d=json.decode(c)if d and type(d)=="table"then return d else _f:debug("Unable to process data, check variable")end else _f:debug("No data found!")end end,set=function(b,e,d)local f=b:load()if f[e]then for g,h in pairs(d)do f[e][g]=h end else f[e]=d end;_f:setGlobal(b.root,json.encode(f))end,get=function(b,e)local f=b:load()if f and type(f)=="table"then for g,h in pairs(f)do if tostring(g)==tostring(e or"")then return h end end end;return nil end}
											_x:set(tostring(self:findDeviceId(vd_id)), { tts = {message=message, duration='auto', language=self.trad.locale, volume=volume} })
											_f:call(self:findDeviceId(vd_id), "pressButton", button_id)
										end,
		},
		jsondecodefromglobal = {name = "JSON Decode from Global",
										optimize = true,
										math     = true,
										getValue = function(vg, property) return self:decode(self:getGlobalValue(vg), property) end,
		},
		jsondecodefromlabel = {name = "JSON Decode from Label",
										optimize = true,
										math     = true,
										getValue = function(id, label, property) return self:decode(tools.getView(id, label, "text"), property) end,
		},
		tempext    = {name = "Temp. Ext.", math = true, getValue = function() return fibaro.getValue(3, "Temperature") end, },
		tempexttts = {name = "Temp. Ext. TTS", getValue = function() local value = fibaro.getValue(3, "Temperature") if value:find("%.") then return value:gsub("%.", " degrés ") end return value .. " degrés" end, },
		monthly   = {name = "monthly",
										getValue = function(day)
											day = day or ""
											day = tostring(day):lower()
											if day == "" or day == "begin" or day == "first" then
												day = 1;
											elseif day == "end" or day == "last" or day == "31" then
												local now = os.date("*t", self.runAt)
												local tomorrow = os.time{year=now.year, month=now.month, day=now.day+1}
												return now.month ~= os.date("*t", tomorrow).month
											end
											if tools.isNumber(day) then
												return tonumber(os.date("%d", self.runAt)) == tonumber(day)
											end
											day = self:translate(day, self.trad.week, self.traduction.en.week)
											local n,d = os.date("%d %A", self.runAt):match("(%d+).?(%w+)")
											return ( tonumber(n) < 8 and d:lower() == day )
										end,
		},
		slider    = {name = "Slider",
										math     = true,
										optimize = true,
										--depends = {"label"},
										control  = function(id, property) if not self.options.checkslider.getValue(id, property) then return false, string.format(self.trad.slider_missing, id, property) else return true end end,
										--getValue = function(id, property) return self.options.label.getValue(id, property) end,
										getValue = function(id, property) return tools.getView(self:findDeviceId(id), property, "value") end, -- Lazer
										--action=function(id, property, value)
											--if (type(id) ~= "table") then id = {id} end
											--for i=1, #id do
												--property = self:findButtonId(self:findDeviceId(id[i]), property)
												--fibaro.call(id[i], "setSlider", property, self:incdec(self:getMessage(value), self.options.label.getValue(id[i], property)))
											--end
										--end
										action   = function(id, property, value) -- Lazer
											if type(id) ~= "table" then id = {id} end
											for i=1, #id do
												--fibaro.call(self:findDeviceId(id[i]), "updateView", property, "value", tostring(value)) -- Ne déclenche pas la fonction associée au slider
												local qa = api.get("/devices/"..self:findDeviceId(id[i]).."/properties/uiCallbacks")
												for j=1, #(qa and qa.value or {}) do
													if qa.value[j].name == property then
														fibaro.call(self:findDeviceId(id[i]), qa.value[j].callback, {elementName = property, deviceId = self:findDeviceId(id[i]), eventType = qa.value[j].eventType, values = {value}})
														break
													end
												end
											end
										end,
										trigger = function(id, property) return {event = {type = "device", id = self:findDeviceId(id), propertyName = "value", componentName = property}, filter = {type = "PluginChangedViewEvent", data = {deviceId = self:findDeviceId(id), propertyName = "value", componentName = property}}} end,
		},
		polling   = {name = "Polling",
										optimize = true,
										control  = function(id) return self.options.number.control(id) end,
										action   = function(id) if type(id) ~= "table" then id = {id} end for i=1, #id do api.post("/devices/"..id[i].."/action/poll") end end,
		},
		ledbrightness = {name = "LedBrightness",
										optimize = true,
										--getValue = function()  return fibaro:getLedBrightness() end,
										getValue = function() return api.get("/settings/led").brightness end, -- Lazer
										--action=function(level) fibaro:setLedBrightness(tonumber(level)) end
										action   = function(level) api.put("/settings/led", {brightness = tonumber(level)}) end, -- Lazer
		},
		devicestate = {name = "DeviceState",
										optimize = true,
										getValue = function(id)
											local device = api.get("/devices/"..self:findDeviceId(id))
											if device.parentId > 1 then device = api.get("/devices/"..device.parentId) end
											return device.properties.deviceState
										end,
		},
		neighborlist = {name = "NeighborList",
										optimize  = true,
										control   = function(id) return self.options.number.control(id) end,
										ids       = "",
										getValue  = function(id)
											local device = api.get("/devices/"..self:findDeviceId(id))
											if device.parentId > 1 then device = api.get("/devices/"..device.parentId) end
											self.options.neighborlist.ids = device.properties.neighborList
											return json.encode(device.properties.neighborList)
										end,
										getName   = function() return self:getName(self.options.neighborlist.ids, self.showRoomNames) end,
										--isBoolean = true,
		},
		lastworkingroute = {name = "LastWorkingRoute",
										optimize  = true,
										control   = function(id) return self.options.number.control(id) end,
										ids       = "",
										getValue  = function(id)
											local device = api.get("/devices/"..self:findDeviceId(id))
											if device.parentId > 1 then device = api.get("/devices/"..device.parentId) end
											self.options.lastworkingroute.ids = device.properties.lastWorkingRoute
											return json.encode(device.properties.lastWorkingRoute)
										end,
										getName   = function() return self:getName(self.options.lastworkingroute.ids, self.showRoomNames) end,
										--isBoolean = true,
		},
		checkvg   = {name = "CheckVG",
										getValue  = function(name)
											if not self.vglist then
												self.vglist = {}
												for _, vg in pairs(api.get("/globalVariables")) do
													self.vglist[vg.name] = true
												end
											end
											local result = self.vglist[name] or false
											return result
										end,
										isBoolean = true,
		},
		checklabel = {name = "CheckLabel",
										getValue  = function(id, name)
											if not self.qaLabelList then
												local function addLabel(qaid, s)
													if type(s) == 'table' then
														if s.type == "label" then
															--tools.debug("checklabel.getValue() " .. tostring(qaid) .. " = " .. tostring(s.name)) -- DEBUG
															self.qaLabelList[qaid][s.name] = true
														end
														for _,v in pairs(s) do
															local r = addLabel(qaid, v)
															if r then
																return r
															end
														end
													end
												end
												self.qaLabelList = {}
												local qas = api.get("/devices?interface=quickApp&enabled=true")
												for _, qa in pairs(qas) do
													self.qaLabelList[qa.id] = {}
													--tools.debug("checklabel.getValue() addLabel...") -- DEBUG
													addLabel(qa.id, qa.properties.viewLayout["$jason"].body.sections)
												end
											end
											if not self.qaLabelList[self:findDeviceId(id)] then return false, string.format(self.trad.id_missing, self:findDeviceId(id)) end
											--return self.qaLabelList[self:findDeviceId(id)][name:gsub("ui.", ""):gsub(".value", "")] or false
											return self.qaLabelList[self:findDeviceId(id)][name] or false
										end,
										isBoolean = true,
		},
		checkslider = {name = "CheckSlider", -- Lazer
										getValue  = function(id, name)
											if not self.qaSliderList then
												local function addSlider(qaid, s)
													if type(s) == 'table' then
														if s.type == "slider" then
															--tools.debug("checkslider.getValue() " .. tostring(qaid) .. " = " .. tostring(s.name)) -- DEBUG
															self.qaSliderList[qaid][s.name] = true
														end
														for _,v in pairs(s) do
															local r = addSlider(qaid, v)
															if r then
																return r
															end
														end
													end
												end
												self.qaSliderList = {}
												local qas = api.get("/devices?interface=quickApp&enabled=true")
												for _, qa in pairs(qas) do
													self.qaSliderList[qa.id] = {}
													--tools.debug("checkslider.getValue() addSlider...") -- DEBUG
													addSlider(qa.id, qa.properties.viewLayout["$jason"].body.sections)
												end
											end
											if not self.qaSliderList[self:findDeviceId(id)] then return false, string.format(self.trad.id_missing, self:findDeviceId(id)) end
											return self.qaSliderList[self:findDeviceId(id)][name] or false
										end,
										isBoolean = true,
		},
		protection = {name = "Protection", -- par 971jmd
										optimize  = true,
										depends   = {"property"},
										getValue  = function(id)
											local loc = tonumber(fibaro.getValue(self:findDeviceId(id), "localProtectionState")) > 0
											local rf = tonumber(fibaro.getValue(self:findDeviceId(id), "RFProtectionState")) > 0
											local result = "off"
											if loc then result = "local" end
											if rf then result = "rf" end
											if loc and rf then result = "local_rf" end
											return result
										end,
										control   = function(id) if not id then id = self.currentMainId end return self.options.number.control(id) end,
										action    = function(id,typeprotection,mode)
											if type(id) ~= "table" then id = {id} end
											if type(id) ~= "table" then id = {id} end
											local arg1 = "0"
											local arg2 = 0
											if typeprotection:lower() == "local_rf" then
												if mode:lower() == "on" then arg1 = "2" arg2 = 1 end
											elseif typeprotection:lower() == "local" then
												--arg1 = "0" arg2 = 2
												if mode:lower() == "on" then arg1 = "2" arg2 = 0 end
											elseif typeprotection:lower() == "rf" then
												--arg1 = "1" arg2 = 0
												if mode:lower() == "on" then arg1 = "0" arg2 = 1 end
											end
											for i=1, #id do
												fibaro.call(self:findDeviceId(id[i]), "setProtection", arg1, arg2)
											end
										end,
										isBoolean = true,
		},
--[[
    multialarm = {name = "multiAlarm", -- par drboss
                    optimize = true,
                    control = function(id, label)
                      local res, msg = self.options.label.control(id, label.."j")
                      if (msg) then msg = msg:gsub(label.."j", label) end
                      return res, msg
                    end,
                    getValue = function(id, multi_a)
                      if (os.date("%H:%M", self.runAt) == fibaro.getValue(self:findDeviceId(id), "ui."..multi_a.."h.value")) then
                        local days = fibaro.getValue(self:findDeviceId(id), "ui."..multi_a.."j.value")
                        days = days:lower()
                        selected = tools.split(days, " ")
                        for i = 1, #selected do
                          for j = 1, #self.trad.week_short do
                            if (self.trad.week_short[j] == selected[i]) then
                              if (self.traduction.en.week[j]:lower() == os.date("%A"):lower()) then
                                return true
                              end
                            end
                          end
                        end
                      end
                      return false
                    end,
                },
--]]
		stringtoalpha = {name = "StringToAlpha", --- par MAM78
										control  = function(condition, value) if condition == nil then return false, "Check option StringToAlpha condition" else return true end end,
										getValue = function(condition, value) local newvalue = "" for word in string.gmatch(value, "%a+") do newvalue = newvalue..word end return condition == newvalue, newvalue end,
		},
		isevenweek = {name = "Even week",
										optimize  = true,
										getValue  = function() return os.date("%w") % 2 == 0 end,
										isBoolean = true,
		},
		profile = {name = "Profile", -- Lazer
										optimize  = true,
										control   = function(id) return type(id) == "number" and api.get("/profiles/" .. tostring(id)) and true or false, string.format(self.trad.profile_missing, tostring(id)) end,
										getValue  = function() return api.get("/profiles").activeProfile end,
										action    = function(id) api.post("/profiles/activeProfile/" .. tostring(id)) end,
										trigger   = function(id) return {event = {type = "profile", id = id}, filter = {type = "ActiveProfileChangedEvent", data = {newActiveProfile = id}}} end,
		},
	}

	-- Alias - self:copyOption(option, <nouveau nom>)
	--self.options.vd = self:copyOption("virtualdevice", "VD")
	self.options.qa = self:copyOption("quickapp", "QA")
	self.options.scene = self:copyOption("scenario")
	self.options.start = self:copyOption("scenario")
	self.options.startscene = self:copyOption("scenario")
	self.options.killscenario = self:copyOption("kill")
	self.options.killscene = self:copyOption("kill")
	self.options.enablescene = self:copyOption("enablescenario")
	self.options.disablescene = self:copyOption("disablescenario")
	self.options.wakeup = self:copyOption("dead")
	self.options.notdst = self:copyOption("nodst", "Not DST")
	self.options.photo = self:copyOption("picture", "Photo")
	self.options.phototomail = self:copyOption("picturetoemail", "PhotoToMail")
	self.options.startprogram = self:copyOption("program", "startProgram")
	self.options.push = self:copyOption("portable", "Push")
	self.options.power = self:copyOption("sensor", "Power")
	--self.options.pressbutton = self:copyOption("virtualdevice", "PressButton")
	self.options.slide = self:copyOption("value2", "Slide")
	self.options.orientation = self:copyOption("value2", "Orientation")
	self.options.issceneenabled = self:copyOption("enablescenario", "isSceneEnabled")
	self.options.isscenedisabled = self:copyOption("disablescenario", "isSceneDisabled")
	--self.options.runconfigscene = self:copyOption("setrunconfigscenario", "RunConfigScene")
	self.options.runmodescene = self:copyOption("setrunmodescenario", "RunModeScene")
	self.options.isscenerunning = self:copyOption("runningscene", "isSceneRunning")
	self.options.dayevenodd = self:copyOption("frequency", "DayEvenOdd")
	self.options.notstarted = self:copyOption("notstart")
	self.options.deviceicon = self:copyOption("currenticon", "DeviceIcon")
	self.options.color = self:copyOption("rgb", "Color")

	-- MOVED by Lazer

	self.options_id = 0

	self.id_entry = 0
	self.entries = {}

	self.nbRun = -1
	self.currentMainId = nil
	self.currentEntry = nil

end -- GEA:__init

function GEA:copyOption(optionName, newName)
	local copy = {}
	local option = self.options[optionName] -- Lazer : local
	copy.name = newName or option.name
	if option.math then copy.math = option.math end
	if option.optimize then copy.optimize = option.optimize end
	if option.keepValues then copy.keepValues = option.keepValues end
	if option.control then copy.control = option.control end
	if option.getValue then copy.getValue = option.getValue end
	if option.action then copy.action = option.action end
	if option.depends then copy.depends = option.depends else copy.depends = {} end
	if option.trigger then copy.trigger = option.trigger end -- Lazer
	table.insert(copy.depends, optionName)
	return copy
end

-- --------------------------------------------------------------------------------
--
-- --------------------------------------------------------------------------------
function GEA:getDuree(valeur)
	if tonumber(valeur) then
		return tonumber(valeur)
	else
		local duree = fibaro.getGlobalVariable(valeur)
		if duree and duree:find(":") then
			local durees = tools.split(duree, ":")
			if #durees == 2 then local h,m = string.match(duree, "(%d+):(%d+)") return h*3600 + m*60 end
			if #durees == 3 then local h,m,s = string.match(duree, "(%d+):(%d+):(%d+)") return h*3600 + m*60 + s end
		end
		return tonumber(duree) or 30
	end
end

-- --------------------------------------------------------------------------------
-- Retourne l'ID d'un scénario selon son nom
-- --------------------------------------------------------------------------------
function GEA:findScenarioId(scenarioId)
	if tonumber(scenarioId) then
		return tonumber(scenarioId)
	else
		local scenes = api.get("/scenes")
		local sceneId = nil
		for _, scene in pairs(scenes) do
			--if scene.name:lower() == scenarioId:lower() then
			if scene.name == scenarioId then
				sceneId = scene.id
				break
			end
		end
		assert(tonumber(sceneId), string.format(self.trad.scene_is_missing, scenarioId))
		--if sceneId then
			return sceneId
		--else
			--tools.error(string.format(self.trad.scene_is_missing, scenarioId), "red")
			----fibaro:abort()
			--tools.error("self:findScenarioId() => fibaro:abort()", "red")
		--end
	end
end

-- --------------------------------------------------------------------------------
-- Retourne l'ID d'un module selon son nom NOM_DEVICE[@ROOM]
-- --------------------------------------------------------------------------------
function GEA:findDeviceId(deviceId, silent)
	if tonumber(deviceId) then
		return tonumber(deviceId)
	elseif type(deviceId) ~= "string" then
		return deviceId
	else
		if self.nameToId[deviceId] then
			return self.nameToId[deviceId]
		end
		local search = "/devices?name="..deviceId
		if deviceId:find("@") then
			search = "/devices?name="..tools.split(deviceId, "@")[1]
			local rooms = api.get("/rooms")
			for _, room in pairs(rooms) do
				if room.name:lower() == tools.split(deviceId, "@")[2]:lower() then
					search = search .. "&roomID="..room.id
				end
			end
		end
		local devices = api.get(search)
		if #devices > 0 then
			self.nameToId[deviceId] = devices[1].id
			return devices[1].id
		else
			if silent then
				return deviceId
			end
			error(string.format(self.trad.device_is_missing, deviceId))
			--tools.error(string.format(self.trad.device_is_missing, deviceId), "red")
			----fibaro:abort()
			--tools.error("self:findDeviceId() => fibaro:abort()", "red")
		end
	end
end

-- --------------------------------------------------------------------------------
-- Retourne l'ID d'un utilisateur selon son nom
-- --------------------------------------------------------------------------------
function GEA:findUserId(userId) -- Lazer
	if tonumber(userId) then
		return tonumber(userId)
	else
		local users = api.get("/users")
		local user_id = nil
		for _, user in pairs(users) do
			if user.name == userId then
				user_id = user.id
				break
			end
		end
		assert(tonumber(user_id), string.format(self.trad.user_missing, userId))
		return user_id
	end
end

-- --------------------------------------------------------------------------------
-- Retourne l'ID d'un mobile selon son nom
-- --------------------------------------------------------------------------------
function GEA:findMobileId(mobileId) -- Lazer
	if tonumber(mobileId) then
		return tonumber(mobileId)
	else
		local iosDevices = api.get("/iosDevices")
		local iosDeviceId = nil
		for _, iosDevice in pairs(iosDevices) do
			if iosDevice.name == mobileId then
				iosDeviceId = iosDevice.id
				break
			end
		end
		assert(tonumber(iosDeviceId), string.format(self.trad.user_missing, mobileId))
		return iosDeviceId
	end
end

-- --------------------------------------------------------------------------------
-- Retourne l'ID d'une partition d'alarme selon son nom
-- --------------------------------------------------------------------------------
--[[
function GEA:findAlarmId(alarmId) -- Lazer
	if tonumber(alarmId) then
		return tonumber(alarmId)
	else
		local partitions = api.get("/alarms/v1/partitions")
		local partitionId = nil
		for _, partition in pairs(partitions) do
			if partition.name == alarmId then
				partitionId = partition.id
				break
			end
		end
		assert(tonumber(partitionId), string.format(self.trad.partition_missing, alarmId))
		return partitionId
	end
end
--]]

-- ----------------------------------------------------------
-- Proposition de pepite et Felig
-- Retrouve l'id d'un bouton selon son numéro, son id ou son nom
-- ----------------------------------------------------------
--[[
  function GEA:findButtonId(deviceId, buttonId)
    if (tonumber(buttonId)) then
      return tonumber(buttonId)
    else
      if (not self.buttonIds[deviceId .. " - " .. buttonId]) then
        local device = api.get("/devices/"..deviceId)
        for i = 1, #device.properties.rows do
          if (device.properties.rows[i].type == "button") then
            for j = 1, #device.properties.rows[i].elements do
              if (self:compareString(device.properties.rows[i].elements[j].name, buttonId) or self:compareString(device.properties.rows[i].elements[j].caption, buttonId)) then
                self.buttonIds[deviceId .. " - " .. buttonId] = device.properties.rows[i].elements[j].id
                return self.buttonIds[deviceId .. " - " .. buttonId]
              end
            end
          end
        end
      end
      return self.buttonIds[deviceId .. " - " .. buttonId]
    end
  end
--]]

-- --------------------------------------------------------------------------------
-- Proposition pepite self.getFrequency pour Frequency
-- --------------------------------------------------------------------------------
function GEA:getFrequency(day, number) --day : 1-31 wday :1-7 (1 :sunday)
	local t = os.date("*t", self.runAt)
	local semainepaire = os.date("%W", self.runAt) %2 == 0
	if os.date("%A", self.runAt):lower() == day:lower() then
		return (number == 2 and semainepaire) or t["day"] < 8
	end
end

-- --------------------------------------------------------------------------------
-- Retourne le contenu d'une variable globale
-- --------------------------------------------------------------------------------
function GEA:getGlobalValue(name)
	if self.options.checkvg.getValue(name) then
		return fibaro.getGlobalVariable(name)
	end
	return nil
end

-- --------------------------------------------------------------------------------
-- Met et retourne le nom d'un module en cache
-- --------------------------------------------------------------------------------
function GEA:getNameInCache(id)
	local id_num = self:findDeviceId(id)
	if type(id_num) == "number" then
		id = tonumber(id_num)
		if not self.moduleNames[id_num] then
			self.moduleNames[id_num] = fibaro.getName(id_num)
		end
		return self.moduleNames[id_num] or self.trad.name_is_missing
	else
		return ""
	end
end

-- --------------------------------------------------------------------------------
-- Met et retourne le nom d'une pièce d'un module en cache
-- --------------------------------------------------------------------------------
function GEA:getRoomInCache(id)
	local id_num = self:findDeviceId(id)
	if type(id_num) == "number" then
		id = tonumber(id_num)
		if not self.moduleRooms[id_num] then
			local idRoom = api.get("/devices/"..id_num)
			if idRoom then idRoom = idRoom.roomID end
			if idRoom and idRoom > 0 then
				self.moduleRooms[id_num] = fibaro.getRoomName(idRoom)
			end
		end
		return self.moduleRooms[id_num] or self.trad.room_is_missing
	else
		return ""
	end
end

-- --------------------------------------------------------------------------------
-- Retourne le nom d'un module (pièce optionnelle)
-- --------------------------------------------------------------------------------
function GEA:getName(id, withRoom)
	if type(id) ~= "table" then id = {id} end
	local names = ""
	for i=1, #id do
		if names ~= "" then names = names .. ", " end
		if withRoom then
			names = names .. self:getNameInCache(id[i]) .. " (" .. self:getRoomInCache(id[i]) .. ")"
		else
			names = names .. self:getNameInCache(id[i])
		end
	end
	return names
end

-- --------------------------------------------------------------------------------
-- Vérification des batteries
-- --------------------------------------------------------------------------------
function GEA:batteries(value, concatroom)
	local res = false
	local names, rooms = "", ""
	for _, v in ipairs(fibaro.getDevicesID({interface="battery", visible=true})) do
		local bat = fibaro.getValue(v, 'batteryLevel')
		local low = tonumber(bat) < tonumber(value)
		if low then
			if names ~= "" then names = names .. ", " end
			names = names .. "["..v.."] " .. self:getName(v, concatroom)
			if rooms ~= "" then rooms = rooms .. ", " end
			rooms = rooms .. self:getRoomInCache(v)
		end
		res = res or low
	end
	return res, names, rooms
end

-- --------------------------------------------------------------------------------
-- Recherche et retourne une option (condition ou action) encapsulée
-- --------------------------------------------------------------------------------
function GEA:getOption(object, silent)
--print("GEA:getOption("..json.encode(object)..", "..tostring(silent)..")") -- DEBUG
	local sname = ""
	local tname = type(object)
	local originalName = object
	if tname == "table" then
		sname = string.lower(tostring(object[1])):gsub("!", ""):gsub("+", ""):gsub("-", ""):gsub("%(", ""):gsub("%)", "") -- Modifié par Lazer
		originalName = object[1]
	else
		sname = string.lower(tostring(object)):gsub("!", ""):gsub("+", ""):gsub("-", ""):gsub("%(", ""):gsub("%)", "")
	end
--tools.error("GEA:getOption() sname (" .. type(sname) .. ") " .. tostring(sname) .. " -  tname (" .. type(tname) .. ") " .. tostring(tname)) -- DEBUG
	if sname~="function" then
		local jo = json.encode(object)
--tools.error("GEA:getOption() jo (" .. type(jo) .. ") " .. tostring(jo)) -- DEBUG
		if self.declared[jo] then return self.declared[jo] end
	end
	local option = nil
	if tonumber(sname) or tonumber(self:findDeviceId(sname, true)) then tname = "number" object = tonumber(self:findDeviceId(sname, true)) end
	if tname=="number" or tname=="boolean" then
		option = self.options[tname]
		option.name = object
		originalName = tostring(originalName)
		object = {object}
		sname = tname
	else
		if sname == "function" then sname = "fonction" end
		if sname == "repeat" then sname = "repe_t" end
		if sname == "or" then sname = "o_r" end
		option = self.options[sname]
	end
--tools.error("GEA:getOption() sname (" .. type(sname) .. ") " .. tostring(sname) .. " -  tname (" .. type(tname) .. ") " .. tostring(tname)) -- DEBUG
	if option then
		self.options_id = self.options_id + 1
		if self.nbRun < 1 then table.insert(self.usedoptions, sname) end
		local o = self:encapsule(option, object, originalName:find("!"), originalName:find("+"), originalName:find("-"), self.options_id, originalName:find("%(") and originalName:find("%)"))
		if jo then self.declared[jo] = o end
		return o
	end
	if not silent then
		tools.error(string.format(self.trad.option_missing, tools.convertToString(originalName)), "red")
		--fibaro:abort()
		tools.error("GEA:getOption() => Restart QuickApp", "red")
		plugin.restart()
	end
end

-- --------------------------------------------------------------------------------
-- Encapsulation d'une option (condition ou action)
-- --------------------------------------------------------------------------------
function GEA:encapsule(option, args, inverse, plus, moins, option_id, not_immediat)
--tools.warning("copy.encapsule() option_id = " .. tostring(option_id)) -- DEBUG
--for k, v in pairs(option) do tools.warning("copy.encapsule() option k="..tostring(k).." - v ("..type(v)..")="..tostring(v)) end -- DEBUG
	local copy = {}
	copy.lastRunAt = 0
	copy.option_id = option_id
	copy.name = self:findDeviceId(option.name, true)
--tools.debug("GEA:encapsule() option.name = (" .. type(option.name) .. ") " .. tostring(option.name) .. " - copy.name = (" .. type(copy.name) .. ") " .. tostring(copy.name)) -- DEBUG
	copy.args = {table.unpack(args)}
	copy.inverse = inverse
	copy.not_immediat = not_immediat
	if copy.args and #copy.args>0 then
		table.remove(copy.args, 1)
	end
	copy.getLog = function()
									local params = "]"
									if #copy.args>0 then
										if copy.name:lower() == "function" then
											params = ", {...}" .. params
										else
											params = ", " .. tools.convertToString(copy.args) .. params
										end
									end
									return "["..tostring(copy.name) .. tools.iif(copy.inverse, "!", "") .. tools.iif(plus, "+", "") .. tools.iif(moins, "-", "") .. params
								end
	copy.lastvalue = ""
	copy.lastDisplayValue = ""
	copy.hasValue = type(option.getValue)=="function" or false
	copy.hasAction = type(option.action)=="function" or false
	copy.hasControl = type(option.control)=="function" or false
	copy.getModuleName = function() if option.getName then return option.getName(copy.searchValues()) end local id = copy.getId() return self:getNameInCache(id) end
	copy.getModuleRoom = function() if option.getRoom then return option.getRoom(copy.searchValues()) end local id = copy.getId() return self:getRoomInCache(id) end
	copy.getId = function()
									if copy.not_immediat then return "" end
									if type(copy.name)=="boolean" then
										return copy.name
									elseif type(copy.name)=="number" then
										return copy.name
									elseif type(copy.name)=="function" then
										return nil
									elseif self.plugins[copy.name] then
										return self.currentEntry.id .. "@" .. copy.option_id
									else
										if copy.name == "Or" or copy.name == "XOr" then
											local ids = {}
											for i=1, #copy.args do table.insert(ids, self:getOption(copy.args[i]).getId()) end
											return ids
										end
										if copy.args[1] then return self:findDeviceId(copy.args[1], true) end
										return nil
									end
								end
	copy.searchValues = function()
--tools.error("copy.searchValues()") -- DEBUG
												if type(copy.name)=="boolean" then
--tools.error("copy.searchValues() boolean : " .. tostring(copy.name)) -- DEBUG
													return copy.name
												elseif type(copy.name)=="number" then
--tools.error("copy.searchValues() number : " .. tostring(copy.name)) -- DEBUG
													return copy.name
												else
--tools.error("copy.searchValues() else for") -- DEBUG
													local results = {}
													for i = 1, #args do
--tools.error("copy.searchValues() i=" .. i) -- DEBUG
														if type(args[i]) == "table" and not option.keepValues and i >= 2 then
--tools.error("copy.searchValues() table") -- DEBUG
															local tableNumber = false
															if tonumber(args[i][1]) then
																tableNumber = true
															end
															local o = self:getOption(args[i], true)
															if o and not tableNumber then
																local v = o.getValue()
																table.insert(results, v)
															else
																table.insert(results, args[i])
															end
														else
--tools.error("copy.searchValues() else table.insert args[i] = " .. args[i]) -- DEBUG
															table.insert(results, args[i])
														end
													end
													if results and #results>0 then table.remove(results, 1) end
													return table.unpack(results)
												end
											end
	--copy.control = function() if self.control and copy.hasControl then return option.control(copy.searchValues()) else return true end end
	copy.control = function() -- Lazer
											if self.control and copy.hasControl then
												local ok, val1, val2 = pcall(option.control, copy.searchValues())
												if ok then
													return val1, val2
												else
													return false, val1
												end
											else
												return true
											end
										end
	copy.action = function() if copy.hasAction then copy.lastRunAt=0; return option.action(copy.searchValues()) else tools.warning(string.format(self.trad.not_an_action, copy.name)) return nil end end
	copy.getValue = function()
--tools.warning("copy.getValue()") -- DEBUG
--tools.warning("copy.getValue() copy.hasValue=" .. tostring(copy.hasValue) .. " - copy.lastvalue, copy.lastDisplayValue = " .. tostring(copy.lastvalue) .. ", " .. tostring(copy.lastDisplayValue)) -- DEBUG
										if not copy.hasValue then
											--tools.warning("copy.getValue() return nil") -- DEBUG
											return
										end
										if copy.lastRunAt == self.runAt and copy.lastvalue and (not self.forceRefreshValues) then
--tools.warning("copy.getValue() 1 return copy.lastvalue, copy.lastDisplayValue :" .. tostring(copy.lastvalue) .. ", " .. tostring(copy.lastDisplayValue)) -- DEBUG
											return copy.lastvalue, copy.lastDisplayValue
										end
--tools.warning("copy.getValue() type(copy.name) = " .. type(copy.name)) -- DEBUG
										if type(args[2])=="function" then
											copy.lastvalue, copy.lastDisplayValue = args[2]()
										elseif type(copy.name)=="boolean" then
											copy.lastvalue, copy.lastDisplayValue = self.options.boolean.getValue(copy.name)
										elseif type(copy.name)=="number" then
											copy.lastvalue, copy.lastDisplayValue = self.options.number.getValue(copy.name)
										else
											copy.lastvalue, copy.lastDisplayValue = option.getValue(copy.searchValues())
										end
										copy.lastRunAt = self.runAt
										if not copy.lastDisplayValue or copy.lastDisplayValue == "" then copy.lastDisplayValue = copy.lastvalue end
										if self.lldebug then tools.warning("copy.getValue() 2 return copy.lastvalue, copy.lastDisplayValue : ("..type(copy.lastvalue)..") " .. tostring(copy.lastvalue) .. ", ("..type(copy.lastDisplayValue)..") " .. tostring(copy.lastDisplayValue), "pink") end -- DEBUG
										return copy.lastvalue, copy.lastDisplayValue
									end
	copy.check = function() -- Modifié par Lazer
									local id, property, value, value2, value3, value4 = copy.searchValues()
									if not copy.hasValue then return true end
									if type(property) == "nil" then property = id end
									if type(value) == "nil" then value = property end
									if type(value2) == "nil" then value2 = value end
									if type(value3) == "nil" then value3 = value2 end
									if type(value4) == "nil" then value4 = value3 end
									if self.lldebug then tools.debug("copy.check() copy.name="..tostring(copy.name).." id="..tostring(id).." property="..tostring(property).." value="..tostring(value).." value2="..tostring(value2).." value3="..tostring(value3).." value4="..tostring(value4), "silver") end -- DEBUG
									local result = copy.getValue()
									if self.lldebug then tools.debug("copy.check() result = (" .. type(result) .. ") " .. tostring(result), "silver") end -- DEBUG
									local checked
									if type(copy.name) == "number" then
										if type(result) == "boolean" then
											checked = result
										elseif type(result) == "number" or type(result) == "integer" then
											checked = result > 0
										elseif type(result) == "string" then
											checked = result ~= ""
										elseif type(result) == "table" then
											checked = #result > 0
										else
											checked = result and true or false
										end
									elseif option.isBoolean then
										checked = result
									elseif plus or moins then
										if tools.isNil(option.math) then
											tools.error(string.format(self.trad.not_math_op, copy.name), "red")
											return false, result
										else
											local num1 = tonumber(string.match(value4, "-?[0-9.]+"))
											local num2 = tonumber(string.match(result, "-?[0-9.]+"))
											if plus then
												checked = num2 > num1
											else
												checked = num2 < num1
											end
										end
									elseif type(value4) == "table" then
										checked = self:compareTable(result, value4)
									elseif type(value4) == "function" then
										checked = value4()
									else
										checked = self:compareString(result, value4)
									end
									local forceInverse = false
									if self.currentEntry and self.currentEntry.inverse[self.currentEntry.id.."-"..copy.option_id] then
										forceInverse = true
									end
									if copy.inverse or forceInverse then
										return not checked, result
									else
										return checked, result
									end
								end
	copy.hasTrigger = type(option.trigger) == "function" or false -- Lazer
	copy.eventTrigger = function() -- Lazer
									if copy.hasTrigger then
										local ok, val = pcall(option.trigger, copy.searchValues())
										if ok then
											return val
										else
											return nil, val
										end
									else
										return nil, string.format(self.trad.not_a_trigger, copy.name)
									end
								end
	return copy
end

-- --------------------------------------------------------------------------------
-- Compare 2 chaînes de caractères (autorise les regex)
-- --------------------------------------------------------------------------------
function GEA:compareString(s1, s2)
	s1 = self:replaceChar(tostring(s1):lower())
	s2 = self:replaceChar(tostring(s2):lower())
	if s2:find("#r#") then
		s2 = s2:gsub("#r#", "")
		local res = false
		for _, v in pairs(tools.split(s2, "|")) do
			res = res or tostring(s1):match(tools.trim(v))
		end
		return res
	end
	return tostring(s1) == tostring(s2)
end

-- --------------------------------------------------------------------------------
-- Compare 2 tableaux récursivement
-- --------------------------------------------------------------------------------
function GEA:compareTable(t1, t2)
	local typ1 = type(t1)
	local typ2 = type(t2)
	if typ1 ~= typ2 then return false end
	if typ1 ~= 'table' and typ2 ~= 'table' then return t1 == t2 end
	for k1, v1 in pairs(t1) do
		local v2 = t2[k1]
		if v2 == nil or not self:compareTable(v1, v2) then return false end
	end
	for k2, v2 in pairs(t2) do
		local v1 = t1[k2]
		if v1 == nil or not self:compareTable(v1, v2) then return false end
	end
	return true
end

-- --------------------------------------------------------------------------------
-- Remplacement des caractères spéciaux
-- --------------------------------------------------------------------------------
function GEA:replaceChar(s)
	return s:gsub("Ã ", "à"):gsub("Ã©", "é"):gsub("Ã¨", "è"):gsub("Ã®", "î"):gsub("Ã´", "ô"):gsub("Ã»", "û"):gsub("Ã¹", "ù"):gsub("Ãª", "ê"):gsub("Ã¢","â"):gsub(" ' ", "'")
end

-- --------------------------------------------------------------------------------
-- Trie un tableau selon sa propriété
-- --------------------------------------------------------------------------------
function GEA:table_sort(t, property)
	local new1, new2 = {}, {}
	for k,v in pairs(t) do table.insert(new1, { key=k, val=v } ) end
	table.sort(new1, function (a,b) return (a.val[property] < b.val[property]) end)
	for _,v in pairs(new1) do table.insert(new2, v.val) end
	return new2
end

-- --------------------------------------------------------------------------------
-- Retourne year, month, days selon un format spécifique
-- --------------------------------------------------------------------------------
function GEA:getDateParts(date_str, date_format)
	local d,m,y = date_format:find("dd"), date_format:find("mm"), date_format:find("yy")
	local arr = { { pos=y, b="yy" }, { pos=m, b="mm" } , { pos=d, b="dd" }  }
	arr = self:table_sort(arr, "pos")
	date_format = date_format:gsub("yyyy","(%%d+)"):gsub("yy","(%%d+)"):gsub("mm","(%%d+)"):gsub("dd","(%%d+)"):gsub(" ","%%s")
	if date_str and date_str~="" then
		_, _, arr[1].c, arr[2].c, arr[3].c = string.find(string.lower(date_str), date_format)
	else
		return nil, nil, nil
	end
	arr = self:table_sort(arr, "b")
	return tonumber(arr[3].c), tonumber(arr[2].c), tonumber(arr[1].c)
end

-- --------------------------------------------------------------------------------
-- Gestion des inc+ et dec-
-- --------------------------------------------------------------------------------
function GEA:incdec(value, oldvalue)
	if type(value) ~= "string" then return value end
	if value:find("inc%+") or value:find("dec%-") then
		local num = value:match("%d+") or 1
		local current = tonumber(oldvalue) or 0
		if value:find("inc%+") then value = current + num else value = current - num end
	end
	return value
end

-- --------------------------------------------------------------------------------
-- Converti un nombre de secondes en un format expressif
-- --------------------------------------------------------------------------------
function GEA:getDureeInString(nbSecondes)
	local dureefull = ""
	local duree = ""
	nHours = math.floor(nbSecondes/3600)
	nMins = math.floor(nbSecondes/60 - (nHours*60))
	nSecs = math.floor(nbSecondes - nHours*3600 - nMins *60)
	if nHours > 0 then
		duree = duree .. nHours .. "h "
		dureefull = dureefull .. nHours
		if nHours > 1 then dureefull = dureefull .. " " .. self.trad.hours else dureefull = dureefull .. " " .. self.trad.hour end
	end
	if nMins > 0 then
		duree = duree .. nMins .. "m "
		if nHours > 0 then dureefull = dureefull .. " " end
		if nSecs == 0 and nHours > 0 then dureefull = dureefull .. "et " end
		dureefull = dureefull .. nMins
		if nMins > 1 then dureefull = dureefull .. " " .. self.trad.minutes else dureefull = dureefull .. " " .. self.trad.minute end
	end
	if nSecs > 0 then
		duree = duree.. nSecs .. "s"
		if nMins > 0 then dureefull = dureefull .. " " .. self.trad.andet .. " " end
		dureefull = dureefull .. nSecs
		if nSecs > 1 then dureefull = dureefull .. " " .. self.trad.seconds else dureefull = dureefull .. " "  .. self.trad.second end
	end
	return duree, dureefull
end

-- --------------------------------------------------------------------------------
-- Retourne les heures au bon format si besoin
-- --------------------------------------------------------------------------------
function GEA:flatTimes(from, to)
	return self:flatTime(from, false), self:flatTime(to, to==from)
end

-- --------------------------------------------------------------------------------
-- Retourne une heure au bon format si besoin
-- --------------------------------------------------------------------------------
function GEA:flatTime(time, force)

	local t = time:lower()
	t = t:gsub(" ", ""):gsub("h", ":"):gsub("sunset", fibaro.getValue(1, "sunsetHour")):gsub("sunrise", fibaro.getValue(1, "sunriseHour"))

	if string.find(t, "<") then
		t = self:flatTime(tools.split(t, "<")[1]).."<"..self:flatTime(tools.split(t, "<")[2])
	end
	if string.find(t, ">") then
		t = self:flatTime(tools.split(t, ">")[1])..">"..self:flatTime(tools.split(t, ">")[2])
	end

	local td = os.date("*t", self.runAt)
	if string.find(t, "+") then
		local time = tools.split(t, "+")[1]
		local add = tools.split(t, "+")[2]
		local sun = os.time{year=td.year, month=td.month, day=td.day, hour=tonumber(tools.split(time, ":")[1]), min=tonumber(tools.split(time, ":")[2]), sec=td.sec}
		sun = sun + (add *60)
		t = os.date("*t", sun)
		t =  string.format("%02d", t.hour).. ":" ..string.format("%02d", t.min)
	elseif string.find(t, "-") then
		local time = tools.split(t, "-")[1]
		local add = tools.split(t, "-")[2]
		local sun = os.time{year=td.year, month=td.month, day=td.day, hour=tonumber(tools.split(time, ":")[1]), min=tonumber(tools.split(time, ":")[2]), sec=td.sec}
		sun = sun - (add *60)
		t = os.date("*t", sun)
		t =  string.format("%02d", t.hour)..":" ..string.format("%02d", t.min)			
	elseif string.find(t, "<") then
		local s1 = tools.split(t, "<")[1]
		local s2 = tools.split(t, "<")[2]
		s1 =  string.format("%02d", tools.split(s1, ":")[1]) .. ":" .. string.format("%02d", tools.split(s1, ":")[2])
		s2 =  string.format("%02d", tools.split(s2, ":")[1]) .. ":" .. string.format("%02d", tools.split(s2, ":")[2])
		if s1 < s2 then t = s1 else t = s2 end
	elseif string.find(t, ">") then
		local s1 = tools.split(t, ">")[1]
		local s2 = tools.split(t, ">")[2]
		s1 =  string.format("%02d", tools.split(s1, ":")[1]) .. ":" .. string.format("%02d", tools.split(s1, ":")[2])
		s2 =  string.format("%02d", tools.split(s2, ":")[1]) .. ":" .. string.format("%02d", tools.split(s2, ":")[2])
		if s1 > s2 then t = s1 else t = s2 end
	else
		t =  string.format("%02d", tools.split(t, ":")[1]) .. ":" .. string.format("%02d", tools.split(t, ":")[2])
	end

	if force then
		if self.currentEntry.firstvalid then
			local td = os.date("*t", self.currentEntry.firstvalid)
			local sun = os.time{year=td.year, month=td.month, day=td.day, hour=td.hour, min=td.min, sec=td.sec}
			sun = sun + self.currentEntry.getDuration()
			t = os.date("*t", sun)	
			return string.format("%02d", t.hour).. ":" ..string.format("%02d", t.min)..":" ..string.format("%02d", t.sec)
		end
	end
	return t .. ":" ..string.format("%02d", td.sec)

end

-- --------------------------------------------------------------------------------
-- Contrôle des heures
-- --------------------------------------------------------------------------------
function GEA:checkTime(from, to)
	local now = os.date("%H%M%S", self.runAt)
	from, to = self:flatTimes(from, to)
	from = from:gsub(":", "")
	to = to:gsub(":", "")
	if to < from then
		return (now >= from) or (now <= to)
	else
		return (now >= from) and (now <= to)
	end
end

-- --------------------------------------------------------------------------------
-- Contrôle des dates
-- --------------------------------------------------------------------------------
function GEA:checkDates(from, to)
	local now = os.date("%Y%m%d", self.runAt)
	to = to or from
	local d,m,y = to:match("(%d+).(%d+).(%d+)")
	local missingYear = false
	if not y then to = to .. self.trad.input_date_format:match("[/,.]") .. os.date("%Y", self.runAt) missingYear = true end
	local toy, tom, tod = self:getDateParts(to, self.trad.input_date_format)
	d,m,y = from:match("(%d+).(%d+).(%d+)")
	if not y then from = from .. self.trad.input_date_format:match("[/,.]") .. os.date("%Y", self.runAt) end
	local fromy, fromm, fromd = self:getDateParts(from, self.trad.input_date_format)
	from = string.format ("%04d", fromy) ..string.format ("%02d", fromm)..string.format ("%02d", fromd)
	to = string.format ("%04d", toy) ..string.format ("%02d", tom)..string.format ("%02d", tod)
	if tonumber(string.format ("%02d", tom)..string.format ("%02d", tod)) < tonumber(string.format ("%02d", fromm)..string.format ("%02d", fromd)) and missingYear then
		to = string.format ("%04d", toy+1) ..string.format ("%02d", tom)..string.format ("%02d", tod)
	end
	return tonumber(now) >= tonumber(from) and tonumber(now) <= tonumber(to)
end

-- --------------------------------------------------------------------------------
-- Contrôle des jours
-- --------------------------------------------------------------------------------
function GEA:checkDays(days)
	if not days or days=="" then days = "All" end
	days = days:lower()
	local jours = days:gsub("all", "weekday,weekend")
	jours = jours:gsub(self.trad.weekdays, self.traduction.en.weekdays):gsub(self.trad.weekend, self.traduction.en.weekend)
	jours = jours:gsub(self.trad.week[1], self.traduction.en.week[1]):gsub(self.trad.week[2], self.traduction.en.week[2]):gsub(self.trad.week[3], self.traduction.en.week[3]):gsub(self.trad.week[4], self.traduction.en.week[4]):gsub(self.trad.week[5], self.traduction.en.week[5]):gsub(self.trad.week[6], self.traduction.en.week[6]):gsub(self.trad.week[7], self.traduction.en.week[7])
	jours = jours:gsub("weekday", "monday,tuesday,wednesday,thursday,friday"):gsub("weekdays", "monday,tuesday,wednesday,thursday,friday"):gsub("weekend", "saturday,sunday")
	return tools.isNotNil(string.find(jours:lower(), os.date("%A", self.runAt):lower()))
end

-- --------------------------------------------------------------------------------
-- Traite les entrées spéciales avant de l'ajouter dans le tableau
-- --------------------------------------------------------------------------------
function GEA:insert(t, v, entry)
	if not v then return end -- Lazer
	local action = tostring(v.name):lower()
	if action == "repeat" then entry.repeating = true return end
	if action == "notstart" then entry.stopped = true return end
	if action == "portables" then entry.portables = v.args[1] return end
	if action == "portable" or action == "push" then entry.portables = {} end
	if action == "inverse" then local num = v.args[1] or 1 entry.inverse[entry.id.."-"..entry.conditions[num].option_id] = true return end
	if action == "time" then if not entry.ortime then entry.ortime = {"Or", {"Time", v.args[1], v.args[2]}} else table.insert(entry.ortime, {"Time", v.args[1], v.args[2]}) end return end
	if action == "dates" then if not entry.ordates then entry.ordates = {"Or", {"Dates", v.args[1], v.args[2]}} else table.insert(entry.ordates, {"Dates", v.args[1], v.args[2]}) end return end
	if action == "maxtime" then
		local time = self.options.maxtime.getValue(entry.id)
		if time and tonumber(time) < 1 then
			entry.stopped = true
		else
			entry.maxtime = v.args[1]
			entry.repeating = true
		end
		return
	end
	if action == "alarm" then entry.duration = 30 entry.getDuration = function() return 30 end entry.repeating = true end
	if action == "depend" then table.insert(self:findEntry(v.args[1]).listeners, entry.id) entry.isWaiting[v.args[1]]=true end
	table.insert(t, v)
	return true
end

-- --------------------------------------------------------------------------------
-- Ajoute dans l'historique
-- --------------------------------------------------------------------------------
function GEA:addHistory(message)
	if not self.auto then return end
	if not self.history then self.history = {} end
	if #self.history >= self.historymax then
		for i = 1, (#self.history-1) do
			self.history[i] = self.history[i+1]
		end
		self.history[#self.history] = nil
	end
	self.history[(#self.history+1)] = os.date(self.trad.hour_format, self.runAt) .. " : " .. message:gsub("<", ""):gsub(">", "")
end

-- --------------------------------------------------------------------------------
-- Ajoute un déclencheur instantané -- Lazer
-- --------------------------------------------------------------------------------
function GEA:addTriggerCondition(o)
	local option = self:getOption(o)
	if type(option) == "table" then
		--tools.info("addTriggerCondition() option["..#option.."]")
		--for k, v in pairs(option) do tools.info("addTriggerCondition() option : k = " .. k .. " - v = " .. type(v) .. " => " .. tostring(v)) end -- DEBUG
		if option.hasTrigger and not option.not_immediat then
			local eventTrigger, msg = option.eventTrigger()
			--tools.info("addTriggerID() eventTrigger => " .. json.encode(eventTrigger)) -- DEBUG
			if type(eventTrigger) == "table" then
				--for k, v in pairs(eventTrigger) do tools.info("addTriggerID() eventTrigger : " .. tostring(k) .. " = " .. tostring(v)) end -- DEBUG
				local found = false
				for i = 1, #triggers do
					--tools.info("addTriggerID() triggers[" .. tostring(i) .. "] => " .. json.encode(triggers[i])) -- DEBUG
						if self:compareTable(triggers[i], eventTrigger) then
							found = true
							--tools.debug("addTriggerID() eventTrigger already exists") -- DEBUG
							break
						end
				end
				if not found then
					triggers[#triggers+1] = eventTrigger
					--tools.debug("addTriggerID() added : " .. json.encode(triggers[#triggers])) -- DEBUG
				end
			else
				tools.error(msg, "red")
			end
		end
	end
end

-- --------------------------------------------------------------------------------
-- Retrouve une entry selon son ID
-- --------------------------------------------------------------------------------
function GEA:findEntry(entryId)
	for i = 1, #self.entries do
		if self.entries[i].id == tonumber(entryId) then return self.entries[i] end
	end
end

-- --------------------------------------------------------------------------------
-- Permet l'ajout des entrées à traiter
-- c : conditions
-- d : durée
-- m : message
-- a : actions
-- l : log
-- --------------------------------------------------------------------------------
GEA.add = function(c, d, m, a, l) -- Conservé pour compatibilité des règles utilisateurs sur HC2
	if GEA_event then
		GEA_event:addEntry(c, d, m, a, l)
	elseif GEA_auto then
		GEA_auto:addEntry(c, d, m, a, l)
	else
		-- n'est jamais censé se produire
		tools.error("GEA_event or GEA_auto not found", "red")
	end
end

function GEA:addEntry(c, d, m, a, l)

	if not c then tools.error(self.trad.err_cond_missing, "red") return end
	if not d then tools.error(self.trad.err_dur_missing, "red") return end
	if not m then tools.error(self.trad.err_msg_missing, "red") return end

	self.id_entry = self.id_entry + 1
--tools.warning("#" .. self.id_entry .. " self:add(" .. json.encode(c) .. ", " .. tostring(d) .. ", \"" .. tostring(m) .. "\", " .. json.encode(a) .. ")") -- DEBUG

	if type(a) == "string" and type(l) == "nil" then
		l = a
		a = nil
	end

	local entry = {
		id = self.id_entry,
		conditions = {},
		duration = d,
		message = m,
		actions = {},
		repeating = false,
		maxtime = -1,
		count = 0,
		stopped = false,
		listeners = {},
		isWaiting = {},
		firstvalid = nil,
		lastvalid = nil,
		runned = false,
		log = "#" .. self.id_entry .. " " ..tools.iif(l, tools.tostring(l), ""),
		portables = self.portables,
		inverse = {}
	}
	entry.getDuration = function()
		return self:getDuree(entry.duration)
	end
	-- entrée inutile, on retourne juste l'id pour référence
	if not self.auto and entry.getDuration() >= 0 then
--tools.warning("self:add() not self.auto") -- DEBUG
		return entry.id
	end
	if self.auto and entry.getDuration() < 0 then
		-- Lazer : Recherche les déclencheurs dans les conditions
		if type(c) == "table" and (type(c[1]) == "table" or type(c[1]) == "number" or c[1]:find("%d+!") or type(c[1]) == "boolean") then
			for i = 1, #c do
				self:addTriggerCondition(c[i])
			end
		else
			self:addTriggerCondition(c)
		end

--tools.warning("self:add() getDuration < 0") -- DEBUG
		return entry.id
	end
	if self.source["type"] == "manual" then
--tools.warning("self:add() source[type] manual") -- DEBUG
		return entry.id
	end

	self.currentEntry = entry

	-- traitement des conditions
	entry.mainid = -1
	local done = false
	if type(c) == "table" and (type(c[1]) == "table" or type(c[1]) == "number" or c[1]:find("%d+!") or type(c[1]) == "boolean") then
		for i = 1, #c do
--tools.warning("Condition n°" .. i) -- DEBUG
			local res = self:insert(entry.conditions, self:getOption(c[i]), entry)
			done = done or res
		end
	else
--tools.warning("Condition") -- DEBUG
		done = self:insert(entry.conditions, self:getOption(c), entry)
	end
	if done then
		local mainid = entry.conditions[1].getId()
		if type(mainid) == "table" then
			entry.mainid = mainid[1]
		else
--tools.debug("mainid : " .. tostring(mainid)) -- DEBUG
	entry.mainid = mainid
		end
	end

	-- analyse des messages pour empêcher la suppression des options utilisées
	if self.auto then self:getMessage(m, true) end

	-- analyse du déclencheur
	if self.event and self.event.id then
		-- si le déclencheur est trouvé en recherche un id correspondant
		local found = false
		for i = 1, #entry.conditions do
--tools.debug("condition i : " .. i) -- DEBUG
			local ids = entry.conditions[i].getId()
--tools.debug("condition ids : " .. json.encode(ids)) -- DEBUG
			if type(ids) == "table" then
				for j = 1, #ids do
					if tostring(ids[j]) == tostring(self.event.id) and not self.event.label then found = true end
					if tostring(ids[j]) == tostring(self.event.id) and self.event.label then
						--if "ui."..entry.conditions[i].args[2]:gsub("ui.", ""):gsub(".value", "")..".value" == self.event.label then
						if entry.conditions[i].args[2] == self.event.label then -- Lazer
							found = true
						end
					end
				end
			else
--tools.debug("ID déclencheur : " .. ids) -- DEBUG
				if tostring(ids) == tostring(self.event.id) and not self.event.label then found = true end
				if tostring(ids) == tostring(self.event.id) and self.event.label then
					--if "ui."..entry.conditions[i].args[2]:gsub("ui.", ""):gsub(".value", "")..".value" == self.event.label then
					if entry.conditions[i].args[2] == self.event.label then -- Lazer
						found = true
					end
				end
			end
		end
		if not found then --[[tools.warning("self:add() event not found")--]] return entry.id end -- DEBUG
	end

	-- traitement des actions
	if a then
		if type(a) == "table" and type(a[1]) == "table" then
			for i = 1, #a do
				if type(a[i]) == "table" and a[i][1]:lower()=="if" then
					self:insert(entry.conditions, self:getOption(a[i][2]), entry)
				elseif type(a[i]) == "table" and self:compareString(a[i][1]:lower(), "#r#^time|dates|days|dst|nodst|^armed|^disarmed") then
					self:insert(entry.conditions, self:getOption(a[i]), entry)
				else
					self:insert(entry.actions, self:getOption(a[i]), entry)
				end
			end
		else
			if type(a) == "table" and a[1]:lower()=="if" then
				self:insert(entry.conditions, self:getOption(a[2]), entry)
			elseif type(a) == "table" and self:compareString(a[1]:lower(), "#r#^time|dates|days|dst|nodst|^armed|^disarmed") then
				self:insert(entry.conditions, self:getOption(a), entry)
			else
				self:insert(entry.actions, self:getOption(a), entry)
			end
		end
	end
	-- gestion des heures et dates multiples
	if entry.ortime then if #entry.ortime > 2 then self:insert(entry.conditions, self:getOption(entry.ortime), entry) else table.insert(entry.conditions, self:getOption(entry.ortime[2])) end end
	if entry.ordates then if #entry.ordates > 2 then self:insert(entry.conditions, self:getOption(entry.ordates), entry) else table.insert(entry.conditions, self:getOption(entry.ordates[2])) end end

	local correct = true
	local erreur = ""
	for i = 1,  #entry.conditions do
		entry.log = tools.iif(l, entry.log, entry.log .. entry.conditions[i].getLog())
		if self.auto then
			-- Contrôle des conditions
			self.currentMainId = entry.mainid
			self.currentCondition = entry.conditions[i]
			check, msg = entry.conditions[i].control()
			if not check then erreur = msg end
			if not entry.conditions[i].hasValue then
				check = false
				erreur = string.format(self.trad.not_an_condition, entry.conditions[i].getLog())
			end
			correct = correct and check
		end
	end

	for i = 1, #entry.actions do
		entry.log = tools.iif(l, entry.log, entry.log .. entry.actions[i].getLog())
		if self.auto then
			-- Contrôle des actions
			self.currentAction = entry.actions[i]
			check, msg = entry.actions[i].control()
			if not check then erreur = msg end
			if not entry.actions[i].hasAction then
				check = false
				erreur = string.format(self.trad.not_an_action, entry.actions[i].getLog())
			end
			correct = correct and check
		end
	end
	entry.simplelog = entry.log
	entry.log = entry.log .."<font color=gray>" .. tools.iif(entry.repeating, " *"..self.trad.repeated.."*", "") .. tools.iif(entry.stopped, " *"..self.trad.stopped.."*", "") .. tools.iif(entry.maxtime > 0, " *"..self.trad.maxtime.."="..entry.maxtime.."*", "") .. "</font>"

	if correct then
		if self.auto then tools.info(self.trad.add_auto .." ".. entry.log) end
			--else tools.debug("Lazer : Ajout instantané" .." ".. entry.log) end -- DEBUG
		table.insert(self.entries, entry)
--tools.warning("self:add() OK") -- DEBUG
		return entry.id
	else
		tools.error(tools.iif(entry.getDuration() < 0, self.trad.add_event .." ", self.trad.add_auto .." ") .. entry.log, "red")
		tools.error(erreur, "red")
		--tools.error(self.trad.gea_failed, "red")
		--fibaro:abort()
		--tools.error("self:add() => fibaro:abort()", "red")
		return
	end
end

-- --------------------------------------------------------------------------------
-- Execute une function et attends un retour
-- --------------------------------------------------------------------------------
function GEA:waitWithTimeout(func, sleep, max)
	local ok, result = func()
	while (not ok and max > 0) do
		fibaro.sleep(sleep)
		max = max - sleep
		ok, result = func()
	end
	return result
end

-- --------------------------------------------------------------------------------
-- Vérifie une entrée pour s'assurer que toutes les conditions soient remplies
-- --------------------------------------------------------------------------------
function GEA:check(entry)

	if self.options.restarttask.getValue(entry.id) then
		self:reset(entry)
		self.stoppedTasks[entry.id] = nil
		self.globalvalue = self.globalvalue:gsub("|R_" .. entry.id.."|", ""):gsub("|S_" .. entry.id.."|", ""):gsub("|M_" .. entry.id .. "{(%d+)}|", "")
	end
	if self.options.stoptask.getValue(entry.id) then entry.stopped = true end

	if entry.stopped then
		if not self.stoppedTasks[entry.id] then tools.debug("&nbsp;&nbsp;&nbsp;["..self.trad.stopped.."] " .. entry.log) end
		self.stoppedTasks[entry.id] = true
	end

	-- test des conditions
	local ready = true
	for i = 1, #entry.conditions do
--tools.error("i = " .. i) -- DEBUG
		self.currentCondition = entry.conditions[i]
--for k, v in pairs(entry.conditions[i]) do
--tools.warning("k = " .. k .. " - v : " .. type(v) .. " => " .. tostring(v)) -- DEBUG
--end
		local result, _ = entry.conditions[i].check()
		if self.lldebug then tools.warning("GEA:check() result = " .. tostring(result) .. ", " .. tostring(_), "blue") end -- DEBUG
		ready = ready and result
	end

	if not entry.stopped then tools.debug("@" ..(self.nbRun*self.checkEvery) .. "s ["..self.trad.validate..tools.iif(ready, "*] ", "] ") .. entry.log) end

	-- si toutes les conditions sont validées
	if ready then
--tools.error("ready") -- DEBUG
		if entry.stopped then return end
		if tools.isNil(entry.lastvalid) then entry.lastvalid = self.runAt end
		if tools.isNil(entry.firstvalid) then entry.firstvalid = self.runAt end
		if os.difftime(self.runAt, entry.lastvalid) >= entry.getDuration() then
			entry.count = entry.count + 1
			entry.lastvalid = self.runAt
			tools.info("&nbsp;&nbsp;&nbsp;["..self.trad.start_entry.."] " .. entry.log, "green")
			-- gestion des actions
			for i = 1, #entry.actions do
				self.currentAction = entry.actions[i]
				tools.debug("&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;["..self.trad.action.."] " .. self:getMessage(entry.actions[i].getLog(), nil, true))
				if self.secureAction then
					local status, err = pcall(function() entry.actions[i].action() end) -- Lazer
					if not status then
						if self.debug then
							tools.error(err, "red")
						end
						tools.error(self.trad.err_check .. entry.actions[i].getLog(), "red")
						self:addHistory(self.trad.err_check .. entry.simplelog)
					end
				else
					entry.actions[i].action()
				end
			end
			-- envoi message push
			if entry.message ~= "" then
				if type(self.output)~="function" then
					for i = 1, #entry.portables do
						local status, err = pcall(function() self:getOption({"Portable", entry.portables[i], self:getMessage()}).action() end)
						if not status then
							if self.debug then
								tools.error(err, "pink")
							end
						end
					end
				else
					-- Message push personnalisé
					self.output(self:getMessage())
				end
			end
			entry.runned = true
			-- mise à jour des écoutes --
			for i=1, #entry.listeners do self:findEntry(entry.listeners[i]).isWaiting[entry.id] = false end
			-- remise à zéro des attente --
			for i=1, #entry.isWaiting do entry.isWaiting[i] = true end
			-- Vérification du MaxTime
			if entry.maxtime > 0 then
				local timeleft = self.options.maxtime.getValue(entry.id)
				if not timeleft then
					self.options.maxtime.action(entry.id, entry.maxtime-1)
				else
					timeleft = tonumber(timeleft)
					self.options.maxtime.action(entry.id, timeleft-1)
				end
			end
			self:addHistory(entry.simplelog)
			if not entry.repeating then entry.stopped = true end
		end
	else
		self:reset(entry)
	end
	return ready
end

-- --------------------------------------------------------------------------------
-- Cherche un mot dans le tableau source et retourne sa valeur dans du tableau destination
-- --------------------------------------------------------------------------------
function GEA:translate(word, tableSource, tableDest)
	for k, v in pairs(tableSource) do if tostring(v):lower() == tostring(word):lower() then return tableDest[k] end end
end

-- --------------------------------------------------------------------------------
-- Cherche un mot anglais et trouve son équivalence dans la langue locale
-- --------------------------------------------------------------------------------
function GEA:translatetrad(key, word)
	if type(self.traduction.en[key])=="table" then
		local res = self:translate(word, self.traduction.en[key], self.trad[key])
		if res then return res end
	elseif self.trad[key] then
		return self.trad[key]
	end
	return word
end

-- --------------------------------------------------------------------------------
-- Remplace les éléments du message
-- --------------------------------------------------------------------------------
function GEA:getMessage(message, forAnalyse, forLog)
	if not forAnalyse then
		if not message then message = self.currentEntry.message end
		message = tostring(message)
		message:gsub("(#.-#)", function(c)
			local position = tonumber(c:match("%[(%d+)%]") or 1)
			c = c:gsub("%[","%%%1"):gsub("%]","%%%1")
			if c:find("value") then message = message:gsub(c, tostring(self.options.result.getValue(position))) end
			if c:find("name") then message = message:gsub(c, self.options.name.getValue(position)) end
			if c:find("room") then message = message:gsub(c, self.options.room.getValue(position)) end
		end)
	end
	message:gsub("({.-})", function(c)
		if forLog then
			-- ne rien faire
		else
		local d = tools.split(c:gsub("{", ""):gsub("}", ""), ",")
			for i = 1, #d do
				d[i] = tools.trim(d[i])
				if tools.isNumber(d[i]) then d[i] = tonumber(d[i])
				elseif d[i]:lower()=="true" then d[i] = true
				elseif d[i]:lower()=="false" then d[i] = false
				end
			end
			local res, mess = self:getOption(d).getValue()
			if type(mess) == "nil" then mess = "n/a" end
			message = message:gsub(c, tostring(mess))
		end
	end)
--tools.debug("GEA:getMessage() => " .. tostring(message)) -- DEBUG
	if not forAnalyse then
		message = message:gsub("#runs#", self.options.runs.getValue())
		message = message:gsub("#seconds#", self.options.seconds.getValue())
		message = message:gsub("#duration#", self.options.duration.getValue())
		message = message:gsub("#durationfull#", self.options.durationfull.getValue())
		message = message:gsub("#time#", self.options.time.getValue())
		message = message:gsub("#date#", self.options.date.getValue())
		message = message:gsub("#datefull#", self.options.datefull.getValue())
		message = message:gsub("#trigger#", self.options.trigger.getValue())
		message:gsub("#translate%(.-%)", function(c)
			local key, word = c:match("%((.-),(.-)%)")
			c = c:gsub("%[","%%%1"):gsub("%]","%%%1"):gsub("%(","%%%1"):gsub("%)","%%%1")
			message = message:gsub(c.."#", self.options.translate.getValue(key, word))
		end)
	end
	if type(self.getMessageDecorator) == "function" then message = self:getMessageDecorator(message) end
	return message
end

-- --------------------------------------------------------------------------------
-- Recherche et activation des plugins scénarios
-- --------------------------------------------------------------------------------
function GEA:searchPlugins()
	if not self.auto then
		local vgplugins = self:getGlobalValue(self.pluginsvariables)
		if vgplugins and vgplugins ~= "" and vgplugins ~= "NaN" then
			self.plugins = json.decode(vgplugins)
			for k, _ in pairs(self.plugins) do if k ~= "retour" then self.options[k] = self:copyOption("pluginscenario", k) end end
		end
		return
	end
	local message = self.trad.search_plugins.." :"
	local scenes = api.get("/scenes")
	local found = false
	for i = 1, #scenes do
		local scene = scenes[i]
		if scene.type and scene.type == "lua" then
			if string.match(scene.content, "GEAPlugin%.version.?=.?(%d+)") then
				local name = scene.name:lower():gsub("%p", ""):gsub("%s", "")
				message = message .. " " .. name
				self.plugins[name] = scene.id
				self.options[name] = self:copyOption("pluginscenario", name)
				found = true
				if tools.isNil(self:getGlobalValue(self.pluginsvariables)) then
					tools.info(string.format(self.trad.gea_global_create, self.pluginsvariables), "yellow")
					api.post("/globalVariables", {name=self.pluginsvariables, isEnum=self.varenum})
				end
				fibaro.setGlobalVariable(self.pluginsvariables, json.encode(self.plugins))
			end
		end
	end
	if not found then message = message .. " " .. self.trad.plugins_none end
	tools.info(message, "yellow")
end

-- --------------------------------------------------------------------------------
-- RAZ d'une entrée
-- --------------------------------------------------------------------------------
function GEA:reset(entry)
	entry.count = 0
	entry.lastvalid = nil
	entry.firstvalid = nil
	entry.stopped = false
	entry.runned = false
	for i=1, #entry.isWaiting do entry.isWaiting[i] = true end
end

-- --------------------------------------------------------------------------------
-- Decode un JSON et va chercher la propriété demandée
-- --------------------------------------------------------------------------------
function GEA:decode(flux, property)
	local d = json.decode(flux)
	if d then
		local lastvalue = d
		for k, v in pairs(tools.split(property, ".")) do
			if v:match("%[(%d+)%]") and type(lastvalue[v:gsub("%[(%d+)%]", "")]) == "table" then
				local number = tonumber(v:match("%[(%d+)%]") or 1)
				if number then
					v = v:gsub("%[(%d+)%]", "")
					lastvalue = lastvalue[v][number]
				end
			elseif v:match("%[(%d+)%]") then
				local number = tonumber(v:match("%[(%d+)%]") or 1)
				if number then
					v = v:gsub("%[(%d+)%]", "")
					lastvalue = lastvalue[number]
				end
			else
				if lastvalue[v] then lastvalue = lastvalue[v] end
			end
		end
		return lastvalue
	end
end

-- --------------------------------------------------------------------------------
-- Permet de retourner les infos de GEA à qui besoin
-- --------------------------------------------------------------------------------
function GEA:answer(params)
	--if tools.isNil(self:getGlobalValue(self.historyvariable)) then self.history = {} else self.history = json.decode(self:getGlobalValue(self.historyvariable)) end -- Lazer
	local histo = quickApp:getVariable(self.historyvariable)
	if histo and histo ~= "" then self.history = json.decode(histo) else self.history = {} end
	if params.vdid then
		for k, v in pairs(params) do
			if type(v)=="string" and v:match("%[(%d+)%]") and type(self[v:gsub("%[(%d+)%]", "")]) == "table" then
				local number = tonumber(v:match("%[(%d+)%]") or 1)
				if number then
					v = v:gsub("%[(%d+)%]", "")
					--fibaro.call(params.vdid, "setProperty", "ui."..k..".value", tools.iif(self[v][number], tools.tostring(self[v][number]), ""))
					fibaro.call(params.vdid, "updateView", k, "text", tools.iif(self[v][number], tools.tostring(self[v][number]), ""))
				end
			elseif type(self[v]) ~= "function" and type(self[v]) ~= "nil" then
				--fibaro.call(params.vdid, "setProperty", "ui."..k..".value", " " .. tools.tostring(self[v]))
				fibaro.call(params.vdid, "updateView", k, "text", " " .. tools.tostring(self[v]))
			end
		end
	end
end

-- --------------------------------------------------------------------------------
-- Optimisation du code
-- --------------------------------------------------------------------------------
function GEA:optimise()
	tools.info(self.trad.optimization, "gray")
	self.answer = nil
	self.insert = nil
	self.searchPlugins = nil
	self.add = nil
	self.copyOption = nil
	self.init = nil
	--setEvents = nil -- Lazer
	--config = nil
	local depends = ""
	local notused = {}
	for k, v in pairs(self.options) do
		local found = false
		for _, w in pairs(self.usedoptions) do
			if k == w then
				found = true
				if v.depends then depends = depends .. table.concat(v.depends, " ") end
			end
		end
		if not found then table.insert(notused, k) end
	end
	for _, v in pairs(notused) do
		if self.options[v] and self.options[v].optimize and (not depends:find(v)) then
			if v == "batteries" then self.batteries = nil end
			if v == "frequency" then self.getFrequency = nil end
			tools.info(self.trad.removeuseless .. v, "gray")
			self.options[v] = nil
		end
	end
	self.usedoptions = nil
	for k, _ in pairs(self.traduction) do if k ~= string.lower(self.language) and k ~= "en" then tools.info(self.trad.removeuselesstrad .. k, "gray") self.traduction[k] = nil end end
end

-- --------------------------------------------------------------------------------
-- Lance le contrôle de toutes les entrées
-- --------------------------------------------------------------------------------
function GEA:run()

	self.runAt = os.time()
	self.forceRefreshValues = false
	--self.globalvalue = self:getGlobalValue(self.globalvariables)
	self.globalvalue = quickApp:getVariable(self.globalvariables) -- Lazer
	self.nbRun = self.nbRun + 1
	if self.nbRun > 0 and math.fmod(self.nbRun, 10) == 0 then
		local garbage = collectgarbage("count")
		tools.info(string.format(self.trad.gea_run_since, self:getDureeInString(self.runAt-self.started)) .. " - " .. self.trad.memoryused .. string.format("%.2f", garbage) .. " KB" )
		table.insert(self.garbagevalues, tostring(garbage))
		if #self.garbagevalues >= 5 then
			local up = true
			local previous = 0
			for _, v in pairs(self.garbagevalues) do
				v = tonumber(v)
				if previous == 0 then previous = v end
				if v < previous then up = false end
				previous = v
			end
			if up then tools.warning(self.trad.memoryused .. string.format("%.2f", previous) .. " KB" ) end
		end
		if #self.garbagevalues >= 10 then table.remove(self.garbagevalues, 1) end
	else
		if --[[not self.debug and--]] self.auto then tools.debug(string.format(self.trad.gea_check_nbr, self.nbRun, (self.nbRun*self.checkEvery)), "cyan", true) end
		if self.nbRun == 1 then self:optimise() self.optimise = nil end
	end

	--self.running = string.lower(fibaro.getGlobalVariable(self.suspendvar)) ~= self.trad.yes
	self.running = string.lower(quickApp:getVariable(self.suspendvar)) ~= self.trad.yes -- Lazer
	quickApp:updateView("labelRunning", "text", "Running : " .. (self.running and self.trad.yes or self.trad.no))
	if self.running then
		local nbEntries = #self.entries
		if nbEntries > 0 then
			for i = 1, nbEntries do
				self.currentMainId = self.entries[i].mainid
				self.currentEntry = self.entries[i]
				self:check(self.entries[i])
			end
			--fibaro.setGlobalVariable(self.globalvariables, self.globalvalue)
			quickApp:setVariable(self.globalvariables, self.globalvalue) -- Lazer
			--fibaro.setGlobalVariable(self.historyvariable, json.encode(self.history))
			quickApp:setVariable(self.historyvariable, json.encode(self.history)) -- Lazer
		end
	else
		tools.warning(string.format(self.trad.gea_suspended, self.suspendvar), "orange", true)
	end

	if self.auto then
		local nextstart = os.difftime(self.started+(self.nbRun+1)*self.checkEvery, os.time())
		setTimeout(function() self:run() end, nextstart * 1000)
	end

end

-- --------------------------------------------------------------------------------
-- Initialisation, démarrage de GEA
-- --------------------------------------------------------------------------------
function GEA:init()
	if type(config) == "function" then -- Lazer
		config(self) -- Chargement des options de configuration utilisateur
	end
	if not self.language then
		if api then self.language = api.get("/settings/info").defaultLanguage end
		if not self.traduction[self.language] then self.language = "en" end
	end
	self.trad = self.traduction[string.lower(self.language)]
	if type(self.portables) ~= "table" then self.portables = {self.portables} end
	tools.info("") -- Ajout Lazer
	if self.auto then
		tools.info("--------------------------------------------------------------------------------", "cyan")
		tools.info(string.format(self.trad.gea_start, self.version, self.source.type), "cyan")
		tools.info("--------------------------------------------------------------------------------", "cyan")
		tools.info(string.format(self.trad.gea_minifier, tools.version), "yellow")
		tools.info(string.format(self.trad.gea_check_every, self.checkEvery), "yellow")
		tools.info(string.format(self.trad.gea_global_create, self.globalvariables), "yellow")
		tools.info(string.format(self.trad.gea_global_create, self.historyvariable), "yellow")
		quickApp:updateView("labelVersion", "text", "Version : " .. self.version)
		quickApp:updateView("labelIntervalle", "text", "Intervalle : " .. tostring(self.checkEvery) .. "s")
		quickApp:updateView("labelPortables", "text", "Portables : " .. json.encode(self.portables))
		quickApp:updateView("labelDebug", "text", "Debug : " .. (self.debug and self.trad.yes or self.trad.no))
	end
	if self.source.type ~= "manual" then tools.info("--------------------------------------------------------------------------------") end
	local line, result = nil, nil
	if not self.auto then
		self.event = {}
		if self.source.type == "device" then
			self.event.id = self.source.id
			if self.source.propertyName and self.source.componentName then -- label ou slider
				self.event.label = self.source.componentName
			end
		elseif self.source.type == "global-variable" then
			self.event.id = self.source.name
		elseif self.source.type == "alarm" then -- Lazer
			self.event.id = self.source.id
		elseif self.source.type == "profile" then -- Lazer
			self.event.id = self.source.id
--[[
		elseif self.source.type == "manual" and fibaro:args() then -- Note : démarrage manuel de la scène, à remplacer par une fonction dédiée au QuickApp ?
			local params = {}
			for _, v in ipairs(fibaro:args()) do for h, w in pairs(v) do if h == "gealine" then line = w end if h == "result" then result = w end params[h] = w end end
			if (params.vdid) then
				self:answer(params)
				return
			end
		elseif self.source.type == "custom-event" then
		elseif self.source.type == "date" then
		elseif self.source.type == "location" then
		elseif self.source.type == "panic" then
		elseif self.source.type == "se-start" then
		elseif self.source.type == "weather" then
		elseif self.source.type == "climate" then
--]]
		end
		if self.source.type ~= "manual" then tools.info(string.format(self.trad.gea_start_event, self.version, self.source.type, self.event.id), "cyan") end
	end
	--tools.info("GEA:init() self.event = " .. json.encode(self.event)) -- DEBUG
	self:searchPlugins()
	if line and result then
		-- retour d'un plugin
		if not self.plugins.retour then self.plugins.retour = {} end
		self.plugins.retour[line] = result
		fibaro.setGlobalVariable(self.pluginsvariables, json.encode(self.plugins))
		return
	end
	if self.auto then
		tools.info(self.trad.gea_load_usercode, "yellow")
		tools.info("--------------------------------------------------------------------------------")
		--if tools.isNil(self:getGlobalValue(self.globalvariables)) then api.post("/globalVariables", {name=self.globalvariables, isEnum=self.varenum}) end -- Lazer
		--if tools.isNil(self:getGlobalValue(self.historyvariable)) then api.post("/globalVariables", {name=self.historyvariable, isEnum=self.varenum}) end -- Lazer
		--if tools.isNil(self:getGlobalValue(self.suspendvar)) then api.post("/globalVariables", {name=self.suspendvar, isEnum=self.varenum}) end -- Lazer
		--fibaro.setGlobalVariable(self.globalvariables, "")
		quickApp:setVariable(self.globalvariables, "") -- Lazer
		--fibaro.setGlobalVariable(self.historyvariable, "")
		quickApp:setVariable(self.historyvariable, "") -- Lazer
		--fibaro.setGlobalVariable(self.suspendvar, self.trad.no)
		local suspendvar = quickApp:getVariable(self.suspendvar)
		if not suspendvar or suspendvar == "" then
			quickApp:setVariable(self.suspendvar, self.trad.no) -- Lazer
		end
		--local histo = self:getGlobalValue(self.historyvariable)
		local histo = quickApp:getVariable(self.historyvariable) -- Lazer
		if histo and histo ~= "" then self.history = json.decode(histo) else self.history = {} end
	end
	--self.globalvalue = self:getGlobalValue(self.globalvariables)
	self.globalvalue = quickApp:getVariable(self.globalvariables) -- Lazer
	setEvents() -- Chargement des règles utilisateur
	tools.isdebug = self.debug
	if #self.entries == 0 then tools.warning(self.trad.gea_nothing) end
	tools.info("--------------------------------------------------------------------------------")
	self.control = false
	if #self.entries > 0 then
		self.started = os.time()
		if self.auto then tools.info(string.format(self.trad.gea_start_time, os.date(self.trad.date_format, self.started), os.date(self.trad.hour_format, self.started))) end
		self:run()
	else
		if self.auto then
			tools.info(self.trad.gea_stopped_auto, "yellow")
			return
		else
			tools.warning(string.format(self.trad.no_entry_for_event, self.options.trigger.getValue()), "orange")
		end
	end
end



-- ================================================================================
-- M A I N ... démarrage de GEA
-- ================================================================================

function QuickApp:onInit()
	setTimeout(self.start, 0)
end


function QuickApp:start()

	-- Initialisation
	triggers = {}
	local lastRefresh = 0
	local http = net.HTTPClient()

	-- Démarre l'instance principale de GEA
	GEA_auto = GEA({type = "autostart"})
	GEA_auto:init()

	-- Boucle d'attente d'événements instantanés
	local function loop()
		local stat,res = http:request("http://127.0.0.1:11111/api/refreshStates?last=" .. lastRefresh, {
			success = function(res)
				local states = json.decode(res.data)
				if type(states) == "table" then
					lastRefresh = states.last or 0
					for _, event in ipairs(states.events or {}) do
						for i = 1, #triggers do
							--tools.debug(json.encode(triggers[i]))
							if tools.filterEvent(event, triggers[i].filter) then
								if GEA_auto.lldebug then tools.debug("Event : " .. json.encode(triggers[i].filter), "blue") end
								if GEA_event then
									-- n'est jamais censé se produire
									tools.warning("GEA_event existe déjà", "orange")
								else
									-- Démarre une instance instantanée de GEA
									GEA_event = GEA(triggers[i].event)
									GEA_event:init()
									GEA_event = nil
								end
							end
						end
					end
				end
				--fibaro.setGlobalVariable(tickEvent, tostring(os.clock()) -- Hack because refreshState hangs if no event : https://forum.fibaro.com/topic/49113-hc3-quickapps-coding-tips-and-tricks/?tab=comments#comment-201173
				setTimeout(loop, GEA_auto.refreshInterval)
			end,
			error = function(res)
				self:error("Error : refreshStates : " .. res)
				setTimeout(loop, 2 * GEA_auto.refreshInterval)
			end,
		})
	end

	if #triggers > 0 then
		--tools.warning("triggers[" .. #triggers .. "] => " .. json.encode(triggers))
		for i = 1, #triggers do
			--tools.info("ID : " .. json.encode(triggers[i]), "blue")
			tools.info(GEA_auto.trad.instant_trigger .. triggers[i].event.type
				.. " " .. (triggers[i].event.id or triggers[i].event.name)
				.. " " .. (triggers[i].event.property or triggers[i].event.propertyName or "") .. " " .. (triggers[i].event.componentName or "")
				.. " " .. (triggers[i].event.value and (triggers[i].event.value.keyId or " ") .. " " .. (triggers[i].event.value.keyAttribute or " ") or "")
				, "blue")
		end
		loop()
	end

end


function QuickApp:buttonON_onReleased(event)
	self:trace("Réactivation de GEA")
	quickApp:setVariable(GEA_auto.suspendvar, GEA_auto.trad.no)
	self:updateView("labelRunning", "text", "Running : " .. GEA_auto.trad.yes)
end


function QuickApp:buttonOFF_onReleased(event)
	self:trace("Désactivation de GEA")
	quickApp:setVariable(GEA_auto.suspendvar, GEA_auto.trad.yes)
	self:updateView("labelRunning", "text", "Running : " .. GEA_auto.trad.no)
end
