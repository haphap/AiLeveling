local _, A = ...
A.Audit = {}
local Audit = A.Audit

local function increment(t, key)
    key = tostring(key or 0)
    t[key] = (t[key] or 0) + 1
end

local function yieldBatch(i)
    local thread, main = coroutine.running()
    if i % 10 == 0 and thread and not main then coroutine.yield() end
end

-- Uses the provider's composed API: baked static fixes, dynamic fixes and locale.
function Audit.Build(data, details)
    local db = data.db
    local report = { scope = "effective QuestieDB public API", contract = db.contractVersion,
        total = 0, entities = {}, byLevel = {}, byZone = {}, byClassMask = {}, byRaceMask = {},
        gaps = {}, quests = {}, dungeons = {}, signedPrerequisiteEntries = 0,
        referenceServices={source="effective QuestieDB NPC API",clientVerified=false,npcs=data.serviceCount or 0,idsByMap={}},
        referenceAmenities={source="effective QuestieDB NPC API",clientVerified=false,npcs=data.amenityCount or 0,idsByMap={}} }
    for map,ids in pairs(data.servicesByMap or {}) do
        local list={};for _,id in ipairs(ids) do list[#list+1]=id end
        report.referenceServices.idsByMap[tostring(map)]=list
    end
    for map,ids in pairs(data.amenitiesByMap or {}) do
        local list={};for _,id in ipairs(ids) do list[#list+1]=id end
        report.referenceAmenities.idsByMap[tostring(map)]=list
    end
    for _, kind in ipairs({"Quest", "Npc", "Object", "Item"}) do
        report.entities[kind] = #db[kind].GetAllIds()
    end
    local zones = db.Support.Get("ZoneDB")
    local dungeonByArea = {}
    for id, d in pairs(zones and zones.private.dungeons or {}) do
        report.dungeons[tostring(id)] = { name = d[1], parentArea = d[3], questIds = {},
            entrances = d[4], classification = "requires-client-confirmation" }
        dungeonByArea[id] = id
        for _, alias in ipairs(d[2] or {}) do dungeonByArea[alias] = id end
    end
    local function gap(row, reason)
        for _, existing in ipairs(row.gaps) do if existing == reason then return end end
        row.gaps[#row.gaps + 1] = reason
        increment(report.gaps, reason)
    end
    local function hasPoints(entity, id)
        if not entity.Exists(id) then return false end
        for area, points in pairs(entity.Get(id, "spawns") or {}) do
            if data.maps[area] and data.maps[area] > 0 then
                for _, p in ipairs(points) do
                    if type(p[1]) == "number" and type(p[2]) == "number" and
                        p[1] >= 0 and p[1] <= 100 and p[2] >= 0 and p[2] <= 100 and
                        (not p[3] or p[3] == 0) then return true end
                end
            end
        end
        return false
    end
    local function located(group)
        for kind, entity in ipairs({db.Npc, db.Object}) do
            for _, id in ipairs(group and group[kind] or {}) do
                if hasPoints(entity, id) then return true end
            end
        end
        return false
    end
    for i, id in ipairs(data.ids) do
        local get = function(field) return db.Quest.Get(id, field) end
        local row = { id = id, level = get("questLevel"), requiredLevel = get("requiredLevel"),
            raceMask = get("requiredRaces"), classMask = get("requiredClasses"),
            zone = get("zoneOrSort"), all = get("preQuestGroup"), any = get("preQuestSingle"),
            sourceItemId = get("sourceItemId"), requiredSourceItems = get("requiredSourceItems"),
            requiredSkill = get("requiredSkill"), requiredRanks = get("requiredRanks"),
            requiredMinRep = get("requiredMinRep"), requiredMaxRep = get("requiredMaxRep"),
            requiredSpell = get("requiredSpell"), requiredSpecialization = get("requiredSpecialization"),
            gaps = {} }
        report.total = report.total + 1
        increment(report.byLevel, row.level)
        increment(report.byZone, row.zone)
        increment(report.byClassMask, row.classMask)
        increment(report.byRaceMask, row.raceMask)
        local starter, finisher = get("startedBy"), get("finishedBy")
        row.startedBy, row.finishedBy = starter, finisher
        if not located(starter) then
            if starter and starter[3] and #starter[3] > 0 then gap(row, "item-starter-needs-source")
            else gap(row, "starter-location") end
        end
        if not located(finisher) then gap(row, "finisher-location") end
        local objectives, objectiveCount = get("objectives") or {}, 0
        row.objectives = objectives
        for kind = 1, 6 do
            for _, objective in ipairs(objectives[kind] or {}) do
                objectiveCount = objectiveCount + 1
                if kind == 1 or kind == 2 then
                    if not hasPoints(kind == 1 and db.Npc or db.Object, objective[1]) then gap(row, "objective-location") end
                elseif kind == 3 then
                    local item, found = objective[1], false
                    for _, pair in ipairs({{db.Npc, "npcDrops"}, {db.Object, "objectDrops"}, {db.Npc, "vendors"}}) do
                        for _, entityId in ipairs(db.Item.Get(item, pair[2]) or {}) do
                            if hasPoints(pair[1], entityId) then found = true end
                        end
                    end
                    if not found then gap(row, "objective-item-source") end
                else gap(row, "special-objective-rule") end
            end
        end
        row.objectiveCount = objectiveCount
        if objectiveCount == 0 then gap(row, "objective-or-delivery-rule") end
        for _, group in ipairs({row.all or {}, row.any or {}}) do
            for _, required in ipairs(group) do
                if required < 0 then
                    report.signedPrerequisiteEntries = report.signedPrerequisiteEntries + 1
                    if group == row.any then gap(row, "signed-alternative-prerequisite") end
                end
                if not db.Quest.Exists(math.abs(required)) then gap(row, "missing-prerequisite") end
            end
        end
        local xp = data.xp[id]
        if not xp or xp[2] == nil then gap(row, "xp-reference") end
        local dungeon = dungeonByArea[row.zone]
        if dungeon then
            local list = report.dungeons[tostring(dungeon)].questIds
            list[#list + 1] = id
        end
        if details then report.quests[tostring(id)] = row end
        yieldBatch(i)
    end
    return report
end

function Audit.Text(report)
    local labels = { ["starter-location"]="接取地点缺失", ["finisher-location"]="交付地点缺失",
        ["item-starter-needs-source"]="开启任务物品来源待核对", ["objective-location"]="任务目标地点缺失",
        ["objective-item-source"]="目标物品来源缺失", ["special-objective-rule"]="特殊目标规则待补",
        ["objective-or-delivery-rule"]="目标或送信规则待补", ["missing-prerequisite"]="前置任务 ID 缺失",
        ["signed-alternative-prerequisite"]="特殊备选前置待核对", ["xp-reference"]="经验参考缺失" }
    local lines = {"QuestieDB 有效数据盘点（含上游修正）", "任务总数：" .. report.total,
        "实体 NPC／对象／物品：" .. report.entities.Npc .. "／" .. report.entities.Object .. "／" .. report.entities.Item,
        "存在字段缺口的任务数（同一任务可有多项）："}
    local keys = {}
    for key in pairs(report.gaps) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do lines[#lines + 1] = (labels[key] or key) .. "：" .. report.gaps[key] end
    return table.concat(lines, "\n")
end
