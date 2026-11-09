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
    add(plan and plan.best)
    for _,candidate in ipairs(plan and plan.alternatives or {}) do add(candidate) end
    for _,candidate in ipairs(plan and plan.taskChoices or {}) do add(candidate) end
    return rows
end

function UI:Create(parent)
    self.frame=CreateFrame("Frame",nil,parent)
    self.frame:SetPoint("TOPLEFT",18,-94);self.frame:SetSize(570,72)
    self.previous=A.UI:Button(self.frame,"上一方案",88,function() self:Move(-1) end)
    self.previous:SetPoint("TOPLEFT")
    self.label=A.UI:Text(self.frame,12)
    self.label:SetPoint("TOPLEFT",100,-7);self.label:SetWidth(358)
    self.next=A.UI:Button(self.frame,"下一方案",88,function() self:Move(1) end)
    self.next:SetPoint("TOPLEFT",474,0)
    self.choose=A.UI:Button(self.frame,"选择任务",200,function()
        local ok,reason
        if self.preview and self.preview.requiresAcceptance then
            ok,reason=A.Selection.CanChoose(self.preview,self.revision)
            if ok then ok,reason=A.Dungeon:Accept(self.preview.dungeonId) end
        else ok,reason=A.Selection:Lock(self.preview,self.revision) end
        self.message=ok and (self.preview and self.preview.kind=="task" and "已锁定任务目标。" or "已保存所选行程。") or reason
        A.UI:SelectTab(1)
    end)
    self.choose:SetPoint("TOPLEFT",0,-36)
    self.automatic=A.UI:Button(self.frame,"恢复自动选择",170,function()
        local ok,reason=A.Selection:Automatic()
        self.message=ok and "已恢复自动选择。" or reason
        A.UI:SelectTab(1)
    end)
    self.automatic:SetPoint("TOPLEFT",210,-36)
    self.recalculate=A.UI:Button(self.frame,"重新计算",170,function()
        if A.ready then A:Replan() end
        A.UI:SelectTab(1)
    end)
    self.recalculate:SetPoint("TOPLEFT",390,-36)
    self.frame:Hide()
end

