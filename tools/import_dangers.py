#!/usr/bin/env python3
"""Convert the pinned, separately licensed danger/first-aid data to plain tables."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '.dependencies/RestedXP-d583b89e'
REV = 'd583b89e455d73be6b93970579f074ecf6bb6326'
HASHES = {'dangerousMobs.lua': '783de951105616ef5224199d8fa5e6f957c46d708f238bf6176c3a55b70a65ca',
          'db.lua': '16efb559a503dc66a6d5cbdc1dbee36a76786b257713289001b350e56630200e'}

EXTRACT = r'''
local function json(value)
    if type(value)=="string" then return '"'..value:gsub('[%z\1-\31\\"]',function(c) return string.format('\\u%04x',c:byte()) end)..'"' end
    if type(value)=="number" or type(value)=="boolean" then return tostring(value) end
    local parts={}
    for k,v in pairs(value) do parts[#parts+1]=json(tostring(k))..':'..json(v) end
    return '{'..table.concat(parts,',')..'}'
end
for _,faction in ipairs({"Alliance","Horde"}) do
    local addon={game="FOREVER"}
    local chunk=assert(loadfile(arg[1]))
    setfenv(chunk,{_G={UnitFactionGroup=function() return faction end}})
    chunk("reference",addon)
    print(json({faction=faction,zones=addon.dangerousMobs}))
end
'''


def main():
    for name, digest in HASHES.items():
        assert hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() == digest, name
    dangerous = SOURCE / 'dangerousMobs.lua'
    db = (SOURCE / 'db.lua').read_text()
    maps = dict((name, int(number)) for name, number in re.findall(
        r'\["([^"]+)"\]\s*=\s*(\d+)', db.split('addon.mapId = {', 1)[1].split('\n}', 1)[0]))
    raw = subprocess.check_output(['lua5.1', '-', str(dangerous)], input=EXTRACT, text=True)
    data, counts, excluded = {}, {}, []
    for document in map(json.loads, raw.splitlines()):
        faction, zones = document['faction'], document['zones']
        data[faction] = {}
        counts[faction] = {'records': 0, 'pins': 0, 'patrols': 0}
        for zone, mobs in sorted(zones.items()):
            if zone not in maps:
                excluded.append({'faction': faction, 'zone': zone, 'reason': 'Not in the fixed Forever map table',
                                 'records': sum(len(rows) for rows in mobs.values())})
                continue
            for name, records in sorted(mobs.items()):
                for _, row in sorted(records.items(), key=lambda item: int(item[0])):
                    assert not row.get('applies'), (zone, name, row['applies'])
                    positions = []
                    for command in re.split(r'[;\r\n]+', row['Location']):
                        command = command.strip()
                        if not command:
                            continue
                        if command.startswith(('.mob ', '.unitscan ', '.target ')):
                            continue
                        match = re.fullmatch(r'\.(pin|line) ([^,]+),([\d.,\s]+)(?:\([^)]*\))?', command)
                        assert match, (zone, name, command)
                        kind, map_name, coordinates = match.groups()
                        map_id = maps[map_name] if map_name in maps else int(map_name)
                        coords = [float(number.strip()) / 100 for number in coordinates.strip().rstrip(',').split(',')]
                        assert len(coords) >= 2 and len(coords) % 2 == 0 and all(0 <= number <= 1 for number in coords), (name, command)
                        if kind == 'pin':
                            assert len(coords) == 2, command
                        positions.append((map_id, kind, coords))
                    assert positions, (zone, name)
                    counts[faction]['records'] += 1
                    by_map = {}
                    for map_id, kind, coords in positions:
                        counts[faction]['pins' if kind == 'pin' else 'patrols'] += 1
                        entry = by_map.setdefault(map_id, {
                            'name': name, 'minLevel': row['MinLevel'], 'maxLevel': row['MaxLevel'],
                            'classification': row['Classification'], 'movement': row.get('Movement', ''),
                            'note': row.get('Notes', ''), 'points': [], 'paths': []})
                        if kind == 'pin':
                            entry['points'].extend(coords)
                        else:
                            entry['paths'].append(coords)
                    for map_id, entry in by_map.items():
                        data[faction].setdefault(map_id, []).append(entry)
    item_block = db.split('addon.emergencyItems = {', 1)[1].split('\n}', 1)[0]
    spell_block = db.split('addon.emergencySpells = {', 1)[1].split('\n}', 1)[0]
    item_ids = sorted(set(map(int, re.findall(r'\[(\d+)\]', item_block))))
    spell_ids = sorted(set(map(int, re.findall(r'\[(\d+)\]', spell_block))))

    def lua(value):
        if isinstance(value, bool):
            return str(value).lower()
        if isinstance(value, (int, float)):
            return format(value, '.8g')
        if isinstance(value, str):
            return json.dumps(value, ensure_ascii=False)
        if isinstance(value, list):
            return '{' + ','.join(map(lua, value)) + '}'
        return '{' + ','.join('[' + lua(key) + ']=' + lua(item) for key, item in value.items()) + '}'

    lines = ['local _,A=...', '-- RestedXP contributors, CC BY-NC-SA 4.0; see docs/LICENSE.RestedXP.txt.',
             '-- Adapted from pinned Forever data by tools/import_dangers.py; no guide parser at runtime.', 'A.DangerData={']
    for faction, zones in data.items():
        lines.append('[' + lua(faction) + ']={')
        for map_id, rows in sorted(zones.items()):
            lines.append('[' + str(map_id) + ']={')
            lines.extend(lua(row) + ',' for row in rows)
            lines.append('},')
        lines.append('},')
    lines.append('items=' + lua(dict.fromkeys(item_ids, True)) + ',')
    lines.append('spells=' + lua(dict.fromkeys(spell_ids, True)) + '}\n')
    (ROOT / 'Data/Dangers.lua').write_text('\n'.join(lines))
    audit = {'source': f'https://github.com/RestedXP/RXPGuides/tree/{REV}/DB/forever',
             'license': 'CC BY-NC-SA 4.0', 'licenseFile': 'docs/LICENSE.RestedXP.txt',
             'changes': 'Convert fixed map locations/patrols and emergency item/spell IDs to plain data; preserve faction, level and notes.',
             'sourceSha256': {name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() for name in ['dangerousMobs.lua', 'db.lua']},
             'counts': counts, 'excludedZones': excluded, 'emergencyItems': len(item_ids), 'emergencySpells': len(spell_ids)}
    (ROOT / 'docs/DANGER_DATA_AUDIT.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2) + '\n')
    (ROOT / 'docs/LICENSE.RestedXP.txt').write_text((SOURCE / 'LICENSE').read_text())
    print(json.dumps(audit['counts']), len(item_ids), len(spell_ids))


if __name__ == '__main__':
    main()
