local _,A=...
local UI=A.UI
local palette={
    white={0.96,0.97,0.99},muted={0.70,0.73,0.80},
    gold={0.90,0.73,0.40},green={0.42,0.85,0.60},blue={0.58,0.79,1},purple={0.78,0.68,1},
    line={0.65,0.70,0.82,0.18},
}
local media="Interface\\AddOns\\AiLeveling\\Media\\"

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

local function destination(action)
    local point=action and action.position
    if A.Navigation and A.Navigation.Target then point=A.Navigation.Target(action) end
    point=point or action and action.recipient
    if not point then return end
    local map=point.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(point.map)
    local name=point.entityName or action.recipient and action.recipient.entityName
    local zone=map and map.name
    return name and (name..(zone and zone~=name and " · "..zone or "")) or zone,name or zone,name and zone~=name and zone
end

local function clockText(seconds)
    if seconds==nil then return "—" end
    seconds=math.max(0,math.ceil(seconds))
    return string.format("%d:%02d",math.floor(seconds/60),seconds%60)
end

local function placeName(point,fallback)
    local map=point and point.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(point.map)
    return point and point.entityName or fallback or map and map.name or "任务地点"
end

function UI.TrackerJourney(state,action)
    local nav=A.Navigation
    if not action or not nav or nav.manual or not nav.actions or not A.Travel then return end
    local index=nav.index or 1
    local current=nav.actions[index]
    local flight=A.Transport and A.Transport.flight
    local hearth=A.Hearth and (A.Hearth.cast or A.Hearth.pending)
    local flying=action.kind=="flight" and flight and flight.action==current
    local returning=action.kind=="hearthCast" and hearth and hearth.action==current
    if not current or current~=action and not flying and not returning then return end
    local result={steps={},seconds=0,distance=0}
    local position,transport=state.position,false
    local function add(kind,title,seconds,detail)
        seconds=seconds and math.max(0,math.ceil(seconds))
        result.steps[#result.steps+1]={kind=kind,title=title,seconds=seconds,detail=detail}
        result.seconds=result.seconds and seconds and result.seconds+seconds or nil
    end
    local function walk(point,name,radius)
        local seconds,distance=A.Travel.Walk(position,point,state,nav)
        if seconds~=0 and (not distance or distance>(radius or 12)) then
            add("walk","走到 "..placeName(point,name),seconds)
            result.distance=result.distance and distance and result.distance+distance or nil
        end
        position=point
    end
    for i=index,#nav.actions do
        local step=nav.actions[i]
        if nav.StaleAction and nav.StaleAction(step,state,nav.plan) then return end
        if step.kind=="transit" then
            transport=true
            local boarded=i==index and (flying or returning or step.atDeparture)
            local from=step.fromTaxi and ((state.taxiNames or {})[step.fromTaxi] or
                A.FlightData and A.FlightData.nodes[step.fromTaxi] and A.FlightData.nodes[step.fromTaxi].name)
            if not boarded and step.mode~="hearth" then walk(step.departure,step.fromName or from,step.departureRadius) end
            local seconds,detail=step.travelSeconds,nil
            if flying and i==index and flight.duration and flight.observedStart then
                seconds=math.max(0,flight.duration-(GetTime()-flight.started));detail="飞行中"
            elseif returning and i==index then
                seconds=step.travelRide and math.max(0,step.travelRide-(GetTime()-hearth.started));detail="炉石返回中"
            elseif step.publicTransit and step.travelWait and step.travelRide then
                detail="平均等候 "..clockText(step.travelWait).." · 乘坐 "..clockText(step.travelRide)
            end
            add(step.mode,step.title or "前往 "..placeName(step.position,step.toName),seconds,detail)
            position=step.position
        elseif step.kind=="move" or step.kind=="approach" then
            walk(step.position,step.title~="前往下一目的地" and step.title or nil,step.arrival)
        else
            result.goal=step
            walk(step.position,nil,step.arrival)
            local verb=({accept="接取",objective="完成",turnin="交付"})[step.kind]
            if verb then
                result.steps[#result.steps+1]={kind=step.kind,title=verb.." "..(step.title or "任务"),task=true}
            end
            break
        end
    end
    if transport and result.goal then return result end
end

local function nextAction(action,plan,state,rows)
    if not action or action.kind=="manual" then return end
    local function listed(stage,id)
        for _,row in ipairs(rows) do
            if (row.atStop or row.along) and row.questId==id and row.kind==stage.kind and
                (stage.kind~="objective" or stage.objectiveIndex==(row.sharedObjective or row.sideAction and row.sideAction.objectiveIndex)) then return true end
        end
    end
    local navigation=A.Navigation
    if navigation and navigation.actions and navigation.actions[navigation.index]==action then
        for i=navigation.index+1,#navigation.actions do
            local stage=navigation.actions[i]
            if stage.kind~="move" and not listed(stage,stage.questId) then return stage,stage.questId,stage.title end
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
        if active and active.ready and name and not choice.itemShortage and not choice.lowValue and not choice.entryBlocked and
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

function UI.TrackerModel(state,plan,action,paused)
    state,plan=state or {},plan or {}
    local quests=state.quests or {}
    local journey=not paused and not A.error and UI.TrackerJourney(state,action) or nil
    action=journey and journey.goal or action
    if A.Navigation and A.Navigation.StaleAction and A.Navigation.StaleAction(action,state,plan) or
        action and action.questId and UI.QuestStatus(state,action.questId,plan)=="已交付" then action=nil end
    local model={journey=journey,action=action,rows={},objectives={},acceptedCount=0,unacceptedCount=0,title=action and action.title or "正在寻找下一步",kind=action and action.kind,
        instruction=action and UI.ActionText(action,A.settings or {}) or "",questId=action and action.questId}
    local active=action and quests[action.questId]
    if active then
        model.title=active.title or model.title
        for _,objective in ipairs(active.objectives or {}) do
            model.objectives[#model.objectives+1]={text=objective.text or "任务目标",done=objective.finished==true,type=objective.type,
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
            if quests[id] and not seen[id] and not choice.lowValue and not choice.entryBlocked and
                not (state.skipped or {})[id] and not (state.chainDeferred or {})[id] and (not state.locked or state.locked==id) then
                seen[id]=true
                local last=choice.stages and choice.stages[#choice.stages]
                for _,requirement in ipairs(last and last.itemRequirements or {}) do
                    if requirement.targetId==action.targetId then total=total+(requirement.need or 0) end
                end
            end
        end
        local need=math.max(have+action.itemGain,total)
        local limit=A.TaskGuide and A.TaskGuide.ItemLimit and A.TaskGuide.ItemLimit(action.targetId,state)
        if limit then need=math.min(need,limit) end
        model.objectives[#model.objectives+1]={text="本次所需物品",done=false,have=have,need=need}
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
        model.metrics=metrics(choice,journey)
        model.unlock=choice.unlock
        if (A.settings or {}).rewardAdvice~=false then model.reward=choice.gear end
    end
    if A.TaskGuide then groups,byQuest=A.TaskGuide.DeliveryGroups(plan.taskChoices,state,plan.taskOrder) end
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
    local seen={}
    if action and action.questId and not currentGroup then seen[action.questId]=true end
    local function add(id,source)
        if not id or seen[id] then return end
        seen[id]=true
        local q=quests[id]
        local status=UI.QuestStatus(state,id,plan)
        if status=="已交付" then return end
        local candidate=choices[id]
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
                    pickup.position and pickup.position.startItemId and pickup.text or pickupPlace and ("接取："..pickupPlace) or "先接取，再推进任务目标"),deferred=deferred,candidate=candidate,
            shared=sharedByQuest[id] and true,sharedObjective=sharedByQuest[id]}
        if sharedByQuest[id] then
            local row=model.rows[#model.rows]
            row.progress=(sharedKind=="item" and "一并收集 · " or "一起推进 · ")..row.progress
        end
        if candidate and candidate.lowValue then
            local row=model.rows[#model.rows]
            row.progress=candidate.lowValue.suggestion.." · "..(candidate.lowValue.summary or "低经验／无装备提升／无任务线")
        elseif candidate and candidate.entryBlocked then
            model.rows[#model.rows].progress=candidate.entryBlocked
        end
        if q then model.acceptedCount=model.acceptedCount+1 else model.unacceptedCount=model.unacceptedCount+1 end
    end
    if plan.best then
        for i=A.Navigation and A.Navigation.index or 1,#(plan.best.actions or {}) do
            local step=plan.best.actions[i]
            if step.questId then planned[step.questId]=planned[step.questId] or i end
            if step.kind~="move" then add(step.questId,step) end
        end
    end
    -- Nearby work is optional: compare the extra straight-line walk without changing navigation.
    local along={}
    local navigation=A.Navigation
    local target=action and (navigation and navigation.Target and navigation.Target(action) or action.position)
    local direct=not paused and not A.error and action and action.questId and
        (action.kind=="accept" or action.kind=="objective" or action.kind=="turnin") and navigation and navigation.Distance and
        navigation:Distance(state.position,target)
    local speed=state.runSpeed
    if direct and speed and speed>0 then
        for _,choice in ipairs(plan.taskChoices or {}) do
            local id=choice.questId
            local q=quests[id]
            if id~=model.questId and not (state.skipped or {})[id] and not (state.chainDeferred or {})[id] and
                not choice.lowValue and not choice.acceptBlocked and not choice.entryBlocked and not choice.requireCheck then
                local kind=not q and "accept" or q.ready and not choice.itemShortage and "turnin" or "objective"
                local step=choice.executionAction or (choice.actions or {})[1]
                for _,stage in ipairs(choice.stages or {}) do
                    local objective=q and stage.objectiveIndex and (q.objectives or {})[stage.objectiveIndex]
                    if stage.kind==kind and (not (objective and objective.finished) or stage.itemGain and stage.itemGain>0) then step=stage;break end
                end
                local group=byQuest[id]
                local waiting=kind=="turnin" and group and not group.splitDelivery and group.ready<#group.choices
                local objective=q and step and step.objectiveIndex and (q.objectives or {})[step.objectiveIndex]
                if step and step.kind==kind and step.position and not waiting and
                    (not (objective and objective.finished) or step.itemGain and step.itemGain>0) then
                    local approach=navigation:Distance(state.position,step.position)
                    local onward=navigation:Distance(step.position,target)
                    if approach and onward and approach<=math.max(direct,180) and onward<=math.max(direct,180) and
                        (kind~="objective" or approach<=180) and math.max(0,approach+onward-direct)/speed<=20 then
                        along[id]={action=step,distance=approach}
                        add(id,step)
                    end
                end
            end
        end
    end
    for _,choice in ipairs(plan.taskOrder or plan.taskChoices or {}) do
        add(choice.questId,choice.executionAction or choice.actions[1])
    end
    local rest={}
    for id in pairs(quests) do if not seen[id] then rest[#rest+1]=id end end
    table.sort(rest);for _,id in ipairs(rest) do add(id) end
    for _,choice in ipairs(plan.taskChoices or {}) do add(choice.questId,choice.actions[1]) end
    local ranked={}
    for _,row in ipairs(model.rows) do if not (row.candidate and row.candidate.lowValue) then ranked[#ranked+1]=row end end
    for _,row in ipairs(model.rows) do if row.candidate and row.candidate.lowValue then ranked[#ranked+1]=row end end
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
    for _,row in ipairs(model.rows) do
        row.delivery=deliveries[row.questId]
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
        model.nextStep,model.nextId,model.nextTitle=nextAction(action,plan,state,model.rows)
    end
    local visible={}
    for _,row in ipairs(model.rows) do
        local candidate=row.candidate or {}
        local eligible=not row.deferred and not candidate.lowValue and not candidate.acceptBlocked and
            not candidate.entryBlocked and not candidate.requireCheck
        if row.questId==model.questId or row.atStop or row.along or eligible and row.planOrder and row.questId~=model.nextId then
            visible[#visible+1]=row
        end
    end
    table.sort(visible,function(a,b)
        local function order(row)
            return row.questId==model.questId and 0 or row.atStop and 1 or row.along and 2 or 3
        end
        local ar,br=order(a),order(b)
        if ar~=br then return ar<br end
        if ar==2 and a.alongDistance~=b.alongDistance then return (a.alongDistance or 0)<(b.alongDistance or 0) end
        if a.planOrder~=b.planOrder then return (a.planOrder or math.huge)<(b.planOrder or math.huge) end
        return a.questId<b.questId
    end)
    model.rows=visible
    if not action then
        if plan.complete then model.title="已达到 60 级";model.instruction="本次升级目标已完成。"
        elseif plan.revision and plan.revision~=state.revision then model.title="正在更新行程";model.instruction="正在安排下一步。"
        elseif plan.selectionBlocked then model.title="所选行程等待处理";model.instruction=plan.selectionBlocked
        elseif not A.indexReady then model.title="正在整理任务";model.instruction="任务数据加载后显示当前步骤。"
        else model.title="选择下一项任务";model.instruction="右键任务可选择优先做，左键查看详情。" end
    end
    if paused then model.instruction="引导已暂停，右键标题栏可继续引导。";model.hint=nil;model.deliverySummary=nil end
    if A.error then model.title="需要处理";model.instruction=A.error;model.hint=nil;model.deliverySummary=nil end
    return model
end

local function text(parent,size,color)
    local value=UI:Text(parent,size,color or palette.white,"OUTLINE")
    value:SetShadowColor(0,0,0,1);value:SetShadowOffset(1,-1)
    return value
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
    line.text=text(line,size or 13,color or palette.green);line.text:SetPoint("TOPLEFT");line.text:SetPoint("TOPRIGHT")
    line:SetHyperlinksEnabled(true)
    line:SetScript("OnHyperlinkClick",function(_,link,label,button)
        local id=link:match("^quest:(%d+)")
        if id then UI:QuestClick(tonumber(id),button) else SetItemRef(link,label,button) end
    end)
    line:SetScript("OnHyperlinkEnter",function(owner,link)
        GameTooltip:SetOwner(owner,"ANCHOR_LEFT");GameTooltip:SetHyperlink(link)
        if owner.advice then
            local upgrade=owner.advice.upgrade
            local _,label=A.Gear.Model(A.state)
            GameTooltip:AddLine(string.format("%s · 属性评分 %.1f → %.1f",label,upgrade.oldScore,upgrade.newScore),0.42,0.85,0.60,true)
            local links=gearLinks(owner.advice)
            if links~=owner.advice.item.link then GameTooltip:AddLine("换装搭配："..links,1,1,1,true) end
        end
        GameTooltip:Show()
        if link:match("^item:") and GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
    end)
    line:SetScript("OnHyperlinkLeave",function() GameTooltip:Hide() end)
    return line
end

function UI.ClassReminders(state,plan)
    local quests={}
    if A.TaskGuide and plan.revision==state.revision then
        for _,choice in ipairs(plan.taskChoices or {}) do
            local id=choice.questId
            if id and not (state.quests or {})[id] and not (state.completed or {})[id] and
                not (state.skipped or {})[id] and not (state.chainDeferred or {})[id] and
                not choice.lowValue and not choice.entryBlocked and not choice.acceptBlocked and not choice.requireCheck then
                if choice.unlock or A.TaskGuide.IsClassQuest(A.Data:GetQuest(id),state,A.Data) then
                    quests[#quests+1]=choice
                end
            end
        end
    end
    return {spells=state.trainableSpells or {},quests=quests}
end

function UI:ClassReminderMenu(owner)
    local reminder=self.ClassReminders(A.state,A.plan or {})
    GameTooltip:Hide()
    MenuUtil.CreateContextMenu(owner,function(_,menu)
        for _,spell in ipairs(reminder.spells) do
            menu:CreateButton(spell.name.." · "..spell.level.."级",function() SetItemRef("spell:"..spell.id,spell.link,"LeftButton") end)
        end
        for _,choice in ipairs(reminder.quests) do
            menu:CreateButton("待接："..choice.title,function() self:QuestClick(choice.questId,"LeftButton") end)
        end
        menu:CreateButton("查看职业任务",function() self.details:Show();self:SelectTab(9) end)
    end)
end

local function questTooltip(owner)
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    if owner.dungeonId then
        GameTooltip:SetText("左键：查看副本任务")
        GameTooltip:AddLine("右键：安排整组任务",1,1,1,true);GameTooltip:Show();return
    end
    local quest=owner.questId and (A.state.quests or {})[owner.questId]
    GameTooltip:SetText(quest and quest.title or owner.candidate and owner.candidate.title or "当前步骤")
    if owner.detail then GameTooltip:AddLine(owner.detail,0.94,0.91,0.83,true)
    elseif owner.progress then GameTooltip:AddLine(owner.progress:GetText(),0.94,0.91,0.83,true) end
    if owner.metrics then GameTooltip:AddLine(owner.metrics,1,0.83,0.45,true) end
    if owner.questId then GameTooltip:AddLine("右键：任务操作\nShift+左键：插入任务链接",1,1,1,true) end
    GameTooltip:Show()
end

function UI:TrackerMenu(owner)
    local id,candidate,revision=owner.questId,owner.candidate,owner.revision
    local action=owner==self.tracker.questTitle and self.tracker.action
    GameTooltip:Hide()
    MenuUtil.CreateContextMenu(owner,function(_,menu)
        if owner.dungeonId then
            menu:CreateButton("安排整组任务",function()
                local ok,why=A.Selection.CanChoose(candidate,revision)
                if ok then ok,why=A.Dungeon:StartTaskBatch(owner.dungeonId) end
                if not ok then A:Message(why) end
            end)
        elseif action and action.kind=="manual" then
            menu:CreateButton("返回任务",function() A.Navigation:ClearManual() end)
        elseif action and action.kind=="service" and action.serviceKind=="repair" then
            menu:CreateButton("忽略维修",function() A.Supplies:IgnoreRepair() end)
        elseif id then
            menu:CreateButton("查看任务详情",function() self:QuestClick(id,"RightButton") end)
            local choose=menu:CreateButton("优先做此任务",function()
                local ok,why
                if candidate then ok,why=A.Selection:Lock(candidate,revision)
                else ok,why=A.Selection:LockQuest(id) end
                if not ok then A:Message(why) end
            end)
            choose:SetEnabled(not owner.deferred and (not candidate or A.Selection.CanChoose(candidate,revision)==true))
            menu:CreateButton("暂缓此任务",function() A.Selection:Skip(id) end):SetEnabled(not owner.deferred)
        end
        if A.char.locked or A.char.itinerary then
            menu:CreateButton("恢复自动安排",function()
                local ok,why=A.Selection:Automatic();if not ok then A:Message(why) end
            end)
        end
        if A.char.serviceStop then
            menu:CreateButton("取消服务，继续任务",function() A.Services:Cancel() end)
        end
        if owner==self.frame or not id and not owner.dungeonId then
            menu:CreateButton(A.char.paused and "继续引导" or "暂停引导",function() A:TogglePause() end)
            menu:CreateButton("详细面板",function() self:ToggleDetails() end)
            if next(A.char.ignoredGear or {}) or (A.Gear and next(A.Gear.dismissedGear or {})) then
                menu:CreateButton("恢复装备提醒",function() A.char.ignoredGear={};A.Gear.dismissedGear={};self:RenderTracker() end)
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
    self:Rounded(f,5);f:SetBackdropColor(0.07,0.085,0.14,0.80);f.material:Hide()
    local T=self.tracker
    T.header=f:CreateTexture(nil,"BACKGROUND");T.header:SetTexture(media.."hud-header.tga")
    T.header:SetPoint("TOPLEFT",4,-4);T.header:SetPoint("TOPRIGHT",-4,-4)
    T.headerLine=f:CreateTexture(nil,"ARTWORK");T.headerLine:SetColorTexture(unpack(palette.gold))
    T.headerLine:SetPoint("TOPLEFT",8,0);T.headerLine:SetPoint("TOPRIGHT",-8,0);T.headerLine:SetHeight(2)
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
    T.content=CreateFrame("Frame",nil,f);T.content:SetPoint("TOPLEFT",10,-10)
    T.zone=text(T.content,14,palette.white);T.zone:SetPoint("TOPLEFT",0,0)
    T.zone:SetText("当前行程");T.zone:SetMaxLines(1)
    T.experience=text(T.content,12,palette.muted);T.experience:SetJustifyH("RIGHT")
    T.collapse=self:Button(T.content,"−",20,function() self.folded=not self.folded;self:LayoutTracker() end,16)
    T.menu=self:Button(T.content,"≡",22,function() self:TrackerMenu(f) end,16)
    for _,button in ipairs({T.collapse,T.menu}) do
        button.baseColor={0,0,0,0};button:SetBackdropColor(0,0,0,0);button.text:SetTextColor(unpack(palette.muted))
        button:SetScript("OnEnter",function()
            button:SetBackdropColor(0.50,0.60,0.85,0.14)
            GameTooltip:SetOwner(button,"ANCHOR_TOP");GameTooltip:SetText(button==T.menu and "行程菜单" or "收起／展开")
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave",function() button:SetBackdropColor(0,0,0,0);GameTooltip:Hide() end)
    end
    T.divider=T.content:CreateTexture(nil,"BACKGROUND");T.divider:SetColorTexture(unpack(palette.line))
    T.career=noticeLine(T.content)
    T.career.text:SetTextColor(unpack(palette.gold))
    T.career.view=self:Button(T.career,"查看",48,function() self:ClassReminderMenu(T.career) end,12)
    T.career.train=self:Button(T.career,"去训练",64,function()
        local rows=A.Services:Choices("classTrain")
        local ok,why
        if rows[1] then ok,why=A.Services:Pick(rows[1],A.state.revision)
        else why="没有找到本职业训练师的位置" end
        if not ok then A:Message(why) end
    end,12)
    T.career.later=self:Button(T.career,"稍后",48,function()
        A.char.classReminderLevel=A.state.level;self:RenderTracker()
    end,12)
    for _,button in ipairs({T.career.view,T.career.train,T.career.later}) do
        button.baseColor={0,0,0,0};button:SetBackdropColor(0,0,0,0)
    end
    T.career.later:SetScript("OnEnter",function(button)
        GameTooltip:SetOwner(button,"ANCHOR_TOP");GameTooltip:SetText("本级不再提醒；可在行程菜单恢复");GameTooltip:Show()
    end)
    T.career.later:SetScript("OnLeave",function() GameTooltip:Hide() end)
    T.gear=noticeLine(T.content,12,palette.white)
    T.gear.text:SetNonSpaceWrap(false)
    T.gear.shade=T.gear:CreateTexture(nil,"BACKGROUND");T.gear.shade:SetAllPoints()
    T.gear.shade:SetColorTexture(0.90,0.73,0.40,0.10)
    T.gear.rule=T.gear:CreateTexture(nil,"BORDER");T.gear.rule:SetColorTexture(1,1,1,0.10)
    T.gear.icon=T.gear:CreateTexture(nil,"ARTWORK");T.gear.icon:SetTexture(media.."hud-equip.tga")
    T.gear.icon:SetVertexColor(unpack(palette.gold))
    local dim={0.765,0.793,0.868}
    for _,key in ipairs({"equip","ignore"}) do
        local button=CreateFrame("Button",nil,T.gear);T.gear[key]=button
        local color=key=="equip" and palette.gold or dim
        button.text=text(button,12,color);button.text:SetPoint("LEFT",0,0)
        button.text:SetText(key=="equip" and "装备它" or "忽略这件")
        button:SetScript("OnEnter",function()
            button.text:SetTextColor(unpack(palette.white));if button.chevron then button.chevron:SetVertexColor(unpack(palette.white)) end
        end)
        button:SetScript("OnLeave",function()
            button.text:SetTextColor(unpack(color));if button.chevron then button.chevron:SetVertexColor(unpack(color)) end
        end)
    end
    T.gear.equip.chevron=T.gear.equip:CreateTexture(nil,"ARTWORK")
    T.gear.equip.chevron:SetTexture(media.."hud-chevron-right.tga");T.gear.equip.chevron:SetVertexColor(unpack(palette.gold))
    T.gear.equip:SetScript("OnClick",function()
        local ok,why=A.Gear:EquipAdvice(T.gear.advice)
        if not ok then A:Message(why) end
        self:RenderTracker()
    end)
    T.gear.ignore:SetScript("OnClick",function()
        if not T.gear.advice then return end
        A.char.ignoredGear=A.char.ignoredGear or {};A.char.ignoredGear["item:"..T.gear.advice.item.id]=true
        self:RenderTracker()
    end)
    T.gear.close=CreateFrame("Button",nil,T.gear)
    T.gear.close.icon=T.gear.close:CreateTexture(nil,"ARTWORK");T.gear.close.icon:SetPoint("CENTER")
    T.gear.close.icon:SetTexture(media.."hud-close.tga");T.gear.close.icon:SetVertexColor(unpack(dim))
    T.gear.close:SetScript("OnEnter",function(button)
        button.icon:SetVertexColor(unpack(palette.white))
        GameTooltip:SetOwner(button,"ANCHOR_TOP");GameTooltip:SetText("关闭");GameTooltip:Show()
    end)
    T.gear.close:SetScript("OnLeave",function(button) button.icon:SetVertexColor(unpack(dim));GameTooltip:Hide() end)
    T.gear.close:SetScript("OnClick",function()
        if not T.gear.advice then return end
        local id=T.gear.advice.item.id
        A.Gear.dismissedGear=A.Gear.dismissedGear or {};A.Gear.dismissedGear[id]=(A.state.bags or {})[id] or 1
        GameTooltip:Hide();self:RenderTracker()
    end)
    T.card=CreateFrame("Frame",nil,T.content)
    T.actionIcon=T.card:CreateTexture(nil,"ARTWORK")
    T.stepIcon=T.card:CreateTexture(nil,"ARTWORK")
    T.primaryLabel=text(T.card,11,palette.muted)
    self.title=text(T.card,15,palette.gold)
    T.location=text(T.card,19,palette.white)
    T.area=text(T.card,12,palette.muted)
    T.questTitle=CreateFrame("Button",nil,T.card);T.questTitle:SetAllPoints(self.title)
    T.questTitle:RegisterForClicks("LeftButtonUp","RightButtonUp")
    T.questTitle:SetScript("OnClick",function(_,mouse)
        if mouse=="RightButton" then self:TrackerMenu(T.questTitle)
        else self:QuestClick(T.questTitle.questId,mouse) end
    end)
    T.questTitle:SetScript("OnEnter",questTooltip)
    T.questTitle:SetScript("OnLeave",function() GameTooltip:Hide() end)
    T.currentScroll=CreateFrame("ScrollFrame",nil,T.card,"UIPanelScrollFrameTemplate")
    T.currentChild=CreateFrame("Frame",nil,T.currentScroll);T.currentScroll:SetScrollChild(T.currentChild)
    T.reward=noticeLine(T.currentChild,12,{0.765,0.793,0.868})
    T.reward.text:SetNonSpaceWrap(false)
    T.reward.icon=T.reward:CreateTexture(nil,"ARTWORK");T.reward.icon:SetTexture(media.."hud-chevron-up.tga")
    T.reward.icon:SetVertexColor(unpack(palette.green))
    T.objectiveFrame=CreateFrame("Frame",nil,T.currentChild)
    self.body=text(T.currentChild,13,palette.muted);self.body:SetMaxLines(2)
    T.objectives={}
    T.footer=text(T.currentChild,12,palette.muted)
    T.journey=CreateFrame("Frame",nil,T.currentChild)
    T.journeyHeader=CreateFrame("Button",nil,T.journey)
    T.journeyLabel=text(T.journeyHeader,13,palette.muted);T.journeyLabel:SetPoint("LEFT");T.journeyLabel:SetText("行程")
    T.journeySummary=text(T.journeyHeader,12,palette.white);T.journeySummary:SetPoint("RIGHT");T.journeySummary:SetJustifyH("RIGHT")
    T.journeyHeader:SetScript("OnClick",function() T.journeyClosed=not T.journeyClosed;self:LayoutTracker() end)
    T.journeyRows={}
    T.journey:SetScript("OnUpdate",function(_,elapsed)
        T.journeyElapsed=(T.journeyElapsed or 0)+elapsed
        if T.journeyElapsed>=1 then T.journeyElapsed=0;self:RenderTracker() end
    end)
    T.questTitle.progress=self.body
    T.thenText=text(T.currentChild,14,palette.blue)
    T.thenDivider=T.currentChild:CreateTexture(nil,"BACKGROUND");T.thenDivider:SetColorTexture(unpack(palette.line))
    T.thenButton=CreateFrame("Button",nil,T.currentChild);T.thenButton:SetAllPoints(T.thenText)
    T.thenButton:SetScript("OnClick",function() self:QuestClick(T.thenButton.questId,"LeftButton") end)
    T.thenButton:SetScript("OnEnter",questTooltip)
    T.thenButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
    T.region=self:Button(T.currentChild,"",250,function() self.details:Show();self:SelectTab(10) end,12)
    T.region.baseColor={0,0,0,0};T.region:SetBackdropColor(0,0,0,0)
    T.queuePanel=CreateFrame("Frame",nil,T.currentChild)
    T.queueLabel=text(T.currentChild,12,palette.muted);T.queueLabel:SetText("后续行程")
    T.queueScroll=CreateFrame("Frame",nil,T.queuePanel)
    T.queueScroll:SetPoint("TOPLEFT",0,0)
    T.queueChild=CreateFrame("Frame",nil,T.queueScroll);T.queueChild:SetPoint("TOPLEFT")
    T.alongLabel=text(T.currentChild,12,palette.blue)
    T.alongScroll=CreateFrame("Frame",nil,T.currentChild)
    T.alongChild=CreateFrame("Frame",nil,T.alongScroll);T.alongChild:SetPoint("TOPLEFT")
    T.rows={}
    T.progress=CreateFrame("Frame",nil,f);T.progress:SetPoint("BOTTOMLEFT",10,10);T.progress:SetPoint("BOTTOMRIGHT",-28,10)
    T.progress:SetHeight(14);T.progress:EnableMouse(true)
    T.progress:SetScript("OnEnter",function()
        GameTooltip:SetOwner(T.progress,"ANCHOR_TOP");GameTooltip:SetText("当前任务目标进度")
        GameTooltip:AddLine(T.model and T.model.title or "",1,1,1);GameTooltip:Show()
    end)
    T.progress:SetScript("OnLeave",function() GameTooltip:Hide() end)
    T.progressBack=T.progress:CreateTexture(nil,"BACKGROUND");T.progressBack:SetColorTexture(unpack(palette.line))
    T.progressFill=T.progress:CreateTexture(nil,"ARTWORK");T.progressFill:SetColorTexture(unpack(palette.gold))
    T.progressText=text(T.progress,12,palette.muted);T.progressText:SetPoint("RIGHT");T.progressText:SetWidth(40);T.progressText:SetJustifyH("RIGHT")
    local nav=CreateFrame("Frame","AiLevelingNavigation",UIParent)
    self.navFrame=nav;nav:SetSize(420,90);nav:SetPoint("CENTER",UIParent,"CENTER",0,-110)
    p=A.settings.navigationPosition
    if p then nav:ClearAllPoints();nav:SetPoint(p[1],UIParent,p[2],p[3],p[4]) end
    self:Movable(nav,"navigationPosition")
    self.nav=text(nav,17,"accent");self.nav:SetPoint("TOP",0,-37);self.nav:SetJustifyH("CENTER")
    T.navTitle=text(nav,12);T.navTitle:SetPoint("TOP",0,-62);T.navTitle:SetWidth(420);T.navTitle:SetJustifyH("CENTER")
    T.arrowLines={}
    for i=1,4 do
        local line=nav:CreateLine(nil,i<=2 and "BACKGROUND" or "OVERLAY")
        line:SetThickness(i<=2 and 6 or 3);T.arrowLines[i]=line
    end
    nav:Hide()
end

local function questTitle(id,title,candidate)
    local quest=(A.state.quests or {})[id]
    local level=quest and quest.level or candidate and candidate.level
    return (level and level>0 and ("["..level.."] ") or "")..title
end

local function renderObjectives(owner,parent,pool,objectives)
    for i,objective in ipairs(objectives) do
        local row=pool[i]
        if not row then
            row=CreateFrame("Button",nil,parent)
            row:RegisterForClicks("LeftButtonUp","RightButtonUp")
            row:SetScript("OnClick",function(_,button)
                if button=="RightButton" then UI:TrackerMenu(owner) else UI:QuestClick(owner.questId,button) end
            end)
            row:SetScript("OnEnter",function() questTooltip(owner) end)
            row:SetScript("OnLeave",function() GameTooltip:Hide() end)
            row.text=text(row,14,palette.white);row.text:SetPoint("TOPLEFT");row.text:SetNonSpaceWrap(false)
            row.icon=row:CreateTexture(nil,"ARTWORK")
            row.count=text(row,13,palette.white);row.count:SetJustifyH("RIGHT")
            row.check=text(row,15,palette.muted);row.check:SetJustifyH("RIGHT")
            row.active=row:CreateTexture(nil,"ARTWORK");row.active:SetColorTexture(unpack(palette.gold))
            pool[i]=row
        end
        local done=objective.done or objective.finished==true
        local need,have=objective.need or objective.numRequired,objective.have or objective.numFulfilled or 0
        row.known=type(need)=="number" and need>0
        row.ratio=done and 1 or row.known and math.max(0,math.min(1,have/need)) or 0
        row.text:SetText((objective.text or "任务目标"):gsub("%s*%d+%s*/%s*%d+",""):gsub("^%s+",""))
        row.text:SetTextColor(unpack(done and palette.muted or objective.type=="item" and palette.purple or palette.blue))
        row.icon:SetTexture(media.."hud-"..(done and "turnin" or objective.type=="item" and "collect" or "objective")..".tga")
        row.icon:SetVertexColor(unpack(done and palette.green or objective.type=="item" and palette.purple or palette.gold))
        row.count:SetText(row.known and string.format("%d/%d",have,need) or "")
        row.count:SetTextColor(unpack(done and palette.green or palette.white))
        row.check:SetText(done and "✓" or "□");row.check:SetTextColor(unpack(done and palette.green or palette.muted))
        row.active:SetShown(not done and owner.activeObjective==i)
        row:Show()
    end
    for i=#objectives+1,#pool do pool[i]:Hide() end
end

local function layoutObjectives(pool,width,scale)
    local y=0
    for _,row in ipairs(pool) do
        if row:IsShown() then
            local countWidth=row.count:GetText()~="" and math.ceil(row.count:GetStringWidth())+6*scale or 0
            row:SetWidth(width);row.text:SetWidth(width-countWidth-42*scale);row.count:SetWidth(countWidth)
            row.count:ClearAllPoints();row.count:SetPoint("TOPRIGHT",-22*scale,0)
            row.check:ClearAllPoints();row.check:SetPoint("TOPRIGHT",0,0);row.check:SetWidth(18*scale)
            row.text:ClearAllPoints();row.text:SetPoint("TOPLEFT",20*scale,0)
            row.icon:ClearAllPoints();row.icon:SetPoint("TOPLEFT",0,-2);row.icon:SetSize(14*scale,14*scale)
            row.active:ClearAllPoints();row.active:SetWidth(2*scale)
            row.active:SetPoint("TOPLEFT",-10*scale,0);row.active:SetPoint("BOTTOMLEFT",-10*scale,6*scale)
            row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-y)
            local height=math.max(18*scale,row.text:GetStringHeight())
            height=height+6*scale
            row:SetHeight(height);y=y+height
        end
    end
    return y
end

function UI:TrackerRow(index)
    local T=self.tracker
    if T.rows[index] then return T.rows[index] end
    local row=CreateFrame("Button",nil,T.queueChild,"BackdropTemplate")
    self:Rounded(row,3);row:SetBackdropColor(0,0,0,0);row.material:Hide()
    row.icon=row:CreateTexture(nil,"ARTWORK")
    row.title=text(row,15,palette.gold)
    row.progress=text(row,13,palette.muted)
    row.objectiveFrame=CreateFrame("Frame",nil,row);row.objectives={}
    row:RegisterForClicks("LeftButtonUp","RightButtonUp")
    row:SetScript("OnEnter",function() row:SetBackdropColor(0.50,0.60,0.85,0.10);questTooltip(row) end)
    row:SetScript("OnLeave",function() row:SetBackdropColor(0,0,0,0);GameTooltip:Hide() end)
    row:SetScript("OnClick",function(_,button)
        if button=="RightButton" then self:TrackerMenu(row)
        elseif row.dungeonId then self.Dungeon.selected=row.dungeonId;self.details:Show();self:SelectTab(4)
        else self:QuestClick(row.questId,button) end
    end)
    T.rows[index]=row
    return row
end

function UI:RenderTracker()
    local T=self.tracker
    if not T then return end
    local state,plan=A.state or {},A.plan or {}
    local action=A.Navigation:Current()
    local model=UI.TrackerModel(state,plan,action,A.char.paused)
    T.model,T.action=model,action
    local reminder=self.ClassReminders(state,plan)
    local notice={}
    if (#reminder.spells>0 or #reminder.quests>0) and A.char.classReminderLevel~=state.level then
        notice[1]=self:Icon("class",14).." "..state.level.."级 · 职业成长"
        if #reminder.spells>0 then
            local links={};for i=1,math.min(2,#reminder.spells) do links[i]=reminder.spells[i].link end
            notice[#notice+1]="可学："..table.concat(links,"、")..(#reminder.spells>2 and (" 等"..#reminder.spells.."项") or "")
        end
        local quest=reminder.quests[1]
        if quest then
            notice[#notice+1]="待接：|cff9acbff|Hquest:"..quest.questId..":"..(quest.level or state.level).."|h["..quest.title.."]|h|r"..
                (#reminder.quests>1 and (" 等"..#reminder.quests.."项") or "")
        end
    end
    T.career.text:SetText(table.concat(notice,"\n"))
    local training=state.serviceStop and state.serviceStop.kind=="train"
    T.career.train:SetShown(#reminder.spells>0)
    T.career.train.text:SetText(training and "已安排" or "去训练")
    T.career.train:SetEnabled(not training and not state.inInstance and not state.dead and not state.onTaxi)
    local bag=A.settings.rewardAdvice~=false and A.Gear and A.Gear.BagUpgrade(state,A.char.ignoredGear) or nil
    T.gear.advice=bag
    local slot=bag and A.Gear.UpgradeSlot(bag)
    T.gear.text:SetText(bag and ("装备提升："..(bag.item.link or bag.item.name).."  ·  "..A.Gear.UpgradeText(bag)..
        (slot and ("  ·  "..slot) or "")) or "")
    T.gear.equip:SetEnabled(not InCombatLockdown())
    T.gear.equip:SetAlpha(InCombatLockdown() and 0.45 or 1)
    T.reward.advice=model.reward
    local reward=model.reward and model.reward.item
    T.reward.icon:SetShown(reward~=nil and model.kind=="turnin")
    T.reward.text:SetText(reward and ((model.kind=="turnin" and "" or "奖励：")..(reward.link or reward.name)..
        " |cff6bd999"..A.Gear.UpgradeText(model.reward).."|r"..(model.kind=="turnin" and "" or " · 交还时")) or "")
    action=model.action
    T.questTitle.questId=model.questId
    T.questTitle.activeObjective=action and action.objectiveIndex
    T.questTitle.candidate,T.questTitle.revision=nil,nil
    T.questTitle.deferred=model.questId and ((state.skipped or {})[model.questId] or (state.chainDeferred or {})[model.questId])
    local current=(state.quests or {})[model.questId]
    local count=0;for _ in pairs(state.quests or {}) do count=count+1 end
    T.experience:SetText(A.char.paused and "已暂停" or "已接 "..count.." 项")
    T.stepIcon:SetTexture(media.."hud-target.tga")
    T.actionIcon:SetTexture(media..(({accept="hud-accept",objective="hud-objective",turnin="hud-turnin"})[model.kind] or "compass")..".tga")
    self.title:SetText(questTitle(model.questId,model.title))
    self.title:SetTextColor(unpack(model.kind=="turnin" and palette.green or model.kind=="accept" and palette.blue or palette.gold))
    local place,name,area
    if model.kind and not A.error then place,name,area=destination(action) end
    T.location:SetText(name and (self:Icon("hud-location",18).." "..name) or "")
    T.actionIcon:SetVertexColor(unpack(model.kind=="turnin" and palette.green or model.kind=="accept" and palette.blue or palette.gold))
    T.area:SetText(area or "")
    local nextStep,nextId,nextTitle=model.nextStep,model.nextId,model.nextTitle
    T.primaryLabel:SetText(model.kind=="turnin" and "本次交付" or model.kind=="accept" and "先接任务" or "主要目标")
    if model.unlock then T.primaryLabel:SetText(A.TaskGuide.UnlockText(model.unlock)) end
    T.thenButton.questId=nextId
    local following=""
    if nextStep then
        local verb=({accept="接取",objective="完成",turnin="交付"})[nextStep.kind]
        local title=(state.quests[nextId] or {}).title or nextTitle or nextStep.title
        local instruction=verb and title and (verb.." "..title) or self.ActionText(nextStep,A.settings)
        local target=destination(nextStep)
        following="接下来："..(target or instruction)
        if target and target~=instruction then following=following.."\n"..instruction end
    end
    T.thenText:SetText(following);T.thenButton.detail=following
    local region
    for _,candidate in ipairs(plan.regions or {}) do
        if not candidate.current and #candidate.choices>=3 then region=candidate;break end
    end
    T.region.text:SetText(region and "可考虑："..region.title.."  ›" or "")
    T.region.region=region

    local instruction=model.instruction
    if model.kind=="objective" and #model.objectives>0 and not A.char.paused and not A.error and
        not (action.position and action.position.sourceKind=="vendor") then instruction=nil end
    local lines={model.deliverySummary or instruction}
    if model.deliverySummary and instruction and model.kind~="turnin" then lines[#lines+1]=instruction end
    if model.destination and model.kind~="objective" and not model.deliverySummary and
        not (instruction and instruction:find(model.destination,1,true)) then lines[#lines+1]=model.destination end
    T.footer:SetText(model.metrics or "");T.questTitle.metrics=model.metrics
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
    self.body:SetText(guidance)
    self.body:SetTextColor(unpack(model.kind=="turnin" and palette.green or model.kind=="accept" and palette.blue or palette.muted))
    T.questTitle.detail=(place and (place.."\n") or "")..table.concat(lines,"\n")
    renderObjectives(T.questTitle,T.objectiveFrame,T.objectives,
        (model.kind=="objective" or current and not current.ready) and model.objectives or {})
    local progress,goals=0,0
    for _,row in ipairs(T.objectives) do
        if row:IsShown() then progress=progress+row.ratio;goals=goals+1 end
    end
    T.progressRatio=goals>0 and progress/goals or nil
    T.progressText:SetText(T.progressRatio and string.format("%.0f%%",T.progressRatio*100) or "")
    local journey=model.journey
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
            row.number=text(row,12,palette.muted)
            row.icon=row:CreateTexture(nil,"ARTWORK")
            row.title=text(row,13,palette.white)
            row.time=text(row,12,palette.white);row.time:SetJustifyH("RIGHT")
            row.detail=text(row,11,palette.muted)
            T.journeyRows[i]=row
        end
        row.number:SetText(i)
        row.icon:SetTexture(media.."hud-"..(({walk="location",zeppelin="boat",flight="flight",boat="boat",tram="tram",hearth="hearth",accept="accept",objective="objective",turnin="turnin"})[step.kind] or "location")..".tga")
        row.icon:SetVertexColor(unpack(i==1 and palette.gold or palette.blue))
        row.title:SetText(step.title);row.title:SetTextColor(unpack(i==1 and palette.gold or palette.white))
        row.time:SetText(step.task and "" or clockText(step.seconds));row.detail:SetText(step.detail or "")
        row:Show()
    end
    for i=#(journey and journey.steps or {})+1,#T.journeyRows do T.journeyRows[i]:Hide() end
    for i,item in ipairs(model.rows) do
        local row=self:TrackerRow(i)
        local isCurrent=item.questId and item.questId==model.questId
        row.icon:SetTexture(media.."hud-"..(item.dungeonId and "entry" or item.kind)..".tga")
        row.title:SetText(questTitle(item.questId,item.title,item.candidate))
        local color=(item.deferred or item.candidate and item.candidate.lowValue) and palette.muted or item.kind=="turnin" and palette.green or item.accepted and palette.gold or palette.blue
        row.title:SetTextColor(unpack(color))
        row.icon:SetVertexColor(unpack(color))
        row.status=item.deferred and (item.accepted and "已接·暂缓" or "未接·暂缓") or item.status
        local progress=item.delivery or item.progress
        if item.along then
            local verb=({accept="顺路接取",turnin="顺路交付",objective="顺路完成"})[item.kind]
            if item.shared then
                local objective=state.quests[item.questId].objectives[item.sharedObjective]
                progress="同一目标"..(objective.numRequired and objective.numRequired>0 and
                    string.format(" · %d/%d",objective.numFulfilled or 0,objective.numRequired) or "")
            elseif item.kind=="objective" then progress=item.candidate and item.candidate.itemShortage and item.sideAction.text or item.progress
            else
                local _,name=destination(item.sideAction)
                progress=verb.." · "..(name or item.progress)
            end
        end
        row.progress:SetText(progress)
        row.progress:SetTextColor(unpack(item.kind=="turnin" and palette.green or item.accepted and palette.muted or palette.blue))
        row.metrics=item.metrics
        row.candidate,row.revision,row.questId=item.candidate,plan.revision,item.questId
        row.deferred,row.dungeonId=item.deferred,item.dungeonId
        row.atStop,row.along=item.atStop,item.along
        row:SetParent(item.atStop and T.currentChild or item.along and T.alongChild or T.queueChild)
        local native=(state.quests or {})[item.questId]
        local objectives=item.accepted and item.kind~="turnin" and not item.deferred and
            not (item.candidate and (item.candidate.lowValue or item.candidate.entryBlocked)) and native and native.objectives or {}
        if item.sharedObjective then objectives={objectives[item.sharedObjective]} end
        renderObjectives(row,row.objectiveFrame,row.objectives,objectives)
        if #objectives>0 and not item.delivery and not (item.candidate and item.candidate.itemShortage) then row.progress:SetText("") end
        row.detail=table.concat({row.status,item.groupTitle or "",item.delivery or item.progress},"\n")
        if isCurrent then T.questTitle.candidate=item.candidate;T.questTitle.revision=plan.revision end
        row:SetEnabled(true);row:Show()
    end
    for i=#model.rows+1,#T.rows do T.rows[i]:Hide() end
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
    local requestedWidth=T.resizing and self.frame:GetWidth() or A.settings.trackerWidth or 0
    if requestedWidth>0 then width=math.max(260,math.min(800,requestedWidth)) end
    local requestedHeight=T.resizing and self.frame:GetHeight() or A.settings.trackerHeight or 0
    self.frame:SetWidth(width)
    width=width-20
    local inner=width-16
    local scale=A.settings.fontScale or 1
    local indent=24*scale
    local bodyWidth=inner-indent
    local collapsed=self.folded or (self.inCombat and A.settings.combatFold)
    local density=A.settings.density or "normal"
    T.resize:SetShown(not collapsed and not A.settings.lockWindow and not InCombatLockdown())
    T.content:SetWidth(width);T.card:SetWidth(width);T.queuePanel:SetWidth(width)
    T.header:SetHeight(29*scale)
    T.zone:SetWidth(width-138*scale)
    T.menu:ClearAllPoints();T.menu:SetPoint("TOPRIGHT",-24*scale,2);T.menu:SetSize(22*scale,22*scale)
    T.collapse:ClearAllPoints();T.collapse:SetPoint("TOPRIGHT",0,2);T.collapse:SetSize(20*scale,22*scale)
    T.collapse.text:SetText(collapsed and "+" or "−")
    T.experience:ClearAllPoints();T.experience:SetPoint("TOPRIGHT",-62*scale,-3);T.experience:SetWidth(64*scale);T.experience:SetMaxLines(1)
    local function layoutRow(row,y)
        row:SetWidth(inner)
        row.icon:ClearAllPoints();row.icon:SetPoint("TOPLEFT",0,-2);row.icon:SetSize(16*scale,16*scale)
        row.title:ClearAllPoints();row.title:SetPoint("TOPLEFT",indent,0);row.title:SetWidth(bodyWidth);row.title:SetMaxLines(2)
        local height=math.max(20*scale,row.title:GetStringHeight())+4
        row.objectiveFrame:ClearAllPoints();row.objectiveFrame:SetPoint("TOPLEFT",indent,-height);row.objectiveFrame:SetWidth(bodyWidth)
        local goals=layoutObjectives(row.objectives,bodyWidth,scale)
        row.objectiveFrame:SetHeight(math.max(1,goals));row.objectiveFrame:SetShown(goals>0)
        height=height+goals
        row.progress:SetShown(not row.atStop and row.progress:GetText()~="")
        row.progress:ClearAllPoints();row.progress:SetPoint("TOPLEFT",indent,-height);row.progress:SetWidth(bodyWidth);row.progress:SetMaxLines(2)
        if row.progress:IsShown() then height=height+math.min(row.progress:GetStringHeight(),36*scale)+4 end
        height=height+8*scale
        row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-y);row:SetHeight(height)
        return height
    end
    local cardTop=36*scale
    T.divider:ClearAllPoints();T.divider:SetPoint("TOPLEFT",0,-cardTop+7);T.divider:SetSize(width,1)
    T.career:ClearAllPoints();T.career:SetPoint("TOPLEFT",0,-cardTop);T.career:SetWidth(width)
    T.career.text:SetWidth(width)
    local noticeHeight=T.career.text:GetStringHeight()+6*scale
    local noticeX=indent
    for _,button in ipairs({T.career.view,T.career.train,T.career.later}) do
        local buttonWidth=(button==T.career.train and 64 or 48)*scale
        button:ClearAllPoints();button:SetPoint("TOPLEFT",noticeX,-noticeHeight);button:SetSize(buttonWidth,20*scale)
        if button:IsShown() then noticeX=noticeX+buttonWidth+8*scale end
    end
    T.career:SetHeight(noticeHeight+24*scale);T.career:SetShown(not collapsed and T.career.text:GetText()~="")
    if T.career:IsShown() then cardTop=cardTop+T.career:GetHeight()+12*scale end
    T.gear:ClearAllPoints();T.gear:SetPoint("TOPLEFT",-10,-cardTop);T.gear:SetWidth(width+20)
    T.gear.icon:ClearAllPoints();T.gear.icon:SetPoint("TOPLEFT",14*scale,-10*scale);T.gear.icon:SetSize(13*scale,13*scale)
    T.gear.text:ClearAllPoints();T.gear.text:SetPoint("TOPLEFT",35*scale,-9*scale);T.gear.text:SetWidth(width+20-73*scale)
    T.gear.close:ClearAllPoints();T.gear.close:SetPoint("TOPRIGHT",-5*scale,-3*scale);T.gear.close:SetSize(24*scale,24*scale)
    T.gear.close.icon:SetSize(12*scale,12*scale)
    local gearHeight=9*scale+T.gear.text:GetStringHeight()+4*scale
    local equipWidth=T.gear.equip.text:GetStringWidth()+16*scale
    T.gear.equip:ClearAllPoints();T.gear.equip:SetPoint("TOPLEFT",35*scale,-gearHeight);T.gear.equip:SetSize(equipWidth,18*scale)
    T.gear.equip.chevron:ClearAllPoints();T.gear.equip.chevron:SetPoint("LEFT",T.gear.equip.text,"RIGHT",3*scale,0);T.gear.equip.chevron:SetSize(11*scale,11*scale)
    T.gear.ignore:ClearAllPoints();T.gear.ignore:SetPoint("TOPLEFT",45*scale+equipWidth,-gearHeight);T.gear.ignore:SetSize(T.gear.ignore.text:GetStringWidth(),18*scale)
    T.gear:SetHeight(gearHeight+27*scale);T.gear:SetShown(not collapsed and T.gear.advice~=nil)
    T.gear.rule:ClearAllPoints();T.gear.rule:SetPoint("BOTTOMLEFT");T.gear.rule:SetSize(width+20,1)
    if T.gear:IsShown() then cardTop=cardTop+T.gear:GetHeight()+12*scale end
    T.card:ClearAllPoints();T.card:SetPoint("TOPLEFT",0,-cardTop)
    local top=0
    T.location:ClearAllPoints();T.location:SetPoint("TOPLEFT",0,0);T.location:SetWidth(width)
    T.location:SetShown(T.location:GetText()~="")
    if T.location:IsShown() then top=T.location:GetStringHeight()+4 end
    T.area:ClearAllPoints();T.area:SetPoint("TOPLEFT",indent,-top);T.area:SetWidth(width-indent)
    T.area:SetShown(T.area:GetText()~="")
    if T.area:IsShown() then top=top+T.area:GetStringHeight()+3 end
    if top>0 then top=top+10 end
    T.primaryLabel:ClearAllPoints();T.primaryLabel:SetPoint("TOPLEFT",indent,-top);T.primaryLabel:SetWidth(width-indent)
    T.primaryLabel:SetShown(not collapsed and T.model~=nil and T.model.kind~=nil)
    if T.primaryLabel:IsShown() then top=top+math.max(18*scale,T.primaryLabel:GetStringHeight()+4*scale) end
    T.actionIcon:ClearAllPoints();T.actionIcon:SetPoint("TOPLEFT",0,-top-2);T.actionIcon:SetSize(16*scale,16*scale)
    T.stepIcon:ClearAllPoints();T.stepIcon:SetPoint("TOPRIGHT",-2,-top-2);T.stepIcon:SetSize(15*scale,15*scale)
    self.title:ClearAllPoints();self.title:SetPoint("TOPLEFT",indent,-top);self.title:SetWidth(bodyWidth);self.title:SetMaxLines(2)
    top=top+math.max(20*scale,self.title:GetStringHeight())+6
    T.currentScroll:SetWidth(inner);T.currentChild:SetWidth(inner)
    T.reward:ClearAllPoints();T.reward:SetPoint("TOPLEFT",indent,0);T.reward:SetWidth(bodyWidth)
    local rewardInset=T.reward.icon:IsShown() and 14*scale or 0
    T.reward.icon:ClearAllPoints();T.reward.icon:SetPoint("TOPLEFT",0,-2*scale);T.reward.icon:SetSize(11*scale,11*scale)
    T.reward.text:ClearAllPoints();T.reward.text:SetPoint("TOPLEFT",rewardInset,0);T.reward.text:SetWidth(bodyWidth-rewardInset)
    T.reward:SetHeight(T.reward.text:GetStringHeight()+8*scale);T.reward:SetShown(T.reward.advice~=nil)
    local childHeight=T.reward:IsShown() and T.reward:GetHeight() or 0
    T.objectiveFrame:ClearAllPoints();T.objectiveFrame:SetPoint("TOPLEFT",indent,-childHeight);T.objectiveFrame:SetWidth(bodyWidth)
    local goals=layoutObjectives(T.objectives,bodyWidth,scale)
    T.objectiveFrame:SetHeight(math.max(1,goals));childHeight=childHeight+goals
    local queueHeight,alongHeight,alongCount=0,0,0
    for i,item in ipairs(T.model and T.model.rows or {}) do
        local row=T.rows[i]
        local current=item.questId and item.questId==T.model.questId
        row:SetShown(not current)
        if not current then
            if row.atStop then childHeight=childHeight+layoutRow(row,childHeight+4)+4
            elseif row.along then alongHeight=alongHeight+layoutRow(row,alongHeight);alongCount=alongCount+1
            else queueHeight=queueHeight+layoutRow(row,queueHeight) end
        end
    end
    self.body:ClearAllPoints();self.body:SetPoint("TOPLEFT",indent,-childHeight);self.body:SetWidth(bodyWidth)
    self.body:SetShown(self.body:GetText()~="")
    if self.body:IsShown() then childHeight=childHeight+self.body:GetStringHeight()+5 end
    T.footer:ClearAllPoints();T.footer:SetPoint("TOPLEFT",indent,-childHeight);T.footer:SetWidth(bodyWidth);T.footer:SetMaxLines(1)
    T.footer:SetShown(T.footer:GetText()~="")
    if T.footer:IsShown() then childHeight=childHeight+18*scale end
    local clipped=math.max(0,childHeight-({compact=100,normal=200,expanded=280})[density]*scale)
    T.journey:ClearAllPoints();T.journey:SetPoint("TOPLEFT",0,-childHeight-10);T.journey:SetWidth(inner)
    T.journey:SetShown(not collapsed and T.model~=nil and T.model.journey~=nil)
    T.journeyHeader:ClearAllPoints();T.journeyHeader:SetPoint("TOPLEFT");T.journeyHeader:SetSize(inner,24*scale)
    T.journeySummary:SetWidth(inner-36*scale);T.journeySummary:SetMaxLines(1)
    T.journeySummary:SetText((T.journeyTime or "")..(T.journeyClosed and "  +" or "  −"))
    local journeyHeight=28*scale
    for i,row in ipairs(T.journeyRows) do
        local shown=not T.journeyClosed and T.model and T.model.journey and T.model.journey.steps[i]~=nil
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
            row.detail:SetShown(row.detail:GetText()~="")
            if row.detail:IsShown() then height=height+row.detail:GetStringHeight() end
            height=height+8*scale;row:SetHeight(height);journeyHeight=journeyHeight+height
        end
    end
    T.journey:SetHeight(journeyHeight)
    if T.journey:IsShown() then childHeight=childHeight+journeyHeight+16 end
    local bottom=childHeight+10
    T.alongLabel:ClearAllPoints();T.alongLabel:SetPoint("TOPLEFT",0,-bottom);T.alongLabel:SetWidth(inner)
    T.alongLabel:SetText("顺路可做 · "..alongCount);T.alongLabel:SetShown(not collapsed and alongCount>0)
    if T.alongLabel:IsShown() then bottom=bottom+24*scale end
    T.alongScroll:ClearAllPoints();T.alongScroll:SetPoint("TOPLEFT",0,-bottom);T.alongScroll:SetWidth(inner)
    T.alongChild:SetWidth(inner);T.alongChild:SetHeight(math.max(1,alongHeight))
    clipped=clipped+math.max(0,alongHeight-({compact=75,normal=120,expanded=180})[density]*scale)
    local alongVisible=alongHeight
    T.alongScroll:SetHeight(math.max(1,alongVisible));T.alongScroll:SetShown(not collapsed and alongCount>0)
    if T.alongScroll:IsShown() then bottom=bottom+alongVisible+10 end
    T.thenDivider:ClearAllPoints();T.thenDivider:SetPoint("TOPLEFT",0,-bottom);T.thenDivider:SetSize(inner,1)
    T.thenText:ClearAllPoints();T.thenText:SetPoint("TOPLEFT",0,-bottom-10);T.thenText:SetWidth(inner)
    T.thenText:SetShown(not collapsed and T.thenText:GetText()~="");T.thenButton:SetShown(T.thenText:IsShown())
    T.thenDivider:SetShown(T.thenText:IsShown())
    if T.thenText:IsShown() then bottom=bottom+T.thenText:GetStringHeight()+24 end
    T.queueLabel:ClearAllPoints();T.queueLabel:SetPoint("TOPLEFT",0,-bottom);T.queueLabel:SetWidth(inner)
    T.queueLabel:SetShown(not collapsed and queueHeight>0)
    if T.queueLabel:IsShown() then bottom=bottom+24*scale end
    T.queuePanel:ClearAllPoints();T.queuePanel:SetPoint("TOPLEFT",0,-bottom)
    T.queueScroll:SetWidth(inner);T.queueChild:SetWidth(inner)
    T.queueChild:SetHeight(math.max(1,queueHeight))
    clipped=clipped+math.max(0,queueHeight-({compact=100,normal=160,expanded=240})[density]*scale)
    local visible=queueHeight
    T.queueScroll:SetHeight(math.max(1,visible));T.queueScroll:SetShown(not collapsed and queueHeight>0)
    T.queuePanel:SetHeight(visible);T.queuePanel:SetShown(not collapsed and queueHeight>0)
    bottom=bottom+(not collapsed and queueHeight>0 and visible+4 or 0)
    T.region:ClearAllPoints();T.region:SetPoint("TOPLEFT",indent,-bottom);T.region:SetSize(width-indent,20*scale)
    T.region.text:SetWidth(width-indent);T.region.text:SetMaxLines(1);T.region:SetShown(not collapsed and T.region.region~=nil)
    if T.region:IsShown() then bottom=bottom+24*scale end
    T.progress:SetShown(not collapsed and T.progressRatio~=nil)
    local progressWidth=width-62*scale
    T.progressText:SetWidth(40*scale)
    T.progressBack:ClearAllPoints();T.progressBack:SetPoint("LEFT",0,0);T.progressBack:SetSize(progressWidth,3)
    T.progressFill:ClearAllPoints();T.progressFill:SetPoint("LEFT",0,0);T.progressFill:SetSize(math.max(1,progressWidth*(T.progressRatio or 0)),3)
    T.progressFill:SetShown(T.progressRatio~=nil and T.progressRatio>0)
    local fixed=cardTop+top+24+(T.progress:IsShown() and 24*scale or 0)
    local minHeight=math.max(200,fixed+40*scale)
    self.frame:SetResizeBounds(260,collapsed and fixed or minHeight,800,math.max(1200,minHeight))
    local total=collapsed and fixed or requestedHeight>0 and math.max(minHeight,requestedHeight) or fixed+bottom-clipped
    T.currentScroll:ClearAllPoints();T.currentScroll:SetPoint("TOPLEFT",0,-top)
    T.currentScroll:SetHeight(math.max(1,total-fixed));T.currentScroll:SetShown(not collapsed)
    T.currentChild:SetHeight(math.max(1,bottom))
    T.currentScroll:SetVerticalScroll(math.min(T.currentScroll:GetVerticalScroll(),math.max(0,bottom-(total-fixed))))
    T.card:SetHeight(top+(collapsed and 0 or total-fixed))
    T.content:SetHeight(total-20);self.frame:SetHeight(total)
    if A.QuestAssist then A.QuestAssist:LayoutTarget() end
end

function UI:SetTrackerNavigation(distance,angle,unverified)
    if not self.navFrame then return end
    local action=A.Navigation:Current()
    local show=A.settings.arrow and distance~=nil and not A.char.paused
    self.navFrame:SetShown(show==true)
    if not show then return end
    local meters=A.settings.distanceUnits=="meters"
    self.nav:SetText(string.format("%.0f %s",meters and distance*0.9144 or distance,meters and "米" or "码"))
    local target=A.Navigation.Target(action)
    self.tracker.navTitle:SetText((action and action.title or "目的地")..(target and target.approximate and " · 区域参考点" or ""))
    self.navFrame:SetHeight(math.max(90,70+self.tracker.navTitle:GetStringHeight()))
    local points={{-10,-6,0,7},{0,7,10,-6}}
    local cos,sin=math.cos(-(angle or 0)),math.sin(-(angle or 0))
    for i,line in ipairs(self.tracker.arrowLines) do
        local p=points[(i-1)%2+1]
        line:SetShown(angle~=nil)
        line:SetStartPoint("TOP",self.navFrame,p[1]*cos-p[2]*sin,-16+p[1]*sin+p[2]*cos)
        line:SetEndPoint("TOP",self.navFrame,p[3]*cos-p[4]*sin,-16+p[3]*sin+p[4]*cos)
        if i<=2 then line:SetColorTexture(0.01,0.02,0.02,0.85) else line:SetColorTexture(self:Accent()) end
    end
end
