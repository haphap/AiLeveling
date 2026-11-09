#!/usr/bin/env python3
"""Replay opening tasks for every confirmed race/class against the pinned runtime."""
import hashlib
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from audit_playable import build, ROOT


def check(persona):
    command = ["lua5.1", str(ROOT / "tools/check_starting_tasks.lua"), str(ROOT),
               str(ROOT / ".dependencies/QuestieDB"), persona["faction"], persona["class"],
               str(persona["raceId"]), persona["raceFile"]]
    result = subprocess.run(command, cwd=ROOT / ".dependencies/QuestieDB-1.0.12",
                            capture_output=True, text=True, timeout=120)
    return {"faction": persona["faction"], "raceId": persona["raceId"], "race": persona["race"],
            "class": persona["class"], "passed": result.returncode == 0,
            "trace": result.stdout.splitlines(), "error": result.stderr}


def main():
    census = build()
    with ThreadPoolExecutor(max_workers=3) as executor:
        results = list(executor.map(check, census["combinations"]))
    report = {"build": census["build"], "clientVerified": False,
              "scope": "All 56 playable combinations. Automatic initial choices, manual accept/objective/turn-in replay, Skyborne prerequisites and faction forks. Live completion and map distances are simulated; not full level-band validation.",
              "inputs": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                         for name in [".dependencies/QuestieDB-1.0.12-Forever.zip", "tools/check_starting_tasks.lua",
                                      "Data/Questie.lua", "Planner/Planner.lua", "Planner/Eligibility.lua"]},
              "results": results}
    output = ROOT / "docs/STARTING_TASK_REPLAY.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    failed = [r for r in results if not r["passed"]]
    print(f"{len(results) - len(failed)}/{len(results)} starting-task personas passed -> {output}")
    for row in failed:
        print(row["race"], row["class"], row["error"])
    raise SystemExit(bool(failed))


if __name__ == "__main__":
    main()
