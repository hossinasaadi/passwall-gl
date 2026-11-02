#!/usr/bin/env python3
"""Build development .ipk packages without the OpenWrt SDK.

Both packages are architecture-independent (Lua, shell, JS), so they can be
packed directly. Release builds should still go through the SDK; this is for
quick install-and-test cycles on a router.

  python3 tools/build-ipk.py            # builds both into dist/
  python3 tools/build-ipk.py passwall-gl

Differences from an SDK build: LuCI translations (.lmo) are not compiled, so
the LuCI pages show English, and dependencies are taken from the Makefiles
as written (Kconfig "select" options are not added).
"""

import io
import os
import re
import subprocess
import sys
import tarfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "dist"

# Same scripts OpenWrt's package build generates: run uci-defaults and enable
# init scripts on install, stop and disable them on removal.
POSTINST = """#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_postinst $0 $@
"""
PRERM = """#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_prerm $0 $@
"""
LUCI_POSTINST = """
[ -n "${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	killall -HUP rpcd 2>/dev/null
	exit 0
}
"""


def make_var(makefile: Path, name: str) -> str:
    """Read a (possibly backslash-continued) NAME:=value from a Makefile."""
    text = makefile.read_text()
    m = re.search(rf"^{name}:=((?:.*\\\n)*.*)$", text, re.M)
    if not m:
        raise SystemExit(f"{name} not found in {makefile}")
    return " ".join(m.group(1).replace("\\\n", " ").split())


def deps_list(spec: str) -> list[str]:
    return [d.lstrip("+") for d in spec.split() if d.startswith("+")]


def source_date() -> int:
    try:
        out = subprocess.run(["git", "-C", str(REPO), "log", "-1", "--format=%ct"],
                             capture_output=True, text=True, check=True).stdout
        return int(out.strip())
    except (subprocess.CalledProcessError, ValueError, FileNotFoundError):
        return 0


def add_tree(tar: tarfile.TarFile, src: Path, dest: str, mtime: int, seen: set) -> int:
    """Add src/* under dest/ in the archive, keeping only the exec bit from disk."""
    size = 0
    for path in sorted(src.rglob("*")):
        if path.name == ".DS_Store" or path.name.startswith("._"):
            continue
        rel = dest.rstrip("/") + "/" + path.relative_to(src).as_posix()
        parts = rel.strip("/").split("/")
        for i in range(1, len(parts) if path.is_file() else len(parts) + 1):
            d = "./" + "/".join(parts[:i])
            if d not in seen:
                seen.add(d)
                info = tarfile.TarInfo(d)
                info.type, info.mode, info.mtime = tarfile.DIRTYPE, 0o755, mtime
                tar.addfile(info)
        if path.is_file():
            data = path.read_bytes()
            info = tarfile.TarInfo("./" + rel.strip("/"))
            info.size, info.mtime = len(data), mtime
            info.mode = 0o755 if os.access(path, os.X_OK) else 0o644
            tar.addfile(info, io.BytesIO(data))
            size += len(data)
    return size


def tar_bytes(build, mtime: int) -> tuple[bytes, int]:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz", format=tarfile.USTAR_FORMAT) as tar:
        size = build(tar)
    return buf.getvalue(), size


def member(name: str, data: bytes, mtime: int, mode: int = 0o644) -> tuple[tarfile.TarInfo, io.BytesIO]:
    info = tarfile.TarInfo("./" + name)
    info.size, info.mtime, info.mode = len(data), mtime, mode
    return info, io.BytesIO(data)


def build_ipk(name, version, depends, section, description, trees, postinst="", conffiles=()):
    mtime = source_date()

    def data(tar):
        seen = set()
        return sum(add_tree(tar, src, dest, mtime, seen) for src, dest in trees if src.is_dir())

    data_tgz, installed = tar_bytes(data, mtime)

    control = "\n".join([
        f"Package: {name}",
        f"Version: {version}",
        "Depends: " + ", ".join(["libc"] + depends),
        "License: GPL-3.0-only",
        f"Section: {section}",
        "Architecture: all",
        f"Installed-Size: {installed}",
        f"Description: {description}",
    ]) + "\n"

    def ctrl(tar):
        tar.addfile(*member("control", control.encode(), mtime))
        tar.addfile(*member("postinst", (POSTINST + postinst).encode(), mtime, 0o755))
        tar.addfile(*member("prerm", PRERM.encode(), mtime, 0o755))
        if conffiles:
            tar.addfile(*member("conffiles", ("\n".join(conffiles) + "\n").encode(), mtime))
        return 0

    control_tgz, _ = tar_bytes(ctrl, mtime)

    OUT.mkdir(exist_ok=True)
    dest = OUT / f"{name}_{version}_all.ipk"
    with tarfile.open(dest, mode="w:gz", format=tarfile.USTAR_FORMAT) as ipk:
        ipk.addfile(*member("debian-binary", b"2.0\n", mtime))
        ipk.addfile(*member("data.tar.gz", data_tgz, mtime))
        ipk.addfile(*member("control.tar.gz", control_tgz, mtime))
    print(f"built {dest.relative_to(REPO)} ({dest.stat().st_size} bytes)")


def luci_app_passwall():
    pkg = REPO / "luci-app-passwall"
    mk = pkg / "Makefile"
    version = f"{make_var(mk, 'PKG_VERSION')}-{make_var(mk, 'PKG_RELEASE')}"
    build_ipk(
        "luci-app-passwall", version,
        ["luci-base"] + deps_list(make_var(mk, "LUCI_DEPENDS")),
        "luci", make_var(mk, "LUCI_TITLE"),
        [(pkg / "luasrc", "/usr/lib/lua/luci"), (pkg / "htdocs", "/www"), (pkg / "root", "/")],
        postinst=LUCI_POSTINST,
        conffiles=["/etc/config/passwall", "/etc/config/passwall_server"],
    )


def passwall_gl():
    pkg = REPO / "passwall-gl"
    view = pkg / "root/www/views/gl-sdk4-ui-passwall.common.js.gz"
    if not view.exists():
        raise SystemExit("page not built: run  npm --prefix passwall-gl/ui run build")
    mk = pkg / "Makefile"
    version = f"{make_var(mk, 'PKG_VERSION')}-{make_var(mk, 'PKG_RELEASE')}"
    build_ipk(
        "passwall-gl", version, ["luci-app-passwall"], "net",
        "PassWall page for the GL.iNet admin panel",
        [(pkg / "root", "/")],
    )


BUILDERS = {"luci-app-passwall": luci_app_passwall, "passwall-gl": passwall_gl}

if __name__ == "__main__":
    names = sys.argv[1:] or list(BUILDERS)
    for n in names:
        if n not in BUILDERS:
            raise SystemExit(f"unknown package {n}; choose from {', '.join(BUILDERS)}")
        BUILDERS[n]()
