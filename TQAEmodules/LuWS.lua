--https://github.com/toggledbits/LuWS
--[[
	luws.lua - Luup WebSocket implemented (for Vera Luup and openLuup systems)
	Copyright 2020 Patrick H. Rigney, All Rights Reserved. http://www.toggledbits.com/
	Works best with SockProxy installed.
	Ref: RFC6455

	NOTA BENE: 64-bit payload length not supported.

	See CHANGELOG.md for release notes at https://github.com/toggledbits/LuWS
--]]
--luacheck: std lua51,module,read globals luup,ignore 542 611 612 614 111/_,no max line length

--module("luws", package.seeall)
local wsopen, wslastping, wsreset, wsreceive, wshandleincoming, wsclose, wssend, debug_mode, luup

local _VERSION = 20358

debug_mode = false

local math = require "math"
local string = require "string"
local socket = require "socket"
local bit = require "bit32"
-- local ltn12 = require "ltn12"

-- local WSGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
local STATE_START = "start"
local STATE_READLEN1 = "len"
local STATE_READLEN161 = "len16-1"
local STATE_READLEN162 = "len16-2"
local STATE_READDATA = "data"
local STATE_SYNC = "sync"
-- local STATE_RESYNC1 = "resync1"
-- local STATE_RESYNC2 = "resync2"
local STATE_READMASK = "mask"
local MAXMESSAGE = 65535 -- maximum WS message size
local CHUNKSIZE = 2048
local DEFAULTMSGTIMEOUT = 0 -- drop connection if no message in this time (0=no timeout)

local timenow = socket.gettime or os.time -- use hi-res time if available
local unpack = unpack or table.unpack -- luacheck: ignore 143
local LOG = (luup and luup.log) or ( function(msg,level) print(level or 50,msg) end )

function dump(t, seen)
	if t == nil then return "nil" end
	if seen == nil then seen = {} end
	local sep = ""
	local str = "{ "
	for k,v in pairs(t) do
		local val
		if type(v) == "table" then
			if seen[v] then val = "(recursion)"
			else
				seen[v] = true
				val = dump(v, seen)
			end
		elseif type(v) == "string" then
			if #v > 255 then val = string.format("%q", v:sub(1,252).."...")
			else val = string.format("%q", v) end
		elseif type(v) == "number" and (math.abs(v-os.time()) <= 86400) then
			val = tostring(v) .. "(" .. os.date("%x.%X", v) .. ")"
		else
			val = tostring(v)
		end
		str = str .. sep .. k .. "=" .. val
		sep = ", "
	end
	str = str .. " }"
	return str
end

local function L(msg, ...) -- luacheck: ignore 212
	local str
	local level = 50
	if type(msg) == "table" then
		str = "luws: " .. tostring(msg.msg or msg[1])
		level = msg.level or level
	else
		str = "luws: " .. tostring(msg)
	end
	str = string.gsub(str, "%%(%d+)", function( n )
			n = tonumber(n, 10)
			if n < 1 or n > #arg then return "nil" end
			local val = arg[n]
			if type(val) == "table" then
				return dump(val)
			elseif type(val) == "string" then
				return string.format("%q", val)
			elseif type(val) == "number" and math.abs(val-os.time()) <= 86400 then
				return tostring(val) .. "(" .. os.date("%x.%X", val) .. ")"
			end
			return tostring(val)
		end
	)
	LOG(str, level)
end

local function D(msg, ...) if debug_mode then L( { msg=msg, prefix="luws[debug]: " }, ... ) end end

local function default( val, dflt ) return ( val == nil ) and dflt or val end

local function split( str, sep )
	sep = sep or ","
	local arr = {}
	if str == nil or #str == 0 then return arr, 0 end
	local rest = string.gsub( str or "", "([^" .. sep .. "]*)" .. sep, function( m ) table.insert( arr, m ) return "" end )
	table.insert( arr, rest )
	return arr, #arr
end

