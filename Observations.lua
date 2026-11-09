local _, A = ...
A.Observations = {}
local O = A.Observations

local function identity(action)
    return action and table.concat({action.kind or "", action.questId or "", action.node or "",
        action.objectiveIndex or "", action.transitId or "",action.serviceId or "",action.serviceKind or ""}, ":")
end

function O:Reset()
    self.current = nil
end

function O:Tick(now, action, active, enabled)
    if not enabled or not action then self:Reset(); return end
    local key = identity(action)
    if not self.current or self.current.key ~= key then
        local kind = action.kind == "objective" and (action.sampleKind or "quest") or
            (action.kind == "move" and "move") or (action.kind=="service" and (action.sampleKind or "recovery"))
        self.current = kind and {key=key, action=action, kind=kind, started=now, last=now,
            lastActive=now, seconds=0, reference=action.referenceSeconds, valid=true} or nil
    end
    local sample = self.current
    if not sample then return end
    local delta = now - sample.last
    if delta < 0 or delta > 2 then sample.valid = false end
    if active then sample.lastActive = now end
    if now - sample.lastActive > 30 then sample.valid = false end
    if sample.valid then sample.seconds = sample.seconds + math.max(0, delta) end
    sample.last = now
end

function O:Finish(confirmed)
    local sample = self.current
    self:Reset()
    if not confirmed or not sample or not sample.valid or not sample.reference or
        sample.reference <= 0 or sample.seconds < 1 then return end
    local ratio = sample.seconds / sample.reference
    if ratio < 0.25 or ratio > 4 then return end
    local samples = A.char.samples
    if samples[sample.kind] and samples[sample.kind].unit ~= "ratio" then samples[sample.kind] = nil end
    A.State.Observe(samples, sample.kind, ratio)
    if samples[sample.kind] then samples[sample.kind].unit = "ratio" end
    A:RequestRefresh()
end

function O:Refresh(state)
    if not A.settings.learn or A.char.paused or A.Navigation.manual or state.onTaxi or
        (A.Transport and A.Transport:InFlight()) then self:Reset(); return end
    local sample = self.current
    if not sample then return end
    if sample.action.kind=="service" and A.Supplies and A.Supplies.Done(sample.action,state) then self:Finish(true);return end
    if sample.action.kind ~= "objective" then return end
    local action = sample.action
    if action.sharedObjectives then
        for _,shared in ipairs(action.sharedObjectives) do
            local q=state.quests[shared.questId]
            local o=q and q.objectives[shared.objectiveIndex]
            if not state.completed[shared.questId] and not (q and (q.ready or (o and o.finished))) then return end
        end
        self:Finish(true)
        return
    end
    local quest = state.quests[action.questId]
    local objective = quest and quest.objectives[action.objectiveIndex or 1]
    if quest and (quest.ready or (objective and objective.finished)) then self:Finish(true) end
end

function O:Context(state)
    local parts = {state.class, state.role, math.floor(state.level / 10),state.damageStyle or "auto"}
    for _, slot in ipairs({16,17,18}) do
        local item=state.equipment[slot]
        parts[#parts + 1] = item and (item.link or item.id) or 0
    end
    local key = table.concat(parts, ":")
    if A.char.sampleContext and A.char.sampleContext ~= key then
        self:Reset()
        if A.Dungeon and A.Dungeon.runSample then A.Dungeon.runSample.valid=false end
        for kind, sample in pairs(A.char.samples) do
            if kind:sub(1,9)=="taskwork:" then A.char.samples[kind]=nil
            elseif kind:sub(1,7)~="flight:" and kind:sub(1,11)~="flighttime:" and kind:sub(1,11)~="hearthtime:" and kind:sub(1,9)~="tasktalk:" then
                sample.n, sample.m2 = math.floor(sample.n / 4), sample.m2 / 4
            end
        end
    end
    A.char.sampleContext = key
end

function O:Update()
    local usable = A.settings.learn and not A.char.paused and not A.Navigation.manual and
        not (A.Transport and A.Transport:InFlight()) and
        not (UnitIsAFK("player") or UnitIsDeadOrGhost("player"))
    local active = IsPlayerMoving() or UnitAffectingCombat("player") or
        (self.progressAt and GetTime() - self.progressAt < 2)
    local action = A.Navigation:Current()
    local starting = not self.current or self.current.key ~= identity(action)
    self:Tick(GetTime(), action, active, usable)
    if starting and self.current and action.kind == "objective" then
        local quest = A.state.quests[action.questId]
        local objective = quest and quest.objectives[action.objectiveIndex or 1]
        if not objective or (objective.numFulfilled or 0) > 0 then self.current.valid = false end
    end
end
