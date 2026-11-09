#!/usr/bin/env python3
"""Check the pinned taxi-speed effect against the production flight estimator."""
import csv
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PINS = {
    '.dependencies/SpellEffect-1.60.1.70862-zhCN.csv': 'cc8f167fe246b495294b560196f6c59439f703e8f937ddb6acd81157bd5f8b9c',
    '.dependencies/Forever-SpellBookDocumentation.lua': '509fabe6d33de10f7166dc71bfb853dc969803d86536acac0833d30b1d0f9179',
    '.dependencies/gear-SpellAuraDefines.h': 'acc33e618fcbe9928ee2b0d29d3d7320be3d8994f41c046d297a03bb20a87c3b',
}


def main():
    for name, digest in PINS.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    with (ROOT / next(iter(PINS))).open() as source:
        effects = [r for r in csv.DictReader(source) if r['SpellID'] == '1225490' and r['EffectAura'] == '388']
    assert len(effects) == 1
    effect = effects[0]
    assert (effect['ID'], effect['DifficultyID'], effect['Effect'], effect['EffectBasePointsF']) == ('1303665', '0', '6', '20')
    result = subprocess.run(['lua5.1', '-'], cwd=ROOT, text=True, capture_output=True, check=True, input='''
local A={}
assert(loadfile("Data/Flights.lua"))("AiLeveling",A)
assert(loadfile("Planner/Flights.lua"))("AiLeveling",A)
local s={clientVersion="1.60.1",clientBuild="70862",interface=16001,samples={}}
local learned=false
C_SpellBook={IsSpellKnown=function(id) assert(id==1225490);return learned end}
local count=0
for _,field in ipairs({"durations","observedDurations"}) do
    for faction,routes in pairs(A.FlightData[field]) do
        s.faction=faction
        for key in pairs(routes) do
            local from,to=key:match("(%d+):(%d+)");from,to=tonumber(from),tonumber(to)
            learned=false;s.taxiSpeed=A.Flights.ReadSpeed(s)
            local base=A.Flights.Seconds(from,to,s)
            learned=true;s.taxiSpeed=A.Flights.ReadSpeed(s)
            local fast=A.Flights.Seconds(from,to,s)
            assert(math.abs(fast-base/1.2)<0.000001,key)
            local sampleKey=A.Flights.TimeKey(from,to,faction,nil,s.taxiSpeed)
            s.samples[sampleKey]={n=3,unit="seconds",mean=10}
            assert(A.Flights.Seconds(from,to,s)==10)
            s.samples={};count=count+1
        end
    end
end
assert(count==891);print(count)
''')
    inputs = dict(PINS)
    for name in ['Planner/Flights.lua', 'Transport.lua', 'Core.lua', 'Data/Flights.lua',
                 'tests/flight.lua', 'tests/reference_flights.lua', 'tests/assist.lua', 'tools/check_flight_speed.py']:
        inputs[name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    report = {'build': '1.60.1.70862', 'clientVerified': False, 'inputs': inputs,
              'checks': {'flightDurationRows': int(result.stdout.strip()), 'speedMultiplier': 1.2,
                         'spellID': 1225490, 'effectID': 1303665},
              'limitations': ['Offline replay with native API stubs; learned passive behavior and real flight times need client verification.',
                              'Only Frequent Flier is modeled; unknown speed state does not produce local timing samples.']}
    (ROOT / 'docs/FLIGHT_SPEED_REPLAY.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('PASS: pinned +20% taxi-speed effect; 891 reference rows and measured-time precedence')


if __name__ == '__main__':
    main()
