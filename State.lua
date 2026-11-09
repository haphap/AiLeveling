local _, A = ...
A.State = {}
local State = A.State

local offerResetEvents={PLAYER_ENTERING_WORLD=true,QUEST_ACCEPTED=true,QUEST_TURNED_IN=true,
    QUEST_REMOVED=true,PLAYER_LEVEL_UP=true,SKILL_LINES_CHANGED=true,UPDATE_FACTION=true,
    SPELLS_CHANGED=true,BAG_UPDATE_DELAYED=true,PLAYER_MONEY=true}

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
    local npc=A.Merchant and UnitGUID and A.Merchant.NpcId(UnitGUID("npc"))
    if not npc then return end
    local function valid(id)
        return (not canaccessvalue or canaccessvalue(id)) and type(id)=="number" and id>0 and id<math.huge and id%1==0
    end
    local offers={}
    local previous=self.questOffers and self.questOffers[npc]
    if event=="GOSSIP_SHOW" then
        if not C_GossipInfo or not C_GossipInfo.GetAvailableQuests then return end
        local ok,list=pcall(C_GossipInfo.GetAvailableQuests)
        if not ok or type(list)~="table" then return end
        for _,quest in pairs(list) do
            if type(quest)~="table" or not valid(quest.questID) then return end
            offers[quest.questID]=true
        end
    else
        -- A direct quest window is also an offer when the NPC skipped gossip.
        local id=GetQuestID and GetQuestID()
        if not valid(id) or previous and previous[id] then return end
        for quest in pairs(previous or {}) do offers[quest]=true end
        offers[id]=true
    end
    local same=previous~=nil
    for id in pairs(offers) do if not previous or not previous[id] then same=false end end
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
    if sets and s.clientVersion==sets.version and tostring(s.clientBuild)==sets.build and s.interface==sets.interface then
        for id in pairs(sets.skills) do skills[id]=true end
    end
    local weapons=A.WeaponSkills
    if weapons and s.clientVersion==weapons.version and tostring(s.clientBuild)==weapons.build and s.interface==weapons.interface then
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
    for _, group in ipairs({"skills", "reputations", "spells", "specializations"}) do
        for id, value in pairs(s[group]) do parts[#parts + 1] = group .. id .. ":" .. tostring(value) end
    end
    for id,skill in pairs(s.weaponSkills or {}) do
        parts[#parts+1]=table.concat({"weapon",id,skill.rank,skill.maxRank,skill.modifier,skill.tempPoints},":")
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

function State:Position(snapshot)
    snapshot=snapshot or A.state
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    snapshot.position = pos and { map = map, x = pos.x, y = pos.y } or nil
    A.Navigation:AttachNode(snapshot.position)
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
                fingerprint[#fingerprint + 1] = "b" .. bag .. ":" .. slot .. ":" .. id .. ":" .. item.stackCount
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

function State:Refresh(force)
    local previous, fingerprint = A.state, {}
    local s = { revision = previous.revision }
    s.questOffers=self.questOffers
    fingerprint[#fingerprint+1]="offers:"..(self.questOffersRevision or 0)
    s.clientVersion,s.clientBuild,s.interface=A.clientVersion,A.build,A.interface
    s.level, s.xp, s.maxXP = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
    local _, class, classId = UnitClass("player")
    local _, _, raceId = UnitRace("player")
    s.class, s.classId, s.raceId = class, classId, raceId
    s.classMask, s.raceMask = LibQuestieDB.Enum.classKeys[class], LibQuestieDB.Enum.raceMaskById[raceId]
    s.faction = UnitFactionGroup("player")
    s.quests, s.completed, s.bags, s.equipment, s.bagEntries = {}, {}, {}, {}, {}
    s.skipped, s.locked, s.samples = A.char.skipped, A.char.locked, {}
    s.role, s.groupSize = A.settings.role, GetNumGroupMembers()
    s.damageStyle=A.settings.damageStyle or "auto"
    self.Movement(s)
    s.now, s.freeSlots = GetTime(), 0
    s.groupSize = math.max(1, s.groupSize)
    fingerprint[#fingerprint+1]=State.Group(s)
    s.inInstance = IsInInstance()
    if GetInstanceInfo then
        local info={GetInstanceInfo()}
        s.instanceName,s.instanceId=info[1],info[8]
        if s.inInstance then s.instanceDifficultyId=info[3] end
    end
    s.dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") or false
    self:Qualifications(s, A.Data and A.Data.requirements)
    fingerprint[#fingerprint + 1] = qualificationKey(s)
    local completed = C_QuestLog.GetAllCompletedQuestIDs()
    s.completionKnown = type(completed) == "table"
    if s.completionKnown then
        for _, id in ipairs(completed) do s.completed[id] = true end
    else
        for id in pairs(previous.completed) do s.completed[id] = true end
    end
    fingerprint[#fingerprint + 1] = "completed:" .. tostring(s.completionKnown)
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
            local objectives = C_QuestLog.GetQuestObjectives(id) or {}
            local q = { id = id, title = info.title, level = info.level, objectives = objectives,
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
            if not questCount then s.questCount=s.questCount+1 end
            local parts = { tostring(id), tostring(q.ready), tostring(q.level), tostring(q.itemId), tostring(q.rewardXP) }
            for _, o in ipairs(objectives) do
                parts[#parts + 1] = table.concat({tostring(o.numFulfilled),tostring(o.numRequired),tostring(o.finished),
                    tostring(o.type),tostring(o.text),tostring(o.targetKind),tostring(o.targetId)}, ":")
            end
            fingerprint[#fingerprint + 1] = table.concat(parts, ":")
        end
    end
    if A.Selection then fingerprint[#fingerprint+1]=A.Selection:Snapshot(s) end
    if A.Chains then fingerprint[#fingerprint+1]=A.Chains:Snapshot(s) end
    if A.Dungeon.TaskBatchSnapshot then fingerprint[#fingerprint+1]=A.Dungeon:TaskBatchSnapshot(s) end
    table.sort(fingerprint)
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
        fingerprint[#fingerprint+1]="e"..slot..":"..(item.link or item.id)..":"..tostring(item.stats~=nil)
    end
    for id,item in pairs(s.items) do fingerprint[#fingerprint+1]="i"..id..":"..tostring(item.pending)..":"..tostring(item.usable) end
    for _,item in ipairs(s.bagEquipment) do fingerprint[#fingerprint+1]="g"..item.instanceKey..":"..tostring(item.link)..":"..tostring(item.pending) end
    self:Position(s)
    if A.Services then fingerprint[#fingerprint+1]=A.Services:Snapshot(s) end
    for kind, sample in pairs(A.char.samples) do
        s.samples[kind] = {}
        for key, value in pairs(sample) do s.samples[kind][key] = value end
        fingerprint[#fingerprint + 1] = kind .. ":" .. sample.n .. ":" .. sample.mean
    end
    A.Dungeon:Sync(s,previous)
    fingerprint[#fingerprint+1]=A.Instances:Snapshot(s)
    if s.dungeon then
        local d = s.dungeon
        local done = {}
        for index in pairs(d.done) do done[#done+1] = tostring(index) end
        table.sort(done)
        fingerprint[#fingerprint+1] = table.concat({d.id,d.round,d.phase,tostring(d.settled),math.floor(d.elapsed/30),table.concat(done,",")},":")
    end
    fingerprint[#fingerprint + 1] = table.concat({s.level, s.xp, tostring(s.maxXP), s.classId, s.raceId, s.groupSize,
        tostring(s.inInstance), A.settings.role, A.settings.minutes,
        tostring(A.settings.dungeons), tostring(s.locked), tostring(s.instanceId), tostring(s.instanceDifficultyId), tostring(s.dead),
        tostring(A.settings.waitMinutes),s.damageStyle,tostring(s.gearTarget),tostring(A.settings.gearPreference),
        tostring(s.runSpeed),tostring(s.swimSpeed)}, ":")
    local key = table.concat(fingerprint, "|")
    A.state = s
    if force or key ~= self.fingerprint then
        s.revision = s.revision + 1
        self.fingerprint = key
        if A.indexReady then A:Replan() end
        A.Navigation:RefreshPins()
    end
    A.QuestAssist:Update()
    A.dirty = true
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