-- Upgrade an HTTP socket to websocket
local function wsupgrade( wsconn )
	D("wsupgrade(%1)", wsconn)
	local mime = require "mime"

	-- Upgrade headers. Map/dict provided; flatten to array and join.
	local uhead = {}
	for k,v in pairs( wsconn.options.upgrade_headers or {} ) do
		table.insert( uhead, k .. ": " .. v )
	end
	uhead = table.concat( uhead, "\r\n" );

	-- Generate key/nonce, 16 bytes base64-encoded
	local key = {}
	for k=1,16 do key[k] = string.char( math.random( 0, 255 ) ) end
	key = mime.b64( table.concat( key, "" ) )
	-- Ref: https://stackoverflow.com/questions/18265128/what-is-sec-websocket-key-for
	local req = string.format("GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n%s\r\n",
		wsconn.path, wsconn.ip, key, uhead)

	-- Send request.
	D("wsupgrade() sending %1", req)
	wsconn.socket:settimeout( 5, "b" )
	wsconn.socket:settimeout( 5, "r" )
	local nb,err = wsconn.socket:send( req )
	if nb == nil then
		return false, "Failed to send upgrade request: "..tostring(err)
	end

	-- Read until we get two consecutive linefeeds.
	wsconn.socket:settimeout( 5, "b" )
	wsconn.socket:settimeout( 5, "r" )
	local buf = {}
	local ntotal = 0
	while true do
		nb,err = wsconn.socket:receive("*l")
		D("wsupgrade() received %1, %2", nb, err)
		if nb == nil then
			L("wsupgrade() error while reading upgrade response, %1", err)
			return false
		end
		if #nb == 0 then break end -- blank line ends
		table.insert( buf, nb )
		ntotal = ntotal + #nb
		if ntotal >= MAXMESSAGE then
			buf = {}
			L({level=1,msg="Buffer overflow reading websocket upgrade response; aborting."})
			break;
		end
	end

	-- Check response
	-- local resp = table.concat( buf, "\n" )
	D("wsupdate() upgrade response: %1", buf)
	if buf[1]:match( "^HTTP/1%.. 101 " ) then
		-- ??? check response key TO-DO
		D("wsupgrade() upgrade succeeded!")
		wsconn.readstate = STATE_START
		return true -- Flag now in websocket protocol
	end
	return false, "upgrade failed; "..tostring(buf[1])
end

local function connect( ip, port )
	local sock = socket.tcp()
	if not sock then
		return nil, "Can't get socket for connection"
	end
	sock:settimeout( 15 )
	local r, e = sock:connect( ip, port )
	if r then
		return sock
	end
	pcall( function() sock:close() end ) -- crash resistant
	return nil, string.format("Connection to %s:%s failed: %s", ip, port, tostring(e))
end

function wsopen( url, handler, options )
	D("wsopen(%1)", url)
	options = options or {}
	options.receive_timeout = default( options.receive_timeout, DEFAULTMSGTIMEOUT )
	options.receive_chunk_size = default( options.receive_chunk_size, CHUNKSIZE )
	options.max_payload_size = default( options.max_payload_size, MAXMESSAGE )
	options.use_masking = default( options.use_masking, true ) -- RFC required, but settable
	options.connect = default( options.connect, connect )
	options.control_handler = default( options.control_handler, nil )
	options.upgrade_headers = default( options.upgrade_headers, nil )

	local port
	local proto, ip, ps = url:match("^(wss?)://([^:/]+)(.*)")
	if not proto then
		error("Invalid protocol/address for WebSocket open in " .. url)
	end
	port = proto == "wss" and 443 or 80
	local p,path = ps:match("^:(%d+)(.*)")
	if p then
		port = tonumber(p) or port
	else
		path = ps
	end
	if path == "" then path = "/" end

	local wsconn = {}
	wsconn.connected = false
	wsconn.proto = proto
	wsconn.ip = ip
	wsconn.port = port
	wsconn.path = path
	wsconn.readstate = STATE_START
	wsconn.msg = nil
	wsconn.msghandler = handler
	wsconn.options = options

	-- This call is async -- it returns immediately.
	local sock,err = options.connect( ip, port )
	if not sock then
		return false, err
	end
	wsconn.socket = sock
	wsconn.socket:setoption( 'keepalive', true )
	if proto == "wss" then
		D("wsopen() preping for SSL connection")
		local ssl = require "ssl"
		local opts = {
			  mode=default( options.ssl_mode, 'client' )
			, verify=default( options.ssl_verify, 'none' )
			, protocol=default( options.ssl_protocol, (ssl._VERSION or ""):match( "^0%.[654]" ) and 'tlsv1_2' or 'any' )
			, options=split( default( options.ssl_options, 'all' ) )
		}
		D("wsopen() wrap %1 %2", wsconn.socket, opts)
		sock = ssl.wrap( wsconn.socket, opts )
		D("wsopen() starting handshake");
		if sock and sock:dohandshake() then
			D("wsopen() successful SSL/TLS negotiation")
			wsconn.socket = sock -- save wrapped socket
		else
			D("wsopen() failed SSL negotation")
			wsconn.socket:close()
			wsconn.socket = nil
			return false, "Failed SSL negotation"
		end
	end
	D("wsopen() upgrading connection to WebSocket")
	local st
	st,err = wsupgrade( wsconn )
	if st then
		wsconn.connected = true
		wsconn.lastMessage = timenow()
		wsconn.lastPing = timenow()
		local m = getmetatable(wsconn) or {}
		m.__tostring = function( o ) return string.format("luws-websock[%s:%s]", o.ip, o.port) end
		-- m.__newindex = function( o, n, v ) error("Immutable luws-websock, can't set "..n) end
		setmetatable(wsconn, m)
		D("wsopen() successful WebSocket startup, wsconn %1", wsconn)
		return wsconn
	end
	pcall( function() wsconn.socket:close() end ) -- crash-resistant
	wsconn.socket = nil
	return false, err
