#!/usr/bin/env python3
"""Import a hash-pinned LevelExperience export for the exact Forever client build."""
import argparse
import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = '1.60.1.70862'
SHA = '09403ebb2fc7d752dfbb790d6d6973b07e8e7b67e3bf93d566cc5eee275cb35c'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    source = ROOT / '.dependencies' / f'LevelExperience-{BUILD}.csv'
    assert hashlib.sha256(source.read_bytes()).hexdigest() == SHA, 'LevelExperience source differs from pinned export'
    with source.open(newline='') as stream:
        reader = csv.DictReader(stream)
        assert reader.fieldnames == ['ID', 'Level', 'ContentSetID', 'Experience']
        rows = [{k: int(v) for k, v in row.items()} for row in reader]
    assert len({r['ID'] for r in rows}) == len(rows)
    selected = [r for r in rows if r['ContentSetID'] == 0 and 1 <= r['Level'] < 60]
    curve = {r['Level']: r['Experience'] for r in selected}
    assert len(selected) == len(curve) == 59 and set(curve) == set(range(1, 60))
    assert all(value > 0 for value in curve.values())
    report = {'source': 'Forever LevelExperience client table', 'build': BUILD, 'interface': 16001,
              'url': f'https://wago.tools/db2/LevelExperience/csv?build={BUILD}', 'sha256': SHA,
              'contentSetId': 0, 'rowsInSource': len(rows), 'levels': 59, 'levelCap': 60,
              'totalXP': sum(curve.values()), 'clientVerified': False,
              'activation': 'Exact version/build/interface and current native UnitXPMax must match.',
              'xpToLevel': curve}
    lua = ('local _,A=...\n-- Generated client-table facts; see docs/EXPERIENCE_DATA_AUDIT.json.\n'
           'A.Experience={version="1.60.1",build="70862",interface=16001,clientVerified=false,\n'
           '    source="Forever-LevelExperience-1.60.1.70862",xpToLevel={\n'
           + ''.join(f'    [{level}]={value},\n' for level, value in sorted(curve.items())) + '}}\n')
    outputs = {ROOT / 'Data/Experience.lua': lua,
               ROOT / 'docs/EXPERIENCE_DATA_AUDIT.json': json.dumps(report, ensure_ascii=False, indent=2) + '\n'}
    for path, value in outputs.items():
        if args.check:
            assert path.read_text() == value, f'Generated experience facts differ: {path}'
        else:
            path.write_text(value)
    print(f'{BUILD}: {len(curve)} thresholds, {sum(curve.values())} XP; source and generated facts match')


if __name__ == '__main__':
    main()
