local EM,FB = ...

local json,LOG = FB.json,EM.LOG

local CRC16Lookup = {
  0x0000,0x1021,0x2042,0x3063,0x4084,0x50a5,0x60c6,0x70e7,0x8108,0x9129,0xa14a,0xb16b,0xc18c,0xd1ad,0xe1ce,0xf1ef,
  0x1231,0x0210,0x3273,0x2252,0x52b5,0x4294,0x72f7,0x62d6,0x9339,0x8318,0xb37b,0xa35a,0xd3bd,0xc39c,0xf3ff,0xe3de,
  0x2462,0x3443,0x0420,0x1401,0x64e6,0x74c7,0x44a4,0x5485,0xa56a,0xb54b,0x8528,0x9509,0xe5ee,0xf5cf,0xc5ac,0xd58d,
  0x3653,0x2672,0x1611,0x0630,0x76d7,0x66f6,0x5695,0x46b4,0xb75b,0xa77a,0x9719,0x8738,0xf7df,0xe7fe,0xd79d,0xc7bc,
  0x48c4,0x58e5,0x6886,0x78a7,0x0840,0x1861,0x2802,0x3823,0xc9cc,0xd9ed,0xe98e,0xf9af,0x8948,0x9969,0xa90a,0xb92b,
  0x5af5,0x4ad4,0x7ab7,0x6a96,0x1a71,0x0a50,0x3a33,0x2a12,0xdbfd,0xcbdc,0xfbbf,0xeb9e,0x9b79,0x8b58,0xbb3b,0xab1a,
  0x6ca6,0x7c87,0x4ce4,0x5cc5,0x2c22,0x3c03,0x0c60,0x1c41,0xedae,0xfd8f,0xcdec,0xddcd,0xad2a,0xbd0b,0x8d68,0x9d49,
  0x7e97,0x6eb6,0x5ed5,0x4ef4,0x3e13,0x2e32,0x1e51,0x0e70,0xff9f,0xefbe,0xdfdd,0xcffc,0xbf1b,0xaf3a,0x9f59,0x8f78,
  0x9188,0x81a9,0xb1ca,0xa1eb,0xd10c,0xc12d,0xf14e,0xe16f,0x1080,0x00a1,0x30c2,0x20e3,0x5004,0x4025,0x7046,0x6067,
  0x83b9,0x9398,0xa3fb,0xb3da,0xc33d,0xd31c,0xe37f,0xf35e,0x02b1,0x1290,0x22f3,0x32d2,0x4235,0x5214,0x6277,0x7256,
  0xb5ea,0xa5cb,0x95a8,0x8589,0xf56e,0xe54f,0xd52c,0xc50d,0x34e2,0x24c3,0x14a0,0x0481,0x7466,0x6447,0x5424,0x4405,
  0xa7db,0xb7fa,0x8799,0x97b8,0xe75f,0xf77e,0xc71d,0xd73c,0x26d3,0x36f2,0x0691,0x16b0,0x6657,0x7676,0x4615,0x5634,
  0xd94c,0xc96d,0xf90e,0xe92f,0x99c8,0x89e9,0xb98a,0xa9ab,0x5844,0x4865,0x7806,0x6827,0x18c0,0x08e1,0x3882,0x28a3,
  0xcb7d,0xdb5c,0xeb3f,0xfb1e,0x8bf9,0x9bd8,0xabbb,0xbb9a,0x4a75,0x5a54,0x6a37,0x7a16,0x0af1,0x1ad0,0x2ab3,0x3a92,
  0xfd2e,0xed0f,0xdd6c,0xcd4d,0xbdaa,0xad8b,0x9de8,0x8dc9,0x7c26,0x6c07,0x5c64,0x4c45,0x3ca2,0x2c83,0x1ce0,0x0cc1,
  0xef1f,0xff3e,0xcf5d,0xdf7c,0xaf9b,0xbfba,0x8fd9,0x9ff8,0x6e17,0x7e36,0x4e55,0x5e74,0x2e93,0x3eb2,0x0ed1,0x1ef0
}

local function crc16(bytes)
  local crc = 0
  for i=1,#bytes do
    local b = string.byte(bytes,i,i)
    crc = ((crc<<8) & 0xffff) ~ CRC16Lookup[(((crc>>8)~b) & 0xff) + 1]
  end
  return tonumber(crc)
end

local function readFile(file) 
  local f = io.open(file); assert(f,"No such file:"..file) local c = f:read("*all"); f:close() return c
end

