local _, A = ...
A.QuestAssist = { buttons = {}, highlights = {} }
local Q = A.QuestAssist
BINDING_HEADER_AILEVELING = "AILeveling"
for i=1,4 do _G["BINDING_NAME_CLICK AiLevelingItem"..i..":LeftButton"] = "使用当前任务物品 "..i end
_G["BINDING_NAME_CLICK AiLevelingTarget:LeftButton"]="选中当前任务目标"
_G["BINDING_NAME_CLICK AiLevelingTarget:RightButton"]="标记当前选中的目标"
_G["BINDING_NAME_CLICK AiLevelingFollowLeader:LeftButton"]="跟随当前队长"
BINDING_NAME_AILEVELING_TARGET_NEXT="切换当前任务目标"

local function readable(value) return not canaccessvalue or canaccessvalue(value) end

function Q.Leader()
    if not IsInGroup or not IsInRaid or not UnitIsGroupLeader or not UnitIsConnected or not UnitName then return end
    local grouped,raid,own=IsInGroup(),IsInRaid(),UnitIsGroupLeader("player")
    if not readable(grouped) or not readable(raid) or not readable(own) or grouped~=true or own~=false or type(raid)~="boolean" then return end
    for index=1,raid and 40 or 4 do
        local unit=(raid and "raid" or "party")..index
        local leader=UnitIsGroupLeader(unit)
        if readable(leader) and leader==true then
            local connected=UnitIsConnected(unit)
            if not readable(connected) or connected~=true then return end
            local name,realm=UnitName(unit)
            if not readable(name) or not readable(realm) or type(name)~="string" or name=="" or
                realm~=nil and type(realm)~="string" then return end
            local fullName=name..(realm and realm~="" and ("-"..realm) or "")
            if #fullName>200 or fullName:find("[%c%[%];/\\]") or fullName:match("^%s") or fullName:match("%s$") then return end
            return {name=name,fullName=fullName}
        end
    end
end

