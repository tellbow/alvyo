#!/usr/bin/env python3
"""Lists the licenses of the Go modules in the binaries, the installed npm
packages and the app's Dart packages, and fails on one that is neither
permissive nor reviewed below (docs/licensing.md). Run from the repository
root after `bun install` and `flutter pub get`: make licenses."""

import collections
import json
import os
import subprocess
import sys

PERMISSIVE = ("MIT", "BSD", "Apache-2.0", "ISC", "0BSD", "CC0", "Unlicense", "BlueOak-1.0.0")

# Reviewed: compatible with AGPL-3.0, or not part of what is distributed.
REVIEWED = {
    "github.com/golang/freetype": "FreeType License (or GPL-2.0+): credited in NOTICE",
    "lightningcss": "MPL-2.0, build tool only",
    "lightningcss-darwin-arm64": "MPL-2.0, build tool only",
    "argparse": "Python-2.0, dev tool only",
    "@lix-js/sdk-darwin-arm64": "no license field, inlang dev tool only",
    "@fontsource-variable/figtree": "OFL-1.1, the font's license",
    "@fontsource-variable/bricolage-grotesque": "OFL-1.1, the font's license",
    "dbus": "MPL-2.0, Linux only, not in the iOS app",
    "geoclue": "MPL-2.0, Linux only, not in the iOS app",
    "gsettings": "MPL-2.0, Linux only, not in the iOS app",
}

TEXTS = [
    ("GNU AFFERO", "AGPL"), ("GNU LESSER", "LGPL"), ("GNU GENERAL", "GPL"),
    ("Mozilla Public", "MPL-2.0"), ("Apache License", "Apache-2.0"),
    ("Redistribution and use", "BSD"), ("Permission is hereby granted", "MIT"),
    ("Permission to use, copy, modify", "ISC"),
]


def from_text(d):
    """The license of a package directory, from its license file."""
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if f.upper().startswith(("LICENSE", "LICENCE", "COPYING")):
            text = " ".join(open(os.path.join(d, f), errors="ignore").read(4000).split())
            return next((name for marker, name in TEXTS if marker in text), "unknown")
    return "none"


def go():
    out = subprocess.run(
        ["go", "list", "-deps", "-f", "{{with .Module}}{{.Path}} {{.Dir}}{{end}}", "./cmd/...", "../swiss/..."],
        cwd="api", capture_output=True, text=True, check=True).stdout
    mods = dict(line.split(" ", 1) for line in set(out.splitlines()) if " " in line)
    return {p: from_text(d) for p, d in mods.items() if not p.startswith("github.com/tellbow/")}


def npm():
    found = {}
    for root, dirs, files in os.walk("web/node_modules"):
        if "package.json" in files and root.count("node_modules") == 1:
            p = json.load(open(os.path.join(root, "package.json")))
            if "name" in p and "version" in p:
                lic = p.get("license") or p.get("licenses") or "none"
                if isinstance(lic, dict):
                    lic = lic.get("type", "none")
                if isinstance(lic, list):
                    lic = " OR ".join(x.get("type", "?") if isinstance(x, dict) else str(x) for x in lic)
                found[p["name"]] = lic
            dirs[:] = [d for d in dirs if d != "node_modules"]
    return found


def dart():
    cfg = json.load(open("app/.dart_tool/package_config.json"))
    return {p["name"]: from_text(p["rootUri"].removeprefix("file://"))
            for p in cfg["packages"]
            if p["rootUri"].startswith("file://") and "/flutter/packages/" not in p["rootUri"] and p["name"] != "alvyo"}


def main():
    bad = []
    for name, packages in (("Go", go()), ("npm", npm()), ("Dart", dart())):
        counts = collections.Counter(packages.values())
        print(f"{name}: {len(packages)} packages:", ", ".join(f"{n} {lic}" for lic, n in counts.most_common()))
        for pkg, lic in sorted(packages.items()):
            if pkg in REVIEWED:
                print(f"  reviewed: {pkg} ({lic}): {REVIEWED[pkg]}")
            elif not any(ok in str(lic) for ok in PERMISSIVE):
                bad.append(f"{name} {pkg}: {lic}")
    for b in bad:
        print("NOT REVIEWED:", b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
