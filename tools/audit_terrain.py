"""Verify full-map terrain provenance and write the offline data audit."""

import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path

from bake_terrain import RECIPE, ROOT, verify_files


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--tools", type=Path, default=ROOT / ".dependencies/SPF-06a819ef")
    parser.add_argument("--output", type=Path, default=ROOT / "docs/TERRAIN_DATA_AUDIT.json")
    args = parser.parse_args()
    recipe = json.loads(RECIPE.read_text())
    verify_files(args.tools, recipe["toolHashes"])
    verify_files(ROOT, recipe["localPatchHashes"])
    spec = importlib.util.spec_from_file_location("terrain_inputs", args.tools / "tools/baker/inputs.py")
    inputs = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inputs)
    patches = {Path(name).name: value for name, value in recipe["toolHashes"].items()
               if name.startswith("tools/baker/") and name.endswith(".patch")}
    patches.update({Path(name).name: value for name, value in recipe["localPatchHashes"].items()})
    maps = []
    for map_id in (0, 1, 2991):
        directory = args.directory / f"trinity{map_id}/mmaps"
        manifest = inputs.complete(directory, map_id)
        if (manifest["build"], manifest["product"], manifest["rows"], manifest["cols"]) != (
                recipe["clientBuild"], recipe["clientProduct"], None, None):
            raise ValueError(f"Map {map_id} has a different build, product or crop")
        provenance = manifest["provenance"]
        if provenance["binaries"] != recipe["binaryHashes"] or provenance["code"] != {
                "trinitycore": recipe["trinityRevision"], "patches": patches}:
            raise ValueError(f"Map {map_id} has a different source or binary recipe")
        body = {k: v for k, v in provenance.items() if k != "binaries"}
        if hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest() != manifest["recipe"]:
            raise ValueError(f"Map {map_id} recipe hash does not match its provenance")
        if {p.name for p in (directory / "status").iterdir()} != set(manifest["tiles"]):
            raise ValueError(f"Map {map_id} has unexpected tile status records")
        metrics = json.loads((args.directory / f"nav{map_id}.metrics.json").read_text())
        tile_hashes = {p.name: sha(p) for p in directory.glob("*.mmtile")}
        if metrics["extractor"] != manifest or metrics["tiles"] != tile_hashes:
            raise ValueError(f"Map {map_id} generated data does not match current tile inputs")
        extraction = json.loads((args.directory / f"trinity{map_id}.metrics.json").read_text())
        raw = Path(extraction["scratch"]) / f"raw/Nav{map_id}.lua"
        if sha(raw) != metrics["output_sha256"]:
            raise ValueError(f"Map {map_id} raw navigation output has changed")
        maps.append({"map": map_id, "expectedTiles": len(manifest["tiles"]),
                     "populatedTiles": len(tile_hashes), "emptyTiles": len(manifest["tiles"]) - len(tile_hashes),
                     "clusters": metrics["clusters"], "graphNodes": metrics["nodes"],
                     "sourceManifestSHA256": sha(directory / "source.json"),
                     "recipe": manifest["recipe"], "generationSeconds": metrics["total_seconds"]})
    nav = args.directory / "addons/ShortestPathForever/Nav"
    names = re.findall(r'<Script file="([^"]+)"', (nav / "Nav.xml").read_text())
    if not names or any(not re.fullmatch(r"Nav\d+(?:_\d+)?\.lua", n) for n in names):
        raise ValueError("Invalid navigation bundle index")
    if {p.name for p in nav.iterdir()} != {"Nav.xml", *names} or any((nav / n).stat().st_size > 524288 for n in names):
        raise ValueError("Navigation bundle has missing, extra or oversized files")
    report = {"schema": 1, "clientBuild": recipe["clientBuild"], "product": recipe["clientProduct"],
              "recipeFileSHA256": sha(RECIPE), "maps": maps,
              "bundle": {n: sha(nav / n) for n in ["Nav.xml", *names]},
              "offlineExtractionVerified": True, "clientVerified": False, "productionImported": False,
              "scope": "Full WDT inventories for maps 0, 1 and 2991; endpoint coverage and gameplay are separate."}
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Verified {len(maps)} maps, {sum(m['expectedTiles'] for m in maps)} expected tiles, {len(names)} Lua files.")


if __name__ == "__main__":
    main()
