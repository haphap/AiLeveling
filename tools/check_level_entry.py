#!/usr/bin/env python3
"""Check automatic entry at each level for every actual playable race/class."""
import hashlib
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from audit_playable import build, ROOT, INPUTS


def check(persona):
    command = ["lua5.1", str(ROOT / "tools/check_level_entry.lua"), str(ROOT),
               str(ROOT / ".dependencies/QuestieDB"), persona["faction"], persona["class"],
               str(persona["raceId"]), persona["raceFile"]]
    p = subprocess.run(command, cwd=ROOT / ".dependencies/QuestieDB-1.0.12",
                       capture_output=True, text=True, timeout=120)
    entries, flows = [], []
    complete = False
    for line in p.stdout.splitlines():
        cols = line.split("\t")
        if cols[0] == "ENTRY":
            entries.append(dict(zip(["level", "originMap", "action", "questId", "questLevel", "candidates", "movementSeconds", "xp"],
                                    [int(cols[1]), int(cols[2]), cols[3], int(cols[4]), int(cols[5]), int(cols[6]), float(cols[7]), float(cols[8])])) )
        elif cols[0] == "FLOW":
            flows.append({"level": int(cols[1]), "questId": int(cols[2]), "activeAction": cols[3], "followingQuestId": int(cols[4])})
        elif cols == ["60", "complete"]:
            complete = True
    passed = p.returncode == 0 and len(entries) == 59 and len(flows) == 6 and complete
    result = {k: persona[k] for k in ["faction", "raceId", "race", "class"]}
    result.update(passed=passed, entries=entries, flows=flows, level60Complete=complete, error=p.stderr)
    print(f"{persona['raceId']} {persona['class']}: {len(entries)} levels, {len(flows)} flows, {'PASS' if passed else 'FAIL'}", flush=True)
    return result


def main():
    census = build()
    names = set(INPUTS) | {".dependencies/QuestieDB-1.0.12-Forever.zip", ".dependencies/UiMapAssignment-1.60.1.70862.csv",
                          "tools/check_level_entry.lua", "tools/check_level_entry.py", "tools/audit_playable.py", "tests/fixtures.lua"}
    names.update(str(p.relative_to(ROOT)) for p in ROOT.glob("*.lua"))
    for directory in ["Planner", "Data"]:
        names.update(str(p.relative_to(ROOT)) for p in (ROOT / directory).glob("*.lua"))
    inputs = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in sorted(names)}
    with ThreadPoolExecutor(max_workers=3) as executor:
        results = list(executor.map(check, census["combinations"]))
    assert all(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest for name, digest in inputs.items()), "inputs changed during replay"
    report = {"build": census["build"], "clientVerified": False, "fullCoverage": False,
              "scope": "56 playable race/class combinations; independent empty-history snapshots at levels 1-59, native full-zone rectangles, 7 yd/s, no known flights/hearth, no profession/reputation unlocks. Six automatic accept/objective/arrival/turn-in/following-task flows per persona with simulated log events. Level 60 exits leveling. This is entry coverage at fixed origins, not a continuous XP-sufficient 1-60 route or live validation.",
              "origins": {"Alliance": ["race opening", 1436, 1433, 1434, 1446, 1452], "Horde": ["race opening", 1413, 1424, 1434, 1446, 1452]},
              "unknownValueSentinel": -1, "inputs": inputs, "results": results}
    output = ROOT / "docs/LEVEL_ENTRY_REPLAY.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    failed = [r for r in results if not r["passed"]]
    print(f"{len(results)-len(failed)}/{len(results)} personas passed -> {output}")
    for r in failed:
        print(r["race"], r["class"], r["error"])
    raise SystemExit(bool(failed))


if __name__ == "__main__":
    main()
