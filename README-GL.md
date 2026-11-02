# PassWall for GL.iNet (Xray-only fork)

A fork of [Openwrt-Passwall/openwrt-passwall](https://github.com/Openwrt-Passwall/openwrt-passwall)
that runs PassWall as a page inside the GL.iNet 4.x admin panel (under **VPN → PassWall**),
with Xray as the only proxy core. Everything else PassWall does is kept: rules,
shunting, ChinaDNS-NG/SmartDNS, access control, subscriptions, HAProxy and the server side.

Licensed under GPL-3.0, like upstream. Anyone you give a build to must be able to get the source.

## How it fits together

```
GL admin panel ── passwall page (Vue 2, our code)
   │  window.$rpcRequest('call', ['sid', 'passwall', method, args])
   ▼
/usr/lib/oui-httpd/rpc/passwall        thin shim inside GL's web server
   │  lua api.lua <method> <request.json>   (fixed method names, args in a temp file)
   ▼
/usr/share/passwall-gl/api.lua         validates input, then calls PassWall's own
   │                                   LuCI controller with stand-ins for LuCI's web layer
   ▼
PassWall engine (unchanged)            /etc/config/passwall, app.sh, firewall, DNS, Xray
```

The engine and LuCI pages stay as close to upstream as possible so upstream fixes merge cleanly.
The LuCI pages still work if LuCI is installed.

## Layout

| Path | What |
|---|---|
| `luci-app-passwall/` | Upstream PassWall. Only the Makefile differs (Xray-only dependencies). |
| `passwall-gl/` | The GL package: menu entry, RPC shim, backend, built page. |
| `passwall-gl/ui/` | Page source (Vue 2). `npm run dev` opens a preview with mock data. |
| `tools/recon.sh` | Read-only router survey. |
| `tools/build-ipk.py` | Builds dev `.ipk` files without the OpenWrt SDK. |
| `tools/deploy.sh` | Copies dev builds to a router. |

## Build

```sh
npm --prefix passwall-gl/ui install
npm --prefix passwall-gl/ui run build
python3 tools/build-ipk.py          # writes dist/*.ipk
```

Release builds should use the OpenWrt or GL SDK for the target. The binary dependencies
(`xray-core`, `chinadns-ng`, `dns2socks`, `microsocks`, `tcping`, `ipt2socks`, `geoview`, `lyaml`)
come from [openwrt-passwall-packages](https://github.com/Openwrt-Passwall/openwrt-passwall-packages)
and must be built for the router's architecture and OpenWrt version.

## Branches

- `main` mirrors upstream. Don't commit to it.
- `gl-main` is this fork. To take upstream changes:
  `git fetch upstream && git switch main && git merge --ff-only upstream/main && git switch gl-main && git merge main`

## Status

| PassWall page | GL page |
|---|---|
| Basic Settings: switch, node, status, connectivity, proxy modes and lists | Done (DNS, log and SOCKS tabs to do) |
| Node List: list, groups, TCPing/URL test, add from links, use, delete | Done (sorting, QR/export, copy to do) |
| Runtime Logs | Done |
| Node editor (Xray), Subscriptions, Rule Manage, Access Control, Other Settings, App Update, Server-Side, HAProxy, backup/restore | To do |

Tested so far: page and backend logic locally (mock data, stubbed PassWall modules).
Not yet tested on a router.

## Testing on a router safely

Back up the router first (System → Backup, or `sysupgrade -b /tmp/backup.tar.gz` and copy it off).
PassWall changes the firewall and DNS; leave it switched off until a node is set up.
GL's hardware acceleration bypasses the firewall and breaks transparent proxying, so it
must be off while PassWall runs.
