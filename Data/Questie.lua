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
    -- Forever's Mature Paletusk drops the same boar meat as the starter-zone boars.
    if item==769 then
        for _,id in ipairs(self.db.Item.Get(item,"npcDrops") or {}) do if id==255851 then return end end
        local spawns=self.db.Npc.Get(255851,"spawns")
        if spawns then visit(self.db.Npc,255851,"npc",spawns) end
    end
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
    if not db or type(db.RequireContract) ~= "function" then return false, "请安装 QuestieDB v1.1.5 无限版或兼容版本。" end
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
    self.dangerNames,self.dangerIDs={},{}
    for _,faction in ipairs({"Alliance","Horde"}) do
        for _,rows in pairs(A.DangerData and A.DangerData[faction] or {}) do
            for _,row in ipairs(rows) do self.dangerNames[row.name]=false end
        end
    end
    for index,id in ipairs(npc.GetAllIds()) do
        if npc.GetRaw then
            local name=npc.GetRaw(id,"name")
            if self.dangerNames[name]~=nil then
                self.dangerNames[name]=npc.Get(id,"name")
                self.dangerIDs[name]=self.dangerIDs[name]==nil and id or false
            end
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
                        description=npc.Get(id,"subName"),position=position,
                        bindName=kind=="bind" and innAreas[id] and C_Map.GetAreaInfo and C_Map.GetAreaInfo(innAreas[id]) or nil}
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

local function chineseTitle(value)
    return (not canaccessvalue or canaccessvalue(value)) and type(value)=="string"
        and value~="未知" and not value:match("^任务 #%d+$") and value:find("[\228-\233][\128-\191][\128-\191]")
end

function D:QuestTitle(id,native,database)
    if not A.questTitlesZhCN then return database or native end
    local record=self.cache[id]
    database=database or record and record.title
    if canaccessvalue and not canaccessvalue(native) then native=nil end
    if not chineseTitle(native) and not chineseTitle(database) and HaveQuestData and HaveQuestData(id)
        and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local name=C_QuestLog.GetTitleForQuestID(id)
        if chineseTitle(name) then native=name end
    end
    if chineseTitle(native) then
        if record then record.title=native else A.questTitlesZhCN[id]=native end
        return native
    end
    if chineseTitle(database) then return database end
    return A.questTitlesZhCN[id] or native or database
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
    local quests=state and state.quests or A.state and A.state.quests
    q.title = self:QuestTitle(id,quests and quests[id] and quests[id].title,q.name) or ("任务 #" .. id)
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

