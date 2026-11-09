# Forever 有效数据与覆盖缺口

自动生成：`python3 tools/audit_data.py`。来源为固定发行包的公开 API，含静态与动态修正，语言 zhCN。

任务 5233 条；NPC 13417、对象 7045、物品 21442。

已通过实际适配器建立 6701 条任务关系；前置、后续关联与互斥分别保留，缺失关联 ID 继续列为资料缺口。

已索引 1082 个有有效地图坐标的参考商人／维修 NPC；逐地图 ID 见报告 referenceServices，阵营与商品关系在推荐时按有效 API 过滤。该计数不计入自有已验证服务内容。

另有 650 个参考训练师／旅店 NPC；逐地图 ID 见 referenceAmenities，职业适用性和可学项目以当前原生训练窗口为准。

双阵营 × 九职业用于遍历上游动态修正分支；当前构建56个可玩组合已与官方表交叉核对，见 PLAYABLE_COVERAGE.md／json 的336项分段清单。完整行程覆盖仍待验收；副本分类见 DUNGEON_COVERAGE.md。

| 缺口 | 任务数（可重复归类） |
| --- | ---: |
| finisher-location | 466 |
| item-starter-needs-source | 383 |
| item-use-rule | 1184 |
| missing-prerequisite | 1 |
| objective-item-source | 1215 |
| objective-location | 82 |
| objective-or-delivery-rule | 1988 |
| special-objective-rule | 156 |
| starter-location | 336 |
| verified-action-chain | 5233 |
| xp-reference | 1739 |

各任务 ID、等级、区域、资格掩码、前置、物品与缺口见 EFFECTIVE_DATA_AUDIT.json。
上游 dungeon 支持表含副本、团队副本、战场和交通区域；原样保留并标记待分类，未当作练级副本完成清单。

自有已验证行动链和副本均为 0；完整行程可执行性仍阻断完整首版发布。道路资料已退出验收。
