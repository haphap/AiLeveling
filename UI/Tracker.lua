local _,A=...
local UI=A.UI
local palette={white={0.92,0.95,0.97},muted={0.57,0.65,0.70},gold={0.95,0.76,0.37},green={0.42,0.84,0.63}}
local verbs={taskReview="任务建议",accept="接取",objective="进行中",turnin="交付",move="前往目的地",transit="交通",service="补给",
    flight="飞行中",hearthCast="炉石返回",manual="手动目的地",pvpEnter="进入战场",pvpLeave="离开战场",dungeonBlocked="进入受限",dungeonWait="等待队伍",dungeonEnter="进入副本",dungeonLeave="离开副本",dungeonRun="副本进行中",dungeonEnd="结束本轮"}

function UI.TrackerModel(state,plan,action,paused)
    state,plan=state or {},plan or {}
    local quests=state.quests or {}
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
    local point=action and A.Navigation and A.Navigation.Target and A.Navigation.Target(action) or action and action.position
    if point then
        local map=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(point.map)
        local parts={}
        local recipient=action.kind=="turnin" and action.recipient
        local name=point.entityName or recipient and recipient.entityName
        if name then parts[#parts+1]=name end
        if map and map.name then parts[#parts+1]=map.name end
        if point.x and point.y then parts[#parts+1]=string.format("%.1f, %.1f",point.x*100,point.y*100) end
        if point.approximate then parts[#parts+1]="区域参考点" end
        if #parts>0 then model.destination=table.concat(parts," · ") end
    end
    if action and action.itemGain and action.itemGain>0 then
        local have=(state.bags or {})[action.targetId] or 0
        model.objectives[#model.objectives+1]={text="这批任务所需物品",done=false,have=have,need=have+action.itemGain}
    end
    if plan.preparingQuest then model.hint="先完成「"..plan.preparingQuest.title.."」的前置准备"
    elseif action and action.referenceFlight then model.hint="从当前飞行点前往任务区域，落地后继续目标指引"
    elseif action and action.sharedObjectives and #action.sharedObjectives>1 then
        model.hint="此目标可同时推进 "..#action.sharedObjectives.." 个任务"
    elseif plan.taskBatch then model.hint=plan.taskBatch.title.." · 任务安排剩余 "..plan.taskBatch.remaining.." 项"
    elseif state.locked and action and state.locked==action.questId then model.hint="按你锁定的任务继续" end
    local groups,byQuest={},{}
    local choices={}
    for _,choice in ipairs(plan.taskOrder or {}) do choices[choice.questId]=choice end
    for _,choice in ipairs(plan.taskChoices or {}) do
        choices[choice.questId]=choices[choice.questId] or choice
    end
    if A.TaskGuide then groups,byQuest=A.TaskGuide.DeliveryGroups(plan.taskChoices,state,plan.taskOrder) end
    local currentGroup=action and byQuest[action.questId]
    model.includesCurrent=currentGroup~=nil
    if currentGroup and not state.locked then
        model.hint=currentGroup.splitDelivery and "物品持有上限限制：先交付已备齐任务，再继续收集" or
            currentGroup.ready==#currentGroup.choices and "整组已完成，前往 "..currentGroup.title.." 集中交付" or
            string.format("同组已完成 %d/%d，先做完剩余任务再集中交付",currentGroup.ready,#currentGroup.choices)
    end
    local seen={}
    if action and action.questId and not currentGroup then seen[action.questId]=true end
    local function add(id,source)
        if not id or seen[id] then return end
        seen[id]=true
        local q=quests[id]
        local candidate=choices[id]
        local step=source or (candidate and candidate.actions[1]) or {}
        local deferred=(state.skipped or {})[id] or (state.chainDeferred or {})[id]
        local counts={}
        for _,objective in ipairs(q and q.objectives or {}) do
            if objective.numRequired and objective.numRequired>0 then
                counts[#counts+1]=string.format("%d/%d",objective.numFulfilled or 0,objective.numRequired)
            end
        end
        model.rows[#model.rows+1]={questId=id,title=q and q.title or step.title or ("任务 #"..id),
            kind=q and (q.ready and "turnin" or "objective") or "accept",
            accepted=q~=nil,status=UI.QuestStatus(state,id),
            progress=q and (q.ready and "目标已完成，前往交付" or (#counts>0 and table.concat(counts," · ") or "查看任务日志中的目标")) or
                (candidate and candidate.acceptBlocked or candidate and candidate.requireCheck and "先确认任务当前是否开放" or "先接取，再推进任务目标"),deferred=deferred,candidate=candidate}
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
    for _,choice in ipairs(plan.taskOrder or plan.taskChoices or {}) do
        if quests[choice.questId] or not next(quests) then add(choice.questId,choice.actions[1]) end
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
    if not action then
        if plan.complete then model.title="已达到 60 级";model.instruction="本次升级目标已完成。"
        elseif plan.selectionBlocked then model.title="所选行程等待处理";model.instruction=plan.selectionBlocked
        elseif not A.indexReady then model.title="正在整理任务";model.instruction="任务数据加载后显示当前步骤。"
        else model.title="选择下一项任务";model.instruction="点击下方任务开始，或打开详情查看行程。" end
    end
    if paused then model.instruction="引导已暂停，点击继续恢复。";model.hint=nil end
    if A.error then model.title="需要处理";model.instruction=A.error;model.hint=nil end
    return model
end

local function text(parent,size,color)
    local value=UI:Text(parent,size,color or palette.white)
    value:SetShadowColor(0,0,0,0.8);value:SetShadowOffset(0,-1)
    return value
end

function UI:CreateTracker()
    local f=CreateFrame("Frame","AiLevelingMain",UIParent)
    self.frame,self.tracker=f,{}
    f:SetSize(360,280);f:SetPoint("RIGHT",UIParent,"RIGHT",-64,90)
    local p=A.settings.position
    if p then f:ClearAllPoints();f:SetPoint(p[1],UIParent,p[2],p[3],p[4]) end
    self:Movable(f,"position")
    local T=self.tracker
    T.zone=text(f,15);T.zone:SetPoint("TOPLEFT",2,-2);T.zone:SetWidth(226);T.zone:SetMaxLines(1)
    T.experience=text(f,11,palette.muted);T.experience:SetPoint("TOPRIGHT",-2,-5);T.experience:SetJustifyH("RIGHT")
    T.xpBack=f:CreateTexture(nil,"BACKGROUND");T.xpBack:SetColorTexture(1,1,1,0.10)
    T.xpBack:SetPoint("TOPLEFT",0,-28);T.xpBack:SetSize(360,2)
    T.xpFill=f:CreateTexture(nil,"ARTWORK");T.xpFill:SetPoint("TOPLEFT",0,-28);T.xpFill:SetSize(1,2)
    T.card=CreateFrame("Frame",nil,f,"BackdropTemplate")
    T.card:SetPoint("TOPLEFT",0,-42);T.card:SetSize(360,150)
    T.card:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    T.card:SetBackdropColor(0.035,0.047,0.057,0.90);T.card:SetBackdropBorderColor(0.30,0.38,0.42,0.30)
    T.rail=T.card:CreateTexture(nil,"ARTWORK");T.rail:SetPoint("TOPLEFT",0,-1);T.rail:SetPoint("BOTTOMLEFT",0,1);T.rail:SetWidth(2)
    T.step=text(T.card,10,"accent");T.step:SetPoint("TOPLEFT",16,-13)
    self.title=text(T.card,17);self.title:SetPoint("TOPLEFT",16,-34);self.title:SetWidth(326)
    T.currentScroll=CreateFrame("ScrollFrame",nil,T.card,"UIPanelScrollFrameTemplate")
    T.currentScroll:SetSize(308,80)
    T.currentChild=CreateFrame("Frame",nil,T.currentScroll);T.currentChild:SetSize(302,80);T.currentScroll:SetScrollChild(T.currentChild)
    self.body=text(T.currentChild,12,palette.white);self.body:SetPoint("TOPLEFT");self.body:SetWidth(302)
    T.objectives={}
    T.queueLabel=text(f,10,palette.muted)
    T.queuePanel=CreateFrame("Frame",nil,f,"BackdropTemplate");T.queuePanel:SetSize(360,144)
    T.queuePanel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    T.queuePanel:SetBackdropColor(0.025,0.04,0.05,0.40);T.queuePanel:SetBackdropBorderColor(0.30,0.38,0.42,0.20)
    T.queueScroll=CreateFrame("ScrollFrame",nil,T.queuePanel,"UIPanelScrollFrameTemplate");T.queueScroll:SetSize(308,120)
    T.queueScroll:SetPoint("TOPLEFT",16,-12)
    T.queueChild=CreateFrame("Frame",nil,T.queueScroll);T.queueChild:SetSize(302,120);T.queueScroll:SetScrollChild(T.queueChild)
    T.rows={}
    T.tools=CreateFrame("Frame",nil,f);T.tools:SetSize(360,26)
    local actions={
        {"暂停",function() A:TogglePause() end},
        {"锁定",function() local action=A.Navigation:Current();local ok,why=A.Selection:LockQuest(action and action.questId);if not ok then A:Message(why) end end},
        {"暂缓",function() local action=A.Navigation:Current();if action and action.questId then A.Selection:Skip(action.questId) end end},
        {"详情",function() self:ToggleDetails() end},
        {"收起",function() self.folded=not self.folded;self:LayoutCard() end},
    }
    for i,spec in ipairs(actions) do
        local b=self:Button(T.tools,spec[1],60,spec[2]);b:SetPoint("TOPLEFT",(i-1)*72,0)
        b:SetBackdropColor(0,0,0,0);b.text:SetTextColor(unpack(palette.muted))
        if i==1 then T.pause=b elseif i==5 then self.fold=b end
    end
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
    row:SetWidth(302);row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});row:SetBackdropColor(0,0,0,0)
    row.group=text(row,11,palette.gold);row.group:SetPoint("TOPLEFT",0,-6);row.group:SetWidth(302)
    row.number=text(row,12,palette.muted);row.number:SetPoint("TOPLEFT",0,-8);row.number:SetWidth(24)
    row.number:SetJustifyH("RIGHT");row.number:SetMaxLines(1)
    row.title=text(row,12);row.title:SetPoint("TOPLEFT",32,-8);row.title:SetWidth(196)
    row.statusBack=row:CreateTexture(nil,"BACKGROUND");row.statusBack:SetPoint("TOPRIGHT",0,-5)
    row.status=text(row,10,palette.muted);row.status:SetPoint("TOPRIGHT",-2,-8)
    row.status:SetJustifyH("CENTER");row.status:SetWidth(64);row.status:SetMaxLines(1)
    row.progress=text(row,10,palette.muted);row.progress:SetPoint("TOPLEFT",32,-27);row.progress:SetWidth(270)
    row:SetScript("OnEnter",function() row:SetBackdropColor(0.15,0.23,0.27,0.35) end)
    row:SetScript("OnLeave",function() row:SetBackdropColor(0,0,0,0) end)
    row:SetScript("OnClick",function()
        local ok,why=A.Selection:Lock(row.candidate,row.revision)
        if not ok then A:Message(why) end
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
    T.model=model
    local map=state.position and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(state.position.map)
    T.zone:SetText(map and map.name or "AiLeveling")
    local ratio=state.maxXP and state.maxXP>0 and math.max(0,math.min(1,(state.xp or 0)/state.maxXP)) or 0
    T.experience:SetText(string.format("%d 级  ·  %.0f%%",state.level or 1,ratio*100))
    T.xpFill:SetWidth(math.max(1,360*ratio));T.xpFill:SetShown(ratio>0)
    local r,g,b=self:Accent();T.xpFill:SetColorTexture(r,g,b,0.70);T.rail:SetColorTexture(r,g,b,0.90)
    local serviceLabel=action and action.kind=="service" and ({train="训练",bind="设置炉石"})[action.serviceKind]
    T.step:SetText(A.char.paused and "已暂停" or serviceLabel or (verbs[model.kind] or "当前步骤"))
    T.pause.text:SetText(A.char.paused and "继续" or "暂停")
    self.title:SetText(model.title)
    local lines={model.instruction}
    if model.destination then lines[#lines+1]=model.destination end
    if model.hint and not A.char.paused then lines[#lines+1]="|cff84969f"..model.hint.."|r" end
    if plan.selectionBlocked then lines[#lines+1]=plan.selectionBlocked end
    if plan.lockedBlocked and not plan.unverified then lines[#lines+1]=plan.lockedBlocked end
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
        if action.moneyCost then lines[#lines+1]="预留费用 "..action.moneyCost.." 铜" end
        if action.moneyGain then lines[#lines+1]="预计收入 "..action.moneyGain.." 铜" end
        if A.Merchant then for _,line in ipairs(A.Merchant.Lines(action,state)) do lines[#lines+1]=line end end
    end
    self.body:SetText(table.concat(lines,"\n"))
    for i,objective in ipairs(model.objectives) do
        local row=T.objectives[i]
        if not row then
            row=CreateFrame("Frame",nil,T.currentChild);row:SetWidth(302)
            row.text=text(row,12);row.text:SetPoint("TOPLEFT");row.text:SetWidth(250)
            row.count=text(row,11,palette.muted);row.count:SetPoint("TOPRIGHT");row.count:SetJustifyH("RIGHT")
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
    for i,item in ipairs(model.rows) do
        local row=self:TrackerRow(i)
        row.group:SetText(item.groupTitle or "");row.group:SetShown(item.groupTitle~=nil)
        row.number:SetText(string.format("%02d",i+(model.includesCurrent and 0 or 1)));row.title:SetText(item.title)
        row.title:SetTextColor(unpack(item.deferred and palette.muted or palette.white))
        row.status:SetText(item.deferred and (item.accepted and "已接·暂缓" or "未接·暂缓") or item.status)
        local color=item.deferred and palette.muted or (item.accepted and palette.green or palette.gold)
        row.status:SetTextColor(unpack(color));row.statusBack:SetColorTexture(color[1],color[2],color[3],0.16)
        row.progress:SetText(item.progress)
        row.candidate,row.revision=item.candidate,plan.revision
        local can=A.Selection.CanChoose(item.candidate,plan.revision)
        row:SetEnabled(not item.deferred and can==true);row:Show()
    end
    for i=#model.rows+1,#T.rows do T.rows[i]:Hide() end
    T.queueLabel:SetText(string.format("%s  ·  已接取 %d  ·  未接取 %d",A.Navigation.manual and "任务列表" or "接下来",
        model.acceptedCount,model.unacceptedCount))
    self:LayoutTracker()
end

function UI:LayoutTracker()
    local T=self.tracker
    if not T then return end
    local scale=A.settings.fontScale or 1
    local titleHeight=math.max(22*scale,self.title:GetStringHeight())
    local top=36+titleHeight+10
    local textHeight=math.max(1,self.body:GetStringHeight())
    local childHeight=textHeight+12
    for i,objective in ipairs(T.model and T.model.objectives or {}) do
        local row=T.objectives[i]
        row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-childHeight)
        local height=math.max(16*scale,row.text:GetStringHeight())+12
        row:SetHeight(height)
        row.back:ClearAllPoints();row.back:SetPoint("BOTTOMLEFT",0,2);row.back:SetSize(302,2)
        row.fill:ClearAllPoints();row.fill:SetPoint("BOTTOMLEFT",0,2)
        row.fill:SetSize(math.max(1,302*(row.ratio or 0)),2);row.fill:SetColorTexture(self:Accent());row.fill:SetShown((row.ratio or 0)>0)
        childHeight=childHeight+height+6
    end
    local density=A.settings.density or "normal"
    local maximum=({compact=78,normal=160,expanded=270})[density]
    local height=math.min(childHeight,maximum*scale)
    local collapsed=self.folded or (self.inCombat and A.settings.combatFold)
    T.currentScroll:ClearAllPoints();T.currentScroll:SetPoint("TOPLEFT",16,-top)
    T.currentScroll:SetHeight(math.max(1,height));T.currentChild:SetHeight(childHeight)
    T.currentScroll:SetShown(not collapsed)
    T.card:SetHeight(top+(collapsed and 0 or height)+14)
    local queueTop=42+T.card:GetHeight()+20
    T.queueLabel:ClearAllPoints();T.queueLabel:SetPoint("TOPLEFT",2,-queueTop)
    T.queuePanel:ClearAllPoints();T.queuePanel:SetPoint("TOPLEFT",0,-queueTop-22)
    local queueHeight=0
    for i=1,#(T.model and T.model.rows or {}) do
        local row=T.rows[i]
        row.statusBack:SetSize(68,18*scale)
        local groupHeight=row.group:GetText()~="" and math.max(16*scale,row.group:GetStringHeight())+12 or 0
        row.number:ClearAllPoints();row.number:SetPoint("TOPLEFT",0,-8-groupHeight)
        row.title:ClearAllPoints();row.title:SetPoint("TOPLEFT",32,-8-groupHeight)
        row.status:ClearAllPoints();row.status:SetPoint("TOPRIGHT",-2,-8-groupHeight)
        row.statusBack:ClearAllPoints();row.statusBack:SetPoint("TOPRIGHT",0,-5-groupHeight)
        local title=math.max(16*scale,row.title:GetStringHeight())
        local progress=row.progress:GetText()~="" and math.max(15*scale,row.progress:GetStringHeight()) or 0
        row.progress:ClearAllPoints();row.progress:SetPoint("TOPLEFT",32,-title-10-groupHeight)
        local rowHeight=groupHeight+title+progress+18
        row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-queueHeight);row:SetHeight(rowHeight)
        queueHeight=queueHeight+rowHeight
    end
    T.queueChild:SetHeight(math.max(1,queueHeight))
    local visible=math.min(queueHeight,({compact=88,normal=220,expanded=330})[density]*scale)
    T.queueScroll:SetHeight(math.max(1,visible));T.queueScroll:SetShown(not collapsed and queueHeight>0)
    T.queuePanel:SetHeight(visible+24);T.queuePanel:SetShown(not collapsed and queueHeight>0)
    T.queueLabel:SetShown(not collapsed and queueHeight>0)
    local bottom=collapsed and (42+T.card:GetHeight()+10) or queueTop+(queueHeight>0 and 46+visible or 0)+8
    T.tools:ClearAllPoints();T.tools:SetPoint("TOPLEFT",0,-bottom)
    self.frame:SetHeight(bottom+28)
    self.fold.text:SetText(self.folded and "展开" or "收起")
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
