local _, A = ...
A.Data = { byLevel = {}, cache = {}, count = 0 }
local D = A.Data
local fields = { "name", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses",
    "preQuestGroup", "preQuestSingle", "exclusiveTo", "parentQuest", "nextQuestInChain",
    "requiredMaxLevel", "availableUntilCompleted", "availableStartingWith", "disabledByQuest",
    "requiredSkill", "requiredRanks", "requiredMinRep", "requiredMaxRep", "requiredSpell",
    "requiredSpecialization", "sourceItemId", "requiredSourceItems", "specialFlags", "questFlags", "zoneOrSort", "breadcrumbForQuestId", "startedBy" }

local function usableSpawn(p)
    return type(p[1])=="number" and type(p[2])=="number" and p[1]>=0 and p[1]<=100 and p[2]>=0 and p[2]<=100 and
        (not p[3] or p[3]==0)
end

-- Parse only numeric map entries from the provider's documented Lua data string.
-- No user content or upstream source string is executed.
function D.ParseMap(source)
    local result = {}
    if type(source) ~= "string" then return result end
    source = source:gsub("%-%-[^\n]*", "")
    for area, map in source:gmatch("%[(%d+)%]%s*=%s*(%d+)") do result[tonumber(area)] = tonumber(map) end
    return result
end

