import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("playable", ROOT / "tools/audit_playable.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PlayableCoverageTests(unittest.TestCase):
    def test_current_build_matches_official_without_marking_content_complete(self):
        report = module.build()
        rows = report["combinations"]
        self.assertEqual(len(rows), 56)
        self.assertEqual(sum(r["faction"] == "Alliance" for r in rows), 28)
        self.assertFalse(report["coverageLocked"])
        self.assertFalse(report["clientVerified"])
        for race_id, mask in ((95, 4294967296), (96, 8589934592)):
            skyborne = [r for r in rows if r["raceId"] == race_id]
            self.assertEqual(len(skyborne), 5)
            self.assertTrue(all(r["raceMask"] == mask for r in skyborne))
        for row in rows:
            ids = row["unknownOrScalingLevelQuestIds"] + row["aboveScopeQuestIds"]
            for band in row["bands"]:
                self.assertEqual(band["coverageStatus"], "unverified")
                ids += band["questIds"]
            self.assertEqual(len(ids), len(set(ids)))
            self.assertEqual(len(ids), row["maskCompatibleTasks"])

    def test_high_race_bit_and_persona_overrides_are_preserved(self):
        p = {"faction": "Horde", "class": "SHAMAN", "raceMask": 2**33, "classMask": 64}
        quests = {"1": {"id": 1, "raceMask": 2**32, "classMask": 64, "level": 1, "gaps": []},
                  "2": {"id": 2, "raceMask": 2**33, "classMask": 64, "level": -1, "gaps": []}}
        audit = {"base": {"persona": {"faction": "Alliance", "class": "SHAMAN"}, "quests": quests},
                 "variants": [{"persona": p, "questOverrides": {"1": dict(quests["1"], raceMask=2**33, level=60)}}]}
        self.assertFalse(module.compatible(quests["1"], p))
        self.assertTrue(module.compatible(quests["2"], p))
        self.assertFalse(module.compatible(dict(quests["2"], classMask=1), p))
        self.assertFalse(module.compatible(dict(quests["2"], raceMask=None), p))
        result = module.project([p], audit)[0]
        self.assertEqual(result["bands"][-1]["questIds"], [1])
        self.assertEqual(result["unknownOrScalingLevelQuestIds"], [2])

    def test_changed_source_duplicate_ids_and_matrix_disagreement_fail(self):
        name = next(iter(module.INPUTS))
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / name).parent.mkdir(parents=True)
            (root / name).write_text("ID,RaceID,ClassID\n1,1,1\n")
            with self.assertRaises(ValueError):
                module.read_pinned(root, name)
        with self.assertRaises(ValueError):
            module.csv_index("ID,RaceID,ClassID\n1,1,1\n1,1,2\n")
        texts = [module.read_pinned(ROOT, n) for n in module.INPUTS]
        base, races, classes = [module.csv_index(t) for t in texts[:3]]
        base.pop(next(iter(base)))
        with self.assertRaises(AssertionError):
            module.census(base, races, classes, texts[3])


if __name__ == "__main__":
    unittest.main()
