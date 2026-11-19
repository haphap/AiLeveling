#!/usr/bin/env python3
"""Generate quest facts from the Forever cache and client spell tables."""
import argparse
import json
import math
from pathlib import Path
from import_cache_xp import load as load_cache_xp
from import_item_effects import read as read_effects, PINS as EFFECT_PINS

ROOT = Path(__file__).resolve().parents[1]


def lua(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        assert math.isfinite(value)
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return '{' + ','.join(lua(v) for v in value) + '}'
    return '{' + ','.join('[' + (k if k.isdigit() else lua(k)) + ']=' + lua(v) for k, v in sorted(value.items())) + '}'


def reward_unlocks(quests):
    spells = read_effects('SpellEffect')
    mounts = {int(r['SpellID']): int(r['SpellID']) for r in spells.values()
              if int(r['Effect']) == 6 and int(r['EffectAura']) == 78}
    learning = [r for r in spells.values() if int(r['Effect']) in (36, 64)]
    learned = {}
    for r in learning:
        if int(r['Effect']) == 36 and int(r['EffectTriggerSpell']) > 0:
            learned.setdefault(int(r['SpellID']), set()).add(int(r['EffectTriggerSpell']))
    changed = True
    while changed:
        changed = False
        for r in learning:
            ident, target = int(r['SpellID']), int(r['EffectTriggerSpell'])
            if target in mounts and ident not in mounts:
                mounts[ident] = mounts[target]; changed = True
            if int(r['Effect']) == 64 and target in learned:
                before = len(learned.get(ident, set()))
                learned.setdefault(ident, set()).update(learned[target])
                changed = changed or len(learned[ident]) > before
    effects = read_effects('ItemEffect')
    items = {}
    for r in read_effects('ItemXItemEffect').values():
        effect = effects.get(int(r['ItemEffectID']))
        if effect and int(effect['SpellID']) in mounts:
            items[int(r['ItemID'])] = mounts[int(effect['SpellID'])]
    for q in quests.values():
        reward = q.get('rewards', {})
        found = [mounts[reward[k]] for k in ('spell', 'spellCast') if reward.get(k) in mounts]
        found += [items[i['id']] for k in ('items', 'choices') for i in reward.get(k, []) if i['id'] in items]
        if found:
            q['mountReward'] = found[0]
        # Cast rewards count only when they teach; display-only spell IDs are replaced by the taught spells.
        unlocks = learned.get(reward.get('spellCast'), set()) | learned.get(reward.get('spell'), set())
        if not unlocks and reward.get('spell'):
            unlocks = {reward['spell']}
        if unlocks:
            q['learnedSpells'] = sorted(unlocks)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    cache, cache_report = load_cache_xp()
    quests = cache['quests']
    reward_unlocks(quests)
    generated = ('local _,A=...\n-- Forever server observations from Efficient Games (CC BY 4.0) '
                 'and numeric quest facts from Wowhead Forever. See docs/TASK_XP_AUDIT.json.\n'
                 'A.TaskFacts={cacheXP=' + lua(cache) + '}\n')
    report = {'source': cache_report['source'], 'url': cache_report['questURL'], 'license': 'CC BY 4.0',
              'licenseScope': 'EG Link observations',
              'build': cache_report['build'], 'questAudit': 'TASK_XP_AUDIT.json', 'effectTables': EFFECT_PINS,
              'quests': len(quests), 'rewardRows': sum('rewards' in row for row in quests.values()),
              'xpRows': cache_report['xpRows'], 'objectives': sum(len(row.get('objectives', [])) for row in quests.values()),
              'mountRewards': sum('mountReward' in row for row in quests.values()),
              'skillRewards': sum('learnedSpells' in row for row in quests.values())}
    outputs = {ROOT / 'Data/TaskFacts.lua': generated,
               ROOT / 'docs/TASK_FACTS_AUDIT.json': json.dumps(report, indent=2, ensure_ascii=False) + '\n',
               ROOT / 'docs/TASK_XP_AUDIT.json': json.dumps(cache_report, indent=2, ensure_ascii=False) + '\n'}
    for path, value in outputs.items():
        if args.check:
            assert path.read_text() == value, f'Generated facts differ: {path}'
        else:
            path.write_text(value)
    print(json.dumps({k: report[k] for k in ['quests', 'rewardRows', 'xpRows', 'objectives']}))


if __name__ == '__main__':
    main()
