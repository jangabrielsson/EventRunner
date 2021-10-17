--[[

Here is a generic implementation of MQTT protocols of all supported versions.

MQTT v3.1.1 documentation (DOCv3.1.1):
	http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/errata01/os/mqtt-v3.1.1-errata01-os-complete.html

MQTT v5.0 documentation (DOCv5.0):
	http://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html

CONVENTIONS:

	* read_func - function to read data from some stream-like object (like network connection).
		We are calling it with one argument: number of bytes to read.
		Use currying/closures to pass other arguments to this function.
		This function should return string of given size on success.
		On failure it should return false/nil and an error message.

]]

-- module table
local protocol = {}

-- load required stuff
local type = type
local error = error
local assert = assert
local require = require
local _VERSION = _VERSION -- lua interpreter version, not a mqtt._VERSION
local tostring = tostring
local setmetatable = setmetatable


local table = require("table")
local tbl_concat = table.concat
local unpack = unpack or table.unpack

local string = require("string")
local str_char = string.char
local str_byte = string.byte
local str_format = string.format

local bit = require("mqtt.bitwrap")
local bor = bit.bor
local band = bit.band
local lshift = bit.lshift
local rshift = bit.rshift

local tools = require("mqtt.tools")
local div = tools.div

-- Create uint8 value data
local function make_uint8(val)
	if val < 0 or val > 0xFF then
		error("value is out of range to encode as uint8: "..tostring(val))
	end
	return str_char(val)
end
protocol.make_uint8 = make_uint8

-- Create uint16 value data
local function make_uint16(val)
	if val < 0 or val > 0xFFFF then
		error("value is out of range to encode as uint16: "..tostring(val))
	end
	return str_char(rshift(val, 8), band(val, 0xFF))
end
protocol.make_uint16 = make_uint16

-- Create uint32 value data
function protocol.make_uint32(val)
	if val < 0 or val > 0xFFFFFFFF then
		error("value is out of range to encode as uint32: "..tostring(val))
	end
	return str_char(rshift(val, 24), band(rshift(val, 16), 0xFF), band(rshift(val, 8), 0xFF), band(val, 0xFF))
end

-- Create UTF-8 string data
-- DOCv3.1.1: 1.5.3 UTF-8 encoded strings
-- DOCv5.0: 1.5.4 UTF-8 Encoded String
function protocol.make_string(str)
	return make_uint16(str:len())..str
end

-- Returns bytes of given integer value encoded as variable length field
-- DOCv3.1.1: 2.2.3 Remaining Length
-- DOCv5.0: 2.1.4 Remaining Length
local function make_var_length(len)
	if len < 0 or len > 268435455 then
		error("value is invalid for encoding as variable length field: "..tostring(len))
	end
	local bytes = {}
	local i = 1
	repeat
		local byte = len % 128
		len = div(len, 128)
		if len > 0 then
			byte = bor(byte, 128)
		end
		bytes[i] = byte
		i = i + 1
	until len <= 0
	return unpack(bytes)
end
protocol.make_var_length = make_var_length

-- Make data for 1-byte property with only 0 or 1 value
function protocol.make_uint8_0_or_1(value)
	if value ~= 0 and value ~= 1 then
		error("expecting 0 or 1 as value")
	end
	return make_uint8(value)
end

-- Make data for 2-byte property with nonzero value check
function protocol.make_uint16_nonzero(value)
	if value == 0 then
		error("expecting nonzero value")
	end
	return make_uint16(value)
end

-- Make data for variable length property with nonzero value check
function protocol.make_var_length_nonzero(value)
	if value == 0 then
		error("expecting nonzero value")
	end
	return make_var_length(value)
end

-- Read string using given read_func function
-- Returns false plus error message on failure
-- Returns parsed string on success
function protocol.parse_string(read_func)
	assert(type(read_func) == "function", "expecting read_func to be a function")
	local len, err = read_func(2)
	if not len then
		return false, "failed to read string length: "..err
	end
	-- convert len string from 2-byte integer
	local byte1, byte2 = str_byte(len, 1, 2)
	len = bor(lshift(byte1, 8), byte2)
	-- and return string if parsed length
	return read_func(len)
end

-- Parse uint8 value using given read_func
local function parse_uint8(read_func)
	assert(type(read_func) == "function", "expecting read_func to be a function")
	local value, err = read_func(1)
	if not value then
		return false, "failed to read 1 byte for uint8: "..err
	end
	return str_byte(value, 1, 1)
end
protocol.parse_uint8 = parse_uint8

-- Parse uint8 value with only 0 or 1 value
function protocol.parse_uint8_0_or_1(read_func)
	local value, err = parse_uint8(read_func)
	if not value then
		return false, err
	end
	if value ~= 0 and value ~= 1 then
		return false, "expecting only 0 or 1 but got: "..value
	end
	return value
end

