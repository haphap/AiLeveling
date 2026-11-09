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
    f'{BASE}/item_uses.json': '2994bdaa81f0db8fff891eb9bc30e8b46a3acac126ad801d3787fa0f1b8f5f01',
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
    uses = json.loads((ROOT / BASE / 'item_uses.json').read_text())
    for obj, dataset in [(cache, 'quests'), (observations, 'turn_ins'), (locations, 'objectives'), (uses, 'item_uses')]:
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
            curves[id]['complex'] = True
    # Independently checked requirements missing from the pinned server cache.
    # These add no XP/rewards; item IDs and counts remain separate from quest eligibility.
    supplements = [
        {'id': 99101, 'level': 9, 'sourceItemId': 286104,
         'objectives': [{'kind': 'item', 'id': 286104, 'count': 1}],
         'url': 'https://www.wowhead.com/forever/quest=99101/our-ancient-enemy'},
        {'id': 97225, 'level': 9, 'sourceItemId': 0,
         'objectives': [{'kind': 'item', 'id': 277135, 'count': 8}],
         'url': 'https://www.wowhead.com/forever/quest=97225/forgotten-loa-idols'},
        {'id': 79093, 'level': 20, 'sourceItemId': 0,
         'objectives': [{'kind': 'item', 'id': 208860, 'count': 1}],
         'url': 'https://www.wowhead.com/forever/quest=79093/rumi-of-gnomeregan-the-collected-works'},
        {'id': 91733, 'level': 10, 'sourceItemId': 0,
         'objectives': [{'kind': 'item', 'id': item, 'count': 1} for item in (247817, 247813, 247818)],
         'url': 'https://www.wowhead.com/forever/quest=91733/downstream'},
        {'id': 97583, 'level': 1, 'sourceItemId': 0,
         'objectives': [{'kind': 'item', 'id': 278265, 'count': 1}],
         'url': 'https://www.wowhead.com/forever/quest=97583/wriggle'},
        {'id': 490, 'level': 8, 'sourceItemId': 0,
         'objectives': [{'kind': 'item', 'id': 5220, 'count': 15}],
         'url': 'https://www.wowhead.com/forever/quest=490/bounty-gnarlpine-furbolg'},
        {'id': 97246, 'level': 15, 'sourceItemId': 0, 'objectives': [],
         'url': 'https://www.wowhead.com/forever/quest=97246/meal-appeal'},
    ]
    for fact in supplements:
        fact.update(checked='2026-11-09', captureBuild=None)
        assert str(fact['id']) not in curves
        curves[str(fact['id'])] = dict(level=fact['level'], sourceItemId=fact['sourceItemId'],
                                      objectives=fact['objectives'], complex=False)
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
    used_items, rejected_uses = [], []
    for id, items in uses['quests'].items():
        for item, observed in items.items():
            spell = observed.get('spellId')
            assert item.isdigit() and int(item) > 0
            if id not in curves or type(spell) is not int or spell <= 0 or observed.get('progressed', 0) <= 0 or observed.get('uses') != observed.get('progressed'):
                rejected_uses.append(dict(id=int(id), item=int(item), reason='no_matching_cache_or_consistent_progress'))
                continue
            assert observed.get('sources', 0) > 0 and observed['uses'] >= observed['progressed']
            targets = []
            for target, count in sorted(observed.get('targets', {}).items()):
                parts = target.split(':')
                if len(parts) == 2 and parts[0] in ('npc', 'object') and parts[1].isdigit() and int(parts[1]) > 0 and count > 0:
                    targets.append(dict(kind=parts[0], id=int(parts[1])))
            curves[id].setdefault('itemUses', {})[item] = dict(spellId=spell, targets=targets)
            used_items.append(dict(id=int(id), item=int(item), spell=spell))
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
                  sourceQuests=len(cache['quests']), xpRows=sum('xp' in q for q in curves.values()), excluded=excluded,
                  objectiveSupplements=supplements,
                  observationChecks=matched, skippedObservations=skipped, clientVerified=False,
                  objectiveLocations=dict(quests=len({o['id'] for o in located}), objectives=len(located),
                                          points=sum(o['points'] for o in located), accepted=located, rejected=rejected,
                                          scope='Character positions when counts increased; approximate fallback only, never target spawns or completion proof.'),
                  itemUses=dict(quests=len({o['id'] for o in used_items}), items=len(used_items), accepted=used_items,
                                rejected=rejected_uses, scope='Successful item spells followed by quest progress. Use purpose and observed targets only; no required quantities, consumption or recovery inferred.'),
                  scope='Base rewards only; native current-level rewards take priority. No character XP bonuses inferred.',
                  flagReference='https://master.trinitycore.net/d8/d60/structquestobjective',
                  transformation='IDs, fixed levels, XP curves and monster/object/item/area-trigger requirements. AreaTrigger and AreaTriggerEnter retain zero amounts as completion flags, not quantities; unsupported or invalid objective types remain complex; payment quests remain complex objectives. No text, eligibility or item rewards copied.')
    return data, report
