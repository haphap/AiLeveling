#!/usr/bin/env python3
"""Import observed server transports and their matching client docking points."""
import csv
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = "1.60.1.70862"
COMMIT = "156f29c9af78b1586883e8eb94a13467eb89638c"
SOURCES = {
    f".dependencies/TaxiPathNode-{BUILD}.csv": "f83f8d8e5bbeae889214f48af477dd51a4c1771ff3c3b53c3fa2cacf2cba7cdb",
    f".dependencies/UiMapAssignment-{BUILD}.csv": "79267e8be8034e47daab14350411b3acc0b1f64e86efc9d821a217497254ca0a",
    f".dependencies/eg-link-156f29c9/{BUILD}/object_details.enUS.json": "63ea8fe2112516932c2633f7cb5507f99211390549c9d2a37d6b63214d906f19",
    f".dependencies/TransportAnimation-{BUILD}.csv": "d734b9cc688c122e2e57cd0c890a3d0545034d48c8a377dfa4da0df50f5836eb",
    ".dependencies/eg-objects-70938-6ff5612.json": "1974e7b86e3ea31758b5903f4e6853a86b0f88b0f97a7bee247dbf95b9bbca40",
    f".dependencies/AreaTrigger-{BUILD}.csv": "c42305d819d250a0003159458f458c17f0720ae1561194fdc1283d7e530f8a8e",
}
UPDATE_SOURCE = "https://raw.githubusercontent.com/JIVESCORP/eg-link-output-wowf/6ff5612b54191f297eb77ca8eda81de029d9d6f0/data/wowf/1.60.1.70938/object_details.enUS.json"
# Names and access factions belong to the actual docks, not reused TaxiNodes names.
ROUTES = [
    (20808, 241, "boat", None, [(1413, "棘齿城码头"), (1434, "藏宝海湾码头")]),
    (175080, 285, "zeppelin", "Horde", [(1434, "格罗姆高飞艇塔"), (1411, "奥格瑞玛南飞艇塔")]),
    (176495, 301, "zeppelin", "Horde", [(1434, "格罗姆高飞艇塔"), (1420, "幽暗城飞艇塔")]),
    (164871, 302, "zeppelin", "Horde", [(1411, "奥格瑞玛南飞艇塔"), (1420, "幽暗城飞艇塔")]),
    (656308, 11616, "boat", "Alliance", [(1439, "奥伯丁暴风城航线码头"), (1453, "暴风城港口码头")]),
    (176244, 293, "boat", "Alliance", [(1438, "鲁瑟兰村码头"), (1439, "奥伯丁鲁瑟兰航线码头")]),
    (176231, 292, "boat", "Alliance", [(1437, "米奈希尔塞拉摩航线码头"), (1445, "塞拉摩码头")]),
    (176310, 11167, "boat", "Alliance", [(1437, "米奈希尔环线码头"), (1424, "南海镇码头"), (1439, "奥伯丁环线码头")]),
    (177233, 303, "boat", "Alliance", [(1444, "羽月要塞码头"), (1444, "被遗忘的海岸码头"), (1444, "羽月要塞码头")]),
    (630567, 11391, "boat", None, [(1446, "热砂港码头"), (2548, "Powderfuse Port 码头")]),
]
EXCLUDED = {
    631278: "Dalaran Skycutter: boarding/access conditions for Zephras Isle are not in the available server object records.",
    644609: "Mulgore Skycutter: boarding/access conditions for Zephras Isle are not in the available server object records.",
}


