-- =================================================================================================
-- QuickApp      : GEA : Gestionnaire d'Evénements Automatique
-- Auteurs       : Steven en collaboration avec Pepite et Thibaut
--                 Lazer : QuickApp pour HC3
-- Version       : 7.33
-- Date          : Juillet 2021
-- Remerciements : Tous les utilisateurs/testeurs/apporteurs d'idées du forum domotique-fibaro.fr
-- =================================================================================================


-- ================================================================================
-- Initialisation des variables locales à GEA
-- ================================================================================

__TAG = "QA_GEA_" .. plugin.mainDeviceId

-- Assign global variables to local variables for performance optimization
local fibaro = fibaro
local json = json
local api = api
local setTimeout = setTimeout
local tostring = tostring
local string = string
local pcall = pcall
local type = type
local math = math
local os = os
local tools = tools
local config = config
local setEvents = setEvents

-- GEA instances
local GEA_auto, GEA_event
local triggers = {}
local running, globalvalue, language
local variablesCache = {}
local askAnswerAction

-- Cache
local propertyList, qaLabelList, qaSliderList, vgList
local deviceNameToId = {}
local sceneNameToId = {}
local mobileNameToId = {}
local userNameToId = {}
local alarmNameToId = {}
local profileNameToId = {}
local climateNameToId = {}
local deviceIdToName = {}
local roomIdToName = {}
local sceneIdToName = {}
local partitionIdToName = {}
local profileIdToName = {}
local customEventName = {}


-- ================================================================================
-- GEA Class Constructor
-- ================================================================================

class "GEA"