end

local function send_frame( wsconn, opcode, fin, s )
	D("send_frame(%1,%2,%3,<%4 bytes>)", wsconn, opcode, fin, #s)
	local mask = wsconn.options.use_masking
	local t = {}
	local b = bit.bor( fin and 0x80 or 0, opcode )
	table.insert( t, string.char(b) )
	if #s < 126 then
		table.insert( t, string.char(#s + ( mask and 128 or 0)) )
	elseif #s < 65536 then
		table.insert( t, string.char(126 + ( mask and 128 or 0)) ) -- indicate 16-bit length follows
		table.insert( t, string.char( math.floor( #s / 256 ) ) )
		table.insert( t, string.char( #s % 256 ) )
	else
		-- We don't currently support 64-bit frame length (caller shouldn't be trying, either)
		error("Super-long frame length not implemented")
	end
	local frame
	if mask then
		-- Generate mask and append to frame.
		local mb = { 0,0,0,0 }
		for k=1,4 do
			mb[k] = math.random(0,255)
			table.insert( t, string.char( mb[k] ) )
		end
		D("send_frame() mask bytes %1", string.format( "%02x %02x %02x %02x", mb[1], mb[2], mb[3], mb[4] ) )
		-- Apply mask to data and append.
		for k=1,#s do
			table.insert( t, string.char( bit.bxor( string.byte( s, k ), mb[((k-1)%4)+1] ) ) )
		end
		frame = table.concat( t, "" )
	else
		-- No masking, just concatenate string as we got it (not RFC for client).
		frame = table.concat( t, "" ) .. s
	end
	t = nil -- luacheck: ignore 311
	D("send_frame() sending frame of %1 bytes for %2", #frame, s)
	wsconn.socket:settimeout( 5, "b" )
	wsconn.socket:settimeout( 5, "r" )
	-- ??? need retry while nb < payload length
	while #frame > 0 do
		local nb,err = wsconn.socket:send( frame )
		if not nb then return false, "send error: "..tostring(err) end
		frame = frame:sub( nb + 1 )
	end
	return true
end

-- Send WebSocket message (opcode and payload). The payload can be an LTN12 source,
-- in which case each chunk from the source is sent as a fragment.
function wssend( wsconn, opcode, s )
	D("wssend(%1,%2,%3)", wsconn, opcode, s)
	if not ( wsconn and wsconn.connected ) then return false, "not connected" end
	if wsconn.closing then return false, "closing" end

	if opcode == 0x08 then
		wsconn.closing = true -- sending close frame
	end

	if type(s) == "function" then
		-- A function as data is assumed to be an LTN12 source
		local chunk, err = s() -- get first chunk
		while chunk do
			local next_chunk, nerr = s() -- get another
			local fin = next_chunk == nil -- no more?
			assert( #chunk < 65536, "LTN12 source returned excessively long chunk" )
			send_frame( wsconn, opcode, fin, chunk ) -- send last
			opcode = 0 -- continuations from here out
			chunk,err = next_chunk, nerr -- new becomes last
		end
		return err == nil, err
	end

	-- Send as string buffer
	if type(s) ~= "string" then s = tostring(s) end
	if #s < 65535 then
		return send_frame( wsconn, opcode, true, s ) -- single frame
	else
		-- Long goes out in 64K-1 chunks; op + noFIN first, op0 + noFIN continuing, op0+FIN final.
		repeat
			local chunk = s:sub( 1, 65535 )
			s = s:sub( 65536 )
			local fin = #s == 0 -- fin when out of data (last chunk)
			if not send_frame( wsconn, opcode, fin, chunk ) then
				return false, "send error"
			end
			opcode = 0 -- all following fragments go as continuation
		until #s == 0
	end
	return true
end

-- Disconnect websocket interface, if connected (safe to call any time)
function wsclose( wsconn )
	D("wsclose(%1)", wsconn)
	if wsconn then
		-- This is not in keeping with the RFC, but may be as good as we can reliably do.
		-- We don't wait for a close reply, just send it and shut down.
		if wsconn.socket and wsconn.connected and not wsconn.closing then
			wsconn.closing = true
			wssend( wsconn, 0x08, "" )
		end
		if wsconn.socket then
			pcall( function() wsconn.socket:close() end ) -- crash-resistant
			wsconn.socket = nil
		end
		wsconn.connected = false
	end
end

-- Handle a control frame. Caller is given option first.
local function handle_control_frame( wsconn, opcode, data )
	D("handle_control_frame(%1,%2,%3)", wsconn, opcode, data )
	if wsconn.options.control_handler and
		false == wsconn.options.control_handler( wsconn, opcode, data, unpack(wsconn.options.handler_args or {}) ) then
		-- If custom handler returns exactly boolean false, don't do default actions
		return
	end
	if opcode == 0x08 then -- close
		if not wsconn.closing then
			wsconn.closing = true
			wssend( wsconn, 0x08, "" )
		end
		-- Notify
		pcall( wsconn.msghandler, wsconn, false, "receiver error: closed",
			unpack(wsconn.options.handler_args or {}) )
	elseif opcode == 0x09 then
		-- Ping. Reply with pong.
		wssend( wsconn, 0x0a, "" )
	elseif opcode == 0x0a then
		-- Pong; no action
	else
		-- Other unsupported control frame
	end
end

-- Take incoming fragment and accumulate into message (or, maybe it's the whole
-- message, or a control message). Dispatch complete and control messages.
-- ??? best application for LTN12 here?
local function wshandlefragment( fin, op, data, wsconn )
	-- D("wshandlefragment(%1,%2,<%3 bytes>,%4)", fin, op, #data, wsconn)
	if fin then
		-- FIN frame
		wsconn.lastMessage = timenow()
		wsconn.lastPing = timenow() -- any complete frame advances ping timer
		if op >= 8 then
			handle_control_frame( wsconn, op, data )
			return
		elseif (wsconn.msg or "") == "" then
			-- Control frame or FIN on first packet, handle immediately, no copy/buffering
			D("wshandlefragment() fast dispatch %1 byte message for op %2", #data, op)
			return pcall( wsconn.msghandler, wsconn, op, data,
				unpack(wsconn.options.handler_args or {}) )
		end
		-- Completion of continuation; RFC6455 requires final fragment to be op 0 (we tolerate same op)
		if op ~= 0 and op ~= wsconn.msgop then
			return pcall( wsconn.msghandler, wsconn, false, "ws completion error",
				unpack(wsconn.options.handler_args or {}) )
		end
		-- Append to buffer and send message
		local maxn = math.max( 0, wsconn.options.max_payload_size - #wsconn.msg )
		if maxn < #data then
			D("wshandlefragment() buffer overflow, have %1, incoming %2, max %3; message truncated.",
				#wsconn.msg, #data, wsconn.options.max_payload_size)
		end
		if maxn > 0 then wsconn.msg = wsconn.msg .. data:sub(1, maxn) end
		D("wshandlefragment() dispatch %2 byte message for op %1", wsconn.msgop, #wsconn.msg)
		wsconn.lastMessage = timenow()
		local ok, err = pcall( wsconn.msghandler, wsconn, wsconn.msgop, wsconn.msg,
			unpack(wsconn.options.handler_args or {}) )
		if not ok then
			L("wsandlefragment() message handler threw error:", err)
		end
		wsconn.msg = nil
	else
		-- No FIN
		if (wsconn.msg or "") == "" then
			-- First fragment, also save op (first determines for all)
			-- D("wshandlefragment() no fin, first fragment")
			wsconn.msgop = op
			wsconn.msg = data
		else
			-- D("wshandlefragment() no fin, additional fragment")
			-- RFC6455 requires op on continuations to be 0.
			if op ~= 0 then return pcall( wsconn.msghandler, wsconn, false,
				"ws continuation error", unpack(wsconn.options.handler_args or {}) ) end
			local maxn = math.max( 0, wsconn.options.max_payload_size - #wsconn.msg )
			if maxn < #data then
				L("wshandlefragment() buffer overflow, have %1, incoming %2, max %3; message truncated",
					#wsconn.msg, #data, wsconn.options.max_payload_size)
			end
			if maxn > 0 then wsconn.msg = wsconn.msg .. data:sub(1, maxn) end
		end
	end
end

-- Unmask buffered data fragments
local function unmask( fragt, maskt )
	local r = {}
	for _,d in ipairs( fragt or {} ) do
		for l=1,#d do
			local k = (#r % 4) + 1 -- convenient
			table.insert( r, string.char( bit.bxor( string.byte( d, l ), maskt[k] ) ) )
		end
	end
	return table.concat( r, "" )
end

-- Handle a block of data. The block does not need to contain an entire message
-- (or fragment). A series of blocks as small as one byte can be passed and the
-- message accumulated properly within the protocol.
function wshandleincoming( data, wsconn )
	D("wshandleincoming(<%1 bytes>,%2) in state %3", #data, wsconn, wsconn.readstate)
	local state = wsconn
	local ix = 1
	while ix <= #data do
		local b = data:byte( ix )
		-- D("wshandleincoming() at %1/%2 byte %3 (%4) state %5", ix, #data, b, string.format("%02X", b), state.readstate)
		if state.readstate == STATE_READDATA then
			-- ??? WHAT ABOUT UNMASKING???
			-- Performance: this at top; table > string concatenation; handle more than one byte, too.
			-- D("wshandleincoming() read state, %1 bytes pending, %2 to go in message", #data, state.flen)
			local nlast = math.min( ix + state.flen - 1, #data )
			-- D("wshandleincoming() nlast is %1, length accepting %2", nlast, nlast-ix+1)
			table.insert( state.frag, data:sub( ix, nlast ) )
			state.flen = state.flen - ( nlast - ix + 1 )
			if debug_mode and state.flen % 500 == 0 then D("wshandleincoming() accepted, now %1 bytes to go", state.flen) end
			if state.flen <= 0 then
				local delta = math.max( timenow() - state.start, 0.001 )
				D("wshandleincoming() message received, %1 bytes in %2 secs, %3 bytes/sec, %4 chunks", state.size, delta, state.size / delta, #state.frag)
				local f = state.masked and unmask( state.frag, state.mask ) or table.concat( state.frag, "" )
				state.frag = nil -- gc eligible
				state.readstate = STATE_START -- ready for next frame
				wshandlefragment( state.fin, state.opcode, f, wsconn )
			end
			ix = nlast
		elseif state.readstate == STATE_START then
			-- D("wshandleincoming() start at %1 byte %2", ix, string.format("%02X", b))
			state.fin = bit.band( b, 128 ) > 0
			state.opcode = bit.band( b, 15 )
			state.flen = 0 -- remaining data bytes to receive
			state.size = 0 -- keep track of original size
			state.masked = nil
			state.mask = nil
			state.masklen = nil
			state.frag = {}
			state.readstate = STATE_READLEN1
			state.start = timenow()
			-- D("wshandleincoming() start of frame, opcode %1 fin %2", state.opcode, state.fin)
		elseif state.readstate == STATE_READLEN1 then
			state.masked = bit.band( b, 128 ) > 0
			state.flen = bit.band( b, 127 )
			if state.flen == 126 then
				-- Payload length in 16 bit integer that follows, read 2 bytes (big endian)
				state.readstate = STATE_READLEN161
			elseif state.flen == 127 then
				-- 64-bit length (unsupported, ignore message)
				L{level=2,msg="Ignoring 64-bit length frame, not supported"}
				state.readstate = STATE_SYNC
			else
				-- 7-bit payload length
				-- D("wshandleincoming() short length, expecting %1 byte payload", state.flen)
				state.size = state.flen
				if state.flen > 0 then
					-- Transition to reading data.
					state.readstate = state.masked and STATE_READMASK or STATE_READDATA
				else
					-- No data with this opcode, process and return to start state.
					wshandlefragment( state.fin, state.opcode, "", wsconn )
					state.readstate = STATE_START
				end
			end
			-- D("wshandleincoming() opcode %1 len %2 next state %3", state.opcode, state.flen, state.readstate)
		elseif state.readstate == STATE_READLEN161 then
			state.flen = b * 256
			state.readstate = STATE_READLEN162
		elseif state.readstate == STATE_READLEN162 then
			state.flen = state.flen + b
			state.size = state.flen
			state.readstate = state.masked and STATE_READMASK or STATE_READDATA
			-- D("wshandleincoming() finished 16-bit length read, expecting %1 byte payload", state.size)
		elseif state.readstate == STATE_READMASK then
			-- ??? According to RFC6455, we MUST error and close for masked data from server [5.1]
			if not state.mask then
				state.mask = { b }
			else
				table.insert( state.mask, b )
				if #state.mask >= 4 then
					state.readstate = STATE_READDATA
				end
			end
			-- D("wshandleincoming() received %1 mask bytes, now %2", state.masklen, state.mask)
		elseif state.readstate == STATE_SYNC then
			return pcall( state.msghandler, wsconn, false, "lost sync", unpack(wsconn.options.handler_args or {}) )
		else
			assert(false, "Invalid state in wshandleincoming: "..tostring(state.readstate))
		end
		ix = ix + 1
	end
	D("wshandleincoming() ending state is %1", state.readstate)
end

-- Receiver task. Use non-blocking read. Returns nil,err on error, otherwise true/false is the
-- receiver believes there may immediately be more data to process.
function wsreceive( wsconn )
	D("wsreceive(%1)", wsconn)
	if not ( wsconn and wsconn.connected ) then return nil, "not connected" end
	wsconn.socket:settimeout( 0, "b" )
	wsconn.socket:settimeout( 0, "r" )
	--[[ PHR 20140: Make sure we provide a number of bytes. Failing to do so apparently kicks-in the
	                special handling of special characters, including 0 bytes, CR, LF, etc. We want
	                the available data completely unmolested.
	--]]
	local nb,err,bb = wsconn.socket:receive( wsconn.options.receive_chunk_size or CHUNKSIZE )
	if nb == nil then
		if err == "timeout" or err == "wantread" then
			if bb and #bb > 0 then
				D("wsreceive() %1; handling partial result %2 bytes", err, #bb)
				wshandleincoming( bb, wsconn )
				return false, #bb -- timeout, say no more data
			elseif wsconn.options.receive_timeout > 0 and
				( timenow() - wsconn.lastMessage ) > wsconn.options.receive_timeout then
				pcall( wsconn.msghandler, wsconn, false, "message timeout",
					unpack(wsconn.options.handler_args or {}) )
				return nil, "message timeout"
			end
			return false, 0 -- not error, no data was handled
		end
		-- ??? error
		pcall( wsconn.msghandler, wsconn, false, "receiver error: "..err,
			unpack(wsconn.options.handler_args or {}) )
		return nil, err
	end
	D("wsreceive() handling %1 bytes", #nb)
	if #nb > 0 then
		wshandleincoming( nb, wsconn )
	end
	return #nb > 0, #nb -- data handled, maybe more?
end

-- Reset receiver state. Brutal resync; may or may not be usable, but worth having the option.
function wsreset( wsconn )
	D("wsreset(%1)", wsconn)
	if wsconn then
		wsconn.msg = nil -- gc eligible
		wsconn.frag = nil -- gc eligible
		wsconn.readstate = STATE_START -- ready for next frame
	end
end

function wslastping( wsconn )
	D("wslastping(%1)", wsconn)
	return wsconn and wsconn.lastPing or 0
end

return {
  version = _VERSION,
  wsopen = wsopen, 
  wslastping = wslastping, 
  wsreset = wsreset, 
  wsreceive = wsreceive, 
  wshandleincoming = wshandleincoming, 
  wsclose = wsclose, 
  wssend = wssend, 
}