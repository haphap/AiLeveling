local _,A=...
local UI=A.UI
local palette=UI.colors
local media="Interface\\AddOns\\AiLeveling\\Media\\"

local function metrics(choice)
    local xp=choice and choice.remainingXP
    local seconds=choice and choice.timing and choice.timing.seconds
    local time="—"
    if seconds then
        seconds=math.ceil(seconds)
        if seconds>=3600 then time=string.format("%d小时%02d分",math.floor(seconds/3600),math.floor(seconds/60)%60)
        elseif seconds>=60 then time=string.format("%d分%02d秒",math.floor(seconds/60),seconds%60)
        else time=string.format("%d秒",seconds) end
    end
    return "经验 "..(xp and string.format("%.0f",xp) or "—").."  ·  路程 "..time
end

local function deliveryAdvice(state,plan,action,choices,byQuest)
    local advice,ordered,seen,immediate={},{},{},{}
    local leading=true
    local function title(choice)
        return (state.quests[choice.questId] or {}).title or choice.title or ("任务 #"..choice.questId)
    end
    local function recipient(choice)
        local last=choice and choice.stages and choice.stages[#choice.stages]
        local point=last and last.kind=="turnin" and (last.recipient or last.position)
        return point and point.entityName
    end
    local function waiting(id)
        local group=byQuest[id]
        return group and not group.splitDelivery and group.ready<#group.choices and state.locked~=id and group
    end
    for id,choice in pairs(choices) do
        local active=(state.quests or {})[id]
        local name=recipient(choice)
        if active and active.ready and name and not choice.itemShortage and not choice.lowValue and not choice.entryBlocked and
            not (state.skipped or {})[id] and not (state.chainDeferred or {})[id] then
            local group=waiting(id)
            if group then
                local pending=0
                for _,other in ipairs(group.choices) do
                    if not (state.quests[other.questId] or {}).ready or (choices[other.questId] or {}).itemShortage then
                        pending=pending+1
                    end
                end
                advice[id]="同组还差 "..pending.." 项，做完一起交"
            else
                local together=byQuest[id]
                advice[id]=together and not together.splitDelivery and together.ready==#together.choices and
                    ("一起交给"..name.."（"..#together.choices.."项）") or ("交付给"..name)
            end
        end
    end
    local function add(choice,stage)
        local id=choice and choice.questId
        if not stage or stage.kind~="turnin" or not id or not (state.quests[id] or {}).ready then leading=false end
        if id and advice[id] and not waiting(id) and not seen[id] and stage and stage.kind=="turnin" then
            ordered[#ordered+1]=choice;seen[id]=true;immediate[id]=leading
        end
    end
    if plan.taskQueue and plan.taskQueue.steps then
        for _,step in ipairs(plan.taskQueue.steps) do
            local choice=step.choice
            add(choice,step.stage or choice and choice.stages and choice.stages[#choice.stages])
        end
    else
        for _,choice in ipairs(plan.taskOrder or {}) do add(choice,choice.stages and choice.stages[#choice.stages]) end
    end
    local current=action and choices[action.questId]
    if not current then return advice end
    local task=current.executionAction or (current.actions or {})[1]
    local turning=action.kind=="turnin" or action.kind=="transit" and task and task.kind=="turnin"
    local summary
    local group=byQuest[current.questId]
    if turning and advice[current.questId] and not waiting(current.questId) then
        local name=recipient(current)
        local batch=not state.locked and group and not group.splitDelivery and group.ready==#group.choices and #group.choices>1
        local nearest=current.distance~=nil
        for id,choice in pairs(choices) do
            if id~=current.questId and advice[id] and not waiting(id) and
                (choice.distance==nil or current.distance==nil or choice.distance<current.distance) then nearest=false end
        end
        summary=batch and ("一起交付：到"..name.."交 "..#group.choices.." 项任务") or
            ((nearest and "就近交付：到" or "顺路先交：到")..name.."交「"..title(current).."」")
        advice[current.questId]=(batch and "本次一起交给" or "现在交给")..name
        local nextName
        for _,choice in ipairs(ordered) do
            local target=recipient(choice)
            if choice.questId==current.questId or batch and byQuest[choice.questId]==group then
                advice[choice.questId]=(batch and "本次一起交给" or "现在交给")..name
            else
                advice[choice.questId]="之后交给"..target.." · 先交「"..title(current).."」"
                if not nextName and target~=name and immediate[choice.questId] then nextName=target end
            end
        end
        if nextName then summary=summary.."；再去"..nextName end
    elseif action.kind=="objective" and (not (state.quests[current.questId] or {}).ready or current.itemShortage) then
        if group and group.ready>0 and waiting(current.questId) then
            summary="同组还差 "..(#group.choices-group.ready).." 项，做完一起交"
        elseif ordered[1] then
            summary="完成当前任务后，到"..recipient(ordered[1]).."交付"
            for _,choice in ipairs(ordered) do advice[choice.questId]="先做「"..title(current).."」，之后交给"..recipient(choice) end
        end
    end
    return advice,summary
end

function UI.TrackerModel(state,plan,action,paused)
    state,plan=state or {},plan or {}
    local quests=state.quests or {}
    if A.Navigation and A.Navigation.StaleAction and A.Navigation.StaleAction(action,state,plan) or
        action and action.questId and UI.QuestStatus(state,action.questId,plan)=="已交付" then action=nil end
    local model={rows={},objectives={},acceptedCount=0,unacceptedCount=0,title=action and action.title or "正在寻找下一步",kind=action and action.kind,
        instruction=action and UI.ActionText(action,A.settings or {}) or "",questId=action and action.questId}
    local active=action and quests[action.questId]
    if active then
        model.title=active.title or model.title
        for _,objective in ipairs(active.objectives or {}) do
            model.objectives[#model.objectives+1]={text=objective.text or "任务目标",done=objective.finished==true,
                have=objective.numFulfilled,need=objective.numRequired}
        end
    end
    local point
    if A.Navigation and A.Navigation.Target then point=A.Navigation.Target(action)
    else point=action and action.position end
    if point then
        local recipient=action.kind=="turnin" and action.recipient
        model.destination=point.entityName or recipient and recipient.entityName
    end
    if action and action.itemGain and action.itemGain>0 then
        local have=(state.bags or {})[action.targetId] or 0
        local total,seen=0,{}
        for _,choice in ipairs(plan.taskOrder or plan.taskChoices or {}) do
            local id=choice.questId
            if quests[id] and not seen[id] and not choice.lowValue and not choice.entryBlocked and
                not (state.skipped or {})[id] and not (state.chainDeferred or {})[id] and (not state.locked or state.locked==id) then
                seen[id]=true
                local last=choice.stages and choice.stages[#choice.stages]
                for _,requirement in ipairs(last and last.itemRequirements or {}) do
                    if requirement.targetId==action.targetId then total=total+(requirement.need or 0) end
                end
            end
        end
        local need=math.max(have+action.itemGain,total)
        local limit=A.TaskGuide and A.TaskGuide.ItemLimit and A.TaskGuide.ItemLimit(action.targetId,state)
        if limit then need=math.min(need,limit) end
        model.objectives[#model.objectives+1]={text="本次所需物品",done=false,have=have,need=need}
    end
    if plan.preparingQuest then model.hint="先完成「"..plan.preparingQuest.title.."」的前置准备"
    elseif action and action.pickupResume then model.hint="顺路接取，与「"..action.pickupResume.."」一并安排"
    elseif action and action.referenceFlight then model.hint="从当前飞行点前往任务区域，落地后继续目标指引"
    elseif plan.serviceDeferred then model.hint=plan.serviceDeferred
    elseif plan.taskBatch and plan.taskBatch.waiting then model.hint="等队时先做附近任务；队伍就绪后继续副本"
    elseif plan.taskBatch then model.hint=plan.taskBatch.title.." · 任务安排剩余 "..plan.taskBatch.remaining.." 项"
    elseif state.locked and action and state.locked==action.questId then model.hint="按你锁定的任务继续" end
    local groups,byQuest={},{}
    local choices={}
    for _,choice in ipairs(plan.taskOrder or {}) do choices[choice.questId]=choice end
    for _,choice in ipairs(plan.taskChoices or {}) do
        choices[choice.questId]=choices[choice.questId] or choice
    end
    if action and choices[action.questId] then model.metrics=metrics(choices[action.questId]) end
    if A.TaskGuide then groups,byQuest=A.TaskGuide.DeliveryGroups(plan.taskChoices,state,plan.taskOrder) end
    local currentGroup=action and byQuest[action.questId]
    model.includesCurrent=currentGroup~=nil
    if currentGroup and not state.locked then
        model.hint=currentGroup.splitDelivery and "物品持有上限限制：先交付已备齐任务，再继续收集" or
            currentGroup.ready==#currentGroup.choices and "整组已完成，前往 "..currentGroup.title.." 集中交付" or
            string.format("同组已完成 %d/%d，先做完剩余任务再集中交付",currentGroup.ready,#currentGroup.choices)
    end
    local shared,sharedKind
    if not paused and A.TaskGuide and A.TaskGuide.SharedObjectives then shared,sharedKind=A.TaskGuide.SharedObjectives(action,plan.taskChoices,state) end
    local sharedByQuest={}
    if shared then
        local titles={}
        for _,entry in ipairs(shared) do
            sharedByQuest[entry.questId]=true
            if entry.questId~=action.questId then titles[#titles+1]="「"..(quests[entry.questId].title or (choices[entry.questId] or {}).title or ("任务 #"..entry.questId)).."」" end
        end
        local summary=(sharedKind=="item" and "一并收集：" or "一起推进：")..table.concat(titles,"、",1,math.min(2,#titles))..(#titles>2 and ("等 "..#titles.." 项任务") or "")
        model.hint=(model.hint and (model.hint.."\n") or "")..summary
    end
    local seen={}
    if action and action.questId and not currentGroup then seen[action.questId]=true end
    local function add(id,source)
        if not id or seen[id] then return end
        seen[id]=true
        local q=quests[id]
        local status=UI.QuestStatus(state,id,plan)
        if status=="已交付" then return end
        local candidate=choices[id]
        local step=source or (candidate and candidate.actions[1]) or {}
        local deferred=(state.skipped or {})[id] or (state.chainDeferred or {})[id]
        local pickup=candidate and candidate.actions[1] or step
        local pickupName=pickup.position and pickup.position.entityName
        local counts={}
        for _,objective in ipairs(q and q.objectives or {}) do
            if objective.numRequired and objective.numRequired>0 then
                local count=string.format("%d/%d",objective.numFulfilled or 0,objective.numRequired)
                local label=objective.text
                counts[#counts+1]=label and label~="" and (label:find("%d+%s*/%s*%d+") and label or label.." · "..count) or count
            end
        end
        model.rows[#model.rows+1]={questId=id,title=q and q.title or step.title or ("任务 #"..id),
            kind=q and (q.ready and "turnin" or "objective") or "accept",
            accepted=q~=nil,status=status,metrics=metrics(candidate),
            progress=q and (q.ready and "目标已完成，前往交付" or (#counts>0 and table.concat(counts," · ") or "查看任务日志中的目标")) or
                (candidate and candidate.acceptBlocked or candidate and candidate.requireCheck and "先确认任务当前是否开放" or
                    step.position and step.position.startItemId and step.text or pickupName and ("接取："..pickupName) or "先接取，再推进任务目标"),deferred=deferred,candidate=candidate,shared=sharedByQuest[id]}
        if sharedByQuest[id] then
            local row=model.rows[#model.rows]
            row.progress=(sharedKind=="item" and "一并收集 · " or "一起推进 · ")..row.progress
        end
        if candidate and candidate.lowValue then
            local row=model.rows[#model.rows]
            row.progress=candidate.lowValue.suggestion.." · "..(candidate.lowValue.summary or "低经验／无装备提升／无任务线")
        elseif candidate and candidate.entryBlocked then
            model.rows[#model.rows].progress=candidate.entryBlocked
        end
        if q then model.acceptedCount=model.acceptedCount+1 else model.unacceptedCount=model.unacceptedCount+1 end
    end
    if plan.best then
        for i=A.Navigation and A.Navigation.index or 1,#(plan.best.actions or {}) do
            local step=plan.best.actions[i]
            if step.kind~="move" then add(step.questId,step) end
        end
    end
    -- Surface a nearby pickup even when its later completion is outside this trip.
    local nearby,nearbyDistance
    local navigation=A.Navigation
    local direct=not paused and action and action.questId and navigation and navigation.Distance and
        navigation:Distance(state.position,action.position)
    if direct and direct>0 then
        for _,choice in ipairs(plan.taskChoices or {}) do
            local id=choice.questId
            local point=choice.actions[1].position
            if not quests[id] and not seen[id] and not (state.skipped or {})[id] and not (state.chainDeferred or {})[id] and
                not choice.lowValue and not choice.acceptBlocked and not choice.entryBlocked and not choice.requireCheck and point then
                local approach=navigation:Distance(state.position,point)
                local onward=navigation:Distance(point,action.position)
                if approach and onward and approach<=direct and onward<=direct and
                    (not nearbyDistance or approach<nearbyDistance) then nearby,nearbyDistance=choice,approach end
            end
        end
    end
    if nearby then
        add(nearby.questId,nearby.actions[1])
        local row=model.rows[#model.rows]
        if row and row.questId==nearby.questId then
            local name=nearby.actions[1].position.entityName
            row.progress="沿途可接"..(name and (" · "..name) or "")
        end
    end
    for _,choice in ipairs(plan.taskOrder or plan.taskChoices or {}) do
        add(choice.questId,choice.executionAction or choice.actions[1])
    end
    local rest={}
    for id in pairs(quests) do if not seen[id] then rest[#rest+1]=id end end
    table.sort(rest);for _,id in ipairs(rest) do add(id) end
    for _,choice in ipairs(plan.taskChoices or {}) do add(choice.questId,choice.actions[1]) end
    local ranked={}
    for _,row in ipairs(model.rows) do if not (row.candidate and row.candidate.lowValue) then ranked[#ranked+1]=row end end
    for _,row in ipairs(model.rows) do if row.candidate and row.candidate.lowValue then ranked[#ranked+1]=row end end
    local grouped,emitted={},{}
    local function emit(group)
        if not group or emitted[group] then return end
        emitted[group]=true
        local first=true
        for _,row in ipairs(ranked) do
            if byQuest[row.questId]==group then
                if first then
                    row.groupTitle=string.format("%s · 已完成 %d/%d",group.title,group.ready,#group.choices)
                    first=false
                end
                if quests[row.questId] and quests[row.questId].ready then
                    row.progress=group.splitDelivery and (row.candidate and row.candidate.itemShortage and
                        "等待前项交付后再收集" or "已备齐 · 可先交付") or
                        row.candidate and row.candidate.itemShortage and "共用物品不足 · 先补齐再一起交付" or
                        (group.ready==#group.choices and "全部完成 · 一起交付" or "已完成 · 等同组任务一起交付")
                end
                grouped[#grouped+1]=row
            end
        end
    end
    emit(currentGroup)
    for _,row in ipairs(ranked) do
        if byQuest[row.questId] then emit(byQuest[row.questId]) else grouped[#grouped+1]=row end
    end
    model.rows=grouped
    if model.kind=="flight" or model.kind=="hearthCast" then model.hint=nil end
    local deliveries,summary=deliveryAdvice(state,plan,action,choices,byQuest)
    model.deliverySummary=summary
    for _,row in ipairs(model.rows) do row.delivery=deliveries[row.questId] end
    if not action then
        if plan.complete then model.title="已达到 60 级";model.instruction="本次升级目标已完成。"
        elseif plan.revision and plan.revision~=state.revision then model.title="正在更新行程";model.instruction="正在安排下一步。"
        elseif plan.selectionBlocked then model.title="所选行程等待处理";model.instruction=plan.selectionBlocked
        elseif not A.indexReady then model.title="正在整理任务";model.instruction="任务数据加载后显示当前步骤。"
        else model.title="选择下一项任务";model.instruction="右键任务可选择优先做，左键查看详情。" end
    end
    local suggestion=not paused and not A.error and plan.suggestedDungeon
    if suggestion and suggestion.reference then
        table.insert(model.rows,1,{dungeonId=suggestion.dungeonId,title=suggestion.title,kind="dungeon",status="副本",
            progress=string.format("%d 项任务 · %s",suggestion.rewards.count,
                suggestion.rewards.prepare>0 and "含前置准备" or "可一起安排"),
            metrics=metrics(suggestion):gsub("路程 ","到入口 "),candidate=suggestion})
    end
    if paused then model.instruction="引导已暂停，右键标题栏可继续引导。";model.hint=nil;model.deliverySummary=nil end
    if A.error then model.title="需要处理";model.instruction=A.error;model.hint=nil;model.deliverySummary=nil end
    return model
end

local function text(parent,size,color)
    local value=UI:Text(parent,size,color or palette.white,"OUTLINE")
    value:SetShadowColor(0,0,0,1);value:SetShadowOffset(1,-1)
    return value
end

local function questTooltip(owner)
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    if owner.dungeonId then
        GameTooltip:SetText("左键：查看副本任务")
        GameTooltip:AddLine("右键：安排整组任务",1,1,1,true);GameTooltip:Show();return
    end
    local quest=owner.questId and (A.state.quests or {})[owner.questId]
    GameTooltip:SetText(quest and quest.title or owner.candidate and owner.candidate.title or "当前步骤")
    if owner.detail then GameTooltip:AddLine(owner.detail,0.94,0.91,0.83,true)
    elseif owner.progress then GameTooltip:AddLine(owner.progress:GetText(),0.94,0.91,0.83,true) end
    if owner.metrics then GameTooltip:AddLine(owner.metrics,1,0.83,0.45,true) end
    if owner.questId then GameTooltip:AddLine("右键：任务操作\nShift+左键：插入任务链接",1,1,1,true) end
    GameTooltip:Show()
end

function UI:TrackerMenu(owner)
    local id,candidate,revision=owner.questId,owner.candidate,owner.revision
    local action=owner==self.tracker.questTitle and self.tracker.action
    GameTooltip:Hide()
    MenuUtil.CreateContextMenu(owner,function(_,menu)
        if owner.dungeonId then
            menu:CreateButton("安排整组任务",function()
                local ok,why=A.Selection.CanChoose(candidate,revision)
                if ok then ok,why=A.Dungeon:StartTaskBatch(owner.dungeonId) end
                if not ok then A:Message(why) end
            end)
        elseif action and action.kind=="manual" then
            menu:CreateButton("返回任务",function() A.Navigation:ClearManual() end)
        elseif action and action.kind=="service" and action.serviceKind=="repair" then
            menu:CreateButton("忽略维修",function() A.Supplies:IgnoreRepair() end)
        elseif id then
            menu:CreateButton("查看任务详情",function() self:QuestClick(id,"RightButton") end)
            local choose=menu:CreateButton("优先做此任务",function()
                local ok,why
                if candidate then ok,why=A.Selection:Lock(candidate,revision)
                else ok,why=A.Selection:LockQuest(id) end
                if not ok then A:Message(why) end
            end)
            choose:SetEnabled(not owner.deferred and (not candidate or A.Selection.CanChoose(candidate,revision)==true))
            menu:CreateButton("暂缓此任务",function() A.Selection:Skip(id) end):SetEnabled(not owner.deferred)
        end
        if A.char.locked or A.char.itinerary then
            menu:CreateButton("恢复自动安排",function()
                local ok,why=A.Selection:Automatic();if not ok then A:Message(why) end
            end)
        end
        if owner==self.frame or not id and not owner.dungeonId then
            menu:CreateButton(A.char.paused and "继续引导" or "暂停引导",function() A:TogglePause() end)
            menu:CreateButton("详细面板",function() self:ToggleDetails() end)
            menu:CreateButton(A.settings.targets~=false and "隐藏目标辅助" or "显示目标辅助",function()
                A:SetOption("targets",A.settings.targets==false)
            end)
            menu:CreateButton("对齐小地图",function()
                A.settings.trackerDocked=true;A.settings.position=nil;self:LayoutCard()
            end)
            menu:CreateButton(self.folded and "展开任务列表" or "收起任务列表",function()
                self.folded=not self.folded;self:LayoutCard()
            end)
        end
    end)
end

function UI:CreateTracker()
    local f=CreateFrame("Frame","AiLevelingMain",UIParent)
    self.frame,self.tracker=f,{}
    f:SetSize(280,280);f:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-24,-260)
    local p=A.settings.position
    if p and A.settings.trackerDocked==false then f:ClearAllPoints();f:SetPoint(p[1],UIParent,p[2],p[3],p[4]) end
    self:Movable(f,"position")
    f:SetScript("OnMouseUp",function(_,button) if button=="RightButton" then self:TrackerMenu(f) end end)
    f:SetScript("OnEnter",function()
        GameTooltip:SetOwner(f,"ANCHOR_TOP");GameTooltip:SetText("AILeveling")
        GameTooltip:AddLine("左键拖动面板\n右键：暂停、收起与详细面板",1,1,1,true);GameTooltip:Show()
    end)
    f:SetScript("OnLeave",function() GameTooltip:Hide() end)
    self:Rounded(f,8);f:SetBackdropColor(0.045,0.050,0.060,0.32)
    local T=self.tracker
    T.content=CreateFrame("Frame",nil,f);T.content:SetPoint("TOPLEFT",10,-10)
    T.zone=text(T.content,14,palette.gold);T.zone:SetPoint("TOPLEFT",0,0)
    T.zone:SetText(self:Icon("accept",16).." 任务")
    T.experience=text(T.content,12,palette.muted);T.experience:SetJustifyH("RIGHT")
    T.collapse=self:Button(T.content,"−",20,function() self.folded=not self.folded;self:LayoutTracker() end,16)
    T.menu=self:Button(T.content,"···",22,function() self:TrackerMenu(f) end,16)
    for _,button in ipairs({T.collapse,T.menu}) do button.baseColor={0,0,0,0};button:SetBackdropColor(0,0,0,0) end
    T.divider=T.content:CreateTexture(nil,"BACKGROUND");T.divider:SetColorTexture(unpack(palette.line))
    T.card=CreateFrame("Frame",nil,T.content)
    T.numberBack=CreateFrame("Frame",nil,T.card);self:Rounded(T.numberBack,3,palette.border)
    T.numberBack:SetBackdropColor(0.18,0.12,0.07,0.7)
    T.number=text(T.numberBack,12,palette.gold);T.number:SetPoint("CENTER");T.number:SetText("1")
    T.stepIcon=T.card:CreateTexture(nil,"ARTWORK")
    self.title=text(T.card,15,palette.gold)
    T.questTitle=CreateFrame("Button",nil,T.card);T.questTitle:SetAllPoints(self.title)
    T.questTitle:RegisterForClicks("LeftButtonUp","RightButtonUp")
    T.questTitle:SetScript("OnClick",function(_,mouse)
        if mouse=="RightButton" then self:TrackerMenu(T.questTitle)
        else self:QuestClick(T.questTitle.questId,mouse) end
    end)
    T.questTitle:SetScript("OnEnter",questTooltip)
    T.questTitle:SetScript("OnLeave",function() GameTooltip:Hide() end)
    T.currentScroll=CreateFrame("ScrollFrame",nil,T.card,"UIPanelScrollFrameTemplate")
    T.currentChild=CreateFrame("Frame",nil,T.currentScroll);T.currentScroll:SetScrollChild(T.currentChild)
    self.body=text(T.currentChild,13,palette.muted);self.body:SetMaxLines(2)
    T.objectives={}
    T.footer=text(T.currentChild,12,palette.muted)
    T.questTitle.progress=self.body
    T.region=self:Button(T.content,"",250,function() self.details:Show();self:SelectTab(10) end,12)
    T.region.baseColor={0,0,0,0};T.region:SetBackdropColor(0,0,0,0)
    T.queuePanel=CreateFrame("Frame",nil,T.content)
    T.queueScroll=CreateFrame("ScrollFrame",nil,T.queuePanel,"UIPanelScrollFrameTemplate")
    T.queueScroll:SetPoint("TOPLEFT",0,0)
    T.queueChild=CreateFrame("Frame",nil,T.queueScroll);T.queueScroll:SetScrollChild(T.queueChild)
    T.rows={}
    local nav=CreateFrame("Frame","AiLevelingNavigation",UIParent)
    self.navFrame=nav;nav:SetSize(420,90);nav:SetPoint("CENTER",UIParent,"CENTER",0,-110)
    p=A.settings.navigationPosition
    if p then nav:ClearAllPoints();nav:SetPoint(p[1],UIParent,p[2],p[3],p[4]) end
    self:Movable(nav,"navigationPosition")
    self.nav=text(nav,17,"accent");self.nav:SetPoint("TOP",0,-37);self.nav:SetJustifyH("CENTER")
    T.navTitle=text(nav,12);T.navTitle:SetPoint("TOP",0,-62);T.navTitle:SetWidth(420);T.navTitle:SetJustifyH("CENTER")
    T.arrowLines={}
    for i=1,4 do
        local line=nav:CreateLine(nil,i<=2 and "BACKGROUND" or "OVERLAY")
        line:SetThickness(i<=2 and 6 or 3);T.arrowLines[i]=line
    end
    nav:Hide()
end

local function questTitle(id,title,candidate)
    local quest=(A.state.quests or {})[id]
    local level=quest and quest.level or candidate and candidate.level
    return (level and level>0 and ("["..level.."] ") or "")..title
end

local function renderObjectives(owner,parent,pool,objectives)
    for i,objective in ipairs(objectives) do
        local row=pool[i]
        if not row then
            row=CreateFrame("Button",nil,parent)
            row:RegisterForClicks("LeftButtonUp","RightButtonUp")
            row:SetScript("OnClick",function(_,button)
                if button=="RightButton" then UI:TrackerMenu(owner) else UI:QuestClick(owner.questId,button) end
            end)
            row:SetScript("OnEnter",function() questTooltip(owner) end)
            row:SetScript("OnLeave",function() GameTooltip:Hide() end)
            row.text=text(row,14);row.text:SetPoint("TOPLEFT");row.text:SetNonSpaceWrap(false)
            row.count=text(row,13);row.count:SetPoint("TOPRIGHT");row.count:SetJustifyH("RIGHT")
            row.back=row:CreateTexture(nil,"BACKGROUND");row.back:SetColorTexture(1,1,1,0.08)
            row.fill=row:CreateTexture(nil,"ARTWORK");pool[i]=row
        end
        local done=objective.done or objective.finished==true
        local need,have=objective.need or objective.numRequired,objective.have or objective.numFulfilled or 0
        row.known=type(need)=="number" and need>0
        row.ratio=row.known and math.max(0,math.min(1,have/need)) or 0
        row.text:SetText((objective.text or "任务目标"):gsub("%s*%d+%s*/%s*%d+",""):gsub("^%s+",""))
        row.text:SetTextColor(unpack(done and palette.muted or palette.white))
        row.count:SetText(row.known and string.format("%d/%d",have,need) or (done and "✓" or ""))
        row.count:SetTextColor(unpack(done and palette.green or palette.white))
        local color=done and palette.green or palette.accent
        row.fill:SetColorTexture(color[1],color[2],color[3],0.75)
        row:Show()
    end
    for i=#objectives+1,#pool do pool[i]:Hide() end
end

local function layoutObjectives(pool,width,scale)
    local y=0
    for _,row in ipairs(pool) do
        if row:IsShown() then
            local countWidth=row.count:GetText()~="" and 46*scale or 0
            row:SetWidth(width);row.text:SetWidth(width-countWidth);row.count:SetWidth(countWidth)
            row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-y)
            local height=math.max(18*scale,row.text:GetStringHeight())
            row.back:ClearAllPoints();row.back:SetPoint("TOPLEFT",0,-height-2);row.back:SetSize(width,2)
            row.fill:ClearAllPoints();row.fill:SetPoint("TOPLEFT",0,-height-2);row.fill:SetSize(math.max(1,width*row.ratio),2)
            row.back:SetShown(row.known);row.fill:SetShown(row.known and row.ratio>0)
            height=height+(row.known and 8 or 4)*scale
            row:SetHeight(height);y=y+height
        end
    end
    return y
end

function UI:TrackerRow(index)
    local T=self.tracker
    if T.rows[index] then return T.rows[index] end
    local row=CreateFrame("Button",nil,T.queueChild,"BackdropTemplate")
    self:Rounded(row,4);row:SetBackdropColor(0,0,0,0)
    row.numberBack=CreateFrame("Frame",nil,row);self:Rounded(row.numberBack,3,palette.border)
    row.numberBack:SetBackdropColor(0.18,0.12,0.07,0.7)
    row.number=text(row.numberBack,12,palette.gold);row.number:SetPoint("CENTER")
    row.title=text(row,15,palette.gold)
    row.progress=text(row,13,palette.muted)
    row.objectiveFrame=CreateFrame("Frame",nil,row);row.objectives={}
    row:RegisterForClicks("LeftButtonUp","RightButtonUp")
    row:SetScript("OnEnter",function() row:SetBackdropColor(0.18,0.12,0.07,0.3);questTooltip(row) end)
    row:SetScript("OnLeave",function() row:SetBackdropColor(0,0,0,0);GameTooltip:Hide() end)
    row:SetScript("OnClick",function(_,button)
        if button=="RightButton" then self:TrackerMenu(row)
        elseif row.dungeonId then self.Dungeon.selected=row.dungeonId;self.details:Show();self:SelectTab(4)
        else self:QuestClick(row.questId,button) end
    end)
    T.rows[index]=row
    return row
end

function UI:RenderTracker()
    local T=self.tracker
    if not T then return end
    local state,plan=A.state or {},A.plan or {}
    local action=A.Navigation:Current()
    local model=UI.TrackerModel(state,plan,action,A.char.paused)
    T.model,T.action=model,action
    T.questTitle.questId=model.questId
    T.questTitle.candidate,T.questTitle.revision=nil,nil
    T.questTitle.deferred=model.questId and ((state.skipped or {})[model.questId] or (state.chainDeferred or {})[model.questId])
    local current=(state.quests or {})[model.questId]
    local count=0;for _ in pairs(state.quests or {}) do count=count+1 end
    T.experience:SetText(A.char.paused and "已暂停" or "已接 "..count)
    T.stepIcon:SetTexture(media..(({accept="accept",objective="objective",turnin="turnin",
        dungeonEnter="entry",dungeonRun="objective",dungeonWait="party"})[model.kind] or "compass")..".tga")
    self.title:SetText(questTitle(model.questId,model.title))
    self.title:SetTextColor(unpack(model.kind=="turnin" and palette.green or model.kind=="accept" and palette.blue or palette.gold))
    T.numberBack:SetShown(model.questId~=nil)
    local region
    for _,candidate in ipairs(plan.regions or {}) do
        if not candidate.current and #candidate.choices>=3 then region=candidate;break end
    end
    T.region.text:SetText(region and "可考虑："..region.title.."  ›" or "")
    T.region.region=region

    local instruction=model.instruction
    if model.kind=="objective" and #model.objectives>0 and not A.char.paused and not A.error and
        not (action.position and action.position.sourceKind=="vendor") then instruction=nil end
    local lines={model.deliverySummary or instruction}
    if model.deliverySummary and instruction and model.kind~="turnin" then lines[#lines+1]=instruction end
    if model.destination and model.kind~="objective" and not model.deliverySummary and
        not (instruction and instruction:find(model.destination,1,true)) then lines[#lines+1]=model.destination end
    T.footer:SetText(model.metrics or "");T.questTitle.metrics=model.metrics
    if #lines==0 and model.hint and not A.char.paused and state.locked~=model.questId then lines[#lines+1]=model.hint end
    if plan.selectionBlocked then lines[#lines+1]=plan.selectionBlocked end
    if plan.gearTargetBlocked then lines[#lines+1]=plan.gearTargetBlocked end
    if plan.supplyIssue then lines[#lines+1]=plan.supplyIssue end
    if action and action.kind=="service" then
        local function items(map,label)
            local ids={};for id in pairs(map or {}) do ids[#ids+1]=id end;table.sort(ids)
            for _,id in ipairs(ids) do
                local item=state.itemMetadata and state.itemMetadata[id]
                lines[#lines+1]=label..(item and item.name or ("#"..id)).." ×"..map[id]
            end
        end
        local goal=action.serviceGoal or {}
        items(goal.items,"需携带：");items(action.consumeItems,"整理／出售：");items(goal.capacityItems,"预留容量：")
        if goal.freeSlots and goal.freeSlots>0 then lines[#lines+1]="通用空格至少 "..goal.freeSlots.." 格" end
        if A.Merchant then for _,line in ipairs(A.Merchant.Lines(action,state)) do lines[#lines+1]=line end end
    end
    local guidance=table.concat(lines,"\n")
    if model.kind=="objective" and #model.objectives>0 and not A.char.paused and not A.error and
        not (action.position and action.position.sourceKind=="vendor") then
        guidance=model.deliverySummary or model.hint or ""
    end
    self.body:SetText(guidance)
    self.body:SetTextColor(unpack(model.kind=="turnin" and palette.green or model.kind=="accept" and palette.blue or palette.muted))
    T.questTitle.detail=table.concat(lines,"\n")
    renderObjectives(T.questTitle,T.currentChild,T.objectives,
        (model.kind=="objective" or current and not current.ready) and model.objectives or {})
    local number=model.questId and 1 or 0
    for i,item in ipairs(model.rows) do
        local row=self:TrackerRow(i)
        local isCurrent=item.questId and item.questId==model.questId
        if not isCurrent and not item.dungeonId then number=number+1 end
        row.number:SetText(item.dungeonId and "!" or tostring(number))
        row.title:SetText(questTitle(item.questId,item.title,item.candidate))
        local color=(item.deferred or item.candidate and item.candidate.lowValue) and palette.muted or item.kind=="turnin" and palette.green or item.accepted and palette.gold or palette.blue
        row.title:SetTextColor(unpack(color))
        row.status=item.deferred and (item.accepted and "已接·暂缓" or "未接·暂缓") or item.status
        row.progress:SetText(item.deferred and "已暂缓" or item.candidate and item.candidate.lowValue and item.candidate.lowValue.suggestion or item.delivery or item.progress)
        row.progress:SetTextColor(unpack(item.kind=="turnin" and palette.green or item.accepted and palette.muted or palette.blue))
        row.metrics=item.metrics
        row.candidate,row.revision,row.questId=item.candidate,plan.revision,item.questId
        row.deferred,row.dungeonId=item.deferred,item.dungeonId
        local native=(state.quests or {})[item.questId]
        local objectives=item.accepted and item.kind~="turnin" and not item.deferred and
            not (item.candidate and (item.candidate.lowValue or item.candidate.entryBlocked)) and native and native.objectives or {}
        renderObjectives(row,row.objectiveFrame,row.objectives,objectives)
        row.hasObjectives=#objectives>0
        row.detail=table.concat({row.status,item.groupTitle or "",item.delivery or item.progress},"\n")
        if isCurrent then T.questTitle.candidate=item.candidate;T.questTitle.revision=plan.revision end
        row:SetEnabled(true);row:Show()
    end
    for i=#model.rows+1,#T.rows do T.rows[i]:Hide() end
    self:LayoutTracker()
end

function UI:LayoutTracker()
    local T=self.tracker
    if not T then return end
    if ObjectiveTrackerFrame and not T.nativeHider and not InCombatLockdown() then
        T.nativeHider=CreateFrame("Frame",nil,UIParent);T.nativeHider:Hide()
        ObjectiveTrackerFrame:SetParent(T.nativeHider)
    end
    local minimap=MinimapCluster and MinimapCluster:IsShown() and MinimapCluster or Minimap
    local width=280
    if minimap then width=math.max(260,math.min(300,minimap:GetWidth()*minimap:GetEffectiveScale()/self.frame:GetEffectiveScale())) end
    if A.settings.trackerDocked~=false then
        self.frame:ClearAllPoints()
        if minimap then self.frame:SetPoint("TOPRIGHT",minimap,"BOTTOMRIGHT",0,-12)
        else self.frame:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-24,-260) end
    end
    self.frame:SetWidth(width)
    width=width-20
    local inner=width-20
    local scale=A.settings.fontScale or 1
    local indent=24*scale
    local bodyWidth=inner-indent
    local collapsed=self.folded or (self.inCombat and A.settings.combatFold)
    local density=A.settings.density or "normal"
    T.content:SetWidth(width);T.card:SetWidth(width);T.queuePanel:SetWidth(width)
    T.zone:SetWidth(width-120*scale)
    T.menu:ClearAllPoints();T.menu:SetPoint("TOPRIGHT",-22*scale,2);T.menu:SetSize(22*scale,22*scale)
    T.collapse:ClearAllPoints();T.collapse:SetPoint("TOPRIGHT",0,2);T.collapse:SetSize(20*scale,22*scale)
    T.collapse.text:SetText(collapsed and "+" or "−")
    T.experience:ClearAllPoints();T.experience:SetPoint("TOPRIGHT",-58*scale,-3);T.experience:SetWidth(62*scale);T.experience:SetMaxLines(1)
    local cardTop=30*scale
    T.divider:ClearAllPoints();T.divider:SetPoint("TOPLEFT",0,-cardTop+7);T.divider:SetSize(width,1)
    T.card:ClearAllPoints();T.card:SetPoint("TOPLEFT",0,-cardTop)
    T.numberBack:ClearAllPoints();T.numberBack:SetPoint("TOPLEFT",0,-1);T.numberBack:SetSize(18*scale,18*scale)
    T.stepIcon:ClearAllPoints();T.stepIcon:SetPoint("TOPRIGHT",-2,-2);T.stepIcon:SetSize(15*scale,15*scale)
    self.title:ClearAllPoints();self.title:SetPoint("TOPLEFT",indent,0);self.title:SetWidth(bodyWidth);self.title:SetMaxLines(2)
    local top=math.max(20*scale,self.title:GetStringHeight())+5
    T.currentScroll:SetWidth(bodyWidth);T.currentChild:SetWidth(bodyWidth)
    local childHeight=layoutObjectives(T.objectives,bodyWidth,scale)
    self.body:ClearAllPoints();self.body:SetPoint("TOPLEFT",0,-childHeight);self.body:SetWidth(bodyWidth)
    self.body:SetShown(self.body:GetText()~="")
    if self.body:IsShown() then childHeight=childHeight+self.body:GetStringHeight()+5 end
    T.footer:ClearAllPoints();T.footer:SetPoint("TOPLEFT",0,-childHeight);T.footer:SetWidth(bodyWidth);T.footer:SetMaxLines(1)
    T.footer:SetShown(T.footer:GetText()~="")
    if T.footer:IsShown() then childHeight=childHeight+18*scale end
    local height=math.min(childHeight,({compact=100,normal=170,expanded=240})[density]*scale)
    T.currentScroll:ClearAllPoints();T.currentScroll:SetPoint("TOPLEFT",indent,-top)
    T.currentScroll:SetHeight(math.max(1,height));T.currentChild:SetHeight(math.max(1,childHeight));T.currentScroll:SetShown(not collapsed)
    T.card:SetHeight(top+(collapsed and 0 or height))
    local queueTop=cardTop+T.card:GetHeight()+10
    T.queuePanel:ClearAllPoints();T.queuePanel:SetPoint("TOPLEFT",0,-queueTop)
    T.queueScroll:SetWidth(inner);T.queueChild:SetWidth(inner)
    local queueHeight=0
    for i,item in ipairs(T.model and T.model.rows or {}) do
        local row=T.rows[i]
        local current=item.questId and item.questId==T.model.questId
        row:SetShown(not current)
        if not current then
            row:SetWidth(inner)
            row.numberBack:ClearAllPoints();row.numberBack:SetPoint("TOPLEFT",0,-1);row.numberBack:SetSize(18*scale,18*scale)
            row.title:ClearAllPoints();row.title:SetPoint("TOPLEFT",indent,0);row.title:SetWidth(bodyWidth);row.title:SetMaxLines(2)
            local rowHeight=math.max(20*scale,row.title:GetStringHeight())+4
            row.objectiveFrame:ClearAllPoints();row.objectiveFrame:SetPoint("TOPLEFT",indent,-rowHeight);row.objectiveFrame:SetWidth(bodyWidth)
            local objectivesHeight=layoutObjectives(row.objectives,bodyWidth,scale)
            row.objectiveFrame:SetHeight(math.max(1,objectivesHeight));rowHeight=rowHeight+objectivesHeight
            row.progress:SetShown(not row.hasObjectives)
            row.progress:ClearAllPoints();row.progress:SetPoint("TOPLEFT",indent,-rowHeight);row.progress:SetWidth(bodyWidth);row.progress:SetMaxLines(2)
            if row.progress:IsShown() then rowHeight=rowHeight+math.min(row.progress:GetStringHeight(),36*scale)+4 end
            rowHeight=rowHeight+10*scale
            row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-queueHeight);row:SetHeight(rowHeight)
            queueHeight=queueHeight+rowHeight
        end
    end
    T.queueChild:SetHeight(math.max(1,queueHeight))
    local visible=math.min(queueHeight,({compact=150,normal=250,expanded=340})[density]*scale)
    T.queueScroll:SetHeight(math.max(1,visible));T.queueScroll:SetShown(not collapsed and queueHeight>0)
    T.queuePanel:SetHeight(visible);T.queuePanel:SetShown(not collapsed and queueHeight>0)
    local bottom=queueTop+(not collapsed and queueHeight>0 and visible+4 or 0)
    T.region:ClearAllPoints();T.region:SetPoint("TOPLEFT",indent,-bottom);T.region:SetSize(width-indent,20*scale)
    T.region.text:SetWidth(width-indent);T.region.text:SetMaxLines(1);T.region:SetShown(not collapsed and T.region.region~=nil)
    if T.region:IsShown() then bottom=bottom+24*scale end
    T.content:SetHeight(bottom);self.frame:SetHeight(bottom+20)
    if A.QuestAssist then A.QuestAssist:LayoutTarget() end
end

function UI:SetTrackerNavigation(distance,angle,unverified)
    if not self.navFrame then return end
    local action=A.Navigation:Current()
    local show=A.settings.arrow and distance~=nil and not A.char.paused
    self.navFrame:SetShown(show==true)
    if not show then return end
    local meters=A.settings.distanceUnits=="meters"
    self.nav:SetText(string.format("%.0f %s",meters and distance*0.9144 or distance,meters and "米" or "码"))
    local target=A.Navigation.Target(action)
    self.tracker.navTitle:SetText((action and action.title or "目的地")..(target and target.approximate and " · 区域参考点" or ""))
    self.navFrame:SetHeight(math.max(90,70+self.tracker.navTitle:GetStringHeight()))
    local points={{-10,-6,0,7},{0,7,10,-6}}
    local cos,sin=math.cos(-(angle or 0)),math.sin(-(angle or 0))
    for i,line in ipairs(self.tracker.arrowLines) do
        local p=points[(i-1)%2+1]
        line:SetShown(angle~=nil)
        line:SetStartPoint("TOP",self.navFrame,p[1]*cos-p[2]*sin,-16+p[1]*sin+p[2]*cos)
        line:SetEndPoint("TOP",self.navFrame,p[3]*cos-p[4]*sin,-16+p[3]*sin+p[4]*cos)
        if i<=2 then line:SetColorTexture(0.01,0.02,0.02,0.85) else line:SetColorTexture(self:Accent()) end
    end
end
