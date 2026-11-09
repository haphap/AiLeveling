#!/usr/bin/env python3
"""Build quest XP curves from pinned Forever server caches and client tiers."""
import csv
import hashlib
import json
import math
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = '1.60.1.70862'
COMMIT = '156f29c9af78b1586883e8eb94a13467eb89638c'
BASE = f'.dependencies/eg-link-{COMMIT[:8]}/{BUILD}'
PINS = {
    f'{BASE}/quests.enUS.json': '0f8b890bbedc79f6c80b99511a88ff5f699048f4a34303bd6d0a0281cfde4b7a',
    f'{BASE}/turn_ins.json': '567debf36003b2c7010e449d3b6f40ce2d7f277e6ea179c60d909b04b2847f02',
    f'{BASE}/objectives.json': 'c71832408f23261698a60c69f6ed69223944d85cd1d931028be36693dda557f9',
    f'.dependencies/QuestXP-{BUILD}.csv': '1513f3f2646ae0b33b79de6219614792f0dbc050bb5bd76c1c4f0fce668a86fd',
}


def reward(tier, multiplier, quest_level, player_level):
    # Round after applying the multiplier and level reduction; confirmed by turn-in observations.
    factor = max(1, min(10, 20 + 2 * (quest_level - player_level)))
    raw = int(tier * Fraction(str(multiplier)) * factor / 10)
    unit = 50 if raw > 1000 else 25 if raw > 500 else 10 if raw > 100 else 5
    return (raw + unit // 2) // unit * unit


def load():
    for name, digest in PINS.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    cache = json.loads((ROOT / BASE / 'quests.enUS.json').read_text())
    observations = json.loads((ROOT / BASE / 'turn_ins.json').read_text())
    locations = json.loads((ROOT / BASE / 'objectives.json').read_text())
    for obj, dataset in [(cache, 'quests'), (observations, 'turn_ins'), (locations, 'objectives')]:
        assert obj['meta']['clientBuild'] == BUILD and obj['meta']['product'] == 'wowf'
        assert obj['meta']['schemaVersion'] == 1 and obj['meta']['dataset'] == dataset
    with (ROOT / f'.dependencies/QuestXP-{BUILD}.csv').open() as stream:
        reader = csv.DictReader(stream)
        assert reader.fieldnames == ['ID'] + [f'Difficulty_{i}' for i in range(10)]
        rows = list(reader)
        tiers = {int(r['ID']): [int(r[f'Difficulty_{i}']) for i in range(10)] for r in rows}
        assert len(tiers) == len(rows) and all(level in tiers for level in range(1, 61))
        assert all(v >= 0 for values in tiers.values() for v in values)
    curves, excluded = {}, {}
    for id, q in cache['quests'].items():
        assert id.isdigit() and int(id) > 0
        level, rewards = q.get('level'), q.get('rewards', {})
        if type(level) is not int or not 1 <= level <= 60:
            excluded[id] = 'outside_fixed_level_1_60'
            continue
        difficulty, multiplier = rewards.get('xpDifficulty'), rewards.get('xpMultiplier')
        assert type(difficulty) is int and 0 <= difficulty < 10, id
        assert type(multiplier) in (int, float) and 0 <= multiplier <= 100, id
        assert q.get('sources', 0) > 0, id
        curve = []
        for player_level in range(1, 60):
            xp = reward(tiers[level][difficulty], multiplier, level, player_level)
            if not curve or curve[-1][1] != xp:
                curve.append([player_level, xp])
        objectives, complex_objectives = [], False
        for objective in q.get('objectives', []):
            kind = {'monster': 'npc', 'gameObject': 'object', 'item': 'item',
                    'areaTrigger': 'areaTrigger', 'areaTriggerEnter': 'areaTriggerEnter'}.get(objective.get('type'))
            target, count = objective.get('objectId'), objective.get('amount')
            # Area triggers store completion flags; zero amount is not an empty requirement.
            flag = kind in ('areaTrigger', 'areaTriggerEnter')
            if kind and type(target) is int and target > 0 and type(count) is int and (count > 0 or flag and count == 0):
                objectives.append(dict(kind=kind, id=target, count=count))
            else:
                complex_objectives = True
        curves[id] = dict(level=level, xp=curve, objectives=objectives, complex=complex_objectives)
        if rewards.get('money', 0) < 0:
            curves[id]['moneyCost'] = -rewards['money']
    located, rejected = [], []
    for id, objectives in locations['quests'].items():
        for index, observed in objectives.items():
            kind = {'monster': 'npc', 'object': 'object', 'item': 'item'}.get(observed.get('type'))
            matches = [o for o in curves.get(id, {}).get('objectives', [])
                       if kind and o['kind'] == kind and o['count'] == observed.get('required')]
            same_shape = sum((o.get('type'), o.get('required')) ==
                             (observed.get('type'), observed.get('required')) for o in objectives.values())
            # Display indices can differ across sources; require a unique type/count match instead.
            if len(matches) != 1 or same_shape != 1:
                rejected.append(dict(id=int(id), index=int(index), reason='ambiguous_or_unmatched_requirement'))
                continue
            points = set()
            if observed.get('gains', 0) > 0 and observed.get('sources', 0) > 0:
                for p in observed.get('positions', []):
                    map_id, x, y = p.get('uiMap'), p.get('mapX'), p.get('mapY')
                    if type(map_id) is int and map_id > 0 and all(type(v) in (int, float) and
                            math.isfinite(v) and 0 <= v <= 1 for v in (x, y)):
                        points.add((map_id, x, y))
            if not points:
                rejected.append(dict(id=int(id), index=int(index), reason='no_valid_progress_position'))
                continue
            matches[0]['locations'] = [dict(map=m, x=x, y=y) for m, x, y in sorted(points)]
            located.append(dict(id=int(id), index=int(index), kind=kind, target=matches[0]['id'], points=len(points)))
    matched, skipped = [], []
    for id, records in observations['quests'].items():
        for observed in records:
            level = observed.get('level')
            if id not in curves or type(level) is not int or not 1 <= level < 60 or observed.get('xpDisabled') or 'xp' not in observed:
                skipped.append(dict(id=int(id), observation=observed))
                continue
            q = cache['quests'][id]
            r = q['rewards']
            xp = reward(tiers[q['level']][r['xpDifficulty']], r['xpMultiplier'], q['level'], level)
            assert xp == observed['xp'], (id, level, xp, observed['xp'])
            matched.append(dict(id=int(id), questLevel=q['level'], playerLevel=level, xp=xp,
                                multiplier=r['xpMultiplier'], sources=observed['sources']))
    assert matched, 'No independent turn-in observations checked'
    data = dict(version='1.60.1', build='70862', interface=16001, quests=curves)
    report = dict(source='EG Link server quest cache + Forever QuestXP client table', build=BUILD,
                  commit=COMMIT, license='CC BY 4.0', attribution=cache['meta']['attribution'],
                  url=f'https://github.com/JIVESCORP/eg-link-output-wowf/tree/{COMMIT}/data/wowf/{BUILD}',
                  tierURL=f'https://wago.tools/db2/QuestXP/csv?build={BUILD}', inputs=PINS,
                  sourceQuests=len(cache['quests']), xpRows=len(curves), excluded=excluded,
                  observationChecks=matched, skippedObservations=skipped, clientVerified=False,
                  objectiveLocations=dict(quests=len({o['id'] for o in located}), objectives=len(located),
                                          points=sum(o['points'] for o in located), accepted=located, rejected=rejected,
                                          scope='Character positions when counts increased; approximate fallback only, never target spawns or completion proof.'),
                  scope='Base rewards only; native current-level rewards take priority. No character XP bonuses inferred.',
                  flagReference='https://master.trinitycore.net/d8/d60/structquestobjective',
                  transformation='IDs, fixed levels, XP curves and monster/object/item/area-trigger requirements. AreaTrigger and AreaTriggerEnter retain zero amounts as completion flags, not quantities; unsupported or invalid objective types remain complex; negative reward money retained as a payment exclusion. No text, eligibility or item rewards copied.')
    return data, report
