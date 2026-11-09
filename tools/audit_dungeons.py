#!/usr/bin/env python3
"""Join pinned client map identities with effective QuestieDB regions and quest prerequisites."""
import argparse
import csv
import hashlib
import json
import io
import struct
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PINS = {
    'Map-1.60.1.70862.tsv': 'b97991211484894f343381012af621f51a9417efbbc8fa32ea62694644b99af1',
    'dungeon-provider-1.0.12.tsv': 'c71ba791164de9210e7c7911150e9ea11390cc82cf0889c3d20577a4337b39bc',
}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def classify(row):
    if 'test' in row['MapName'].lower() or '<unused>' in row['MapName'].lower():
        return 'test-or-unused'
    return {0:'world-or-transport', 1:'party', 2:'raid', 3:'battleground', 4:'arena'}.get(int(row['InstanceType']), 'unknown')

def build():
    for name, expected in PINS.items():
        assert digest(ROOT / '.dependencies' / name) == expected, name
    raw_map = ROOT / '.dependencies/terrain-crop-active-70862-zhCN/extract0-rdx8bxsz/dbc/zhCN/Map.db2'
    assert digest(raw_map) == 'e1c512fb47642216fc0e90a4bcf9bddf73a30d8cd1f7b39a22171dfdb6fff580'
    raw = raw_map.read_bytes()
    assert raw[:8] == b'WDC5\x05\x00\x00\x00'
    header_records = struct.unpack_from('<I', raw, 136)[0]
    source = ROOT / 'docs/EFFECTIVE_DATA_AUDIT.json' 
    audit = json.loads(source.read_text())
    base = audit['base']
    provider, aliases = {}, defaultdict(set)
    for line in (ROOT / '.dependencies/dungeon-provider-1.0.12.tsv').read_text().splitlines():
        kind, a, b = line.split('\t'); a, b = int(a), int(b)
        if kind == 'M':
            assert a not in provider
            provider[a] = b
        else:
            assert kind == 'A'
            aliases[a].add(b)
    # Preserve every persona's relations; an OR branch is a possible prerequisite, not a compulsory route.
    by_zone, parents = defaultdict(set), defaultdict(set)
    levels = defaultdict(set)
    all_ids = {int(qid) for qid in base['quests']}
    versions = [base['quests']] + [v['questOverrides'] for v in audit['variants']]
    for quests in versions:
        for qid, quest in quests.items():
            qid = int(qid)
            by_zone[quest.get('zone', 0)].add(qid)
            levels[qid].add(quest.get('level', 0))
            for key in ('all', 'any'):
                for parent in quest.get(key, []):
                    parents[qid].add(abs(parent))
    rows, conflicts, represented = [], [], set()
    for native in csv.DictReader(io.StringIO((ROOT / '.dependencies/Map-1.60.1.70862.tsv').read_text()), delimiter='\t'):
        mid, native_area = int(native['ID']), int(native['AreaTableID'])
        area = provider.get(mid) or native_area
        if native_area and mid in provider and native_area != provider[mid]:
            conflicts.append({'mapId':mid,'nativeArea':native_area,'providerArea':provider[mid]})
            area = native_area
        region_ids = aliases.get(area, {area}) if area else set()
        represented.update(region_ids)
        quests = set().union(*(by_zone[a] for a in region_ids)) if region_ids else set()
        closure, pending = set(quests), list(quests)
        while pending:
            for parent in parents[pending.pop()]:
                if parent not in closure:
                    closure.add(parent); pending.append(parent)
        d = base['dungeons'].get(str(area), {})
        row = {'mapId':mid,'name':native['MapName'],'directory':native['Directory'],
               'instanceType':int(native['InstanceType']),'classification':classify(native),
               'areaId':area,'nativeAreaId':native_area,'aliases':sorted(region_ids),
               'clientMaxPlayers':int(native['MaxPlayers']), 'providerName':d.get('name'),
               'entrances':d.get('entrances', []),'categoryQuestIds':sorted(quests),
               'possiblePrerequisiteIds':sorted(closure-quests),
               'missingPrerequisiteIds':sorted(closure-all_ids),
               'questLevelValues':sorted(set().union(*(levels[q] for q in quests))) if quests else [],
               'clientVerified':False,'itineraryReady':False}
        rows.append(row)
    assert len(rows) == 73 and len({r['mapId'] for r in rows}) == len(rows)
    unresolved = [{'areaId':int(area),'name':d['name'],'reason':'not-linked-to-readable-client-map'}
                  for area,d in base['dungeons'].items() if int(area) not in represented]
    rows.sort(key=lambda r:r['mapId']); unresolved.sort(key=lambda r:r['areaId'])
    counts = dict(sorted(Counter(r['classification'] for r in rows).items()))
    return {'schema':1,'build':'1.60.1.70862','clientVerified':False,'coverageLocked':False,
            'scope':'Readable client Map.db2 records plus all 18 effective faction/class correction contexts',
            'mapRead':{'headerRecords':header_records,'decodedRecords':len(rows),'unreadableRecords':header_records-len(rows),'copyRecords':0},
            'sources':[{'path':'.dependencies/'+n,'sha256':h} for n,h in PINS.items()] +
                      [{'path':str(source.relative_to(ROOT)),'sha256':digest(source)},
                       {'path':str(raw_map.relative_to(ROOT)),'sha256':digest(raw_map)}],
            'counts':counts,'maps':rows,'identityConflicts':conflicts,'unmatchedProviderAreas':unresolved,
            'limits':['Eight client map records are inaccessible to this offline reader; their identities are unknown.',
                      'Party type does not prove enabled content, suitable level, entrance access, or a complete itinerary.',
                      'Category quest IDs are associations, not proof that every objective lies in this instance.',
                      'Prerequisite closure includes alternative and signed conditions; eligibility must still evaluate each branch.',
                      'Client MaxPlayers is a map cap, not a recommended party size.']}

