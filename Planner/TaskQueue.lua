local _,A=...
A.TaskQueue={}
local Q=A.TaskQueue

-- Shared collections can finish after the native objective has already turned green.
function Q.StockChanged(plan,before,after)
    if not plan or not before or not after or before==after then return false end
    local function crossed(id,need)
        return id and need and ((before[id] or 0)>=need)~=((after[id] or 0)>=need)
    end
    local function changed(stage)
        if not stage then return end
        if stage.targetKind=="item" and crossed(stage.targetId,stage.need) then return true end
        for id,need in pairs(stage.consumeItems or {}) do if crossed(id,need) then return true end end
        for id,need in pairs(stage.serviceGoal and stage.serviceGoal.items or {}) do if crossed(id,need) then return true end end
    end
    local goal=plan.fallback
    if goal and goal.itemGain and goal.itemGain>0 and plan.itemStock and
        crossed(goal.targetId,(plan.itemStock[goal.targetId] or 0)+goal.itemGain) then return true end
    if changed(goal) then return true end
    for _,step in ipairs(plan.taskQueue and plan.taskQueue.steps or {}) do
        if changed(step.stage) then return true end
    end
    return false
end

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
    local available
    local result={}
    for _,original in ipairs(order) do
        local source=reassign and original.itemOriginal or original
        local last=source.stages and source.stages[#source.stages]
        local requirements=last and last.itemRequirements or {}
        local choice=original
        if not source.itemsPrepared and not original.stageIndex and #requirements>0 then
            available=available or setmetatable({}, {__index=state.bags})
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
    -- Prefixes keep only item counts changed by this route. Other stacks come from the snapshot.
    local inventory={__index=state.bags}
    local bags=setmetatable({},inventory)
    local context=copy(state)
    if A.Supplies then
        local log=A.Supplies.QuestLog(state)
        for _,choice in ipairs(order) do
            for _,stage in ipairs(choice.stages or {}) do
                if not A.Supplies.ApplyQuestLog({kind=stage.kind,questId=stage.questId or choice.questId},log) then return end
            end
        end
    end
    local paths={{position=state.position,seconds=0,low=0,high=0,xp=0,xpKnown=true,
        forecast={level=state.level,xp=state.xp,maxXP=state.maxXP,uncertain=state.xpUncertain},
        initial=false,hearthReady=state.hearthReady}}
    cache=cache or {}
    -- Reuse identical task prefixes across the trial orders in this solve.
    if cache.prefixState~=state then cache.prefixState,cache.prefixes=state,{} end
    local prefixes=cache.prefixes
    for index,choice in ipairs(order) do
        if not choice.stagesComplete then return end
        local source=choice.itemOriginal or choice.sourceChoice or choice
        local key=table.concat({choice.questId,tostring(source.stages),choice.stageIndex or "task",choice.itemAllocationKey or ""},":")
        local saved=prefixes[key]
        if saved then
            paths,bags=saved.paths,saved.bags
        else
            local staged=choice
            local changedBags=false
            for stageIndex,original in ipairs(choice.stages or {}) do
                local stage=original
                if A.TaskGuide.ItemGainBlocked(stage,state,bags) then return end
                if not changedBags and (next(stage.gainItems or {}) or (stage.itemGain or 0)>0 or next(stage.consumeItems or {})) then
                    bags=setmetatable(copy(bags),inventory);changedBags=true
                end
                for id,count in pairs(stage.gainItems or {}) do bags[id]=(bags[id] or 0)+count end
                if stage.itemGain and stage.itemGain>0 then
                    if staged==choice then staged=copy(choice);staged.stages=copy(choice.stages) end
                    stage=copy(stage);stage.have=bags[stage.targetId] or 0;stage.need=stage.have+stage.itemGain
                    bags[stage.targetId]=stage.need
                    staged.stages[stageIndex]=stage
                end
                for id,count in pairs(stage.consumeItems or {}) do
                    if (bags[id] or 0)<count then return end
                    bags[id]=bags[id]-count
                end
            end
            local evaluated=staged
            local last=choice.stages and choice.stages[#choice.stages]
            if not last or not last.position then return end
            local nextPaths={}
            for _,path in ipairs(paths) do
                context.position=path.position
                context.hearthReady=path.hearthReady
                context.now=(state.now or 0)+path.seconds
                context.maxSeconds=state.maxSeconds and math.max(0,state.maxSeconds-path.seconds)
                context.level,context.xp,context.maxXP=path.forecast.level,path.forecast.xp,path.forecast.maxXP
                context.xpUncertain=path.forecast.uncertain or path.forecast.xpUncertain
                local p=path.position
                if not p then return end
                local timing=A.TaskGuide.Timing(p,evaluated,context,navigation)
                if timing and timing.seconds and timing.travelRoutes then
                    local xp
                    if choice.stageIndex and last.kind~="turnin" then xp=0
                    elseif not context.xpUncertain then
                        local quest=data and data:GetQuest(choice.questId)
                        xp=quest and A.TaskGuide.XP(quest,context.level,context) or
                            (context.level==state.level and choice.remainingXP or nil)
                    end
                    local forecast=path.forecast
                    if xp and A.Progression and not (xp==0 and context.maxXP and context.maxXP>(context.xp or 0)) then
                        forecast=A.Progression.Advance(context,xp)
                    end
                    if xp==nil then forecast=copy(path.forecast);forecast.uncertain=true end
                    for _,route in ipairs(timing.travelRoutes) do
                        local stepTiming=timing
                        if route~=timing.travelPlan then
                            stepTiming=copy(timing)
                            stepTiming.travelPlan,stepTiming.travel=route,route.seconds
                            stepTiming.coarse=route.coarse
                            stepTiming.travelLow,stepTiming.travelHigh=route.low,route.high
                            stepTiming.flightCount=route.flights
                            stepTiming.hearthReady,stepTiming.hearthCount=route.hearthReady,route.hearths
                            stepTiming.seconds,stepTiming.low,stepTiming.high=route.seconds,route.low,route.high
                            stepTiming.initial=route.initial
                        end
                        if not state.maxSeconds or path.seconds+stepTiming.seconds<=state.maxSeconds then
                            nextPaths[#nextPaths+1]={position=last.position,
                                seconds=path.seconds+stepTiming.seconds,low=path.low+stepTiming.low,high=path.high+stepTiming.high,
                                xp=path.xp+(xp or 0),xpKnown=path.xpKnown and xp~=nil,forecast=forecast,
                                previous=path,index=index,
                                step={choice=choice.sourceChoice or choice,stage=choice.stageIndex and evaluated.stages[1] or nil,timing=stepTiming,xp=xp},initial=path.initial or stepTiming.initial,
                                hearthReady=route.hearthReady}
                        end
                    end
                end
                checkpoint()
            end
            paths=A.Travel.Prune(nextPaths,state.now)
            if #paths==0 then return end
            saved={paths=paths,bags=bags,next={}}
            prefixes[key]=saved
        end
        prefixes=saved.next
    end
    if not paths[1] then return end
    -- Materialize the chosen steps once, rather than copying the prefix at every stage.
    local result=copy(paths[1]);result.steps={};result.bags=copy(state.bags or {})
    for id,count in pairs(bags) do result.bags[id]=count end
    local node=paths[1]
    while node.step do result.steps[node.index]=node.step;node=node.previous end
    result.previous,result.index,result.step=nil,nil,nil
    return result
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
function Q.Interleave(order,state,navigation,data,cache,seedOrder,prefix)
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
    for i=1,prefix or 0 do
        local group=byQuest[order[i].questId]
        if group then for _,choice in ipairs(group.choices) do byQuest[choice.questId]=nil end end
    end
    local batched=next(byQuest)~=nil
    if not multiple and not batched then return end
    if batched then stages=batchStages(stages,byQuest) end
    local best=Q.Evaluate(stages,state,navigation,data,cache)
    local first=state.locked and (#order[1].stages+1) or (order[1].orderHeld and 2 or 1)
    local fixed=0
    for i=1,prefix or 0 do fixed=fixed+#order[i].stages end
    first=math.max(first,fixed+1)
    local changed=batched
    -- Retain the regional pickup/work/hand-in candidate before local permutations.
    if not state.locked and not order[1].orderHeld then
        local phased={}
        for i=1,fixed do phased[#phased+1]=stages[i] end
        for _,kind in ipairs({"accept","objective","turnin"}) do
            for i,choice in ipairs(seedOrder or order) do
                if i>(prefix or 0) then
                    for index,stage in ipairs(choice.stages) do
                        if stage.kind==kind then
                            phased[#phased+1]={questId=choice.questId,stagesComplete=true,stages={stage},
                                stageIndex=index,sourceChoice=choice,remainingXP=choice.remainingXP}
                        end
                    end
                end
            end
        end
        if batched then phased=batchStages(phased,byQuest) end
        if #phased==#stages then
            local candidate=Q.Evaluate(phased,state,navigation,data,cache)
            if better(candidate,best,state) then stages,best,changed=phased,candidate,true end
        end
    end
    if not best then return nil,batched end
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

function Q.Solve(order,state,navigation,data,prefix)
    operations,deadline=0,clock()+1
    if #order==0 or not A.Flights or not A.TaskGuide or not A.Travel then return end
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
    local seed={};for i,c in ipairs(base) do seed[i]=c end
    local first=math.max((state.locked or best and base[1].orderHeld) and 2 or 1,(prefix or 0)+1)
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
    local interleaved,batchBlocked=Q.Interleave(base,state,navigation,data,cache,seed,prefix)
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
