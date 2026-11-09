import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("census",ROOT/"tools/audit_dungeons.py")
census=importlib.util.module_from_spec(spec);spec.loader.exec_module(census)

class DungeonCensus(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report=census.build();cls.maps={r['mapId']:r for r in cls.report['maps']}
    def test_type_and_special_maps(self):
        for mid,expected in [(36,'party'),(409,'raid'),(489,'battleground'),(369,'world-or-transport'),(13,'test-or-unused')]:
            self.assertEqual(self.maps[mid]['classification'],expected)
        self.assertEqual(self.maps[2959]['classification'],'party')
        self.assertEqual(self.maps[2980]['classification'],'world-or-transport')
    def test_zero_area_and_aliases(self):
        deadmines=self.maps[36]
        self.assertEqual(deadmines['nativeAreaId'],0)
        self.assertEqual(deadmines['areaId'],1581)
        self.assertIn(166,deadmines['categoryQuestIds'])
        self.assertIn(155,deadmines['possiblePrerequisiteIds'])
        self.assertIn(978,self.maps[209]['aliases'])
        self.assertIn(2768,self.maps[209]['categoryQuestIds'])
    def test_unresolved_records_stay_explicit(self):
        self.assertEqual(self.report['mapRead']['headerRecords'],81)
        self.assertEqual(self.report['mapRead']['unreadableRecords'],8)
        self.assertFalse(self.report['coverageLocked'])
        self.assertTrue(self.report['unmatchedProviderAreas'])
        self.assertFalse(self.report['identityConflicts'])
        self.assertFalse(any(r['itineraryReady'] for r in self.maps.values()))
    def test_complete_partition_and_no_quest_duplicates(self):
        self.assertEqual(sum(self.report['counts'].values()),len(self.maps))
        for row in self.maps.values():
            self.assertEqual(len(row['categoryQuestIds']),len(set(row['categoryQuestIds'])))
            self.assertFalse(set(row['categoryQuestIds']) & set(row['possiblePrerequisiteIds']))

if __name__=='__main__': unittest.main()
