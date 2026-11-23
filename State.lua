local _, A = ...
A.State = {}
local State = A.State

local function questTitle(id,title)
    if A.Data and A.Data.QuestTitle then return A.Data:QuestTitle(id,title) end
    return title
end

local offerResetEvents={PLAYER_ENTERING_WORLD=true,QUEST_ACCEPTED=true,QUEST_TURNED_IN=true,
    QUEST_REMOVED=true,PLAYER_LEVEL_UP=true}

local function readableText(text)
    if (not canaccessvalue or canaccessvalue(text)) and type(text)=="string" and text:find("%S") then return text end
end

-- The offer contains the character's name and class in the client's current language.
local function rememberQuestText(id,description,objective)
    description,objective=readableText(description),readableText(objective)
    if not A.char or not description then return end
    local locale=GetLocale()
    A.char.questText=A.char.questText or {}
    local texts=A.char.questText[locale] or {}
    A.char.questText[locale]=texts
    local entry=texts[id]
    if entry and entry.description==description and (not objective or entry.objective==objective) then return end
    texts[id]={description=description,objective=objective or (entry and entry.objective)}
    return true
end

function State:QuestText(id)
    local index=C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
    if (not canaccessvalue or canaccessvalue(index)) and type(index)=="number" and index>0 and GetQuestLogQuestText then
        rememberQuestText(id,GetQuestLogQuestText(index))
    end
    local texts=A.char and A.char.questText and A.char.questText[GetLocale()]
    local entry=texts and texts[id]
    if entry then return entry.description,entry.objective end
end

-- Observed offers belong to this NPC and this eligibility context, not to saved progress.
function State:QuestOffersEvent(event)
    if offerResetEvents[event] then
        if self.questOffers and next(self.questOffers) then
            self.questOffers={}
            self.questOffersRevision=(self.questOffersRevision or 0)+1
        end
        return
    end
    if event~="GOSSIP_SHOW" and event~="QUEST_DETAIL" then return end
    local function valid(id)
        return (not canaccessvalue or canaccessvalue(id)) and type(id)=="number" and id>0 and id<math.huge and id%1==0
    end
    local detailId
    if event=="QUEST_DETAIL" then
        detailId=GetQuestID and GetQuestID()
        if not valid(detailId) then return end
        if GetQuestText and rememberQuestText(detailId,GetQuestText(),GetObjectiveText and GetObjectiveText()) then
            local browser=A.UI and A.UI.Browser
            if browser and browser.selected and browser.selected.questId==detailId and browser.frame:IsVisible() then browser:Detail() end
        end
    end
    local npc=A.Merchant and UnitGUID and A.Merchant.NpcId(UnitGUID("npc"))
    if not npc then return end
    local offers={}
    local previous=self.questOffers and self.questOffers[npc]
    local location={};self:Position(location)
    local point=location.position
    if point then
        point.entityKind,point.entityId,point.approximate="npc",npc,true
        local name=UnitName and UnitName("npc")
        if (not canaccessvalue or canaccessvalue(name)) and type(name)=="string" then point.entityName=name end
    end
    local function offer(id,title,level,repeatable)
        if canaccessvalue and not canaccessvalue(title) or type(title)~="string" then title=nil end
        if canaccessvalue and not canaccessvalue(level) or type(level)~="number" then level=nil end
        return {id=id,title=questTitle(id,title) or ("任务 #"..id),questLevel=level,nativeOffer=point,
            repeatable=(not canaccessvalue or canaccessvalue(repeatable)) and repeatable==true}
    end
    if event=="GOSSIP_SHOW" then
        if not C_GossipInfo or not C_GossipInfo.GetAvailableQuests then return end
        local ok,list=pcall(C_GossipInfo.GetAvailableQuests)
        if not ok or type(list)~="table" then return end
        for _,quest in pairs(list) do
            if type(quest)~="table" or not valid(quest.questID) then return end
            offers[quest.questID]=offer(quest.questID,quest.title,quest.questLevel,quest.repeatable)
        end
    else
        -- A direct quest window is also an offer when the NPC skipped gossip.
        local id=detailId
        if previous and previous[id] then return end
        for quest,info in pairs(previous or {}) do offers[quest]=info end
        offers[id]=offer(id,GetTitleText and GetTitleText())
    end
    local same=previous~=nil
    for id,info in pairs(offers) do
        local old=previous and previous[id]
        local p,op=info.nativeOffer,old and old.nativeOffer
        if not old or info.title~=old.title or info.questLevel~=old.questLevel or info.repeatable~=old.repeatable or
            (p~=nil)~=(op~=nil) or p and op and (p.map~=op.map or p.x~=op.x or p.y~=op.y) then same=false end
    end
    for id in pairs(previous or {}) do if not offers[id] then same=false end end
    if same then return end
    local snapshot={}
    for id,quests in pairs(self.questOffers or {}) do snapshot[id]=quests end
    snapshot[npc]=offers
    self.questOffers=snapshot
    self.questOffersRevision=(self.questOffersRevision or 0)+1
