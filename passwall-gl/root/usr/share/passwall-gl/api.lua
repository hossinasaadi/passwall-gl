#!/usr/bin/lua
-- PassWall GL.iNet fork: backend for the GL admin page.
--
-- This is free software, licensed under the GNU General Public License v3.
--
-- Runs under the same Lua 5.1 environment as PassWall itself, so it can reuse
-- PassWall's API and its LuCI controller instead of reimplementing them.
-- The oui-httpd RPC shim (/usr/lib/oui-httpd/rpc/passwall) calls it as:
--   lua /usr/share/passwall-gl/api.lua <method> <request.json> <answer.json>
-- and it writes exactly one JSON object to answer.json: {"code":0,"data":...}
-- on success, {"code":-1,"error":"..."} on failure. Without answer.json it
-- prints the object instead, which is handy from a shell.

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
		if type(v) == "number" then v = tostring(v) end
		for _, c in ipairs(choices) do
			if v == c then return v end
		end
		fail("invalid value")
	end
end

-- Printable text of bounded length: no control characters except tab and
-- newlines. With trim, surrounding whitespace is dropped.
local function check_text(max, trim)
	return function(v)
		if type(v) ~= "string" or #v > max or v:find("[%z\1-\8\11\12\14-\31\127]") then
			fail("invalid text")
		end
		return trim and api.trim(v) or v
	end
end

