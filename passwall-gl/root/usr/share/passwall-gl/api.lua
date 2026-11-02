#!/usr/bin/lua
-- PassWall GL.iNet fork: backend for the GL admin page.
--
-- This is free software, licensed under the GNU General Public License v3.
--
-- Runs under the same Lua 5.1 environment as PassWall itself, so it can reuse
-- PassWall's API and its LuCI controller instead of reimplementing them.
-- The oui-httpd RPC shim (/usr/lib/oui-httpd/rpc/passwall) calls it as:
--   lua /usr/share/passwall-gl/api.lua <method> <request.json>
-- and it prints exactly one JSON object: {"code":0,"data":...} on success,
-- {"code":-1,"error":"..."} on failure.

local jsonc = require "luci.jsonc"

-- Stand-ins for LuCI's web layer, so controller functions run outside a
-- LuCI request. They must be in place before the controller is loaded.
local form = {}
local reply

local http = {}
function http.formvalue(name)
	local v = form[name]
	if v == nil then return nil end
	return tostring(v)
end
function http.prepare_content(content_type) reply.content_type = content_type end
function http.write(s) if s then reply.body[#reply.body + 1] = s end end
function http.redirect(url) reply.redirect = url end
function http.status(code, message) reply.status = code end
function http.header(name, value) end

local dispatcher = {}
function dispatcher.build_url(...) return table.concat({ ... }, "/") end
function dispatcher.test_post_security() return true end

package.loaded["luci.http"] = http
package.loaded["luci.dispatcher"] = dispatcher
luci = luci or {}
luci.http = http
luci.dispatcher = dispatcher

local api = require "luci.passwall.api"
local ctl = require "luci.controller.passwall"
local datatypes = require "luci.cbi.datatypes"

local uci_get, uci_set, uci_save = api.uci_get_c, api.uci_set_c, api.uci_save_c

local function fail(msg)
	error({ gl_error = msg }, 0)
end

-- Run a PassWall controller action with the given form values and return
-- what it wrote: a decoded table for JSON replies, otherwise the raw text.
local function run_ctl(name, values)
	form = values or {}
	reply = { body = {} }
	ctl[name]()
	local body = table.concat(reply.body)
	form, reply = {}, nil
	if body ~= "" then
		local decoded = jsonc.parse(body)
		if decoded ~= nil then return decoded end
	end
	return body
end

local function restart_service()
	luci.sys.call("/etc/init.d/passwall restart >/dev/null 2>&1 &")
end

local function restart_if_enabled()
	if uci_get("@global[0]", "enabled") == "1" then restart_service() end
end

-- Input checks. Everything that reaches a shell or UCI goes through these.

local function check_id(v)
	if type(v) ~= "string" or not v:match("^[%w_]+$") or #v > 64 then
		fail("invalid id")
	end
	return v
end

local function check_node(v)
	check_id(v)
	if uci_get(v) == nil or uci_get(v, "remarks") == nil then fail("unknown node") end
	return v
end

local function check_group(v)
	if v == nil or v == "" then return "default" end
	if type(v) ~= "string" or #v > 64 or not v:match("^[%w_%-]+$") then
		fail("group names may only use letters, digits, - and _")
	end
	return v
end

local function check_flag(v)
	if v == true or v == "1" or v == 1 then return "1" end
	if v == false or v == "0" or v == 0 then return "0" end
	fail("invalid flag")
end

local function check_oneof(choices)
	return function(v)
		for _, c in ipairs(choices) do
			if v == c then return v end
		end
		fail("invalid value")
	end
end

-- Main settings the GL page may change, each with its validator. Settings
-- pages add to this table as they are ported.
local global_options = {
	enabled = check_flag,
	node = check_node,
	localhost_proxy = check_flag,
	client_proxy = check_flag,
	tcp_proxy_mode = check_oneof({ "disable", "proxy" }),
	udp_proxy_mode = check_oneof({ "disable", "proxy" }),
	use_direct_list = check_flag,
	use_proxy_list = check_flag,
	use_block_list = check_flag,
	use_gfw_list = check_flag,
	chn_list = check_oneof({ "0", "direct", "proxy" }),
	log_node = check_flag,
}

-- Homepage connectivity probes, mirroring PassWall's status page.
local probe_urls = {
	aliyun = "https://www.aliyun.com/favicon.ico",
	google = "https://www.google.com/generate_204",
	github = "https://github.com/favicon.ico",
	youtube = "https://www.youtube.com/generate_204",
}

local function node_summary(e)
	return {
		id = e[".name"],
		remarks = e.remarks,
		remark = api.get_node_remarks(e),
		type = e.type,
		protocol = e.protocol,
		address = e.address,
		port = e.port,
		group = e.group or "",
		add_mode = e.add_mode,
		special = e.protocol ~= nil and e.protocol:sub(1, 1) == "_",
	}
end

local methods = {}

function methods.status()
	local s = run_ctl("index_status")
	if type(s) ~= "table" then s = {} end
	local node = uci_get("@global[0]", "node")
	local node_cfg = node and uci_get(node)
	local in_use = run_ctl("get_now_use_node")
	s.enabled = uci_get("@global[0]", "enabled") == "1"
	s.node = node
	s.node_remark = node_cfg and api.get_full_node_remarks(node_cfg) or nil
	s.node_in_use = type(in_use) == "table" and in_use.global or nil
	s.version = api.get_version()
	s.xray_version = api.get_app_version("xray")
	return s
end

function methods.get_global()
	local g = uci_get("@global[0]") or {}
	local out = {}
	for k in pairs(global_options) do out[k] = g[k] end
	return out
end

function methods.set_global(args)
	local values = type(args.values) == "table" and args.values or fail("missing values")
	-- Check everything first: with newer LuCI each set is staged right away,
	-- so a failure halfway through would leave a partial change behind.
	local clean = {}
	for k, v in pairs(values) do
		local check = global_options[k] or fail("option not allowed: " .. tostring(k))
		clean[k] = check(v)
	end
	for k, v in pairs(clean) do
		uci_set("@global[0]", k, v)
	end
	uci_save(true)
	if args.apply ~= false then restart_service() end
	return true
end

function methods.list_nodes()
	local nodes = {}
	api.uci_foreach_c("nodes", function(e)
		nodes[#nodes + 1] = node_summary(e)
	end)
	return { nodes = nodes, current = uci_get("@global[0]", "node") }
end

function methods.set_node(args)
	run_ctl("set_node", { type = "@global[0]", config = "node", section = check_node(args.id) })
	restart_if_enabled()
	return true
end

function methods.ping_node(args)
	-- Take the address and port from the saved node, never from the caller.
	local id = check_node(args.id)
	local address, port = uci_get(id, "address"), uci_get(id, "port")
	if not address or not (api.is_ip(address) or datatypes.hostname(address)) then
		fail("node has no usable address")
	end
	port = tonumber(port)
	if not port or port < 1 or port > 65535 then fail("node has no usable port") end
	local mode = args.mode == "icmp" and "icmp" or "tcping"
	local r = run_ctl("ping_node", { address = address, port = tostring(math.floor(port)), type = mode })
	return { ping = type(r) == "table" and tonumber(r.ping) or nil }
end

function methods.urltest_node(args)
	return run_ctl("urltest_node", { id = check_node(args.id) })
end

function methods.connect_status(args)
	local url = probe_urls[args.target] or fail("unknown target")
	return run_ctl("connect_status", { url = url })
end

function methods.add_links(args)
	local links = args.links
	if type(links) ~= "string" or links == "" then fail("no links") end
	if #links > 1024 * 1024 then fail("too much text") end
	run_ctl("link_add_node", {
		chunk = links, chunk_index = 0, total_chunks = 1, group = check_group(args.group)
	})
	return true
end

function methods.delete_nodes(args)
	local ids = type(args.ids) == "table" and args.ids or fail("missing ids")
	for i, id in ipairs(ids) do ids[i] = check_id(id) end
	if #ids == 0 then return true end
	run_ctl("delete_select_nodes", { ids = table.concat(ids, ",") })
	return true
end

function methods.get_log()
	local text = run_ctl("get_log")
	return type(text) == "string" and text or ""
end

function methods.clear_log()
	run_ctl("clear_log")
	return true
end

function methods.restart()
	restart_service()
	return true
end

local function respond(t)
	io.write(jsonc.stringify(t))
	io.write("\n")
end

local function read_request(path)
	if not path then return {} end
	local f = io.open(path, "r")
	if not f then return {} end
	local raw = f:read("*a")
	f:close()
	local t = jsonc.parse(raw or "")
	return type(t) == "table" and t or {}
end

local name = arg[1]
local method = name and methods[name]
local ok, result
if method then
	ok, result = pcall(method, read_request(arg[2]))
else
	ok, result = false, { gl_error = "unknown method" }
end
if ok then
	respond({ code = 0, data = result })
else
	local msg = type(result) == "table" and result.gl_error or tostring(result)
	respond({ code = -1, error = msg })
	os.exit(1)
end