-- Parse uint16 value using given read_func
local function parse_uint16(read_func)
	assert(type(read_func) == "function", "expecting read_func to be a function")
	local value, err = read_func(2)
	if not value then
		return false, "failed to read 2 byte for uint16: "..err
	end
	local byte1, byte2 = str_byte(value, 1, 2)
	return lshift(byte1, 8) + byte2
end
protocol.parse_uint16 = parse_uint16

-- Parse uint16 non-zero value using given read_func
function protocol.parse_uint16_nonzero(read_func)
	local value, err = parse_uint16(read_func)
	if not value then
		return false, err
	end
	if value == 0 then
		return false, "expecting non-zero value"
	end
	return value
end

-- Parse uint32 value using given read_func
function protocol.parse_uint32(read_func)
	assert(type(read_func) == "function", "expecting read_func to be a function")
	local value, err = read_func(4)
	if not value then
		return false, "failed to read 4 byte for uint32: "..err
	end
	local byte1, byte2, byte3, byte4 = str_byte(value, 1, 4)
	if _VERSION < "Lua 5.3" then
		return byte1 * (2 ^ 24) + lshift(byte2, 16) + lshift(byte3, 8) + byte4
	else
		return lshift(byte1, 24) + lshift(byte2, 16) + lshift(byte3, 8) + byte4
	end
end

-- Max variable length integer value
local max_mult = 128 * 128 * 128

-- Returns variable length field value calling read_func function read data, DOC: 2.2.3 Remaining Length
local function parse_var_length(read_func)
	assert(type(read_func) == "function", "expecting read_func to be a function")
	local mult = 1
	local val = 0
	repeat
		local byte, err = read_func(1)
		if not byte then
			return false, err
		end
		byte = str_byte(byte, 1, 1)
		val = val + band(byte, 127) * mult
		if mult > max_mult then
			return false, "malformed variable length field data"
		end
		mult = mult * 128
	until band(byte, 128) == 0
	return val
end
protocol.parse_var_length = parse_var_length

-- Parse Variable Byte Integer with non-zero constraint
function protocol.parse_var_length_nonzero(read_func)
	local value, err = parse_var_length(read_func)
	if not value then
		return false, err
	end
	if value == 0 then
		return false, "expecting non-zero value"
	end
	return value
end

-- Create fixed packet header data
-- DOCv3.1.1: 2.2 Fixed header
-- DOCv5.0: 2.1.1 Fixed Header
function protocol.make_header(ptype, flags, len)
	local byte1 = bor(lshift(ptype, 4), band(flags, 0x0F))
	return str_char(byte1, make_var_length(len))
end

-- Returns true if given value is a valid QoS
function protocol.check_qos(val)
	return (val == 0) or (val == 1) or (val == 2)
end

-- Returns true if given value is a valid Packet Identifier
-- DOCv3.1.1: 2.3.1 Packet Identifier
-- DOCv5.0: 2.2.1 Packet Identifier
function protocol.check_packet_id(val)
	return val >= 1 and val <= 0xFFFF
end

-- Returns the next Packet Identifier value relative to given current value
-- DOCv3.1.1: 2.3.1 Packet Identifier
-- DOCv5.0: 2.2.1 Packet Identifier
function protocol.next_packet_id(curr)
	if not curr then
		return 1
	end
	assert(type(curr) == "number", "expecting curr to be a number")
	assert(curr >= 1, "expecting curr to be >= 1")
	curr = curr + 1
	if curr > 0xFFFF then
		curr = 1
	end
	return curr
end

-- MQTT protocol fixed header packet types
-- DOCv3.1.1: 2.2.1 MQTT Control Packet type
-- DOCv5.0: 2.1.2 MQTT Control Packet type
local packet_type = {
	CONNECT = 			1,
	CONNACK = 			2,
	PUBLISH = 			3,
	PUBACK = 			4,
	PUBREC = 			5,
	PUBREL = 			6,
	PUBCOMP = 			7,
	SUBSCRIBE = 		8,
	SUBACK = 			9,
	UNSUBSCRIBE = 		10,
	UNSUBACK = 			11,
	PINGREQ = 			12,
	PINGRESP = 			13,
	DISCONNECT = 		14,
	AUTH =				15, -- NOTE: new in MQTTv5.0
	[1] = 				"CONNECT",
	[2] = 				"CONNACK",
	[3] = 				"PUBLISH",
	[4] = 				"PUBACK",
	[5] = 				"PUBREC",
	[6] = 				"PUBREL",
	[7] = 				"PUBCOMP",
	[8] = 				"SUBSCRIBE",
	[9] = 				"SUBACK",
	[10] = 				"UNSUBSCRIBE",
	[11] = 				"UNSUBACK",
	[12] = 				"PINGREQ",
	[13] = 				"PINGRESP",
	[14] = 				"DISCONNECT",
	[15] =				"AUTH", -- NOTE: new in MQTTv5.0
}
protocol.packet_type = packet_type

