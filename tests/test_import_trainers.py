import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('trainers', Path(__file__).resolve().parents[1] / 'tools/import_trainers.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TrainerImportTests(unittest.TestCase):
    def setUp(self):
        self.trainer = {'trainerType': 0, 'tradeskill': False, 'services': {'17': {'spellId': 17}}}
        self.skills = {1: {'ID': '1', 'CategoryID': '7'}, 2: {'ID': '2', 'CategoryID': '11'}}
        self.abilities = {17: [{'SkillLine': '1', 'ClassMask': '16'}]}

    def test_ambiguous_or_missing_links_do_not_assign_a_class(self):
        self.assertEqual(module.classify(self.trainer, self.abilities, self.skills)[0], {'classMask': 16})
        self.abilities[17].append({'SkillLine': '1', 'ClassMask': '128'})
        self.assertEqual(module.classify(self.trainer, self.abilities, self.skills)[0], {})
        profile, gaps = module.classify(self.trainer, {}, self.skills)
        self.assertEqual((profile, gaps), ({}, [17]))

    def test_shared_weapon_masks_are_not_exclusive_class_profiles(self):
        self.skills[1]['CategoryID'] = '6'
        self.abilities[17][0]['ClassMask'] = '1493'
        self.assertEqual(module.classify(self.trainer, self.abilities, self.skills)[0], {})

    def test_profession_uses_skill_identity_and_conflicts_stay_unknown(self):
        self.trainer.update(trainerType=2, tradeskill=True)
        self.abilities[17] = [{'SkillLine': '2', 'ClassMask': '0'}]
        self.assertEqual(module.classify(self.trainer, self.abilities, self.skills)[0], {'skill': 2})
        self.skills[3] = {'ID': '3', 'CategoryID': '9'}
        self.abilities[17].append({'SkillLine': '3', 'ClassMask': '0'})
        self.assertEqual(module.classify(self.trainer, self.abilities, self.skills)[0], {})


if __name__ == '__main__':
    unittest.main()
