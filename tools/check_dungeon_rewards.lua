-- Real fixed QuestieDB runtime, character state and map distances simulated.
local root,package,faction,class,raceId,raceFile=assert(arg[1]),assert(arg[2]),assert(arg[3]),assert(arg[4]),assert(tonumber(arg[5])),assert(arg[6])
local client,metadata=dofile("emulator/client.lua"),dofile("emulator/metadata.lua")
client.install({expansion="Forever",faction=faction,classFile=class,raceId=raceId,raceFile=raceFile,locale="zhCN"})
metadata.load(package.."/QuestieDB_Forever.toc","QuestieDB")
local db=metadata.loadAddon(package.."/QuestieDB_Forever.toc","QuestieDB",package)
local A={Navigation={Distance=function(_,a,b)
    if a and b and a.map==b.map then return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)*1000 end
end}}
C_Map={GetMapInfo=function(id) return {mapID=id} end};C_QuestLog={}
for _,file in ipairs({"State.lua","Hearth.lua","Data/Content.lua","Data/TaskFacts.lua","Data/Experience.lua","Data/Flights.lua","Data/Questie.lua",
    "Planner/Eligibility.lua","Planner/Chains.lua","Planner/TaskGuide.lua","Planner/TaskQueue.lua","Planner/Estimates.lua","Planner/Gear.lua",
    "Planner/Progression.lua","Planner/Travel.lua","Planner/Flights.lua","Planner/Supplies.lua","Planner/Dungeon.lua","Planner/Planner.lua"}) do
    assert(loadfile(root.."/"..file))("AiLeveling",A)
end
local function run(fn)
    local co=coroutine.create(fn)
    while true do
        local ok,result=coroutine.resume(co);assert(ok,result)
        if coroutine.status(co)=="dead" then return result end
    end
end
assert(A.Data:Connect(db));run(function() A.Data:BuildIndex() end)
assert(loadfile(root.."/Data/Dungeons.lua"))("AiLeveling",A)
assert(loadfile(root.."/Planner/DungeonTasks.lua"))("AiLeveling",A)
assert(loadfile(root.."/Planner/Selection.lua"))("AiLeveling",A)
local s=dofile(root.."/tests/fixtures.lua").State()
s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
s.faction,s.class,s.raceId=faction,class,raceId
s.classMask,s.raceMask=db.Enum.classKeys[class],db.Enum.raceMaskById[raceId]
s.spells,s.specializations,s.completionKnown={},{},true
s.position={map=faction=="Alliance" and 1436 or 1413,x=0.5,y=0.5}
local count,total,known=0,0,0
local catalog=A.Dungeon.Catalog(s,A.Content)
for _,level in ipairs({10,20,30,40,50,59}) do
    s.level,s.maxXP=level,A.Experience.xpToLevel[level]
    for id,d in pairs(catalog) do
        count=count+1
        local rows=A.Dungeon.Tasks(d,s,A.Data)
        local eligible,sum,unknown=0,0,0
        for _,row in ipairs(rows) do
            total=total+1
            local q=A.Data:GetQuest(row.id)
            local xp=A.TaskGuide.XP(q,level,s)
            if row.group==5 then assert(row.xp==nil) else assert(row.xp==xp) end
            if row.xp then known=known+1 end
            if row.group~=5 and not row.lowValue and not row.requireCheck and (row.allowed and (row.position or row.areaId) or row.preparation) then
                eligible=eligible+1
                if xp then sum=sum+xp else unknown=unknown+1 end
            end
        end
        local result=A.Dungeon.TaskRewards(rows)
        assert(result.count==eligible and result.xp==sum and result.unknownXP==unknown)
        assert(not next(s.quests) and not next(s.completed))
    end
end
assert(count==204 and total>100)
print(string.format("catalog\t%d dungeon/level checks\t%d task rows\t%d known XP rows",count,total,known))
s.level,s.maxXP=20,A.Experience.xpToLevel[20]
local d=catalog[faction=="Alliance" and "reference:36" or "reference:389"]
A.state,A.char,A.ready=s,{turnIns={},skipped={}},true
A.State.Refresh=function() A.Selection:Snapshot(s);A.Dungeon:TaskBatchSnapshot(s) end
assert(A.Dungeon:StartTaskBatch(d.id))
local p=run(function() return A.Planner.Build(s,A.Data,{minutes=60,gearPreference="xp",dungeons=true,role="DAMAGER"}) end)
assert(p.taskBatch.rewards.count>0 and p.taskBatch.rewards.xp>0)
local r=p.taskBatch.rewards
print(string.format("batch\t%s\t%d roots\t%d counted\t%d reference XP\t%d unknown\t%d need prerequisites",d.title,p.taskBatch.remaining,r.count,r.xp,r.unknownXP,r.prepare))
assert(not next(s.quests) and not next(s.completed))
print("PASS all 34 dungeon catalogs at 6 levels and selected starter-dungeon task rewards")
-- Real source/encounter/entrance identities; no synthetic item stats imply real usability.
local drops=0
for id,source in pairs(A.Gear.DungeonSources(s)) do
    assert(A.Gear.GetSource(id,A.Data,s)==source)
    local dungeon=catalog[source.dungeonId]
    local boss=A.Dungeon.EncounterIdentity(source.encounterId,s)
    assert(dungeon and boss and dungeon.instanceId==boss.instanceId)
    local p={}
    s.inInstance,s.instanceId=false,nil
    A.Gear.PlanDungeonTarget(p,source,s,A.Data)
    assert(p.gearPlan and p.fallback.kind=="dungeonEnter" and p.fallback.position)
    assert(p.fallback.position.label==dungeon.title.."入口")
    s.inInstance,s.instanceId=true,source.instanceId
    A.Gear.PlanDungeonTarget(p,source,s,A.Data)
    assert(p.fallback.kind=="dungeonRun" and not p.fallback.position and not s.gearAcquired)
    drops=drops+1
end
assert(drops==11 and not next(s.completed))
print("PASS 11 observed drop sources: actual encounter maps and Questie entry maps; outside/inside guidance")
