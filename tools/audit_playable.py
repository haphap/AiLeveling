#!/usr/bin/env python3
"""Cross-check the Forever playable census and project the effective quest audit onto it."""
import csv
import hashlib
import io
import json
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = "1.60.1.70862"
OFFICIAL = "https://wow.blizzard.cn/news/24304075/index.html"
INPUTS = {
    ".dependencies/CharBaseInfo-1.60.1.70862-enUS.csv": "6894b5d04495e875c3f08085630b951abeda6b798b5ed47de4f3405dd346cbc2",
    ".dependencies/ChrRaces-1.60.1.70862-zhCN.csv": "57e5006ca87d6737c7db0ebe57aca55a4579b03910620535e79284b2f65c7849",
    ".dependencies/ChrClasses-1.60.1.70862-enUS.csv": "e08c2f00e1652ff6857734915d649a80d8a2a86419986f59dbe82ba3a6975597",
    ".dependencies/Forever-playable-official-24304075.html": "4d012553c699117259166eceb1e1eb08f42f8f8540b25ecd3d50f16723b80111",
    "docs/EFFECTIVE_DATA_AUDIT.json": "af835504db2470b09b096dbb0b33665d4b945664051aad32334f642797a408cb",
}
CLASS_IDS = {"战士": 1, "圣骑士": 2, "猎人": 3, "潜行者": 4, "牧师": 5,
             "萨满祭司": 7, "法师": 8, "术士": 9, "德鲁伊": 11}


def read_pinned(root, name):
    data = (root / name).read_bytes()
    if hashlib.sha256(data).hexdigest() != INPUTS[name]:
        raise ValueError("Source hash changed: " + name)
    return data.decode("utf-8-sig")


def csv_index(text):
    rows = {}
    for row in csv.DictReader(io.StringIO(text)):
        key = int(row["ID"])
        if key in rows:
            raise ValueError("Duplicate ID: " + str(key))
        rows[key] = row
    return rows


