local _, A = ...
A.UI = {fonts={}}
local UI = A.UI
local colors = { bg = {0.035, 0.05, 0.065, 0.96}, border = {0.13, 0.2, 0.24, 1} }
function UI:Accent()
    local class=A.state and A.state.class
    if not class and UnitClass then local _,playerClass=UnitClass("player");class=playerClass end
    local color=RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r,color.g,color.b end
    return 1,1,1
end

function UI:RegisterFont(text,size,role)
    self.fonts[#self.fonts+1]={text=text,size=size,role=role}
    text:SetFont(STANDARD_TEXT_FONT,size*(A.settings.fontScale or 1),"")
end

function UI:Panel(name, parent, width, height)
    local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    f:SetBackdropColor(unpack(colors.bg))
    f:SetBackdropBorderColor(unpack(colors.border))
    return f
end

function UI:Text(parent, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY")
    self:RegisterFont(text,size,color=="accent" and "accent" or nil)
    if color=="accent" then text:SetTextColor(self:Accent()) else text:SetTextColor(unpack(color or {0.86, 0.9, 0.93})) end
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    return text
end

function UI:Button(parent, label, width, callback)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 26)
    b:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
    b:SetBackdropColor(0.09, 0.14, 0.18, 1)
    b.text = self:Text(b, 12)
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnClick", callback)
    b:SetScript("OnEnter", function() local r,g,blue=UI:Accent();b:SetBackdropColor(r*0.35,g*0.35,blue*0.35,1) end)
    b:SetScript("OnLeave", function() b:SetBackdropColor(0.09, 0.14, 0.18, 1) end)
    return b
end

function UI:Movable(frame,key)
    frame:SetMovable(true);frame:EnableMouse(true);frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",function() if not A.settings.lockWindow then frame:StartMoving() end end)
    frame:SetScript("OnDragStop",function()
        frame:StopMovingOrSizing()
        local point,_,relative,x,y=frame:GetPoint()
        A.settings[key]={point,relative,x,y}
    end)
end

function UI:ShowStartupError(message)
    if self.frame then self.frame:Hide() end
    if self.details then self.details:Hide() end
    if self.navFrame then self.navFrame:Hide() end
    local f=self.startupPanel
    if not f then
        f=self:Panel("AiLevelingStartupError",UIParent,560,240)
        self.startupPanel=f
        f:SetPoint("CENTER");f:SetFrameStrata("DIALOG")
        -- Use native fonts directly, even if custom text creation caused the failure.
        local title=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
        title:SetPoint("TOPLEFT",16,-16);title:SetText("AiLeveling 加载失败")
        local close=CreateFrame("Button",nil,f,"UIPanelCloseButton")
        close:SetPoint("TOPRIGHT");close:SetScript("OnClick",function() f:Hide() end)
        f.copy=CreateFrame("EditBox",nil,f)
        f.copy:SetPoint("TOPLEFT",16,-52);f.copy:SetPoint("BOTTOMRIGHT",-16,16)
        f.copy:SetMultiLine(true);f.copy:SetAutoFocus(false);f.copy:SetFontObject(GameFontHighlight)
        f.copy:SetScript("OnEscapePressed",function(box) box:ClearFocus() end)
    end
    f.copy:SetText("版本："..A.version.."\n\n"..message.."\n\n请点击文字，Ctrl+A、Ctrl+C 复制报错反馈。\n关闭后可用 /ail 再次打开。")
    f:Show()
end

function UI:Create()
    self:CreateTracker()
    self.details = self:Panel("AiLevelingDetails", UIParent, 620, 520)
    self.details:SetPoint("CENTER")
    local p=A.settings.detailPosition
    if p then self.details:ClearAllPoints();self.details:SetPoint(p[1],UIParent,p[2],p[3],p[4]) end
    self:Movable(self.details,"detailPosition")
    self.details:SetFrameStrata("DIALOG")
    self.details:Hide()
    local close = self:Button(self.details, "关闭", 50, function() self.details:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -12)
    self.tabs = {}
    for i, label in ipairs({"行程", "任务链", "装备", "副本", "设置", "数据", "服务"}) do
        local b = self:Button(self.details, label, 72, function() self:SelectTab(i) end)
        b:SetPoint("TOPLEFT", 16 + (i - 1) * 78, -52)
        self.tabs[i] = b
    end
    local heading = self:Text(self.details, 20)
    heading:SetPoint("TOPLEFT", 18, -18); heading:SetText("规划与角色详情")
    self.scroll = CreateFrame("ScrollFrame", nil, self.details, "UIPanelScrollFrameTemplate")
    self.scroll:SetPoint("TOPLEFT", 18, -96); self.scroll:SetPoint("BOTTOMRIGHT", -36, 18)
    self.scrollChild = CreateFrame("Frame", nil, self.scroll)
    self.scrollChild:SetSize(560, 380); self.scroll:SetScrollChild(self.scrollChild)
    self.detailText = self:Text(self.scrollChild, 13)
    self.detailText:SetPoint("TOPLEFT"); self.detailText:SetWidth(552)
    self.copyBox = CreateFrame("EditBox", nil, self.scrollChild)
    self.copyBox:SetPoint("TOPLEFT"); self.copyBox:SetSize(552, 380)
    self.copyBox:SetMultiLine(true); self.copyBox:SetAutoFocus(false)
    self.copyBox:SetFontObject(GameFontHighlight)
    self:RegisterFont(self.copyBox,13)
    self.copyBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    self.copyBox:Hide()
    self.Settings:Create(self.details)
    self.Dungeon:Create(self.details)
    self.Gear:Create(self.details)
    self.Plan:Create(self.details)
    self.Chains:Create(self.details)
    self.Services:Create(self.details)
    self.selectedTab = 1
    self.inCombat=InCombatLockdown()
    self:ApplyStyle()
end

function UI:ApplyStyle()
    if not self.frame then return end
    self.frame:SetScale(A.settings.scale)
    self.frame:SetAlpha(A.settings.alpha)
    self.details:SetScale(A.settings.scale)
    self.details:SetAlpha(A.settings.alpha)
    for _,entry in ipairs(self.fonts) do
        entry.text:SetFont(STANDARD_TEXT_FONT,entry.size*(A.settings.fontScale or 1),"")
        if entry.role=="accent" then entry.text:SetTextColor(self:Accent()) end
    end
    if self.accent then local r,g,b=self:Accent();self.accent:SetColorTexture(r,g,b,1) end
    if A.settings.lockWindow then self.frame:StopMovingOrSizing();self.details:StopMovingOrSizing() end
    if self.navFrame then
        self.navFrame:SetScale(A.settings.scale);self.navFrame:SetAlpha(A.settings.alpha)
        if A.settings.lockWindow then self.navFrame:StopMovingOrSizing() end
    end
    self:LayoutCard()
end

function UI:LayoutCard()
    if self.tracker then self:LayoutTracker() end
end

function UI:ToggleDetails()
    self.details:SetShown(not self.details:IsShown())
    if self.details:IsShown() then self:SelectTab(self.selectedTab or 1) end
end

function UI:ShowText(text)
    self.details:Show(); self.Settings.frame:Hide(); self.scroll:Show()
    self.Dungeon.frame:Hide()
    self.Gear.frame:Hide()
    self.Plan.frame:Hide()
    self.Chains.frame:Hide()
    self.Services.frame:Hide()
    self.scroll:SetPoint("TOPLEFT",18,-96)
    self.exporting = true
    self.detailText:SetText(text)
    local height = math.max(380, self.detailText:GetStringHeight() + 20)
    self.scrollChild:SetHeight(height)
    self.detailText:Hide()
    self.copyBox:SetHeight(height); self.copyBox:SetText(text); self.copyBox:Show()
    self.copyBox:SetFocus(); self.copyBox:HighlightText()
end

function UI:SelectTab(index)
    self.exporting = false
    self.copyBox:ClearFocus(); self.copyBox:Hide(); self.detailText:Show()
    if self.selectedTab~=index then self.scroll:SetVerticalScroll(0) end
    self.selectedTab = index
    self.Settings.frame:SetShown(index == 5)
    self.scroll:SetShown(index ~= 5 and index ~= 2)
    self.Dungeon.frame:SetShown(index==4)
    self.Gear.frame:SetShown(index==3)
    self.Plan.frame:SetShown(index==1)
    self.Chains.frame:SetShown(index==2)
    self.Services.frame:SetShown(index==7)
    self.scroll:SetPoint("TOPLEFT",18,index==4 and -314 or (index==3 or index==1 or index==7) and -178 or -96)
    if index == 5 then self.Settings:Refresh(); return end
    if index == 2 then self.Chains:Refresh();return end
    local lines = {}
    if index == 1 then
        self.Plan:Refresh()
        lines=self.Plan:Lines()
    elseif index == 3 then
        lines=self.Gear:Lines()
    elseif index == 4 then
        self.Dungeon:Refresh()
        self.scroll:SetPoint("TOPLEFT",18,-self.Dungeon.bodyTop)
        lines=self.Dungeon:Lines()
    elseif index==7 then
        self.Services:Refresh();lines=self.Services:Lines()
    else lines[1] = A:Diagnostics(); lines[2] = "运行 /ail audit 生成当前安装数据库的实际覆盖盘点。" end
    self.detailText:SetText(table.concat(lines, "\n\n"))
    self.scrollChild:SetHeight(math.max(380, self.detailText:GetStringHeight() + 20))
end

function UI:Combat(inCombat)
    self.inCombat=inCombat
    self:LayoutCard()
end

function UI:RefreshDetails()
    if self.details:IsShown() and self.selectedTab ~= 5 and not self.exporting then self:SelectTab(self.selectedTab) end
end

function UI.ActionText(action,settings)
    local point=action.position
    if action.kind=="objective" and point and point.sourceKind=="vendor" then
        return "向"..(point.entityName or "商人").."购买"..(point.targetName or "任务物品").."。"
    end
    if action.kind=="transit" then
        if settings.transportHints==false then return "前往下一交通目的地" end
        return action.text or ({flight="与出发点飞行管理员交谈，手动选择目的地。",boat="在出发点等候并搭乘对应船只。",
            hearth="使用炉石返回当前绑定地点。"})[action.mode] or "按当前交通段的使用条件前往下一地点"
    end
    return action.text or ({move="前往下一目的地",accept="接取任务",objective="完成任务目标",turnin="交付任务"})[action.kind] or "继续当前行动"
end

function UI.QuestStatus(state,id)
    local q=(state.quests or {})[id]
    return q and (q.ready and "可交付" or "已接取") or "未接取"
end

function UI:TaskLines(compact)
    local state,plan=A.state or {},A.plan or {}
    local quests,ids,seen=state.quests or {},{},{}
    local function add(id)
        if quests[id] and not seen[id] then ids[#ids+1]=id;seen[id]=true end
    end
    for _,choice in ipairs(plan.taskOrder or plan.taskChoices or {}) do add(choice.questId) end
    local rest={}
    for id in pairs(quests) do if not seen[id] then rest[#rest+1]=id end end
    table.sort(rest);for _,id in ipairs(rest) do add(id) end
    local pending,pendingSeen={},{}
    for _,choice in ipairs(plan.taskChoices or {}) do
        if choice.questId and not quests[choice.questId] and not pendingSeen[choice.questId] then
            pending[#pending+1]=choice;pendingSeen[choice.questId]=true
        end
    end
    if #ids==0 and #pending==0 then return {} end
    local ready=0
    for _,id in ipairs(ids) do if quests[id].ready then ready=ready+1 end end
    local lines={string.format("任务总览 · 已接取 %d 项 · 可交付 %d 项 · 未接取 %d 项",#ids,ready,#pending)}
    local action=A.Navigation and A.Navigation:Current()
    local suspended=(A.char and A.char.paused) or (A.Navigation and A.Navigation.manual) or
        (A.Transport and A.Transport.InFlight and A.Transport:InFlight())
    local recommended=not suspended and action and quests[action.questId] and action.questId
    if recommended and ((state.skipped or {})[recommended] or (state.chainDeferred or {})[recommended]) then recommended=nil end
    if recommended then
        local reason
        if action.referenceFlight then reason="当前飞行点可达任务区域，先乘飞行再继续目标"
        elseif state.locked==recommended then reason="按你锁定的任务继续"
        elseif plan.best then reason="按当前完整行程顺序推进"
        elseif quests[recommended].ready then reason="当前建议先到此目标交付，并释放任务栏位"
        elseif action.position then reason="优先当前地图内较近的已接目标"
        elseif action.areaId then reason=UI.ActionText(action,A.settings or {}):gsub("。$","")
        else reason="继续当前任务目标" end
        lines[#lines+1]="建议先做："..(quests[recommended].title or action.title or ("任务 #"..recommended)).."；"..reason.."。"
    elseif plan.selectionBlocked then lines[#lines+1]="所选行程条件不足，先处理行程页列出的条件。"
    elseif action and action.kind=="service" then lines[#lines+1]="建议先处理当前补给服务，再继续任务。" end
    if not suspended and plan.taskOrder and #plan.taskOrder>1 then
        local titles={}
        for _,choice in ipairs(plan.taskOrder) do
            titles[#titles+1]="["..UI.QuestStatus(state,choice.questId).."] "..(choice.title or ("任务 #"..choice.questId))
        end
        lines[#lines+1]="建议顺序："..table.concat(titles," → ").."。"
    end
    if not suspended and action and action.sharedObjectives and #action.sharedObjectives>1 then
        local titles={}
        for _,objective in ipairs(action.sharedObjectives) do
            local q=quests[objective.questId]
            titles[#titles+1]=q and q.title or ("任务 #"..objective.questId)
        end
        lines[#lines+1]="可一起推进："..table.concat(titles,"、").."；当前行动共用同一目标。"
    end
    if #ids>0 then lines[#lines+1]="已接取任务 · 按当前日志推进" end
    for i,id in ipairs(ids) do
        local q=quests[id]
        local deferred=(state.skipped or {})[id] or (state.chainDeferred or {})[id]
        local label=UI.QuestStatus(state,id)..(deferred and "·暂缓" or "")
        lines[#lines+1]=string.format("%d. %s[%s] %s",i,id==recommended and "★ " or "",label,q.title or ("任务 #"..id))
        local counts={}
        for _,objective in ipairs(q.objectives or {}) do
            if compact then
                if objective.numRequired and objective.numRequired>0 then
                    counts[#counts+1]=string.format("%d/%d",objective.numFulfilled or 0,objective.numRequired)
                end
            elseif objective.text then lines[#lines+1]="  "..(objective.finished and "✓ " or "· ")..objective.text end
        end
        if #counts>0 then lines[#lines]=lines[#lines].." · "..table.concat(counts," / ") end
    end
    if #pending>0 then
        lines[#lines+1]="未接取任务 · 先到发布者处接取"
        for i,choice in ipairs(pending) do
            local deferred=(state.skipped or {})[choice.questId] or (state.chainDeferred or {})[choice.questId]
            lines[#lines+1]=string.format("%d. [未接取%s] %s",i,deferred and "·暂缓" or "",choice.title or ("任务 #"..choice.questId))
            lines[#lines+1]=choice.acceptBlocked and ("  "..choice.acceptBlocked) or choice.requireCheck and "  先向发布者确认任务是否开放，再接取。" or "  先接取，再推进任务目标。"
        end
    end
    if compact and recommended then
        for _,objective in ipairs(quests[recommended].objectives or {}) do
            if objective.text then lines[#lines+1]=(objective.finished and "✓ " or "· ")..objective.text end
        end
    end
    return lines
end

function UI:Render()
    self:RenderTracker()
    self:RefreshDetails()
end

function UI:SetNavigation(distance, angle, unverified)
    self:SetTrackerNavigation(distance,angle,unverified)
end
