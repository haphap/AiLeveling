#!/usr/bin/env python3
"""Diagnose every confirmed playable persona; this is not live 1-60 acceptance."""
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import hashlib
import json
import re
import subprocess
import time

from audit_playable import ROOT, build, INPUTS


def parse_trace(lines, faction):
    stops = [line.split('\t') for line in lines if line.startswith('STOP\t')]
    summaries = [line.split('\t') for line in lines if line.startswith('SUMMARY\t')]
    assert len(stops) == len(summaries) == 1, 'Missing or duplicate terminal record'
    stop, summary = stops[0], summaries[0]
    assert len(stop) == 6 and len(summary) == 9 and summary[1] == faction
    assert lines[-1].split('\t') == summary
    turnins = [line.split('\t') for line in lines if line.startswith('TURNIN\t')]
    assert len(turnins) == int(summary[4]) == int(stop[3])
    assert all(int(row[1]) == i for i, row in enumerate(turnins, 1))
    assert sum(int(row[4]) for row in turnins if row[4] != 'UNKNOWN') == int(summary[5])
    assert sum(row[4] == 'UNKNOWN' for row in turnins) == int(summary[6])
    assert int(stop[2]) == int(summary[2]) and 1 <= int(summary[2]) <= 60
    return dict(reason=stop[1], questId=int(stop[4]) if stop[4] else None, action=stop[5],
                level=int(summary[2]), xp=int(summary[3]), turnIns=int(summary[4]),
                knownQuestXP=int(summary[5]), unknownRewards=int(summary[6]),
                directHandIns=int(summary[7]), movementSeconds=float(summary[8]),
                completedQuestIds=sorted({int(row[2]) for row in turnins}))


def main():
    census = build()
    personas = [{k: row[k] for k in ('faction', 'raceId', 'race', 'raceFile', 'class')}
                for row in census['combinations']]
    assert len(personas) == len({(p['raceId'], p['class']) for p in personas}) == 56
    names = set(INPUTS) | {'tools/check_continuous_personas.py', 'tools/audit_playable.py',
        'tools/check_continuous.lua', 'tools/continuous_inventory.lua', 'tests/fixtures.lua',
        'AiLeveling.toc', '.dependencies/UiMapAssignment-1.60.1.70862.csv'}
    for directory in (ROOT, ROOT/'Data', ROOT/'Planner', ROOT/'.dependencies/QuestieDB',
                      ROOT/'.dependencies/QuestieDB-1.0.12/emulator'):
        paths = directory.glob('*.lua') if directory in (ROOT, ROOT/'Data', ROOT/'Planner') else directory.rglob('*')
        names.update(str(p.relative_to(ROOT)) for p in paths if p.is_file())
    inputs = {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in sorted(names)}
    version = re.search(r'^## Version: (.+)$', (ROOT/'AiLeveling.toc').read_text(), re.M).group(1)
    stamp = str(time.time_ns())

    def run(persona):
        log = ROOT/f"dist/continuous-personas-{stamp}-{persona['raceId']}-{persona['class']}.log"
        command = ['lua5.1', str(ROOT/'tools/check_continuous.lua'), str(ROOT),
                   str(ROOT/'.dependencies/QuestieDB'), persona['faction'], persona['class'],
                   str(persona['raceId']), persona['raceFile']]
        started = time.monotonic()
        with log.open('x') as stream:
            process = subprocess.run(command, cwd=ROOT/'.dependencies/QuestieDB-1.0.12',
                                     stdout=stream, stderr=subprocess.STDOUT)
        row = dict(persona, exitCode=process.returncode, elapsedSeconds=round(time.monotonic()-started, 3),
                   log=str(log.relative_to(ROOT)), logSHA256=hashlib.sha256(log.read_bytes()).hexdigest())
        if process.returncode == 0:
            try:
                row['stop'] = parse_trace(log.read_text().splitlines(), persona['faction'])
            except (ValueError, AssertionError, IndexError) as error:
                row['traceError'] = str(error) or type(error).__name__
        return row

    results = []
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = [pool.submit(run, persona) for persona in personas]
        for future in as_completed(futures):
            row = future.result(); results.append(row)
            stop = row.get('stop', {})
            print(len(results), row['race'], row['class'], stop.get('reason', 'script-error'),
                  stop.get('questId'), stop.get('level'), flush=True)
    assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest() == h for n, h in inputs.items()), 'Inputs changed during replay'
    results.sort(key=lambda row: (row['faction'], row['raceId'], row['class']))
    failed = [row for row in results if row['exitCode'] or 'traceError' in row]
    stops = Counter((row['stop']['reason'], row['stop']['questId']) for row in results if 'stop' in row)
    report = dict(version=version, build=census['build'], result='script-errors' if failed else 'diagnostic-incomplete',
                  clientVerified=False, fullCoverage=False, personaCount=len(results),
                  terminalTraces=len(results)-len(failed),
                  scope='All confirmed playable combinations, from level 1 until the first diagnostic stop. No skipped blockers or invented quest requirements.',
                  stops=[dict(reason=reason, questId=quest, personas=count) for (reason, quest), count in stops.most_common()],
                  results=results, inputs=inputs,
                  limits=['Character events and item acquisition are simulated; this does not verify client gameplay.',
                          'Only known quest turn-in XP is credited; kill, exploration and bonus XP are omitted.',
                          'Economy, skills, reputation, gear changes, transport unlocks and complete inventory rules are not simulated.',
                          'A diagnostic stop can reflect missing reference facts or simulator capabilities; inspect the exact quest before changing runtime behavior.'])
    output = ROOT/'docs/CONTINUOUS_PERSONAS_REPLAY.json'
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(f'{len(results)} personas, {len(failed)} script errors, {len(stops)} distinct stops -> {output}', flush=True)
    raise SystemExit(bool(failed))


if __name__ == '__main__':
    main()
