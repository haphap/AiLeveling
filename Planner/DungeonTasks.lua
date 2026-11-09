local _,A=...
local D=A.Dungeon

local function catalogFor(state)
    local catalog=A.DungeonCatalog
    if catalog and state.clientVersion==catalog.version and tostring(state.clientBuild)==catalog.build then return catalog end
end

local function pvpFor(state)
    local catalog=A.PvPCatalog
    if catalog and state.clientVersion==catalog.version and tostring(state.clientBuild)==catalog.build then return catalog.entries end
end

function D.TaskPvP(position,state,data,areaId)
    local entries=pvpFor(state)
    if not entries then return end
    local area=position and position.sourceAreaId or areaId
    for _,entry in pairs(entries) do
        for _,id in ipairs(entry.areas) do if id==area then return entry end end
    end
    local map,seen=position and position.map,{}
    while map and map>0 and not seen[map] do
        seen[map]=true
        for _,entry in pairs(entries) do
            for _,id in ipairs(entry.maps) do if id==map then return entry end end
        end
        local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        map=info and info.parentMapID
    end
end

-- Resolve the actual map or an unambiguous source area, never the quest category.
function D.TaskInstance(position,state,data,areaId)
    local catalog=catalogFor(state)
    if not catalog or not data.maps then return end
    local hbd=A.Navigation and A.Navigation.hbd
    if position and hbd and hbd.GetWorldCoordinatesFromZone then
        local _,_,mapId=hbd:GetWorldCoordinatesFromZone(position.x,position.y,position.map)
        if mapId then
            for _,d in pairs(catalog.entries) do if d.instanceId==mapId then return d end end
        end
    end
    local sourceArea=position and position.sourceAreaId or not position and areaId
    if sourceArea or not position then
        if not sourceArea then return end
        local instance
        for _,d in pairs(catalog.entries) do
            for _,area in ipairs(d.areas or {}) do
                if area==sourceArea then
                    if instance and instance~=d then return end
                    instance=d
                end
            end
        end
        return instance
    end
    local map,seen,instance=position.map,{},nil
    while map and map>0 and not seen[map] do
        seen[map]=true
        -- Some dungeon areas use their outdoor entrance map; that map alone cannot identify the instance.
        for _,d in pairs(catalog.entries) do
            for _,entry in ipairs(d.entrances or {}) do if data.maps[entry[1]]==map then return end end
        end
        for _,d in pairs(catalog.entries) do
            for _,area in ipairs(d.areas or {}) do
                if data.maps[area]==map then
                    if instance and instance~=d then return end
                    instance=d
                end
            end
        end
        if instance then break end
        local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        map=info and info.parentMapID
    end
    return instance
end