function GEA:__init(source)

	-- Paramètres modifiables par l'utilisateur dans config()
	self.checkEvery        = 30                 -- durée en secondes
	self.control           = true               -- vérifie les paramètres des options
	self.debug             = false              -- mode d'affichage debug on/off
	self.lldebug           = false              -- mode d'affichage debug de bas niveau
	self.secureAction      = true               -- utilise pcall() ou pas
	self.language          = nil                -- force une langue spécifique si différente du système
	self.suspendvar        = "SuspendreGEA"     -- Variable interne du QuickApp GEA
	self.historyvariable   = "GEA_History"      -- historique
	self.historymax        = 5                  -- historique
	self.refreshInterval   = 100                -- durée en millisecondes
	self.optimize          = true               -- optimisation de la mémoire
	self.portables         = {}                 -- notifications
	self.output            = nil                -- notifications
	self.showRoomNames     = true               -- nom des pièces
	self.batteriesWithRoom = self.showRoomNames -- nom des pièces
	self.emailSubject      = "GEA"              -- sujet du mail
	self.notificationTitle = "GEA"              -- titre de la notification

	-- Paramètres internes
	self.version            = 7.33
	self._VERSION           = "7.33"
	self.source             = source
	self.auto               = self.source.type == "autostart"
	self.runAt              = nil
	self.nbRun              = -1
	self.stoppedTasks       = {}
	self.history            = {}
	self.garbagevalues      = {}
	self.usedoptions        = {}
	self.event              = {}
	self.declared           = {}
	self.forceRefreshValues = false
	self.options_id         = 0
	self.id_entry           = 0
	self.entries            = {}
	self.currentMainId      = nil
	self.currentEntry       = nil

	self.refreshDeviceProperties    = true
	self.refreshLabelValues         = true
	self.refreshSliderValues        = true
	self.refreshClimatePanel        = true
	self.refreshPartitionProperties = true
	self.refreshGlobalVariables     = true
	self.refreshQuickAppVariables   = true
	self.refreshSceneProperties     = true
	self.refreshWeather             = true
	self.refreshActiveProfile       = true
	self.refreshSettingsInfo        = true

	self.cachedDeviceProperties    = {}
	self.cachedLabelValues         = {}
	self.cachedSliderValues        = {}
	self.cachedClimatePanel        = {}
	self.cachedPartitionProperties = {}
	self.cachedGlobalVariables     = {}
	self.cachedQuickAppVariables   = {}
	self.cachedSceneProperties     = {}
	self.cachedWeatherProperties   = {}
	self.cachedActiveProfile       = nil
	self.cachedCustomEvents        = {}
	self.cachedSettingsInfo        = {}

	--self.firmware           = api.get("/settings/info").currentVersion.version
	--self.pluginsvariables   = "GEA_Plugins"
	--self.pluginretry        = 500
	--self.pluginmax          = 5
	--self.plugins            = {}
	--self.pluginsreturn      = {}

	self.traduction = {
		en = {
			id_missing            = "ID : %s doesn't exists",
			global_missing        = "Global : %s doesn't exists",
			label_missing         = "Label : [%d] %s doesn't exists",
			slider_missing        = "Slider : [%d] %s doesn't exists",
			not_number            = "%s must be a number",
			not_string            = "%s must be a string",
			from_missing          = "&lt;from&gt; is mandatory",
			central_instant       = "CentralSceneEvent works only with event instance",
			central_missing       = "id, key et attribute are mandatory",
			property_missing      = "Property : %s can't be found",
			option_missing        = "Option <b>%s</b> is missing",
			not_an_action         = "Option : %s can't be used as an action",
			not_a_trigger         = "Option : %s can't be used as a trigger",
			not_math_op           = "Option : %s doesn't allow + or - operations",
			hour                  = "hour",
			hours                 = "hours",
			andet                 = "and",
			minute                = "minute",
			minutes               = "minutes",
			second                = "second",
			seconds               = "seconds",
			err_cond_missing      = "Error : condition(s) required",
			err_dur_missing       = "Error : duration required",
			err_msg_missing       = "message required, empty string is allowed",
			err_rule_excluded     = "Rule excluded",
			not_an_condition      = "Option : %s can't be used as a condition",
			no_action             = "< no action >",
			repeated              = "repeat",
			stopped               = "stopped",
			maxtime               = "MaxTime",
			add_event             = "Add immediately",
			add_auto              = "Add auto",
			gea_failed            = "GEA ... STOPPED",
			validate              = "Validation",
			action                = "action",
			err_check             = "Error, check : ",
			date_format           = "%d.%m.%y",
			hour_format           = "%X",
			input_date_format     = "dd/mm/yyyy",
			quit                  = "Quit",
			gea_run_since         = "GEA run since %s",
			gea_check_nbr         = "... check running #%d @%ds...",
			gea_start             = "GEA %s started automatically: mode %s",
			gea_start_event       = "GEA %s started by event: mode %s",
			gea_tools             = "Use tools library v%s",
			gea_check_every       = "Check automatic every %s seconds",
			gea_global_create     = "Creation of %s global variable",
			gea_qa_variable       = "GEA QuickApp variable : %s",
			gea_load_usercode     = "Loading user code setEvents() :",
			err_no_usercode       = "Error : no setEvents() function found",
			gea_nothing           = "No entry to check in automatic mode",
			gea_start_time        = "GEA started in automatic mode on %s at %s ...",
			gea_stopped_auto      = "GEA has stopped running in automatic mode",
			week_short            = {"mo", "tu", "we", "th", "fr", "sa", "su"},
			week                  = {"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"},
			months                = {"january", "febuary", "march", "april", "may", "juin", "july", "august", "september", "october", "november", "december"},
			weekend               = "Weekend",
			weekdays              = "Weekdays",
			weather               = {"clear", "cloudy", "rain", "snow", "storm", "fog"},
			search_plugins        = "Searching plugins :",
			plugins_none          = "Found any",
			plugin_not_found      = "Plugin not found",
			memoryused            = "Memory used: %.2f KB",
			cpuused               = "CPU consumed: %.2f ms ( %.3f %% )",
			optimization          = "Optimization...",
			removeuseless         = "Removing useless option: ",
			removeuselesstrad     = "Removing useless traduction: ",
			start_entry           = "Started",
			no_entry_for_event    = "No entry for this event %s, please remove it from header",
			locale                = "en-US",
			execute               = "Démarrer",
			name_is_missing       = "Name isn't specified",
			room_is_missing       = "Room isn't specified",
			device_is_missing     = "Device \"<b>%s</b>\" unknown",
			scene_is_missing      = "Scene \"<b>%s</b>\" unknown",
			partition_missing     = "Alarm partition missing",
			partition_unknown     = "Alarm partition \"<b>%s</b>\" unknown",
			user_missing          = "User \"<b>%s</b>\" unknown",
			profile_missing       = "Profile missing",
			profile_unknown       = "Profile \"<b>%s</b>\" unknown",
			ask_id_invalid        = "Invalid \"<b>%s</b>\" action parameter",
			custom_event_unknown  = "Custom event \"<b>%s</b>\" unknown",
			mac_missing           = "MAC address missing",
			param_missing         = "Parameter missing",
			http_missing          = "HTTP request \"<b>url</b>\" missing",
			call_missing          = "Call \"<b>id</b>\" or \"<b>action</b>\" missing",
			custom_event_missing  = "Custom event missing",
			climate_panel_missing = "Climate zone missing",
			climate_panel_unknown = "Climate zone \"<b>%s</b>\" unknown",
			climate_mode_missing  = "Climate mode missing",
			climate_mode_unknown  = "Climate mode \"<b>%s</b>\" not supported",
			doorlock_action       = "Invalid DoorLock action",
			alarm_unknown         = "Invalid <b>%d</b> alarm number",
			instant_trigger       = "Event triggers: %d",
			no_instant_trigger    = "No event trigger in event mode",
			gea_suspended         = "GEA suspended (variable : %s) ...",
			yes                   = "yes",
			no                    = "no",
		},
		fr = {
			id_missing            = "ID : %s n'existe(nt) pas",
			global_missing        = "Global : %s n'existe(nt) pas",
			label_missing         = "Label : [%d] %s n'existe pas",
			slider_missing        = "Slider : [%d] %s n'existe pas",
			not_number            = "%s doit être un numéro",
			not_string            = "%s doit être une chaîne de caractères",
			from_missing          = "&lt;from&gt; est obligatoire",
			central_instant       = "CentralSceneEvent ne fonctionne qu'avec des déclenchements instantanés",
			central_missing       = "id, key et attribute sont obligatoires",
			property_missing      = "Propriété: %s introuvable",
			option_missing        = "Option <b>%s</b> n'existe pas",
			not_an_action         = "Option : %s ne peut pas être utilisé comme action",
			not_a_trigger         = "Option : %s ne peut pas être utilisé comme trigger",
			not_math_op           = "Option : %s n'autorise pas les + ou -",
			hour                  = "heure",
			hours                 = "heures",
			andet                 = "et",
			minute                = "minute",
			minutes               = "minutes",
			second                = "seconde",
			seconds               = "secondes",
			err_cond_missing      = "Erreur : condition(s) requise(s)",
			err_dur_missing       = "Erreur : durée requise",
			err_msg_missing       = "message requis, chaîne vide autorisée",
			err_rule_excluded     = "Règle exclue",
			not_an_condition      = "Option : %s ne peut pas être utilisé comme une condition",
			no_action             = "< pas d'action >",
			repeated              = "répété",
			stopped               = "stoppé",
			maxtime               = "MaxTime",
			add_event             = "Ajout immédiat",
			add_auto              = "Ajout auto",
			gea_failed            = "GEA ... ARRETE",
			validate              = "Validation",
			action                = "action",
			err_check             = "Erreur, vérifier : ",
			date_format           = "%d.%m.%y",
			hour_format           = "%X",
			input_date_format     = "dd/mm/yyyy",
			quit                  = "Quitter",
			gea_run_since         = "GEA fonctionne depuis %s",
			gea_check_nbr         = "... vérification en cours #%d @%ds...",
			gea_start             = "Démarrage automatique de GEA %s : mode %s",
			gea_start_event       = "Démarrage par événement de GEA %s : mode %s",
			gea_tools             = "Utilisation de la librairie tools v%s",
			gea_check_every       = "Vérification automatique toutes les %s secondes",
			gea_global_create     = "Création de la variable globale : %s",
			gea_qa_variable       = "Variable QuickApp GEA : %s",
			gea_load_usercode     = "Chargement du code utilisateur setEvents() :",
			err_no_usercode       = "Erreur : pas de fonction setEvents() trouvée pour le code utilisateur",
			gea_nothing           = "Aucun traitement à effectuer en mode automatique",
			gea_start_time        = "GEA a démarré en mode automatique le %s à %s ...",
			gea_stopped_auto      = "GEA est arrêté en mode automatique",
			week_short            = {"lu", "ma", "me", "je", "ve", "sa", "di"},
			week                  = {"lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"},
			months                = {"janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"},
			weekend               = "Weekend",
			weekdays              = "Semaine",
			weather               = {"dégagé", "nuageux", "pluvieux", "neigeux", "orageux", "brouillard"},
			search_plugins        = "Recherche de plugins :",
			plugins_none          = "Aucun plugin trouvé",
			plugin_not_found      = "Plugin inexistant",
			memoryused            = "Mémoire utilisée : %.2f Ko",
			cpuused               = "CPU utilisé : %.2f ms ( %.3f %% )",
			optimization          = "Optimisation en cours ...",
			removeuseless         = "Suppression d'option inutile : ",
			removeuselesstrad     = "Suppression de traduction inutile : ",
			start_entry           = "Démarrage",
			no_entry_for_event    = "Aucune entrée pour l'événement %s, supprimer le de l'entête",
			locale                = "fr-FR",
			execute               = "Execute",
			name_is_missing       = "Nom inconnu",
			room_is_missing       = "Pièce inconnue",
			device_is_missing     = "Module \"<b>%s</b>\" inconnu",
			scene_is_missing      = "Scène \"<b>%s</b>\" inconnue",
			partition_missing     = "Zone d'alarme manquante",
			partition_unknown     = "Zone d'alarme \"<b>%s</b>\" inconnue",
			user_missing          = "Utilisateur \"<b>%s</b>\" inconnu",
			profile_missing       = "Profil manquant",
			profile_unknown       = "Profil \"<b>%s</b>\" inconnu",
			ask_id_invalid        = "Paramètre action \"<b>%s</b>\" invalide",
			custom_event_unknown  = "Événement personnalisé \"<b>%s</b>\" inconnu",
			mac_missing           = "Adresse MAC manquante",
			param_missing         = "Paramètre manquant",
			http_missing          = "Requête HTTP \"<b>url</b>\" manquante",
			call_missing          = "Call \"<b>id</b>\" ou \"<b>action</b>\" manquant",
			custom_event_missing  = "Événement personnalisé manquant",
			climate_panel_missing = "Zone de climat manquante",
			climate_panel_unknown = "Zone de climat \"<b>%s</b>\" inconnue",
			climate_mode_missing  = "Mode de climat manquant",
			climate_mode_unknown  = "Mode de climat \"<b>%s</b>\" non supporté",
			doorlock_action       = "Action invalide pour DoorLock",
			alarm_unknown         = "Numéro d'alarme <b>%d</b> invalide",
			instant_trigger       = "Déclencheurs instantanés : %d",
			no_instant_trigger    = "Aucun déclencheur instantané en mode événement",
			gea_suspended         = "GEA suspendu (variable : %s) ...",
			yes                   = "oui",
			no                    = "non",
		}
	}

	-- ================================================================================
	-- Tous ce que GEA sait faire est ici
	-- ================================================================================
	-- --------------------------------------------------------------------------------
	-- Déclaration de toutes les fonctions de GEA
	--   f    = {name = "Nouvelle fonction",
	--              optimize   = true,
	--              math       = true, -- autorise les + et -
	--              keepValues = true, -- ne traduit pas les sous-table {"TurnOn", 73} reste ainsi et non pas true ou false
	--              depends    = {"value"},
	--              control    = function(name, value) if (...) then return true else return false, "Message d'erreur" end end,
	--              getValue   = function(name) return <la valeur> end,
	--              action     = function(name, value) <effectuer l'action> end,
	--              getName    = function(name) return <le nom> end,
	--              getRoom    = function(name) return <la pièce> end,
	--              trigger    = function(id) return {event = {}, filter = {}} end,
	--              isBoolean  = true, -- ne compare pas le résultat
	--          },
	-- --------------------------------------------------------------------------------
	self.options = {
		number    = {name = "ID",
									control  = function(id) if type(id) ~= "table" then id = {id} end local res, msg = true, "" for i=1, #id do if not self:getDeviceProperty(id[i]) then res = false msg = msg .. self:findDeviceId(id[i]) .. " " end end return res, string.format(self.trad.id_missing, msg) end,
									getValue = function(id) return self:getDeviceProperty(id, "value") end,
									trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value"}}} end,
		},
		boolean   = {name = "Boolean",
									getValue = function(bool) return bool end,
		},
		value     = {name = "Value",
									optimize = true,
									math     = true, -- autorise les Value+ et Value-
									control  = function(id) return self.options.number.control(id) end,
									getValue = function(id) if not id then id = self.currentMainId end return self:getDeviceProperty(id, "value") end,
									action   = function(id, value)
										if not value then value = id id = self.currentMainId end
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findDeviceId(id[i])
											self.cachedDeviceProperties[id_num] = {}
											fibaro.call(id_num,"setValue",self:incdec(value, self.options.value.getValue(id_num)))
										end
									end,
									trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value"}}} end,
		},
		value2    = {name = "Value2",
									optimize = true,
									math     = true,
									control  = function(id) return self.options.value.control(id) end,
									getValue = function(id) if not id then id = self.currentMainId end return self:getDeviceProperty(id, "value2") end,
									action   = function(id, value)
										if not value then value = id id = self.currentMainId end
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findDeviceId(id[i])
											self.cachedDeviceProperties[id_num] = {}
											fibaro.call(id_num,"setValue2",self:incdec(value, self.options.value2.getValue(id_num)))
										end
									end,
									trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value2"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value2"}}} end,
		},
		power    = {name = "Power",
									optimize = true,
									math     = true,
									control  = function(id) if not id then id = self.currentMainId end return self.options.number.control(id) end,
									getValue = function(id) if not id then id = self.currentMainId end return self:getDeviceProperty(id, "power") end,
									trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "power"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "power"}}} end,
		},
		property  = {name = "Property",
									optimize = true,
									math     = true,
									control  = function(id) return self.options.number.control(id) end,
									getValue = function(id, property) return self:getDeviceProperty(id, property) end,
									action   = function(id, property, value)
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findDeviceId(id[i])
											self.cachedDeviceProperties[id_num] = {}
											fibaro.call(id_num, "updateProperty", property, self:getMessage(self:incdec(value, self.options.property.getValue(id_num, property))))
										end
									end,
									trigger  = function(id, property) return {event = {type = "device", id = self:findDeviceId(id), property = property}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = property}}} end,
		},
		checkproperty = {name = "CheckProperty",
									getValue  = function(id, property)
										if not propertyList then
											propertyList = {}
										end
										local id_num = self:findDeviceId(id)
										if not propertyList[id_num] then
											propertyList[id_num] = {}
										end
										if not propertyList[id_num][property] then
											propertyList[id_num][property] = self:getDeviceProperty(id_num, property) ~= nil
										end
										return propertyList[id_num][property]
									end,
									isBoolean = true,
		},
		turnon    = {name = "TurnOn",
									optimize  = true,
									control   = function(id) if not id then id = self.currentMainId end return self.options.number.control(id) end,
									getValue  = function(id) if not id then id = self.currentMainId end local val = self:getDeviceProperty(id, "value") return type(val)=="boolean" and val or type(val)=="number" and val>0 or type(val)=="string" and val~="" or false end,
									action    = function(id, duree)
										if not id then id = self.currentMainId end
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findDeviceId(id[i])
											self.cachedDeviceProperties[id_num] = {}
											fibaro.call(id_num, "turnOn")
										end
										if duree then setTimeout(function() for i=1, #id do fibaro.call(self:findDeviceId(id[i]),"turnOff") end end, self:getDuree(duree) * 1000)
										end
									end,
									trigger   = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value"}}} end,
									isBoolean = true,
		},
		turnoff   = {name = "TurnOff",
									optimize  = true,
									control   = function(id) if not id then id = self.currentMainId end return self.options.number.control(id) end,
									getValue  = function(id) if not id then id = self.currentMainId end local val = self:getDeviceProperty(id, "value") return not(type(val)=="boolean" and val or type(val)=="number" and val>0 or type(val)=="string" and val~="" or false) end,
									action    = function(id, duree)
										if not id then id = self.currentMainId end
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findDeviceId(id[i])
											self.cachedDeviceProperties[id_num] = {}
											fibaro.call(id_num, "turnOff")
										end
										if duree then setTimeout(function() for i=1, #id do fibaro.call(self:findDeviceId(id[i]),"turnOn") end end, self:getDuree(duree) * 1000)
										end
									end,
									trigger   = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value"}}} end,
									isBoolean = true,
		},
		open      = {name = "Open",
									optimize = true,
									math     = true,
									depends  = {"value"},
									control  = function(id) return self.options.number.control(id) end,
									getValue = function(id) return math.abs(-100+tonumber(self.options.value.getValue(id))) end,
									action   = function(id, value) if not id then id = self.currentMainId end if type(id) ~= "table" then id = {id} end if not value then value = 100 end for i=1, #id do self.options.value.action(id[i], value) end end,
									trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value"}}} end,
		},
		close     = {name = "Close",
									optimize = true,
									math     = true,
									depends  = {"value"},
									control  = function(id) return self.options.number.control(id) end,
									getValue = function(id) return self.options.value.getValue(id) end,
									action   = function(id, value) if not id then id = self.currentMainId end if type(id) ~= "table" then id = {id} end if not value then value = 100 end for i=1, #id do self.options.value.action(id[i], math.abs(-100+value)) end end,
									trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "value"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "value"}}} end,
		},
		stop      = {name = "Stop",
									optimize = true,
									control  = function(id) return self.options.number.control(id) end,
									action   = function(id) if type(id) ~= "table" then id = {id} end for i=1, #id do local id_num = self:findDeviceId(id[i]) self.cachedDeviceProperties[id_num] = {} fibaro.call(id_num, "stop") end end,
		},
		battery   = {name = "Battery",
									optimize = true,
									math     = true,
									control  = function(id) return self.options.number.control(id) end,
									getValue = function(id) return self:getDeviceProperty(id, "batteryLevel") end,
									trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "batteryLevel"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "batteryLevel"}}} end,
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
									getValue  = function(id) return self:getDeviceProperty(id, "dead") end,
									action    = function(id) self.refreshDeviceProperties = true if type(id) ~= "table" then id = {id} end for i=1, #id do local response, status = api.post("/devices/" .. tostring(self:findDeviceId(id[i])) .. "/action/wakeUpDeadDevice", {}) assert(status == 202, response) end end,
									trigger   = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "dead"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "dead"}}} end,
									isBoolean = true,
		},
		deads     = {name = "Deads",
									optimize  = true,
									depends   = {"dead"},
									getValue  = function() local devices = api.get("/devices?property=[dead,true]&enabled=true") return #devices>0, #devices end,
									action    = function() self.refreshDeviceProperties = true local devices = api.get("/devices?property=[dead,true]&enabled=true&interface=zwave&parentId=1") for _, v in pairs(devices) do self.options.dead.action(v.id) end end,
									getName   = function() return "" end,
									getRoom   = function() return "" end,
									isBoolean = true,
		},
		polling   = {name = "Polling",
									optimize = true,
									control  = function(id) return self.options.number.control(id) end,
									action   = function(id) self.refreshDeviceProperties = true if type(id) ~= "table" then id = {id} end for i=1, #id do local response, status = api.post("/devices/" .. tostring(self:getParentDevice(id[i]).id) .. "/action/poll", {}) assert(status == 202, response) end end,
		},
		devicestate = {name = "DeviceState",
									optimize = true,
									getValue = function(id) return self:getParentDevice(id).properties.deviceState end,
		},
		neighborlist = {name = "NeighborList",
									optimize  = true,
									control   = function(id) return self.options.number.control(id) end,
									ids       = "",
									getValue  = function(id)
										local device = self:getParentDevice(id)
										self.options.neighborlist.ids = device.properties.neighborList
										return json.encode(device.properties.neighborList)
									end,
									getName   = function() local n = self:getDeviceFullName(self.options.neighborlist.ids, self.showRoomNames) return n end,
		},
		lastworkingroute = {name = "LastWorkingRoute",
									optimize  = true,
									control   = function(id) return self.options.number.control(id) end,
									ids       = "",
									getValue  = function(id)
										local device = self:getParentDevice(id)
										self.options.lastworkingroute.ids = device.properties.lastWorkingRoute
										return json.encode(device.properties.lastWorkingRoute)
									end,
									getName   = function() local n = self:getDeviceFullName(self.options.lastworkingroute.ids, self.showRoomNames) return n end,
		},
		program   = {name = "Program",
									optimize = true,
									math     = true,
									getValue = function(id) return self:getDeviceProperty(id, "currentProgramID") end,
									action   = function(id, prog) if type(id) ~= "table" then id = {id} end for i=1, #id do local id_num = self:findDeviceId(id[i]) self.cachedDeviceProperties[id_num] = {} fibaro.call(id_num, "startProgram", prog) end end,
									trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "currentProgramID"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "currentProgramID"}}} end,
		},
		rgb       = {name = "RGB",
									optimize = true,
									control  = function(id) return self.options.number.control(id) end,
									action   = function(id, r, g, b, w) if type(id) ~= "table" then id = {id} end for i=1, #id do local id_num = self:findDeviceId(id[i]) self.cachedDeviceProperties[id_num] = {} fibaro.call(id_num, "setColor", r or 0, g or 0, b or 0, w or 0) end end,
		},
		hue       = {name = "Hue",
									optimize = true,
									math     = true,
									control  = function(id) return self.options.number.control(id) end,
									getValue = function(id, property) if not id then id = self.currentMainId end return self:getDeviceProperty(id, property) end,
									getHubParam=function(id)
										local lightid = self:getDeviceProperty(id, "lightId")
										local parent = self:getParentDevice(id)
										return lightid, parent.properties.ip, parent.properties.userName
									end,
									action   = function(id, property, value) if type(id) ~= "table" then id = {id} end
										local http = net.HTTPClient()
										for i=1, #id do
											local id_num = self:findDeviceId(id[i])
											self.cachedDeviceProperties[id_num] = {}
											local lightid, ip, username = self.options.hue.getHubParam(id_num)
											local datas = "{\""..property.."\":"..tools:iif(type(value)=="boolean", tostring(value), value).."}"
											http:request("http://"..ip.."/api/"..username.."/lights/"..lightid.."/state", { options = {method = "PUT", data = datas}, success = function(response) end, error = function(err) tools:error(err) end })
										end
									end,
		},
		doorlock  = {name = "DoorLock",
									optimize  = true,
									control   = function(id) return self.options.number.control(id) end,
									getValue  = function(id) if not id then id = self.currentMainId end return self:getDeviceProperty(id, "secured") == 0 end,
									action    = function(id, value)
										if not id then id = self.currentMainId end
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findDeviceId(id[i])
											self.cachedDeviceProperties[id_num] = {}
											if value == "secure" then
												fibaro.call(id_num, "secure")
											elseif value == "unsecure" then
												fibaro.call(id_num, "unsecure")
											else
												error(self.trad.doorlock_action)
											end
										end
									end,
									trigger   = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "secured"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "secured"}}} end,
									isBoolean = true,
		},
		protection = {name = "Protection", -- par 971jmd
									optimize  = true,
									depends   = {"property"},
									getValue  = function(id)
										local loc = tonumber(self:getDeviceProperty(id, "localProtectionState")) > 0
										local rf = tonumber(self:getDeviceProperty(id, "RFProtectionState")) > 0
										local result = "Off"
										if loc then result = "Local" end
										if rf then result = "RF" end
										if loc and rf then result = "Local_RF" end
										return result
									end,
									control   = function(id) if not id then id = self.currentMainId end return self.options.number.control(id) end,
									action    = function(id, typeprotection, mode)
										if type(id) ~= "table" then id = {id} end
										local arg1 = "0"
										local arg2 = 0
										if typeprotection:lower() == "local_rf" then
											if mode:lower() == "on" then arg1 = "2" arg2 = 1 end
										elseif typeprotection:lower() == "local" then
											if mode:lower() == "on" then arg1 = "2" arg2 = 0 end
										elseif typeprotection:lower() == "rf" then
											if mode:lower() == "on" then arg1 = "0" arg2 = 1 end
										end
										for i=1, #id do
											local id_num = self:findDeviceId(id[i])
											self.cachedDeviceProperties[id_num] = {}
											fibaro.call(id_num, "setProtection", arg1, arg2)
										end
									end,
									isBoolean = true,
		},
		parameter = {name = "Parameter",
									optimize  = true,
									control   = function(id, param) return self.options.number.control(id) and type(param) == "number", self.trad.param_missing end,
									getValue  = function(id, param)
										local parameters = api.get("/devices/" .. self:findDeviceId(id) .. "/properties/parameters") or {}
										for _, parameter in pairs(parameters.value or {}) do
											if parameter.id and parameter.id == param then return parameter.value end
										end
									end,
									action    = function(id, param, value)
										local id = self:findDeviceId(id)
										self.cachedDeviceProperties[id] = {}
										local parameters = api.get("/devices/" .. id .. "/properties/parameters") or {}
										for _, parameter in pairs(parameters.value or {}) do
											if parameter.id == param then
												parameter.value = value
												local response, status = api.put("/devices/" .. id, {properties = {parameters = parameters}})
												assert(status == 200, response)
												break
											end
										end
									end,
		},
		roomlights = {name = "RoomLights",
									optimize = true,
									action   = function(roomName, action)
										local rooms = api.get("/rooms")
										for _, room in pairs(rooms) do
											if room.name:lower() == roomName:lower() then
												for _, device in pairs(api.get("/devices?property=[isLight,true]&roomID="..room.id)) do self.cachedDeviceProperties[device.id] = {} fibaro.call(device.id, action) end
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
		filters   = {name = "Filters",
									optimize = true,
									--control = function(id) return self.options.number.control(id) end,
									action   = function(typefilter, choicefilter)
										if typefilter:lower() == "lights" then
											for _,v in ipairs(fibaro.getDevicesID({properties = {isLight = true}})) do
												self.cachedDeviceProperties[v] = {}
												fibaro.call(v, choicefilter)
											end
										elseif typefilter:lower() == "blinds" then
											for _,v in ipairs(fibaro.getDevicesID({type = tools:tostring("com.fibaro.FGRM222")})) do
												self.cachedDeviceProperties[v] = {}
												fibaro.call(v, choicefilter)
											end
										end
									end,
		},
		switch    = {name = "Switch",
									optimize = true,
									control  = function(id) if not id then id = self.currentMainId end return self.options.number.control(id) end,
									action   = function(id)
										if not id then id = self.currentMainId end
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findDeviceId(id[i])
											self.cachedDeviceProperties[id_num] = {}
											local val = fibaro.getValue(id_num, "value")
											if type(val)=="boolean" and val or type(val)=="number" and val>0 or false then
												fibaro.call(id_num,"turnOff")
											else
												fibaro.call(id_num,"turnOn")
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
		transpose = {name = "Transpose",
									getValue  = function(table1, table2, value) return self:translate(value, table1, table2) end,
									action    = function(table1, table2, value) return self:translate(value, table1, table2) end,
									isBoolean = true,
		},
		sceneactivation = {name = "SceneActivation",
									optimize  = true,
									getValue  = function(id, value) return tonumber(self:getDeviceProperty(id, "sceneActivation")) == tonumber(value) end,
									trigger   = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "sceneActivation"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "sceneActivation"}}} end,
									--trigger   = function(id, value) return {event = {type = "device", id = self:findDeviceId(id), property = "sceneActivation"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "sceneActivation", newValue = value}}} end,
									--trigger   = function(id, value) return {event = {type = "device", id = self:findDeviceId(id), property = "sceneActivation"}, filter = {type = "SceneActivationEvent", data = {deviceId = self:findDeviceId(id), sceneId = value}}} end,
									isBoolean = true,
		},
		centralsceneevent = {name = "CentralSceneEvent",
									optimize  = true,
									control   = function(id, key, attribute)
										if self.currentEntry.getDuration() > -1 then return false, self.trad.central_instant end
										return self.options.number.control(id) and type(key)~="nil" and type(attribute)~="nil", self.trad.central_missing
									end,
									getValue  = function(id, key, attribute) return self.source.id == tonumber(self:findDeviceId(id)) and tostring(self.source.value.keyId) == tostring(key) and tostring(self.source.value.keyAttribute) == tostring(attribute) end,
									trigger   = function(id, key, attribute) return {event = {type = "device", id = self:findDeviceId(id), property = "centralSceneEvent", value = {keyId = key, keyAttribute = attribute}}, filter = {type = "CentralSceneEvent", data = {id = self:findDeviceId(id), keyId = key, keyAttribute = attribute}}} end,
									isBoolean = true,
		},
		deviceicon = {name = "DeviceIcon",
									optimize = true,
									control  = function(id) return self.options.number.control(id) end,
									getValue = function(id) return self:getDeviceProperty(id, "deviceIcon") end,
									action   = function(id, value) if type(id) ~= "table" then id = {id} end for i=1, #id do local id_num = self:findDeviceId(id[i]) self.cachedDeviceProperties[id_num] = {} fibaro.call(id_num, "updateProperty", "deviceIcon", tonumber(value)) end end,
		},
		quickapp  = {name = "QuickApp",
									optimize = true,
									control  = function(id, method) if type(id) ~= "table" then id = {id} end for i=1, #id do local check, message = self.options.number.control(self:findDeviceId(id[i])) if check then return type(method) == "string", string.format(self.trad.not_string, method) else return check, message end end end,
									action   = function(id, method, ...) if type(id) ~= "table" then id = {id} end for i=1, #id do local id_num = self:findDeviceId(id[i]) self.cachedDeviceProperties[id_num] = {} self.cachedQuickAppVariables[id_num] = {} fibaro.call(id_num, method, table.unpack({...})) end end,
		},
		label     = {name = "Label",
									optimize = true,
									math     = true,
									control  = function(id, property) if not self.options.checklabel.getValue(id, property) then return false, string.format(self.trad.label_missing, id, property) else return true end end,
									getValue = function(id, property) return self:getLabelValue(id, property) end,
									action   = function(id, property, value)
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findDeviceId(id[i])
											self.cachedLabelValues[id_num] = {}
											local status = tools.updateLabel(id_num, property, self:getMessage(self:incdec(value, self.options.label.getValue(id_num, property))))
											assert(status == true, response)
											end
										end,
									trigger  = function(id, property) return {event = {type = "device", id = self:findDeviceId(id), propertyName = "text", componentName = property}, filter = {type = "PluginChangedViewEvent", data = {deviceId = self:findDeviceId(id), propertyName = "text", componentName = property}}} end,
		},
		slider    = {name = "Slider",
									math     = true,
									optimize = true,
									control  = function(id, property) if not self.options.checkslider.getValue(id, property) then return false, string.format(self.trad.slider_missing, id, property) else return true end end,
									getValue = function(id, property) return self:getSliderValue(id, property) end,
									action   = function(id, property, value)
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findDeviceId(id[i])
											self.cachedSliderValues[id_num] = {}
											--fibaro.call(id_num, "updateView", property, "value", tostring(value)) -- Ne déclenche pas la fonction callback associée au slider
											local qa = api.get("/devices/"..id_num.."/properties/uiCallbacks") or {}
											for j=1, #(qa.value or {}) do
												if qa.value[j].name == property then
													fibaro.call(id_num, qa.value[j].callback, {elementName = property, deviceId = id_num, eventType = qa.value[j].eventType, values = {value}})
													break
												end
											end
										end
									end,
									trigger = function(id, property) return {event = {type = "device", id = self:findDeviceId(id), propertyName = "value", componentName = property}, filter = {type = "PluginChangedViewEvent", data = {deviceId = self:findDeviceId(id), propertyName = "value", componentName = property}}} end,
		},
		checklabel = {name = "CheckLabel",
									getValue  = function(id, name)
										if not qaLabelList then
											local function addLabel(qaid, s)
												if type(s) == 'table' then
													if s.type == "label" then
														qaLabelList[qaid][s.name] = true
													end
													for _,v in pairs(s) do
														local r = addLabel(qaid, v)
														if r then
															return r
														end
													end
												end
											end
											qaLabelList = {}
											local qas = api.get("/devices?interface=quickApp&enabled=true") or {}
											for _, qa in pairs(qas) do
												qaLabelList[qa.id] = {}
												addLabel(qa.id, qa.properties.viewLayout["$jason"].body.sections)
											end
										end
										local id_num = self:findDeviceId(id)
										if not qaLabelList[id_num] then return false, string.format(self.trad.id_missing, id_num) end
										return qaLabelList[id_num][name] or false
									end,
									isBoolean = true,
		},
		checkslider = {name = "CheckSlider",
									getValue  = function(id, name)
										if not qaSliderList then
											local function addSlider(qaid, s)
												if type(s) == 'table' then
													if s.type == "slider" then
														qaSliderList[qaid][s.name] = true
													end
													for _,v in pairs(s) do
														local r = addSlider(qaid, v)
														if r then
															return r
														end
													end
												end
											end
											qaSliderList = {}
											local qas = api.get("/devices?interface=quickApp&enabled=true") or {}
											for _, qa in pairs(qas) do
												qaSliderList[qa.id] = {}
												addSlider(qa.id, qa.properties.viewLayout["$jason"].body.sections)
											end
										end
										local id_num = self:findDeviceId(id)
										if not qaSliderList[id_num] then return false, string.format(self.trad.id_missing, id_num) end
										return qaSliderList[id_num][name] or false
									end,
									isBoolean = true,
		},
		thermostatmode = {name = "ThermostatMode",
									optimize = true,
									control  = function(id) return self.options.number.control(id) end,
									getValue = function(id) return self:getDeviceProperty(id, "thermostatMode") end,
									action   = function(id, mode) if type(id) ~= "table" then id = {id} end for i=1, #id do local id_num = self:findDeviceId(id[i]) self.cachedDeviceProperties[id_num] = {} fibaro.call(id_num, "setThermostatMode", mode) end end,
									trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "thermostatMode"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "thermostatMode"}}} end,
		},
		heatingthermostatsetpoint = {name = "HeatingThermostatSetpoint",
									optimize = true,
									math     = true,
									control  = function(id) return self.options.number.control(id) end,
									getValue = function(id) return self:getDeviceProperty(id, "heatingThermostatSetpoint") end,
									action   = function(id, value) if type(id) ~= "table" then id = {id} end for i=1, #id do local id_num = self:findDeviceId(id[i]) self.cachedDeviceProperties[id_num] = {} fibaro.call(id_num, "setHeatingThermostatSetpoint", self:incdec(value, self.options.heatingthermostatsetpoint.getValue(id_num))) end end,
									trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "heatingThermostatSetpoint"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "heatingThermostatSetpoint"}}} end,
		},
		coolingthermostatsetpoint = {name = "CoolingThermostatSetpoint",
									optimize = true,
									math     = true,
									control  = function(id) return self.options.number.control(id) end,
									getValue = function(id) return self:getDeviceProperty(id, "coolingThermostatSetpoint") end,
									action   = function(id, value) if type(id) ~= "table" then id = {id} end for i=1, #id do local id_num = self:findDeviceId(id[i]) self.cachedDeviceProperties[id_num] = {} fibaro.call(id_num, "setCoolingThermostatSetpoint", self:incdec(value, self.options.coolingthermostatsetpoint.getValue(id_num))) end end,
									trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "coolingThermostatSetpoint"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "coolingThermostatSetpoint"}}} end,
		},
		thermostatfanmode = {name = "ThermostatFanMode",
									optimize = true,
									control  = function(id) return self.options.number.control(id) end,
									getValue = function(id) return self:getDeviceProperty(id, "thermostatFanMode") end,
									action   = function(id, fan) if type(id) ~= "table" then id = {id} end for i=1, #id do local id_num = self:findDeviceId(id[i]) self.cachedDeviceProperties[id_num] = {} fibaro.call(id_num, "setThermostatFanMode", fan) end end,
									trigger  = function(id) return {event = {type = "device", id = self:findDeviceId(id), property = "thermostatFanMode"}, filter = {type = "DevicePropertyUpdatedEvent", data = {id = self:findDeviceId(id), property = "thermostatFanMode"}}} end,
		},
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
		climate = {name = "Climate",
									optimize  = true,
									math      = true,
									control   = function(id) return self:getClimatePanel(id) and true or false, string.format(self.trad.climate_panel_unknown, tostring(id)) end,
									getValue  = function(id, property)
										local climate = self:getClimatePanel(id)
										if string.lower(property) == "active" then
											return climate.active
										elseif string.lower(property) == "mode" then
											return climate.mode
										elseif string.lower(property) == "heat" then
											return climate.properties.currentTemperatureHeating
										elseif string.lower(property) == "cool" then
											return climate.properties.currentTemperatureCooling
										end
									end,
									action    = function(id, mode, heat_value, cool_value, duration)
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											self.cachedClimatePanel[self:findClimateId(id[i])] = nil
											local id_num = self:findClimateId(id[i])
											assert(type(mode) == "string", self.trad.climate_mode_missing)
											local climate_properties = api.get("/panels/climate/" .. id_num).properties
											local climate_mode = climate_properties.mode
											local properties = {}
											local derogation = false
											local setPointHeating, setPointCooling
											if string.lower(mode) == "vacation" then
												local now = os.date("*t", self.runAt)
												local begin = os.time{year = now.year, month = now.month, day = now.day, hour = 0, min = 0, sec = 0} -- Today
												local finish = os.time{year = now.year, month = now.month, day = now.day + (tonumber(duration) or 0), hour = 23, min = 59, sec = 59} -- Last day
												properties.vacationMode = climate_mode
												properties.handTimestamp = 0
												properties.vacationStartTime = begin
												properties.vacationEndTime = finish
												derogation = true
												setPointHeating = "vacationSetPointHeating"
												setPointCooling = "vacationSetPointCooling"
											elseif string.lower(mode) == "manual" then
												properties.handMode = climate_mode
												properties.handTimestamp = self.runAt + duration
												properties.vacationStartTime = 0
												properties.vacationEndTime = 0
												derogation = true
												setPointHeating = "handSetPointHeating"
												setPointCooling = "handSetPointCooling"
											elseif string.lower(mode) == "schedule" then
												properties.handTimestamp = 0
												properties.vacationStartTime = 0
												properties.vacationEndTime = 0
											else
												error(string.format(self.trad.climate_mode_unknown, mode))
											end
											if derogation then
												if climate_mode == "Auto" then
													properties[setPointHeating] = tonumber(heat_value) or climate_properties[setPointHeating]
													properties[setPointCooling] = tonumber(cool_value) or climate_properties[setPointCooling]
												elseif climate_mode == "Heat" then
													properties[setPointHeating] = tonumber(heat_value) or climate_properties[setPointHeating]
												elseif climate_mode == "Cool" then
													properties[setPointCooling] = tonumber(cool_value) or climate_properties[setPointCooling]
												end
											end
											local response, status = api.put("/panels/climate/" .. id_num, {properties = properties})
											assert(status == 200, response)
										end
									end,
									getName   = function(id) return self:getClimatePanel(id).name end,
		},
		armed     = {name = "Armed",
									optimize  = true,
									control   = function(id) return self:getPartitionProperty(id) and true or false, string.format(self.trad.partition_unknown, tostring(id)) end,
									getId     = function(id) return self:findPartitionId(id) end,
									getValue  = function(id) return self:getPartitionProperty(id, "armed") end,
									getName   = function(id) local n = self:getPartitionNameInCache(id) return n end,
									trigger   = function(id) local id_num = self:findPartitionId(id) if not id_num then error(string.format(self.trad.partition_unknown, id)) end return {event = {type = "alarm", id = id_num, property = "armed"}, filter = {type = "AlarmPartitionArmedEvent", data = {partitionId = id_num, armed = true}}} end,
									isBoolean = true,
		},
		disarmed  = {name = "Disarmed",
									optimize  = true,
									control   = function(id) return self:getPartitionProperty(id) and true or false, string.format(self.trad.partition_unknown, tostring(id)) end,
									getId     = function(id) return self:findPartitionId(id) end,
									getValue  = function(id) return not self:getPartitionProperty(id, "armed") end,
									getName   = function(id) local n = self:getPartitionNameInCache(id) return n end,
									trigger   = function(id) local id_num = self:findPartitionId(id) if not id_num then error(string.format(self.trad.partition_unknown, id)) end return {event = {type = "alarm", id = id_num, property = "armed"}, filter = {type = "AlarmPartitionArmedEvent", data = {partitionId = id_num, armed = false}}} end,
									isBoolean = true,
		},
		setarmed  = {name = "SetArmed",
									optimize  = true,
									control   = function(id) if type(id) ~= "table" then id = {id} end local res, msg = true, "" for i=1, #id do if not self:getPartitionProperty(id[i]) then res = false msg = msg .. tostring(id[i]) .. " " end end return res, string.format(self.trad.partition_unknown, msg) end,
									action    = function(id) if type(id) ~= "table" then id = {id} end for i=1, #id do local id_num = self:findPartitionId(id[i]) self.cachedPartitionProperties[id_num] = {} local response, status = api.post("/alarms/v1/partitions/" .. id_num .. "/actions/arm") assert(status == 204, response) end end,
		},
		setdisarmed = {name = "SetDisarmed",
									optimize  = true,
									control   = function(id) if type(id) ~= "table" then id = {id} end local res, msg = true, "" for i=1, #id do if not self:getPartitionProperty(id[i]) then res = false msg = msg .. tostring(id[i]) .. " " end end return res, string.format(self.trad.partition_unknown, msg) end,
									action    = function(id) if type(id) ~= "table" then id = {id} end for i=1, #id do local id_num = self:findPartitionId(id[i]) self.cachedPartitionProperties[id_num] = {} local response, status = api.delete("/alarms/v1/partitions/" .. id_num .. "/actions/arm") assert(status == 204, response) end end,
		},
		breached     = {name = "Breached",
									optimize  = true,
									control   = function(id) return type(id) == "nil" or self:getPartitionProperty(id) and true or false, string.format(self.trad.partition_unknown, tostring(id)) end,
									getValue  = function(id) if type(id) == "nil" then return #(api.get("/alarms/v1/partitions/breached") or {}) > 0 else return self:getPartitionProperty(id, "breached") end end,
									getName   = function(id) if type(id) == "nil" then return self:getSettingsInfo("hcName") else local n = self:getPartitionNameInCache(id) return n end end,
									trigger   = function(id)
										if type(id) == "nil" then
											return {event = {type = "alarm", property = "breached"}, filter = {type = "HomeBreachedEvent"}}
										else
											local id_num = self:findPartitionId(id) if not id_num then error(string.format(self.trad.partition_unknown, id)) end
											return {event = {type = "alarm", id = id_num, property = "breached"}, filter = {type = "AlarmPartitionBreachedEvent", data = {partitionId = id_num}}}
										end
									end,
									isBoolean = true,
		},
		global    = {name = "Global",
									optimize = true,
									math     = true, -- autorise les Global+ et Global-
									control  = function(name) if type(name) ~= "table" then name = {name} end local res, msg = true, "" for i=1, #name do if not self:getGlobalValue(name[i]) then res = false msg = msg .. name[i] .. " " end end return res, string.format(self.trad.global_missing, msg) end,
									getValue = function(name) return self:getGlobalValue(name) end,
									action   = function(name, value)
										if type(name) ~= "table" then name = {name} end
										for i=1, #name do
											self.cachedGlobalVariables[name] = nil
											fibaro.setGlobalVariable(name[i], self:getMessage(self:incdec(value, self.options.global.getValue(name[i]))))
										end
									end,
									trigger  = function(name) return {event = {type = "global-variable", name = name}, filter = {type = "GlobalVariableChangedEvent", data = {variableName = name}}} end,
		},
		copyglobal = {name = "CopyGlobal",
									optimize = true,
									control  = function(source, destination) return self.options.global.control({source, destination}) end,
									action   = function(source, destination) self.cachedGlobalVariables[destination] = nil fibaro.setGlobalVariable(destination, self:getGlobalValue(source)) end,
		},
		checkvg   = {name = "CheckVG",
									getValue  = function(name)
										if not vgList then
											vgList = {}
											for _, vg in pairs(api.get("/globalVariables")) do
												vgList[vg.name] = true
											end
										end
										return vgList[name] or false
									end,
									isBoolean = true,
		},
		variablecache = {name = "VariableCache",
									optimize = true,
									math     = true,
									getValue = function(var) return variablesCache[var] end,
									getName  = function(var) return var end,
									action   = function(var, value) local newValue = self:incdec(value, variablesCache[var]) variablesCache[var] = type(newValue) == "number" and newValue or self:getMessage(newValue) end,
		},
		variablequickapp = {name = "VariableQuickApp",
									optimize = true,
									math     = true,
									control  = function(id) return self.options.number.control(id) end,
									getValue = function(id, var) return self:getQuickAppVariableValue(id, var) end,
									getName  = function(id, var) return var end,
									action   = function(id, var, value) local id_num = self:findDeviceId(id) self.cachedQuickAppVariables[id_num] = {} local newValue = self:incdec(value, tools.getVariable(id_num, var)) fibaro.call(id_num, "setVariable", var, type(newValue) == "number" and newValue or self:getMessage(newValue)) end,
		},
		scene  = {name = "Scene",
									keepValues = true,
									control    = function(id) return self:getSceneProperty(id) and true or false end,
									getId      = function(id) return self:findSceneId(id) end,
									getValue   = function(id) return self:getSceneProperty(id, "isRunning") end,
									action     = function(id)
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findSceneId(id[i])
											self.cachedSceneProperties[id_num] = {}
											fibaro.scene("execute", {id_num})
										end
									end,
									getName    = function(id) local n = self:getSceneNameInCache(id) return n end,
									trigger    = function(id) local id_num = self:findSceneId(id) if not id_num then error(string.format(self.trad.scene_is_missing, id)) end return {event = {type = "scene", id = id_num}, filter = {type = "SceneStartedEvent", data = {id = id_num}}} end,
									isBoolean  = true,
		},
		kill      = {name = "Kill",
									optimize   = true,
									control    = function(id) return self.options.scenario.control(id) end,
									getId      = function(id) return self:findSceneId(id) end,
									getValue   = function(id) return not self:getSceneProperty(id, "isRunning") end,
									action     = function(id)
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findSceneId(id[i])
											self.cachedSceneProperties[id_num] = {}
											fibaro.scene("kill", {id_num})
										end
									end,
									getName    = function(id) local n = self:getSceneNameInCache(id) return n end,
									trigger    = function(id) local id_num = self:findSceneId(id) if not id_num then error(string.format(self.trad.scene_is_missing, id)) end return {event = {type = "scene", id = id_num}, filter = {type = "SceneFinishedEvent", data = {id = id_num}}} end,
									isBoolean  = true,
		},
		enablescene = {name = "EnableScene",
									optimize  = true,
									control   = function(id) return self.options.scenario.control(id) end,
									getValue  = function(id) return self:getSceneProperty(id, "enabled") end,
									action    = function(id)
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findSceneId(id[i])
											self.cachedSceneProperties[id_num] = {}
											local url = "/scenes/" .. id_num
											local scene = api.get(url)
											scene.enabled = true
											local response, status = api.put(url, scene)
											assert(status == 204, response)
										end
									end,
									isBoolean = true,
		},
		disablescene = {name = "DisableScene",
									optimize  = true,
									control   = function(id) return self.options.scenario.control(id) end,
									getValue  = function(id) return not self:getSceneProperty(id, "enabled") end,
									action    = function(id)
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findSceneId(id[i])
											self.cachedSceneProperties[id_num] = {}
											local url = "/scenes/" .. id_num
											local scene = api.get(url)
											scene.enabled = false
											local response, status = api.put(url, scene)
											assert(status == 204, response)
										end
									end,
									isBoolean = true,
		},
		runmodescene = {name = "RunModeScene",
									optimize = true,
									control  = function(id) return self.options.scenario.control(id) end,
									getValue = function(id) return self:getSceneProperty(id, "mode") end,
									action   = function(id, runmode)
										if type(id) ~= "table" then id = {id} end
										for i=1, #id do
											local id_num = self:findSceneId(id[i])
											self.cachedSceneProperties[id_num] = {}
											local url = "/scenes/" .. id_num
											local scene = api.get(url)
											scene.mode = runmode
											api.put(url, scene)
										end
									end,
		},
		countscenes = {name = "CountScenes",
									optimize = true,
									control  = function(id) return self.options.scenario.control(id) end,
									getValue = function(id) if self:getSceneProperty(id, "isRunning") == true then return 1 else return 0 end end,
		},
		runningscene = {name = "RunningScene",
									optimize  = true,
									control   = function(id) return self.options.scenario.control(id) end,
									getValue  = function(id) return self:getSceneProperty(id, "isRunning") end,
									isBoolean = true,
		},
		portable  = {name = "Portable",
									action = function(id, message) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findMobileId(id[i]), "sendPush", string.gsub(self:getMessage(message), "'", "’")) end end,
		},
		email     = {name = "Email",
									optimize = true,
									action   = function(id, message, sujet) if type(id) ~= "table" then id = {id} end for i=1, #id do fibaro.call(self:findUserId(id[i]), "sendEmail", sujet or (self.emailSubject), tools:urlencode(self:getMessage(message))) end end,
		},
		picture   = {name = "Picture",
									optimize   = true,
									keepValues = true,
									action     = function(id, destinataire) if type(id) ~= "table" then id = {id} end if type(destinataire) ~= "table" then destinataire = {destinataire} end for i=1, #id do for j=1, #destinataire do fibaro.call(self:findDeviceId(id[i]), "sendPhotoToUser", self:findUserId(destinataire[j])) end end end
		},
		picturetoemail = {name = "PictureToEmail",
									optimize   = true,
									keepValues = true,
									action     = function(id, destinataire) if type(id) ~= "table" then id = {id} end if type(destinataire) ~= "table" then destinataire = {destinataire} end for i=1, #id do for j=1, #destinataire do fibaro.call(self:findDeviceId(id[i]), "sendPhotoToEmail", destinataire[j]) end end end
		},
		ask       = {name = "Ask",
									optimize   = true,
									control    = function(id, titre, question, action, method) return type(action) == "table" or type(action) == "string" or tonumber(action) and true, string.format(self.trad.ask_id_invalid, tools:tostring(action, true, true)) end,
									keepValues = true,
									action     = function(id, titre, question, action, method)
										if type(id) ~= "table" then id = {id} end
										if #id == 0 then id = self.portables end
										for i=1, #id do id[i] = self:findMobileId(id[i]) end
										if not titre then titre = self.notificationTitle end
										if type(action) == "table" then
											askAnswerAction = self:getOption(action)
											api.post("/mobile/push", {
												mobileDevices = id,
												category = "YES_NO", -- "RUN_CANCEL",
												title = titre,
												message = self:getMessage(question),
												service = "Device",
												action = "RunAction",
												data = {
													deviceId = plugin.mainDeviceId,
													actionName = "answer",
												},
											})
										elseif type(action) == "string" or tonumber(action) then
											if type(method) == "string" and method ~= "" then
												api.post("/mobile/push", {
													mobileDevices = id,
													category = "YES_NO", -- "RUN_CANCEL",
													title = titre,
													message = self:getMessage(question),
													service = "Device",
													action = "RunAction",
													data = {
														deviceId = self:findDeviceId(action),
														actionName = method,
													},
												})
											else
												api.post("/mobile/push", {
													mobileDevices = id,
													category = "YES_NO", -- "RUN_CANCEL",
													title = titre,
													message = self:getMessage(question),
													service = "Scene",
													action = "Run",
													data = {
														sceneId = self:findSceneId(action),
													},
												})
											end
										else
											error(string.format(self.trad.ask_id_invalid, tools:tostring(action, true, true)))
										end
									end,
		},
		sonostts  = {name = "SonosTTS",
									action = function(qa_id, message, volume)
										error("SonosTTS not yet implemented")
										local message = self:getMessage(message)
										if not volume then volume = 30 end
										--local _f = fibaro
										--local _x ={root="x_sonos_object",load=function(b)local c=_f:getGlobalValue(b.root)if string.len(c)>0 then local d=json.decode(c)if d and type(d)=="table"then return d else _f:debug("Unable to process data, check variable")end else _f:debug("No data found!")end end,set=function(b,e,d)local f=b:load()if f[e]then for g,h in pairs(d)do f[e][g]=h end else f[e]=d end;_f:setGlobal(b.root,json.encode(f))end,get=function(b,e)local f=b:load()if f and type(f)=="table"then for g,h in pairs(f)do if tostring(g)==tostring(e or"")then return h end end end;return nil end}
										--_x:set(tostring(self:findDeviceId(vd_id)), { tts = {message=message, duration='auto', language=self.trad.locale, volume=volume} })
										--_f:call(self:findDeviceId(vd_id), "pressButton", button_id)
									end,
		},
		sonosmp3  = {name = "SonosMP3",
									action = function(qa_id, filepath, volume)
										if not volume then volume = 30 end
										fibaro.call(self:findDeviceId(qa_id), "playFile", filepath, true, volume)
									end,
		},
		weather   = {name = "Weather",
									optimize = true,
									math     = true,
									getValue = function(property) if not property or property == "" then property = "WeatherCondition" end return self:getWeather(property) end,
									trigger  = function(property) return {event = {type = "weather", property = property}, filter = {type = "WeatherChangedEvent", data = {change = property}}} end,
		},
		weatherlocal = {name = "WeatherLocal",
									optimize = true,
									math     = true,
									depends  = {"weather"},
									getValue = function(property) return self:translatetrad("weather", self:getOption({"Weather", property}).getValue()) end,
		},
		profile = {name = "Profile",
									control   = function(id) return api.get("/profiles/" .. self:findProfileId(id)) and true or false, string.format(self.trad.profile_unknown, tostring(id)) end,
									getId     = function(id) return self:findProfileId(id) end,
									getValue  = function(id) local value if tonumber(id) then value = self:getActiveProfile() else value = self:getProfileNameInCache(self:getActiveProfile()) end return value end,
									action    = function(id) self.refreshActiveProfile = true local response, status = api.post("/profiles/activeProfile/" .. self:findProfileId(id)) assert(status == 200, response) end,
									getName   = function(id) local n = self:getProfileNameInCache(id) return n end,
									trigger   = function(id) local id_num = self:findProfileId(id) if not id_num then error(string.format(self.trad.profile_unknown, id)) end return {event = {type = "profile", id = id_num}, filter = {type = "ActiveProfileChangedEvent", data = {newActiveProfile = id_num}}} end,
		},
		customevent = {name = "CustomEvent",
									optimize  = true,
									control   = function(name) return type(name) == "string" and name ~= "" and self:getCustomEvent(name), self.trad.custom_event_missing end,
									getValue  = function(name) return self:getCustomEvent(name) end,
									action    = function(name) fibaro.emitCustomEvent(name) end,
									getName   = function(name) local n = self:getCustomEventNameInCache(name) return n end,
									trigger   = function(name) return {event = {type = "custom-event", name = name}, filter = {type = "CustomEvent", data = {name = name}}} end,
									isBoolean = true,
		},
		info      = {name = "Info",
									optimize = true,
									math     = true,
									control  = function(property) if type(self:getSettingsInfo(property)) == "nil" then return false, string.format(self.trad.property_missing, property) else return true end end,
									getValue = function(property) return self:getSettingsInfo(property) end,
		},
		ledbrightness = {name = "LedBrightness",
									optimize = true,
									getValue = function() return api.get("/settings/led").brightness end,
									action   = function(level) local response, status = api.put("/settings/led", {brightness = tonumber(level)}) assert(status == 202, response) end,
		},
		-- TODO : ne fonctionne plus depuis firmware 5.050.13 => https://www.domotique-fibaro.fr/topic/14130-hc3-commande-shutdown/
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
												tools:debug("success() : " .. json.encode(response))
											end,
											error = function(err)
												tools:error("error() : " .. json.encode(err))
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
												tools:debug("success() : " .. json.encode(response))
											end,
											error = function(err)
												tools:error("error() : " .. json.encode(err))
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
												tools:debug("success() : " .. json.encode(response))
											end,
											error = function(err)
												tools:error("error() : " .. json.encode(err))
											end,
											options = {
												method = "POST",
												headers = {["X-Fibaro-Version"] = "2"}
											}
										})
									end,
		},
		["function"] = {name = "Function",
									optimize  = true,
									getValue  = function(func) return func() end,
									action    = function(func) self.forceRefreshValues = true self.refreshDeviceProperties = true self.refreshLabelValues = true self.refreshSliderValues = true self.refreshClimatePanel = true self.refreshPartitionProperties = true self.refreshGlobalVariables = true self.refreshQuickAppVariables = true self.refreshSceneProperties = true self.refreshActiveProfile = true func() end,
									isBoolean = true,
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
		alarm     = {name = "Alarm",
									optimize  = true,
									control   = function(id) return self.options.number.control(id) end,
									getValue  = function(id, alarm_id)
										local alarms = {}
										local Nombre_Alarme = tonumber(self:getQuickAppVariableValue(id, "Nombre_Alarme")) or 0
										if type(alarm_id) == "number" then
											if alarm_id > 0 and alarm_id <= Nombre_Alarme then
												alarms[1] = alarm_id
											else
												tools:error(string.format(self.trad.alarm_unknown, alarm_id))
												return false
											end
										else
											for i = 1, Nombre_Alarme do
												alarms[#alarms+1] = i
											end
										end
										for _, alarm in ipairs(alarms) do
											if os.date("%H:%M", self.runAt) == self:getQuickAppVariableValue(id, "_Heure" .. tostring(alarm)) then
												local days = self:getQuickAppVariableValue(id, "_Jours" .. tostring(alarm))
												days = days:lower()
												selected = tools:split(days, " ")
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
										end
										return false
									end,
									isBoolean = true,
		},
		wol = {name = "WOL",
									optimize  = true,
									control   = function(mac) return string.match(mac, "%x%x:%x%x:%x%x:%x%x:%x%x:%x%x") and true or string.match(mac, "%x%x-%x%x-%x%x-%x%x-%x%x-%x%x") and true or string.match(mac, "%x%x%x%x%x%x%x%x%x%x%x%x") and true or false, self.trad.mac_missing end,
									action    = function(mac) local status, message = tools:WOL(mac, {error = function(err) tools:error(err) end}) assert(status == true, message) end,
		},
		apiget    = {name = "ApiGet",
									optimize = true,
									math     = true,
									getValue = function(url) return api.get(url) end,
									action   = function(url) self.refreshDeviceProperties = true self.refreshLabelValues = true self.refreshSliderValues = true self.refreshClimatePanel = true self.refreshPartitionProperties = true self.refreshGlobalVariables = true self.refreshQuickAppVariables = true self.refreshSceneProperties = true self.refreshActiveProfile = true api.get(url) end,
		},
		apipost   = {name = "ApiPost",
									optimize = true,
									getValue = function(url, data) __assert_type(data, "table") return api.post(url, data) end,
									action   = function(url, data) __assert_type(data, "table") self.refreshDeviceProperties = true self.refreshLabelValues = true self.refreshSliderValues = true self.refreshClimatePanel = true self.refreshPartitionProperties = true self.refreshGlobalVariables = true self.refreshQuickAppVariables = true self.refreshSceneProperties = true self.refreshActiveProfile = true api.post(url, data) end,
		},
		apiput    = {name = "ApiPut",
									optimize = true,
									getValue = function(url, data) __assert_type(data, "table") return api.put(url, data) end,
									action   = function(url, data) __assert_type(data, "table") self.refreshDeviceProperties = true self.refreshLabelValues = true self.refreshSliderValues = true self.refreshClimatePanel = true self.refreshPartitionProperties = true self.refreshGlobalVariables = true self.refreshQuickAppVariables = true self.refreshSceneProperties = true self.refreshActiveProfile = true api.put(url, data) end,
		},
		httpget = {name = "httpGet",
									optimize  = true,
									control   = function(url) return type(url) == "string" and url ~= "" and true or false, self.trad.http_missing end,
									action    = function(url, user, password)
										local http = net.HTTPClient()
										http:request(url, {
											success = function(response) tools:print(nil, "HTTP response status : ", response.status) if self.debug then tools:print(nil, response.data) end end,
											error   = function(err) tools:error(err) end,
											options = {method = "GET", headers = {["Authorization"] = user and password and "Basic "..tools:base64(user..":"..password) or nil}},
										})
									end,
		},
		call = {name = "Call",
									optimize  = true,
									control   = function(id, action) return self.options.number.control(id) and type(action) == "string" and action ~= "", self.trad.call_missing end,
									action    = function(id, action, ...) self.cachedDeviceProperties[self:findDeviceId(id)] = {} fibaro.call(self:findDeviceId(id), action, table.unpack({...})) end,
		},
		stringtoalpha = {name = "StringToAlpha", --- par MAM78
									control  = function(condition, value) if condition == nil then return false, "Check option StringToAlpha condition" else return true end end,
									getValue = function(condition, value) local newvalue = "" for word in string.gmatch(value, "%a+") do newvalue = newvalue..word end return condition == newvalue, newvalue end,
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
		frequency = {name = "Frequency",
									optimize  = true,
									getValue  = function(freqday, freqnumber) return self:getFrequency(freqday, freqnumber) end,
									isBoolean = true,
		},
		monthly   = {name = "Monthly",
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
										if tools:isNumber(day) then
											return tonumber(os.date("%d", self.runAt)) == tonumber(day)
										end
										day = self:translate(day, self.trad.week, self.traduction.en.week)
										local n,d = os.date("%d %A", self.runAt):match("(%d+).?(%w+)")
										return ( tonumber(n) < 8 and d:lower() == day )
									end,
		},
		isevenweek = {name = "isEvenWeek",
									optimize  = true,
									getValue  = function() return os.date("%w") % 2 == 0 end,
									isBoolean = true,
		},
		isevenday = {name = "isEvenDay", -- par Dragoniacs
									optimize  = true,
									getValue  = function() return os.date("%d") % 2 == 0 end,
									isBoolean = true,
		},
		["repeat"] = {name = "Repeat",
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
									getValue = function(taskid) return globalvalue:match("|M_" .. taskid .. "{(%d+)}|") end,
									action   = function(taskid, number) if number == 0 then self.options.stoptask.action(taskid) else globalvalue = globalvalue:gsub("|M_" .. taskid .. "{(%d+)}|", "") .. "|M_" .. taskid .. "{"..number.."}|" end end,
		},
		restarttask = {name = "RestartTask",
									getValue = function(taskid) return globalvalue:find("|R_" .. taskid.."|") end,
									action   = function(taskid) if type(taskid) ~= "table" then taskid = {taskid} end for i=1, #taskid do if taskid[i]=="self" then taskid[i]=self.currentEntry.id end globalvalue = globalvalue:gsub("|R_" .. taskid[i].."|", ""):gsub("|M_" .. taskid[i] .. "{(%d+)}|", ""):gsub("|S_" .. taskid[i].."|", "") .. "|R_" .. taskid[i].."|" end end,
		},
		stoptask  = {name = "StopTask",
									getValue = function(taskid) return globalvalue:find("|S_" .. taskid) end,
									action   = function(taskid) if type(taskid) ~= "table" then taskid = {taskid} end for i=1, #taskid do if taskid[i]=="self" then taskid[i]=self.currentEntry.id end globalvalue = globalvalue:gsub("|S_" .. taskid[i].."|", ""):gsub("|M_" .. taskid[i] .. "{(%d+)}|", ""):gsub("|R_" .. taskid[i].."|", "") .. "|S_" .. taskid[i].."|" end end,
		},
		depend    = {name = "Depend",
									optimize  = true,
									control   = function(entryId) return type(self:findEntry(entryId)) ~= "nil" end,
									getValue  = function(entryId) return not self.currentEntry.isWaiting[entryId] end,
									isBoolean = true,
		},
		sleep     = {name = "Sleep",
									control    = function(duree, option) return type(duree)=="number" and type(self:getOption(option, true)~="nil") end,
									keepValues = true,
									action     = function(duree, option) local o = self:getOption(option) if duree and o then setTimeout(function() self.currentAction.name = o.name o.action(true) end, self:getDuree(duree)*1000) end end,
		},
		["or"]    = {name = "Or",
									optimize   = true,
									keepValues = true,
									control    = function(...)
										local args = {...}
										for i = 1, #args do
											local o, err = self:getOption(args[i])
											if type(o) == "nil" then
												return false, err
											end
										end
										return true
									end,
									getValue   = function(...) local args = {...} for i = 1, #args do if self:getOption(args[i]).check() then return true end end return false end,
									getName    = function(...)
										local args = {...}
										local name = ""
										for i = 1, #args do if self:getOption(args[i]).check() then name = name .. " " .. self:getOption(args[i]).getModuleName() end end
										return tools:trim(name)
									end,
									isBoolean  = true,
		},
		xor       = {name = "XOr",
									optimize   = true,
									keepValues = true,
									control    = function(...)
										local args = {...}
										for i = 1, #args do
											local o, err = self:getOption(args[i])
											if type(o) == "nil" then
												return false, err
											end
										end
										return true
									end,
									getValue   = function(...) local args = {...} local nb = 0 for i = 1, #args do if self:getOption(args[i]).check() then nb = nb+1 end end return nb == 1 end,
									getName    = function(...)
										local args = {...}
										local name = ""
										for i = 1, #args do if self:getOption(args[i]).check() then name = name .. " " .. self:getOption(args[i]).getModuleName() end end
										return tools:trim(name)
									end,
									isBoolean  = true,
		},
		result    = {name = "Result", math = true, getValue = function(position) if not position then position = 1 end return self.currentEntry.conditions[position].lastDisplayValue end },
		name      = {name = "Name", getValue = function(position) if not position then position = 1 end return self.currentEntry.conditions[position].getModuleName() end },
		room      = {name = "Room", getValue = function(position) if not position then position = 1 end return self.currentEntry.conditions[position].getModuleRoom() end },
		runs      = {name = "Runs", math = true, getValue = function() return self.nbRun end },
		seconds   = {name = "Seconds", math = true, getValue = function() return self.checkEvery end },
		duration  = {name = "Duration", math = true, getValue = function() local d, _ = self:getDureeInString(os.difftime(self.runAt, self.currentEntry.firstvalid)) return d end },
		durationfull = {name = "DurationFull", getValue = function() local _, d = self:getDureeInString(os.difftime(self.runAt, self.currentEntry.firstvalid)) return d end },
		sunrise   = {name = "Sunrise", getValue = function() return self:getDeviceProperty(1, "sunriseHour"):gsub(":", " " .. self.trad.hour .. " ") end },
		sunset    = {name = "Sunset", getValue = function() return self:getDeviceProperty(1, "sunsetHour"):gsub(":", " " .. self.trad.hour .. " ") end },
		date      = {name = "Date", getValue = function() return os.date(self.trad.date_format, self.runAt) end },
		trigger   = {name = "Trigger",
									getValue = function()
										--tools:print("silver", '"Trigger" : options.trigger.getValue() self.source.type='..tostring(self.source.type)..' self.source.propertyName='..tostring(self.source.propertyName)..' self.source.deviceID='..tostring(self.source.deviceID)) -- DEBUG
										if self.source.type == "autostart" then
											return "autostart"
										elseif self.source.type == "device" then
											if self.source.propertyName then
												return "Device[" .. tools:tostring(self.source.id, true, true) .. " - " .. tools:tostring(self.source.propertyName, true, true) .. "]"
											end
											return "Device[" .. tools:tostring(self.source.id, true, true) .. "]"
										elseif self.source.type == "global-variable" then
											return "Global[" .. tools:tostring(self.source.name, true, true) .. "]"
										elseif self.source.type == "alarm" then
											return "Alarm[" .. tools:tostring(self.source.id, true, true) .. "]"
										elseif self.source.type == "profile" then
											return "Profile[" .. tools:tostring(self.source.id, true, true) .. "]"
										elseif self.source.type == "weather" then
											return "Weather[" .. tools:tostring(self.source.property, true, true) .. "]"
										elseif self.source.type == "scene" then
											return "Scene[" .. tools:tostring(self.source.id, true, true) .. "]"
										elseif self.source.type == "custom-event" then
											return "CustomEvent[" .. tools:tostring(self.source.name, true, true) .. "]"
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
									getValue = function(key, word) word = self:getMessage(word) return self:translatetrad(tools:trim(key), tools:trim(word)) end,
		},
		tempext    = {name = "TempExt",
									math = true,
									depends  = {"weather"},
									getValue = function() return self.options.weather.getValue("Temperature") end,
		},
		tempexttts = {name = "TempExtTTS",
									depends  = {"weather"},
									getValue = function() local value = self.options.weather.getValue("Temperature") if value:find("%.") then return value:gsub("%.", " degrés ") end return value .. " degrés" end,
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
		test      = {name = "Test",
									optimize  = true,
									control   = function(name) tools:print("pink", '"Test" control()') return true end,
									getValue  = function(name) tools:print("pink", '"Test" getValue()') return name end,
									action    = function(name) tools:print("pink", '"Test" action()', self:getMessage(name)) end,
		},
	}

	-- self.options.alias           = self:copyOption("option_existante", "Alias")
	self.options.slide              = self:copyOption("value2", "Slide")
	self.options.orientation        = self:copyOption("value2", "Orientation")
	self.options.sensor             = self:copyOption("power", "Sensor")
	self.options.wakeup             = self:copyOption("dead", "WakeUp")
	self.options.startprogram       = self:copyOption("program", "StartProgram")
	self.options.color              = self:copyOption("rgb", "Color")
	self.options.currenticon        = self:copyOption("deviceicon", "CurrentIcon")
	self.options.qa                 = self:copyOption("quickapp", "QA")
	self.options.variableqa         = self:copyOption("variablequickapp", "VariableQA")
	self.options.start              = self:copyOption("scene", "Start")
	self.options.startscene         = self:copyOption("scene", "StartScene")
	self.options.scenario           = self:copyOption("scene", "Scenario")
	self.options.killscene          = self:copyOption("kill", "KillScene")
	self.options.killscenario       = self:copyOption("kill", "KillScenario")
	self.options.issceneenabled     = self:copyOption("enablescene", "isSceneEnabled")
	self.options.enablescenario     = self:copyOption("enablescene", "EnableScenario")
	self.options.isscenedisabled    = self:copyOption("disablescene", "isSceneDisabled")
	self.options.disablescenario    = self:copyOption("disablescene", "DisableScenario")
	self.options.setrunmodescenario = self:copyOption("runmodescene", "SetRunModeScenario")
	self.options.isscenerunning     = self:copyOption("runningscene", "isSceneRunning")
	self.options.push               = self:copyOption("portable", "Push")
	self.options.photo              = self:copyOption("picture", "Photo")
	self.options.phototomail        = self:copyOption("picturetoemail", "PhotoToMail")
	self.options.notdst             = self:copyOption("nodst", "NotDST")
	self.options.dayevenodd         = self:copyOption("frequency", "DayEvenOdd")
	self.options.notstarted         = self:copyOption("notstart", "NotStarted")

end -- GEA:__init

-- --------------------------------------------------------------------------------
-- Copie une option avec un alias
-- --------------------------------------------------------------------------------
function GEA:copyOption(optionName, newName)
	local copy = {}
	local option = self.options[optionName]
	copy.name = newName or option.name
	if option.math then copy.math = option.math end
	if option.optimize then copy.optimize = option.optimize end
	if option.keepValues then copy.keepValues = option.keepValues end
	if option.control then copy.control = option.control end
	if option.getId then copy.getId = option.getId end
	if option.getValue then copy.getValue = option.getValue end
	if option.action then copy.action = option.action end
	if option.getName then copy.getName = option.getName end
	if option.depends then copy.depends = option.depends else copy.depends = {} end
	if option.trigger then copy.trigger = option.trigger end
	if option.isBoolean then copy.isBoolean = option.isBoolean end
	table.insert(copy.depends, optionName)
	return copy
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
		if deviceNameToId[deviceId] then
			return deviceNameToId[deviceId]
		end
		if silent and self.options[string.lower(deviceId)] then
			return deviceId
		end
		local search
		if deviceId:find("@") then
			search = "/devices?name="..tools:split(deviceId, "@")[1]
			local rooms = api.get("/rooms")
			for _, room in pairs(rooms) do
				if room.name:lower() == tools:split(deviceId, "@")[2]:lower() then
					search = search .. "&roomID="..room.id
				end
			end
		else
			search = "/devices?name="..deviceId
		end
		local devices = api.get(search)
		if #devices > 0 then
			deviceNameToId[deviceId] = devices[1].id
			return devices[1].id
		else
			if silent then
				return deviceId
			end
			error(string.format(self.trad.device_is_missing, deviceId))
		end
	end
end

-- --------------------------------------------------------------------------------
-- Retourne l'ID d'un panneau de climat selon son nom
-- --------------------------------------------------------------------------------
function GEA:findClimateId(climateId)
	if tonumber(climateId) then
		return tonumber(climateId)
	else
		assert(type(climateId) == "string", self.trad.climate_panel_missing)
		if climateNameToId[climateId] then
			return climateNameToId[climateId]
		end
		local climates = api.get("/panels/climate")
		local id
		for _, climat in ipairs(climates) do
			if climat.name:lower() == climateId:lower() then
				id = climat.id
				break
			end
		end
		assert(tonumber(id), string.format(self.trad.climate_panel_unknown, climateId))
		climateNameToId[climateId] = id
		return id
	end
end

-- --------------------------------------------------------------------------------
-- Retourne l'ID d'une partition d'alarme selon son nom
-- --------------------------------------------------------------------------------
function GEA:findPartitionId(alarmId)
	if tonumber(alarmId) then
		return tonumber(alarmId)
	elseif type(alarmId) == "string" then
		if alarmNameToId[alarmId] then
			return alarmNameToId[alarmId]
		end
		local partitions = api.get("/alarms/v1/partitions")
		local partitionId = nil
		for _, partition in pairs(partitions) do
			if partition.name == alarmId then
				partitionId = partition.id
				break
			end
		end
		if tonumber(partitionId) then
			alarmNameToId[alarmId] = partitionId
			return partitionId
		end
	end
end

-- --------------------------------------------------------------------------------
-- Retourne l'ID d'une scène selon son nom
-- --------------------------------------------------------------------------------
function GEA:findSceneId(scenarioId)
	if tonumber(scenarioId) then
		return tonumber(scenarioId)
	else
		if sceneNameToId[scenarioId] then
			return sceneNameToId[scenarioId]
		end
		local scenes = api.get("/scenes")
		local sceneId = nil
		for _, scene in pairs(scenes) do
			if scene.name == scenarioId then
				sceneId = scene.id
				break
			end
		end
		if tonumber(sceneId) then
			sceneNameToId[scenarioId] = sceneId
			return sceneId
		end
	end
end

-- --------------------------------------------------------------------------------
-- Retourne l'ID d'un mobile selon son nom
-- --------------------------------------------------------------------------------
function GEA:findMobileId(mobileId)
	if tonumber(mobileId) then
		return tonumber(mobileId)
	else
		if mobileNameToId[mobileId] then
			return mobileNameToId[mobileId]
		end
		local iosDevices = api.get("/iosDevices")
		local iosDeviceId = nil
		for _, iosDevice in pairs(iosDevices) do
			if iosDevice.name == mobileId then
				iosDeviceId = iosDevice.id
				break
			end
		end
		assert(tonumber(iosDeviceId), string.format(self.trad.user_missing, mobileId))
		mobileNameToId[mobileId] = iosDeviceId
		return iosDeviceId
	end
end

-- --------------------------------------------------------------------------------
-- Retourne l'ID d'un utilisateur selon son nom
-- --------------------------------------------------------------------------------
function GEA:findUserId(userId)
	if tonumber(userId) then
		return tonumber(userId)
	else
		if userNameToId[userId] then
			return userNameToId[userId]
		end
		local users = api.get("/users")
		local user_id = nil
		for _, user in pairs(users) do
			if user.name == userId then
				user_id = user.id
				break
			end
		end
		assert(tonumber(user_id), string.format(self.trad.user_missing, userId))
		userNameToId[userId] = user_id
		return user_id
	end
end

-- --------------------------------------------------------------------------------
-- Retourne l'ID d'un profil selon son nom
-- --------------------------------------------------------------------------------
function GEA:findProfileId(profileId)
	if tonumber(profileId) then
		return tonumber(profileId)
	else
		if profileNameToId[profileId] then
			return profileNameToId[profileId]
		end
		local profiles = api.get("/profiles")
		local id
		for _, profile in pairs(profiles.profiles) do
			if profile.name:lower() == profileId:lower() then
				id = profile.id
				break
			end
		end
		if tonumber(id) then
			profileNameToId[profileId] = id
			return id
		end
	end
end

-- --------------------------------------------------------------------------------
-- Met et retourne le nom d'un module en cache
-- --------------------------------------------------------------------------------
function GEA:getDeviceNameInCache(id)
	local id_num = tonumber(self:findDeviceId(id))
	if id_num then
		if not deviceIdToName[id_num] then
			deviceIdToName[id_num] = fibaro.getName(id_num)
		end
		return deviceIdToName[id_num] or string.format(self.trad.device_is_missing, id), deviceIdToName[id_num] ~= nil
	else
		return string.format(self.trad.device_is_missing, id), false
	end
end

-- --------------------------------------------------------------------------------
-- Met et retourne le nom d'une pièce d'un module en cache
-- --------------------------------------------------------------------------------
function GEA:getRoomNameInCache(id)
	local id_num = tonumber(self:findDeviceId(id))
	if id_num then
		if not roomIdToName[id_num] then
			local room = api.get("/devices/" .. id_num)
			if room then
				local roomID = room.roomID
				if roomID and roomID > 0 then
					roomIdToName[id_num] = fibaro.getRoomName(roomID)
				end
			end
		end
		return roomIdToName[id_num] or self.trad.room_is_missing
	else
		return self.trad.room_is_missing
	end
end

-- --------------------------------------------------------------------------------
-- Met et retourne le nom d'une scène en cache
-- --------------------------------------------------------------------------------
function GEA:getSceneNameInCache(id)
	local id_num = tonumber(self:findSceneId(id) or "")
	if id_num then
		if not sceneIdToName[id_num] then
			local scene = api.get("/scenes/" .. id_num)
			if type(scene) == "table" then
				sceneIdToName[id_num] = scene.name
			end
		end
		return sceneIdToName[id_num] or string.format(self.trad.scene_is_missing, id), sceneIdToName[id_num] ~= nil
	else
		return string.format(self.trad.scene_is_missing, id), false
	end
end

-- --------------------------------------------------------------------------------
-- Met et retourne le nom d'une partition d'alarme en cache
-- --------------------------------------------------------------------------------
function GEA:getPartitionNameInCache(id)
	local id_num = tonumber(self:findPartitionId(id) or "")
	if id_num then
		if not partitionIdToName[id_num] then
			local partition = api.get("/alarms/v1/partitions/" .. id_num)
			if type(partition) == "table" then
				partitionIdToName[id_num] = partition.name
			end
		end
		return partitionIdToName[id_num] or string.format(self.trad.partition_unknown, id), partitionIdToName[id_num] ~= nil
	else
		return string.format(self.trad.partition_unknown, id), false
	end
end

-- --------------------------------------------------------------------------------
-- Met et retourne le nom d'un profil en cache
-- --------------------------------------------------------------------------------
function GEA:getProfileNameInCache(id)
	local id_num = tonumber(self:findProfileId(id) or "")
	if id_num then
		if not profileIdToName[id_num] then
			local profile = api.get("/profiles/" .. id_num)
			if type(profile) == "table" then
				profileIdToName[id_num] = profile.name
			end
		end
		return profileIdToName[id_num] or string.format(self.trad.profile_unknown, id), profileIdToName[id_num] ~= nil
	else
		return string.format(self.trad.profile_unknown, id), false
	end
end

-- --------------------------------------------------------------------------------
-- Met et retourne le nom d'un événement personnalisé en cache
-- --------------------------------------------------------------------------------
function GEA:getCustomEventNameInCache(name)
	if name then
		if not customEventName[name] then
			local customEvent = api.get("/customEvents/" .. tostring(name))
			if type(customEvent) == "table" then
				customEventName[name] = customEvent.name
			end
		end
		return customEventName[name] or string.format(self.trad.custom_event_unknown, name), customEventName[name] ~= nil
	else
		return string.format(self.trad.custom_event_unknown, name), false
	end
end

-- --------------------------------------------------------------------------------
-- Met en cache et retourne la valeur de propriété d'un module
-- --------------------------------------------------------------------------------
function GEA:getDeviceProperty(id, property)
	if self.refreshDeviceProperties then
		self.cachedDeviceProperties = {}
		self.refreshDeviceProperties = false
	end
	local id_num = self:findDeviceId(id)
	if id_num then
		if self.cachedDeviceProperties[id_num] then
			if property == nil or property == "" then
				return self.cachedDeviceProperties[id_num]
			elseif self.cachedDeviceProperties[id_num][property] ~= nil then
				return self.cachedDeviceProperties[id_num][property]
			else
				self.cachedDeviceProperties[id_num][property] = api.get("/devices/" .. id_num .. "/properties/" .. property).value
				return self.cachedDeviceProperties[id_num][property]
			end
		else
			local device = api.get("/devices/" .. id_num .. (property ~= nil and property ~= "" and "/properties/" .. property or ""))
			if device then
				if not self.cachedDeviceProperties[id_num] then
					self.cachedDeviceProperties[id_num] = {}
				end
				if property == nil or property == "" then
					return self.cachedDeviceProperties[id_num]
				else
					self.cachedDeviceProperties[id_num][property] = device.value
					return self.cachedDeviceProperties[id_num][property]
				end
			end
		end
	end
end

-- --------------------------------------------------------------------------------
-- Met en cache et retourne la valeur d'un label d'un QuickApp
-- --------------------------------------------------------------------------------
function GEA:getLabelValue(id, name)
	if self.refreshLabelValues then
		self.cachedLabelValues = {}
		self.refreshLabelValues = false
	end
	local id_num = self:findDeviceId(id)
	if id_num then
		if self.cachedLabelValues[id_num] and self.cachedLabelValues[id_num][name] ~= nil then
			return self.cachedLabelValues[id_num][name]
		else
			if not self.cachedLabelValues[id_num] then
				self.cachedLabelValues[id_num] = {}
			end
			self.cachedLabelValues[id_num][name] = tools.getLabel(id_num, name)
			return self.cachedLabelValues[id_num][name]
		end
	end
end

-- --------------------------------------------------------------------------------
-- Met en cache et retourne la valeur d'un slider d'un QuickApp
-- --------------------------------------------------------------------------------
function GEA:getSliderValue(id, name)
	if self.refreshSliderValues then
		self.cachedSliderValues = {}
		self.refreshSliderValues = false
	end
	local id_num = self:findDeviceId(id)
	if id_num then
		if self.cachedSliderValues[id_num] and self.cachedSliderValues[id_num][name] ~= nil then
			return self.cachedSliderValues[id_num][name]
		else
			if not self.cachedSliderValues[id_num] then
				self.cachedSliderValues[id_num] = {}
			end
			self.cachedSliderValues[id_num][name] = tools.getSlider(id_num, name)
			return self.cachedSliderValues[id_num][name]
		end
	end
end

-- --------------------------------------------------------------------------------
-- Met en cache et retourne une zone de climat
-- --------------------------------------------------------------------------------
function GEA:getClimatePanel(id)
	if self.refreshClimatePanel then
		self.cachedClimatePanel = {}
		self.refreshClimatePanel = false
	end
	local id_num = tonumber(self:findClimateId(id) or "")
	if id_num then
		if self.cachedClimatePanel[id_num] ~= nil then
			return self.cachedClimatePanel[id_num]
		else
			self.cachedClimatePanel[id_num] = api.get("/panels/climate/" .. id_num)
			return self.cachedClimatePanel[id_num]
		end
	end
end

-- --------------------------------------------------------------------------------
-- Met en cache et retourne la valeur de propriété d'une partition d'alarme
-- --------------------------------------------------------------------------------
function GEA:getPartitionProperty(id, property)
	if self.refreshPartitionProperties then
		self.cachedPartitionProperties = {}
		self.refreshPartitionProperties = false
	end
	local id_num = tonumber(self:findPartitionId(id) or "")
	if id_num then
		if self.cachedPartitionProperties[id_num] then
			if property == nil or property == "" then
				return self.cachedPartitionProperties[id_num]
			elseif self.cachedPartitionProperties[id_num][property] ~= nil then
				return self.cachedPartitionProperties[id_num][property]
			end
		else
			local partition = api.get("/alarms/v1/partitions/" .. id_num)
			if partition then
				if not self.cachedPartitionProperties[id_num] then
					self.cachedPartitionProperties[id_num] = {}
				end
				if property == nil or property == "" then
					return self.cachedPartitionProperties[id_num]
				else
					self.cachedPartitionProperties[id_num][property] = partition[property]
					return self.cachedPartitionProperties[id_num][property]
				end
			end
		end
	end
end

-- --------------------------------------------------------------------------------
-- Met en cache et retourne le contenu d'une variable globale
-- --------------------------------------------------------------------------------
function GEA:getGlobalValue(name)
	if self.refreshGlobalVariables then
		self.cachedGlobalVariables = {}
		self.refreshGlobalVariables = false
	end
	if self.cachedGlobalVariables[name] then
		return self.cachedGlobalVariables[name]
	elseif self.options.checkvg.getValue(name) then
		self.cachedGlobalVariables[name] = fibaro.getGlobalVariable(name)
		return self.cachedGlobalVariables[name]
	end
end

-- --------------------------------------------------------------------------------
-- Met en cache et retourne le contenu d'une variable d'un QuickApp
-- --------------------------------------------------------------------------------
function GEA:getQuickAppVariableValue(id, name)
	if self.refreshQuickAppVariables then
		self.cachedQuickAppVariables = {}
		self.refreshQuickAppVariables = false
	end
	local id_num = self:findDeviceId(id)
	if id_num then
		if self.cachedQuickAppVariables[id_num] and self.cachedQuickAppVariables[id_num][name] ~= nil then
			return self.cachedQuickAppVariables[id_num][name]
		else
			if not self.cachedQuickAppVariables[id_num] then
				self.cachedQuickAppVariables[id_num] = {}
			end
			self.cachedQuickAppVariables[id_num][name] = tools.getVariable(id_num, name)
			return self.cachedQuickAppVariables[id_num][name]
		end
	end
end

-- --------------------------------------------------------------------------------
-- Met en cache et retourne la valeur de propriété d'une scène
-- --------------------------------------------------------------------------------
function GEA:getSceneProperty(id, property)
	if self.refreshSceneProperties then
		self.cachedSceneProperties = {}
		self.refreshSceneProperties = false
	end
	local id_num = tonumber(self:findSceneId(id) or "")
	if id_num then
		if self.cachedSceneProperties[id_num] then
			if property == nil or property == "" then
				return self.cachedSceneProperties[id_num]
			elseif self.cachedSceneProperties[id_num][property] ~= nil then
				return self.cachedSceneProperties[id_num][property]
			end
		else
			local partition = api.get("/scenes/" .. id_num)
			if partition then
				if not self.cachedSceneProperties[id_num] then
					self.cachedSceneProperties[id_num] = {}
				end
				if property == nil or property == "" then
					return self.cachedSceneProperties[id_num]
				else
					self.cachedSceneProperties[id_num][property] = partition[property]
					return self.cachedSceneProperties[id_num][property]
				end
			end
		end
	end
end

-- --------------------------------------------------------------------------------
-- Met en cache et retourne la météo
-- --------------------------------------------------------------------------------
function GEA:getWeather(property)
	if self.refreshWeather then
		self.cachedWeatherProperties = {}
		self.refreshWeather = false
	end
	if self.cachedWeatherProperties[property] then
		return self.cachedWeatherProperties[property]
	else
		self.cachedWeatherProperties[property] = api.get("/weather")[property]
		return self.cachedWeatherProperties[property]
	end
end

-- --------------------------------------------------------------------------------
-- Met en cache et retourne le profil actif
-- --------------------------------------------------------------------------------
function GEA:getActiveProfile()
	if not self.refreshActiveProfile and self.cachedActiveProfile then
		return self.cachedActiveProfile
	else
		self.cachedActiveProfile = api.get("/profiles").activeProfile
		self.refreshActiveProfile = false
		return self.cachedActiveProfile
	end
end

-- --------------------------------------------------------------------------------
-- Met en cache et retourne un événement personnalisé
-- --------------------------------------------------------------------------------
function GEA:getCustomEvent(name)
	if self.cachedCustomEvents[name] ~= nil then
		return self.cachedCustomEvents[name]
	else
		self.cachedCustomEvents[name] = api.get("/customEvents/" .. tostring(name)) and true or false
		return self.cachedCustomEvents[name]
	end
end

-- --------------------------------------------------------------------------------
-- Met en cache et retourne une info système
-- --------------------------------------------------------------------------------
function GEA:getSettingsInfo(property)
	if self.refreshSettingsInfo then
		self.cachedSettingsInfo = {}
		self.refreshSettingsInfo = false
	end
	if self.cachedSettingsInfo[property] then
		return self.cachedSettingsInfo[property]
	else
		self.cachedSettingsInfo[property] = api.get("/settings/info")[property]
		return self.cachedSettingsInfo[property]
	end
end

-- --------------------------------------------------------------------------------
-- Retourne le nom d'un module (pièce optionnelle)
-- --------------------------------------------------------------------------------
function GEA:getDeviceFullName(id, withRoom)
	if type(id) ~= "table" then id = {id} end
	local names = ""
	local exists = true
	for i=1, #id do
		if names ~= "" then names = names .. ", " end
		local name, exist = self:getDeviceNameInCache(id[i])
		exists = exists and exist
		if withRoom then
			names = names .. name .. " (" .. self:getRoomNameInCache(id[i]) .. ")"
		else
			names = names .. name
		end
	end
	return names, exists
end

-- --------------------------------------------------------------------------------
-- Vérification des batteries
-- --------------------------------------------------------------------------------
function GEA:batteries(value, concatroom)
	local res = false
	local names, rooms = "", ""
	for _, v in ipairs(fibaro.getDevicesID({interface="battery", visible=true})) do
		local bat = self:getDeviceProperty(v, "batteryLevel")
		local low = tonumber(bat) < tonumber(value)
		if low then
			if names ~= "" then names = names .. ", " end
			names = names .. "["..v.."] " .. self:getDeviceFullName(v, concatroom)
			if rooms ~= "" then rooms = rooms .. ", " end
			rooms = rooms .. self:getRoomNameInCache(v)
		end
		res = res or low
	end
	return res, names, rooms
end

-- --------------------------------------------------------------------------------
-- Retourne l'ID du parent d'un module Z-Wave
-- --------------------------------------------------------------------------------
function GEA:getParentDevice(id)
	local id_num = self:findDeviceId(id)
	assert(type(id_num) == "number", string.format(self.trad.id_missing, id))
	local device = api.get("/devices/" .. id_num)
	assert(type(device) == "table", string.format(self.trad.id_missing, id_num))
	if device.parentId > 1 then
		return api.get("/devices/" .. device.parentId)
	else
		return device
	end
end

-- --------------------------------------------------------------------------------
-- Converti une heure au format HH:MM:SS en secondes
-- --------------------------------------------------------------------------------
function GEA:getDuree(valeur)
	if tonumber(valeur) then
		return tonumber(valeur)
	else
		local function getDuree(duree)
			if type(duree) == "string" and duree:find(":") then
				local durees = tools:split(duree, ":")
				if #durees == 2 then local h,m = string.match(duree, "(%d+):(%d+)") return h*3600 + m*60 end
				if #durees == 3 then local h,m,s = string.match(duree, "(%d+):(%d+):(%d+)") return h*3600 + m*60 + s end
			end
			return tonumber(duree) or 30
		end
		if type(valeur) == "string" then
			return getDuree(valeur:find(":") and valeur or fibaro.getGlobalVariable(valeur))
		end
	end
	return 30
end

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
-- Recherche et retourne une option (condition ou action) encapsulée
-- --------------------------------------------------------------------------------
function GEA:getOption(object, silent)
	--tools:print("silver", "GEA:getOption("..json.encode(object)..", "..tostring(silent)..")") -- DEBUG
	local sname = ""
	local tname = type(object)
	local originalName = object
	if tname == "table" then
		sname = string.lower(tostring(object[1])):gsub("!", ""):gsub("+", ""):gsub("-", ""):gsub("%(", ""):gsub("%)", "")
		originalName = object[1]
	else
		sname = string.lower(tostring(object)):gsub("!", ""):gsub("+", ""):gsub("-", ""):gsub("%(", ""):gsub("%)", "")
	end
	--tools:print("silver", "GEA:getOption() sname (" .. type(sname) .. ") " .. tostring(sname) .. " -  tname (" .. type(tname) .. ") " .. tostring(tname)) -- DEBUG
	if sname ~= "function" then
		local jo = json.encode(object)
		--tools:print("silver", "GEA:getOption() jo (" .. type(jo) .. ") " .. tostring(jo)) -- DEBUG
		if self.declared[jo] then return self.declared[jo] end
	end
	local option
	if tonumber(sname) or tonumber(self:findDeviceId(sname, true)) then tname = "number" object = tonumber(self:findDeviceId(sname, true)) end
	if tname == "number" or tname == "boolean" then
		option = self.options[tname]
		option.name = object
		originalName = tostring(originalName)
		object = {object}
		sname = tname
	else
		option = self.options[sname]
	end
	--tools:print("silver", "GEA:getOption() sname (" .. type(sname) .. ") " .. tostring(sname) .. " -  tname (" .. type(tname) .. ") " .. tostring(tname)) -- DEBUG
	if option then
		self.options_id = self.options_id + 1
		if self.nbRun < 1 then table.insert(self.usedoptions, sname) end
		local o = self:encapsule(option, object, originalName:find("!"), originalName:find("+"), originalName:find("-"), self.options_id, originalName:find("%(") and originalName:find("%)"))
		if jo then self.declared[jo] = o end
		return o
	end
	if not silent then
		return nil, string.format(self.trad.option_missing, tools:tostring(originalName, true, true))
	end
end

-- --------------------------------------------------------------------------------
-- Encapsulation d'une option (condition ou action)
-- --------------------------------------------------------------------------------
function GEA:encapsule(option, args, inverse, plus, moins, option_id, not_immediat)
	--tools:print("gray", "GEA:encapsule() copy.encapsule() option_id = " .. tostring(option_id)) -- DEBUG
	--for k, v in pairs(option) do tools:print("gray", "GEA:encapsule() copy.encapsule() option k="..tostring(k).." - v ("..type(v)..")="..tostring(v)) end -- DEBUG
	local copy = {}
	copy.lastRunAt = 0
	copy.option_id = option_id
	copy.name = self:findDeviceId(option.name, true)
	--tools:print("gray", "GEA:encapsule() option.name = (" .. type(option.name) .. ") " .. tostring(option.name) .. " - copy.name = (" .. type(copy.name) .. ") " .. tostring(copy.name)) -- DEBUG
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
											params = ",{...}" .. params
										else
											params = "," .. tools:tostring(copy.args, false, true) .. params
										end
									end
									local name
									local extra = tools:iif(copy.inverse, "!", "") .. tools:iif(plus, "+", "") .. tools:iif(moins, "-", "")
									if extra ~= "" then
										name = tostring(copy.name) .. extra
									else
										name = copy.name
									end
									return "[" ..  tools:tostring(name, false, true)  .. params
								end
	copy.lastvalue = ""
	copy.lastDisplayValue = ""
	copy.hasValue = type(option.getValue)=="function" or false
	copy.hasAction = type(option.action)=="function" or false
	copy.hasControl = type(option.control)=="function" or false
	copy.getModuleName = function() if option.getName then return option.getName(copy.searchValues()) end local id = copy.getId() local n = self:getDeviceNameInCache(id) return n end
	copy.getModuleRoom = function() if option.getRoom then return option.getRoom(copy.searchValues()) end local id = copy.getId() return self:getRoomNameInCache(id) end
	copy.hasGetId = type(option.getId) == "function" or false
	copy.getId = function()
									if copy.not_immediat then
										return ""
									elseif copy.hasGetId then
										return option.getId(copy.args[1])
									elseif type(copy.name)=="boolean" then
										return copy.name
									elseif type(copy.name)=="number" then
										return copy.name
									elseif type(copy.name)=="function" then
										return nil
									--elseif self.plugins[copy.name] then
										--return self.currentEntry.id .. "@" .. copy.option_id
									else
										if copy.name == "Or" or copy.name == "XOr" then
											local ids = {}
											for i=1, #copy.args do
												local o, err = self:getOption(copy.args[i])
												if o then
													table.insert(ids, o.getId())
												elseif self.debug then
													tools:warning(err)
												end
											end
											return ids
										end
										if copy.args[1] then return self:findDeviceId(copy.args[1], true) end
										return nil
									end
								end
	copy.searchValues = function()
												--tools:print("gray", "GEA:encapsule() copy.searchValues()") -- DEBUG
												if type(copy.name)=="boolean" then
													--tools:print("gray", "GEA:encapsule() copy.searchValues() boolean : " .. tostring(copy.name)) -- DEBUG
													return copy.name
												elseif type(copy.name)=="number" then
													--tools:print("gray", "GEA:encapsule() copy.searchValues() number : " .. tostring(copy.name)) -- DEBUG
													return copy.name
												else
													--tools:print("gray", "GEA:encapsule() copy.searchValues() else for") -- DEBUG
													local results = {}
													for i = 1, #args do
														--tools:print("gray", "GEA:encapsule() copy.searchValues() i=" .. i) -- DEBUG
														if type(args[i]) == "table" and not option.keepValues and i >= 2 then
															--tools:print("gray", "GEA:encapsule() copy.searchValues() table") -- DEBUG
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
															--tools:print("gray", "GEA:encapsule() copy.searchValues() else table.insert args[i] = " .. args[i]) -- DEBUG
															table.insert(results, args[i])
														end
													end
													if results and #results>0 then table.remove(results, 1) end
													return table.unpack(results)
												end
											end
	copy.control = function()
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
	copy.action = function() if copy.hasAction then copy.lastRunAt=0; return option.action(copy.searchValues()) else tools:warning(string.format(self.trad.not_an_action, copy.name)) return nil end end
	copy.getValue = function()
										--tools:print("gray", "GEA:encapsule() copy.getValue() copy.hasValue=" .. tostring(copy.hasValue) .. " - copy.lastvalue, copy.lastDisplayValue = " .. tostring(copy.lastvalue) .. ", " .. tostring(copy.lastDisplayValue)) -- DEBUG
										if not copy.hasValue then
											if self.lldebug then tools:print("gray", "GEA:encapsule() copy.getValue() return nil") end
											return
										end
										if copy.lastRunAt == self.runAt and copy.lastvalue and not self.forceRefreshValues then
											if self.lldebug then tools:print("gray", "GEA:encapsule() copy.getValue() 1 return copy.lastvalue, copy.lastDisplayValue :", tools:tostring(copy.lastvalue, true, true) .. ", " .. tools:tostring(copy.lastDisplayValue, true, true)) end
											return copy.lastvalue, copy.lastDisplayValue
										end
										--tools:print("gray", "GEA:encapsule() copy.getValue() type(copy.name) = " .. type(copy.name)) -- DEBUG
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
										if self.lldebug then tools:print("gray", "GEA:encapsule() copy.getValue() 2 return copy.lastvalue, copy.lastDisplayValue :", tools:tostring(copy.lastvalue, true, true) .. ", " .. tools:tostring(copy.lastDisplayValue, true, true)) end
										return copy.lastvalue, copy.lastDisplayValue
									end
	copy.check = function()
									local id, property, value, value2, value3, value4 = copy.searchValues()
									--local isValue = true
									if not copy.hasValue then return true end
									if type(property) == "nil" then property = id --[[isValue = false--]] end
									if type(value) == "nil" then value = property end
									if type(value2) == "nil" then value2 = value end
									if type(value3) == "nil" then value3 = value2 end
									if type(value4) == "nil" then value4 = value3 end
									if self.lldebug then tools:print("gray", "GEA:encapsule() copy.check() copy.name="..tools:tostring(copy.name, true, true).." id="..tools:tostring(id, true, true).." property="..tools:tostring(property, true, true).." value="..tools:tostring(value, true, true).." value2="..tools:tostring(value2, true, true).." value3="..tools:tostring(value3, true, true).." value4="..tools:tostring(value4, true, true)) end
									local result = copy.getValue()
									if self.lldebug then tools:print("gray", "GEA:encapsule() copy.check() result =", tools:tostring(result, true, true)) end
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
										if tools:isNil(option.math) then
											tools:error(string.format(self.trad.not_math_op, copy.name))
											return false, result
										else
											local num1 = tonumber(string.match(value4, "-?[0-9.]+"))
											local num2 = tonumber(string.match(result or "0", "-?[0-9.]+"))
											if type(num1) == "number" and type(num2) == "number" then
												if plus then
													checked = num2 > num1
												else
													checked = num2 < num1
												end
											else
												checked = false
											end
										end
									elseif type(value4) == "table" then
										checked = tools:deepCompare(result, value4)
									elseif type(value4) == "function" then
										checked = value4()
									--elseif not isValue then
										--checked = result and true or false
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
	copy.hasTrigger = type(option.trigger) == "function" or false
	copy.eventTrigger = function()
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
	copy.typeTrigger = function()
									local trigger = copy.eventTrigger()
									if trigger then
										return trigger.event.type
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
		for _, v in pairs(tools:split(s2, "|")) do
			res = res or tostring(s1):match(tools:trim(v))
		end
		return res
	end
	return tostring(s1) == tostring(s2)
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
		local num = tonumber(value:match("%d+")) or 1
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
	t = t:gsub(" ", ""):gsub("h", ":"):gsub("sunset", self:getDeviceProperty(1, "sunsetHour")):gsub("sunrise", self:getDeviceProperty(1, "sunriseHour"))

	if string.find(t, "<") then
		t = self:flatTime(tools:split(t, "<")[1]).."<"..self:flatTime(tools:split(t, "<")[2])
	end
	if string.find(t, ">") then
		t = self:flatTime(tools:split(t, ">")[1])..">"..self:flatTime(tools:split(t, ">")[2])
	end

	local td = os.date("*t", self.runAt)
	if string.find(t, "+") then
		local time = tools:split(t, "+")[1]
		local add = tools:split(t, "+")[2]
		local sun = os.time{year=td.year, month=td.month, day=td.day, hour=tonumber(tools:split(time, ":")[1]), min=tonumber(tools:split(time, ":")[2]), sec=td.sec}
		sun = sun + (add *60)
		t = os.date("*t", sun)
		t =  string.format("%02d", t.hour).. ":" ..string.format("%02d", t.min)
	elseif string.find(t, "-") then
		local time = tools:split(t, "-")[1]
		local add = tools:split(t, "-")[2]
		local sun = os.time{year=td.year, month=td.month, day=td.day, hour=tonumber(tools:split(time, ":")[1]), min=tonumber(tools:split(time, ":")[2]), sec=td.sec}
		sun = sun - (add *60)
		t = os.date("*t", sun)
		t =  string.format("%02d", t.hour)..":" ..string.format("%02d", t.min)			
	elseif string.find(t, "<") then
		local s1 = tools:split(t, "<")[1]
		local s2 = tools:split(t, "<")[2]
		s1 =  string.format("%02d", tools:split(s1, ":")[1]) .. ":" .. string.format("%02d", tools:split(s1, ":")[2])
		s2 =  string.format("%02d", tools:split(s2, ":")[1]) .. ":" .. string.format("%02d", tools:split(s2, ":")[2])
		if s1 < s2 then t = s1 else t = s2 end
	elseif string.find(t, ">") then
		local s1 = tools:split(t, ">")[1]
		local s2 = tools:split(t, ">")[2]
		s1 =  string.format("%02d", tools:split(s1, ":")[1]) .. ":" .. string.format("%02d", tools:split(s1, ":")[2])
		s2 =  string.format("%02d", tools:split(s2, ":")[1]) .. ":" .. string.format("%02d", tools:split(s2, ":")[2])
		if s1 > s2 then t = s1 else t = s2 end
	else
		t =  string.format("%02d", tools:split(t, ":")[1]) .. ":" .. string.format("%02d", tools:split(t, ":")[2])
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
	return tools:isNotNil(string.find(jours:lower(), os.date("%A", self.runAt):lower()))
end

-- --------------------------------------------------------------------------------
-- Traite les entrées spéciales avant de l'ajouter dans le tableau
-- --------------------------------------------------------------------------------
function GEA:insert(t, v, entry)
	if not v then return end
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
-- Ajoute un déclencheur instantané
-- --------------------------------------------------------------------------------
function GEA:addTriggerCondition(o)
	local option = self:getOption(o)
	--tools:print("silver", "GEA:addTriggerCondition() option =", tools:tostring(option, true, true)) -- DEBUG
	--tools:deepPrint(option) -- DEBUG
	if type(option) == "table" then
		if option.hasTrigger and not option.not_immediat then
			local eventTrigger, msg = option.eventTrigger()
			--tools:print("silver", "GEA:addTriggerCondition() eventTrigger => " .. json.encode(eventTrigger)) -- DEBUG
			if type(eventTrigger) == "table" then
				--for k, v in pairs(eventTrigger) do tools:print("silver", "GEA:addTriggerCondition() eventTrigger : " .. tostring(k) .. " = " .. tostring(v)) end -- DEBUG
				local found = false
				for i = 1, #triggers do
					--tools:print("silver", "GEA:addTriggerCondition() triggers[" .. tostring(i) .. "] => " .. json.encode(triggers[i])) -- DEBUG
						if tools:deepCompare(triggers[i], eventTrigger) then
							found = true
							--tools:print("silver", "GEA:addTriggerCondition() eventTrigger already exists") -- DEBUG
							break
						end
				end
				if not found then
					triggers[#triggers+1] = eventTrigger
					--tools:print("silver", "GEA:addTriggerCondition() added : " .. json.encode(triggers[#triggers])) -- DEBUG
				end
			else
				tools:error(msg)
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
		return GEA_event:addEntry(c, d, m, a, l)
	elseif GEA_auto then
		return GEA_auto:addEntry(c, d, m, a, l)
	else
		-- n'est jamais censé se produire
		tools:error("GEA_event or GEA_auto not found")
	end
end

function GEA:addEntry(c, d, m, a, l)

	if not c then tools:error(self.trad.err_cond_missing) return end
	if not d then tools:error(self.trad.err_dur_missing) return end
	if not m then tools:error(self.trad.err_msg_missing) return end

	self.id_entry = self.id_entry + 1
	if self.lldebug then tools:printargs("silver", "GEA:addEntry", c, d, m, a, l) end

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
		log = "#" .. self.id_entry .. " : " ..tools:iif(l, tools:tostring(l), ""),
		portables = self.portables,
		inverse = {}
	}
	entry.getDuration = function()
		return self:getDuree(entry.duration)
	end
	-- entrée inutile, on retourne juste l'id pour référence
	if not self.auto and entry.getDuration() >= 0 then
		--tools:print("silver", "GEA:addEntry() not self.auto") -- DEBUG
		return entry.id
	end
	if self.auto and entry.getDuration() < 0 then
		-- Recherche les déclencheurs dans les conditions
		if type(c) == "table" and (type(c[1]) == "table" or type(c[1]) == "number" or c[1]:find("%d+!") or type(c[1]) == "boolean") then
			for i = 1, #c do
				self:addTriggerCondition(c[i])
			end
		else
			self:addTriggerCondition(c)
		end
		--tools:print("silver", "GEA:addEntry() getDuration < 0") -- DEBUG
		return entry.id
	end
	if self.source.type == "manual" then
		--tools:print("silver", "GEA:addEntry() source[type] manual") -- DEBUG
		return entry.id
	end

	self.currentEntry = entry

	-- traitement des conditions
	entry.mainid = -1
	local done = false
	if type(c) == "table" and (type(c[1]) == "table" or type(c[1]) == "number" or c[1]:find("%d+!") or type(c[1]) == "boolean") then
		for i = 1, #c do
			--tools:print("silver", "GEA:addEntry() Condition n°" .. i) -- DEBUG
			local o, err = self:getOption(c[i])
			if not o then
				tools:error(tools:color("cyan", tools:iif(entry.getDuration() < 0, self.trad.add_event, self.trad.add_auto)), tools:color("white", "#" .. tostring(entry.id), ":"), self.trad.err_rule_excluded, ":", err)
				return entry.id
			end
			local res = self:insert(entry.conditions, o, entry)
			done = done or res
		end
	else
		--tools:print("silver", "GEA:addEntry() Condition") -- DEBUG
		local o, err = self:getOption(c)
		if not o then
			tools:error(tools:color("cyan", tools:iif(entry.getDuration() < 0, self.trad.add_event, self.trad.add_auto)), tools:color("white", "#" .. tostring(entry.id), ":"), self.trad.err_rule_excluded, ":", err)
			return entry.id
		end
		done = self:insert(entry.conditions, o, entry)
	end
	if done then
		local mainid = entry.conditions[1].getId()
		if type(mainid) == "table" then
			entry.mainid = mainid[1]
		else
			--tools:print("silver", "GEA:addEntry() mainid : " .. tostring(mainid)) -- DEBUG
			entry.mainid = mainid
		end
	end

	-- analyse des messages pour empêcher la suppression des options utilisées
	if self.auto then self:getMessage(m, true) end

	-- analyse du déclencheur
	if self.event and self.event.id then
		--tools:print("silver", "GEA:addEntry() self.event :", self.event) -- DEBUG
		-- si le déclencheur est trouvé en recherche un id correspondant
		local found = false
		for i = 1, #entry.conditions do
			--tools:print("silver", "GEA:addEntry() condition i : " .. i) -- DEBUG
			if self.source and self.source.type == entry.conditions[i].typeTrigger() then
				local ids = entry.conditions[i].getId()
				--tools:print("silver", "GEA:addEntry() condition ids : " .. json.encode(ids)) -- DEBUG
				if type(ids) == "table" then
					for j = 1, #ids do
						if tostring(ids[j]) == tostring(self.event.id) and not self.event.label then found = true break end
						if tostring(ids[j]) == tostring(self.event.id) and self.event.label then
							if entry.conditions[i].args[2] == self.event.label then
								found = true
								break
							end
						end
					end
				else
					--tools:print("silver", "GEA:addEntry() ID déclencheur : " .. ids) -- DEBUG
					if tostring(ids) == tostring(self.event.id) and not self.event.label then found = true end
					if tostring(ids) == tostring(self.event.id) and self.event.label then
						if entry.conditions[i].args[2] == self.event.label then
							found = true
						end
					end
				end
			end
		end
		if not found then
			--tools:print("silver", "GEA:addEntry() event not found") -- DEBUG
			return entry.id
		end
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
	for i = 1, #entry.conditions do
		entry.log = tools:iif(l, entry.log, entry.log .. " " .. entry.conditions[i].getLog())
		if self.auto then
			-- Contrôle des conditions
			self.currentMainId = entry.mainid
			self.currentCondition = entry.conditions[i]
			local check, msg = entry.conditions[i].control()
			if not check then erreur = msg end
			if not entry.conditions[i].hasValue then
				check = false
				erreur = string.format(self.trad.not_an_condition, entry.conditions[i].getLog())
			end
			correct = correct and check
		end
	end

	entry.log = tools:iif(l, entry.log, entry.log .. " => ")

	for i = 1, #entry.actions do
		entry.log = tools:iif(l, entry.log, entry.log .. " " .. entry.actions[i].getLog())
		if self.auto then
			-- Contrôle des actions
			self.currentAction = entry.actions[i]
			local check, msg = entry.actions[i].control()
			if not check then erreur = msg end
			if not entry.actions[i].hasAction then
				check = false
				erreur = string.format(self.trad.not_an_action, entry.actions[i].getLog())
			end
			correct = correct and check
		end
	end
	entry.simplelog = entry.log
	entry.log = entry.log .. tools:color("gray", tools:iif(entry.repeating, " *"..self.trad.repeated.."*", "") .. tools:iif(entry.stopped, " *"..self.trad.stopped.."*", "") .. tools:iif(entry.maxtime > 0, " *"..self.trad.maxtime.."="..entry.maxtime.."*", ""))

	if correct then
		if self.auto then
			tools:print(nil, tools:color("cyan", self.trad.add_auto), entry.log)
		elseif self.debug then
			tools:print(nil, tools:color("cyan", self.trad.add_event), entry.log)
		end
		table.insert(self.entries, entry)
		--tools:print("silver", "GEA:addEntry() OK") -- DEBUG
		return entry.id
	else
		tools:error(tools:color("cyan", tools:iif(entry.getDuration() < 0, self.trad.add_event, self.trad.add_auto)), tools:color("white", entry.log), self.trad.err_rule_excluded, ":", erreur)
		--tools:error(self.trad.gea_failed)
		--plugin.restart()
		return
	end
end

-- --------------------------------------------------------------------------------
-- Execute une function et attends un retour
-- --------------------------------------------------------------------------------
--[[
function GEA:waitWithTimeout(func, sleep, max)
	local ok, result = func()
	while (not ok and max > 0) do
		fibaro.sleep(sleep)
		max = max - sleep
		ok, result = func()
	end
	return result
end
--]]

-- --------------------------------------------------------------------------------
-- Vérifie une entrée pour s'assurer que toutes les conditions soient remplies
-- --------------------------------------------------------------------------------
function GEA:check(entry)

	if self.options.restarttask.getValue(entry.id) then
		self:reset(entry)
		self.stoppedTasks[entry.id] = nil
		globalvalue = globalvalue:gsub("|R_" .. entry.id.."|", ""):gsub("|S_" .. entry.id.."|", ""):gsub("|M_" .. entry.id .. "{(%d+)}|", "")
	end
	if self.options.stoptask.getValue(entry.id) then entry.stopped = true end

	-- test des conditions
	local ready = true
	for i = 1, #entry.conditions do
		--tools:print("silver", "GEA:check() i = " .. i) -- DEBUG
		self.currentCondition = entry.conditions[i]
		--for k, v in pairs(entry.conditions[i]) do tools:print("silver", "GEA:check() k = " .. k .. " - v : " .. type(v) .. " => " .. tostring(v)) end -- DEBUG
		local result, _ = entry.conditions[i].check()
		if self.lldebug then tools:print("silver", "GEA:check() result = " .. (result and tools:color("green", tools:tostring(result, true, true)) or tools:color("red", tools:tostring(result, true, true))) .. ", " .. tools:tostring(_, true, true)) end
		ready = ready and result
	end
	if self.lldebug then tools:print("silver", "GEA:check() ready =", ready and tools:color("green", tools:tostring(ready, true, true)) or tools:color("red", tools:tostring(ready, true, true))) end

	if entry.stopped then
		if not self.stoppedTasks[entry.id] and self.debug or self.lldebug then tools:print(nil, "&nbsp;&nbsp;&nbsp;["..tools:color("orange", self.trad.stopped).."] " .. entry.log) end
		self.stoppedTasks[entry.id] = true
	elseif self.debug then
		tools:print(nil, "@" .. (self.nbRun*self.checkEvery) .. "s [" .. tools:iif(ready, tools:color("green", self.trad.validate.."*"), tools:color("red", self.trad.validate)) .. "] " .. entry.log)
	end

	-- si toutes les conditions sont validées
	if ready then
		if entry.stopped then return end
		if tools:isNil(entry.lastvalid) then entry.lastvalid = self.runAt end
		if tools:isNil(entry.firstvalid) then entry.firstvalid = self.runAt end
		if os.difftime(self.runAt, entry.lastvalid) >= entry.getDuration() then
			if self.lldebug then tools:print("silver", "GEA:check() difftime(" .. os.difftime(self.runAt, entry.lastvalid)..")", tools:color("green", ">="), entry.getDuration()) end
			entry.count = entry.count + 1
			entry.lastvalid = self.runAt
			tools:debug("&nbsp;&nbsp;&nbsp;["..self.trad.start_entry.."] " .. entry.log)
			-- gestion des actions
			for i = 1, #entry.actions do
				self.currentAction = entry.actions[i]
				tools:debug("&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;["..self.trad.action.."] " .. self:getMessage(entry.actions[i].getLog(), nil, true))
				if self.secureAction then
					local status, err = pcall(function() entry.actions[i].action() end)
					if not status then
						if self.debug then
							tools:error(err)
						end
						tools:error(self.trad.err_check .. entry.actions[i].getLog())
						self:addHistory(self.trad.err_check .. entry.simplelog)
					end
				else
					entry.actions[i].action()
				end
			end
			-- Envoi message push
			if entry.message ~= "" then
				if type(self.output) ~= "function" then
					-- Message push standard
					for i = 1, #entry.portables do
						local status, err = pcall(function() self:getOption({"Portable", entry.portables[i], self:getMessage()}).action() end)
						if not status then
							if self.debug then
								tools:error(err)
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
		elseif self.lldebug then
			tools:print("silver", "GEA:check() difftime(" .. os.difftime(self.runAt, entry.lastvalid)..")", tools:color("red", "<"), entry.getDuration())
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
			local d = tools:split(c:gsub("{", ""):gsub("}", ""), ",")
			for i = 1, #d do
				d[i] = tools:trim(d[i])
				if tools:isNumber(d[i]) then d[i] = tonumber(d[i])
				elseif d[i]:lower()=="true" then d[i] = true
				elseif d[i]:lower()=="false" then d[i] = false
				end
			end
			local res, mess = self:getOption(d).getValue()
			if type(mess) == "nil" then mess = "n/a" end
			message = message:gsub(c, tostring(mess))
		end
	end)
	--tools:print("silver", "GEA:getMessage() => " .. tostring(message)) -- DEBUG
	if not forAnalyse then
		message = message:gsub("#runs#", self.options.runs.getValue())
		message = message:gsub("#seconds#", self.options.seconds.getValue())
		message = message:gsub("#duration#", self.options.duration.getValue())
		message = message:gsub("#durationfull#", self.options.durationfull.getValue())
		message = message:gsub("#time#", self.options.time.getValue())
		message = message:gsub("#date#", self.options.date.getValue())
		message = message:gsub("#datefull#", self.options.datefull.getValue())
		message = message:gsub("#trigger#", self.options.trigger.getValue())
		message = message:gsub("#profile#", self.options.profile.getValue())
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
		for k, v in pairs(tools:split(property, ".")) do
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
-- Recherche et activation des plugins scénarios
-- --------------------------------------------------------------------------------
--[[ -- Désactivé car les scènes ne peuvent plus recevoir de paramètres sur HC3
function GEA:searchPlugins()
	if not self.auto then
		local vgplugins = self:getGlobalValue(self.pluginsvariables)
		if vgplugins and vgplugins ~= "" and vgplugins ~= "NaN" then
			self.plugins = json.decode(vgplugins)
			for k, _ in pairs(self.plugins) do if k ~= "retour" then self.options[k] = self:copyOption("pluginscenario", k) end end
		end
		return
	end
	local message = tools:color("cyan", self.trad.search_plugins)
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
				if not tools:checkVG(self.pluginsvariables) then
					tools:trace(string.format(self.trad.gea_global_create, self.pluginsvariables))
					tools:createVG(self.pluginsvariables, "")
				end
				fibaro.setGlobalVariable(self.pluginsvariables, json.encode(self.plugins))
			end
		end
	end
	if not found then message = message .. " " .. self.trad.plugins_none end
	tools:print(nil, message)
	tools:print("cyan", "----------------------------------------------------------------------------------------------------")
end
--]]

-- --------------------------------------------------------------------------------
-- Permet de retourner les infos de GEA à qui besoin
-- --------------------------------------------------------------------------------
--[[
function GEA:answer(params)
	--if tools:isNil(self:getGlobalValue(self.historyvariable)) then self.history = {} else self.history = json.decode(self:getGlobalValue(self.historyvariable)) end
	local histo = quickApp:getVariable(self.historyvariable)
	if histo and histo ~= "" then self.history = json.decode(histo) else self.history = {} end
	if params.vdid then
		for k, v in pairs(params) do
			if type(v)=="string" and v:match("%[(%d+)%]") and type(self[v:gsub("%[(%d+)%]", "")]) == "table" then
				local number = tonumber(v:match("%[(%d+)%]") or 1)
				if number then
					v = v:gsub("%[(%d+)%]", "")
					fibaro.call(params.vdid, "updateView", k, "text", tools:iif(self[v][number], tools:tostring(self[v][number]), ""))
				end
			elseif type(self[v]) ~= "function" and type(self[v]) ~= "nil" then
				fibaro.call(params.vdid, "updateView", k, "text", " " .. tools:tostring(self[v]))
			end
		end
	end
end
--]]

-- --------------------------------------------------------------------------------
-- Optimisation du code
-- --------------------------------------------------------------------------------
function GEA:optimise()
	tools:print("gray", "----------------------------------------------------------------------------------------------------")
	tools:print("gray", self.trad.optimization)
	self.answer = nil
	self.insert = nil
	self.searchPlugins = nil
	self.add = nil
	self.copyOption = nil
	self.init = nil
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
			tools:print("gray", self.trad.removeuseless .. v)
			self.options[v] = nil
		end
	end
	self.usedoptions = nil
	for k, _ in pairs(self.traduction) do if k ~= string.lower(language) and k ~= "en" then tools:print("gray", self.trad.removeuselesstrad .. k) self.traduction[k] = nil end end
	tools:print("gray", "----------------------------------------------------------------------------------------------------")
end

-- --------------------------------------------------------------------------------
-- Lance le contrôle de toutes les entrées
-- --------------------------------------------------------------------------------
function GEA:run()

	self.runAt = os.time()
	self.forceRefreshValues = false
	self.nbRun = self.nbRun + 1
	if self.nbRun > 0 then
		if math.fmod(self.nbRun, 10) == 0 then
			local garbage = collectgarbage("count")
			local newExecTime = os.time()
			local elapsedTime = os.difftime(newExecTime, self.lastExecTime or 0)
			self.lastExecTime = newExecTime
			local cpuConsumed = os.clock()
			local cpuDelta = cpuConsumed - self.cpuConsumed
			self.cpuConsumed = cpuConsumed
			tools:print("gray", string.format(self.trad.gea_run_since, self:getDureeInString(self.runAt-self.started)) .. " - " .. string.format(self.trad.memoryused, garbage) .. " - " .. string.format(self.trad.cpuused, cpuDelta*1000, cpuDelta/elapsedTime*100/self.nbCPUs))
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
				if up then tools:warning(self.trad.memoryused .. string.format("%.2f", previous) .. " KB" ) end
			end
			if #self.garbagevalues >= 10 then table.remove(self.garbagevalues, 1) end
		elseif self.nbRun == 1 and self.optimize then
			tools:optimize()
			self:optimise()
			self.optimise = nil
		end
	elseif self.auto then
		self.lastExecTime = os.time()
		self.nbCPUs = #(api.get("/diagnostics").cpuLoad or {{}})
		if self.nbCPUs < 1 then self.nbCPUs = 1 end
		self.cpuConsumed = os.clock()
	end
	if self.auto and self.debug then
		tools:print("cyan", string.format(self.trad.gea_check_nbr, self.nbRun, (self.nbRun*self.checkEvery)))
	end

	quickApp:updateView("labelRunning", "text", "Running : " .. (running and self.trad.yes or self.trad.no))
	if running then
		local nbEntries = #self.entries
		if nbEntries > 0 then
			self.refreshDeviceProperties = true
			self.refreshLabelValues = true
			self.refreshSliderValues = true
			self.refreshClimatePanel = true
			self.refreshPartitionProperties = true
			self.refreshGlobalVariables = true
			self.refreshQuickAppVariables = true
			self.refreshSceneProperties = true
			self.refreshWeather = true
			self.refreshActiveProfile = true
			self.refreshSettingsInfo = true
			for i = 1, nbEntries do
				self.currentMainId = self.entries[i].mainid
				self.currentEntry = self.entries[i]
				self:check(self.entries[i])
			end
			if self.historymax > 0 then
				quickApp:setVariable(self.historyvariable, json.encode(self.history))
			end
		end
	else
		tools:warning(string.format(self.trad.gea_suspended, self.suspendvar))
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

	-- Chargement des options de configuration utilisateur
	if type(config) == "function" then
		config(self)
	end

	-- Recherche de la langue des traductions
	if not language then
		if self.language then
			language = self.language
		else
			if api then language = self:getSettingsInfo("defaultLanguage") end
		end
	end
	if not self.traduction[language] then language = "en" end
	self.trad = self.traduction[string.lower(language)]

	-- Notifications Push
	if type(self.portables) ~= "table" then self.portables = {self.portables} end

	-- Affichage bannière de démarrage
	if self.lldebug then tools:print("silver", "GEA:init() self.source =", tools:tostring(self.source, true, true)) end
	if self.auto then
		tools:trace("")
		tools:trace("----------------------------------------------------------------------------------------------------")
		tools:trace(string.format(self.trad.gea_start, self._VERSION, self.source.type))
		tools:trace("----------------------------------------------------------------------------------------------------")
		tools:print("cyan", string.format(self.trad.gea_tools, tools._VERSION or tools.version))
		tools:print("cyan", string.format(self.trad.gea_check_every, self.checkEvery))
		tools:print("cyan", string.format(self.trad.gea_qa_variable, self.historyvariable))
		quickApp:updateView("labelVersion", "text", "Version : " .. self._VERSION)
		quickApp:updateView("labelIntervalle", "text", "Intervalle : " .. tostring(self.checkEvery) .. "s")
		quickApp:updateView("labelPortables", "text", "Portables : " .. json.encode(self.portables))
		quickApp:updateView("labelDebug", "text", "Debug : " .. (self.debug and self.trad.yes or self.trad.no))
	end
	if self.source.type ~= "manual" and self.auto then tools:print("cyan", "----------------------------------------------------------------------------------------------------") end
	--local line, result = nil, nil
	if not self.auto then
		self.event = {}
		if self.source.type == "device" then
			self.event.id = self.source.id
			if self.source.propertyName and self.source.componentName then -- label ou slider
				self.event.label = self.source.componentName
			end
		elseif self.source.type == "global-variable" then
			self.event.id = self.source.name
		elseif self.source.type == "alarm" then
			self.event.id = self.source.id
		elseif self.source.type == "profile" then
			self.event.id = self.source.id
		elseif self.source.type == "weather" then
			self.event.id = self.source.property
		elseif self.source.type == "scene" then
			self.event.id = self.source.id
		elseif self.source.type == "custom-event" then
			self.event.id = self.source.name
		--[[
		elseif self.source.type == "manual" and fibaro:args() then -- Note : démarrage manuel de la scène, à remplacer par une fonction dédiée au QuickApp ?
			local params = {}
			for _, v in ipairs(fibaro:args()) do for h, w in pairs(v) do if h == "gealine" then line = w end if h == "result" then result = w end params[h] = w end end
			if (params.vdid) then
				self:answer(params)
				return
			end
		elseif self.source.type == "date" then
		elseif self.source.type == "location" then
		elseif self.source.type == "panic" then
		elseif self.source.type == "se-start" then
		elseif self.source.type == "climate" then
		--]]
		end
		if self.source.type ~= "manual" then
			tools:trace("----------------------------------------------------------------------------------------------------")
			tools:trace(string.format(self.trad.gea_start_event, self._VERSION, tools:color("white", self.source.type, self.source.msg)))
			tools:trace("----------------------------------------------------------------------------------------------------")
		end
		if self.lldebug then tools:print("silver", "GEA:init() self.event =", tools:tostring(self.event, true, true)) end
	end

	-- Recherche des plugins
	--self:searchPlugins() -- Désactivé car les scènes ne peuvent plus recevoir de paramètres sur HC3
	--if line and result then
		---- retour d'un plugin
		--if not self.plugins.retour then self.plugins.retour = {} end
		--self.plugins.retour[line] = result
		--fibaro.setGlobalVariable(self.pluginsvariables, json.encode(self.plugins))
		--return
	--end

	-- Initialisation
	if self.auto then
		tools:print("cyan", self.trad.gea_load_usercode)
		globalvalue = ""
		quickApp:setVariable(self.historyvariable, "")
		local suspendvar = tools.getVariable(quickApp, self.suspendvar)
		if suspendvar then
			running = string.lower(suspendvar) ~= self.trad.yes
		else
			running = true
			quickApp:setVariable(self.suspendvar, self.trad.no)
		end
		local histo = quickApp:getVariable(self.historyvariable)
		if histo and histo ~= "" then self.history = json.decode(histo) else self.history = {} end
	end

	-- Chargement des règles utilisateur
	if type(setEvents) == "function" then
		setEvents()
	else
		tools:error(self.trad.err_no_usercode)
	end
	tools.isdebug = self.debug
	if #self.entries == 0 then
		tools:warning(self.trad.gea_nothing)
	end

	-- Affichage des déclencheurs instantanés
	if self.auto then
		tools:print("cyan", "----------------------------------------------------------------------------------------------------")
		tools:print("cyan", string.format(GEA_auto.trad.instant_trigger, #triggers))
		if #triggers > 0 then
			for i = 1, #triggers do
				local trigger = triggers[i]
				local msg
				if trigger.event.type == "device" then
					local name, exist = self:getDeviceFullName(trigger.event.id, self.showRoomNames)
					if exist then name = tools:color("green", name) else name = tools:color("red", name) end
					local property
					if trigger.event.propertyName and trigger.event.componentName then -- Label ou Slider
						if trigger.event.propertyName == "text" then
							property = "label" .. " " .. (self.options.checklabel.getValue(trigger.event.id, trigger.event.componentName) and tools:color("yellow", trigger.event.componentName) or tools:color("red", trigger.event.componentName))
						elseif trigger.event.propertyName == "value" then
							property = "slider" .. " " .. (self.options.checkslider.getValue(trigger.event.id, trigger.event.componentName) and tools:color("yellow", trigger.event.componentName) or tools:color("red", trigger.event.componentName))
						else
							property = trigger.event.propertyName .. " " .. trigger.event.componentName
						end
					elseif trigger.event.property == "centralSceneEvent" then -- CentralSceneEvent
						if self.options.checkproperty.getValue(trigger.event.id, "centralSceneSupport") then property = tools:color("yellow", trigger.event.property) else property = tools:color("red", trigger.event.property) end
						property = property .. (trigger.event.value and " " .. (trigger.event.value.keyId or " ") .. " " .. (trigger.event.value.keyAttribute or " ") or "")
					else
						if self.options.checkproperty.getValue(trigger.event.id, trigger.event.property or trigger.event.propertyName) then property = tools:color("yellow", trigger.event.property) else property = tools:color("red", trigger.event.property) end
					end
					msg = "#" .. (trigger.event.id or "?id?") .. " <b>" .. name .. "</b> <b>" .. property .. "</b>"
				elseif trigger.event.type == "global-variable" then
					local name
					if self.options.checkvg.getValue(trigger.event.name) then name = tools:color("green", trigger.event.name) else name = tools:color("red", trigger.event.name) end
					msg = "<b>" .. name .. "</b>"
				elseif trigger.event.type == "alarm" then
					if trigger.event.id then
						local name, exist = self:getPartitionNameInCache(trigger.event.id)
						if exist then name = tools:color("green", name) else name = tools:color("red", name) end
						msg = "#" .. trigger.event.id .. " <b>" .. name .. "</b> " or ""
					else
						msg = ""
					end
					msg = msg .. tools:color("yellow", trigger.event.property or "?property?")
				elseif trigger.event.type == "profile" then
					local name, exist = self:getProfileNameInCache(trigger.event.id)
					if exist then name = tools:color("green", name) else name = tools:color("red", name) end
					msg = "#" .. trigger.event.id .. " <b>" .. name .. "</b>"
				elseif trigger.event.type == "weather" then
					local property
					if self:getWeather(trigger.event.property) ~= nil then property = tools:color("green", trigger.event.property) else property = tools:color("red", trigger.event.property) end
					msg = "<b>" .. property .. "</b>"
				elseif trigger.event.type == "scene" then
					local name, exist = self:getSceneNameInCache(trigger.event.id)
					if exist then name = tools:color("green", name) else name = tools:color("red", name) end
					msg = "#" .. (trigger.event.id or "?id?") .. " <b>" .. name .. "</b>"
				elseif trigger.event.type == "custom-event" then
					local name, exist = self:getCustomEventNameInCache(trigger.event.name)
					if exist then name = tools:color("green", name) else name = tools:color("red", name) end
					msg = "<b>" .. name .. "</b>"
				else
					msg = "???"
				end
				trigger.event.msg = msg
				tools:print(nil, tools:color("cyan", "Trigger :"),
					trigger.event.type,
					msg
				)
			end
		else
			tools:warning(self.trad.no_instant_trigger)
		end
		tools:print("cyan", "----------------------------------------------------------------------------------------------------")
	end

	self.control = false
	if #self.entries > 0 then
		self.started = os.time()
		if self.auto then
			tools:print("cyan", string.format(self.trad.gea_start_time, os.date(self.trad.date_format, self.started), os.date(self.trad.hour_format, self.started)))
			tools:print("cyan", "----------------------------------------------------------------------------------------------------")
		end
		self:run()
	else
		if self.auto then
			tools:print("cyan", self.trad.gea_stopped_auto)
			return
		else
			tools:warning(string.format(self.trad.no_entry_for_event, self.options.trigger.getValue()))
		end
	end
end



-- ================================================================================
-- M A I N ... démarrage de GEA
-- ================================================================================

local function start()

	-- Initialisation
	local lastRefresh = 0
	local http = net.HTTPClient()
	local http_request = http.request

	-- Démarre l'instance principale de GEA
	GEA_auto = GEA({type = "autostart"})
	GEA_auto:init()

	-- Boucle d'attente d'événements instantanés
	local nbTriggers = #triggers
	local lldebug = GEA_auto.lldebug
	local refreshInterval = GEA_auto.refreshInterval
	local json_decode = json.decode
	local tools_deepFilter = tools.deepFilter
	local function loop()
		local status, err = pcall(function()
			local stat, res = http_request(http, "http://127.0.0.1:11111/api/refreshStates?last=" .. lastRefresh, {
				success = function(res)
					local status, states = pcall(function() return json_decode(res.data) end)
					if status then
						if type(states) == "table" then
							lastRefresh = states.last or 0
							local events = states.events
							local nbEvents = #(events or {})
							for i = 1, nbEvents do
								local event = events[i]
								for j = 1, nbTriggers do
									local trigger = triggers[j]
									if tools_deepFilter(tools, event, trigger.filter) then
										if lldebug then tools:print("silver", "Event : " .. json.encode(trigger.filter)) end
										-- Démarre une instance instantanée de GEA
										GEA_event = GEA(trigger.event)
										GEA_event:init()
										GEA_event = nil
									end
								end
							end
						else
							tools:error("Invalid states :", type(states))
						end
					else
						tools:error(states or "json.decode() failed")
					end
					setTimeout(loop, refreshInterval)
				end,
				error = function(res)
					tools:error("Error : API refreshStates :", res)
					setTimeout(loop, 5 * refreshInterval)
				end,
			})
		end)
		if not status then
			tools:error(err)
			setTimeout(loop, 5 * refreshInterval)
		end
	end

	if nbTriggers > 0 then
		loop()
	end

end


function QuickApp:onInit()

	-- Check dependent libraries
	if not tools then
		self:error("Fatal error : tools library not found")
		self:updateView("labelRunning", "text", "Error : tools library not found")
		self:updateProperty("log", "Error")
		return
	end
	if not tonumber(tools.version) or tools.version < 2.12 then
		self:error("Fatal error : tools library too old")
		self:updateView("labelRunning", "text", "Error : tools library version too old")
		self:updateProperty("log", "Error")
		return
	end
	if not GEA then
		tools:error("Fatal error : GEA library not found")
		tools.updateLabel(self, "labelRunning", "Error : GEA library not found")
		tools.log(self, "Error", 0)
		return
	end

	-- Check if QuickApp device is enabled
	if not api.get("/devices/"..tostring(self.id)).enabled then
		tools.log(self, "Disabled", 0)
		tools.updateLabel(self, "labelRunning", "QuickApp Disabled")
		tools:warning("Device", self.name, "is disabled => QuickApp stopped")
		return
	end

	-- Update main device properties
	tools.log(self, "", 0)

	setTimeout(start, 0)

end


function QuickApp:buttonON_onReleased(event)
	tools:trace("Réactivation de GEA")
	running = true
	self:setVariable(GEA_auto.suspendvar, GEA_auto.trad.no)
	tools.updateLabel(self, "labelRunning", "Running : " .. GEA_auto.trad.yes)
end


function QuickApp:buttonOFF_onReleased(event)
	tools:trace("Désactivation de GEA")
	running = false
	self:setVariable(GEA_auto.suspendvar, GEA_auto.trad.yes)
	tools.updateLabel(self, "labelRunning", "Running : " .. GEA_auto.trad.no)
end


function QuickApp:answer()
	if askAnswerAction then
		askAnswerAction.action(true)
		askAnswerAction = nil
	end
end
