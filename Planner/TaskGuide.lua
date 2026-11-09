local _,A=...
A.TaskGuide={}
local G=A.TaskGuide
local function cacheXP(state)
    local cache=A.TaskFacts and A.TaskFacts.cacheXP
    local version=state and state.clientVersion or A.clientVersion
    local build=state and state.clientBuild or A.build
    local interface=state and state.interface or A.interface
    if cache and version==cache.version and tostring(build)==cache.build and interface==cache.interface then return cache end
end
function G.Counts()
    local quests,rewards,xp=0,0,0
    local facts=A.TaskFacts and A.TaskFacts.quests or {}
    for _,fact in pairs(facts) do
        quests=quests+1
        if fact.rewards then rewards=rewards+1 end
        if fact.xp then xp=xp+1 end
    end
    local cache=cacheXP()
    for id,row in pairs(cache and cache.quests or {}) do
        if not facts[id] then quests=quests+1 end
        if row.xp and (not facts[id] or not facts[id].xp) then xp=xp+1 end
    end
    return quests,rewards,xp
end

local function copy(value)
    local result={};for key,item in pairs(value) do result[key]=item end;return result
end

function G.XP(q,level,state)
    if level>=60 then return end
    local active=state and state.quests and state.quests[q.id]
    if active and active.rewardXPLevel==level and active.rewardXP~=nil then return active.rewardXP end
    local facts=q.taskFacts
    local cache=cacheXP(state)
    if cache and cache.quests[q.id] then facts=cache.quests[q.id] end
    if facts and facts.xp and type(facts.level)=="number" and facts.level==q.questLevel then
        local value
        for _,change in ipairs(facts.xp) do if level>=change[1] then value=change[2] else break end end
        if value~=nil then return value end
    end
    if type(q.referenceXPLevel)=="number" and q.referenceXPLevel==q.questLevel and q.referenceXP~=nil then
        local factor=math.max(1,math.min(10,20+2*(q.referenceXPLevel-level)))
        local raw=math.floor(q.referenceXP*factor/10)
        local unit=raw>1000 and 50 or raw>500 and 25 or raw>100 and 10 or 5
        return math.floor((raw+unit/2)/unit)*unit
    end
end

