local A = {}
assert(loadfile("Data/TaskFacts.lua"))("AiLeveling", A)
assert(loadfile("Data/Experience.lua"))("AiLeveling", A)
assert(loadfile("Data/Flights.lua"))("AiLeveling", A)
assert(loadfile("Data/Dungeons.lua"))("AiLeveling", A)
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
    assert(positive(id) and id%1==0 and A.FlightData.nodes[path[1]] and A.FlightData.nodes[path[2]])
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
print(string.format("参考飞行：%d 节点、%d 有向航线、%d 分阵营耗时记录",flightNodes,flightPaths,flightTimes))
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
local referenceDungeons=0
assert(A.DungeonCatalog.version=="1.60.1" and A.DungeonCatalog.build=="70862","副本目录与目标构建不匹配")
for _ in pairs(A.DungeonCatalog.entries) do referenceDungeons=referenceDungeons+1 end
print(string.format("动态副本任务目录：%d 项；服务点通过 QuestieDB 公开接口查询",referenceDungeons))
assert(referenceDungeons>0,"副本任务目录尚未建立")
print("内容结构检查通过")
