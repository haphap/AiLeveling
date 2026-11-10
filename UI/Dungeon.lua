local _, A = ...
A.UI.Dungeon = {}
local UI = A.UI.Dungeon
local statusColors={"|cfff2bd7a","|cff9cc9a6","|cffadc9d1","|cffc7b8a8","|cffc7b8a8"}

function UI:Create(parent)
    local frame = CreateFrame("Frame",nil,parent)
    frame:SetPoint("TOPLEFT",18,-94); frame:SetSize(744,448)
    self.frame = frame
    local side=A.UI:Panel(nil,frame,254,464)
    side:SetPoint("TOPLEFT",500,8);side:SetBackdropColor(0.18,0.14,0.12,0.70)
    self.selector = A.UI:Button(frame,"选择副本",474,function()
        local ids = self:Ids()
        MenuUtil.CreateContextMenu(self.selector,function(_,menu)
            menu:SetScrollMode(320)
            for _,id in ipairs(ids) do
                local d=self.entries[id]
                local label=d.title
                if d.minLevel and d.maxLevel then label=label..string.format("  ·  %d—%d级",d.minLevel,d.maxLevel) end
                menu:CreateRadio(label,function() return self.selected==id end,function()
                    self.selected=id;self.message=nil
                    A.UI.scroll:SetVerticalScroll(0)
                    self:Refresh();A.UI:SelectTab(4)
                end)
            end
        end)
    end,14)
    self.selector:SetPoint("TOPLEFT")
    self.selector.text:SetWidth(462);self.selector.text:SetMaxLines(1)
    self.taskBatch=A.UI:Button(frame,"安排关联任务",160,function()
        local current=A.char.taskBatch
        local ok,why
        if current and current.id==self.selected then ok,why=A.Selection:Automatic()
        else ok,why=A.Dungeon:StartTaskBatch(self.selected) end
        self.message=not ok and why or nil
        self:Refresh();A.UI:SelectTab(4)
    end,14)
    local function control(label,event)
        local button = A.UI:Button(frame,label,106,function()
            local ok,reason
            if event=="accept" then ok,reason=A.Dungeon:Accept(self.selected)
            elseif event=="ready" and A.char.taskBatch and A.char.taskBatch.id==self.selected then
                ok,reason=A.Dungeon:ToggleTaskBatchWait()
            else ok,reason=A.Dungeon:Control(event) end
            self.message = ok and nil or reason
            self:Refresh(); A.UI:SelectTab(4)
        end,14)
        return button
    end
    self.accept = control("接受行程","accept")
    self.ready = control("队伍就绪","ready")
    self.finish = control("本轮结束","finish")
    self.again = control("再刷一轮","again")
    self.stop = control("结束行程","stop")
    self.confirmReset=A.UI:Button(frame,"确认已重置",170,function()
        local ok,reason=A.Instances:ConfirmReset(self.selected)
        self.message=ok and "已记录玩家确认；进入资格继续由客户端检查。" or reason
        self:Refresh();A.UI:SelectTab(4)
    end,14)
    self.retry=A.UI:Button(frame,"重新检查",170,function()
        local ok,reason=A.Instances:Retry()
        self.message=not ok and reason or nil
        self:Refresh();A.UI:SelectTab(4)
    end,14)
    self.summaryScroll=CreateFrame("ScrollFrame",nil,frame,"UIPanelScrollFrameTemplate")
    self.summaryScroll:SetPoint("TOPLEFT",514,0)
    self.summaryChild=CreateFrame("Frame",nil,self.summaryScroll)
    self.summaryChild:SetSize(200,280);self.summaryScroll:SetScrollChild(self.summaryChild)
    self.status = A.UI:Text(self.summaryChild,14,{0.9,0.94,1})
    self.status:SetPoint("TOPLEFT");self.status:SetWidth(200)
    self.taskSelector=A.UI:Button(frame,"关联任务",320,function()
        local rows=self.tasks or {}
        if #rows>0 then self.taskIndex=(self.taskIndex or 1)%#rows+1 end
        self:Refresh();A.UI:SelectTab(4)
    end,14)
    self.taskSelector.text:SetWidth(308);self.taskSelector.text:SetMaxLines(1)
    self.taskChain=A.UI:Button(frame,"查看任务链",108,function()
        local row=self.tasks and self.tasks[self.taskIndex or 1]
        if row then A.UI.Chains:Focus(row.id) end
    end,14)
    self.taskGo=A.UI:Button(frame,"继续此任务",116,function()
        local d=self.entries and self.entries[self.selected]
        local row=self.tasks and self.tasks[self.taskIndex or 1]
        if d and row then
            local ok,why=A.Dungeon:ContinueTask(d,row.id)
            self.message=ok and "已选择此任务" or why
            self:Refresh();A.UI:SelectTab(4)
        end
    end,14)
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
    self.selector.text:SetText(d and (A.UI:Icon("entry").."  "..d.title.."  ▾") or "当前构建没有副本任务目录")
    self.selector:SetEnabled(#ids>0)
    local candidate,reason
    if d and A.ready then
        if d.reference then reason="选择并准备关联任务。"
        else candidate,reason=A.Dungeon.Evaluate(d,A.state,A.settings,A.Data) end
    end
    self.tasks=d and A.ready and A.Dungeon.Tasks(d,A.state,A.Data) or {}
    self.taskIndex=math.max(1,math.min(self.taskIndex or 1,#self.tasks))
    local row=self.tasks[self.taskIndex]
    self.taskSelector.text:SetText(row and (self.taskIndex.."/"..#self.tasks.."  "..statusColors[row.group]..row.status.."|r · "..row.title) or "暂无适用的关联任务")
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
    local waiting=compact and batch and batch.id==self.selected and not A.state.inInstance
    self.retry:SetShown(not compact or not not entryError)
    self.bodyTop=136
    self.accept:SetEnabled(candidate~=nil and (not session or session.phase=="complete"))
    self.ready:SetShown(not compact or not not waiting)
    self.ready.text:SetText(waiting and (batch.waiting and "出发去副本" or "等队做任务") or "队伍就绪")
    self.ready:SetEnabled(waiting and A.ready and not A.refreshAt or session~=nil and not session.settled and session.phase~="inside")
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
        lines[#lines+1]=batch.returning and "任务已交齐，离开副本后继续练级。" or
            batch.waiting and "等队时做附近任务；集合后点击「出发去副本」。" or nil
    elseif reason then lines[#lines+1]=reason
    else lines[#lines+1]="点击接受，开始副本行程。" end
    if entryError then lines={entryError}
    elseif self.message then lines[#lines+1]=self.message end
    self.statusText=table.concat(lines,"\n")
    local _,summary=self:Lines()
    self.status:SetText(table.concat(summary,"\n\n"))
    self.summaryChild:SetHeight(self.status:GetStringHeight()+8)
    local controls={{self.taskBatch}}
    if compact then
        if waiting then controls[#controls+1]={self.ready} end
        if entryError then controls[#controls+1]={self.retry} end
    else
        controls[#controls+1]={self.accept,self.ready}
        controls[#controls+1]={self.finish,self.again}
        controls[#controls+1]={self.stop,self.confirmReset}
        controls[#controls+1]={self.retry}
    end
    controls[#controls+1]={self.taskSelector}
    controls[#controls+1]={self.taskGo,self.taskChain}
    for i,buttons in ipairs(controls) do
        local width=#buttons==1 and 226 or 108
        for j,button in ipairs(buttons) do
            button:ClearAllPoints();button:SetPoint("TOPLEFT",514+(j-1)*118,-(448-#controls*32+(i-1)*32))
            button:SetSize(width,26);button.text:SetWidth(width-10)
            button.text:SetJustifyH(button==self.taskSelector and "LEFT" or "CENTER")
        end
    end
    self.summaryScroll:SetSize(212,448-#controls*32-12)
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
    local lines,summary,shown={},{},{}
    local r,g,b=A.UI:Accent()
    local heading=string.format("|cff%02x%02x%02x",r*255,g*255,b*255)
    local selected=self.entries and self.entries[self.selected]
    if selected then
        local _,group=A.Dungeon.GroupStatus(selected,A.state)
        if (A.state.groupSize or 1)==1 and not A.state.inInstance then
            group=group.."\n先准备副本任务；组队后前往入口。"
        end
        summary[#summary+1]=A.UI:Icon("party").."  "..group:gsub(" · ","\n",1)
    end
    if self.statusText and self.statusText~="" then summary[#summary+1]=self.statusText end
    local encounter=A.Dungeon.EncounterProgress(self.entries and self.entries[self.selected],A.state)
    if encounter then summary[#summary+1]=encounter end
    local activity=A.Dungeon:TaskActivityText(self.selected)
    if activity then summary[#summary+1]=activity end
    local batch=A.char.taskBatch
    local current=batch and batch.id==self.selected
    local plan=current and A.plan
    local choices=plan and plan.revision==A.state.revision and plan.taskBatch and plan.taskBatch.id==self.selected and plan.taskChoices
    local journey=choices and plan.taskBatch.journey
    if journey then
        local function phase(title,steps)
            for _,step in ipairs(steps) do
                local action=step.action
                shown[action.questId]=true
                local verb=action.kind=="accept" and "接取" or action.kind=="turnin" and "交付" or "完成"
                local active=A.state.quests[action.questId]
                local status=active and (active.ready and (statusColors[1].."可交付") or (statusColors[2].."已接")) or (statusColors[3].."未接")
                local where=step.recipient and step.recipient.entityName or action.position and action.position.entityName or step.instance
                local symbol=action.kind=="accept" and "accept" or action.kind=="turnin" and "turnin" or "objective"
                local text=A.UI:Icon(symbol).."  "..heading..title.."|r  "..status.."|r  "..verb.."「"..action.title.."」"
                if action.kind=="objective" and action.text then text=text.."\n    "..action.text end
                if where and where~=step.instance then text=text.."\n    |cffc7b8a8"..where.."|r" end
                if step.preparingQuest then text=text.."\n    为「"..step.preparingQuest.title.."」准备前置，交付后接续。" end
                if step.blocked then text=text.."\n    "..step.blocked end
                lines[#lines+1]=text
            end
        end
        phase("入本前",journey.before)
        if journey.entry then lines[#lines+1]=A.UI:Icon("entry").."  "..journey.entry.text end
        phase("副本内",journey.inside)
        if journey.leave and #journey.after==0 then lines[#lines+1]="离开副本，继续练级。" end
        phase(journey.leave and "出本后" or "接下来",journey.after)
    end
    local rewards=A.Dungeon.TaskRewards(self.tasks or {},current and batch.baselines or nil,choices)
    if rewards.count>0 then
        summary[#summary+1]=string.format("%s %d 项\n进行中 %d · %s可交付 %d|r",
            current and "已安排任务" or "可准备任务",rewards.count,rewards.active,statusColors[1],rewards.ready)
        if rewards.unknownXP==0 then summary[#summary+1]=A.UI:Icon("xp").."  "..string.format("%s交付经验：%d|r",statusColors[1],rewards.xp) end
        if rewards.prepare>0 then summary[#summary+1]=rewards.prepare.." 项需先完成前置。" end
        if rewards.upgrades>0 then summary[#summary+1]=rewards.upgrades.." 项任务有装备提升。" end
    end
    if rewards.excluded>0 then summary[#summary+1]="另有 "..rewards.excluded.." 项低收益任务。" end
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
    for i,row in ipairs(self.tasks or {}) do
        if not shown[row.id] then
            local hint=row.relation=="preparation" and "入本准备" or row.relation=="alternative" and "部分目标有其他来源" or
                row.relation=="inside" and "副本目标" or "关联任务"
            local selected=A.char.taskBatch and A.char.taskBatch.id==self.selected and A.char.taskBatch.baselines[row.id]~=nil
            if selected then hint=hint.." · 已安排" end
            if row.lowValue then hint=hint.." · "..row.lowValue.suggestion end
            if row.xp then hint=hint.." · "..row.xp.." 经验" end
            local detail=row.requireCheck and "向任务发布者查看任务" or
                not row.allowed and row.group~=5 and row.reason or row.recipientName
            local symbol=row.group==1 and "turnin" or row.group==2 and "objective" or "accept"
            lines[#lines+1]=A.UI:Icon(symbol).."  "..string.format("%s%s%s|r  %s\n    |cffc7b8a8%s%s|r",i==self.taskIndex and "› " or "",statusColors[row.group],row.status,row.title,hint,detail and (" · "..detail) or "")
            if row.gear then
                local reward=row.gear
                lines[#lines+1]=string.format("     装备提升：%s · 属性评分 %+.1f",reward.item.link or reward.item.name or ("物品 #"..reward.item.id),reward.upgrade.delta)
            end
        end
    end
    if #lines==0 then lines[1]="当前角色暂无适用的关联任务。" end
    local text=self:RepeatText()
    if text then summary[#summary+1]=text end
    return lines,summary
end
