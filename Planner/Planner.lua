local _, A = ...
A.Planner = {}
local P = A.Planner

local function copy(map)
    local result = {}
    for k, v in pairs(map) do result[k] = v end
    return result
end

local function rank(a, b)
    if (a.priority or 0) ~= (b.priority or 0) then return (a.priority or 0) > (b.priority or 0) end
    if a.rate ~= b.rate then return a.rate > b.rate end
    if a.seconds ~= b.seconds then return a.seconds < b.seconds end
    return tostring(a.id) < tostring(b.id)
end

-- Task ordering depends on destinations and movement, not execution-time estimates.
function P.TaskChoices(state,data,ids,onlySelected,options)
    local choices,seen={},{}
    local function add(id)
        if seen[id] then return end
        seen[id]=true
        local active=state.quests[id]
        local q=data:GetQuest(id)
        if not q and active then q={id=id,title=active.title or ("任务 #"..id)} end
        if not q or not A.Eligibility.Check(q,state,data) then return end
        local position=data:Target(q,state)
        local areaId,objectiveIndex
        if not position and data.UnmappedTargetArea then areaId,objectiveIndex=data:UnmappedTargetArea(q,state) end
        local instance=A.Dungeon and A.Dungeon.TaskInstance and A.Dungeon.TaskInstance(position,state,data,areaId) or
            A.Dungeon and A.Dungeon.TaskPvP and A.Dungeon.TaskPvP(position,state,data,areaId)
        local currentInstance=state.inInstance and instance and instance.instanceId==state.instanceId or false
        if not active and id~=state.locked and not state.preparingQuest and not currentInstance then
            if not position or not state.position then return end
            -- Adjacent zones share world coordinates; a UI map boundary is not a travel barrier.
            if position.map~=state.position.map then
                if state.inInstance or instance or not A.Travel then return end
                if A.Travel.Walk(state.position,position,state,A.Navigation)==nil and
                    (not A.Flights or not A.Flights.Routes(state.position,position,state,A.Navigation)) then return end
            end
        end
        local kind=active and (active.ready and "turnin" or "objective") or "accept"
        local action={kind=kind,questId=id,title=active and active.title or q.title,position=position,
            areaId=areaId,objectiveIndex=position and position.objectiveIndex or objectiveIndex,
            text=({accept="前往任务发布者，查看并接取任务。",objective="按任务日志继续完成目标。",turnin="目标已完成，前往任务交付者。"})[kind]}
        if kind=="objective" and data.DeliveryOnly and data:DeliveryOnly(q,state) then
            action.text="前往任务交付者对话，按游戏提示完成任务。"
        end
        local choice={id="task:"..id,kind="task",questId=id,title=action.title,actions={action},
            status=kind,level=q.questLevel,referenceXP=q.referenceXP,
            distance=position and A.Navigation and A.Navigation.Distance and A.Navigation:Distance(state.position,position)}
        if state.inInstance then choice.currentInstance=currentInstance end
        if A.TaskGuide then
            choice.stages,choice.stagesComplete=A.TaskGuide.Stages(q,state,data,action)
            local localAction=A.Dungeon and A.Dungeon.OrderTaskObjectives and A.Dungeon.OrderTaskObjectives(choice.stages,state,data)
            if localAction then
                action=localAction;choice.actions[1]=action
                instance=A.Dungeon.TaskInstance(action.position,state,data,action.areaId) or
                    A.Dungeon.TaskPvP and A.Dungeon.TaskPvP(action.position,state,data,action.areaId)
                if state.inInstance then choice.currentInstance=instance and instance.instanceId==state.instanceId or false end
                choice.distance=action.position and A.Navigation and A.Navigation.Distance and A.Navigation:Distance(state.position,action.position)
            end
            choice.remainingXP=A.TaskGuide.XP(q,state.level,state)
            if choice.remainingXP then choice.forecast=A.Progression.Advance(state,choice.remainingXP) end
        end
        if kind=="accept" and A.Supplies then choice.acceptBlocked=A.Supplies.AcceptIssue(state) end
        if q.taskFacts then
            choice.rewards,choice.groupReference=q.taskFacts.rewards,q.taskFacts.group
            if not active then
                local offers=position and position.entityKind=="npc" and state.questOffers and state.questOffers[position.entityId]
                choice.requireCheck=q.taskFacts.hidden and not (offers and offers[id])
                if choice.requireCheck then
                    choice.stagesComplete=false
                    action.text="向任务发布者查看此任务。"
                end
            end
        end
        if A.TaskGuide then choice.timing=A.TaskGuide.Timing(state.position,choice,state,A.Navigation) end
        if A.Dungeon and A.Dungeon.TaskEntryIssue then
            choice.entryBlocked=A.Dungeon.TaskEntryIssue(choice,state,data,options)
        end
        if A.TaskGuide then choice.lowValue=A.TaskGuide.LowValue(q,state,data,choice) end
        if A.Gear and A.Gear.TaskBenefits then A.Gear.TaskBenefits(choice,q,state,data) end
        choices[#choices+1]=choice
    end
    if not onlySelected then
        for id in pairs(state.quests) do add(id) end
        if state.locked then add(state.locked) end
    end
    for i,id in ipairs(ids) do
        add(id)
        if i%(A.TaskGuide and 5 or 25)==0 then coroutine.yield() end
    end
    local unknownXP={}
    for _,choice in ipairs(choices) do
        if choice.timing and choice.timing.seconds~=nil and choice.remainingXP==nil then
            unknownXP[choice.status..(choice.lowValue and ":low" or "")]=true
        end
    end
    table.sort(choices,function(a,b)
        if (a.questId==state.locked)~=(b.questId==state.locked) then return a.questId==state.locked end
        local aBlocked,bBlocked=a.acceptBlocked or a.entryBlocked,b.acceptBlocked or b.entryBlocked
        if (aBlocked~=nil)~=(bBlocked~=nil) then return not aBlocked end
        if (a.lowValue~=nil)~=(b.lowValue~=nil) then return not a.lowValue end
        if a.currentInstance~=b.currentInstance then return a.currentInstance==true end
        local order={turnin=1,objective=2,accept=3}
        if a.status~=b.status then return order[a.status]<order[b.status] end
        if A.TaskGuide and a.timing and b.timing and a.timing.seconds and b.timing.seconds then
            -- Keep one basis per status and priority group; skipped rewards do not change the active comparison.
            if not unknownXP[a.status..(a.lowValue and ":low" or "")] then
                local ar=A.TaskGuide.MovementRate(a.timing.seconds,a.remainingXP)
                local br=A.TaskGuide.MovementRate(b.timing.seconds,b.remainingXP)
                if ar~=br then return ar>br end
                if a.remainingXP~=b.remainingXP then return a.remainingXP>b.remainingXP end
            end
            if a.timing.seconds~=b.timing.seconds then return a.timing.seconds<b.timing.seconds end
        elseif (a.timing and a.timing.seconds~=nil or false)~=(b.timing and b.timing.seconds~=nil or false) then
            return a.timing and a.timing.seconds~=nil or false
        end
        if (a.distance~=nil)~=(b.distance~=nil) then return a.distance~=nil end
        if a.distance and a.distance~=b.distance then return a.distance<b.distance end
        return a.questId<b.questId
    end)
    return choices
end

function P.TaskOrder(state,choices,data)
    local pending,order,optional={},{},{}
    for _,choice in ipairs(choices) do
        choice.executionTiming=nil;choice.executionAction=nil
        if state.quests[choice.questId] or choice.questId==state.locked then
            if (choice.lowValue or choice.entryBlocked) and choice.questId~=state.locked then optional[#optional+1]=choice
            else pending[#pending+1]=choice end
        end
    end
    if #pending==0 then return choices end
    if A.TaskQueue then pending=A.TaskQueue.PrepareItems(pending,state) end
    local origin=state.position
    local projected=copy(state)
    while #pending>0 do
        local completion,distances,allStages={},{},true
        local timings,allTimes,allXP= {},true,true
        for index,choice in ipairs(pending) do
            if choice.remainingXP==nil then allXP=false end
            local pos=choice.actions[1].position
            if origin and pos then
                distances[index]=A.Navigation and A.Navigation.Distance and A.Navigation:Distance(origin,pos)
                local total
                if A.TaskGuide then
                    timings[index]=A.TaskGuide.Timing(origin,choice,projected,A.Navigation)
                    total=timings[index].geometric
                end
                if distances[index]~=nil or timings[index] and timings[index].seconds then
                    if timings[index] then
                        if not timings[index].seconds then allTimes=false end
                    else allTimes=false end
                    completion[index]=total
                    if total==nil then allStages=false end
                else timings[index]=nil end
            end
        end
        local useTime=allTimes
        local useRate=useTime and allXP and A.TaskGuide and A.TaskGuide.MovementRate
        local best,bestDistance,bestLocal
        for index,choice in ipairs(pending) do
            local localTarget=choice.currentInstance or (useTime and timings[index]~=nil or distances[index]~=nil)
            local distance=(allStages and completion[index]) or
                distances[index]
            if timings[index] then
                if useTime then distance=timings[index].seconds end
                if useRate then distance=-A.TaskGuide.MovementRate(timings[index].seconds,choice.remainingXP) end
            end
            local forced=#order==0 and choice.questId==state.locked
            if forced then best=index;break end
            if not best or (localTarget and not bestLocal) or (localTarget==bestLocal and
                ((distance and not bestDistance) or (distance and bestDistance and (distance<bestDistance or useRate and distance==bestDistance and (choice.remainingXP>pending[best].remainingXP or choice.remainingXP==pending[best].remainingXP and timings[index].seconds<timings[best].seconds))))) then
                best,bestDistance,bestLocal=index,distance,localTarget
            end
        end
        local held
        if #order==0 and not state.locked and timings[best] and useTime then
            for index,choice in ipairs(pending) do
                local current,proposed=timings[index],timings[best]
                if choice.questId==state.currentTask and not (state.quests[choice.questId] or {}).ready and index~=best and current then
                    local keep
                    if useRate then
                        keep=A.TaskGuide.MovementRate(current.seconds,choice.remainingXP)>=
                            A.TaskGuide.MovementRate(proposed.seconds,pending[best].remainingXP)*0.9
                        if current.seconds==proposed.seconds and choice.remainingXP<pending[best].remainingXP then keep=false end
                    else keep=current.seconds<=proposed.seconds/0.9 or current.low<=proposed.high end
                    if keep then best=index;held=true end
                    break
                end
            end
        end
        local choice=table.remove(pending,best)
        choice.orderHeld=held
        choice.orderTiming=timings[best]
        choice.orderBasis=timings[best] and useTime and (useRate and "movement-xp" or "movement-time") or
            (allStages and completion[best] and "completion-geometry" or "geometry")
        order[#order+1]=choice
        local last=choice.stages and choice.stages[#choice.stages]
        origin=(useTime or choice.orderBasis=="completion-geometry") and last and last.position or choice.actions[1].position or origin
    end
    if A.TaskQueue then
        local joint,queue=A.TaskQueue.Solve(order,state,A.Navigation,data)
        local pickup,pickupQueue=A.TaskQueue.Pickup(joint or order,choices,state,A.Navigation,data,queue)
        joint,queue=pickup or joint,pickupQueue or queue
        if joint then
            for _,choice in ipairs(optional) do joint[#joint+1]=choice end
            queue.optional=#optional
            return joint,queue
        end
    end
    for _,choice in ipairs(order) do
        if choice.itemsPrepared then
            choice.executionAction=choice.stages[1]
            choice.executionTiming=choice.orderTiming
        end
    end
    for _,choice in ipairs(optional) do order[#order+1]=choice end
    return order
end

function P.Build(state, data, options)
    if state.level >= 60 and (not state.dungeon or state.dungeon.phase=="complete") then return { revision = state.revision, complete = true, alternatives = {} } end
    local gearSource=state.gearTarget and A.Gear.GetSource and A.Gear.GetSource(state.gearTarget,data,state)
    if type(state.gearTarget)=="string" and (state.gearTarget:match("^reward:") or state.gearTarget:match("^drop:")) and not gearSource then
        local reason="所选装备来源暂不可用；可恢复升级目标。"
        return {revision=state.revision,alternatives={},taskChoices={},selectionBlocked=reason,
            fallback={kind="selectionBlocked",title="装备目标暂不可用",text=reason}}
    end
    if gearSource and gearSource.reference and gearSource.kind=="quest" then state=copy(state);state.locked=gearSource.questId end
    local preparation,preparationReason
    if state.locked and (not state.dungeon or state.dungeon.phase=="complete") and A.Chains and A.Chains.Preparation then
        local root=data:GetQuest(state.locked)
        if root then
            local allowed,reason=A.Eligibility.Check(root,state,data)
            if not allowed then
                preparationReason=reason
                local ids=A.Chains.Preparation(root.id,data,state)
                local eligible={};for _,id in ipairs(ids) do eligible[id]=true end
                local context=copy(state);context.locked=nil;context.preparingQuest=root.id
                for _,choice in ipairs(P.TaskChoices(context,data,ids)) do
                    if eligible[choice.questId] and not choice.acceptBlocked then
                        state=copy(state);state.locked=choice.questId
                        preparation={id=root.id,title=root.title};break
                    elseif eligible[choice.questId] and choice.acceptBlocked then preparationReason=choice.acceptBlocked end
                end
            end
        end
    end
    local batchChoices,batch
    if state.taskBatch and A.Dungeon.TaskBatchChoices then batchChoices,batch=A.Dungeon.TaskBatchChoices(state,data) end
    local ids=batch and {} or data:Candidates(state)
    -- Include eligible prerequisites outside the current level index.
    local seen = {}
    local function prerequisites(id, depth)
        if seen[id] or depth > 32 then return end
        seen[id] = true
        local q = data:GetQuest(id)
        if not q then return end
        for _, list in ipairs({q.preQuestGroup or {}, q.preQuestSingle or {}}) do
            for _, required in ipairs(list) do
                prerequisites(math.abs(required), depth + 1)
                if required > 0 and list == q.preQuestGroup then
                    local pre = data:GetQuest(required)
                    for _, alternative in ipairs(pre and pre.exclusiveTo or {}) do prerequisites(alternative, depth + 1) end
                end
            end
        end
    end
    for _, id in ipairs(ids) do prerequisites(id, 0) end
    ids = {}
    for id in pairs(seen) do ids[#ids + 1] = id end
    table.sort(ids)
    local alternatives={}
    for _,dungeon in pairs(not batch and data.content.dungeons or {}) do
        local candidate=A.Dungeon.Evaluate(dungeon,state,options,data)
        if candidate then alternatives[#alternatives+1]=candidate end
    end
    table.sort(alternatives,rank)
    A.Gear.Benefits(alternatives,state,data.content)
    local result={revision=state.revision,best=alternatives[1],alternatives=alternatives,preparingQuest=preparation,
        origin=state.position and {map=state.position.map,node=state.position.node}}
    result.taskChoices=batchChoices or P.TaskChoices(state,data,ids,nil,options)
    local preferred=not batch and A.Gear.PreferTask and A.Gear.PreferTask(result.taskChoices,state,options)
    if preferred then
        for index,choice in ipairs(result.taskChoices) do if choice==preferred then table.remove(result.taskChoices,index);break end end
        table.insert(result.taskChoices,1,preferred);result.preferenceApplied=true
    end
    result.taskBatch=batch
    if state.locked then result.best=nil end
    if result.best and result.best.requiresAcceptance then
        result.suggestedDungeon=result.best;result.best=nil
    end
    if not state.locked then
        local previous=result.best
        result.best,result.gearTargetBlocked=A.Gear.Prefer(alternatives,result.best,state,options)
        result.preferenceApplied=result.preferenceApplied or state.gearTarget~=nil or previous~=result.best
    end
    if state.dungeon and state.dungeon.phase~="complete" then
        local d = data.content.dungeons[state.dungeon.id]
        local actions = d and A.Dungeon.ActivePlan(d,state,data)
        if actions then
            result.best = {id="accepted:"..d.id..":"..state.dungeon.round,title=d.title,
                kind="dungeon",dungeonId=d.id,actions=actions,seconds=0,xp=0,rate=0}
            result.sessionActive = true
        else
            result.fallback = {title="副本资料暂不可用",kind="dungeonBlocked",text="保留已选行程，可结束行程后恢复练级"}
            result.best=nil
            result.sessionActive=true
        end
    end
    if not result.sessionActive and gearSource and gearSource.reference and gearSource.kind=="dungeon" then
        A.Gear.PlanDungeonTarget(result,gearSource,state,data)
    end
    if not result.sessionActive and A.Supplies and (not result.best or state.serviceStop and
        (state.freeSlots==0 or state.durability and state.durability<0.2)) then
        local maintenance,why=A.Supplies.Fallback(state,data)
        result.supplyIssue=not maintenance and why or nil
        if maintenance then
            result.maintenance=true
            if maintenance.reference then
                result.unverified=true;result.travelActions=maintenance.actions
                result.fallback=maintenance.actions[#maintenance.actions]
            else result.best=maintenance end
        end
    end
    if result.maintenance then
        local choices=batch and A.Dungeon.TaskBatchStage(result.taskChoices,state,data) or result.taskChoices
        result.taskOrder,result.taskQueue=P.TaskOrder(state,choices,data)
    end
    if not result.best and not result.sessionActive and not result.maintenance and not result.serviceStop and not result.gearPlan then
        -- Reference quests use straight-line travel estimates.
        result.unverified = true
        local choices=batch and A.Dungeon.TaskBatchStage(result.taskChoices,state,data) or result.taskChoices
        result.taskOrder,result.taskQueue=P.TaskOrder(state,choices,data)
        local automatic={}
        for _,choice in ipairs(result.taskOrder) do automatic[#automatic+1]=choice end
        for _,choice in ipairs(choices) do automatic[#automatic+1]=choice end
        local deliveryGroups={}
        if A.TaskGuide then local groups;groups,deliveryGroups=A.TaskGuide.DeliveryGroups(result.taskChoices,state,result.taskOrder) end
        local entryBlocked
        local itemBlockedQuests={}
        for _,choice in ipairs(automatic) do
            local group=deliveryGroups[choice.questId]
            local waiting=not state.locked and group and not group.splitDelivery and group.ready<#group.choices and
                (choice.executionAction or choice.actions[1]).kind=="turnin"
            local itemBlocked=itemBlockedQuests[choice.questId] or A.TaskGuide and A.TaskGuide.ItemGainBlocked(choice.executionAction or choice.actions[1],state)
            if itemBlocked then result.itemLimitIssue=true;itemBlockedQuests[choice.questId]=true end
            if not itemBlocked and not waiting and not choice.lowValue and not choice.acceptBlocked and (not state.locked or choice.questId==state.locked) and (not choice.requireCheck or state.locked==choice.questId) then
                local task=choice.executionAction or choice.actions[1]
                local approach=choice.entryBlocked and {kind="dungeonBlocked",questId=choice.questId,title=choice.title,text=choice.entryBlocked} or
                    A.Dungeon and A.Dungeon.TaskApproach and A.Dungeon.TaskApproach(task,state,data) or task
                if approach.kind=="dungeonBlocked" then entryBlocked=entryBlocked or approach
                else
                    result.preparingQuest=choice.preparingQuest or result.preparingQuest
                    result.fallback=approach
                    local timing=choice.executionTiming or choice.timing
                    local journey=timing and timing.travelPlan
                    if result.fallback~=task or not journey then
                        local routes=A.Flights and result.fallback.position and A.Flights.Itinerary(state.position,{result.fallback},state,A.Navigation)
                        journey=routes and routes[1]
                    end
                    local complete=A.Flights and journey and A.Flights.Actions(journey.firstRoute,result.fallback,A.Navigation)
                    if complete then result.travelActions=complete;result.referenceJourney=journey end
                    local flight=not complete and A.Flights and A.Flights.Guide(result.fallback,state,A.Navigation)
                    if flight then result.travelActions=flight.actions;result.referenceFlight=flight end
                    break
                end
            end
        end
        result.fallback=result.fallback or entryBlocked
        if not result.fallback and result.itemLimitIssue then
            result.fallback={kind="selectionBlocked",title="先交付已备齐的任务",text="任务物品已达持有上限，交付后再继续收集。"}
        end
    end
    if not result.best and not result.fallback then
        for _,choice in ipairs(result.taskChoices) do
            if choice.acceptBlocked and (not state.locked or choice.questId==state.locked) then
                result.fallback={kind="selectionBlocked",title="接取任务前先处理日志",text=choice.acceptBlocked}
                break
            end
        end
    end
    if not result.best and not result.fallback and preparationReason then
        result.fallback={kind="selectionBlocked",title="所选任务暂不可继续",text=preparationReason.."；可在任务链中查看条件。"}
    end
    if not result.best and not result.fallback then
        for _,choice in ipairs(result.taskChoices or {}) do
            if choice.lowValue then
                result.fallback={kind="taskReview",title="当前剩余任务收益偏低",text="可查看下方放弃／跳过建议，或点击任务手动继续。"}
                break
            end
        end
    end
    if batch and not result.best and not result.fallback then
        result.fallback={kind="selectionBlocked",title=batch.title.."任务等待处理",
            text=(batch.blocked[1] or "当前任务尚无可执行目标").."；可在副本页查看任务条件或结束安排。"}
    end
    if A.Dungeon.TaskBatchWaitPlan then A.Dungeon.TaskBatchWaitPlan(result,state,data,options) end
    if A.Services then result.bindingChoices=A.Services.PlanBindings(result,state,data) end
    if A.Services then result.automaticService=A.Services.AutomaticBinding(result,state) end
    if (state.serviceStop or result.automaticService) and A.Services and not result.sessionActive and not result.maintenance then
        local stop=A.Services.Build(state,result,result.automaticService)
        if stop then
            result.serviceResume=A.Services.TaskDestination(result)
            result.best=nil;result.serviceStop=true;result.unverified=true
            result.fallback,result.travelActions=stop.fallback,stop.travelActions
            result.referenceJourney,result.referenceFlight=stop.referenceJourney,stop.referenceFlight
        end
    end
    return result
end
