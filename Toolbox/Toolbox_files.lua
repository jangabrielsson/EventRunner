--[[
  Toolbox triggers.
  
  Functions to copy QA files

  function QuickApp:copyFileFromTo(fileName,deviceFrom,deviceTo) -- Copies file from one QA to another
  function QuickApp:addFileTo(fileContent,device)                -- Creates a new file for a QA
  function QuickApp:listFiles(device)                            -- Get list of all files
  function QuickApp:getFile(fileName,device)                     -- Get file
--]]

Toolbox_Module = Toolbox_Module or {}
Toolbox_Module.file ={
  name = "File manager",
  author = "jan@gabrielsson.com",
  version = "0.1"
}

function Toolbox_Module.file.init(self)

  function self:deleteFile(deviceId,file)
    local name = type(file)=='table' and file.name or file
    return api.delete("/quickApp/"..deviceId.."/files/"..name)
  end

  function self:updateFile(deviceId,file,content)
    if type(file)=='string' then
      file = {isMain=false,isOpen=false,name=file,content=""}
    end
    file.content = type(content)=='string' and content or file.content
    return api.put("/quickApp/"..deviceId.."/files/"..file.name,file) 
  end

  function self:updateFiles(deviceId,list)
    return api.put("/quickApp/"..deviceId.."/files",list) 
  end

  function self:createFile(deviceId,file,content)
    if type(file)=='string' then
      file = {isMain=false,isOpen=false,name=file,content=""}
    end
    file.content = type(content)=='string' and content or file.content
    return api.post("/quickApp/"..deviceId.."/files",file) 
  end

  function self:getFile(deviceId,file)
    local name = type(file)=='table' and file.name or file
    return api.get("/quickApp/"..deviceId.."/files/"..name) 
  end

  function self:getFiles(deviceId)
    local res,code = api.get("/quickApp/"..deviceId.."/files")
    return res or {},code
  end

  function self:copyFileFromTo(fileName,deviceFrom,deviceTo)
    deviceTo = deviceTo or self.id
    local copyFile = self:getFile(deviceFrom,fileName)
    assert(copyFile,"File doesn't exists")
    self:addFileTo(copyFile.content,fileName,deviceTo)
  end

  function self:addFileTo(fileContent,fileName,deviceId)
    local file = self:getFile(deviceId,fileName)
    if not file then
      local stat,res = self:createFile(deviceId,{   -- Create new file
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
      local stat,res = self:updateFile(deviceId,fileName,{   -- Update existing file
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