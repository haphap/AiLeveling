#!/usr/bin/env python3
"""Join effective entity-source evidence to readable client instance areas."""
import argparse
import hashlib
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def build(root=ROOT):
    census = json.loads((root / 'docs/DUNGEON_COVERAGE.json').read_text())
    exports = json.loads((root / 'dist/quest-locations-export.json').read_text())
    areas = defaultdict(set)
    for m in census['maps']:
        if m['classification'] in ('party', 'raid'):
            for area in m['aliases']:
                areas[area].add(m['mapId'])
    datasets = {}
    for export in exports:
        raw = (root / export['file']).read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        assert digest == export['sha256'], export['file']
        assert len(raw.splitlines()) == export['rows'], export['file']
        if digest not in datasets:
            targets = defaultdict(list)
            for line in raw.decode().splitlines():
                qid, phase, kind, tid, source, eid, area, precise = line.split('\t')
                assert phase in ('accept', 'objective', 'turnin')
                area = int(area)
                targets[(int(qid), phase, kind, int(tid))].append({
                    'source': source, 'entityId': int(eid), 'areaId': area,
                    'precise': precise == '1', 'instanceMapIds': sorted(areas[area]),
                })
            selected_quests = {key[0] for key, rows in targets.items()
                               if any(row['instanceMapIds'] for row in rows)}
            evidence = []
            for (qid, phase, kind, tid), rows in sorted(targets.items()):
                if qid not in selected_quests:
                    continue
                evidence.append({'questId': qid, 'phase': phase, 'targetKind': kind,
                                 'targetId': tid, 'sources': rows})
            datasets[digest] = {'sha256': digest, 'personas': [], 'targets': evidence}
        datasets[digest]['personas'].append(export['persona'])
    maps = []
    for m in census['maps']:
        if m['classification'] not in ('party', 'raid'):
            continue
        phases = {phase: set() for phase in ('accept', 'objective', 'turnin')}
        mixed, unknown = set(), set()
        for dataset in datasets.values():
            for target in dataset['targets']:
                rows = target['sources']
                if not any(m['mapId'] in row['instanceMapIds'] for row in rows):
                    continue
                qid = target['questId']
                phases[target['phase']].add(qid)
                if target['phase'] == 'objective':
                    if any(row['areaId'] > 0 and m['mapId'] not in row['instanceMapIds'] for row in rows):
                        mixed.add(qid)
                    if any(row['areaId'] == 0 for row in rows):
                        unknown.add(qid)
        maps.append({'mapId': m['mapId'], 'name': m['name'], 'classification': m['classification'],
                     'phaseQuestIds': {p: sorted(ids) for p, ids in phases.items()},
                     'objectivesWithOtherAreaSources': sorted(mixed),
                     'objectivesWithUnlocatedSources': sorted(unknown)})
    return {'schema': 1, 'build': census['build'], 'clientVerified': False,
            'limitations': [
                'Entity source presence does not prove a quest requires entering an instance.',
                'Unmatched areas are not assumed outdoors; eight client map records remain unreadable.',
                'Only NPC, object and item objective kinds are exported; special objectives require separate review.',
                'Area evidence includes provider markers; precise=false is not an exact coordinate.',
                'Correction contexts are not character eligibility or playable-combination claims.',
                'No source may also mean missing provider data; absence is not proof of no requirement.',
            ], 'exports': exports, 'maps': maps, 'datasets': list(datasets.values())}


def markdown(report):
    lines = ['# 副本任务实体来源核对', '',
             '覆盖 18 个阵营／职业修正上下文，按相同输出合并；保留接取、目标与交付的独立实体证据。', '',
             '表中数量为可能关联，不能直接作为必进副本的任务数。其他区域来源也可能属于另一个副本。', '',
             '特殊目标类型、缺来源目标、8 条不可读地图及实际开放条件仍待核对。精确坐标缺失时只记录区域，不补造坐标。', '',
             '| 地图 | 名称 | 接取 | 目标 | 交付 | 目标有其他区域来源 |',
             '|---|---|---:|---:|---:|---:|']
    for m in report['maps']:
        p = m['phaseQuestIds']
        lines.append(f"| {m['mapId']} | {m['name']} | {len(p['accept'])} | {len(p['objective'])} | {len(p['turnin'])} | {len(m['objectivesWithOtherAreaSources'])} |")
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    report = build()
    outputs = {'docs/DUNGEON_QUEST_LOCATIONS.json': json.dumps(report, ensure_ascii=False, separators=(',', ':')) + '\n',
               'docs/DUNGEON_QUEST_LOCATIONS.md': markdown(report)}
    for name, text in outputs.items():
        if args.check:
            assert (ROOT / name).read_text() == text, name
        else:
            (ROOT / name).write_text(text)
    print('Quest location evidence:', len(report['exports']), 'contexts,', len(report['datasets']), 'distinct datasets')
