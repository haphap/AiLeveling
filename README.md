<h1 align="center">AILeveling</h1>

<p align="center"><b>少跑路，多经验。</b><br>为 World of Warcraft: Forever 动态安排接任务、做目标与集中交付。</p>

<p align="center">
  <a href="https://github.com/haphap/AiLeveling/releases"><b>下载安装包</b></a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#功能">功能</a> ·
  <a href="https://github.com/haphap/AiLeveling/issues">反馈问题</a>
</p>

从你当前的位置和任务进度出发，AILeveling 会考虑已接任务、可接任务与前置关系，把附近目标一起安排，并告诉你下一步去哪里、找谁、做什么。打怪和拾取时，列表实时更新数量。同一区域内走动和停下会沿用当前行程。接取或交付任务、完成子目标、升级或换区时，插件会重新安排下一步。

## 界面一览

<table>
  <tr>
    <td width="35%" valign="top" align="center">
      <a href="https://github.com/haphap/AiLeveling/blob/main/docs/images/tracker.png"><img src="https://raw.githubusercontent.com/haphap/AiLeveling/main/docs/images/tracker.png" width="300" alt="任务追踪：当前目标、接下来、后续行程和顺路任务"></a>
      <br><b>边走边做。</b><br>目标数量、下一步与顺路机会集中显示。
    </td>
    <td width="65%" valign="top" align="center">
      <a href="https://github.com/haphap/AiLeveling/blob/main/docs/images/plan.png"><img src="https://raw.githubusercontent.com/haphap/AiLeveling/main/docs/images/plan.png" width="640" alt="主界面：分类导航、任务列表与所选任务详情"></a>
      <br><b>看清整趟安排。</b><br>浏览任务、职业、专业、坐骑和地下城。在地下城详情切换「装备掉落」，按首领查看装备和物品提示。
    </td>
  </tr>
</table>

图片由插件实际 UI 代码渲染，使用示例数据；任务组合与进度用于展示布局。

## 快速开始

适用于 **WoW: Forever**，目标接口 `16001`、客户端构建 `1.60.1.70862`。

