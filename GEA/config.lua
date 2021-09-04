function config(GEA)
	-- ===================================================
	-- Configuration générale
	-- ===================================================
	GEA.debug = false
	GEA.portables = {}
end

function setEvents()
	-- ==========================================================
	-- Règles utilisateur
	-- ==========================================================

	local id = {
	}

	GEA.add(true, 0, "Démarrage de GEA le #date# à #time#", nil, "Démarrage GEA")
	GEA.add({"Info+", "serverStatus", os.time()-120}, 0, "Box redémarrée le #date# à #time#", nil, "Démarrage box")
	GEA.add({"Info", "updateStableAvailable", true}, 24*60*60, "Une nouvelle version Stable est disponible", nil, "Détection nouvelle version stable")
	GEA.add({"Info", "updateBetaAvailable", true}, 24*60*60, "Une nouvelle version BETA est disponible", nil, "Détection nouvelle version beta")
  GEA.add(48, -1, "Hupp", {{"TurnOn", 30}}) 


end

