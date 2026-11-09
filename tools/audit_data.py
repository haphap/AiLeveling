#!/usr/bin/env python3
"""Inventory the pinned release's composed API across faction/class correction branches."""
import hashlib
import json
from pathlib import Path
import subprocess
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[1]
CLASSES = ('WARRIOR', 'PALADIN', 'HUNTER', 'ROGUE', 'PRIEST', 'SHAMAN', 'MAGE', 'WARLOCK', 'DRUID')


def audit(persona):
    faction, cls = persona
    result = subprocess.run(['lua5.1', str(ROOT / 'tools/audit_effective.lua'), str(ROOT),
                             str(ROOT / '.dependencies/QuestieDB'), faction, cls],
                            cwd=ROOT / '.dependencies/QuestieDB-1.0.12',
                            check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def main():
    personas = [(faction, cls) for faction in ('Alliance', 'Horde') for cls in CLASSES]
    # These exercise correction branches; playable combinations still need a client census.
    with ThreadPoolExecutor(max_workers=3) as executor:
        results = list(executor.map(audit, personas))
    base = results[0]
    variants = []
    for report in results[1:]:
        changes = {key: row for key, row in report['quests'].items()
                   if row != base['quests'].get(key)}
        variant={'persona': report['persona'], 'total': report['total'],
                 'gaps': report['gaps'], 'questOverrides': changes,
                 'referenceServicesSameAsBase': report['referenceServices']==base['referenceServices']}
        if not variant['referenceServicesSameAsBase']:
            variant['referenceServices']=report['referenceServices']
        variant['referenceAmenitiesSameAsBase']=report['referenceAmenities']==base['referenceAmenities']
        if not variant['referenceAmenitiesSameAsBase']:
            variant['referenceAmenities']=report['referenceAmenities']
        variants.append(variant)
    report = {'schema': 1, 'source': 'QuestieDB 1.0.12 Forever packaged runtime',
              'scope': 'baked static + persona dynamic corrections; zhCN; offline API',
              'coverageLocked': False, 'clientVerified': False,
              'personaScope': 'both factions x nine class correction branches; not a playable race/class census',
              'base': base, 'variants': variants}
    archive = ROOT / '.dependencies/QuestieDB-1.0.12-Forever.zip'
    report['archiveSHA256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
    output = ROOT / 'docs/EFFECTIVE_DATA_AUDIT.json'
    output.write_text(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + '\n')
    lines = ['# Forever 有效数据与覆盖缺口', '',
             '自动生成：`python3 tools/audit_data.py`。来源为固定发行包的公开 API，含静态与动态修正，语言 zhCN。', '',
             f'任务 {base["total"]} 条；NPC {base["entities"]["Npc"]}、对象 {base["entities"]["Object"]}、物品 {base["entities"]["Item"]}。', '',
             f'已通过实际适配器建立 {base["adapter"]["chainRelations"]} 条任务关系；前置、后续关联与互斥分别保留，缺失关联 ID 继续列为资料缺口。', '',
             f'已索引 {base["referenceServices"]["npcs"]} 个有有效地图坐标的参考商人／维修 NPC；逐地图 ID 见报告 referenceServices，阵营与商品关系在推荐时按有效 API 过滤。该计数不计入自有已验证服务内容。', '',
             f'另有 {base["referenceAmenities"]["npcs"]} 个参考训练师／旅店 NPC；逐地图 ID 见 referenceAmenities，职业适用性和可学项目以当前原生训练窗口为准。', '',
             '双阵营 × 九职业用于遍历上游动态修正分支；当前构建56个可玩组合已与官方表交叉核对，见 PLAYABLE_COVERAGE.md／json 的336项分段清单。完整行程覆盖仍待验收；副本分类见 DUNGEON_COVERAGE.md。', '',
             '| 缺口 | 任务数（可重复归类） |', '| --- | ---: |']
    lines.extend(f'| {key} | {count} |' for key, count in sorted(base['gaps'].items()))
    lines.extend(['', '各任务 ID、等级、区域、资格掩码、前置、物品与缺口见 EFFECTIVE_DATA_AUDIT.json。',
                  '上游 dungeon 支持表含副本、团队副本、战场和交通区域；原样保留并标记待分类，未当作练级副本完成清单。', '',
                  '自有已验证行动链和副本均为 0；完整行程可执行性仍阻断完整首版发布。道路资料已退出验收。', ''])
    (ROOT / 'docs/DATA_COVERAGE.md').write_text('\n'.join(lines))
    print(f'{len(results)} correction personas; {base["total"]} effective quests -> {output}')


if __name__ == '__main__':
    main()
