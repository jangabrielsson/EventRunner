--[[
  Toolbox triggers.
  
  Functions to copy QA files

  function QuickApp:copyFileFromTo(fileName,deviceFrom,deviceTo) -- Copies file from one QA to another
  function QuickApp:addFileTo(fileContent,device)                -- Creates a new file for a QA
  function QuickApp:getFiles(device)                             -- Get list of all files
  function QuickApp:getFile(device,file)                         -- Get file
  function QuickApp:updateFile(device,file,content)              -- Update file
  function QuickApp:updateFiles(device,list)                     -- Update files
  function QuickApp:createFile(device,file,content)              -- Create file
  function QuickApp:deleteFile(device,file)                      -- Delete file
  function QuickApp:getManifest(url,callback)
  function QuickApp:updateFilesFromRepo(args)
--]]

Toolbox_Module = Toolbox_Module or {}
Toolbox_Module.files ={
  name = "File manager",
  author = "jan@gabrielsson.com",
  version = "0.3"
}

function Toolbox_Module.files.init(self)
  if Toolbox_Module.files.inited then return end
  Toolbox_Module.files.inited = true 
  
  function self:deleteFile(deviceId,file)
    local name = type(file)=='table' and file.name or file
    return api.delete("/quickApp/"..deviceId.."/files/"..name)
  end

  function self:updateFile(deviceId,file,content)
    if type(file)=='string' then
      file = {isMain=false,type='lua',isOpen=false,name=file,content=""}
    end
    file.content = type(content)=='string' and content or file.content
    return api.put("/quickApp/"..deviceId.."/files/"..file.name,file) 
  end

  function self:updateFiles(deviceId,list)
    if #list == 0 then return true end
    return api.put("/quickApp/"..deviceId.."/files",list) 
  end

  function self:createFile(deviceId,file,content)
    if type(file)=='string' then
      file = {isMain=false,type='lua',isOpen=false,name=file,content=""}
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
      local stat,res = self:updateFile(deviceId,{   -- Update existing file
          name=file.name,
          type="lua",
          isMain=file.isMain,
          isOpen=file.isOpen,
          content=fileContent
        })
      if res == 200 then
        self:debug("File '",fileName,"' updated")
      else self:error("Error:",res) end
    else
      self:debug("File '",fileName,"' not changed")
    end
  end

  function QuickApp:replicateTo(id)
    local dest = self:getFiles(id)
    local src = self:getFiles(self.id)
    for _,f in ipairs(dest) do
      if not f.isMain then self:deleteFile(id,f.name) end
    end
    for _,f in ipairs(src) do self:copyFileFromTo(f.name,self.id,id) end    
  end

  function QuickApp:patchTwins(name,value)
    local n = 0
    for _,d in ipairs(api.get("/devices?interface=quickApp") or {})  do
      if d.id ~= self.id then
        for _,qv in ipairs(d.properties.quickAppVariables or {}) do
          if qv.name==name and qv.value==value then
            self:tracef("Updating QAid:%s, '%s'",d.id,d.name)
            self:replicateTo(d.id)
            n = n+1
          end
        end
      end
    end
    return n
  end

  function self:getFQA(deviceId) return api.get("/quickApp/export/"..deviceId) end

  function self:putFQA(content) -- Should be .fqa json
    if type(content)=='table' then content = json.encode(content) end
    return api.post("/quickApp/",content)
  end


-- Functions for autoupdating QA from web location (ex. GitHub)
-- still experimental...

  local function httpGet(url,callback,err)
    net.HTTPClient():request(url,{
        options={method="GET", checkCertificate = false, timeout=5000},
        success=function(res) 
          if res.status <= 204 then callback(res.data) else
            if err then err(res.status) end
          end
        end,
        error=function(res)  if err then err(res.status) end end,
      })
  end

  function self:getManifest(url,callback)
    local errMsg = "Unable to retrieve manifest:%s - %s"
    httpGet(url,
      function(data)
        local stat,res = pcall(function()
            local manifest = json.decode(data)
            callback(manifest)
          end)
        if not stat then self:errorf(errMsg,res,url)  end
      end,
      function(err) self:errorf(errMsg,err,url) end
    )
  end

  local function getFiles_aux(cont)
    local files = cont.files
    if #files == 0 then cont.cont(cont.res)
    else
      local args = files[1]
      table.remove(files,1)
      net.HTTPClient():request(args.url,{
          options={method="GET", checkCertificate = false, timeout=5000},
          success=function(res) 
            if res.status <= 204 then
              cont.res[args.name]=res.data
            else cont.error(res.status) end
            getFiles_aux(cont)
          end,
          error=function(res) cont.error(res) getFiles_aux(cont) end,
        })
    end
  end

  local function getFiles(args)
    local files = args.files
    local deviceId = args.id or self.id
    getFiles_aux{
      res = {},
      files = files,
      id = deviceId,
      error = function(res) self:warningf("%s",res) end,
      cont = function(res) -- Files we got
        local update = {}
        local create = {}
        local delete = {}
        local seen = {}
        for name,content in pairs(res) do
          local f = self:getFile(deviceId,name)
          if not f then 
            create[name]=content
          elseif f.content ~= content then
            local e = {isMain=false,type='lua',isOpen=false,name=name,content=content}
            update[#update+1]=e
          else self:tracef("File '%s' up to date",name) end
          seen[name]=true
        end
        for _,f in ipairs(self:getFiles(deviceId)) do 
          if not seen[f.name] then delete[#delete+1]=name end
        end           -- fileContent,fileName,deviceId)
        if next(create) then 
          for name,content in pairs(create) do 
            self:tracef("Creating file '%s'",name)
            if not args.test then self:addFileTo(content,name,deviceId) end
          end 
        end
        if #delete > 0 and args.delete == true then 
          for _,name in ipairs(delete) do 
            self:tracef("Deleting file '%s'",name)
            if not args.test then self:deleteFile(deviceId,name) end
          end
        end
        if #update > 0 then 
          for _,f in ipairs(update) do self:tracef("Updating file '%s'",f.name) end
          if not args.test then self:updateFiles(deviceId,update) end
        end
      end
    }
  end

--  <fileList> = {
--    {name='Test', url="...."},
--  }

--  <args> = {
--    files = <filelist>,
--    deviceId = <QA id>,
--    ignoreUpdated = <boolean>,
--  }
  function self:updateFilesFromRepo(args) getFiles(args) end

end

Toolbox_Module.file = Toolbox_Module.files
Toolbox_Module.file.init = Toolbox_Module.files.init