-- Packet types requiring packet identifier field
-- DOCv3.1.1: 2.3.1 Packet Identifier
-- DOCv5.0: 2.2.1 Packet Identifier
local packets_requiring_packet_id = {
	[packet_type.PUBACK] 		= true,
	[packet_type.PUBREC] 		= true,
	[packet_type.PUBREL] 		= true,
	[packet_type.PUBCOMP] 		= true,
	[packet_type.SUBSCRIBE] 	= true,
	[packet_type.SUBACK] 		= true,
	[packet_type.UNSUBSCRIBE] 	= true,
	[packet_type.UNSUBACK] 		= true,
}

-- CONNACK return code/reason code strings
local connack_rc = {
	-- MQTT v3.1.1 Connect return codes, DOCv3.1.1: 3.2.2.3 Connect Return code
	[0] = "Connection Accepted",
	[1] = "Connection Refused, unacceptable protocol version",
	[2] = "Connection Refused, identifier rejected",
	[3] = "Connection Refused, Server unavailable",
	[4] = "Connection Refused, bad user name or password",
	[5] = "Connection Refused, not authorized",

	-- MQTT v5.0 Connect reason codes, DOCv5.0: 3.2.2.2 Connect Reason Code
	[0x80] = "Unspecified error",
	[0x81] = "Malformed Packet",
	[0x82] = "Protocol Error",
	[0x83] = "Implementation specific error",
	[0x84] = "Unsupported Protocol Version",
	[0x85] = "Client Identifier not valid",
	[0x86] = "Bad User Name or Password",
	[0x87] = "Not authorized",
	[0x88] = "Server unavailable",
	[0x89] = "Server busy",
	[0x8A] = "Banned",
	[0x8C] = "Bad authentication method",
	[0x90] = "Topic Name invalid",
	[0x95] = "Packet too large",
	[0x97] = "Quota exceeded",
	[0x99] = "Payload format invalid",
	[0x9A] = "Retain not supported",
	[0x9B] = "QoS not supported",
	[0x9C] = "Use another server",
	[0x9D] = "Server moved",
	[0x9F] = "Connection rate exceeded",
}
protocol.connack_rc = connack_rc

-- Returns true if Packet Identifier field are required for given packet
function protocol.packet_id_required(args)
	assert(type(args) == "table", "expecting args to be a table")
	assert(type(args.type) == "number", "expecting .type to be a number")
	local ptype = args.type
	if ptype == packet_type.PUBLISH and args.qos and args.qos > 0 then
		return true
	end
	return packets_requiring_packet_id[ptype]
end

-- Metatable for combined data packet, should looks like a string
local combined_packet_mt = {
	-- Convert combined data packet to string
	__tostring = function(self)
		local strings = {}
		for i, part in ipairs(self) do
			strings[i] = tostring(part)
		end
		return tbl_concat(strings)
	end,

	-- Get length of combined data packet
	len = function(self)
		local len = 0
		for _, part in ipairs(self) do
			len = len + part:len()
		end
		return len
	end,

	-- Append part to the end of combined data packet
	append = function(self, part)
		self[#self + 1] = part
	end
}

-- Make combined_packet_mt table works like a class
combined_packet_mt.__index = function(_, key)
	return combined_packet_mt[key]
end

-- Combine several data parts into one
function protocol.combine(...)
	return setmetatable({...}, combined_packet_mt)
end

-- Convert any value to string, respecting strings and tables
local function value_tostring(value)
	local t = type(value)
	if t == "string" then
		return str_format("%q", value)
	elseif t == "table" then
		local res = {}
		for k, v in pairs(value) do
			if type(k) == "number" then
				res[#res + 1] = value_tostring(v)
			else
				if k:match("^[a-zA-Z_][_%w]*$") then
					res[#res + 1] = str_format("%s=%s", k, value_tostring(v))
				else
					res[#res + 1] = str_format("[%q]=%s", k, value_tostring(v))
				end
			end
		end
		return str_format("{%s}", tbl_concat(res, ", "))
	else
		return tostring(value)
	end
end

-- Convert packet to string representation
local function packet_tostring(packet)
	local res = {}
	for k, v in pairs(packet) do
		res[#res + 1] = str_format("%s=%s", k, value_tostring(v))
	end
	return str_format("%s{%s}", tostring(packet_type[packet.type]), tbl_concat(res, ", "))
end
protocol.packet_tostring = packet_tostring

-- Parsed packet metatable
protocol.packet_mt = {
	__tostring = packet_tostring,
}

-- Parsed CONNACK packet metatable
protocol.connack_packet_mt = {
	__tostring = packet_tostring,
}
protocol.connack_packet_mt.__index = protocol.connack_packet_mt

--- Returns reason string for CONNACK packet
-- @treturn string Reason string according packet's rc field
function protocol.connack_packet_mt:reason_string()
	return connack_rc[self.rc]
end

-- export module table
return protocol

-- vim: ts=4 sts=4 sw=4 noet ft=lua
