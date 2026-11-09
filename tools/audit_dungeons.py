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

# Official announced leveling scope, including entries the readable Map table cannot identify yet.
ANNOUNCEMENT = 'https://news.blizzard.com/en-us/article/24301455/explore-the-new-dungeons-of-world-of-warcraft-forever'
ANNOUNCED = [
    {'name':'Hall of Thanes','levels':[13,18],'location':'Dun Morogh','mapId':3065},
    {'name':'Ruins of Lordaeron','levels':[15,20],'location':'Tirisfal Glades','mapId':2999},
    {'name':'Excavation Site','levels':[24,29],'location':'Wetlands','mapId':2998},
    {'name':'City of Dalaran','levels':[28,33],'location':'Alterac Mountains','mapId':2959,
     'preparationQuests':{'Alliance':[92432],'Horde':[93680,544]}},
    {'name':'The Drowned City','levels':[35,40],'location':'Stranglethorn Vale, west of Grom\'gol','mapId':2970,
     'identitySource':'https://wowforevertalents.com/dungeons/the-drowned-city/','lfgId':3270,'areaId':16550,'entryArea':33,
     'entryHint':'前往荆棘谷格罗姆高营地以西的海域，从水下洞口进入沉没之城。',
     'objectiveQuestIds':[95775,95776,95787,95789,95791,96774,97130]},
    {'name':"Krol'dok Stronghold",'levels':[40,45],'location':'Riverglades','mapId':3039,
     'identitySource':'https://wowforevertalents.com/dungeons/krol-dok-stronghold/','lfgId':3275,'areaId':16842,'entryArea':16591,
     'entryHint':'前往河谷林地北部的克罗多克要塞，从山间洞口进入。',
     'objectiveQuestIds':[94968,94972,94982,94983,94984,96771]},
    {'name':'Alcaz Prison','levels':[48,53],'location':'Dustwallow Marsh, Alcaz Island','mapId':2994,
     'identitySource':'https://wowforevertalents.com/dungeons/alcaz-prison/','lfgId':3269,'areaId':16620,'entryArea':15,
     'entryHint':'前往尘泥沼泽东北方的奥卡兹岛，进入岛下的奥卡兹监狱。','objectiveQuestIds':[96772]},
    {'name':'Blackmaw Hold','levels':[55,60],'location':'Azshara','mapId':2974,
     'identitySource':'https://wowforevertalents.com/dungeons/blackmaw-hold/','lfgId':3268,'areaId':16554,'entryArea':16,
     'entryHint':'前往艾萨拉北部的熊怪城门，沿隧道进入黑喉要塞。','objectiveQuestIds':[97173]},
    {'name':"Shaper's Terrace",'levels':[58,60],'location':"Un'Goro Crater, northern hills",'mapId':3001,
     'identitySource':'https://wowforevertalents.com/dungeons/the-shaper-s-terrace/','lfgId':3267,'areaId':16667,'entryArea':490,
     'entryHint':'前往安戈洛环形山北部山地，进入塑造者之台。','objectiveQuestIds':[95928]},
]

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
    extra_sources = {
        '.dependencies/LFGDungeons-1.60.1.70862-zhCN.csv':'5005d79edb52a8c75d642174c475fa2a81c728f8b0ed0f5b9e4575a1e53cbfb6',
        '.dependencies/DungeonEncounter-1.60.1.70862-zhCN.csv':'13c1a984836ccd90fc0adb56d7a52aeacab794b7276e836f30e18a80725e8677',
        '.dependencies/eg-link-156f29c9/1.60.1.70862/quests.enUS.json':'0f8b890bbedc79f6c80b99511a88ff5f699048f4a34303bd6d0a0281cfde4b7a',
    }
    for name,expected in extra_sources.items(): assert digest(ROOT/name)==expected, name
    lfg = {int(r['ID']):r for r in csv.DictReader(io.StringIO((ROOT / '.dependencies/LFGDungeons-1.60.1.70862-zhCN.csv').read_text()))}
    encounters = list(csv.DictReader(io.StringIO((ROOT / '.dependencies/DungeonEncounter-1.60.1.70862-zhCN.csv').read_text())))
    cached = json.loads((ROOT / '.dependencies/eg-link-156f29c9/1.60.1.70862/quests.enUS.json').read_text())['quests']
    checked_path = ROOT / 'docs/TASK_XP_AUDIT.json'
    checked = {q['id']:q for q in json.loads(checked_path.read_text())['objectiveSupplements'] if q.get('dungeonMapId')}
    supplemental=[]
    for announced in ANNOUNCED:
        if not announced.get('identitySource'): continue
        mid,area=announced['mapId'],announced.get('areaId')
        encounter_ids=sorted(int(r['ID']) for r in encounters if int(r['MapID'])==mid)
        assert encounter_ids and mid not in {r['mapId'] for r in rows}
        quests=sorted(int(id) for id,q in cached.items() if area and q.get('zoneAreaId')==area)
        targets={}
        for id in announced.get('objectiveQuestIds',[]):
            if id in checked:
                quest=checked[id]
                assert quest['dungeonMapId']==mid and quest['areaId']==area
                quests.append(id)
                targets[str(id)]={f'{o["kind"]}:{o["id"]}':area for o in quest['objectives']}
                continue
            quest=cached[str(id)]
            assert quest['zoneAreaId']==area and id in quests
            targets[str(id)]={}
            for o in quest['objectives']:
                kind={'monster':'npc','gameObject':'object','item':'item'}[o['type']]
                targets[str(id)][f'{kind}:{o["objectId"]}']=area
        supplemental.append({'mapId':mid,'name':lfg[announced['lfgId']]['Name_lang'],'classification':'party',
            'mapRecordDecoded':False,'identitySource':announced['identitySource'],'encounterIds':encounter_ids,
            'aliases':[area] if area else [],'entrances':[],'entryArea':announced['entryArea'],
            'entryHint':announced['entryHint'],'categoryQuestIds':quests,'objectiveAreas':targets,
            'clientVerified':False,'itineraryReady':False})
    counts = dict(sorted(Counter(r['classification'] for r in rows).items()))
    return {'schema':1,'build':'1.60.1.70862','clientVerified':False,'coverageLocked':False,
            'scope':'Readable client Map.db2 records plus all 18 effective faction/class correction contexts',
            'mapRead':{'headerRecords':header_records,'decodedRecords':len(rows),'unreadableRecords':header_records-len(rows),'copyRecords':0},
            'sources':[{'path':'.dependencies/'+n,'sha256':h} for n,h in PINS.items()] +
                       [{'path':str(source.relative_to(ROOT)),'sha256':digest(source)},
                        {'path':str(raw_map.relative_to(ROOT)),'sha256':digest(raw_map)}] +
                        [{'path':name,'sha256':sha} for name,sha in extra_sources.items()] +
                        [{'path':str(checked_path.relative_to(ROOT)),'sha256':digest(checked_path)}],
            'counts':counts,'maps':rows,'identityConflicts':conflicts,'unmatchedProviderAreas':unresolved,
            'supplementalMaps':supplemental,
            'announcedLevelingDungeons':{'source':ANNOUNCEMENT,'entries':ANNOUNCED},
            'limits':['Eight client map records are inaccessible to this offline reader; their identities are unknown.',
                      'Party type does not prove enabled content, suitable level, entrance access, or a complete itinerary.',
                      'Category quest IDs are associations, not proof that every objective lies in this instance.',
                      'Prerequisite closure includes alternative and signed conditions; eligibility must still evaluate each branch.',
                      'Client MaxPlayers is a map cap, not a recommended party size.']}

