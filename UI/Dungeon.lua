local _, A = ...
A.UI.Dungeon = {}
local UI = A.UI.Dungeon

function UI:Create(parent)
    local frame = CreateFrame("Frame",nil,parent)
    frame:SetPoint("TOPLEFT",18,-94); frame:SetSize(570,214)
    self.frame = frame
    self.selector = A.UI:Button(frame,"选择副本",392,function()
        local ids = self:Ids()
        for index,id in ipairs(ids) do
            if id==self.selected then self.selected=ids[index%#ids+1]; break end
        end
        self.message=nil
        self:Refresh(); A.UI:SelectTab(4)
    end)
    self.selector:SetPoint("TOPLEFT")
    self.selector.text:SetWidth(380);self.selector.text:SetMaxLines(1)
    self.taskBatch=A.UI:Button(frame,"安排关联任务",160,function()
        local current=A.char.taskBatch
        local ok,why
        if current and current.id==self.selected then ok,why=A.Selection:Automatic()
        else ok,why=A.Dungeon:StartTaskBatch(self.selected) end
        self.message=not ok and why or nil
        self:Refresh();A.UI:SelectTab(4)
    end)
    self.taskBatch:SetPoint("TOPLEFT",400,0)
    local function control(label,column,event)
        local button = A.UI:Button(frame,label,106,function()
            local ok,reason
            if event=="accept" then ok,reason=A.Dungeon:Accept(self.selected)
            elseif event=="ready" and A.char.taskBatch and A.char.taskBatch.id==self.selected then
                ok,reason=A.Dungeon:ToggleTaskBatchWait()
            else ok,reason=A.Dungeon:Control(event) end
            self.message = ok and nil or reason
            self:Refresh(); A.UI:SelectTab(4)
        end)
        button:SetPoint("TOPLEFT",column*114,-36)
        return button
    end
    self.accept = control("接受行程",0,"accept")
    self.ready = control("队伍就绪",1,"ready")
    self.finish = control("本轮结束",2,"finish")
    self.again = control("再刷一轮",3,"again")
    self.stop = control("结束行程",4,"stop")
    self.confirmReset=A.UI:Button(frame,"确认已重置",170,function()
        local ok,reason=A.Instances:ConfirmReset(self.selected)
        self.message=ok and "已记录玩家确认；进入资格继续由客户端检查。" or reason
        self:Refresh();A.UI:SelectTab(4)
    end)
    self.confirmReset:SetPoint("TOPLEFT",0,-72)
    self.retry=A.UI:Button(frame,"重新检查",170,function()
        local ok,reason=A.Instances:Retry()
        self.message=not ok and reason or nil
        self:Refresh();A.UI:SelectTab(4)
    end)
    self.retry:SetPoint("TOPLEFT",180,-72)
    self.status = A.UI:Text(frame,12)
    self.status:SetPoint("TOPLEFT",0,-110); self.status:SetWidth(558); self.status:SetHeight(60)
    self.taskSelector=A.UI:Button(frame,"关联任务",320,function()
        local rows=self.tasks or {}
        if #rows>0 then self.taskIndex=(self.taskIndex or 1)%#rows+1 end
        self:Refresh();A.UI:SelectTab(4)
    end)
    self.taskSelector:SetPoint("TOPLEFT",0,-176)
    self.taskSelector.text:SetWidth(308);self.taskSelector.text:SetMaxLines(1)
    self.taskChain=A.UI:Button(frame,"查看任务链",108,function()
        local row=self.tasks and self.tasks[self.taskIndex or 1]
        if row then A.UI.Chains:Focus(row.id) end
    end)
    self.taskChain:SetPoint("TOPLEFT",328,-176)
    self.taskGo=A.UI:Button(frame,"继续此任务",116,function()
        local d=self.entries and self.entries[self.selected]
        local row=self.tasks and self.tasks[self.taskIndex or 1]
        if d and row then
            local ok,why=A.Dungeon:ContinueTask(d,row.id)
            self.message=ok and "已选择此任务" or why
            self:Refresh();A.UI:SelectTab(4)
        end
    end)
    self.taskGo:SetPoint("TOPLEFT",444,-176)
    frame:Hide()
end

function UI:Ids()
    local ids = {}
    self.entries=A.Dungeon.Catalog(A.state,A.Content)
    for id in pairs(self.entries) do ids[#ids+1]=id end
    table.sort(ids,function(a,b) return tostring(a)<tostring(b) end)
    return ids
end

function UI:Refresh()
    local ids = self:Ids()
    if not self.selected or not self.entries[self.selected] then self.selected=ids[1] end
    local d = self.selected and self.entries[self.selected]
    if self.taskDungeon~=self.selected then self.taskIndex,self.taskDungeon=1,self.selected end
    self.selector.text:SetText(d and ("当前查看："..d.title.."（点击切换）") or "当前构建没有副本任务目录")
    self.selector:SetEnabled(#ids>0)
    local candidate,reason
    if d and A.ready then
        if d.reference then reason="选择并准备关联任务。"
        else candidate,reason=A.Dungeon.Evaluate(d,A.state,A.settings,A.Data) end
    end
    self.tasks=d and A.ready and A.Dungeon.Tasks(d,A.state,A.Data) or {}
    self.taskIndex=math.max(1,math.min(self.taskIndex or 1,#self.tasks))
    local row=self.tasks[self.taskIndex]
    self.taskSelector.text:SetText(row and (self.taskIndex.."/"..#self.tasks.."  "..row.status.." · "..row.title) or "暂无适用的关联任务")
    self.taskSelector:SetEnabled(#self.tasks>1)
    self.taskChain:SetEnabled(row~=nil)
    self.taskGo.text:SetText(row and row.preparation and "准备前置任务" or "继续此任务")
    self.taskGo:SetEnabled(A.Dungeon.CanContinueTask(row) and not (A.char.dungeon and A.char.dungeon.phase~="complete"))
    local batch=A.char.taskBatch
    self.taskBatch.text:SetText(batch and batch.id==self.selected and "结束任务安排" or "安排关联任务")
    local preparable=false
    for _,task in ipairs(self.tasks) do if A.Dungeon.CanContinueTask(task) then preparable=true;break end end
    self.taskBatch:SetEnabled(A.ready and not A.refreshAt and d~=nil and
        (preparable or batch and batch.id==self.selected) and not (A.char.dungeon and A.char.dungeon.phase~="complete"))
    local session = A.char.dungeon
    local compact=d and d.reference and (not session or session.phase=="complete")
    for _,button in ipairs({self.accept,self.ready,self.finish,self.again,self.stop,self.confirmReset,self.retry}) do button:SetShown(not compact) end
    local entryError=not A.state.inInstance and A.state.instanceEntryError
    local retryRow=compact and entryError and 36 or 0
    local waitRow=compact and batch and batch.id==self.selected and not A.state.inInstance and 36 or 0
    self.retry:SetShown(not compact or not not entryError)
    self.retry:ClearAllPoints();self.retry:SetPoint("TOPLEFT",compact and 0 or 180,compact and -76 or -72)
    self.bodyTop=compact and 214+retryRow+waitRow or 314
    self.frame:SetHeight(compact and 114+retryRow+waitRow or 214)
    self.status:ClearAllPoints();self.status:SetPoint("TOPLEFT",0,compact and -36 or -110)
    self.status:SetHeight(compact and 32 or 60)
    for _,entry in ipairs({{self.taskSelector,0},{self.taskChain,328},{self.taskGo,444}}) do
        entry[1]:ClearAllPoints();entry[1]:SetPoint("TOPLEFT",entry[2],compact and -76-retryRow-waitRow or -176)
    end
    self.accept:SetEnabled(candidate~=nil and (not session or session.phase=="complete"))
    self.ready:SetShown(not compact or waitRow>0)
    self.ready:ClearAllPoints();self.ready:SetPoint("TOPLEFT",compact and 0 or 114,compact and -76-retryRow or -36)
    self.ready.text:SetText(waitRow>0 and (batch.waiting and "队伍就绪" or "等队做任务") or "队伍就绪")
    self.ready:SetEnabled(waitRow>0 and A.ready and not A.refreshAt or session~=nil and not session.settled and session.phase~="inside")
    self.finish:SetEnabled(session~=nil and session.entered==true and not session.settled)
    local again
    if session and session.settled and not A.state.inInstance and A.ready then
        local active=A.Content.dungeons[session.id]
        local options={}
        for key,value in pairs(A.settings) do options[key]=value end
        options.minutes=math.max(0,session.budget-session.elapsed)/60
        again=active and A.Dungeon.Evaluate(active,A.state,options,A.Data)
    end
    self.again:SetEnabled(again~=nil)
    self.stop:SetEnabled(session~=nil)
    local pending=d and A.state.pendingResets and A.state.pendingResets[d.instanceId]
    self.confirmReset:SetEnabled(A.ready and pending~=nil and not A.state.inInstance and
        (not session or session.settled or session.phase=="complete"))
    self.retry:SetEnabled(A.ready and not A.state.inInstance)
    local lines = {}
    if session and session.phase~="complete" then
        local active = A.Content.dungeons[session.id]
        lines[#lines+1] = (active and active.title or ("#"..session.id)).." · 第 "..session.round.." 轮 · "..(A.Dungeon.phases[session.phase] or "准备中")
        lines[#lines+1] = string.format("行程预算剩余 %.1f 分钟；再刷时重新计算收益与往返成本",math.max(0,session.budget-session.elapsed)/60)
    elseif batch and batch.id==self.selected then
        local count=0;for _ in pairs(batch.baselines) do count=count+1 end
        lines[#lines+1]=batch.returning and "任务已交齐，离开副本后继续练级。" or
            batch.waiting and "等队期间先完成准备，再做附近任务；队伍就绪后出发。" or
            "已安排 "..count.." 项任务，按当前进度接续准备、目标与交付。"
    elseif reason then lines[#lines+1]=reason
    else lines[#lines+1]="点击接受，开始副本行程。" end
    if entryError then lines={entryError}
    elseif self.message then lines[#lines+1]=self.message end
    self.status:SetText(table.concat(lines,"\n"))
end

function UI:RepeatText()
    local session=A.char.dungeon
    if not session or not session.settled or A.state.inInstance then return nil end
    local d=A.Content.dungeons[session.id]
    if not d then return "当前暂无再刷建议" end
    local options={}
    for key,value in pairs(A.settings) do options[key]=value end
    options.minutes=math.max(0,session.budget-session.elapsed)/60
    local candidate,reason=A.Dungeon.Evaluate(d,A.state,options,A.Data)
    if not candidate then return "再刷条件："..reason end
    local text=string.format("下一轮重新估计：%.1f 分钟 · %.0f 经验/小时",candidate.seconds/60,candidate.rate*3600)
    for _,alternative in ipairs(A.plan and A.plan.alternatives or {}) do
        if alternative.kind~="dungeon" and alternative.rate>candidate.rate then
            return text.."\n建议转回野外行程："..alternative.title.."，预计经验效率更高。"
        end
    end
    return text.."\n点击再刷，安排下一轮。"
end

function UI:Lines()
    local lines={}
    local selected=self.entries and self.entries[self.selected]
    if selected then
        local _,group=A.Dungeon.GroupStatus(selected,A.state)
        lines[#lines+1]=group
    end
    local encounter=A.Dungeon.EncounterProgress(self.entries and self.entries[self.selected],A.state)
    if encounter then lines[#lines+1]=encounter end
    local activity=A.Dungeon:TaskActivityText(self.selected)
    if activity then lines[#lines+1]=activity end
    local batch=A.char.taskBatch
    local current=batch and batch.id==self.selected
    local plan=current and A.plan
    local choices=plan and plan.revision==A.state.revision and plan.taskBatch and plan.taskBatch.id==self.selected and plan.taskChoices
    local journey=choices and plan.taskBatch.journey
    if journey then
        lines[#lines+1]="|cffffd36b本次任务安排|r"
        local function phase(title,steps)
            if #steps==0 then return end
            lines[#lines+1]="|cffffd36b"..title.."|r"
            for _,step in ipairs(steps) do
                local action=step.action
                local verb=action.kind=="accept" and "接取" or action.kind=="turnin" and "交付" or "完成"
                local active=A.state.quests[action.questId]
                local status=active and (active.ready and "可交付" or "已接") or "未接"
                local where=step.recipient and step.recipient.entityName or action.position and action.position.entityName or step.instance
                local text=status.." · "..verb.." · "..action.title..(where and (" — "..where) or "")
                if action.kind=="objective" and action.text then text=text.."\n    "..action.text end
                if step.preparingQuest then text=text.."\n    为「"..step.preparingQuest.title.."」准备前置，交付后接续。" end
                if step.blocked then text=text.."\n    "..step.blocked end
                lines[#lines+1]=text
            end
        end
        phase("出发前准备",journey.before)
        if journey.entry then lines[#lines+1]=journey.entry.text end
        phase("副本内任务",journey.inside)
        if journey.leave then lines[#lines+1]=#journey.inside>0 and "本内目标完成后离开副本，继续剩余目标与交付。" or "离开副本，继续剩余目标与交付。" end
        phase(journey.leave and "出本后接续与交付" or "剩余目标与交付",journey.after)
        lines[#lines+1]="|cffffd36b任务与奖励|r"
    end
    local rewards=A.Dungeon.TaskRewards(self.tasks or {},current and batch.baselines or nil,choices)
    if rewards.count>0 then
        lines[#lines+1]=string.format("%s %d 项 · 进行中 %d 项 · 可交付 %d 项",
            current and "本次有效任务" or "可准备任务",rewards.count,rewards.active,rewards.ready)
        if rewards.unknownXP==0 then lines[#lines+1]=string.format("交付经验：%d",rewards.xp) end
        if rewards.prepare>0 then lines[#lines+1]="其中 "..rewards.prepare.." 项需先完成前置。" end
        if rewards.upgrades>0 then lines[#lines+1]="其中 "..rewards.upgrades.." 项任务有装备提升。" end
    end
    if rewards.excluded>0 then lines[#lines+1]="另有 "..rewards.excluded.." 项低收益任务。" end
    local drops=selected and A.Gear.DungeonBenefits and A.Gear.DungeonBenefits(selected,A.state,A.Data) or {}
    if #drops>0 then
        lines[#lines+1]="|cffffd36b副本装备提升|r"
        for _,value in ipairs(drops) do
            lines[#lines+1]=string.format("%s · 属性评分 %+.1f\n    %s",value.item.link or value.item.name or ("物品 #"..value.item.id),
                value.upgrade.delta,value.source.title)
            for _,note in ipairs(value.upgrade.notes) do lines[#lines+1]="    "..note end
        end
        lines[#lines+1]="可在装备页选择获取目标。"
    end
    local headings={"可交付", "已接任务", "可接任务", "尚未满足条件", "已交付"}
    local group
    for i,row in ipairs(self.tasks or {}) do
        if group~=row.group then group=row.group;lines[#lines+1]="|cffffd36b"..headings[group].."|r" end
        local hint=row.relation=="preparation" and "入本准备" or row.relation=="alternative" and "部分目标有其他来源" or
            row.relation=="inside" and "副本目标" or "关联任务"
        local selected=A.char.taskBatch and A.char.taskBatch.id==self.selected and A.char.taskBatch.baselines[row.id]~=nil
        if selected then hint=hint.." · 已安排" end
        if row.lowValue then hint=hint.." · "..row.lowValue.suggestion end
        if row.xp then hint=hint.." · "..row.xp.." 经验" end
        local detail=row.requireCheck and "向任务发布者查看任务" or
            not row.allowed and row.group~=5 and row.reason or row.recipientName
        lines[#lines+1]=string.format("%s%02d  %s  ·  %s%s",i==self.taskIndex and "› " or "",i,row.title,hint,detail and ("\n     "..detail) or "")
        if row.gear then
            local reward=row.gear
            lines[#lines+1]=string.format("     装备提升：%s · 属性评分 %+.1f",reward.item.link or reward.item.name or ("物品 #"..reward.item.id),reward.upgrade.delta)
        end
    end
    if #lines==0 then lines[1]="当前角色暂无适用的关联任务。" end
    local text=self:RepeatText()
    if text then lines[#lines+1]=text end
    return lines
end
