#!/usr/bin/env python3
"""Replay generated XP through the runtime and quantify the previous continuous-history gap."""
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path
from import_cache_xp import load

ROOT = Path(__file__).resolve().parents[1]


def main():
    data, audit = load()
    effective = json.loads((ROOT / 'docs/EFFECTIVE_DATA_AUDIT.json').read_text())['base']['quests']
    old_gaps = json.loads((ROOT / 'dist/xp-gap-classification-0.1.74.json').read_text())['rows']
    code = ['local A={};assert(loadfile("Data/TaskFacts.lua"))("AiLeveling",A)',
            'assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",A)',
            'local s={clientVersion="1.60.1",clientBuild="70862",interface=16001,quests={}}']
    checks = 0
    for id, q in data['quests'].items():
        curve, index = q['xp'], 0
        for level in range(1, 60):
            while index + 1 < len(curve) and curve[index + 1][0] <= level:
                index += 1
            code.append(f'assert(A.TaskGuide.XP({{id={id},questLevel={q["level"]}}},{level},s)=={curve[index][1]},"{id}:{level}")')
            checks += 1
    with tempfile.NamedTemporaryFile(mode='w', suffix='.lua') as f:
        f.write('\n'.join(code));f.flush()
        subprocess.run(['lua5.1', f.name], cwd=ROOT, check=True)
    gaps = []
    for row in old_gaps:
        id = str(row['id'])
        q = data['quests'].get(id)
        status = 'filled' if q and effective[id]['level'] == q['level'] else 'level_mismatch' if q else 'no_current_cache'
        gaps.append(dict(id=int(id), status=status, cacheLevel=q and q['level'], effectiveLevel=effective[id]['level']))
    report = dict(build='1.60.1.70862', clientVerified=False, runtimeChecks=checks,
                  observedTurnIns=len(audit['observationChecks']), previousGaps=gaps,
                  filled=sum(r['status'] == 'filled' for r in gaps),
                  inputs={n: hashlib.sha256((ROOT / n).read_bytes()).hexdigest() for n in
                          ['tools/check_cache_xp.py', 'tools/import_cache_xp.py', 'tools/import_task_facts.py',
                           'Planner/TaskGuide.lua', 'Data/TaskFacts.lua', 'docs/EFFECTIVE_DATA_AUDIT.json',
                           'dist/xp-gap-classification-0.1.74.json']})
    (ROOT / 'docs/TASK_XP_REPLAY.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f'{checks} runtime XP checks; {report["observedTurnIns"]} recorded turn-ins; {report["filled"]}/{len(gaps)} historical gaps filled')


if __name__ == '__main__':
    main()
