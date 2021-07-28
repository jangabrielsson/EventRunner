local function readFile(file) 
  local f = io.open(file); assert(f,"No such file:"..file) local c = f:read("*all"); f:close() return c
end

local TEMP = PARAMS.temp or os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "temp/" -- Try
local firstTemp = true
local function createTemp(name,content,suffix) -- Storing code fragments on disk will help debugging. TBD
  if firstTemp and verbose then LOG("Using %s for temporary files",TEMP) firstTemp=false end
  local fname = TEMP..name.."_"..suffix..".lua"  
  local f,res = io.open(fname,"w+")
  if not f then LOG("Warning - couldn't create temp files in %s - %s",TEMP,res) return 
  elseif verbose then LOG("Created temp file %s",fname) end
  f:write(content) 
  f:close()
  return fname
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
  table.insert(files,{name="main",content=code,isMain=true,fname=fileName})
  local info = code:match("%-%-%[%[QAemu(.-)%-%-%]%]")
  if info==nil then
    local il = {}
    code:gsub("%-%-%%%%(.-)[\n\r]+",function(l) il[#il+1]=l end)
    info=table.concat(il,",")
  end
  if info then 
    local code,res = load("return {"..info.."}")
    if not code then error(res) end
    info,res = code()
    if res then error(res) end
  end
  return files,(info or {})
end

local function loadLua(fileName) return loadSource(readFile(fileName),fileName) end

local function loadFQA(fqa,suffix)  -- Load FQA
  local files,main = {}
  for _,f in ipairs(fqa.files) do
    local fname = createTemp(f.name,f.content,suffix) or f.name -- Create temp files for fqa files, easier to debug
    if f.isMain then f.fname=fname main=f
    else files[#files+1] = {name=f.name,content=f.content,isMain=f.isMain,fname=fname} end
  end
  table.insert(files,main)
  return files,{name=fqa.name,type=fqa.type,properties=fqa.initialProperties}
end

function loadFile(code,file)
  local suffix = tostring({}):match("%s(.*)")
  if file and not code then
    if file:match("%.fqa$") then return loadFQA(json.decode(readFile(file)),suffix)
    elseif file:match("%.lua$") then return loadLua(file)
    else error("No such file:"..file) end
  elseif type(code)=='table' then  -- fqa table
    return loadFQA(code,suffix)
  elseif code then
    local fname = file or createTemp("main",code,suffix) or "main"..suffix -- Create temp file for string code easier to debug
    return loadSource(code,fname)
  end
end