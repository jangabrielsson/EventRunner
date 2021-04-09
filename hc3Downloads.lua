local version = "1.0"
local downloads = {
  ["fibaroapiHC3.lua"] = {
    url="https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/fibaroapiHC3.lua",
    path = "fibaroapiHC3.lua"
  },
  ["fibaroapiHC3plug.lua"] = {
    url="https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/fibaroapiHC3plug.lua",
    path = "fibaroapiHC3plug.lua"
  },
  ["Toolbox/*"] = {
    pathdir = "Toolbox",
    urldir = "https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/Toolbox/",
    files = {
      ["Toolbox_basic.lua"]="Toolbox_basic.lua",
      ["Toolbox_events.lua"]="Toolbox_events.lua",
      ["Toolbox_child.lua"]="Toolbox_child.lua",
      ["Toolbox_triggers.lua"]="Toolbox_triggers.lua",
      ["Toolbox_files.lua"]="Toolbox_files.lua",
      ["Toolbox_rpc.lua"]="Toolbox_rpc.lua",
      ["Toolbox_pubsub.lua"]="Toolbox_pubsub.lua",
      ["Toolbox_ui.lua"]="Toolbox_ui.lua",
    }
  },
  ["EventRunner4.lua"] = {
    url="https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/EventRunner4.lua",
    path = "EventRunner4.lua"
  },
  ["EventRunnerEngine.lua"] = {
    url="https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/EventRunnerEngine.lua",
    path = "EventRunnerEngine.lua"
  },
  ["MQTT/*"] = {
    pathdir = "mqtt",
    urldir = "https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/mqtt/",
    files = {
      ["bit53.lua"]="bit53.lua",
      ["bitwrap.lua"]="bitwrap.lua",
      ["client.lua"]="client.lua",
      ["init.lua"]="init.lua",
      ["ioloop.lua"]="ioloop.lua",
      ["luasocket_ssl.lua"]="luasocket_ssl.lua",
      ["luasocket.lua"]="luasocket.lua",
      ["ngxsocket.lua"]="ngxsocket.lua",
      ["protocol.lua"]="protocol.lua",
      ["protocol4.lua"]="protocol4.lua",
      ["protocol5.lua"]="protocol5.lua",
      ["tools.lua"]="tools.lua",
    }
  },  
  ["wsLua_ER.lua"] = {
    url="https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/wsLua_ER.lua",
    path = "wsLua_ER.lua"
  },
  ["credentials_ex.lua"] = {
    url="https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/credentials_ex.lua",
    path = "credentials_ex.lua"
  },
}

return {version=version, files=downloads}