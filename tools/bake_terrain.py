"""Run the pinned offline terrain baker against the supported local client.

This launcher is MIT licensed. Downloaded SPF tools and their generated navigation
retain their separate GPL-3.0-or-later licence; this does not install their output.
"""

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RECIPE = ROOT / "docs/TERRAIN_RECIPE.json"
PATCHES = ("trinitycore-client.patch", "trinitycore.patch", "trinitycore-nav.patch")


def verify_files(root, hashes):
    for name, expected in hashes.items():
        path = root / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Pinned file missing or changed: {path}")


def check_client(wow, output, recipe):
    wow, output = wow.resolve(), output.resolve()
    if output == wow or wow in output.parents or output in wow.parents:
        raise ValueError("Output must be separate from the game installation")
    lines = (wow / ".build.info").read_text().splitlines()
    if not lines:
        raise ValueError("Client .build.info is empty")
    columns = [c.split("!")[0] for c in lines[0].split("|")]
    if any(columns.count(name) != 1 for name in ("Product", "Active", "Version")):
        raise ValueError("Client .build.info needs unique Product, Active and Version columns")
    if any(len(line.split("|")) != len(columns) for line in lines[1:] if line.strip()):
        raise ValueError("Client .build.info has an incomplete row")
    rows = [dict(zip(columns, line.split("|"))) for line in lines[1:] if line.strip()]
    builds = [r.get("Version") for r in rows if r.get("Active") == "1" and r.get("Product") == recipe["clientProduct"]]
    if builds != [recipe["clientBuild"]]:
        raise ValueError(f"Expected {recipe['clientProduct']} {recipe['clientBuild']}; found {builds}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wow", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--tools", type=Path, default=ROOT / ".dependencies/SPF-06a819ef")
    parser.add_argument("--bin", type=Path, default=ROOT / ".dependencies/terrain-build/build/bin/Release/bin")
    parser.add_argument("--locale", choices=("enUS", "zhCN"), default="zhCN")
    parser.add_argument("--maps", type=int, nargs="+", default=[0, 1, 2991])
    parser.add_argument("--rows", type=int, nargs=2)
    parser.add_argument("--cols", type=int, nargs=2)
    parser.add_argument("--threads", type=int, default=2)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--check", action="store_true", help="validate inputs without extracting")
    args = parser.parse_args()
    if min(args.threads, args.jobs) < 1:
        parser.error("Worker counts must be positive")
    if len(set(args.maps)) != len(args.maps) or any(not 0 <= m <= 9999 for m in args.maps):
        parser.error("Map IDs must be unique and within 0..9999")
    for bounds in (args.rows, args.cols):
        if bounds is not None and not 0 <= bounds[0] <= bounds[1] <= 63:
            parser.error("Tile bounds must be ordered within 0..63")
    recipe = json.loads(RECIPE.read_text())
    try:
        check_client(args.wow, args.out, recipe)
        verify_files(args.tools, recipe["toolHashes"])
        verify_files(ROOT, recipe["localPatchHashes"])
        verify_files(args.bin, recipe["binaryHashes"])
    except (ValueError, OSError) as error:
        parser.error(str(error))
    if args.check:
        print("Client build, output isolation, pinned tools and binaries verified; no extraction performed.")
        return
    # Pass the installed locale without editing the checksum-pinned upstream tools.
    bootstrap = (
        "import importlib.util,sys;"
        "p,locale=sys.argv[1:3];sys.argv=[p,*sys.argv[3:]];"
        "s=importlib.util.spec_from_file_location('terrain_baker',p);"
        "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);"
        "m.LOCALE=locale;m.main()"
    )
    baker = args.tools.resolve() / "tools/baker"
    command = [sys.executable, "-c", bootstrap, str(baker / "trinity.py"), args.locale,
               "--wow", str(args.wow.resolve()), "--out", str(args.out.resolve()),
               "--bin", str(args.bin.resolve()), "--product", recipe["clientProduct"],
               "--rev", recipe["trinityRevision"], "--maps", *map(str, args.maps),
               "--threads", str(args.threads), "--jobs", str(args.jobs)]
    for name in PATCHES:
        command += ["--patch", str(baker / name)]
    for name in recipe["localPatchHashes"]:
        command += ["--patch", str(ROOT / name)]
    for flag, bounds in (("--rows", args.rows), ("--cols", args.cols)):
        if bounds is not None:
            command += [flag, *map(str, bounds)]
    subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
