local addonName, A = ...
_G.AiLeveling = A
A.name = addonName
A.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName,"Version") or "dev"
A.defaults = { mode = "relaxed", minutes = 60, dungeons = true, role = "DAMAGER",
    scale = 1, alpha = 0.94, arrow = true, pins = true, items = true, highlight = true, worldHighlight = true, scanRares = true,
    combatFold = true, learn = true, waitMinutes = 10, damageStyle = "auto",
    fontScale=1,density="normal",lockWindow=false,routes=true,minimapPins=true,
    distanceUnits="yards",transportHints=true,quantity=true,missingChecks=true,rewardAdvice=true,sound=false,gearPreference="nearby",autoAccept=true,autoTurnIn=true,autoTaxi=true,targets=true,levelingStats=true }
A.jobs, A.dirty, A.requestedItems = {}, false, {}

function A:NormalizeSettings(settings)
    settings.accent=nil
    local choices={mode={relaxed=true,fast=true,story=true},role={DAMAGER=true,TANK=true,HEALER=true},
        damageStyle={auto=true,strength=true,agility=true,ranged=true,caster=true,hybrid=true},
        density={compact=true,normal=true,expanded=true},
        distanceUnits={yards=true,meters=true},gearPreference={nearby=true,xp=true}}
    local bounds={scale={0.75,1.5},alpha={0.2,1},minutes={15,240},waitMinutes={0,60},fontScale={0.85,1.2}}
    for key,default in pairs(self.defaults) do
        local value=settings[key]
        local invalid=type(value)~=type(default)
        if not invalid and type(value)=="number" then
            local range=bounds[key]
            invalid=value~=value or value==math.huge or value==-math.huge or (range and (value<range[1] or value>range[2]))
        end
        if choices[key] and not choices[key][value] then invalid=true end
        if invalid then settings[key]=default end
    end
    for _,key in ipairs({"position","detailPosition","navigationPosition"}) do
    local p=settings[key]
    if p then
        local points={TOPLEFT=true,TOP=true,TOPRIGHT=true,LEFT=true,CENTER=true,RIGHT=true,BOTTOMLEFT=true,BOTTOM=true,BOTTOMRIGHT=true}
        if type(p)~="table" or not points[p[1]] or not points[p[2]] or type(p[3])~="number" or type(p[4])~="number" or
            p[3]~=p[3] or p[4]~=p[4] or math.abs(p[3])>10000 or math.abs(p[4])>10000 then settings[key]=nil end
    end
    end
end

