local _, A = ...
A.Navigation = { pins = {}, index = 1 }
local N = A.Navigation

function N.StaleAction(action,state,plan)
    state,plan=state or A.state,plan or N.plan
    if action and action.kind=="transit" and action.mode=="flight" and action.fromTaxi and action.toTaxi and
        state and state.transportKnown and not state.onTaxi then
        local unlocked=state.unlocked or {}
        if unlocked["taxi:"..action.fromTaxi]~=true or unlocked["taxi:"..action.toTaxi]~=true or
            (state.taxiAvailability or {})[action.fromTaxi..":"..action.toTaxi]~=true then return true end
    end
    if not (action and action.questId and plan and plan.revision and state and plan.revision~=state.revision) then return end
    if action.kind=="transit" or action.kind=="move" or action.kind=="approach" then
        local actions=plan.best and plan.best.actions or plan.travelActions
        local goal=actions and actions[#actions]
        if goal and goal.questId==action.questId then action=goal end
    end
    local active=(state.quests or {})[action.questId]
    if (state.skipped or {})[action.questId] or (state.chainDeferred or {})[action.questId] then return true end
    if not active then
        if (state.completed or {})[action.questId] then return true end
        if (action.kind=="objective" or action.kind=="turnin") and not action.expected then return true end
    end
    if action.kind=="accept" then
        local item=action.position and action.position.startItemId
        return active~=nil or item and ((state.bags or {})[item] or 0)==0
    end
    if not active then return end
    if action.kind=="turnin" and not action.expected then return not active.ready end
    -- Extra collection may still be needed for other quests using the same stock.
    if action.kind=="objective" and action.itemGain and action.itemGain>0 and plan.itemStock then
        return ((state.bags or {})[action.targetId] or 0)>=(plan.itemStock[action.targetId] or 0)+action.itemGain
    elseif action.kind=="objective" and not (action.itemGain and action.itemGain>0) then
        local objective=action.objectiveIndex and (active.objectives or {})[action.objectiveIndex]
        return active.ready or objective and objective.finished
    end
end

function N:Initialize()
    self.hbd = LibStub and LibStub("HereBeDragons-2.0", true)
    self.hbdPins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
end

function N:Distance(from, to)
    if not from or not to or not self.hbd then return nil end
    return self.hbd:GetZoneDistance(from.map, from.x, from.y, to.map, to.x, to.y)
end

function N:SetPlan(plan)
    self.plan=plan
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
    self.transitDeparted = nil
    local pos=A.state.position
    self.taskOrigin=pos and {map=pos.map,x=pos.x,y=pos.y}
    self:RefreshPins()
    A.QuestAssist:Update()
end

function N:Advance()
    local sequence=self:Sequence()
    sequence.index, self.transitDeparted = sequence.index + 1, nil
    self:RefreshPins()
    A.QuestAssist:Update()
    A.dirty = true
end

function N:Sequence()
    return self.manual and self.manual.actions and self.manual or self
end

function N:Pickup(action)
    if not action or action.kind~="accept" then return false end
    return self:Navigate(action)
end

function N:NavigateQuest(id)
    for _,choice in ipairs(self.plan and self.plan.taskChoices or {}) do
        if choice.questId==id and not choice.acceptBlocked and not choice.revisitLevel and
            not choice.requireCheck and not choice.entryBlocked then
            return self:Navigate(choice.actions and choice.actions[1])
        end
    end
    return false
end

function N:Navigate(action)
    local state=A.state
    local id=action and action.questId
    local point=action and action.position
    local active=id and (state.quests or {})[id]
    if not action or (id and ((state.completed or {})[id] or (state.skipped or {})[id] or (state.chainDeferred or {})[id])) or
        state.dead or state.onTaxi or A.char.paused then return false end
    if id and (action.kind=="accept" and active or action.kind=="objective" and (not active or active.ready or
        action.objectiveIndex and (active.objectives or {})[action.objectiveIndex] and active.objectives[action.objectiveIndex].finished) or
        action.kind=="turnin" and (not active or not active.ready)) then return false end
    local target=action
    if action.kind~="accept" and action.kind~="objective" and action.kind~="turnin" then
        target={kind="manual",title=action.title,position=N.Target(action)}
    end
    local approach=A.Dungeon and A.Dungeon.TaskApproach and A.Dungeon.TaskApproach(target,state,A.Data) or target
    if not approach.position and not (id and approach.text) then return false end
    local routes=not (point and point.startItemId) and approach.position and A.Flights and A.Flights.Itinerary(state.position,{approach},state,self)
    local actions=routes and routes[1] and A.Flights.Actions(routes[1],approach,self) or {approach}
    self.manual={title=action.title,action=target,actions=actions,index=1,
        instanceId=state.instanceId,inInstance=state.inInstance,plan={revision=-1,travelActions=actions,itemStock=self.plan and self.plan.itemStock}}
    self:RefreshPins(true)
    self:Update()
    A.QuestAssist:Update()
    A.dirty=true
    return true
end

function N:ClearManual(replan)
    if not self.manual then return end
    self.manual = nil
    self:RefreshPins()
    A.QuestAssist:Update()
    if replan~=false then A:Replan() end
    A.dirty = true
end

function N:Current()
    local flight=A.Transport and A.Transport:FlightGate()
    if flight then return flight end
    local hearth=A.Hearth and A.Hearth:Gate()
    if hearth then return hearth end
    if self.manual then
        local goal=self.manual.action
        if goal and N.StaleAction(goal,A.state,self.manual.plan or {revision=-1}) then
            self:ClearManual(false)
        else
            if goal and (self.manual.inInstance~=A.state.inInstance or A.state.inInstance and self.manual.instanceId~=A.state.instanceId) then
                if self:Navigate(goal) then return self:Current() end
            end
            local action=self.manual.actions and self.manual.actions[self.manual.index] or goal
            if not N.StaleAction(action,A.state,self.manual.plan) then
                return action or {kind="manual",title=self.manual.title or "手动目的地",position=self.manual}
            end
            self:ClearManual(false)
        end
    end
    local action=self.actions and self.actions[self.index]
    if not N.StaleAction(action) then return action end
end

function N:Near(position,target,radius)
    if not position or not target or position.map~=target.map then return false end
    local distance=self:Distance(position,target)
    return distance~=nil and distance<=(radius or 12)
end

function N.Target(action)
    if action and action.kind=="accept" and action.position and action.position.startItemId then return end
    return action and ((action.kind=="transit" and (action.mode=="flight" or action.publicTransit and not action.atDeparture) and action.departure) or action.position)
end

function N:BeginFlight(origin)
    local sequence=self:Sequence()
    for i=sequence.index,#(sequence.actions or {}) do
        local action=sequence.actions[i]
        if action.kind=="transit" and action.mode=="flight" then
            if self:Near(origin,action.departure,action.departureRadius) then
                sequence.index=i
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
    local sequence=self:Sequence()
    if action and sequence.actions and sequence.actions[sequence.index]==action and not A.char.paused and
        arrived then
        self:Advance()
        return true
    end
    if action and not arrived and A.Message then
        A:Message("已在其他飞行点落地，按实际位置重新规划。")
    end
    return false
end

function N:MapPoints()
    if A.settings.mapTaskScope=="off" then return {} end
    local points,seen,routeCount={},{},0
    local current=self:Current()
    local sequence=self:Sequence()
    local function add(action,required,catalog)
        if N.StaleAction(action,A.state,sequence.plan) then return end
        local pos=N.Target(action)
        if not pos then return end
        local key=table.concat({pos.map,pos.x,pos.y},":")
        local point=seen[key]
        if not point then
            if routeCount>=6 and not required then return end
            point={position=pos,action=action,actions={},seen={}}
            points[#points+1]=point;seen[key]=point
        end
        if not catalog and not point.order then routeCount=routeCount+1;point.order=routeCount end
        if action==current then point.current=true end
        local identity=table.concat({action.kind or "",action.questId or "",action.objectiveIndex or action.targetId or ""},":")
        if not point.seen[identity] then
            point.actions[#point.actions+1]=action;point.seen[identity]=#point.actions
        elseif action.targetKind then
            local previous=point.actions[point.seen[identity]]
            point.actions[point.seen[identity]]=action
            if point.action==previous then point.action=action end
        end
        if catalog and not point.current and not point.available then point.action=action end
        point.available=point.available or catalog
    end
    add(current)
    if self.manual then
        for i=(self.manual.index or 1)+1,#(self.manual.actions or {}) do add(self.manual.actions[i]) end
    else
        local batch=self.plan and self.plan.taskBatch and A.Dungeon.TaskBatchFrontier(self.plan)
        for _,step in ipairs(batch or {}) do add(step.action,true,true) end
        for i=self.index+1,#(self.actions or {}) do add(self.actions[i]) end
        local queue=self.plan and self.plan.taskQueue
        for _,step in ipairs(queue and queue.steps or {}) do
            if step.stage then add(step.stage)
            else for _,stage in ipairs(step.choice.stages or {}) do add(stage) end end
        end
        if not queue then
            local goal=self.actions and self.actions[#self.actions]
            for _,choice in ipairs(self.plan and self.plan.taskChoices or {}) do
                if goal and choice.questId==goal.questId then
                    for _,stage in ipairs(choice.stages or {}) do add(stage) end
                    break
                end
            end
        end
    end
    if A.settings.mapTaskScope=="route" then return points end
    -- Reuse resolved candidates; map coverage must not depend on the six-stop route preview.
    for _,choice in ipairs(self.plan and self.plan.taskChoices or {}) do
        local id=choice.questId
        local active=(A.state.quests or {})[id]
        if not choice.lowValue and not choice.acceptBlocked and not choice.requireCheck and not choice.entryBlocked and
            not (A.state.completed or {})[id] and not (A.state.skipped or {})[id] and not (A.state.chainDeferred or {})[id] then
            if not active then
                local pickup=choice.pickupAction or not choice.revisitLevel and choice.actions and choice.actions[1]
                if pickup and pickup.kind=="accept" then add(pickup,true,true) end
            elseif not choice.revisitLevel then
                local kind=active.ready and "turnin" or "objective"
                for _,stage in ipairs(choice.stages or choice.actions or {}) do
                    local objective=stage.objectiveIndex and (active.objectives or {})[stage.objectiveIndex]
                    if stage.kind==kind and not (objective and objective.finished) then add(stage,true,true) end
                end
            end
        end
    end
    return points
end

local function mapPin()
    local pin=CreateFrame("Button",nil,UIParent)
    pin.texture=pin:CreateTexture(nil,"OVERLAY");pin.texture:SetAllPoints()
    pin.number=pin:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    pin.number:SetPoint("TOP",pin,"BOTTOM",0,1)
    pin.number:SetTextColor(1,1,1);pin.number:SetShadowOffset(1,-1)
    pin:Hide();pin:EnableMouse(true)
    pin:RegisterForClicks("LeftButtonUp","RightButtonUp")
    pin:SetScript("OnClick",function(f,button)
        GameTooltip:Hide()
        local action=f.point.action
        if button=="RightButton" then
            if N.manual then N:ClearManual() end
        elseif IsModifiedClick and IsModifiedClick("CHATLINK") and action.questId then
            A.UI:QuestClick(action.questId,button)
        elseif not N:Navigate(action) and action.questId then
            if not N:NavigateQuest(action.questId) then A.UI:QuestClick(action.questId,button) end
        end
    end)
    pin:SetScript("OnEnter",function(f)
        local point=f.point
        GameTooltip:SetOwner(f,"ANCHOR_RIGHT")
        GameTooltip:SetText((point.current and "当前目的地 · " or point.order and string.format("%02d · ",point.order) or "")..
            (point.action.title or "AILeveling")..(point.position.approximate and " · 区域参考点" or ""))
        for _,action in ipairs(point.actions) do
            local active=(A.state.quests or {})[action.questId]
            local label=action.kind=="accept" and "接取任务" or action.kind=="turnin" and (active and active.ready and "交付任务" or "完成后交付") or
                action.kind=="objective" and (not active and "接取后目标" or action.targetKind=="item" and "收集目标" or "任务目标") or "前往"
            local detail=action.kind=="objective" and action.text
            GameTooltip:AddLine(label.." · "..(action.title or "目的地")..(detail and ("\n"..detail) or ""),1,1,1,true)
        end
        GameTooltip:AddLine("左键：导航到此处"..(N.manual and "\n右键：返回原行程" or ""),1,0.83,0.45,true)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave",function() GameTooltip:Hide() end)
    return pin
end

local function actionAtlas(action)
    return ({accept="QuestNormal",turnin="UI-QuestPoi-QuestBangTurnIn",dungeonEnter="Dungeon"})[action.kind]
        or (action.kind=="transit" and action.mode=="flight" and "FlightPath") or "Waypoint-MapPin-Tracked"
end

function N:SyncWaypointUI(force)
    self.externalWaypoint=nil
    local api=WaypointUIAPI and WaypointUIAPI.Navigation
    if not (api and api.GetUserNavigation and api.NewUserNavigation and api.ClearUserNavigation) then return end
    local nav=api.GetUserNavigation()
    local owned=nav and nav.flags=="AiLeveling"
    local enabled=A.settings.waypointUI~=false
    local tracked=api.IsUserNavigationTracked() or api.IsPathStepWaypointTracked()
    local rawPin=not tracked and C_SuperTrack and C_SuperTrack.GetHighestPrioritySuperTrackingType and Enum and Enum.SuperTrackingType and
        C_SuperTrack.GetHighestPrioritySuperTrackingType()==Enum.SuperTrackingType.UserWaypoint
    if not force and (nav and not owned and tracked or rawPin) then
        self.externalWaypoint=enabled
        return
    end
    local action=self:Current()
    local target=action and N.Target(action)
    if not enabled or A.char.paused or action and (action.kind=="flight" or action.kind=="hearth" or action.publicTransit and action.atDeparture) then target=nil end
    if not target then
        if owned and tracked then api.ClearUserNavigation(false,true) end
        return
    end
    local q=action.questId and ((A.state.quests or {})[action.questId] or A.Data and A.Data:GetQuest(action.questId))
    local label=action.title or q and q.title or target.entityName or action.text or "任务目的地"
    local atlas=actionAtlas(action)
    if owned and nav.mapID==target.map and math.abs(nav.x-target.x)<0.000001 and math.abs(nav.y-target.y)<0.000001 and
        nav.name==label and nav.iconTexture==atlas then return end
    api.NewUserNavigation({mapID=target.map,x=target.x*100,y=target.y*100,name=label,flags="AiLeveling",
        iconTexture=atlas,iconType="ATLAS",stripCoordinates=true,suppressAudio=true})
end

function N:RefreshPins(force)
    self:SyncWaypointUI(force)
    if not self.hbdPins then return end
    self.hbdPins:RemoveAllWorldMapIcons(self)
    self.hbdPins:RemoveAllMinimapIcons(self)
    for _, pin in ipairs(self.pins) do pin:Hide() end
    if (not A.settings.pins and not A.settings.minimapPins) or A.char.paused then return end
    for order,point in ipairs(self:MapPoints()) do
        local action,pos=point.action,point.position
        local atlas=actionAtlas(action)
        -- HBD-Pins requires separate frames for minimap/world map ownership.
        for surface=1,2 do
            local index=(order-1)*2+surface
            local pin=self.pins[index] or mapPin();self.pins[index]=pin
            pin.point,pin.order=point,order
            local size=(surface==1 and 24 or 18)+(point.current and 4 or 0)
            pin:SetSize(size,size)
            pin:SetAlpha(1)
            pin.number:SetText(point.order and string.format("%02d",point.order) or #point.actions>1 and tostring(#point.actions) or "")
            if action.kind=="objective" then
                pin.texture:SetTexture("Interface\\AddOns\\AiLeveling\\Media\\hud-"..
                    (action.targetKind=="item" and "collect" or "objective")..".tga")
            else pin.texture:SetAtlas(atlas,false) end
            local color=action.kind=="objective" and (action.targetKind=="item" and {0.78,0.68,1} or {0.58,0.79,1}) or {1,1,1}
            pin.texture:SetVertexColor(unpack(color))
            if surface==1 and A.settings.pins then self.hbdPins:AddWorldMapIconMap(self,pin,pos.map,pos.x,pos.y,1)
            elseif surface==2 and A.settings.minimapPins then self.hbdPins:AddMinimapIconMap(self,pin,pos.map,pos.x,pos.y,false,point.current or false) end
        end
    end
end

function N:Update()
    self:SyncWaypointUI()
    if self.externalWaypoint then A.UI:SetNavigation(nil);return end
    if not self.hbd then return end
    if A.Transport and A.Transport:InFlight() then A.UI:SetNavigation(nil);return end
    if A.Hearth and A.Hearth:InTransit() then A.UI:SetNavigation(nil);return end
    local action, pos = self:Current(), A.state.position
    if action and action.publicTransit and not A.char.paused and pos then
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
        local expectedTransit = action and action.kind == "transit" and action.position and action.position.map == pos.map
        if not publicTravel and not self.manual and not A.char.paused and (changedMap and not expectedTransit) and
            (not self.replanAt or GetTime() >= self.replanAt) then
            self.replanAt = GetTime() + 2
            A:Replan()
        end
        self.lastMap = pos.map
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
    if action.kind=="manual" and not A.state.dead and pos.map==target.map and distance and distance<=(action.arrival or 12) then
        self:ClearManual()
        return
    end
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
