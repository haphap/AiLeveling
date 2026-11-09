local A = {}
assert(loadfile("Data/Content.lua"))("AiLeveling", A)
assert(loadfile("Data/TaskFacts.lua"))("AiLeveling", A)
assert(loadfile("Data/Experience.lua"))("AiLeveling", A)
assert(loadfile("Data/Flights.lua"))("AiLeveling", A)
assert(loadfile("Data/Dungeons.lua"))("AiLeveling", A)
assert(loadfile("Planner/Dungeon.lua"))("AiLeveling", A)
assert(loadfile("Planner/Supplies.lua"))("AiLeveling", A)
assert(loadfile("Planner/Travel.lua"))("AiLeveling", A)
local c, errors, questCount, nodeCount, dungeonCount,serviceCount = A.Content, {}, 0, 0, 0,0
local release = arg[1] == "--release"
local function fail(text) errors[#errors + 1] = text end
local function positive(v) return type(v)=="number" and v>0 and v<math.huge end
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local flightNodes,flightPaths,flightTimes=0,0,0
for id,node in pairs(A.FlightData.nodes) do
    assert(positive(id) and id%1==0 and type(node.name)=="string" and #node.world==3 and
        finite(node.world[1]) and finite(node.world[2]) and finite(node.world[3]) and
        (node.instance==0 or node.instance==1 or node.instance==2991) and node.factionMask>=1 and node.factionMask<=3)
    flightNodes=flightNodes+1
end
for id,path in pairs(A.FlightData.paths) do
    assert(positive(id) and id%1==0 and A.FlightData.nodes[path[1]] and A.FlightData.nodes[path[2]] and finite(path[3]) and path[3]>=0)
    flightPaths=flightPaths+1
end
for _,times in pairs(A.FlightData.durations) do
    for pair,seconds in pairs(times) do
        local from,to=pair:match("^(%d+):(%d+)$")
        assert(A.FlightData.nodes[tonumber(from)] and A.FlightData.nodes[tonumber(to)] and positive(seconds))
        flightTimes=flightTimes+1
    end
end
assert(flightNodes==71 and flightPaths==292 and flightTimes==881)
print(string.format("参考飞行：%d 节点、%d 有向航线、%d 分阵营耗时记录；原生可达与票价门控",flightNodes,flightPaths,flightTimes))
local experienceLevels,experienceTotal=0,0
for level,xp in pairs(A.Experience.xpToLevel) do
    assert(finite(level) and level%1==0 and level>=1 and level<60 and positive(xp) and xp%1==0,"参考经验门槛无效")
    experienceLevels=experienceLevels+1;experienceTotal=experienceTotal+xp
end
assert(experienceLevels==59 and experienceTotal==4084700,"参考经验门槛不完整")
print(string.format("参考升级经验：%d 个门槛，1—60 累计 %d XP；需版本和原生当前门槛匹配",experienceLevels,experienceTotal))
local factCount,rewardCount,xpCount=0,0,0
for id,fact in pairs(A.TaskFacts.quests) do
    factCount=factCount+1
    assert(positive(id) and id%1==0 and (fact.level==nil or finite(fact.level)),"参考任务身份无效")
    for _,o in ipairs(fact.objectives or {}) do
        assert((o.kind=="npc" or o.kind=="object" or o.kind=="item") and positive(o.id) and o.id%1==0,"参考目标无效")
        assert(finite(o.count) and o.count>=0 and o.count%1==0,"参考目标数量无效")
    end
    if fact.xp then
        xpCount=xpCount+1;local previous=0
        for _,change in ipairs(fact.xp) do
            assert(change[1]>previous and change[1]<60 and change[1]%1==0 and finite(change[2]) and change[2]>=0,"参考经验模型无效")
            previous=change[1]
        end
    end
    if fact.rewards then
        rewardCount=rewardCount+1
        assert(finite(fact.rewards.money) and fact.rewards.money%1==0,"参考奖励金币无效")
        for _,list in ipairs({fact.rewards.items,fact.rewards.choices}) do for _,item in ipairs(list) do
            assert(positive(item.id) and item.id%1==0 and positive(item.count) and item.count%1==0,"参考奖励物品无效")
        end end
    end
end
for itemId,drop in pairs(A.TaskFacts.drops or {}) do
    assert(positive(itemId) and itemId%1==0,"参考掉落物品无效")
    for _,kind in ipairs({"npcs","objects","containers"}) do
        for _,source in ipairs(drop[kind] or {}) do
            assert(positive(source.id) and source.id%1==0 and finite(source.percent) and source.percent>=0 and source.percent<=100,"参考掉落来源无效")
        end
    end
end
print(string.format("参考任务：%d 条；奖励 %d 条；等级经验模型 %d 条",factCount,rewardCount,xpCount))
local kinds={accept=true,objective=true,turnin=true,move=true,service=true,transit=true}
for id,node in pairs(c.nodes) do
    nodeCount=nodeCount+1
    local p=node.position
    if not p or not positive(p.map) or type(p.x)~="number" or type(p.y)~="number" or p.x<0 or p.x>1 or p.y<0 or p.y>1 then
        fail("目的地坐标无效："..id)
    end
    if node.verified and not c.sources[node.source] then fail("已验证节点缺少来源："..id) end
    if node.hearth and (type(node.bindName)~="string" or node.bindName=="") then fail("炉石节点缺少绑定地名："..id) end
end
for id,transit in pairs(c.transit or {}) do
    if (not c.nodes[transit.from] and not (transit.kind=="hearth" and transit.from==nil)) or not c.nodes[transit.to] then fail("交通节点缺失："..id) end
    if transit.kind=="flight" and (not positive(transit.fromTaxi) or not positive(transit.toTaxi)) then fail("飞行点映射缺失："..id) end
    if not positive(transit.seconds) then fail("交通耗时无效："..id) end
    if transit.period and not positive(transit.period) then fail("交通周期无效："..id) end
    if transit.kind=="hearth" and not positive(transit.cooldown) then fail("炉石冷却无效："..id) end
    if transit.cost and (type(transit.cost)~="number" or transit.cost<0 or transit.cost==math.huge) then fail("交通费用无效："..id) end
    if transit.verified and not c.sources[transit.source] then fail("已验证交通缺少来源："..id) end
end
for id,q in pairs(c.quests) do
    questCount=questCount+1
    for item,rule in pairs(q.itemRules or {}) do
        local types={use=true,collect=true,key=true,source=true,start=true}
        if not positive(item) or type(rule)~="table" or not types[rule.kind] then fail("物品用途规则无效："..id)
        elseif rule.count and (not positive(rule.count) or rule.count%1~=0) then fail("物品需求数量无效："..id) end
    end
    if q.verified then
        if not c.sources[q.source] then fail("已验证任务缺少来源："..id) end
        if not q.actions or #q.actions==0 or q.actions[#q.actions].kind~="turnin" then fail("任务行动链缺少交付："..id) end
        if q.xp==nil then fail("任务经验模型缺失："..id) end
        for _,a in ipairs(q.actions or {}) do
            if not kinds[a.kind] then fail("未知行动类型："..id) end
            local valid,why=A.Supplies.ValidAction(a)
            if not valid then fail("任务资源模型无效："..id.."，"..why) end
            if a.node and not c.nodes[a.node] then fail("任务目的地缺失："..id) end
            if a.shareKey and (a.kind~="objective" or (a.shareType~="kill" and a.shareType~="collect") or
                not positive(a.targetId) or not positive(a.workUnits) or not positive(a.secondsPerUnit)) then fail("共享目标模型无效："..id) end
        end
    elseif release then fail("未验证任务："..id) end
end
for id,item in pairs(c.items or {}) do
    if item.verified and not c.sources[item.source] then fail("装备记录缺少来源："..id) end
    if item.stackSize and (not positive(item.stackSize) or item.stackSize%1~=0) then fail("物品堆叠数量无效："..id) end
    if item.family and (type(item.family)~="number" or item.family<0 or item.family%1~=0) then fail("物品家族无效："..id) end
    if item.weaponDPS and (type(item.weaponDPS)~="number" or item.weaponDPS<0 or item.weaponDPS>=math.huge) then fail("武器伤害无效："..id) end
end
local function probability(value) return type(value)=="number" and value>=0 and value<=1 end
for id,source in pairs(c.gearSources or {}) do
    if not positive(source.itemId) or (source.kind~="quest" and source.kind~="dungeon") then fail("装备来源类型或物品无效："..id) end
    if source.verified then
        if not c.sources[source.source] then fail("装备来源缺少证据："..id) end
        if source.kind=="quest" and not c.quests[source.questId] then fail("装备奖励任务缺失："..id) end
        if source.kind=="dungeon" and not c.dungeons[source.dungeonId] then fail("装备掉落副本缺失："..id) end
    end
    local low,high=source.chanceLow or source.chance,source.chanceHigh or source.chance
    if (low~=nil or high~=nil) and (not probability(low) or not probability(high) or low>high) then fail("掉落概率区间无效："..id) end
    if source.shareChance~=nil and not probability(source.shareChance) then fail("装备分配概率无效："..id) end
end
local progression=c.progression
if progression and progression.verified then
    if not c.sources[progression.source] then fail("升级经验曲线缺少来源") end
    for level,xp in pairs(progression.xpToLevel or {}) do
        if type(level)~="number" or level%1~=0 or level<1 or level>=60 or not positive(xp) then fail("升级经验曲线条目无效") end
    end
end
for id,d in pairs(c.dungeons) do
    dungeonCount=dungeonCount+1
    if d.verified and not c.sources[d.source] then fail("副本缺少来源："..id) end
    if d.verified then
        if type(d.lockoutNames)~="table" or not next(d.lockoutNames) then fail("副本原生锁定名称映射缺失："..id) end
        local valid,reason=A.Supplies.ValidAction(d)
        if not valid then fail("副本资源模型无效："..id.."，"..reason) end
        for _,action in ipairs(d.actions or {}) do
            local ok,why=A.Supplies.ValidAction(action)
            if not ok then fail("副本行动资源无效："..id.."，"..why) end
        end
        valid,reason=A.Dungeon.Workflow(d,c)
        if not valid then fail("副本行程不完整："..id.."，"..reason) end
        if not positive(d.runSeconds) or type(d.xp)~="number" or d.xp<0 or d.xp==math.huge then fail("副本耗时／经验无效："..id) end
    end
    if release and not d.verified then fail("副本尚未验证："..id) end
end
for id,point in pairs(c.services or {}) do
    serviceCount=serviceCount+1
    local valid,why=A.Supplies.ValidService(point,c)
    if not valid then fail("服务点无效："..id.."，"..why) end
    if release and not point.verified then fail("服务点尚未验证："..id) end
end
if release then
    if c.version=="unverified" then fail("真实内容包尚未验证") end
    if questCount==0 or dungeonCount==0 then fail("任务／副本内容覆盖尚未建立") end
    if serviceCount==0 then fail("服务点内容覆盖尚未建立") end
    if not c.coverage or not c.coverage.locked then fail("完整覆盖盘点尚未锁定") end
    if not c.clientVerified then fail("目标客户端实机验证尚未完成") end
end
print(string.format("自有内容：%d 个任务、%d 个目的地、%d 个副本、%d 个服务点",questCount,nodeCount,dungeonCount,serviceCount))
if questCount==0 then print("QuestieDB 基础任务数量须由实际依赖运行盘点，未计入自有内容。") end
for _,err in ipairs(errors) do io.stderr:write(err,"\n") end
if #errors>0 then os.exit(1) end
print(release and "正式内容门槛通过" or "开发内容结构检查通过；完整首版尚未达到发布门槛")
