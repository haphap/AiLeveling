local _, A = ...
A.Planner = {}
local P = A.Planner

local function copy(map)
    local result = {}
    for k, v in pairs(map) do result[k] = v end
    return result
end

local function contains(candidate, id)
    if candidate.questId == id then return true end
    for _, questId in ipairs(candidate.questIds or {}) do if questId == id then return true end end
    for _,action in ipairs(candidate.actions or {}) do if action.questId==id then return true end end
    return false
end

function P.MergeObjectives(actions,state)
    local result,groups={},{}
    for _,action in ipairs(actions) do
        local active=state.quests[action.questId]
        local key=action.kind=="objective" and action.shareKey and
            not next(action.items or {}) and not next(action.requiredItems or {}) and not next(action.gainItems or {}) and
            not next(action.consumeItems or {}) and not action.reserveSlots and not action.minFreeSlots and not action.durabilityLoss and
            (action.shareType=="kill" or action.shareType=="collect") and action.targetId and
            table.concat({action.shareKey,action.shareType,action.targetId,action.node or ""},"|")
        local shared=key and groups[key]
        if shared and (shared.clientItem~=(active and active.itemId)) then shared=nil;key=nil end
        if shared then
            if shared.minDurability or action.minDurability then shared.minDurability=math.max(shared.minDurability or 0,action.minDurability or 0) end
            shared.sharedObjectives[#shared.sharedObjectives+1]={questId=action.questId,objectiveIndex=action.objectiveIndex or 1}
        else
            if key then
                action.sharedObjectives={{questId=action.questId,objectiveIndex=action.objectiveIndex or 1}}
                action.clientItem=active and active.itemId
                groups[key]=action
            end
            result[#result+1]=action
        end
    end
    return result
end

function P.Actions(q, state)
    local active, result = state.quests[q.id], {}
    for _, action in ipairs(q.actions or {}) do
        local done = action.kind == "accept" and active ~= nil
        if action.kind=="service" and A.Supplies then done=A.Supplies.Done(action,state) end
        if action.kind == "objective" and active then
            local o = active.objectives[action.objectiveIndex or 1]
            done = active.ready or (o and o.finished)
        end
        if not done then
            local item = copy(action)
            item.questId, item.title = q.id, action.title or q.title
            result[#result + 1] = item
        end
    end
    return result
end

function P.EvaluateMany(quests, state, data, options, from)
    if #quests==0 then return nil,"候选任务为空" end
    local raw, rewards, priority, ids, titles = {}, 0, 0, {}, {}
    local questById={}
    local phases = {accept=1, objective=2, turnin=3}
    for _, q in ipairs(quests) do
        local eligible, reason = A.Eligibility.Check(q, state, data)
        if not eligible then return nil, reason end
        if not q.verified or not q.actions then return nil, "行动链尚未验证" end
        if options.mode == "relaxed" and q.requiresGroup and state.groupSize < q.requiresGroup then
            return nil, "轻松模式下队伍条件不足"
        end
        if q.xp==nil then return nil,"任务经验模型缺失" end
        questById[q.id]=q
        ids[#ids + 1], titles[#titles + 1] = q.id, q.title
        if options.mode == "story" and q.story then priority = 1 end
        local actions = P.Actions(q, state)
        if #actions == 0 or actions[#actions].kind ~= "turnin" then return nil, "行动链未包含交付" end
        local previousPhase = 0
        for _, action in ipairs(actions) do
            if #quests > 1 then
                local phase = phases[action.kind]
                if not phase or phase < previousPhase then return nil, "复杂任务保留独立行动顺序" end
                previousPhase = phase
            end
            if action.shareKey and (action.kind~="objective" or
                (action.shareType~="kill" and action.shareType~="collect") or
                type(action.targetId)~="number" or action.targetId<=0 or action.targetId>=math.huge or action.targetId~=action.targetId) then
                return nil,"共享目标身份无效"
            end
            if phases[action.kind] then
                action.seconds=0
                action.referenceSeconds,action.sampleKind=nil,nil
            end
            if action.kind=="objective" then
                action.minDurability=action.minDurability or q.minDurability or (q.combat and 0.2 or nil)
            end
            if A.Supplies then
                local valid,why=A.Supplies.ValidAction(action)
                if not valid then return nil,why end
            end
            if action.seconds == nil then return nil, "行动耗时尚未建立" end
            raw[#raw + 1] = action
        end
    end
    if #quests > 1 then
        table.sort(raw, function(a,b)
            if phases[a.kind] ~= phases[b.kind] then return phases[a.kind] < phases[b.kind] end
            if a.node ~= b.node then return tostring(a.node) < tostring(b.node) end
            return a.questId < b.questId
        end)
        raw=P.MergeObjectives(raw,state)
    end
    local context=copy(state)
    for _,action in ipairs(raw) do
        action.position=action.position or (action.node and data.content.nodes[action.node].position)
        if action.kind=="turnin" then
            local q=questById[action.questId]
            if type(q.xp)=="table" and context.xpUncertain then return nil,"预测等级未确认，交付经验待核对" end
            local xp=type(q.xp)=="table" and q.xp[context.level] or q.xp
            if type(xp)~="number" or xp<0 or xp>=math.huge or xp~=xp then return nil,"当前等级经验未知" end
            rewards=rewards+xp
            action.unlockAfter="quest:"..action.questId
            local forecast=A.Progression.Advance(context,xp,data.content)
            context.level,context.xp,context.maxXP,context.xpUncertain=forecast.level,forecast.xp,forecast.maxXP,forecast.uncertain
            context.xpCurveSource=forecast.curveSource
            action.levelAfter=forecast.level
        end
    end
    local travelState=copy(state)
    travelState.maxSeconds=options.minutes*60
    local paths,reason
    if A.Supplies then paths,reason=A.Supplies.Itinerary(data.content,from,raw,travelState)
    else paths,reason=A.Travel.Itinerary(data.content,from,raw,travelState) end
    if not paths then return nil,reason end
    local variants={}
    for _,path in ipairs(paths) do
        local seconds=path.seconds
        path.resources.now=(state.now or 0)+seconds
        local candidate={id=#ids==1 and ids[1] or ("cluster:"..table.concat(ids,":")),
            title=table.concat(titles,"＋"),questId=ids[1],questIds=ids,
            seconds=seconds,xp=rewards,rate=rewards/math.max(1,seconds),
            actions=path.actions,lastNode=path.lastNode,kind=#ids==1 and "quest" or "cluster",
            priority=priority,resources=path.resources,sequence=table.concat(ids,":"),
            forecast={level=context.level,xp=context.xp,maxXP=context.maxXP,uncertain=context.xpUncertain,curveSource=context.xpCurveSource}}
        candidate.routeKey=P.RouteKey(candidate)
        variants[#variants+1]=candidate
    end
    return variants[1],nil,variants
end

function P.RouteKey(candidate)
    local keys={}
    for _,action in ipairs(candidate.actions or {}) do
        keys[#keys+1]=table.concat({action.kind or "",action.questId or "",action.node or "",action.transitId or "",action.serviceId or ""},":")
    end
    return table.concat(keys,"|")
end

-- Beam width counts task sequences; each selected sequence retains its resource alternatives.
function P.Select(candidates,limit)
    local result,groups,keys,count={},{},{},0
    for _,candidate in ipairs(candidates) do
        local group=candidate.sequence or tostring(candidate.id)
        if not groups[group] and count<limit then groups[group]=true;count=count+1 end
        local key=candidate.routeKey or group
        if groups[group] and not keys[key] then result[#result+1]=candidate;keys[key]=true end
    end
    return result,count,groups
end

function P.Evaluate(q, state, data, options, from)
    if not q then return nil,"任务资料缺失" end
    return P.EvaluateMany({q}, state, data, options, from)
end

function P.Project(state,path)
    local virtual=copy(state)
    virtual.completed,virtual.quests=copy(state.completed),copy(state.quests)
    for _,action in ipairs(path.actions) do
        if action.kind=="turnin" then virtual.completed[action.questId],virtual.quests[action.questId]=true,nil end
    end
    if path.resources then
        virtual.now,virtual.money,virtual.hearthReady=path.resources.now,path.resources.money,path.resources.hearthReady
        virtual.unlocked=path.resources.unlocked or virtual.unlocked
        if A.Supplies and path.resources.supplies then A.Supplies.Project(virtual,path.resources.supplies) end
    end
    if path.forecast then
        virtual.level,virtual.xp,virtual.maxXP=path.forecast.level,path.forecast.xp,path.forecast.maxXP
        virtual.xpUncertain=path.forecast.uncertain
    end
    return virtual
end

function P.Join(path,nextPart)
    local joined=copy(path)
    joined.actions,joined.questIds={},{}
    for _,part in ipairs({path,nextPart}) do
        for _,action in ipairs(part.actions) do joined.actions[#joined.actions+1]=action end
        for _,id in ipairs(part.questIds or {part.questId}) do joined.questIds[#joined.questIds+1]=id end
    end
    joined.title=path.title.." → "..nextPart.title
    joined.seconds,joined.xp=path.seconds+nextPart.seconds,path.xp+nextPart.xp
    joined.rate,joined.lastNode=joined.xp/math.max(1,joined.seconds),nextPart.lastNode
    joined.priority=math.max(path.priority or 0,nextPart.priority or 0)
    joined.sequence=path.sequence..">"..nextPart.sequence
    joined.resources,joined.forecast=nextPart.resources,nextPart.forecast
    joined.routeKey=P.RouteKey(joined)
    return joined
end

local function clusterKey(q, state)
    local target, count = nil, 0
    for _, a in ipairs(P.Actions(q, state)) do
        if a.kind == "objective" then
            count = count + 1
            if not a.node or (target and target ~= a.node) then return nil end
            target = a.node
        end
    end
    if count == 1 then return target end
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
            if choice.remainingXP then choice.forecast=A.Progression.Advance(state,choice.remainingXP,data.content) end
        end
        if kind=="accept" and A.Supplies then choice.acceptBlocked=A.Supplies.AcceptIssue(state) end
        if q.taskFacts then
            choice.rewards,choice.groupReference=q.taskFacts.rewards,q.taskFacts.group
            if not active then
                choice.requireCheck=q.taskFacts.hidden
                if choice.requireCheck then
                    choice.stagesComplete=false
                    action.text="资料含节日、退役或获取限制标记，先到任务发布者确认当前是否开放。"
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
    table.sort(choices,function(a,b)
        if (a.questId==state.locked)~=(b.questId==state.locked) then return a.questId==state.locked end
        local aBlocked,bBlocked=a.acceptBlocked or a.entryBlocked,b.acceptBlocked or b.entryBlocked
        if (aBlocked~=nil)~=(bBlocked~=nil) then return not aBlocked end
        if (a.lowValue~=nil)~=(b.lowValue~=nil) then return not a.lowValue end
        if a.currentInstance~=b.currentInstance then return a.currentInstance==true end
        local order={turnin=1,objective=2,accept=3}
        if a.status~=b.status then return order[a.status]<order[b.status] end
        if A.TaskGuide and a.timing and b.timing and a.timing.seconds and b.timing.seconds then
            -- An unknown reward must not erase the XP comparison of every other candidate.
            if (a.remainingXP~=nil)~=(b.remainingXP~=nil) then return a.remainingXP~=nil end
            if a.remainingXP~=nil then
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
        if choice.orderTiming and choice.orderTiming.travelPlan then projected.money=choice.orderTiming.money end
        choice.orderBasis=timings[best] and useTime and (useRate and "movement-xp" or "movement-time") or
            (allStages and completion[best] and "completion-geometry" or "geometry")
        order[#order+1]=choice
        local last=choice.stages and choice.stages[#choice.stages]
        origin=(useTime or choice.orderBasis=="completion-geometry") and last and last.position or choice.actions[1].position or origin
    end
    if A.TaskQueue then
        local joint,queue=A.TaskQueue.Solve(order,state,A.Navigation,data)
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
    local gearSource=state.gearTarget and A.Gear.GetSource and A.Gear.GetSource(state.gearTarget,data)
    if type(state.gearTarget)=="string" and state.gearTarget:match("^reward:") and not gearSource then
        local reason="所选装备奖励资料暂不可用；可恢复升级目标。"
        return {revision=state.revision,alternatives={},taskChoices={},selectionBlocked=reason,
            fallback={kind="selectionBlocked",title="装备目标暂不可用",text=reason}}
    end
    if gearSource and gearSource.reference then state=copy(state);state.locked=gearSource.questId end
    local preparation,preparationReason
    if state.locked and not state.itinerary and (not state.dungeon or state.dungeon.phase=="complete") and A.Chains and A.Chains.Preparation then
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
    local ids, candidates, blocked = batch and {} or data:Candidates(state), {}, {}
    -- Include prerequisite closures before the bounded search, including low-reward setup quests.
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
    local from = state.position and (state.position.node or state.position)
    local clusters = {}
    for i, id in ipairs(ids) do
        local q = data:GetQuest(id)
        local candidate, reason, variants = P.Evaluate(q, state, data, options, from)
        if candidate then
            for _,variant in ipairs(variants) do candidates[#candidates+1]=variant end
            local key = not q.repeatable and clusterKey(q, state)
            if key then
                clusters[key] = clusters[key] or {}
                clusters[key][#clusters[key] + 1] = q
            end
        else blocked[id] = reason end
        if i % 10 == 0 then coroutine.yield() end
    end
    for _, quests in pairs(clusters) do
        -- Small bundles keep the search responsive while retaining shared travel savings.
        for i = 1, #quests - 1 do
            local bundle = {quests[i]}
            for j = i + 1, math.min(#quests, i + 2) do
                bundle[#bundle + 1] = quests[j]
                local candidate,_,variants = P.EvaluateMany(bundle, state, data, options, from)
                if candidate then for _,variant in ipairs(variants) do candidates[#candidates+1]=variant end end
            end
        end
    end
    table.sort(candidates, rank)
    local alternatives,groupCount,groups=P.Select(candidates,8)
    for _,candidate in ipairs(candidates) do
        local q=data:GetQuest(candidate.id)
        local group=candidate.sequence
        if q and q.setup and (groups[group] or groupCount<12) then
            if not groups[group] then groups[group]=true;groupCount=groupCount+1 end
            local found=false
            for _,existing in ipairs(alternatives) do if existing.routeKey==candidate.routeKey then found=true;break end end
            if not found then alternatives[#alternatives+1]=candidate end
        end
    end
    local beam = {}
    for _, c in ipairs(alternatives) do beam[#beam + 1] = c end
    for depth = 2, 3 do
        local expanded = {}
        for _, path in ipairs(beam) do
            if not path.forecast or (not path.forecast.uncertain and path.forecast.level<60) then
            local virtual = P.Project(state,path)
            local remaining = copy(options)
            remaining.minutes = options.minutes - path.seconds / 60
            for i, id in ipairs(ids) do
                local q = data:GetQuest(id)
                local nextPart,_,variants = P.Evaluate(q, virtual, data, remaining, path.lastNode)
                if nextPart and not q.repeatable then
                    for _,nextPart in ipairs(variants) do
                    expanded[#expanded + 1] = P.Join(path,nextPart)
                    end
                end
                if i % 10 == 0 then coroutine.yield() end
            end
            end
        end
        table.sort(expanded, rank)
        beam=P.Select(expanded,8)
        for _,candidate in ipairs(beam) do alternatives[#alternatives+1]=candidate end
    end
    for _, dungeon in pairs(not batch and data.content.dungeons or {}) do
        local candidate = A.Dungeon.Evaluate(dungeon, state, options, data)
        if candidate then alternatives[#alternatives + 1] = candidate end
    end
    if state.gearTarget then
        local source=(data.content.gearSources or {})[state.gearTarget]
        if source and source.kind=="quest" then
            for _,candidate in ipairs(candidates) do
                if contains(candidate,source.questId) then
                    local found=false
                    for _,existing in ipairs(alternatives) do if existing==candidate then found=true;break end end
                    if not found then alternatives[#alternatives+1]=candidate end
                end
            end
        end
    end
    local selected,selectionReason
    if state.itinerary and A.Selection then
        selected,selectionReason=A.Selection.Evaluate(state.itinerary,state,data,options)
        for index,candidate in ipairs(selected or {}) do
            local found=false
            for _,existing in ipairs(alternatives) do
                if existing.routeKey==candidate.routeKey then selected[index]=existing;found=true;break end
            end
            if not found then alternatives[#alternatives+1]=candidate end
        end
    end
    table.sort(alternatives, rank)
    A.Gear.Benefits(alternatives,state,data.content)
    local best = alternatives[1]
    local result = { revision = state.revision, best = best, alternatives = alternatives, blocked = blocked,preparingQuest=preparation,
        origin=state.position and {map=state.position.map,node=state.position.node} }
    result.taskChoices=batchChoices or P.TaskChoices(state,data,ids,nil,options)
    local preferred=not batch and A.Gear.PreferTask and A.Gear.PreferTask(result.taskChoices,state,options)
    if preferred then
        for index,choice in ipairs(result.taskChoices) do if choice==preferred then table.remove(result.taskChoices,index);break end end
        table.insert(result.taskChoices,1,preferred);result.preferenceApplied=true
    end
    result.taskBatch=batch
    if state.locked and not state.itinerary then
        for _, c in ipairs(alternatives) do if contains(c, state.locked) then result.best = c; break end end
        if not result.best or not contains(result.best, state.locked) then
            for _, c in ipairs(candidates) do if contains(c, state.locked) then result.best = c; break end end
        end
        if not result.best or not contains(result.best, state.locked) then
            result.best=nil
            result.lockedBlocked = blocked[state.locked] or "锁定任务暂无完整行程估计"
        end
    end
    if result.best and result.best.requiresAcceptance then
        result.suggestedDungeon = result.best
        result.best = nil
        for _, c in ipairs(alternatives) do if c.kind ~= "dungeon" then result.best = c; break end end
    end
    if not state.locked and not state.itinerary then
        local previous=result.best
        result.best,result.gearTargetBlocked=A.Gear.Prefer(alternatives,result.best,state,options)
        result.preferenceApplied=result.preferenceApplied or state.gearTarget~=nil or previous~=result.best
    end
    if state.itinerary then
        result.selectionActive,result.selectionBlocked=true,selectionReason
        result.best=selected and selected[1] or nil
        if selected then
            for _,candidate in ipairs(selected) do
                if candidate.routeKey==state.itinerary.preferredKey then result.best=candidate;break end
            end
        end
    end
    if state.dungeon and state.dungeon.phase~="complete" then
        local d = data.content.dungeons[state.dungeon.id]
        local actions = d and A.Dungeon.ActivePlan(d,state,data)
        if actions then
            result.best = {id="accepted:"..d.id..":"..state.dungeon.round,title=d.title,
                kind="dungeon",dungeonId=d.id,actions=actions,seconds=0,xp=0,rate=0}
            if state.dungeon.phase=="preparing" and actions[1] and actions[1].kind=="dungeonWait" then
                local wait = math.max(0,(options.waitMinutes and options.waitMinutes*60 or d.waitSeconds or 0)-(state.dungeon.waited or 0))
                wait=math.min(wait,math.max(0,state.dungeon.budget-state.dungeon.elapsed))
                local evaluation=A.Dungeon.Evaluate(d,state,options,data)
                local activity=evaluation and evaluation.waitActivity
                if activity and activity.seconds>wait then activity=nil end
                if activity then result.best=activity; result.waitingDungeon=d.id end
            end
            result.sessionActive = true
        else
            result.fallback = {title="副本资料暂不可用",kind="dungeonBlocked",text="保留已选行程，可结束行程后恢复练级"}
            result.best=nil
            result.sessionActive=true
        end
    end
    if not result.sessionActive and A.Supplies and (not result.best or state.serviceStop and
        (state.freeSlots==0 or state.durability and state.durability<0.2)) then
        local maintenance,why=A.Supplies.Fallback(state,data,blocked)
        result.supplyIssue=not maintenance and why or nil
        if maintenance then
            result.maintenance=true
            if maintenance.reference then
                result.unverified=true;result.travelActions=maintenance.actions
                result.fallback=maintenance.actions[#maintenance.actions]
            else result.best=maintenance end
        end
    end
    if not result.best and not result.sessionActive and not result.maintenance and not result.serviceStop and result.selectionActive then
        result.fallback={kind="selectionBlocked",title="所选行程暂不可执行",
            text=(result.selectionBlocked or "等待可用任务与位置").."；可在行程页恢复自动选择。"}
    end
    if not result.best and not result.sessionActive and not result.maintenance and not result.serviceStop and not result.selectionActive then
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
    if A.Services then result.bindingChoices=A.Services.PlanBindings(result,state,data) end
    if A.Services then result.flightUnlockChoices=A.Services.PlanFlightUnlocks(result,state) end
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

function P.Choose(old, new, locked)
    if locked or new.sessionActive or new.preferenceApplied or new.maintenance or new.selectionActive or new.serviceStop or new.taskBatch then return new end
    -- Both plans must have been recomputed against the same current state.
    -- Never reuse an old plan with stale eligibility or spent travel costs.
    if not old or not old.best then return new end
    local oldCandidate
    for _,c in ipairs(new.alternatives) do
        if (old.best.routeKey and c.routeKey==old.best.routeKey) or (not old.best.routeKey and c.id==old.best.id) then oldCandidate=c;break end
    end
    if oldCandidate and new.best and ((locked and contains(oldCandidate, locked)) or
        ((oldCandidate.priority or 0) >= (new.best.priority or 0) and oldCandidate.rate >= new.best.rate * 0.9)) then
        new.best = oldCandidate
    end
    return new
end
