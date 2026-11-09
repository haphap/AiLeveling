local _, A = ...
A.Navigation = { pins = {}, index = 1 }
local N = A.Navigation

function N:Initialize()
    self.hbd = LibStub and LibStub("HereBeDragons-2.0", true)
    self.hbdPins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
end

function N:Distance(from, to)
    if not from or not to or not self.hbd then return nil end
    return self.hbd:GetZoneDistance(from.map, from.x, from.y, to.map, to.x, to.y)
end

function N:AttachNode(position)
    if not position then return end
    local nearest, best
    for id, node in pairs(A.Content.nodes) do
        -- Authored accessRadius certifies the short connection inside this open area.
        if node.accessRadius and node.position.map == position.map then
            local distance = self:Distance(position, node.position)
            if distance and distance <= node.accessRadius and (not best or distance < best) then nearest, best = id, distance end
        end
    end
    position.node = nearest
end

function N:SetPlan(plan)
    local current=self.actions and self.actions[self.index]
    local goal=self.actions and self.actions[#self.actions]
    local nextActions=plan.best and plan.best.actions or plan.travelActions or (plan.fallback and {plan.fallback}) or {}
    local nextGoal=nextActions[#nextActions]
    local before,after=goal and goal.position,nextGoal and nextGoal.position
    -- Replanning at sea must not send the same task back to its departure dock.
    if current and current.publicTransit and current.atDeparture and goal and nextGoal and
        goal.questId==nextGoal.questId and goal.kind==nextGoal.kind and goal.objectiveIndex==nextGoal.objectiveIndex and
        before and after and before.map==after.map and before.x==after.x and before.y==after.y and not A.state.dead and not self.manual then
        self:RefreshPins();A.QuestAssist:Update();return
    end
    self.index = 1
    self.actions = nextActions
    local node = A.state.position and A.state.position.node
    for i, action in ipairs(self.actions) do
        if action.kind ~= "move" then break end
        if node and action.node == node then self.index = i + 1 end
    end
    self.transitDeparted = nil
    local pos=A.state.position
    self.taskOrigin=pos and {map=pos.map,x=pos.x,y=pos.y}
    self:RefreshPins()
    A.QuestAssist:Update()
end

function N.OnApproach(plan, node)
    if not node or not plan or not plan.best then return false end
    for _, action in ipairs(plan.best.actions or {}) do
        if action.node == node then return true end
        if action.kind ~= "move" and action.kind ~= "transit" then break end
    end
    return false
end

function N:Advance()
    local action = self.actions and self.actions[self.index]
    if A.Dungeon then A.Dungeon:Arrived(action) end
    if A.Observations then A.Observations:Finish(true) end
    self.index, self.transitDeparted = self.index + 1, nil
    self:RefreshPins()
    A.QuestAssist:Update()
    A.dirty = true
end

function N:Current()
    local flight=A.Transport and A.Transport:FlightGate()
    if flight then return flight end
    local hearth=A.Hearth and A.Hearth:Gate()
    if hearth then return hearth end
    if self.manual then return {kind = "manual", title = "手动目的地", position = self.manual} end
    return self.actions and self.actions[self.index]
end

function N:Near(position,target,radius)
    if not position or not target or position.map~=target.map then return false end
    local distance=self:Distance(position,target)
    return distance~=nil and distance<=(radius or 12)
end

function N.Target(action)
    return action and ((action.kind=="transit" and (action.mode=="flight" or action.publicTransit and not action.atDeparture) and action.departure) or action.position)
end

function N:BeginFlight(origin)
    for i=self.index,#(self.actions or {}) do
        local action=self.actions[i]
        if action.kind=="transit" and action.mode=="flight" then
            if self:Near(origin,action.departure,action.departureRadius) then
                self.index=i
                return action
            end
            return
        end
        if action.kind~="move" or not self:Near(origin,action.position,action.arrival) then return end
    end
end

function N:LandFlight(flight,position)
    local action=flight.action
    -- A reference landing can use the continent map while the player reports a zone map.
    local distance=action and self:Distance(position,action.position)
    local arrived=distance~=nil and distance<=(action and action.arrival or 12)
    if action and self.actions and self.actions[self.index]==action and not A.char.paused and not self.manual and
        arrived then
        self:Advance()
        return true
    end
    if action and not arrived and A.Message then
        A:Message("已在其他飞行点落地，按实际位置重新规划。")
    end
    return false
end

function N:RefreshPins()
    if not self.hbdPins then return end
    self.hbdPins:RemoveAllWorldMapIcons(self)
    self.hbdPins:RemoveAllMinimapIcons(self)
    for _, pin in ipairs(self.pins) do pin:Hide() end
    if (not A.settings.pins and not A.settings.minimapPins) or A.char.paused then return end
    local action = self:Current()
    local pos = N.Target(action)
    if not pos then return end
    local pin = self.pins[1]
    if not pin then
        pin = CreateFrame("Frame", nil, UIParent)
        pin:SetSize(24, 24)
        pin.texture = pin:CreateTexture(nil, "OVERLAY")
        pin.texture:SetAllPoints()
        pin:Hide();pin:EnableMouse(true)
        pin:SetScript("OnEnter", function(f)
            GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
            local current = N:Current()
            local target=N.Target(current)
            GameTooltip:SetText((current and current.title or "AiLeveling")..(target and target.approximate and " · 区域参考点" or ""))
            GameTooltip:Show()
        end)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.pins[1] = pin
    end
    -- HBD-Pins requires separate frames for minimap/world map ownership.
    local mini = self.pins[2]
    if not mini then
        mini = CreateFrame("Frame", nil, UIParent)
        mini:SetSize(18, 18)
        mini.texture = mini:CreateTexture(nil, "OVERLAY")
        mini.texture:SetAllPoints()
        mini:Hide();mini:EnableMouse(true)
        mini:SetScript("OnEnter",function(f)
            GameTooltip:SetOwner(f,"ANCHOR_RIGHT")
            local current=N:Current();local target=N.Target(current)
            GameTooltip:SetText((current and current.title or "AiLeveling")..(target and target.approximate and " · 区域参考点" or ""));GameTooltip:Show()
        end)
        mini:SetScript("OnLeave",function() GameTooltip:Hide() end)
        self.pins[2] = mini
    end
    local atlas=({accept="QuestNormal",turnin="UI-QuestPoi-QuestBangTurnIn",dungeonEnter="Dungeon"})[action.kind]
        or (action.kind=="transit" and action.mode=="flight" and "FlightPath") or "Waypoint-MapPin-Tracked"
    pin.texture:SetAtlas(atlas,false);mini.texture:SetAtlas(atlas,false)
    if A.settings.pins then self.hbdPins:AddWorldMapIconMap(self, pin, pos.map, pos.x, pos.y, 1) end
    if A.settings.minimapPins then self.hbdPins:AddMinimapIconMap(self, mini, pos.map, pos.x, pos.y, false, true) end
end

function N:Update()
    if not self.hbd then return end
    if A.Transport and A.Transport:InFlight() then A.UI:SetNavigation(nil);return end
    if A.Hearth and A.Hearth:InTransit() then A.UI:SetNavigation(nil);return end
    local action, pos = self:Current(), A.state.position
    if action and action.publicTransit and not A.char.paused and not self.manual and pos then
        local arrival=self:Distance(pos,action.position)
        if arrival and arrival<=(action.arrival or 40) then self:Advance();return end
        if not action.atDeparture and self:Near(pos,action.departure,action.departureRadius) then
            action.atDeparture=true;self:RefreshPins();A.dirty=true
        end
    end
    local publicTravel=action and action.publicTransit and action.atDeparture
    if not publicTravel and A.plan and A.plan.unverified and pos and self.taskOrigin and not self.manual and not A.char.paused and
        (not self.replanAt or GetTime()>=self.replanAt) and not (A.jobs and A.jobs.plan) then
        local distance=self:Distance(self.taskOrigin,pos)
        if distance and distance>=75 then self.replanAt=GetTime()+5;A:Replan() end
    end
    if pos then
        local changedMap = self.lastMap and self.lastMap ~= pos.map
        local offRoad = pos.node and pos.node ~= self.lastNode and not N.OnApproach(A.plan, pos.node)
        local expectedTransit = action and action.kind == "transit" and action.position and action.position.map == pos.map
        if not publicTravel and not self.manual and not A.char.paused and ((changedMap and not expectedTransit) or offRoad) and
            (not self.replanAt or GetTime() >= self.replanAt) then
            self.replanAt = GetTime() + 2
            A:Replan()
        end
        self.lastMap, self.lastNode = pos.map, pos.node
    end
    if action and action.kind=="service" and not A.char.paused and A.Supplies and A.Supplies.Done(action,A.state) then
        self:Advance();return
    end
    if not action or not action.position or not pos or A.char.paused then
        A.UI:SetNavigation(nil)
        return
    end
    if publicTravel then A.UI:SetNavigation(nil);return end
    local flight=action.kind=="transit" and action.mode=="flight"
    if (flight or action.kind=="transit" and action.mode=="hearth") and self:Near(pos,action.position,action.arrival) and
        (not self.replanAt or GetTime()>=self.replanAt) then
        self.replanAt=GetTime()+2
        A:Replan()
        return
    end
    local target = N.Target(action)
    if not target then A.UI:SetNavigation(nil);return end
    local distance = self:Distance(pos, target)
    -- Floor changes need a map match as well as geometric proximity.
    if (action.kind == "move" or action.kind=="approach" or action.kind == "dungeonEnd") and pos.map == target.map and distance and distance <= (action.arrival or 12) then
        self:Advance()
        return
    end
    if action.kind == "transit" and not flight and action.mode~="hearth" and not action.publicTransit then
        if not distance or pos.map ~= target.map or distance > (action.arrival or 12) then self.transitDeparted = true end
        if self.transitDeparted and pos.map == target.map and distance and distance <= (action.arrival or 12) then
            self:Advance()
            return
        end
    end
    local x, y, instance = self.hbd:GetWorldCoordinatesFromZone(pos.x, pos.y, pos.map)
    local tx, ty, targetInstance = self.hbd:GetWorldCoordinatesFromZone(target.x, target.y, target.map)
    local angle
    if x and tx and instance == targetInstance then angle = self.hbd:GetWorldVector(instance, x, y, tx, ty) end
    local facing = GetPlayerFacing()
    A.UI:SetNavigation(distance, angle and facing and (angle - facing), A.plan and A.plan.unverified)
end
