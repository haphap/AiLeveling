local _,A=...
local UI=A.UI
local palette={white={0.97,0.98,1},muted={0.78,0.84,0.89},gold={1,0.83,0.45},green={0.55,0.95,0.72},blue={0.55,0.80,1}}
local media="Interface\\AddOns\\AiLeveling\\Media\\"
local verbs={taskReview="任务建议",accept="接取",objective="进行中",turnin="交付",move="前往目的地",transit="交通",service="补给",
    flight="飞行中",hearthCast="炉石返回",manual="手动目的地",pvpEnter="进入战场",pvpLeave="离开战场",dungeonBlocked="进入受限",dungeonWait="等待队伍",dungeonEnter="进入副本",dungeonLeave="离开副本",dungeonRun="副本进行中",dungeonEnd="结束本轮"}

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
                    step.position and step.position.startItemId and step.text or "先接取，再推进任务目标"),deferred=deferred,candidate=candidate,shared=sharedByQuest[id]}
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
    GameTooltip:SetText(owner.questId and "左键：查看任务详情" or "右键：当前步骤操作")
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
        GameTooltip:SetOwner(f,"ANCHOR_TOP");GameTooltip:SetText("AiLeveling")
        GameTooltip:AddLine("左键拖动面板\n右键：暂停、收起与详细面板",1,1,1,true);GameTooltip:Show()
    end)
    f:SetScript("OnLeave",function() GameTooltip:Hide() end)
    local T=self.tracker
    T.zone=text(f,14);T.zone:SetPoint("TOPLEFT",2,-2);T.zone:SetMaxLines(1)
    T.experience=text(f,12,palette.muted);T.experience:SetPoint("TOPRIGHT",-2,-3);T.experience:SetJustifyH("RIGHT")
    T.xpBack=f:CreateTexture(nil,"BACKGROUND");T.xpBack:SetColorTexture(1,1,1,0.10)
    T.xpBack:SetPoint("TOPLEFT",0,-23);T.xpBack:SetSize(280,2)
    T.xpFill=f:CreateTexture(nil,"ARTWORK");T.xpFill:SetPoint("TOPLEFT",0,-23);T.xpFill:SetSize(1,2)
    T.card=CreateFrame("Frame",nil,f)
    T.card:SetPoint("TOPLEFT",0,-34);T.card:SetSize(280,150)
    T.rail=T.card:CreateTexture(nil,"ARTWORK");T.rail:SetPoint("TOPLEFT",0,0);T.rail:SetPoint("BOTTOMLEFT",0,0);T.rail:SetWidth(2)
    T.stepIcon=T.card:CreateTexture(nil,"ARTWORK")
    T.stepIcon:SetPoint("TOPLEFT",8,-2)
    T.step=text(T.card,12,"accent");T.step:SetPoint("TOPRIGHT",-4,-5);T.step:SetJustifyH("RIGHT")
    self.title=text(T.card,17)
    T.questTitle=CreateFrame("Button",nil,T.card);T.questTitle:SetAllPoints(self.title)
    T.questTitle:RegisterForClicks("LeftButtonUp","RightButtonUp")
    T.questTitle:SetScript("OnClick",function(_,mouse)
        if mouse=="RightButton" then self:TrackerMenu(T.questTitle)
        else self:QuestClick(T.questTitle.questId,mouse) end
    end)
    T.questTitle:SetScript("OnEnter",questTooltip)
    T.questTitle:SetScript("OnLeave",function() GameTooltip:Hide() end)
    T.currentScroll=CreateFrame("ScrollFrame",nil,T.card,"UIPanelScrollFrameTemplate")
    T.currentScroll:SetSize(252,80)
    T.currentChild=CreateFrame("Frame",nil,T.currentScroll);T.currentChild:SetSize(252,80);T.currentScroll:SetScrollChild(T.currentChild)
    self.body=text(T.currentChild,14,palette.white);self.body:SetPoint("TOPLEFT")
    T.objectives={}
    T.queueLabel=text(f,12,palette.white)
    T.queuePanel=CreateFrame("Frame",nil,f);T.queuePanel:SetSize(280,144)
    T.queueScroll=CreateFrame("ScrollFrame",nil,T.queuePanel,"UIPanelScrollFrameTemplate");T.queueScroll:SetSize(252,120)
    T.queueScroll:SetPoint("TOPLEFT",8,-4)
    T.queueChild=CreateFrame("Frame",nil,T.queueScroll);T.queueChild:SetSize(252,120);T.queueScroll:SetScrollChild(T.queueChild)
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