end

function State.Status(snapshot, id)
    local q = snapshot.quests[id]
    if q then return q.ready and "ready" or "active" end
    if snapshot.completed[id] then return "turnedIn" end
    if snapshot.completionKnown == false then return "unknown" end
    return "notStarted"
end

function State:Qualifications(s, requirements)
    s.spells, s.skills, s.reputations, s.specializations = {}, {}, {}, {}
    s.weaponSkills=nil
    requirements = requirements or {}
    local skills={}
    for id in pairs(requirements.skills or {}) do skills[id]=true end
    local trainers=A.Services and A.Services.TrainerData(s)
    for id in pairs(trainers and trainers.skills or {}) do skills[id]=true end
    local sets=A.ItemSets
    if sets and s.clientVersion==sets.version and s.interface==sets.interface then
        for id in pairs(sets.skills) do skills[id]=true end
    end
    local weapons=A.WeaponSkills
    if weapons and s.clientVersion==weapons.version and s.interface==weapons.interface then
        s.weaponSkills={}
        for _,weapon in pairs(weapons.subclasses) do skills[weapon.skill]=true end
    end
    local function number(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
    for id in pairs(skills) do
        if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
            local skill = C_SkillInfo.GetSkillLineInfoByID(id)
            s.skills[id] = skill and skill.rank or 0
            if s.weaponSkills and skill and number(skill.rank) and skill.rank>=0 and number(skill.maxRank) and
                skill.maxRank>0 and skill.rank<=skill.maxRank and number(skill.modifier) and number(skill.tempPoints) then
                s.weaponSkills[id]={rank=skill.rank,maxRank=skill.maxRank,modifier=skill.modifier,tempPoints=skill.tempPoints}
            end
        end
    end
    for id in pairs(requirements.reputations or {}) do
        if C_Reputation and C_Reputation.GetFactionDataByID then
            local faction = C_Reputation.GetFactionDataByID(id)
            s.reputations[id] = faction and faction.currentStanding
        end
    end
    local known = C_SpellBook and C_SpellBook.IsSpellKnown
    for id in pairs(requirements.spells or {}) do
        if known then s.spells[id] = known(id) == true end
    end
    -- QuestieDB specialization keys contain both profession skill IDs and learned spells.
    for id in pairs(requirements.specializations or {}) do
        local skill = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID and C_SkillInfo.GetSkillLineInfoByID(id)
        if skill and skill.rank > 0 then s.specializations[id] = true
        elseif known then s.specializations[id] = known(id) == true end
    end
end

local function qualificationKey(s)
    local parts = {}
    local requirements=A.Data and A.Data.requirements or {}
    for _,group in ipairs({"skills","reputations","spells","specializations"}) do
        for id,value in pairs(s[group]) do
            local thresholds=requirements[group] and requirements[group][id]
            if type(value)=="number" then
                local tier=group=="skills" and value>0 and 1 or nil
                if type(thresholds)=="table" then
                    for n in pairs(thresholds) do if value>=n and (not tier or tier<n) then tier=n end end
                end
                value=tier or "below"
            end
            parts[#parts+1]=group..id..":"..tostring(value)
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

function State:Position(snapshot)
    snapshot=snapshot or A.state
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if snapshot==A.state and pos and (not snapshot.position or snapshot.position.map~=map) then A:RequestRefresh() end
    snapshot.position = pos and { map = map, x = pos.x, y = pos.y } or nil
end

function State.Movement(snapshot)
    if not GetUnitSpeed then return end
    local _,run,_,swim=GetUnitSpeed("player")
    local function usable(value)
        return (not canaccessvalue or canaccessvalue(value)) and type(value)=="number" and value>0 and value<math.huge
    end
    snapshot.runSpeed=usable(run) and run or nil
    snapshot.swimSpeed=usable(swim) and swim or nil
end

function State:TurnedIn(id)
    self.confirmed = self.confirmed or {}
    if self.confirmed[id] then return end
    A.state.completed[id] = true
    -- QUEST_TURNED_IN is the acknowledgement; log removal is not one.
    self.confirmed[id] = true
    A.char.turnIns[id] = (A.char.turnIns[id] or 0) + 1
end

function State:SnapshotBags(s,fingerprint)
    s.bags,s.bagEntries,s.freeSlots={},{},0
    s.inventory={bags={},slots={}}
    local indexed=A.Data and A.Data.requirements and A.Data.requirements.startItems
    local function read(bag,special)
        local free,family=C_Container.GetContainerNumFreeSlots(bag)
        if bag==0 then family=0
        elseif special and family==0 then family=nil end
        s.inventory.bags[bag]={free=free or 0,family=family}
        if family==0 then s.freeSlots=s.freeSlots+(free or 0) end
        local slots=bag==KEYRING_CONTAINER and GetKeyRingSize and GetKeyRingSize() or C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item then
                local id = item.itemID
                s.bags[id] = (s.bags[id] or 0) + item.stackCount
                s.bagEntries[#s.bagEntries+1]={id=id,link=item.hyperlink,key=bag..":"..slot,bag=bag,slot=slot,count=item.stackCount,locked=item.isLocked}
            end
        end
    end
    local constants=Constants and Constants.InventoryConstants or {}
    local bags=constants.NumBagSlots or NUM_BAG_SLOTS
    local extra=constants.NumReagentBagSlots or NUM_REAGENTBAG_SLOTS or 0
    for bag=0,bags+extra do read(bag,bag>bags) end
    -- A hidden keyring still contains carried items; its free slots are never general space.
    if KEYRING_CONTAINER and (KEYRING_CONTAINER<0 or KEYRING_CONTAINER>bags+extra) and
        C_ActionBar and C_ActionBar.ShouldShowKeyring and C_ActionBar.ShouldShowKeyring() then
        read(KEYRING_CONTAINER,true)
    end
    local pickupItems=A.Data and A.Data.requirements and A.Data.requirements.pickupItems
    for id,count in pairs(s.bags) do
        if id==6948 or indexed and indexed[id] then fingerprint[#fingerprint+1]="has:"..id end
        local thresholds=pickupItems and pickupItems[id]
        if thresholds then
            for need in pairs(thresholds) do
                if count>=need then fingerprint[#fingerprint+1]="pickup:"..id..":"..need end
            end
        end
    end
end

local function groupValue(fn,unit,other)
    if type(fn)~="function" then return end
    local ok,value=pcall(fn,unit,other)
    if ok and (not canaccessvalue or canaccessvalue(value)) then return value end
end

function State.Group(s)
    local raid=groupValue(IsInRaid)
    local g={tank=0,healer=0,damage=0,unknown=0,online=0,offline=0,connectionUnknown=0,raid=raid}
    local roles={TANK="tank",HEALER="healer",DAMAGER="damage"}
    for i=1,s.groupSize do
        local unit=raid==true and ("raid"..i) or i==1 and "player" or ("party"..(i-1))
        local connected=groupValue(UnitIsConnected,unit)
        local role=groupValue(UnitGroupRolesAssigned,unit)
        if not roles[role] and (unit=="player" or groupValue(UnitIsUnit,unit,"player")==true) then role=s.role end
        if connected==false then g.offline=g.offline+1
        elseif connected~=true or raid==nil and s.groupSize>1 then g.connectionUnknown=g.connectionUnknown+1
        else
            g.online=g.online+1
            local key=roles[role] or "unknown";g[key]=g[key]+1
        end
    end
    s.group=g
    return table.concat({tostring(raid),g.tank,g.healer,g.damage,g.unknown,g.online,g.offline,g.connectionUnknown},":")
end

function State:Refresh(force, manual)
    local previous, fingerprint = A.state, {}
    local restart=force
    local s = { revision = previous.revision }
    s.questOffers=self.questOffers
    s.questNPC=s.questOffers and A.Merchant and UnitGUID and A.Merchant.NpcId(UnitGUID("npc"))
    s.clientVersion,s.clientBuild,s.interface=A.clientVersion,A.build,A.interface
    s.level, s.xp, s.maxXP = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
    local className, class, classId = UnitClass("player")
    local _, _, raceId = UnitRace("player")
    s.class, s.classId, s.raceId = class, classId, raceId
    s.className=className
    s.classMask, s.raceMask = LibQuestieDB.Enum.classKeys[class], LibQuestieDB.Enum.raceMaskById[raceId]
    s.faction = UnitFactionGroup("player")
    s.quests, s.completed, s.bags, s.equipment, s.bagEntries = {}, {}, {}, {}, {}
    s.skipped, s.locked, s.samples = A.char.skipped, A.char.locked, {}
    s.role, s.groupSize = A.settings.role, GetNumGroupMembers()
    s.damageStyle=A.settings.damageStyle or "auto"
    s.talentTree=A.Talents and A.Talents:MainTree()
    self.Movement(s)
    s.now, s.freeSlots = GetTime(), 0
    s.groupSize = math.max(1, s.groupSize)
    fingerprint[#fingerprint+1]=State.Group(s)
    s.inInstance,s.instanceType = IsInInstance()
    if GetInstanceInfo then
        local info={GetInstanceInfo()}
        s.instanceName,s.instanceId=info[1],info[8]
        if s.inInstance then s.instanceDifficultyId=info[3] end
    end
    if s.instanceId==nil and UnitPosition then s.instanceId=select(4,UnitPosition("player")) end
    s.dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") or false
    self:Qualifications(s, A.Data and A.Data.requirements)
    local qualifications=qualificationKey(s)
    if self.qualifications and self.qualifications~=qualifications and self.questOffers and next(self.questOffers) then
        self.questOffersRevision=(self.questOffersRevision or 0)+1
        self.questOffers=nil;s.questOffers=nil
    end
    self.qualifications=qualifications
    fingerprint[#fingerprint+1]=qualifications
    fingerprint[#fingerprint+1]="offers:"..(self.questOffersRevision or 0)
    local completed = C_QuestLog.GetAllCompletedQuestIDs()
    local newlyCompleted=false
    s.completionKnown = type(completed) == "table"
    if s.completionKnown then
        for _, id in ipairs(completed) do
            if not previous.completed[id] then newlyCompleted=true end
            s.completed[id] = true
        end
    else
        for id in pairs(previous.completed) do s.completed[id] = true end
    end
    fingerprint[#fingerprint + 1] = "completed:" .. tostring(s.completionKnown and #completed)
    for id in pairs(self.confirmed or {}) do s.completed[id] = true end
    local deliveries=0
    for id,count in pairs(A.char.turnIns or {}) do
        if count>0 then s.completed[id]=true;deliveries=deliveries+count end
    end
    fingerprint[#fingerprint+1]="turnins:"..deliveries
    local entries,questCount=C_QuestLog.GetNumQuestLogEntries()
    s.questCount=questCount or 0
    s.questLimit=C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()
    for i = 1, entries do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and info.questID > 0 then
            local id = info.questID
            local nativeObjectives=C_QuestLog.GetQuestObjectives(id) or {}
            local objectives={}
            local q = { id = id, title = questTitle(id,info.title), level = info.level, objectives = objectives,
                ready = C_QuestLog.ReadyForTurnIn(id) == true, logIndex = i }
            if GetQuestLogSpecialItemInfo then
                local link = GetQuestLogSpecialItemInfo(i)
                q.itemId = link and tonumber(link:match("item:(%d+)"))
            end
            if GetQuestLogRewardXP then
                local ok,xp=pcall(GetQuestLogRewardXP,id)
                -- shortcut: zero may be uncached; accept it after the client cache contract is verified.
                if ok and (not canaccessvalue or canaccessvalue(xp)) and type(xp)=="number" and xp>0 and xp<math.huge then
                    q.rewardXP,q.rewardXPLevel=xp,s.level
                end
            end
            s.quests[id] = q
            local old=previous.quests[id]
            if old and old.title~=q.title then A.dirty=true end
            if not old or old.ready~=q.ready then restart=true end
            if not questCount then s.questCount=s.questCount+1 end
            local parts = { tostring(id), tostring(q.ready), tostring(q.level), tostring(q.itemId), tostring(q.rewardXP) }
            for index,o in ipairs(nativeObjectives) do
                objectives[index]=o
                local before=old and (old.objectives or {})[index]
                local done=o.finished or (type(o.numRequired)=="number" and o.numRequired>0 and
                    type(o.numFulfilled)=="number" and o.numFulfilled>=o.numRequired) or false
                if done and not o.finished then
                    local copy={};for k,v in pairs(o) do copy[k]=v end
                    copy.finished=true;objectives[index]=copy
                end
                if not before or (before.finished==true)~=done or before.type~=o.type or before.targetId~=o.targetId or
                    before.numRequired~=o.numRequired then restart=true end
                if not before or before.numFulfilled~=o.numFulfilled or before.text~=o.text then A.dirty=true end
                local label=o.text and o.text:gsub("%d+%s*/%s*%d+", "#/#"):gsub("%d+[.,]?%d*%s*%%","#%%")
                parts[#parts+1]=table.concat({tostring(done),tostring(o.numRequired),tostring(o.type),
                    tostring(label),tostring(o.targetKind),tostring(o.targetId)}, ":")
            end
            fingerprint[#fingerprint + 1] = table.concat(parts, ":")
        end
    end
    for id in pairs(previous.quests) do if not s.quests[id] then restart=true end end
    if A.Selection then fingerprint[#fingerprint+1]=A.Selection:Snapshot(s) end
    if A.Chains then fingerprint[#fingerprint+1]=A.Chains:Snapshot(s) end
    self:SnapshotBags(s,fingerprint)
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then
            s.equipment[slot] = {id=id,link=GetInventoryItemLink("player",slot)}
        end
    end
    A.Items:Snapshot(s)
    fingerprint[#fingerprint+1]=A.Supplies:Snapshot(s)
    if A.Merchant then fingerprint[#fingerprint+1]=A.Merchant:Snapshot(s) end
    fingerprint[#fingerprint+1]="weapons:"..tostring(s.capabilities.dualWield)..":"..tostring(s.capabilities.titanGrip)
    A.Transport:Snapshot(s)
    fingerprint[#fingerprint+1]=A.Transport.Key(s)
    A.Gear:SyncTarget(s)
    for slot,item in pairs(s.equipment) do
        fingerprint[#fingerprint+1]="e"..slot..":"..A.Items.Key(item)
    end
    for id,item in pairs(s.items) do fingerprint[#fingerprint+1]="i"..id..":"..A.Items.Key(item) end
    self:Position(s)
    -- The world map exposes quest pins separately from intermediate travel waypoints.
    local map=s.position and s.position.map
    if map and C_QuestLog.GetQuestsOnMap then
        for _,pin in ipairs(C_QuestLog.GetQuestsOnMap(map) or {}) do
            local quest=s.quests[pin.questID]
            if quest and pin.mapID==map and (pin.childDepth or 0)==0 and not pin.isQuestStart and not pin.isMapIndicatorQuest and
                type(pin.x)=="number" and pin.x>=0 and pin.x<=1 and type(pin.y)=="number" and pin.y>=0 and pin.y<=1 then
                -- Multiple markers do not identify a particular objective or recipient.
                if quest.mapPin==nil then
                    quest.mapPin={map=map,x=pin.x,y=pin.y,ready=quest.ready}
                else quest.mapPin=false end
            end
        end
        for id,quest in pairs(s.quests) do
            local pin=quest.mapPin
            if pin then
                local old=previous.quests[id] and previous.quests[id].mapPin
                -- The map and quest log can update in separate frames.
                if old and old.map==pin.map and old.x==pin.x and old.y==pin.y then pin.ready=old.ready end
                fingerprint[#fingerprint+1]=string.format("poi:%d:%.4f:%.4f:%s",id,pin.x,pin.y,tostring(pin.ready))
            end
        end
    end
    if A.Dungeon.TaskBatchSnapshot then fingerprint[#fingerprint+1]=A.Dungeon:TaskBatchSnapshot(s) end
    fingerprint[#fingerprint+1]="map:"..tostring(s.position and s.position.map)
    if A.Services then fingerprint[#fingerprint+1]=A.Services:Snapshot(s) end
    local stop=s.serviceStop
    if s.locked or s.taskBatch or s.gearTarget or stop or s.inInstance or s.dead then
        s.routeFocus=table.concat({s.locked or "",s.taskBatch and s.taskBatch.id or "",s.gearTarget or "",
            stop and stop.kind or "",stop and stop.npcId or "",stop and stop.taxiId or "",stop and stop.learnKey or "",
            s.inInstance and (s.instanceId or "instance") or "",s.dead and "dead" or ""},":")
    end
    for kind, sample in pairs(A.char.samples) do
        s.samples[kind] = {}
        for key, value in pairs(sample) do s.samples[kind][key] = value end
    end
    fingerprint[#fingerprint+1]=A.Instances:Snapshot(s)
    fingerprint[#fingerprint + 1] = table.concat({s.level, tostring(s.maxXP), s.classId, s.raceId, s.groupSize,
        tostring(s.inInstance), A.settings.role, A.settings.minutes,
        tostring(A.settings.dungeons), tostring(s.locked), tostring(s.instanceId), tostring(s.instanceDifficultyId), tostring(s.dead),
        tostring(A.settings.waitMinutes),s.damageStyle,tostring(s.talentTree),tostring(s.gearTarget),tostring(A.settings.gearPreference)}, ":")
    table.sort(fingerprint)
    local key = table.concat(fingerprint, "|")
    A.state = s
    A.Gear:ScanBagOffers(s)
    if force or newlyCompleted or key ~= self.fingerprint or A.TaskQueue and A.TaskQueue.StockChanged(A.plan,previous.bags,s.bags) then
        s.revision = s.revision + 1
        self.fingerprint = key
        restart=restart or previous.routeFocus~=s.routeFocus or previous.level~=s.level or previous.dead~=s.dead or
            previous.inInstance~=s.inInstance or previous.instanceId~=s.instanceId or
            (previous.freeSlots==0)~=(s.freeSlots==0) or previous.ignoreRepair~=s.ignoreRepair or
            (previous.durability and previous.durability<0.2)~=(s.durability and s.durability<0.2)
        if A.indexReady then A:Replan(restart,force and manual~=false) end
        A.Navigation:RefreshPins()
        A.dirty = true
    end
    A.QuestAssist:Update()
end

function State.Observe(samples, kind, seconds)
    if seconds <= 0 or seconds > 7200 then return end
    local s = samples[kind] or { n = 0, mean = seconds, m2 = 0 }
    if s.n >= 5 and (seconds > s.mean * 4 or seconds < s.mean / 4) then return end
    if s.n >= 100 then s.n, s.m2 = 50, s.m2 / 2 end
    s.n = s.n + 1
    local delta = seconds - s.mean
    s.mean = s.mean + delta / s.n
    s.m2 = s.m2 + delta * (seconds - s.mean)
    samples[kind] = s
end

function State.Estimate(reference, sample)
    if not sample or sample.unit ~= "ratio" or sample.n < 3 then return reference end
    local weight = math.min(0.75, sample.n / (sample.n + 10))
    return reference * (1 - weight + sample.mean * weight)
end