function Q.TargetNPCs(action,state,data)
    local targets,seen={},{}
    if not action or not state or not data or
        (action.kind~="accept" and action.kind~="turnin" and action.kind~="objective" and action.kind~="service") then return targets end
    local function add(id,point)
        if type(id)~="number" or id<=0 or id>=2147483648 or id%1~=0 or seen[id] then return end
        local name=data.db and data.db.Npc.Get(id,"name") or
            point and point.entityKind=="npc" and point.entityId==id and point.entityName
        -- Names enter a secure macro: reject command syntax instead of escaping it.
        if type(name)~="string" or name=="" or #name>200 or name:find("[%c%[%];/\\]") or name:match("^%s") or name:match("%s$") then return end
        seen[id]=true;targets[#targets+1]={id=id,name=name}
    end
    local point=action.position
    local id=action.npcId or (point and point.entityKind=="npc" and point.entityId)
    local q=action.questId and data:GetQuest(action.questId)
    local active=action.questId and (state.quests or {})[action.questId]
    if action.kind=="objective" then
        if not active or active.ready then return targets end
        local objective=action.objectiveIndex and (active.objectives or {})[action.objectiveIndex]
        if not (objective and objective.finished) then add(id or action.targetKind=="npc" and action.targetId,point) end
        if q then
            local points={}
            for _,p in ipairs(data.ObjectiveTargets and data:ObjectiveTargets(q,state) or {}) do points[p.objectiveIndex or 1]=p end
            local identities=data.ObjectiveIdentities and data:ObjectiveIdentities(q,state) or {}
            for index,o in ipairs(active.objectives or {}) do
                if not o.finished then
                    local p,identity=points[index],identities[index]
                    if p and p.entityKind=="npc" then add(p.entityId,p) end
                    if identity and identity.kind=="npc" then add(identity.id)
                    elseif identity and identity.kind=="killcredit" then
                        for _,npcId in ipairs(identity.npcIds or {}) do add(npcId) end
                    end
                end
            end
        end
    else
        if not id and q and data.Target then
            local lookup={position=state.position,faction=state.faction,completed=state.completed,quests={}}
            if action.kind=="turnin" then lookup.quests[q.id]={ready=true} end
            point=data:Target(q,lookup)
            id=point and point.entityKind=="npc" and point.entityId
        end
        add(id,point)
    end
    return targets
end

function Q:TargetStatus()
    if not self.targetButton then return end
    local target=self.targetActive
    local count=#(self.targetActiveChoices or {})
    local prefix=count>1 and (self.targetActiveIndex.."/"..count.." · ") or ""
    self.targetTitle=target and (prefix.."选中 "..target.name) or ""
    local status=count>1 and "滚轮／中键切换 · 右键标记" or "右键：为当前选中的目标加骷髅标记"
    if self.targetQueued then status="战斗结束后更新目标"
    elseif target and UnitGUID then
        local guid=UnitGUID("target")
        if (not canaccessvalue or canaccessvalue(guid)) and type(guid)=="string" then
            local kind,id=guid:match("^(%a+)%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)%-")
            if kind=="Creature" or kind=="Vehicle" then
                for _,npc in ipairs(self.targetActiveChoices or {}) do
                    if tonumber(id)==npc.id then status="已选中 · "..npc.name.." · 右键标记";break end
                end
            end
        end
    end
    self.targetStatus=status
end

function Q:LayoutTarget()
    local button,T=self.targetButton,A.UI.tracker
    if not button or not T then return end
    if not InCombatLockdown() then
        local x,y=T.stepIcon:GetCenter()
        local visible=self.targetActive~=nil and A.UI.frame:IsShown() and x~=nil and y~=nil
        if visible then
            -- Screen coordinates keep the secure button separate from the resizable tracker.
            local scale=A.UI.frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
            local size=T.stepIcon:GetWidth()*scale
            button:ClearAllPoints();button:SetPoint("CENTER",UIParent,"BOTTOMLEFT",x*scale,y*scale)
            button:SetSize(size+6*scale,size+6*scale);button.icon:SetSize(size,size)
            button.icon:SetVertexColor(A.UI:Accent())
        end
        button:SetShown(visible)
    end
    T.stepIcon:SetShown(not button:IsShown())
end

function Q:ApplyTarget()
    if not self.targetButton then return end
    if InCombatLockdown() then
        self.targetQueued=self.targetActiveKey~=self.targetKey
        self:TargetStatus();return
    end
    self.targetQueued=nil
    local target=self.targetWanted
    self.targetActive=target
    self.targetActiveChoices,self.targetActiveIndex,self.targetActiveKey=self.targetChoices,self.targetIndex,self.targetKey
    self.targetButton:SetAttribute("macrotext1",target and ("/targetexact "..target.name) or nil)
    self:LayoutTarget()
    self:TargetStatus()
end

function Q:CycleTarget(delta)
    if InCombatLockdown() or #(self.targetChoices or {})<2 then return end
    self.targetIndex=(self.targetIndex-1+delta)%#self.targetChoices+1
    self.targetWanted=self.targetChoices[self.targetIndex];self:ApplyTarget()
end

function Q:ApplyFollow()
    if not self.followButton or InCombatLockdown() then return end
    local wanted=self.followWanted
    self.followButton:SetAttribute("macrotext1",wanted and ("/follow "..wanted.fullName) or nil)
    self.followButton:SetShown(wanted~=nil)
end

function Q.DialogChoice(id,kind)
    local state,plan=A.state,A.plan
    if not state or not plan or plan.revision and plan.revision~=state.revision or state.locked and state.locked~=id then return end
    local active=(state.quests or {})[id]
    if kind=="accept" and active or kind=="turnin" and not (active and active.ready) then return end
    for _,choice in ipairs(plan.taskChoices or {}) do
        if choice.questId==id and not choice.lowValue and not choice.requireCheck and not choice.entryBlocked then
            if kind=="accept" then return not choice.acceptBlocked and choice.status=="accept" or nil end
            if A.TaskGuide and not state.locked then
                local _,groups=A.TaskGuide.DeliveryGroups(plan.taskChoices,state,plan.taskOrder)
                local group=groups[id]
                if group and not group.splitDelivery and group.ready<#group.choices then return end
            end
            return not choice.itemShortage
        end
    end
end

function Q:TaskGossipOption()
    if not A.Services.CanAutomate("autoGossip") or not C_GossipInfo.GetOptions then return end
    local action=A.Navigation:Current()
    if not action or action.kind~="objective" or A.plan and A.plan.revision and A.plan.revision~=A.state.revision then return end
    local quest=A.state.quests[action.questId]
    local objective=quest and action.objectiveIndex and (quest.objectives or {})[action.objectiveIndex]
    if not quest or quest.ready or objective and objective.finished then return end
    local guid=UnitGUID("npc")
    if not readable(guid) then return end
    local npc=A.Merchant.NpcId(guid)
    local point=action.position
    local target=action.npcId or point and point.entityKind=="npc" and point.entityId or action.targetKind=="npc" and action.targetId
    if not npc or npc~=target then return end
    local options=C_GossipInfo.GetOptions()
    -- A branch is a player choice; only continue a single ordinary conversation option.
    if #options~=1 then return end
    local option=options[1]
    if not readable(option.icon) or option.icon~=132053 or not readable(option.status) or
        option.status~=Enum.GossipOptionStatus.Available then return end
    local method,value
    if readable(option.gossipOptionID) and type(option.gossipOptionID)=="number" then
        method,value="SelectOption",option.gossipOptionID
    elseif readable(option.orderIndex) and type(option.orderIndex)=="number" then
        method,value="SelectOptionByIndex",option.orderIndex
    else return end
    if not readable(option.name) then return end
    return {key=table.concat({"task",guid,action.questId,method,value,option.name},":"),select=C_GossipInfo[method],value=value}
end

-- Only act on a dialog the player opened; the client events still acknowledge progress.
function Q:DialogEvent(event)
    if event=="QUEST_FINISHED" or event=="GOSSIP_CLOSED" or event=="PLAYER_ENTERING_WORLD" then self.dialogDone=nil;self.dialogPending=nil;return end
    if event~="GOSSIP_SHOW" and event~="QUEST_DETAIL" and event~="QUEST_PROGRESS" and event~="QUEST_COMPLETE" then return end
    self.dialogPending=nil
    if not A.ready or not A.settings or not A.char or A.char.paused or
        InCombatLockdown and InCombatLockdown() or IsShiftKeyDown and IsShiftKeyDown() or
        A.Navigation and A.Navigation.manual then return end
    local function valid(id)
        return (not canaccessvalue or canaccessvalue(id)) and type(id)=="number" and id>0 and id<2147483648 and id%1==0
    end
    if A.refreshAt or A.jobs and A.jobs.plan then
        local guid=UnitGUID and UnitGUID("npc")
        local id=event~="GOSSIP_SHOW" and GetQuestID and GetQuestID()
        if canaccessvalue and not canaccessvalue(guid) or event~="GOSSIP_SHOW" and not valid(id) then return end
        local pending={}
        self.dialogPending=pending
        A:Queue("quest:dialog",function()
            -- This event can update NPC offers and the plan before selecting a quest or service.
            while self.dialogPending==pending and (A.refreshAt or A.jobs.plan) do coroutine.yield() end
            if self.dialogPending~=pending then return end
            local current=UnitGUID and UnitGUID("npc")
            if canaccessvalue and not canaccessvalue(current) or current~=guid then return end
            if event~="GOSSIP_SHOW" then
                local quest=GetQuestID and GetQuestID()
                if not valid(quest) or quest~=id then return end
            end
            self:DialogEvent(event)
        end)
        return
    end
    local function once(key,fn,...)
        if not fn then return end
        self.dialogDone=self.dialogDone or {}
        if self.dialogDone[key] then return end
        self.dialogDone[key]=true
        return pcall(fn,...)
    end
    if event=="GOSSIP_SHOW" then
        if not C_GossipInfo then return end
        for _,kind in ipairs({"turnin","accept"}) do
            local enabled=kind=="accept" and A.settings.autoAccept or kind=="turnin" and A.settings.autoTurnIn
            local getter=kind=="accept" and C_GossipInfo.GetAvailableQuests or C_GossipInfo.GetActiveQuests
            if getter then
                local ok,list=pcall(getter)
                if ok and type(list)=="table" then
                    for _,row in ipairs(list) do
                        if type(row)=="table" and valid(row.questID) and (kind=="accept" or row.isComplete==true) and Q.DialogChoice(row.questID,kind) then
                            if enabled then
                                local selectQuest=kind=="accept" and C_GossipInfo.SelectAvailableQuest or C_GossipInfo.SelectActiveQuest
                                once("select:"..row.questID,selectQuest,row.questID)
                            end
                            return
                        end
                    end
                end
            end
        end
        local option=A.Services and A.Services.GossipOption and (A.Services:GossipOption() or self:TaskGossipOption())
        if option then once(option.key,option.select,option.value) end
        return
    end
    local id=GetQuestID and GetQuestID()
    if not valid(id) then return end
    if event=="QUEST_DETAIL" and A.settings.autoAccept and Q.DialogChoice(id,"accept") then
        once("accept:"..id,AcceptQuest)
    elseif event=="QUEST_PROGRESS" and A.settings.autoTurnIn and Q.DialogChoice(id,"turnin") and IsQuestCompletable and IsQuestCompletable() then
        once("progress:"..id,CompleteQuest)
    elseif event=="QUEST_COMPLETE" and A.settings.autoTurnIn and Q.DialogChoice(id,"turnin") then
        local count=GetNumQuestChoices and GetNumQuestChoices()
        local money=GetQuestMoneyToGet and GetQuestMoneyToGet()
        if (count==0 or count==1) and type(money)=="number" and money<=0 then once("reward:"..id,GetQuestReward,count) end
    end
end

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
            for id,rule in pairs(data.ItemUseRules and data:ItemUseRules(quest,state) or {}) do
                if not byId[id] then add(id,rule) end
            end
            if not byId[quest.sourceItemId] then add(quest.sourceItemId,{kind="source"}) end
            for _,id in ipairs(quest.requiredSourceItems or {}) do if not byId[id] then add(id,{kind="key"}) end end
        elseif action.kind=="accept" then
            local starter=action.position and action.position.startItemId
            if starter then add(starter,{kind="start"})
            else for _,id in ipairs(quest.startedBy and quest.startedBy[3] or {}) do add(id,{kind="start"}) end end
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
    local target=CreateFrame("Button","AiLevelingTarget",UIParent,"SecureActionButtonTemplate")
    self.targetButton=target
    target:SetSize(24,24)
    target.icon=target:CreateTexture(nil,"ARTWORK");target.icon:SetPoint("CENTER")
    target.icon:SetTexture("Interface\\AddOns\\AiLeveling\\Media\\target.tga")
    target:RegisterForClicks("AnyUp","AnyDown")
    target:EnableMouseWheel(true)
    target:SetScript("OnMouseWheel",function(_,delta) self:CycleTarget(delta>0 and -1 or 1) end)
    target:SetScript("PostClick",function(_,button,down) if button=="MiddleButton" and not down then self:CycleTarget(1) end end)
    target:SetAttribute("type1","macro")
    target:SetAttribute("type2","raidtarget");target:SetAttribute("unit2","target")
    target:SetAttribute("marker2",8);target:SetAttribute("action2","set-unmarked")
    target:SetScript("OnEnter",function(b)
        if self.targetActive then
            GameTooltip:SetOwner(b,"ANCHOR_LEFT");GameTooltip:SetText(self.targetTitle)
            GameTooltip:AddLine(self.targetStatus,1,1,1,true)
            GameTooltip:AddLine("左键选中；右键标记；战斗外滚轮或中键切换。",1,1,1,true)
            GameTooltip:AddLine("标题栏右键可隐藏目标辅助。",0.75,0.8,0.85,true);GameTooltip:Show()
        end
    end)
    target:SetScript("OnLeave",function() GameTooltip:Hide() end)
    target:Hide()
    local follow=CreateFrame("Button","AiLevelingFollowLeader",UIParent,"SecureActionButtonTemplate")
    self.followButton=follow
    -- Keyboard binding only: no floating button or mouse hit area.
    follow:SetSize(1,1);follow:SetPoint("TOPLEFT",UIParent,"TOPLEFT")
    follow:RegisterForClicks("AnyUp","AnyDown");follow:SetAttribute("type1","macro")
    follow:EnableMouse(false);follow:Hide()
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
                local value={item=item,upgrade=comparison,index=index}
                comparisons[#comparisons+1]=value
                if #(comparison.notes or {})>0 then manual=true end
                if A.Gear.BetterReward(value,best,state) then best=value end
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
                entry.item.link or entry.item.name or ("#"..entry.item.id),entry.upgrade.delta)
            for _,note in ipairs(entry.upgrade.notes or {}) do lines[#lines+1]=note end
        end
        return lines
    end
    if not best then return {} end
    return {string.format("奖励建议：选择第 %d 项 %s%s",best.index,best.item.link or best.item.name or ("#"..best.item.id),
        best.upgrade.delta>0 and (" · "..A.Gear.UpgradeText(best)) or "")}
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
    self.followWanted=A.settings.targets~=false and not A.char.paused and Q.Leader() or nil
    self.targetChoices=A.settings.targets~=false and not A.char.paused and Q.TargetNPCs(action,A.state,A.Data) or {}
    local targets={tostring(action and action.kind),tostring(action and action.questId),tostring(action and action.objectiveIndex)}
    for _,npc in ipairs(self.targetChoices) do targets[#targets+1]=npc.id..":"..npc.name end
    local targetKey=table.concat(targets,"\031")
    if self.targetKey~=targetKey then self.targetIndex=1;self.targetKey=targetKey end
    self.targetWanted=self.targetChoices[self.targetIndex]
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
    if InCombatLockdown() then self:ApplyTarget();self:ApplyFollow();return end
    self:Create()
    self:ApplyTarget()
    self:ApplyFollow()
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
    self:EachBagButton(highlightButton)
end

function Q:EachBagButton(callback)
    local function highlightBag(frame)
        if not frame or not frame:IsShown() or not frame.EnumerateValidItems then return end
        for _, button in frame:EnumerateValidItems() do
            local bag, slot = button:GetBagID(), button:GetID()
            callback(button,bag,slot)
        end
    end
    highlightBag(ContainerFrameCombinedBags)
    for i = 1, NUM_CONTAINER_FRAMES or 13 do highlightBag(_G["ContainerFrame" .. i]) end
    -- DaylightUI Bags 1.6.2 exposes the live bag's slot set on its named window.
    -- Bank/alt viewers have separate windows and are deliberately not enumerated.
    local frame=DaylightUIBag
    if frame and frame.kind=="bag" and frame.set and type(frame.set.Slots)=="function" and
        not (frame.IsForbidden and frame:IsForbidden()) then
        if self.daylightFrame~=frame and frame.HookScript and hooksecurefunc and not InCombatLockdown() then
            local refresh=function() self:ScheduleHighlight() end
            frame:HookScript("OnShow",refresh);frame:HookScript("OnHide",refresh)
            if type(frame.set.Sync)=="function" then hooksecurefunc(frame.set,"Sync",refresh) end
            self.daylightFrame=frame
        end
        if frame:IsShown() then
            for _,entry in ipairs(frame.set.Slots()) do
                local button=entry.button
                if button and button.GetID then callback(button,entry.bag,button:GetID()) end
            end
        end
    end
end
