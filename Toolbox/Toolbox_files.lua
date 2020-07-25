--[[
  Toolbox triggers.
  
  Functions to copy QA files

  function QuickApp:copyFileFromTo(fileName,deviceFrom,deviceTo) -- Copies file from one QA to another
  function QuickApp:addFileTo(fileContent,device)                -- Creates a new file for a QA
--]]

Toolbox_Module = Toolbox_Module or {}

function Toolbox_Module.file(self)
  local version = "0.1"
  self:debugf("Setup: File manager (%s)",version)

  function self:copyFileFromTo(fileName,deviceFrom,deviceTo)
    deviceTo = deviceTo or self.id
    local copyFile = api.get(("/quickApp/%s/files/%s"):format(deviceFrom,fileName))
    assert(copyFile,"File doesn't exists")
    self:addFileTo(copyFile.content,fileName,deviceTo)
  end

  function self:addFileTo(fileContent,fileName,deviceId)
    local file = api.get(("/quickApp/%s/files/%s"):format(deviceId,fileName))
    if not file then
      local stat,res = api.post(("/quickApp/%s/files"):format(deviceId),{   -- Create new file
          name=fileName,
          type="lua",
          isMain=false,
          isOpen=false,
          content=fileContent
        })
      if res == 200 then
        self:debug("File '",fileName,"' added")
      else self:error("Error:",res) end
    elseif file.content ~= fileContent then
      local stat,res = api.put(("/quickApp/%s/files/%s"):format(deviceId,fileName),{   -- Update existing file
          name=fileName,
          type="lua",
          isMain=false,
          isOpen=false,
          content=fileContent
        })
      if res == 200 then
        self:debug("File '",fileName,"' updated")
      else self:error("Error:",res) end
    else
      self:debug("File '",fileName,"' not changed")
    end
  end

end