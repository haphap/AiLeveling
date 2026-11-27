local _,A=...
local UI=A.UI
local palette=UI.colors
local spacing=UI.metrics
local media="Interface\\AddOns\\AiLeveling\\Media\\"

local function setHUDIcon(texture,icon,muted)
    texture:SetTexture(UI.IconTexture(icon))
    texture:SetAlpha(muted and 0.72 or 1)
end

local function nearbyDistance(yards)
    local meters=A.settings.distanceUnits=="meters"
    return string.format("%d %s",math.floor(yards*(meters and 0.9144 or 1)/5+0.5)*5,meters and "米" or "码")
end

local function metrics(choice,xpOnly)
    local xp=choice and choice.remainingXP
    local reward="经验 "..(xp and string.format("%.0f",xp) or "—")
    if xpOnly then return reward end
    local seconds=choice and choice.timing and choice.timing.seconds
    local time="—"
    if seconds then
        seconds=math.ceil(seconds)
        if seconds>=3600 then time=string.format("%d小时%02d分",math.floor(seconds/3600),math.floor(seconds/60)%60)
        elseif seconds>=60 then time=string.format("%d分%02d秒",math.floor(seconds/60),seconds%60)
        else time=string.format("%d秒",seconds) end
    end
    return reward.."  ·  路程 "..time
end

local function placeLabel(name)
    return "|cff"..UI.hex.place..name.."|r"
end

local function mapLocation(point)
    if not point or point.approximate or point.areaOnly or not (point.map and point.x and point.y) then return end
    local map=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(point.map)
    if map and map.name then
        local prefix=point.sourceKind=="escortStart" and "护送起点 · " or point.spawnArea and "出没区域 · " or ""
        return placeLabel(("%s%s %.1f，%.1f"):format(prefix,map.name,100*point.x,100*point.y))
    end
end

local function destination(action,styled)
    local point=action and action.position
    if A.Navigation and A.Navigation.Target then point=A.Navigation.Target(action) end
    point=point or action and action.recipient
    if not point then
        local instance=action and action.areaId and A.Data and A.Dungeon and A.Dungeon.TaskInstance and
            A.Dungeon.TaskInstance(nil,A.state,A.Data,action.areaId)
        local name=instance and instance.title
        if styled and name then name=placeLabel(name) end
        return name,name
    end
    local map=point.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(point.map)
    local name=point.siteName or point.entityName or action.kind=="turnin" and action.recipient and action.recipient.entityName
    local zone=map and map.name
    local area=name and zone~=name and zone
    if styled then
        if point.siteName then name=placeLabel(point.siteName) end
        if zone then zone=placeLabel(zone) end
        if area then area=zone end
    end
    return name and (name..(area and " · "..area or "")) or zone,name or zone,area
end

local function clockText(seconds)
    if seconds==nil then return "—" end
    seconds=math.max(0,math.ceil(seconds))
    return string.format("%d:%02d",math.floor(seconds/60),seconds%60)
end

local function placeName(point,fallback)
    local map=point and point.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(point.map)
    if point and point.entityName then return point.entityName,point.siteName end
    if point and point.siteName then return point.siteName,point.siteName end
    local name=fallback or map and map.name
    return name or "任务地点",map and map.name
end

