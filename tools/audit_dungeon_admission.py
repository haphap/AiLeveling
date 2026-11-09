#!/usr/bin/env python3
"""Join build-pinned admission records without inventing semantics or missing conditions."""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = '1.60.1.70862'
PINS = {
    'MapDifficulty': ('zhCN', 'f92ef61347dbb2088b103a8d72ac127fe4a67ec7c66a518008907b16fd916ab8'),
    'MapDifficultyXCondition': ('zhCN', '93995169dfb310f5c26d6718523f5c2ce15496c929ed2f304533d85c73e4b46a'),
    'Difficulty': ('zhCN', '727c5ad7c7df449d717f03acf62c37486c083da7db3134bf1b49fca322c4546a'),
    'PlayerCondition': ('zhCN', 'ddf88d67ef3773230e7e4d8d0408621b3e75686a291eb8e56ee67440888d0228'),
    'ContentTuning': ('enUS', 'f58de0c02f23e85ebb40f5a2584ed7e179879464a62cca6d6b2bbcea0ee44e14'),
    'LFGDungeons': ('zhCN', '5005d79edb52a8c75d642174c475fa2a81c728f8b0ed0f5b9e4575a1e53cbfb6'),
}


def read_table(path, expected):
    raw = path.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == expected, f'input changed: {path}'
    result = {}
    for row in csv.DictReader(io.StringIO(raw.decode('utf-8-sig'))):
        assert None not in row and all(v is not None for v in row.values()), 'malformed CSV'
        ident = int(row['ID'])
        assert ident > 0 and ident not in result, f'duplicate/invalid ID: {ident}'
        result[ident] = row
    return result


def join(maps, tables):
    records, used, missing = [], set(), set()
    for m in sorted(maps, key=lambda row: row['mapId']):
        if m['classification'] != 'party':
            continue
        difficulties = []
        for ident, row in sorted(tables['MapDifficulty'].items()):
            if int(row['MapID']) != m['mapId']:
                continue
            conditions = []
            for link in sorted(tables['MapDifficultyXCondition'].values(),
                               key=lambda r: (int(r['OrderIndex']), int(r['ID']))):
                if int(link['MapDifficultyID']) != ident:
                    continue
                cid = int(link['PlayerConditionID'])
                used.add(cid)
                condition = tables['PlayerCondition'].get(cid)
                if condition is None:
                    missing.add(cid)
                tuning_id = int(condition['ContentTuningID']) if condition else 0
                conditions.append({'link': link, 'record': condition,
                                   'status': 'present' if condition is not None else 'missing-row',
                                   'contentTuning': tables['ContentTuning'].get(tuning_id)})
            tuning_id = int(row['ContentTuningID'])
            difficulties.append({'record': row,
                                 'difficulty': tables['Difficulty'].get(int(row['DifficultyID'])),
                                 'contentTuning': tables['ContentTuning'].get(tuning_id),
                                 'conditions': conditions,
                                 'missingConditionIds': sorted({int(c['link']['PlayerConditionID'])
                                                               for c in conditions if c['record'] is None}),
                                 'admissionVerified': False})
        # MapID=0 LFG rows cannot be linked by localized names or equal tuning alone.
        lfg = [r for _, r in sorted(tables['LFGDungeons'].items()) if int(r['MapID']) == m['mapId']]
        records.append({'mapId': m['mapId'], 'name': m['name'], 'difficulties': difficulties,
                        'lfgByMapId': lfg, 'admissionVerified': False})
    ids = {m['mapId'] for m in records}
    return {'maps': records, 'conditionIds': sorted(used), 'missingConditionIds': sorted(missing),
            'lfgWithoutMapId': [r for _, r in sorted(tables['LFGDungeons'].items()) if int(r['MapID']) == 0],
            'mapDifficultyOutsideCatalog': [r for _, r in sorted(tables['MapDifficulty'].items())
                                                  if int(r['MapID']) not in ids]}


