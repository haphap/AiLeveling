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
C_Map.GetMapInfo=function(id) return {mapID=id,mapType=3,name="模拟地图"} end
local originMap=faction=="Alliance" and 1429 or 1411
local nextMap=faction=="Alliance" and 1436 or 1413
-- Only these adjacent outdoor maps share the simulated coordinate frame.
-- This tests planner continuity, not the client's actual world geometry or travel time.
local cross=true
A.Navigation.Distance=function(_,a,b)
    if not a or not b then return end
    if a.map==b.map then return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)*5000 end
    if not cross or (a.map~=originMap and a.map~=nextMap) or (b.map~=originMap and b.map~=nextMap) then return end
    local ax=a.x+(a.map==originMap and 1 or 0)
    local bx=b.x+(b.map==originMap and 1 or 0)
    return math.sqrt((ax-bx)^2+(a.y-b.y)^2)*5000
end
local s=dofile(root.."/tests/fixtures.lua").State()
s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
s.level,s.maxXP,s.faction,s.class,s.raceId=12,A.Experience.xpToLevel[12],faction,class,raceId
s.classMask,s.raceMask=db.Enum.classKeys[class],db.Enum.raceMaskById[raceId]
s.spells,s.specializations,s.completionKnown={},{},true
s.position={map=originMap,x=0.02,y=0.5}
local options={minutes=60,mode="fast",dungeons=false,role="DAMAGER"}
local started=os.clock()
local function plan() return run(function() return A.Planner.Build(s,A.Data,options) end) end
if faction=="Horde" then
    local q=assert(A.Data:GetQuest(844))
    local outside=assert(A.Data:Target(q,s))
    assert(outside.sourceAreaId==17 and outside.map==1413)
    assert(A.Dungeon.TaskInstance(outside,s,A.Data)==nil,"outdoor quest misclassified as Wailing Caverns")
    local action={kind="accept",questId=844,position=outside}
    assert(A.Dungeon.TaskApproach(action,s,A.Data)==action)
end
local p=plan()
local remote,localCount=0,0
for _,c in ipairs(p.taskChoices) do
    assert(A.Eligibility.Check(A.Data:GetQuest(c.questId),s,A.Data))
    local point=c.actions[1].position
    assert(point and (point.map==originMap or point.map==nextMap))
    if point.map==nextMap then remote=remote+1
    else s.skipped[c.questId]=true;localCount=localCount+1 end
end
assert(remote>0,"adjacent zone has no automatic candidate")
-- A player defers the local candidates; a useful remote task must continue automatically.
p=plan()
local first=assert(p.fallback,"no action after local tasks deferred")
assert(first.kind=="accept" and first.position.map==nextMap)
local id=first.questId
assert(not s.locked and not s.quests[id] and not s.completed[id])
local q=A.Data:GetQuest(id)
print(table.concat({"cross-zone",originMap,nextMap,remote,localCount,id,q.title},"\t"))
-- Losing the cross-map metric must remove the automatic remote options, then recover.
cross=false
local missing=plan()
assert(#missing.taskChoices==0 and not missing.fallback)
cross=true
p=plan();assert(p.fallback.questId==id)
s.position=first.position
p=plan();assert(p.fallback.kind=="accept")
local stillAvailable=false
for _,c in ipairs(p.taskChoices) do if c.questId==id then assert(c.status=="accept");stillAvailable=true end end
assert(stillAvailable and not s.quests[id] and not s.completed[id])
s.quests[id]={title=q.title,objectives={{text="未匹配目标采用区域参考点",numFulfilled=0,numRequired=1}}}
p=plan();assert(p.fallback.questId==id and p.fallback.kind=="objective")
assert(not s.quests[id].ready and not s.completed[id])
s.quests[id].ready=true
p=plan();assert(p.fallback.questId==id and p.fallback.kind=="turnin")
s.quests[id]=nil;s.completed[id]=true
p=plan()
for _,c in ipairs(p.taskChoices) do assert(c.questId~=id or q.repeatable) end
print(string.format("PASS %d remote candidates; full cross-zone accept/objective/turn-in replay; %.3fs CPU",remote,os.clock()-started))
