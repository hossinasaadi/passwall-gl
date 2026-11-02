#!/usr/bin/env python3
"""Build development .ipk packages without the OpenWrt SDK.

Both packages are architecture-independent (Lua, shell, JS), so they can be
packed directly. Release builds should still go through the SDK; this is for
quick install-and-test cycles on a router.

  python3 tools/build-ipk.py            # builds both into dist/
  python3 tools/build-ipk.py passwall-gl
  python3 tools/build-ipk.py passwall-gl-full   # everything in one ipk (needs dist/deps)
  python3 tools/build-ipk.py bin --help # pack a prebuilt binary (used by build-deps.sh)

Differences from an SDK build: LuCI translations (.lmo) are not compiled, so
the LuCI pages show English, and dependencies are taken from the Makefiles
as written (Kconfig "select" options are not added).
"""

import argparse
import io
import os
import re
import subprocess
import sys
import tarfile
import tempfile
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


def add_path(tar: tarfile.TarFile, path: Path, rel: str, mtime: int, seen: set) -> int:
    """Add one file or directory at rel, plus any missing parent directories.
    Only the exec bit is taken from disk; owners and other modes are normalised."""
    parts = rel.strip("/").split("/")
    for i in range(1, len(parts) if path.is_file() else len(parts) + 1):
        d = "./" + "/".join(parts[:i])
        if d not in seen:
            seen.add(d)
            info = tarfile.TarInfo(d)
            info.type, info.mode, info.mtime = tarfile.DIRTYPE, 0o755, mtime
            tar.addfile(info)
    if not path.is_file():
        return 0
    name = "./" + rel.strip("/")
    if name in seen:
        raise SystemExit(f"two sources for {name}")
    seen.add(name)
    data = path.read_bytes()
    info = tarfile.TarInfo(name)
    info.size, info.mtime = len(data), mtime
    info.mode = 0o755 if os.access(path, os.X_OK) else 0o644
    tar.addfile(info, io.BytesIO(data))
    return len(data)


def add_tree(tar: tarfile.TarFile, src: Path, dest: str, mtime: int, seen: set) -> int:
    """Add src/* under dest/ in the archive."""
    size = 0
    for path in sorted(src.rglob("*")):
        if path.name == ".DS_Store" or path.name.startswith("._"):
            continue
        rel = dest.rstrip("/") + "/" + path.relative_to(src).as_posix()
        size += add_path(tar, path, rel, mtime, seen)
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


def build_ipk(name, version, depends, section, description, trees=(), files=(), postinst="",
              conffiles=(), arch="all", license="GPL-3.0-only", out=OUT, preinst="",
              control_extra=()):
    mtime = source_date()

    def data(tar):
        seen = set()
        size = sum(add_tree(tar, src, dest, mtime, seen) for src, dest in trees if src.is_dir())
        return size + sum(add_path(tar, src, dest, mtime, seen) for src, dest in files)

    data_tgz, installed = tar_bytes(data, mtime)

    control = "\n".join([
        f"Package: {name}",
        f"Version: {version}",
        "Depends: " + ", ".join(["libc"] + depends),
        f"License: {license}",
        f"Section: {section}",
        f"Architecture: {arch}",
        f"Installed-Size: {installed}",
        *control_extra,
        f"Description: {description}",
    ]) + "\n"

    def ctrl(tar):
        tar.addfile(*member("control", control.encode(), mtime))
        if preinst:
            tar.addfile(*member("preinst", preinst.encode(), mtime, 0o755))
        tar.addfile(*member("postinst", (POSTINST + postinst).encode(), mtime, 0o755))
        tar.addfile(*member("prerm", PRERM.encode(), mtime, 0o755))
        if conffiles:
            tar.addfile(*member("conffiles", ("\n".join(conffiles) + "\n").encode(), mtime))
        return 0

    control_tgz, _ = tar_bytes(ctrl, mtime)

    out.mkdir(parents=True, exist_ok=True)
    dest = out / f"{name}_{version}_{arch}.ipk"
    with tarfile.open(dest, mode="w:gz", format=tarfile.USTAR_FORMAT) as ipk:
        ipk.addfile(*member("debian-binary", b"2.0\n", mtime))
        ipk.addfile(*member("data.tar.gz", data_tgz, mtime))
        ipk.addfile(*member("control.tar.gz", control_tgz, mtime))
    print(f"built {dest.relative_to(REPO) if dest.is_relative_to(REPO) else dest} ({dest.stat().st_size} bytes)")


PASSWALL_CONFFILES = ["/etc/config/passwall", "/etc/config/passwall_server"]


def luci_app_passwall_spec():
    pkg = REPO / "luci-app-passwall"
    mk = pkg / "Makefile"
    return {
        "version": f"{make_var(mk, 'PKG_VERSION')}-{make_var(mk, 'PKG_RELEASE')}",
        "depends": ["luci-base"] + deps_list(make_var(mk, "LUCI_DEPENDS")),
        "title": make_var(mk, "LUCI_TITLE"),
        "trees": [(pkg / "luasrc", "/usr/lib/lua/luci"), (pkg / "htdocs", "/www"), (pkg / "root", "/")],
    }