def markdown(report):
    lines = ['# Forever 副本内容清单', '',
             '目标构建 1.60.1.70862；由 `python3 tools/audit_dungeons.py` 生成。', '',
             '地图表 81 条中读取 73 条，另 8 条当前不可读取，编号未知。分类基于实例类型；练级范围和完整行程尚未验收。', '',
              f'[官方新练级副本清单]({ANNOUNCEMENT})列出九项；四项来自可读地图表，另五项以同构建客户端提取记录关联原生首领表补入目录。原始地图读取分母保持不变。推荐等级不作为准入等级。', '',
              '| 官方名称 | 推荐等级 | 地区 | 实例 ID |',
              '| --- | --- | --- | --- |']
    for row in report['announcedLevelingDungeons']['entries']:
        lines.append(f'| {row["name"]} | {row["levels"][0]}—{row["levels"][1]} | {row["location"]} | {row["mapId"] or "尚未关联"} |')
    lines += ['', '补充地图身份来源及目标资料：', '']
    for row in report['supplementalMaps']:
        lines.append(f'- [{row["name"]}]({row["identitySource"]})：实例 {row["mapId"]}，原生首领 {len(row["encounterIds"])} 项，关联任务 {len(row["categoryQuestIds"])} 项。')
    lines += ['', '补充目录的入口使用官方所在地区中心及入口方向说明；已确认本内目标来自同构建服务器任务原文和已核对任务事实，其他分类任务保持普通关联。任务接交者仍从 QuestieDB 查询，缺少的任务以实际提供及日志接入。塑造者之台关联95928的四种水晶目标，来源见TASK_XP_AUDIT.json；其余两项已报告任务缺实际ID，尚未补入。', '']
    lines += ['', '达拉然入城准备：联盟从任务 92432（An Alarming Request）开始，部落关联 93680（Key to the City）及 544（Prison Break In）。目录接入这些准备任务，资格和进度继续由数据库及原生日志决定；资料尚未给出整条解锁链的最终完成标记。', '',
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
              '运行时使用 Data/Dungeons.lua 的副本任务目录，按 QuestieDB 资格、前置及实际目标位置安排准备、进入、目标和交付。全部交齐后保留本内离开步骤，出本恢复自动路线；整次任务行程计时已接入动态任务组。', '',
              '任务实际位置关联见 DUNGEON_QUEST_LOCATIONS.json，原生准入条件见 DUNGEON_ADMISSION.md。表中无入口或无分类任务的项目须结合这些来源确认用途；未知地图及尚缺入口的项目继续保留在覆盖清单。完整副本覆盖和统一实机验收尚未关闭。', '']
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
