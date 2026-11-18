local _, A = ...
A.UI.Dungeon = {}
local UI = A.UI.Dungeon

-- Describe the same live destination used by task navigation; never print coordinates.
function UI:TaskDirection(row)
    if row.group==5 then return end
    local id,point,area,item=row.id,row.position,row.areaId,row.pickupItem
    if not row.allowed then
        if not row.preparation then return row.reason or "先解锁任务" end
        if #row.preparation>1 then return "先完成前置任务 · 点击指引" end
        id=row.preparation[1]
        local q=A.Data:GetQuest(id)
        local unavailable
        if q then point,unavailable,item=A.Data:Target(q,A.state) end
        area=not point and q and A.Data.UnmappedTargetArea and A.Data:UnmappedTargetArea(q,A.state)
        if unavailable then return "前置任务接取点暂不可用" end
    end
    local active=A.state.quests[id]
    local kind=active and (active.ready and "turnin" or "objective") or "accept"
    local q=A.Data:GetQuest(id)
    local action=A.Dungeon.TaskApproach({kind=kind,questId=id,title=q and q.title or row.title,position=point,areaId=area,
        startItemId=item and item.held and item.id,text=item and item.text},A.state,A.Data)
    local destination=action.position
    local label
    if destination and destination.startItemId then
        label="使用「"..(destination.label or "任务物品").."」接取"
    elseif destination and destination.sourceKind=="patrol" then
        label=destination.travelHint
    elseif destination then
        local map=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(destination.map)
        local place=map and map.name or "任务区域"
        local name=destination.entityName
        if action.kind=="dungeonEnter" then name=destination.label end
        label=(kind=="accept" and action.kind==kind and "接取：" or kind=="turnin" and action.kind==kind and "交付：" or "前往：")..
            place..(name and name~=place and " · "..name or "")
    else
        label=action.text or (kind=="accept" and "接取位置未知" or "继续任务目标")
    end
    if id~=row.id then label="前置 · "..label end
    local seconds=destination and not destination.startItemId and A.Travel.Walk(A.state.position,destination,A.state,A.Navigation)
    return label,seconds
end
