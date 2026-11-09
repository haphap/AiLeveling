import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('locations', ROOT / 'tools/audit_quest_locations.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Locations(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = module.build()

    def target(self, qid, item):
        return next(t for t in self.report['datasets'][0]['targets']
                    if t['questId'] == qid and t['phase'] == 'objective' and t['targetId'] == item)

    def test_vancleef_keeps_area_only_and_source_identity(self):
        rows = self.target(166, 3637)['sources']
        row = next(r for r in rows if r['entityId'] == 639)
        self.assertEqual(row['areaId'], 1581)
        self.assertEqual(row['instanceMapIds'], [36])
        self.assertFalse(row['precise'])

    def test_mixed_item_is_not_dungeon_exclusive(self):
        rows = self.target(214, 915)['sources']
        self.assertTrue(any(r['areaId'] == 40 and r['precise'] for r in rows))
        self.assertTrue(any(36 in r['instanceMapIds'] for r in rows))
        deadmines = next(m for m in self.report['maps'] if m['mapId'] == 36)
        self.assertIn(214, deadmines['objectivesWithOtherAreaSources'])

    def test_all_contexts_and_phases_preserved(self):
        self.assertEqual(sum(len(d['personas']) for d in self.report['datasets']), 18)
        targets = self.report['datasets'][0]['targets']
        self.assertEqual({t['phase'] for t in targets if t['questId'] == 166},
                         {'accept', 'objective', 'turnin'})
        ragefire = next(m for m in self.report['maps'] if m['mapId'] == 389)
        self.assertIn(5723, ragefire['phaseQuestIds']['objective'])


if __name__ == '__main__':
    unittest.main()
