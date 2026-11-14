local _,A=...
A.TaskQueue={}
local Q=A.TaskQueue

local function copy(source)
    local result={};for key,value in pairs(source) do result[key]=value end;return result
end
local function append(source,value)
    local result={};for i,item in ipairs(source) do result[i]=item end;result[#result+1]=value;return result
end
local operations,deadline=0,0
local clock=debugprofilestop or function() return os.clock()*1000 end
local function checkpoint()
    local thread,main=coroutine.running()
    if thread and not main then
        operations=operations+1
        if operations>=128 or clock()>=deadline then
            operations=0;coroutine.yield();deadline=clock()+1
        end
    end
end

-- Reserve each physical item once; collection steps supply only the unreserved deficit.
function Q.PrepareItems(order,state,reassign)
    local available=copy(state.bags or {})
    local result={}
    for _,original in ipairs(order) do
        local source=reassign and original.itemOriginal or original
        local last=source.stages and source.stages[#source.stages]
        local requirements=last and last.itemRequirements or {}
        local choice=original
        if not source.itemsPrepared and not original.stageIndex and #requirements>0 then
            choice=copy(original);choice.stages={};choice.itemsPrepared=true
            choice.itemOriginal=source;choice.itemShortage=nil;choice.stagesComplete=source.stagesComplete
            local gains,collects,consume,grants,allocation={},{},{},{},{}
            for _,requirement in ipairs(requirements) do
                local id,need=requirement.targetId,requirement.need
                local granted=requirement.providedOnAccept and ((state.bags or {})[id] or 0)==0 and 1 or 0
                local held=math.min(available[id] or 0,need-granted)
                available[id]=(available[id] or 0)-held
                consume[id]=need
                if granted>0 then grants[id]=granted end
                gains[id]=need-held-granted
                allocation[#allocation+1]=id.."="..gains[id]..":"..granted
                if gains[id]>0 then
                    collects[id]=copy(requirement)
                    collects[id].itemGain=gains[id]
                    collects[id].text=string.format("%s · 还需收集 %d 件供这批任务交付。",requirement.text or "任务物品",gains[id])
                    choice.itemShortage=true
                end
            end
            choice.itemAllocationKey=table.concat(allocation,",")
            for _,originalStage in ipairs(source.stages) do
                local stage=originalStage
                if stage.kind=="accept" and next(grants) then stage=copy(stage);stage.gainItems=grants end
                if stage.kind=="objective" and stage.targetKind=="item" and gains[stage.targetId]~=nil then
                    stage=copy(stage);stage.itemGain=gains[stage.targetId]
                    if collects[stage.targetId] then stage.text=collects[stage.targetId].text end
                    collects[stage.targetId]=nil
                    gains[stage.targetId]=0
                end
                if stage.kind=="turnin" then
                    for _,requirement in ipairs(requirements) do
                        local collect=collects[requirement.targetId]
                        if collect then
                            choice.stages[#choice.stages+1]=collect
                            if not collect.position then choice.stagesComplete=false end
                        end
                    end
                    stage=copy(stage);stage.consumeItems=consume
                end
                choice.stages[#choice.stages+1]=stage
            end
        end
        result[#result+1]=choice
    end
    return result
end

-- Compare routes only at the same completed prefix and endpoint.
function Q.Evaluate(order,state,navigation,data,cache)
    -- Whole-task permutations may spend the stock on a different recipient first.
    -- Split stages retain their allocation so interleaving cannot create extra items.
    order=Q.PrepareItems(order,state,true)
    local bags=copy(state.bags or {})
    if A.Supplies then
        local log=A.Supplies.QuestLog(state)
        for _,choice in ipairs(order) do
            for _,stage in ipairs(choice.stages or {}) do
                if not A.Supplies.ApplyQuestLog({kind=stage.kind,questId=stage.questId or choice.questId},log) then return end
            end
        end
    end
    local paths={{position=state.position,seconds=0,low=0,high=0,xp=0,xpKnown=true,
        forecast=state,steps={},initial=false,hearthReady=state.hearthReady}}
    cache=cache or {}
    -- Keep only the last trial's prefixes; local swaps reuse the unchanged work.
    local previous=cache.prefixState==state and cache.prefixes or {}
    local prefixes,same={},true
    cache.prefixState,cache.prefixes=state,prefixes
    for index,choice in ipairs(order) do
        if not choice.stagesComplete then return end
        local source=choice.itemOriginal or choice
        local key=table.concat({choice.questId,tostring(source.stages),choice.stageIndex or "task",choice.itemAllocationKey or ""},":")
        local saved=previous[index]
        if same and saved and saved.key==key then
            paths,bags=saved.paths,copy(saved.bags)
            prefixes[index]=saved
        else
            same=false
            local staged=copy(choice);staged.stages={}
            for _,original in ipairs(choice.stages or {}) do
                local stage=original
                if A.TaskGuide.ItemGainBlocked(stage,state,bags) then return end
                for id,count in pairs(stage.gainItems or {}) do bags[id]=(bags[id] or 0)+count end
                if stage.itemGain and stage.itemGain>0 then
                    stage=copy(stage);stage.have=bags[stage.targetId] or 0;stage.need=stage.have+stage.itemGain
                    bags[stage.targetId]=stage.need
                end
                for id,count in pairs(stage.consumeItems or {}) do
                    if (bags[id] or 0)<count then return end
                    bags[id]=bags[id]-count
                end
                staged.stages[#staged.stages+1]=stage
            end
            local evaluated=staged
            local last=choice.stages and choice.stages[#choice.stages]
            if not last or not last.position then return end
            local nextPaths={}
            for _,path in ipairs(paths) do
                local context=copy(state)
                context.position=path.position
                context.hearthReady=path.hearthReady
                context.now=(state.now or 0)+path.seconds
                context.maxSeconds=state.maxSeconds and math.max(0,state.maxSeconds-path.seconds)
                context.level,context.xp,context.maxXP=path.forecast.level,path.forecast.xp,path.forecast.maxXP
                context.xpUncertain=path.forecast.uncertain or path.forecast.xpUncertain
                local p=path.position
                if not p then return end
                local key=table.concat({choice.questId,tostring(choice.itemOriginal and choice.itemOriginal.stages or choice.stages),
                    choice.itemAllocationKey or "",choice.stageIndex or "task",p.map,string.format("%.9f",p.x),string.format("%.9f",p.y),
                    tostring(context.level),tostring(context.maxSeconds),tostring(context.hearthReady),
                    state.hearthPoint and tostring(context.now) or ""},":")
                local timing=cache[key]
                if timing==nil then
                    timing=A.TaskGuide.Timing(p,evaluated,context,navigation)
                    cache[key]=timing or false
                end
                if timing and timing.seconds and timing.travelRoutes then
                    local xp
                    if choice.stageIndex and last.kind~="turnin" then xp=0
                    elseif not context.xpUncertain then
                        local quest=data and data:GetQuest(choice.questId)
                        xp=quest and A.TaskGuide.XP(quest,context.level,context) or
                            (context.level==state.level and choice.remainingXP or nil)
                    end
                    local forecast=xp and A.Progression and A.Progression.Advance(context,xp) or path.forecast
                    if xp==nil then forecast=copy(path.forecast);forecast.uncertain=true end
                    for _,route in ipairs(timing.travelRoutes) do
                        local stepTiming=copy(timing)
                        stepTiming.travelPlan,stepTiming.travel=route,route.seconds
                        stepTiming.coarse=route.coarse
                        stepTiming.travelLow,stepTiming.travelHigh=route.low,route.high
                        stepTiming.flightCount=route.flights
                        stepTiming.hearthReady,stepTiming.hearthCount=route.hearthReady,route.hearths
                        stepTiming.seconds=route.seconds
                        stepTiming.low=route.low
                        stepTiming.high=route.high
                        stepTiming.initial=route.initial
                        if not state.maxSeconds or path.seconds+stepTiming.seconds<=state.maxSeconds then
                            nextPaths[#nextPaths+1]={position=last.position,
                                seconds=path.seconds+stepTiming.seconds,low=path.low+stepTiming.low,high=path.high+stepTiming.high,
                                xp=path.xp+(xp or 0),xpKnown=path.xpKnown and xp~=nil,forecast=forecast,
                                steps=append(path.steps,{choice=choice.sourceChoice or choice,stage=choice.stageIndex and evaluated.stages[1] or nil,timing=stepTiming,xp=xp}),initial=path.initial or stepTiming.initial,
                                hearthReady=route.hearthReady}
                        end
                    end
                end
                checkpoint()
            end
            paths=A.Travel.Prune(nextPaths,state.now)
            if #paths==0 then return end
            prefixes[index]={key=key,paths=paths,bags=copy(bags)}
        end
    end
    if paths[1] then paths[1].bags=bags end
    return paths[1]
end

local function better(candidate,current,state)
    if not candidate then return false end
    if not current then return true end
    local useXP=candidate.xpKnown and current.xpKnown
    local cr=useXP and A.TaskGuide.MovementRate(candidate.seconds,candidate.xp)
    local old=useXP and A.TaskGuide.MovementRate(current.seconds,current.xp)
    local improved
    if useXP and cr~=old then improved=cr>old
    else
        if useXP and candidate.xp~=current.xp then improved=candidate.xp>current.xp
        elseif candidate.seconds~=current.seconds then improved=candidate.seconds<current.seconds
        elseif useXP then
            -- With equal total reward and travel, collect the larger reward earlier.
            for i,step in ipairs(candidate.steps) do
                if step.xp~=current.steps[i].xp then improved=step.xp>current.steps[i].xp;break end
            end
        end
    end
    if not improved then return false end
    if current.steps[1].choice.questId==state.currentTask and
        candidate.steps[1].choice.questId~=state.currentTask then
        if useXP and candidate.xp~=current.xp then
            if cr<old/0.9 then return false end
        elseif candidate.seconds~=current.seconds then
            if candidate.seconds>current.seconds*0.9 then return false end
            if candidate.low<=current.high and current.low<=candidate.high then return false end
        end
    end
    return true
end

-- Collect every member's objectives before one contiguous visit to the recipient.
local function batchStages(stages,byQuest)
    local anchor,deliveries={},{}
    for i,entry in ipairs(stages) do
        local group=byQuest[entry.questId]
        if group then
            if entry.stages[1].kind=="turnin" then
                deliveries[group]=append(deliveries[group] or {},entry)
                anchor[group]=anchor[group] or i
            else anchor[group]=i end
        end
    end
    local result={}
    for i,entry in ipairs(stages) do
        local group=byQuest[entry.questId]
        if not group or entry.stages[1].kind~="turnin" then result[#result+1]=entry end
        if group and anchor[group]==i then
            for _,delivery in ipairs(deliveries[group] or {}) do result[#result+1]=delivery end
        end
    end
    return result
end

-- Interleave nearby task stages without changing the order within any task.
function Q.Interleave(order,state,navigation,data,cache)
    order=Q.PrepareItems(order,state)
    local stages,multiple={},false
    for _,choice in ipairs(order) do
        multiple=multiple or #choice.stages>1
        for index,stage in ipairs(choice.stages) do
            stages[#stages+1]={questId=choice.questId,stagesComplete=true,stages={stage},
                stageIndex=index,sourceChoice=choice,remainingXP=choice.remainingXP}
        end
    end
    local groups,byQuest=A.TaskGuide.DeliveryGroups(order,state,nil,true)
    -- A possession cap can make collecting the entire recipient group impossible.
    for _,group in ipairs(groups) do
        if group.splitDelivery then
            for _,choice in ipairs(group.choices) do byQuest[choice.questId]=nil end
        end
    end
    -- An explicit single-task lock remains an override of automatic batching.
    if state.locked then
        local lockedGroup=byQuest[state.locked]
        if lockedGroup then for _,choice in ipairs(lockedGroup.choices) do byQuest[choice.questId]=nil end end
    end
    local batched=next(byQuest)~=nil
    if not multiple and not batched then return end
    if batched then stages=batchStages(stages,byQuest) end
    local best=Q.Evaluate(stages,state,navigation,data,cache)
    if not best then return nil,batched end
    local first=state.locked and (#order[1].stages+1) or (order[1].orderHeld and 2 or 1)
    local changed=batched
    -- shortcut: two passes across at most three tasks; enlarge only if route replay shows a need.
    for pass=1,2 do
        local improved=false
        for index=first+1,#stages do
            local moving=stages[index]
            local nextOrder,nextBest=stages,best
            -- Move later as well: a city hand-in can wait until all nearby objectives are done.
            for _,direction in ipairs({-1,1}) do
                local crossed,count={},0
                local last=direction<0 and first or #stages
                for target=index+direction,last,direction do
                    local id=stages[target].questId
                    if id==moving.questId then break end
                    if not crossed[id] then crossed[id]=true;count=count+1 end
                    if count>2 then break end
                    local trial={};for i,entry in ipairs(stages) do trial[i]=entry end
                    table.remove(trial,index);table.insert(trial,target,moving)
                    if batched then trial=batchStages(trial,byQuest) end
                    local candidate=Q.Evaluate(trial,state,navigation,data,cache)
                    if better(candidate,nextBest,state) then nextOrder,nextBest=trial,candidate end
                end
            end
            if nextOrder~=stages then stages,best=nextOrder,nextBest;changed,improved=true,true end
        end
        if not improved then break end
    end
    if changed then best.stagePlan=true;best.deliveryBatches=batched and groups or nil;return best end
end

function Q.Solve(order,state,navigation,data)
    operations,deadline=0,clock()+1
    if #order<2 or not A.Flights or not A.TaskGuide or not A.Travel then return end
    order=Q.PrepareItems(order,state)
    local base,pending={},{}
    local groups,byQuest=A.TaskGuide.DeliveryGroups(order,state,nil,true)
    local incomplete={}
    for _,group in ipairs(groups) do
        for _,choice in ipairs(group.choices) do
            if not choice.stagesComplete then incomplete[group]=true end
        end
    end
    for _,choice in ipairs(order) do
        local complete=choice.stagesComplete and (state.locked or not incomplete[byQuest[choice.questId]])
        local timing=complete and A.TaskGuide.Timing(state.position,choice,state,navigation)
        -- An unpriced distant trip must not block the work we can compare here.
        if timing and timing.seconds~=nil then base[#base+1]=choice
        else pending[#pending+1]=choice end
    end
    if #base==0 or state.locked and base[1]~=order[1] then return end
    local cache={}
    local best=Q.Evaluate(base,state,navigation,data,cache)
    local first=(state.locked or best and base[1].orderHeld) and 2 or 1
    do
        -- Three-task rolling windows keep the existing short planning horizon; every trial funds the whole queue.
        for start=math.max(first,#base-2),first,-1 do
            local length=math.min(3,#base-start+1)
            local window={};for i=1,length do window[i]=base[start+i-1] end
            local function permute(index)
                if index>length then
                    local trial={};for i,c in ipairs(base) do trial[i]=c end
                    for i,c in ipairs(window) do trial[start+i-1]=c end
                    local candidate=Q.Evaluate(trial,state,navigation,data,cache)
                    if better(candidate,best,state) then best=candidate end
                    return
                end
                for i=index,length do
                    window[index],window[i]=window[i],window[index]
                    permute(index+1)
                    window[index],window[i]=window[i],window[index]
                end
            end
            permute(1)
            if best then for i,step in ipairs(best.steps) do base[i]=step.choice end end
        end
    end
    local interleaved,batchBlocked=Q.Interleave(base,state,navigation,data,cache)
    if batchBlocked then return end
    best=interleaved or best
    if not best then return end
    local result,seen={},{}
    for i,step in ipairs(best.steps) do
        local choice=step.choice
        if not seen[choice.questId] then
            seen[choice.questId]=true
            choice.orderTiming=step.timing
            choice.orderBasis=best.xpKnown and "queue-movement-xp" or "queue-movement"
            choice.executionTiming=i==1 and step.timing or nil
            choice.executionAction=i==1 and (step.stage or choice.itemsPrepared and choice.stages[1]) or nil
            result[#result+1]=choice
        end
    end
    best.taskCount=#result
    best.remaining=#pending
    for _,choice in ipairs(pending) do
        choice.executionTiming=nil;choice.executionAction=nil
        result[#result+1]=choice
    end
    return result,best
end

-- Compare every eligible pickup against the complete trip, including objectives and hand-in.
function Q.Pickup(order,choices,state,navigation,data,queue)
    if not data or not navigation or not navigation.Distance or #order==0 or state.locked or
        state.taskBatch or state.gearTarget or state.inInstance then return end
    local base=queue or Q.Evaluate(order,state,navigation,data)
    local best,bestQueue
    local routed={}
    for _,step in ipairs(base and base.steps or {}) do routed[step.choice.questId]=true end
    if not base then
        for _,choice in ipairs(order) do
            local timing=choice.stagesComplete and A.TaskGuide.Timing(state.position,choice,state,navigation)
            if timing and timing.seconds~=nil then routed[choice.questId]=true end
        end
    end
    local cache={}
    local candidates={}
    for _,choice in ipairs(choices) do
        if choice.questId==state.currentTask then table.insert(candidates,1,choice)
        else candidates[#candidates+1]=choice end
    end
    for _,choice in ipairs(candidates) do
        if choice.status=="accept" and not choice.lowValue and not choice.acceptBlocked and not choice.entryBlocked and
            not choice.requireCheck and choice.stagesComplete and (choice.remainingXP==nil or choice.remainingXP>0) then
            local trial={copy(choice)}
            for _,existing in ipairs(order) do
                if routed[existing.questId] then trial[#trial+1]=copy(existing) end
            end
            -- Compare every pickup once; optimize only the selected addition to the trip.
            local path=Q.Evaluate(trial,state,navigation,data,cache)
            if better(path,bestQueue,state) then
                best,bestQueue=choice,path
            end
            checkpoint()
        end
    end
    if best then
        local trial={copy(best)}
        for _,existing in ipairs(order) do trial[#trial+1]=copy(existing) end
        best,bestQueue=Q.Solve(trial,state,navigation,data)
        if not bestQueue or base and ((bestQueue.remaining or 0)>(base.remaining or 0) or not better(bestQueue,base,state)) then return end
        local action=best[1].executionAction or best[1].stages[1]
        if action.kind=="accept" then
            best[1].executionAction=copy(action)
            best[1].executionAction.pickupResume=order[1].title
        end
        return best,bestQueue
    end
end
