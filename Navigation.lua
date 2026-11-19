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
    action=action.questAction or action
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
    self.plan=plan
    self.planInstance=A.state.inInstance and A.state.instanceId
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
    if id and (action.kind=="accept" and active or action.kind=="objective" and (not active or active.ready or
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
    local routes=not (point and point.startItemId) and approach.position and A.Flights and A.Flights.Itinerary(state.position,{approach},state,self)
    local actions=routes and routes[1] and A.Flights.Actions(routes[1],approach,self)
    if not actions then actions={A.Flights and A.Flights.MissingCrossing and A.Flights.MissingCrossing(approach,state,self) or approach} end
    self.manual={title=action.title,action=target,actions=actions,index=1,
        instanceId=state.instanceId,inInstance=state.inInstance,plan={revision=-1,travelActions=actions,itemStock=self.plan and self.plan.itemStock}}
    self:RefreshPins(not keepWaypoint)
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
                crossing and A.state.position and (crossing.map~=A.state.position.map or A.Travel.Separated(crossing,A.state.position,self))) then
                if self:Navigate(goal,true) then return self:Current() end
            end
            if not N.StaleAction(action,A.state,self.manual.plan) then
                return action or {kind="manual",title=self.manual.title or "手动目的地",position=self.manual}
            end
            self:ClearManual(false)
        end
    end
    if A.state.inInstance and self.planInstance~=A.state.instanceId then return end
    local action=self.actions and self.actions[self.index]
    if N.StaleAction(action) then action=nil end
    local state=A.state
    local position=state.position
    local plan=A.plan
    if A.indexReady and not (A.jobs and A.jobs.plan) then return action end
    local changedZone=position and plan and plan.origin and plan.origin.map~=position.map
    local previousQuest=action and (action.kind=="turnin" or action.kind=="objective" or action.kind=="accept")
    local previousStop=changedZone and N.Target(action)
    local reachedStop=changedZone and action and action.publicTransit and action.position and action.position.map==position.map
    if action and action.kind~="taskReview" and not (changedZone and previousQuest or
        previousStop and previousStop.map~=position.map or reachedStop) then return action end
    local selected=state.locked or state.preparingQuest or state.taskBatch or state.gearTarget or state.serviceStop
    if position and not (selected or state.dead or state.onTaxi or state.inInstance or (state.level or 0)>=60 or A.error or A.char.paused)
        and A.TaskGuide and A.Data and A.Data.Target then
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
        -- The previous itinerary can still contain a valid local objective after its first task is handed in.
        for _,choice in ipairs(plan and plan.taskOrder or {}) do
            local quest=state.quests[choice.questId]
            local step=choice.executionAction or (choice.actions or {})[1]
            if quest and not quest.ready and step and step.kind=="objective" and step.position and
                step.position.map==position.map and not (step.expected or step.position.areaOnly or choice.itemShortage or
                choice.entryBlocked or choice.lowValue or choice.revisitLevel) and
                not N.StaleAction(step,state,plan) then return step end
        end
    end
    return action
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
        if not catalog and not point.order and routeCount<6 then
            routeCount=routeCount+1
            point.order,point.action=routeCount,action
        end
        if action==current then point.current=true end
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

local media="Interface\\AddOns\\AiLeveling\\Media\\"
local function cell(texture,index)
    texture:SetTexture(media.."map-markers.tga")
    texture:SetTexCoord(index/4,(index+1)/4,0,1)
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

local function showPinTip(pin)
    local point,primary=pin.point,pin.action
    local quest=(primary.kind=="accept" or primary.kind=="objective" or primary.kind=="turnin") and A.state.quests[primary.questId]
    local title=quest and quest.title or primary.title or "目的地"
    GameTooltip:SetOwner(pin,"ANCHOR_RIGHT")
    GameTooltip:SetText((point.current and "当前目标 · " or "")..title)
    for _,action in ipairs(point.actions) do
        if not pin.mini or action==primary or availableAction(action) then
            local active=A.state.quests[action.questId]
            local label=action.kind=="accept" and "接取任务" or action.kind=="turnin" and
                (active and active.ready and "交付任务" or "完成后交付") or action.kind=="objective" and
                (not active and "接取后目标" or action.targetKind=="item" and "收集目标" or "任务目标") or "前往"
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
        GameTooltip:AddLine(place,0.8,0.8,0.82,true)
    end
    GameTooltip:AddLine("左键导航"..(N.manual and "  ·  右键返回原行程" or ""),0.9,0.77,0.57)
    GameTooltip:Show()
end

local function mapPin(mini)
    local pin=CreateFrame("Button",nil,UIParent)
    pin.mini=mini
    local face=pin:CreateTexture(nil,"BACKGROUND")
    cell(face,0);face:SetAllPoints();face:SetVertexColor(0.09,0.09,0.12)
    pin.ring=pin:CreateTexture(nil,"BORDER")
    cell(pin.ring,1);pin.ring:SetPoint("CENTER")
    pin.texture=pin:CreateTexture(nil,"ARTWORK");pin.texture:SetPoint("CENTER")
    if not mini then
        pin.badge=pin:CreateTexture(nil,"ARTWORK",nil,1)
        cell(pin.badge,0);pin.badge:SetSize(15,15);pin.badge:SetPoint("CENTER",pin,"TOPRIGHT",-1,-2)
        pin.number=pin:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        pin.number:SetPoint("CENTER",pin.badge)
    end
    pin:Hide();pin:EnableMouse(true)
    pin:RegisterForClicks("LeftButtonUp","RightButtonUp")
    pin:SetScript("OnClick",function(f,button)
        GameTooltip:Hide()
        local action=f.action
        if button=="RightButton" then
            if N.manual then N:ClearManual() end
        elseif IsModifiedClick and IsModifiedClick("CHATLINK") and action.questId then
            A.UI:QuestClick(action.questId,button)
        elseif not N:Navigate(action) and action.questId then
            if not N:NavigateQuest(action.questId) then A.UI:QuestClick(action.questId,button) end
        end
    end)
    pin:SetScript("OnEnter",showPinTip)
    pin:SetScript("OnLeave",function() GameTooltip:Hide() end)
    return pin
end

local function actionAtlas(action)
    return ({accept="QuestNormal",turnin="UI-QuestPoi-QuestBangTurnIn",dungeonEnter="Dungeon"})[action.kind]
        or (action.kind=="transit" and action.mode=="flight" and "FlightPath") or "Waypoint-MapPin-Tracked"
end

function N:SyncWaypointUI(force)
    local api=WaypointUIAPI and WaypointUIAPI.Navigation
    if not (api and api.GetUserNavigation and api.NewUserNavigation and api.ClearUserNavigation and api.IsUserNavigationTracked) then return end
    -- WaypointUI tracks the pin but hides its world HUD inside dungeons.
    local enabled=A.settings.waypointUI~=false and not A.state.inInstance
    local action=enabled and self:Current()
    local nav=api.GetUserNavigation()
    local owned=nav and nav.flags=="AiLeveling"
    if not enabled and not owned then return end
    local userTracked=api.IsUserNavigationTracked()
    local tracked=userTracked or api.IsPathStepWaypointTracked and api.IsPathStepWaypointTracked()
    local rawPin=not tracked and C_SuperTrack and C_SuperTrack.GetHighestPrioritySuperTrackingType and Enum and Enum.SuperTrackingType and
        C_SuperTrack.GetHighestPrioritySuperTrackingType()==Enum.SuperTrackingType.UserWaypoint
    if enabled and not force and (not owned and tracked or rawPin) then
        return "external"
    end
    local target=action and N.Target(action)
    if not target or A.char.paused or action.kind=="flight" or action.kind=="hearth" or action.publicTransit and action.atDeparture or
        C_Map and C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(target.map) then
        if owned then api.ClearUserNavigation(not userTracked,true) end
        return
    end
    local q=action.questId and ((A.state.quests or {})[action.questId] or A.Data and A.Data:GetQuest(action.questId))
    local label=action.title or q and q.title or target.entityName or action.text or "任务目的地"
    local atlas=actionAtlas(action)
    if owned and nav.mapID==target.map and math.abs(nav.x-target.x)<0.000001 and math.abs(nav.y-target.y)<0.000001 and
        nav.name==label and nav.iconTexture==atlas and (tracked or not force) then
        if tracked then return "itinerary" end
        return
    end
    local placed=api.NewUserNavigation({mapID=target.map,x=target.x*100,y=target.y*100,name=label,flags="AiLeveling",
        iconTexture=atlas,iconType="ATLAS",stripCoordinates=true,suppressAudio=true})
    if placed then return "itinerary" end
    if owned then api.ClearUserNavigation(not userTracked,true) end
end

local function stylePin(pin,point,action,r,g,b)
    pin.point,pin.action=point,action
    local size=(pin.mini and 19 or 24)+(point.current and 4 or 0)
    pin:SetSize(size,size)
    pin.texture:SetSize(size-4,size-4)
    pin.ring:SetSize(size+(point.current and 5 or 0),size+(point.current and 5 or 0))
    if point.current then pin.ring:SetVertexColor(r,g,b) else pin.ring:SetVertexColor(0.43,0.39,0.37) end
    if pin.badge then
        pin.badge:SetShown(point.order~=nil);pin.number:SetText(point.order and tostring(point.order) or "")
        if point.current then pin.badge:SetVertexColor(r,g,b);pin.number:SetTextColor(0.08,0.07,0.09)
        else pin.badge:SetVertexColor(0.16,0.16,0.19);pin.number:SetTextColor(1,1,1) end
    end
    local tex=pin.texture
    if action.kind=="accept" then
        cell(tex,2);tex:SetVertexColor(1,0.84,0.46)
    elseif action.kind=="turnin" then
        cell(tex,3)
        if availableAction(action) then tex:SetVertexColor(0.56,0.93,0.77) else tex:SetVertexColor(0.73,0.72,0.69) end
    elseif action.kind=="objective" then
        local item=action.targetKind=="item"
        tex:SetTexture(media..(item and "hud-collect.tga" or "hud-objective.tga"))
        tex:SetTexCoord(0,1,0,1)
        if item then tex:SetVertexColor(0.87,0.74,1) else tex:SetVertexColor(0.64,0.83,1) end
    else
        tex:SetAtlas(actionAtlas(action),false);tex:SetVertexColor(1,1,1)
    end
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
    self.waypointDisplay=self:SyncWaypointUI(force)
    self:DrawPins()
end

function N:DrawPins()
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
                if availableAction(other) then nearby=other;break end
            end
        end
        -- A walk ending at the quest pin should show what to do on arrival.
        if nearby and (not point.current or nearby.questId==action.questId and (action.kind=="move" or action.kind=="approach")) then action=nearby end
        local index=(order-1)*2
        -- Keep grouped quest tooltips even when WaypointUI draws the destination.
        local delegated=point.current and self.waypointDisplay=="itinerary" and #point.actions==1
        local edge=point.current and not self.waypointDisplay
        if A.settings.pins and not delegated then
            local pin=self.pins[index+1] or mapPin(false);self.pins[index+1]=pin
            stylePin(pin,point,action,r,g,b)
            self.hbdPins:AddWorldMapIconMap(self,pin,pos.map,pos.x,pos.y,1)
        end
        if A.settings.minimapPins and not delegated and (point.current or nearby) then
            local pin=self.pins[index+2] or mapPin(true);self.pins[index+2]=pin
            stylePin(pin,point,point.current and action or nearby,r,g,b)
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
end

function N:Update()
    local display=self:SyncWaypointUI()
    if display~=self.waypointDisplay then
        self.waypointDisplay=display
        self:DrawPins()
    end
    updateEdge(self.edgePin,self.hbdPins)
    local action, pos = self:Current(), A.state.position
    if A.char.paused or not action then A.UI:SetNavigation(nil);return end
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
    if action.kind=="service" and A.Supplies and A.Supplies.Done(action,A.state) then
        self:Advance();return
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
