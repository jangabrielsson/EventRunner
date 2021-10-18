local copas,timer,timerwheel2,lock
local binaryheap

local socket = require("socket")
local url = require("socket.url")
local ltn12 = require("ltn12")
local mime = require("mime")
local string = require("string")
local headers = require("socket.headers")

------- Timer wheel --------------
do
  local default_now  -- return time in seconds
  if _G['ngx'] then -- no problem, main thread
    default_now = _G['ngx'].now
  else
    local ok, socket2 = pcall(require, "socket")
    if ok then
      default_now = socket2.gettime
    else
      default_now = nil -- we don't have a default
    end
  end

  local new_tab = function(narr, nrec) return {} end

  local xpcall = xpcall --pcall(function() return require("coxpcall").xpcall end) or xpcall
  local default_err_handler = function(err)
    io.stderr:write(debug.traceback("TimerWheel callback failed with: " .. tostring(err)))
  end

  local math_floor = math.floor
  local math_huge = math.huge
  local EMPTY = {}

  local _M = {}

  function _M.new(opts)
    assert(opts ~= _M, "new should not be called with colon ':' notation")

    opts = opts or EMPTY
    assert(type(opts) == "table", "expected options to be a table")

    local precision = opts.precision or 0.050  -- in seconds, 50ms by default
    local ringsize  = opts.ringsize or 72000   -- #slots per ring, default 1 hour = 60 * 60 / 0.050
    local now       = opts.now or default_now  -- function to get time in seconds
    local err_handler = opts.err_handler or default_err_handler
    opts = nil   -- luacheck: ignore

    assert(type(precision) == "number" and precision > 0,
      "expected 'precision' to be number > 0")
    assert(type(ringsize) == "number" and ringsize > 0 and math_floor(ringsize) == ringsize,
      "expected 'ringsize' to be an integer number > 0")
    assert(type(now) == "function",
      "expected 'now' to be a function, got: " .. type(now))
    assert(type(err_handler) == "function",
      "expected 'err_handler' to be a function, got: " .. type(err_handler))

    local start     = now()
    local position  = 1  -- position next up in first ring of timer wheel
    local id_count  = 0  -- counter to generate unique ids (all negative)
    local id_list   = {} -- reverse lookup table to find timers by id
    local rings     = {} -- list of rings, index 1 is the current ring
    local rings_n   = 0  -- the number of the last ring in the rings list
    local count     = 0  -- how many timers do we have
    local wheel     = {} -- the returned wheel object
    -- because we assume hefty setting and cancelling, we're reusing tables
    -- to prevent excessive GC.
    local tables    = {} -- list of tables to be reused
    local tables_n  = 0  -- number of tables in the list
    --- Checks and executes timers.
    -- Call this function (at least) every `precision` seconds.
    -- @return `true`
    function wheel:step()
      local new_position = math_floor((now() - start) / precision) + 1
      local ring = rings[1] or EMPTY

      while position < new_position do
        -- get the expired slot, and remove it from the ring
        local slot = ring[position]
        ring[position] = nil
        -- forward pointers
        position = position + 1
        if position > ringsize then
          -- current ring is done, remove it and forward pointers
          for i = 1, rings_n do
            -- manual loop, since table.remove won't deal with holes
            rings[i] = rings[i + 1]
          end
          rings_n = rings_n - 1

          ring = rings[1] or EMPTY
          start = start + ringsize * precision
          position = 1
          new_position = new_position - ringsize
        end
        -- only deal with slot after forwarding pointers, to make sure that
        -- any cb inserting another timer, does not end up in the slot being
        -- handled
        if slot then
          -- deal with the slot
          local ids = slot.ids
          local args = slot.arg
          for i = 1, slot.n do
            local id  = slot[i];  slot[i]  = nil; slot[id] = nil
            local cb  = ids[id];  ids[id]  = nil
            local arg = args[id]; args[id] = nil
            id_list[id] = nil
            count = count - 1
            xpcall(cb, err_handler, arg)
          end

          slot.n = 0
          -- delete the slot
          tables_n = tables_n + 1
          tables[tables_n] = slot
        end

      end
      return true
    end

    --- Gets the number of timers.
    -- @return number of timers
    function wheel:count()
      return count
    end

    function wheel:set(expire_in, cb, arg)
      local time_expire = now() + expire_in
      local pos = math_floor((time_expire - start) / precision) + 1
      if pos < position then
        -- we cannot set it in the past
        pos = position
      end
      local ring_idx = math_floor((pos - 1) / ringsize) + 1
      local slot_idx = pos - (ring_idx - 1) * ringsize

      -- fetch actual ring table
      local ring = rings[ring_idx]
      if not ring then
        ring = new_tab(ringsize, 0)
        rings[ring_idx] = ring
        if ring_idx > rings_n then
          rings_n = ring_idx
        end
      end

      -- fetch actual slot
      local slot = ring[slot_idx]
      if not slot then
        if tables_n == 0 then
          slot = { n = 0, ids = {}, arg = {} }
        else
          slot = tables[tables_n]
          tables_n = tables_n - 1
        end
        ring[slot_idx] = slot
      end

      -- get new id
      local id = id_count - 1 -- use negative idx to not interfere with array part
      id_count = id

      -- store timer
      -- if we do not do this check, it will go unnoticed and lead to very
      -- hard to find bugs (`count` will go out of sync)
      slot.ids[id] = cb or error("the callback parameter is required", 2)
      slot.arg[id] = arg
      local idx = slot.n + 1
      slot.n = idx
      slot[idx] = id
      slot[id] = idx
      id_list[id] = slot
      count = count + 1

      return id
    end

    function wheel:cancel(id)
      local slot = id_list[id]
      if slot then
        local idx = slot[id]
        slot[id] = nil
        slot.ids[id] = nil
        slot.arg[id] = nil
        local n = slot.n
        slot[idx] = slot[n]
        slot[n] = nil
        slot.n = n - 1
        id_list[id] = nil
        count = count - 1
        return true
      end
      return false
    end

    function wheel:peek(max_ahead)
      if count == 0 then
        return nil
      end
      local time_now = now()

      -- convert max_ahead from seconds to positions
      if max_ahead then
        max_ahead = math_floor((time_now + max_ahead - start) / precision)
      else
        max_ahead = math_huge
      end

      local position_idx = position
      local ring_idx = 1
      local ring = rings[ring_idx] or EMPTY -- TODO: if EMPTY then we can skip it?
      local ahead_count = 0
      while ahead_count < max_ahead do

        local slot = ring[position_idx]
        if slot then
          if slot[1] then
            -- we have a timer
            return ((ring_idx - 1) * ringsize + position_idx) * precision +
            start - time_now
          end
        end

        -- there is nothing in this position
        position_idx = position_idx + 1
        ahead_count = ahead_count + 1
        if position_idx > ringsize then
          position_idx = 1
          ring_idx = ring_idx + 1
          ring = rings[ring_idx] or EMPTY
        end
      end
      return nil
    end
    return wheel
  end

  timerwheel2 = _M
end

--------- Binary heap ----------
do

  local M = {}
  local floor = math.floor

  M.binaryHeap = function(swap, erase, lt)

    local heap = {
      values = {},  -- list containing values
      erase = erase,
      swap = swap,
      lt = lt,
    }

    function heap:bubbleUp(pos)
      local values = self.values
      while pos>1 do
        local parent = floor(pos/2)
        if not lt(values[pos], values[parent]) then
          break
        end
        swap(self, parent, pos)
        pos = parent
      end
    end

    function heap:sinkDown(pos)
      local values = self.values
      local last = #values
      while true do
        local min = pos
        local child = 2 * pos

        for c = child, child + 1 do
          if c <= last and lt(values[c], values[min]) then min = c end
        end

        if min == pos then break end

        swap(self, pos, min)
        pos = min
      end
    end

    return heap
  end

  local update
