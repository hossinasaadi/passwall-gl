-- PassWall GL.iNet fork: argument rules for GL's RPC layer.
--
-- This is free software, licensed under the GNU General Public License v3.
--
-- GL's oui-rpc checks every string argument against '^[%w%.%s%-_:#/]-$'
-- unless this file gives a rule for it (see /usr/lib/lua/oui/rpc.lua).
-- Share links and subscription URLs always contain characters outside that
-- set (? & = @ %), so the methods that take them get their own rule here.
-- Rules are per method, then per argument; anything not listed keeps GL's
-- default. The backend validates every value again before using it.

-- Printable text of bounded size: no NUL or other control characters
-- except tab and newlines.
local function text(max)
	return function(v)
		return #v <= max and not v:find("[%z\1-\8\11\12\14-\31\127]")
	end
end

return {
	add_links = { links = text(1024 * 1024) },
}
