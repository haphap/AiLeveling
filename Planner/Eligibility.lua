local _, A = ...
A.Eligibility = {}
local E = A.Eligibility

function E.InMask(mask, member)
    if not mask or mask == 0 then return true end
    if not member or member <= 0 then return nil end
    -- Division preserves the 33rd/34th bits used by Forever race masks.
    return math.floor(mask / member) % 2 == 1
end

local function started(s, id) return s.quests[id] ~= nil or s.completed[id] == true end
local function rank(s, requirement)
    if not requirement then return true end
    local value = s.skills and s.skills[requirement[1]]
    if value == nil then return nil end
    return value >= requirement[2]
end

function E.Prerequisite(id, s, data)
    if s.completed[math.abs(id)] then return true end
    -- Questie group negatives require that exact turn-in; positives accept an exclusive alternative.
    if id > 0 and data then
        local required = data:GetQuest(id)
        for _, alternative in ipairs(required and required.exclusiveTo or {}) do
            if s.completed[alternative] then return true end
        end
    end
    return false
end

function E.Check(q, s, data, ignorePrerequisites)
    if s.skipped and s.skipped[q.id] then return false, "已暂缓" end
    if s.chainDeferred and s.chainDeferred[q.id] then return false,"整链已暂缓（起点 #"..s.chainDeferred[q.id].."）" end
    if s.quests[q.id] then return true end
    if s.completionKnown == false then return false, "已交付任务记录加载中" end
    if s.completed[q.id] and not q.repeatable then return false, "已交付" end
    if s.level < (q.requiredLevel or 0) then return false, "等级不足" end
    if (q.requiredMaxLevel or 0) > 0 and s.level > q.requiredMaxLevel then return false, "超过可接等级" end
    if E.InMask(q.requiredRaces, s.raceMask) ~= true then return false, "种族条件不满足或未知" end
    if E.InMask(q.requiredClasses, s.classMask) ~= true then return false, "职业条件不满足或未知" end
    for _, id in ipairs(not ignorePrerequisites and q.preQuestGroup or {}) do
        if id == 0 or not E.Prerequisite(id, s, data) then return false, "前置未交付", math.abs(id) end
    end
    if not ignorePrerequisites and q.preQuestSingle and #q.preQuestSingle > 0 then
        local met = false
        for _, id in ipairs(q.preQuestSingle) do if s.completed[id] then met = true end end
        if not met then return false, "备选前置未交付", q.preQuestSingle[1] end
    end
    for _, id in ipairs(q.exclusiveTo or {}) do if started(s, id) then return false, "互斥任务已开始" end end
    if not ignorePrerequisites and (q.parentQuest or 0) > 0 and not s.quests[q.parentQuest] then return false, "父任务未进行" end
    if (q.nextQuestInChain or 0) > 0 and started(s, q.nextQuestInChain) then return false, "后续任务已开始" end
    if (q.breadcrumbForQuestId or 0) > 0 and started(s, q.breadcrumbForQuestId) then return false, "指向任务已开始" end
    if (q.availableUntilCompleted or 0) > 0 and s.completed[q.availableUntilCompleted] then return false, "可接窗口结束" end
    if not ignorePrerequisites and (q.availableStartingWith or 0) > 0 and not started(s, q.availableStartingWith) then return false, "尚未开放" end
    if (q.disabledByQuest or 0) > 0 and s.quests[q.disabledByQuest] then return false, "暂时不可接" end
    if rank(s, q.requiredSkill) ~= true then return false, "专业资格不足或未知" end
    if q.requiredRanks then
        local met = false
        for _, r in ipairs(q.requiredRanks) do if rank(s, r) == true then met = true end end
        if not met then return false, "备选专业资格不足或未知" end
    end
    for _, key in ipairs({"requiredMinRep", "requiredMaxRep"}) do
        local req = q[key]
        if req then
            local value = s.reputations and s.reputations[req[1]]
            if value == nil then return false, "声望资格未知" end
            if key == "requiredMinRep" and value < req[2] then return false, "声望不足" end
            if key == "requiredMaxRep" and value >= req[2] then return false, "超过声望上限" end
        end
    end
    if (q.requiredSpell or 0) > 0 and not (s.spells and s.spells[q.requiredSpell]) then return false, "所需技能未确认" end
    if (q.requiredSpecialization or 0) > 0 and not (s.specializations and s.specializations[q.requiredSpecialization]) then
        return false, "专业或专精条件未满足或未知"
    end
    return true
end
