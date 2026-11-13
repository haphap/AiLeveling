local _, A = ...
A.UI.Gear = {}
local UI=A.UI.Gear

function UI:Ids()
    local ids,seen={},{}
    local function add(id) if not seen[id] then ids[#ids+1]=id;seen[id]=true end end
    for _,choice in ipairs(A.plan and A.plan.taskChoices or {}) do
        for id in pairs(choice.gearSources or {}) do add(id) end
    end
    for id,source in pairs(A.Gear.DungeonSources(A.state)) do
        local value=A.Gear.Source(source,A.state,A.Data)
        if value and not value.owned and (value.upgrade.delta>0 or #(value.upgrade.notes or {})>0) then add(id) end
    end
    local target=A.char and A.char.gearTarget
    if target and A.Gear.GetSource(target) then add(target) end
    table.sort(ids,function(a,b) return tostring(a)<tostring(b) end)
    return ids
end
