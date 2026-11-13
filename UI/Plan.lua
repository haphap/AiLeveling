local _, A = ...
A.UI.Plan = {}
local UI=A.UI.Plan

function UI.Key(candidate)
    return candidate and tostring(candidate.id)
end

function UI.Rows(plan)
    local rows,seen={},{}
    local function add(candidate)
        if candidate and candidate.questId and A.UI.QuestStatus(A.state or {},candidate.questId,plan)=="已交付" then return end
        local key=UI.Key(candidate)
        if key and not seen[key] then rows[#rows+1]=candidate;seen[key]=true end
    end
    add(plan and plan.suggestedDungeon)
    for _,candidate in ipairs(plan and plan.dungeonChoices or {}) do add(candidate) end
    add(plan and plan.best)
    for _,candidate in ipairs(plan and plan.taskChoices or {}) do add(candidate) end
    return rows
end

function UI:Choose(candidate,revision)
    local ok,reason=A.Selection.CanChoose(candidate,revision)
    if not ok then return false,reason end
    if candidate.requiresAcceptance then
        return A.Dungeon:StartTaskBatch(candidate.dungeonId)
    end
    return A.Selection:Lock(candidate,revision)
end