function UI:TrackerRow(index)
    local T=self.tracker
    if T.rows[index] then return T.rows[index] end
    local row=CreateFrame("Button",nil,T.queueChild,"BackdropTemplate")
    row:SetWidth(302);self:Rounded(row,7);row:SetBackdropColor(0,0,0,0)
    row.group=text(row,13,palette.gold);row.group:SetPoint("TOPLEFT",0,-6);row.group:SetWidth(302)
    row.number=text(row,15,palette.muted);row.number:SetPoint("TOPLEFT",0,-8);row.number:SetWidth(24)
    row.number:SetJustifyH("RIGHT");row.number:SetMaxLines(1)
    row.title=text(row,15);row.title:SetPoint("TOPLEFT",32,-8);row.title:SetWidth(270)
    row.statusBack=CreateFrame("Frame",nil,row);self:Rounded(row.statusBack,6)
    row.statusIcon=row.statusBack:CreateTexture(nil,"ARTWORK");row.statusIcon:SetPoint("LEFT",5,0)
    row.status=text(row.statusBack,12,palette.muted);row.status:SetPoint("CENTER",9,0)
    row.status:SetJustifyH("CENTER");row.status:SetMaxLines(1)
    row.progress=text(row,13,palette.muted)
    row.metrics=text(row,13,palette.gold);row.metrics:SetWidth(270)
    row.separator=row:CreateTexture(nil,"BACKGROUND");row.separator:SetColorTexture(0.6,0.7,0.8,0.15)
    row.separator:SetPoint("BOTTOMLEFT",0,0);row.separator:SetSize(302,1)
    row:RegisterForClicks("LeftButtonUp","RightButtonUp")
    row:SetScript("OnEnter",function() row:SetBackdropColor(0.15,0.23,0.27,0.35);questTooltip(row) end)
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
    T.questTitle.deferred=model.questId and ((state.skipped or {})[model.questId] or (state.chainDeferred or {})[model.questId])
    local map=state.position and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(state.position.map)
    T.zone:SetText(map and map.name or "AiLeveling")
    local ratio=state.maxXP and state.maxXP>0 and math.max(0,math.min(1,(state.xp or 0)/state.maxXP)) or 0
    T.experience:SetText(string.format("%d 级  ·  %.0f%%",state.level or 1,ratio*100))
    T.xpRatio=ratio;T.xpFill:SetShown(ratio>0)
    local r,g,b=self:Accent();T.xpFill:SetColorTexture(r,g,b,0.70);T.rail:SetColorTexture(r,g,b,0.90)
    local serviceLabel=action and action.kind=="service" and ({train="训练",bind="设置炉石",repair="维修"})[action.serviceKind]
    T.step:SetText(A.char.paused and "已暂停" or serviceLabel or (verbs[model.kind] or "当前步骤"))
    T.stepIcon:SetTexture(media..(({accept="accept",objective="objective",turnin="turnin",
        dungeonEnter="entry",dungeonRun="objective",dungeonWait="party"})[model.kind] or "compass")..".tga")
    self.title:SetText(model.title)
    local instruction=model.instruction
    if model.kind=="objective" and #model.objectives>0 and not A.char.paused and not A.error and
        not (action.position and action.position.sourceKind=="vendor") then instruction=nil end
    local lines={model.deliverySummary or instruction}
    if model.deliverySummary and instruction and model.kind~="turnin" then lines[#lines+1]=instruction end
    if model.destination and model.kind~="objective" and not model.deliverySummary then lines[#lines+1]=model.destination end
    if model.metrics then lines[#lines+1]=self:Icon("xp",16).." |cffffd474"..model.metrics.."|r" end
    if model.hint and not A.char.paused and not (model.deliverySummary and model.includesCurrent) then lines[#lines+1]="|cffc7d6e3"..model.hint.."|r" end
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
    self.body:SetText(table.concat(lines,"\n"))
    for i,objective in ipairs(model.objectives) do
        local row=T.objectives[i]
        if not row then
            row=CreateFrame("Frame",nil,T.currentChild);row:SetWidth(302)
            row.text=text(row,14);row.text:SetPoint("TOPLEFT");row.text:SetWidth(250)
            row.count=text(row,13,palette.muted);row.count:SetPoint("TOPRIGHT");row.count:SetJustifyH("RIGHT")
            row.back=row:CreateTexture(nil,"BACKGROUND");row.back:SetColorTexture(1,1,1,0.09)
            row.fill=row:CreateTexture(nil,"ARTWORK");T.objectives[i]=row
        end
        row.text:SetText(objective.text);row.text:SetTextColor(unpack(objective.done and palette.green or palette.white))
        local known=type(objective.need)=="number" and objective.need>0
        row.count:SetText(known and string.format("%d/%d",objective.have or 0,objective.need) or (objective.done and "完成" or ""))
        row.ratio=known and math.max(0,math.min(1,(objective.have or 0)/objective.need)) or (objective.done and 1 or 0)
        row:Show()
    end
    for i=#model.objectives+1,#T.objectives do T.objectives[i]:Hide() end
    local number=model.includesCurrent and 0 or 1
    for i,item in ipairs(model.rows) do
        if not item.dungeonId then number=number+1 end
        local row=self:TrackerRow(i)
        row.group:SetText(item.groupTitle or "");row.group:SetShown(item.groupTitle~=nil)
        row.number:SetText(item.dungeonId and "" or string.format("%02d",number));row.title:SetText(item.title)
        row.title:SetTextColor(unpack(item.deferred and palette.muted or palette.white))
        row.status:SetText(item.deferred and (item.accepted and "已接·暂缓" or "未接·暂缓") or item.status)
        local color=item.deferred and palette.muted or
            (item.status=="可交付" and palette.gold or item.accepted and palette.green or palette.blue)
        row.status:SetTextColor(unpack(color));row.statusBack:SetBackdropColor(color[1],color[2],color[3],0.12)
        row.statusIcon:SetTexture(media..(item.dungeonId and "entry" or item.kind=="turnin" and "turnin" or item.accepted and "objective" or "accept")..".tga")
        row.progress:SetText(item.delivery or item.progress)
        if item.shared then row.progress:SetTextColor(self:Accent()) else row.progress:SetTextColor(unpack(palette.muted)) end
        row.metrics:SetText(self:Icon("xp",14).." "..item.metrics)
        row.candidate,row.revision,row.questId=item.candidate,plan.revision,item.questId
        row.deferred,row.dungeonId=item.deferred,item.dungeonId
        row:SetEnabled(true);row:Show()
    end
    for i=#model.rows+1,#T.rows do T.rows[i]:Hide() end
    T.queueLabel:SetText(string.format("%s  ·  已接取 %d  ·  未接取 %d",A.Navigation.manual and "任务列表" or "接下来",
        model.acceptedCount,model.unacceptedCount))
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
    local inner=width-28
    self.frame:SetWidth(width);T.card:SetWidth(width);T.queuePanel:SetWidth(width)
    T.currentScroll:SetWidth(inner);T.currentChild:SetWidth(inner);self.body:SetWidth(inner)
    T.queueScroll:SetWidth(inner);T.queueChild:SetWidth(inner)
    T.xpBack:SetWidth(width);T.xpFill:SetWidth(math.max(1,width*(T.xpRatio or 0)))
    local scale=A.settings.fontScale or 1
    T.zone:SetWidth(width-104*scale)
    T.stepIcon:SetSize(18*scale,18*scale)
    local titleLeft=8+24*scale
    self.title:ClearAllPoints();self.title:SetPoint("TOPLEFT",titleLeft,-2);self.title:SetWidth(width-titleLeft-64*scale)
    local titleHeight=math.max(20*scale,self.title:GetStringHeight())
    local top=titleHeight+10
    local textHeight=math.max(1,self.body:GetStringHeight())
    local childHeight=textHeight+6
    for i,objective in ipairs(T.model and T.model.objectives or {}) do
        local row=T.objectives[i]
        row:SetWidth(inner);row.text:SetWidth(inner-52*scale)
        row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-childHeight)
        local height=math.max(16*scale,row.text:GetStringHeight())+6
        row:SetHeight(height)
        row.back:ClearAllPoints();row.back:SetPoint("BOTTOMLEFT",0,1);row.back:SetSize(inner,2)
        row.fill:ClearAllPoints();row.fill:SetPoint("BOTTOMLEFT",0,1)
        row.fill:SetSize(math.max(1,inner*(row.ratio or 0)),2);row.fill:SetColorTexture(self:Accent());row.fill:SetShown((row.ratio or 0)>0)
        childHeight=childHeight+height+3
    end
    local density=A.settings.density or "normal"
    local maximum=({compact=78,normal=128,expanded=210})[density]
    local height=math.min(childHeight,maximum*scale)
    local collapsed=self.folded or (self.inCombat and A.settings.combatFold)
    T.currentScroll:ClearAllPoints();T.currentScroll:SetPoint("TOPLEFT",8,-top)
    T.currentScroll:SetHeight(math.max(1,height));T.currentChild:SetHeight(childHeight)
    T.currentScroll:SetShown(not collapsed)
    T.card:SetHeight(top+(collapsed and 0 or height)+4)
    local queueTop=34+T.card:GetHeight()+12
    T.queueLabel:ClearAllPoints();T.queueLabel:SetPoint("TOPLEFT",2,-queueTop)
    T.queuePanel:ClearAllPoints();T.queuePanel:SetPoint("TOPLEFT",0,-queueTop-20*scale)
    local queueHeight=0
    for i=1,#(T.model and T.model.rows or {}) do
        local row=T.rows[i]
        row:SetWidth(inner);row.group:SetWidth(inner);row.separator:SetWidth(inner)
        local statusWidth=(T.model.rows[i].deferred and 92 or 68)*scale
        row.statusBack:SetSize(statusWidth,20*scale);row.status:SetWidth(statusWidth-22*scale)
        row.status:ClearAllPoints();row.status:SetPoint("CENTER",9*scale,0)
        row.statusIcon:SetSize(14*scale,14*scale)
        local inset=24*scale
        row.number:SetWidth(20*scale);row.progress:SetWidth(inner-inset);row.metrics:SetWidth(inner-inset)
        local groupHeight=row.group:GetText()~="" and math.max(16*scale,row.group:GetStringHeight())+6 or 0
        row.number:ClearAllPoints();row.number:SetPoint("TOPLEFT",0,-4-groupHeight)
        row.title:ClearAllPoints();row.title:SetPoint("TOPLEFT",inset,-4-groupHeight);row.title:SetWidth(inner-inset-statusWidth-6)
        local title=math.max(18*scale,row.title:GetStringHeight())
        local progress=math.max(16*scale,row.progress:GetStringHeight())
        local progressTop=groupHeight+title+7
        row.statusBack:ClearAllPoints();row.statusBack:SetPoint("TOPRIGHT",0,-3-groupHeight)
        row.progress:ClearAllPoints();row.progress:SetPoint("TOPLEFT",inset,-progressTop)
        local metricsTop=progressTop+progress+3
        row.metrics:ClearAllPoints();row.metrics:SetPoint("TOPLEFT",inset,-metricsTop)
        local rowHeight=metricsTop+math.max(16*scale,row.metrics:GetStringHeight())+6
        row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-queueHeight);row:SetHeight(rowHeight)
        queueHeight=queueHeight+rowHeight
    end
    T.queueChild:SetHeight(math.max(1,queueHeight))
    local visible=math.min(queueHeight,({compact=132,normal=240,expanded=320})[density]*scale)
    T.queueScroll:SetHeight(math.max(1,visible));T.queueScroll:SetShown(not collapsed and queueHeight>0)
    T.queuePanel:SetHeight(visible+8);T.queuePanel:SetShown(not collapsed and queueHeight>0)
    T.queueLabel:SetShown(not collapsed and queueHeight>0)
    local bottom=34+T.card:GetHeight()+4
    if not collapsed and queueHeight>0 then bottom=queueTop+20*scale+visible+8 end
    self.frame:SetHeight(bottom)
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
