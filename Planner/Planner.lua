local _, A = ...
A.Planner = {}
local P = A.Planner
local clock=debugprofilestop or function() return os.clock()*1000 end

local function copy(map)
    local result = {}
    for k, v in pairs(map) do result[k] = v end
    return result
end

-- Task ordering depends on destinations and movement, not execution-time estimates.
function P.TaskChoices(state,data,ids,onlySelected,options)
    local choices,seen={},{}
    local unlocks=A.TaskGuide and A.TaskGuide.UnlockRecommendations(state,data,data.ids or ids) or {}
    local automatic=not (state.locked or state.preparingQuest or state.taskBatch or state.gearTarget or state.inInstance)
    local thread,isMain=coroutine.running()
    local deadline=clock()+1
    local function add(id)
        if seen[id] then return end
        seen[id]=true
        local active=state.quests[id]
        local q=data:GetQuest(id,state)
        if not q and active then q={id=id,title=active.title or ("任务 #"..id),questLevel=active.level} end
        if not q or not A.Eligibility.Check(q,state,data) then return end
        local kind=active and (active.ready and "turnin" or "objective") or "accept"
        local lowValue
        if A.TaskGuide and not unlocks[id] then lowValue=A.TaskGuide.LowValue(q,state,data) end
        local later=automatic and kind~="turnin" and not unlocks[id] and (q.questLevel or state.level)>state.level+2
        if automatic and (lowValue or later) then
            -- Keep catalog and revisit metadata without resolving targets that will not be routed.
            local title=active and active.title or q.title
            local facts=q.taskFacts or data.CacheQuest and data:CacheQuest(q,state)
            local map=data.maps and data.maps[q.zoneOrSort]
            choices[#choices+1]={id="task:"..id,kind="task",questId=id,title=title,status=kind,
                level=q.questLevel,remainingXP=A.TaskGuide.XP(q,state.level,state),
                rewards=facts and facts.rewards,lowValue=lowValue,
                regionMap=map and map>0 and map or nil,
                revisitLevel=later and math.max(q.requiredLevel or 0,q.questLevel-2) or nil,
                stages={},stagesComplete=false,actions={{kind=kind,questId=id,title=title,
                    text=active and "按任务日志继续完成目标。" or "前往任务发布者，查看并接取任务。"}}}
            local choice=choices[#choices]
            -- Keep a nearby next-level pickup without resolving its objectives or routing it yet.
            if later and not active and not lowValue and choice.revisitLevel==state.level+1 and
                state.position and map==state.position.map and not (facts and facts.hidden) and
                not (A.Supplies and A.Supplies.AcceptIssue(state)) then
                local point,issue=data:Target(q,state)
                if point and not issue and point.map==map then
                    choice.pickupAction={kind="accept",questId=id,title=title,position=point,
                        text=point.startItemId and ("使用「"..point.label.."」接取任务。") or "先接取，稍后一起做。"}
                end
            end
            return
        end
        local position,unavailable,pickupItem=data:Target(q,state)
        local areaId,objectiveIndex
        if not position and data.UnmappedTargetArea then areaId,objectiveIndex=data:UnmappedTargetArea(q,state) end
        local instance=A.Dungeon and A.Dungeon.TaskInstance and A.Dungeon.TaskInstance(position,state,data,areaId) or
            A.Dungeon and A.Dungeon.TaskPvP and A.Dungeon.TaskPvP(position,state,data,areaId)
        local held=pickupItem and pickupItem.held
        local currentInstance=state.inInstance and (held or instance and instance.instanceId==state.instanceId) or false
        local action={kind=kind,questId=id,title=active and active.title or q.title,position=position,
            areaId=areaId,objectiveIndex=position and position.objectiveIndex or objectiveIndex,
            text=({accept="前往任务发布者，查看并接取任务。",objective="按任务日志继续完成目标。",turnin="目标已完成，前往任务交付者。"})[kind]}
        if pickupItem then
            action.text=pickupItem.text
            action.startItemId=held and pickupItem.id or nil
        elseif kind=="accept" and position and position.startItemId then
            action.text="使用「"..position.label.."」接取任务。"
        end
        if kind=="objective" and data.DeliveryOnly and data:DeliveryOnly(q,state) then
            action.text="前往任务交付者对话，按游戏提示完成任务。"
        end
        if position and position.travelHint then action.text=position.travelHint end
        local choice={id="task:"..id,kind="task",questId=id,title=action.title,actions={action},
            status=kind,level=q.questLevel,unlock=unlocks[id],lowValue=lowValue,
            requireCheck=not active and (unavailable or not position and not instance and not held) or nil,
            distance=position and A.Navigation and A.Navigation.Distance and A.Navigation:Distance(state.position,position,true)}
        if state.inInstance then choice.currentInstance=currentInstance end
        -- Equivalent follow-ups can be offered by different machines in the same room.
        local objects=not active and q.startedBy and q.startedBy[2]
        if objects and #objects==1 and q.exclusiveTo and data.QuestContact then
            for _,parent in ipairs(q.preQuestSingle or {}) do
                if state.completed[parent] then
                    local contact=data:QuestContact(parent,"finishedBy")
                    if contact and contact.entityKind=="object" and contact.entityId==objects[1] then action.sameMachine=true;break end
                end
            end
        end
        if A.TaskGuide then
            choice.stages,choice.stagesComplete=A.TaskGuide.Stages(q,state,data,action)
            local localAction=A.Dungeon and A.Dungeon.OrderTaskObjectives and A.Dungeon.OrderTaskObjectives(choice.stages,state,data)
            if localAction then
                action=localAction;choice.actions[1]=action
                instance=A.Dungeon.TaskInstance(action.position,state,data,action.areaId) or
                    A.Dungeon.TaskPvP and A.Dungeon.TaskPvP(action.position,state,data,action.areaId)
                if state.inInstance then choice.currentInstance=instance and instance.instanceId==state.instanceId or false end
                choice.distance=action.position and A.Navigation and A.Navigation.Distance and A.Navigation:Distance(state.position,action.position,true)
            end
            choice.remainingXP=A.TaskGuide.XP(q,state.level,state)
            if choice.remainingXP then choice.forecast=A.Progression.Advance(state,choice.remainingXP) end
        end
        if kind=="accept" and A.Supplies then choice.acceptBlocked=A.Supplies.AcceptIssue(state) end
        local facts=q.taskFacts or not active and data.CacheQuest and data:CacheQuest(q,state)
        if facts then
            choice.rewards=facts.rewards
            if not active then
                local offers=position and position.entityKind=="npc" and state.questOffers and state.questOffers[position.entityId]
                choice.requireCheck=choice.requireCheck or facts.hidden and not (offers and offers[id])
            end
        end
        if choice.requireCheck then
            choice.stagesComplete=false
            action.text=pickupItem and pickupItem.text or "向任务发布者查看此任务。"
        end
        if A.TaskGuide then
            if not choice.lowValue and (not automatic or kind=="turnin" or choice.unlock or
                (q.questLevel or state.level)<=state.level+2) then
                choice.timing=A.TaskGuide.Timing(state.position,choice,state,A.Navigation)
                if not choice.unlock then choice.lowValue=A.TaskGuide.LowValue(q,state,data,choice) end
            end
        end
        if A.Dungeon and A.Dungeon.TaskEntryIssue then
            choice.entryBlocked=A.Dungeon.TaskEntryIssue(choice,state,data,options)
        end
        if not active and instance and not currentInstance and id~=state.locked and
            not state.preparingQuest and not state.taskBatch then
            choice.entryBlocked=choice.entryBlocked or "任务在副本内接取，可在副本页安排。"
        end
        if A.Gear and A.Gear.TaskBenefits then A.Gear.TaskBenefits(choice,q,state,data) end
        choices[#choices+1]=choice
    end
    if not onlySelected then
        for id in pairs(state.quests) do add(id) end
        if state.locked then add(state.locked) end
    end
    for _,id in ipairs(ids) do
        add(id)
        if thread and not isMain and clock()>=deadline then coroutine.yield();deadline=clock()+1 end
    end
    local nearbyRate
    for _,choice in ipairs(choices) do
        local seconds=choice.timing and choice.timing.seconds
        local point=choice.actions[1].position
        if not choice.lowValue and not choice.unlock and not choice.acceptBlocked and not choice.entryBlocked and
            not choice.requireCheck and choice.status~="turnin" and (choice.level or 0)<=state.level+2 and
            point and state.position and point.map==state.position.map and seconds and seconds>=60 and seconds<300 and
            choice.remainingXP and choice.remainingXP>0 then
            local rate=A.TaskGuide.MovementRate(seconds,choice.remainingXP)
            nearbyRate=math.max(nearbyRate or 0,rate)
        end
    end
    for _,choice in ipairs(choices) do
        if nearbyRate and not choice.lowValue and not choice.unlock then
            choice.lowValue=A.TaskGuide.LowValue(data:GetQuest(choice.questId),state,data,choice,nearbyRate)
        end
    end
    -- Keep a detour only when every remaining stop fits an already accepted, worthwhile trip.
    local anchors={}
    for _,choice in ipairs(choices) do
        if state.quests[choice.questId] and choice.status=="objective" and not choice.lowValue and
            not choice.entryBlocked and choice.timing and choice.timing.seconds then anchors[#anchors+1]=choice end
    end
    local unknownXP={}
    for _,choice in ipairs(choices) do
        if choice.lowValue and choice.lowValue.distant and not choice.lowValue.obsolete then
            for _,anchor in ipairs(anchors) do
                local cursor,extra=0,0
                for _,stage in ipairs(choice.stages) do
                    local found
                    for i=cursor,#anchor.stages do
                        local point=i==0 and state.position or anchor.stages[i].position
                        local distance=stage.position and point and A.Navigation:Distance(stage.position,point,true)
                        if distance and distance<=140 then
                            cursor=i;extra=extra+2*distance/(state.runSpeed or 7);found=true;break
                        end
                    end
                    if not found then extra=math.huge;break end
                end
                if extra<=60 then choice.lowValue=nil;break end
            end
        end
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
        local am,bm=a.actions[1].sameMachine,b.actions[1].sameMachine
        if am~=bm then return am==true end
        return a.questId<b.questId
    end)
    return choices
end

function P.TaskOrder(state,choices,data)
    local pending,order,optional={},{},{}
    for _,choice in ipairs(choices) do
        choice.executionTiming=nil;choice.executionAction=nil
        local pickupHere=choice.currentInstance and choice.status=="accept" and not
            (choice.acceptBlocked or choice.requireCheck or choice.entryBlocked)
        if not choice.lowValue and not choice.revisitLevel and (state.quests[choice.questId] or choice.questId==state.locked or pickupHere) then
            if choice.entryBlocked and choice.questId~=state.locked then optional[#optional+1]=choice
            else pending[#pending+1]=choice end
        end
    end
    if #pending==0 then
        for _,choice in ipairs(choices) do if not choice.lowValue then order[#order+1]=choice end end
        if A.TaskQueue then
            local joint,queue=A.TaskQueue.Solve(order,state,A.Navigation,data)
            if joint then return joint,queue end
        end
        return order
    end
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
                distances[index]=A.Navigation and A.Navigation.Distance and A.Navigation:Distance(origin,pos,true)
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

-- Compare one visit per region: pickups, nearby work, then grouped hand-ins.
function P.TaskRegions(state,plan,data)
    local regions,byMap={},{}
    local automatic=state.position and not (state.locked or state.taskBatch or state.gearTarget or state.inInstance)
    for _,c in ipairs(plan and plan.taskChoices or {}) do
        local q=data:GetQuest(c.questId)
        local level=c.level or q and q.questLevel or state.level
        local point=c.actions and c.actions[1] and c.actions[1].position
        for _,stage in ipairs(c.stages or {}) do
            if stage.kind=="objective" and stage.position then point=stage.position;break end
        end
        local map=point and point.map or c.regionMap
        if map and not c.lowValue and not c.entryBlocked and not c.requireCheck and
            not (q and (q.requiredSkill or q.requiredRanks)) then
            local r=byMap[map]
            if not r then
                local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
                r={map=map,title=info and info.name or "区域 #"..map,choices={},pickups={},handins={},revisit={},
                    xp=0,unknownXP=0,active=0,work=0,
                    current=state.position and state.position.map==map}
                byMap[map]=r;regions[#regions+1]=r
            end
            if c.status~="turnin" and level>state.level+2 then
                local entry={choice=c,level=math.max(q and q.requiredLevel or 0,level-2)}
                r.revisit[#r.revisit+1]=entry
                if automatic then c.revisitLevel=entry.level end
            elseif not c.acceptBlocked then
                r.choices[#r.choices+1]=c
                if c.status=="objective" then r.active=r.active+1 end
            end
        end
    end
    local current=state.position and byMap[state.position.map]
    local ready={}
    for _,c in ipairs(current and current.choices or {}) do
        if c.status=="turnin" then ready[#ready+1]=c end
    end
    for _,r in ipairs(regions) do
        local priced,known,unknownActive={},false,false
        for _,c in ipairs(r.choices) do
            unknownActive=unknownActive or state.quests[c.questId] and c.remainingXP==nil
            if c.stagesComplete and c.timing and c.timing.seconds~=nil then
                priced[c.questId]=true
                known=known or c.remainingXP~=nil
            end
        end
        local available={}
        for _,c in ipairs(r.choices) do
            -- Unknown rewards remain visible, but do not dilute a priced pickup batch.
            if state.quests[c.questId] or priced[c.questId] and (not known or c.remainingXP~=nil) then
                available[#available+1]=c
            end
        end
        if next(priced) then r.choices=available end
        table.sort(r.revisit,function(a,b)
            if a.level~=b.level then return a.level<b.level end
            return a.choice.questId<b.choice.questId
        end)
        local batch={}
        if not r.current then for _,c in ipairs(ready) do batch[#batch+1]=copy(c) end end
        local prefix=#batch
        for _,c in ipairs(r.choices) do batch[#batch+1]=copy(c) end
        if #r.choices>0 and A.TaskQueue then
            if r.active>0 and prefix==0 and not unknownActive then
                r.order,r.queue=P.TaskOrder(state,batch,data)
            else r.order,r.queue=A.TaskQueue.Solve(batch,state,A.Navigation,data,prefix) end
        end
        local routed={}
        if r.queue then
            r.travelSeconds=r.queue.seconds
            for _,step in ipairs(r.queue.steps) do routed[step.choice.questId]=true end
        else
            -- Keep tasks with incomplete routes available through the existing fallback.
            r.order=r.choices
        end
        local members={};for _,c in ipairs(r.choices) do members[c.questId]=true end
        r.choices={}
        r.xp,r.unknownXP,r.work,r.active=0,0,0,0
        local reward,knownRewards=0,0
        for _,c in ipairs(r.order or {}) do
            if members[c.questId] then
                r.choices[#r.choices+1]=c
                r.xp=r.xp+(c.remainingXP or 0)
                if c.remainingXP==nil then r.unknownXP=r.unknownXP+1 end
                if c.status~="turnin" then r.work=r.work+1 end
                if c.status=="objective" then r.active=r.active+1 end
                if c.status=="accept" then r.pickups[#r.pickups+1]=c end
                r.handins[#r.handins+1]=c
            end
        end
        for _,c in ipairs(batch) do
            if routed[c.questId] and c.remainingXP~=nil then
                reward=reward+c.remainingXP;knownRewards=knownRewards+1
            end
        end
        r.first=r.choices[1]
        local point=r.first and (r.first.executionAction or r.first.actions[1]).position
        if point and A.Flights then
            local routes=A.Flights.Routes(state.position,point,state,A.Navigation)
            r.seconds=routes and routes[1] and routes[1].seconds
        elseif point and A.Travel then r.seconds=A.Travel.Walk(state.position,point,state,A.Navigation) end
        if r.queue and r.queue.xpKnown then reward=r.queue.xp end
        r.rate=knownRewards>0 and r.travelSeconds and A.TaskGuide.MovementRate(r.travelSeconds,reward) or nil
    end
    table.sort(regions,function(a,b)
        if (a.first~=nil)~=(b.first~=nil) then return a.first~=nil end
        if (a.rate~=nil)~=(b.rate~=nil) then return a.rate~=nil end
        if a.rate and b.rate and a.rate~=b.rate then return a.rate>b.rate end
        if a.current~=b.current then return a.current end
        local at,bt=a.travelSeconds or a.seconds or math.huge,b.travelSeconds or b.seconds or math.huge
        if at~=bt then return at<bt end
        return a.map<b.map
    end)
    if not automatic then return regions end
    local best,nextRegion
    for _,r in ipairs(regions) do
        if r.work>0 and r.seconds~=nil then
            best=best or r
            if not r.current then nextRegion=nextRegion or r end
        end
    end
    local selected=best or current and current.work>0 and current
    -- Keep local accepted work only while its batch reward is within the existing 10% tolerance.
    if current and current.active>0 and current.rate and best and best.rate and current.rate>=best.rate*0.9 then
        selected=current
    end
    local visit={current=current,destination=selected and not selected.current and selected or nextRegion,
        choices=selected and selected.order or {},order=selected and selected.order,queue=selected and selected.queue,
        handins={},revisit=current and current.revisit or {}}
    if #ready>0 and selected~=current then
        visit.handins=ready
        if not visit.queue then visit.choices=ready;visit.order=nil end
    elseif selected and selected.current then visit.handins=selected.handins end
    if not selected and #ready==0 then
        -- Keep tasks with incomplete location data available through the existing fallback.
        for _,c in ipairs(plan.taskChoices or {}) do
            if not c.lowValue and not c.revisitLevel and not c.entryBlocked and not c.acceptBlocked then
                visit.choices[#visit.choices+1]=c
            end
        end
    end
    if not current and not selected then return regions end
    return regions,visit
end

function P.Build(state, data, options)
    state=copy(state);state.objectiveTargets={}
    -- Reuse immutable travel geometry within this snapshot; discard it after the build.
    state.travelCache={walks={},flights={},routes={}}
    if state.level >= 60 then return { revision = state.revision, complete = true } end
    local gearSource=state.gearTarget and A.Gear.GetSource and A.Gear.GetSource(state.gearTarget,data,state)
    if type(state.gearTarget)=="string" and (state.gearTarget:match("^reward:") or state.gearTarget:match("^drop:")) and not gearSource then
        local reason="所选装备来源暂不可用；可恢复升级目标。"
        return {revision=state.revision,taskChoices={},selectionBlocked=reason,
            fallback={kind="selectionBlocked",title="装备目标暂不可用",text=reason}}
    end
    if gearSource and gearSource.reference and gearSource.kind=="quest" then state=copy(state);state.locked=gearSource.questId end
    local preparation,preparationReason
    if state.locked and A.Chains and A.Chains.Preparation then
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
    local result={revision=state.revision,preparingQuest=preparation,origin=state.position and {map=state.position.map}}
    result.taskChoices=batchChoices or P.TaskChoices(state,data,ids,nil,options)
    if state.position and A.Flights and A.Flights.UnlockCandidates then
        result.flightUnlocks=A.Flights.UnlockCandidates(state,{[state.position.map]=true},A.Navigation)
    end
    local preferred=not batch and A.Gear.PreferTask and A.Gear.PreferTask(result.taskChoices,state,options)
    if preferred then
        for index,choice in ipairs(result.taskChoices) do if choice==preferred then table.remove(result.taskChoices,index);break end end
        table.insert(result.taskChoices,1,preferred);result.preferenceApplied=true
    end
    result.taskBatch=batch
    if not state.inInstance then result.regions,result.regionPlan=P.TaskRegions(state,result,data) end
    local choices=batch and A.Dungeon.TaskBatchStage(result.taskChoices,state,data) or
        result.regionPlan and result.regionPlan.choices or result.taskChoices
    result.taskPool=result.regionPlan and choices or nil
    if batch and batch.returning then
        result.unverified=true
        result.fallback={kind="dungeonLeave",title="离开"..batch.title,text="任务已交齐，离开副本后继续练级。"}
        return result
    end
    if gearSource and gearSource.reference and gearSource.kind=="dungeon" then
        A.Gear.PlanDungeonTarget(result,gearSource,state,data)
    end
    if A.Supplies and (not result.best or state.serviceStop and
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
        if result.regionPlan and result.regionPlan.queue then
            result.taskOrder,result.taskQueue=result.regionPlan.order,result.regionPlan.queue
        else result.taskOrder,result.taskQueue=P.TaskOrder(state,choices,data) end
    end
    if not result.best and not result.maintenance and not result.serviceStop and not result.gearPlan then
        -- Reference quests use straight-line travel estimates.
        result.unverified = true
        if result.regionPlan and result.regionPlan.queue then
            result.taskOrder,result.taskQueue=result.regionPlan.order,result.regionPlan.queue
        else result.taskOrder,result.taskQueue=P.TaskOrder(state,choices,data) end
        if result.regionPlan then
            local handins={}
            for _,c in ipairs(result.taskOrder or {}) do
                local last=c.stages and c.stages[#c.stages]
                if last and last.position and state.position and last.position.map==state.position.map then
                    handins[#handins+1]=c
                end
            end
            result.regionPlan.handins=handins
        end
        local automatic={}
        for _,choice in ipairs(result.taskOrder) do automatic[#automatic+1]=choice end
        for _,choice in ipairs(choices) do automatic[#automatic+1]=choice end
        local deliveryGroups={}
        if A.TaskGuide then local groups;groups,deliveryGroups=A.TaskGuide.DeliveryGroups(result.taskPool or result.taskChoices,state,result.taskOrder) end
        local entryBlocked
        local itemBlockedQuests={}
        for _,choice in ipairs(automatic) do
            local group=deliveryGroups[choice.questId]
            local waiting=not state.locked and group and not group.splitDelivery and group.ready<#group.choices and
                (choice.executionAction or choice.actions[1]).kind=="turnin"
            local itemBlocked=itemBlockedQuests[choice.questId] or A.TaskGuide and A.TaskGuide.ItemGainBlocked(choice.executionAction or choice.actions[1],state)
            if itemBlocked then result.itemLimitIssue=true;itemBlockedQuests[choice.questId]=true end
            if not itemBlocked and not waiting and not choice.lowValue and not choice.revisitLevel and not choice.acceptBlocked and (not state.locked or choice.questId==state.locked) and (not choice.requireCheck or state.locked==choice.questId) then
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
                    if flight then result.travelActions=flight.actions;result.referenceFlight=flight
                    elseif not journey and A.Flights and A.Flights.MissingCrossing then
                        result.fallback=A.Flights.MissingCrossing(approach,state,A.Navigation) or approach
                    end
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
                result.fallback={kind="taskReview",title="当前剩余任务收益偏低",text="在任务面板查看跳过建议，或选择任务手动继续。"}
                break
            end
        end
    end
    if not result.best and not result.fallback then
        for _,choice in ipairs(result.taskChoices) do
            if choice.revisitLevel then
                result.fallback={kind="taskReview",title="这些任务留待回访",text="在任务面板查看建议等级，或选择任务手动继续。"}
                break
            end
        end
    end
    if batch and not result.best and not result.fallback then
        result.fallback={kind="selectionBlocked",title=batch.title.."任务等待处理",
            text=(batch.blocked[1] or "当前任务尚无可执行目标").."；可在副本页查看任务条件或结束安排。"}
    end
    if A.Dungeon.SuggestTaskBatch then
        local suggested,choices=A.Dungeon.SuggestTaskBatch(state,data,options)
        result.suggestedDungeon=result.suggestedDungeon or suggested
        result.dungeonChoices=choices
    end
    if A.Dungeon.TaskBatchWaitPlan then A.Dungeon.TaskBatchWaitPlan(result,state,data,options) end
    if A.Services then result.bindingChoices=A.Services.PlanBindings(result,state,data) end
    if A.Services then result.automaticService=A.Services.AutomaticBinding(result,state) end
    if (state.serviceStop or result.automaticService) and A.Services and not result.maintenance then
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
