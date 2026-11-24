#!/usr/bin/env python3
"""Import Forever flight paths and estimate their duration from same-build observations."""
import argparse
import csv
import hashlib
import json
import math
import re
from collections import defaultdict
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parents[1]
BUILD = '1.60.1.70862'

EG_REV = '30c3bb9c8e792208feab362357471603dc51e12e'
EG_FILE = f'eg-link-{EG_REV[:8]}/{BUILD}/flights.json'
EG_HASH = '41531a30f3900c91f5c62f9d888779e92e6673318f541d5df1b2cd1df10c82f3'
PINS = {
    f'TaxiNodes-{BUILD}.csv': '4360793e0edfbb8de62d12d87a69260b6a1bc6314b1e506b141c33e8802d8249',
    f'TaxiPath-{BUILD}.csv': '3e5c18b53621ca7cd2618447e12498874e6aba7aa7f1f6bfda9a7977979da179',
    f'TaxiPathNode-{BUILD}.csv': 'f83f8d8e5bbeae889214f48af477dd51a4c1771ff3c3b53c3fa2cacf2cba7cdb',
}


def build_observations(data, nodes, paths):
    assert data['meta']['clientBuild'] == BUILD and data['meta']['product'] == 'wowf'
    assert data['meta']['schemaVersion'] == 1 and data['meta']['license'] == 'CC BY 4.0'
    edges = {(int(row['FromTaxiNode']), int(row['ToTaxiNode'])) for row in paths}
    kept, excluded = [], {}
    for key, route in sorted(data['routes'].items()):
        if not route.get('seconds'):
            continue
        match = re.fullmatch(r'(\d+)>(\d+)', key)
        if not match:
            excluded[key] = 'modified flight speed or unsupported route key'
            continue
        origin, dest = map(int, match.groups())
        hops = route['hops']
        assert len(hops) >= 2 and hops[0] == origin and hops[-1] == dest and len(set(hops)) == len(hops), key
        if any(node not in nodes for node in hops) or any(pair not in edges for pair in zip(hops, hops[1:])):
            excluded[key] = 'route not in current client topology'
            continue
        mask = 3
        for node in hops:
            mask &= int(nodes[node]['Flags']) & 3
        if mask not in (1, 2):
            excluded[key] = 'observing faction cannot be identified from the route'
            continue
        samples = []
        for seconds, count in route['seconds'].items():
            seconds = float(seconds)
            assert math.isfinite(seconds) and 1 <= seconds <= 7200, key
            assert type(count) is int and count > 0, key
            samples.append((seconds, count))
        count = sum(n for _, n in samples)
        kept.append({'key': f'{origin}:{dest}', 'faction': 'Alliance' if mask == 1 else 'Horde',
                     'seconds': sum(seconds * n for seconds, n in samples) / count,
                     'samples': count, 'sources': route['sources'], 'hops': hops})
    return kept, excluded


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    sources, tables = [], {}
    for name, digest in PINS.items():
        path = ROOT / '.dependencies' / name
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, name
        table = name.split('-')[0]
        tables[table] = list(csv.DictReader(path.open()))
        sources.append({'url': f'https://wago.tools/db2/{table}/csv?build={BUILD}&locale=enUS', 'sha256': digest})
    names_path = ROOT / '.dependencies' / f'TaxiNodes-{BUILD}-zhCN.csv'
    names_hash = '31d33d135eb97b6b561f74fb3563b68fd163274ce9fbebd228f2161a1499ce09'
    assert hashlib.sha256(names_path.read_bytes()).hexdigest() == names_hash
    with names_path.open() as stream:
        zh_names = {int(row['ID']): row['Name_lang'] for row in csv.DictReader(stream)}
    sources.append({'url': f'https://wago.tools/db2/TaxiNodes/csv?build={BUILD}&locale=zhCN', 'sha256': names_hash})
    # SPELL_EFFECT_SEND_TAXI tracks belong to spells or gossip, not the regular taxi menu.
    effects_name = f'SpellEffect-{BUILD}-zhCN.csv'
    effects = ROOT / '.dependencies' / effects_name
    digest = 'cc8f167fe246b495294b560196f6c59439f703e8f937ddb6acd81157bd5f8b9c'
    assert hashlib.sha256(effects.read_bytes()).hexdigest() == digest
    with effects.open() as stream:
        spell_paths = {r['EffectMiscValue_0'] for r in csv.DictReader(stream) if r['Effect'] == '123'}
    spell_pairs = {(r['FromTaxiNode'], r['ToTaxiNode']) for r in tables['TaxiPath'] if r['ID'] in spell_paths}
    sources.append({'url': f'https://wago.tools/db2/SpellEffect/csv?build={BUILD}&locale=zhCN', 'sha256': digest})
    nodes = {}
    excluded = []
    for row in tables['TaxiNodes']:
        node = int(row['ID'])
        if (not int(row['Flags']) & 3 or int(row['ContinentID']) not in {0, 1, 2991} or
                row['Name_lang'].startswith(('zzOLD', 'Quest ')) or
                not (int(row['MountCreatureID_0']) or int(row['MountCreatureID_1']))):
            excluded.append(node)
            continue
        nodes[node] = row
    geometry = defaultdict(list)
    for row in tables['TaxiPathNode']:
        geometry[int(row['PathID'])].append(row)
    paths, rejected, lengths = [], [], {}
    for row in tables['TaxiPath']:
        origin, dest = int(row['FromTaxiNode']), int(row['ToTaxiNode'])
        track = geometry[int(row['ID'])]
        if ((row['FromTaxiNode'], row['ToTaxiNode']) in spell_pairs or
                origin not in nodes or dest not in nodes or len(track) < 2 or
                any(int(p['Delay']) or int(p['ContinentID']) != int(nodes[origin]['ContinentID']) for p in track) or
                nodes[origin]['ContinentID'] != nodes[dest]['ContinentID']):
            rejected.append(int(row['ID']))
        else:
            ordered = sorted(track, key=lambda p: int(p['NodeIndex']))
            for endpoint, key in [(ordered[0], 'FromTaxiNode'), (ordered[-1], 'ToTaxiNode')]:
                node = nodes[int(row[key])]
                assert math.hypot(float(endpoint['Loc_0']) - float(node['Pos_0']),
                                  float(endpoint['Loc_1']) - float(node['Pos_1'])) <= 25, row['ID']
            coords = [tuple(float(point[f'Loc_{i}']) for i in range(3)) for point in ordered]
            length = sum(math.dist(a, b) for a, b in zip(coords, coords[1:]))
            assert length > 0, row['ID']
            # The client can contain alternate tracks between identical endpoints.
            lengths[origin, dest] = length if (origin, dest) not in lengths else None
            paths.append(row)
    observed_path = ROOT / '.dependencies' / EG_FILE
    assert hashlib.sha256(observed_path.read_bytes()).hexdigest() == EG_HASH
    observed, excluded_observed = build_observations(json.loads(observed_path.read_text()), nodes, paths)
    sources.append({'url': f'https://raw.githubusercontent.com/JIVESCORP/eg-link-output-wowf/{EG_REV}/data/wowf/{BUILD}/flights.json',
                    'sha256': EG_HASH, 'license': 'CC BY 4.0'})
    speeds = [lengths[tuple(row['hops'])] / row['seconds'] for row in observed if len(row['hops']) == 2 and lengths[tuple(row['hops'])]]
    base_speed = median(speeds)
    kept = {}
    for (origin, dest), distance in lengths.items():
        if distance is None:
            continue
        for side, bit in [('Alliance', 1), ('Horde', 2)]:
            if int(nodes[origin]['Flags']) & int(nodes[dest]['Flags']) & bit:
                kept[side, origin, dest] = max(1, round(distance / base_speed))
    # Retain the key used by saved character measurements. It is independent of estimated times.
    lines = ['local _,A=...', '-- Generated by tools/import_flights.py; external reference, not client verification.',
             f'A.FlightData={{version="{BUILD}:2efdd7ba6d0e",clientVersion="1.60.1",build=70862,interface=16001,nodes={{']
    quote = lambda value: json.dumps(value, ensure_ascii=False)
    for node, row in sorted(nodes.items()):
        xyz = ','.join(row[f'Pos_{i}'] for i in range(3))
        lines.append(f' [{node}]={{name={quote(row["Name_lang"])},zhCN={quote(zh_names[node])},world={{{xyz}}},instance={row["ContinentID"]},'
                     f'factionMask={int(row["Flags"]) & 3},condition={row["ConditionID"]},visibility={row["VisibilityConditionID"]}}},')
    lines += ['},paths={']
    for row in sorted(paths, key=lambda x: int(x['ID'])):
        lines.append(f' [{row["ID"]}]={{{row["FromTaxiNode"]},{row["ToTaxiNode"]}}},')
    lines += ['},durations={']
    for side in ['Alliance', 'Horde']:
        lines.append(f' {side}={{')
        for (faction, origin, dest), seconds in sorted(kept.items()):
            if faction == side:
                lines.append(f'  ["{origin}:{dest}"]={seconds},')
        lines.append(' },')
    lines += ['},observedDurations={']
    for side in ['Alliance', 'Horde']:
        lines.append(f' {side}={{')
        for row in observed:
            if row['faction'] == side:
                lines.append(f'  ["{row["key"]}"]={row["seconds"]:.10g},')
        lines.append(' },')
    lines += ['},observedHops={']
    for side in ['Alliance', 'Horde']:
        lines.append(f' {side}={{')
        for row in observed:
            if row['faction'] == side:
                lines.append(f'  ["{row["key"]}"]="{":".join(map(str, row["hops"]))}",')
        lines.append(' },')
    lines += ['}}', '']
    audit = {'build': BUILD, 'sources': sources, 'inputRows': {key: len(rows) for key, rows in tables.items()},
             'referenceNodes': len(nodes), 'referenceDirectedPaths': len(paths), 'factionDurationPairs': len(kept),
             'excludedNodes': sorted(excluded), 'excludedPaths': sorted(rejected), 'clientVerified': False,
             'buildObservations': observed, 'excludedBuildObservations': excluded_observed,
             'spellTaxiPaths': sorted(int(r['ID']) for r in tables['TaxiPath'] if r['ID'] in spell_paths),
             'calibration': {'directObservations': len(speeds), 'medianYardsPerSecond': base_speed},
             'notes': ['Estimates use only directed Forever TaxiPathNode tracks with same-faction endpoints.',
                       'The reference speed is the median of direct regular-speed Forever route measurements.',
                       'Matching observed hops and then character samples supersede the geometry estimate.',
                       'Flight eligibility still requires learned nodes and native availability.']}
    outputs = {ROOT / 'Data/Flights.lua': '\n'.join(lines),
               ROOT / 'docs/FLIGHT_DATA_AUDIT.json': json.dumps(audit, ensure_ascii=False, indent=2) + '\n'}
    for path, output in outputs.items():
        if args.check:
            assert path.read_text() == output, path
        else:
            path.write_text(output)
    print(f'Flight reference: {len(nodes)} nodes, {len(paths)} directed paths, {len(kept)} faction duration pairs, {len(observed)} same-build observations')


if __name__ == '__main__':
    main()