def passwall_gl_spec():
    pkg = REPO / "passwall-gl"
    view = pkg / "root/www/views/gl-sdk4-ui-passwall.common.js.gz"
    if not view.exists():
        raise SystemExit("page not built: run  npm --prefix passwall-gl/ui run build")
    mk = pkg / "Makefile"
    return {
        "version": f"{make_var(mk, 'PKG_VERSION')}-{make_var(mk, 'PKG_RELEASE')}",
        "trees": [(pkg / "root", "/")],
        "preinst": (pkg / "preinst.sh").read_text(),
        # Appended after the standard postinst, so its own #! line is just a comment.
        "postinst": "\n" + (pkg / "postinst.sh").read_text(),
    }


def luci_app_passwall():
    s = luci_app_passwall_spec()
    build_ipk("luci-app-passwall", s["version"], s["depends"], "luci", s["title"], s["trees"],
              postinst=LUCI_POSTINST, conffiles=PASSWALL_CONFFILES)


def passwall_gl():
    s = passwall_gl_spec()
    build_ipk("passwall-gl", s["version"], ["luci-app-passwall"], "net",
              "PassWall page for the GL.iNet admin panel", s["trees"], preinst=s["preinst"],
              postinst=s["postinst"])


# Packages PassWall's iptables rules need that its Makefile only selects in
# the build config, so no package depends on them. Same list as install.sh.
FEED_EXTRAS = ["iptables-mod-iprange"]


def read_ipk(ipk: Path) -> tuple[dict, bytes]:
    """Return an ipk's control fields and its data.tar.gz."""
    with tarfile.open(ipk) as outer:
        ctrl = outer.extractfile("./control.tar.gz").read()
        data = outer.extractfile("./data.tar.gz").read()
    with tarfile.open(fileobj=io.BytesIO(ctrl)) as t:
        text = t.extractfile("./control").read().decode()
    fields = dict(line.split(": ", 1) for line in text.splitlines() if ": " in line)
    return fields, data


def passwall_gl_full(arch="aarch64_cortex-a53"):
    """Everything in one ipk, for installing from a web page such as LuCI's
    System > Software > Upload Package. Only packages from GL's own feed
    remain as dependencies, and opkg fetches those."""
    parts = sorted((OUT / "deps").glob(f"*_{arch}.ipk")) + sorted((OUT / "deps").glob("*_all.ipk"))
    if not parts:
        raise SystemExit(f"no dependency packages for {arch} in dist/deps; run tools/build-deps.sh first")
    lap, gl = luci_app_passwall_spec(), passwall_gl_spec()
    bundled = {"luci-app-passwall", "passwall-gl"}
    depends = set(lap["depends"])
    trees = lap["trees"] + gl["trees"]
    with tempfile.TemporaryDirectory() as tmp:
        for i, ipk in enumerate(parts):
            fields, data = read_ipk(ipk)
            bundled.add(fields["Package"])
            depends |= {d.split()[0] for d in fields.get("Depends", "").split(",") if d.strip()}
            dest = Path(tmp) / str(i)
            with tarfile.open(fileobj=io.BytesIO(data)) as t:
                t.extractall(dest, filter="data")
            trees.append((dest, "/"))
        build_ipk(
            "passwall-gl-full", gl["version"],
            sorted(depends - bundled - {"libc"}) + FEED_EXTRAS, "net",
            "PassWall for GL.iNet in one package: Xray, PassWall, its helpers, geo data "
            "and the GL admin page",
            # The GL part first: LUCI_POSTINST ends the script with exit 0.
            trees, postinst=gl["postinst"] + LUCI_POSTINST, preinst=gl["preinst"], conffiles=PASSWALL_CONFFILES,
            arch=arch, control_extra=["Conflicts: " + ", ".join(sorted(bundled))],
        )


def prebuilt(argv):
    """Pack already-built files (e.g. a Go binary) as an architecture-specific ipk."""
    p = argparse.ArgumentParser(prog="build-ipk.py bin")
    p.add_argument("--name", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--arch", required=True)
    p.add_argument("--depends", default="", help="comma-separated")
    p.add_argument("--license", required=True)
    p.add_argument("--section", default="net")
    p.add_argument("--description", required=True)
    p.add_argument("--out", type=Path, default=OUT)
    p.add_argument("files", nargs="+", metavar="SRC=DEST")
    a = p.parse_args(argv)
    files = []
    for spec in a.files:
        src, sep, dest = spec.partition("=")
        if not sep or not dest.startswith("/"):
            raise SystemExit(f"expected SRC=/absolute/dest, got {spec}")
        files.append((Path(src), dest))
    build_ipk(a.name, a.version, [d.strip() for d in a.depends.split(",") if d.strip()],
              a.section, a.description, files=files, arch=a.arch, license=a.license, out=a.out)


BUILDERS = {
    "luci-app-passwall": luci_app_passwall,
    "passwall-gl": passwall_gl,
    "passwall-gl-full": passwall_gl_full,
}

if __name__ == "__main__":
    if sys.argv[1:2] == ["bin"]:
        prebuilt(sys.argv[2:])
        sys.exit()
    # The all-in-one package needs tools/build-deps.sh first, so only on request.
    names = sys.argv[1:] or ["luci-app-passwall", "passwall-gl"]
    for n in names:
        if n not in BUILDERS:
            raise SystemExit(f"unknown package {n}; choose from {', '.join(BUILDERS)}")
        BUILDERS[n]()