local firstTemp = true
local function createTemp(name,content) -- Storing code fragments on disk will help debugging. TBD
  if firstTemp then LOG(EM.LOGINFO1,"Using %s for temporary files",EM.temp) firstTemp=false end
  local crc = crc16(content)
  local fname = EM.temp..name.."_"..crc..".lua" 
  local f,res = io.open(fname,"r") 
  if f then f:close() return fname end -- If it exists, don't store it again
  f,res = io.open(fname,"w+")
  if not f then LOG(EM.LOGERR,"Warning - couldn't create temp files in %s - %s",EM.temp,res) return 
  else LOG(EM.LOGINFO2,"Created temp file %s",fname) end
  f:write(content) 
  f:close()
  return fname
end

local function mergeUI(info)
  local ui,res = {},{}
  for k,v in pairs(info) do if k:match("u%d+$") then ui[#ui+1]={k,v} end end
  table.sort(ui,function(a,b) return a[1] < b[1] end)
  for _,u in ipairs(ui) do res[#res+1]=u[2] info[u[1]]=nil end
  info.UI = res
end

local function loadSource(code,fileName) -- Load code and resolve info and --FILE directives
  local files = {}
  local function gf(pattern)
    code = code:gsub(pattern,
      function(file,name)
        files[#files+1]={name=name,content=readFile(file),isMain=false,fname=file}
        return ""
      end)
  end
  gf([[%-%-FILE:%s*(.-)%s*,%s*(.-);]])
  table.insert(files,1,{name="main",content=code,isMain=true,fname=fileName})
  local info = code:match("%-%-%[%[QAemu(.-)%-%-%]%]")
  if info==nil then
    local il = {}
    code:gsub("%-%-%%%%(.-)[\n\r]+",function(l) il[#il+1]=l end)
    info=table.concat(il,",")
  end
  if info then 
    local icode,res = load("return {"..info.."}")
    if not icode then error(res) end
    info,res = icode()
    if res then error(res) end
  end
  mergeUI(info)
  return files,(info or {})
end

local function loadLua(fileName) return loadSource(readFile(fileName),fileName) end

local function loadFQA(fqa)  -- Load FQA
  local files,main = {}
  for _,f in ipairs(fqa.files) do
    local fname = createTemp(f.name,f.content) or f.name..crc16(f.content) -- Create temp files for fqa files, easier to debug
    if f.isMain then f.fname=fname main=f
    else files[#files+1] = {name=f.name,content=f.content,isMain=f.isMain,fname=fname} end
  end
  table.insert(files,main)
  return files,{name=fqa.name,type=fqa.type,properties=fqa.initialProperties}
end

local function loadFile(code,file)
  if file and not code then
    if file:match("%.fqa$") then return loadFQA(json.decode(readFile(file)))
    elseif file:match("%.lua$") then return loadLua(file)
    else error("No such file:"..file) end
  elseif type(code)=='table' then  -- fqa table
    return loadFQA(code)
  elseif code then
    local fname = file or createTemp("main",code) or "main"..crc16(code) -- Create temp file for string code easier to debug
    return loadSource(code,fname)
  end
end

local function packageFQA(D)
  local dev = D.dev
  for _,f in ipairs(D.files or {}) do f.fname=nil end
  local fqa = {
    name = dev.name,
    type = dev.type,
    apiVersion="1.2",
    initialInterfaces = dev.interfaces,
    initialProperties = {
      apiVersion="1.2",
      viewLayout=dev.properties.viewLayout,
      uiCallbacks = dev.properties.uiCallbacks,
      quickAppVariables = dev.properties.quickAppVariables,
      typeTemplateInitialized=true,
    },
    files = D.files
  }
  return fqa
end

local function saveFQA(D)
  local fqa = packageFQA(D)
  local stat,res = pcall(function()
      local f = io.open(D.save,"w+")
      assert(f,"Can't open file "..D.save)
      f:write((json.encode(fqa)))
      f:close()
    end)
  if not stat then LOG(EM.LOGERR,"Error save .fqa - %s",res) 
  else LOG(EM.LOGALLW,"Saved %s",D.save) end
end

local function uploadFQA(D)
  local fqa = packageFQA(D)
  local dev = D.dev
  local res,err = FB.api.post("/quickApp/",fqa)
  if not res then LOG(EM.LOGERR,"Error uploading .fqa '%s' - %s",dev.name,err) 
  else LOG(EM.LOGALLW,"Uploaded '%s', deviceId:%s",res.name,res.id) end
end

EM.loadFile, EM.saveFQA, EM.uploadFQA = loadFile, saveFQA, uploadFQA