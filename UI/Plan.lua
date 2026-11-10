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

function UI:Create(parent)
    self.frame=CreateFrame("Frame",nil,parent)
    self.frame:SetPoint("TOPLEFT",18,-94);self.frame:SetSize(570,72)
    self.previous=A.UI:Button(self.frame,"上一方案",88,function() self:Move(-1) end)
    self.previous:SetPoint("TOPLEFT")
    self.label=A.UI:Text(self.frame,12)
    self.label:SetPoint("TOPLEFT",100,-7);self.label:SetWidth(360)
    self.next=A.UI:Button(self.frame,"下一方案",88,function() self:Move(1) end)
    self.next:SetPoint("TOPLEFT",474,0)
    self.choose=A.UI:Button(self.frame,"选择任务",200,function()
        local ok,reason
        if self.preview and self.preview.requiresAcceptance then
            ok,reason=A.Selection.CanChoose(self.preview,self.revision)
            if ok then
                if self.preview.reference then ok,reason=A.Dungeon:StartTaskBatch(self.preview.dungeonId)
                else ok,reason=A.Dungeon:Accept(self.preview.dungeonId) end
            end
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

function UI:Render()
    if not self.content then
        self.content=CreateFrame("Frame",nil,A.UI.scrollChild)
        self.content:SetPoint("TOPLEFT");self.content:SetWidth(552)
        self.cards={}
    end
    self.content:Show();A.UI.detailText:Hide()
    for _,row in ipairs(self.cards) do row:Hide() end
    local y,scale=0,A.settings.fontScale or 1
    for i,entry in ipairs(self:Entries()) do
        local row=self.cards[i]
        if not row then
            row=CreateFrame("Frame",nil,self.content);row:SetWidth(552);row:EnableMouse(true);A.UI:Rounded(row,7)
            row:SetHyperlinksEnabled(true)
            row.title=A.UI:Text(row,16,{0.97,0.98,1});row.title:SetPoint("TOPLEFT",34,-8);row.title:SetWidth(398)
            row.status=A.UI:Text(row,12);row.status:SetPoint("TOPRIGHT",-4,-10);row.status:SetWidth(110);row.status:SetJustifyH("RIGHT")
            row.detail=A.UI:Text(row,13,{0.78,0.84,0.89});row.detail:SetWidth(250)
            row.metrics=A.UI:Text(row,13);row.metrics:SetWidth(248);row.metrics:SetJustifyH("RIGHT")
            row.icon=A.UI:Text(row,16);row.icon:SetPoint("TOPLEFT",0,-8)
            row.line=row:CreateTexture(nil,"BACKGROUND");row.line:SetColorTexture(0.6,0.7,0.8,0.12)
            row.line:SetPoint("BOTTOMLEFT");row.line:SetPoint("BOTTOMRIGHT");row.line:SetHeight(1)
            row:SetScript("OnHyperlinkClick",function(f,_,_,button)
                if button=="RightButton" then A.UI:TrackerMenu(f)
                else
                    self.key=UI.Key(f.candidate);self.message=nil
                    A.UI:QuestClick(f.questId,button)
                    A.UI:SelectTab(1)
                end
            end)
            row:SetScript("OnHyperlinkEnter",function(f)
                GameTooltip:SetOwner(f,"ANCHOR_RIGHT")
                GameTooltip:SetText(f.candidate.title or "任务详情")
                GameTooltip:AddLine(verbs[f.stepKind] or "任务",1,0.83,0.45)
                for n,line in ipairs(self:Lines(f.candidate)) do if n>1 then GameTooltip:AddLine(line,0.9,0.94,1,true) end end
                GameTooltip:AddLine("左键：任务详情  ·  右键：任务操作",1,0.83,0.45,true);GameTooltip:Show()
            end)
            row:SetScript("OnHyperlinkLeave",function() GameTooltip:Hide() end)
            row:SetScript("OnHide",function() GameTooltip:Hide() end)
            self.cards[i]=row
        end
        row.candidate,row.questId,row.revision=entry.choice,entry.choice and entry.choice.questId,A.plan and A.plan.revision
        row.stepKind=entry.icon
        row.deferred=row.questId and ((A.state.skipped or {})[row.questId] or (A.state.chainDeferred or {})[row.questId])
        local r,g,b=A.UI:Accent()
        row:SetBackdropColor(r*0.2,g*0.2,b*0.2,entry.choice and entry.choice==self.preview and 0.6 or 0)
        row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-y)
        row.title:ClearAllPoints();row.title:SetPoint("TOPLEFT",entry.heading and 0 or 34,-8)
        row.title:SetWidth(entry.heading and 552 or 424-100*scale)
        row.title:SetText(entry.title)
        if entry.heading then row.title:SetTextColor(A.UI:Accent()) else row.title:SetTextColor(0.97,0.98,1) end
        row.icon:SetText(entry.icon and A.UI:Icon(entry.icon,20) or "")
        row.status:SetText(entry.status or "")
        local top=math.max(row.title:GetStringHeight(),20*scale)+14
        row.detail:ClearAllPoints();row.detail:SetPoint("TOPLEFT",entry.heading and 0 or 34,-top)
        row.detail:SetWidth(entry.heading and 552 or 250);row.detail:SetMaxLines(entry.heading and 0 or 1);row.detail:SetText(entry.detail or "")
        row.metrics:ClearAllPoints();row.metrics:SetPoint("TOPRIGHT",-4,-top);row.metrics:SetText(entry.metrics or "")
        local bottom=math.max(entry.detail and row.detail:GetStringHeight() or 0,entry.metrics and entry.metrics~="" and row.metrics:GetStringHeight() or 0)
        row:SetHeight(top+bottom+12);row.line:SetShown(not entry.heading);row:Show()
        y=y+row:GetHeight()+4
    end
    self.content:SetHeight(y);A.UI.scrollChild:SetHeight(math.max(1,y))
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
