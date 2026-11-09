#!/usr/bin/env python3
"""Run selected reference-data checks; continuous histories are a separate diagnostic."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
CHECKS = {
    'inventory': ('check_continuous_inventory.lua', 2),
    'area': ('check_area_triggers.lua', 1),
    'cache': ('check_cache_objectives.lua', 1),
    'delivery': ('check_delivery_only.lua', 1),
}
CLASSES = ['WARRIOR', 'PALADIN', 'HUNTER', 'ROGUE', 'PRIEST', 'SHAMAN', 'MAGE', 'WARLOCK', 'DRUID']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checks', nargs='+', choices=CHECKS)
    args = parser.parse_args()
    stamp = str(time.time_ns())
    (ROOT/'dist').mkdir(exist_ok=True)
    paths = {p for directory in ['', 'Data', 'Planner', 'UI', 'tests', 'tools']
             for pattern in ['*.lua', '*.py'] for p in (ROOT/directory).glob(pattern)}
    paths.update(ROOT/p for p in ['AiLeveling.toc', 'README.md',
                 '.dependencies/UiMapAssignment-1.60.1.70862.csv',
                 '.dependencies/eg-link-156f29c9/DATASETS.md',
                 '.dependencies/eg-link-156f29c9/1.60.1.70862/quests.enUS.json'])
    inputs = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}

    def run(job):
        check, faction, cls = job
        script, expected = CHECKS[check]
        log = ROOT/f'dist/reference-{stamp}-{check}-{faction}-{cls}.log'
        command = ['lua5.1', str(ROOT/'tools'/script), str(ROOT), str(ROOT/'.dependencies/QuestieDB'),
                   faction, cls, '1' if faction == 'Alliance' else '2',
                   'Human' if faction == 'Alliance' else 'Orc']
        with log.open('x') as stream:
            result = subprocess.run(command, cwd=ROOT/'.dependencies/QuestieDB-1.0.12',
                                    stdout=stream, stderr=subprocess.STDOUT)
        lines = log.read_text().splitlines()
        assert result.returncode == 0 and len(lines) == expected and all(line.startswith('PASS\t') for line in lines), str(log)
        return dict(check=check, faction=faction, playerClass=cls, output=lines,
                    log=str(log.relative_to(ROOT)), logSHA256=hashlib.sha256(log.read_bytes()).hexdigest())

    jobs = [(check, faction, cls) for check in dict.fromkeys(args.checks)
            for faction in ['Alliance', 'Horde']
            for cls in (['WARRIOR'] if check == 'inventory' else CLASSES)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(run, jobs))
    assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest() == h for n, h in inputs.items())
    version = next(line.removeprefix('## Version: ').strip() for line in
                   (ROOT/'AiLeveling.toc').read_text().splitlines() if line.startswith('## Version: '))
    report = dict(version=version, result='passed', clientVerified=False, fullCoverage=False,
                  scope='Selected fixed-data checks with simulated character state; not continuous 1-60 coverage.',
                  results=results, inputs=inputs)
    output = ROOT/f'dist/reference-{stamp}.json'
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(f'{len(results)} reference checks passed: {output.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
