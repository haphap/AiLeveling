-- Diagnostic-only simulated inventory. Never loaded by the addon or written to SavedVariables.
local M={}

function M.Refresh(state)
    for _,active in pairs(state.quests) do
        local ready=true
        for _,o in ipairs(active.objectives) do
            if o.targetKind=="item" then
                o.numFulfilled=state.bags[o.targetId] or 0
                o.finished=o.numFulfilled>=o.numRequired
            end
            if not o.finished then ready=false end
        end
        active.ready=ready
    end
end

function M.Accept(q,state,data)
    local objectives,_,complex=data:ReferenceObjectiveTargets(q,state)
    if complex or #objectives==0 and not data:DeliveryOnly(q,state) then return nil,"unsupported-objectives" end
    for _,o in ipairs(objectives) do
        if o.targetKind=="item" and (type(o.numRequired)~="number" or o.numRequired<=0 or o.numRequired%1~=0) then
            return nil,"unknown-item-count"
        end
    end
    for _,o in ipairs(objectives) do
        if o.providedOnAccept then state.bags[o.targetId]=math.max(state.bags[o.targetId] or 0,1) end
        o.providedOnAccept=nil
    end
    local active={title=q.title,objectives=objectives}
    state.quests[q.id]=active
    M.Refresh(state)
    return active
end

function M.Objective(id,index,state,gain)
    local active=assert(state.quests[id])
    local objective=index and active.objectives[index]
    if not objective then
        for _,o in ipairs(active.objectives) do if not o.finished then objective=o;break end end
    end
    assert(objective,"no unfinished objective")
    if objective.targetKind=="item" then
        local have=state.bags[objective.targetId] or 0
        state.bags[objective.targetId]=math.max(have+(gain or 0),objective.numRequired)
    else objective.finished=true end
    M.Refresh(state)
end

function M.TurnIn(id,state)
    M.Refresh(state)
    local active=assert(state.quests[id]);assert(active.ready,"turn-in lacks required items")
    local required={}
    for _,o in ipairs(active.objectives) do
        if o.targetKind=="item" then required[o.targetId]=math.max(required[o.targetId] or 0,o.numRequired) end
    end
    for item,count in pairs(required) do state.bags[item]=state.bags[item]-count end
    state.quests[id]=nil;state.completed[id]=true
    M.Refresh(state)
end

return M
