local _, A = ...
A.UI = {fonts={},daylightFonts={},shells={}}
local UI = A.UI
local backgroundAlpha=0.40 -- 60% transparent
UI.colors={
    bg={0.078,0.094,0.145,backgroundAlpha},
    panel={0,0,0,0}, button={0.095,0.102,0.145,backgroundAlpha},
    primary={0.91,0.72,0.41,1}, primaryHover={1,0.82,0.52,1}, ink={0.085,0.075,0.10},
    hover={0.22,0.24,0.32,backgroundAlpha}, selected={0.19,0.22,0.30,backgroundAlpha},
    rowHover={0.31,0.36,0.49,backgroundAlpha}, hud={0.086,0.102,0.153,backgroundAlpha},
    navigation={0.086,0.102,0.153,backgroundAlpha},
    white={247/255,248/255,253/255}, muted={195/255,202/255,221/255},
    quest={1,0.84,0.45}, gold={0.96,0.78,0.43}, green={0.52,0.91,0.65}, blue={0.59,0.80,1}, purple={0.81,0.65,1},
    focus={0.40,0.69,0.96}, red={0.95,0.61,0.61},
    line={0.68,0.72,0.81,0.20}, border={0.55,0.59,0.69,0.28},
    gearText={0.765,0.793,0.868},
}
local colors=UI.colors
colors.place=colors.blue
UI.daylight=DaylightUI and DaylightUI.API and DaylightUI.API.major==1 and DaylightUI.API
colors.accent=colors.gold
colors.accept=colors.gold;colors.objective=colors.white;colors.turnin=colors.green
colors.collect=colors.purple
UI.hex={}
for name,color in pairs(colors) do
    UI.hex[name]=string.format("%02x%02x%02x",math.floor(color[1]*255+0.5),math.floor(color[2]*255+0.5),math.floor(color[3]*255+0.5))
end
function UI.QuestName(text,dimmed)
    return "|cff"..(dimmed and UI.hex.muted or UI.hex.quest)..text.."|r"
end

function UI.DungeonQuestColor(level,dimmed)
    if dimmed then return unpack(colors.muted) end
    local c=type(level)=="number" and level>0 and GetQuestDifficultyColor and GetQuestDifficultyColor(level)
    if c then return c.r,c.g,c.b end
    return unpack(colors.quest)
end

UI.fontSizes={caption=12,body=14,task=15,heading=18,brand=18,title=20}
local guideSizes={guideName=15,guideAction=14,guideBody=13,guideLabel=12,guideNote=11}
local detailRoles={title="guideName",heading="guideName",task="guideAction",body="guideBody",caption="guideLabel"}
local function inDetails(frame)
    if not UI.details then return false end
    while frame and frame~=UI.details do frame=frame:GetParent() end
    return frame~=nil
end
local daylightRoles={caption="small",body="body",task="body",heading="head",brand="title",title="title"}
UI.metrics={tight=4,gap=8,padding=12,section=16,indent=24,icon=16,smallIcon=12,
    guidePadding=14,guideIndent=25,detailInset=100,button=28,hit=24,scrollbar=16,radius=6,controlRadius=4}
local metrics=UI.metrics
local media="Interface\\AddOns\\AiLeveling\\Media\\"
function UI:ClassColor()
    local class=A.state and A.state.class
    if not class and UnitClass then local _,playerClass=UnitClass("player");class=playerClass end
    local color=RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r,color.g,color.b end
    return 1,1,1
end

function UI:Accent()
    if self.daylight then return self.daylight.Accent() end
    return self:ClassColor()
end

function UI:FontScale()
    return (A.settings.fontScale or 1)*(self.daylight and self.daylight.GetSetting("general","fontScale") or 1)
end