def markdown(report):
    lines = ['# Forever 副本内容清单', '',
             '目标构建 1.60.1.70862；由 `python3 tools/audit_dungeons.py` 生成。', '',
             '地图表 81 条中读取 73 条，另 8 条当前不可读取，编号未知。分类基于实例类型；练级范围和完整行程尚未验收。', '',
             '以下列出全部可读的 party 类型地图。任务数按区域分类及别名关联，合并 18 个阵营／职业修正上下文；前置含备选分支，实际执行继续检查资格。', '',
             '| 实例 ID | 名称 | 区域 ID | 入口记录 | 分类关联任务 | 前置候选 |',
             '| ---: | --- | ---: | ---: | ---: | ---: |']
    for row in report['maps']:
        if row['classification'] == 'party':
            lines.append('| {mapId} | {name} | {areaId} | {entrances} | {quests} | {parents} |'.format(
                **{k:v for k,v in row.items() if k!='entrances'},entrances=len(row['entrances']),
                quests=len(row['categoryQuestIds']),parents=len(row['possiblePrerequisiteIds'])))
    lines += ['', '分类计数：'+ '、'.join(f'{k} {v}' for k,v in report['counts'].items())+'。', '',
              f"另有 {len(report['unmatchedProviderAreas'])} 个上游区域未关联可读客户端地图，完整清单和逐任务 ID 见 DUNGEON_COVERAGE.json。", '',
              '下一步补齐实际目标／掉落关联、准入等级、入口可达性、任务准备与返回交付。当前运行版副本内容仍为空；此报告不自动启用副本推荐。', '']
    return '\n'.join(lines)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    report=build()
    artifacts={'docs/DUNGEON_COVERAGE.json':json.dumps(report,ensure_ascii=False,indent=2)+'\n',
               'docs/DUNGEON_COVERAGE.md':markdown(report)}
    for name,text in artifacts.items():
        path=ROOT/name
        if args.check: assert path.read_text()==text, name
        else: path.write_text(text)
    print(json.dumps(report['counts'],ensure_ascii=False), 'identity conflicts:',len(report['identityConflicts']))
if __name__=='__main__': main()