def build():
    tables, sources = {}, []
    for table, (locale, digest) in PINS.items():
        path = f'.dependencies/{table}-{BUILD}-{locale}.csv'
        tables[table] = read_table(ROOT / path, digest)
        sources.append({'path': path, 'sha256': digest, 'rows': len(tables[table]),
                        'url': f'https://wago.tools/db2/{table}/csv?build={BUILD}&locale={locale}'})
    path = ROOT / 'docs/DUNGEON_COVERAGE.json'
    census = json.loads(path.read_text())
    assert census['build'] == BUILD
    sources.append({'path': str(path.relative_to(ROOT)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    report = join(census['maps'] + census['supplementalMaps'], tables)
    report.update({'schema': 1, 'build': BUILD, 'sources': sources, 'clientVerified': False,
                   'coverageLocked': False, 'unreadableMapRecords': census['mapRead']['unreadableRecords']})
    report['counts'] = {'partyMaps': len(report['maps']),
                        'mapDifficulties': sum(len(m['difficulties']) for m in report['maps']),
                        'referencedConditions': len(report['conditionIds']),
                        'missingConditions': len(report['missingConditionIds']),
                        'lfgWithoutMapId': len(report['lfgWithoutMapId'])}
    return report


def markdown(report):
    c = report['counts']
    lines = ['# Forever 副本准入资料核对', '',
             f'构建 {BUILD}；运行 `python3 tools/audit_dungeon_admission.py --check` 可重现核对。', '',
             f'已关联目录中 {c["partyMaps"]} 个副本（含五个补充身份）、{c["mapDifficulties"]} 条地图难度记录。'
             f'引用 {c["referencedConditions"]} 个角色条件，其中 {c["missingConditions"]} 个条件行未出现在固定版本下载表中。', '',
             'MapDifficulty 的提示文字、PlayerCondition 的原始等级、ContentTuning 的等级配置分开保留。'
             '角色条件使用 Flags 和 ContentTuningID，字段含义及运行时覆盖需继续确认；不从提示文字推导准入等级。', '',
             '没有条件行、关联表中没有条件引用、以及条件存在但不含某字段是不同状态。'
             '这些记录均未通过客户端进入验证，不能据此宣称无等级、钥匙或开放限制。', '',
             '| 实例 ID | 名称 | 难度 ID | 引用条件数 | 缺失条件 ID |',
             '| ---: | --- | --- | ---: | --- |']
    for m in report['maps']:
        for d in m['difficulties']:
            lines.append(f'| {m["mapId"]} | {m["name"]} | {d["record"]["DifficultyID"]} | '
                         f'{len(d["conditions"])} | {", ".join(map(str,d["missingConditionIds"])) or "—"} |')
        if not m['difficulties']:
            lines.append(f'| {m["mapId"]} | {m["name"]} | 未找到 | — | — |')
    lines += ['', f'LFG 表有 {c["lfgWithoutMapId"]} 条 MapID=0 的记录，保留原文，不按同名或相同调节表推断实例身份。', '',
              f'原地图表仍有 {report["unreadableMapRecords"]} 条未读记录；补充身份的来源与范围见 DUNGEON_COVERAGE.md，未将其计作成功解码。', '',
              '数据来源、SHA256、全部原始条件字段与逐难度关联见 DUNGEON_ADMISSION.json。', '',
              '运行时沿用客户端返回的进入错误与实际实例状态，允许重新检查和退出安排；静态资料用于核对。任务接取等级和推荐等级分别保留。', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    report = build()
    for name, text in {'docs/DUNGEON_ADMISSION.json': json.dumps(report, ensure_ascii=False, indent=2)+'\n',
                       'docs/DUNGEON_ADMISSION.md': markdown(report)}.items():
        path = ROOT / name
        if args.check:
            assert path.read_text() == text, name
        else:
            path.write_text(text)
    print(json.dumps(report['counts'], ensure_ascii=False))


if __name__ == '__main__':
    main()