-- Keep item requirements even when the native log says this quest alone is ready.
function G.ItemRequirements(q,state,data,reference)
    local active=(state.quests or {})[q.id]
    local descriptions,positions,identities,areas,complex
    if active then
        local context=copy(state);context.quests=copy(state.quests)
        local log=copy(active);log.objectives={};log.ready=false;context.quests[q.id]=log
        local hasItems=false
        for index,o in ipairs(active.objectives or {}) do
            log.objectives[index]=copy(o)
            if o.type=="item" or o.targetKind=="item" then log.objectives[index].finished=false;hasItems=true end
        end
        if not hasItems then return {} end
        descriptions=log.objectives
        identities=data.ObjectiveIdentities and data:ObjectiveIdentities(q,context) or {}
        positions={}
        for _,point in ipairs(data.ObjectiveTargets and data:ObjectiveTargets(q,context) or {}) do positions[point.objectiveIndex]=point end
        areas={}
        for index,identity in pairs(identities) do
            if identity.kind=="item" and not positions[index] and data.UnmappedTargetArea then
                areas[index]=data:UnmappedTargetArea(q,context,index)
            end
        end
    elseif reference then
        descriptions,positions,areas=reference.descriptions,reference.positions,reference.areas
    elseif data.ReferenceObjectiveTargets then
        descriptions,positions,complex,areas=data:ReferenceObjectiveTargets(q,state)
    end
    local result,byId={},{}
    for index,o in ipairs(descriptions or {}) do
        local identity=active and identities[index] or {kind=o.targetKind,id=o.targetId}
        if identity and identity.kind=="item" and type(o.numRequired)=="number" and o.numRequired>0 and o.numRequired%1==0 then
            local need=o.numRequired
            local old=byId[identity.id]
            if not old then
                local areaId=areas and areas[index]
                local point=positions[index]
                if not point and not areaId then
                    point=data.QuestAreaTarget and data:QuestAreaTarget(q,state) or data.AreaTarget and data:AreaTarget(q)
                end
                old={kind="objective",questId=q.id,title=q.title,text=o.text,position=point,areaId=areaId,
                    objectiveIndex=active and index or nil,expected=not active,targetKind="item",targetId=identity.id,
                    need=need,providedOnAccept=o.providedOnAccept}
                byId[identity.id]=old;result[#result+1]=old
            else old.need=math.max(old.need,need) end
        end
    end
    return result
end

function G.Stages(q,state,data,first)
    local active=state.quests[q.id]
    local deliveryOnly=data.DeliveryOnly and data:DeliveryOnly(q,state)
    local area=data.QuestAreaTarget and data:QuestAreaTarget(q,state) or data.AreaTarget and data:AreaTarget(q)
    local stages,complete,reference={},true,nil
    local function add(kind,position,text,index,expected,areaId)
        if not position and not areaId then position=area end
        local stage={kind=kind,questId=q.id,title=q.title,position=position,text=text,
            objectiveIndex=index,expected=expected,areaId=areaId}
        stages[#stages+1]=stage
        if not position then complete=false end
        return stage
    end
    local function reward(stage)
        stage.itemRequirements=G.ItemRequirements(q,state,data,reference)
        if data.Recipient then stage.recipient=data:Recipient(q,stage.position) end
        return stage
    end
    if active and active.ready then return {reward(copy(first))},first.position~=nil end
    if not active then stages[#stages+1]=copy(first);if not first.position then complete=false end end
    local added,described=0,false
    if active then
        local located={}
        local identities=data.ObjectiveIdentities and data:ObjectiveIdentities(q,state) or {}
        if data.ObjectiveTargets then
            for _,point in ipairs(data:ObjectiveTargets(q,state)) do located[point.objectiveIndex]=point end
        end
        local currentIndex=first.objectiveIndex
        if not currentIndex and first.position and first.position.label=="客户端任务目标" then
            local only,count=nil,0
            for index,o in ipairs(active.objectives or {}) do if not o.finished then only,count=index,count+1 end end
            if count==1 then currentIndex=only end
        end
        if not currentIndex and first.position and first.position.label=="客户端任务目标" then
            add("objective",first.position,first.text,nil,false);added=added+1
            if not area then complete=false end
        end
        local function objective(index,o)
            if not o or o.finished then return end
            local position=(index==currentIndex and first.position) or located[index]
            local areaId=not position and data.UnmappedTargetArea and data:UnmappedTargetArea(q,state,index)
            local stage=add("objective",position,o.text or "按任务日志完成目标",index,false,areaId)
            stage.have,stage.need=o.numFulfilled,o.numRequired
            local identity=identities[index]
            if identity then stage.targetKind,stage.targetId,stage.objectiveType=identity.kind,identity.id,identity.objectiveType end
            added=added+1
        end
        if currentIndex then objective(currentIndex,(active.objectives or {})[currentIndex]) end
        for index,o in ipairs(active.objectives or {}) do if index~=currentIndex then objective(index,o) end end
    elseif data.ReferenceObjectiveTargets then
        local descriptions,positions,complex,areas=data:ReferenceObjectiveTargets(q,state)
        reference={descriptions=descriptions,positions=positions,areas=areas}
        described=#descriptions>0
        for index,o in ipairs(descriptions) do
            if not o.finished and not o.providedOnAccept then
                local stage=add("objective",positions[index],o.text,nil,true,areas and areas[index])
                stage.targetKind,stage.targetId=o.targetKind,o.targetId
                stage.areaTriggerId=o.areaTriggerId
                stage.have,stage.need=o.numFulfilled,o.numRequired
                for _,fact in ipairs(q.taskFacts and q.taskFacts.objectives or {}) do
                    if not stage.need and fact.kind==o.targetKind and fact.id==o.targetId and (fact.count or 0)>0 then stage.need=fact.count;break end
                end
                added=added+1
            end
        end
        if complex then add("objective",nil,"接取后按日志核对额外的探索、技能或声望要求。",nil,true);added=added+1 end
    end
    if added==0 and not described and not (not active and deliveryOnly) then
        add("objective",active and first.position or nil,deliveryOnly and "前往任务交付者对话，按游戏提示完成任务。" or
            "按任务日志完成要求；完成后再交付。",first.objectiveIndex,not active,active and first.areaId)
    end
    local lookup={position=state.position,faction=state.faction,completed=state.completed,quests={[q.id]={ready=true}}}
    local finish=data:Target(q,lookup)
    local finishArea=not finish and data.UnmappedTargetArea and data:UnmappedTargetArea(q,lookup)
    reward(add("turnin",finish,"目标全部完成后，前往交付。",nil,true,finishArea))
    return stages,complete
end

-- Group by the actual recipient, never by the quest giver or just a shared coordinate.
function G.ItemLimit(id,state)
    local reference=A.ItemLimits
    if reference and (state.clientVersion or A.clientVersion)==reference.version and
        tostring(state.clientBuild or A.build)==reference.build and (state.interface or A.interface)==reference.interface then
        return reference.counts[id]
    end
end

function G.ItemGainBlocked(action,state,bags)
    bags=bags or state.bags or {}
    local gains={}
    for id,count in pairs(action.gainItems or {}) do gains[id]=count end
    if action.itemGain and action.itemGain>0 then gains[action.targetId]=(gains[action.targetId] or 0)+action.itemGain end
    for id,count in pairs(gains) do
        local limit=G.ItemLimit(id,state)
        if limit and (bags[id] or 0)+count>limit then return true end
    end
    return false
end

function G.DeliveryGroups(choices,state,planned,includeAccepts)
    local groups,byKey,byQuest={},{},{}
    local shortages={}
    for _,choice in ipairs(planned or choices or {}) do shortages[choice.questId]=choice.itemShortage end
    for _,choice in ipairs(choices or {}) do
        local id=choice.questId
        local active=(state.quests or {})[id]
        local last=choice.stages and choice.stages[#choice.stages]
        local p=last and last.kind=="turnin" and (last.recipient or last.position)
        local accepting=includeAccepts and choice.stages and choice.stages[1] and choice.stages[1].kind=="accept"
        if (active or accepting) and not choice.lowValue and not choice.entryBlocked and not (state.skipped or {})[id] and not (state.chainDeferred or {})[id] and
            p and p.entityKind and p.entityId then
            local key=p.entityKind..":"..p.entityId
            local group=byKey[key]
            if not group then
                group={key=key,title=p.entityName or ((p.entityKind=="npc" and "NPC #" or "对象 #")..p.entityId),choices={},ready=0,items={}}
                byKey[key]=group;groups[#groups+1]=group
            end
            group.choices[#group.choices+1]=choice
            for _,requirement in ipairs(last.itemRequirements or {}) do
                local item=requirement.targetId
                group.items[item]=(group.items[item] or 0)+requirement.need
                local limit=G.ItemLimit(item,state)
                if limit and group.items[item]>limit then group.splitDelivery=true end
            end
            if active and active.ready and not shortages[id] then group.ready=group.ready+1 end
            byQuest[id]=group
        end
    end
    local batches={}
    for _,group in ipairs(groups) do
        if #group.choices>1 then batches[#batches+1]=group
        else byQuest[group.choices[1].questId]=nil end
    end
    return batches,byQuest
end

-- Equal task execution costs cancel out when ordering the same tasks; compare movement only.
function G.Distance(origin,choice,navigation,state)
    if not choice.stagesComplete or not origin or not navigation then return end
    local geometric,seconds=0,0
    local position=origin
    for _,stage in ipairs(choice.stages or {}) do
        local target=stage.position
        if not target then return end
        local distance=navigation:Distance(position,target)
        if distance==nil then return end
        geometric=geometric+distance
        local time=A.Travel.Walk(position,target,state,navigation)
        if seconds and time then seconds=seconds+time else seconds=nil end
        position=target
    end
    return geometric,seconds
end

function G.Timing(origin,choice,state,navigation)
    local geometric,travel=G.Distance(origin,choice,navigation,state)
    local result={geometric=geometric,travel=travel,movementOnly=true}
    if choice.stagesComplete and A.Flights then
        result.travelRoutes=A.Flights.Itinerary(origin,choice.stages,state,navigation)
        result.travelPlan=result.travelRoutes and result.travelRoutes[1]
        local route=result.travelPlan
        travel=route and route.seconds or nil;result.travel=travel
        if route then
            result.travelLow,result.travelHigh=route.low,route.high
            result.flightCount=route.flights
            result.hearthReady,result.hearthCount=route.hearthReady,route.hearths
            result.initial,result.coarse=route.initial,route.coarse
        end
    else result.initial,result.coarse=travel and travel>0,travel and travel>0 end
    if travel and choice.stagesComplete and not state.dead and not state.onTaxi and not state.inInstance then
        result.seconds=travel
        result.low,result.high=result.travelLow or travel,result.travelHigh or travel
    end
    return result
end

-- This is reward per movement second, not XP per gameplay second.
function G.MovementRate(seconds,xp)
    if seconds==nil or xp==nil then return end
    if xp==0 then return 0 end
    return seconds==0 and math.huge or xp/seconds
end

function G.LowValue(q,state,data,choice)
    local active=state.quests[q.id]
    if state.locked==q.id or state.itinerary or active and active.ready then return end
    local rewards=q.taskFacts and q.taskFacts.rewards
    local chains=data.chainIndex
    if not active and q.repeatable and rewards and (rewards.spellCast or 0)>0 and
        (state.rewardAuras or {})[rewards.spellCast] and G.XP(q,state.level,state)==0 and
        #(rewards.items or {})==0 and #(rewards.choices or {})==0 and
        ((rewards.spell or 0)==0 or rewards.spell==rewards.spellCast) and
        chains and chains.nodes[q.id] and #(chains.outgoing[q.id] or {})==0 and
        not q.requiredSkill and (not q.requiredClasses or q.requiredClasses==0) and (q.requiredSpell or 0)==0 then
        return {summary="增益仍在生效",reason="相同增益仍在生效，先继续其他任务。",suggestion="稍后再领"}
    end
    if not active and q.repeatable and rewards and #(rewards.choices or {})==0 and
        data.DeliveryOnly and data:DeliveryOnly(q,state) then
        for _,item in ipairs(rewards.items or {}) do
            local limit=G.ItemLimit(item.id,state)
            if limit and (item.count or 0)>0 and ((state.bags or {})[item.id] or 0)>=limit then
                return {summary="道具已持有",reason="补领道具已在背包中，先继续其他任务。",suggestion="无需补领"}
            end
        end
    end
    if not q.questLevel or q.questLevel<=0 then return end
    local gap=state.level-q.questLevel
    local xp,base=G.XP(q,state.level,state),G.XP(q,q.questLevel,state)
    if not xp or not base or base<=0 then return end
    local obsolete=gap>=6 and xp<=base*0.25
    -- Count the whole remaining journey, including the return to the recipient.
    local travel=choice and choice.timing and choice.timing.seconds
    local lowXP=xp<=base*0.5 or type(state.maxXP)=="number" and state.maxXP>0 and xp<=state.maxXP*0.02
    local distant=gap>=3 and travel and travel>=300 and lowXP
    if not obsolete and not distant then return end
    local index=data.chainIndex
    if not index or not index.nodes[q.id] or #(index.incoming[q.id] or {})>0 or #(index.outgoing[q.id] or {})>0 then return end
    if q.requiredClasses and q.requiredClasses~=0 or q.requiredSkill or (q.requiredSpell or 0)>0 then return end
    local source=A.Gear and A.Gear.GetSource and A.Gear.GetSource(state.gearTarget,data) or
        (data.content and data.content.gearSources and data.content.gearSources[state.gearTarget])
    if source and source.questId==q.id then return end
    if not rewards or (rewards.spell or 0)>0 or (rewards.spellCast or 0)>0 then return end
    for _,list in ipairs({rewards.items or {},rewards.choices or {}}) do
        for _,entry in ipairs(list) do
            local id=entry.id
            if type(id)~="number" or id<=0 then return end
            local item=state.items and state.items[id]
            if not item and A.Items and C_Item and C_Item.GetItemInfo then item=A.Items:Read(id) end
            if not item or item.pending or item.equipLoc==nil then return end
            if item.equipLoc~="" then
                if not A.Gear or not state.equipment then return end
                local future=copy(item);future.futureCopy=true
                local upgrade=A.Gear.Upgrade(future,state)
                if not upgrade or upgrade.provisional or upgrade.delta>0 or #(upgrade.notes or {})>0 then return end
            end
        end
    end
    return {xp=xp,baseXP=base,distant=distant and true or nil,
        summary=distant and "路远收益低／无装备提升／无任务线" or "低经验／无装备提升／无任务线",
        reason=distant and "任务地点远、等级偏低、经验收益低；奖励装备无提升，未关联任务线。" or
            string.format("任务低于角色 %d 级，经验仅剩 %.0f%%；奖励装备无提升，未关联任务线。",gap,xp/base*100),
        suggestion=active and "建议放弃" or "建议跳过"}
end