--- Updates the value of an element in the heap.
-- @function heap:update
-- @param pos the position which value to update
-- @param newValue the new value to use for this payload
  update = function(self, pos, newValue)
    assert(newValue ~= nil, "cannot add 'nil' as value")
    assert(pos >= 1 and pos <= #self.values, "illegal position")
    self.values[pos] = newValue
    if pos > 1 then self:bubbleUp(pos) end
    if pos < #self.values then self:sinkDown(pos) end
  end

  local remove
--- Removes an element from the heap.
-- @function heap:remove
-- @param pos the position to remove
-- @return value, or nil if a bad `pos` value was provided
  remove = function(self, pos)
    local last = #self.values
    if pos < 1 then
      return  -- bad pos

    elseif pos < last then
      local v = self.values[pos]
      self:swap(pos, last)
      self:erase(last)
      self:bubbleUp(pos)
      self:sinkDown(pos)
      return v

    elseif pos == last then
      local v = self.values[pos]
      self:erase(last)
      return v

    else
      return  -- bad pos: pos > last
    end
  end

  local insert
--- Inserts an element in the heap.
-- @function heap:insert
-- @param value the value used for sorting this element
-- @return nothing, or throws an error on bad input
  insert = function(self, value)
    assert(value ~= nil, "cannot add 'nil' as value")
    local pos = #self.values + 1
    self.values[pos] = value
    self:bubbleUp(pos)
  end

  local pop
--- Removes the top of the heap and returns it.
-- @function heap:pop
-- @return value at the top, or `nil` if there is none
  pop = function(self)
    if self.values[1] ~= nil then
      return remove(self, 1)
    end
  end

  local peek
--- Returns the element at the top of the heap, without removing it.
-- @function heap:peek
-- @return value at the top, or `nil` if there is none
  peek = function(self)
    return self.values[1]
  end

  local size
--- Returns the number of elements in the heap.
-- @function heap:size
-- @return number of elements
  size = function(self)
    return #self.values
  end

  local function swap(heap, a, b)
    heap.values[a], heap.values[b] = heap.values[b], heap.values[a]
  end

  local function erase(heap, pos)
    heap.values[pos] = nil
  end

  do end -- luacheck: ignore
-- the above is to trick ldoc (otherwise `update` below disappears)

  local updateU
  function updateU(self, payload, newValue)
    return update(self, self.reverse[payload], newValue)
  end

  local insertU
  function insertU(self, value, payload)
    assert(self.reverse[payload] == nil, "duplicate payload")
    local pos = #self.values + 1
    self.reverse[payload] = pos
    self.payloads[pos] = payload
    return insert(self, value)
  end

  local removeU
  function removeU(self, payload)
    local pos = self.reverse[payload]
    if pos ~= nil then
      return remove(self, pos), payload
    end
  end

  local popU
  function popU(self)
    if self.values[1] then
      local payload = self.payloads[1]
      local value = remove(self, 1)
      return payload, value
    end
  end

  local peekU
  peekU = function(self)
    return self.payloads[1], self.values[1]
  end

  local peekValueU
  peekValueU = function(self)
    return self.values[1]
  end

  local valueByPayload
  valueByPayload = function(self, payload)
    return self.values[self.reverse[payload]]
  end

  local sizeU
  sizeU = function(self)
    return #self.values
  end

  local function swapU(heap, a, b)
    local pla, plb = heap.payloads[a], heap.payloads[b]
    heap.reverse[pla], heap.reverse[plb] = b, a
    heap.payloads[a], heap.payloads[b] = plb, pla
    swap(heap, a, b)
  end

  local function eraseU(heap, pos)
    local payload = heap.payloads[pos]
    heap.reverse[payload] = nil
    heap.payloads[pos] = nil
    erase(heap, pos)
  end

--================================================================
-- unique heap creation
--================================================================

  local function uniqueHeap(lt)
    local h = M.binaryHeap(swapU, eraseU, lt)
    h.payloads = {}  -- list contains payloads
    h.reverse = {}  -- reverse of the payloads list
    h.peek = peekU
    h.peekValue = peekValueU
    h.valueByPayload = valueByPayload
    h.pop = popU
    h.size = sizeU
    h.remove = removeU
    h.insert = insertU
    h.update = updateU
    return h
  end

  M.minUnique = function(lt)
    if not lt then
      lt = function(a,b) return (a < b) end
    end
    return uniqueHeap(lt)
  end

  binaryheap = M
end

--------- Copas ------------------
do
  local gettime = socket.gettime
  local ssl -- only loaded upon demand

  local WATCH_DOG_TIMEOUT = 120
  local UDP_DATAGRAM_MAX = 8192  -- TODO: dynamically get this value from LuaSocket
  local TIMEOUT_PRECISION = 0.1  -- 100ms
  local fnil = function() end

  local pcall = pcall

-- Redefines LuaSocket functions with coroutine safe versions
-- (this allows the use of socket.http from within copas)
  local function statusHandler(status, ...)
    if status then return ... end
    local err = (...)
    if type(err) == "table" then
      return nil, err[1]
    else
      error(err)
    end
  end

  function socket.protect(func)
    return function (...)
      return statusHandler(pcall(func, ...))
    end
  end

  function socket.newtry(finalizer)
    return function (...)
      local status = (...)
      if not status then
        pcall(finalizer, select(2, ...))
        error({ (select(2, ...)) }, 0)
      end
      return ...
    end
  end

  copas = {}

-- Meta information is public even if beginning with an "_"
  copas._COPYRIGHT   = "Copyright (C) 2005-2017 Kepler Project"
  copas._DESCRIPTION = "Coroutine Oriented Portable Asynchronous Services"
  copas._VERSION     = "Copas 2.0.2"

-- Close the socket associated with the current connection after the handler finishes
  copas.autoclose = true

-- indicator for the loop running
  copas.running = false
-------------------------------------------------------------------------------
-- Simple set implementation
-- adds a FIFO queue for each socket in the set
-------------------------------------------------------------------------------

  local function newsocketset()
    local set = {}

    do  -- set implementation
      local reverse = {}

      -- Adds a socket to the set, does nothing if it exists
      function set:insert(skt)
        if not reverse[skt] then
          self[#self + 1] = skt
          reverse[skt] = #self
        end
      end

      -- Removes socket from the set, does nothing if not found
      function set:remove(skt)
        local index = reverse[skt]
        if index then
          reverse[skt] = nil
          local top = self[#self]
          self[#self] = nil
          if top ~= skt then
            reverse[top] = index
            self[index] = top
          end
        end
      end
    end

    do  -- queues implementation
      local fifo_queues = setmetatable({},{
          __mode = "k",                 -- auto collect queue if socket is gone
          __index = function(self, skt) -- auto create fifo queue if not found
            local newfifo = {}
            self[skt] = newfifo
            return newfifo
          end,
        })

      -- pushes an item in the fifo queue for the socket.
      function set:push(skt, itm)
        local queue = fifo_queues[skt]
        queue[#queue + 1] = itm
      end

      -- pops an item from the fifo queue for the socket
      function set:pop(skt)
        local queue = fifo_queues[skt]
        return table.remove(queue, 1)
      end
    end
    return set
  end

-- Threads immediately resumable
  local _resumable = {} do
    local resumelist = {}

    function _resumable:push(co)
      resumelist[#resumelist + 1] = co
    end

    function _resumable:clear_resumelist()
      local lst = resumelist
      resumelist = {}
      return lst
    end
    function _resumable:done()
      return resumelist[1] == nil
    end
  end

-- Similar to the socket set above, but tailored for the use of
-- sleeping threads
  local _sleeping = {} do

    local heap = binaryheap.minUnique()
    local lethargy = setmetatable({}, { __mode = "k" }) -- list of coroutines sleeping without a wakeup time
    -- Required base implementation
    -----------------------------------------
    _sleeping.insert = fnil
    _sleeping.remove = fnil

    -- push a new timer on the heap
    function _sleeping:push(sleeptime, co)
      if sleeptime < 0 then
        lethargy[co] = true
      elseif sleeptime == 0 then
        _resumable:push(co)
      else
        heap:insert(gettime() + sleeptime, co)
      end
    end

    -- find the thread that should wake up to the time, if any
    function _sleeping:pop(time)
      if time < (heap:peekValue() or math.huge) then
        return
      end
      return heap:pop()
    end

    -- additional methods for time management
    -----------------------------------------
    function _sleeping:getnext()  -- returns delay until next sleep expires, or nil if there is none
      local t = heap:peekValue()
      if t then
        -- never report less than 0, because select() might block
        return math.max(t - gettime(), 0)
      end
    end

    function _sleeping:wakeup(co)
      if lethargy[co] then
        lethargy[co] = nil
        _resumable:push(co)
        return
      end
      if heap:remove(co) then
        _resumable:push(co)
      end
    end

    -- @param tos number of timeouts running
    function _sleeping:done(tos)
      -- return true if we have nothing more to do
      -- the timeout task doesn't qualify as work (fallbacks only),
      -- the lethargy also doesn't qualify as work ('dead' tasks),
      -- but the combination of a timeout + a lethargy can be work
      return heap:size() == 1       -- 1 means only the timeout-timer task is running
      and not (tos > 0 and next(lethargy))
    end

  end   -- _sleeping

-------------------------------------------------------------------------------
-- Tracking coroutines and sockets
-------------------------------------------------------------------------------

  local _servers = newsocketset() -- servers being handled
  local _threads = setmetatable({}, {__mode = "k"})  -- registered threads added with addthread()
  local _canceled = setmetatable({}, {__mode = "k"}) -- threads that are canceled and pending removal

-- for each socket we log the last read and last write times to enable the
-- watchdog to follow up if it takes too long.
-- tables contain the time, indexed by the socket
  local _reading_log = {}
  local _writing_log = {}

  local _reading = newsocketset() -- sockets currently being read
  local _writing = newsocketset() -- sockets currently being written
  local _isSocketTimeout = { -- set of errors indicating a socket-timeout
    ["timeout"] = true,      -- default LuaSocket timeout
    ["wantread"] = true,     -- LuaSec specific timeout
    ["wantwrite"] = true,    -- LuaSec specific timeout
  }

-------------------------------------------------------------------------------
-- Coroutine based socket timeouts.
-------------------------------------------------------------------------------
  local usertimeouts = setmetatable({}, {
      __mode = "k",
      __index = function(self, skt)
        -- if there is no timeout found, we insert one automatically,
        -- a 10 year timeout as substitute for the default "blocking" should do
        self[skt] = 10*365*24*60*60
        return self[skt]
      end,
    })

  local useSocketTimeoutErrors = setmetatable({},{ __mode = "k" })

-- sto = socket-time-out
  local sto_timeout, sto_timed_out, sto_change_queue, sto_error do

    local socket_register = setmetatable({}, { __mode = "k" })    -- socket by coroutine
    local operation_register = setmetatable({}, { __mode = "k" }) -- operation "read"/"write" by coroutine
    local timeout_flags = setmetatable({}, { __mode = "k" })      -- true if timedout, by coroutine


    local function socket_callback(co)
      local skt = socket_register[co]
      local queue = operation_register[co]

      -- flag the timeout and resume the coroutine
      timeout_flags[co] = true
      _resumable:push(co)

      -- clear the socket from the current queue
      if queue == "read" then
        _reading:remove(skt)
      elseif queue == "write" then
        _writing:remove(skt)
      else
        error("bad queue name; expected 'read'/'write', got: "..tostring(queue))
      end
    end

    -- Sets a socket timeout.
    -- Calling it as `sto_timeout()` will cancel the timeout.
    -- @param queue (string) the queue the socket is currently in, must be either "read" or "write"
    -- @param skt (socket) the socket on which to operate
    -- @return true
    function sto_timeout(skt, queue)
      local co = coroutine.running()
      socket_register[co] = skt
      operation_register[co] = queue
      timeout_flags[co] = nil
      if skt then
        copas.timeout(usertimeouts[skt], socket_callback)
      else
        copas.timeout(0)
      end
      return true
    end

    -- Changes the timeout to a different queue (read/write).
    -- Only usefull with ssl-handshakes and "wantread", "wantwrite" errors, when
    -- the queue has to be changed, so the timeout handler knows where to find the socket.
    -- @param queue (string) the new queue the socket is in, must be either "read" or "write"
    -- @return true
    function sto_change_queue(queue)
      operation_register[coroutine.running()] = queue
      return true
    end

    -- Responds with `true` if the operation timed-out.
    function sto_timed_out()
      return timeout_flags[coroutine.running()]
    end

    -- Returns the poroper timeout error
    function sto_error(err)
      return useSocketTimeoutErrors[coroutine.running()] and err or "timeout"
    end
  end
-------------------------------------------------------------------------------
-- Coroutine based socket I/O functions.
-------------------------------------------------------------------------------

  local function isTCP(socket)
    return string.sub(tostring(socket),1,3) ~= "udp"
  end

  function copas.settimeout(skt, timeout)
    if timeout ~= nil and type(timeout) ~= "number" then
      return nil, "timeout must be a 'nil' or a number"
    end

    if timeout and timeout < 0 then
      timeout = nil    -- negative is same as nil; blocking indefinitely
    end

    usertimeouts[skt] = timeout
    return true
  end

-- reads a pattern from a client and yields to the reading set on timeouts
-- UDP: a UDP socket expects a second argument to be a number, so it MUST
-- be provided as the 'pattern' below defaults to a string. Will throw a
-- 'bad argument' error if omitted.
  function copas.receive(client, pattern, part)
    local s, err
    pattern = pattern or "*l"
    local current_log = _reading_log
    sto_timeout(client, "read")

    repeat
      s, err, part = client:receive(pattern, part)

      if s then
        current_log[client] = nil
        sto_timeout()
        return s, err, part

      elseif not _isSocketTimeout[err] then
        current_log[client] = nil
        sto_timeout()
        return s, err, part

      elseif sto_timed_out() then
        current_log[client] = nil
        return nil, sto_error(err)
      end

      if err == "wantwrite" then -- wantwrite may be returned during SSL renegotiations
        current_log = _writing_log
        current_log[client] = gettime()
        sto_change_queue("write")
        coroutine.yield(client, _writing)
      else
        current_log = _reading_log
        current_log[client] = gettime()
        sto_change_queue("read")
        coroutine.yield(client, _reading)
      end
    until false
  end

-- receives data from a client over UDP. Not available for TCP.
-- (this is a copy of receive() method, adapted for receivefrom() use)
  function copas.receivefrom(client, size)
    local s, err, port
    size = size or UDP_DATAGRAM_MAX
    sto_timeout(client, "read")

    repeat
      s, err, port = client:receivefrom(size) -- upon success err holds ip address

      if s then
        _reading_log[client] = nil
        sto_timeout()
        return s, err, port

      elseif err ~= "timeout" then
        _reading_log[client] = nil
        sto_timeout()
        return s, err, port

      elseif sto_timed_out() then
        _reading_log[client] = nil
        return nil, sto_error(err)
      end

      _reading_log[client] = gettime()
      coroutine.yield(client, _reading)
    until false
  end

-- same as above but with special treatment when reading chunks,
-- unblocks on any data received.
  function copas.receivePartial(client, pattern, part)
    local s, err
    pattern = pattern or "*l"
    local current_log = _reading_log
    sto_timeout(client, "read")

    repeat
      s, err, part = client:receive(pattern, part)

      if s or (type(pattern) == "number" and part ~= "" and part ~= nil) then
        current_log[client] = nil
        sto_timeout()
        return s, err, part

      elseif not _isSocketTimeout[err] then
        current_log[client] = nil
        sto_timeout()
        return s, err, part

      elseif sto_timed_out() then
        current_log[client] = nil
        return nil, sto_error(err)
      end

      if err == "wantwrite" then
        current_log = _writing_log
        current_log[client] = gettime()
        sto_change_queue("write")
        coroutine.yield(client, _writing)
      else
        current_log = _reading_log
        current_log[client] = gettime()
        sto_change_queue("read")
        coroutine.yield(client, _reading)
      end
    until false
  end

-- sends data to a client. The operation is buffered and
-- yields to the writing set on timeouts
-- Note: from and to parameters will be ignored by/for UDP sockets
  function copas.send(client, data, from, to)
    local s, err
    from = from or 1
    local lastIndex = from - 1
    local current_log = _writing_log
    sto_timeout(client, "write")

    repeat
      s, err, lastIndex = client:send(data, lastIndex + 1, to)

      -- adds extra coroutine swap
      -- garantees that high throughput doesn't take other threads to starvation
      if (math.random(100) > 90) then
        current_log[client] = gettime()   -- TODO: how to handle this??
        if current_log == _writing_log then
          coroutine.yield(client, _writing)
        else
          coroutine.yield(client, _reading)
        end
      end

      if s then
        current_log[client] = nil
        sto_timeout()
        return s, err, lastIndex

      elseif not _isSocketTimeout[err] then
        current_log[client] = nil
        sto_timeout()
        return s, err, lastIndex

      elseif sto_timed_out() then
        current_log[client] = nil
        return nil, sto_error(err)
      end

      if err == "wantread" then
        current_log = _reading_log
        current_log[client] = gettime()
        sto_change_queue("read")
        coroutine.yield(client, _reading)
      else
        current_log = _writing_log
        current_log[client] = gettime()
        sto_change_queue("write")
        coroutine.yield(client, _writing)
      end
    until false
  end

  function copas.sendto(client, data, ip, port)
    -- deprecated; for backward compatibility only, since UDP doesn't block on sending
    return client:sendto(data, ip, port)
  end

-- waits until connection is completed
  function copas.connect(skt, host, port)
    skt:settimeout(0)
    local ret, err, tried_more_than_once
    sto_timeout(skt, "write")

    repeat
      ret, err = skt:connect(host, port)

      -- non-blocking connect on Windows results in error "Operation already
      -- in progress" to indicate that it is completing the request async. So essentially
      -- it is the same as "timeout"
      if ret or (err ~= "timeout" and err ~= "Operation already in progress") then
        _writing_log[skt] = nil
        sto_timeout()
        -- Once the async connect completes, Windows returns the error "already connected"
        -- to indicate it is done, so that error should be ignored. Except when it is the
        -- first call to connect, then it was already connected to something else and the
        -- error should be returned
        if (not ret) and (err == "already connected" and tried_more_than_once) then
          return 1
        end
        return ret, err

      elseif sto_timed_out() then
        _writing_log[skt] = nil
        return nil, sto_error(err)
      end

      tried_more_than_once = tried_more_than_once or true
      _writing_log[skt] = gettime()
      coroutine.yield(skt, _writing)
    until false
  end
---
-- Peforms an (async) ssl handshake on a connected TCP client socket.
-- NOTE: replace all previous socket references, with the returned new ssl wrapped socket
-- Throws error and does not return nil+error, as that might silently fail
-- in code like this;
--   copas.addserver(s1, function(skt)
--       skt = copas.wrap(skt, sparams)
--       skt:dohandshake()   --> without explicit error checking, this fails silently and
--       skt:send(body)      --> continues unencrypted
-- @param skt Regular LuaSocket CLIENT socket object
-- @param sslt Table with ssl parameters
-- @return wrapped ssl socket, or throws an error
  function copas.dohandshake(skt, sslt)
    ssl = ssl or require("ssl")
    local nskt, err = ssl.wrap(skt, sslt)
    if not nskt then return error(err) end
    local queue
    nskt:settimeout(0)  -- non-blocking on the ssl-socket
    copas.settimeout(nskt, usertimeouts[skt]) -- copy copas user-timeout to newly wrapped one
    sto_timeout(nskt, "write")

    repeat
      local success, err = nskt:dohandshake()

      if success then
        sto_timeout()
        return nskt

      elseif not _isSocketTimeout[err] then
        sto_timeout()
        return error(err)

      elseif sto_timed_out() then
        return nil, sto_error(err)

      elseif err == "wantwrite" then
        sto_change_queue("write")
        queue = _writing

      elseif err == "wantread" then
        sto_change_queue("read")
        queue = _reading

      else
        error(err)
      end

      coroutine.yield(nskt, queue)
    until false
  end

-- flushes a client write buffer (deprecated)
  function copas.flush()
  end

-- wraps a TCP socket to use Copas methods (send, receive, flush and settimeout)
  local _skt_mt_tcp = {
    __tostring = function(self)
      return tostring(self.socket).." (copas wrapped)"
    end,
    __index = {

      send = function (self, data, from, to)
        return copas.send (self.socket, data, from, to)
      end,

      receive = function (self, pattern, prefix)
        if usertimeouts[self.socket] == 0 then
          return copas.receivePartial(self.socket, pattern, prefix)
        end
        return copas.receive(self.socket, pattern, prefix)
      end,

      flush = function (self)
        return copas.flush(self.socket)
      end,

      settimeout = function (self, time)
        return copas.settimeout(self.socket, time)
      end,

      -- TODO: socket.connect is a shortcut, and must be provided with an alternative
      -- if ssl parameters are available, it will also include a handshake
      connect = function(self, ...)
        local res, err = copas.connect(self.socket, ...)
        if res and self.ssl_params then
          res, err = self:dohandshake()
        end
        return res, err
      end,

      close = function(self, ...) return self.socket:close(...) end,

      -- TODO: socket.bind is a shortcut, and must be provided with an alternative
      bind = function(self, ...) return self.socket:bind(...) end,
      -- TODO: is this DNS related? hence blocking?
      getsockname = function(self, ...) return self.socket:getsockname(...) end,
      getstats = function(self, ...) return self.socket:getstats(...) end,
      setstats = function(self, ...) return self.socket:setstats(...) end,
      listen = function(self, ...) return self.socket:listen(...) end,
      accept = function(self, ...) return self.socket:accept(...) end,
      setoption = function(self, ...) return self.socket:setoption(...) end,
      -- TODO: is this DNS related? hence blocking?
      getpeername = function(self, ...) return self.socket:getpeername(...) end,
      shutdown = function(self, ...) return self.socket:shutdown(...) end,
      dohandshake = function(self, sslt)
        self.ssl_params = sslt or self.ssl_params
        local nskt, err = copas.dohandshake(self.socket, self.ssl_params)
        if not nskt then return nskt, err end
        self.socket = nskt  -- replace internal socket with the newly wrapped ssl one
        return self
      end,

    }}

-- wraps a UDP socket, copy of TCP one adapted for UDP.
  local _skt_mt_udp = {__index = { }}
  for k,v in pairs(_skt_mt_tcp) do _skt_mt_udp[k] = _skt_mt_udp[k] or v end
  for k,v in pairs(_skt_mt_tcp.__index) do _skt_mt_udp.__index[k] = v end

  _skt_mt_udp.__index.send        = function(self, ...) return self.socket:send(...) end

  _skt_mt_udp.__index.sendto      = function(self, ...) return self.socket:sendto(...) end

  _skt_mt_udp.__index.receive =     function (self, size)
    return copas.receive (self.socket, (size or UDP_DATAGRAM_MAX))
  end

  _skt_mt_udp.__index.receivefrom = function (self, size)
    return copas.receivefrom (self.socket, (size or UDP_DATAGRAM_MAX))
  end

  -- TODO: is this DNS related? hence blocking?
  _skt_mt_udp.__index.setpeername = function(self, ...) return self.socket:setpeername(...) end

  _skt_mt_udp.__index.setsockname = function(self, ...) return self.socket:setsockname(...) end

  -- do not close client, as it is also the server for udp.
  _skt_mt_udp.__index.close       = function(self, ...) return true end
---
-- Wraps a LuaSocket socket object in an async Copas based socket object.
-- @param skt The socket to wrap
-- @sslt (optional) Table with ssl parameters, use an empty table to use ssl with defaults
-- @return wrapped socket object
  function copas.wrap (skt, sslt)
    if (getmetatable(skt) == _skt_mt_tcp) or (getmetatable(skt) == _skt_mt_udp) then
      return skt -- already wrapped
    end
    skt:settimeout(0)
    if not isTCP(skt) then
      return  setmetatable ({socket = skt}, _skt_mt_udp)
    else
      return  setmetatable ({socket = skt, ssl_params = sslt}, _skt_mt_tcp)
    end
  end

--- Wraps a handler in a function that deals with wrapping the socket and doing the
-- optional ssl handshake.
  function copas.handler(handler, sslparams)
    -- TODO: pass a timeout value to set, and use during handshake
    return function (skt, ...)
      skt = copas.wrap(skt)
      if sslparams then skt:dohandshake(sslparams) end
      return handler(skt, ...)
    end
  end

--------------------------------------------------
-- Error handling
--------------------------------------------------
  local _errhandlers = setmetatable({}, { __mode = "k" })   -- error handler per coroutine

  local function _deferror(msg, co, skt)
    msg = ("%s (coroutine: %s, socket: %s)"):format(tostring(msg), tostring(co), tostring(skt))
    if type(co) == "thread" then
      -- regular Copas coroutine
      msg = debug.traceback(co, msg)
    else
      -- not a coroutine, but the main thread, this happens if a timeout callback
      -- (see `copas.timeout` causes an error (those callbacks run on the main thread).
      msg = debug.traceback(msg, 2)
    end
    print(msg)
  end

  function copas.setErrorHandler (err, default)
    if default then
      _deferror = err
    else
      _errhandlers[coroutine.running()] = err
    end
  end
  function copas.setErrorHandler2(err, co)
    _errhandlers[co] = err
  end
-- if `bool` is truthy, then the original socket errors will be returned in case of timeouts;
-- `timeout, wantread, wantwrite, Operation already in progress`. If falsy, it will always
-- return `timeout`.
  function copas.useSocketTimeoutErrors(bool)
    useSocketTimeoutErrors[coroutine.running()] = not not bool -- force to a boolean
  end

-------------------------------------------------------------------------------
-- Thread handling
-------------------------------------------------------------------------------

  local function _doTick (co, skt, ...)
    if not co then return end
    -- if a coroutine was canceled/removed, don't resume it
    if _canceled[co] then
      _canceled[co] = nil -- also clean up the registry
      _threads[co] = nil
      return
    end

    local ok, res, new_q = coroutine.resume(co, skt, ...) 

    if ok and res and new_q then
      new_q:insert (res)
      new_q:push (res, co)
    else
      if not ok then pcall (_errhandlers [co] or _deferror, res, co, skt) end
      if skt and copas.autoclose and isTCP(skt) then
        skt:close() -- do not auto-close UDP sockets, as the handler socket is also the server socket
      end
      _errhandlers [co] = nil
    end
  end

-- accepts a connection on socket input
  local function _accept(server_skt, handler)
    local client_skt = server_skt:accept()
    if client_skt then
      client_skt:settimeout(0)
      local co = coroutine.create(handler)
      _doTick(co, client_skt)
    end
  end
-------------------------------------------------------------------------------
-- Adds a server/handler pair to Copas dispatcher
-------------------------------------------------------------------------------
  do
    local function addTCPserver(server, handler, timeout)
      server:settimeout(timeout or 0)
      _servers[server] = handler
      _reading:insert(server)
    end

    local function addUDPserver(server, handler, timeout)
      server:settimeout(timeout or 0)
      local co = coroutine.create(handler)
      _reading:insert(server)
      _doTick(co, server)
    end

    function copas.addserver(server, handler, timeout)
      if isTCP(server) then
        addTCPserver(server, handler, timeout)
      else
        addUDPserver(server, handler, timeout)
      end
    end
  end

  function copas.removeserver(server, keep_open)
    local skt = server
    local mt = getmetatable(server)
    if mt == _skt_mt_tcp or mt == _skt_mt_udp then
      skt = server.socket
    end
    _servers:remove(skt)
    _reading:remove(skt)
    if keep_open then
      return true
    end
    return server:close()
  end

-------------------------------------------------------------------------------
-- Adds an new coroutine thread to Copas dispatcher
-------------------------------------------------------------------------------
  function copas.addthread(handler, ...)
    -- create a coroutine that skips the first argument, which is always the socket
    -- passed by the scheduler, but `nil` in case of a task/thread
    local thread = coroutine.create(function(_, ...) return handler(...) end)
    _threads[thread] = true -- register this thread so it can be removed
    _doTick (thread, nil, ...)
    return thread
  end

  function copas.removethread(thread)
    -- if the specified coroutine is registered, add it to the canceled table so
    -- that next time it tries to resume it exits.
    _canceled[thread] = _threads[thread or 0]
  end
-------------------------------------------------------------------------------
-- Sleep/pause management functions
-------------------------------------------------------------------------------
-- yields the current coroutine and wakes it after 'sleeptime' seconds.
-- If sleeptime < 0 then it sleeps until explicitly woken up using 'wakeup'
  function copas.sleep(sleeptime)
    coroutine.yield((sleeptime or 0), _sleeping)
  end

-- Wakes up a sleeping coroutine 'co'.
  function copas.wakeup(co)
    _sleeping:wakeup(co)
  end
-------------------------------------------------------------------------------
-- Timeout management
-------------------------------------------------------------------------------
  do
    local timeout_register = setmetatable({}, { __mode = "k" })
    local timerwheel = timerwheel2.new({
        precision = TIMEOUT_PRECISION,                -- timeout precision 100ms
        ringsize = math.floor(60/TIMEOUT_PRECISION),  -- ring size 1 minute
        err_handler = function(...) return _deferror(...) end,
      })

    copas.addthread(function()
        while true do
          copas.sleep(TIMEOUT_PRECISION)
          timerwheel:step()
        end
      end)

    -- get the number of timeouts running
    function copas.gettimeouts()
      return timerwheel:count()
    end

    function copas.timeout(delay, callback)
      local co = coroutine.running()
      local existing_timer = timeout_register[co]
      if existing_timer then
        timerwheel:cancel(existing_timer)
      end
      if delay > 0 then
        timeout_register[co] = timerwheel:set(delay, callback, co)
      else
        timeout_register[co] = nil
      end
      return true
    end
  end

  local _tasks = {} do function _tasks:add(tsk) _tasks[#_tasks + 1] = tsk end end

-- a task to check ready to read events
  local _readable_task = {} do

    local function tick(skt)
      local handler = _servers[skt]
      if handler then
        _accept(skt, handler)
      else
        _reading:remove(skt)
        _doTick(_reading:pop(skt), skt)
      end
    end
    function _readable_task:step()
      for _, skt in ipairs(self._evs) do
        tick(skt)
      end
    end
    _tasks:add(_readable_task)
  end

-- a task to check ready to write events
  local _writable_task = {} do

    local function tick(skt)
      _writing:remove(skt)
      _doTick(_writing:pop(skt), skt)
    end

    function _writable_task:step()
      for _, skt in ipairs(self._evs) do tick(skt) end
    end
    _tasks:add(_writable_task)
  end

-- sleeping threads task
  local _sleeping_task = {} do

    function _sleeping_task:step()
      local now = gettime()

      local co = _sleeping:pop(now)
      while co do
        -- we're pushing them to _resumable, since that list will be replaced before
        -- executing. This prevents tasks running twice in a row with sleep(0) for example.
        -- So here we won't execute, but at _resumable step which is next
        _resumable:push(co)
        co = _sleeping:pop(now)
      end
    end

    _tasks:add(_sleeping_task)
  end

-- resumable threads task
  local _resumable_task = {} do

    function _resumable_task:step()
      -- replace the resume list before iterating, so items placed in there
      -- will indeed end up in the next copas step, not in this one, and not
      -- create a loop
      local resumelist = _resumable:clear_resumelist()

      for _, co in ipairs(resumelist) do _doTick(co) end
    end

    _tasks:add(_resumable_task)
  end

-------------------------------------------------------------------------------
-- Checks for reads and writes on sockets
-------------------------------------------------------------------------------
  local _select do

    local last_cleansing = 0
    local duration = function(t2, t1) return t2-t1 end

    _select = function(timeout)
      local err
      local now = gettime()

      _readable_task._evs, _writable_task._evs, err = socket.select(_reading, _writing, timeout)
      local r_evs, w_evs = _readable_task._evs, _writable_task._evs

      if duration(now, last_cleansing) > WATCH_DOG_TIMEOUT then
        last_cleansing = now

        -- Check all sockets selected for reading, and check how long they have been waiting
        -- for data already, without select returning them as readable
        for skt,time in pairs(_reading_log) do
          if not r_evs[skt] and duration(now, time) > WATCH_DOG_TIMEOUT then
            -- This one timedout while waiting to become readable, so move
            -- it in the readable list and try and read anyway, despite not
            -- having been returned by select
            _reading_log[skt] = nil
            r_evs[#r_evs + 1] = skt
            r_evs[skt] = #r_evs
          end
        end

        -- Do the same for writing
        for skt,time in pairs(_writing_log) do
          if not w_evs[skt] and duration(now, time) > WATCH_DOG_TIMEOUT then
            _writing_log[skt] = nil
            w_evs[#w_evs + 1] = skt
            w_evs[skt] = #w_evs
          end
        end
      end

      if err == "timeout" and #r_evs + #w_evs > 0 then
        return nil
      else
        return err
      end
    end
  end
-------------------------------------------------------------------------------
-- Dispatcher loop step.
-- Listen to client requests and handles them
-- Returns false if no socket-data was handled, or true if there was data
-- handled (or nil + error message)
-------------------------------------------------------------------------------
  function copas.step(timeout)
    -- Need to wake up the select call in time for the next sleeping event
    if not _resumable:done() then
      timeout = 0
    else
      timeout = math.min(_sleeping:getnext(), timeout or math.huge)
    end
    local err = _select(timeout)
    for _, tsk in ipairs(_tasks) do
      tsk:step()
    end
    if err then
      if err == "timeout" then return false end
      return nil, err
    end
    return true
  end
-------------------------------------------------------------------------------
-- Check whether there is something to do.
-- returns false if there are no sockets for read/write nor tasks scheduled
-- (which means Copas is in an empty spin)
-------------------------------------------------------------------------------
  function copas.finished()
    return #_reading == 0 and #_writing == 0 and _resumable:done() and _sleeping:done(copas.gettimeouts())
  end
-------------------------------------------------------------------------------
-- Dispatcher endless loop.
-- Listen to client requests and handles them forever
-------------------------------------------------------------------------------
  function copas.loop(initializer, timeout)
    if type(initializer) == "function" then
      copas.addthread(initializer)
    else
      timeout = initializer or timeout
    end

    copas.running = true
    while not copas.finished() do copas.step(timeout) end
    copas.running = false
  end
end
--------- Copas timer ---------
do
  timer = {}
  timer.__index = timer

  do
    local function expire_func(self, initial_delay)
      copas.sleep(initial_delay)
      while true do
        if not self.cancelled then
          self:callback(self.params)
        end
        if (not self.recurring) or self.cancelled then
          -- clean up and exit the thread
          self.co = nil
          self.cancelled = true
          return
        end
        copas.sleep(self.delay)
      end
    end

    function timer:arm(initial_delay)
      assert(initial_delay == nil or initial_delay >= 0, "delay must be greater than or equal to 0")
      if self.co then return nil, "already armed" end
      self.cancelled = false
      self.co = copas.addthread(expire_func, self, initial_delay or self.delay)
      return self
    end
  end

  function timer:cancel()
    if not self.co then return nil, "not armed" end
    if self.cancelled then return nil, "already cancelled" end
    self.cancelled = true
    copas.wakeup(self.co)       -- resume asap
    copas.removethread(self.co) -- will immediately drop the thread upon resuming
    self.co = nil
    return self
  end

  function timer.new(opts)
    assert(opts.delay >= 0, "delay must be greater than or equal to 0")
    assert(type(opts.callback) == "function", "expected callback to be a function")
    return setmetatable({
        delay = opts.delay,
        callback = opts.callback,
        recurring = not not opts.recurring,
        params = opts.params,
        cancelled = false,
        }, timer):arm(opts.initial_delay)
  end
end

--------- Copas HTTP support -------------------------
do
  -----------------------------------------------------------------------------
-- Full copy of the LuaSocket code, modified to include
-- https and http/https redirects, and Copas async enabled.
-----------------------------------------------------------------------------
-- HTTP/1.1 client support for the Lua language.
-- LuaSocket toolkit.
-- Author: Diego Nehab
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module and import dependencies
-------------------------------------------------------------------------------
  local base = _G
  --local table = require("table")
  local try = socket.try
  copas.http = {}
  local _M = copas.http

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- connection timeout in seconds
  _M.TIMEOUT = 60
-- default port for document retrieval
  _M.PORT = 80
-- user agent field sent in request
  _M.USERAGENT = socket._VERSION

-- Default settings for SSL
  _M.SSLPORT = 443
  _M.SSLPROTOCOL = "tlsv1_2"
  _M.SSLOPTIONS  = "all"
  _M.SSLVERIFY   = "none"


-----------------------------------------------------------------------------
-- Reads MIME headers from a connection, unfolding where needed
-----------------------------------------------------------------------------
  local function receiveheaders(sock, headers)
    local line, name, value, err
    headers = headers or {}
    -- get first line
    line, err = sock:receive()
    if err then return nil, err end
    -- headers go until a blank line is found
    while line ~= "" do
      -- get field-name and value
      name, value = socket.skip(2, string.find(line, "^(.-):%s*(.*)"))
      if not (name and value) then return nil, "malformed reponse headers" end
      name = string.lower(name)
      -- get next line (value might be folded)
      line, err  = sock:receive()
      if err then return nil, err end
      -- unfold any folded values
      while string.find(line, "^%s") do
        value = value .. line
        line = sock:receive()
        if err then return nil, err end
      end
      -- save pair in table
      if headers[name] then headers[name] = headers[name] .. ", " .. value
      else headers[name] = value end
    end
    return headers
  end

-----------------------------------------------------------------------------
-- Extra sources and sinks
-----------------------------------------------------------------------------
  socket.sourcet["http-chunked"] = function(sock, headers)
    return base.setmetatable({
        getfd = function() return sock:getfd() end,
        dirty = function() return sock:dirty() end
        }, {
        __call = function()
          -- get chunk size, skip extention
          local line, err = sock:receive()
          if err then return nil, err end
          local size = base.tonumber(string.gsub(line, ";.*", ""), 16)
          if not size then return nil, "invalid chunk size" end
          -- was it the last chunk?
          if size > 0 then
            -- if not, get chunk and skip terminating CRLF
            local chunk, err = sock:receive(size)
            if chunk then sock:receive() end
            return chunk, err
          else
            -- if it was, read trailers into headers table
            headers, err = receiveheaders(sock, headers)
            if not headers then return nil, err end
          end
        end
      })
  end

  socket.sinkt["http-chunked"] = function(sock)
    return base.setmetatable({
        getfd = function() return sock:getfd() end,
        dirty = function() return sock:dirty() end
        }, {
        __call = function(self, chunk, err)
          if not chunk then return sock:send("0\r\n\r\n") end
          local size = string.format("%X\r\n", string.len(chunk))
          return sock:send(size ..  chunk .. "\r\n")
        end
      })
  end

-----------------------------------------------------------------------------
-- Low level HTTP API
-----------------------------------------------------------------------------
  local metat = { __index = {} }

  function _M.open(reqt)
    -- create socket with user connect function
    local c = socket.try(reqt:create())   -- method call, passing reqt table as self!
    local h = base.setmetatable({ c = c }, metat)
    -- create finalized try
    h.try = socket.newtry(function() h:close() end)
    -- set timeout before connecting
    h.try(c:settimeout(reqt.timeout or _M.TIMEOUT))
    h.try(c:connect(reqt.host, reqt.port or _M.PORT))
    -- here everything worked
    return h
  end

  function metat.__index:sendrequestline(method, uri)
    local reqline = string.format("%s %s HTTP/1.1\r\n", method or "GET", uri)
    return self.try(self.c:send(reqline))
  end

  function metat.__index:sendheaders(tosend)
    local canonic = headers.canonic
    local h = "\r\n"
    for f, v in base.pairs(tosend) do
      h = (canonic[f] or f) .. ": " .. v .. "\r\n" .. h
    end
    self.try(self.c:send(h))
    return 1
  end

  function metat.__index:sendbody(headers, source, step)
    source = source or ltn12.source.empty()
    step = step or ltn12.pump.step
    -- if we don't know the size in advance, send chunked and hope for the best
    local mode = "http-chunked"
    if headers["content-length"] then mode = "keep-open" end
    return self.try(ltn12.pump.all(source, socket.sink(mode, self.c), step))
  end
  function metat.__index:receivestatusline()
    local status = self.try(self.c:receive(5))
    -- identify HTTP/0.9 responses, which do not contain a status line
    -- this is just a heuristic, but is what the RFC recommends
    if status ~= "HTTP/" then return nil, status end
    -- otherwise proceed reading a status line
    status = self.try(self.c:receive("*l", status))
    local code = socket.skip(2, string.find(status, "HTTP/%d*%.%d* (%d%d%d)"))
    return self.try(base.tonumber(code), status)
  end

  function metat.__index:receiveheaders()
    return self.try(receiveheaders(self.c))
  end

  function metat.__index:receivebody(headers, sink, step)
    sink = sink or ltn12.sink.null()
    step = step or ltn12.pump.step
    local length = base.tonumber(headers["content-length"])
    local t = headers["transfer-encoding"] -- shortcut
    local mode = "default" -- connection close
    if t and t ~= "identity" then mode = "http-chunked"
    elseif base.tonumber(headers["content-length"]) then mode = "by-length" end
    return self.try(ltn12.pump.all(socket.source(mode, self.c, length),
        sink, step))
  end

  function metat.__index:receive09body(status, sink, step)
    local source = ltn12.source.rewind(socket.source("until-closed", self.c))
    source(status)
    return self.try(ltn12.pump.all(source, sink, step))
  end

  function metat.__index:close() return self.c:close() end

-----------------------------------------------------------------------------
-- High level HTTP API
-----------------------------------------------------------------------------
  local function adjusturi(reqt)
    local u = reqt
    -- if there is a proxy, we need the full url. otherwise, just a part.
    if not reqt.proxy and not _M.PROXY then
      u = {
        path = socket.try(reqt.path, "invalid path 'nil'"),
        params = reqt.params,
        query = reqt.query,
        fragment = reqt.fragment
      }
    end
    return url.build(u)
  end

  local function adjustproxy(reqt)
    local proxy = reqt.proxy or _M.PROXY
    if proxy then
      proxy = url.parse(proxy)
      return proxy.host, proxy.port or 3128
    else
      return reqt.host, reqt.port
    end
  end

  local function adjustheaders(reqt)
    -- default headers
    local host = string.gsub(reqt.authority, "^.-@", "")
    local lower = {
      ["user-agent"] = _M.USERAGENT,
      ["host"] = host,
      ["connection"] = "close, TE",
      ["te"] = "trailers"
    }
    -- if we have authentication information, pass it along
    if reqt.user and reqt.password then
      lower["authorization"] =
      "Basic " ..  (mime.b64(reqt.user .. ":" .. reqt.password))
    end
    -- override with user headers
    for i,v in base.pairs(reqt.headers or lower) do
      lower[string.lower(i)] = v
    end
    return lower
  end

-- default url parts
  local default = {
    host = "",
    port = _M.PORT,
    path ="/",
    scheme = "http"
  }

  local function adjustrequest(reqt)
    -- parse url if provided
    local nreqt = reqt.url and url.parse(reqt.url, default) or {}
    -- explicit components override url
    for i,v in base.pairs(reqt) do nreqt[i] = v end
    if nreqt.port == "" then nreqt.port = 80 end
    socket.try(nreqt.host and nreqt.host ~= "",
      "invalid host '" .. base.tostring(nreqt.host) .. "'")
    -- compute uri if user hasn't overriden
    nreqt.uri = reqt.uri or adjusturi(nreqt)
    -- ajust host and port if there is a proxy
    nreqt.host, nreqt.port = adjustproxy(nreqt)
    -- adjust headers in request
    nreqt.headers = adjustheaders(nreqt)
    return nreqt
  end

  local function shouldredirect(reqt, code, headers)
    return headers.location and
    string.gsub(headers.location, "%s", "") ~= "" and
    (reqt.redirect ~= false) and
    (code == 301 or code == 302 or code == 303 or code == 307) and
    (not reqt.method or reqt.method == "GET" or reqt.method == "HEAD")
    and (not reqt.nredirects or reqt.nredirects < 5)
  end

  local function shouldreceivebody(reqt, code)
    if reqt.method == "HEAD" then return nil end
    if code == 204 or code == 304 then return nil end
    if code >= 100 and code < 200 then return nil end
    return 1
  end

-- forward declarations
  local trequest, tredirect

--[[local]] function tredirect(reqt, location)
    local result, code, headers, status = trequest {
      -- the RFC says the redirect URL has to be absolute, but some
      -- servers do not respect that
      url = url.absolute(reqt.url, location),
      source = reqt.source,
      sink = reqt.sink,
      headers = reqt.headers,
      proxy = reqt.proxy,
      nredirects = (reqt.nredirects or 0) + 1,
      create = reqt.create
    }
    -- pass location header back as a hint we redirected
    headers = headers or {}
    headers.location = headers.location or location
    return result, code, headers, status
  end

--[[local]] function trequest(reqt)
    -- we loop until we get what we want, or
    -- until we are sure there is no way to get it
    local nreqt = adjustrequest(reqt)
    local h = _M.open(nreqt)
    -- send request line and headers
    h:sendrequestline(nreqt.method, nreqt.uri)
    h:sendheaders(nreqt.headers)
    -- if there is a body, send it
    if nreqt.source then
      h:sendbody(nreqt.headers, nreqt.source, nreqt.step)
    end
    local code, status = h:receivestatusline()
    -- if it is an HTTP/0.9 server, simply get the body and we are done
    if not code then
      h:receive09body(status, nreqt.sink, nreqt.step)
      return 1, 200
    end
    local headers
    -- ignore any 100-continue messages
    while code == 100 do
      h:receiveheaders()
      code, status = h:receivestatusline()
    end
    headers = h:receiveheaders()
    -- at this point we should have a honest reply from the server
    -- we can't redirect if we already used the source, so we report the error
    if shouldredirect(nreqt, code, headers) and not nreqt.source then
      h:close()
      return tredirect(reqt, headers.location)
    end
    -- here we are finally done
    if shouldreceivebody(nreqt, code) then
      h:receivebody(headers, nreqt.sink, nreqt.step)
    end
    h:close()
    return 1, code, headers, status
  end

-- Return a function which performs the SSL/TLS connection.
  local function tcp(params)
    params = params or {}
    -- Default settings
    params.protocol = params.protocol or _M.SSLPROTOCOL
    params.options = params.options or _M.SSLOPTIONS
    params.verify = params.verify or _M.SSLVERIFY
    params.mode = "client"   -- Force client mode
    -- upvalue to track https -> http redirection
    local washttps = false
    -- 'create' function for LuaSocket
    return function (reqt)
      local u = url.parse(reqt.url)
      if (reqt.scheme or u.scheme) == "https" then
        -- https, provide an ssl wrapped socket
        local conn = copas.wrap(socket.tcp(), params)
        -- insert https default port, overriding http port inserted by LuaSocket
        if not u.port then
          u.port = _M.SSLPORT
          reqt.url = url.build(u)
          reqt.port = _M.SSLPORT
        end
        washttps = true
        return conn
      else
        -- regular http, needs just a socket...
        if washttps and params.redirect ~= "all" then
          try(nil, "Unallowed insecure redirect https to http")
        end
        return copas.wrap(socket.tcp())
      end
    end
  end

-- parses a shorthand form into the advanced table form.
-- adds field `target` to the table. This will hold the return values.
  _M.parseRequest = function(u, b)
    local reqt = {
      url = u,
      target = {},
    }
    reqt.sink = ltn12.sink.table(reqt.target)
    if b then
      reqt.source = ltn12.source.string(b)
      reqt.headers = {
        ["content-length"] = string.len(b),
        ["content-type"] = "application/x-www-form-urlencoded"
      }
      reqt.method = "POST"
    end
    return reqt
  end
  _M.request = socket.protect(function(reqt, body)
      if base.type(reqt) == "string" then
        reqt = _M.parseRequest(reqt, body)
        local ok, code, headers, status = _M.request(reqt)

        if ok then
          return table.concat(reqt.target), code, headers, status
        else
          return nil, code
        end
      else
        reqt.create = reqt.create or tcp(reqt)
        return trequest(reqt)
      end
    end)

  http = _M
end
--------- Copas Lock support -------------------------
do
  local DEFAULT_TIMEOUT = 10
  local gettime = socket.gettime
  lock = {}
  lock.__index = lock

-- registry, locks indexed by the coroutines using them.
  local registry = setmetatable({}, { __mode="kv" })

--- Creates a new lock.
-- @param seconds (optional) default timeout in seconds when acquiring the lock (defaults to 10)
-- @param not_reentrant (optional) if truthy the lock will not allow a coroutine to grab the same lock multiple times
-- @return the lock object
  function lock.new(seconds, not_reentrant)
    local timeout = tonumber(seconds or DEFAULT_TIMEOUT) or -1
    if timeout < 0 then
      error("expected timeout (1st argument) to be a number greater than or equal to 0, got: " .. tostring(seconds), 2)
    end
    return setmetatable({
        timeout = timeout,
        not_reentrant = not_reentrant,
        queue = {},
        q_tip = 0,  -- index of the first in line waiting
        q_tail = 0, -- index where the next one will be inserted
        owner = nil, -- coroutine holding lock currently
        call_count = nil, -- recursion call count
        errors = setmetatable({}, { __mode = "k" }), -- error indexed by coroutine
        }, lock)
  end

  do
    local destroyed_func = function()
      return nil, "destroyed"
    end

    local destroyed_lock_mt = {
      __index = function()
        return destroyed_func
      end
    }
    --- destroy a lock.
    -- Releases all waiting threads with `nil+"destroyed"`
    function lock:destroy()
      --print("destroying ",self)
      for i = self.q_tip, self.q_tail do
        local co = self.queue[i]
        if co then
          self.errors[co] = "destroyed"
          --print("marked destroyed ", co)
          copas.wakeup(co)
        end
      end
      if self.owner then
        self.errors[self.owner] = "destroyed"
        --print("marked destroyed ", co)
      end
      self.queue = {}
      self.q_tip = 0
      self.q_tail = 0
      self.destroyed = true
      setmetatable(self, destroyed_lock_mt)
      return true
    end
  end

  local function timeout_handler(co)
    local self = registry[co]
    for i = self.q_tip, self.q_tail do
      if co == self.queue[i] then
        self.queue[i] = nil
        self.errors[co] = "timeout"
        --print("marked timeout ", co)
        copas.wakeup(co)
        return
      end
    end
  end

--- Acquires the lock.
-- If the lock is owned by another thread, this will yield control, until the
-- lock becomes available, or it times out.
-- If `timeout == 0` then it will immediately return (without yielding).
-- @param timeout (optional) timeout in seconds, if given overrides the timeout passed to `new`.
-- @return wait-time on success, or nil+error+wait_time on failure. Errors can be "timeout", "destroyed", or "lock is not re-entrant"
  function lock:get(timeout)
    local co = coroutine.running()
    local start_time

    -- is the lock already taken?
    if self.owner then
      -- are we re-entering?
      if co == self.owner then
        if self.not_reentrant then
          return nil, "lock is not re-entrant", 0
        else
          self.call_count = self.call_count + 1
          return 0
        end
      end

      self.queue[self.q_tail] = co
      self.q_tail = self.q_tail + 1
      timeout = timeout or self.timeout
      if timeout == 0 then
        return nil, "timeout", 0
      end

      registry[co] = self
      copas.timeout(timeout, timeout_handler)
      start_time = gettime()
      copas.sleep(-1)
      local err = self.errors[co]
      self.errors[co] = nil
      if err ~= "timeout" then
        copas.timeout(0)
      end
      if err then
        self.errors[co] = nil
        return nil, err, gettime() - start_time
      end
    end
    self.owner = co
    self.call_count = 1
    return start_time and (gettime() - start_time) or 0
  end
--- Releases the lock currently held.
-- Releasing a lock that is not owned by the current co-routine will return
-- an error.
-- returns true, or nil+err on an error
  function lock:release()
    local co = coroutine.running()
    if co ~= self.owner then
      return nil, "cannot release a lock not owned"
    end
    self.call_count = self.call_count - 1
    if self.call_count > 0 then
      -- same coro is still holding it
      return true
    end
    if self.q_tail == self.q_tip then
      -- queue is empty
      self.owner = nil
      return true
    end
    while self.q_tip < self.q_tail do
      local next_up = self.queue[self.q_tip]
      if next_up then
        self.owner = next_up
        self.queue[self.q_tip] = nil
        self.q_tip = self.q_tip + 1
        copas.wakeup(next_up)
        return true
      end
      self.q_tip = self.q_tip + 1
    end
    -- queue is empty, reset pointers
    self.q_tip = 0
    self.q_tail = 0
    return true
  end
end

return {
  http=copas.http, loop=copas.loop, https=copas.https, timer=timer, lock=lock, removethread=copas.removethread,
  sleep = copas.sleep, addserver = copas.addserver, wrap = copas.wrap, 
  send = copas.send, receive = copas.receive,
}