-- Finish objectives in the current instance/outdoors before crossing its boundary.
function D.OrderTaskObjectives(stages,state,data)
    local first=stages[1]
    if not first or first.kind~="objective" or not catalogFor(state) then return end
    -- An unassociated native waypoint may describe a prerequisite to the logged objectives.
    if first.position and first.position.label=="客户端任务目标" and not first.objectiveIndex then return end
    local nearby,remaining={},{}
    local hasInstance=false
    for _,stage in ipairs(stages) do
        local instance=stage.kind=="objective" and (D.TaskInstance(stage.position,state,data,stage.areaId) or D.TaskPvP(stage.position,state,data,stage.areaId))
        hasInstance=hasInstance or not not instance
        local map=stage.position and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(stage.position.map)
        local here=stage.kind=="objective" and (state.inInstance and instance and instance.instanceId==state.instanceId or
            not state.inInstance and not instance and map and (map.mapType==2 or map.mapType==3))
        local target=here and nearby or remaining
        target[#target+1]=stage
    end
    if not hasInstance or #nearby==0 then return end
    for _,stage in ipairs(remaining) do nearby[#nearby+1]=stage end
    local changed=false
    for i,stage in ipairs(nearby) do if stages[i]~=stage then changed=true;break end end
    if not changed then return end
    for i,stage in ipairs(nearby) do stages[i]=stage end
    return stages[1]
end

function D.TaskApproach(action,state,data)
    if not action then return action end
    local pvp=D.TaskPvP(action.position,state,data,action.areaId)
    if pvp then
        if state.inInstance and state.instanceId==pvp.instanceId then return action end
        return {kind="pvpEnter",questId=action.questId,title=action.title,
            text=(state.inInstance and "离开当前实例后，" or "").."通过游戏战场界面或战场军官排队进入「"..pvp.title.."」，进入后继续任务。"}
    end
    local currentPvP=state.inInstance and pvpFor(state) and pvpFor(state)[state.instanceId]
    if currentPvP and action.position then
        return {kind="pvpLeave",questId=action.questId,title=action.title,
            text="离开「"..currentPvP.title.."」后，"..(action.kind=="turnin" and "前往任务交付者交付任务。" or "继续野外任务。")}
    end
    if not catalogFor(state) then return action end
    local instance=D.TaskInstance(action.position,state,data,action.areaId)
    local info=action.position and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(action.position.map)
    if not instance and state.inInstance and info and (info.mapType==2 or info.mapType==3) then
        local destination=action.position.entityName or info.name or "任务目的地"
        return {kind="dungeonLeave",questId=action.questId,title=action.title,
            text="离开当前副本后，前往"..destination..(action.kind=="turnin" and "交付任务。" or "继续任务。")}
    end
    if not instance then return action end
    if state.inInstance and state.instanceId==instance.instanceId then
        if action.position then return action end
        local inside={};for k,v in pairs(action) do inside[k]=v end
        inside.text="在"..instance.title.."内，"..(action.text or "按任务日志继续任务。")
        return inside
    end
    if state.inInstance then
        return {kind="dungeonLeave",questId=action.questId,title=action.title,
            text="目标位于"..instance.title.."，先离开当前副本，再前往入口。"}
    end
    if state.instanceEntryError then
        return {kind="dungeonBlocked",questId=action.questId,title=action.title,
            text=state.instanceEntryError.."；可在副本页重新检查。"}
    end
    local nearest,best,fastest,bestSeconds
    for _,entry in ipairs(instance.entrances or {}) do
        local entryMap=data.maps[entry[1]]
        if entryMap and entryMap>0 then
            local point={map=entryMap,x=entry[2]/100,y=entry[3]/100,label=instance.title.."入口"}
            local distance=A.Navigation and A.Navigation:Distance(state.position,point)
            if not nearest or distance and (not best or distance<best) then nearest,best=point,distance end
            if #instance.entrances>1 and A.Flights and A.Flights.Routes then
                for _,route in ipairs(A.Flights.Routes(state.position,point,state,A.Navigation) or {}) do
                    if not bestSeconds or route.seconds<bestSeconds then fastest,bestSeconds=point,route.seconds end
                end
            end
        end
    end
    nearest=fastest or nearest
    if not nearest and instance.entryArea and data.maps[instance.entryArea] then
        local map=data.maps[instance.entryArea]
        local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        if info then
            return {kind="dungeonEnter",questId=action.questId,title=action.title,
                position={map=map,x=0.5,y=0.5,approximate=true,label=info.name or instance.title},text=instance.entryHint}
        end
    end
    if not nearest then
        if action.position then return action end
        local guide={};for k,v in pairs(action) do guide[k]=v end
        guide.text="前往"..instance.title.."入口，进入副本后继续任务。"
        return guide
    end
    return {kind="dungeonEnter",questId=action.questId,title=action.title,position=nearest,
        text="前往"..instance.title.."入口，进入副本后继续任务。"}
end

function D.TaskEntryIssue(choice,state,data,options)
    if state.locked~=choice.questId and not state.preparingQuest and not state.taskBatch then
        for _,stage in ipairs(choice.stages or choice.actions) do
            local pvp=D.TaskPvP(stage.position,state,data,stage.areaId)
            if pvp and not (state.inInstance and state.instanceId==pvp.instanceId) then
                return "任务需要进入「"..pvp.title.."」；可手动选择后排队进入。"
            end
        end
    end
    if state.instanceEntryError then
        local approach=D.TaskApproach(choice.actions[1],state,data)
        if approach.kind=="dungeonBlocked" then return approach.text end
    end
    if not options or options.dungeons~=false or state.locked==choice.questId or state.preparingQuest or
        state.taskBatch or choice.currentInstance then return end
    -- Check the remaining journey, so an outdoor giver cannot bypass the preference.
    for _,stage in ipairs(choice.stages or choice.actions) do
        local instance=D.TaskInstance(stage.position,state,data,stage.areaId)
        if instance and not (state.inInstance and state.instanceId==instance.instanceId) then
            return "已关闭副本建议；可手动选择此任务继续。"
        end
    end
end

function D.Catalog(state,content)
    local entries,instances={},{}
    for id,d in pairs(content.dungeons) do entries[id]=d;instances[d.instanceId]=true end
    local catalog=catalogFor(state)
    if catalog then
        for id,d in pairs(catalog.entries) do if not instances[d.instanceId] then entries[id]=d end end
    end
    return entries
end

function D.Tasks(d,state,data)
    local refs={}
    if d.reference then
        for id,kind in pairs(d.quests[state.faction] or {}) do refs[id]=kind end
    else
        for _,action in ipairs(d.actions or {}) do if action.questId then refs[action.questId]="inside" end end
    end
    if state.taskBatch and state.taskBatch.id==d.id then
        for id in pairs(state.taskBatch.baselines) do refs[id]=refs[id] or "selected" end
    end
    for id,active in pairs(state.quests) do
        if not refs[id] then
            local q=data:GetQuest(id) or {id=id,title=active.title,questLevel=active.level}
            local position=data:Target(q,state)
            local instance=D.TaskInstance(position,state,data)
            if instance and instance.instanceId==d.instanceId then refs[id]="inside" end
        end
    end
    local rows={}
    for id,relation in pairs(refs) do
        local active=state.quests[id]
        local q=data:GetQuest(id,state) or active and {id=id,title=active.title,questLevel=active.level}
        if q and (active or A.Eligibility.InMask(q.requiredRaces,state.raceMask)==true and
            A.Eligibility.InMask(q.requiredClasses,state.classMask)==true) then
            local status=A.State.Status(state,id)
            local allowed,reason=A.Eligibility.Check(q,state,data)
            local group=status=="ready" and 1 or status=="active" and 2 or
                status=="turnedIn" and not q.repeatable and 5 or allowed and 3 or 4
            local point=allowed and data:Target(q,state)
            local areaId
            if allowed and not point and data.UnmappedTargetArea then
                local area=data:UnmappedTargetArea(q,state)
                if D.TaskInstance(nil,state,data,area) then areaId=area end
            end
            local preparation=not allowed and group~=5 and A.Chains and A.Chains.Preparation and A.Chains.Preparation(id,data,state)
            local recipient
            if active then
                recipient=data:Target(q,{position=state.position,faction=state.faction,completed=state.completed,quests={[id]={ready=true}}})
                if data.Recipient then recipient=data:Recipient(q,recipient) end
            end
            local key=recipient and recipient.entityId and (recipient.entityKind..":"..recipient.entityId)
            local rewards={}
            if group~=5 and A.Gear and A.Gear.TaskBenefits then A.Gear.TaskBenefits(rewards,q,state,data) end
            rows[#rows+1]={id=id,title=q.title,group=group,allowed=allowed,reason=reason,position=point,areaId=areaId,
                xp=group~=5 and A.TaskGuide and A.TaskGuide.XP(q,state.level,state) or nil,
                gear=rewards.gear,gearSources=rewards.gearSources,
                requireCheck=not active and q.taskFacts and q.taskFacts.hidden or nil,
                lowValue=group~=5 and A.TaskGuide and A.TaskGuide.LowValue(q,state,data) or nil,
                relation=relation,recipient=key,recipientName=recipient and recipient.entityName,
                status=group==1 and "可交付" or group==2 and "已接取" or group==3 and "未接取" or group==5 and "已交付" or "未接取",
                questLevel=q.questLevel,preparation=preparation and #preparation>0 and preparation or nil}
        end
    end
    table.sort(rows,function(a,b)
        if a.group~=b.group then return a.group<b.group end
        if (a.recipient or "")~=(b.recipient or "") then return (a.recipient or "")<(b.recipient or "") end
        return a.id<b.id
    end)
    return rows
end

function D.CanContinueTask(row)
    return row~=nil and (row.allowed and (row.position~=nil or row.areaId~=nil) or row.preparation~=nil)
end

-- Report task rewards separately from dungeon kills and future prerequisite rewards.
function D.TaskRewards(rows,baselines,choices)
    local result={count=0,xp=0,unknownXP=0,ready=0,active=0,prepare=0,blocked=0,excluded=0,upgrades=0}
    local seen,byId={},{}
    for _,choice in ipairs(choices or {}) do byId[choice.questId]=choice end
    for _,row in ipairs(rows) do
        if not seen[row.id] and row.group~=5 and (not baselines or baselines[row.id]~=nil) then
            seen[row.id]=true
            local choice=byId[row.id]
            if row.lowValue or choice and choice.lowValue then result.excluded=result.excluded+1
            elseif not row.requireCheck and D.CanContinueTask(row) then
                result.count=result.count+1
                if row.xp==nil then result.unknownXP=result.unknownXP+1 else result.xp=result.xp+row.xp end
                if row.group==1 then result.ready=result.ready+1
                elseif row.group==2 then result.active=result.active+1
                elseif row.preparation then result.prepare=result.prepare+1 end
                if row.gear then result.upgrades=result.upgrades+1 end
            else result.blocked=result.blocked+1 end
        end
    end
    return result
end

function D:ContinueTask(d,id)
    if not A.ready or A.refreshAt then return false,"任务状态正在更新" end
    for _,row in ipairs(D.Tasks(d,A.state,A.Data)) do
        if row.id==id then
            if not row.allowed and not row.preparation then return false,row.reason end
            if not D.CanContinueTask(row) then return false,"请先查看任务说明确认目的地" end
            local paused=A.char.paused;A.char.paused=false
            local ok,why=A.Selection:LockQuest(id)
            if not ok then A.char.paused=paused end
            return ok,why
        end
    end
    return false,"当前角色没有这项关联任务"
end


function D.ValidTaskBatch(batch)
    if type(batch)~="table" or (type(batch.id)~="string" and type(batch.id)~="number") or
        type(batch.baselines)~="table" or (batch.waiting~=nil and type(batch.waiting)~="boolean") or
        (batch.returning~=nil and type(batch.returning)~="boolean") then return false end
    if type(batch.id)=="string" and (#batch.id==0 or #batch.id>128) or
        type(batch.id)=="number" and (batch.id<=0 or batch.id>=math.huge or batch.id%1~=0) then return false end
    local count=0
    for id,n in pairs(batch.baselines) do
        if type(id)~="number" or id<=0 or id>=2147483648 or id%1~=0 or
            type(n)~="number" or n<0 or n>=math.huge or n%1~=0 then return false end
        count=count+1
        if count>512 then return false end
    end
    return count>0 or batch.returning==true
end

-- A sample covers this whole task trip, including preparation, travel and delivery.
-- It lives only for this login; reloading must not turn a partial trip into a full sample.
function D:UpdateTaskActivity(state)
    local sample=self.taskActivity
    if not sample then return end
    if sample.batch~=A.char.taskBatch or A.settings.learn==false then self.taskActivity=nil;return end
    local grouped=(state.groupSize or 1)>1
    if state.dead or UnitIsAFK("player") or A.char.paused or A.Navigation.manual or
        sample.grouped and not grouped then sample.valid=false end
    sample.grouped=sample.grouped or grouped
    if state.inInstance then
        if state.instanceId~=sample.instance or sample.difficulty and sample.difficulty~=state.difficulty then
            sample.valid=false
        elseif not sample.difficulty then
            sample.difficulty=state.difficulty
            sample.key=sample.key..":"..tostring(state.difficulty)
        end
    end
end

function D:FinishTaskActivity()
    local batch,sample=A.char.taskBatch,self.taskActivity
    self.lastTaskTrip={id=batch.id}
    if sample and sample.batch==batch and sample.valid and sample.difficulty and A.settings.learn~=false then
        local seconds=GetTime()-sample.started
        if seconds>0 then
            A.char.samples=A.char.samples or {}
            A.State.Observe(A.char.samples,sample.key,seconds/60)
            if A.char.samples[sample.key] then A.char.samples[sample.key].unit="minutes" end
            self.lastTaskTrip.seconds=seconds
        end
    end
    self.taskActivity=nil
end

function D:TaskActivityText(id)
    local sample=self.taskActivity
    if sample and sample.batch==A.char.taskBatch and sample.batch.id==id then
        local text=string.format("本次行程 %.1f 分钟",math.max(0,GetTime()-sample.started)/60)
        local previous=sample.difficulty and (A.char.samples or {})[sample.key]
        if previous then text=text..string.format(" · 同组历史平均 %.1f 分钟",previous.mean) end
        return text
    end
    local last=self.lastTaskTrip
    if last and last.id==id then
        return "任务已交齐，已恢复自动路线"..(last.seconds and string.format(" · 本次 %.1f 分钟",last.seconds/60) or "")
    end
end

function D:TaskBatchSnapshot(state)
    state.taskBatch=nil
    self:UpdateTaskActivity(state)
    local batch=A.char.taskBatch
    if not batch then return "" end
    if not D.ValidTaskBatch(batch) or A.char.locked or
        A.char.dungeon and A.char.dungeon.phase~="complete" then A.char.taskBatch=nil;return "" end
    local ids,baselines={},{}
    for id,n in pairs(batch.baselines) do
        local q=A.Data:GetQuest(id)
        local done=(A.char.turnIns[id] or 0)>n or
            (not state.quests[id] and state.completed[id] and q and not q.repeatable)
        if done then batch.baselines[id]=nil
        else ids[#ids+1]=id;baselines[id]=n end
    end
    if #ids==0 then
        if state.inInstance then batch.returning=true
        else self:FinishTaskActivity();A.char.taskBatch=nil;return "" end
    end
    table.sort(ids)
    if state.inInstance then batch.waiting=nil end
    state.taskBatch={id=batch.id,baselines=baselines,waiting=batch.waiting,returning=batch.returning}
    return "dungeonTasks:"..tostring(batch.id)..":"..tostring(batch.waiting)..":"..tostring(batch.returning)..":"..table.concat(ids,",")
end

function D:StartTaskBatch(id)
    if not A.ready or A.refreshAt then return false,"任务状态正在更新" end
    if A.Transport and A.Transport:InFlight() then return false,"落地后再安排任务" end
    if A.char.dungeon and A.char.dungeon.phase~="complete" then return false,"先结束当前副本行程" end
    local d=D.Catalog(A.state,A.Content)[id]
    if not d then return false,"当前构建没有这项副本目录" end
    local baselines={}
    for _,row in ipairs(D.Tasks(d,A.state,A.Data)) do
        if D.CanContinueTask(row) then baselines[row.id]=(A.char.turnIns or {})[row.id] or 0 end
    end
    if not next(baselines) then return false,"当前没有可准备的关联任务" end
    A.Selection:Clear()
    A.char.taskBatch={id=id,baselines=baselines}
    A.char.gearTarget,A.char.gearBaseline,A.char.serviceStop=nil,nil,nil
    A.char.paused=false;A.Navigation.manual=nil
    self.lastTaskTrip=nil
    if A.settings.learn~=false then
        local ids={};for questId in pairs(baselines) do ids[#ids+1]=questId end;table.sort(ids)
        self.taskActivity={batch=A.char.taskBatch,instance=d.instanceId,started=GetTime(),valid=not A.state.inInstance,
            key="dungeontrip:"..tostring(A.state.clientBuild)..":"..tostring(d.instanceId)..":"..table.concat(ids,",")}
    end
    A.State:Refresh(true)
    return true
end

function D:ToggleTaskBatchWait()
    if not A.ready or A.refreshAt then return false,"任务状态正在更新" end
    if not A.char.taskBatch then return false,"请先安排副本关联任务" end
    if A.state.inInstance or A.Transport and A.Transport:InFlight() then return false,"离开副本并落地后再切换" end
    A.char.taskBatch.waiting=not A.char.taskBatch.waiting or nil
    A.State:Refresh(true)
    return true
end

-- Waiting is an explicit choice; nearby outdoor objectives never join the dungeon's reward batch.
function D.TaskBatchWaitPlan(plan,state,data,options)
    local batch=state.taskBatch
    local entry=plan.fallback
    if not (batch and batch.waiting and entry and entry.kind=="dungeonEnter") or
        state.inInstance or state.dead or state.onTaxi or state.serviceStop then return end
    local ids={}
    for id,active in pairs(state.quests) do
        if not batch.baselines[id] and not active.ready then ids[#ids+1]=id end
    end
    table.sort(ids)
    local context={};for key,value in pairs(state) do context[key]=value end
    context.taskBatch=nil
    local wait=math.min(options.waitMinutes or 0,options.minutes or 0)*60
    local speed=state.runSpeed or 7
    local choices=A.Planner.TaskChoices(context,data,ids,true)
    local action
    for _,choice in ipairs(choices) do
        local step=(choice.stages or choice.actions)[1]
        local objective=(state.quests[choice.questId].objectives or {})[step.objectiveIndex]
        local kind=step.objectiveType or objective and objective.type
        if step.targetKind=="item" and step.need then step.itemGain=math.max(0,step.need-(step.have or 0)) end
        local map=step.position and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(step.position.map)
        local instance=D.TaskInstance(step.position,state,data,step.areaId) or D.TaskPvP(step.position,state,data,step.areaId)
        if step.kind=="objective" and (kind=="monster" or kind=="item") and not choice.lowValue and
            not choice.entryBlocked and not choice.requireCheck and not (A.TaskGuide and A.TaskGuide.ItemGainBlocked(step,state)) and map and (map.mapType==2 or map.mapType==3) and not instance and entry.position and speed>0 then
            local outward=A.Navigation:Distance(state.position,step.position)
            local back=A.Navigation:Distance(step.position,entry.position)
            if outward and back and (outward+back)/speed<=wait then action=step;break end
        end
    end
    plan.taskBatch.waiting=true
    plan.fallback=action or {kind="dungeonWait",title=plan.taskBatch.title,text="等待队伍；准备好后在副本页点击“队伍就绪”。"}
    plan.travelActions={plan.fallback}
    plan.referenceJourney,plan.referenceFlight=nil,nil
end

-- Expand only today's executable prerequisites; real turn-ins unlock the next frontier.
function D.TaskBatchChoices(state,data)
    local batch=state.taskBatch
    local d=D.Catalog(state,data.content)[batch.id]
    local info={id=batch.id,title=d and d.title or "所选副本",remaining=0,blocked={},returning=batch.returning}
    if batch.returning then return {},info end
    local ids,roots,seen={},{},{}
    local members={}
    local rows=d and D.Tasks(d,state,data) or {}
    for _,row in ipairs(rows) do members[row.id]=row end
    local selected={}
    for id in pairs(batch.baselines) do selected[#selected+1]=id end
    table.sort(selected)
    for _,id in ipairs(selected) do
        info.remaining=info.remaining+1
        local row=members[id]
        local frontier=row and (row.allowed and {id} or row.preparation) or {}
        if not frontier or #frontier==0 then info.blocked[#info.blocked+1]=row and row.reason or "任务目录暂不可用" end
        for _,nextId in ipairs(frontier or {}) do
            if not seen[nextId] then seen[nextId]=true;ids[#ids+1]=nextId end
            if nextId~=id and (not roots[nextId] or id<roots[nextId].id) then roots[nextId]={id=id,title=row.title} end
        end
    end
    table.sort(ids)
    local context={};for k,v in pairs(state) do context[k]=v end
    context.preparingQuest=true
    local choices=A.Planner.TaskChoices(context,data,ids,true)
    for _,choice in ipairs(choices) do
        choice.preparingQuest=roots[choice.questId]
        choice.dungeonPreparation=members[choice.questId] and members[choice.questId].relation=="preparation"
    end
    info.rewards=D.TaskRewards(rows,batch.baselines,choices)
    info.journey=d and D.TaskJourney(d,choices,state,data) or nil
    return choices,info
end

-- Show the remaining executable frontier; future prerequisites unlock only after real turn-ins.
function D.TaskJourney(d,choices,state,data)
    local journey={before={},inside={},after={}}
    local here=state.inInstance and state.instanceId==d.instanceId
    for _,choice in ipairs(choices) do
        if not choice.lowValue and not choice.entryBlocked and not choice.requireCheck then
            local crossed=here
            for _,stage in ipairs(choice.stages or choice.actions) do
                local instance=D.TaskInstance(stage.position,state,data,stage.areaId)
                local inside=instance and instance.instanceId==d.instanceId
                local phase=inside and "inside" or (crossed or stage.kind=="turnin" and not
                    (choice.preparingQuest or choice.dungeonPreparation)) and "after" or "before"
                if inside then crossed=true end
                local step={action=stage,preparingQuest=choice.preparingQuest,
                    recipient=stage.kind=="turnin" and (stage.recipient or stage.position),
                    instance=instance and instance.title,blocked=stage.kind=="accept" and choice.acceptBlocked}
                journey[phase][#journey[phase]+1]=step
            end
        end
    end
    -- Return visits to the same actual recipient stay adjacent even across different quests.
    local function recipientKey(step)
        local p=step.recipient
        return p and p.entityKind and p.entityId and (p.entityKind..":"..p.entityId)
    end
    local grouped,turnins,used={},{},{}
    for _,step in ipairs(journey.after) do
        if step.action.kind=="turnin" then turnins[#turnins+1]=step else grouped[#grouped+1]=step end
    end
    for index,step in ipairs(turnins) do
        if not used[index] then
            grouped[#grouped+1]=step;used[index]=true
            local key=recipientKey(step)
            if key then
                for i=index+1,#turnins do
                    if not used[i] and recipientKey(turnins[i])==key then
                        grouped[#grouped+1]=turnins[i];used[i]=true
                    end
                end
            end
        end
    end
    journey.after=grouped
    if #journey.inside>0 and not here then
        local action=journey.inside[1].action
        journey.entry=D.TaskApproach(action,state,data)
    end
    journey.leave=(here or #journey.inside>0) and #journey.after>0
    return journey
end

function D.TaskBatchStage(choices,state,data)
    local preferred={}
    local groups={}
    if A.TaskGuide then local list;list,groups=A.TaskGuide.DeliveryGroups(choices,state) end
    for _,choice in ipairs(choices) do
        local position=choice.actions[1].position
        local instance=D.TaskInstance(position,state,data,choice.actions[1].areaId)
        local localStep=state.inInstance and choice.currentInstance or
            not state.inInstance and position and not instance
        local group=groups[choice.questId]
        local waiting=choice.status=="turnin" and group and group.ready<#group.choices
        if localStep and not waiting and not choice.lowValue and not choice.requireCheck and not choice.acceptBlocked then preferred[#preferred+1]=choice end
    end
    return #preferred>0 and preferred or choices
end
