import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('admission', Path(__file__).resolve().parents[1] / 'tools/audit_dungeon_admission.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class AdmissionEvidenceTests(unittest.TestCase):
    def test_missing_condition_is_not_an_empty_condition_and_difficulties_stay_separate(self):
        maps = [{'mapId': 36, 'name': '死亡矿井', 'classification': 'party'},
                {'mapId': 999, 'name': '测试', 'classification': 'test-or-unused'}]
        tables = {name: {} for name in audit.PINS}
        tables['MapDifficulty'] = {1: {'MapID': '36', 'DifficultyID': '1', 'ContentTuningID': '5'},
                                  2: {'MapID': '36', 'DifficultyID': '213', 'ContentTuningID': '0'}}
        tables['MapDifficultyXCondition'] = {
            1: {'ID': '1', 'MapDifficultyID': '1', 'PlayerConditionID': '100', 'OrderIndex': '1'},
            2: {'ID': '2', 'MapDifficultyID': '1', 'PlayerConditionID': '101', 'OrderIndex': '2'}}
        tables['PlayerCondition'] = {101: {'ID': '101', 'ContentTuningID': '0', 'MinLevel': '0'}}
        tables['ContentTuning'] = {5: {'ID': '5', 'MinLevelSquish': '16'}}
        tables['LFGDungeons'] = {1: {'MapID': '0', 'Name_lang': '死亡矿井', 'ContentTuningID': '5'},
                                 2: {'MapID': '36', 'Name_lang': 'Exact'}}
        report = audit.join(maps, tables)
        self.assertEqual(len(report['maps']), 1)
        normal, other = report['maps'][0]['difficulties']
        self.assertEqual(normal['missingConditionIds'], [100])
        self.assertIsNone(normal['conditions'][0]['record'])
        self.assertEqual(normal['conditions'][1]['status'], 'present')
        self.assertEqual(other['conditions'], [])
        self.assertFalse(other['admissionVerified'])
        self.assertEqual(len(report['maps'][0]['lfgByMapId']), 1)
        self.assertEqual(len(report['lfgWithoutMapId']), 1)

    def test_duplicate_ids_and_changed_sources_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'table.csv'
            raw = b'ID,MapID\n1,36\n1,43\n'
            path.write_bytes(raw)
            with self.assertRaisesRegex(AssertionError, 'duplicate'):
                audit.read_table(path, hashlib.sha256(raw).hexdigest())
            with self.assertRaisesRegex(AssertionError, 'input changed'):
                audit.read_table(path, '0'*64)

    def test_pinned_real_build_retains_conflicting_raw_fields(self):
        report = audit.build()
        self.assertEqual(report['counts']['partyMaps'], 34)
        self.assertEqual(report['counts']['referencedConditions'], 42)
        self.assertEqual(report['counts']['missingConditions'], 33)
        scholo = next(m for m in report['maps'] if m['mapId'] == 289)
        normal = next(d for d in scholo['difficulties'] if d['record']['DifficultyID'] == '1')
        level = next(c for c in normal['conditions'] if c['link']['PlayerConditionID'] == '159274')
        self.assertEqual(level['record']['MinLevel'], '10')
        self.assertEqual(level['record']['MaxLevel'], '20')
        self.assertEqual(level['record']['Flags'], '33')
        self.assertEqual(level['contentTuning']['MinLevelSquish'], '50')
        self.assertIn('33', normal['record']['Message_lang'])
        self.assertFalse(normal['admissionVerified'])


if __name__ == '__main__':
    unittest.main()