function UI:Move(delta)
    local rows=UI.Rows(A.plan)
    if #rows==0 then return end
    local index=1
    for i,c in ipairs(rows) do if UI.Key(c)==self.key then index=i;break end end
    self.key=UI.Key(rows[(index-1+delta)%#rows+1])
    self.message=nil
    A.UI.scroll:SetVerticalScroll(0)
    A.UI:SelectTab(1)
end

function UI:Refresh()
    local rows=UI.Rows(A.plan)
    local index=1
    for i,c in ipairs(rows) do if UI.Key(c)==self.key then index=i;break end end
    self.preview,self.revision=rows[index],A.plan and A.plan.revision
    self.key=UI.Key(self.preview)
    self.label:SetText(#rows>0 and string.format("%s %d / %d · %s",self.preview.kind=="task" and "任务" or "方案",index,#rows,
        self.preview==A.plan.best and "当前规划" or "备选预览") or "当前没有符合条件的任务或行程")
    self.previous:SetEnabled(#rows>1);self.next:SetEnabled(#rows>1)
    self.recalculate:SetEnabled(A.ready==true and not (A.Transport and A.Transport:InFlight()))
    local can,why=A.Selection.CanChoose(self.preview,self.revision)
    self.choose:SetEnabled(can==true)
    self.choose.text:SetText(self.preview and (self.preview.kind=="task" and (self.preview.acceptBlocked and "保留任务，空位后继续" or "导航并锁定此任务") or
        (self.preview.requiresAcceptance and "接受副本行程")) or "选择任务")
    self.blocked=not can and why or nil
    local origin,pos=A.plan and A.plan.origin,A.state.position
    if origin and pos and (origin.map~=pos.map or origin.node~=pos.node) and A.ready and A.jobs and not A.jobs.plan and
        not A.refreshAt and not (A.Transport and A.Transport:InFlight()) then A:Replan() end
end

local function ongoing(candidate)
    return candidate and candidate.kind=="dungeon" and not candidate.requiresAcceptance and (candidate.seconds or 0)<=0
end

local function breakdown(candidate)
    local walking,transport,execution=0,0,0
    for _,action in ipairs(candidate.actions or {}) do
        if action.kind=="move" then walking=walking+(action.travelSeconds or action.seconds or 0)
        elseif action.kind=="transit" then transport=transport+(action.travelSeconds or 0)
        else execution=execution+(action.seconds or 0) end
    end
    return walking,transport,execution,math.max(0,(candidate.seconds or 0)-walking-transport-execution)
end

function UI:Lines()
    local plan,candidate=A.plan or {},self.preview
    if candidate and candidate.questId and A.UI.QuestStatus(A.state or {},candidate.questId,plan)=="已交付" then candidate=nil end
    local lines={}
    local groups=A.TaskGuide and A.TaskGuide.DeliveryGroups(plan.taskChoices,A.state or {},plan.taskOrder) or {}
    for _,group in ipairs(groups) do
        lines[#lines+1]=string.format("%s · %s · 已完成 %d/%d",group.splitDelivery and "分批交付" or "集中交付",group.title,group.ready,#group.choices)
        lines[#lines+1]=group.splitDelivery and "物品持有上限限制，先交付已备齐任务，再继续收集。" or group.ready==#group.choices and "整组已完成，一次交付。" or "先完成同组剩余目标，再一起返回交付。"
        for _,choice in ipairs(group.choices) do
            lines[#lines+1]="  ["..A.UI.QuestStatus(A.state,choice.questId,plan).."] "..(choice.title or ("任务 #"..choice.questId))
        end
    end
    if plan.taskQueue and (not plan.revision or plan.revision==(A.state or {}).revision) then
        local queue=plan.taskQueue
        lines[#lines+1]=string.format("本次行程 · %d 项任务",queue.taskCount or #queue.steps)
        if queue.stagePlan then
            lines[#lines+1]="行动顺序："
            for i,step in ipairs(queue.steps) do
                local stage=step.stage
                local label=({accept="接取",objective="完成目标",turnin="交付"})[stage.kind] or stage.kind
                lines[#lines+1]=string.format("%02d  %s · %s%s",i,label,step.choice.title or ("任务 #"..step.choice.questId),
                    stage.kind=="objective" and stage.text and ("："..stage.text) or "")
            end
        end
        if queue.xpKnown then lines[#lines+1]=string.format("预计交付经验：%.0f",queue.xp) end
        if (queue.remaining or 0)>0 then lines[#lines+1]="另有 "..queue.remaining.." 项任务位置待确认，仍保留在建议列表。" end
        if (queue.optional or 0)>0 then lines[#lines+1]="另有 "..queue.optional.." 项任务暂未计入自动行程。" end
    end
    if A.char.paused then lines[#lines+1]="规划提示已暂停；执行所选行程会恢复提示。" end
    if A.Navigation.manual then lines[#lines+1]="当前导航到手动目的地；执行所选行程会解除手动导航。" end
    if A.char.locked then lines[#lines+1]="当前锁定任务 #"..A.char.locked.."。" end
    if plan.selectionBlocked then lines[#lines+1]="当前目标暂不可执行："..plan.selectionBlocked end
    if A.UI.TaskLines then
        for _,line in ipairs(A.UI:TaskLines()) do lines[#lines+1]=line end
    end
    if self.message then lines[#lines+1]=self.message end
    if self.blocked and not plan.complete then lines[#lines+1]=self.blocked end
    if not candidate then
        if plan.complete then lines[#lines+1]="已达到 60 级，本次升级规划目标已完成。"
        elseif plan.revision and plan.revision~=(A.state or {}).revision then lines[#lines+1]="正在更新行程。"
        elseif plan.sessionActive then lines[#lines+1]=plan.fallback and plan.fallback.text or "当前副本行程等待处理，可在副本页查看。"
        else lines[#lines+1]="当前暂无推荐任务。" end
        return lines
    end
    lines[#lines+1]=candidate.title
    if candidate.kind=="task" then
        local status=A.UI.QuestStatus(A.state,candidate.questId,plan)
        lines[#lines+1]="["..status.."] "..(status=="未接取" and (candidate.acceptBlocked or "先向任务发布者接取，再推进目标。") or
            (status=="可交付" and "目标已完成，前往交付。" or "继续任务日志中的目标。"))
        if candidate.level then lines[#lines+1]="任务等级："..candidate.level end
        local action=candidate.actions[1]
        if not candidate.acceptBlocked then lines[#lines+1]=action.text end
        if plan.referenceFlight and plan.fallback and plan.fallback.questId==candidate.questId then
            lines[#lines+1]="当前飞行接续："..plan.referenceFlight.actions[1].text
        end
        local pos=action.position
        if pos then
            local map=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(pos.map)
            lines[#lines+1]=string.format("%s · %.1f, %.1f",map and map.name or ("地图 #"..pos.map),pos.x*100,pos.y*100)
        else lines[#lines+1]="按下列任务目标继续。" end
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
                local p=stage.position
                lines[#lines+1]=string.format("%d. [%s] %s%s",index,names[stage.kind] or stage.kind,stage.text or stage.title,
                    stage.need and (" · 要求 "..stage.need) or "")
                if p then lines[#lines+1]=string.format("地图 #%d · %.1f, %.1f",p.map,p.x*100,p.y*100)
                elseif stage.areaId then
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
    if ongoing(candidate) then lines[#lines+1]="本轮副本行程进行中。"
    else
        lines[#lines+1]=string.format("预计 %.1f 分钟 · %.0f 经验 · %.0f 经验／小时",candidate.seconds/60,candidate.xp,candidate.rate*3600)
        local walk,transit,execute,other=breakdown(candidate)
        lines[#lines+1]=string.format("步行 %.1f 分钟；交通／等待 %.1f 分钟；执行／服务 %.1f 分钟；其他预留／未拆分 %.1f 分钟",walk/60,transit/60,execute/60,other/60)
    end
    local current=plan.best
    if current and current~=candidate and not ongoing(current) and not ongoing(candidate) then
        lines[#lines+1]=string.format("与当前规划方案相比：耗时 %+.1f 分钟；经验 %+.0f；经验率 %+.0f／小时",
            (candidate.seconds-current.seconds)/60,candidate.xp-current.xp,(candidate.rate-current.rate)*3600)
    end
    if candidate.resources then
        local r=candidate.resources
        if r.hearthReady then
            local seconds=math.max(0,r.hearthReady-(r.now or 0))
            lines[#lines+1]=seconds==0 and "行程结束时炉石可用" or string.format("行程结束时炉石仍冷却 %.1f 分钟",seconds/60)
        end
    end
    if candidate.forecast and not candidate.forecast.uncertain then
        lines[#lines+1]="交付后等级："..candidate.forecast.level
    end
    if candidate.gear then
        local g=candidate.gear
        lines[#lines+1]=string.format("装备评分提升 %+.1f；获得概率 %.0f%%—%.0f%%",g.upgrade.delta,g.chanceLow*100,g.chanceHigh*100)
    end
    if candidate.requiresAcceptance then lines[#lines+1]="此方案包含副本；点击接受后进入准备、等队与实际进入流程。" end
    lines[#lines+1]="完整行动预览："
    local names={move="移动",transit="交通",accept="接取",objective="目标",turnin="交付",service="服务",
        dungeonWait="等队",dungeonEnter="进入副本",dungeonRun="本轮副本",dungeonEnd="返程／结束"}
    for i,action in ipairs(candidate.actions or {}) do
        local duration=action.travelSeconds or action.seconds
        local node=action.node and A.Content.nodes[action.node]
        lines[#lines+1]=string.format("%d. [%s] %s%s%s",i,names[action.kind] or action.kind,
            action.title or (action.questId and ("任务 #"..action.questId)) or "继续当前阶段",
            node and node.label and (" · "..node.label) or "",duration and string.format(" · %.1f 分钟",duration/60) or "")
        if action.text then lines[#lines+1]=action.text end
    end
    if plan.gearTargetBlocked then lines[#lines+1]=plan.gearTargetBlocked end
    return lines
end