function UI:StyleFont(entry)
    local api=self.daylight
    local face,size,flags=STANDARD_TEXT_FONT,entry.size,entry.flags or ""
    if api then
        -- Untouched role samples follow Daylight's font, scale, outline and shadow updates.
        local sample=self.daylightFonts[entry.daylightRole]
        if not sample then
            sample=api.Text(self.details or self.frame or UIParent,entry.daylightRole);sample:Hide()
            self.daylightFonts[entry.daylightRole]=sample
        end
        face,size,flags=sample:GetFont()
        entry.text:SetShadowOffset(sample:GetShadowOffset())
        entry.text:SetShadowColor(sample:GetShadowColor())
    end
    if entry.guide then
        size=entry.size*(api and api.GetSetting("general","fontScale") or 1)
        flags=""
        if entry.text.SetSpacing then entry.text:SetSpacing(0) end
        entry.text:SetShadowOffset(1,-1)
        entry.text:SetShadowColor(0,0,0,0.6)
    elseif entry.flags=="OUTLINE" then
        size=math.max(size,(entry.size+2)*(api and api.GetSetting("general","fontScale") or 1))
        flags=entry.flags or ""
        entry.text:SetShadowOffset(1,-1)
        entry.text:SetShadowColor(0,0,0,1)
    end
    entry.text:SetFont(face,size*(A.settings.fontScale or 1),flags or "")
end

