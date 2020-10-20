if dofile and not hc3_emulator then
  hc3_emulator = {
    name="iCalendar",
    type="com.fibaro.binarySwitch",
    proxy=true,
    poll = 1000,
    --speed=36,
    colorDebug=false,
    quickVars={['Jan']='$CREDS.googleCal'},
    --deploy=true,
    poll=1000,
    UI = {
      {label='name',text=""},
      {button='refresh', text='Refresh calendar',onReleased='refreshCalendar'},
      {label='row1',text=""},
      {label='row2',text=""},
      {label='row3',text=""},
    }
  }
  dofile("fibaroapiHC3.lua")
end

hc3_emulator.FILE("Toolbox/Toolbox_basic.lua","Toolbox")
hc3_emulator.FILE("Toolbox/Toolbox_events.lua","Toolbox_events")
hc3_emulator.FILE("Toolbox/Toolbox_pubsub.lua","Toolbox_pubsub")

----------- Code -----------------------------------------------------------
_version = "0.7"
modules = { "events", "pubsub" }

--[[
Credits:
Based on code from jcichon01 https://forum.fibaro.com/topic/29046-google-calendar-synchronization/
Part of the code after "baran" from http://www.zwave-community.it/
--]]

---  Need url to your google or Apple iCloud calendar file
---  Google
---   https://calendar.google.com/calendar/ical/XXXXXXXX%40gmail.com/private-googleid/yyyyy.ics
---  Apple 
---   "https://p64-calendars.icloud.com/published/2/MTMxsdfsfsdfsdfsfsfdF01LBw1p8vFrjxFq9NvCD"

--CALURL = "https://calendar.google.com/calendar/ical/jangabrielsson%40gmail.com/private-7ecd64859a57120d541xxxxx5c8/basic.ics"

--CALNAME = "Joe"
local CUSTOMEVENT = "name" -- or title

POLLINTERVAL = 30*60 -- check calendars every 30min
calendars = {}
calendarAlarms = {}
dateFormat = "%m/%d/%H:%M"
DEBUG,EMU = true,false
days = 2
local format = string.format 
local function Debug(...) if DEBUG then quickApp:debugf(...) end end
local STARTPATTERN = "#start:([%w_]+)"
local ENDPATTERN = "#end:([%w_]+)"
--local REMOVEDELAY = 6 

function QuickApp:turnOn() 
  self:updateProperty("value",true)
  self:refreshCalendar()
  setTimeout(function() self:turnOff() end, 1000)
end 
function QuickApp:turnOff() self:updateProperty("value",false) end 
function QuickApp:addCalendar(name,url)
  if name and url then
    self:post({type='createCalendar', name=name, url=url})
  end
end
function QuickApp:removeCalendar(name) self:post({type='removeCalendar', name=name}) end
function QuickApp:refreshCalendar(name)
  name = type(name)=='string' and name and {[name]=true} or calendars
  for n,_ in pairs(name) do self:post({type='checkCalendar', name=n}) end
end
function QuickApp:dumpCalendar(name)
  name = name and {[name]=true} or calendars
  for n,_ in pairs(name) do self:post({type='dumpEntries', name=n}) end
end

local function emitEvent(name,value)
  local a,b = api.delete("/customEvents/"..name)
  local val = json.encode(value)
  local a,b = api.post("/customEvents",{name=name,userDescription=val})
  local a,b = api.post("/customEvents/"..name)
  Debug("Emitting custom event:%s - %s",name,value.name)
  if REMOVEDELAY then
    setTimeout(function() api.delete("/customEvents/"..name) end,1000*REMOVEDELAY)
  end
end

