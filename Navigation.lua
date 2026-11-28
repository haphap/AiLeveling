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
    if not (action and action.questId and state) then return end
    action=action.questAction or action
    if (state.skipped or {})[action.questId] or (state.chainDeferred or {})[action.questId] then return true end
    if plan and (action.kind=="transit" or action.kind=="move" or action.kind=="approach") then
        local actions=plan.best and plan.best.actions or plan.travelActions
        local goal=actions and actions[#actions]
        if goal and goal.questId==action.questId then action=goal end
    end
    local active=(state.quests or {})[action.questId]
    if action.kind=="turnin" and A.State and A.State.confirmed and A.State.confirmed[action.questId] then return true end
    if action.kind=="accept" then
        local loot=action.position and action.position.pickupLoot
        if loot and ((state.bags or {})[loot.id] or 0)>=loot.count then return true end
    end
    if not active and action.expected and action.kind=="objective" and action.targetKind=="item" and action.need and action.need>0 and
        not (action.itemGain and action.itemGain>0) and ((state.bags or {})[action.targetId] or 0)>=action.need then return true end
    if not (plan and plan.revision and plan.revision~=state.revision) then return end
    if not active then
        if (state.completed or {})[action.questId] then return true end
        if (action.kind=="objective" or action.kind=="turnin") and not action.expected then return true end
    end
    if action.kind=="accept" then
        local item=action.startItemId or action.position and action.position.startItemId
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

function N:Distance(from, to, onFoot)
    if not from or not to or not self.hbd then return nil end
    if onFoot and A.Travel.Separated(from,to,self) then return end
    return self.hbd:GetZoneDistance(from.map, from.x, from.y, to.map, to.x, to.y)
end

function N:SetPlan(plan)
    local sameFocus=not self.plan or self.plan.routeFocus==plan.routeFocus
    self.plan=plan
    self.planInstance=A.state.inInstance and A.state.instanceId
    self.upcomingQuest=nil
    local current=self.actions and self.actions[self.index]
    local goal=self.actions and self.actions[#self.actions]
    local nextActions=plan.best and plan.best.actions or plan.travelActions or (plan.fallback and {plan.fallback}) or {}
    local nextGoal=nextActions[#nextActions]
    local before,after=goal and goal.position,nextGoal and nextGoal.position
    -- Replanning at sea must not send the same task back to its departure dock.
    if sameFocus and current and current.publicTransit and current.atDeparture and goal and nextGoal and
        goal.questId==nextGoal.questId and goal.kind==nextGoal.kind and goal.objectiveIndex==nextGoal.objectiveIndex and
        before and after and before.map==after.map and before.x==after.x and before.y==after.y and not A.state.dead and not self.manual then
        self:RefreshPins();A.QuestAssist:Update();return
    end
    self.index = 1
    self.actions = nextActions
    self.transitDeparted = nil
    self:RefreshPins()
    A.QuestAssist:Update()
end

function N:Advance()
    local sequence=self:Sequence()
    self.upcomingQuest=nil
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
        if choice.questId==id and not choice.acceptBlocked and
            not choice.requireCheck and not choice.entryBlocked then
            return self:Navigate(choice.pickupAction or not choice.revisitLevel and choice.actions and choice.actions[1])
        end
    end
    return false
end

function N:Navigate(action,keepWaypoint)
    local state=A.state
    local clicked=action
    action=action and (action.questAction or action)
    local id=action and action.questId
    local point=action and action.position
    local active=id and (state.quests or {})[id]
    if not action or (id and ((state.completed or {})[id] or (state.skipped or {})[id] or (state.chainDeferred or {})[id])) or
        state.dead or state.onTaxi or A.char.paused then return false end
    if id and (action.kind=="accept" and (active or N.StaleAction(action,state,self.plan)) or action.kind=="objective" and (not active or active.ready or
        action.objectiveIndex and (active.objectives or {})[action.objectiveIndex] and active.objectives[action.objectiveIndex].finished) or
        action.kind=="turnin" and (not active or not active.ready)) then return false end
    if clicked.kind=="transit" and clicked==self:Current() then
        self:RefreshPins(true)
        return true
    end
    local target=action
    if action.kind~="accept" and action.kind~="objective" and action.kind~="turnin" then
        target={kind="manual",title=action.title,position=N.Target(action)}
    end
    local approach=A.Dungeon and A.Dungeon.TaskApproach and A.Dungeon.TaskApproach(target,state,A.Data) or target
    if not approach.position and not (id and approach.text) then return false end
    if A.ShortestPath then A.ShortestPath:Sync(approach) end
    local external=A.ShortestPath and A.ShortestPath:For(approach)
    local routes=not external and not (point and point.startItemId) and approach.position and A.Flights and A.Flights.Itinerary(state.position,{approach},state,self)
    local actions=routes and routes[1] and A.Flights.Actions(routes[1],approach,self)
    if not actions then actions={not external and A.Flights and A.Flights.MissingCrossing and A.Flights.MissingCrossing(approach,state,self) or approach} end
    self.manual={title=action.title,action=target,actions=actions,index=1,externalRoute=external~=nil,
        instanceId=state.instanceId,inInstance=state.inInstance,plan={revision=-1,travelActions=actions,itemStock=self.plan and self.plan.itemStock}}
    self.upcomingQuest=nil
    self:RefreshPins(not keepWaypoint)
    self:Update()
    A.QuestAssist:Update()
    A.dirty=true
    return true
end

local function clearMapArea()
    if not N.mapAreaAction then return end
    N.mapAreaAction=nil
    -- Restore the native details panel's focus if it was open behind this preview.
    local detail=QuestMapFrame_GetDetailQuestID and QuestMapFrame_GetDetailQuestID()
    if detail then WorldMapFrame:SetFocusedQuestID(detail) else WorldMapFrame:ClearFocusedQuestID() end
end

function N:ClearManual(replan)
    clearMapArea()
    if not self.manual then return end
    self.manual,self.upcomingQuest=nil,nil
    self:RefreshPins()
    A.QuestAssist:Update()
    if replan~=false then A:Replan() end
    A.dirty = true
end

local function leveling(state)
    return not (state.locked or state.regionTarget or state.preparingQuest or state.taskBatch or state.gearTarget or state.serviceStop or
        state.inInstance or state.dead or state.onTaxi)
end

-- A numbered itinerary belongs to the selected activity and the zone where it was planned.
function N:RouteStatus(plan,state)
    if (self.planInstance or nil)~=(state.inInstance and state.instanceId or nil) or
        plan and plan.routeFocus~=state.routeFocus then return "replaced" end
    if not (state.position and plan and plan.origin and plan.origin.map~=state.position.map) then return end
    local step=self.actions and self.actions[self.index]
    if leveling(state) and not (step and step.publicTransit and step.atDeparture) then return "moved" end
end

local function regionChoices(plan,map)
    for _,region in ipairs(plan and plan.regions or {}) do
        if region.map==map then return region.choices end
    end
end

function N:TrackerPlan(plan,state)
    local status=self:RouteStatus(plan,state)
    if status=="moved" then
        return {revision=plan.revision,taskChoices=regionChoices(plan,state.position.map),itemStock=plan.itemStock}
    end
    if status=="replaced" then return {} end
    return plan or {}
end

function N:LocalAction()
    if A.Transport and A.Transport.tram and not A.state.dead then return A.Transport.tram end
    local flight=A.Transport and A.Transport:FlightGate()
    if flight then return flight end
    local hearth=A.Hearth and A.Hearth:Gate()
    if hearth then return hearth end
    if self.manual then
        local goal=self.manual.action
        if goal and N.StaleAction(goal,A.state,self.manual.plan or {revision=-1}) then
            self:ClearManual(false)
        else
            local action=self.manual.actions and self.manual.actions[self.manual.index] or goal
            local crossing=action and action.crossingFrom
            if goal and (self.manual.inInstance~=A.state.inInstance or A.state.inInstance and self.manual.instanceId~=A.state.instanceId or
                action and action.kind=="transit" and action.mode=="flight" and N.StaleAction(action,A.state,self.manual.plan) or
                crossing and A.state.position and (crossing.map~=A.state.position.map or A.Travel.Separated(crossing,A.state.position,self))) then
                if self:Navigate(goal,true) then return self:Current() end
                return
            end
            if not N.StaleAction(action,A.state,self.manual.plan) then
                return action or {kind="manual",title=self.manual.title or "手动目的地",position=self.manual}
            end
            self:ClearManual(false)
        end
    end
    local state=A.state
    local plan=A.plan
    local status=self:RouteStatus(plan,state)
    local action=self.actions and self.actions[self.index]
    if status=="replaced" then plan,action=nil,nil
    elseif N.StaleAction(action) then action=nil end
    local position=state.position
    local changedZone=status=="moved"
    if not status and A.indexReady and not (A.jobs and A.jobs.plan) then return action end
    local automatic=leveling(state) and (state.level or 0)<60 and not A.error and not A.char.paused
    local arrivedQuest
    -- Drop the old itinerary while the new plan waits for the player to stop.
    if changedZone and action then
        local stop=N.Target(action)
        if stop and stop.map==position.map and (action.kind=="accept" or action.kind=="objective" or action.kind=="turnin") then
            arrivedQuest=action
        end
        action=nil
    end
    if action and action.kind~="taskReview" then return action end
    if position and automatic and A.TaskGuide and A.Data and A.Data.Target then
        local nearest,best
        for id,step in pairs(A.TaskGuide.ReadyTurnIns(state,A.Data)) do
            if step.position.map==position.map then
                local distance=self:Distance(position,step.position,true)
                if distance and (not best or distance<best or distance==best and id<nearest.questId) then
                    nearest,best=step,distance
                end
            end
        end
        if nearest then return nearest end
        local choices=plan and plan.taskOrder
        if changedZone then choices=regionChoices(plan,position.map) or choices end
        for _,choice in ipairs(choices or {}) do
            local quest=state.quests[choice.questId]
            local step=choice.executionAction or (choice.actions or {})[1]
            if step and step.position and step.position.map==position.map and
                not (step.expected or step.position.areaOnly or choice.itemShortage or choice.entryBlocked or
                choice.lowValue or choice.revisitLevel or N.StaleAction(step,state,plan)) then
                if quest and not quest.ready and step.kind=="objective" then return step end
                if changedZone and not quest and step.kind=="accept" and not (choice.requireCheck or choice.acceptBlocked or
                    A.Supplies and A.Supplies.AcceptIssue(state)) then return step end
            end
        end
    end
    return action or arrivedQuest
end

function N:Current()
    local action=self:LocalAction()
    return A.ShortestPath and A.ShortestPath:For(action) or action
end

function N:Near(position,target,radius)
    if not position or not target or position.map~=target.map then return false end
    local distance=self:Distance(position,target)
    return distance~=nil and distance<=(radius or 12)
end

function N.Target(action)
    if action and action.kind=="accept" and action.position and action.position.startItemId then return end
    local point=action and ((action.kind=="transit" and (action.mode=="flight" or action.publicTransit and not action.atDeparture) and action.departure) or action.position)
    if point and not point.areaOnly then return point end
end

function N:BeginFlight(origin)
    if A.ShortestPath and A.ShortestPath.owned then return end
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

function N:SetUpcomingQuest(action)
    local old=self.upcomingQuest
    self.upcomingManual=self.manual
    self.upcomingQuest=action
    if old==action then return end
    local before,after=N.Target(old),N.Target(action)
    if before and after and before.map==after.map and before.x==after.x and before.y==after.y and
        old.kind==action.kind and old.questId==action.questId and old.objectiveIndex==action.objectiveIndex then return end
    self:DrawPins()
end

function N:MapPoints()
    if A.settings.mapTaskScope=="off" then return {} end
    local points,seen,turnins,recipients,routeCount={},{},{},{},0
    local current=self:Current()
    local sequence=self:Sequence()
    local status=self:RouteStatus(self.plan,A.state)
    local upcoming=self.upcomingManual==self.manual and (self.manual or not status) and self.upcomingQuest or nil
    local function add(action,required,catalog,lowOffer)
        if action and A.ShortestPath and A.ShortestPath:For(action) and action~=current then return end
        if N.StaleAction(action,A.state,sequence.plan) then return end
        local pos=N.Target(action)
        if not pos then return end
        local key=table.concat({pos.map,pos.x,pos.y},":")
        local point=seen[key]
        local contacts,knownContact
        if action.kind=="turnin" and pos.entityKind and pos.entityId then
            local recipient=table.concat({pos.map,pos.entityKind,pos.entityId},":")
            contacts=recipients[recipient] or {}
            recipients[recipient]=contacts
            for _,contact in ipairs(contacts) do
                if point==contact or not point and self:Near(contact.position,pos) then
                    point,knownContact=contact,true;break
                end
            end
        end
        if not point then
            if routeCount>=6 and not required then return end
            point={position=pos,action=action,actions={},seen={},lowOnly=lowOffer}
            points[#points+1]=point
        elseif point.lowOnly and not lowOffer then
            point.lowOnly,point.action=nil,action
        end
        if lowOffer then
            point.lowOffers=point.lowOffers or {}
            point.lowOffers[action.questId]=true
        end
        if contacts and not knownContact then contacts[#contacts+1]=point end
        seen[key]=point
        if not catalog and not point.order and routeCount<6 then
            routeCount=routeCount+1
            point.order,point.action=routeCount,action
        end
        if action==current then point.current=true end
        if action==upcoming then point.upcoming=true end
        if action.kind=="turnin" and action.questId then turnins[action.questId]=true end
        local identity=table.concat({action.kind or "",action.questId or "",action.objectiveIndex or action.targetId or ""},":")
        if not point.seen[identity] then
            point.actions[#point.actions+1]=action;point.seen[identity]=#point.actions
        elseif action.targetKind then
            local previous=point.actions[point.seen[identity]]
            point.actions[point.seen[identity]]=action
            if point.action==previous then point.action=action end
        end
    end
    add(current)
    if self.manual then
        if current then
            for i=(self.manual.index or 1)+1,#(self.manual.actions or {}) do add(self.manual.actions[i]) end
        end
    elseif not status then
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
    -- The next quest stays visible even when the journey to it has six transport stops.
    add(upcoming,true,true)
    if A.settings.mapTaskScope=="route" then return points end
    -- Reuse resolved candidates; map coverage must not depend on the six-stop route preview.
    local choices=status~="replaced" and self.plan and self.plan.taskChoices
    local trackLow=not (C_Minimap and C_Minimap.IsTrackingHiddenQuests) or C_Minimap.IsTrackingHiddenQuests()
    local range=UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player") or
        C_QuestLog and C_QuestLog.GetTrivialRange and C_QuestLog.GetTrivialRange()
    local cutoff=range and A.state.level and A.state.level-range
    for _,choice in ipairs(choices or {}) do
        local id=choice.questId
        local active=(A.state.quests or {})[id]
        if not choice.lowValue and not choice.acceptBlocked and not choice.requireCheck and not choice.entryBlocked and
            not (A.state.completed or {})[id] and not (A.state.skipped or {})[id] and not (A.state.chainDeferred or {})[id] then
            if not active then
                local pickup=choice.pickupAction or not choice.revisitLevel and choice.actions and choice.actions[1]
                if pickup and pickup.kind=="accept" then
                    local low=C_QuestLog and C_QuestLog.IsQuestTrivial and C_QuestLog.IsQuestTrivial(id)
                    if not low and cutoff and choice.level and choice.level>0 and choice.level<cutoff then
                        -- Off-log offers can lack client data. Prefer a live scaled level when available.
                        local live=C_QuestLog and C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(id)
                        low=not live or live<=0 or live<cutoff
                    end
                    if trackLow or not low then add(pickup,true,true,low) end
                end
            elseif not choice.revisitLevel then
                local kind=active.ready and "turnin" or "objective"
                for _,stage in ipairs(choice.stages or choice.actions or {}) do
                    local objective=stage.objectiveIndex and (active.objectives or {})[stage.objectiveIndex]
                    if stage.kind==kind and not (objective and objective.finished) then add(stage,true,true) end
                end
            end
        end
    end
    if A.indexReady and A.TaskGuide and A.Data and A.Data.Target then
        for id,step in pairs(A.TaskGuide.ReadyTurnIns(A.state,A.Data)) do
            local active=A.state.quests[id]
            if not turnins[id] and active and active.ready then add(step,true,true) end
        end
    end
    return points
end

local media="Interface\\AddOns\\AiLeveling\\Media\\"
local function cell(texture,index)
    texture:SetTexture(media.."map-markers.tga")
    texture:SetTexCoord(index/2,(index+1)/2,0,1)
end

local function taxiMarker(parent)
    local mark=CreateFrame("Frame",nil,parent)
    mark:EnableMouse(false);mark:SetSize(34,34)
    local ring=mark:CreateTexture(nil,"OVERLAY");cell(ring,1);ring:SetAllPoints()
    local arrow=mark:CreateTexture(nil,"OVERLAY");arrow:SetSize(21,21)
    arrow:SetTexture(media.."hud-chevron-up.tga");arrow:SetRotation(math.pi)
    arrow:SetPoint("BOTTOM",mark,"TOP",0,-3)
    local label=mark:CreateFontString(nil,"OVERLAY","GameFontNormal")
    label:SetPoint("BOTTOM",arrow,"TOP",0,2);label:SetShadowColor(0,0,0,1);label:SetShadowOffset(1,-1)
    local wave=mark:CreateTexture(nil,"ARTWORK");cell(wave,1);wave:SetAllPoints()
    local pulse=wave:CreateAnimationGroup();pulse:SetLooping("REPEAT")
    local grow=pulse:CreateAnimation("Scale")
    if grow.SetScaleFrom then grow:SetScaleFrom(1,1);grow:SetScaleTo(1.5,1.5) else grow:SetScale(1.5,1.5) end
    grow:SetDuration(1.6)
    local fade=pulse:CreateAnimation("Alpha");fade:SetFromAlpha(0.85);fade:SetToAlpha(0);fade:SetDuration(1.6)
    local bob=arrow:CreateAnimationGroup();bob:SetLooping("BOUNCE")
    local move=bob:CreateAnimation("Translation");move:SetOffset(0,4);move:SetDuration(0.75);move:SetSmoothing("IN_OUT")
    mark:SetScript("OnHide",function() pulse:Stop();bob:Stop() end)
    mark.label,mark.arrow,mark.ring,mark.wave,mark.pulse,mark.bob=label,arrow,ring,wave,pulse,bob
    return mark
end

-- Map opening, building the buttons and producing a route can finish in any order.
function N.TaxiMapDrawn()
    if not A.Transport.taxiMapOpen then return end
    local choices=A.Transport.taxiChoices
    local flight=A.Transport:PlannedFlight()
    local hadOffers=choices and next(choices.slots)
    if not hadOffers or flight and flight.fromTaxi==choices.from and not A.Transport:TaxiDestination() then
        A.Transport:CaptureTaxi(true)
        if A.Transport:TaxiDestination() or not hadOffers and A.Transport.taxiChoices and next(A.Transport.taxiChoices.slots) then
            A:RequestRefresh()
        end
    end
    N:RefreshTaxiMarker()
end

function N:RefreshTaxiMarker()
    if A.Transport.taxiMapOpen then
        if TaxiFrame and self.hookedTaxiFrame~=TaxiFrame then
            TaxiFrame:HookScript("OnShow",N.TaxiMapDrawn)
            self.hookedTaxiFrame=TaxiFrame
        end
        if FlightMapFrame and self.hookedFlightMap~=FlightMapFrame then
            hooksecurefunc(FlightMapFrame,"RefreshAllDataProviders",N.TaxiMapDrawn)
            self.hookedFlightMap=FlightMapFrame
        end
    end
    local slot,node=A.Transport:TaxiDestination()
    local pin
    if slot and TaxiFrame and TaxiFrame:IsShown() then
        local button=_G["TaxiButton"..slot]
        if button and button:GetID()==slot and button:IsShown() and TaxiNodeGetType(slot)=="REACHABLE" then pin=button end
    elseif slot and FlightMapFrame and FlightMapFrame:IsShown() then
        for button in FlightMapFrame:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
            local data=button.taxiNodeData
            if data and data.nodeID==node.id and data.state==1 and not data.isMapLayerTransition and button:IsShown() then pin=button;break end
        end
    end
    local mark=self.taxiMarker
    if not pin then if mark then mark:Hide() end;return end
    if not mark then mark=taxiMarker(pin);self.taxiMarker=mark end
    if mark:GetParent()~=pin then mark:SetParent(pin) end
    mark:ClearAllPoints();mark:SetPoint("CENTER",pin,"CENTER")
    mark:SetFrameLevel(pin:GetFrameLevel()+2)
    local name=node.name or (TaxiNodeName and TaxiNodeName(slot))
    mark.label:SetText(name and ("下一步 · "..name) or "下一步")
    local r,g,b=A.UI:Accent()
    mark.ring:SetVertexColor(r,g,b);mark.wave:SetVertexColor(r,g,b);mark.arrow:SetVertexColor(r,g,b)
    mark:Show()
    A.Transport:PreviewTaxi(slot,node,mark)
    local reduce=C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("cameraReduceUnexpectedMovement")
    mark.wave:SetShown(not reduce)
    if reduce then mark.pulse:Stop();mark.bob:Stop()
    else
        if not mark.pulse:IsPlaying() then mark.pulse:Play() end
        if not mark.bob:IsPlaying() then mark.bob:Play() end
    end
end

local function availableAction(action)
    local active=A.state.quests[action.questId]
    if action.kind=="accept" then return not active and not action.expected end
    if action.kind=="turnin" then return active and active.ready end
    if action.kind=="objective" and active and not active.ready then
        local objective=active.objectives and active.objectives[action.objectiveIndex]
        return not (objective and objective.finished)
    end
end

local function isAreaTarget(action)
    return action.kind=="objective" and availableAction(action)
end

local function showMapArea(action,point)
    if not isAreaTarget(action) then return end
    local map=WorldMapFrame
    if not map or not map:IsShown() or map:GetMapID()~=point.map then
        local open=OpenWorldMap or C_Map and C_Map.OpenWorldMap
        if open then open(point.map) end
        map=WorldMapFrame
    end
    if not (map and map:IsShown() and map:GetMapID()==point.map and map.SetFocusedQuestID and map.ClearFocusedQuestID) then return end
    if not N.mapAreaHooks then
        map:HookScript("OnHide",clearMapArea)
        -- A subsequent native selection owns the highlight from then on.
        local function nativeSelection() N.mapAreaAction=nil end
        map:RegisterCallback("SetFocusedQuestID",nativeSelection,N)
        map:RegisterCallback("ClearFocusedQuestID",nativeSelection,N)
        if EventRegistry then
            EventRegistry:RegisterFrameEventAndCallback("SUPER_TRACKING_CHANGED",function()
                if not N.mapAreaAction or C_SuperTrack.GetHighestPrioritySuperTrackingType()~=Enum.SuperTrackingType.Quest then return end
                local id=C_SuperTrack.GetSuperTrackedQuestID()
                if id and id>0 and id~=N.mapAreaAction.questId then clearMapArea() end
            end,N)
        end
        N.mapAreaHooks=true
    end
    map:SetFocusedQuestID(action.questId)
    N.mapAreaAction=action
    return true
end

local function showPinTip(pin)
    local point,primary=pin.point,pin.action
    local quest=(primary.kind=="accept" or primary.kind=="objective" or primary.kind=="turnin") and A.state.quests[primary.questId]
    local title=quest and quest.title or primary.title or "目的地"
    GameTooltip:SetOwner(pin,"ANCHOR_RIGHT")
    GameTooltip:SetText((point.current and "当前目标 · " or point.upcoming and "接下来 · " or "")..title)
    for _,action in ipairs(point.actions) do
        if not pin.mini or action==primary or availableAction(action) then
            local active=A.state.quests[action.questId]
            local label=action.kind=="accept" and (action.position and action.position.pickupLoot and "拾取任务物品" or "接取任务") or action.kind=="turnin" and
                (active and active.ready and "交付任务" or "完成后交付") or action.kind=="objective" and
                (not active and "接取后目标" or action.targetKind=="item" and "收集目标" or "任务目标") or "前往"
            if action.kind=="accept" and point.lowOffers and point.lowOffers[action.questId] then label=label.."（低等级）" end
            local objective=active and active.objectives and active.objectives[action.objectiveIndex]
            local detail=action.kind=="objective" and (objective and objective.text or action.text)
            if detail and objective and objective.numRequired and objective.numRequired>0 then
                detail=detail:gsub("%s*%d+%s*/%s*%d+",""):match("^%s*(.-)%s*$"):gsub("：$",""):gsub(":$","")
                detail=detail.."  "..(objective.numFulfilled or 0).."/"..objective.numRequired
            end
            if action~=primary then label=label.." · "..(active and active.title or action.title or "任务") end
            if detail then
                label=action==primary and active and detail or label.."\n"..detail
            end
            GameTooltip:AddLine(label,1,1,1,true)
        end
    end
    local pos=N.Target(primary) or point.position
    local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(pos.map)
    local area=pos.sourceAreaId and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(pos.sourceAreaId) or info and info.name
    local place=pos.siteName or pos.entityName or area
    if place then
        if area and area~=place then place=place.." · "..area end
        if pos.approximate then place=place.." · "..(pos.sourceKind=="patrol" and "巡逻路线" or "区域参考点") end
        if pos.spawnArea then place=place.." · 出没区域" end
        if pos.sourceKind=="escortStart" then place=place.." · 护送起点" end
        GameTooltip:AddLine(place,0.8,0.8,0.82,true)
    end
    if pos.travelHint then GameTooltip:AddLine(pos.travelHint,1,1,1,true) end
    GameTooltip:AddLine((isAreaTarget(primary) and "左键查看任务范围并导航" or "左键导航")..(N.manual and "  ·  右键返回原行程" or ""),0.9,0.77,0.57)
    GameTooltip:Show()
end

local function mapPin(mini)
    local pin=CreateFrame("Button",nil,UIParent)
    pin.mini=mini
    pin.face=pin:CreateTexture(nil,"BACKGROUND")
    cell(pin.face,0);pin.face:SetAllPoints();pin.face:SetVertexColor(0.09,0.09,0.12)
    pin.ring=pin:CreateTexture(nil,"BORDER")
    cell(pin.ring,1);pin.ring:SetPoint("CENTER")
    pin.texture=pin:CreateTexture(nil,"ARTWORK");pin.texture:SetPoint("CENTER")
    pin:Hide();pin:EnableMouse(true)
    pin:RegisterForClicks("LeftButtonUp","RightButtonUp")
    pin:SetScript("OnClick",function(f,button)
        GameTooltip:Hide()
        local action=f.action
        if button=="RightButton" then
            N:ClearManual()
        elseif IsModifiedClick and IsModifiedClick("CHATLINK") and action.questId then
            A.UI:QuestClick(action.questId,button)
        else
            -- Navigating can recycle this pin. Keep the coordinates actually clicked.
            local point=f.point.position
            clearMapArea()
            local routed=N:Navigate(action)
            if not showMapArea(action,point) and not routed and action.questId then
                if not N:NavigateQuest(action.questId) then A.UI:QuestClick(action.questId,button) end
            end
        end
    end)
    pin:SetScript("OnEnter",showPinTip)
    pin:SetScript("OnLeave",function() GameTooltip:Hide() end)
    return pin
end

local function actionTexture(action)
    local quest=(A.state.quests or {})[action.questId]
    local icon=A.UI.QuestIcon(action.kind,action,quest and quest.objectives)
    return A.UI.IconTexture(icon=="compass" and "location" or icon)
end

local function sameMapSpot(map,x,y,p)
    return p and p.map==map and math.abs(p.x-x)<.00001 and math.abs(p.y-y)<.00001
end

-- WaypointUI writes a 2D user waypoint, including when SPF hands it a route.
-- Restore the height only on that same, still tracked pin. A bend can be on
-- another floor from the destination, even on a short walk.
local function syncWaypointHeight(api,nav,goal,route)
    if not (nav and nav.flags==(route and "ShortestPathForever" or "AiLeveling") and
        C_Map and C_Map.GetUserWaypoint and C_Map.SetUserWaypoint and UiMapPoint) then
        N.heightPin=nil
        return
    end
    local p=goal and N.Target(goal)
    if not (sameMapSpot(nav.mapID,nav.x,nav.y,p) and p.z) then
        p=route and route:GuidancePoint()
    end
    if not (p and p.z and sameMapSpot(nav.mapID,nav.x,nav.y,p) and api.IsUserNavigationTracked()) then
        N.heightPin=nil
        return
    end
    local pin=C_Map.GetUserWaypoint()
    if not (pin and pin.position and sameMapSpot(pin.uiMapID,pin.position.x,pin.position.y,p)) then
        N.heightPin=nil
        return
    end
    if pin.z and math.abs(pin.z-p.z)<.01 then
        N.heightPin=nil
        return
    end
    -- Some clients omit z on readback. One write per marker also bounds synchronous waypoint events.
    if sameMapSpot(nav.mapID,nav.x,nav.y,N.heightPin) and N.heightPin.z==p.z then return end
    if InCombatLockdown() or route and not route.api.CurrentStop("AiLeveling") then return end
    N.heightPin={map=pin.uiMapID,x=pin.position.x,y=pin.position.y,z=p.z}
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(pin.uiMapID,pin.position.x,pin.position.y,p.z))
end

function N:SyncWaypointUI(force)
    local api=WaypointUIAPI and WaypointUIAPI.Navigation
    local external=A.ShortestPath and A.ShortestPath.owned
    if not (api and api.GetUserNavigation and api.NewUserNavigation and api.ClearUserNavigation and api.IsUserNavigationTracked) then
        return external and "external" or nil
    end
    -- WaypointUI tracks the pin but hides its world HUD inside dungeons.
    local enabled=A.settings.waypointUI~=false and not A.state.inInstance and not external
    local action=enabled and self:Current()
    local nav=api.GetUserNavigation()
    local owned=nav and nav.flags=="AiLeveling"
    if not (A.char.paused or A.state.dead) then
        syncWaypointHeight(api,nav,external and A.ShortestPath.goal or action,external and A.ShortestPath)
        -- SPF formats a single stop as a journey. At our quest destination use the log title on the same WUI pin.
        local route=external and A.settings.waypointUI~=false and A.ShortestPath
        local goal=route and route.goal
        if goal and goal.questId and (goal.kind=="accept" or goal.kind=="objective" or goal.kind=="turnin") and
            route.title and nav and nav.flags=="ShortestPathForever" and nav.name~=route.title and
            sameMapSpot(nav.mapID,nav.x,nav.y,N.Target(goal)) and not InCombatLockdown() and
            route.api.CurrentStop("AiLeveling") and api.IsUserNavigationTracked() then
            local options={}
            for key,value in pairs(nav) do options[key]=value end
            options.name,options.x,options.y=route.title,nav.x*100,nav.y*100
            options.suppressAudio,options.syncNativeWaypoint=true,false
            api.NewUserNavigation(options)
        end
    end
    if not enabled and not owned then return external and "external" or nil end
    local userTracked=api.IsUserNavigationTracked()
    local tracked=userTracked or api.IsPathStepWaypointTracked and api.IsPathStepWaypointTracked()
    local rawPin=not tracked and C_SuperTrack and C_SuperTrack.GetHighestPrioritySuperTrackingType and Enum and Enum.SuperTrackingType and
        C_SuperTrack.GetHighestPrioritySuperTrackingType()==Enum.SuperTrackingType.UserWaypoint
    if enabled and not force and (not owned and tracked or rawPin) then
        return "external"
    end
    local target=action and N.Target(action)
    if not target or A.char.paused or action.kind=="flight" or action.mode=="hearth" or action.publicTransit and action.atDeparture or
        C_Map and C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(target.map) then
        if owned then api.ClearUserNavigation(not userTracked,true) end
        return external and "external" or nil
    end
    local q=action.questId and ((A.state.quests or {})[action.questId] or A.Data and A.Data:GetQuest(action.questId))
    local questStep=action.kind=="accept" or action.kind=="objective" or action.kind=="turnin"
    local label=questStep and q and q.title or action.title or q and q.title or target.entityName or action.text or "任务目的地"
    local texture=actionTexture(action)
    if owned and nav.mapID==target.map and math.abs(nav.x-target.x)<0.000001 and math.abs(nav.y-target.y)<0.000001 and
        nav.name==label and nav.iconTexture==texture and (tracked or not force) then
        if tracked then return "itinerary" end
        return
    end
    local placed=api.NewUserNavigation({mapID=target.map,x=target.x*100,y=target.y*100,name=label,flags="AiLeveling",
        iconTexture=texture,iconType="TEXTURE",stripCoordinates=true,suppressAudio=true})
    if placed then return "itinerary" end
    if owned then api.ClearUserNavigation(not userTracked,true) end
end

-- Keep the itinerary badge and group tooltip while the client draws the same hand-in.
local function showGlyph(pin,shown)
    pin.face:SetShown(shown);pin.ring:SetShown(shown);pin.texture:SetShown(shown)
end

local function screenCenter(frame)
    local x,y=frame:GetCenter()
    if x and y then
        local scale=frame:GetEffectiveScale()
        return x*scale,y*scale
    end
end

local function syncHandinPins()
    N.handinSyncQueued=nil
    local map=WorldMapFrame
    if not (N.hasHandinPins and map and map:IsShown() and map.EnumeratePinsByTemplate) then return end
    local native={}
    for pin in map:EnumeratePinsByTemplate("QuestPinTemplate") do
        if not N.watchedQuestPins[pin] then
            N.watchedQuestPins[pin]=true
            pin:HookScript("OnShow",N.QueueHandinPins);pin:HookScript("OnHide",N.QueueHandinPins)
        end
        local id=pin:GetQuestID()
        if pin:IsShown() and (not canaccessvalue or canaccessvalue(id)) and id and
            (A.state.quests[id] or {}).ready then
            local group=native[id] or {}
            group[#group+1]=pin;native[id]=group
        end
    end
    for _,pin in pairs(N.pins) do
        if not pin.mini and pin:IsShown() and pin.action.kind=="turnin" then
            local x,y=screenCenter(pin)
            local radius=pin:GetWidth()*pin:GetEffectiveScale()*0.65
            local covered=false
            for _,action in ipairs(pin.point.actions) do
                if x and action.kind=="turnin" then
                    for _,other in ipairs(native[action.questId] or {}) do
                        local ox,oy=screenCenter(other)
                        if ox and (x-ox)^2+(y-oy)^2<=radius^2 then covered=true;break end
                    end
                end
                if covered then break end
            end
            showGlyph(pin,not (covered or pin.spfHandin))
        end
    end
end

function N.QueueHandinPins()
    if N.handinSyncQueued or not N.hasHandinPins or not WorldMapFrame:IsShown() then return end
    N.handinSyncQueued=true
    C_Timer.After(0,syncHandinPins)
end

local function watchHandinPins()
    local map=WorldMapFrame
    if not (map and map.EnumeratePinsByTemplate and hooksecurefunc and C_Timer) then return end
    if not N.watchedQuestPins then
        N.watchedQuestPins=setmetatable({},{__mode="k"})
        map:HookScript("OnShow",N.QueueHandinPins)
        hooksecurefunc(map,"AcquirePin",function(_,template)
            if template=="QuestPinTemplate" then N.QueueHandinPins() end
        end)
        hooksecurefunc(map,"OnCanvasScaleChanged",N.QueueHandinPins)
    end
    N.QueueHandinPins()
end

-- Native offers reset desaturation for their floor on every acquisition, including pooled pins.
local function styleNativeOffer(_,pin)
    if pin.pinTemplate~="QuestOfferPinTemplate" then return end
    pin.aiLevelingLowOffer=nil
    if N.nativeOffersEnabled and pin.questIcon=="QuestNormal" and
        (pin.isHidden or C_QuestLog and C_QuestLog.IsQuestTrivial and C_QuestLog.IsQuestTrivial(pin.questID)) and
        not pin.Texture:IsDesaturated() then
        pin.Texture:SetDesaturated(true)
        pin.aiLevelingLowOffer=true
    end
end

local function syncNativeOffers()
    local map=WorldMapFrame
    if not (map and map.RegisterPin and map.EnumeratePinsByTemplate and hooksecurefunc) then return end
    local enabled=A.settings.pins and A.settings.mapTaskScope~="off" and not A.char.paused
    if N.nativeOffersEnabled==enabled then return end
    N.nativeOffersEnabled=enabled
    if enabled and not N.nativeOfferHook then
        hooksecurefunc(map,"RegisterPin",styleNativeOffer)
        N.nativeOfferHook=true
    end
    for pin in map:EnumeratePinsByTemplate("QuestOfferPinTemplate") do
        if enabled then styleNativeOffer(map,pin)
        elseif pin.aiLevelingLowOffer then
            pin.Texture:SetDesaturated(false)
            pin.aiLevelingLowOffer=nil
        end
    end
end

local function stylePin(pin,point,action,r,g,b,hitOnly)
    pin.point,pin.action=point,action
    if not pin.mini then showGlyph(pin,true) end
    pin:SetAlpha(hitOnly and 0 or 1)
    local size=(pin.mini and 19 or 24)+(point.current and 4 or point.lowOnly and -4 or 0)
    pin:SetSize(size,size)
    pin.texture:SetSize(size-4,size-4)
    pin.ring:SetSize(size+(point.current and 5 or 0),size+(point.current and 5 or 0))
    if point.current then pin.ring:SetVertexColor(r,g,b) else pin.ring:SetVertexColor(0.43,0.39,0.37) end
    if not pin.mini then A.UI:SetMapPinNumber(pin,point.order,nil,point.current) end
    pin.texture:SetTexture(actionTexture(action))
    pin.texture:SetDesaturated(point.lowOnly==true)
end

local function updateEdge(pin,pins)
    if not pin then return end
    if not pin:IsShown() or not pins:IsMinimapIconOnEdge(pin) then pin.arrow:Hide();return end
    local _,_,_,x,y=pin:GetPoint()
    if not x or not y or x==0 and y==0 then pin.arrow:Hide();return end
    if pin.arrow:IsShown() and pin.arrowX==x and pin.arrowY==y then return end
    pin.arrowX,pin.arrowY=x,y
    local offset=(pin:GetWidth()/2+4)/math.sqrt(x*x+y*y)
    pin.arrow:ClearAllPoints();pin.arrow:SetPoint("CENTER",pin,"CENTER",x*offset,y*offset)
    pin.arrow:SetRotation(math.atan2(-x,y));pin.arrow:Show()
end

function N:RefreshPins(force)
    if A.Transport and A.Transport.taxiMapOpen then self:RefreshTaxiMarker() end
    self.waypointDisplay=self:SyncWaypointUI(force)
    self:DrawPins()
end

function N:DrawPins()
    syncNativeOffers()
    if self.mapAreaAction and (not isAreaTarget(self.mapAreaAction) or A.char.paused or A.settings.mapTaskScope=="off") then clearMapArea() end
    self.hasHandinPins=nil
    if not self.hbdPins then return end
    self.hbdPins:RemoveAllWorldMapIcons(self)
    self.hbdPins:RemoveAllMinimapIcons(self)
    if self.edgePin then self.edgePin.arrow:Hide();self.edgePin=nil end
    for _,pin in pairs(self.pins) do pin:Hide() end
    if (not A.settings.pins and not A.settings.minimapPins) or A.char.paused then return end
    local r,g,b=A.UI:ClassColor()
    for order,point in ipairs(self:MapPoints()) do
        local action,pos=point.action,point.position
        local nearby=availableAction(action) and action
        if not nearby then
            for _,other in ipairs(point.actions) do
                if availableAction(other) then
                    nearby=other
                    if other.kind~="accept" or not (point.lowOffers and point.lowOffers[other.questId]) then break end
                end
            end
        end
        -- A walk ending at the quest pin should show what to do on arrival.
        if nearby and (not point.current or nearby.questId==action.questId and (action.kind=="move" or action.kind=="approach")) then action=nearby end
        local index=(order-1)*2
        -- Keep grouped quest tooltips even when WaypointUI draws the destination.
        local delegated=point.current and self.waypointDisplay=="itinerary" and #point.actions==1
        -- WaypointUI draws a single destination glyph. Keep our quest click target over it.
        local areaHit=delegated and isAreaTarget(action)
        local edge=point.current and action.mode~="hearth" and not self.waypointDisplay
        if A.settings.pins and (not delegated or areaHit) then
            local pin=self.pins[index+1] or mapPin(false);self.pins[index+1]=pin
            local handin=action.kind=="turnin"
            if handin then self.hasHandinPins=true end
            pin.spfHandin=handin and point.current and A.ShortestPath and A.ShortestPath:For(point.action)
            stylePin(pin,point,action,r,g,b,areaHit)
            if pin.spfHandin then showGlyph(pin,false) end
            self.hbdPins:AddWorldMapIconMap(self,pin,pos.map,pos.x,pos.y,1,
                (areaHit or handin and (point.order or #point.actions>1)) and "PIN_FRAME_LEVEL_WAYPOINT_LOCATION" or nil)
        end
        if A.settings.minimapPins and (not delegated or areaHit) and (point.current or nearby) then
            local pin=self.pins[index+2] or mapPin(true);self.pins[index+2]=pin
            stylePin(pin,point,point.current and action or nearby,r,g,b,areaHit)
            if edge then
                if not pin.arrow then
                    pin.arrow=pin:CreateTexture(nil,"OVERLAY");pin.arrow:SetTexture(media.."hud-chevron-up.tga")
                    pin.arrow:SetSize(12,12)
                end
                pin.arrow:SetVertexColor(r,g,b);pin.arrow:Hide();self.edgePin=pin
            end
            self.hbdPins:AddMinimapIconMap(self,pin,pos.map,pos.x,pos.y,false,edge or false)
        end
    end
    if self.hasHandinPins then watchHandinPins() end
end

local function hasWaypointText(label)
    if not (label and label.GetText and label:IsVisible()) then return false end
    local alpha=label:GetEffectiveAlpha()
    if (issecretvalue and issecretvalue(alpha)) or alpha<=0 then return false end
    local text=label:GetText()
    return (issecretvalue and issecretvalue(text)) or (text~=nil and text~="")
end

-- Both world markers follow C_Navigation.GetFrame(). Let WaypointUI have the
-- text below it while its caption is visible. DaylightUI still draws the trail.
local hiddenDaylightDistance
local function syncWorldMarkerText()
    local marker=DaylightUIQuestMarker
    local label=marker and marker.dist
    local hide
    if label and marker:IsVisible() then
        local footer=WUIWaypointFrame and WUIWaypointFrame.Footer
        local pinpoint=WUIPinpointFrame and WUIPinpointFrame.Foreground
        hide=footer and (hasWaypointText(footer.DistanceText) or hasWaypointText(footer.InfoText) or
            hasWaypointText(footer.ArrivalTimeText)) or pinpoint and hasWaypointText(pinpoint.Content)
    end
    if hiddenDaylightDistance and (not hide or hiddenDaylightDistance~=label) then
        hiddenDaylightDistance:Show()
        hiddenDaylightDistance=nil
    end
    if hide and label:IsShown() then
        label:Hide()
        hiddenDaylightDistance=label
    end
end

function N:Update()
    syncWorldMarkerText()
    local action
    if A.ShortestPath and ShortestPathForever then
        local current=self:LocalAction()
        -- In transit the status action temporarily replaces the quest that owns the journey.
        local riding=A.state.onTaxi or current and (current.kind=="flight" or current.kind=="hearthCast" or current.kind=="tram")
        if not (riding and A.ShortestPath.owned) or A.char.paused or A.state.dead then A.ShortestPath:Sync(current) end
        action=A.ShortestPath:For(current) or current
    else action=self:Current() end
    if self.manual and self.manual.externalRoute and not A.ShortestPath.owned and not (A.char.paused or A.state.dead or A.state.onTaxi) then
        self.manual.externalRoute=nil
        if self:Navigate(self.manual.action,true) then return end
    end
    local display=self:SyncWaypointUI()
    if display~=self.waypointDisplay then
        self.waypointDisplay=display
        self:DrawPins()
    end
    updateEdge(self.edgePin,self.hbdPins)
    local pos=A.state.position
    if A.char.paused or not action then A.UI:SetNavigation(nil);return end
    if action.kind=="service" and A.Supplies and A.Supplies.Done(action,A.state) then
        self:Advance();return
    end
    if A.ShortestPath and A.ShortestPath:For(action) then
        if action.kind=="manual" and self:Near(pos,action.position,action.arrival) then self:ClearManual();return end
        A.UI:SetNavigation(nil,nil,nil,action);return
    end
    if action.kind=="flight" or action.kind=="hearthCast" or action.kind=="tram" then A.UI:SetNavigation(nil,nil,nil,action);return end
    local instanceGuide=A.state.inInstance and not A.state.dead and
        (action.kind=="accept" or action.kind=="objective" or action.kind=="turnin" or action.kind=="dungeonLeave")
    if action.publicTransit and pos then
        local arrival=self:Distance(pos,action.position)
        -- Players emerge beside the portal. Crossing onto its destination land
        -- also handles a load screen ending after the player has moved away.
        if arrival and arrival<=(action.arrival or 40) or action.mode=="portal" and
            not A.Travel.Separated(pos,action.position,self) then self:Advance();return end
        if action.mode~="portal" and not action.atDeparture and self:Near(pos,action.departure,action.departureRadius) then
            action.atDeparture=true;self:RefreshPins();A.dirty=true
        end
    end
    local target=N.Target(action)
    if not self.hbd or not target or not pos and not instanceGuide or action.publicTransit and action.atDeparture then
        A.UI:SetNavigation(nil,nil,nil,action)
        return
    end
    local flight=action.kind=="transit" and action.mode=="flight"
    if (flight or action.kind=="transit" and action.mode=="hearth") and self:Near(pos,action.position,action.arrival) then
        if not self.atTransitDestination and not (A.jobs and A.jobs.plan) then A:Replan() end
        self.atTransitDestination=action
        A.UI:SetNavigation(nil,nil,nil,action)
        return
    end
    self.atTransitDestination=nil
    if action.mode=="hearth" then A.UI:SetNavigation(nil,nil,nil,action);return end
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
    -- WaypointUI supplies the bearing. The itinerary still supplies the instruction.
    if display or A.settings.arrow==false then A.UI:SetNavigation(nil,nil,nil,action);return end
    local x,y,instance
    if instanceGuide and self.hbd.GetPlayerWorldPosition then x,y,instance=self.hbd:GetPlayerWorldPosition() end
    if not x and pos then x,y,instance=self.hbd:GetWorldCoordinatesFromZone(pos.x,pos.y,pos.map) end
    local tx, ty, targetInstance = self.hbd:GetWorldCoordinatesFromZone(target.x, target.y, target.map)
    local angle
    if x and tx and instance==targetInstance and (not instanceGuide or instance==A.state.instanceId) then
        local bearing,yards=self.hbd:GetWorldVector(instance,x,y,tx,ty)
        angle,distance=bearing,yards or distance
    elseif instanceGuide then distance=nil end
    local facing=angle and GetPlayerFacing()
    A.UI:SetNavigation(distance,angle and facing and (angle-facing),A.plan and A.plan.unverified,action)
end
