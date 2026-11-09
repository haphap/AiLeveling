#!/usr/bin/env python3
"""Replay fixed native encounter identities against the shipped dungeon catalog, offline."""
import csv
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / '.dependencies/eg-link-156f29c9/1.60.1.70862/encounters.json'
assert hashlib.sha256(source.read_bytes()).hexdigest() == '5e528485bf73b2cb80c34a13e2795a1bb48f44b21a904036c998004b5f11c4c8'
records = json.loads(source.read_text())
assert records['meta']['clientBuild'] == '1.60.1.70862'
table = ROOT / '.dependencies/DungeonEncounter-1.60.1.70862-zhCN.csv'
assert hashlib.sha256(table.read_bytes()).hexdigest() == '13c1a984836ccd90fc0adb56d7a52aeacab794b7276e836f30e18a80725e8677'
census = json.loads((ROOT / 'docs/DUNGEON_COVERAGE.json').read_text())
maps = {m['mapId'] for m in census['maps'] if m['classification'] == 'party'}
rows = [r for r in csv.DictReader(table.open()) if int(r['MapID']) in maps]
assert len(rows) == 263 and len({r['MapID'] for r in rows}) == 27
roster = ['{%s,%s,%s,%s}' % (r['ID'], r['MapID'], r['DifficultyID'], json.dumps(r['Name_lang'], ensure_ascii=False)) for r in rows]
cases = []
for key, record in records['encounters'].items():
    for difficulty in record['difficulties']:
        cases.append('{%d,%d,%d,%s}' % (int(key), record['map'], int(difficulty), json.dumps(record['name'], ensure_ascii=False)))
script = '''
local A={Content={dungeons={}},char={samples={}},state={clientVersion="1.60.1",clientBuild="70862"},RequestRefresh=function() end}
for _,file in ipairs({"Planner/Dungeon.lua","Planner/DungeonTasks.lua","Data/Dungeons.lua"}) do assert(loadfile(file))("AiLeveling",A) end
local cases={%s}
local roster={%s}
local count=0
for _ in pairs(A.DungeonCatalog.encounters) do count=count+1 end
assert(count==#roster)
for _,row in ipairs(roster) do
    local id,map,diff,title=unpack(row)
    local r=A.Dungeon.EncounterIdentity(id,A.state)
    assert(r and r.instanceId==map and r.difficultyId==diff and r.title==title)
    local difficulty=diff==0 and 1 or diff
    GetInstanceInfo=function() return "catalog","party",difficulty,nil,nil,nil,nil,map end
    A.state.inInstance,A.state.instanceId,A.state.instanceDifficultyId=true,map,difficulty
    A.Dungeon:EncounterEvent("PLAYER_ENTERING_WORLD")
    A.Dungeon:EncounterEvent("ENCOUNTER_START",id,nil,difficulty,5)
    A.Dungeon:EncounterEvent("ENCOUNTER_END",id,nil,difficulty,5,1)
    assert(A.Dungeon.encounterVisit.kills[id]==title)
    local wrongMap=map==48 and 389 or 48
    GetInstanceInfo=function() return "wrong map","party",difficulty,nil,nil,nil,nil,wrongMap end
    A.Dungeon:EncounterEvent("PLAYER_ENTERING_WORLD")
    A.Dungeon:EncounterEvent("ENCOUNTER_START",id,title,difficulty,5)
    A.Dungeon:EncounterEvent("ENCOUNTER_END",id,title,difficulty,5,1)
    assert(A.Dungeon.encounterVisit==nil)
    if diff>0 then
        difficulty=diff+1
        GetInstanceInfo=function() return "wrong difficulty","party",difficulty,nil,nil,nil,nil,map end
        A.Dungeon:EncounterEvent("ENCOUNTER_START",id,title,difficulty,5)
        A.Dungeon:EncounterEvent("ENCOUNTER_END",id,title,difficulty,5,1)
        assert(A.Dungeon.encounterVisit==nil)
    end
end
-- Distinct encounters sharing a completion bit must not be collapsed.
assert(A.DungeonCatalog.encounters[3493] and A.DungeonCatalog.encounters[3495])
for _,case in ipairs(cases) do
    local id,map,difficulty,name=unpack(case)
    local selected
    for _,d in pairs(A.Dungeon.Catalog(A.state,A.Content)) do if d.instanceId==map then selected=d;break end end
    assert(selected,"Observed encounter lacks a matching catalog instance")
    local record=A.Dungeon.EncounterIdentity(id,A.state)
    assert(record and record.instanceId==map and (record.difficultyId==0 or record.difficultyId==difficulty))
    GetInstanceInfo=function() return selected.title,"party",difficulty,nil,nil,nil,nil,map end
    A.state.inInstance,A.state.instanceId,A.state.instanceDifficultyId=true,map,difficulty
    A.Dungeon:EncounterEvent("PLAYER_ENTERING_WORLD")
    A.Dungeon:EncounterEvent("ENCOUNTER_START",id,name,difficulty,5)
    A.Dungeon:EncounterEvent("ENCOUNTER_END",id,name,difficulty,5,1)
    assert(A.Dungeon.EncounterProgress(selected,A.state):find(name,1,true))
    assert(A.Dungeon.encounterVisit.count==1)
    A.Dungeon:EncounterEvent("ENCOUNTER_END",id,name,difficulty,5,1)
    assert(A.Dungeon.encounterVisit.count==1)
    assert(A.char.dungeon==nil and next(A.char.samples)==nil)
    A.state.clientBuild="other"
    A.Dungeon:EncounterEvent("PLAYER_ENTERING_WORLD")
    A.Dungeon:EncounterEvent("ENCOUNTER_START",id,name,difficulty,5)
    A.Dungeon:EncounterEvent("ENCOUNTER_END",id,name,difficulty,5,1)
    assert(A.Dungeon.encounterVisit==nil)
    A.state.clientBuild="70862"
end
print(#roster.." catalog identities and "..#cases.." observed encounter identities replayed; map/difficulty/build boundaries passed; no full-run inference")
''' % (','.join(cases), ','.join(roster))
subprocess.run(['lua5.1', '-'], input=script, text=True, cwd=ROOT, check=True)
inputs = [source, table, ROOT/'docs/DUNGEON_COVERAGE.json', ROOT/'Data/Dungeons.lua', ROOT/'Planner/Dungeon.lua', Path(__file__).resolve()]
report = {'clientBuild': '1.60.1.70862', 'catalogIdentities': len(rows), 'catalogMaps': 27,
          'observedIdentities': len(cases), 'result': 'passed', 'clientVerified': False,
          'limits': ['Encounter identities do not identify mandatory route completion sets or prove full clears.',
                     'Difficulty zero is unspecified; it is not positive proof of availability in every difficulty.',
                     'Unknown native identities remain observable; known conflicting map/difficulty identities are rejected.'],
          'inputs': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}}
(ROOT/'docs/DUNGEON_ENCOUNTER_REPLAY.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