function QuickApp:main()

  self:event({type='start'},function(e)  
      local vars = api.get("/devices/"..self.id).properties.quickAppVariables or {}
      for _,v in ipairs(vars) do
        if not ({PROXYIP=true,TPUBSUB=true,pollTime=true})[v.name] then
          self:post({type='createCalendar', name=v.name, url=v.value})
        end
      end
    end)

  self:event({type='createCalendar'},function(e) -- {type='createCalendar', name=<string>, url=<string>}
      e = e.event
      if calendars[e.name] then
        self:debugf("Calendar %s already exists")
      else
        local cal = makeICal(e.name,e.url,e.days or 30,e.tz or 0)
        if cal then
          local entries = {}
          local url = e.url
          calendars[e.name] = {cal=cal,entries=entries,url=url}
          self:tracef("Calendar %s created",e.name)
          self:post({type='checkCalendar', name=e.name, interval=POLLINTERVAL})
        else
          self:tracef("Unable to create calendar %s",e.name)
        end
      end
    end)

  self:event({type='removeCalendar'},function(e)
      e = e.event
      calendars[e.name] = nil
    end)

  self:event({type='checkCalendar'},function(e) -- {type='checkCalendar', name=<string>, interval=<seconds>}
      e = e.event
      local events = calendars[e.name].cal.fetchData()
      if e.interval then self:post(e,e.interval) end
    end)

  self:event({type='newEntries'}, function(e) -- {type='newEntries', name=name, entries=myCal}
      e = e.event
      local newCal,name, entries = {},e.name, e.entries
      for _,e in ipairs(calendarAlarms) do
        if e.name == name then 
          if e.start then self:cancel(e.start) end
          if e.ends then self:cancel(e.ends) end
        else 
          newCal[#newCal+1]=e 
        end
      end
      calendarAlarms = newCal
      calendars[name].entries = entries
      local now = os.time()
      local url = calendars[name].url
      local custom = calendars[name].custom
      for i,entry in ipairs(entries) do
        --Debug("POST:%s , %s, %s",os.date("%c",entry.startDate),os.date("%c",entry.endDate),entry.startDate-now)
        local refS = self:post({type='calAlarm',status='start',name=name,entry=entry},entry.startDate-now)
        local refE = self:post({type='calAlarm',status='end',name=name,entry=entry},entry.endDate-now)
        calendarAlarms[#calendarAlarms+1] = {start=refS,ends=refE,name=name,uid=entry.uid, entry=entry}
      end
      Debug("#New events:%s",#calendarAlarms)
      table.sort(calendarAlarms,function(a,b) return a.entry.startDate < b.entry.startDate end)
      self:post({type='updateView'})
    end)

  local function fixName(str)
    str = str:match("^%s*(.-)%s*$")
    str = str:gsub("[^%w]","_")
    return str:gsub("_+","_")
  end

--"#start:Lunch\\n#end:Lunch ends"
  self:event({type='calAlarm'}, function(e) -- {type='calAlarm',status='start',name=name,entry=entry}
      e = e.event
      -- customevent = {name = "iCal_"..<name>, userDescription=json.encode(entry)}
      local descr = e.entry.descr or ""

      local pub = self.util.copy(e.entry)
      pub.calname = e.name
      pub.status = e.status
      pub.type='iCAL'
      self:publish(pub) 
      
      if e.status=='start' then  -- Always emit "iCalendar_"..<name> events
        local ename
        if CUSTOMEVENT == 'name' then
          ename = "iCalendar_"..e.name
        else
          ename = e.entry.name
        end
        Debug("ename:%s",ename)
        ename = fixName(ename) 
        if EMU then Debug("Emitting customEvent:%s",ename)
        else 
          emitEvent(ename,e.entry) 
        end

        local estart = descr:match(STARTPATTERN) -- If start pattern, emit custom event
        if estart then
          estart = fixName(estart)
          if estart ~= "" then
            if EMU then Debug("Emitting start event:%s",estart)
            else
              emitEvent(estart,e.entry)
            end
          end
        end

      elseif e.status=='end' then
        local eend = descr:match(ENDPATTERN)   -- If end pattern, emit custom event
        if eend then
          eend = fixName(eend)
          if eend ~= "" then
            if EMU then Debug("Emitting end event:%s",eend)
            else
              emitEvent(eend,e.entry)
            end
          end
        end
      end
    end)

  self:event({type='updateView'}, function(e)  -- {type='updateView'}
      e = e.event
      local ROWS = 3
      local i = 1
      while calendarAlarms[i] and i < ROWS do 
        local e = calendarAlarms[i].entry
        Debug("Event:%s %s",e.name,os.date("%c",e.startDate))
        quickApp:updateView("row"..i,"text",format("%s %s",os.date("%c",e.startDate),e.name))
        i=i+1
      end
      while i <= ROWS do quickApp:updateView("row"..i,"text","  ") i=i+1 end
      if calendarAlarms[i] then
        local e = calendarAlarms[i].entry
        local txt = format("Next:%s,%s",e.name,os.date("%d/%m %H:%M",e.startDate))
        quickApp:updateProperty("log",txt )
        Debug("UPDATE "..txt)
      else quickApp:updateProperty("log","") end
    end)

  self:event({type='dumpEntries'}, function(e)  -- {type='dumpCalendar, name=name'}
      e = e.event
      for i,entry in ipairs(calendarAlarms) do
        if e.name==entry.name then
          self:tracef("Entry%s:'%s' start:%s, end:%s, day:%s",
            i,e.name,os.date("%c",entry.startDate),os.date("%c",entry.endDate),entry.wholeDay)
        end
      end
    end)
end -- main

function makeICal(name,url,days,tz)
  local self = {}
  local HC = net.HTTPClient()
  local calUrl = url
  name = name or "Calendar"

--- Time zone correction: 1 = gmt+1 2=gmt+2 ecc ecc
  local nowt = os.time()
  local timeZone = os.difftime(nowt, os.time(os.date("!*t", nowt))) / 3600                 
  timeZone = tz or 0 -- Typically calendar add entries in timezone.... mine does...

-- other variables
  local myCal        = {}
  local maxDays       = days or 30
  local daysInMonth = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

  local function AppendToCal(e)
    local now = os.time()
    -- quickApp:tracef("%s D:%s NOW:%s",e.descr,os.date("%c", e.endDate),os.date("%c", now))
    if e.endDate < now or e.startDate > now+2*24*60*60 then return end 
    --quickApp:debug("E:",os.date("%c",e.endDate)," N:",os.date("%c"))
    local wd = os.date("%X",e.startDate)=="00:00:00" and os.date("%X",e.endDate)=="00:00:00"
    myCal[#myCal+1] = { 
      name       = e.name,
      startDate  = e.startDate,
      endDate    = e.endDate,
      location   = e.location or "",
      uid        = e.uid or "",
      descr      = e.descr or "",
      wholeDay   = wd
    }
  end

  local function getTimezone() local now = os.time() return os.difftime(now, os.time(os.date("!*t", now))) end
  utc = getTimezone() / 3600

-- parse dates
  local function UTCTimePhrase(data)
--- v 1.2 whole-day events are defined by date only
    local year,month,day,rest=data:match("(%d%d%d%d)(%d%d)(%d%d)(.*)")
    local hour,min,sec,Z=rest:match("T(%d%d)(%d%d)(%d%d)(%w*)")
    if hour == nil then hour,min,sec=0,0,0 end
    local epoc = os.time{year=tonumber(year),month=tonumber(month),day=tonumber(day),
      hour=tonumber(hour),min=tonumber(min),sec=tonumber(sec)}+(Z=='Z' and utc*60*60 or 0)
    local t = os.date("*t")
    if t.isdst then epoc = epoc+60*60 end
    return epoc
  end

  local function AppendRecuringEntry(recurance, e)
    local i = 1;
    local l_rule;
    local l_finish;
    local l_multiplier;
    -- is there delimiter like "until", "count"?
    l_rule = "NONE";
    l_finish = "No";

    for l = 1, #recurance do
      -- split the lines               
      recurance[l] = string.split(recurance[l], "=");

      if recurance[l][1] == "COUNT" then 
        l_rule    = "COUNT";
        l_ruleEnd = recurance[l][2];
      elseif  recurance[l][1] == "UNTIL" then 
        l_rule    = "UNTIL";
        l_ruleEnd = UTCTimePhrase(recurance[l][2]);
      end
    end

    if l_ruleEnd == nil then l_ruleEnd = "not delimited" end
    -- recognize the dates for recurring events
    local maxTime = os.time()+maxDays*24*60*60
    while e.startDate < maxTime and  l_finish == "No" do    -- should I stop searching?
      if     recurance[1][2] == "WEEKLY"  then l_multiplier = 7
      elseif recurance[1][2] == "DAILY"   then l_multiplier = 1
      elseif recurance[1][2] == "MONTHLY" then l_multiplier = daysInMonth[os.date("!*t",e.startDate).month]
      else   l_multiplier = 9999 
      end -- no handling

      if l_multiplier == 9999 then
        l_finish = "Yes";
      else  
        AppendToCal(e);
        e.startDate = e.startDate + l_multiplier * (60 * 60 * 24 )
        e.endDate   = e.endDate + l_multiplier * (60 * 60 * 24 )

        -- did I reach the end?
        if l_rule == "COUNT" then
          if tonumber(l_ruleEnd) == i then 
            l_finish = "Yes" 
          end
        elseif l_rule == "UNTIL" then
          if  e.startDate >= l_ruleEnd then 
            l_finish = "Yes" 
          end
        end
        i = i + 1;
      end
    end       
  end

  local function OutputData()
--sort to have it in chronological order
    table.sort(myCal,function(a,b) return a.startDate < b.startDate end)
    --for i = 1, #myCal do
    --  myCal[i].startDate = myCal[i].startDate + timeZone*3600; 
    --  myCal[i].endDate = myCal[i].endDate + timeZone*3600;        
    --end
    --quickApp:tracef(json.encode(myCal))
    --quickApp:tracef("MyCal #:%s",#myCal)
    quickApp:post({type='newEntries', name=name, entries=myCal})
  end

-- parse the entries
  local function CalRead(data)
    local e = {}
    local recurring,rRule,currentBlock

    data = string.gsub(data, "\r", "") -- Remove Return
    lines = string.split(data, "\n")        -- Split Cal string

    for i,line in ipairs(lines) do 

      local v1,v2 = line:match("(.-):(.*)")
      local values
      values= v1 and {v1,v2} or {line}

      if values[1] == "BEGIN" and values[2] == "VEVENT" then
        currentBlock = "VEVENT"  -- we're at the beginning of event definition
        rRule = "No"            -- no recurrance by default
      end

      if currentBlock == "VEVENT" then
        --- get the Cal events START,STOP and 
        --- v 1.1 for recurring events - time zone included in the timestamp
        ---       syntax as follows: DTSTART;TZID=America/New_York:20120503T180000
        --- v 1.2 in case DTSTART/DTEND contains date only - 
        ---       it is whole/multiple day event. e.g. DTSTART;VALUE=DATE:20170312

        if values[1] == "DTSTART" 
        or string.sub(values[1], 1, 12)  == "DTSTART;TZID" 
        or string.sub(values[1], 1, 13)  == "DTSTART;VALUE"
        then
          e.startDate  = UTCTimePhrase(values[2])
        end

        if values[1] == "DTEND" 
        or string.sub(values[1], 1, 10)  == "DTEND;TZID"
        or string.sub(values[1], 1, 11)  == "DTEND;VALUE"
        then
          e.endDate = UTCTimePhrase(values[2])
        end

        if values[1] == "X-WR-CALNAME" then e.name = values[2] end
        if values[1] == "SUMMARY" then e.name = values[2] end
        if values[1] == "DESCRIPTION" then e.descr = values[2] end
        if values[1] == "LOCATION" then e.loc = values[2] end
        if values[1] == "UID" then e.uid = values[2] end

        if values[1] == "RRULE" then
          recurring = string.split(values[2], ";");
          rRule = "Yes";
        end

        if values[1] == "END" 
        then
          currentBlock = "None"

--   filter to the events of the current month (and year)
          if rRule == "No" 
          then
            AppendToCal(e)
          else      
            AppendRecuringEntry(recurring, e)        
          end -- recurance
        end
      end
    end
    return OutputData()
  end

  local function GetICalData(url)
    HC:request(url,{ 
        options = {method = "GET", checkCertificate = false, timeout=20000},
        success = function(response) 
          if response.status==301 then
            GetICalData(response.headers.location)
          elseif response.status==200 then
            CalRead(response.data) 
          else
            quickApp:tracef("HTTP Error: ".."Bad request")
          end
        end,
        error =  function(err) quickApp:tracef("HTTP Error:"..json.encode(err)) end,
      })
  end

  TESTING=true
  function self.fetchData()
    myCal = {}
    if TESTING then
      local t=os.date("*t")
      --t.day=19 t.hour=23 t.min=0 t.sec=0
      t.sec=t.sec+30
      local tt = os.time(t)
      for i=1,2 do
        myCal[#myCal+1] = {
          startDate = tt+(i-1)*60,
          endDate = tt+(i+1-1)*60,
          name = "Test"..i,
          uid = tostring(i).."uid",
          descr="A"..i,
          wholeDay=false,
        }
      end
      quickApp:tracef("MyCal #:%s",#myCal)
      table.sort(myCal,function(a,b) return a.startDate < b.startDate end)
      quickApp:post({type='newEntries', name=name, entries=myCal})
    else
      return GetICalData(calUrl)
    end
  end

  return self
end

function QuickApp:onInit()  -- onInit() sets up stuff...
  -- Fibaro quickvariables editor don't allow long strings like an URL... :-(
  if CALURL then self:setVariable(CALNAME,"Joe",CALURL) end
  self:turnOff()
  self:post({type='start'},1)                     
end

