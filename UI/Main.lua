local _, A = ...
A.UI = {fonts={}}
local UI = A.UI
UI.colors={
    bg={0.07,0.085,0.14,0.96}, sidebar={0.05,0.065,0.11,0.94},
    panel={0,0,0,0}, button={0.13,0.15,0.21,0.90},
    hover={0.20,0.24,0.32,0.96}, selected={0.17,0.20,0.28,0.90},
    rowHover={0.50,0.60,0.85,0.14}, hud={0.07,0.085,0.14,0.40},
    white={0.96,0.97,0.99}, muted={0.70,0.73,0.80},
    gold={0.90,0.73,0.40}, green={0.42,0.85,0.60}, blue={0.58,0.79,1}, purple={0.78,0.68,1},
    red={0.95,0.61,0.61}, line={0.65,0.70,0.82,0.18}, border={0.50,0.55,0.65,0.25},
    gearShade={0.90,0.73,0.40,0.10}, gearText={0.765,0.793,0.868},
}
local colors=UI.colors
colors.accent=colors.gold
colors.accept=colors.blue;colors.objective=colors.gold;colors.turnin=colors.green
UI.hex={}
for name,color in pairs(colors) do
    UI.hex[name]=string.format("%02x%02x%02x",math.floor(color[1]*255+0.5),math.floor(color[2]*255+0.5),math.floor(color[3]*255+0.5))
end
UI.fontSizes={caption=12,body=14,task=15,brand=18,title=20}
UI.metrics={tight=4,gap=8,padding=12,section=16,indent=24,icon=16,smallIcon=12,
    button=28,hit=24,scrollbar=16,radius=6,controlRadius=4}
local metrics=UI.metrics
local media="Interface\\AddOns\\AiLeveling\\Media\\"
function UI:Accent()
    local class=A.state and A.state.class
    if not class and UnitClass then local _,playerClass=UnitClass("player");class=playerClass end
    local color=RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r,color.g,color.b end
    return 1,1,1
end

