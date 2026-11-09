#!/usr/bin/env python3
"""Import pinned client topology, InFlight times and same-build flight observations."""
import argparse
import csv
import hashlib
import json
import math
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = '1.60.1.70862'
REV = '2efdd7ba6d0e094edf84a04eeb40c038f004ea52'
EG_REV = '156f29c9af78b1586883e8eb94a13467eb89638c'
EG_FILE = f'eg-link-{EG_REV[:8]}/{BUILD}/flights.json'
EG_HASH = '5e79d3e676517a43d243cca9f1adbdfff495bd75abf2f012885bab14798f89aa'
PINS = {
    f'TaxiNodes-{BUILD}.csv': '4360793e0edfbb8de62d12d87a69260b6a1bc6314b1e506b141c33e8802d8249',
    f'TaxiPath-{BUILD}.csv': '3e5c18b53621ca7cd2618447e12498874e6aba7aa7f1f6bfda9a7977979da179',
    f'TaxiPathNode-{BUILD}.csv': 'f83f8d8e5bbeae889214f48af477dd51a4c1771ff3c3b53c3fa2cacf2cba7cdb',
    f'InFlight-{REV}-Defaults.lua': '1cffe287a433e423a29d5b0442dc547da477dfc41a23f313108f33bd735b3a0a',
    f'InFlight-{REV}-LICENSE': 'e5f058cf153f069d5b93e3742b8b9ea1013e0ba4a5248bc60414b954699ed4e3',
}


def observations(text, section):
    # Only consume these literal tables, never execute the addon's settings or era-selection code.
    match = re.search(r'^local ' + section + r' = \{\n(.*?)^\}', text, re.M | re.S)
    assert match, section
    result, side, origin = {}, None, None
    for line in match[1].splitlines():
        faction = re.fullmatch(r'  \["(Horde|Alliance)"\] = \{', line)
        source = re.fullmatch(r'    \[(\d+)\] = \{', line)
        value = re.fullmatch(r'      \[(\d+)\] = (\d+),', line)
        if faction:
            side, origin = faction[1], None
        elif source:
            origin = int(source[1])
        elif re.fullmatch(r'    \[".*"\] = \{.*', line):
            origin = None  # Named gossip flights have no native taxi node identity.
        elif value:
            if origin is None:
                continue
            assert side
            key = (side, origin, int(value[1]))
            assert key not in result and int(value[2]) > 0
            result[key] = int(value[2])
        elif line.strip().startswith('[') and not re.fullmatch(r'      \[".*"\] = (".*"|\d+),.*', line):
            raise ValueError('Unexpected literal in ' + section + ': ' + line)
    return result


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
        if name.startswith('InFlight-'):
            continue
        table = name.split('-')[0]
        tables[table] = list(csv.DictReader(path.open()))
        sources.append({'url': f'https://wago.tools/db2/{table}/csv?build={BUILD}&locale=enUS', 'sha256': digest})
    defaults = ROOT / '.dependencies' / f'InFlight-{REV}-Defaults.lua'
    license_path = ROOT / '.dependencies' / f'InFlight-{REV}-LICENSE'
    for path in [defaults, license_path]:
        sources.append({'url': f'https://raw.githubusercontent.com/LudiusMaximus/InFlight/{REV}/{path.name.split(REV + "-")[1]}',
                        'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    text = defaults.read_text()
    durations = observations(text, 'global_classic')
    durations.update(observations(text, 'global_forever'))
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
    paths, rejected = [], []
    for row in tables['TaxiPath']:
        origin, dest = int(row['FromTaxiNode']), int(row['ToTaxiNode'])
        track = geometry[int(row['ID'])]
        if (origin not in nodes or dest not in nodes or len(track) < 2 or
                any(int(p['Delay']) or int(p['ContinentID']) != int(nodes[origin]['ContinentID']) for p in track) or
                nodes[origin]['ContinentID'] != nodes[dest]['ContinentID']):
            rejected.append(int(row['ID']))
        else:
            ordered = sorted(track, key=lambda p: int(p['NodeIndex']))
            for endpoint, key in [(ordered[0], 'FromTaxiNode'), (ordered[-1], 'ToTaxiNode')]:
                node = nodes[int(row[key])]
                assert math.hypot(float(endpoint['Loc_0']) - float(node['Pos_0']),
                                  float(endpoint['Loc_1']) - float(node['Pos_1'])) <= 25, row['ID']
            paths.append(row)
    kept = {(side, origin, dest): seconds for (side, origin, dest), seconds in durations.items()
            if origin in nodes and dest in nodes and nodes[origin]['ContinentID'] == nodes[dest]['ContinentID'] and
            int(nodes[origin]['Flags']) & (1 if side == 'Alliance' else 2) and
            int(nodes[dest]['Flags']) & (1 if side == 'Alliance' else 2)}
    observed_path = ROOT / '.dependencies' / EG_FILE
    assert hashlib.sha256(observed_path.read_bytes()).hexdigest() == EG_HASH
    observed, excluded_observed = build_observations(json.loads(observed_path.read_text()), nodes, paths)
    sources.append({'url': f'https://raw.githubusercontent.com/JIVESCORP/eg-link-output-wowf/{EG_REV}/data/wowf/{BUILD}/flights.json',
                    'sha256': EG_HASH, 'license': 'CC BY 4.0'})
    lines = ['local _,A=...', '-- Generated by tools/import_flights.py; external reference, not client verification.',
             f'A.FlightData={{version="{BUILD}:{REV[:12]}",clientVersion="1.60.1",build=70862,interface=16001,nodes={{']
    quote = lambda value: json.dumps(value, ensure_ascii=False)
    for node, row in sorted(nodes.items()):
        xyz = ','.join(row[f'Pos_{i}'] for i in range(3))
        lines.append(f' [{node}]={{name={quote(row["Name_lang"])},world={{{xyz}}},instance={row["ContinentID"]},'
                     f'factionMask={int(row["Flags"]) & 3},condition={row["ConditionID"]},visibility={row["VisibilityConditionID"]}}},')
    lines += ['},paths={']
    for row in sorted(paths, key=lambda x: int(x['ID'])):
        lines.append(f' [{row["ID"]}]={{{row["FromTaxiNode"]},{row["ToTaxiNode"]},{row["Cost"]}}},')
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
             'notes': ['Durations are directed and faction-specific; Classic Era plus Forever overrides only.',
                       'Same-build EG Link duration histograms override InFlight references; local valid samples retain priority.',
                       'Observed routes must match client topology and identify exactly one faction; speed-modified variants are excluded.',
                       'Observation counts are external evidence, not this character\'s learned samples; native fares and unlocks remain required.',
                       'A duration pair may contain intermediate stops; it is not an assertion of a direct flight edge.',
                       'Native discovered/available destinations and actual fares gate every suggested flight.',
                       'Client base costs are catalog metadata, never substituted for unknown native fares.']}
    outputs = {ROOT / 'Data/Flights.lua': '\n'.join(lines),
               ROOT / 'docs/FLIGHT_DATA_AUDIT.json': json.dumps(audit, ensure_ascii=False, indent=2) + '\n',
               ROOT / 'docs/LICENSE.InFlight.txt': license_path.read_text()}
    for path, output in outputs.items():
        if args.check:
            assert path.read_text() == output, path
        else:
            path.write_text(output)
    print(f'Flight reference: {len(nodes)} nodes, {len(paths)} directed paths, {len(kept)} faction duration pairs, {len(observed)} same-build observations')


if __name__ == '__main__':
    main()
