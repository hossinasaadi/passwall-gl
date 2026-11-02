-- PassWall GL.iNet fork: argument rules for GL's RPC layer.
--
-- This is free software, licensed under the GNU General Public License v3.
--
-- GL's oui-rpc checks every string argument against '^[%w%.%s%-_:#/]-$'
-- unless this file gives a rule for it (see /usr/lib/lua/oui/rpc.lua).
-- Share links, subscription URLs, names and filter keywords often contain
-- characters outside that set (? & = @ % and non-ASCII text), so those
-- arguments get their own rule here. Rules are per method, then per
-- argument; a function rule receives the value, which for a list is the
-- whole table. Anything not listed keeps GL's default. The backend
-- validates every value again before using it.

-- Printable text of bounded size: no NUL or other control characters
-- except tab and newlines.
local function text(max)
	return function(v)
		return type(v) == "string" and #v <= max and not v:find("[%z\1-\8\11\12\14-\31\127]")
	end
end

local function list_of(check, max_items)
	return function(v)
		if type(v) ~= "table" or #v > max_items then return false end
		for _, item in ipairs(v) do
			if not check(item) then return false end
		end
		return true
	end
end

local keywords = list_of(text(256), 200)

return {
	add_links = { links = text(1024 * 1024) },
	save_subscription = {
		values = {
			remark = text(64),
			url = text(4096),
			user_agent = text(512),
			filter_discard_list = keywords,
			filter_keep_list = keywords,
		},
	},
	set_subscribe_filter = {
		values = { filter_discard_list = keywords, filter_keep_list = keywords },
	},
	save_rules = {
		lists = {
			direct_host = text(512 * 1024), direct_ip = text(512 * 1024),
			proxy_host = text(512 * 1024), proxy_ip = text(512 * 1024),
			block_host = text(512 * 1024), block_ip = text(512 * 1024),
		},
	},
}
