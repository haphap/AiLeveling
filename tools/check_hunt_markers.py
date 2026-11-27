"""Compare check_quest_markers.lua exports to Forever client kill and loot observations."""
import argparse
import csv
import json
import math
import sys
from collections import defaultdict
from pathlib import Path


def field_positions(quests, observations):
    identities = defaultdict(set)
    for path in quests:
        for quest, record in json.loads(path.read_text())["quests"].items():
            for index, goal in enumerate(record.get("objectives", []), 1):
                identities[quest, str(index)].add((goal.get("type"), goal.get("objectId"), goal.get("amount")))

    points = defaultdict(set)
    for path in observations:
        for quest, goals in json.loads(path.read_text())["quests"].items():
            for index, goal in goals.items():
                identity = identities.get((quest, index), set())
                if len(identity) != 1 or not goal.get("gains") or not goal.get("sources"):
                    continue
                kind, target, amount = next(iter(identity))
                if kind not in ("monster", "item") or kind != goal["type"] or amount != goal.get("required"):
                    continue
                key = quest, index, "npc" if kind == "monster" else kind, str(target), str(amount)
                for pos in goal.get("positions", []):
                    if pos.get("uiMap") and "mapX" in pos and "mapY" in pos:
                        points[key, pos["uiMap"]].add((pos["mapX"], pos["mapY"]))
    return points


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--markers", type=Path, nargs="+", required=True, help="catalog TSVs, one per character context")
    parser.add_argument("--quests", type=Path, nargs="+", required=True, help="quests.enUS.json files")
    parser.add_argument("--observations", type=Path, nargs="+", required=True, help="objectives.json files")
    parser.add_argument("--maps", type=Path, required=True, help="UiMapAssignment CSV")
    args = parser.parse_args()
    points = field_positions(args.quests, args.observations)
    with args.maps.open() as source:
        sizes = {int(r["UiMapID"]): (abs(float(r["Region_4"]) - float(r["Region_1"])),
                                     abs(float(r["Region_3"]) - float(r["Region_0"])))
                 for r in csv.DictReader(source) if r["OrderIndex"] == "0"}

    rows = set()
    for path in args.markers:
        with path.open() as source:
            for row in csv.reader(source, delimiter="\t", quoting=csv.QUOTE_NONE):
                quest, title, phase, index, kind, target, status, zone, x, y, entity, npc, source_kind, _, _, amount = row
                if phase != "objective" or entity != "npc" or source_kind != "-" or status not in ("located", "spawnArea"):
                    continue
                zone = int(zone)
                samples = points.get(((quest, index, kind, target, amount), zone))
                if not samples or zone not in sizes:
                    continue
                width, height = sizes[zone]
                if not width or not height:
                    continue
                x, y = float(x), float(y)
                nearest = min(math.hypot((px - x) * width, (py - y) * height) for px, py in samples)
                rows.add((int(quest), int(index), title, kind, int(target), int(npc), zone, x, y, len(samples), round(nearest)))

    output = csv.writer(sys.stdout, delimiter="\t", lineterminator="\n")
    output.writerow(("quest", "slot", "title", "type", "target", "npc", "map", "x", "y", "samplePoints", "nearestYards"))
    output.writerows(sorted(rows, key=lambda r: (-r[-1], r)))
    print(f"{len({r[0] for r in rows})} quests with same-map observations", file=sys.stderr)


if __name__ == "__main__":
    main()