function UI:RegisterFont(text,size,role,flags)
    size=type(size)=="string" and self.fontSizes[size] or size
    self.fonts[#self.fonts+1]={text=text,size=size,role=role,flags=flags}
    text:SetFont(STANDARD_TEXT_FONT,size*(A.settings.fontScale or 1),flags or "")
end

function UI:Icon(name,size)
    size=math.floor((size or metrics.icon)*(A.settings.fontScale or 1)+0.5)
    return "|T"..media..name..".tga:"..size..":"..size..":0:0|t"
end

function UI:Rounded(frame,radius,border)
    frame.surface={}
    local function texture()
        local t=frame:CreateTexture(nil,"BACKGROUND",nil,-7)
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        frame.surface[#frame.surface+1]=t
        return t
    end
    for _,corner in ipairs({{"TOPLEFT",0,1,0,1},{"TOPRIGHT",1,0,0,1},
        {"BOTTOMLEFT",0,1,1,0},{"BOTTOMRIGHT",1,0,1,0}}) do
        local t=texture();t:SetSize(radius,radius);t:SetPoint(corner[1])
        t:SetTexture(media.."corner.tga");t:SetTexCoord(unpack(corner,2))
    end
    local center=texture();center:SetPoint("TOPLEFT",radius,0);center:SetPoint("BOTTOMRIGHT",-radius,0)
    local left=texture();left:SetPoint("TOPLEFT",0,-radius);left:SetPoint("BOTTOMRIGHT",frame,"BOTTOMLEFT",radius,radius)
    local right=texture();right:SetPoint("TOPLEFT",frame,"TOPRIGHT",-radius,-radius);right:SetPoint("BOTTOMRIGHT",0,radius)
    local material=frame:CreateTexture(nil,"BACKGROUND",nil,-6)
    material:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
    material:SetHorizTile(true);material:SetVertTile(true)
    material:SetPoint("TOPLEFT",radius/2,-radius/2);material:SetPoint("BOTTOMRIGHT",-radius/2,radius/2)
    frame.material=material
    local trim={}
    if border then
        local function edge()
            local t=frame:CreateTexture(nil,"BACKGROUND",nil,-5)
            t:SetTexture("Interface\\Buttons\\WHITE8X8");trim[#trim+1]=t;return t
        end
        for _,corner in ipairs({{"TOPLEFT",0,1,0,1},{"TOPRIGHT",1,0,0,1},
            {"BOTTOMLEFT",0,1,1,0},{"BOTTOMRIGHT",1,0,1,0}}) do
            local t=edge();t:SetSize(radius,radius);t:SetPoint(corner[1])
            t:SetTexture(media.."rim.tga");t:SetTexCoord(unpack(corner,2))
        end
        for _,side in ipairs({{"TOPLEFT","TOPRIGHT",radius,0,-radius,0},
            {"BOTTOMLEFT","BOTTOMRIGHT",radius,0,-radius,0}}) do
            local t=edge();t:SetPoint(side[1],side[3],side[4]);t:SetPoint(side[2],side[5],side[6]);t:SetHeight(2)
            t:SetTexture("Interface\\FrameGeneral\\UIFrameSimpleMetal");t:SetTexCoord(0,1,4/256,9/256)
        end
        for _,side in ipairs({{"TOPLEFT","BOTTOMLEFT"},{"TOPRIGHT","BOTTOMRIGHT"}}) do
            local t=edge();t:SetPoint(side[1],0,-radius);t:SetPoint(side[2],0,radius);t:SetWidth(2)
            t:SetTexture("Interface\\FrameGeneral\\UIFrameSimpleMetalVertical");t:SetTexCoord(4/128,9/128,0,1)
        end
    end
    frame.SetBackdropColor=function(self,...)
        for _,t in ipairs(self.surface) do t:SetVertexColor(...) end
        local _,_,_,alpha=...
        material:SetVertexColor(0.65,0.70,0.82,(alpha or 1)*0.12)
        if border then
            for _,t in ipairs(trim) do t:SetVertexColor(border[1],border[2],border[3],(alpha or 1)*border[4]) end
        end
    end
end

function UI:Panel(name, parent, width, height)
    local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    self:Rounded(f,metrics.radius,colors.border)
    f:SetBackdropColor(unpack(colors.bg))
    return f
end

function UI:Text(parent, size, color, flags)
    local text = parent:CreateFontString(nil, "OVERLAY")
    self:RegisterFont(text,size,color=="accent" and "accent" or nil,flags)
    if color=="accent" then text:SetTextColor(self:Accent()) else text:SetTextColor(unpack(color or colors.white)) end
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    return text
end

function UI:Button(parent, label, width, callback, fontSize)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width,metrics.button)
    self:Rounded(b,metrics.controlRadius,colors.border)
    b:SetBackdropColor(unpack(colors.button))
    b.highlight=b:CreateTexture(nil,"BACKGROUND",nil,-4)
    b.highlight:SetAllPoints();b.highlight:SetTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    b.highlight:SetTexCoord(0,0.625,0,0.6875);b.highlight:SetVertexColor(unpack(colors.rowHover))
    b:SetHighlightTexture(b.highlight,"ADD")
    b.text = self:Text(b, fontSize or "caption")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnClick", callback)
    b:SetScript("OnEnter", function()
        b:SetBackdropColor(unpack(b.baseColor==colors.panel and colors.rowHover or colors.hover))
    end)
    b:SetScript("OnLeave", function()
        b:SetBackdropColor(unpack(b.baseColor or colors.button))
    end)
    return b
end

function UI:Movable(frame,key)
    frame:SetMovable(true);frame:EnableMouse(true);frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",function()
        if not A.settings.lockWindow then
            if key=="position" then A.settings.trackerDocked=false end
            frame:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop",function()
        frame:StopMovingOrSizing()
        local point,_,relative,x,y=frame:GetPoint()
        A.settings[key]={point,relative,x,y}
        if key=="position" and A.QuestAssist then A.QuestAssist:LayoutTarget() end
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
        title:SetPoint("TOPLEFT",16,-16);title:SetText("AILeveling 加载失败")
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
    self.details = self:Panel("AiLevelingDetails", UIParent, 1000, 600)
    self.details:SetPoint("CENTER")
    local p=A.settings.detailPosition
    if p then self.details:ClearAllPoints();self.details:SetPoint(p[1],UIParent,p[2],p[3],p[4]) end
    self:Movable(self.details,"detailPosition")
    self.details:SetFrameStrata("DIALOG")
    self.details:Hide()
    local close = self:Button(self.details, "×", 26, function() self.details:Hide() end,"title")
    close:SetPoint("TOPRIGHT", -14, -14)
    self.tabs = {}
    local side=CreateFrame("Frame",nil,self.details);side:SetSize(164,584)
    side:SetPoint("TOPLEFT",8,-8)
    self:Rounded(side,metrics.radius);side:SetBackdropColor(unpack(colors.sidebar))
    local divider=self.details:CreateTexture(nil,"BACKGROUND")
    divider:SetPoint("TOPLEFT",180,-14);divider:SetPoint("BOTTOMLEFT",180,14);divider:SetWidth(1)
    divider:SetColorTexture(unpack(colors.line))
    local header=self.details:CreateTexture(nil,"BACKGROUND")
    header:SetPoint("TOPLEFT",194,-74);header:SetPoint("TOPRIGHT",-22,-74);header:SetHeight(1)
    header:SetColorTexture(unpack(colors.line))
    self.detailMark=side:CreateTexture(nil,"ARTWORK")
    self.detailMark:SetTexture(media.."compass.tga");self.detailMark:SetSize(24,24);self.detailMark:SetPoint("TOPLEFT",12,-16)
    local brand=self:Text(side,"brand",colors.gold);brand:SetPoint("TOPLEFT",42,-18);brand:SetText("AILeveling")
    local subtitle=self:Text(side,"caption",colors.muted);subtitle:SetPoint("TOPLEFT",12,-50);subtitle:SetText("少跑路 · 多经验")
    local labels={"任务行程","任务链","装备","地下城","设置","数据","服务","专业任务","职业任务","练级区域","坐骑任务"}
    local icons={"compass","chain","gear","entry","settings","xp","accept","profession","class","location","mount"}
    for n,i in ipairs({1,10,9,8,11,4,3,2,7,5,6}) do
        local b=self:Button(side,self:Icon(icons[i],16).."  "..labels[i],148,function() self:SelectTab(i) end,"body")
        b:SetPoint("TOPLEFT",8,-84-(n-1)*40);b:SetHeight(30)
        b.text:ClearAllPoints();b.text:SetPoint("LEFT",10,0);b.text:SetJustifyH("LEFT")
        self.tabs[i]=b
    end
    self.detailHeading=self:Text(self.details,"title",colors.white)
    self.detailHeading:SetPoint("TOPLEFT",194,-22);self.detailHeading:SetText("任务行程")
    self.detailSubtitle=self:Text(self.details,"body",colors.muted)
    self.detailSubtitle:SetPoint("TOPLEFT",194,-54)
    self.scroll = CreateFrame("ScrollFrame", nil, self.details, "UIPanelScrollFrameTemplate")
    self.scroll:SetPoint("TOPLEFT", 18, -96); self.scroll:SetPoint("BOTTOMRIGHT", -36, 18)
    self.scrollChild = CreateFrame("Frame", nil, self.scroll)
    self.scrollChild:SetSize(560, 380); self.scroll:SetScrollChild(self.scrollChild)
    self.detailText = self:Text(self.scrollChild,"body", colors.white)
    self.detailText:SetPoint("TOPLEFT"); self.detailText:SetWidth(552)
    self.copyBox = CreateFrame("EditBox", nil, self.scrollChild)
    self.copyBox:SetPoint("TOPLEFT"); self.copyBox:SetSize(552, 380)
    self.copyBox:SetMultiLine(true); self.copyBox:SetAutoFocus(false)
    self.copyBox:SetFontObject(GameFontHighlight)
    self:RegisterFont(self.copyBox,"body")
    self.copyBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    self.copyBox:Hide()
    self.Settings:Create(self.details)
    self.Chains:Create(self.details)
    self.Services:Create(self.details)
    self.Browser:Create(self.details)
    self.selectedTab = 1
    self.inCombat=InCombatLockdown()
    self:ApplyStyle()
end

function UI:ApplyStyle()
    if not self.frame then return end
    self.frame:SetScale(A.settings.scale)
    self.frame:SetAlpha(1)
    self.details:SetScale(A.settings.scale)
    self.details:SetAlpha(A.settings.alpha)
    for _,entry in ipairs(self.fonts) do
        entry.text:SetFont(STANDARD_TEXT_FONT,entry.size*(A.settings.fontScale or 1),entry.flags or "")
        if entry.role=="accent" then entry.text:SetTextColor(self:Accent()) end
    end
    if self.accent then local r,g,b=self:Accent();self.accent:SetColorTexture(r,g,b,1) end
    if self.detailMark then self.detailMark:SetVertexColor(unpack(colors.accent)) end
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
    self.details:SetSize(1000,600)
    self.Browser.frame:Hide()
    self.scroll:SetPoint("BOTTOMRIGHT",-36,18);self.scrollChild:SetWidth(560)
    self.detailText:SetWidth(552)
    self.Chains.frame:Hide()
    self.Services.frame:Hide()
    self.scroll:SetPoint("TOPLEFT",194,-96)
    self.exporting = true
    self.detailText:SetText(text)
    local height = math.max(380, self.detailText:GetStringHeight() + 20)
    self.scrollChild:SetHeight(height)
    self.detailText:Hide()
    self.copyBox:SetHeight(height); self.copyBox:SetText(text); self.copyBox:Show()
    self.copyBox:SetFocus(); self.copyBox:HighlightText()
end

function UI:SelectTab(index,reuse)
    self.exporting = false
    self.copyBox:ClearFocus(); self.copyBox:Hide(); self.detailText:Show()
    if self.selectedTab~=index then self.scroll:SetVerticalScroll(0) end
    self.selectedTab = index
    local r,g,b=unpack(colors.accent)
    for i,tab in ipairs(self.tabs or {}) do
        tab.baseColor=i==index and colors.selected or {0,0,0,0}
        tab:SetBackdropColor(unpack(tab.baseColor))
        if i==index then tab.text:SetTextColor(r,g,b) else tab.text:SetTextColor(unpack(colors.muted)) end
    end
    local names={"任务行程","任务链","装备情况","地下城","设置","运行数据","附近服务","专业任务","职业任务","练级区域","坐骑任务"}
    self.detailHeading:SetText(names[index])
    self.detailSubtitle:SetText(({[1]="当前安排与可选任务",[3]="当前装备、背包提升与任务奖励",[4]="选择副本，查看等级和任务安排",
        [8]="按专业查看条件、奖励与前置",[9]="当前职业的任务与解锁奖励",[10]="比较适合当前等级的任务区域",[11]="坐骑奖励及其前置任务"})[index] or "")
    self.details:SetSize(1000,600)
    self.scroll:SetPoint("BOTTOMRIGHT",-36,18);self.scrollChild:SetWidth(750);self.detailText:SetWidth(742)
    self.Settings.frame:SetShown(index==5)
    self.Chains.frame:SetShown(index==2)
    self.Services.frame:SetShown(index==7)
    for _,panel in ipairs({self.Settings.frame,self.Chains.frame,self.Services.frame}) do
        panel:ClearAllPoints();panel:SetPoint("TOPLEFT",194,-94);panel:SetPoint("BOTTOMRIGHT",-18,18)
    end
    local browse=index==1 or index==3 or index==4 or index>=8
    self.Browser.frame:SetShown(browse)
    self.scroll:SetShown(not browse and index~=5 and index~=2)
    self.scroll:SetPoint("TOPLEFT",194,index==7 and -178 or -96)
    if browse then self.Browser:Refresh(index,reuse);return end
    if index == 5 then self.Settings:Refresh(); return end
    if index == 2 then self.Chains:Refresh();return end
    local lines={}
    if index==7 then self.Services:Refresh();lines=self.Services:Lines()
    else lines[1]=A:Diagnostics();lines[2]="运行 /ail audit 查看数据库覆盖情况。" end
    self.detailText:SetText(table.concat(lines, "\n\n"))
    self.scrollChild:SetHeight(math.max(380, self.detailText:GetStringHeight() + 20))
end

function UI:Combat(inCombat)
    self.inCombat=inCombat
    self:LayoutCard()
end

function UI:RefreshDetails()
    if self.details:IsShown() and self.selectedTab ~= 5 and not self.exporting then self:SelectTab(self.selectedTab,true) end
end

function UI.PurchaseText(purchase)
    if not purchase then return end
    local map=purchase.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(purchase.map)
    return "可购买 · "..(purchase.name or ("商人 #"..purchase.npcId))..(map and map.name and (" · "..map.name) or "")
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

function UI.QuestStatus(state,id,plan)
    local q=(state.quests or {})[id]
    if q then return q.ready and "可交付" or "已接取" end
    if plan and plan.revision and plan.revision~=state.revision and (state.completed or {})[id] then return "已交付" end
    return "未接取"
end

function UI:QuestClick(id,button)
    if type(id)~="number" or id<=0 or id%1~=0 then return end
    if button~="RightButton" and IsModifiedClick and IsModifiedClick("CHATLINK") then
        local link=GetQuestLink and GetQuestLink(id)
        if (not canaccessvalue or canaccessvalue(link)) and type(link)=="string" and link~="" and
            ChatFrameUtil and ChatFrameUtil.InsertLink and ChatFrameUtil.OpenChat then
            if not ChatFrameUtil.InsertLink(link) then ChatFrameUtil.OpenChat(link) end
        end
        return true
    end
    local index=C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
    if (not canaccessvalue or canaccessvalue(index)) and type(index)=="number" and index>0 and QuestMapFrame_OpenToQuestDetails then
        QuestMapFrame_OpenToQuestDetails(id)
    else
        for _,candidate in ipairs(self.Plan.Rows(A.plan)) do
            if candidate.questId==id then
                self.Plan.key=self.Plan.Key(candidate);self.Plan.message=nil
                self.scroll:SetVerticalScroll(0);self.details:Show();self:SelectTab(1)
                break
            end
        end
    end
    return true
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
        if choice.questId and not quests[choice.questId] and not pendingSeen[choice.questId] and UI.QuestStatus(state,choice.questId,plan)~="已交付" then
            pending[#pending+1]=choice;pendingSeen[choice.questId]=true
        end
    end
    if #ids==0 and #pending==0 then return {} end
    local ready=0
    for _,id in ipairs(ids) do if quests[id].ready then ready=ready+1 end end
    local lines={string.format("任务总览 · 已接取 %d 项 · 可交付 %d 项 · 未接取 %d 项",#ids,ready,#pending)}
    local action=A.Navigation and A.Navigation:Current()
    if A.Navigation and A.Navigation.StaleAction and A.Navigation.StaleAction(action,state,plan) then action=nil end
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
            local status=UI.QuestStatus(state,choice.questId,plan)
            if status~="已交付" then titles[#titles+1]="["..status.."] "..(choice.title or ("任务 #"..choice.questId)) end
        end
        if #titles>0 then lines[#lines+1]="建议顺序："..table.concat(titles," → ").."。" end
    end
    local shared=A.TaskGuide and A.TaskGuide.SharedObjectives and A.TaskGuide.SharedObjectives(action,plan.taskChoices,state)
    if not suspended and shared then
        local titles={}
        for _,objective in ipairs(shared) do
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