1. 安装以下两个依赖，并在游戏插件列表中启用：

   | 依赖 | 版本要求 |
   | --- | --- |
   | [QuestieDB](https://github.com/Questie/QuestieDB/releases/tag/v1.0.13) | v1.0.13 Forever；兼容 v1.0.12 或公开 Contract 4 的兼容发行版 |
   | [HereBeDragons](https://www.wowace.com/projects/herebedragons/files) | Forever 兼容包，包含 HBD 2.0 与 HBD-Pins 2.0 |

2. 从 [Releases](https://github.com/haphap/AiLeveling/releases) 下载附件 **`AiLeveling-*.zip`**。将其中的 `AiLeveling` 文件夹解压到：

   ```text
   World of Warcraft/_forever_/Interface/AddOns/AiLeveling/
   ```

   `AiLeveling.toc` 应直接位于这个文件夹中。GitHub 的 “Source code” 是源码归档，安装请使用上述 ZIP 附件。

3. 完全退出并重新启动游戏，启用 AILeveling。登录后查看小地图下方的任务列表；输入 **`/ail`** 打开主界面。

## 功能

- **动态任务行程。** 按当前位置、等级、任务进度与前置关系安排接取、目标和交付，比较整批经验与跑路距离。自动跳过过级、往返远且收益低的任务，保留同路目标和有价值的后续；也可自行暂缓或锁定任务。
- **DaylightUI 皮肤。** 启用 DaylightUI 后自动跟随其窗口、按钮、字体与配色，HUD 保持 60% 透明度；未启用时使用默认外观。
- **按批次换区。** 先完成本区值得做的已接任务并集中交付，再前往下一站；行程明确列出要交的任务、下一站要接的任务，以及适合升级后回访的任务。
- **一起做，一起交。** 合并附近与共同目标，同一 NPC 的任务尽量集中交付；完成后明确提示现在就近交，还是做完同组再交。主行程连续展示，附近可接任务与未开通飞行点列在主行程之后，点击即可导航；适合下一级做的本地任务可先接备用，并标明建议等级。
- **路过就提醒。** 附近有顺路目标时显示“顺便完成”、具体行动、剩余数量和距离，点击让箭头指路，右键忽略附近提示；同一目标再次忽略后，本次地图停留期间不再提示。
- **地图标记。** 大地图用角标显示行程顺序，职业色外环标出当前目的地。绿色问号可立即交付，灰色问号是后续交付。小地图显示附近能做的任务和当前目的地方向。
- **跨区导航。** AILeveling 的导航界面显示当前步骤和下一步。途中提示在哪里搭车、坐船或转乘，抵达后指引接取、完成或交付任务。启用 WaypointUI 时由它显示方向和距离，步骤文字持续显示。副本内即使没有可用坐标，也能查看当前任务指引。
- **副本任务模式。** 进本后，小地图下原有的任务列表自动切换到当前副本。列表逐项显示进行中、未接取和可交付的任务，沿用原来的图标、目标计数和滚动方式。漏接的任务显示接取指引或前置，完成后提示在本内还是出本后交付。点击「副本任务」可打开详情。出本后原位恢复练级行程。
- **职业、技能与坐骑。** 在主窗口左侧切换“练级任务”和“职业任务”可查看各自的任务。点击“跟随这条职业任务线”后从前置推进到解锁，点击“恢复练级导航”返回自动安排。可学技能在任务列表提醒，坐骑解锁可在“坐骑任务”中查看。
- **装备提升。** 任务列表内简短显示新装备和提升幅度，右键换装，点 × 后不再提醒这件。接任务时预告提升奖励，交任务时建议可选奖励；悬停物品链接查看对比。
- **副本任务准备。** 优先推荐等级合适且有任务可做的副本，前置准备、过级补做靠后，按当前可做任务的经验与路程排序。主任务列表显示建议和任务数，点击查看待接任务与前置；选择后提供接取地点和跑路指引，从准备、入本到交付连续安排。点击“返回正常练级”可随时结束副本安排，已接任务和进度保留。
- **练级辅助。** 任务道具与目标按钮、背包整理、队伍进度、天赋方案、经验统计、稀有和危险提醒可按需使用。

## 常用操作

| 操作 | 作用 |
| --- | --- |
| `/ail` | 打开主界面与设置 |
| 左键任务 | 查看任务日志或待接任务详情 |
| 左键顺路待接任务，或右键选「导航到此任务」 | 指向接取地点。开启自动接取时，对话只接所选任务，随后继续原行程。物品起始任务显示使用入口 |
| 右键任务 | 优先做、暂缓、解除锁定 |
| 标题栏 ≡／右键标题栏 | 放大缩小字体、暂停、收起列表、恢复小地图对齐 |
| 拖动标题栏／右下角 | 移动面板／调整宽高 |
| `/ail pause`、`/ail resume` | 暂停引导／恢复自动安排 |
| 与 NPC 对话时按住 Shift | 临时手动接交和选择航线 |

任务状态使用图标与颜色区分：**蓝色待接、金色已接、绿色可交付**。目标数量实时更新，完成项保留勾选标记。

<details>
<summary>更多命令</summary>

| 命令 | 作用 |
| --- | --- |
| `/ail bags` | 背包整理与垃圾／保留标记 |
| `/ail party` | 队友进度与任务共享 |
| `/ail talents` | 保存、预览和载入天赋方案 |
| `/ail stats` | 经验效率与等级耗时统计 |
| `/ail history` | 已完成任务历史 |
| `/ail way 地图ID 横坐标 纵坐标` | 设置手动目的地，坐标范围 0—100 |
| `/ail status` | 查看版本和诊断信息 |

任务物品按钮可在“系统按键设置 → AILeveling”绑定快捷键。

</details>

## 更新与反馈

更新前退出游戏，备份原 `AiLeveling` 文件夹，再用新安装包替换。保留账号与角色的 `SavedVariables/AiLeveling.lua`（以及同名 `.lua.bak`），即可保留设置和任务选择；需要回退时恢复备份。

遇到任务安排、导航或显示问题，请在 [Issues](https://github.com/haphap/AiLeveling/issues) 提供任务名、所在区域、具体操作，以及 `/ail status` 的诊断信息。界面问题可附截图。每个 Release 都附有安装 ZIP 和 SHA256 校验文件。

## 致谢与许可

任务接取、目标与交付使用无限版 [QuestieDB](https://github.com/Questie/QuestieDB)。任务奖励和飞行耗时采用无限版客户端与服务器记录。坐标与地图标记使用 [HereBeDragons](https://www.wowace.com/projects/herebedragons)。界面与交互参考 [Polestar](https://github.com/fitzforge/polestar)、[LumensUI](https://www.curseforge.com/wow/addons/lumensui)、[RestedXP](https://github.com/RestedXP/RXPGuides) 和 [Lueur](https://www.curseforge.com/wow/addons/lueur)。

自有代码采用 [MIT](https://github.com/haphap/AiLeveling/blob/main/LICENSE)。Polestar 装备图标按 [GPL-3.0](https://github.com/haphap/AiLeveling/blob/main/docs/LICENSE.Polestar.txt) 分发；RestedXP 危险位置与急救参考数据按 [CC BY-NC-SA 4.0](https://github.com/haphap/AiLeveling/blob/main/docs/LICENSE.RestedXP.txt) 分发。游戏界面素材版权归 Blizzard Entertainment，来源与版本见 [来源记录](https://github.com/haphap/AiLeveling/blob/main/docs/SOURCES.json)。
