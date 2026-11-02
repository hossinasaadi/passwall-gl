# Developing PassWall for GL.iNet

How the GL port is put together, how to build and release it, and what we learned about GL's
firmware along the way. For installing and using it, see the [README](../.github/README.md).

## How it fits together

```
GL admin panel ── passwall page (Vue 2, passwall-gl/ui)
   │  window.$rpcRequest('call', ['sid', 'passwall', method, args])
   ▼
/usr/lib/oui-httpd/rpc/passwall        thin module inside GL's nginx
   │  lua api.lua <method> <request.json> <answer.json>
   │  (fixed method names; arguments and answer travel in temp files)
   ▼
/usr/share/passwall-gl/api.lua         validates input, then calls PassWall's own LuCI
   │                                   controller with stand-ins for LuCI's web layer
   ▼
PassWall engine (unchanged)            /etc/config/passwall, app.sh, firewall, DNS, Xray
```

The engine and LuCI pages stay as close to upstream as possible so upstream fixes merge cleanly.
The LuCI pages keep working at `http://<router>:8080/cgi-bin/luci/admin/services/passwall`.

## Layout

| Path | What |
|---|---|
| `luci-app-passwall/` | Upstream PassWall. Only the Makefile differs (Xray-only dependencies). |
| `passwall-gl/` | The GL package: menu entry, RPC module, input rules, backend, built page. |
| `passwall-gl/ui/` | Page source (Vue 2). `npm run dev` opens a preview with sample data. |
| `passwall-gl/bundle/install.sh` | Installer that runs on the router (SSH bundle). |
| `tools/build-deps.sh` | Builds the binary dependencies GL's feed lacks (Docker), plus their sources. |
| `tools/make-bundle.sh` | Packs both downloads: the SSH bundle and the one-file `passwall-gl-full` ipk. |
| `tools/build-ipk.py` | Builds `.ipk` files without the OpenWrt SDK (all three packages are prebuilt or scripts). |
| `tools/deploy.sh` | Copies dev builds to a router. |
| `tools/screenshots.sh` | Retakes the README screenshots from the preview (headless Chrome). |
| `tools/recon.sh`, `tools/recon2.sh` | Read-only router surveys. |
| `.github/workflows/gl-release.yml` | Builds everything and publishes a GitHub release for a `v*` tag. |

## Build

```sh
npm --prefix passwall-gl/ui ci
tools/build-deps.sh       # dist/deps/*.ipk and dist/deps/sources/ (needs Docker)
tools/make-bundle.sh      # dist/passwall-gl-<ver>-<arch>.tar.gz and dist/passwall-gl-full_<ver>_<arch>.ipk
```

