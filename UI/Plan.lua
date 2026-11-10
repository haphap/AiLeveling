local _, A = ...
A.UI.Plan = {}
local UI=A.UI.Plan

function UI.Key(candidate)
    return candidate and tostring(candidate.id)
end

function UI.Rows(plan)
    local rows,seen={},{}
    local function add(candidate)
        if candidate and candidate.questId and A.UI.QuestStatus(A.state or {},candidate.questId,plan)=="已交付" then return end
        local key=UI.Key(candidate)
        if key and not seen[key] then rows[#rows+1]=candidate;seen[key]=true end
    end
    add(plan and plan.suggestedDungeon)
    for _,candidate in ipairs(plan and plan.dungeonChoices or {}) do add(candidate) end
    add(plan and plan.best)
    for _,candidate in ipairs(plan and plan.alternatives or {}) do add(candidate) end
    for _,candidate in ipairs(plan and plan.taskChoices or {}) do add(candidate) end
    return rows
end

function UI:Choose(candidate,revision)
    local ok,reason=A.Selection.CanChoose(candidate,revision)
    if not ok then return false,reason end
    if candidate.requiresAcceptance then
        if candidate.reference then return A.Dungeon:StartTaskBatch(candidate.dungeonId) end
        return A.Dungeon:Accept(candidate.dungeonId)
    end
    return A.Selection:Lock(candidate,revision)
end

local tones={accept="8cccff",objective="8cf2b8",turnin="ffd473",muted="b4c1cd"}
local verbs={accept="接取",objective="完成目标",turnin="交付"}
local function tint(color,text) return "|cff"..color..text.."|r" end
local function link(id,title) return "|Hquest:"..id..":0|h["..title.."]|h" end

function UI:Entries()
    local plan,state=A.plan or {},A.state or {}
    local entries,seen={},{}
    local queue=plan.taskQueue
    local fresh=not plan.revision or plan.revision==state.revision
    local function heading(title,detail)
        entries[#entries+1]={title=title,detail=detail,heading=true}
    end
    local function task(choice,stage,number)
        local id=choice.questId
        local status=A.UI.QuestStatus(state,id,plan)
        if status=="已交付" then return end
        local active=(state.quests or {})[id]
        local kind=stage and stage.kind or (status=="未接取" and "accept" or status=="可交付" and "turnin" or "objective")
        local color=tones[status=="未接取" and "accept" or status=="可交付" and "turnin" or "objective"]
        local deferred=(state.skipped or {})[id] or (state.chainDeferred or {})[id]
        local title=active and active.title or choice.title or ("任务 #"..id)
        local detail
        if kind=="objective" then
            detail=stage and stage.text
            for _,objective in ipairs(active and active.objectives or {}) do
                if not detail and not objective.finished and objective.text then detail=objective.text;break end
            end
        end
        local action=stage or choice.executionAction or (choice.actions or {})[1]
        local point=action and (action.recipient or action.position)
        detail=detail or point and point.entityName
        if not detail and kind=="turnin" then
            local last=choice.stages and choice.stages[#choice.stages]
            local recipient=last and (last.recipient or last.position)
            detail=recipient and recipient.entityName
        end
        if choice.lowValue then detail=choice.lowValue.suggestion
        elseif choice.acceptBlocked then detail=choice.acceptBlocked
        elseif choice.entryBlocked then detail=choice.entryBlocked end
        local timing=choice.executionTiming or choice.timing
        local metrics={}
        if choice.remainingXP then metrics[#metrics+1]=A.UI:Icon("xp",14).." "..tint(tones.turnin,string.format("%.0f",choice.remainingXP)) end
        if timing and timing.seconds then
            local seconds=math.ceil(timing.seconds)
            metrics[#metrics+1]=tint(tones.muted,string.format("路程 %d分%02d秒",math.floor(seconds/60),seconds%60))
        end
        entries[#entries+1]={title=(number and tint(tones.muted,string.format("%02d  ",number)) or "")..tint(color,link(id,title)),detail=detail,
            status=tint(deferred and tones.muted or color,deferred and "已暂缓" or status),
            icon=tones[kind] and kind or "objective",metrics=table.concat(metrics,"  "),choice=choice}
        seen[id]=true
    end
    if not fresh then heading("正在更新行程")
    else
        local count=queue and queue.taskCount or #(plan.taskOrder or {})
        heading("本次行程 · "..count.." 项任务",queue and queue.xpKnown and (A.UI:Icon("xp",16).." "..tint(tones.turnin,string.format("交付经验 %.0f",queue.xp))) or nil)
        for i,step in ipairs(queue and queue.steps or {}) do task(step.choice,step.stage,i) end
        if not queue or not queue.steps or #queue.steps==0 then
            for i,choice in ipairs(plan.taskOrder or {}) do task(choice,nil,i) end
        end
    end
    local groups=A.TaskGuide and A.TaskGuide.DeliveryGroups(plan.taskChoices,state,plan.taskOrder) or {}
    for _,group in ipairs(groups) do
        heading(string.format("%s · %s · 已完成 %d/%d",group.splitDelivery and "分批交付" or "集中交付",group.title,group.ready,#group.choices),
            group.splitDelivery and "先交已备齐任务" or group.ready==#group.choices and "现在一起交" or "做完同组剩余任务再一起交")
    end
    local other=false
    for _,choice in ipairs(plan.taskChoices or {}) do
        if not seen[choice.questId] and (state.quests or {})[choice.questId] then
            if not other then heading("其他已接任务");other=true end
            task(choice)
        end
    end
    local missing={}
    for id in pairs(state.quests or {}) do if not seen[id] then missing[#missing+1]=id end end
    table.sort(missing)
    for _,id in ipairs(missing) do
        if not other then heading("其他已接任务");other=true end
        task({id="task:"..id,questId=id,kind="task",title=state.quests[id].title,actions={}})
    end
    local candidate=self.preview
    if candidate and candidate.questId and not seen[candidate.questId] and A.UI.QuestStatus(state,candidate.questId,plan)~="已交付" then
        task(candidate)
        local selected=table.remove(entries)
        table.insert(entries,1,selected);table.insert(entries,1,{title="选中任务",heading=true})
    elseif candidate and candidate.kind~="task" then
        local detail=candidate.requiresAcceptance and "接受后开始副本行程" or "本轮副本行程进行中"
        if candidate.requiresAcceptance and (candidate.remainingXP or candidate.xp) then detail=detail..string.format(" · 经验 %.0f",candidate.remainingXP or candidate.xp) end
        if candidate.reference then detail=string.format("%d 项任务 · 安排整组任务后开始",candidate.rewards.count)..(candidate.remainingXP and string.format(" · 经验 %.0f",candidate.remainingXP) or "") end
        heading(candidate.title,detail)
    end
    if A.char.paused then heading("引导已暂停") end
    if A.Navigation.manual then heading("正在导航到手动目的地") end
    local message=self.message or plan.selectionBlocked or self.blocked
    if message and not plan.complete then heading(message) end
    if not candidate and #entries==1 then
        heading(plan.complete and "升级目标已完成" or plan.sessionActive and "副本行程进行中 · 在副本页查看" or "当前暂无推荐任务")
    end
    return entries
end

function UI:Lines(candidate)
    local plan=A.plan or {}
    candidate=candidate or self.preview
    if not candidate or candidate.questId and A.UI.QuestStatus(A.state or {},candidate.questId,plan)=="已交付" then return {} end
    local lines={candidate.title or "任务详情"}
    if candidate.kind=="task" then
        local status=A.UI.QuestStatus(A.state,candidate.questId,plan)
        lines[#lines+1]="["..status.."] "..(status=="未接取" and (candidate.acceptBlocked or "先向任务发布者接取，再推进目标。") or
            (status=="可交付" and "目标已完成，前往交付。" or "继续任务日志中的目标。"))
        if candidate.level then lines[#lines+1]="任务等级："..candidate.level end
        local action=candidate.executionAction or (candidate.actions or {})[1]
        if action and not candidate.acceptBlocked then lines[#lines+1]=action.text end
        if plan.referenceFlight and plan.fallback and plan.fallback.questId==candidate.questId then
            lines[#lines+1]="当前飞行接续："..plan.referenceFlight.actions[1].text
        end
        for _,objective in ipairs((A.state.quests[candidate.questId] or {}).objectives or {}) do
            if objective.text then lines[#lines+1]=(objective.finished and "[已完成] " or "[进行中] ")..objective.text end
        end
        if candidate.lowValue then
            lines[#lines+1]=candidate.lowValue.suggestion.."："..candidate.lowValue.reason
            lines[#lines+1]="点击执行可继续此任务；在任务日志中可放弃。"
        end
        if candidate.entryBlocked then lines[#lines+1]=candidate.entryBlocked end
        if candidate.remainingXP then lines[#lines+1]=string.format("交付经验：%.0f",candidate.remainingXP) end
        if candidate.forecast and not candidate.forecast.uncertain then
            if candidate.forecast.level>=60 then lines[#lines+1]="交付后达到 60 级"
            elseif candidate.forecast.maxXP then
                lines[#lines+1]=string.format("交付后：%d 级，进度 %.0f / %.0f",candidate.forecast.level,candidate.forecast.xp,candidate.forecast.maxXP)
            else lines[#lines+1]=string.format("交付后：%d 级",candidate.forecast.level) end
        end
        if candidate.groupReference and candidate.groupReference>1 then lines[#lines+1]="建议人数："..candidate.groupReference end
        if candidate.rewards then
            local reward=candidate.rewards
            local function items(rows,label)
                for _,item in ipairs(rows or {}) do
                    local name=C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item.id)
                    local value=(candidate.gearSources or {})["reward:"..candidate.questId..":"..item.id]
                    local upgrade=value and (value.upgrade.provisional and "" or string.format(" · 属性评分%s %+.1f",value.upgrade.delta>0 and "提升" or "变化",value.upgrade.delta)) or ""
                    lines[#lines+1]=label..(name or ("物品 #"..item.id)).." ×"..item.count..upgrade
                    for _,note in ipairs(value and value.upgrade.notes or {}) do lines[#lines+1]=note end
                end
            end
            items(reward.items,"任务奖励：");items(reward.choices,"可选奖励：")
        end
        if candidate.stages then
            lines[#lines+1]="剩余任务步骤："
            for index,stage in ipairs(candidate.stages) do
                local names={accept="接取",objective="目标",turnin="交付"}
                lines[#lines+1]=string.format("%d. [%s] %s%s",index,names[stage.kind] or stage.kind,stage.text or stage.title or candidate.title,
                    stage.need and (" · 要求 "..stage.need) or "")
                if stage.areaId then
                    local instance=A.Dungeon and A.Dungeon.TaskInstance and A.Dungeon.TaskInstance(nil,A.state,A.Data,stage.areaId)
                    local name=instance and instance.title or C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(stage.areaId)
                    if name then lines[#lines+1]="目的地："..name end
                end
            end
        end
        local timing=candidate.executionTiming or candidate.timing
        if timing and timing.seconds then
            if timing.flightCount and timing.flightCount>0 then
                for _,leg in ipairs(timing.travelPlan.legs) do
                    if leg.kind=="flight" then
                        local names=A.state.taxiNames or {}
                        local from=names[leg.fromTaxi] or A.FlightData.nodes[leg.fromTaxi].name
                        local to=names[leg.toTaxi] or A.FlightData.nodes[leg.toTaxi].name
                        lines[#lines+1]=string.format("飞行：%s → %s · %.1f 分钟",from,to,leg.flightSeconds/60)
                    end
                end
            end
            if timing.hearthCount and timing.hearthCount>0 then
                lines[#lines+1]="使用炉石返回。"
            end
        end
        return lines
    end
    lines[#lines+1]=candidate.requiresAcceptance and "接受后开始副本行程" or "本轮副本行程进行中"
    return lines
end
