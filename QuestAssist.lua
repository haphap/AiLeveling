local _, A = ...
A.QuestAssist = { buttons = {}, highlights = {} }
local Q = A.QuestAssist
BINDING_HEADER_AILEVELING = "AiLeveling"
for i=1,4 do _G["BINDING_NAME_CLICK AiLevelingItem"..i..":LeftButton"] = "使用当前任务物品 "..i end

function Q.Requirements(action,state,data)
    local rows,byId = {},{}
    if not action then return rows end
    if action.kind=="transit" and action.mode=="hearth" then
        local have=(state.bags or {})[6948] or 0
        return {{id=6948,kind="use",count=1,countKnown=true,have=have,missing=math.max(0,1-have),clientConfirmed=true}}
    end
    local active = action.questId and state.quests[action.questId]
    local quest = data and action.questId and data:GetQuest(action.questId)
    local function add(id,rule)
        if not id or id<=0 then return end
        local row=byId[id]
        if not row then row={id=id,count=1,kind="source"}; rows[#rows+1]=row; byId[id]=row end
        for key,value in pairs(rule or {}) do row[key]=value end
        if rule and rule.count then row.countKnown=true end
    end
    if quest then
        for id,rule in pairs(quest.itemRules or {}) do
            local stage=rule.stage or (rule.kind=="use" and "objective") or (rule.kind=="start" and "accept")
            if not stage or stage==action.kind then add(id,rule) end
        end
        if action.kind=="objective" then
            if not byId[quest.sourceItemId] then add(quest.sourceItemId,{kind="source"}) end
            for _,id in ipairs(quest.requiredSourceItems or {}) do if not byId[id] then add(id,{kind="key"}) end end
        elseif action.kind=="accept" then
            for _,id in ipairs(quest.startedBy and quest.startedBy[3] or {}) do add(id,{kind="start"}) end
        end
    end
    if active and (not action.kind or action.kind=="objective") and not active.ready then add(active.itemId,{kind="use",clientConfirmed=true}) end
    for id,count in pairs(action.items or {}) do add(id,{kind="use",count=count}) end
    for id,count in pairs(action.requiredItems or {}) do add(id,{kind="key",count=count}) end
    for _,row in ipairs(rows) do
        row.have=state.bags[row.id] or 0
        row.missing=math.max(0,row.count-row.have)
        if row.kind=="use" and active and active.ready then row.finished=true end
    end
    table.sort(rows,function(a,b)
        if (a.clientConfirmed==true)~=(b.clientConfirmed==true) then return a.clientConfirmed==true end
        return a.id<b.id
    end)
    return rows
end

function Q.Page(items,page)
    local pages=math.max(1,math.ceil(#items/4))
    page=math.max(1,math.min(page or 1,pages))
    local result={}
    for i=(page-1)*4+1,math.min(#items,page*4) do result[#result+1]=items[i] end
    return result,page,pages
end

function Q:Create()
    if self.container or InCombatLockdown() then return end
    local f = CreateFrame("Frame", "AiLevelingItems", UIParent)
    f:SetSize(180, 48)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    self.container = f
    self.info = CreateFrame("Frame",nil,UIParent)
    self.info:SetSize(340,110); self.info:SetPoint("TOP",f,"BOTTOM",0,-4)
    self.info.text = A.UI:Text(self.info,12)
    self.info.text:SetPoint("TOPLEFT"); self.info.text:SetWidth(340); self.info.text:SetHeight(76)
    self.info:EnableMouse(true)
    self.info:SetScript("OnEnter",function(f)
        GameTooltip:SetOwner(f,"ANCHOR_RIGHT"); GameTooltip:SetText("任务辅助详情")
        GameTooltip:AddLine(self.detailsText or "",1,1,1,true); GameTooltip:Show()
    end)
    self.info:SetScript("OnLeave",function() GameTooltip:Hide() end)
    self.next = A.UI:Button(self.info,"下一组任务物品",150,function()
        self.page=(self.page or 1)%math.max(1,math.ceil(#(self.wanted or {})/4))+1
        self:Update()
    end)
    self.next:SetPoint("TOPLEFT",0,-80)
    for i = 1, 4 do
        local button = CreateFrame("Button", "AiLevelingItem" .. i, f, "SecureActionButtonTemplate")
        button:SetSize(38, 38)
        button:SetPoint("LEFT", f, "LEFT", (i - 1) * 46, 0)
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("type", "item")
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.count = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.count:SetPoint("BOTTOMRIGHT", -2, 2)
        button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        button.cooldown:SetAllPoints()
        button:SetScript("OnEnter", function(b)
            if b.itemId then GameTooltip:SetOwner(b, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(b.itemId); GameTooltip:Show() end
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:Hide()
        self.buttons[i] = button
    end
end

function Q.Desired(action, state, enabled, data)
    local items, seen = {}, {}
    if not enabled or not action then return items end
    local function add(id)
        if id and id > 0 and not seen[id] then items[#items + 1], seen[id] = id, true end
    end
    for _,row in ipairs(Q.Requirements(action,state,data)) do
        if not row.finished and (row.kind=="use" or row.kind=="start") then add(row.id) end
    end
    return items
end

function Q.Describe(rows,options,nameFor)
    local lines,kinds={}, {use="使用",collect="收集",key="携带",source="来源物品",start="开启任务"}
    for _,row in ipairs(rows) do
        if not row.finished then
            local quantity=""
            if options.quantity~=false then quantity=row.countKnown and string.format(" %d/%d",row.have,row.count) or (" 背包 "..row.have) end
            local missing=options.missingChecks~=false and row.missing>0 and row.kind~="source"
            lines[#lines+1]=(kinds[row.kind] or "物品").."："..nameFor(row.id)..quantity..
                (missing and (" · 缺少 "..row.missing..(row.recovery and ("；"..row.recovery) or "")) or "")
            if row.missing==0 and (row.target or row.condition) then lines[#lines+1]=table.concat({row.target or "",row.condition or ""}," ") end
        end
    end
    return lines
end

function Q.CompareRewards(items,state)
    local best,unknown,manual
    local comparisons={}
    for index,item in ipairs(items) do
        if item.pending then unknown=true
        elseif item.equipLoc and item.equipLoc~="" then
            if item.usable==nil then unknown=true end
            local comparison=A.Gear.Upgrade(item,state)
            if comparison and comparison.provisional then unknown=true end
            if comparison then
                comparisons[#comparisons+1]={item=item,comparison=comparison,index=index}
                if #(comparison.notes or {})>0 then manual=true end
            end
            if comparison and comparison.delta>0 and (not best or comparison.delta>best.comparison.delta) then
                best={item=item,comparison=comparison,index=index}
            end
        end
    end
    return not manual and best or nil,unknown,manual and comparisons or nil
end

function Q:RewardDialog(open)
    self.rewardQuest=open and GetQuestID and GetQuestID() or nil
    if self.rewardQuest==0 then self.rewardQuest=nil end
    self:Update(true)
end

function Q:RewardLines()
    if A.settings.rewardAdvice==false or not self.rewardQuest or not GetQuestID or GetQuestID()~=self.rewardQuest or
        not GetNumQuestChoices or not GetQuestItemLink then return {} end
    local count=GetNumQuestChoices()
    if count<=1 then return {} end
    local items,unknown={},false
    for i=1,count do
        local link=GetQuestItemLink("choice",i)
        local id=link and tonumber(link:match("item:(%d+)"))
        if id then items[i]=A.Items:Read(id,link) else items[i]={pending=true};unknown=true end
    end
    local best,pending,comparisons=Q.CompareRewards(items,A.state)
    if pending or unknown then return {"任务 #"..self.rewardQuest.."：奖励属性加载中。"} end
    if comparisons then
        local lines={"任务 #"..self.rewardQuest.."：奖励需要权衡，请比较后选择。"}
        for _,entry in ipairs(comparisons) do
            lines[#lines+1]=string.format("第 %d 项 %s · 属性评分变化 %+.1f",entry.index,
                entry.item.link or entry.item.name or ("#"..entry.item.id),entry.comparison.delta)
            for _,note in ipairs(entry.comparison.notes or {}) do lines[#lines+1]=note end
        end
        return lines
    end
    if not best then return {"任务 #"..self.rewardQuest.."：没有装备提升，可按需选择奖励。"} end
    return {string.format("任务 #%d 奖励建议：第 %d 项 %s · 属性评分变化 %+.1f。",
        self.rewardQuest,best.index,best.item.link or best.item.name or ("#"..best.item.id),best.comparison.delta)}
end

function Q:Notice(action,rows,quiet)
    if not action or (action.kind~="accept" and action.kind~="objective" and action.kind~="turnin" and action.kind~="service") then return end
    local active=action.questId and A.state.quests[action.questId]
    local parts={action.kind,action.questId or "",action.objectiveIndex or "",action.serviceId or "",tostring(active and active.ready)}
    if A.settings.missingChecks~=false then
        for _,row in ipairs(rows) do if not row.finished and row.kind~="source" and row.missing>0 then parts[#parts+1]=row.id end end
    end
    local key=table.concat(parts,":")
    local changed=self.noticeKey and key~=self.noticeKey
    self.noticeKey=key
    if not changed or quiet or not A.settings.sound or A.char.paused or InCombatLockdown() or
        (A.Transport and A.Transport:InFlight()) then return end
    local now=GetTime()
    if self.lastSoundAt and now-self.lastSoundAt<5 then return end
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_SELECT then PlaySound(SOUNDKIT.IG_QUEST_LIST_SELECT);self.lastSoundAt=now end
end

function Q:Update(quiet)
    if not A.state or not A.settings then return end
    local action = A.Navigation:Current()
    local wanted = Q.Desired(action,A.state,A.settings.items,A.Data)
    local key = table.concat(wanted,":")
    if key~=self.key then self.page=1; self.key=key end
    self.wanted=wanted
    local pages
    self.pending,self.page,pages=Q.Page(wanted,self.page)
    self:ApplyPending()
    local rows=Q.Requirements(action,A.state,A.Data)
    self.requirements=rows
    self:Highlight()
    self:Notice(action,rows,quiet)
    if self.info then
        local lines=A.settings.items and Q.Describe(rows,A.settings,function(id)
            local name=C_Item.GetItemNameByID(id)
            if not name and not A.requestedItems[id] then A.requestedItems[id]=true;C_Item.RequestLoadItemDataByID(id) end
            return name or ("物品 #"..id)
        end) or {}
        local rewards=self:RewardLines()
        local rewardStart=#lines+1
        for _,line in ipairs(rewards) do lines[#lines+1]=line end
        if pages>1 then lines[#lines+1]=string.format("物品按钮第 %d/%d 组",self.page,pages) end
        if self.pending and InCombatLockdown() then lines[#lines+1]="物品按钮将在战斗结束后同步" end
        self.detailsText=table.concat(lines,"\n")
        if #rewards>1 then
            for i=1,#rewards do table.remove(lines,rewardStart) end
            table.insert(lines,1,"奖励需要权衡；悬停查看各项比较。")
        end
        self.info.text:SetText(table.concat(lines,"\n"))
        self.info:SetShown(#lines>0)
        self.next:SetShown(pages>1)
    end
end

function Q:ApplyPending()
    if InCombatLockdown() then return end
    self:Create()
    if not self.pending then return end
    local items = self.pending
    self.active, self.pending = items, nil
    for i, button in ipairs(self.buttons) do
        local id = items[i]
        button.itemId = id
        button:SetAttribute("item", id and ("item:" .. id) or nil)
        if id then
            button.icon:SetTexture(C_Item.GetItemIconByID(id))
            local count = A.state.bags[id] or 0
            button.count:SetText(A.settings.quantity~=false and count or "")
            button.icon:SetDesaturated(count == 0)
            button:Show()
        else button:Hide() end
    end
    self:Cooldowns()
end

function Q:Cooldowns()
    for _, button in ipairs(self.buttons) do
        if button.itemId then
            local start, duration = C_Container.GetItemCooldown(button.itemId)
            if start and duration and duration > 0 then button.cooldown:SetCooldown(start, duration)
            else button.cooldown:Clear() end
        end
    end
end

function Q:ScheduleHighlight()
    if self.highlightScheduled then return end
    if C_Timer and C_Timer.After then
        self.highlightScheduled=true
        C_Timer.After(0,function() self.highlightScheduled=nil;self:Highlight() end)
    else self:Highlight() end
end

function Q:Highlight()
    if InCombatLockdown() then return end
    for _, texture in ipairs(self.highlights) do texture:Hide() end
    self.highlights = {}
    if not A.settings.highlight or A.char and A.char.paused then return end
    local wanted = {}
    if self.requirements then
        for _,row in ipairs(self.requirements) do if not row.finished then wanted[row.id]=true end end
    else for _,id in ipairs(self.wanted or self.pending or self.active or {}) do wanted[id]=true end end
    local seen={}
    local function highlightButton(button,bag,slot)
        if not button or seen[button] or not button:IsShown() or
            button.IsForbidden and button:IsForbidden() then return end
        seen[button]=true
        local id=C_Container.GetContainerItemID(bag,slot)
        if id and not (issecretvalue and issecretvalue(id)) and wanted[id] then
            if not button.AiLevelingHighlight then
                local texture=button:CreateTexture(nil,"OVERLAY")
                texture:SetAllPoints();texture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                texture:SetBlendMode("ADD");texture:SetVertexColor(0.2,1,0.8)
                button.AiLevelingHighlight=texture
            end
            button.AiLevelingHighlight:Show()
            self.highlights[#self.highlights+1]=button.AiLevelingHighlight
        end
    end
    local function highlightBag(frame)
        if not frame or not frame:IsShown() or not frame.EnumerateValidItems then return end
        for _, button in frame:EnumerateValidItems() do
            local bag, slot = button:GetBagID(), button:GetID()
            highlightButton(button,bag,slot)
        end
    end
    highlightBag(ContainerFrameCombinedBags)
    for i = 1, NUM_CONTAINER_FRAMES or 13 do highlightBag(_G["ContainerFrame" .. i]) end
    -- DaylightUI Bags 1.6.2 exposes the live bag's slot set on its named window.
    -- Bank/alt viewers have separate windows and are deliberately not enumerated.
    local frame=DaylightUIBag
    if frame and frame.kind=="bag" and frame.set and type(frame.set.Slots)=="function" and
        not (frame.IsForbidden and frame:IsForbidden()) then
        if self.daylightFrame~=frame and frame.HookScript and hooksecurefunc then
            local refresh=function() self:ScheduleHighlight() end
            frame:HookScript("OnShow",refresh);frame:HookScript("OnHide",refresh)
            if type(frame.set.Sync)=="function" then hooksecurefunc(frame.set,"Sync",refresh) end
            self.daylightFrame=frame
        end
        if frame:IsShown() then
            for _,entry in ipairs(frame.set.Slots()) do
                local button=entry.button
                if button and button.GetID then highlightButton(button,entry.bag,button:GetID()) end
            end
        end
    end
end
