local _, A = ...
A.Data = { ids = {}, cache = {}, count = 0 }
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

local function areaOnlySpawn(p)
    return p[1]==-1 and p[2]==-1 and (not p[3] or p[3]==0)
end

-- A drop available in the current dungeon takes precedence over outdoor alternatives.
local function eachItemDrop(self,item,state,visit)
    local sources={{self.db.Npc,"npcDrops","npc"},{self.db.Object,"objectDrops","object"}}
    local current=state.inInstance and state.instanceId and A.DungeonCatalog and
        A.DungeonCatalog.entries["reference:"..state.instanceId]
    local function scan(insideOnly)
        local found=false
        for _,source in ipairs(sources) do
            for _,id in ipairs(self.db.Item.Get(item,source[2]) or {}) do
                local spawns=source[1].Get(id,"spawns")
                if insideOnly then
                    local localSpawns={}
                    for _,area in ipairs(current.areas) do
                        local points=spawns and spawns[area]
                        if points and A.Dungeon.TaskInstance(nil,state,self,area)==current then
                            for _,p in ipairs(points) do
                                if usableSpawn(p) or areaOnlySpawn(p) then localSpawns[area]=points;break end
                            end
                        end
                    end
                    spawns=next(localSpawns) and localSpawns
                end
                if spawns then visit(source[1],id,source[3],spawns);found=true end
            end
        end
        return found
    end
    if current and current.areas and A.Dungeon and A.Dungeon.TaskInstance and scan(true) then return end
    scan(false)
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
    if not db.flavor or db.flavor.expansion~="Forever" then return false, "请安装无限版 QuestieDB。" end
    self.db = db
    self.cache,self.chainIndex,self.byArea={},nil,{}
    self.servicesByMap,self.serviceCount={},0
    self.amenitiesByMap,self.amenityCount={},0
    self.innkeepers,self.bindLookup=nil,nil
    self.ids={}
    for _,id in ipairs(db.Quest.GetAllIds()) do self.ids[#self.ids+1]=id end
    table.sort(self.ids)
    local zones = db.Support.Get("ZoneDB")
    self.maps = D.ParseMap(zones and zones.private and zones.private.areaIdToUiMapId)
    for area, map in pairs(D.ParseMap(zones and zones.private and zones.private.areaIdToUiMapIdOverride)) do
        self.maps[area] = map
    end
    return true
end

local function indexThreshold(group,requirement)
    if not requirement or type(requirement[1])~="number" or type(requirement[2])~="number" then return end
    local id=requirement[1]
    group[id]=group[id] or {}
    group[id][requirement[2]]=true
end

function D:BuildIndex()
    self.byArea, self.count = {}, 0
    self.requirements = {skills = {}, reputations = {}, spells = {}, specializations = {}, startItems = {}, pickupItems = {}}
    local sets=A.ItemSets
    if sets and sets.version==A.clientVersion and sets.interface==A.interface then
        for _,set in pairs(sets.sets) do
            if set.skill then indexThreshold(self.requirements.skills,{set.skill,set.rank}) end
        end
    end
    local chainIndex=A.Chains.NewIndex()
    for i, id in ipairs(self.ids) do
        local q=self:GetQuest(id)
        if q and q.zoneOrSort and q.zoneOrSort>0 then
            self.byArea[q.zoneOrSort]=self.byArea[q.zoneOrSort] or {}
            table.insert(self.byArea[q.zoneOrSort],id)
        end
        self.count = self.count + 1
        local function get(key) return q and q[key] end
        indexThreshold(self.requirements.skills,get("requiredSkill"))
        for _,r in ipairs(get("requiredRanks") or {}) do indexThreshold(self.requirements.skills,r) end
        for _,key in ipairs({"requiredMinRep","requiredMaxRep"}) do indexThreshold(self.requirements.reputations,get(key)) end
        local objectives=self.db.Quest.Get(id,"objectives") or {}
        indexThreshold(self.requirements.reputations,objectives[4])
        for _,item in ipairs(q and q.startedBy and q.startedBy[3] or {}) do self.requirements.startItems[item]=true end
        -- Some quest markers point at the loot itself. The NPC can still offer the quest after pickup.
        local starters=q and q.startedBy or {}
        local objectives=q and q.taskFacts and q.taskFacts.objectives or {}
        local item=objectives[1]
        if next(starters[1] or {}) and next(starters[2] or {}) and #objectives==1 and
            item.kind=="item" and (item.count or 0)>0 then
            for _,drop in ipairs(self.db.Item.Get(item.id,"objectDrops") or {}) do
                for _,object in ipairs(starters[2]) do
                    if drop==object then
                        q.pickupLoot=q.pickupLoot or {}
                        q.pickupLoot[object]=item
                        indexThreshold(self.requirements.pickupItems,{item.id,item.count})
                    end
                end
            end
        end
        local spell, spec = get("requiredSpell"), get("requiredSpecialization")
        if spell and spell > 0 then self.requirements.spells[spell] = true end
        for _,reward in ipairs(q and q.taskFacts and q.taskFacts.learnedSpells or {}) do self.requirements.spells[reward]=true end
        local mount=q and q.taskFacts and q.taskFacts.mountReward
        if mount then self.requirements.spells[mount]=true end
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
    local innkeepers={}
    self.dangerNames={}
    for _,faction in ipairs({"Alliance","Horde"}) do
        for _,rows in pairs(A.DangerData and A.DangerData[faction] or {}) do
            for _,row in ipairs(rows) do self.dangerNames[row.name]=false end
        end
    end
    for index,id in ipairs(npc.GetAllIds()) do
        if npc.GetRaw then
            local name=npc.GetRaw(id,"name")
            if self.dangerNames[name]~=nil then self.dangerNames[name]=npc.Get(id,"name") end
        end
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
                if flag(value,flags.INNKEEPER) then innkeepers[#innkeepers+1]=id end
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
    self.innkeepers,self.bindLookup=innkeepers,nil
end

-- Outdoor inn subareas at the QuestieDB spawns, from Forever 1.60.1.70862 terrain.
-- Area names come from the client even when the exploration overlay is unavailable.
local innAreas={
    [295]=87,[1247]=131,[1464]=150,[2352]=271,[2388]=272,[3934]=380,[5688]=159,[5814]=117,
    [6272]=513,[6727]=69,[6734]=144,[6735]=1659,[6736]=186,[6737]=442,[6738]=415,[6739]=228,
    [6747]=222,[6790]=42,[6791]=392,[6807]=35,[6928]=362,[6930]=75,[7714]=378,[7731]=460,
    [7733]=976,[7736]=1116,[7737]=1099,[7744]=349,[8931]=108,[9356]=340,[9501]=321,[11103]=608,
    [11106]=2408,[11116]=484,[11118]=2255,[12196]=431,[14731]=3317,[15174]=3425,[16256]=2268,[16458]=467,
    [28687]=279,[32413]=279,[240482]=3137,[243815]=16849,[244512]=16848,[254089]=16624,[255894]=16727,[255940]=16638,
    [256675]=16743,[257595]=16724,[258380]=16848,
}

-- GetBindLocation gives a localized name. Match it to a friendly inn on the client map.
function D:BindPoint(name,faction)
    if not self.innkeepers or not (faction=="Alliance" or faction=="Horde") or not C_Map then return end
    local lookup=self.bindLookup
    if lookup and lookup.name==name and lookup.faction==faction then return lookup.point end
    lookup={name=name,faction=faction};self.bindLookup=lookup
    local npc=self.db.Npc
    local explored=C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition
    for _,id in ipairs(self.innkeepers) do
        local side=npc.Get(id,"friendlyToFaction")
        if side=="AH" or side==(faction=="Alliance" and "A" or "H") then
            for _,p in ipairs(self:EntityPoints(npc,id)) do
                local map=C_Map.GetMapInfo(p.map)
                local area=innAreas[id]
                local matches=map and map.name==name or area and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area)==name
                if not matches and explored and CreateVector2D and C_Map.GetAreaInfo then
                    for _,area in ipairs(explored(p.map,CreateVector2D(p.x,p.y)) or {}) do
                        if C_Map.GetAreaInfo(area)==name then matches=true;break end
                    end
                end
                if matches then
                    if lookup.point and not (lookup.point.map==p.map and lookup.point.x==p.x and lookup.point.y==p.y)
                        and not A.Navigation:Near(lookup.point,p,50) then
                        lookup.point=nil;return
                    end
                    lookup.point=lookup.point or p
                end
            end
        end
    end
    return lookup.point
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

function D:GetQuest(id,state)
    if self.cache[id] then return self.cache[id] end
    local values = self.db.Quest.GetAll(id, fields)
    if not values then
        for _,offers in pairs(state and state.questOffers or {}) do
            if type(offers[id])=="table" then return offers[id] end
        end
        return nil
    end
    local q = { id = id }
    for i, key in ipairs(fields) do q[key] = values and values[i] end
    q.taskFacts=self:CacheQuest(q,A)
    local catalog=A.DungeonCatalog
    local parent=q.taskFacts and q.taskFacts.prerequisite or
        catalog and catalog.version==A.clientVersion and catalog.prerequisites and catalog.prerequisites[id]
    if parent and not next(q.preQuestGroup or {}) and not next(q.preQuestSingle or {}) then
        q.preQuestGroup={parent}
    end
    q.repeatable = math.floor((q.specialFlags or 0) / 1) % 2 == 1
    q.title = q.name or ("任务 #" .. id)
    if q.taskFacts and q.taskFacts.requiredLevel~=nil then
        q.questLevel,q.requiredLevel=q.taskFacts.level,q.taskFacts.requiredLevel
    end
    local sorts=A.TaskFacts and A.TaskFacts.cacheXP and A.TaskFacts.cacheXP.eventSorts
    if not q.taskFacts and sorts and sorts[-(q.zoneOrSort or 0)] then q.taskFacts={hidden="event"} end
    self.cache[id] = q
    return q
end

function D:Candidates(snapshot)
    local ids, seen = {}, {}
    local function add(id) if not seen[id] then ids[#ids + 1], seen[id] = id, true end end
    for id in pairs(snapshot.quests) do add(id) end
    for _,offers in pairs(snapshot.questOffers or {}) do
        for id,available in pairs(offers) do if available then add(id) end end
    end
    if self.db and self.db.Item then
        for item,count in pairs(snapshot.bags or {}) do
            local id=count>0 and self.db.Item.Get(item,"startQuest")
            if id and id>0 then add(id) end
        end
    end
    for _,id in ipairs(self.ids) do
        local q=self:GetQuest(id)
        if q and (q.requiredLevel or 0)<=snapshot.level and
            (not (snapshot.completed or {})[id] or q.repeatable) then add(id) end
    end
    if snapshot.locked then add(snapshot.locked) end
    table.sort(ids)
    return ids
end

function D:EntityPoints(entity, id, allowArea, spawns)
    spawns=spawns or entity.Get(id,"spawns")
    local points=self:SpawnPoints(spawns,allowArea)
    -- The two tram quests have no zone map. Guide to the existing entrance, then name the platform.
    local map=entity==self.db.Npc and ({[12997]=1455,[13016]=1455,[13018]=1453})[id]
    if #points==0 and map and spawns and spawns[2257] then
        for _,leg in ipairs(A.PublicTransitData and A.PublicTransitData.legs or {}) do
            if leg.kind=="tram" and leg.from.map==map then
                local city=map==1455 and "铁炉堡" or "暴风城"
                points[1]={map=map,x=leg.from.x,y=leg.from.y,sourceAreaId=2257,approximate=true,
                    label=leg.fromName,travelHint="进入地铁，在"..city.."一侧站台寻找"..(entity.Get(id,"name") or "任务目标").."。"}
                break
            end
        end
    end
    return points
end

function D:SpawnPoints(spawnList,allowArea)
    local points,areas = {},{}
    for area, spawns in pairs(spawnList or {}) do
        local map = self.maps[area]
        if map and map > 0 and C_Map.GetMapInfo(map) then
            for _, p in ipairs(spawns) do
                if usableSpawn(p) then
                    points[#points + 1] = { map = map, x = p[1] / 100, y = p[2] / 100, sourceAreaId=area }
                elseif allowArea and areaOnlySpawn(p) then
                    if areas[map]==nil then areas[map]=area elseif areas[map]~=area then areas[map]=false end
                end
            end
        end
    end
    if #points==0 then
        for map,area in pairs(areas) do points[#points+1]={map=map,x=0.5,y=0.5,sourceAreaId=area or nil,areaOnly=true,approximate=true,label="区域参考点"} end
    end
    table.sort(points,function(a,b)
        if a.map~=b.map then return a.map<b.map end
        if a.x~=b.x then return a.x<b.x end
        return a.y<b.y
    end)
    return points
end

-- Compare actual journeys only when competing locations are on separate land.
-- A more distant walk can still beat the ferry, or an unlocked flight can win.
local function nearerSource(state,point,distance,best,bestDistance)
    if not best then return true end
    local travel=state.routeState or state
    if state.position and travel.runSpeed and travel.clientVersion and not travel.inInstance and
        not point.areaOnly and not best.areaOnly and A.Flights and A.Flights.Routes and
        A.Travel.Separated(point,best,A.Navigation) then
        local a=A.Flights.Routes(state.position,point,travel,A.Navigation)
        local b=A.Flights.Routes(state.position,best,travel,A.Navigation)
        local first=a and a[1].seconds or math.huge
        local second=b and b[1].seconds or math.huge
        if first~=second then return first<second end
    end
    if distance then return not bestDistance or distance<bestDistance end
    return not bestDistance and state.position and point.map==state.position.map and best.map~=point.map
end

function D:TriggerTarget(q,state)
    local trigger=self.db.Quest.Get(q.id,"triggerEnd")
    local best,bestDistance
    for _,point in ipairs(self:SpawnPoints(trigger and trigger[2],true)) do
        local distance=A.Navigation:Distance(state.position,point)
        local precise=best and best.approximate and not point.approximate
        local comparable=not best or (not best.approximate)==(not point.approximate)
        if precise or comparable and nearerSource(state,point,distance,best,bestDistance) then
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
        return {map=map,x=0.5,y=0.5,label="区域参考点",areaOnly=true,approximate=true}
    end
end

-- Class/race categories are not geographic areas; the giver's area is the last reference.
function D:QuestAreaTarget(q,state)
    local point=self:AreaTarget(q)
    if point or type(q.zoneOrSort)=="number" and q.zoneOrSort>0 then return point end
    local giver=self:Target(q,{quests={},completed={},position=state.position,faction=state.faction,locked=q.id})
    if giver then
        return {map=giver.map,x=0.5,y=0.5,label="区域参考点",areaOnly=true,approximate=true}
    end
end

local function nativeWaypoint(id)
    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        local map, x, y = C_QuestLog.GetNextWaypoint(id)
        if map and map > 0 and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            return { map = map, x = x, y = y, label = "客户端任务目标" }
        end
    end
end

local function soleContact(self,sources)
    if not sources or #(sources[1] or {})+#(sources[2] or {})~=1 then return end
    local npc=#(sources[1] or {})==1
    local id=sources[npc and 1 or 2][1]
    return {entityKind=npc and "npc" or "object",entityId=id,
        entityName=(npc and self.db.Npc or self.db.Object).Get(id,"name")}
end

local function oppositeGiver(entity,id,faction)
    local side=entity.Get(id,"friendlyToFaction")
    return side=="H" and faction=="Alliance" or side=="A" and faction=="Horde"
end

local function hasFriendlyRecipient(entity,sources,faction)
    local npcs=sources[1] or {}
    if #npcs<2 then return false end
    local friendly=faction=="Alliance" and "A" or faction=="Horde" and "H"
    for _,id in ipairs(npcs) do
        local side=entity.Get(id,"friendlyToFaction")
        if side=="AH" or friendly and side==friendly then return true end
    end
    return false
end

-- Use a recorded passing point when the contact patrols the player's current zone.
local function patrolContact(point,paths,origin,maps,turnin)
    if type(paths)~="table" then return end
    local nearest
    for area,segments in pairs(paths) do
        local hasPath=type(segments)=="table" and type(segments[1])=="table" and type(segments[1][1])=="table"
        if hasPath then point.sourceKind="patrol" end
        if hasPath and origin and maps[area]==origin.map then
            for _,path in ipairs(segments) do
                for _,p in ipairs(path) do
                    if usableSpawn(p) then
                        local x,y=p[1]/100,p[2]/100
                        local distance=((x-origin.x)*1.5)^2+(y-origin.y)^2
                        if not nearest or distance<nearest then
                            nearest=distance
                            point.map,point.x,point.y,point.sourceAreaId=origin.map,x,y,area
                        end
                    end
                end
            end
        end
    end
    if point.sourceKind~="patrol" then return end
    point.approximate,point.label=true,"巡逻路线参考点"
    point.travelHint="沿巡逻路线寻找「"..(point.entityName or "任务联系人").."」"..(turnin and "交付任务。" or "接取任务。")
end

local function waypointMatchesInstance(self,q,state,waypoint,target)
    local instanceFor=state.inInstance and A.Dungeon and A.Dungeon.TaskInstance
    if not instanceFor then return true end
    local area=not target and self:UnmappedTargetArea(q,state)
    local destination=instanceFor(target,state,self,area)
    return not destination or destination.instanceId~=state.instanceId or instanceFor(waypoint,state,self)==destination
end

local function collectedLoot(loot,state)
    return loot and ((state.bags or {})[loot.id] or 0)>=loot.count
end

function D:Target(q, state)
    local status = A.State.Status(state, q.id)
    local active = state.quests[q.id]
    local observations=not active and state.questOffers
    local speaker=observations and observations[state.questNPC]
    local offer=speaker and speaker[q.id]
    if type(offer)=="table" and offer.nativeOffer then return offer.nativeOffer end
    local group = status == "ready" and "finishedBy" or "startedBy"
    if status == "active" then
        local target=self:ObjectiveTarget(q,state)
        if not target and #(active.objectives or {})==0 then target=self:TriggerTarget(q,state) end
        if target and not target.approximate then return target end
        local waypoint=nativeWaypoint(q.id)
        if waypoint then
            if waypointMatchesInstance(self,q,state,waypoint,target) then return waypoint end
            return target
        end
        if target then return target end
        if self:DeliveryOnly(q,state) then
            return self:Target(q,{position=state.position,faction=state.faction,completed=state.completed,
                routeState=state.routeState or state,quests={[q.id]={ready=true}}})
        end
        if not self:UnmappedTargetArea(q,state) then return self:QuestAreaTarget(q,state) end
        return
    end
    local sources = self.db.Quest.Get(q.id, group) or {}
    local pickupItem
    if not active then
        for _,item in ipairs(sources[3] or {}) do
            local held=((state.bags or {})[item] or 0)>0
            if held or not pickupItem and not next(sources[1] or {}) and not next(sources[2] or {}) then
                local name=self.db.Item.Get(item,"name") or ("物品 #"..item)
                pickupItem={id=item,held=held,text=(held and "使用「" or "获得并使用「")..name.."」接取任务。"}
                if held then
                    local p=state.position
                    return p and {map=p.map,x=p.x,y=p.y,node=p.node,startItemId=item,label=name},nil,pickupItem
                end
            end
        end
    end
    local best, bestDistance, sourceCount, unavailable = nil, nil, 0, 0
    local bestPriority=0
    local function nearer(point,priority)
        if priority<bestPriority then return false end
        local distance=A.Navigation:Distance(state.position,point)
        if priority==bestPriority and not nearerSource(state,point,distance,best,bestDistance) then return false end
        best,bestDistance,bestPriority=point,distance,priority
        return true
    end
    if observations then
        for _,offers in pairs(observations) do
            local observed=offers[q.id]
            if type(observed)=="table" and observed.nativeOffer then nearer(observed.nativeOffer,2) end
        end
    end
    -- Zero-level records join automatic leveling when an NPC actually offers them.
    local offeredOnly=not active and (q.questLevel==0 and state.locked~=q.id and
        not state.preparingQuest and not state.taskBatch or best and q.taskFacts and q.taskFacts.hidden)
    local filterFaction=not active or hasFriendlyRecipient(self.db.Npc,sources,state.faction)
    for kind = 1, 2 do
        local entity = kind == 1 and self.db.Npc or self.db.Object
        for _, id in ipairs(sources[kind] or {}) do
            sourceCount=sourceCount+1
            local offers=not active and kind==1 and state.questOffers and state.questOffers[id]
            local loot=not active and kind==2 and q.pickupLoot and q.pickupLoot[id]
            if collectedLoot(loot,state) or offers and not offers[q.id] or not (offers and offers[q.id]) and
                (offeredOnly or filterFaction and kind==1 and oppositeGiver(entity,id,state.faction)) then
                unavailable=unavailable+1
            else
                for _, point in ipairs(self:EntityPoints(entity, id, active~=nil)) do
                    -- Current giver, known location, then area fallback.
                    local priority=offer and kind==1 and id==state.questNPC and 3 or point.approximate and 1 or 2
                    if nearer(point,priority) then
                        best.label=best.travelHint and best.label or best.approximate and "区域参考点" or (kind==1 and "QuestieDB NPC 位置" or "QuestieDB 对象位置")
                        best.entityKind,best.entityId=kind==1 and "npc" or "object",id
                        best.entityName=entity.Get(id,"name")
                        best.pickupLoot=loot or nil
                    end
                end
            end
        end
    end
    local pin=active and active.ready and active.mapPin
    if pin and pin.ready and waypointMatchesInstance(self,q,state,pin,best) then
        local point={map=pin.map,x=pin.x,y=pin.y,label="任务交付点"}
        local recipient=self:Recipient(q)
        if not recipient and best and not best.approximate and A.Navigation:Near(point,best,30) then recipient=best end
        if recipient then point.entityKind,point.entityId,point.entityName=recipient.entityKind,recipient.entityId,recipient.entityName end
        return point
    end
    if best and not best.approximate then
        if best.entityKind=="npc" and best.sourceAreaId then
            patrolContact(best,self.db.Npc.Get(best.entityId,"waypoints"),state.position,self.maps,active)
        end
        if not best.approximate then return best end
    end
    -- Forecast turn-ins use a virtual ready state; only a genuinely ready quest has a native recipient waypoint.
    if active and active.ready and C_QuestLog and C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(q.id) then
        local point=nativeWaypoint(q.id)
        if point and waypointMatchesInstance(self,q,state,point,best) then return point end
    end
    if best then return best end
    if (sourceCount>0 or offeredOnly) and unavailable==sourceCount then return nil,true end
    -- The journal category and a starter item's drop area are not the quest giver's position.
    if not active then return nil,nil,pickupItem end
    if self:UnmappedTargetArea(q,state) then return end
    local point=self:QuestAreaTarget(q,state)
    if point then
        local contact=soleContact(self,sources)
        if contact then
            point.entityKind,point.entityId,point.entityName=contact.entityKind,contact.entityId,contact.entityName
        end
    end
    return point
end

function D:QuestContact(id,group)
    return soleContact(self,self.db.Quest.Get(id,group))
end

-- A recipient's identity remains useful for batching even without a usable map.
function D:Recipient(q,point)
    if point and point.entityKind and point.entityId then
        return {entityKind=point.entityKind,entityId=point.entityId,entityName=point.entityName}
    end
    return soleContact(self,self.db.Quest.Get(q.id,"finishedBy"))
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
        (state.interface or A.interface)~=cache.interface then return end
    local facts=cache.quests[q.id]
    -- The audited Forever directory supplies both level fields by quest ID.
    if facts and (facts.requiredLevel~=nil or facts.hidden=="retired" or facts.level==q.questLevel or q.questLevel==-1) and
        (not facts.sourceItemId or facts.sourceItemId==(q.sourceItemId or 0)) then return facts end
end

local function dungeonAreas(q,state)
    local catalog=A.DungeonCatalog
    return catalog and (state.clientVersion or A.clientVersion)==catalog.version and
        catalog.objectiveAreas and catalog.objectiveAreas[q.id]
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
    local recipients=self.db.Quest.Get(q.id,"finishedBy") or {}
    local areas=dungeonAreas(q,state)
    return facts~=nil and (facts.level==q.questLevel or q.questLevel==-1 and cache~=nil) and facts.complex==false and
        facts.objectives~=nil and #facts.objectives==0 and (#(recipients[1] or {})+#(recipients[2] or {})>0 or
        areas~=nil and areas.turnin~=nil)
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
                    if nearerSource(state,p,distance,best,bestDistance) then
                        best,bestDistance=p,distance
                    end
                end
            end
        end
    end
    -- These are positions of players receiving progress, not exact target spawns.
    if best then return {map=best.map,x=best.x,y=best.y,approximate=true,sourceKind="observation",label="任务目标附近"} end
end

-- Native event text can locate a related NPC without inventing a completion objective.
function D:EventNPC(q,objective)
    if objective.type~="event" or objective.finished or objective.targetId or type(objective.text)~="string" then return end
    local found
    for _,field in ipairs({"finishedBy","startedBy"}) do
        for _,id in ipairs((self.db.Quest.Get(q.id,field) or {})[1] or {}) do
            local name=self.db.Npc.Get(id,"name")
            if type(name)=="string" and name~="" and objective.text:find(name,1,true) then
                if found and found~=id then return end
                found=id
            end
        end
    end
    return found
end

function D:ObjectiveTargets(q,state)
    local active=state.quests[q.id]
    if not active then return {} end
    -- Shared only by the immutable snapshot of one planning pass.
    local cache=state.objectiveTargets
    local cached=cache and cache[active]
    if cached and cached.position==state.position then return cached.points,cached.purchases end
    local identities=self:ObjectiveIdentities(q,state)
    local chosen,distances,purchases={},{},{}
    local thread,main=coroutine.running()
    local work=0
    local function checkpoint()
        work=work+1
        if work==100 and thread and not main then work=0;coroutine.yield() end
    end
    local function consider(entity,id,label,index,kind,identity,sourceKind,points)
        for _,point in ipairs(points or self:EntityPoints(entity,id,true)) do
            local best,bestDistance=chosen[index],distances[index]
            local distance=A.Navigation:Distance(state.position,point)
            if sourceKind=="vendor" then
                local old=purchases[index]
                if not old or not old.map or distance and (not old.distance or distance<old.distance) then
                    purchases[index]={npcId=id,name=entity.Get(id,"name"),map=point.map,distance=distance}
                end
            end
            local precise=best and best.approximate and not point.approximate
            local comparable=not best or (not best.approximate)==(not point.approximate)
            if precise or comparable and nearerSource(state,point,distance,best,bestDistance) then
                chosen[index],distances[index]=point,distance
                point.label,point.objectiveIndex=point.travelHint and point.label or point.approximate and "区域参考点" or label,index
                point.entityKind,point.entityId=kind,id
                point.targetKind,point.targetId=identity.kind,identity.id
                point.sourceKind=sourceKind
                if sourceKind=="vendor" then point.targetName=self.db.Item.Get(identity.id,"name") end
            end
            checkpoint()
        end
        checkpoint()
    end
    for index,entry in pairs(identities) do
        if entry.kind=="killcredit" then
            for _,id in ipairs(entry.npcIds or {}) do
                consider(self.db.Npc,id,"任务目标分布",index,"npc",entry)
            end
        elseif entry.kind=="npc" or entry.kind=="object" then
            consider(entry.kind=="npc" and self.db.Npc or self.db.Object,entry.id,"QuestieDB 任务目标分布",index,entry.kind,entry)
        elseif entry.kind=="item" and q.id==470 and entry.id==3349 then
            -- Sida specifies Ironbeard's Tomb. Crimson Ooze spawns there; Black Ooze also spawns across Wetlands.
            consider(self.db.Npc,1031,"铁须之墓",index,"npc",entry)
            if chosen[index] then chosen[index].siteName="铁须之墓" end
        elseif entry.kind=="item" then
            eachItemDrop(self,entry.id,state,function(entity,id,kind,spawns)
                consider(entity,id,"QuestieDB 任务物品来源分布",index,kind,entry,nil,self:EntityPoints(entity,id,true,spawns))
            end)
            for _,id in ipairs(self.db.Item.Get(entry.id,"vendors") or {}) do
                local faction=self.db.Npc.Get(id,"friendlyToFaction")
                if faction=="AH" or faction==(state.faction=="Alliance" and "A" or state.faction=="Horde" and "H") then
                    purchases[index]=purchases[index] or {npcId=id,name=self.db.Npc.Get(id,"name")}
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
    for index,o in ipairs(active.objectives or {}) do
        local id=not chosen[index] and not identities[index] and self:EventNPC(q,o)
        if id then consider(self.db.Npc,id,"任务事件地点",index,"npc",{},"event") end
    end
    local singleIndex
    for index,o in ipairs(active.objectives or {}) do
        if not o.finished then
            if singleIndex then singleIndex=nil;break end
            singleIndex=index
        end
    end
    local result={}
    local areas=dungeonAreas(q,state)
    local inside=areas and areas.objective and A.Dungeon and A.Dungeon.TaskInstance and
        A.Dungeon.TaskInstance(nil,state,self,areas.objective)
    for index,o in ipairs(active.objectives or {}) do
        if not o.finished then
            local identity=identities[index]
            local point=chosen[index]
            if not point or point.approximate then point=self:ObservedObjectiveTarget(q,state,identity,o) or point end
            -- Some instance mobs are also plotted on the outdoor entrance map by the provider.
            if point and inside and A.Dungeon.TaskInstance(point,state,self)~=inside then point=nil end
            local unmapped=not point and self:UnmappedTargetArea(q,state,index)
            if not point and not unmapped then point=self:QuestAreaTarget(q,state) end
            local pin=index==singleIndex and active.mapPin
            if pin and not pin.ready and not inside and not unmapped then
                if not point or point.approximate or not A.Navigation:Near(pin,point,100) then
                    point={label="任务目标地点"}
                end
                point.map,point.x,point.y=pin.map,pin.x,pin.y
            end
            if point then
                if point.entityId then
                    local entity=point.entityKind=="npc" and self.db.Npc or self.db.Object
                    point.entityName=entity.Get(point.entityId,"name")
                end
                if identity then point.targetKind,point.targetId=identity.kind,identity.id end
                point.objectiveIndex=index;point.purchase=purchases[index];result[#result+1]=point
            end
        end
    end
    if cache then cache[active]={position=state.position,points=result,purchases=purchases} end
    return result,purchases
end

function D:ObjectiveTarget(q,state)
    local best,bestDistance
    for _,point in ipairs(self:ObjectiveTargets(q,state)) do
        local distance=A.Navigation:Distance(state.position,point)
        local precise=best and best.approximate and not point.approximate
        local comparable=not best or (not best.approximate)==(not point.approximate)
        if precise or comparable and nearerSource(state,point,distance,best,bestDistance) then
            best,bestDistance=point,distance
        end
    end
    return best
end

-- Preserve a destination's known area when no UI-map coordinate can be produced.
function D:UnmappedTargetArea(q,state,objectiveIndex)
    local objectiveAreas=dungeonAreas(q,state)
    local function areaOf(lists,pickup)
        local found
        for _,spawns in ipairs(lists) do
            for area,points in pairs(spawns) do
                for _,p in ipairs(points) do
                    if usableSpawn(p) or areaOnlySpawn(p) then
                        local map=self.maps[area]
                        if (not pickup or usableSpawn(p)) and map and map>0 and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map) then return end
                        if found and found~=area then
                            -- Different floors can still identify one instance even without a pin.
                            local instanceFor=A.Dungeon and A.Dungeon.TaskInstance
                            local instance=instanceFor and instanceFor(nil,state,self,found)
                            if not instance or instanceFor(nil,state,self,area)~=instance then return end
                            found=math.min(found,area)
                        else
                            found=area
                        end
                        if not pickup then break end
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
        local filterFaction=not active or hasFriendlyRecipient(self.db.Npc,sources,state.faction)
        local lists={}
        for kind=1,2 do
            local entity=kind==1 and self.db.Npc or self.db.Object
            for _,id in ipairs(sources[kind] or {}) do
                local offers=not active and kind==1 and state.questOffers and state.questOffers[id]
                local loot=not active and kind==2 and q.pickupLoot and q.pickupLoot[id]
                if not collectedLoot(loot,state) and
                    (kind==2 or (offers and offers[q.id]) or not offers and (not filterFaction or not oppositeGiver(entity,id,state.faction))) then
                    add(lists,entity,id)
                end
            end
        end
        if not active then
            for _,item in ipairs(sources[3] or {}) do
                if (state.bags or {})[item] and state.bags[item]>0 then return end
                for _,id in ipairs(self.db.Item.Get(item,"npcDrops") or {}) do add(lists,self.db.Npc,id) end
                for _,id in ipairs(self.db.Item.Get(item,"objectDrops") or {}) do add(lists,self.db.Object,id) end
            end
        end
        return areaOf(lists,not active) or #lists==0 and objectiveAreas and objectiveAreas[active and "turnin" or "accept"] or nil
    end
    if objectiveAreas and objectiveAreas.objective then
        for index,o in ipairs(active.objectives or {}) do
            if not o.finished and (not objectiveIndex or objectiveIndex==index) then return objectiveAreas.objective,index end
        end
        if #(active.objectives or {})==0 and not objectiveIndex then return objectiveAreas.objective end
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
        local eventNpc=not entry and self:EventNPC(q,o)
        if (not objectiveIndex or index==objectiveIndex) and not o.finished and (entry or counts[index]==1 or eventNpc) then
            local lists={}
            if eventNpc then add(lists,self.db.Npc,eventNpc)
            elseif entry and (entry.kind=="npc" or entry.kind=="object") then add(lists,entry.kind=="npc" and self.db.Npc or self.db.Object,entry.id)
            elseif entry and entry.kind=="killcredit" then for _,id in ipairs(entry.npcIds or {}) do add(lists,self.db.Npc,id) end
            elseif entry and entry.kind=="item" then
                eachItemDrop(self,entry.id,state,function(_,_,_,spawns) lists[#lists+1]=spawns end)
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
            area=entry and objectiveAreas and objectiveAreas[entry.kind..":"..entry.id]
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
                    local supplied=#(starters[1] or {})+#(starters[2] or {})+#(starters[3] or {})>0
                    for _,id in ipairs(starters[3] or {}) do if id==row[1] then supplied=false;break end end
                    description.providedOnAccept=not state.quests[q.id] and need==1 and q.sourceItemId==row[1] and supplied or nil
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
    local events={}
    for _,fact in ipairs(cache and cache.objectives or {}) do
        if fact.kind=="areaTrigger" or fact.kind=="areaTriggerEnter" or fact.kind=="criteriaTree" then events[#events+1]=fact end
    end
    for _,fact in ipairs(events) do
        local criteria=fact.kind=="criteriaTree"
        local description={text=criteria and "按任务日志完成事件" or "探索任务指定区域，按日志完成探索要求。",
            type="event",finished=false,numRequired=fact.count>0 and fact.count or nil}
        description[criteria and "criteriaTreeId" or "areaTriggerId"]=fact.id
        if order.eventObjectiveFirst and order.eventObjectiveFirst[q.id] then table.insert(descriptions,1,description)
        else descriptions[#descriptions+1]=description end
    end
    -- The provider's single event point locates the cached event; do not add it twice.
    if trigger and #events==0 then
        local description={text="按任务日志完成事件",type="event",finished=false}
        if order.eventObjectiveFirst and order.eventObjectiveFirst[q.id] then table.insert(descriptions,1,description)
        else descriptions[#descriptions+1]=description end
    end
    -- Query reference placements only; this temporary lookup never becomes a character snapshot.
    -- Malformed requirements leave their native indices unknown.
    local virtual={position=state.position,faction=state.faction,inInstance=state.inInstance,instanceId=state.instanceId,
        referenceIndexUnknown=complex,routeState=state,quests={[q.id]={objectives=descriptions}},
        clientVersion=state.clientVersion,clientBuild=state.clientBuild,interface=state.interface}
    local positions={}
    local targets,purchases=self:ObjectiveTargets(q,virtual)
    for _,point in ipairs(targets) do positions[point.objectiveIndex]=point end
    local areas={}
    for index in ipairs(descriptions) do
        if not positions[index] then areas[index]=self:UnmappedTargetArea(q,virtual,index) end
    end
    return descriptions,positions,complex,areas,purchases
end

function D:Audit()
    return A.Audit.Text(A.Audit.Build(self, false))
end