function A:NormalizeCharacter(char)
    if self.LevelingTracker then self.LevelingTracker.Normalize(char) end
    char.ignoreRepair=char.ignoreRepair==true or nil
    for _,key in ipairs({"skipped","deferredChains","samples","turnIns","pendingResets"}) do if type(char[key])~="table" then char[key]={} end end
    for _,key in ipairs({"skipped","deferredChains"}) do
        for id,value in pairs(char[key]) do
            if type(id)~="number" or id<=0 or id>=2147483648 or id%1~=0 or value~=true then char[key][id]=nil end
        end
    end
    local flightCount,hearthCount=0,0
    for kind,sample in pairs(char.samples) do
        local valid=type(kind)=="string" and type(sample)=="table" and type(sample.n)=="number" and
            sample.n>=0 and sample.n<=100 and sample.n%1==0 and type(sample.mean)=="number" and
            sample.mean>0 and sample.mean<math.huge and type(sample.m2)=="number" and sample.m2>=0 and sample.m2<math.huge
        if valid and (kind=="quest" or kind=="move" or kind:sub(1,4)=="task") then valid=false end
        if valid and kind:sub(1,11)=="flighttime:" then
            local route,speed=kind:match("^(.-):speed:([^:]+)$")
            valid=#kind<=128 and sample.unit=="seconds" and sample.mean>=1 and sample.mean<=7200 and
                (not speed or speed=="1" or speed=="1.2") and
                (route or kind):match("^flighttime:[%w%.:%-]+:%d+:%d+$")~=nil
            if valid then flightCount=flightCount+1;valid=flightCount<=128 end
        end
        if valid and kind:sub(1,11)=="hearthtime:" then
            valid=kind:match("^hearthtime:v1:%d+$")~=nil and sample.unit=="seconds" and sample.mean>=1 and sample.mean<=120
            if valid then hearthCount=hearthCount+1;valid=hearthCount<=8 end
        end
        if not valid then char.samples[kind]=nil end
    end
    for id,count in pairs(char.turnIns) do
        if type(id)~="number" or id<=0 or type(count)~="number" or count<0 or count%1~=0 then char.turnIns[id]=nil end
    end
    for id,value in pairs(char.pendingResets) do
        if type(id)~="number" or id<=0 or id%1~=0 or type(value)~="table" or
            (value.name~=nil and type(value.name)~="string") then char.pendingResets[id]=nil end
    end
    if char.dungeon and not self.Dungeon.ValidSession(char.dungeon) then char.dungeon=nil end
    local target=char.gearTarget
    if (type(target)~="string" or target=="") and (type(target)~="number" or target<=0 or target>=math.huge or target%1~=0) then char.gearTarget=nil end
    if type(char.gearBaseline)~="number" or char.gearBaseline<0 or char.gearBaseline>19 or char.gearBaseline%1~=0 then char.gearBaseline=nil;char.gearTarget=nil end
    local binding=char.hearthBinding
    if binding and (type(binding)~="table" or type(binding.name)~="string" or
        (type(binding.node)~="string" and type(binding.node)~="number")) then char.hearthBinding=nil end
    if char.itinerary and (not self.Selection or not self.Selection.Valid(char.itinerary)) then char.itinerary=nil;char.locked=nil end
    if char.taskBatch and (not self.Dungeon.ValidTaskBatch or not self.Dungeon.ValidTaskBatch(char.taskBatch)) then char.taskBatch=nil end
    if type(char.serviceStop)=="table" and char.serviceStop.kind=="bind" then char.serviceStop.afterTask=nil end
    if char.serviceStop and (not self.Services or not self.Services.ValidStop(char.serviceStop)) then char.serviceStop=nil end
    if type(char.declinedBinding)~="string" or #char.declinedBinding>4096 then char.declinedBinding=nil end
    if char.locked~=nil and (type(char.locked)~="number" or char.locked<=0 or char.locked>=math.huge or char.locked%1~=0) then char.locked=nil end
end