function UI:RegisterFont(text,size,role,flags)
    local daylightRole=daylightRoles[size] or (type(size)=="number" and size<=12 and "small" or "body")
    local guide=guideSizes[size] or (inDetails(text) and guideSizes[detailRoles[size]])
    size=guide or self.fontSizes[size] or size
    self.fonts[#self.fonts+1]={text=text,size=size,role=role,flags=flags,daylightRole=daylightRole,guide=guide}
    self:StyleFont(self.fonts[#self.fonts])
end

local objectiveIcons={item="collect",monster="objective",talkto="talk",object="interact",spell="spell",
    areaTrigger="location",areaTriggerEnter="location",reputation="reputation"}
local travelIcons={walk="location",move="location",approach="location",manual="location",zeppelin="boat",flight="flight",
    boat="boat",tram="tram",lift="location",passage="entry",teleport="entry",hearth="hearth",hearthCast="hearth",portal="entry",dungeonEnter="entry",dungeonLeave="entry",dungeonRun="entry"}

function UI.ObjectiveIcon(goal)
    if not goal then return end
    if goal.areaTriggerId and goal.areaTriggerId>0 then return "location" end
    local kind=goal.type or goal.objectiveType
    -- Some conversations are logged as monster or event credit. Only use
    -- the speech bubble when the objective itself calls for talking.
    local text=goal.text
    if type(text)=="string" and (kind=="monster" or kind=="event" or goal.targetKind=="npc" or goal.targetKind=="killcredit") and
        (text:match("^与.-交谈") or text:match("^和.-交谈") or text:match("^与.-对话") or text:match("^[Ss]peak to ") or text:match("^[Tt]alk to ")) then
        return "talk"
    end
    return objectiveIcons[kind] or objectiveIcons[goal.targetKind]
end

function UI.QuestIcon(kind,step,goals)
    if kind=="turnin" and step and step.kind=="turnin" then
        local quest=(A.state.quests or {})[step.questId]
        return quest and quest.ready and "turnin" or "pending"
    end
    if kind=="accept" or kind=="turnin" then return kind end
    if kind~="objective" then return travelIcons[kind] or step and travelIcons[step.mode] or "compass" end
    if step and step.kind=="objective" then
        local quest=(A.state.quests or {})[step.questId]
        local selected=quest and (quest.objectives or {})[step.objectiveIndex]
        if not (selected and (selected.finished or selected.done)) then
            local icon=step.areaTriggerId and step.areaTriggerId>0 and "location" or UI.ObjectiveIcon(selected) or UI.ObjectiveIcon(step) or UI.ObjectiveIcon(step.position)
            if icon then return icon end
        end
    end
    for _,goal in ipairs(goals or {}) do
        if not (goal.finished or goal.done) then return UI.ObjectiveIcon(goal) or "target" end
    end
    return "target"
end

function UI.IconTexture(name)
    return media..name..".tga"
end

function UI:Icon(name,size)
    size=math.floor((size or metrics.icon)*self:FontScale()+0.5)
    return "|T"..UI.IconTexture(name)..":"..size..":"..size..":0:0|t"
end

local function roundedFill(frame,radius)
    local surface={}
    local function texture()
        local t=frame:CreateTexture(nil,"BACKGROUND",nil,-7)
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        surface[#surface+1]=t
        return t
    end
    for _,corner in ipairs({{"TOPLEFT",0,1,0,1},{"TOPRIGHT",1,0,0,1},
        {"BOTTOMLEFT",0,1,1,0},{"BOTTOMRIGHT",1,0,1,0}}) do
        local t=texture();t:SetSize(radius,radius);t:SetPoint(corner[1])
        t:SetTexture(media.."corner.tga");t:SetTexCoord(unpack(corner,2))
        surface[corner[1]]=t
    end
    local center=texture();center:SetPoint("TOPLEFT",radius,0);center:SetPoint("BOTTOMRIGHT",-radius,0)
    local left=texture();left:SetPoint("TOPLEFT",0,-radius);left:SetPoint("BOTTOMRIGHT",frame,"BOTTOMLEFT",radius,radius)
    local right=texture();right:SetPoint("TOPLEFT",frame,"TOPRIGHT",-radius,-radius);right:SetPoint("BOTTOMRIGHT",0,radius)
    return surface
end

local function tintFill(surface,...)
    for _,t in ipairs(surface) do t:SetVertexColor(...) end
end

function UI:Rounded(frame,radius,border)
    if self.daylight then
        if border then self:DaylightShell(frame,0) end
        local fill=frame:CreateTexture(nil,"BACKGROUND",nil,-6);fill:SetAllPoints()
        frame.SetBackdropColor=function(_,r,g,b,alpha)
            fill:SetColorTexture(r,g,b,alpha or 1)
        end
        return
    end
    frame.surface=roundedFill(frame,radius)
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
        tintFill(self.surface,...)
        local _,_,_,alpha=...
        material:SetVertexColor(0.65,0.70,0.82,(alpha or 1)*0.12)
        if border then
            for _,t in ipairs(trim) do t:SetVertexColor(border[1],border[2],border[3],(alpha or 1)*border[4]) end
        end
    end
end

local backgroundTints={charcoal={0.035,0.035,0.035},navy={0.035,0.075,0.14},brown={0.12,0.075,0.045}}
local function background(key)
    local settings=A.settings or {}
    local percent=settings[key] or A.defaults[key]
    return backgroundTints[settings.backgroundStyle],(100-percent)/100
end

function UI:BindBackground(frame,base,key,setColor)
    setColor=setColor or frame.SetBackdropColor
    local function paint()
        local tint,alpha=background(key)
        local rgb=tint or base
        setColor(frame,rgb[1],rgb[2],rgb[3],alpha)
    end
    self.shells[#self.shells+1]={key=key,refresh=paint}
    paint()
end

function UI:PanelBackground(frame,base,key)
    local fill=roundedFill(frame,metrics.radius)
    self:BindBackground(fill,base,key,tintFill)
    return fill
end

function UI:DaylightShell(frame,alpha,windowColor,key)
    local api=self.daylight
    if not api then return end
    local opts=alpha and {panel=true,bgAlpha=alpha} or {window=true,bgAlpha=(windowColor or colors.bg)[4],bgColor=windowColor}
    local function paint()
        if key then
            local tint,opacity=background(key)
            opts.bgColor,opts.bgAlpha=tint or windowColor,opacity
        end
        api.Skin(frame,opts)
    end
    self.shells[#self.shells+1]={key=key,refresh=paint}
    paint()
    frame:HookScript("OnSizeChanged",paint)
end

function UI:Panel(name, parent, width, height,background,key)
    local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    if self.daylight then self:PanelBackground(f,background or colors.bg,key or "detailTransparency")
    else
        self:Rounded(f,metrics.radius,colors.border)
        local base=background or colors.bg
        if key then self:BindBackground(f,base,key) else f:SetBackdropColor(unpack(base)) end
    end
    return f
end

function UI:Text(parent, size, color, flags)
    local text = self.daylight and self.daylight.Text(parent,daylightRoles[size] or "small") or parent:CreateFontString(nil, "OVERLAY")
    self:RegisterFont(text,size,color=="accent" and "accent" or nil,flags)
    if color=="accent" then text:SetTextColor(self:Accent()) else text:SetTextColor(unpack(color or colors.white)) end
    self.fonts[#self.fonts].color=color~="accent" and (color or colors.white) or nil
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    return text
end

-- Keep the native label, focus ring and input handlers above a single local fill.
local function daylightControlFill(frame)
    frame:DisableDrawLayer("BACKGROUND")
    local fill=frame:CreateTexture(nil,"BORDER",nil,-8);fill:SetAllPoints()
    return fill
end

function UI:Input(parent,opts,color)
    color=color or colors.button
    if self.daylight then
        local input=self.daylight.Input(parent,opts)
        daylightControlFill(input):SetColorTexture(unpack(color))
        return input
    end
    local input=CreateFrame("EditBox",nil,parent,"BackdropTemplate")
    self:Rounded(input,metrics.controlRadius,colors.border)
    input:SetBackdropColor(unpack(color))
    local inset=opts.search and 10 or 6
    input:SetTextInsets(inset,inset,0,0)
    if opts.numeric then input:SetNumeric(true) end
    return input
end

function UI:Button(parent, label, width, callback, fontSize)
    if inDetails(parent) then
        local button=self:ListButton(parent,label,width,callback,fontSize or "guideLabel")
        button.baseColor=colors.button
        button:SetBackdropColor(unpack(button.baseColor))
        return button
    end
    if self.daylight then
        local b=self.daylight.Button(parent,label,metrics.button)
        b:SetWidth(width);b:SetScript("OnClick",callback)
        self:RegisterFont(b.text,fontSize or "caption")
        local fill=daylightControlFill(b)
        b.SetBackdropColor=function(_,...) fill:SetColorTexture(...) end
        b:SetBackdropColor(unpack(colors.button))
        b:HookScript("OnEnter",function()
            local base=b.baseColor or colors.button
            b:SetBackdropColor(unpack(base==colors.primary and colors.primaryHover or base[4]==0 and colors.rowHover or colors.hover))
        end)
        b:HookScript("OnLeave",function() b:SetBackdropColor(unpack(b.baseColor or colors.button)) end)
        return b
    end
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
        b:SetBackdropColor(unpack(b.baseColor==colors.primary and colors.primaryHover or b.baseColor==colors.panel and colors.rowHover or colors.hover))
    end)
    b:SetScript("OnLeave", function()
        b:SetBackdropColor(unpack(b.baseColor or colors.button))
    end)
    return b
end

-- Flat list, sidebar and link controls share the same hover and selection surface.
function UI:ListButton(parent,label,width,callback,role)
    local b=CreateFrame("Button",nil,parent)
    b:SetSize(width,metrics.button)
    local fill=b:CreateTexture(nil,"BACKGROUND");fill:SetAllPoints()
    b.SetBackdropColor=function(_,...) fill:SetColorTexture(...) end
    b.baseColor=colors.panel;b:SetBackdropColor(unpack(colors.panel))
    b.text=self:Text(b,role or "body");b.text:SetPoint("CENTER");b.text:SetText(label)
    b:SetScript("OnClick",callback)
    b:SetScript("OnEnter",function() b:SetBackdropColor(unpack(b.baseColor==colors.primary and colors.primaryHover or colors.rowHover)) end)
    b:SetScript("OnLeave",function() b:SetBackdropColor(unpack(b.baseColor)) end)
    return b
end

function UI:MarkChoice(button,active)
    button.baseColor=active and colors.selected or colors.panel
    button:SetBackdropColor(unpack(button.baseColor))
    button.text:SetTextColor(unpack(active and colors.gold or colors.muted))
end

function UI:Movable(handle,key,frame,button)
    frame=frame or handle
    frame:SetMovable(true);handle:EnableMouse(true);handle:RegisterForDrag(button or "LeftButton")
    handle:SetScript("OnDragStart",function()
        if not A.settings.lockWindow and (frame~=self.navAnchor or not InCombatLockdown()) then
            if key=="position" then A.settings.trackerDocked=false end
            if frame==self.navAnchor then self.navDragging=true end
            frame:StartMoving()
        end
    end)
    handle:SetScript("OnDragStop",function()
        if frame==self.navAnchor then
            if InCombatLockdown() then return end
            self.navDragging=nil
        end
        frame:StopMovingOrSizing()
        local point,_,relative,x,y=frame:GetPoint()
        A.settings[key]={point,relative,x,y}
        if key=="position" and A.QuestAssist then A.QuestAssist:LayoutTarget() end
    end)
end

function UI:ClampNavigation()
    if not self.navFrame or InCombatLockdown() then return end
    local list=A.QuestAssist and A.QuestAssist.targetList
    local top=self.navFrame:IsShown() and math.max(0,self.navFrame:GetHeight()-self.navAnchor:GetHeight()) or 0
    local bottom=list and list:IsShown() and list:GetHeight() or 0
    self.navAnchor:SetClampRectInsets(0,0,top,-bottom)
end

function UI:PlaceNavigation(restore)
    local anchor=self.navAnchor
    if not anchor then return end
    if restore then self.restoreNavPosition=true end
    if InCombatLockdown() then return end
    if self.navDragging and (self.restoreNavPosition or A.settings.lockWindow or self.navDragDeferred) then
        anchor:StopMovingOrSizing();self.navDragging=nil
        if not self.restoreNavPosition then
            local point,_,relative,x,y=anchor:GetPoint();A.settings.navigationPosition={point,relative,x,y}
        end
    end
    self.navDragDeferred=nil
    anchor:SetScale(A.settings.scale);anchor:SetWidth(268*self:FontScale())
    local list=A.QuestAssist and A.QuestAssist.targetList
    if list then A.QuestAssist:LayoutTargetList(list.mark) end
    self:ClampNavigation()
    if self.restoreNavPosition then
        self.restoreNavPosition=nil
        anchor:ClearAllPoints()
        local p=A.settings.navigationPosition
        if p then anchor:SetPoint(p[1],UIParent,p[2],p[3],p[4])
        else anchor:SetPoint("CENTER",UIParent,"CENTER",0,-110) end
    end
end

function UI:Menu(owner,build)
    if not self.daylight then return MenuUtil.CreateContextMenu(owner,build) end
    local entries={}
    build(owner,{CreateButton=function(_,label,callback)
        local entry={label=label,callback=callback,enabled=true}
        function entry:SetEnabled(enabled) self.enabled=enabled end
        entries[#entries+1]=entry;return entry
    end})
    local keys,labels={},{}
    for i,entry in ipairs(entries) do
        if entry.enabled then keys[#keys+1]=i;labels[i]=entry.label end
    end
    self.daylight.Menu(owner,keys,labels,nil,function(key) entries[key].callback() end,220,{atCursor=true})
end

function UI:ShowStartupError(message)
    if self.frame then self.frame:Hide() end
    if self.details then self.details:Hide() end
    if self.navFrame then self.navFrame:Hide() end
    local f=self.startupPanel
    if not f then
        f=self:Panel("AiLevelingStartupError",UIParent,560,240,nil,"detailTransparency")
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
    self.details=CreateFrame("Frame","AiLevelingDetails",UIParent)
    self.details:SetSize(1000,600)
    self.detailBackground=self:PanelBackground(self.details,colors.hud,"detailTransparency")
    self.details:SetPoint("CENTER")
    local p=A.settings.detailPosition
    if p then self.details:ClearAllPoints();self.details:SetPoint(p[1],UIParent,p[2],p[3],p[4]) end
    self:Movable(self.details,"detailPosition")
    self.details:SetFrameStrata("DIALOG")
    self.details:Hide()
    local close=self:ListButton(self.details,"×",26,function() self.details:Hide() end,"guideName")
    close:SetPoint("TOPRIGHT",-metrics.guidePadding,-metrics.guidePadding)
    self.tabs = {}
    local side=CreateFrame("Frame",nil,self.details);side:SetSize(76,584)
    side:SetPoint("TOPLEFT",8,-8)
    local divider=self.details:CreateTexture(nil,"BACKGROUND")
    divider:SetPoint("TOPLEFT",88,-14);divider:SetPoint("BOTTOMLEFT",88,14);divider:SetWidth(1)
    divider:SetColorTexture(unpack(colors.line))
    self.detailMark=side:CreateTexture(nil,"ARTWORK")
    self.detailMark:SetTexture(media.."compass.tga");self.detailMark:SetSize(26,26);self.detailMark:SetPoint("TOP",0,-10)
    local labels={"练级任务","任务链","装备","地下城","设置","数据","服务","专业任务","职业任务","练级区域","坐骑任务"}
    local icons={"compass","chain","gear","entry","settings","xp","talk","profession","class","location","mount"}
    for n,i in ipairs({1,9,10,8,11,4,3,2,7,5,6}) do
        local b=self:ListButton(side,labels[i],76,function() self:SelectTab(i) end,"caption")
        b:SetPoint("TOPLEFT",0,-44-(n-1)*47);b:SetHeight(46)
        b.icon=self:Text(b,"body");b.icon:SetPoint("TOP",0,-3)
        b.icon:SetText(self:Icon(icons[i],14))
        b.text:ClearAllPoints();b.text:SetPoint("TOP",b.icon,"BOTTOM",0,-2)
        self.tabs[i]=b
    end
    self.tabMark=side:CreateTexture(nil,"ARTWORK");self.tabMark:SetWidth(2)
    self.detailHeading=self:Text(self.details,"title",colors.white)
    self.detailHeading:SetPoint("TOPLEFT",metrics.detailInset,-metrics.guidePadding);self.detailHeading:SetText("练级任务")
    self.detailRule=self.details:CreateTexture(nil,"ARTWORK")
    self.detailRule:SetPoint("TOPLEFT",self.detailHeading,"BOTTOMLEFT",0,-metrics.tight)
    self.detailRule:SetHeight(1);self.detailRule:SetColorTexture(unpack(colors.line))
    local underline=self.details:CreateTexture(nil,"ARTWORK",nil,1)
    underline:SetPoint("LEFT",self.detailRule,"LEFT");underline:SetSize(42,2);underline:SetColorTexture(unpack(colors.gold))
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
    if self.daylight then
        local function refresh()
            self:ApplyStyle();self:RenderTracker()
            if self.exporting then self:SizeReport()
            elseif self.details:IsShown() then self:SelectTab(self.selectedTab or 1,true) end
        end
        self.daylight.On("StyleChanged",refresh,"AiLeveling")
        self.daylight.On("Login",refresh,"AiLeveling")
    end
end

function UI:ApplyBackgrounds(key)
    for _,shell in ipairs(self.shells) do
        if not key or shell.key==key then shell.refresh() end
    end
end

function UI:ApplyStyle()
    if not self.frame then return end
    self:ApplyBackgrounds()
    self.frame:SetScale(A.settings.scale)
    self.frame:SetAlpha(1)
    self.details:SetScale(A.settings.scale)
    self.details:SetAlpha(1)
    for _,entry in ipairs(self.fonts) do
        self:StyleFont(entry)
        if entry.role=="accent" then entry.text:SetTextColor(self:Accent())
        elseif entry.color then entry.text:SetTextColor(unpack(entry.color)) end
    end
    if self.accent then local r,g,b=self:Accent();self.accent:SetColorTexture(r,g,b,1) end
    if self.detailMark then self.detailMark:SetVertexColor(unpack(colors.accent)) end
    if A.settings.lockWindow then self.frame:StopMovingOrSizing();self.details:StopMovingOrSizing() end
    if self.navFrame then
        self.tracker.navScale=nil
        self:PlaceNavigation()
        self.tracker.navBearing:SetAlpha(A.settings.alpha)
        self.nav:SetAlpha(A.settings.alpha)
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

function UI:SizeReport()
    local width=1000-metrics.detailInset-40
    self.scrollChild:SetWidth(width);self.detailText:SetWidth(width);self.copyBox:SetWidth(width)
    local height=math.max(380,self.detailText:GetStringHeight()+20)
    self.scrollChild:SetHeight(height);self.copyBox:SetHeight(height)
end

function UI:ShowText(text,heading)
    self.details:Show(); self.Settings.frame:Hide(); self.scroll:Show()
    self.details:SetSize(1000,600)
    self.Browser.frame:Hide()
    self.scroll:SetPoint("BOTTOMRIGHT",-36,18)
    self.detailHeading:SetText(heading or "报告");self.detailRule:SetWidth(self.details:GetWidth()-metrics.detailInset-2*metrics.guidePadding)
    self.Chains.frame:Hide()
    self.Services.frame:Hide()
    self.scroll:SetPoint("TOPLEFT",self.detailRule,"BOTTOMLEFT",0,-metrics.guidePadding)
    self.exporting = true
    self.detailText:SetText(text)
    self:SizeReport();self.detailText:Hide()
    self.copyBox:SetText(text);self.copyBox:Show()
    self.copyBox:SetFocus();self.copyBox:HighlightText();self.scroll:SetVerticalScroll(0)
end

function UI:SelectTab(index,reuse)
    self.exporting = false
    self.copyBox:ClearFocus(); self.copyBox:Hide(); self.detailText:Show()
    if self.selectedTab~=index then self.Browser:ClearSearch();self.scroll:SetVerticalScroll(0) end
    self.selectedTab = index
    local r,g,b=unpack(colors.accent)
    for i,tab in ipairs(self.tabs or {}) do
        tab.baseColor=i==index and colors.selected or {0,0,0,0}
        tab:SetBackdropColor(unpack(tab.baseColor))
        if i==index then tab.text:SetTextColor(r,g,b) else tab.text:SetTextColor(unpack(colors.muted)) end
    end
    local selected=self.tabs[index]
    self.tabMark:ClearAllPoints();self.tabMark:SetPoint("TOPLEFT",selected,"TOPLEFT");self.tabMark:SetPoint("BOTTOMLEFT",selected,"BOTTOMLEFT")
    self.tabMark:SetColorTexture(unpack(colors.gold))
    local names={"练级任务","任务链","装备情况","地下城","设置","运行数据","附近服务","专业任务","职业任务","练级区域","坐骑任务"}
    self.detailHeading:SetText(names[index])
    local browse=index==1 or index==3 or index==4 or index>=8
    self.detailRule:SetWidth(self.details:GetWidth()-metrics.detailInset-2*metrics.guidePadding)
    self.details:SetSize(1000,600)
    self.scroll:SetPoint("BOTTOMRIGHT",-36,18);self.scrollChild:SetWidth(1000-metrics.detailInset-40);self.detailText:SetWidth(self.scrollChild:GetWidth())
    self.Settings.frame:SetShown(index==5)
    self.Chains.frame:SetShown(index==2)
    self.Services.frame:SetShown(index==7)
    for _,panel in ipairs({self.Settings.frame,self.Chains.frame,self.Services.frame}) do
        panel:ClearAllPoints();panel:SetPoint("TOPLEFT",self.detailRule,"BOTTOMLEFT",0,-metrics.guidePadding);panel:SetPoint("BOTTOMRIGHT",-18,18)
    end
    self.Browser.frame:SetShown(browse)
    self.scroll:SetShown(not browse and index~=5 and index~=2)
    self.scroll:SetPoint("TOPLEFT",self.detailRule,"BOTTOMLEFT",0,-metrics.guidePadding-(index==7 and 84 or 0))
    if browse then
        self.Browser:Refresh(index,reuse,not reuse)
        self.detailRule:SetWidth(self.Browser.list:GetWidth())
        return
    end
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

function UI.DungeonXPText(rewards)
    if rewards.unknownXP==0 then return tostring(rewards.xp) end
    if rewards.xp>0 then return "至少 "..rewards.xp end
    return "待确认"
end

function UI.DungeonPickupStatus(row,state)
    if row.group==1 then return "可交付" end
    if row.group==2 then return "已接取" end
    if row.group==5 then return "已交付" end
    if row.group==3 then
        if state.completed[row.id] then return "可重复" end
        return row.requireCheck and "待确认" or "未接取"
    end
    if row.preparation or row.reason=="前置未交付" or row.reason=="备选前置未交付" then return "需前置" end
    return "不可接"
end

function UI.DungeonPickupSummary(rows,state)
    if not A.indexReady or state.completionKnown==false then return "正在核对副本任务…" end
    local counts={}
    for _,row in ipairs(rows) do
        if row.relation~="preparation" then
            local status=UI.DungeonPickupStatus(row,state)
            counts[status]=(counts[status] or 0)+1
        end
    end
    local held=(counts["已接取"] or 0)+(counts["可交付"] or 0)
    local missing=counts["未接取"] or 0
    local parts={}
    if held+missing>0 then
        parts[1]=string.format("已接 %d/%d",held,held+missing)
        if missing>0 then parts[2]="还差 "..missing.." 项"
        elseif not counts["待确认"] then parts[2]="当前可接已接齐" end
    else
        parts[1]=counts["待确认"] and "接取资格待核实" or "当前无待接任务"
    end
    for _,status in ipairs({"需前置","待确认","可交付","已交付","可重复"}) do
        if counts[status] then parts[#parts+1]=status.." "..counts[status] end
    end
    return table.concat(parts," · ")
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

function UI.QuestDeferral(id)
    if not id then return end
    local skipped=(A.char.skipped or {})[id]
    if skipped then return "恢复推荐",A.Selection.ResumeQuest,skipped~="ignored" end
    if (A.state.chainDeferred or {})[id] then return end
    if (A.state.completed or {})[id] and not (A.state.quests or {})[id] then
        local q=A.Data:GetQuest(id,A.state)
        if not (q and q.repeatable) then return end
    end
    return "暂时不做",A.Selection.Skip,true
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
        if A.State and A.State.QuestText then A.State:QuestText(id) end
        self.details:Hide()
        QuestMapFrame_OpenToQuestDetails(id)
        return true
    end
    local tab=1
    for _,choice in ipairs(A.plan and A.plan.taskChoices or {}) do
        if choice.questId==id then
            if self.Browser:IsCareerChoice(choice) then tab=9 end
            break
        end
    end
    local key="q:"..id
    if tab==9 then self.Browser.selection[tab]=key else self.Plan.key=key end
    self.Browser:ClearSearch();self.Browser.info:SetVerticalScroll(0)
    self.details:Show();self:SelectTab(tab)
    if tab==9 and not (self.Browser.selected and self.Browser.selected.questId==id) then
        self.Plan.key=key;self:SelectTab(1)
    end
    return true
end

function UI:TaskLines(compact)
    local state=A.state or {}
    local plan=A.Navigation and A.Navigation.TrackerPlan and A.Navigation:TrackerPlan(A.plan,state) or A.plan or {}
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
            if status~="已交付" and not (state.skipped or {})[choice.questId] and not (state.chainDeferred or {})[choice.questId] then
                titles[#titles+1]="["..status.."] "..(choice.title or ("任务 #"..choice.questId))
            end
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
        local label=UI.QuestStatus(state,id)..(deferred=="ignored" and "·忽略" or deferred and "·暂缓" or "")
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
            lines[#lines+1]=string.format("%d. [未接取%s] %s",i,deferred=="ignored" and "·忽略" or deferred and "·暂缓" or "",choice.title or ("任务 #"..choice.questId))
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

function UI:SetNavigation(distance, angle, unverified, guide)
    self:SetTrackerNavigation(distance,angle,unverified,guide)
end