`build-deps.sh` takes versions and source hashes from
[openwrt-passwall-packages](https://github.com/Openwrt-Passwall/openwrt-passwall-packages) at a
pinned commit. The C helpers, ChinaDNS-NG and the geo data are built with the OpenWrt 21.02.3 SDK,
so they link against the firmware's musl. Xray and geoview are static Go builds.

For quick iterations on a router, `tools/deploy.sh page` copies just the page, RPC module,
input rules and backend, then reloads nginx.

## Releasing

1. Set `PKG_VERSION` in `passwall-gl/Makefile` (and reset `PKG_RELEASE` to 1).
2. Commit, then tag and push: `git tag v0.2.0 && git push origin v0.2.0`.
3. The `GL release` workflow checks that the tag matches `PKG_VERSION`, builds everything and
   publishes a release with the bundle, the one-file ipk, a source archive for the bundled
   third-party packages and `SHA256SUMS`.

Run the workflow by hand (Actions → GL release → Run workflow) to get a test build as a workflow
artifact without publishing anything.

## GL firmware notes

Learned on a GL-MT3000 with firmware 4.8.1:

| | |
|---|---|
| Base | GL's OpenWrt 21.02 build, feeds `v21.02.3`, kernel 5.4.211, `aarch64_cortex-a53` |
| Firewall | fw3 with iptables 1.8.7 (legacy); no nftables, so PassWall uses `iptables.sh` |
| Lua / LuCI | Lua 5.1 and LuCI (`luci-base`, `luci-compat`, `luci-lib-jsonc`) already installed |
| Web stack | nginx with Lua; `/rpc` runs `/usr/share/gl-ngx/oui-rpc.lua`, which loads `/usr/lib/oui-httpd/rpc/<object>` |
| Front end | Vue 2.7.16; pages load from `/www/views/gl-sdk4-ui-<view>.common.js(.gz)`; menu entries in `/usr/share/oui/menu.d/` |
| Space | about 150 MB free in `/overlay`, about 280 MB RAM available |

Things that bit us, so the code works around them:

- **Argument rules.** GL's RPC layer checks every string argument against `^[%w%.%s%-_:#/]-$`
  unless the object ships rules in `/usr/share/gl-validator.d/<object>.lua`. Share links, URLs,
  names and filter keywords need rules there (`passwall-gl/root/usr/share/gl-validator.d/passwall.lua`).
- **No `null` arguments.** Any `null` value fails with -32602 ("Illegal parameter"). The page
  strips them in `src/rpc.js`.
- **Module cache.** nginx workers keep each RPC module loaded. `/etc/init.d/nginx reload` does
  not replace the workers; `nginx -s reload` does, gracefully. The package's postinst runs it.
- **Pipes inside nginx.** Reading a child's output through `io.popen` can come back short. The
  RPC module runs the backend with `os.execute` and reads its answer from a file.
- **Call logging.** GL logs every call whose method name lacks `get`, `load` or `check`, so
  anything the page polls is named `get_…`.
- **Empty lists.** PassWall's JSON encoder writes an empty Lua table as `{}`. The page treats
  every list with `asList()`.

### Dependencies

| Package | Source | License |
|---|---|---|
| curl, dnsmasq-full, ip-full, ipset, iptables mods, kmod-ipt-tproxy, lua, luci-*, unzip, resolveip, coreutils-timeout | Already on the router | various |
| coreutils-base64, coreutils-nohup, lyaml, iptables-mod-iprange, haproxy, smartdns | GL's package feed | various |
| xray-core | Built here (GL's feed has 1.5.9, far too old) | MPL-2.0 |
| geoview | Built here | Apache-2.0 |
| chinadns-ng | Built here (upstream static binary) | AGPL-3.0 |
| ipt2socks | Built here | AGPL-3.0 |
| tcping | Built here | GPL-2.0 |
| dns2socks | Built here | BSD-3-Clause |
| microsocks | Built here | MIT |
| v2ray-geoip / v2ray-geosite | Built here (Loyalsoldier data) | CC-BY-SA-4.0 / MIT |

Releases carry these licenses in `SOURCES.txt`, and the sources of the bundled third-party
packages as a separate release file, for the GPL and AGPL ones in particular.

### Living with GL's routing

GL marks LAN traffic in `mangle PREROUTING` (`0x8000/0xf000`) and routes on those bits with
`ip rule` priorities 6000 and up. PassWall adds `fwmark 0x50535731 table 999` at priority 999 and
appends its `PSW` chain after GL's `ROUTE_POLICY`, so it sets its full mark last and proxied
traffic reaches Xray first. GL's table 16800 (priority 1) is empty unless a GL VPN uses it.

Tested on 2026-11-02 (one VLESS + HTTPUpgrade + TLS node, default settings, ChinaDNS-NG): LAN and
router traffic both exit through the node, DNS works, the admin panel stays reachable, TCP is
redirected and UDP goes through TPROXY. Hardware acceleration (`mtkhnat`) can stay on. Xray used
about 34 MB of RAM. Not yet tested: GL VPN client policies at the same time, access control, IPv6.

## Branches

- `main` mirrors upstream. Don't commit to it.
- `gl-main` is this fork. To take upstream changes:
  `git fetch upstream && git switch main && git merge --ff-only upstream/main && git switch gl-main && git merge main`

Upstream's own workflows stay in `.github/workflows/`. On GitHub, "Close stale issues and PRs"
runs daily; disable it under Actions if this repository uses its own issue tracker.

## Testing on a router safely

Back up the router first (System → Backup, or `sysupgrade -b /tmp/backup.tar.gz` and copy it off).
PassWall changes the firewall and DNS; leave it switched off until a node is set up.