-- A list of items, each checked with check_item; empty items are dropped.
local function check_list(check_item, max_items)
	return function(v)
		if type(v) ~= "table" or #v > max_items then fail("invalid list") end
		local out = {}
		for _, item in ipairs(v) do
			item = check_item(item)
			if item ~= "" then out[#out + 1] = item end
		end
		return out
	end
end

local function check_hhmm(v)
	local h, m = tostring(v):match("^(%d%d?):(%d%d)$")
	if not h or tonumber(h) > 23 or tonumber(m) > 59 then fail("invalid time") end
	return v
end

local function numbers(from, to)
	local t = {}
	for i = from, to do t[#t + 1] = tostring(i) end
	return t
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

local function check_sub_url(v)
	-- Like PassWall's form: whitespace inside the URL is dropped.
	v = check_text(4096)(v):gsub("%s+", "")
	if not v:match("^https?://[^/]") then fail("The subscription URL must start with http:// or https://") end
	return v
end

local filter_list = check_list(check_text(256, true), 200)

-- Per-subscription options the GL page may set (PassWall's node_subscribe_config
-- page). Core-type options are left out: Xray is the only core.
local subscription_options = {
	remark = check_text(64, true),
	url = check_sub_url,
	update_week_mode = check_oneof({ "", "0", "1", "2", "3", "4", "5", "6", "7", "8" }),
	update_time_mode = check_hhmm,
	update_interval_mode = check_oneof(numbers(1, 24)),
	boot_update = check_flag,
	filter_keyword_mode = check_oneof(numbers(0, 5)),
	filter_discard_list = filter_list,
	filter_keep_list = filter_list,
	user_agent = check_text(512, true),
	access_mode = check_oneof({ "", "direct", "proxy" }),
	domain_strategy = check_oneof({ "", "UseIPv4v6", "UseIPv6v4", "UseIPv4", "UseIPv6" }),
	allowInsecure = check_flag,
}

-- Changing these rewrites PassWall's update schedule, which only happens when
-- the service (re)starts.
local schedule_options = { update_week_mode = true, update_time_mode = true, update_interval_mode = true }

-- Global subscription filter (PassWall's node_subscribe page).
local subscribe_filter_options = {
	filter_keyword_mode = check_oneof(numbers(0, 4)),
	filter_discard_list = filter_list,
	filter_keep_list = filter_list,
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

function methods.get_status()
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

function methods.get_nodes()
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

-- Counted with the uci tool rather than this process's cursor, because
-- subscribe.lua changes the config from a separate process.
local function count_nodes()
	return tonumber(luci.sys.exec("uci -q show passwall | grep -c '=nodes$'")) or 0
end

function methods.add_links(args)
	local links = args.links
	if type(links) ~= "string" or links == "" then fail("no links") end
	if #links > 1024 * 1024 then fail("too much text") end
	local lines, urls = 0, 0
	for line in links:gmatch("[^\r\n]+") do
		if line:match("%S") then
			lines = lines + 1
			if line:match("^%s*https?://") then urls = urls + 1 end
		end
	end
	if lines > 0 and urls == lines then
		fail("That is a subscription address, not a share link. Add it on the Subscriptions tab.")
	end
	local before = count_nodes()
	run_ctl("link_add_node", {
		chunk = links, chunk_index = 0, total_chunks = 1, group = check_group(args.group)
	})
	local added = count_nodes() - before
	if added <= 0 then
		fail("No nodes found. Paste share links such as vless://… or vmess://…, one per line.")
	end
	return { added = added }
end

function methods.delete_nodes(args)
	local ids = type(args.ids) == "table" and args.ids or fail("missing ids")
	for i, id in ipairs(ids) do ids[i] = check_id(id) end
	if #ids == 0 then return true end
	run_ctl("delete_select_nodes", { ids = table.concat(ids, ",") })
	return true
end

-- Subscriptions

local SUBSCRIBE = "lua /usr/share/passwall/subscribe.lua"

local function check_subscription(v)
	check_id(v)
	if (uci_get(v) or {})[".type"] ~= "subscribe_list" then fail("unknown subscription") end
	return v
end

-- A subscription's nodes are the ones whose group is its remark (any case),
-- so renaming it moves them along, as PassWall's own form does.
local function rename_group(old, new)
	local changes = {}
	api.uci_foreach_c("nodes", function(e)
		if e.group and e.group:lower() == old:lower() then
			changes[#changes + 1] = { e[".name"], "group", new }
		end
		if (e.protocol == "_balancing" or e.protocol == "_urltest") and e.node_group then
			local gs = {}
			for g in e.node_group:gmatch("%S+") do
				gs[#gs + 1] = (g == api.UrlEncode(old)) and api.UrlEncode(new) or g
			end
			changes[#changes + 1] = { e[".name"], "node_group", table.concat(gs, " ") }
		end
	end)
	for _, c in ipairs(changes) do uci_set(c[1], c[2], c[3]) end
end

-- Forget each subscription's content hash, so the next update re-reads it
-- with the new settings (PassWall's form does the same on save).
local function forget_subscription_hashes()
	local ids = {}
	api.uci_foreach_c("subscribe_list", function(e) ids[#ids + 1] = e[".name"] end)
	for _, id in ipairs(ids) do api.uci_del_c(id, "md5") end
end

function methods.get_subscriptions()
	local counts = {}
	api.uci_foreach_c("nodes", function(e)
		if e.group and e.group ~= "" then
			local g = e.group:lower()
			counts[g] = (counts[g] or 0) + 1
		end
	end)
	local subs = {}
	api.uci_foreach_c("subscribe_list", function(e)
		local s = {
			id = e[".name"],
			nodes = counts[(e.remark or ""):lower()] or 0,
			rem_traffic = e.rem_traffic,
			expired_date = e.expired_date,
		}
		for k in pairs(subscription_options) do s[k] = e[k] end
		subs[#subs + 1] = s
	end)
	local g = uci_get("@global_subscribe[0]") or {}
	local filter = {}
	for k in pairs(subscribe_filter_options) do filter[k] = g[k] end
	return {
		subscriptions = subs,
		filter = filter,
		-- The [.] keeps pgrep from matching the shell that runs it.
		updating = luci.sys.call("busybox pgrep -f 'passwall/subscribe[.]lua' >/dev/null") == 0,
	}
end

function methods.save_subscription(args)
	local values = type(args.values) == "table" and args.values or fail("missing values")
	local id = (args.id ~= nil and args.id ~= "") and check_subscription(args.id) or nil
	local clean = {}
	for k, v in pairs(values) do
		local check = subscription_options[k] or fail("option not allowed: " .. tostring(k))
		clean[k] = check(v)
	end

	local remark = clean.remark or (id and uci_get(id, "remark")) or ""
	if remark == "" then fail("Give the subscription a name.") end
	local taken = remark:lower() == "default"
	api.uci_foreach_c("subscribe_list", function(e)
		if e[".name"] ~= id and (e.remark or ""):lower() == remark:lower() then taken = true end
	end)
	if taken then fail("That name is already used. Choose another.") end
	if (clean.url or (id and uci_get(id, "url")) or "") == "" then fail("Enter the subscription URL.") end

	local reschedule = false
	for k in pairs(schedule_options) do
		if clean[k] ~= nil and clean[k] ~= (id and uci_get(id, k) or "") then reschedule = true end
	end

	if id then
		local old = uci_get(id, "remark") or ""
		if old ~= remark then rename_group(old, remark) end
	else
		id = "sub_" .. api.gen_random_char(5)
		api.uci:section(api.c_config, "subscribe_list", id)
		-- PassWall's form sets these on every new subscription.
		uci_set(id, "hysteria_up_mbps", "100")
		uci_set(id, "hysteria_down_mbps", "100")
	end
	for k, v in pairs(clean) do uci_set(id, k, v) end
	forget_subscription_hashes()
	uci_save(true)
	if reschedule then restart_if_enabled() end
	return { id = id }
end

function methods.delete_subscription(args)
	local id = check_subscription(args.id)
	local remark = uci_get(id, "remark")
	api.uci_del_c(id)
	uci_save(true)
	-- Nodes go afterwards: subscribe.lua edits the config in its own process.
	if args.keep_nodes ~= true and remark and remark ~= "" then
		run_ctl("subscribe_del_node", { remark = remark })
	end
	return true
end

function methods.update_subscription(args)
	local id = check_subscription(args.id)
	luci.sys.call(SUBSCRIBE .. " start " .. id .. " manual >/dev/null 2>&1 &")
	return true
end

function methods.update_all_subscriptions()
	luci.sys.call(SUBSCRIBE .. " start all manual >/dev/null 2>&1 &")
	return true
end

function methods.delete_subscription_nodes(args)
	local remark = uci_get(check_subscription(args.id), "remark") or fail("subscription has no name")
	run_ctl("subscribe_del_node", { remark = remark })
	return true
end

function methods.delete_all_subscription_nodes()
	run_ctl("subscribe_del_all")
	return true
end

function methods.set_subscribe_filter(args)
	local values = type(args.values) == "table" and args.values or fail("missing values")
	local clean = {}
	for k, v in pairs(values) do
		local check = subscribe_filter_options[k] or fail("option not allowed: " .. tostring(k))
		clean[k] = check(v)
	end
	for k, v in pairs(clean) do uci_set("@global_subscribe[0]", k, v) end
	forget_subscription_hashes()
	uci_save(true)
	return true
end

-- Routing lists (PassWall's Rule List page): plain files, one entry per
-- line, "#" for comments, geosite:/geoip: entries allowed.

local RULES_DIR = "/etc/passwall/rules/"
local rule_lists = {
	direct_host = { kind = "domain", label = "Direct domains" },
	direct_ip = { kind = "ip", label = "Direct IPs" },
	proxy_host = { kind = "domain", label = "Proxy domains" },
	proxy_ip = { kind = "ip", label = "Proxy IPs" },
	block_host = { kind = "domain", label = "Blocked domains" },
	block_ip = { kind = "ip", label = "Blocked IPs" },
}

-- The clean-up PassWall's form does: unusual spaces become plain ones and
-- each line is trimmed.
local function clean_rule_text(text)
	local nbsp = string.char(0xC2, 0xA0)
	local fullwidth_space = string.char(0xE3, 0x80, 0x80)
	return (text:gsub("\t", " "):gsub(nbsp, " "):gsub(fullwidth_space, " ")
		:gsub("\r\n", "\n"):gsub("^%s+", ""):gsub("%s+$", "\n"):gsub("[ \t]*\n[ \t]*", "\n"))
end

local function check_rule_text(name, text)
	local list = rule_lists[name]
	text = clean_rule_text(check_text(512 * 1024)(text))
	if text == "\n" or text == "" then return "" end
	-- End with a newline so line-by-line readers don't skip the last entry.
	if not text:find("\n$") then text = text .. "\n" end
	local n = 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		n = n + 1
		if line ~= "" and not line:find("^#") then
			local ok
			if list.kind == "domain" then
				ok = line:find("^geosite:") or datatypes.hostname(line)
			else
				ok = line:find("^geoip:") or datatypes.ipmask4(line) or datatypes.ipmask6(line)
			end
			if not ok then
				fail(string.format('%s, line %d: "%s" is not a valid %s.', list.label, n, line,
					list.kind == "domain" and "domain" or "IP address or range"))
			end
		end
	end
	return text
end

function methods.get_rules()
	local lists = {}
	for name in pairs(rule_lists) do
		lists[name] = api.fs.readfile(RULES_DIR .. name) or ""
	end
	return { lists = lists }
end

function methods.save_rules(args)
	local lists = type(args.lists) == "table" and args.lists or fail("missing lists")
	local clean = {}
	for name, text in pairs(lists) do
		if not rule_lists[name] then fail("unknown list: " .. tostring(name)) end
		clean[name] = check_rule_text(name, text)
	end
	luci.sys.call("mkdir -p " .. RULES_DIR)
	for name, text in pairs(clean) do
		api.fs.writefile(RULES_DIR .. name, text)
	end
	-- As PassWall's form does: rebuild its address sets on the next start.
	uci_set("@global[0]", "flush_set", "1")
	uci_save(true)
	restart_if_enabled()
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
	local out = jsonc.stringify(t) .. "\n"
	local path = arg[3]
	if not path then
		io.write(out)
		return
	end
	-- Write then rename, so the shim never reads a half-written answer.
	local f = io.open(path .. ".tmp", "w")
	if f then
		f:write(out)
		f:close()
		os.rename(path .. ".tmp", path)
	end
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