function D:Connect(db)
    if not db or type(db.RequireContract) ~= "function" then return false, "请安装 QuestieDB v1.0.12 或兼容版本。" end
    local ok, message = db.RequireContract(4)
    if not ok then return false, message end
    self.db = db
    self.cache,self.chainIndex={},nil
    self.servicesByMap,self.serviceCount={},0
    self.amenitiesByMap,self.amenityCount={},0
    self.ids={}
    local seen={}
    for _,id in ipairs(db.Quest.GetAllIds()) do self.ids[#self.ids+1]=id;seen[id]=true end
    for id in pairs(A.Content.quests) do if not seen[id] then self.ids[#self.ids+1]=id end end
    table.sort(self.ids)
    local zones = db.Support.Get("ZoneDB")
    self.maps = D.ParseMap(zones and zones.private and zones.private.areaIdToUiMapId)
    for area, map in pairs(D.ParseMap(zones and zones.private and zones.private.areaIdToUiMapIdOverride)) do
        self.maps[area] = map
    end
    local xp = db.Support.Get("QuestXP")
    self.xp = xp and xp.db or {}
    self.content = A.Content
    return true
end

function D:BuildIndex()
    self.byLevel, self.count = {}, 0
    self.requirements = {skills = {}, reputations = {}, spells = {}, specializations = {}}
    local chainIndex=A.Chains.NewIndex()
    for i, id in ipairs(self.ids) do
        local q=self:GetQuest(id)
        local level = math.max(0, q and q.questLevel or 0)
        level = math.floor(level)
        self.byLevel[level] = self.byLevel[level] or {}
        table.insert(self.byLevel[level], id)
        self.count = self.count + 1
        local function get(key) return q and q[key] end
        local skill = get("requiredSkill")
        if skill then self.requirements.skills[skill[1]] = true end
        for _, r in ipairs(get("requiredRanks") or {}) do self.requirements.skills[r[1]] = true end
        for _, key in ipairs({"requiredMinRep", "requiredMaxRep"}) do
            local r = get(key)
            if r then self.requirements.reputations[r[1]] = true end
        end
        local objectives=self.db.Quest.Get(id,"objectives") or {}
        local reputation=objectives[4]
        if reputation and type(reputation[1])=="number" and reputation[1]>0 then self.requirements.reputations[reputation[1]]=true end
        local spell, spec = get("requiredSpell"), get("requiredSpecialization")
        if spell and spell > 0 then self.requirements.spells[spell] = true end
        if spec and spec > 0 then self.requirements.specializations[spec] = true end
        A.Chains.IndexQuest(chainIndex,q,self)
        if i % 25 == 0 then coroutine.yield() end
    end
    self.chainIndex=chainIndex
    self:BuildServices()
end

local function flag(value,mask)
    return type(value)=="number" and type(mask)=="number" and mask>0 and math.floor(value/mask)%2==1
end

function D:BuildServices()
    self.servicesByMap,self.serviceCount={},0
    self.amenitiesByMap,self.amenityCount={},0
    local npc,flags=self.db.Npc,self.db.Enum.npcFlags
    for index,id in ipairs(npc.GetAllIds()) do
        local value=npc.Get(id,"npcFlags")
        local service=flag(value,flags.VENDOR) or flag(value,flags.REPAIR)
        local amenity=flag(value,flags.TRAINER) or flag(value,flags.INNKEEPER)
        if service or amenity then
            local maps={}
            for area,spawns in pairs(npc.Get(id,"spawns") or {}) do
                local map=self.maps[area]
                if map and map>0 then
                    for _,point in ipairs(spawns) do if usableSpawn(point) then maps[map]=true;break end end
                end
            end
            if next(maps) then
                if service then self.serviceCount=self.serviceCount+1 end
                if amenity then self.amenityCount=self.amenityCount+1 end
            end
            for map in pairs(maps) do
                if service then
                    self.servicesByMap[map]=self.servicesByMap[map] or {}
                    self.servicesByMap[map][#self.servicesByMap[map]+1]=id
                end
                if amenity then
                    self.amenitiesByMap[map]=self.amenitiesByMap[map] or {}
                    self.amenitiesByMap[map][#self.amenitiesByMap[map]+1]=id
                end
            end
        end
        if index%100==0 then coroutine.yield() end
    end
end

function D:AmenityPoints(state,kind,maps)
    local points={}
    if not state.position or (kind~="train" and kind~="bind") then return points end
    local npc,flags=self.db.Npc,self.db.Enum.npcFlags
    local allowed={[state.position.map]=true}
    for map,selected in pairs(maps or {}) do
        local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        if selected and info and (info.mapType==2 or info.mapType==3) then allowed[map]=true end
    end
    local ids,seen={},{}
    for map in pairs(allowed) do
        for _,id in ipairs((self.amenitiesByMap or {})[map] or {}) do
            if not seen[id] then seen[id]=true;ids[#ids+1]=id end
        end
    end
    table.sort(ids)
    for _,id in ipairs(ids) do
        local faction=npc.Get(id,"friendlyToFaction")
        local friendly=faction=="AH" or faction==(state.faction=="Alliance" and "A" or state.faction=="Horde" and "H")
        if friendly and flag(npc.Get(id,"npcFlags"),kind=="train" and flags.TRAINER or flags.INNKEEPER) then
            for _,position in ipairs(self:EntityPoints(npc,id)) do
                if allowed[position.map] and not (A.Dungeon and A.Dungeon.TaskInstance and A.Dungeon.TaskInstance(position,state,self)) then
                    points[#points+1]={kind=kind,npcId=id,title=npc.Get(id,"name") or ("NPC #"..id),
                        description=npc.Get(id,"subName"),position=position}
                end
            end
        end
    end
    return points
end

function D:ServicePoints(state,kind,missing)
    local result={}
    if not state.position then return result end
    local npc,flags=self.db.Npc,self.db.Enum.npcFlags
    local stock={}
    if kind=="supply" then
        for item,count in pairs(missing or {}) do
            for _,id in ipairs(self.db.Item.Get(item,"vendors") or {}) do
                stock[id]=stock[id] or {};stock[id][item]=(state.bags[item] or 0)+count
            end
        end
    end
    for index,id in ipairs((self.servicesByMap or {})[state.position.map] or {}) do
        local friendly=npc.Get(id,"friendlyToFaction")
        local allowed=friendly=="AH" or (state.faction=="Alliance" and friendly=="A") or (state.faction=="Horde" and friendly=="H")
        local value=npc.Get(id,"npcFlags")
        local capable=kind=="repair" and flag(value,flags.REPAIR) or
            (kind=="vendor" or kind=="supply") and flag(value,flags.VENDOR)
        if allowed and capable and (kind~="supply" or stock[id]) then
            for _,point in ipairs(self:EntityPoints(npc,id)) do
                if point.map==state.position.map then
                    point.label="QuestieDB 服务 NPC 位置"
                    result[#result+1]={npcId=id,title=npc.Get(id,"name") or ("NPC #"..id),position=point,targets=stock[id]}
                end
            end
        end
        local thread,main=coroutine.running()
        if index%25==0 and thread and not main then coroutine.yield() end
    end
    return result
end

function D:GetQuest(id)
    if self.cache[id] then return self.cache[id] end
    local values = self.db.Quest.GetAll(id, fields)
    local overlay = self.content.quests[id]
    if not values and not overlay then return nil end
    local q = { id = id }
    for i, key in ipairs(fields) do q[key] = values and values[i] end
    q.repeatable = math.floor((q.specialFlags or 0) / 1) % 2 == 1
    q.title = q.name or ("任务 #" .. id)
    local xp = self.xp[id]
    if type(xp)=="table" and type(xp[1])=="number" and xp[1]>=1 and xp[1]<=60 and xp[1]%1==0 and
        type(xp[2])=="number" and xp[2]>=0 and xp[2]<math.huge and xp[2]%1==0 then
        q.referenceXPLevel,q.referenceXP=xp[1],xp[2]
    end
    q.taskFacts=A.TaskFacts and A.TaskFacts.quests[id]
    if overlay then for k, v in pairs(overlay) do q[k] = v end end
    self.cache[id] = q
    return q
end

function D:Candidates(snapshot)
    local ids, seen = {}, {}
    local function add(id) if not seen[id] then ids[#ids + 1], seen[id] = id, true end end
    for id in pairs(snapshot.quests) do add(id) end
    for level = math.max(0, snapshot.level - 8), snapshot.level + 2 do
        for _, id in ipairs(self.byLevel[level] or {}) do add(id) end
    end
    if snapshot.locked then add(snapshot.locked) end
    table.sort(ids)
    return ids
end

function D:EntityPoints(entity, id, allowArea)
    return self:SpawnPoints(entity.Get(id,"spawns"),allowArea)
end

function D:SpawnPoints(spawnList,allowArea)
    local points,areas = {},{}
    for area, spawns in pairs(spawnList or {}) do
        local map = self.maps[area]
        if map and map > 0 and C_Map.GetMapInfo(map) then
            for _, p in ipairs(spawns) do
                if usableSpawn(p) then
                    points[#points + 1] = { map = map, x = p[1] / 100, y = p[2] / 100, sourceAreaId=area }
                elseif allowArea and p[1]==-1 and p[2]==-1 and (not p[3] or p[3]==0) then
                    if areas[map]==nil then areas[map]=area elseif areas[map]~=area then areas[map]=false end
                end
            end
        end
    end
    if #points==0 then
        for map,area in pairs(areas) do points[#points+1]={map=map,x=0.5,y=0.5,sourceAreaId=area or nil,approximate=true,label="区域参考点"} end
    end
    table.sort(points,function(a,b)
        if a.map~=b.map then return a.map<b.map end
        if a.x~=b.x then return a.x<b.x end
        return a.y<b.y
    end)
    return points
end

function D:TriggerTarget(q,state)
    local trigger=self.db.Quest.Get(q.id,"triggerEnd")
    local best,bestDistance
    for _,point in ipairs(self:SpawnPoints(trigger and trigger[2],true)) do
        local distance=A.Navigation:Distance(state.position,point)
        local precise=best and best.approximate and not point.approximate
        local comparable=not best or (not best.approximate)==(not point.approximate)
        if not best or precise or comparable and distance and (not bestDistance or distance<bestDistance) then
            best,bestDistance=point,distance
        end
    end
    if best then best.sourceKind="trigger";best.label=best.approximate and "区域参考点" or "任务事件地点" end
    return best
end

function D:AreaTarget(q)
    local area=q.zoneOrSort
    local map=type(area)=="number" and area>0 and self.maps and self.maps[area]
    if map and map>0 and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map) then
        return {map=map,x=0.5,y=0.5,label="区域参考点",approximate=true}
    end
end

-- Class/race categories are not geographic areas; the giver's area is the last reference.
function D:QuestAreaTarget(q,state)
    local point=self:AreaTarget(q)
    if point or type(q.zoneOrSort)=="number" and q.zoneOrSort>0 then return point end
    local giver=self:Target(q,{quests={},completed={},position=state.position,faction=state.faction})
    if giver then
        return {map=giver.map,x=0.5,y=0.5,sourceAreaId=giver.sourceAreaId,label="区域参考点",approximate=true}
    end
end

function D:Target(q, state)
    local status = A.State.Status(state, q.id)
    local active = state.quests[q.id]
    if active and status ~= "ready" and C_QuestLog and C_QuestLog.GetNextWaypoint then
        local map, x, y = C_QuestLog.GetNextWaypoint(q.id)
        if map and map > 0 and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            return { map = map, x = x, y = y, label = "客户端任务目标" }
        end
    end
    local group = status == "ready" and "finishedBy" or "startedBy"
    if status == "active" then
        local target=self:ObjectiveTarget(q,state) or (#(active.objectives or {})==0 and self:TriggerTarget(q,state))
        if target then return target end
        if self:DeliveryOnly(q,state) then
            return self:Target(q,{position=state.position,faction=state.faction,completed=state.completed,quests={[q.id]={ready=true}}})
        end
        if not self:UnmappedTargetArea(q,state) then return self:QuestAreaTarget(q,state) end
        return
    end
    local sources = self.db.Quest.Get(q.id, group) or {}
    local best, bestDistance, sourceCount, unavailable = nil, nil, 0, 0
    for kind = 1, 2 do
        local entity = kind == 1 and self.db.Npc or self.db.Object
        for _, id in ipairs(sources[kind] or {}) do
            sourceCount=sourceCount+1
            local offers=not active and kind==1 and state.questOffers and state.questOffers[id]
            if offers and not offers[q.id] then
                unavailable=unavailable+1
            else
                for _, point in ipairs(self:EntityPoints(entity, id, true)) do
                    local distance = A.Navigation:Distance(state.position, point)
                    local same=state.position and point.map==state.position.map
                    local bestSame=best and state.position and best.map==state.position.map
                    local precise=best and best.approximate and not point.approximate
                    local comparable=not best or (not best.approximate)==(not point.approximate)
                    if not best or precise or comparable and (distance and (not bestDistance or distance<bestDistance) or
                        not distance and not bestDistance and same and not bestSame) then
                        best, bestDistance = point, distance
                        best.label=best.approximate and "区域参考点" or (kind==1 and "QuestieDB NPC 位置" or "QuestieDB 对象位置")
                        best.entityKind,best.entityId=kind==1 and "npc" or "object",id
                        best.entityName=entity.Get(id,"name")
                    end
                end
            end
        end
    end
    if best then return best end
    if sourceCount>0 and unavailable==sourceCount then return end
    if self:UnmappedTargetArea(q,state) then return end
    local point=status=="ready" and self:QuestAreaTarget(q,state) or self:AreaTarget(q)
    -- A known sole recipient remains the same recipient even when its placement is missing.
    if point and #(sources[1] or {})+#(sources[2] or {})==1 then
        local npc=#(sources[1] or {})==1
        point.entityKind=npc and "npc" or "object"
        point.entityId=(sources[npc and 1 or 2])[1]
        point.entityName=(npc and self.db.Npc or self.db.Object).Get(point.entityId,"name")
    end
    return point
end

-- A recipient's identity remains useful for batching even without a usable map.
function D:Recipient(q,point)
    if point and point.entityKind and point.entityId then
        return {entityKind=point.entityKind,entityId=point.entityId,entityName=point.entityName}
    end
    local sources=self.db.Quest.Get(q.id,"finishedBy") or {}
    if #(sources[1] or {})+#(sources[2] or {})~=1 then return end
    local npc=#(sources[1] or {})==1
    local id=sources[npc and 1 or 2][1]
    return {entityKind=npc and "npc" or "object",entityId=id,
        entityName=(npc and self.db.Npc or self.db.Object).Get(id,"name")}
end

local function requirementName(kind,id)
    if kind==4 and C_Reputation and C_Reputation.GetFactionDataByID then
        local faction=C_Reputation.GetFactionDataByID(id)
        return faction and faction.name
    elseif kind==6 and C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
end

function D:CacheQuest(q,state)
    local cache=A.TaskFacts and A.TaskFacts.cacheXP
    if not cache or (state.clientVersion or A.clientVersion)~=cache.version or
        tostring(state.clientBuild or A.build)~=cache.build or (state.interface or A.interface)~=cache.interface then return end
    local facts=cache.quests[q.id]
    if facts and facts.level==q.questLevel then return facts end
end

function D:DeliveryOnly(q,state)
    local active=state.quests[q.id]
    if active and #(active.objectives or {})>0 or math.floor((q.specialFlags or 0)/2)%2==1 or
        next((self:ObjectiveEntries(q,state))) or self.db.Quest.Get(q.id,"triggerEnd") or
        next(q.requiredSourceItems or {}) then return false end
    local cache=self:CacheQuest(q,state)
    if cache and next(cache.itemUses or {}) then return false end
    -- Unindexed travel hints do not add completion requirements to a cache-confirmed delivery.
    for _,extra in pairs(self.db.Quest.Get(q.id,"extraObjectives") or {}) do
        if not cache or extra[4]~=0 then return false end
    end
    local facts=cache or q.taskFacts
    return facts~=nil and facts.level==q.questLevel and facts.complex==false and
        facts.objectives~=nil and #facts.objectives==0 and not facts.moneyCost and
        not (facts.rewards and (facts.rewards.money or 0)<0) and self:Recipient(q)~=nil
end

function D:ItemUseRules(q,state)
    local facts=self:CacheQuest(q,state)
    local rules={}
    for id,use in pairs(facts and facts.itemUses or {}) do
        local names,seen={},{}
        for _,target in ipairs(use.targets or {}) do
            local entity=target.kind=="npc" and self.db.Npc or self.db.Object
            local name=entity.Get(target.id,"name")
            if type(name)=="string" and name~="" and not seen[name] then names[#names+1]=name;seen[name]=true end
        end
        rules[id]={kind="use",target=#names>0 and ("使用目标："..table.concat(names,"、")) or nil}
    end
    return rules
end

function D:ObjectiveEntries(q,state)
    local entries=self.db.Quest.Get(q.id,"objectives") or {}
    if next(entries) then return entries end
    local facts=self:CacheQuest(q,state)
    if not facts then return entries end
    local result={}
    for _,o in ipairs(facts.objectives or {}) do
        local kind=({npc=1,object=2,item=3})[o.kind]
        if kind then
            result[kind]=result[kind] or {}
            result[kind][#result[kind]+1]={o.id,count=o.count}
        end
    end
    return result,facts.complex
end

function D:ObjectiveIdentities(q,state)
    local active=state.quests[q.id]
    if not active then return {} end
    local objectives,complex=self:ObjectiveEntries(q,state)
    local entries={}
    for kind=1,3 do
        for _,row in ipairs(objectives[kind] or {}) do entries[#entries+1]={kind=kind,id=row[1]} end
    end
    local reputation=objectives[4]
    if reputation and type(reputation[1])=="number" and type(reputation[2])=="number" then
        entries[#entries+1]={kind=4,id=reputation[1]}
    end
    for _,row in ipairs(objectives[5] or {}) do entries[#entries+1]={kind=5,id=row[2],npcIds=row[1],text=row[3]} end
    for _,row in ipairs(objectives[6] or {}) do entries[#entries+1]={kind=6,id=row[1],text=row[2]} end
    local only=not complex and #entries==1 and #(active.objectives or {})==1 and
        not self.db.Quest.Get(q.id,"triggerEnd")
    local identities={}
    for index,objective in ipairs(active.objectives or {}) do
        local found,count=nil,0
        for _,entry in ipairs(entries) do
            local kind=({"npc","object","item","reputation","killcredit","spell"})[entry.kind]
            local entity=(entry.kind==1 or entry.kind==5) and self.db.Npc or (entry.kind==2 and self.db.Object or self.db.Item)
            local name
            if entry.kind==4 or entry.kind==6 then name=requirementName(entry.kind,entry.id)
            else name=entity.Get(entry.id,"name") end
            local nativeKind=({monster="npc",object="object",item="item",reputation="reputation",spell="spell"})[objective.type]
            local typed=objective.type~="event" and (not nativeKind or nativeKind==kind)
            local matched=objective.targetId and objective.targetId==entry.id and objective.targetKind==kind or
                not objective.targetId and (only or type(name)=="string" and name~="" and type(objective.text)=="string" and objective.text:find(name,1,true))
            if entry.kind==4 or entry.kind==6 then
                typed=not objective.type or objective.type==kind or objective.type=="event" and
                    (only or entry.kind==6 and not self.db.Quest.Get(q.id,"triggerEnd"))
                if not objective.targetId and type(objective.text)=="string" and type(entry.text)=="string" and entry.text~="" and
                    objective.text:find(entry.text,1,true) then matched=true end
            elseif entry.kind==5 then
                typed=not objective.type or objective.type=="monster" or objective.type=="killcredit" or objective.type=="event" and only
                local ids={entry.id};for _,id in ipairs(entry.npcIds or {}) do ids[#ids+1]=id end
                for _,id in ipairs(ids) do
                    local alias=self.db.Npc.Get(id,"name")
                    if objective.targetId then
                        if objective.targetId==id and (objective.targetKind=="npc" or objective.targetKind=="killcredit") then matched=true end
                    elseif type(objective.text)=="string" and type(alias)=="string" and alias~="" and objective.text:find(alias,1,true) then matched=true end
                end
                if not objective.targetId and type(objective.text)=="string" and type(entry.text)=="string" and entry.text~="" and
                    objective.text:find(entry.text,1,true) then matched=true end
            end
            if not objective.finished and typed and matched then
                found,count={kind=kind,id=entry.id,npcIds=entry.npcIds,objectiveType=objective.type},count+1
            end
        end
        if count==1 then identities[index]=found end
    end
    return identities
end

function D:ObjectiveExtras(q,state)
    local active=state.quests[q.id]
    local extras=self.db.Quest.Get(q.id,"extraObjectives") or {}
    local byIndex,counts={},{}
    for _,extra in ipairs(extras) do
        local index=extra[4]
        if index==0 and #extras==1 and #(active.objectives or {})==1 and not state.referenceIndexUnknown then index=1 end
        if type(index)=="number" and index>0 and index%1==0 and not state.referenceIndexUnknown then
            counts[index]=(counts[index] or 0)+1;byIndex[index]=extra
        end
    end
    return byIndex,counts
end

function D:ObservedObjectiveTarget(q,state,identity,objective)
    if not identity or not objective.numRequired then return end
    local facts=self:CacheQuest(q,state)
    local best,bestDistance
    for _,entry in ipairs(facts and facts.objectives or {}) do
        if entry.kind==identity.kind and entry.id==identity.id and entry.count==objective.numRequired then
            for _,p in ipairs(entry.locations or {}) do
                if C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(p.map) then
                    local distance=A.Navigation:Distance(state.position,p)
                    local same=state.position and p.map==state.position.map
                    local bestSame=best and state.position and best.map==state.position.map
                    if not best or distance and (not bestDistance or distance<bestDistance) or
                        not distance and not bestDistance and same and not bestSame then
                        best,bestDistance=p,distance
                    end
                end
            end
        end
    end
    -- These are positions of players receiving progress, not exact target spawns.
    if best then return {map=best.map,x=best.x,y=best.y,approximate=true,sourceKind="observation",label="任务目标附近"} end
end

function D:ObjectiveTargets(q,state)
    local active=state.quests[q.id]
    if not active then return {} end
    local identities=self:ObjectiveIdentities(q,state)
    local chosen,distances={},{}
    local function consider(entity,id,label,index,kind,identity,sourceKind,points)
        for _,point in ipairs(points or self:EntityPoints(entity,id,true)) do
            local best,bestDistance=chosen[index],distances[index]
            local distance=A.Navigation:Distance(state.position,point)
            local same=state.position and point.map==state.position.map
            local bestSame=best and state.position and best.map==state.position.map
            local precise=best and best.approximate and not point.approximate
            local comparable=not best or (not best.approximate)==(not point.approximate)
            if not best or precise or comparable and (distance and (not bestDistance or distance<bestDistance) or
                not distance and not bestDistance and same and not bestSame) then
                chosen[index],distances[index]=point,distance
                point.label,point.objectiveIndex=point.approximate and "区域参考点" or label,index
                point.entityKind,point.entityId=kind,id
                point.targetKind,point.targetId=identity.kind,identity.id
                point.sourceKind=sourceKind
                if sourceKind=="vendor" then
                    point.entityName=entity.Get(id,"name")
                    point.targetName=self.db.Item.Get(identity.id,"name")
                end
            end
        end
    end
    for index,entry in pairs(identities) do
        if entry.kind=="killcredit" then
            for _,id in ipairs(entry.npcIds or {}) do
                consider(self.db.Npc,id,"任务目标分布",index,"npc",entry)
            end
        elseif entry.kind=="npc" or entry.kind=="object" then
            consider(entry.kind=="npc" and self.db.Npc or self.db.Object,entry.id,"QuestieDB 任务目标分布",index,entry.kind,entry)
        elseif entry.kind=="item" then
            for _,source in ipairs({{self.db.Npc,"npcDrops","npc"},{self.db.Object,"objectDrops","object"}}) do
                for _,id in ipairs(self.db.Item.Get(entry.id,source[2]) or {}) do
                    consider(source[1],id,"QuestieDB 任务物品来源分布",index,source[3],entry)
                end
            end
            for _,id in ipairs(self.db.Item.Get(entry.id,"vendors") or {}) do
                local faction=self.db.Npc.Get(id,"friendlyToFaction")
                if faction=="AH" or faction==(state.faction=="Alliance" and "A" or state.faction=="Horde" and "H") then
                    consider(self.db.Npc,id,"任务物品商人",index,"npc",entry,"vendor")
                end
            end
        end
    end
    local eventIndex,eventCount=nil,0
    for index,o in ipairs(active.objectives or {}) do
        if o.type=="event" then eventIndex,eventCount=index,eventCount+1 end
    end
    local objectives=self:ObjectiveEntries(q,state)
    if eventCount==0 and #(active.objectives or {})==1 and not active.objectives[1].type and not next(objectives) then
        eventIndex,eventCount=1,1
    end
    if eventCount==1 and not active.objectives[eventIndex].finished then
        chosen[eventIndex]=self:TriggerTarget(q,state) or chosen[eventIndex]
    end
    local byIndex,counts=self:ObjectiveExtras(q,state)
    for index,extra in pairs(byIndex) do
        local o=(active.objectives or {})[index]
        if counts[index]==1 and o and not o.finished and (not chosen[index] or chosen[index].approximate) then
            local identity=identities[index] or {}
            consider(nil,nil,"任务目标地点",index,nil,identity,"extra",self:SpawnPoints(extra[1],true))
            for _,ref in ipairs(extra[5] or {}) do
                local entity=ref[1]=="monster" and self.db.Npc or ref[1]=="object" and self.db.Object
                if entity then
                    consider(entity,ref[2],"任务目标地点",index,ref[1]=="monster" and "npc" or "object",identity,"extra")
                end
            end
        end
    end
    local result={}
    for index,o in ipairs(active.objectives or {}) do
        if not o.finished then
            local identity=identities[index]
            local point=chosen[index]
            if not point or point.approximate then point=self:ObservedObjectiveTarget(q,state,identity,o) or point end
            local unmapped=not point and self:UnmappedTargetArea(q,state,index)
            if not point and not unmapped then point=self:QuestAreaTarget(q,state) end
            if point then
                if identity then point.targetKind,point.targetId=identity.kind,identity.id end
                point.objectiveIndex=index;result[#result+1]=point
            end
        end
    end
    return result
end

function D:ObjectiveTarget(q,state)
    local best,bestDistance
    for _,point in ipairs(self:ObjectiveTargets(q,state)) do
        local distance=A.Navigation:Distance(state.position,point)
        local same=state.position and point.map==state.position.map
        local bestSame=best and state.position and best.map==state.position.map
        if not best or distance and (not bestDistance or distance<bestDistance) or
            not distance and not bestDistance and same and not bestSame then
            best,bestDistance=point,distance
        end
    end
    return best
end

-- Preserve a destination's known area when no UI-map coordinate can be produced.
function D:UnmappedTargetArea(q,state,objectiveIndex)
    local function areaOf(lists)
        local found
        for _,spawns in ipairs(lists) do
            for area,points in pairs(spawns) do
                for _,p in ipairs(points) do
                    if usableSpawn(p) or p[1]==-1 and p[2]==-1 and (not p[3] or p[3]==0) then
                        local map=self.maps[area]
                        if map and map>0 and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map) then return end
                        if found and found~=area then return end
                        found=area
                    end
                end
            end
        end
        return found
    end
    local function add(lists,entity,id)
        local spawns=entity.Get(id,"spawns")
        if spawns then lists[#lists+1]=spawns end
    end
    local active=state.quests[q.id]
    if not active or active.ready or self:DeliveryOnly(q,state) then
        local sources=self.db.Quest.Get(q.id,active and "finishedBy" or "startedBy") or {}
        local lists={}
        for kind=1,2 do for _,id in ipairs(sources[kind] or {}) do add(lists,kind==1 and self.db.Npc or self.db.Object,id) end end
        return areaOf(lists)
    end
    local trigger=self.db.Quest.Get(q.id,"triggerEnd")
    local eventIndex,eventCount=nil,0
    for index,o in ipairs(active.objectives or {}) do if o.type=="event" then eventIndex,eventCount=index,eventCount+1 end end
    if eventCount==0 and #(active.objectives or {})==1 and not active.objectives[1].type and
        not next((self:ObjectiveEntries(q,state))) then eventIndex,eventCount=1,1 end
    if (not objectiveIndex or objectiveIndex==eventIndex) and (eventCount==1 and not active.objectives[eventIndex].finished or #(active.objectives or {})==0) then
        local area=trigger and areaOf({trigger[2] or {}})
        if area then return area,eventIndex end
    end
    local identities=self:ObjectiveIdentities(q,state)
    local extras,counts=self:ObjectiveExtras(q,state)
    for index,o in ipairs(active.objectives or {}) do
        local entry=identities[index]
        if (not objectiveIndex or index==objectiveIndex) and not o.finished and (entry or counts[index]==1) then
            local lists={}
            if entry and (entry.kind=="npc" or entry.kind=="object") then add(lists,entry.kind=="npc" and self.db.Npc or self.db.Object,entry.id)
            elseif entry and entry.kind=="killcredit" then for _,id in ipairs(entry.npcIds or {}) do add(lists,self.db.Npc,id) end
            elseif entry and entry.kind=="item" then
                for _,source in ipairs({{self.db.Npc,"npcDrops"},{self.db.Object,"objectDrops"}}) do
                    for _,id in ipairs(self.db.Item.Get(entry.id,source[2]) or {}) do add(lists,source[1],id) end
                end
                for _,id in ipairs(self.db.Item.Get(entry.id,"vendors") or {}) do
                    local faction=self.db.Npc.Get(id,"friendlyToFaction")
                    if faction=="AH" or faction==(state.faction=="Alliance" and "A" or state.faction=="Horde" and "H") then add(lists,self.db.Npc,id) end
                end
            end
            local extra=extras[index]
            if counts[index]==1 then
                if extra[1] then lists[#lists+1]=extra[1] end
                for _,ref in ipairs(extra[5] or {}) do
                    local entity=ref[1]=="monster" and self.db.Npc or ref[1]=="object" and self.db.Object
                    if entity then add(lists,entity,ref[2]) end
                end
            end
            local area=areaOf(lists)
            if area then return area,index end
            -- A missing source still has the quest's area; retain it when that area has no UI map.
            if entry and #lists==0 and type(q.zoneOrSort)=="number" and q.zoneOrSort>0 and not self:AreaTarget(q) then
                return q.zoneOrSort,index
            end
        end
    end
end

function D:ReferenceObjectiveTargets(q,state)
    local entries,complex=self:ObjectiveEntries(q,state)
    local cache=self:CacheQuest(q,state)
    complex=complex or false
    local order=self.db.ObjectiveFirst or {}
    local descriptions={}
    for kind=1,3 do
        local entity=kind==1 and self.db.Npc or (kind==2 and self.db.Object or self.db.Item)
        for _,row in ipairs(entries[kind] or {}) do
            local name=entity.Get(row[1],"name")
            local description={text=name or ("目标 #"..row[1]),finished=false,
                targetKind=({"npc","object","item"})[kind],targetId=row[1]}
            local need=row.count
            for _,fact in ipairs(q.taskFacts and q.taskFacts.objectives or {}) do
                if not need and fact.kind==description.targetKind and fact.id==row[1] then need=fact.count end
            end
            if not need then
                local count
                for _,fact in ipairs(cache and cache.objectives or {}) do
                    if fact.kind==description.targetKind and fact.id==row[1] then
                        if count and count~=fact.count then count=false;break end
                        count=fact.count
                    end
                end
                need=count or nil
            end
            if type(need)=="number" and need>0 then
                description.numRequired=need
                if kind==3 then
                    local have=(state.bags or {})[row[1]] or 0
                    description.numFulfilled=have;description.finished=have>=need
                    local starters=q.startedBy or {}
                    description.providedOnAccept=not state.quests[q.id] and need==1 and q.sourceItemId==row[1] and
                        (#(starters[1] or {})+#(starters[2] or {})>0) and #(starters[3] or {})==0 or nil
                end
            end
            local first=kind==2 and order.objectObjectiveFirst or kind==3 and order.itemObjectiveFirst
            if first and first[q.id] then table.insert(descriptions,1,description)
            else descriptions[#descriptions+1]=description end
        end
    end
    local reputation=entries[4]
    if reputation and next(reputation) then
        local id,need=reputation[1],reputation[2]
        if type(id)=="number" and id>0 and type(need)=="number" then
            local have=state.reputations and state.reputations[id]
            local standing=({[0]="中立",[3000]="友善",[9000]="尊敬",[21000]="崇敬",[42000]="崇拜"})[need] or tostring(need)
            descriptions[#descriptions+1]={text=(requirementName(4,id) or "任务指定阵营").."声望达到"..standing,
                type="reputation",targetKind="reputation",targetId=id,numRequired=need,numFulfilled=have,
                finished=type(have)=="number" and have>=need}
        else complex=true end
    end
    for _,row in ipairs(entries[5] or {}) do
        local name=self.db.Npc.Get(row[2],"name")
        local description={text=name or "按任务日志完成目标",finished=false,targetKind="killcredit",targetId=row[2]}
        if order.killCreditObjectiveFirst and order.killCreditObjectiveFirst[q.id] then table.insert(descriptions,1,description)
        else descriptions[#descriptions+1]=description end
    end
    for _,row in ipairs(entries[6] or {}) do
        if type(row[1])=="number" and row[1]>0 then
            local name=requirementName(6,row[1])
            local description={text=name and ("按任务要求施放"..name) or "按任务日志施放指定法术",type="spell",
                finished=false,targetKind="spell",targetId=row[1]}
            if order.spellObjectiveFirst and order.spellObjectiveFirst[q.id] then table.insert(descriptions,1,description)
            else descriptions[#descriptions+1]=description end
        else complex=true end
    end
    local trigger=self.db.Quest.Get(q.id,"triggerEnd")
    local explorations={}
    for _,fact in ipairs(cache and cache.objectives or {}) do
        if fact.kind=="areaTrigger" or fact.kind=="areaTriggerEnter" then explorations[#explorations+1]=fact end
    end
    for _,fact in ipairs(explorations) do
        local description={text="探索任务指定区域，按日志完成探索要求。",type="event",finished=false,
            areaTriggerId=fact.id,numRequired=fact.count>0 and fact.count or nil}
        if order.eventObjectiveFirst and order.eventObjectiveFirst[q.id] then table.insert(descriptions,1,description)
        else descriptions[#descriptions+1]=description end
    end
    -- The provider's single event point locates the cached exploration; do not add it twice.
    if trigger and #explorations==0 then
        local description={text="按任务日志完成事件",type="event",finished=false}
        if order.eventObjectiveFirst and order.eventObjectiveFirst[q.id] then table.insert(descriptions,1,description)
        else descriptions[#descriptions+1]=description end
    end
    -- Query reference placements only; this temporary lookup never becomes a character snapshot.
    -- Malformed requirements leave their native indices unknown.
    local virtual={position=state.position,faction=state.faction,referenceIndexUnknown=complex,quests={[q.id]={objectives=descriptions}},
        clientVersion=state.clientVersion,clientBuild=state.clientBuild,interface=state.interface}
    local positions={}
    for _,point in ipairs(self:ObjectiveTargets(q,virtual)) do positions[point.objectiveIndex]=point end
    local areas={}
    for index in ipairs(descriptions) do
        if not positions[index] then areas[index]=self:UnmappedTargetArea(q,virtual,index) end
    end
    return descriptions,positions,complex,areas
end

function D:NodeCount()
    local n = 0
    for _ in pairs(A.Content.nodes) do n = n + 1 end
    return n
end

function D:Audit()
    return A.Audit.Text(A.Audit.Build(self, false))
end
