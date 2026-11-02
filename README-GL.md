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
| `tools/recon.sh`, `tools/recon2.sh` | Read-only router surveys. |
| `tools/build-ipk.py` | Builds dev `.ipk` files without the OpenWrt SDK. |
| `tools/build-deps.sh` | Builds the binary dependencies GL's feed lacks (Docker). |
| `tools/make-bundle.sh` | Packs the end-user bundle: `install.sh` plus every package. |
| `passwall-gl/bundle/install.sh` | Installer that runs on the router. |
| `tools/deploy.sh` | Copies dev builds to a router. |

## Install (end users)

Not released yet. Once it is, there will be one file per router type, for example
`passwall-gl-0.1.0-aarch64_cortex-a53.tar.gz` for the GL-MT3000. From a computer on the router's network:

```sh
cat passwall-gl-0.1.0-aarch64_cortex-a53.tar.gz | ssh root@192.168.8.1 \
  'cd /tmp && tar -xzf - && sh passwall-gl-0.1.0-aarch64_cortex-a53/install.sh'
```

The installer checks the firmware, installs everything in one step and leaves PassWall switched off.
Then open the admin panel and go to **VPN → PassWall**. To remove it:
`ssh root@192.168.8.1 sh /usr/share/passwall-gl/uninstall.sh`.

## Build

```sh
npm --prefix passwall-gl/ui install
npm --prefix passwall-gl/ui run build
python3 tools/build-ipk.py          # writes dist/*.ipk
```

The binary dependencies GL's feed lacks are built by `tools/build-deps.sh` (needs Docker),
from the versions and source hashes pinned in
[openwrt-passwall-packages](https://github.com/Openwrt-Passwall/openwrt-passwall-packages):

```sh
tools/build-deps.sh                 # writes dist/deps/*.ipk
```

## First target: GL-MT3000, firmware 4.8.1

From `tools/recon.sh` on a real router:

| | |
|---|---|
| Base | GL's OpenWrt 21.02 build, feeds `v21.02.3`, kernel 5.4.211 |
| Package architecture | `aarch64_cortex-a53` |
| Firewall | fw3 with iptables 1.8.7 (legacy); no nftables, so PassWall uses `iptables.sh` |
| Lua / LuCI | Lua 5.1, LuCI with `luci-base`, `luci-compat`, `luci-lib-jsonc` already installed |
| GL web stack | nginx; `/rpc` runs `/usr/share/gl-ngx/oui-rpc.lua`, which loads `/usr/lib/oui-httpd/rpc/*` |
| Space | about 150 MB free in `/overlay`, about 280 MB RAM available |

Where each dependency comes from:

| Package | Source | License |
|---|---|---|
| curl, dnsmasq-full, ip-full, ipset, iptables mods, kmod-ipt-tproxy, lua, luci-*, unzip, resolveip, coreutils-timeout | Already on the router | various |
| coreutils-base64, coreutils-nohup, lyaml, haproxy, smartdns | GL's package feed | various |
| xray-core | Built here (GL's feed has 1.5.9, far too old) | MPL-2.0 |
| geoview | Built here | Apache-2.0 |
| chinadns-ng | Built here (upstream static binary) | AGPL-3.0 |
| ipt2socks | Built here | AGPL-3.0 |
| tcping | Built here | GPL-2.0 |
| dns2socks | Built here | BSD-3-Clause |
| microsocks | Built here | MIT |
| v2ray-geoip / v2ray-geosite | Built here (Loyalsoldier data) | CC-BY-SA-4.0 / MIT |

Releases that ship these must carry their licenses, and for the GPL and AGPL ones, an offer of
the source.

### Living with GL's routing

GL marks LAN traffic in `mangle PREROUTING` (`0x8000/0xf000`) and routes on those bits with
`ip rule` priorities 6000 and up. PassWall adds `fwmark 0x50535731 table 999` at priority 999 and
appends its `PSW` chain after GL's `ROUTE_POLICY`, so it sets its full mark last and proxied
traffic reaches Xray first. GL's table 16800 (priority 1) is empty unless a GL VPN uses it.

Tested on 2026-11-02 (GL-MT3000, 4.8.1, one VLESS + HTTPUpgrade + TLS node, default PassWall
settings, ChinaDNS-NG): LAN and router traffic both exit through the node, DNS works, the admin
panel stays reachable, TCP is redirected and UDP goes through TPROXY. **Hardware acceleration
(`mtkhnat`) can stay on.** Xray used about 34 MB of RAM. Not yet tested: GL VPN client policies
running at the same time, access-control rules, IPv6.

GL's RPC layer only accepts string arguments matching `^[%w%.%s%-_:#/]-$` unless the object ships
rules in `/usr/share/gl-validator.d/<object>.lua`. `passwall-gl` ships one for the arguments that
carry links and URLs.

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

Tested on a GL-MT3000: install, the page inside the admin panel, adding a node from a link,
the URL test, and proxying with PassWall switched on (see "Living with GL's routing").
Until the other pages exist, PassWall's own LuCI pages work at
`http://192.168.8.1:8080/cgi-bin/luci/admin/services/passwall`.

## Testing on a router safely

Back up the router first (System → Backup, or `sysupgrade -b /tmp/backup.tar.gz` and copy it off).
PassWall changes the firewall and DNS; leave it switched off until a node is set up.
On the GL-MT3000 PassWall worked with hardware acceleration on. If traffic on another model
doesn't go through the proxy, try switching acceleration off.