class Tables(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tables, self.table, self.row, self.cell = [], None, None, None

    def handle_starttag(self, tag, attrs):
        if tag == "table":
            self.table = []
        elif tag == "tr" and self.table is not None:
            self.row = []
        elif tag in ("th", "td") and self.row is not None:
            self.cell = []

    def handle_data(self, text):
        if self.cell is not None:
            self.cell.append(text)

    def handle_endtag(self, tag):
        if tag in ("th", "td") and self.cell is not None:
            self.row.append("".join(self.cell).strip())
            self.cell = None
        elif tag == "tr" and self.row is not None:
            self.table.append(self.row)
            self.row = None
        elif tag == "table" and self.table is not None:
            self.tables.append(self.table)
            self.table = None


def census(base, races, classes, html):
    parser = Tables()
    parser.feed(html)
    assert len(parser.tables) == 2, "Official matrix shape changed"
    expected = set()
    for faction, table in zip(("Horde", "Alliance"), parser.tables):
        assert table[0][0] == "种族" and set(table[0][1:]) == set(CLASS_IDS)
        for row in table[1:]:
            assert len(row) == 10 and all(v in ("", "X") for v in row[1:])
            for name, value in zip(table[0][1:], row[1:]):
                if value == "X":
                    item = (faction, row[0], CLASS_IDS[name])
                    assert item not in expected, "Duplicate official combination"
                    expected.add(item)
    result, actual, seen = [], set(), set()
    for item in base.values():
        race_id, class_id = int(item["RaceID"]), int(item["ClassID"])
        assert (race_id, class_id) not in seen, "Duplicate race/class combination"
        seen.add((race_id, class_id))
        race, cls = races[race_id], classes[class_id]
        faction = {"0": "Alliance", "1": "Horde"}[race["Alliance"]]
        name = race["Name_lang"]
        actual.add((faction, "天裔" if name.endswith("天裔") else name, class_id))
        bit = int(race["PlayableRaceBit"])
        assert 0 <= bit < 53
        assert int(race["StartingLevel"]) == int(cls["StartingLevel"]) == 1
        result.append({"raceId": race_id, "race": name, "raceFile": race["ClientFileString"],
                       "faction": faction, "classId": class_id, "class": cls["Filename"],
                       "raceMask": 2 ** bit, "classMask": 2 ** (class_id - 1),
                       "startLevel": 1, "targetLevel": 60})
    assert actual == expected, f"Official/build mismatch: {actual ^ expected}"
    assert len(result) == len(expected) == 56
    return sorted(result, key=lambda r: (r["faction"], r["raceId"], r["classId"]))


def compatible(quest, persona):
    # Static mask compatibility is independent of prerequisite completion and live eligibility.
    for key in ("raceMask", "classMask"):
        mask = quest.get(key)
        if type(mask) is not int or mask < 0:
            return False
        if mask and not mask & persona[key]:
            return False
    return True


def project(personas, audit):
    base = audit["base"]
    contexts = {(base["persona"]["faction"], base["persona"]["class"]): base["quests"]}
    for variant in audit["variants"]:
        key = (variant["persona"]["faction"], variant["persona"]["class"])
        assert key not in contexts
        contexts[key] = dict(base["quests"], **variant["questOverrides"])
    results = []
    for persona in personas:
        quests = contexts[(persona["faction"], persona["class"])]
        matching = sorted((q for q in quests.values() if compatible(q, persona)), key=lambda q: q["id"])
        bands = []
        for lower in range(1, 60, 10):
            upper = min(lower + 9, 60)
            rows = [q for q in matching if lower <= (q.get("level") or -1) <= upper]
            bands.append({"minLevel": lower, "maxLevel": upper, "questIds": [q["id"] for q in rows],
                          "gapCounts": dict(sorted(Counter(g for q in rows for g in q["gaps"]).items())),
                          "coverageStatus": "unverified"})
        result = dict(persona, maskCompatibleTasks=len(matching), bands=bands,
                      unknownOrScalingLevelQuestIds=[q["id"] for q in matching if (q.get("level") or -1) <= 0],
                      aboveScopeQuestIds=[q["id"] for q in matching if (q.get("level") or -1) > 60])
        results.append(result)
    return results


def build(root=ROOT):
    sources = {name: read_pinned(root, name) for name in INPUTS}
    base, races, classes = [csv_index(sources[n]) for n in list(INPUTS)[:3]]
    personas = census(base, races, classes, sources[list(INPUTS)[3]])
    return {"schema": 1, "build": BUILD, "playableCensusConfirmed": True,
            "coverageLocked": False, "clientVerified": False,
            "method": "Official matrix equals CharBaseInfo; static quest mask projection of the 18 audited correction contexts. Band uses quest level, not current character eligibility.",
            "sources": [{"path": n, "sha256": h, "url": OFFICIAL if n.endswith("html") else
                         f"https://wago.tools/db2/{Path(n).name.split('-')[0]}/csv?build={BUILD}&locale={'zhCN' if 'zhCN' in n else 'enUS'}" if n.endswith("csv") else None}
                        for n, h in INPUTS.items()],
            "combinations": project(personas, json.loads(sources["docs/EFFECTIVE_DATA_AUDIT.json"]))}


def main():
    report = build()
    path = ROOT / "docs/PLAYABLE_COVERAGE.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    lines = ["# Forever 可玩组合与全程覆盖清单", "",
             f"构建：{BUILD}。复现：`python3 tools/audit_playable.py`。", "",
             f"[官方种族职业表]({OFFICIAL})与构建 CharBaseInfo 逐项一致：56组，联盟28组、部落28组，全部从1级开始。",
             "种族ID95/96分别使用第32/33位资格掩码，不能按ID减一生成掩码。", "",
             "下表是任务等级分段的静态种族／职业掩码匹配数，来自已盘点的18个修正上下文；前置、互斥、特殊条件及实机可执行性另行验证。",
             "每格对应任务ID及缺口在同名JSON；缩放／未知等级单列。56组×6等级段共336项，当前均未通过完整行程验收。道路资料已退出验收。", "",
             "| 阵营 | 种族 | 职业 | 1—10 | 11—20 | 21—30 | 31—40 | 41—50 | 51—60 |",
             "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for row in report["combinations"]:
        counts = " | ".join(str(len(b["questIds"])) for b in row["bands"])
        lines.append(f"| {row['faction']} | {row['race']} | {row['class']} | {counts} |")
    (ROOT / "docs/PLAYABLE_COVERAGE.md").write_text("\n".join(lines) + "\n")
    print(f"56 combinations; 336 level-band review items -> {path}")


if __name__ == "__main__":
    main()
