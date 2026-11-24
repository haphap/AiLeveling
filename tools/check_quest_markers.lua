-- Print each phase for the full provider catalog plus cache-only quests, for one correction context.
-- Run from the emulator directory with the quest_runtime.lua arguments and a comma-separated list of native UI map IDs.
local A=dofile(arg[1].."/tools/quest_runtime.lua")
for _,file in ipairs({"Data/PublicTransit.lua","Planner/DungeonTasks.lua"}) do
    assert(loadfile(arg[1].."/"..file))("AiLeveling",A)
end
local native={}
for id in assert(arg[7],"native UI map IDs required"):gmatch("%d+") do native[tonumber(id)]={mapID=tonumber(id)} end
C_Map.GetMapInfo=function(id) return native[id] end
local data=A.Data
local ids,seen={},{}
for _,id in ipairs(data.ids) do ids[#ids+1]=id;seen[id]=true end
for id in pairs(A.TaskFacts.cacheXP.quests) do if not seen[id] then ids[#ids+1]=id end end
table.sort(ids)
local state={clientVersion=A.clientVersion,interface=A.interface,clientBuild=A.build,faction=arg[3],quests={},completed={},bags={}}
local function emit(q,phase,index,objective,point,area)
    local status="located"
    if not point then status=area and "areaId" or "unknown"
    elseif point.areaOnly then status="zone"
    elseif point.spawnArea then status="spawnArea"
    elseif point.approximate then status="approximate" end
    local p=point or {}
    print(q.id,q.title or "",phase,index or 0,objective and objective.targetKind or "-",objective and objective.targetId or 0,
        status,p.map or 0,p.x or 0,p.y or 0,p.entityKind or "-",p.entityId or 0,p.sourceKind or "-",seen[q.id] and "db" or "cache",area or p.sourceAreaId or 0,objective and objective.numRequired or 0)
    assert(not point or (p.map>0 and p.x>=0 and p.x<=1 and p.y>=0 and p.y<=1),q.id)
    assert(not p.areaOnly or not A.Navigation.Target({position=p}),q.id)
end
for _,id in ipairs(ids) do
    local facts=A.TaskFacts.cacheXP.quests[id]
    local q=data:GetQuest(id) or {id=id,title="",questLevel=facts.level,taskFacts=facts}
    state.position=nil
    local giver=data:Target(q,state)
    emit(q,"accept",nil,nil,giver,not giver and data:UnmappedTargetArea(q,state))
    state.position=giver
    local objectives,points,complex,areas=data:ReferenceObjectiveTargets(q,state)
    for i,o in ipairs(objectives) do emit(q,"objective",i,o,points[i],areas[i]) end
    if complex or (#objectives==0 and not data:DeliveryOnly(q,state)) then emit(q,"unspecified") end
    state.quests[id]={ready=true}
    local recipient=data:Target(q,state)
    emit(q,"turnin",nil,nil,recipient,not recipient and data:UnmappedTargetArea(q,state))
    state.quests[id]=nil
end