function A:Message(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff53d6c7AiLeveling|r  " .. text)
end

function A:Queue(key, callback)
    self.jobs[key] = coroutine.create(callback)
end

function A:RequestRefresh()
    self.refreshAt = self.refreshAt or (GetTime() + 0.1)
end

function A:Replan()
    if not self.ready then return end
    if self.Transport and self.Transport:InFlight() or self.Hearth and self.Hearth:InTransit() then self.jobs.plan=nil;return end
    local snapshot,revision={},self.state.revision
    for key,value in pairs(self.state) do snapshot[key]=value end
    snapshot.currentTask=self.plan and self.plan.unverified and self.plan.fallback and self.plan.fallback.questId or nil
    snapshot.completed={}
    for id,value in pairs(self.state.completed or {}) do snapshot.completed[id]=value end
    if self.state.position then
        snapshot.position={}
        for key,value in pairs(self.state.position) do snapshot.position[key]=value end
    end
    local options={}
    for key,value in pairs(self.settings or {}) do options[key]=value end
    self:Queue("plan", function()
        local result = self.Planner.Build(snapshot, self.Data, options)
        if self.Transport and self.Transport:InFlight() then return end
        if self.state.revision ~= revision then return end
        if snapshot.position and self.state.position and snapshot.position.node ~= self.state.position.node then
            if (self.state.position.node or snapshot.position.map ~= self.state.position.map) and
                not self.Navigation.OnApproach(result, self.state.position.node) then
                self:Replan()
                return
            end
        end
        self.plan = self.Planner.Choose(self.plan, result, self.char.locked)
        self.dirty = true
        self.Navigation:SetPlan(self.plan)
    end)
end

function A:SetOption(key, value)
    if key=="levelingStats" and self.LevelingTracker then self.LevelingTracker:Update("option") end
    self.settings[key] = value
    if key=="levelingStats" and self.LevelingTracker then self.LevelingTracker:Update("option") end
    if key=="learn" then
        self.Observations:Reset(); self.Dungeon.runSample=nil;self.Transport:InvalidateSample()
        if self.Hearth then self.Hearth:InvalidateSample() end
    end
    self.UI:ApplyStyle()
    if self.WorldInteract then self.WorldInteract:Refresh() end
    if self.RareScanner then self.RareScanner:Refresh() end
    self.Navigation:RefreshPins()
    if self.QuestAssist then self.QuestAssist:Update(true) end
    if self.Routes then self.Routes:Update(true) end
    if self.ready and (key=="mode" or key=="role" or key=="minutes" or key=="dungeons" or key=="waitMinutes" or key=="damageStyle" or key=="gearPreference") then self.State:Refresh(true)
    else self:RequestRefresh() end
    self.dirty = true
end

function A:RestoreSettings()
    for key in pairs(self.settings) do self.settings[key]=nil end
    for key,value in pairs(self.defaults) do self.settings[key]=value end
    self.UI.frame:ClearAllPoints()
    self.UI.frame:SetPoint("RIGHT",UIParent,"RIGHT",-60,100)
    if self.UI.details then self.UI.details:ClearAllPoints();self.UI.details:SetPoint("CENTER") end
    if self.UI.navFrame then self.UI.navFrame:ClearAllPoints();self.UI.navFrame:SetPoint("CENTER",UIParent,"CENTER",0,-110) end
    self.UI:ApplyStyle()
    self.UI.Settings:Refresh()
    self.Observations:Reset()
    self.Transport:InvalidateSample()
    if self.Hearth then self.Hearth:InvalidateSample() end
    if self.ready then self.State:Refresh(true) end
    if self.WorldInteract then self.WorldInteract:Refresh() end
    if self.RareScanner then self.RareScanner:Refresh() end
    self.Navigation:RefreshPins()
    if self.QuestAssist then self.QuestAssist:Update() end
    if self.Routes then self.Routes:Update(true) end
end

function A:TogglePause()
    if self.LevelingTracker then self.LevelingTracker:Update("pause") end
    self.char.paused = not self.char.paused
    if self.LevelingTracker then self.LevelingTracker:Update("pause") end
    self.Observations:Reset()
    self.Transport:InvalidateSample()
    if self.Hearth then self.Hearth:InvalidateSample() end
    if self.WorldInteract then self.WorldInteract:Refresh() end
    if self.RareScanner then self.RareScanner:Refresh() end
    self.Navigation:RefreshPins()
    if self.QuestAssist then self.QuestAssist:Update(true) end
    self.dirty = true
end

function A:Diagnostics()
    local lines = { "AiLeveling " .. self.version, "Interface: " .. tostring(self.interface),
        "客户端构建: " .. tostring(self.build),
        "QuestieDB: " .. tostring(C_AddOns.GetAddOnMetadata("QuestieDB", "Version")),
        "QuestieDB contract: " .. tostring(LibQuestieDB and LibQuestieDB.contractVersion),
        "HereBeDragons: " .. tostring(C_AddOns.GetAddOnMetadata("HereBeDragons", "Version")),
        "角色决策版本: " .. tostring(self.state and self.state.revision),
        "已索引任务: " .. tostring(self.Data.count or 0),
        "参考服务 NPC: " .. tostring(self.Data.serviceCount or 0),
        "自有目的地: " .. tostring(self.Data:NodeCount()),
        "地面移动估时: 直线距离 ÷ 当前跑速",
        "参考任务／奖励／经验模型: " .. (self.TaskGuide and table.concat({self.TaskGuide.Counts()},"／") or "0／0／0"),
        "副本锁定信息: " .. tostring(self.state and self.state.instanceLocksKnown),
        "原生保存进度条数: " .. tostring(self.state and self.state.instanceLockouts and #self.state.instanceLockouts or 0),
        "任务日志: "..tostring(self.state and self.state.questCount).."/"..tostring(self.state and self.state.questLimit),
        "通用背包空格: "..tostring(self.state and self.state.freeSlots),
        "最低装备耐久: "..tostring(self.state and self.state.durability),
        "原生飞行状态: "..tostring(self.state and self.state.onTaxi),
        "实机验证: 待完成" }
    if self.Progression and self.state and self.Experience then
        local curve,source=self.Progression.Curve(self.state,self.Content)
        lines[#lines+1]="升级经验门槛: "..(curve and (source=="authored" and "自有已验证曲线" or "当前构建参考表已匹配") or source)
    end
    for _, missing in ipairs(self.missing or {}) do lines[#lines + 1] = "缺少接口: " .. missing end
    return table.concat(lines, "\n")
end

function A:Initialize()
    local version, build, _, interface = GetBuildInfo()
    self.clientVersion=version
    self.build = build
    self.interface = interface
    AiLevelingDB = type(AiLevelingDB)=="table" and AiLevelingDB or {}
    AiLevelingCharDB = type(AiLevelingCharDB)=="table" and AiLevelingCharDB or {}
    self.settings, self.char = AiLevelingDB, AiLevelingCharDB
    self:NormalizeSettings(self.settings)
    self:NormalizeCharacter(self.char)
    self.state = { revision = 0, completed = {}, quests = {} }
    self.UI:Create()
    self.QuestAssist:Create()
    self.Navigation:Initialize()
    self.missing = {}
    local capabilities = {
        {"C_QuestLog.GetInfo", C_QuestLog and C_QuestLog.GetInfo},
        {"C_QuestLog.GetAllCompletedQuestIDs", C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs},
        {"C_QuestLog.GetQuestObjectives", C_QuestLog and C_QuestLog.GetQuestObjectives},
        {"C_QuestLog.ReadyForTurnIn", C_QuestLog and C_QuestLog.ReadyForTurnIn},
        {"C_Map.GetPlayerMapPosition", C_Map and C_Map.GetPlayerMapPosition},
        {"C_Container.GetContainerItemInfo", C_Container and C_Container.GetContainerItemInfo},
        {"C_Item.GetItemInfo", C_Item and C_Item.GetItemInfo},
        {"C_Item.GetItemInfoInstant", C_Item and C_Item.GetItemInfoInstant},
        {"C_Item.GetItemStats", C_Item and C_Item.GetItemStats},
        {"C_Item.RequestLoadItemDataByID", C_Item and C_Item.RequestLoadItemDataByID},
        {"UnitOnTaxi", UnitOnTaxi},
    }
    for _, c in ipairs(capabilities) do if type(c[2]) ~= "function" then self.missing[#self.missing + 1] = c[1] end end
    if WOW_PROJECT_ID ~= WOW_PROJECT_CAMELOT or not WOW_PROJECT_CAMELOT or interface ~= 16001 then
        self.error = "此开发构建仅适配 Forever（Interface 16001）。"
    elseif #self.missing > 0 then
        self.error = "关键接口缺失，请打开数据页查看。"
    else
        local ok, message = self.Data:Connect(LibQuestieDB)
        if not ok then self.error = message end
    end
    if self.error then self.UI:Render(); return end
    if self.WorldInteract then self.WorldInteract:Initialize() end
    self.ready = true
    if self.RareScanner then self.RareScanner:Initialize() end
    self.State:Refresh(true)
    self:Queue("index", function()
        self.Data:BuildIndex()
        self.indexReady = true
        self.State:Refresh(true)
    end)
    self:Message("开发构建已加载。/ail 打开详情，/ail status 查看状态。")
end

function A:Start()
    local ok,message=xpcall(function() self:Initialize() end,function(err)
        geterrorhandler()(err)
        return tostring(err)
    end)
    if not ok then
        self.ready=false
        self.jobs={}
        self.startupError=message
        self:Message("加载失败："..message)
        if self.UI then self.UI:ShowStartupError(message) end
    end
    return ok
end

local frame = CreateFrame("Frame")
A.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
    if A.ready and A.LevelingTracker and (event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_XP_UPDATE" and (...)=="player" or
        event=="PLAYER_FLAGS_CHANGED" and (...)=="player" or event=="PLAYER_LEVEL_UP" or event=="PLAYER_DEAD" or
        event=="PLAYER_ALIVE" or event=="PLAYER_UNGHOST" or event=="PLAYER_LOGOUT") then A.LevelingTracker:Update(event) end
    if A.ready and A.State and A.State.QuestOffersEvent then A.State:QuestOffersEvent(event) end
    local hearthChanged=A.ready and A.Hearth and A.Hearth:Event(event,...)
    if hearthChanged then A.dirty=true end
    if A.ready and A.Services then A.Services:Event(event,...) end
    if A.ready and A.Dungeon and A.Dungeon.EncounterEvent then A.Dungeon:EncounterEvent(event,...) end
    if event == "ADDON_LOADED" then
        if ... ~= addonName then return end
        A:Start()
        if not A.ready then return end
        for _, name in ipairs({"PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED",
            "QUEST_DATA_LOAD_RESULT", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_COMPLETE", "QUEST_PROGRESS", "QUEST_FINISHED", "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_DETAIL", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE",
            "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "GROUP_ROSTER_UPDATE", "UNIT_CONNECTION", "PLAYER_ROLES_ASSIGNED", "UNIT_SPEED", "PLAYER_TARGET_CHANGED", "PLAYER_FLAGS_CHANGED", "PLAYER_LOGOUT",
            "ZONE_CHANGED_NEW_AREA", "PLAYER_DIFFICULTY_CHANGED", "PLAYER_ALIVE", "PLAYER_DEAD", "PLAYER_UNGHOST", "PLAYER_REGEN_ENABLED",
            "PLAYER_REGEN_DISABLED", "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_COOLDOWN", "BAG_OPEN", "BAG_CLOSED", "UPDATE_INVENTORY_DURABILITY", "MERCHANT_SHOW", "MERCHANT_CLOSED"}) do
            frame:RegisterEvent(name)
        end
        for _, name in ipairs({"SKILL_LINES_CHANGED", "UPDATE_FACTION", "SPELLS_CHANGED"}) do
            frame:RegisterEvent(name)
        end
        for _,name in ipairs({"TAXIMAP_OPENED","TAXIMAP_CLOSED","TAXI_NODE_STATUS_CHANGED","HEARTHSTONE_BOUND","UPDATE_INSTANCE_INFO","CHAT_MSG_SYSTEM","UI_ERROR_MESSAGE","UI_INFO_MESSAGE"}) do frame:RegisterEvent(name) end
        for _,name in ipairs({"TRAINER_SHOW","TRAINER_UPDATE","TRAINER_CLOSED","TRAINER_DESCRIPTION_UPDATE","TRAINER_SERVICE_INFO_NAME_UPDATE","CONFIRM_BINDER"}) do frame:RegisterEvent(name) end
        for _,name in ipairs({"ENCOUNTER_START","ENCOUNTER_END"}) do frame:RegisterEvent(name) end
        for _,name in ipairs({"UNIT_SPELLCAST_START","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_FAILED_QUIET","UNIT_SPELLCAST_INTERRUPTED"}) do frame:RegisterEvent(name) end
        if C_TooltipInfo and C_TooltipInfo.GetHyperlink then frame:RegisterEvent("TOOLTIP_DATA_UPDATE") end
        if C_Spell and C_Spell.GetSpellDescription then frame:RegisterEvent("SPELL_TEXT_UPDATE") end
        A.Instances:Request()
    elseif event=="QUEST_COMPLETE" then
        A.QuestAssist:RewardDialog(true)
    elseif event=="QUEST_FINISHED" then
        A.QuestAssist:RewardDialog(false)
    elseif event=="UPDATE_INSTANCE_INFO" then
        A.Instances:Capture();A:RequestRefresh()
    elseif event=="CHAT_MSG_SYSTEM" then
        A.Instances:SystemMessage(...)
    elseif event=="UI_ERROR_MESSAGE" or event=="UI_INFO_MESSAGE" then
        A.Instances:Error(...)
    elseif event == "QUEST_ACCEPTED" then
        local id = ...
        if A.State.confirmed then A.State.confirmed[id] = nil end
        A:RequestRefresh()
    elseif event=="QUEST_DATA_LOAD_RESULT" then
        local id,success=...
        if success and A.state.quests and A.state.quests[id] then A:RequestRefresh() end
    elseif event == "QUEST_TURNED_IN" then
        local before=A.char.turnIns[(...)] or 0
        A.State:TurnedIn(...)
        if A.LevelingTracker and (A.char.turnIns[(...)] or 0)>before then A.LevelingTracker:QuestTurnedIn() end
        A:RequestRefresh()
    elseif event=="UNIT_SPEED" then
        if (...)=="player" then A:RequestRefresh() end
    elseif event:sub(1,15)=="UNIT_SPELLCAST_" then
        if hearthChanged then A:RequestRefresh() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        A.QuestAssist:ApplyPending()
        A.UI:Combat(false)
        A:RequestRefresh()
    elseif event=="PLAYER_TARGET_CHANGED" then
        A.QuestAssist:TargetStatus()
    elseif event == "PLAYER_REGEN_DISABLED" then
        A.UI:Combat(true)
    elseif event == "BAG_UPDATE_COOLDOWN" then
        A.QuestAssist:Cooldowns()
        A:RequestRefresh()
    elseif event=="TAXIMAP_OPENED" then
        A.Transport:CaptureTaxi();A:RequestRefresh()
    elseif event=="TAXIMAP_CLOSED" then
        A.Transport.taxiSelected=nil
    elseif event=="HEARTHSTONE_BOUND" then
        A.State:Position();A.Transport:Bound();A:RequestRefresh()
    elseif event == "BAG_OPEN" or event == "BAG_CLOSED" then
        A.QuestAssist:Highlight()
    elseif event == "TOOLTIP_DATA_UPDATE" or event == "SPELL_TEXT_UPDATE" then
        local id=...
        local pending=A.Items and (event=="TOOLTIP_DATA_UPDATE" and A.Items.tooltipData or event=="SPELL_TEXT_UPDATE" and A.Items.spellData)
        if id and pending and pending[id] then
            pending[id]=nil
            A.State.fingerprint=nil
            A:RequestRefresh()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local id = ...
        A.requestedItems[id] = nil
        A:RequestRefresh()
    else
        if A.Merchant then A.Merchant:Event(event) end
        if event=="TAXI_NODE_STATUS_CHANGED" or event=="PLAYER_ENTERING_WORLD" or event=="UPDATE_FACTION" then
            A.Transport.dirty=true
            if event=="UPDATE_FACTION" or event=="TAXI_NODE_STATUS_CHANGED" then A.Transport:InvalidateFlights() end
        end
        if A.Observations and (event == "QUEST_LOG_UPDATE" or event == "BAG_UPDATE_DELAYED") then
            A.Observations.progressAt = GetTime()
        end
        if A.Observations and (event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_UNGHOST") then A.Observations:Reset() end
        if event=="PLAYER_ENTERING_WORLD" then A.Dungeon.lastTick=nil;A.Instances:Request();A.Transport:World() end
        A:RequestRefresh()
    end
    if A.ready and A.QuestAssist and A.QuestAssist.DialogEvent then A.QuestAssist:DialogEvent(event) end
end)

local tick = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    if not A.ready then return end
    if A.Transport:InFlight() or A.Hearth and A.Hearth:InTransit() then A.jobs.plan=nil end
    if A.refreshAt and GetTime() >= A.refreshAt then
        A.refreshAt = nil
        A.State:Refresh()
    end
    local start = debugprofilestop()
    -- One resume per job per frame; jobs yield after small batches.
    for _, key in ipairs({"index", "plan"}) do
        local job = A.jobs[key]
        if job then
            local ok, err = coroutine.resume(job)
            if not ok then
                A.jobs[key] = nil
                A.error = "计算失败：" .. tostring(err)
                A.dirty = true
                geterrorhandler()(err)
            elseif coroutine.status(job) == "dead" and A.jobs[key] == job then
                A.jobs[key] = nil
            end
        end
        if debugprofilestop() - start >= 2 then break end
    end
    tick = tick + elapsed
    if tick >= 0.2 then
        tick = 0
        A.State:Position()
        A.Transport:Update()
        if A.Hearth then A.Hearth:Update() end
        A.Instances:Update()
        A.Dungeon:Update()
        A.Observations:Update()
        if A.LevelingTracker then A.LevelingTracker:Update() end
        A.Navigation:Update()
        if A.Routes then A.Routes:Update() end
        if A.dirty then A.UI:Render(); A.dirty = false end
    end
end)

SLASH_AILEVELING1, SLASH_AILEVELING2 = "/ail", "/aileveling"
SlashCmdList.AILEVELING = function(command)
    if A.startupError then A.UI:ShowStartupError(A.startupError);return end
    if not A.UI.frame then return end
    if command == "status" then A.UI:ShowText(A:Diagnostics())
    elseif command=="stats" and A.LevelingTracker then A.UI:ShowText(A.LevelingTracker:Report())
    elseif command == "pause" then A:TogglePause()
    elseif command == "resume" then
        A.Selection:Clear()
        A.char.serviceStop=nil
        if A.Services then A.Services.binding=nil end
        if A.LevelingTracker then A.LevelingTracker:Update("resume") end
        A.char.paused=false
        if A.LevelingTracker then A.LevelingTracker:Update("resume") end
        A.Navigation.manual=nil
        A.State:Refresh(true)
    elseif command:match("^way ") then
        local map, x, y = command:match("^way (%d+) ([%d.]+) ([%d.]+)$")
        map, x, y = tonumber(map), tonumber(x), tonumber(y)
        if map and x and y and x <= 100 and y <= 100 and C_Map.GetMapInfo(map) then
            A.Navigation.manual = {map=map,x=x/100,y=y/100}
            A.Transport:InvalidateSample()
            if A.Hearth then A.Hearth:InvalidateSample() end
            A.Observations:Reset(); A.QuestAssist:Update()
            A.Navigation:RefreshPins(); A.dirty = true
        else A:Message("格式：/ail way 地图ID 横坐标 纵坐标（0—100）") end
    elseif command == "audit" then
        if not A.ready then return end
        if not A.indexReady then A:Message("任务索引尚未完成，请稍后盘点。"); return end
        A:Queue("index", function()
            local report = A.Data:Audit()
            A.UI:ShowText(report)
        end)
    else A.UI:ToggleDetails() end
end