-- Match only the named endpoints of this step. Prefer the longer name when stops overlap.
local function placeText(text,origin,destination)
    if not text or not (origin or destination) or text:find("|",1,true) then return text end
    local start,parts=1
    while true do
        local first,last
        if origin and origin~="" then first,last=text:find(origin,start,true) end
        if destination and destination~="" then
            local left,right=text:find(destination,start,true)
            if left and (not first or left<first or left==first and right>last) then first,last=left,right end
        end
        if not first then break end
        parts=parts or {}
        parts[#parts+1]=text:sub(start,first-1)..placeLabel(text:sub(first,last))
        start=last+1
    end
    return parts and table.concat(parts)..text:sub(start) or text
end

local function routeSequence(state)
    local nav=A.Navigation
    if nav and (nav.manual or not nav.RouteStatus or not nav:RouteStatus(A.plan,state)) then
        return nav.Sequence and nav:Sequence() or nav
    end
end

local function trackerPlan(state)
    local nav=A.Navigation
    return nav and nav.TrackerPlan and nav:TrackerPlan(A.plan,state) or A.plan or {}
end

function UI.TrackerJourney(state,action)
    local nav=A.Navigation
    if A.ShortestPath and A.ShortestPath:For(action) then
        local trip=A.ShortestPath.journey
        if trip then
            local finalWalk=trip.steps[1].kind=="walk" and (#trip.steps==1 or trip.steps[2].task)
            if not finalWalk or not nav:Near(state.position,trip.goal.position,trip.goal.arrival) then return trip end
        end
        return
    end
    if not action or not nav or not A.Travel then return end
    local sequence=routeSequence(state)
    if not sequence or not sequence.actions then return end
    local index=sequence.index or 1
    local current=sequence.actions[index]
    local flight=A.Transport and A.Transport.flight
    local hearth=A.Hearth and (A.Hearth.cast or A.Hearth.pending)
    local flying=action.kind=="flight" and flight and flight.action==current
    local returning=action.kind=="hearthCast" and hearth and hearth.action==current
    if not current or current~=action and not flying and not returning then return end
    local result={steps={},seconds=0,distance=0,action=action,atDeparture=action.atDeparture}
    local position,transport=state.position,false
    local function add(kind,title,seconds,detail,place)
        seconds=seconds and math.max(0,math.ceil(seconds))
        result.steps[#result.steps+1]={kind=kind,title=title,seconds=seconds,detail=detail,place=place}
        result.seconds=result.seconds and seconds and result.seconds+seconds or nil
    end
    local function walk(point,name,radius,place)
        local seconds,distance=A.Travel.Walk(position,point,state,nav)
        if seconds~=0 and (not distance or distance>(radius or 12)) then
            local label,site=placeName(point,name)
            add("walk","走到 "..label,seconds,nil,place or site)
            result.distance=result.distance and distance and result.distance+distance or nil
        end
        position=point
    end
    for i=index,#sequence.actions do
        local step=sequence.actions[i]
        if nav.StaleAction and nav.StaleAction(step,state,sequence.plan) then return end
        if step.kind=="transit" then
            transport=true
            local boarded=i==index and (flying or returning or step.atDeparture)
            local from=step.fromTaxi and ((state.taxiNames or {})[step.fromTaxi] or
                A.FlightData and A.FlightData.nodes[step.fromTaxi] and A.FlightData.nodes[step.fromTaxi].name)
            if not boarded and step.mode~="hearth" then
                from=step.fromName or from
                walk(step.departure,from,step.departureRadius,step.fromPlace or from)
            end
            local seconds,detail=step.travelSeconds,nil
            if flying and i==index and flight.duration and flight.observedStart then
                seconds=math.max(0,flight.duration-(GetTime()-flight.started));detail="飞行中"
            elseif returning and i==index then
                seconds=step.travelRide and math.max(0,step.travelRide-(GetTime()-hearth.started));detail="炉石返回中"
            elseif step.publicTransit and step.travelWait and step.travelRide then
                detail="平均等候 "..clockText(step.travelWait).." · 乘坐 "..clockText(step.travelRide)
            end
            local title,place=step.title,step.toName
            if not title then
                local label,site=placeName(step.position,place)
                title,place="前往 "..label,place or site
            end
            add(step.mode,title,seconds,detail,place)
            position=step.position
        elseif step.kind=="move" or step.kind=="approach" then
            walk(step.position,step.title~="前往下一目的地" and step.title or nil,step.arrival)
        else
            result.goal=step
            walk(step.position,nil,step.arrival)
            local verb=({accept="接取",objective="完成",turnin="交付"})[step.kind]
            if verb then
                result.steps[#result.steps+1]={kind=step.kind,title=verb.." "..(step.title or "任务"),task=true,action=step}
            end
            break
        end
    end
    if transport and result.goal then return result end
end

local function nextAction(action,plan,state,rows,batchSteps)
    if not action or action.kind=="manual" then return end
    local navigation=routeSequence(state)
    local function listed(stage,id)
        if A.Navigation and A.Navigation.StaleAction and A.Navigation.StaleAction(stage,state,
            navigation and navigation.plan or plan) then return true end
        if id and id==action.questId then
            if stage.kind==action.kind or stage.kind=="accept" then return true end
            if stage.kind=="objective" and action.kind~="accept" then return true end
        end
        for _,row in ipairs(rows) do
            if (row.atStop or row.along) and row.questId==id and row.kind==stage.kind and
                (stage.kind~="objective" or stage.objectiveIndex==(row.sharedObjective or row.sideAction and row.sideAction.objectiveIndex)) then return true end
        end
    end
    if navigation and navigation.actions and navigation.actions[navigation.index]==action then
        for i=navigation.index+1,#navigation.actions do
            local stage=navigation.actions[i]
            if stage.kind~="move" and not listed(stage,stage.questId) then return stage,stage.questId,stage.title end
        end
    end
    if A.Navigation and A.Navigation.manual then return end
    if batchSteps then
        for _,step in ipairs(batchSteps) do
            local stage=step.action
            if stage.questId~=action.questId and not listed(stage,stage.questId) then
                return stage,stage.questId,stage.title
            end
        end
    end
    local after=action.kind=="service" or action.kind=="flight" or action.kind=="hearthCast"
    local steps=plan.taskQueue and plan.taskQueue.steps or plan.taskOrder or {}
    for _,step in ipairs(steps) do
        local choice=step.choice or step
        for _,stage in ipairs(step.stage and {step.stage} or choice.stages or {}) do
            local id=stage.questId or choice.questId
            if not state.locked or id==state.locked then
                if after and not listed(stage,id) then return stage,id,choice.title end
                if id==action.questId and stage.kind==action.kind and
                    (not action.objectiveIndex or action.objectiveIndex==stage.objectiveIndex) then after=true end
            end
        end
    end
end

local function deliveryAdvice(state,plan,action,choices,byQuest)
    local advice,ordered,seen,immediate={},{},{},{}
    local leading=true
    local function title(choice)
        return (state.quests[choice.questId] or {}).title or choice.title or ("任务 #"..choice.questId)
    end
    local function recipient(choice)
        local last=choice and choice.stages and choice.stages[#choice.stages]
        local point=last and last.kind=="turnin" and (last.recipient or last.position)
        return point and point.entityName
    end
    local function waiting(id)
        local group=byQuest[id]
        return group and not group.splitDelivery and group.ready<#group.choices and state.locked~=id and group
    end
    for id,choice in pairs(choices) do
        local active=(state.quests or {})[id]
        local name=recipient(choice)
        if active and active.ready and name and not choice.itemShortage and not choice.lowValue and not choice.revisitLevel and not choice.entryBlocked and
            not (state.skipped or {})[id] and not (state.chainDeferred or {})[id] then
            local group=waiting(id)
            if group then
                local pending=0
                for _,other in ipairs(group.choices) do
                    if not (state.quests[other.questId] or {}).ready or (choices[other.questId] or {}).itemShortage then
                        pending=pending+1
                    end
                end
                advice[id]="同组还差 "..pending.." 项，做完一起交"
            else
                local together=byQuest[id]
                advice[id]=together and not together.splitDelivery and together.ready==#together.choices and
                    ("一起交给"..name.."（"..#together.choices.."项）") or ("交付给"..name)
            end
        end
    end
    local function add(choice,stage)
        local id=choice and choice.questId
        if not stage or stage.kind~="turnin" or not id or not (state.quests[id] or {}).ready then leading=false end
        if id and advice[id] and not waiting(id) and not seen[id] and stage and stage.kind=="turnin" then
            ordered[#ordered+1]=choice;seen[id]=true;immediate[id]=leading
        end
    end
    if plan.taskQueue and plan.taskQueue.steps then
        for _,step in ipairs(plan.taskQueue.steps) do
            local choice=step.choice
            add(choice,step.stage or choice and choice.stages and choice.stages[#choice.stages])
        end
    else
        for _,choice in ipairs(plan.taskOrder or {}) do add(choice,choice.stages and choice.stages[#choice.stages]) end
    end
    local current=action and choices[action.questId]
    if not current then return advice end
    local task=current.executionAction or (current.actions or {})[1]
    local turning=action.kind=="turnin" or action.kind=="transit" and task and task.kind=="turnin"
    local summary
    local group=byQuest[current.questId]
    if turning and advice[current.questId] and not waiting(current.questId) then
        local name=recipient(current)
        local batch=not state.locked and group and not group.splitDelivery and group.ready==#group.choices and #group.choices>1
        local nearest=current.distance~=nil
        for id,choice in pairs(choices) do
            if id~=current.questId and advice[id] and not waiting(id) and
                (choice.distance==nil or current.distance==nil or choice.distance<current.distance) then nearest=false end
        end
        summary=batch and ("一起交付：到"..name.."交 "..#group.choices.." 项任务") or
            ((nearest and "就近交付：到" or "顺路先交：到")..name.."交「"..title(current).."」")
        advice[current.questId]=(batch and "本次一起交给" or "现在交给")..name
        local nextName
        for _,choice in ipairs(ordered) do
            local target=recipient(choice)
            if choice.questId==current.questId or batch and byQuest[choice.questId]==group then
                advice[choice.questId]=(batch and "本次一起交给" or "现在交给")..name
            else
                advice[choice.questId]="之后交给"..target.." · 先交「"..title(current).."」"
                if not nextName and target~=name and immediate[choice.questId] then nextName=target end
            end
        end
        if nextName then summary=summary.."；再去"..nextName end
    elseif action.kind=="objective" and (not (state.quests[current.questId] or {}).ready or current.itemShortage) then
        if group and group.ready>0 and waiting(current.questId) then
            summary="同组还差 "..(#group.choices-group.ready).." 项，做完一起交"
        elseif ordered[1] then
            summary="完成当前任务后，到"..recipient(ordered[1]).."交付"
            for _,choice in ipairs(ordered) do advice[choice.questId]="先做「"..title(current).."」，之后交给"..recipient(choice) end
        end
    end
    return advice,summary
end

local function alongTasks(state,plan,action,paused,byQuest)
    local quests=state.quests or {}
    byQuest=byQuest or {}
    -- Nearby work is optional: compare the extra straight-line walk without changing navigation.
    local along={}
    local navigation=A.Navigation
    local target=action and action.position
    if action and navigation and navigation.Target then target=navigation.Target(action) end
    local direct=not paused and not A.error and action and action.questId and
        (action.kind=="accept" or action.kind=="objective" or action.kind=="turnin") and navigation and navigation.Distance and
        navigation:Distance(state.position,target,true)
    local speed=state.runSpeed
    if direct and speed and speed>0 then
        for _,choice in ipairs(plan.taskChoices or {}) do
            local id=choice.questId
            local q=quests[id]
            if id~=action.questId and not (state.skipped or {})[id] and not (state.chainDeferred or {})[id] and
                not choice.lowValue and (not choice.revisitLevel or not q and choice.pickupAction) and
                not choice.acceptBlocked and not choice.entryBlocked and not choice.requireCheck then
                local kind=not q and "accept" or q.ready and not choice.itemShortage and "turnin" or "objective"
                local step=not q and choice.pickupAction or choice.executionAction or (choice.actions or {})[1]
                for _,stage in ipairs(choice.stages or {}) do
                    local objective=q and stage.objectiveIndex and (q.objectives or {})[stage.objectiveIndex]
                    if stage.kind==kind and (not (objective and objective.finished) or stage.itemGain and stage.itemGain>0) then step=stage;break end
                end
                local group=byQuest[id]
                local waiting=kind=="turnin" and group and not group.splitDelivery and group.ready<#group.choices
                local objective=q and step and step.objectiveIndex and (q.objectives or {})[step.objectiveIndex]
                if step and step.kind==kind and step.position and not step.position.areaOnly and not waiting and
                    (not (objective and objective.finished) or step.itemGain and step.itemGain>0) then
                    local approach=navigation:Distance(state.position,step.position,true)
                    local onward=navigation:Distance(step.position,target,true)
                    local atHub=kind=="accept" and (action.kind=="accept" or action.kind=="turnin") and
                        direct<=180 and approach and approach<=180 and onward and onward<=180
                    if approach and onward and approach<=math.max(direct,180) and onward<=math.max(direct,180) and
                        (kind~="objective" or approach<=180) and (atHub or math.max(0,approach+onward-direct)/speed<=20) then
                        along[id]={action=step,distance=approach}
                    end
                end
            end
        end
    end
    if state.position and not paused and not A.error and not state.dead and not state.onTaxi and not state.inInstance and navigation and navigation.Distance then
        local ignored=UI.tracker and UI.tracker.nearby and UI.tracker.nearby.map==state.position.map and UI.tracker.nearby.ignored or {}
        for _,stop in ipairs(plan.flightUnlocks or {}) do
            local key="taxi:"..stop.taxiId
            local distance=navigation:Distance(state.position,stop.position,true)
            if distance and distance<=180 and (state.unlocked or {})[key]==false and not ignored[key] and
                not (state.serviceStop and state.serviceStop.kind=="unlockFlight" and state.serviceStop.taxiId==stop.taxiId) then
                along[key]={action=stop,distance=distance}
            end
        end
    end
    return along
end

function UI.TrackerModel(state,plan,action,paused,along)
    state,plan=state or {},plan or {}
    local tram=action and action.kind=="tram" and action
    if tram then plan,along={},{} end
    local quests=state.quests or {}
    local journey=not paused and not A.error and UI.TrackerJourney(state,action) or nil
    local flight=action and action.kind=="flight" and A.Transport and A.Transport.flight
    local node=flight and A.FlightData and A.FlightData.nodes[flight.toTaxi]
    local flightName=flight and (flight.name or (state.taxiNames or {})[flight.toTaxi] or flight.action and flight.action.toName)
    local town=flightName and (flightName:gsub("，",",")..","):match("^%s*(.-)%s*,")
    local arrival=tram and tram.arrivalPoint or action and action.kind=="hearthCast" and state.hearthPoint or action and action.kind=="transit" and action.position or
        (journey and journey.goal or action or {}).position
    action=journey and journey.goal or action
    if A.Navigation and A.Navigation.StaleAction and A.Navigation.StaleAction(action,state,plan) or
        action and action.questId and UI.QuestStatus(state,action.questId,plan)=="已交付" then action=nil end
    local model={journey=journey,action=action,rows={},objectives={},acceptedCount=0,unacceptedCount=0,title=action and action.title or "正在寻找下一步",kind=action and action.kind,
        instruction=action and UI.ActionText(action,A.settings or {}) or "",questId=action and action.questId}
    local active=action and quests[action.questId]
    if active then
        model.title=active.title or model.title
        for _,objective in ipairs(active.objectives or {}) do
            model.objectives[#model.objectives+1]={text=objective.text or "任务目标",done=objective.finished==true,type=objective.type,targetKind=objective.targetKind,areaTriggerId=objective.areaTriggerId,
                have=objective.numFulfilled,need=objective.numRequired}
        end
    end
    local point
    if A.Navigation and A.Navigation.Target then point=A.Navigation.Target(action)
    else point=action and action.position end
    if point then
        local recipient=action.kind=="turnin" and action.recipient
        model.destination=point.entityName or recipient and recipient.entityName
    end
    if action and action.itemGain and action.itemGain>0 then
        local have=(state.bags or {})[action.targetId] or 0
        local total,seen=0,{}
        for _,choice in ipairs(plan.taskOrder or plan.taskChoices or {}) do
            local id=choice.questId
            if quests[id] and not seen[id] and not choice.lowValue and not choice.revisitLevel and not choice.entryBlocked and
                not (state.skipped or {})[id] and not (state.chainDeferred or {})[id] and (not state.locked or state.locked==id) then
                seen[id]=true
                local last=choice.stages and choice.stages[#choice.stages]
                for _,requirement in ipairs(last and last.itemRequirements or {}) do
                    if requirement.targetId==action.targetId then total=total+(requirement.need or 0) end
                end
            end
        end
        local stock=plan.itemStock and (plan.itemStock[action.targetId] or 0) or have
        local need=math.max(stock+action.itemGain,total)
        local limit=A.TaskGuide and A.TaskGuide.ItemLimit and A.TaskGuide.ItemLimit(action.targetId,state)
        if limit then need=math.min(need,limit) end
        local objective=action.objectiveIndex and model.objectives[action.objectiveIndex]
        if objective and objective.type=="item" then
            objective.done,objective.have,objective.need=false,have,need
            objective.purchase=action.purchase
        else
            model.objectives[#model.objectives+1]={text=action.position and action.position.targetName or action.text or "本次所需物品",
                type="item",done=false,have=have,need=need,purchase=action.purchase}
        end
    end
    if plan.preparingQuest then model.hint="先完成「"..plan.preparingQuest.title.."」的前置准备"
    elseif action and action.pickupResume then model.hint="顺路接取，与「"..action.pickupResume.."」一并安排"
    elseif action and action.referenceFlight then model.hint="从当前飞行点前往任务区域，落地后继续目标指引"
    elseif plan.serviceDeferred then model.hint=plan.serviceDeferred
    elseif plan.taskBatch and plan.taskBatch.waiting then model.hint="等队时先做附近任务；队伍就绪后继续副本"
    elseif plan.taskBatch then model.hint=plan.taskBatch.title.." · 任务安排剩余 "..plan.taskBatch.remaining.." 项"
    elseif state.locked and action and state.locked==action.questId then model.hint="按你锁定的任务继续" end
    local groups,byQuest={},{}
    local choices={}
    for _,choice in ipairs(plan.taskOrder or {}) do choices[choice.questId]=choice end
    for _,choice in ipairs(plan.taskChoices or {}) do
        choices[choice.questId]=choices[choice.questId] or choice
    end
    if action and choices[action.questId] then
        local choice=choices[action.questId]
        model.choice=choice
        model.metrics=metrics(choice,journey)
        model.unlock=choice.unlock
        local pick=choice.rewardPick
        if (A.settings or {}).rewardAdvice~=false and not paused and not (state.skipped or {})[action.questId] and
            not (state.chainDeferred or {})[action.questId] and pick and
            (model.kind=="turnin" or model.kind=="accept" and pick.upgrade.delta>0) then model.reward=pick end
    end
    if A.TaskGuide then groups,byQuest=A.TaskGuide.DeliveryGroups(plan.taskPool or plan.taskChoices,state,plan.taskOrder) end
    local currentGroup=action and byQuest[action.questId]
    model.includesCurrent=currentGroup~=nil
    if currentGroup and not state.locked then
        model.hint=currentGroup.splitDelivery and "物品持有上限限制：先交付已备齐任务，再继续收集" or
            currentGroup.ready==#currentGroup.choices and "整组已完成，前往 "..currentGroup.title.." 集中交付" or
            string.format("同组已完成 %d/%d，先做完剩余任务再集中交付",currentGroup.ready,#currentGroup.choices)
    end
    local shared,sharedKind
    if not paused and A.TaskGuide and A.TaskGuide.SharedObjectives then shared,sharedKind=A.TaskGuide.SharedObjectives(action,plan.taskChoices,state) end
    local sharedByQuest={}
    if shared then
        local titles={}
        for _,entry in ipairs(shared) do
            sharedByQuest[entry.questId]=entry.objectiveIndex
            if entry.questId~=action.questId then titles[#titles+1]="「"..(quests[entry.questId].title or (choices[entry.questId] or {}).title or ("任务 #"..entry.questId)).."」" end
        end
        local summary=(sharedKind=="item" and "一并收集：" or "一起推进：")..table.concat(titles,"、",1,math.min(2,#titles))..(#titles>2 and ("等 "..#titles.." 项任务") or "")
        model.hint=(model.hint and (model.hint.."\n") or "")..summary
    end
    local planned={}
    for i,step in ipairs(plan.taskQueue and plan.taskQueue.steps or plan.taskOrder or {}) do
        local choice=step.choice or step
        if choice.questId and not planned[choice.questId] then planned[choice.questId]=i end
    end
    local batchSteps=plan.taskBatch and A.Dungeon.TaskBatchFrontier(plan,choices)
    local batchPhases={}
    for i,step in ipairs(batchSteps or {}) do
        planned[step.action.questId]=i
        batchPhases[step.action.questId]=step.phase
    end
    model.batchPhases=batchPhases
    local batchMembers=plan.taskBatch and not plan.taskBatch.waiting and state.taskBatch and
        plan.taskBatch.id==state.taskBatch.id and state.taskBatch.baselines
    local seen={}
    if action and action.questId and not currentGroup then seen[action.questId]=true end
    local function add(id,source)
        if not id or seen[id] then return end
        seen[id]=true
        local q=quests[id]
        local status=UI.QuestStatus(state,id,plan)
        if status=="已交付" then return end
        local candidate=choices[id]
        if candidate and candidate.lowValue and not (q and batchMembers and batchMembers[id]) then return end
        if q then model.acceptedCount=model.acceptedCount+1 else model.unacceptedCount=model.unacceptedCount+1 end
        if not q and not (planned[id] or along and along[id] or batchMembers and batchMembers[id]) then return end
        local step=source or (candidate and candidate.actions[1]) or {}
        local deferred=(state.skipped or {})[id] or (state.chainDeferred or {})[id]
        local pickup=candidate and candidate.actions[1] or step
        for _,stage in ipairs(candidate and candidate.stages or {}) do
            if stage.kind=="accept" then pickup=stage;break end
        end
        local pickupPlace=not q and destination(pickup)
        local counts={}
        for index,objective in ipairs(q and q.objectives or {}) do
            if (not sharedByQuest[id] or sharedByQuest[id]==index) and objective.numRequired and objective.numRequired>0 then
                local count=string.format("%d/%d",objective.numFulfilled or 0,objective.numRequired)
                local label=objective.text
                counts[#counts+1]=label and label~="" and (label:find("%d+%s*/%s*%d+") and label or label.." · "..count) or count
            end
        end
        model.rows[#model.rows+1]={questId=id,title=q and q.title or candidate and candidate.title or step.title or ("任务 #"..id),
            kind=q and (q.ready and "turnin" or "objective") or "accept",
            accepted=q~=nil,status=status,metrics=metrics(candidate),
            progress=q and (q.ready and "目标已完成，前往交付" or (#counts>0 and table.concat(counts," · ") or "查看任务日志中的目标")) or
                (candidate and candidate.acceptBlocked or candidate and candidate.requireCheck and "先确认任务当前是否开放" or
                    (pickup.startItemId or pickup.position and pickup.position.startItemId) and pickup.text or pickupPlace and ("接取："..pickupPlace) or "先接取，再推进任务目标"),deferred=deferred,candidate=candidate,
            shared=sharedByQuest[id] and true,sharedObjective=sharedByQuest[id]}
        if sharedByQuest[id] then
            local row=model.rows[#model.rows]
            row.progress=(sharedKind=="item" and "一并收集 · " or "一起推进 · ")..row.progress
        end
        if candidate and candidate.entryBlocked then
            model.rows[#model.rows].progress=candidate.entryBlocked
        end
        if not q and batchPhases[id] and not (candidate and candidate.acceptBlocked) then
            local prefix=batchPhases[id]=="inside" and "副本内接取" or "入本前接取"
            model.rows[#model.rows].progress=prefix.." · "..(pickupPlace or pickup.text or "任务发布者")
        end
    end
    if plan.best then
        for i=A.Navigation and A.Navigation.index or 1,#(plan.best.actions or {}) do
            local step=plan.best.actions[i]
            if step.questId then planned[step.questId]=planned[step.questId] or i end
            if step.kind~="move" then add(step.questId,step) end
        end
    end
    along=along or alongTasks(state,plan,action,paused,byQuest)
    model.along,model.deliveryGroups=along,byQuest
    for _,choice in ipairs(plan.taskChoices or {}) do
        local side=along[choice.questId]
        if side then add(choice.questId,side.action) end
    end
    for _,choice in ipairs(plan.taskOrder or plan.taskChoices or {}) do
        add(choice.questId,choice.executionAction or choice.actions[1])
    end
    local rest={}
    for id in pairs(quests) do if not seen[id] then rest[#rest+1]=id end end
    table.sort(rest);for _,id in ipairs(rest) do add(id) end
    for _,choice in ipairs(plan.taskChoices or {}) do add(choice.questId,choice.actions[1]) end
    local ranked=model.rows
    local grouped,emitted={},{}
    local function emit(group)
        if not group or emitted[group] then return end
        emitted[group]=true
        local first=true
        for _,row in ipairs(ranked) do
            if byQuest[row.questId]==group then
                if first then
                    row.groupTitle=string.format("%s · 已完成 %d/%d",group.title,group.ready,#group.choices)
                    first=false
                end
                if quests[row.questId] and quests[row.questId].ready then
                    row.progress=group.splitDelivery and (row.candidate and row.candidate.itemShortage and
                        "等待前项交付后再收集" or "已备齐 · 可先交付") or
                        row.candidate and row.candidate.itemShortage and "共用物品不足 · 先补齐再一起交付" or
                        (group.ready==#group.choices and "全部完成 · 一起交付" or "已完成 · 等同组任务一起交付")
                end
                grouped[#grouped+1]=row
            end
        end
    end
    emit(currentGroup)
    for _,row in ipairs(ranked) do
        if byQuest[row.questId] then emit(byQuest[row.questId]) else grouped[#grouped+1]=row end
    end
    model.rows=grouped
    if model.kind=="flight" or model.kind=="hearthCast" then model.hint=nil end
    local deliveries,summary=deliveryAdvice(state,plan,action,choices,byQuest)
    model.deliverySummary=summary
    local handins=not (paused or A.error) and (tram or not (state.inInstance or state.taskBatch)) and A.TaskGuide and
        A.TaskGuide.ReadyTurnIns and A.Data and A.Data.Target and A.TaskGuide.ReadyTurnIns(state,A.Data,tram and arrival) or {}
    local arrivalRow
    for _,row in ipairs(model.rows) do
        row.delivery=deliveries[row.questId]
        local handin=handins[row.questId]
        if handin and not row.deferred and not (row.candidate and (row.candidate.itemShortage or row.candidate.entryBlocked)) then
            local point=handin.position
            local zone=town and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(point.map)
            local landing=node and A.Navigation.hbd and A.Flights.Position(node,point.map,A.Navigation.hbd)
            local distance=landing and A.Navigation.Distance and A.Navigation:Distance(landing,point,true)
            -- Adjacent zones overlap on the world map. A city name or the landing's immediate vicinity identifies a stop.
            local flyingHere=zone and zone.name==town or distance and distance<=180
            local here=not flight and not tram and state.position and point.map==state.position.map
            local arriving=flyingHere or not node and arrival and arrival.map==point.map and not here
            if tram and arriving then distance=A.Navigation:Distance(arrival,point,true) end
            row.turnInAction=handin
            row.deliveryPriority=arriving and 1 or here and 2 or 3
            if arriving or not planned[row.questId] and not byQuest[row.questId] then
                row.delivery=(arriving and "抵达后交付" or "可交付").." · "..(destination(handin) or row.title)
            end
            if arriving and (flight or tram) and not state.locked and (not arrivalRow or
                (distance or math.huge)<arrivalRow.distance or (distance or math.huge)==arrivalRow.distance and row.questId<arrivalRow.questId) then
                arrivalRow={questId=row.questId,action=handin,title=row.title,distance=distance or math.huge}
            end
        end
        row.atStop=not paused and not A.error and not state.locked and not row.deferred and
            model.kind=="turnin" and row.kind=="turnin" and currentGroup~=nil and byQuest[row.questId]==currentGroup and
            not (row.candidate and row.candidate.itemShortage)
        local side=along[row.questId]
        row.along=not paused and not A.error and not row.deferred and row.questId~=model.questId and not row.atStop and
            (row.shared or side~=nil) or false
        row.sideAction=side and side.action
        if row.along and side then row.kind=side.action.kind end
        row.alongDistance=row.shared and 0 or side and side.distance
        row.planOrder=planned[row.questId]
    end
    if action and not paused and not A.error then
        if arrivalRow then
            model.nextOnArrival=tram and "下车后" or "落地后"
            model.nextStep,model.nextId,model.nextTitle=arrivalRow.action,arrivalRow.questId,arrivalRow.title
        else model.nextStep,model.nextId,model.nextTitle=nextAction(action,plan,state,model.rows,batchSteps) end
        model.nextChoice=choices[model.nextId]
    end
    local visible={}
    for _,row in ipairs(model.rows) do
        local candidate=row.candidate or {}
        local eligible=not row.deferred and not candidate.lowValue and not candidate.revisitLevel and not candidate.acceptBlocked and
            not candidate.entryBlocked and not candidate.requireCheck
        local member=batchMembers and batchMembers[row.questId] and not row.deferred and
            (row.accepted or candidate.acceptBlocked and not candidate.requireCheck and not candidate.entryBlocked)
        local point=row.turnInAction and row.turnInAction.position
        local station=not tram or point and (arrival and point.map==arrival.map or not arrival and A.Transport.IsTramStation(point.map))
        if station and (row.questId==model.questId or row.atStop or row.along or row.questId~=model.nextId and
            (member or eligible and (row.planOrder or row.turnInAction or not action and not batchMembers and row.accepted))) then
            visible[#visible+1]=row
        end
    end
    for _,stop in ipairs(plan.flightUnlocks or {}) do
        local side=along["taxi:"..stop.taxiId]
        if side then
            visible[#visible+1]={kind="unlockFlight",title="开通飞行点 · "..stop.title,status="未开通",along=true,
                alongDistance=side.distance,serviceStop=stop,progress="与飞行管理员交谈"}
        end
    end
    table.sort(visible,function(a,b)
        local function order(row)
            return row.questId and row.questId==model.questId and 0 or row.atStop and 1 or row.along and 2 or 3
        end
        local ar,br=order(a),order(b)
        if ar~=br then return ar<br end
        if ar==3 and a.deliveryPriority~=b.deliveryPriority then return (a.deliveryPriority or 4)<(b.deliveryPriority or 4) end
        if ar==2 and a.alongDistance~=b.alongDistance then return (a.alongDistance or 0)<(b.alongDistance or 0) end
        if a.planOrder~=b.planOrder then return (a.planOrder or math.huge)<(b.planOrder or math.huge) end
        return (a.questId or -a.serviceStop.taxiId)<(b.questId or -b.serviceStop.taxiId)
    end)
    -- Only actionable stops belong between the current step and the end of this route.
    local needsPreview=not model.nextStep
    model.otherCount=0
    for _,row in ipairs(visible) do
        local other=row.accepted and row.questId~=model.questId and not (row.atStop or row.along or
            row.deliveryPriority==1 or batchMembers and batchMembers[row.questId])
        if other and needsPreview and (row.planOrder or not action) then other=false;needsPreview=false end
        row.otherAccepted=other
        if other then model.otherCount=model.otherCount+1 end
    end
    model.rows=visible
    if plan.taskBatch and state.taskBatch and plan.taskBatch.id==state.taskBatch.id and
        not (paused or A.error or state.inInstance or state.dead) and plan.revision==state.revision then
        model.bindingReminder=plan.taskBatch.bindingReminder
    end
    if not action then
        if plan.complete then model.title="已达到 60 级";model.instruction="本次升级目标已完成。"
        elseif A.planningResumeAt then
            model.title="停下后更新行程";model.instruction="脱离战斗并停下后，自动安排下一步。"
        elseif (A.jobs and A.jobs.plan) or (plan.revision and plan.revision~=state.revision) then
            model.title="正在安排行程";model.instruction="下方显示已接任务与进度。"
        elseif plan.selectionBlocked then model.title="所选行程等待处理";model.instruction=plan.selectionBlocked
        elseif not A.indexReady then model.title="正在整理任务";model.instruction="任务数据加载后显示当前步骤。"
        else model.title="选择下一项任务";model.instruction="右键任务可选择优先做，左键查看详情。" end
    end
    if paused then model.instruction="引导已暂停，右键标题栏可继续引导。";model.hint=nil;model.deliverySummary=nil end
    if A.error then model.title="需要处理";model.instruction=A.error;model.hint=nil;model.deliverySummary=nil end
    return model
end

local function text(parent,size,color)
    return UI:Text(parent,size,color or palette.white,"OUTLINE")
end

local function gearLinks(value)
    local links={}
    for slot=1,19 do
        local item=value.upgrade.replacements[slot]
        if item then links[#links+1]=item.link or item.name or ("物品 #"..item.id) end
    end
    return table.concat(links," + ")
end

local function noticeLine(parent,size,color)
    local line=CreateFrame("Frame",nil,parent)
    line.text=text(line,size or "body",color or palette.green);line.text:SetPoint("TOPLEFT");line.text:SetPoint("TOPRIGHT")
    line:SetHyperlinksEnabled(true)
    line:SetScript("OnHyperlinkClick",function(_,link,label,button)
        local id=link:match("^quest:(%d+)")
        if id then UI:QuestClick(tonumber(id),button) else SetItemRef(link,label,button) end
    end)
    local function showLink(owner,link)
        GameTooltip:SetOwner(owner,"ANCHOR_LEFT");GameTooltip:SetHyperlink(link)
        if owner.advice then
            local upgrade=owner.advice.upgrade
            local _,label=A.Gear.Model(A.state)
            GameTooltip:AddLine(string.format("%s · 属性评分 %.1f → %.1f",label,upgrade.oldScore,upgrade.newScore),0.42,0.85,0.60,true)
            local links=gearLinks(owner.advice)
            if links~=owner.advice.item.link then GameTooltip:AddLine("换装搭配："..links,1,1,1,true) end
        end
        if owner.hint then GameTooltip:AddLine(owner.hint,unpack(palette.muted)) end
        GameTooltip:Show()
        if link:match("^item:") and GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
    end
    line:SetScript("OnHyperlinkEnter",showLink)
    line:SetScript("OnEnter",function(owner)
        if owner.details then
            GameTooltip:SetOwner(owner,"ANCHOR_LEFT");GameTooltip:SetText(owner.details,1,1,1,true);GameTooltip:Show()
        elseif owner.advice then showLink(owner,owner.advice.item.link or ("item:"..owner.advice.item.id)) end
    end)
    line:SetScript("OnLeave",function() GameTooltip:Hide() end)
    line:SetScript("OnHyperlinkLeave",function() GameTooltip:Hide() end)
    return line
end

function UI:ClassReminderMenu(owner)
    GameTooltip:Hide()
    self:Menu(owner,function(_,menu)
        for _,spell in ipairs(A.state.trainableSpells or {}) do
            menu:CreateButton(spell.name.." · "..spell.level.."级",function() SetItemRef("spell:"..spell.id,spell.link,"LeftButton") end)
        end
        menu:CreateButton("查看职业任务",function() self.details:Show();self:SelectTab(9) end)
    end)
end

function UI.DungeonReminders(state,plan)
    if A.settings.dungeons==false or A.char.paused or A.error or state.inInstance or state.taskBatch or state.gearTarget then return {} end
    return plan.dungeonChoices or (plan.suggestedDungeon and {plan.suggestedDungeon}) or {}
end

local function dungeonRewardSummary(candidate)
    local rewards=candidate.availableRewards
    if not rewards or rewards.count==0 then return candidate.rewards.count.."项任务" end
    return rewards.count.."项任务 · 经验 "..UI.DungeonXPText(rewards)
end

function UI:DungeonReminderMenu(owner)
    GameTooltip:Hide()
    self:Menu(owner,function(_,menu)
        for _,candidate in ipairs(self.DungeonReminders(A.state,A.plan or {})) do
            local d=A.DungeonCatalog and A.DungeonCatalog.entries[candidate.dungeonId]
            local range=d and A.DungeonCatalog.recommendedLevels and A.DungeonCatalog.recommendedLevels[d.instanceId]
            local levels=range and string.format(" · %d—%d级",range[1],range[2]) or ""
            menu:CreateButton(candidate.title..levels.." · "..dungeonRewardSummary(candidate)..
                (candidate.recommendation and " · "..candidate.recommendation or ""),function()
                self.Dungeon.selected=candidate.dungeonId;self.details:Show();self:SelectTab(4)
            end)
        end
        menu:CreateButton("查看全部地下城",function() self.details:Show();self:SelectTab(4) end)
        menu:CreateButton("本级稍后提醒",function()
            self.tracker.dungeons.dismissedLevel=A.state.level;self:RenderTracker()
        end)
    end)
end

local function questTooltip(owner)
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    if owner==UI.tracker.questTitle and UI.tracker.instanceRoster then
        GameTooltip:SetText(UI.tracker.model.dungeonName)
        GameTooltip:AddLine("点击查看任务详情",1,1,1,true);GameTooltip:Show();return
    end
    if owner.serviceStop then
        GameTooltip:SetText("开通飞行点 · "..owner.serviceStop.title)
        GameTooltip:AddLine("左键：导航到飞行管理员\n右键：导航或暂不提示",1,1,1,true)
        GameTooltip:Show();return
    end
    if owner.dungeonId then
        GameTooltip:SetText("左键：查看副本任务")
        GameTooltip:AddLine("右键：安排整组任务",1,1,1,true);GameTooltip:Show();return
    end
    local quest=owner.questId and (A.state.quests or {})[owner.questId]
    GameTooltip:SetText(quest and quest.title or owner.candidate and owner.candidate.title or "当前步骤")
    if owner.detail then GameTooltip:AddLine(owner.detail,0.94,0.91,0.83,true)
    elseif owner.progress then GameTooltip:AddLine(owner.progress:GetText(),0.94,0.91,0.83,true) end
    if owner.metrics then GameTooltip:AddLine(owner.metrics,1,0.83,0.45,true) end
    if owner.questId then GameTooltip:AddLine("左键查看任务详情\n右键导航或选择任务操作\nShift+左键插入任务链接",1,1,1,true) end
    GameTooltip:Show()
end

function UI:PickTrackerFlight(target)
    for _,stop in ipairs(A.Services:Choices("unlockFlight")) do
        if stop.taxiId==target.taxiId then
            local ok,why=A.Services:Pick(stop,A.state.revision)
            if not ok then A:Message(why) end
            return
        end
    end
    self:RenderTracker()
end

function UI:TrackerMenu(owner)
    local id,candidate,revision=owner.questId,owner.candidate,owner.revision
    local serviceStop=owner.serviceStop
    local action=owner==self.tracker.questTitle and not self.tracker.instanceRoster and self.tracker.action
    GameTooltip:Hide()
    self:Menu(owner,function(_,menu)
        if serviceStop then
            menu:CreateButton("导航到飞行管理员",function() self:PickTrackerFlight(serviceStop) end)
            menu:CreateButton("暂不提示此飞行点",function()
                self.tracker.nearby.ignored["taxi:"..serviceStop.taxiId]={count=2}
                self:RenderTracker()
            end)
        elseif owner.dungeonId then
            menu:CreateButton("安排整组任务",function()
                local ok,why=A.Selection.CanChoose(candidate,revision)
                if ok then ok,why=A.Dungeon:StartTaskBatch(owner.dungeonId) end
                if not ok then A:Message(why) end
            end)
        elseif action and A.Navigation.manual then
            menu:CreateButton("返回任务",function() A.Navigation:ClearManual() end)
        elseif action and action.kind=="service" and action.serviceKind=="repair" then
            menu:CreateButton("忽略维修",function() A.Supplies:IgnoreRepair() end)
        elseif id then
            local step=owner.mapAction or owner.pickupAction or owner.dungeonAction or owner.turnInAction
            local point=owner.mapAction and A.Navigation.Target and A.Navigation.Target(owner.mapAction)
            if point and C_Map and C_Map.OpenWorldMap then
                menu:CreateButton("在地图上查看位置",function() C_Map.OpenWorldMap(point.map) end)
            end
            menu:CreateButton("导航到此任务",function()
                if step and A.Navigation:Navigate(step) then return end
                if not A.Navigation:NavigateQuest(id) then self:QuestClick(id,"RightButton") end
            end):SetEnabled(not owner.deferred)
            menu:CreateButton("查看任务详情",function() self:QuestClick(id,"RightButton") end)
            local choose=menu:CreateButton(candidate and candidate.unlock and "切换到解锁任务线" or "优先做此任务",function()
                local ok,why
                if candidate then ok,why=A.Selection:Lock(candidate,revision)
                else ok,why=A.Selection:LockQuest(id) end
                if not ok then A:Message(why) end
            end)
            choose:SetEnabled(not owner.deferred and (not candidate or A.Selection.CanChoose(candidate,revision)==true))
        end
        local label,change,canIgnore=self.QuestDeferral(id)
        if label then menu:CreateButton(label,function() change(A.Selection,id) end) end
        if canIgnore then menu:CreateButton("忽略此任务",function() A.Selection:Skip(id,true) end) end
        if A.char.taskBatch or A.char.locked or A.char.itinerary then
            menu:CreateButton(A.char.taskBatch and "返回正常练级" or "恢复自动安排",function()
                local ok,why=A.Selection:Automatic();if not ok then A:Message(why) end
            end)
        end
        if A.char.serviceStop then
            menu:CreateButton("取消服务，继续任务",function() A.Services:Cancel() end)
        end
        if owner==self.frame or not id and not owner.dungeonId then
            menu:CreateButton(A.char.paused and "继续引导" or "暂停引导",function() A:TogglePause() end)
            menu:CreateButton("详细面板"..(self.tracker.experience:IsShown() and "" or " · "..(self.tracker.experience:GetText() or "")),function() self:ToggleDetails() end)
            if next(A.char.ignoredGear or {}) then
                menu:CreateButton("恢复装备提醒",function() A.char.ignoredGear={};self:RenderTracker() end)
            end
            if A.char.classReminderLevel then
                menu:CreateButton("恢复职业提醒",function() A.char.classReminderLevel=nil;self:RenderTracker() end)
            end
            menu:CreateButton(A.settings.targets~=false and "隐藏目标辅助" or "显示目标辅助",function()
                A:SetOption("targets",A.settings.targets==false)
            end)
            local scale=A.settings.fontScale or 1
            local smaller,larger
            for _,value in ipairs({0.85,1,1.1,1.2}) do
                if value<scale then smaller=value
                elseif value>scale and not larger then larger=value end
            end
            local function fontOption(label,value)
                menu:CreateButton(label..(value and string.format(" · %d%%",math.floor(value*100+0.5)) or ""),function()
                    A:SetOption("fontScale",value)
                    self.Settings:Refresh()
                end):SetEnabled(value~=nil)
            end
            fontOption("放大字体",larger)
            fontOption("缩小字体",smaller)
            menu:CreateButton("对齐小地图",function()
                A.settings.trackerDocked=true;A.settings.position=nil;self:LayoutCard()
            end)
            menu:CreateButton("恢复自动尺寸",function()
                A.settings.trackerWidth=0;A.settings.trackerHeight=0;self:LayoutTracker()
            end)
            menu:CreateButton(self.folded and "展开任务列表" or "收起任务列表",function()
                self.folded=not self.folded;self:LayoutCard()
            end)
        end
    end)
end

function UI:CreateTracker()
    local f=CreateFrame("Frame","AiLevelingMain",UIParent)
    self.frame,self.tracker=f,{}
    f:SetSize(280,280);f:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-24,-260)
    local p=A.settings.position
    if p and A.settings.trackerDocked==false then f:ClearAllPoints();f:SetPoint(p[1],UIParent,p[2],p[3],p[4]) end
    self:Movable(f,"position")
    f:SetScript("OnMouseUp",function(_,button) if button=="RightButton" then self:TrackerMenu(f) end end)
    f:SetScript("OnEnter",function()
        GameTooltip:SetOwner(f,"ANCHOR_TOP");GameTooltip:SetText("AILeveling")
        GameTooltip:AddLine("左键拖动面板，右下角调整宽高\n右键：字号、暂停、收起与详细面板",1,1,1,true);GameTooltip:Show()
    end)
    f:SetScript("OnLeave",function() GameTooltip:Hide() end)
    if self.daylight then self:DaylightShell(f,palette.hud[4])
    else self:Rounded(f,spacing.radius);f:SetBackdropColor(unpack(palette.hud));f.material:Hide() end
    local T=self.tracker
    T.nearby=CreateFrame("Button",nil,f,"BackdropTemplate")
    local notice=T.nearby
    notice:SetPoint("TOP",UIParent,"TOP",0,-150);notice:SetClampedToScreen(true);notice:SetFrameStrata("HIGH")
    notice:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,
        insets={left=1,right=1,top=1,bottom=1}})
    if self.daylight then notice:SetBackdrop(nil);self:DaylightShell(notice,palette.hud[4])
    else notice:SetBackdropColor(unpack(palette.hud));notice:SetBackdropBorderColor(unpack(palette.line)) end
    notice.mark=notice:CreateTexture(nil,"ARTWORK");notice.mark:SetColorTexture(unpack(palette.gold))
    notice.icon=notice:CreateTexture(nil,"ARTWORK")
    notice.heading=text(notice,"caption",palette.gold);notice.heading:SetText("顺便完成")
    notice.body=text(notice,"body",palette.white);notice.body:SetMaxLines(1)
    notice.ignored={};notice:RegisterForClicks("LeftButtonUp","RightButtonUp")
    notice:SetScript("OnEnter",function()
        GameTooltip:SetOwner(notice,"ANCHOR_BOTTOM");GameTooltip:SetText("顺便完成")
        GameTooltip:AddLine(notice.title or "",1,1,1,true)
        GameTooltip:AddLine("点击让箭头指向此处",unpack(palette.gold))
        GameTooltip:AddLine("右键：在这附近忽略（忽略两次后，本地区内不再提示）。",palette.muted[1],palette.muted[2],palette.muted[3],true)
        GameTooltip:Show()
    end)
    notice:SetScript("OnLeave",function() GameTooltip:Hide() end)
    notice:SetScript("OnHide",function() GameTooltip:Hide() end)
    notice:SetScript("OnClick",function(_,button)
        local key=notice.key
        self:UpdateNearby()
        if not key or notice.key~=key then return end
        local position=A.state.position
        if button=="RightButton" then
            local old=notice.ignored[key]
            notice.ignored[key]={count=(old and old.count or 0)+1,position={map=position.map,x=position.x,y=position.y}}
        else
            A.Navigation:Navigate(notice.action)
        end
        GameTooltip:Hide();self:UpdateNearby()
    end)
    notice:Hide()
    f:SetScript("OnUpdate",function(_,elapsed)
        T.nearbyElapsed=(T.nearbyElapsed or 0)+elapsed
        if T.nearbyElapsed>=1 then T.nearbyElapsed=0;self:UpdateTrackerDynamic() end
    end)
    f:RegisterEvent("DISPLAY_SIZE_CHANGED");f:RegisterEvent("UI_SCALE_CHANGED")
    f:SetScript("OnEvent",function() self:LayoutTracker() end)
    f:SetResizable(true);f:SetClampedToScreen(true)
    T.resize=CreateFrame("Button",nil,f);T.resize:SetSize(18,18);T.resize:SetPoint("BOTTOMRIGHT",-2,2)
    for _,length in ipairs({6,11}) do
        local line=T.resize:CreateLine(nil,"OVERLAY");line:SetThickness(2);line:SetColorTexture(unpack(palette.gold))
        line:SetStartPoint("BOTTOMRIGHT",T.resize,-length,2);line:SetEndPoint("BOTTOMRIGHT",T.resize,-2,length)
    end
    local function finishSizing()
        if not T.resizing then return end
        f:StopMovingOrSizing();T.resizing=nil;T.resize:SetScript("OnUpdate",nil)
        A.settings.trackerWidth,A.settings.trackerHeight=f:GetSize()
        local point,_,relative,x,y=f:GetPoint()
        A.settings.position={point,relative,x,y}
        self:LayoutTracker()
    end
    T.resize:SetScript("OnMouseDown",function(_,button)
        if button~="LeftButton" or A.settings.lockWindow or self.folded or InCombatLockdown() then return end
        GameTooltip:Hide();A.settings.trackerDocked=false;T.resizing=true;f:StartSizing("BOTTOMRIGHT")
        T.resize:SetScript("OnUpdate",function()
            if A.settings.lockWindow or InCombatLockdown() then finishSizing() else self:LayoutTracker() end
        end)
    end)
    T.resize:SetScript("OnMouseUp",finishSizing);T.resize:SetScript("OnHide",finishSizing)
    T.resize:SetScript("OnEnter",function()
        GameTooltip:SetOwner(T.resize,"ANCHOR_LEFT");GameTooltip:SetText("调整宽高")
        GameTooltip:AddLine("按住左键拖动，松开保存尺寸",1,1,1,true);GameTooltip:Show()
    end)
    T.resize:SetScript("OnLeave",function() GameTooltip:Hide() end)
    T.content=CreateFrame("Frame",nil,f);T.content:SetPoint("TOPLEFT",spacing.padding,-spacing.padding)
    T.location=text(T.content,self.daylight and "heading" or "title",palette.white)
    T.location:SetPoint("TOPLEFT");T.location:SetMaxLines(2)
    T.area=text(T.content,"caption",palette.muted);T.area:SetMaxLines(1)
    T.experience=text(T.content,"caption",palette.muted);T.experience:SetJustifyH("RIGHT")
    T.collapse=self:Button(T.content,"−",20,function() self.folded=not self.folded;self:LayoutTracker() end,"body")
    T.menu=self:Button(T.content,"≡",22,function() self:TrackerMenu(f) end,"body")
    for _,button in ipairs({T.collapse,T.menu}) do
        button.baseColor={0,0,0,0};button:SetBackdropColor(0,0,0,0);button.text:SetTextColor(unpack(palette.muted))
        button:HookScript("OnEnter",function()
            button:SetBackdropColor(unpack(palette.rowHover))
            GameTooltip:SetOwner(button,"ANCHOR_TOP");GameTooltip:SetText(button==T.menu and "行程菜单" or "收起／展开")
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave",function() button:SetBackdropColor(0,0,0,0);GameTooltip:Hide() end)
    end
    T.divider=T.content:CreateTexture(nil,"BACKGROUND");T.divider:SetColorTexture(unpack(palette.border))
    T.headerLine=T.content:CreateTexture(nil,"ARTWORK");T.headerLine:SetColorTexture(unpack(palette.gold))
    T.headerLine:SetPoint("LEFT",T.divider,"LEFT")
    T.career=noticeLine(T.content,"body",palette.white)
    T.career.heading=text(T.career,"caption",palette.gold)
    T.career.view=self:Button(T.career,"查看",48,function() self:ClassReminderMenu(T.career) end,"caption")
    T.career.train=self:Button(T.career,"去训练",64,function()
        local rows=A.Services:Choices("classTrain")
        local ok,why
        if rows[1] then ok,why=A.Services:Pick(rows[1],A.state.revision)
        else why="没有找到本职业训练师的位置" end
        if not ok then A:Message(why) end
    end,"caption")
    T.career.later=self:Button(T.career,"稍后",48,function()
        A.char.classReminderLevel=A.state.level;self:RenderTracker()
    end,"caption")
    for _,button in ipairs({T.career.view,T.career.train,T.career.later}) do
        button.baseColor={0,0,0,0};button:SetBackdropColor(0,0,0,0)
    end
    T.career.later:HookScript("OnEnter",function(button)
        GameTooltip:SetOwner(button,"ANCHOR_TOP");GameTooltip:SetText("本级不再提醒；可在行程菜单恢复");GameTooltip:Show()
    end)
    T.career.later:HookScript("OnLeave",function() GameTooltip:Hide() end)
    T.dungeons=CreateFrame("Button",nil,T.content)
    T.dungeons.heading=text(T.dungeons,"caption",palette.muted)
    T.dungeons.text=text(T.dungeons,"body",palette.blue)
    T.dungeons.text:SetMaxLines(2)
    T.dungeons:SetScript("OnClick",function()
        if A.char.taskBatch then
            local ok,why=A.Selection:Automatic()
            if not ok then A:Message(why) end
            self:RenderTracker()
        else self:DungeonReminderMenu(T.dungeons) end
    end)
    T.dungeons:SetScript("OnEnter",function()
        GameTooltip:SetOwner(T.dungeons,"ANCHOR_LEFT")
        if A.char.taskBatch then
            GameTooltip:SetText("返回正常练级")
            GameTooltip:AddLine("结束这次副本行程，按当前位置重新安排练级任务。已接任务和进度保留。",1,1,1,true)
            GameTooltip:Show();return
        end
        GameTooltip:SetText("副本建议")
        local candidate=T.dungeons.candidate
        if candidate and candidate.recommendation then
            GameTooltip:AddLine(candidate.recommendation.." · 当前可做 "..candidate.availableTasks.."项",1,1,1,true)
        end
        if candidate and candidate.rewards.prepare>0 then
            GameTooltip:AddLine(candidate.rewards.prepare.."项任务需先完成前置。",unpack(palette.gold))
        end
        GameTooltip:AddLine("点击选择副本，查看待接任务与前置，再安排整组行程。",1,1,1,true);GameTooltip:Show()
    end)
    T.dungeons:SetScript("OnLeave",function() GameTooltip:Hide() end)
    T.card=CreateFrame("Frame",nil,T.content)
    T.focusLabel=text(T.card,"caption",palette.gold)
    T.focusLabel:SetText("当前追踪")
    T.header=T.card:CreateTexture(nil,"BACKGROUND")
    T.header:SetColorTexture(unpack(palette.navigation))
    T.actionIcon=T.card:CreateTexture(nil,"ARTWORK")
    T.currentMark=T.card:CreateTexture(nil,"ARTWORK")
    T.primaryLabel=text(T.card,"caption",palette.muted)
    self.title=text(T.card,"task",palette.gold)
    T.questTitle=CreateFrame("Button",nil,T.card);T.questTitle:SetAllPoints(self.title)
    T.questTitle:RegisterForClicks("LeftButtonUp","RightButtonUp")
    T.questTitle:SetScript("OnClick",function(_,mouse)
        if mouse=="RightButton" then self:TrackerMenu(T.questTitle)
        elseif T.questTitle.questId then self:QuestClick(T.questTitle.questId,mouse)
        elseif T.model and T.model.dungeonName then
            self.Dungeon.selected=T.model.dungeonId
            self.details:Show();self:SelectTab(T.model.dungeonId and 4 or 1)
        end
    end)
    T.questTitle:SetScript("OnEnter",questTooltip)
    T.questTitle:SetScript("OnLeave",function() GameTooltip:Hide() end)
    T.skip=self:ListButton(T.card,"暂时不做",64,function() A.Selection:Skip(T.questTitle.questId) end,"caption")
    T.skip.text:SetTextColor(unpack(palette.muted))
    T.skip:HookScript("OnEnter",function(button)
        GameTooltip:SetOwner(button,"ANCHOR_TOP");GameTooltip:SetText("升级后重新推荐")
        GameTooltip:AddLine("右键点任务名可选择「忽略此任务」。",1,1,1);GameTooltip:Show()
    end)
    T.skip:HookScript("OnLeave",function() GameTooltip:Hide() end)
    T.currentScroll=CreateFrame("ScrollFrame",nil,T.card,"UIPanelScrollFrameTemplate")
    T.currentChild=CreateFrame("Frame",nil,T.currentScroll);T.currentScroll:SetScrollChild(T.currentChild)
    T.career:SetParent(T.currentChild)
    T.gear=noticeLine(T.currentChild,"caption",palette.gearText)
    T.gear.hint="右键换装 · 点击 × 忽略这件"
    T.gear:EnableMouse(true);T.gear.text:SetMaxLines(1)
    T.gear.icon=T.gear:CreateTexture(nil,"ARTWORK");T.gear.icon:SetTexture(media.."hud-equip.tga")
    T.gear.icon:SetVertexColor(unpack(palette.gold))
    local function ignoreGear(advice)
        if not advice then return end
        A.char.ignoredGear=A.char.ignoredGear or {};A.char.ignoredGear["item:"..advice.item.id]=true
        GameTooltip:Hide();self:RenderTracker()
    end
    local function gearMenu()
        local advice=T.gear.advice
        if not advice then return end
        GameTooltip:Hide()
        self:Menu(T.gear,function(_,menu)
            menu:CreateButton("装备这件",function()
                local ok,why=A.Gear:EquipAdvice(advice)
                if not ok then A:Message(why) end
                self:RenderTracker()
            end):SetEnabled(not InCombatLockdown())
            menu:CreateButton("忽略这件",function() ignoreGear(advice) end)
        end)
    end
    T.gear:SetScript("OnMouseUp",function(_,button) if button=="RightButton" then gearMenu() end end)
    T.gear:SetScript("OnHyperlinkClick",function(_,link,label,button)
        if button=="RightButton" then gearMenu() else SetItemRef(link,label,button) end
    end)
    T.gear.close=self:Button(T.gear,"",spacing.hit,function() ignoreGear(T.gear.advice) end)
    T.gear.close.baseColor=palette.panel;T.gear.close:SetBackdropColor(0,0,0,0)
    T.gear.close.icon=T.gear.close:CreateTexture(nil,"ARTWORK");T.gear.close.icon:SetPoint("CENTER")
    T.gear.close.icon:SetTexture(media.."hud-close.tga");T.gear.close.icon:SetVertexColor(unpack(palette.muted))
    T.gear.close:HookScript("OnEnter",function(button)
        GameTooltip:SetOwner(button,"ANCHOR_TOP");GameTooltip:SetText("忽略这件装备，不再提醒");GameTooltip:Show()
    end)
    T.gear.close:HookScript("OnLeave",function() GameTooltip:Hide() end)
    T.reward=noticeLine(T.currentChild,"caption",palette.gearText)
    T.reward:EnableMouse(true)
    T.reward.text:SetMaxLines(1)
    T.reward.text:SetNonSpaceWrap(false)
    T.reward.icon=T.reward:CreateTexture(nil,"ARTWORK");T.reward.icon:SetTexture(media.."hud-chevron-up.tga")
    T.reward.icon:SetVertexColor(unpack(palette.green))
    T.objectiveFrame=CreateFrame("Frame",nil,T.currentChild)
    self.body=text(T.currentChild,"caption",palette.muted);self.body:SetMaxLines(2)
    T.objectives={}
    T.footer=text(T.currentChild,"caption",palette.muted)
    T.journey=CreateFrame("Frame",nil,T.currentChild)
    T.journeyHeader=CreateFrame("Button",nil,T.journey)
    T.journeyLabel=text(T.journeyHeader,"caption",palette.muted);T.journeyLabel:SetPoint("LEFT");T.journeyLabel:SetText("行程")
    T.journeySummary=text(T.journeyHeader,"caption",palette.white);T.journeySummary:SetPoint("RIGHT");T.journeySummary:SetJustifyH("RIGHT")
    T.journeyHeader:SetScript("OnClick",function() T.journeyClosed=not T.journeyClosed;self:LayoutTracker() end)
    T.journeyClosed=true
    T.journeyRows={}
    T.questTitle.progress=self.body
    T.thenText=text(T.currentChild,"caption",palette.gold)
    T.thenDivider=T.currentChild:CreateTexture(nil,"BACKGROUND");T.thenDivider:SetColorTexture(unpack(palette.line))
    T.thenButton=self:TrackerRow(nil,T.currentChild)
    T.region=CreateFrame("Button",nil,T.currentChild)
    T.region.heading=text(T.region,"caption",palette.muted)
    T.region.heading:SetText("本轮收尾")
    T.region.rule=T.region:CreateTexture(nil,"BACKGROUND")
    T.region.rule:SetColorTexture(unpack(palette.line))
    T.region.more=T.region:CreateTexture(nil,"ARTWORK")
    T.region.more:SetTexture(media.."hud-chevron-right.tga")
    T.region.more:SetVertexColor(unpack(palette.muted))
    T.region.rows={}
    for i=1,3 do
        local row={label=text(T.region,"caption",palette.muted),value=text(T.region,"body",palette.white)}
        row.label:SetMaxLines(1);row.value:SetMaxLines(1)
        T.region.rows[i]=row
    end
    T.region:SetScript("OnEnter",function() T.region.more:SetVertexColor(unpack(palette.white)) end)
    T.region:SetScript("OnLeave",function() T.region.more:SetVertexColor(unpack(palette.muted)) end)
    T.region:SetScript("OnClick",function()
        local region=T.region.region
        if region then self.Browser.selection[10]="map:"..region.map;self.Browser:ClearSearch() end
        self.details:Show();self:SelectTab(10)
    end)
    T.queuePanel=CreateFrame("Frame",nil,T.currentChild)
    T.queueLabel=text(T.currentChild,"caption",palette.muted);T.queueLabel:SetText("后续行程")
    T.queueScroll=CreateFrame("Frame",nil,T.queuePanel)
    T.queueScroll:SetPoint("TOPLEFT",0,0)
    T.queueChild=CreateFrame("Frame",nil,T.queueScroll);T.queueChild:SetPoint("TOPLEFT")
    T.alongLabel=text(T.currentChild,"caption",palette.blue)
    T.alongScroll=CreateFrame("Frame",nil,T.currentChild)
    T.alongChild=CreateFrame("Frame",nil,T.alongScroll);T.alongChild:SetPoint("TOPLEFT")
    T.queueRule=T.currentChild:CreateTexture(nil,"BACKGROUND")
    T.alongRule=T.currentChild:CreateTexture(nil,"BACKGROUND")
    T.otherHeader=CreateFrame("Button",nil,T.currentChild)
    T.otherLabel=text(T.otherHeader,"caption",palette.muted);T.otherLabel:SetPoint("LEFT")
    T.otherToggle=text(T.otherHeader,"caption",palette.muted);T.otherToggle:SetPoint("RIGHT")
    T.otherHeader:SetScript("OnClick",function() T.otherOpen=not T.otherOpen;self:RenderTracker() end)
    T.otherChild=CreateFrame("Frame",nil,T.currentChild)
    T.rows={}
    T.progress=CreateFrame("Frame",nil,f);T.progress:SetPoint("BOTTOMLEFT",spacing.padding,spacing.padding);T.progress:SetPoint("BOTTOMRIGHT",-28,spacing.padding)
    T.progress:SetHeight(14);T.progress:EnableMouse(true)
    T.progress:SetScript("OnEnter",function()
        GameTooltip:SetOwner(T.progress,"ANCHOR_TOP");GameTooltip:SetText("当前任务目标进度")
        GameTooltip:AddLine(T.model and T.model.title or "",1,1,1);GameTooltip:Show()
    end)
    T.progress:SetScript("OnLeave",function() GameTooltip:Hide() end)
    T.progressBack=T.progress:CreateTexture(nil,"BACKGROUND");T.progressBack:SetColorTexture(unpack(palette.line))
    T.progressFill=T.progress:CreateTexture(nil,"ARTWORK");T.progressFill:SetColorTexture(unpack(palette.gold))
    if self.daylight then
        T.progressBar=self.daylight.Bar(T.progress);T.progressBar:SetMinMaxValues(0,1)
    end
    T.progressLabel=text(T.progress,"caption",palette.muted);T.progressLabel:SetPoint("LEFT");T.progressLabel:SetText("当前任务进度")
    T.progressText=text(T.progress,"caption",palette.muted);T.progressText:SetPoint("RIGHT");T.progressText:SetWidth(40);T.progressText:SetJustifyH("RIGHT")
    -- The secure item buttons and the freely resizable card share a fixed lower edge.
    local anchor=CreateFrame("Frame",nil,UIParent)
    self.navAnchor=anchor;anchor:SetSize(268,48);anchor:SetClampedToScreen(true)
    self:PlaceNavigation(true)
    local nav=CreateFrame("Button","AiLevelingNavigation",anchor)
    self.navFrame=nav;nav:SetPoint("BOTTOM",anchor,"BOTTOM")
    self:Movable(nav,"navigationPosition",anchor)
    nav:RegisterForClicks("LeftButtonUp","RightButtonUp")
    nav:SetScript("OnMouseDown",function(button) button.dragged=nil end)
    nav:HookScript("OnDragStart",function(button) button.dragged=true end)
    nav:SetScript("OnClick",function(button,mouse)
        if button.dragged then return end
        if mouse=="RightButton" and button.questId then self:TrackerMenu(button)
        else self:QuestClick(button.questId,mouse) end
    end)
    nav:SetSize(268,48)
    if self.daylight then self:DaylightShell(nav,palette.navigation[4])
    else self:Rounded(nav,spacing.radius);nav:SetBackdropColor(unpack(palette.navigation));nav.material:Hide() end
    T.navIcon=nav:CreateTexture(nil,"ARTWORK")
    T.navTitle=text(nav,"task",palette.white)
    T.navDetail=text(nav,"body",palette.white)
    T.navRule=nav:CreateTexture(nil,"ARTWORK")
    T.navNextIcon=nav:CreateTexture(nil,"ARTWORK")
    T.navNext=text(nav,"caption",palette.muted)
    self.nav=text(nav,"caption","accent");self.nav:SetJustifyH("RIGHT")
    T.navBearing=nav:CreateTexture(nil,"ARTWORK")
    T.navBearing:SetTexture(media.."hud-chevron-up.tga")
    nav:Hide()
end

local function questTitle(id,title,candidate)
    local quest=(A.state.quests or {})[id]
    local level=quest and quest.level or candidate and candidate.level
    return (level and level>0 and ("["..level.."] ") or "")..title
end

local function renderObjectives(owner,parent,pool,objectives,sharedIndex)
    for i,objective in ipairs(objectives) do
        local row=pool[i]
        if not row then
            row=CreateFrame("Button",nil,parent)
            row:RegisterForClicks("LeftButtonUp","RightButtonUp")
            row:SetScript("OnClick",function(_,button)
                if button=="RightButton" then UI:TrackerMenu(owner) else UI:QuestClick(owner.questId,button) end
            end)
            row:SetScript("OnEnter",function(f)
                questTooltip(owner)
                if f.purchase then GameTooltip:AddLine(f.purchase,1,0.82,0.35,true);GameTooltip:Show() end
            end)
            row:SetScript("OnLeave",function() GameTooltip:Hide() end)
            row.text=text(row,"body",palette.white);row.text:SetPoint("TOPLEFT");row.text:SetNonSpaceWrap(false)
            row.purchaseText=text(row,"caption",palette.gold);row.purchaseText:SetMaxLines(1)
            row.icon=row:CreateTexture(nil,"ARTWORK")
            row.count=text(row,"body",palette.white);row.count:SetJustifyH("RIGHT")
            row.check=text(row,"task",palette.muted);row.check:SetJustifyH("RIGHT")
            row.active=row:CreateTexture(nil,"ARTWORK");row.active:SetColorTexture(unpack(palette.focus))
            pool[i]=row
        end
        local done=objective.done or objective.finished==true
        local need,have=objective.need or objective.numRequired,objective.have or objective.numFulfilled or 0
        row.known=type(need)=="number" and need>0
        row.ratio=done and 1 or row.known and math.max(0,math.min(1,have/need)) or 0
        local icon=UI.ObjectiveIcon(objective)
        local purchase=objective.purchase
        for _,stage in ipairs(owner.candidate and owner.candidate.stages or {}) do
            if stage.kind=="objective" and stage.objectiveIndex==(sharedIndex or i) then
                icon=icon or UI.ObjectiveIcon(stage);purchase=purchase or stage.purchase;break
            end
        end
        row.purchase=not done and (not row.known or have<need) and UI.PurchaseText(purchase) or nil
        local label=objective.text or "任务目标"
        if row.known then label=label:gsub("%s*%d+%s*/%s*%d+",""):gsub("^%s+","") end
        row.text:SetText(label)
        row.purchaseText:SetText(row.purchase and ("可购买 · "..(purchase.name or ("商人 #"..purchase.npcId))) or "")
        row.purchaseText:SetShown(row.purchase~=nil)
        row.text:SetTextColor(unpack(done and palette.green or palette.white))
        setHUDIcon(row.icon,done and "done" or icon or "target")
        row.count:SetText(row.known and string.format("%d/%d",have,need) or "")
        row.count:SetTextColor(unpack(done and palette.green or palette.gold))
        row.check:SetText(done and "✓" or "");row.check:SetShown(done and not row.known);row.check:SetTextColor(unpack(palette.green))
        row.active:SetShown(not done and owner.activeObjective==i)
        row:Show()
    end
    for i=#objectives+1,#pool do pool[i]:Hide() end
end

local function layoutObjectives(pool,width,scale)
    local y=0
    for _,row in ipairs(pool) do
        if row:IsShown() then
            local countWidth=(row.count:GetText() or "")~="" and math.ceil(row.count:GetStringWidth())+6*scale or 0
            row:SetWidth(width);row.text:SetWidth(width-countWidth-(row.check:IsShown() and 42 or 20)*scale);row.count:SetWidth(countWidth)
            row.count:ClearAllPoints();row.count:SetPoint("TOPRIGHT",0,0)
            row.check:ClearAllPoints();row.check:SetPoint("TOPRIGHT",0,0);row.check:SetWidth(18*scale)
            row.text:ClearAllPoints();row.text:SetPoint("TOPLEFT",20*scale,0)
            row.icon:ClearAllPoints();row.icon:SetPoint("TOPLEFT",0,-2);row.icon:SetSize(14*scale,14*scale)
            row.active:ClearAllPoints();row.active:SetWidth(2*scale)
            row.active:SetPoint("TOPLEFT",-10*scale,0);row.active:SetPoint("BOTTOMLEFT",-10*scale,6*scale)
            row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-y)
            local height=math.max(18*scale,row.text:GetStringHeight())
            row.purchaseText:ClearAllPoints();row.purchaseText:SetPoint("TOPLEFT",20*scale,-height)
            row.purchaseText:SetWidth(width-20*scale)
            if row.purchaseText:IsShown() then height=height+row.purchaseText:GetStringHeight()+spacing.tight*scale end
            height=height+(UI.daylight and 3 or 6)*scale
            row:SetHeight(height);y=y+height
        end
    end
    return y
end

function UI:DetailObjectives(frame,choice,goals,width)
    frame.candidate,frame.questId,frame.revision=choice,choice.questId,A.plan and A.plan.revision
    frame.deferred=(A.state.skipped or {})[choice.questId] or (A.state.chainDeferred or {})[choice.questId]
    frame.rows=frame.rows or {}
    renderObjectives(frame,frame,frame.rows,goals)
    return layoutObjectives(frame.rows,width,self:FontScale())
end

function UI:TrackerRow(index,parent)
    local T=self.tracker
    if index and T.rows[index] then return T.rows[index] end
    local row=CreateFrame("Button",nil,parent or T.queueChild,"BackdropTemplate")
    self:Rounded(row,spacing.controlRadius);row:SetBackdropColor(0,0,0,0)
    if row.material then row.material:Hide() end
    row.icon=row:CreateTexture(nil,"ARTWORK")
    row.title=text(row,"task",palette.gold)
    row.progress=text(row,"caption",palette.muted)
    row.objectiveFrame=CreateFrame("Frame",nil,row);row.objectives={}
    row:RegisterForClicks("LeftButtonUp","RightButtonUp")
    row:SetScript("OnEnter",function() row:SetBackdropColor(unpack(palette.rowHover));questTooltip(row) end)
    row:SetScript("OnLeave",function() row:SetBackdropColor(0,0,0,0);GameTooltip:Hide() end)
    row:SetScript("OnClick",function(_,button)
        if button=="RightButton" then self:TrackerMenu(row)
        elseif row.serviceStop then self:PickTrackerFlight(row.serviceStop)
        elseif row.dungeonId then self.Dungeon.selected=row.dungeonId;self.details:Show();self:SelectTab(4)
        else self:QuestClick(row.questId,button) end
    end)
    if index then T.rows[index]=row end
    return row
end

function UI:UpdateNearby(along)
    local notice=self.tracker and self.tracker.nearby
    if not notice then return end
    if self.tracker.instanceRoster then notice:Hide();return end
    local state,navigation=A.state,A.Navigation
    local position=state.position
    local map=position and position.map
    if notice.map~=map then notice.map=map;notice.ignored={} end
    notice.key,notice.action=nil,nil
    local best,goal,bestKey
    if position and not A.char.paused and not state.dead and not state.onTaxi and not navigation.manual and not A.error then
        if not along then
            local action=navigation:Current()
            local journey=self.TrackerJourney(state,action)
            along=alongTasks(state,trackerPlan(state),journey and journey.goal or action,false,self.tracker.model and self.tracker.model.deliveryGroups)
        end
        for id,side in pairs(along) do
            local q=(state.quests or {})[id]
            local objective=q and (q.objectives or {})[side.action.objectiveIndex]
            if side.action.kind=="objective" and objective and not objective.finished and side.distance<=180 and
                (not objective.numRequired or objective.numRequired<=0 or (objective.numFulfilled or 0)<objective.numRequired) then
                local key=id..":"..side.action.objectiveIndex
                local ignored=notice.ignored[key]
                local away=ignored and navigation:Distance(position,ignored.position)
                if (not ignored or ignored.count<2 and away and away>180) and
                    (not best or side.distance<best.distance or side.distance==best.distance and key<bestKey) then
                    best,goal,bestKey=side,objective,key
                end
            end
        end
    end
    if not best then notice:Hide();return end
    local title=(goal.text or "完成任务目标"):gsub("%s*%d+%s*/%s*%d+",""):gsub("：%s*$",""):gsub(":%s*$","")
    local step,point=best.action,best.action.position
    local db=A.Data and A.Data.db
    local entity=db and (point.entityKind=="npc" and db.Npc or point.entityKind=="object" and db.Object)
    local source=point.entityName or entity and point.entityId and entity.Get(point.entityId,"name")
    local kind,id=step.targetKind or point.targetKind,step.targetId or point.targetId
    local item=point.targetName or kind=="item" and db and db.Item and id and db.Item.Get(id,"name")
    if not item and goal.type=="item" then item=title:gsub("^收集%s*","") end
    if item then
        if point.sourceKind=="vendor" then title="购买 "..item
        elseif source and source~=item then
            local faction=point.entityKind=="npc" and entity and point.entityId and entity.Get(point.entityId,"friendlyToFaction")
            local friendly=faction=="AH" or faction==(state.faction=="Alliance" and "A" or state.faction=="Horde" and "H")
            title=point.entityKind=="npc" and not friendly and ("为 "..item.." 击杀 "..source) or
                ("从 "..source.." 收集 "..item)
        else title="收集 "..item end
    elseif source and (kind=="npc" or goal.type=="monster") then title="击杀 "..source end
    local need,have=goal.numRequired,goal.numFulfilled or 0
    if type(need)=="number" and need>0 then title=string.format("%s，还差 %d",title,math.max(0,need-have)) end
    notice.key,notice.action,notice.title=bestKey,best.action,title
    notice.body:SetText(title.."  ·  "..nearbyDistance(best.distance))
    setHUDIcon(notice.icon,UI.ObjectiveIcon(goal) or UI.ObjectiveIcon(step) or "target")
    local scale=A.settings.fontScale or 1
    notice.mark:ClearAllPoints();notice.mark:SetPoint("TOPLEFT",1,-1);notice.mark:SetPoint("BOTTOMLEFT",1,1);notice.mark:SetWidth(2*scale)
    notice.icon:ClearAllPoints();notice.icon:SetPoint("LEFT",14*scale,0);notice.icon:SetSize(16*scale,16*scale)
    notice.heading:ClearAllPoints();notice.heading:SetPoint("TOPLEFT",44*scale,-8*scale)
    notice.body:ClearAllPoints();notice.body:SetPoint("TOPLEFT",44*scale,-8*scale-notice.heading:GetStringHeight()-spacing.tight*scale);notice.body:SetWidth(264*scale)
    notice:SetSize(320*scale,16*scale+notice.heading:GetStringHeight()+spacing.tight*scale+notice.body:GetStringHeight())
    notice:Show()
end

local function stepIcon(step)
    local task=step.action or step
    local quest=(A.state.quests or {})[task.questId]
    local icon=UI.QuestIcon(task.kind,task,quest and quest.objectives)
    return icon=="compass" and "location" or icon
end

function UI:RenderJourney(journey,dynamic)
    local T=self.tracker
    T.journeyTime=journey and clockText(journey.seconds) or ""
    if journey and journey.distance and journey.distance>0 then
        local meters=A.settings.distanceUnits=="meters"
        local distance=journey.distance*(meters and 0.9144 or 1)
        T.journeyTime=T.journeyTime.." · 步行 "..(distance>=1000 and string.format("%.1f",distance/1000)..(meters and "公里" or "k码") or string.format("%.0f",distance)..(meters and "米" or "码"))
    end
    for i,step in ipairs(journey and journey.steps or {}) do
        local row=T.journeyRows[i]
        if not row then
            row=CreateFrame("Frame",nil,T.journey)
            row.number=text(row,"caption",palette.muted)
            row.icon=row:CreateTexture(nil,"ARTWORK")
            row.title=text(row,"body",palette.white)
            row.time=text(row,"caption",palette.white);row.time:SetJustifyH("RIGHT")
            row.detail=text(row,"caption",palette.muted)
            T.journeyRows[i]=row
        end
        if not dynamic then
            row.number:SetText(i)
            local icon=stepIcon(step)
            setHUDIcon(row.icon,icon)
            row.title:SetText(placeText(step.title,step.place));row.title:SetTextColor(unpack(i==1 and palette.gold or palette.white))
            row.detail:SetText(step.detail or "")
            row:SetShown(i==1 or not T.journeyClosed)
        end
        row.time:SetText(step.task and "" or clockText(step.seconds))
    end
    for i=#(journey and journey.steps or {})+1,#T.journeyRows do T.journeyRows[i]:Hide() end
    T.journeySummary:SetText((T.journeyTime or "")..(T.journeyClosed and "  +" or "  −"))
end

local function trackerMoved(T,position)
    local map,x,y=position and position.map,position and position.x,position and position.y
    local moved=map~=T.lastMap or x~=T.lastX or y~=T.lastY
    T.lastMap,T.lastX,T.lastY=map,x,y
    return moved
end

local function navigationStep(action)
    if action and action.kind=="manual" then return A.Navigation.manual or action end
    if action and action.kind=="flight" then return A.Transport and A.Transport.flight or action end
    if action and action.kind=="hearthCast" then return A.Hearth and (A.Hearth.cast or A.Hearth.pending) or action end
    return action
end

function UI:UpdateTrackerDynamic()
    local T=self.tracker
    if not T or not T.model or T.model.dungeonName then return end
    local state=A.state
    local action=A.Navigation:Current()
    if navigationStep(action)~=T.lastStep then self:RenderTracker();return end
    if action and action.kind=="tram" then return end
    if not trackerMoved(T,state.position) then
        if T.model.journey and action and (action.kind=="flight" or action.kind=="hearthCast") then
            T.model.journey=self.TrackerJourney(state,action)
            self:RenderJourney(T.model.journey,true)
        end
        return
    end
    local journey=not A.char.paused and not A.error and self.TrackerJourney(state,action)
    local goal=journey and journey.goal or action
    local along=alongTasks(state,trackerPlan(state),goal,A.char.paused,T.model.deliveryGroups)
    local previous=T.model.along or {}
    for id,side in pairs(along) do
        if not previous[id] or previous[id].action~=side.action then self:RenderTracker(along);return end
    end
    for id in pairs(previous) do if not along[id] then self:RenderTracker(along);return end end
    T.model.along=along
    self:UpdateNearby(along)
    local old=T.model.journey
    local layout=(journey~=nil)~=(old~=nil) or #(journey and journey.steps or {})~=#(old and old.steps or {})
    for _,row in ipairs(T.rows) do
        local side=along[row.questId or row.serviceStop and ("taxi:"..row.serviceStop.taxiId)]
        if row.along and side and row:IsShown() and row.progress:IsShown() then
            local height=row.progress:GetStringHeight()
            row.progress:SetText(row.progressBase.." · "..nearbyDistance(side.distance))
            layout=layout or height~=row.progress:GetStringHeight()
        end
    end
    for i,step in ipairs(journey and journey.steps or {}) do
        local before=old and old.steps[i]
        if not before or before.title~=step.title or before.detail~=step.detail or before.place~=step.place then layout=true end
    end
    T.model.journey=journey
    self:RenderJourney(journey,not layout)
    if layout then self:LayoutTracker() end
end

function UI:RenderTracker(along)
    local T=self.tracker
    if not T then return end
    local state=A.state or {}
    local plan=trackerPlan(state)
    local action=A.Navigation:Current()
    if action and action.kind=="tram" then plan={} end
    local model=self:DungeonTrackerModel(state,action) or UI.TrackerModel(state,plan,action,A.char.paused,along)
    trackerMoved(T,state.position)
    T.model,T.action,T.lastStep=model,action,navigationStep(action)
    self:UpdateNearby(model.along)
    local spells=not model.dungeonName and state.trainableSpells or {}
    local links={}
    if #spells>0 and A.char.classReminderLevel~=state.level then
        T.career.heading:SetText(self:Icon("class",12).." "..state.level.."级 · 可学技能")
        for i=1,math.min(2,#spells) do links[i]=spells[i].link end
    end
    T.career.text:SetText(#links>0 and table.concat(links,"、")..(#spells>2 and (" 等"..#spells.."项") or "") or "")
    local training=state.serviceStop and state.serviceStop.kind=="train"
    T.career.train:SetShown(#spells>0)
    T.career.train.text:SetText(training and "已安排" or "去训练")
    T.career.train:SetEnabled(not training and not state.inInstance and not state.dead and not state.onTaxi)
    local dungeons=not model.dungeonName and self.DungeonReminders(state,plan) or {}
    local suggested=dungeons[1]
    T.dungeons.candidate=suggested
    local batch=A.char.taskBatch
    local dungeon=batch and A.DungeonCatalog and A.DungeonCatalog.entries[batch.id]
    T.dungeons.heading:SetText(batch and ("副本行程"..(dungeon and " · "..dungeon.title or "")) or ("副本建议 · "..#dungeons.."处  ›"))
    T.dungeons.text:SetText(batch and "返回正常练级  ›" or suggested and
        (self:Icon("entry",16).." "..suggested.title.." · "..dungeonRewardSummary(suggested)..
        (suggested.recommendation and " · "..suggested.recommendation or "")) or "")
    local bag=A.settings.rewardAdvice~=false and A.Gear and A.Gear.BagUpgrade(state,A.char.ignoredGear) or nil
    T.gear.advice=bag
    T.gear.text:SetText(bag and ("装备："..(bag.item.link or bag.item.name).." |cff"..UI.hex.green..A.Gear.UpgradeText(bag).."|r") or "")
    local rewardLines=A.QuestAssist and A.QuestAssist.rewardLines or {}
    T.reward.advice=not rewardLines[1] and model.reward or nil
    T.reward.details=rewardLines[1] and table.concat(rewardLines,"\n") or nil
    local dialogQuest=A.QuestAssist and (state.quests or {})[A.QuestAssist.rewardQuest]
    if T.reward.details and dialogQuest and dialogQuest.title then T.reward.details=dialogQuest.title.."\n"..T.reward.details end
    local reward=model.reward and model.reward.item
    local upgrade=reward and model.reward.upgrade.delta>0
    T.reward.icon:SetShown(not rewardLines[1] and upgrade and model.kind=="turnin" or false)
    local prefix=model.kind=="accept" and "奖励：" or upgrade and "" or "选择 "
    T.reward.text:SetText(rewardLines[1] or reward and (prefix..(reward.link or reward.name)..
        (upgrade and (" |cff"..UI.hex.green..A.Gear.UpgradeText(model.reward).."|r") or "")) or "")
    action=model.action
    T.questTitle.questId=model.questId
    T.questTitle.activeObjective=action and action.objectiveIndex
    T.questTitle.candidate,T.questTitle.revision=model.choice,plan.revision
    T.questTitle.deferred=model.questId and ((state.skipped or {})[model.questId] or (state.chainDeferred or {})[model.questId])
    local current=(state.quests or {})[model.questId]
    local count=0;for _ in pairs(state.quests or {}) do count=count+1 end
    T.experience:SetText(A.char.paused and "已暂停" or model.dungeonName and (#model.rows.." 项") or "已接 "..count.." 项")
    T.currentMark:SetColorTexture(unpack(palette.focus))
    T.currentMark:SetShown(model.questId~=nil)
    local currentIcon=model.dungeonName and not model.questId and "entry" or UI.QuestIcon(model.kind,action,model.objectives)
    self.title:SetText(questTitle(model.questId,model.title))
    self.title:SetTextColor(unpack(model.kind=="turnin" and palette.green or model.kind=="accept" and palette.gold or palette.white))
    local place,name,area
    if model.kind and not A.error then place,name,area=destination(action,true) end
    name=model.dungeonName and placeLabel(model.dungeonName) or name
    T.location:SetText(name and (self:Icon("location",18).." "..name) or "当前行程")
    setHUDIcon(T.actionIcon,currentIcon)
    T.area:SetText(area or "")
    local nextStep,nextId,nextTitle=model.nextStep,model.nextId,model.nextTitle
    T.primaryLabel:SetText(model.questId and (model.kind=="objective" and current and not current.ready and "进行中" or self.QuestStatus(state,model.questId,plan)) or "")
    T.primaryLabel:SetTextColor(unpack(model.kind=="turnin" and palette.green or model.kind=="accept" and palette.gold or palette.muted))
    local nextRow=T.thenButton
    local nextQuest=(state.quests or {})[nextId]
    local taskStep=nextStep and (nextStep.kind=="accept" or nextStep.kind=="objective" or nextStep.kind=="turnin")
    local sameQuest=taskStep and nextId==model.questId
    local tone=not taskStep and "white" or nextQuest and (nextQuest.ready and "green" or "white") or "gold"
    nextRow.questId,nextRow.candidate,nextRow.revision=nextId,model.nextChoice,plan.revision
    nextRow.mapAction=taskStep and nextStep or nil
    if A.Navigation.SetUpcomingQuest then A.Navigation:SetUpcomingQuest(nextRow.mapAction) end
    nextRow.pickupAction=taskStep and nextStep.kind=="accept" and nextStep or nil
    nextRow.turnInAction=model.nextOnArrival and nextStep or nil
    nextRow.status=taskStep and nextId and self.QuestStatus(state,nextId,plan)
    local following,title,instruction="","",""
    if nextStep then
        title=taskStep and nextId and questTitle(nextId,nextQuest and nextQuest.title or nextTitle or nextStep.title or ("任务 #"..nextId),model.nextChoice)
            or self.ActionText(nextStep,A.settings)
        local verb=({accept="接取",objective="前往",turnin="交付"})[nextStep.kind] or "前往"
        if nextStep.kind=="turnin" and not (nextQuest and nextQuest.ready) then verb="完成后交付" end
        local target=destination(nextStep,true)
        local phase=nextStep.kind=="accept" and model.batchPhases[nextId]
        if phase then verb=phase=="inside" and "副本内接取" or "入本前接取" end
        instruction=target and (verb.." · "..target) or (nextStep.kind=="turnin" or phase) and verb or ""
        local point=taskStep and A.Navigation.Target and A.Navigation.Target(nextStep)
        local location=mapLocation(point)
        if location then
            local npc=point.entityName or point.siteName
            instruction=npc and (verb.." · "..npc) or verb
        end
        following=(model.nextOnArrival or "接下来")..(nextRow.status and (" · |cff"..self.hex[tone]..nextRow.status.."|r") or "")
        if sameQuest then
            following="接下来"
            if nextStep.kind=="objective" then
                title=nextStep.text or "完成任务目标"
                local instance=A.Dungeon and A.Dungeon.TaskInstance and A.Dungeon.TaskInstance(nextStep.position,state,A.Data,nextStep.areaId)
                instruction=instance and ("副本 · "..placeLabel(instance.title)) or instruction
                if model.kind=="accept" then following="接取后" end
            else title=instruction;instruction="" end
        end
        if location then instruction=location..(instruction~="" and ("\n"..instruction) or "") end
    end
    T.thenText:SetText(following)
    nextRow.title:SetText(title);nextRow.title:SetTextColor(unpack(palette[tone]))
    local nextIcon=UI.QuestIcon(nextStep and nextStep.kind,nextStep,nextQuest and nextQuest.objectives)
    setHUDIcon(nextRow.icon,nextIcon);nextRow.progress:SetText(instruction)
    nextRow.detail=(nextRow.status or "").."\n"..instruction
    renderObjectives(nextRow,nextRow.objectiveFrame,nextRow.objectives,taskStep and not sameQuest and nextQuest and not nextQuest.ready and nextQuest.objectives or {})
    local visit=not model.dungeonName and plan.regionPlan
    local region=visit and (visit.destination or visit.current)
    local rows=T.region.rows
    local handins=visit and visit.handins or {}
    local ready=true
    for _,c in ipairs(handins) do ready=ready and (state.quests[c.questId] or {}).ready and not c.itemShortage end
    rows[1].label:SetText(ready and "先交付" or "做完再交")
    rows[1].label:SetTextColor(unpack(palette[ready and "green" or "gold"]))
    rows[1].value:SetText(handins[1] and ((#handins>1 and #handins.."项 · " or "")..handins[1].title) or "")

    local nextRegion=visit and visit.destination
    rows[2].label:SetText("下一站")
    if nextRegion then
        local pickup=nextRegion.pickups[1]
        local task=pickup or nextRegion.choices[1]
        rows[2].value:SetText(nextRegion.title..(task and ((pickup and " · 接 " or " · 做 ")..task.title) or ""))
    else rows[2].value:SetText("") end

    local revisit=visit and visit.revisit or {}
    rows[3].label:SetText("回访")
    local first=revisit[1]
    rows[3].value:SetText(first and (first.level.."级"..(#revisit>1 and ("起 · "..#revisit.."项任务") or (" · "..first.choice.title))) or "")
    T.region.region=(#handins>0 or nextRegion or first) and region or nil

    local instruction=model.instruction
    local contact=(model.kind=="accept" or model.kind=="turnin") and action.position
    local contactHint=contact and not A.char.paused and not A.error and contact.travelHint
    if model.kind=="accept" then
        for _,stage in ipairs(model.choice and model.choice.stages or {}) do
            local instance=stage.kind=="objective" and A.Dungeon and A.Dungeon.TaskInstance and
                A.Dungeon.TaskInstance(stage.position,state,A.Data,stage.areaId)
            if instance then instruction=(state.taskBatch and "副本任务 · " or "先接备用 · ")..instance.title;break end
        end
    end
    if model.kind=="objective" and #model.objectives>0 and not A.char.paused and not A.error and
        not (action.position and action.position.sourceKind=="vendor") then instruction=nil end
    local lines={contactHint or model.deliverySummary or instruction}
    if model.deliverySummary and instruction and model.kind~="turnin" and instruction~=lines[1] then lines[#lines+1]=instruction end
    if model.destination and model.kind~="objective" and not model.deliverySummary and
        not (lines[1] and lines[1]:find(model.destination,1,true)) then lines[#lines+1]=model.destination end
    local location=(model.kind=="turnin" or contact and contact.sourceKind=="escortStart") and mapLocation(contact)
    local footer=location and (location..(model.metrics and ("\n"..model.metrics) or "")) or model.metrics
    T.footer:SetText(footer or "");T.footer:SetMaxLines(location and 0 or 1);T.questTitle.metrics=footer
    if #lines==0 and model.hint and not A.char.paused and state.locked~=model.questId then lines[#lines+1]=model.hint end
    if plan.selectionBlocked then lines[#lines+1]=plan.selectionBlocked end
    if plan.gearTargetBlocked then lines[#lines+1]=plan.gearTargetBlocked end
    if plan.supplyIssue then lines[#lines+1]=plan.supplyIssue end
    if action and action.kind=="service" then
        local function items(map,label)
            local ids={};for id in pairs(map or {}) do ids[#ids+1]=id end;table.sort(ids)
            for _,id in ipairs(ids) do
                local item=state.itemMetadata and state.itemMetadata[id]
                lines[#lines+1]=label..(item and item.name or ("#"..id)).." ×"..map[id]
            end
        end
        local goal=action.serviceGoal or {}
        items(goal.items,"需携带：");items(action.consumeItems,"整理／出售：");items(goal.capacityItems,"预留容量：")
        if goal.freeSlots and goal.freeSlots>0 then lines[#lines+1]="通用空格至少 "..goal.freeSlots.." 格" end
        if A.Merchant then for _,line in ipairs(A.Merchant.Lines(action,state)) do lines[#lines+1]=line end end
    end
    local guidance=table.concat(lines,"\n")
    if model.kind=="objective" and #model.objectives>0 and not A.char.paused and not A.error and
        not (action.position and action.position.sourceKind=="vendor") then
        guidance=model.deliverySummary or model.hint or ""
    end
    if model.unlock then guidance=A.TaskGuide.UnlockText(model.unlock)..(guidance~="" and (" · "..guidance) or "") end
    if model.dungeonName then
        guidance=model.instruction or ""
        if model.feedback then guidance=model.feedback..(guidance~="" and ("\n"..guidance) or "") end
    end
    local reminder=model.bindingReminder
    if reminder then guidance=reminder..(guidance~="" and ("\n"..guidance) or "") end
    self.body:SetMaxLines(reminder and 0 or 2)
    self.body:SetText(guidance)
    self.body:SetTextColor(unpack((model.feedback or model.kind=="turnin") and palette.green or palette.white))
    T.questTitle.detail=model.dungeonName and "点击查看副本任务详情" or (place and (place.."\n") or "")..table.concat(lines,"\n")
    renderObjectives(T.questTitle,T.objectiveFrame,T.objectives,
        (model.kind=="objective" or current and not current.ready) and model.objectives or {})
    local progress,goals=0,0
    for _,row in ipairs(T.objectives) do
        if row:IsShown() then progress=progress+row.ratio;goals=goals+1 end
    end
    T.progressRatio=goals>0 and progress/goals or nil
    T.progressText:SetText(T.progressRatio and string.format("%.0f%%",T.progressRatio*100) or "")
    self:RenderJourney(model.journey)
    local rows={}
    for _,item in ipairs(model.rows) do
        if not item.otherAccepted or T.otherOpen then rows[#rows+1]=item end
    end
    T.displayRows=rows
    for i,item in ipairs(rows) do
        local row=self:TrackerRow(i)
        local isCurrent=item.questId and item.questId==model.questId
        local title=questTitle(item.questId,item.title,item.candidate)
        local group=item.group
        local tone=item.kind=="turnin" and "green" or item.kind=="accept" and "gold" or group and "purple" or "white"
        local color=(item.deferred or item.candidate and item.candidate.lowValue) and palette.muted or palette[tone]
        row.title:SetText(group and (item.number..". "..title..(group=="focus" and "  |cff"..self.hex[tone]..item.status.."|r" or "")) or title);row.title:SetTextColor(unpack(color))
        if group and item.number==1 then
            if not row.section then row.section=text(row,"caption",palette.muted) end
            row.section:SetText(({focus="当前追踪",objective="进行中",turnin="可交付",accept="待接取",related="其他关联任务"})[group])
            row.section:SetTextColor(unpack(group=="focus" and palette.gold or palette[tone]));row.section:Show()
        elseif row.section then row.section:Hide() end
        if group=="focus" then
            if not row.focusMark then
                row.focusMark=row:CreateTexture(nil,"ARTWORK");row.focusMark:SetColorTexture(unpack(palette.focus))
            end
            row.focusMark:Show()
        elseif row.focusMark then row.focusMark:Hide() end
        row.status=item.deferred and ((item.accepted and "已接" or "未接")..(item.deferred=="ignored" and "·忽略" or "·暂缓")) or item.status
        local progress=item.delivery or item.progress
        if item.along and not item.serviceStop then
            local verb=({accept="顺路接取",turnin="顺路交付",objective="顺路完成"})[item.kind]
            if item.shared then
                local objective=state.quests[item.questId].objectives[item.sharedObjective]
                progress="同一目标"..(objective.numRequired and objective.numRequired>0 and
                    string.format(" · %d/%d",objective.numFulfilled or 0,objective.numRequired) or "")
            elseif item.kind=="objective" then progress=item.candidate and item.candidate.itemShortage and item.sideAction.text or item.progress
            else
                local _,name=destination(item.sideAction,true)
                progress=verb.." · "..(name or item.progress)
                if item.kind=="accept" and item.candidate and item.candidate.revisitLevel then
                    progress=progress.." · "..item.candidate.revisitLevel.."级再做"
                end
            end
        end
        row.progressBase=progress
        if item.alongDistance then progress=progress.." · "..nearbyDistance(item.alongDistance) end
        row.progress:SetText(progress)
        row.progress:SetTextColor(unpack(item.kind=="turnin" and palette.green or palette.muted))
        row.metrics=item.metrics
        row.candidate,row.revision,row.questId=item.candidate,plan.revision,item.questId
        row.deferred,row.dungeonId,row.serviceStop=item.deferred,item.dungeonId,item.serviceStop
        row.atStop,row.along=item.atStop,item.along
        row.dungeonAction=item.dungeonAction
        row.turnInAction=item.turnInAction
        row.pickupAction=item.kind=="accept" and (item.dungeonAction or item.along and item.sideAction) or nil
        row:SetParent(item.atStop and T.currentChild or item.along and T.alongChild or item.otherAccepted and T.otherChild or T.queueChild)
        local native=(state.quests or {})[item.questId]
        local objectives=item.objectives or item.accepted and item.kind~="turnin" and not item.deferred and
            not (item.candidate and (item.candidate.lowValue or item.candidate.entryBlocked)) and native and native.objectives or {}
        if item.sharedObjective then objectives={objectives[item.sharedObjective]} end
        local step=item.sideAction or item.dungeonAction or item.candidate and item.candidate.executionAction
        local icon=item.serviceStop and "flight" or item.dungeonId and not item.questId and "entry" or UI.QuestIcon(item.kind,step,objectives)
        setHUDIcon(row.icon,icon,color==palette.muted)
        renderObjectives(row,row.objectiveFrame,row.objectives,objectives,item.sharedObjective)
        if #objectives>0 and not item.objectives and not item.delivery and not (item.candidate and item.candidate.itemShortage) then row.progress:SetText("") end
        row.detail=table.concat({row.status,item.groupTitle or "",item.delivery or item.progress},"\n")
        if isCurrent then T.questTitle.candidate=item.candidate;T.questTitle.revision=plan.revision end
        row:SetEnabled(true);row:Show()
    end
    for i=#rows+1,#T.rows do T.rows[i]:Hide() end
    self:LayoutTracker()
end

function UI:LayoutTracker()
    local T=self.tracker
    if not T then return end
    if ObjectiveTrackerFrame and not T.nativeHider and not InCombatLockdown() then
        T.nativeHider=CreateFrame("Frame",nil,UIParent);T.nativeHider:Hide()
        ObjectiveTrackerFrame:SetParent(T.nativeHider)
    end
    local minimap=MinimapCluster and MinimapCluster:IsShown() and MinimapCluster or Minimap
    local width=280
    if minimap then width=math.max(260,math.min(300,minimap:GetWidth()*minimap:GetEffectiveScale()/self.frame:GetEffectiveScale())) end
    if A.settings.trackerDocked~=false then
        self.frame:ClearAllPoints()
        if minimap then self.frame:SetPoint("TOPRIGHT",minimap,"BOTTOMRIGHT",0,-12)
        else self.frame:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-24,-260) end
    end
    local frameScale=self.frame:GetEffectiveScale()
    local available=UIParent:GetHeight()*UIParent:GetEffectiveScale()/frameScale
    if A.settings.trackerDocked~=false then
        if minimap then
            local _,center=minimap:GetCenter()
            if center then available=(center-minimap:GetHeight()/2)*minimap:GetEffectiveScale()/frameScale-12 end
        else available=available-260 end
    end
    local requestedWidth=T.resizing and self.frame:GetWidth() or A.settings.trackerWidth or 0
    if requestedWidth>0 then width=math.max(260,math.min(800,requestedWidth)) end
    local requestedHeight=T.resizing and self.frame:GetHeight() or A.settings.trackerHeight or 0
    self.frame:SetWidth(width)
    width=width-2*spacing.padding
    local inner=width-spacing.scrollbar
    local scale=self:FontScale()
    local indent=spacing.indent*scale
    local bodyWidth=inner-indent
    local collapsed=self.folded or (self.inCombat and A.settings.combatFold)
    local density=A.settings.density or "normal"
    T.resize:SetShown(not collapsed and not A.settings.lockWindow and not InCombatLockdown())
    T.content:SetWidth(width);T.card:SetWidth(width);T.queuePanel:SetWidth(width)
    T.menu:ClearAllPoints();T.menu:SetPoint("TOPRIGHT",-(spacing.hit+spacing.tight)*scale,2);T.menu:SetSize(spacing.hit*scale,spacing.hit*scale)
    T.collapse:ClearAllPoints();T.collapse:SetPoint("TOPRIGHT",0,2);T.collapse:SetSize(spacing.hit*scale,spacing.hit*scale)
    T.collapse.text:SetText(collapsed and "+" or "−")
    local headerRoom=width-(2*spacing.hit+2*spacing.tight)*scale
    T.location:SetWidth(0);T.area:SetWidth(0);T.experience:SetWidth(0)
    local placeWidth=math.ceil(T.location:GetStringWidth())
    local areaWidth=math.ceil(T.area:GetStringWidth())
    local gap=spacing.gap*scale
    local showArea=(T.area:GetText() or "")~="" and placeWidth+gap+areaWidth<=headerRoom
    local used=math.min(headerRoom,placeWidth)+(showArea and gap+areaWidth or 0)
    T.location:SetWidth(math.max(1,math.min(headerRoom,placeWidth)))
    T.area:ClearAllPoints();T.area:SetPoint("TOPLEFT",placeWidth+gap,-3*scale);T.area:SetWidth(math.max(1,areaWidth));T.area:SetShown(showArea)
    T.experience:ClearAllPoints();T.experience:SetPoint("TOPRIGHT",headerRoom-width,-3*scale)
    local countWidth=math.ceil(T.experience:GetStringWidth())
    T.experience:SetWidth(math.max(1,countWidth));T.experience:SetShown(used+gap+countWidth<=headerRoom)
    local function layoutRow(row,y)
        row:SetWidth(inner)
        local top=0
        if row.section and row.section:IsShown() then
            row.section:ClearAllPoints();row.section:SetPoint("TOPLEFT");row.section:SetWidth(inner)
            top=row.section:GetStringHeight()+spacing.tight*scale
        end
        local inset=row.focusMark and row.focusMark:IsShown() and gap or 0
        row.icon:ClearAllPoints();row.icon:SetPoint("TOPLEFT",inset,-top-2);row.icon:SetSize(16*scale,16*scale)
        row.title:ClearAllPoints();row.title:SetPoint("TOPLEFT",indent+inset,-top);row.title:SetWidth(bodyWidth-inset);row.title:SetMaxLines(2)
        local height=top+math.max(20*scale,row.title:GetStringHeight())+spacing.tight*scale
        if inset>0 then
            row.focusMark:ClearAllPoints();row.focusMark:SetPoint("TOPLEFT",0,-top);row.focusMark:SetSize(3*scale,height-top)
        end
        row.objectiveFrame:ClearAllPoints();row.objectiveFrame:SetPoint("TOPLEFT",indent,-height);row.objectiveFrame:SetWidth(bodyWidth)
        local goals=layoutObjectives(row.objectives,bodyWidth,scale)
        row.objectiveFrame:SetHeight(math.max(1,goals));row.objectiveFrame:SetShown(goals>0)
        height=height+goals
        row.progress:SetShown(not row.atStop and (row.progress:GetText() or "")~="")
        row.progress:ClearAllPoints();row.progress:SetPoint("TOPLEFT",indent,-height);row.progress:SetWidth(bodyWidth);row.progress:SetMaxLines(2)
        if row.progress:IsShown() then height=height+row.progress:GetStringHeight()+4 end
        height=height+spacing.gap*scale
        row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-y);row:SetHeight(height)
        return height
    end
    local cardTop=math.max(36*scale,T.location:GetStringHeight()+spacing.padding*scale)
    T.divider:ClearAllPoints();T.divider:SetPoint("TOPLEFT",0,-cardTop+7);T.divider:SetSize(width,1);T.headerLine:SetSize(38*scale,2)
    T.career:SetWidth(inner)
    T.career.heading:ClearAllPoints();T.career.heading:SetPoint("TOPLEFT");T.career.heading:SetWidth(inner)
    local noticeHeight=T.career.heading:GetStringHeight()+spacing.tight*scale
    T.career.text:ClearAllPoints();T.career.text:SetPoint("TOPLEFT",indent,-noticeHeight);T.career.text:SetWidth(bodyWidth)
    noticeHeight=noticeHeight+T.career.text:GetStringHeight()+spacing.tight*scale
    local noticeX=indent
    for _,button in ipairs({T.career.view,T.career.train,T.career.later}) do
        local buttonWidth=(button==T.career.train and 64 or 48)*scale
        button:ClearAllPoints();button:SetPoint("TOPLEFT",noticeX,-noticeHeight);button:SetSize(buttonWidth,20*scale)
        if button:IsShown() then noticeX=noticeX+buttonWidth+8*scale end
    end
    T.career:SetHeight(noticeHeight+24*scale);T.career:SetShown(not collapsed and (T.career.text:GetText() or "")~="")
    local batch=A.char.taskBatch
    local dungeonParent=batch and T.content or T.currentChild
    if dungeonParent~=T.dungeonParent then T.dungeons:SetParent(dungeonParent);T.dungeonParent=dungeonParent end
    T.dungeons:SetWidth(inner)
    T.dungeons.heading:ClearAllPoints();T.dungeons.heading:SetPoint("TOPLEFT");T.dungeons.heading:SetWidth(inner)
    local dungeonTop=T.dungeons.heading:GetStringHeight()+spacing.tight*scale
    T.dungeons.text:ClearAllPoints();T.dungeons.text:SetPoint("TOPLEFT",0,-dungeonTop);T.dungeons.text:SetWidth(inner)
    T.dungeons:SetHeight(dungeonTop+T.dungeons.text:GetStringHeight())
    T.dungeons:SetShown(not collapsed and not (T.model and T.model.dungeonName) and (A.char.taskBatch~=nil or T.dungeons.dismissedLevel~=A.state.level) and (T.dungeons.text:GetText() or "")~="")
    if batch and T.dungeons:IsShown() then
        T.dungeons:ClearAllPoints();T.dungeons:SetPoint("TOPLEFT",0,-cardTop)
        cardTop=cardTop+T.dungeons:GetHeight()+gap
    end
    T.card:ClearAllPoints();T.card:SetPoint("TOPLEFT",0,-cardTop)
    T.primaryLabel:SetShown((T.primaryLabel:GetText() or "")~="")
    T.focusLabel:SetShown(not collapsed and T.model and T.model.questId~=nil)
    T.focusLabel:ClearAllPoints();T.focusLabel:SetPoint("TOPLEFT",gap,0)
    local titleY=T.focusLabel:IsShown() and T.focusLabel:GetStringHeight()+spacing.tight*scale or 0
    T.actionIcon:ClearAllPoints();T.actionIcon:SetPoint("TOPLEFT",gap,-titleY-2);T.actionIcon:SetSize(16*scale,16*scale)
    self.title:ClearAllPoints();self.title:SetPoint("TOPLEFT",indent+gap,-titleY)
    local titleWidth=width-indent-gap
    T.skip:SetShown(self.QuestDeferral(T.questTitle.questId)=="暂时不做")
    if T.skip:IsShown() then
        local w=math.ceil(T.skip.text:GetStringWidth())+2*gap
        T.skip:ClearAllPoints();T.skip:SetPoint("TOPRIGHT",0,0);T.skip:SetSize(w,20*scale)
        if not T.focusLabel:IsShown() then titleWidth=titleWidth-w-gap end
    end
    if T.primaryLabel:IsShown() then
        self.title:SetWidth(0)
        titleWidth=math.min(math.ceil(self.title:GetStringWidth()),titleWidth-math.ceil(T.primaryLabel:GetStringWidth())-gap)
        T.primaryLabel:ClearAllPoints();T.primaryLabel:SetPoint("TOPLEFT",indent+2*gap+titleWidth,-titleY-3*scale)
    end
    self.title:SetWidth(math.max(1,titleWidth));self.title:SetMaxLines(2)
    local top=titleY+math.max(20*scale,self.title:GetStringHeight())+gap
    T.currentMark:ClearAllPoints();T.currentMark:SetPoint("TOPLEFT",0,-titleY);T.currentMark:SetSize(3*scale,top-titleY-gap)
    local dungeonSummary=T.model and T.model.dungeonName and T.model.queueLabel~="" and not collapsed
    local labelParent=dungeonSummary and T.card or T.currentChild
    if T.queueLabelParent~=labelParent then T.queueLabel:SetParent(labelParent);T.queueLabelParent=labelParent end
    if dungeonSummary then
        T.queueLabel:ClearAllPoints();T.queueLabel:SetPoint("TOPLEFT",gap,-top);T.queueLabel:SetWidth(inner-gap)
        T.queueLabel:SetText(T.model.queueLabel);T.queueLabel:Show()
        top=top+T.queueLabel:GetStringHeight()+gap
    end
    T.header:ClearAllPoints();T.header:SetPoint("TOPLEFT",0,spacing.tight*scale);T.header:SetSize(width,top)
    T.header:SetShown(not collapsed)
    T.currentScroll:SetWidth(inner);T.currentChild:SetWidth(inner)
    T.reward:ClearAllPoints();T.reward:SetPoint("TOPLEFT",indent,0);T.reward:SetWidth(bodyWidth)
    local rewardInset=T.reward.icon:IsShown() and 14*scale or 0
    T.reward.icon:ClearAllPoints();T.reward.icon:SetPoint("TOPLEFT",0,-2*scale);T.reward.icon:SetSize(11*scale,11*scale)
    T.reward.text:ClearAllPoints();T.reward.text:SetPoint("TOPLEFT",rewardInset,0);T.reward.text:SetWidth(bodyWidth-rewardInset)
    T.reward:SetHeight(T.reward.text:GetStringHeight()+8*scale);T.reward:SetShown((T.reward.text:GetText() or "")~="")
    local childHeight=T.reward:IsShown() and T.reward:GetHeight() or 0
    T.objectiveFrame:ClearAllPoints();T.objectiveFrame:SetPoint("TOPLEFT",indent,-childHeight);T.objectiveFrame:SetWidth(bodyWidth)
    local goals=layoutObjectives(T.objectives,bodyWidth,scale)
    T.objectiveFrame:SetHeight(math.max(1,goals));childHeight=childHeight+goals
    local queueHeight,alongHeight,alongCount,pickups,otherHeight=0,0,0,0,0
    for i,item in ipairs(T.displayRows or {}) do
        local row=T.rows[i]
        local current=item.questId and item.questId==T.model.questId
        row:SetShown(not current)
        if not current then
            if row.atStop then childHeight=childHeight+layoutRow(row,childHeight+4)+4
            elseif row.along then
                alongHeight=alongHeight+layoutRow(row,alongHeight);alongCount=alongCount+1
                if item.kind=="accept" then pickups=pickups+1 end
            elseif item.otherAccepted then otherHeight=otherHeight+layoutRow(row,otherHeight)
            else queueHeight=queueHeight+layoutRow(row,queueHeight) end
        end
    end
    self.body:ClearAllPoints();self.body:SetPoint("TOPLEFT",indent,-childHeight);self.body:SetWidth(bodyWidth)
    self.body:SetShown((self.body:GetText() or "")~="")
    if self.body:IsShown() then childHeight=childHeight+self.body:GetStringHeight()+5 end
    T.footer:ClearAllPoints();T.footer:SetPoint("TOPLEFT",indent,-childHeight);T.footer:SetWidth(bodyWidth)
    T.footer:SetShown((T.footer:GetText() or "")~="")
    if T.footer:IsShown() then childHeight=childHeight+math.max(18*scale,T.footer:GetStringHeight()+spacing.gap*scale) end
    T.gear:ClearAllPoints();T.gear:SetPoint("TOPLEFT",indent,-childHeight);T.gear:SetSize(bodyWidth,spacing.hit*scale)
    T.gear.icon:ClearAllPoints();T.gear.icon:SetPoint("LEFT");T.gear.icon:SetSize(spacing.smallIcon*scale,spacing.smallIcon*scale)
    T.gear.text:ClearAllPoints();T.gear.text:SetPoint("LEFT",(spacing.smallIcon+spacing.gap)*scale,0)
    T.gear.text:SetWidth(bodyWidth-(spacing.smallIcon+spacing.gap+spacing.hit+spacing.tight)*scale)
    T.gear.close:ClearAllPoints();T.gear.close:SetPoint("RIGHT");T.gear.close:SetSize(spacing.hit*scale,spacing.hit*scale)
    T.gear.close.icon:SetSize(spacing.smallIcon*scale,spacing.smallIcon*scale)
    T.gear:SetShown(T.gear.advice~=nil)
    if T.gear:IsShown() then childHeight=childHeight+T.gear:GetHeight()+spacing.tight*scale end
    local clipped=math.max(0,childHeight-({compact=100,normal=200,expanded=280})[density]*scale)
    T.journey:ClearAllPoints();T.journey:SetPoint("TOPLEFT",0,-childHeight-spacing.gap*scale);T.journey:SetWidth(inner)
    T.journey:SetShown(not collapsed and T.model~=nil and T.model.journey~=nil)
    T.journeyHeader:ClearAllPoints();T.journeyHeader:SetPoint("TOPLEFT");T.journeyHeader:SetSize(inner,24*scale)
    T.journeySummary:SetWidth(inner-36*scale);T.journeySummary:SetMaxLines(1)
    T.journeySummary:SetText((T.journeyTime or "")..(T.journeyClosed and "  +" or "  −"))
    local journeyHeight=28*scale
    for i,row in ipairs(T.journeyRows) do
        local shown=(i==1 or not T.journeyClosed) and T.model and T.model.journey and T.model.journey.steps[i]~=nil
        row:SetShown(shown==true)
        if shown then
            row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-journeyHeight);row:SetWidth(inner)
            row.number:ClearAllPoints();row.number:SetPoint("TOPLEFT",0,-2);row.number:SetWidth(16*scale)
            row.icon:ClearAllPoints();row.icon:SetPoint("TOPLEFT",18*scale,-2);row.icon:SetSize(14*scale,14*scale)
            local timeWidth=math.ceil(row.time:GetStringWidth())
            row.title:ClearAllPoints();row.title:SetPoint("TOPLEFT",38*scale,0);row.title:SetWidth(inner-44*scale-timeWidth)
            row.time:ClearAllPoints();row.time:SetPoint("TOPRIGHT",0,0);row.time:SetWidth(timeWidth)
            local height=math.max(18*scale,row.title:GetStringHeight())
            row.detail:ClearAllPoints();row.detail:SetPoint("TOPLEFT",38*scale,-height);row.detail:SetWidth(inner-38*scale)
            row.detail:SetShown((row.detail:GetText() or "")~="")
            if row.detail:IsShown() then height=height+row.detail:GetStringHeight() end
            height=height+spacing.gap*scale;row:SetHeight(height);journeyHeight=journeyHeight+height
        end
    end
    T.journey:SetHeight(journeyHeight)
    if T.journey:IsShown() then childHeight=childHeight+journeyHeight+spacing.section*scale end
    local bottom=childHeight+spacing.gap*scale
    T.thenDivider:ClearAllPoints();T.thenDivider:SetPoint("TOPLEFT",0,-bottom);T.thenDivider:SetSize(inner,1)
    T.thenText:ClearAllPoints();T.thenText:SetPoint("TOPLEFT",0,-bottom-spacing.gap*scale);T.thenText:SetWidth(inner)
    T.thenText:SetShown(not collapsed and (T.thenText:GetText() or "")~="");T.thenButton:SetShown(T.thenText:IsShown())
    T.thenDivider:SetShown(T.thenText:IsShown())
    if T.thenText:IsShown() then
        bottom=bottom+spacing.gap*scale+math.max(spacing.hit*scale,T.thenText:GetStringHeight()+spacing.tight*scale)
        bottom=bottom+layoutRow(T.thenButton,bottom)+spacing.gap*scale
    end
    if not dungeonSummary then
        T.queueLabel:ClearAllPoints();T.queueLabel:SetPoint("TOPLEFT",0,-bottom);T.queueLabel:SetWidth(inner)
        T.queueLabel:SetText(T.model and T.model.queueLabel or T.model and T.model.action and "后续行程" or "已接任务")
        T.queueLabel:SetShown(not collapsed and queueHeight>0)
        if T.queueLabel:IsShown() then bottom=bottom+24*scale end
    end
    T.queuePanel:ClearAllPoints();T.queuePanel:SetPoint("TOPLEFT",0,-bottom)
    T.queueScroll:SetWidth(inner);T.queueChild:SetWidth(inner)
    T.queueChild:SetHeight(math.max(1,queueHeight))
    clipped=clipped+math.max(0,queueHeight-({compact=100,normal=160,expanded=240})[density]*scale)
    local visible=queueHeight
    T.queueScroll:SetHeight(math.max(1,visible));T.queueScroll:SetShown(not collapsed and queueHeight>0)
    T.queuePanel:SetHeight(visible);T.queuePanel:SetShown(not collapsed and queueHeight>0)
    bottom=bottom+(not collapsed and queueHeight>0 and visible+4 or 0)
    T.alongLabel:ClearAllPoints();T.alongLabel:SetPoint("TOPLEFT",0,-bottom);T.alongLabel:SetWidth(inner)
    T.alongLabel:SetText((pickups==alongCount and "顺路可接" or pickups==0 and "顺路可做" or "顺路机会").." · "..alongCount);T.alongLabel:SetShown(not collapsed and alongCount>0)
    if T.alongLabel:IsShown() then bottom=bottom+24*scale end
    T.alongScroll:ClearAllPoints();T.alongScroll:SetPoint("TOPLEFT",0,-bottom);T.alongScroll:SetWidth(inner)
    T.alongChild:SetWidth(inner);T.alongChild:SetHeight(math.max(1,alongHeight))
    clipped=clipped+math.max(0,alongHeight-({compact=75,normal=120,expanded=180})[density]*scale)
    local alongVisible=alongHeight
    T.alongScroll:SetHeight(math.max(1,alongVisible));T.alongScroll:SetShown(not collapsed and alongCount>0)
    if T.alongScroll:IsShown() then bottom=bottom+alongVisible+spacing.gap*scale end
    for rule,label in pairs({[T.queueRule]=T.queueLabel,[T.alongRule]=T.alongLabel}) do
        rule:ClearAllPoints();rule:SetPoint("BOTTOMLEFT",label,"TOPLEFT",0,2*scale)
        rule:SetSize(inner,1);rule:SetColorTexture(unpack(palette.line));rule:SetShown(label:IsShown() and not (dungeonSummary and rule==T.queueRule))
    end
    T.region:SetShown(not collapsed and T.region.region~=nil)
    if T.region:IsShown() then
        T.region:ClearAllPoints();T.region:SetPoint("TOPLEFT",0,-bottom);T.region:SetWidth(inner)
        T.region.rule:ClearAllPoints();T.region.rule:SetPoint("TOPLEFT");T.region.rule:SetSize(inner,1)
        T.region.heading:ClearAllPoints();T.region.heading:SetPoint("TOPLEFT",0,-gap)
        T.region.more:ClearAllPoints();T.region.more:SetPoint("TOPRIGHT",0,-gap);T.region.more:SetSize(spacing.smallIcon*scale,spacing.smallIcon*scale)
        local height=gap+T.region.heading:GetStringHeight()+gap
        local labelWidth=0
        for _,row in ipairs(T.region.rows) do labelWidth=math.max(labelWidth,math.ceil(row.label:GetStringWidth())) end
        for _,row in ipairs(T.region.rows) do
            local visible=(row.value:GetText() or "")~=""
            row.label:SetShown(visible);row.value:SetShown(visible)
            if visible then
                row.label:ClearAllPoints();row.label:SetPoint("TOPLEFT",0,-height)
                row.value:ClearAllPoints();row.value:SetPoint("TOPLEFT",labelWidth+gap,-height);row.value:SetWidth(math.max(1,inner-labelWidth-gap))
                height=height+math.max(row.label:GetStringHeight(),row.value:GetStringHeight())+spacing.tight*scale
            end
        end
        T.region:SetHeight(height);bottom=bottom+height+gap
    end
    for _,notice in ipairs({T.career,T.dungeons}) do
        if notice:IsShown() and (notice~=T.dungeons or not batch) then
            notice:ClearAllPoints();notice:SetPoint("TOPLEFT",0,-bottom)
            bottom=bottom+notice:GetHeight()+gap
        end
    end
    T.otherHeader:SetShown(not collapsed and T.model and (T.model.otherCount or 0)>0)
    T.otherChild:SetShown(T.otherHeader:IsShown() and otherHeight>0)
    if T.otherHeader:IsShown() then
        T.otherLabel:SetText("其他已接任务 · "..T.model.otherCount)
        T.otherToggle:SetText(T.otherOpen and "收起" or "展开")
        T.otherHeader:ClearAllPoints();T.otherHeader:SetPoint("TOPLEFT",0,-bottom);T.otherHeader:SetSize(inner,spacing.hit*scale)
        T.otherChild:ClearAllPoints();T.otherChild:SetPoint("TOPLEFT",T.otherHeader,"BOTTOMLEFT",0,0)
        T.otherChild:SetSize(inner,math.max(1,otherHeight))
        bottom=bottom+T.otherHeader:GetHeight()+otherHeight+gap
        clipped=clipped+math.max(0,otherHeight-160*scale)
    end
    T.progress:SetShown(not collapsed and T.progressRatio~=nil)
    local labelWidth=40*scale
    T.progressText:SetWidth(labelWidth);T.progressText:SetMaxLines(1)
    local barStart=math.ceil(T.progressLabel:GetStringWidth())+gap
    local progressWidth=math.max(1,width-24*scale-labelWidth-barStart)
    T.progressBack:ClearAllPoints();T.progressBack:SetPoint("LEFT",barStart,0);T.progressBack:SetSize(progressWidth,3)
    T.progressFill:ClearAllPoints();T.progressFill:SetPoint("LEFT",barStart,0);T.progressFill:SetSize(math.max(1,progressWidth*(T.progressRatio or 0)),3)
    T.progressFill:SetShown(T.progressRatio~=nil and T.progressRatio>0)
    if T.progressBar then
        T.progressBack:Hide();T.progressFill:Hide()
        T.progressBar:ClearAllPoints();T.progressBar:SetPoint("LEFT",barStart,0);T.progressBar:SetSize(progressWidth,4)
        T.progressBar:SetStatusBarColor(unpack(palette.gold));T.progressBar:SetValue(T.progressRatio or 0)
    end
    local fixed=cardTop+top+24+(T.progress:IsShown() and 24*scale or 0)
    available=math.max(fixed+1,math.floor(available))
    local minHeight=math.min(available,math.max(200,fixed+40*scale))
    self.frame:SetResizeBounds(260,collapsed and fixed or minHeight,800,math.max(1200,minHeight))
    local total=collapsed and fixed or requestedHeight>0 and math.max(minHeight,requestedHeight) or fixed+bottom-(T.model and T.model.dungeonName and 0 or clipped)
    total=math.min(total,available)
    T.currentScroll:ClearAllPoints();T.currentScroll:SetPoint("TOPLEFT",0,-top)
    T.currentScroll:SetHeight(math.max(1,total-fixed));T.currentScroll:SetShown(not collapsed)
    T.currentChild:SetHeight(math.max(1,bottom))
    T.currentScroll:SetVerticalScroll(math.min(T.currentScroll:GetVerticalScroll(),math.max(0,bottom-(total-fixed))))
    T.card:SetHeight(top+(collapsed and 0 or total-fixed))
    T.content:SetHeight(total-20);self.frame:SetHeight(total)
    if A.QuestAssist then A.QuestAssist:LayoutTarget() end
end

-- Keep the catalog lookup off ordinary progress updates. Counts come from the live quest log.
local function dungeonGuideSteps(d,state)
    local inside,other={},{}
    local rows=A.Dungeon.Tasks(d,state,A.Data)
    for _,row in ipairs(rows) do
        local status=UI.DungeonPickupStatus(row,state)
        if status=="需前置" or status=="待确认" then
            local names={}
            for _,id in ipairs(row.preparation or {}) do
                local q=A.Data:GetQuest(id,state)
                names[#names+1]=q and q.title or ("#"..id)
            end
            other[#other+1]={kind="accept",questId=row.id,title=row.title,stageLabel=status,related=status,
                text=#names>0 and table.concat(names,"、") or row.reason}
        elseif row.group<=2 and not row.allowed then
            other[#other+1]={kind=row.group==1 and "turnin" or "objective",questId=row.id,title=row.title,
                stageLabel=status,text=row.reason,related=row.relation=="preparation" and "入本前准备"}
        elseif row.allowed and row.group<=3 then
            local point,item=row.position,row.pickupItem
            local area,index=row.areaId,row.objectiveIndex
            local hits=row.insideObjectives
            if hits and not hits[index] then point,area,index=hits.point,hits.area,hits.first end
            local kind=({"turnin","objective","accept"})[row.group]
            local instance=A.Dungeon.TaskInstance(point,state,A.Data,area)
            local here=instance==d or item and item.held
            local action={kind=kind,questId=row.id,title=row.title,position=point,areaId=area,
                objectiveIndex=index,insideObjectives=hits,text=item and item.text}
            local group=other
            if here then
                group=inside
                if not item then action=A.Dungeon.TaskApproach(action,state,A.Data) end
            else
                local map=point and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(point.map)
                local elsewhere=instance or map and (map.mapType==2 or map.mapType==3) and (not point.areaOnly or point.sourceAreaId)
                if elsewhere then
                    action.stageLabel=({"本外交付","本外目标","本外接取"})[row.group]
                    local place=instance and instance.title or map and map.name
                    local contact=point and point.entityName or row.group==1 and row.recipientName
                    action.text=item and item.text or (place and contact and (place.." · "..contact) or contact or place)
                else
                    action.stageLabel=row.status
                    action.text=item and item.text or "地点待确认"
                end
            end
            action.related=row.relation=="preparation" and "入本前准备" or status=="可重复" and status or nil
            group[#group+1]=action
        end
    end
    return inside,other,UI.DungeonPickupSummary(rows,state)
end

local function questStepHint(action)
    local point=action.position
    if not action.stageLabel and point and point.entityName and not point.travelHint and not point.startItemId then
        if action.kind=="accept" then return "向「"..point.entityName.."」接取任务。" end
        if action.kind=="turnin" then return "到「"..point.entityName.."」交付任务。" end
    end
    return point and point.travelHint or action.text
end

function UI:DungeonTurnedIn(id)
    local roster=self.tracker and self.tracker.instanceRoster
    local s=A.state
    if not roster or not s.inInstance or roster.visit~=(s.instanceId or s.instanceName) or A.char.paused or s.dead then return end
    local title=roster.displayed and roster.displayed[id]
    if not title then return end
    roster.receipts=roster.receipts or {}
    roster.receipts[id]="已交付 · "..title
    A.dirty=true
end

local function dungeonFeedback(roster,state)
    local changes=roster.receipts or {}
    roster.receipts=nil
    if roster.lastLog and roster.lastLog~=state.quests then
        for id,title in pairs(roster.displayed or {}) do
            local old,now=roster.lastLog[id],state.quests[id]
            if old and now and not changes[id] then
                if now.ready and not old.ready then
                    local where="可交付"
                    for _,step in ipairs(roster.inside) do
                        if step.questId==id and step.kind=="turnin" then where="本内可交";break end
                    end
                    for _,step in ipairs(roster.other) do
                        if step.questId==id and step.stageLabel=="本外交付" then where="出本后交";break end
                    end
                    changes[id]="任务完成 · "..title.."（"..where.."）"
                elseif not now.ready then
                    local done={}
                    for i,o in ipairs(now.objectives or {}) do
                        local before=(old.objectives or {})[i]
                        if o.finished and before and not before.finished then done[#done+1]=o.text or title end
                    end
                    if #done>0 then changes[id]="目标完成 · "..table.concat(done,"、") end
                end
            end
        end
    end
    if next(changes) then
        for id,line in pairs(roster.recent or {}) do changes[id]=changes[id] or line end
        roster.recent=changes
        local lines={}
        for _,line in pairs(changes) do lines[#lines+1]=line end
        table.sort(lines)
        roster.feedback=table.concat(lines,"\n")
        C_Timer.After(7,function()
            if UI.tracker.instanceRoster==roster and roster.recent==changes then
                roster.recent,roster.feedback=nil,nil
                A.dirty=true
            end
        end)
    end
    roster.lastLog=state.quests
end

function UI:DungeonTrackerModel(state,action)
    local tracker=self.tracker
    local dungeon=state.inInstance and A.DungeonCatalog and A.DungeonCatalog.entries["reference:"..tostring(state.instanceId)]
    if not state.inInstance or not (dungeon or state.instanceType=="party" or state.instanceType=="raid") then
        if tracker.instanceRoster then
            tracker.currentScroll:SetVerticalScroll(tracker.instanceRoster.outdoorScroll)
            tracker.instanceRoster=nil
        end
        return
    end
    local visit=state.instanceId or state.instanceName
    local roster=tracker.instanceRoster
    if not roster or roster.visit~=visit then
        roster={visit=visit,outdoorScroll=roster and roster.outdoorScroll or tracker.currentScroll:GetVerticalScroll()}
        tracker.instanceRoster=roster
        tracker.currentScroll:SetVerticalScroll(0)
    end
    if not roster.inside or roster.dungeon~=dungeon or roster.revision~=state.revision or roster.indexReady~=A.indexReady then
        if dungeon and A.indexReady then roster.inside,roster.other,roster.pickups=dungeonGuideSteps(dungeon,state)
        else roster.inside,roster.other,roster.pickups={},{},nil end
        roster.dungeon,roster.revision,roster.indexReady=dungeon,state.revision,A.indexReady
    end
    local model={dungeonName=state.instanceName or dungeon and dungeon.title or "地下城",dungeonId=dungeon and dungeon.id,
        title="副本任务",rows={},objectives={},along={}}
    local statuses={accept="未接取",objective="进行中",turnin="可交付"}
    local seen={}
    local focus=not A.char.paused and not state.dead and (A.Navigation.manual or A.Navigation.planInstance==state.instanceId and state.instanceId) and action
    local function add(step,fallbackHint)
        local id=step.questId
        if not id or seen[id] or not statuses[step.kind] then return end
        local active=state.quests[id]
        local kind=active and (active.ready and "turnin" or "objective") or step.kind
        local status=statuses[kind]
        local hint=questStepHint(step) or fallbackHint
        if step.stageLabel=="本外接取" or step.stageLabel=="本外目标" or step.stageLabel=="本外交付" then
            hint=step.stageLabel..(hint and (" · "..hint) or "")
        end
        if step.related then hint=step.related..(hint and (" · "..hint) or "") end
        if kind=="accept" and not step.related and state.questLimit and state.questCount and state.questCount>=state.questLimit then
            hint=(hint and hint.." · " or "").."任务日志已满"
        end
        local goals={}
        for i,o in ipairs(kind=="objective" and active and active.objectives or {}) do
            if o.finished or not step.insideObjectives or step.insideObjectives[i] then goals[#goals+1]=o end
        end
        if #goals>0 and not step.stageLabel and not (step.position and step.position.travelHint) then hint=nil end
        seen[id]=step.title or ("任务 #"..id)
        model.rows[#model.rows+1]={questId=id,title=seen[id],kind=kind,status=status,accepted=active~=nil,related=step.related,
            progress=hint or "",objectives=goals,dungeonAction=(step.position or step.areaId or not step.stageLabel and step.text) and step or nil}
    end
    if focus and statuses[focus.kind] then
        local focusStep
        for _,list in ipairs({roster.inside,roster.other}) do
            for _,step in ipairs(list) do
                if step.questId==focus.questId then focusStep=step;break end
            end
            if focusStep then break end
        end
        if focusStep then
            add(focusStep,focusStep.kind==focus.kind and focus.text)
        elseif not A.indexReady or not dungeon then add(focus) end
    elseif focus and (focus.kind=="dungeonLeave" or focus.kind=="dungeonRun" or focus.kind=="selectionBlocked") then
        model.instruction=focus.text or focus.title
    end
    for _,step in ipairs(roster.inside) do add(step) end
    for _,step in ipairs(roster.other) do add(step) end
    dungeonFeedback(roster,state);roster.displayed=seen
    model.queueLabel=roster.pickups or ""
    -- Group the display only. Keep the guide's ordering within each section.
    local ordered={}
    for _,kind in ipairs({"focus","accept","objective","turnin","related"}) do
        local number=0
        for _,row in ipairs(model.rows) do
            local group=focus and row.questId==focus.questId and "focus" or row.related and "related" or row.kind
            if group==kind then
                number=number+1
                row.group,row.number=kind,number
                ordered[#ordered+1]=row
            end
        end
    end
    model.rows=ordered
    if #model.rows==0 and not model.instruction then
        model.instruction=A.indexReady and "当前没有可显示的副本任务。" or "正在读取副本任务。"
    end
    model.feedback=roster.feedback
    return model
end

local questVerbs={accept="接取",objective="完成",turnin="交付"}
local stepLabels={accept="接取任务",objective="任务目标",turnin="交付任务",move="步行",approach="步行",
    dungeonEnter="进入副本",dungeonLeave="离开副本",flight="飞行",hearthCast="使用炉石"}
local vehicles={boat="船",tram="地铁",zeppelin="飞艇"}
local transitLabels={boat="乘船",tram="乘地铁",zeppelin="乘飞艇",hearth="使用炉石",portal="穿过传送门",flight="搭乘航班"}

local function navigationInstruction(action,journey)
    local nav=A.Navigation
    if journey and journey.action==action and action.kind~="flight" and action.kind~="hearthCast" and journey.atDeparture==action.atDeparture and
        nav.atTransitDestination~=action and A.settings.transportHints~=false then
        -- The tracker already expands transport legs into walks and connections.
        local first,second=journey.steps[1],journey.steps[2]
        return placeText(first.title,first.place),nil,second and placeText(second.title,second.place),stepIcon(first),second and stepIcon(second)
    end
    local heading=transitLabels[action.mode] or stepLabels[action.kind] or "当前步骤"
    local sequence=routeSequence(A.state)
    local index=sequence and sequence.index
    local nextStep,counter
    local leg=action.kind=="flight" and A.Transport and A.Transport.flight or
        action.kind=="hearthCast" and A.Hearth and (A.Hearth.cast or A.Hearth.pending)
    if sequence and sequence.actions and #sequence.actions>1 and sequence.actions[index]==(leg and leg.action or action) then
        counter=string.format("%d/%d",index,#sequence.actions)
        nextStep=sequence.actions[index+1]
    end
    local target=nav.Target(action)
    local hint=target and target.spawnArea and " · 出没区域" or target and target.approximate and (target.sourceKind=="patrol" and " · 巡逻路线" or " · 区域参考点") or ""
    local title=action.title or heading
    if action.title and (action.kind=="accept" or action.kind=="turnin") then title=questVerbs[action.kind].."「"..title.."」" end
    local detail=questStepHint(action)
    if action.kind=="objective" and target and target.sourceKind=="vendor" then
        detail=UI.ActionText(action,A.settings)
    elseif action.kind=="objective" and action.objectiveIndex and not (target and target.travelHint) then
        local quest=(A.state.quests or {})[action.questId]
        local goal=quest and (quest.objectives or {})[action.objectiveIndex]
        detail=goal and goal.text or detail
    elseif action.kind=="transit" then
        if nav.atTransitDestination==action then title,detail="已抵达本段终点",nil
        elseif A.settings.transportHints==false then detail=nil
        elseif action.atDeparture and vehicles[action.mode] and action.toName then
            title,detail="搭乘开往"..action.toName.."的"..vehicles[action.mode],nil
        end
    end
    if detail==title then detail=nil end
    local following
    if nextStep and nextStep.title and not (nav.StaleAction and nav.StaleAction(nextStep,A.state,sequence.plan)) then
        local verb=questVerbs[nextStep.kind]
        following=verb and verb.."「"..nextStep.title.."」" or placeText(nextStep.title,nextStep.toName,nextStep.position and nextStep.position.siteName)
    end
    local place=action.toName or action.siteName or target and target.siteName
    if not questVerbs[action.kind] and not (action.questAction and action.title==action.questAction.title) then
        title=placeText(title,place,action.fromName)
    end
    detail=placeText(detail,place,action.fromPlace or action.fromName or action.roomName)
    local location=(action.kind=="turnin" or target and target.sourceKind=="escortStart") and mapLocation(target)
    if location then
        if target.entityName and not (action.stageLabel or target.travelHint or action.roomName) then
            detail=target.entityName.." · "..location
        else
            detail=location..(detail and ("\n"..detail) or "")
        end
    end
    return title..hint,detail,following,stepIcon(action),following and stepIcon(nextStep),counter
end

function UI:SetTrackerNavigation(distance,angle,unverified,action)
    if not self.navFrame then return end
    action=action or distance and A.Navigation:Current()
    local guide=action~=nil and not A.char.paused
    self.navFrame.questId=guide and questVerbs[action.kind] and action.questId or nil
    local itemHeight=A.QuestAssist and A.QuestAssist:NavigationItems(action,guide) or 0
    self.navFrame:SetShown(guide or itemHeight>0)
    if not guide and itemHeight==0 then return end
    local T=self.tracker
    local title,detail,following,icon,nextIcon,meta
    if guide then title,detail,following,icon,nextIcon,meta=navigationInstruction(action,T.model and T.model.journey)
    else title,icon="任务物品","collect" end
    if A.settings.arrow and distance then
        local meters=A.settings.distanceUnits=="meters"
        local value=string.format("%.0f %s",meters and distance*0.9144 or distance,meters and "米" or "码")
        meta=meta and meta.." · "..value or value
    end
    angle=A.settings.arrow and angle or nil
    local scale=self:FontScale()
    if T.navScale~=scale or (self.nav:GetText() or "")~=(meta or "") then
        self.nav:SetText(meta or "")
        T.navMetaWidth=meta and math.ceil(self.nav:GetStringWidth())+spacing.gap*scale or 0
    end
    local nextText=following and ("下一步  "..following) or ""
    local inset=spacing.padding*scale
    local metaRight=angle and inset+20*scale or inset
    local reserved=T.navMetaWidth+metaRight
    local width=self.navAnchor:GetWidth()
    if T.navScale~=scale or T.navReserved~=reserved or T.navWidth~=width or T.navItemHeight~=itemHeight or T.navTitle:GetText()~=title or
        (T.navDetail:GetText() or "")~=(detail or "") or (T.navNext:GetText() or "")~=nextText or T.navKind~=icon or T.navNextKind~=nextIcon then
        T.navScale,T.navReserved,T.navKind,T.navNextKind=scale,reserved,icon,nextIcon
        T.navWidth,T.navItemHeight=width,itemHeight
        local left=inset+spacing.indent*scale
        local textWidth=width-left-inset
        local function place(widget,x,y)
            widget:ClearAllPoints();widget:SetPoint("TOPLEFT",self.navFrame,"TOPLEFT",x,-y)
        end
        setHUDIcon(T.navIcon,icon)
        T.navIcon:SetSize(spacing.icon*scale,spacing.icon*scale);place(T.navIcon,inset,inset)
        T.navTitle:SetWidth(width-left-reserved);T.navTitle:SetText(title);place(T.navTitle,left,inset)
        self.nav:ClearAllPoints();self.nav:SetPoint("TOPRIGHT",self.navFrame,"TOPRIGHT",-metaRight,-inset)
        T.navBearing:SetSize(spacing.icon*scale,spacing.icon*scale)
        T.navBearing:ClearAllPoints();T.navBearing:SetPoint("TOPRIGHT",self.navFrame,"TOPRIGHT",-inset,-inset)
        T.navBearing:SetVertexColor(self:Accent())
        local y=inset+math.max(spacing.icon*scale,T.navTitle:GetStringHeight())
        T.navDetail:SetText(detail or "");T.navDetail:SetShown(detail~=nil and detail~="")
        if T.navDetail:IsShown() then
            y=y+spacing.tight*scale
            T.navDetail:SetWidth(textWidth);place(T.navDetail,left,y);y=y+T.navDetail:GetStringHeight()
        end
        T.navNext:SetText(nextText);T.navNext:SetShown(following~=nil)
        T.navRule:SetShown(following~=nil);T.navNextIcon:SetShown(following~=nil)
        if following then
            y=y+spacing.gap*scale
            T.navRule:SetColorTexture(unpack(palette.line));T.navRule:SetSize(width-2*inset,1);place(T.navRule,inset,y)
            y=y+1+spacing.gap*scale
            setHUDIcon(T.navNextIcon,nextIcon,true);T.navNextIcon:SetSize(spacing.smallIcon*scale,spacing.smallIcon*scale)
            place(T.navNextIcon,inset+2*scale,y+scale)
            T.navNext:SetWidth(textWidth);place(T.navNext,left,y);y=y+math.max(spacing.smallIcon*scale,T.navNext:GetStringHeight())
        end
        local height=y+inset+itemHeight
        if self.navFrame:GetWidth()~=width or self.navFrame:GetHeight()~=height then
            self.navFrame:SetSize(width,height)
            if not InCombatLockdown() then self.navAnchor:SetClampRectInsets(0,0,math.max(0,height-48),0) end
        end
    end
    T.navBearing:SetShown(angle~=nil)
    if angle then T.navBearing:SetRotation(-angle) end
end
