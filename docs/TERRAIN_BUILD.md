# 当前客户端地形生成

此流程补充任务目标附近的步行通路。游戏内已安装版本仍为 0.1.28-dev；本文件记录离线工具与数据产物，目标客户端行走、端点楼层和规划性能需要后续接线验收。

## 固定输入

- 本机产品 wowf，构建 1.60.1.70862，资源语言 zhCN；从安装根目录的 .build.info 核对唯一活动记录。
- [Shortest Path Forever 06a819ef](https://github.com/cjber/shortest-path-forever/tree/06a819ef3be7920b373b99da377adb7c0e91b125/tools/baker)：152 个工具文件下载时核对固定 Git tree 的 blob SHA1，执行前再核对 TERRAIN_RECIPE.json 内的 SHA256。
- [TrinityCore e3916b2](https://github.com/TrinityCore/TrinityCore/tree/e3916b2adcf2f8a70ae33817fc57b6c0266e2fb0)：仅编译 mapextractor、vmap4extractor、vmap4assembler、mmaps_generator，禁用服务端、脚本、测试及 jemalloc。
- 应用 SPF 的 trinitycore-client.patch、trinitycore.patch、trinitycore-nav.patch，再应用 tools/terrain/trinitycore-active-doodads.patch。四份补丁的哈希以及四个实际可执行文件哈希均固定在 TERRAIN_RECIPE.json；重新编译产生不同哈希时，需要记录新配方并使用新输出目录。
- Ninja 1.13.2-3.1、Boost 1.92.0-1.1 只解压到 .dependencies/terrain-toolchain/prefix；下载包的系统信任密钥签名检查通过，下载地址、SHA256 和签名摘要见该目录的 packages.json。Boost 运行库来自相同版本的本机包缓存。没有系统安装操作。

## 编译记录

SPF 工具保存在 .dependencies/SPF-06a819ef；TrinityCore 源码、构建和日志保存在 .dependencies/terrain-build。

TrinityCore 使用固定提交的 sparse checkout，目录包括 src/tools、src/common、src/genrev、dep、cmake、sql/base/dev。CMake 使用 Ninja、Release、TOOLS=ON、SERVERS=OFF、SCRIPTS=none、BUILD_TESTING=OFF、USE_COREPCH=OFF、NOJEM=ON，CMAKE_PREFIX_PATH 指向上述本地 prefix/usr。仅运行 build，没有运行 install。首次配置／编译日志为 configure.log、build.log；活动集合补丁重编译记录为 build-active-doodads.log。

原三补丁版本的二进制保存在 bin-before-active-doodads，旧配方保存在 dist/TERRAIN_RECIPE-before-active-doodads.json。当前补丁是对原三补丁之后的源码应用；活动集合补丁之外没有手工修改第三方工具。

## 执行

以下命令从项目根目录运行。输出目录必须与游戏目录分离，启动器同时拒绝游戏子目录、指向游戏的符号链接及游戏的祖先目录。检查模式核对构建、工具、补丁和可执行文件，不运行提取。

```sh
rtk proxy python3 tools/bake_terrain.py \
  --wow '/home/hap/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft' \
  --out .dependencies/terrain-input-check --check

rtk proxy nice -n 10 python3 tools/bake_terrain.py \
  --wow '/home/hap/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft' \
  --out .dependencies/terrain-active-70862-zhCN \
  --maps 2991 0 1 --threads 4 --jobs 4
```

默认 zhCN 通过独立 Python 子进程配置上游 LOCALE 变量，不修改其固定源码。每个原生命令、locale、产品和补丁进入 source.json 的配方。mapextractor 从 WDT 盘点预期地形块，每个预期块必须有 ok 或 empty 终态；缺少、失败或额外 tile 会阻止生成。压缩包只有经过完整性检查才替换输出目录下的 Nav 文件。图幅之外的地图、地下城与动态障碍另行建设。

完成三张图后运行 `rtk proxy python3 tools/audit_terrain.py .dependencies/terrain-active-70862-zhCN`，逐一核对 WDT 终态、配方、实际 tile 哈希、生成输入、原始输出和压缩文件清单，写入 TERRAIN_DATA_AUDIT.json。

同一输出目录只运行一个进程。接续前先检查当前会话与日志；失败时保留 scratch 和错误。相同配方可以使用上游的终态恢复；不同构建、二进制或裁剪范围使用新目录。不得将失败地形块按 empty 处理。

## 活动装饰集合修正

原提取器在读取建筑物模型的名称表时，会打开所有名称对应的小模型，包括没有放置于当前活动集合中的旧模型。本机全图在 ID 194853 和 603672 上得到 FILE_NOT_FOUND；对中文、英文和所有语言掩码的只读 CASC 查询结果一致。

补丁将读取延后到既有 ExtractSet 的过滤之后，只解析建筑实际引用、且属于默认集合或该实例选定集合的模型。实际引用的模型读取失败仍由原 FailExtraction 终止，正常的无碰撞模型仍按原逻辑处理。补丁没有添加模型排除名单，也没有把缺失碰撞视为空地。

四个裁剪地形块的前后对照保存在 dist/terrain-active-regression.json：54698 条碰撞摆放记录在排除临时生成 ID 后的多重集相同，实际引用的 466 个模型逐字节相同；未使用的模型文件从 502 减到 466。生成的临时 ID 和输入顺序变化使 Recast 三角化结果稍有差异，因此 mmtile 的 byteIdentical 结果保留为 false。对照检查基于实际摆放、变换、边界和模型内容。

实际危险液体 helper 的 10 项检查通过；tools/test_bake_terrain.py 的三个输入边界用例覆盖固定文件篡改／缺失、目录隔离与产品构建身份。离线查询探针位于 dist/terrain-query-probe.lua，借用固定的 SPF 搜索器检查生成网格；网格内样本查询不证明所有任务端点或实机行走均可用。

## 许可与交付边界

AiLeveling 的启动器及原有代码保留 MIT。独立的 TrinityCore 修改补丁为 GPL-2.0-or-later，完整许可见 tools/terrain/COPYING.GPL-2.0.txt，原代码版权归 TrinityCore 作者。下载的 SPF 工具及其派生导航数据为 GPL-3.0-or-later，Recast/Detour 为 zlib，CascLib 为 MIT。来源与声明见固定 SPF 的 README、LICENSE 和 THIRD_PARTY.md。

当前生成数据与第三方路由代码尚未导入游戏内插件。接入时应携带相应许可、来源与适用构建，在实际规划器中处理楼层歧义、路端连接、分帧和缓存；正式发布继续受 PLAN.md 的完整覆盖与实机门槛约束。