-- Outdoor farming areas use a recorded spawn nearest the center of each populated patch.
local huntPatches=setmetatable({}, {__mode="k"})
local function patchesFor(spawns)
    if huntPatches[spawns]~=nil then return huntPatches[spawns] end
    local cells,seen={},{}
    local peak=0
    for _,p in ipairs(spawns) do
        if usableSpawn(p) then
            local x,y=p[1],p[2]
            local key=x..","..y
            if not seen[key] then
                seen[key]=true
                -- Outdoor zone maps have a 3:2 aspect ratio.
                local cellId=math.floor(x/3)*32+math.floor(y/4.5)
                local cell=cells[cellId] or {x=0,y=0}
                cells[cellId]=cell
                cell[#cell+1]=p
                cell.x,cell.y=cell.x+x,cell.y+y
                peak=math.max(peak,#cell)
            end
        end
    end
    local result=peak>=3 and {peak=peak,cells={}} or false
    if result then
        for cellId,cell in pairs(cells) do
            local x,y=cell.x/#cell,cell.y/#cell
            local best,distance
            for _,p in ipairs(cell) do
                local d=((p[1]-x)*1.5)^2+(p[2]-y)^2
                if not best or d<distance then best,distance=p,d end
            end
            result.cells[cellId]={point=best,count=#cell}
        end
    end
    huntPatches[spawns]=result
    return result
end

local function useHuntPatch(cells,cellId,minimum)
    if cells[cellId].count>=minimum then return true end
    -- Suppress a fringe point only in favour of a neighbouring patch. A smaller,
    -- separate camp can still be the best place for a player already beside it.
    local nearby=0
    for dx=-1,1 do
        for dy=-1,1 do
            local cell=cells[cellId+32*dx+dy]
            if cell then
                if cell.count>=minimum then return false end
                nearby=nearby+cell.count
            end
        end
    end
    return nearby>=3
end

function D:EntityPoints(entity, id, allowArea, spawns, huntCount)
    spawns=spawns or entity.Get(id,"spawns")
    local points=self:SpawnPoints(spawns,allowArea,huntCount)
    -- Sergeant Riftan's fixed camp. The Riverglades terrain here is 165.76 yd
    -- (1.60.1 build 70862); the walking mesh has a single surface at 166 yd.
    if entity==self.db.Npc and id==258023 then
        for _,p in ipairs(points) do
            if p.map==2548 and math.abs(p.x-.3071)<.00001 and math.abs(p.y-.4906)<.00001 then p.z=165.76 end
        end
    end
    -- Pyron's synthetic continent pin misses the quarry. Forever kill credit locates
    -- the search area near the BRD portal, not a fixed spawn for this patrol.
    if entity==self.db.Npc and id==9026 and #points==1 and points[1].sourceAreaId==10074 and C_Map.GetMapInfo(1427) then
        points[1]={map=1427,x=0.2615,y=0.7413,sourceAreaId=1445,approximate=true,sourceKind="observation",
            siteName="黑石山采石场",label="任务目标附近",travelHint="进入黑石山，在黑石深渊入口外的采石场寻找巡逻的征服者派隆。"}
    end
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

function D:SpawnPoints(spawnList,allowArea,huntCount)
    local points,areas = {},{}
    for area, spawns in pairs(spawnList or {}) do
        local map = self.maps[area]
        local info=map and map>0 and C_Map.GetMapInfo(map)
        local patches=info and huntCount and huntCount>=1 and #spawns>=8 and
            (not info.mapType or info.mapType==3) and patchesFor(spawns)
        if patches and (huntCount>1 or patches.peak>=8) then
            -- Even one quest drop can take repeated kills. Only group these for well-sampled common mobs.
            local minimum=math.max(3,huntCount==1 and math.ceil(patches.peak/2) or math.min(huntCount,patches.peak))
            for cellId,patch in pairs(patches.cells) do
                if useHuntPatch(patches.cells,cellId,minimum) then
                    local p=patch.point
                    points[#points+1]={map=map,x=p[1]/100,y=p[2]/100,sourceAreaId=area,spawnArea=true}
                end
            end
        elseif info then
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
local function nearerSource(state,point,distance,best,bestDistance,preferredMap)
    if not best then return true end
    local map=preferredMap or state.browseMap
    if map then
        if (point.map==map)~=(best.map==map) then return point.map==map end
        return distance and (not bestDistance or distance<bestDistance)
    end
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

-- Compare travel to a known patrol and a fixed spawn on equal terms.
local function preferObjective(state,point,distance,best,bestDistance)
    if best then
        local located=not point.approximate or point.sourceKind=="patrol"
        local bestLocated=not best.approximate or best.sourceKind=="patrol"
        if located~=bestLocated then return located end
    end
    return nearerSource(state,point,distance,best,bestDistance)
end

function D:TriggerTarget(q,state)
    local trigger=self.db.Quest.Get(q.id,"triggerEnd")
    local best,bestDistance
    for _,point in ipairs(self:SpawnPoints(trigger and trigger[2],true)) do
        local distance=A.Navigation:Distance(state.position,point)
        if preferObjective(state,point,distance,best,bestDistance) then
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

local function contactName(self,entity,id)
    local name=entity.Get(id,"name")
    if entity==self.db.Item and A.QuestItemZhCN then return A.QuestItemZhCN(id,name) end
    if entity==self.db.Object and A.contactObjectsZhCN and not chineseTitle(name) then return A.contactObjectsZhCN[id] or name end
    return name
end

local function soleContact(self,sources)
    if not sources or #(sources[1] or {})+#(sources[2] or {})~=1 then return end
    local npc=#(sources[1] or {})==1
    local id=sources[npc and 1 or 2][1]
    return {entityKind=npc and "npc" or "object",entityId=id,
        entityName=contactName(self,npc and self.db.Npc or self.db.Object,id)}
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

-- Ghostmaw's two Riverglades bounties share this NPC. The provider has sightings
-- but no ordered path. These bends trace the reported river corridor on the zone map.
local ghostmawRiver = { [16591] = {{
    {63.4,37.2},{62.3,38.6},{62.3,40.1},{61.8,40.9},{60.3,42.1},{58.2,42.1},
    {57.1,42.9},{55.9,44.2},{55.4,45.6},{55.3,47.2},{54.7,49.3},{54.1,50.9},
    {53.1,52.1},{52.2,52.5},{50.3,52.4},{49.6,52.4},{48.8,53.4},{47.6,53.9},
    {47.1,54.8},{46.7,56.4},{46.4,57.6},{45.4,58.5},{44.0,59.6},{43.0,61.0},
    {42.4,62.5},{42.3,64.6},{42.6,66.0},{43.4,67.3},{44.5,68.2},{46.0,68.8},
    {47.5,68.8},{49.2,68.3},{50.5,67.4},{51.5,66.8},{52.7,66.9},{53.6,67.6},
    {53.8,68.9},{53.7,70.5},{53.2,71.7},{52.3,72.9},{51.2,73.5},{50.1,74.4},
    {49.7,75.6},{49.5,77.4},{49.6,78.6},{50.1,79.8},
}} }

local function npcPatrols(self,id)
    local paths=self.db.Npc.Get(id,"waypoints")
    if id==263380 and not (paths and paths[16591] and #paths[16591]>0) then return ghostmawRiver end
    return paths
end

-- Use a recorded passing point when the target patrols the player's current zone.
local function patrolTarget(point,paths,origin,maps,phase,pin)
    if type(paths)~="table" then return end
    local nearest
    for area,segments in pairs(paths) do
        local hasPath=(phase~="objective" or area==point.sourceAreaId) and type(segments)=="table" and type(segments[1])=="table" and type(segments[1][1])=="table"
        if hasPath then point.sourceKind="patrol" end
        local map=maps[area]
        if hasPath and (origin and map==origin.map or pin and map==pin.map) then
            for _,path in ipairs(segments) do
                for _,p in ipairs(path) do
                    if usableSpawn(p) then
                        local x,y=p[1]/100,p[2]/100
                        if pin and map==pin.map and A.Navigation:Near(pin,{map=map,x=x,y=y},30) then return true end
                        if origin and map==origin.map then
                            local distance=((x-origin.x)*1.5)^2+(y-origin.y)^2
                            if not nearest or distance<nearest then
                                nearest=distance
                                point.map,point.x,point.y,point.sourceAreaId=map,x,y,area
                            end
                        end
                    end
                end
            end
        end
    end
    if point.sourceKind~="patrol" then return end
    point.approximate,point.label=true,"巡逻路线参考点"
    point.travelHint="沿巡逻路线寻找「"..(point.entityName or "任务目标").."」"..
        (phase=="objective" and "。" or phase=="turnin" and "交付任务。" or "接取任务。")
end

local function matchesSourceMap(waypoint,target)
    return not (target and target.areaOnly and target.sourceAreaId) or waypoint.map==target.map
end

local function waypointFitsTarget(self,q,state,waypoint,target,turnin)
    if not matchesSourceMap(waypoint,target) then return false end
    local instanceFor=(state.inInstance or turnin) and A.Dungeon and A.Dungeon.TaskInstance
    if not instanceFor then return true end
    local area=not target and self:UnmappedTargetArea(q,state)
    local destination=instanceFor(target,state,self,area)
    if not destination or (not turnin and destination.instanceId~=state.instanceId) then return true end
    return instanceFor(waypoint,state,self)==destination
end

local function collectedLoot(loot,state)
    return loot and ((state.bags or {})[loot.id] or 0)>=loot.count
end

local function contactHint(point,spawn,turnin)
    -- Forever quests 657 and 660 share Kinelory, who leaves Quae during the escort.
    if point.entityKind=="npc" and point.entityId==2713 and not point.travelHint then
        point.travelHint="若只看到奎艾，可在奎艾处等基恩洛护送结束后返回。"
        if spawn then point.sourceKind,point.label="escortStart","护送起点" end
    elseif turnin and point.entityKind=="object" and point.entityId==177491 then
        -- Both factions place the quest barrel on crate 177490 at the same mill.
        point.travelHint="在北山伐木场的箱子上放置白蚁桶，再与桶互动交付。"
    end
    return point
end

function D:Target(q, state, pickupMap)
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
        if target and (not target.approximate or target.sourceKind=="patrol") then return target end
        local waypoint=nativeWaypoint(q.id)
        if waypoint then
            if waypointFitsTarget(self,q,state,waypoint,target) then return waypoint end
            return target
        end
        if target then return target end
        if self:DeliveryOnly(q,state) then
            return self:Target(q,{position=state.position,faction=state.faction,completed=state.completed,
                routeState=state.routeState or state,browseMap=state.browseMap,quests={[q.id]={ready=true}}})
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
                local name=contactName(self,self.db.Item,item) or ("物品 #"..item)
                pickupItem={id=item,held=held,text=(held and "使用「" or "获得并使用「")..name.."」接取任务。"}
                if held then
                    local p=state.position
                    return p and {map=p.map,x=p.x,y=p.y,node=p.node,startItemId=item,label=name},nil,pickupItem
                end
            end
        end
    end
    local best, bestDistance, sourceCount, unavailable = nil, nil, 0, 0
    local pin=active and active.ready and active.mapPin
    if pin and not pin.ready then pin=nil end
    local bestPriority=0
    local function nearer(point,priority)
        if priority<bestPriority then return false end
        local distance=A.Navigation:Distance(state.position,point)
        if best and priority==bestPriority and not nearerSource(state,point,distance,best,bestDistance,pickupMap) then return false end
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
                    -- A quest-wide marker may identify one of several eligible recipients.
                    if pin and not point.approximate and A.Navigation:Near(pin,point,30) then priority=4 end
                    if nearer(point,priority) then
                        best.label=best.travelHint and best.label or best.approximate and "区域参考点" or (kind==1 and "QuestieDB NPC 位置" or "QuestieDB 对象位置")
                        best.entityKind,best.entityId=kind==1 and "npc" or "object",id
                        best.entityName=contactName(self,entity,id)
                        best.pickupLoot=loot or nil
                    end
                end
            end
        end
    end
    local matchesRecipient=bestPriority==4
    if best and not best.approximate and best.entityKind=="npc" and best.sourceAreaId and not matchesRecipient then
        matchesRecipient=patrolTarget(best,self.db.Npc.Get(best.entityId,"waypoints"),state.position,self.maps,active and "turnin" or "accept",pin)
    end
    if pin and (matchesRecipient or not best or best.areaOnly) and waypointFitsTarget(self,q,state,pin,best,true) then
        local point={map=pin.map,x=pin.x,y=pin.y,label="任务交付点"}
        -- A nearby quest POI confirms the recipient. Keep the surveyed 3D spawn
        -- instead of transplanting its height to the POI's slightly different XY.
        if bestPriority==4 and best.z then return contactHint(best,true,true) end
        local recipient=matchesRecipient and best or self:Recipient(q)
        if recipient then point.entityKind,point.entityId,point.entityName=recipient.entityKind,recipient.entityId,recipient.entityName end
        return contactHint(point,false,true)
    end
    if best and not best.approximate then return contactHint(best,best.sourceAreaId~=nil,active) end
    -- Forecast turn-ins use a virtual ready state; only a genuinely ready quest has a native recipient waypoint.
    if active and active.ready and C_QuestLog and C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(q.id) then
        local point=nativeWaypoint(q.id)
        if point and waypointFitsTarget(self,q,state,point,best,true) then return point end
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

-- Resolve only the selected, unfinished objectives. Spawn and kill locations have no travel order.
function D:QuestPatrolSegments(id,state,map,focus,out)
    local seen={}
    local function add(npc)
        if not npc or seen[npc] then return end
        seen[npc]=true
        local before=#out
        for area,paths in pairs(npcPatrols(self,npc) or {}) do
            if self.maps[area]==map then
                for _,path in ipairs(paths) do
                    local prev
                    for _,p in ipairs(path) do
                        if usableSpawn(p) then
                            if prev and (prev[1]~=p[1] or prev[2]~=p[2]) then
                                out[#out+1]={prev[1]/100,prev[2]/100,p[1]/100,p[2]/100}
                            end
                            prev=p
                        else prev=nil end
                    end
                end
            end
        end
        -- Some named outdoor mobs have an ordered route only in the danger map.
        if #out==before and self.dangerIDs and self.db.Npc.GetRaw then
            local name=self.db.Npc.GetRaw(npc,"name")
            local zones=A.DangerData and A.DangerData[state.faction]
            if self.dangerIDs[name]==npc then
                for _,row in ipairs(zones and zones[map] or {}) do
                    if row.name==name then
                        for _,path in ipairs(row.paths) do
                            for i=3,#path,2 do out[#out+1]={path[i-2],path[i-1],path[i],path[i+1]} end
                        end
                    end
                end
            end
        end
    end
    local point=focus and focus.position
    if point and (point.sourceKind=="vendor" or point.entityKind=="object") then return end
    if point and point.entityKind=="npc" and point.entityId then
        add(point.entityId)
        return
    end
    local quest=self:GetQuest(id,state) or {id=id}
    for index,goal in pairs(self:ObjectiveIdentities(quest,state)) do
        if not focus or not focus.objectiveIndex or focus.objectiveIndex==index then
            if goal.kind=="npc" then add(goal.id)
            elseif goal.kind=="killcredit" then
                for _,npc in ipairs(goal.npcIds or {}) do add(npc) end
            elseif goal.kind=="item" then
                local drops=self.db.Item.Get(goal.id,"npcDrops")
                if drops and #drops==1 then add(drops[1]) end
            end
        end
    end
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

-- Ordinary centaur in the opposing clan's village. The quest extras also list a friendly bodyguard.
local centaurHunts={
    [92]={camp="玛格拉姆村",hint="击败玛格拉姆半人马，提升吉尔吉斯声望。",npcs={4638,4639,4640,4641,4642,4643,4644,4645}},
    [93]={camp="吉尔吉斯村",hint="击败吉尔吉斯半人马，提升玛格拉姆声望。",npcs={4646,4647,4648,4649,4651,4652,4653}},
}

-- Recorded hunting sites in Riverglades. The nearest coastal sighting can be outside the quest area.
local rivergladesHunts={
    [257001]={x=.77,y=.73,siteName="鱼人小岛",label="老腐块出没区域",hint="在河林东南的鱼人小岛及周围水域寻找老腐块。"},
    [257901]={x=.8633,y=.3860,siteName="爆破引线港北侧海盗营地"}, -- Eastsea Buccaneer
    [257910]={x=.8695,y=.3914,siteName="爆破引线港北侧海盗营地"}, -- Eastsea Musketeer
    [257915]={questId=95122,x=.7924,y=.3214,siteName="爆破引线港北侧海盗营地"}, -- Eastsea Raider
    [257916]={questId=95122,x=.7985,y=.3232,siteName="爆破引线港北侧海盗营地"}, -- Eastsea Bombardier
    [257861]={questId=95124,x=.9062,y=.2919,siteName="东侧海盗船",label="拉莫拉所在的上层甲板",
        hint="登上东侧海盗船，在上层甲板寻找拉莫拉。"},
}

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
    local areas=dungeonAreas(q,state)
    local outdoor=not state.inInstance and not (areas and areas.objective)
    local function consider(entity,id,label,index,kind,identity,sourceKind,points,spawns)
        local site=outdoor and kind=="npc" and not sourceKind and self.maps[16591] and rivergladesHunts[id]
        if outdoor and kind=="npc" and id==263380 and not sourceKind and self.maps[16591] then
            local path=npcPatrols(self,id)[16591][1]
            if path and path[1] and usableSpawn(path[1]) then
                points={{map=self.maps[16591],sourceAreaId=16591,x=path[1][1]/100,y=path[1][2]/100}}
            end
        elseif site and (not site.questId or site.questId==q.id) then
            points={{map=self.maps[16591],sourceAreaId=16591,x=site.x,y=site.y,spawnArea=true,
                siteName=site.siteName,label=site.label,travelHint=site.hint}}
        end
        if not points then
            local hunt=outdoor and kind=="npc" and not sourceKind and active.objectives[index].numRequired
            if hunt==1 and (identity.kind~="item" or (entity.Get(id,"rank") or 0)~=0 or next(entity.Get(id,"waypoints") or {})) then
                hunt=nil
            end
            points=self:EntityPoints(entity,id,true,spawns,hunt)
        end
        if outdoor and kind=="npc" and not sourceKind and #points==1 and not points[1].approximate and not points[1].spawnArea then
            local paths=npcPatrols(self,id)
            if paths and paths[points[1].sourceAreaId] then
                points[1].entityName=entity.Get(id,"name")
                patrolTarget(points[1],paths,state.position,self.maps,"objective")
                if paths==ghostmawRiver then points[1].travelHint="沿洛格玛北侧瀑布至南部农场的河道寻找幽魂之颚。金线为巡逻参考河段。" end
            end
        end
        for _,point in ipairs(points) do
            local best,bestDistance=chosen[index],distances[index]
            local distance=A.Navigation:Distance(state.position,point)
            if sourceKind=="vendor" then
                local old=purchases[index]
                if not old or not old.map or distance and (not old.distance or distance<old.distance) then
                    purchases[index]={npcId=id,name=entity.Get(id,"name"),map=point.map,distance=distance}
                end
            end
            if preferObjective(state,point,distance,best,bestDistance) then
                chosen[index],distances[index]=point,distance
                point.label,point.objectiveIndex=point.travelHint and point.label or point.approximate and "区域参考点" or label,index
                point.entityKind,point.entityId=kind,id
                point.targetKind,point.targetId=identity.kind,identity.id
                point.sourceKind=sourceKind or point.sourceKind
                if sourceKind=="vendor" then point.targetName=contactName(self,self.db.Item,identity.id) end
            end
            checkpoint()
        end
        checkpoint()
    end
    for index,entry in pairs(identities) do
        local hunt=entry.kind=="reputation" and centaurHunts[entry.id]
        if hunt then
            for _,id in ipairs(hunt.npcs) do
                consider(self.db.Npc,id,hunt.camp,index,"npc",entry,"reputation",self:EntityPoints(self.db.Npc,id,false))
            end
            local point=chosen[index]
            if point then point.siteName,point.travelHint=hunt.camp,hunt.hint end
        elseif entry.kind=="killcredit" then
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
                consider(entity,id,"QuestieDB 任务物品来源分布",index,kind,entry,nil,nil,spawns)
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
    -- The POI has no objective index. Use it only for a single goal without a known site.
    local pin=#(active.objectives or {})==1 and active.mapPin
    local result={}
    local inside=areas and areas.objective and A.Dungeon and A.Dungeon.TaskInstance and
        A.Dungeon.TaskInstance(nil,state,self,areas.objective)
    for index,o in ipairs(active.objectives or {}) do
        if not o.finished then
            local identity=identities[index]
            local point=chosen[index]
            if not point or point.approximate and point.sourceKind~="patrol" then point=self:ObservedObjectiveTarget(q,state,identity,o) or point end
            -- Some instance mobs are also plotted on the outdoor entrance map by the provider.
            if point and inside and A.Dungeon.TaskInstance(point,state,self)~=inside then point=nil end
            local unmapped=not point and self:UnmappedTargetArea(q,state,index)
            if not point and not unmapped then point=self:QuestAreaTarget(q,state) end
            if pin and not pin.ready and not inside and not unmapped and (not point or point.areaOnly) and matchesSourceMap(pin,point) then
                point={map=pin.map,x=pin.x,y=pin.y,label="客户端任务标记"}
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
        if preferObjective(state,point,distance,best,bestDistance) then
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
            local name=contactName(self,entity,row[1])
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