def main():
    for name, digest in SOURCES.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    nodes = list(csv.DictReader((ROOT / next(iter(SOURCES))).open()))
    assignments = list(csv.DictReader((ROOT / f".dependencies/UiMapAssignment-{BUILD}.csv").open()))
    def map_point(map_id, name, continent, world_x, world_y):
        matches = []
        for a in assignments:
            if int(a["UiMapID"]) != map_id or a["MapID"] != continent:
                continue
            if [float(a[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1")] != [0, 0, 1, 1]:
                continue
            x = (float(a["Region_4"]) - world_y) / (float(a["Region_4"]) - float(a["Region_1"]))
            y = (float(a["Region_3"]) - world_x) / (float(a["Region_3"]) - float(a["Region_0"]))
            if 0 <= x <= 1 and 0 <= y <= 1:
                matches.append(dict(map=map_id, x=round(x, 9), y=round(y, 9), name=name))
        assert len(matches) == 1, (map_id, name, matches)
        return matches[0]

    cache = json.loads((ROOT / list(SOURCES)[2]).read_text())
    assert cache["meta"]["clientBuild"] == BUILD
    updated = json.loads((ROOT / ".dependencies/eg-objects-70938-6ff5612.json").read_text())
    assert updated["meta"]["clientBuild"] == "1.60.1.70938"
    objects = dict(cache["objects"], **updated["objects"])
    observed = {int(id) for id, obj in objects.items() if obj["type"] == 15}
    included = {route[0] for route in ROUTES}
    assert not included.intersection(EXCLUDED)
    assert observed == included.union(EXCLUDED), ("Unreviewed transport objects", observed ^ included.union(EXCLUDED))
    legs, evidence = [], []
    for object_id, path_id, mode, faction, ports in ROUTES:
        obj = objects[str(object_id)]
        assert obj["type"] == 15 and obj["data"][0] == path_id
        speed, acceleration = obj["data"][1:3]
        assert speed > 0 and acceleration > 0
        path = sorted((r for r in nodes if int(r["PathID"]) == path_id), key=lambda r: int(r["NodeIndex"]))
        stops = [i for i, r in enumerate(path) if int(r["Delay"]) > 0]
        assert len(stops) == len(ports) >= 2
        points = []
        for i, (map_id, name) in zip(stops, ports):
            r = path[i]
            points.append(map_point(map_id, name, r["ContinentID"], float(r["Loc_0"]), float(r["Loc_1"])))
        delays = [int(path[i]["Delay"]) for i in stops]
        closing = None
        # The ferry's final stop repeats its first dock; it is not a third destination.
        if ports[0] == ports[-1]:
            assert sum((float(path[stops[0]][f"Loc_{j}"]) - float(path[stops[-1]][f"Loc_{j}"])) ** 2 for j in range(3)) < 1
            closing = stops.pop()
            points.pop()
            delays[0] += delays.pop()
        rides = []
        for direction, start in enumerate(stops):
            end = stops[(direction + 1) % len(stops)]
            if direction == len(stops) - 1 and closing is not None:
                end = closing
            distance, i = 0, start
            while i != end:
                nxt = (i + 1) % len(path)
                a, b = path[i], path[nxt]
                # Teleport edges have no travel distance, including same-world teleports.
                if a["ContinentID"] == b["ContinentID"] and not int(a["Flags"]) & 1 and nxt != 0:
                    distance += math.sqrt(sum((float(a[f"Loc_{j}"]) - float(b[f"Loc_{j}"])) ** 2 for j in range(3)))
                i = nxt
            # Reference estimate: polyline cruise plus one acceleration/deceleration allowance.
            rides.append(math.ceil(distance / speed + speed / acceleration))
        cycle = sum(rides) + sum(delays)
        for start in range(len(stops)):
            ride, at = 0, start
            for _ in range(len(stops) - 1):
                ride += rides[at]
                at = (at + 1) % len(stops)
                key = f"public:{path_id}:{start}" + (f":{at}" if len(stops) > 2 else "")
                legs.append(dict(key=key, kind=mode, fromPoint=points[start], toPoint=points[at], faction=faction,
                                 seconds=ride+cycle/2, low=ride, high=ride+cycle))
                # Stay on the same ship through intermediate ports: no second boarding wait.
                ride += delays[at]
        evidence.append(dict(objectId=object_id, pathId=path_id, serverName=obj["name"], sources=obj["sources"],
                             speed=speed, acceleration=acceleration, ports=points, rideSeconds=rides, cycleSeconds=cycle))
    triggers = {int(r["ID"]): r for r in csv.DictReader((ROOT / f".dependencies/AreaTrigger-{BUILD}.csv").open())}
    tram_points = []
    for trigger, map_id, name in [(2173, 1453, "暴风城地铁入口"), (2175, 1455, "铁炉堡地铁入口")]:
        row = triggers[trigger]
        assert row["ContinentID"] == "0"
        tram_points.append(map_point(map_id, name, row["ContinentID"], float(row["Pos_0"]), float(row["Pos_1"])))
    with (ROOT / f".dependencies/TransportAnimation-{BUILD}.csv").open() as stream:
        track = sorted((r for r in csv.DictReader(stream) if r["TransportID"] == "176080"),
                       key=lambda r: int(r["TimeIndex"]))
    stops = [(int(a["TimeIndex"]), int(b["TimeIndex"])) for a, b in zip(track, track[1:])
             if all(a[f"Pos_{i}"] == b[f"Pos_{i}"] for i in range(3))]
    assert len(stops) == 2 and int(track[0]["TimeIndex"]) == 0 and stops[1][0] - stops[0][1] == stops[0][0]
    ride, cycle = stops[0][0] / 1000, int(track[-1]["TimeIndex"]) / 1000
    for direction in range(2):
        legs.append(dict(key=f"public:tram:{direction}", kind="tram", fromPoint=tram_points[direction],
                         toPoint=tram_points[1-direction], faction="Alliance",
                         seconds=round(ride+cycle/2, 3), low=ride, high=round(ride+cycle, 3)))
    evidence.append(dict(name="Deeprun Tram", ports=tram_points, rideSeconds=ride, cycleSeconds=cycle,
                         triggers=[2173, 2175], transportId=176080, source=f"https://wago.tools/db2/TransportAnimation?build={BUILD}"))
    portal = {}
    for trigger_id, map_id, name in [(542, 1438, "鲁瑟兰村"), (527, 1457, "达纳苏斯")]:
        r = triggers[trigger_id]
        assert r["ContinentID"] == "1" and int(r["AreaTriggerActionSetID"]) > 0
        portal[trigger_id] = map_point(map_id, name, r["ContinentID"], float(r["Pos_0"]), float(r["Pos_1"]))
    for start, end in [(542, 527), (527, 542)]:
        legs.append(dict(key=f"public:portal:{start}", kind="portal", fromPoint=portal[start], toPoint=portal[end],
                         faction=None, seconds=0, low=0, high=0))
    evidence.append(dict(name="Rut'theran Village – Darnassus portal", triggers=portal,
                         source=f"https://wago.tools/db2/AreaTrigger?build={BUILD}"))
    lines = ['local _,A=...', '-- Generated by tools/import_public_transit.py; reference estimates, not observed arrival times.',
             'A.PublicTransitData={clientVersion="1.60.1",build=70862,interface=16001,legs={']
    for leg in legs:
        def point(p):
            return '{map=%d,x=%.9f,y=%.9f}' % (p['map'], p['x'], p['y'])
        lines.append('    {key="%s",kind="%s",from=%s,to=%s,fromName="%s",toName="%s",seconds=%s,low=%s,high=%s%s},' % (
            leg['key'], leg['kind'], point(leg['fromPoint']), point(leg['toPoint']), leg['fromPoint']['name'],
            leg['toPoint']['name'], leg['seconds'], leg['low'], leg['high'], ',faction="'+leg['faction']+'"' if leg['faction'] else ''))
    lines += ['}}', '']
    (ROOT / 'Data/PublicTransit.lua').write_text('\n'.join(lines))
    report = dict(build=BUILD, inputs=SOURCES, source=f'https://github.com/JIVESCORP/eg-link-output-wowf/tree/{COMMIT}/data/wowf/{BUILD}',
                  attribution='Efficient Games, CC BY 4.0; Blizzard client tables via Wago', clientVerified=False,
                  serverUpdateSource=UPDATE_SOURCE,
                  scope=f'{len(ROUTES)} server-observed boat/zeppelin templates, Deeprun Tram and the Ruttheran portal; {len(legs)} directed journeys. Dock geography and faction access are curated. Multi-stop ships retain their forward stop order.',
                  estimation='Client polyline / server speed + speed / acceleration. Mean wait is half estimated cycle. No load-screen delay or live schedule. Ground travel remains straight distance / player speed.',
                  coverage=dict(observedObjects=len(observed), includedObjects=sorted(included), excludedObjects=EXCLUDED), routes=evidence)
    (ROOT / 'docs/PUBLIC_TRANSIT_AUDIT.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print('Imported', len(legs), 'directed transport legs')


if __name__ == '__main__':
    main()
