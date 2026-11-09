"""Guard the external observation boundary; runtime routing is tested in Lua."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('import_flights', Path(__file__).resolve().parents[1] / 'tools/import_flights.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FlightObservations(unittest.TestCase):
    def setUp(self):
        self.data = {'meta': {'clientBuild': module.BUILD, 'product': 'wowf', 'schemaVersion': 1, 'license': 'CC BY 4.0'},
                     'routes': {'80>23': {'hops': [80, 25, 23], 'seconds': {'68': 2, '69': 1}, 'sources': 1}}}
        self.nodes = {80: {'Flags': '3'}, 25: {'Flags': '2'}, 23: {'Flags': '2'}}
        self.paths = [{'FromTaxiNode': '80', 'ToTaxiNode': '25'}, {'FromTaxiNode': '25', 'ToTaxiNode': '23'}]

    def read(self):
        return module.build_observations(self.data, self.nodes, self.paths)

    def test_histogram_and_multihop_identity(self):
        rows, excluded = self.read()
        self.assertFalse(excluded)
        self.assertEqual(rows[0]['faction'], 'Horde')
        self.assertEqual(rows[0]['hops'], [80, 25, 23])
        self.assertEqual(rows[0]['samples'], 3)
        self.assertAlmostEqual(rows[0]['seconds'], 205 / 3)

    def test_modifiers_unknown_routes_and_ambiguous_factions(self):
        self.data['routes']['80>23|frequentFlier:1'] = copy.deepcopy(self.data['routes']['80>23'])
        self.data['routes']['23>80'] = {'hops': [23, 80], 'costs': {'4': 100}}
        rows, excluded = self.read()
        self.assertEqual(len(rows), 1)
        self.assertIn('80>23|frequentFlier:1', excluded)
        self.paths.pop()
        self.assertFalse(self.read()[0])
        self.paths.append({'FromTaxiNode': '25', 'ToTaxiNode': '23'})
        for node in self.nodes.values():
            node['Flags'] = '3'
        self.assertFalse(self.read()[0])

    def test_wrong_build_corrupt_histogram_and_mismatched_hops_fail(self):
        original = copy.deepcopy(self.data)
        for histogram in [{'nan': 1}, {'0': 1}, {'80': -1}, {'80': 1.5}, {'80': True}]:
            self.data['routes']['80>23']['seconds'] = histogram
            with self.assertRaises(AssertionError):
                self.read()
        self.data = copy.deepcopy(original)
        self.data['routes']['80>23']['hops'] = [25, 23]
        with self.assertRaises(AssertionError):
            self.read()
        self.data = original
        self.data['meta']['clientBuild'] = '1.60.1.0'
        with self.assertRaises(AssertionError):
            self.read()


if __name__ == '__main__':
    unittest.main()
