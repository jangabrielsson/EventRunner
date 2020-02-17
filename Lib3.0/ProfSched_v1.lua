--[[
%%LibDevice
properties: {
"name": "Profile scheduler",
"type":"com.fibaro.binarySensor",
"variables":{
   },
"UI":[
  [{"button":"time","text":"07:00"},{"button":"profile","text":"Home"}],
  [{"button":"hour1","text":"0"},{"button":"hour2","text":"7"},{"button":"min1","text":"0"},{"button":"min2","text":"0"}],
  [{"button":"save","text":"Save"},{"button":"enabled","text":"Enabled"}]  
  ]
}
--]]

local data = {}  -- Should be stored/retrieved from a quickVar
local curr = 1
local mode = {
    function(data) data.type='time' end, 
    function(data) data.type='sunrise'; data.modifier='+' end, 
    function(data) data.type='sunrise'; data.modifier='-' end, 
    function(data) data.type='sunset'; data.modifier='+' end, 
    function(data) data.type='sunset'; data.modifier='-' end, 
}

local function setUp()
  for _,p in ipairs((api.get("/profiles")).profiles) do
    data[#data+1] = {name=p.name,id=p.id,enabled=false,time="07:00",type='time', modifier="", mode=1}
  end
end
 
local function update(self)
    local p = data[curr]
    --self:debug(json.encode(p))
    self:updateView("profile","text",p.name)
    local h1,h2,m1,m2 = p.time:match("(%d)(%d):(%d)(%d)")
    self:updateView("hour1","text",h1)
    self:updateView("hour2","text",h2)
    self:updateView("min1","text",m1)  
    self:updateView("min2","text",m2)          
    if p.type~='time' then
      self:updateView("time","text",p.type..p.modifier..p.time)
    else
      self:updateView("time","text",p.time)
    end
    self:updateView("enabled","text",p.enabled and "Scheduled" or "Unscheduled")
end

function add(hour,min,self)
    local p = data[curr]
    local h,m = p.time:match("(%d%d):(%d%d)")
    h,m=hour+h,min+m
    h,m = h>23 and 0 or h,m> 59 and 0 or m
    p.time=string.format("%02d:%02d",h,m)
    update(self)
end

local function toTime(t) local h,m = t:match("(%d+):(%d+)") return 60*h+m end
local function fromTime(t) local h,m = t:match("(%d+):(%d+)") return 60*h+m end

function sunCalc(sun,mod,time)
    local st = toTime(fibaro.call(1,sun.."Hour"))+((mod=='+' and 1 or -1)*toTime(time))
    return string.format("%02d:%02d",math.floor(st/60),st % 60)
end

do
  local oldSetTimeout = setTimeout
  function setTimeout(fun,ms)
     return oldSetTimeout(function()
     stat,res = pcall(fun)
     if not stat then print("Error in setTimeout:"..res) end
     end,ms)
  end
end

function QuickApp:onInit()
    self:debug("onInit")
    setTimeout(function() bar() self:debug("OK") end,1000)  -- will crash because 'bar' is not defined
end

local function schedule(self)
    local nt = nt or os.time()
    local function loop()
      local now = os.date("%H:%M")
      for _,p in pairs(data) do
          local t = p.type=='time' and p.time or sunCalc(p.type,p.modifier,p.time)
          if now == t and p.enabled then 
               fibaro.profile(p.id, "activateProfile")
               self:debug("Activated profile "..p.name)
          elseif p.enabled then
               self:debug("Will activate profile "..p.name.." at "..t)  
          end
      end
      nt=nt+60
      setTimeout(loop,1000*(nt-os.time()))
    end
    loop()
end

function QuickApp:timeClicked() 
   local p = data[curr]
   p.mode = p.mode+1; if p.mode > #mode then p.mode=1 end
   mode[p.mode](p)
   update(self)
end
function QuickApp:profileClicked()
  curr = curr+1
  if curr > #data then curr=1 end
  update(self)
end
function QuickApp:hour1Clicked() add(10,0,self) end
function QuickApp:hour2Clicked() add(1,0,self) end
function QuickApp:min1Clicked() add(0,10,self) end
function QuickApp:min2Clicked() add(0,1,self) end
function QuickApp:saveClicked() self:debug("Save") end
function QuickApp:enabledClicked() local p = data[curr]; p.enabled=not p.enabled; update(self) end

function QuickApp:onInit()
    self:debug("onInit")
    setUp()
    update(self)
    schedule(self)
end