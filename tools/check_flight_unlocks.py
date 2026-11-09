#!/usr/bin/env python3
"""Check prospective unlock edges against the pinned client TaxiPath table."""
import csv
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '.dependencies/TaxiPath-1.60.1.70862.csv'
PIN = '3e5c18b53621ca7cd2618447e12498874e6aba7aa7f1f6bfda9a7977979da179'


def main():
    assert hashlib.sha256((ROOT / SOURCE).read_bytes()).hexdigest() == PIN
    with (ROOT / SOURCE).open() as f:
        client = {int(r['ID']): (int(r['FromTaxiNode']), int(r['ToTaxiNode']), int(r['Cost']))
                  for r in csv.DictReader(f)}
    result = subprocess.run(['lua5.1', '-'], cwd=ROOT, check=True, text=True, capture_output=True, input='''
local A={}
assert(loadfile("Data/Flights.lua"))("AiLeveling",A)
assert(loadfile("Planner/Flights.lua"))("AiLeveling",A)
-- Projection stub: this checks identities, direction, costs and state isolation, not map geometry.
C_Map={GetMapInfo=function() return {mapType=3} end}
local nav={hbd={GetZoneCoordinatesFromWorldInstance=function(_,x,y) return x/40000+0.5,y/40000+0.5 end}}
for id,path in pairs(A.FlightData.paths) do print("path",id,path[1],path[2],path[3]) end
for _,faction in ipairs({"Alliance","Horde"}) do
    local s={clientVersion="1.60.1",clientBuild="70862",interface=16001,faction=faction,transportKnown=true,
        unlocked={},taxiCosts={},taxiAvailability={},taxiSpeed=1}
    for id in pairs(A.FlightData.nodes) do s.unlocked["taxi:"..id]=false end
    local rows=A.Flights.UnlockCandidates(s,{[1]=true},nav)
    for _,row in ipairs(rows) do
        for id in pairs(A.FlightData.nodes) do s.unlocked["taxi:"..id]=id~=row.taxiId end
        local preview=A.Flights.PreviewUnlock(s,row,nav)
        local count=0
        if preview then
            for key in pairs(preview.taxiAvailability) do
                local from,to=key:match("^(%d+):(%d+)$");from,to=tonumber(from),tonumber(to)
                assert(from==row.taxiId or to==row.taxiId)
                local source,dest=A.FlightData.nodes[from],A.FlightData.nodes[to]
                assert(source.instance==dest.instance and source.condition==0 and dest.condition==0)
                local found=false
                for id,path in pairs(A.FlightData.paths) do
                    if path[1]==from and path[2]==to and path[3]==preview.taxiCosts[key] then found=true end
                end
                assert(found,key);assert(preview.taxiHops[key]==key)
                assert(A.Flights.Seconds(from,to,preview,key)>0);count=count+1
            end
        end
        assert(s.unlocked["taxi:"..row.taxiId]==false and next(s.taxiCosts)==nil and next(s.taxiAvailability)==nil)
        print("candidate",faction,row.taxiId,count)
    end
end
''')
    paths, candidates = {}, []
    for line in result.stdout.splitlines():
        values = line.split()
        if values[0] == 'path':
            ident, *path = map(int, values[1:])
            assert tuple(path) == client[ident]
            paths[ident] = path
        else:
            assert values[0] == 'candidate'
            candidates.append({'faction': values[1], 'taxiId': int(values[2]), 'previewEdges': int(values[3])})
    assert len(paths) == 292 and candidates
    build = (ROOT / 'dist/build-0.1.91-dev.log').read_text()
    scenarios = int(re.search(r'(\d+) 个关键回归场景通过', build)[1])
    assert scenarios == 514
    inputs = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in
              [SOURCE, 'Data/Flights.lua', 'Planner/Flights.lua', 'Planner/Planner.lua', 'Services.lua',
               'Transport.lua', 'UI/Services.lua', 'tests/services.lua', 'tools/check_flight_unlocks.py']}
    report = {'build': '1.60.1.70862', 'result': 'passed', 'clientVerified': False, 'luaScenarios': scenarios,
              'inputs': inputs, 'directedPathsChecked': len(paths), 'candidates': candidates,
              'limitations': ['Synthetic character unlocks and coordinate projection; no client/map validation.',
                              'Preview uses client base fares and reference times, not native availability or quotes.',
                              'Single unlock and direct edges only; user chooses the service, native unlock confirms completion.']}
    (ROOT / 'docs/FLIGHT_UNLOCK_REPLAY.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f'PASS: {len(paths)} client directed paths; {len(candidates)} faction/node previews; {scenarios} regression scenarios')


if __name__ == '__main__':
    main()
