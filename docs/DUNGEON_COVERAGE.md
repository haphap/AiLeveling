# Forever 副本内容清单

目标构建 1.60.1.70862；由 `python3 tools/audit_dungeons.py` 生成。

地图表 81 条中读取 73 条，另 8 条当前不可读取，编号未知。本表记录数据读取与实例分类；开发覆盖结论见 docs/ACCEPTANCE.md，实机证据按原记录保留。

[官方新练级副本清单](https://news.blizzard.com/en-us/article/24301455/explore-the-new-dungeons-of-world-of-warcraft-forever)列出九项；四项来自可读地图表，另五项以同构建客户端提取记录关联原生首领表补入目录。原始地图读取分母保持不变。推荐等级不作为准入等级。

| 官方名称 | 推荐等级 | 地区 | 实例 ID |
| --- | --- | --- | --- |
| Hall of Thanes | 13—18 | Dun Morogh | 3065 |
| Ruins of Lordaeron | 15—20 | Tirisfal Glades | 2999 |
| Excavation Site | 24—29 | Wetlands | 2998 |
| City of Dalaran | 28—33 | Alterac Mountains | 2959 |
| The Drowned City | 35—40 | Stranglethorn Vale, west of Grom'gol | 2970 |
| Krol'dok Stronghold | 40—45 | Riverglades | 3039 |
| Alcaz Prison | 48—53 | Dustwallow Marsh, Alcaz Island | 2994 |
| Blackmaw Hold | 55—60 | Azshara | 2974 |
| Shaper's Terrace | 58—60 | Un'Goro Crater, northern hills | 3001 |

补充地图身份来源及目标资料：

- [沉没之城](https://wowforevertalents.com/dungeons/the-drowned-city/)：实例 2970，原生首领 6 项，关联任务 7 项。
- [克罗多克要塞](https://wowforevertalents.com/dungeons/krol-dok-stronghold/)：实例 3039，原生首领 5 项，关联任务 12 项。
- [奥卡兹监狱](https://wowforevertalents.com/dungeons/alcaz-prison/)：实例 2994，原生首领 5 项，关联任务 3 项。
- [黑喉要塞](https://wowforevertalents.com/dungeons/blackmaw-hold/)：实例 2974，原生首领 7 项，关联任务 1 项。
- [塑造者之台](https://wowforevertalents.com/dungeons/the-shaper-s-terrace/)：实例 3001，原生首领 11 项，关联任务 1 项。

补充目录的入口使用官方所在地区中心及入口方向说明；已确认本内目标来自同构建服务器任务原文和已核对任务事实，其他分类任务保持普通关联。任务接交者仍从 QuestieDB 查询，缺少的任务以实际提供及日志接入。塑造者之台关联95928的四种水晶目标，来源见TASK_XP_AUDIT.json；其余两项已报告任务缺实际ID，尚未补入。


达拉然入城准备：联盟从任务 92432（An Alarming Request）开始，部落关联 93680（Key to the City）及 544（Prison Break In）。目录接入这些准备任务，资格和进度继续由数据库及原生日志决定；资料尚未给出整条解锁链的最终完成标记。

密斯特曼托庄园3109的入口使用暮色森林区域中心与东北部方向说明。[实际插件观察](https://ahledger.com/wow-forever/dungeons/3109-manor-mistmantle)记录庄园内掉落[密斯特曼托家族戒指3629](https://ahledger.com/items/3629-mistmantle-family-ring)，QuestieDB将其关联任务98。目录保留该任务及原有前置，目标位置继续优先用原生航点；观察记录不用于覆盖数据库中的野外位置。

以下列出全部可读的 party 类型地图。任务数按区域分类、别名及已观察任务物品关联，合并 18 个阵营／职业修正上下文；前置含备选分支，实际执行继续检查资格。

| 实例 ID | 名称 | 区域 ID | 入口记录 | 分类关联任务 | 前置候选 |
| ---: | --- | ---: | ---: | ---: | ---: |
| 33 | 影牙城堡 | 209 | 1 | 3 | 0 |
| 34 | 暴风城监狱 | 717 | 1 | 6 | 3 |
| 36 | 死亡矿井 | 1581 | 1 | 6 | 15 |
| 43 | 哀嚎洞穴 | 718 | 1 | 9 | 4 |
| 47 | 剃刀沼泽 | 491 | 1 | 6 | 1 |
| 48 | 黑暗深渊 | 719 | 1 | 12 | 0 |
| 70 | 奥达曼 | 1337 | 2 | 29 | 10 |
| 90 | 诺莫瑞根 | 721 | 1 | 27 | 1 |
| 109 | 沉没的神庙 | 1477 | 1 | 9 | 21 |
| 129 | 剃刀高地 | 722 | 1 | 7 | 0 |
| 189 | 血色修道院 | 796 | 1 | 8 | 10 |
| 209 | 祖尔法拉克 | 1176 | 1 | 10 | 7 |
| 229 | 黑石塔 | 1583 | 2 | 37 | 119 |
| 230 | 黑石深渊 | 1584 | 2 | 41 | 72 |
| 269 | 时光之穴 | 2366 | 1 | 0 | 0 |
| 289 | 通灵学院 | 2057 | 1 | 12 | 92 |
| 329 | 斯坦索姆 | 2017 | 2 | 16 | 97 |
| 349 | 玛拉顿 | 2100 | 1 | 11 | 0 |
| 389 | 怒焰裂谷 | 2437 | 1 | 6 | 2 |
| 429 | 厄运之槌 | 2557 | 1 | 37 | 77 |
| 2720 | 灼热盆地 | 0 | 0 | 0 | 0 |
| 2784 | 屠魔峡谷 | 15475 | 1 | 0 | 0 |
| 2806 | 暗影堡 | 0 | 0 | 0 | 0 |
| 2807 | 燃烧的安多哈尔 | 15828 | 1 | 0 | 0 |
| 2817 | 星陨兽穴 | 15938 | 0 | 0 | 0 |
| 2853 | 逆风小径 | 0 | 0 | 0 | 0 |
| 2875 | 卡拉赞墓穴 | 16074 | 1 | 0 | 0 |
| 2902 | 甲虫之台 | 16295 | 0 | 0 | 0 |
| 2921 | 纳克萨玛斯 | 16394 | 0 | 0 | 0 |
| 2959 | 达拉然城 | 16544 | 1 | 8 | 0 |
| 2998 | 挖掘场：湿地 | 16732 | 1 | 14 | 0 |
| 2999 | 洛丹伦废墟 | 16611 | 1 | 13 | 6 |
| 3065 | 领主大厅 | 16919 | 1 | 3 | 1 |
| 3109 | 密斯特曼托庄园 | 17191 | 0 | 1 | 12 |

分类计数：battleground 5、party 34、raid 13、test-or-unused 6、world-or-transport 15。

另有 87 个上游区域未关联可读客户端地图，完整清单和逐任务 ID 见 DUNGEON_COVERAGE.json。

运行时使用 Data/Dungeons.lua 的副本任务目录，按 QuestieDB 资格、前置及实际目标位置安排准备、进入、目标和交付。全部交齐后保留本内离开步骤，出本恢复自动路线；整次任务行程计时已接入动态任务组。

任务实际位置关联见 DUNGEON_QUEST_LOCATIONS.json，原生准入条件见 DUNGEON_ADMISSION.md。表中无入口或无分类任务的项目须结合这些来源确认用途；未知地图及尚缺入口的项目继续保留在覆盖清单。完整副本覆盖和统一实机验收尚未关闭。
