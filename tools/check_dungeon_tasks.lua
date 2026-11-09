-- Run from the pinned QuestieDB source emulator directory.
local root,package,faction=assert(arg[1]),assert(arg[2]),assert(arg[3])
local client,metadata=dofile("emulator/client.lua"),dofile("emulator/metadata.lua")
client.install({expansion="Forever",faction=faction,classFile="WARRIOR",locale="zhCN"})
metadata.load(package.."/QuestieDB_Forever.toc","QuestieDB")
local db=metadata.loadAddon(package.."/QuestieDB_Forever.toc","QuestieDB",package)
local A={Navigation={Distance=function(_,a,b)
    if a and b and a.map==b.map then return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
end}}
-- Native map types are simulated; quest entities and coordinates come from the pinned database.
C_Map={GetMapInfo=function(id)
    local types={[1436]=3,[1453]=3,[1454]=3,[1456]=3,[291]=4,[213]=4}
    return {mapID=id,mapType=types[id]}
end};C_QuestLog={}
for _,file in ipairs({"State.lua","Data/Content.lua","Data/Dungeons.lua","Data/Questie.lua",
    "Planner/Chains.lua","Planner/Eligibility.lua","Planner/Dungeon.lua","Planner/DungeonTasks.lua",
    "Planner/Travel.lua","Planner/Gear.lua","Planner/Progression.lua","Planner/Supplies.lua",
    "Planner/TaskGuide.lua","Planner/TaskQueue.lua","Planner/Planner.lua","Planner/Selection.lua"}) do
    assert(loadfile(root.."/"..file))("AiLeveling",A)
end
assert(A.Data:Connect(db))
local s={revision=1,level=20,runSpeed=7,freeSlots=16,durability=1,groupSize=1,role="DAMAGER",
    equipment={},bags={},samples={},xp=0,maxXP=100000,questLimit=20,quests={},completed={},skipped={},completionKnown=true,
    clientVersion="1.60.1",clientBuild="70862",faction=faction,
    raceMask=db.Enum.raceMaskById[faction=="Alliance" and 1 or 2],classMask=db.Enum.classKeys.WARRIOR,
    skills={},reputations={},spells={},specializations={},position={map=1429,x=0.5,y=0.5}}
local catalog=A.Dungeon.Catalog(s,A.Content)
local count=0;for _ in pairs(catalog) do count=count+1 end;assert(count==34)
local d=catalog[faction=="Alliance" and "reference:36" or "reference:389"]
local activeId,readyId=faction=="Alliance" and 166 or 5723,faction=="Alliance" and 167 or 5722
local function byId()
    local result={}
    for _,row in ipairs(A.Dungeon.Tasks(d,s,A.Data)) do result[row.id]=row end
    return result
end
local initial=byId()
assert(initial[activeId] and initial[readyId])
local prepareId=faction=="Alliance" and 166 or 5728
local preparation=assert(initial[prepareId].preparation,"real prerequisite preparation missing")
local simulated={};for key,value in pairs(s) do simulated[key]=value end
simulated.completed={};simulated.quests={}
local steps={}
while not A.Eligibility.Check(A.Data:GetQuest(prepareId),simulated,A.Data) do
    local nextIds=A.Chains.Preparation(prepareId,A.Data,simulated)
    assert(#nextIds>0 and #steps<32,"preparation stopped before the selected quest")
    local id=nextIds[1];assert(A.Eligibility.Check(A.Data:GetQuest(id),simulated,A.Data))
    assert(not simulated.completed[id]);steps[#steps+1]=id
    simulated.completed[id]=true
end
assert(#steps>0 and not next(s.completed) and not next(s.quests))
print(faction..": prerequisite turn-in replay "..table.concat(steps," > ").." > "..prepareId)
A.state,A.char,A.ready=s,{turnIns={},skipped={}},true
A.State.Refresh=function() A.Selection:Snapshot(s);A.Dungeon:TaskBatchSnapshot(s) end
assert(A.Dungeon:StartTaskBatch(d.id))
assert(A.char.taskBatch.baselines[prepareId]==0 and not A.char.dungeon)
local co=coroutine.create(function()
    return A.Planner.Build(s,A.Data,{minutes=60,mode="fast",dungeons=true,role="DAMAGER"})
end)
local batchPlan
repeat
    local ok,result=coroutine.resume(co);assert(ok,result)
    if coroutine.status(co)=="dead" then batchPlan=result end
until batchPlan
assert(batchPlan.taskBatch and batchPlan.taskBatch.remaining>1 and #batchPlan.taskChoices>1)
assert(batchPlan.fallback and batchPlan.fallback.questId and not batchPlan.best)
local seen={}
for _,choice in ipairs(batchPlan.taskChoices) do
    assert(not seen[choice.questId]);seen[choice.questId]=true
    assert(A.Eligibility.Check(A.Data:GetQuest(choice.questId),s,A.Data))
end
print(faction..": batch roots="..batchPlan.taskBatch.remaining..", executable frontier="..#batchPlan.taskChoices..
    ", first="..batchPlan.fallback.questId.." ("..batchPlan.fallback.kind..")")
A.char.taskBatch=nil;s.taskBatch=nil
if faction=="Alliance" then
    assert(initial[166].group==4 and initial[166].reason=="备选前置未交付")
    assert(initial[214].relation=="alternative")
    assert(initial[166].relation=="inside")
end
s.quests[activeId]={objectives={{text="actual quest objective"}}}
s.quests[readyId]={ready=true,objectives={}}
local rows=byId()
assert(rows[activeId].status=="已接取" and rows[readyId].status=="可交付")
assert(rows[readyId].position and rows[readyId].recipient)
local target=assert(rows[activeId].position)
local action={kind="objective",questId=activeId,title=rows[activeId].title,position=target}
s.position={map=faction=="Alliance" and 1436 or 1454,x=0.5,y=0.5}
local gate=A.Dungeon.TaskApproach(action,s,A.Data)
assert(gate.kind=="dungeonEnter" and gate.questId==activeId)
assert(gate.position.map==s.position.map)
assert(gate.position.x==(faction=="Alliance" and 42.5 or 52.6)/100)
assert(gate.position.y==(faction=="Alliance" and 71.7 or 49)/100)
s.inInstance,s.instanceId=true,d.instanceId
assert(A.Dungeon.TaskApproach(action,s,A.Data)==action)
s.inInstance=false
assert(A.Dungeon.TaskApproach(action,s,A.Data).kind=="dungeonEnter")
if faction=="Alliance" then
    s.quests[214]={objectives={{text="Red Silk Bandana"}}}
    local outdoor={kind="objective",questId=214,position=assert(A.Data:Target(A.Data:GetQuest(214),s))}
    assert(outdoor.position.map==1436 and A.Dungeon.TaskApproach(outdoor,s,A.Data)==outdoor)
end
assert(not s.completed[activeId] and not s.quests[activeId].ready)
s.quests[activeId].ready=true;s.inInstance,s.instanceId=true,d.instanceId
local finish=assert(A.Data:Target(A.Data:GetQuest(activeId),s))
assert(finish.map==(faction=="Alliance" and 1436 or 1456))
assert(finish.entityId==(faction=="Alliance" and 234 or 11833))
local delivery={kind="turnin",questId=activeId,title=action.title,position=finish}
local leave=A.Dungeon.TaskApproach(delivery,s,A.Data)
assert(leave.kind=="dungeonLeave" and leave.position==nil and leave.questId==activeId)
assert(leave.text:find(finish.entityName,1,true))
if faction=="Horde" then
    local insideDelivery={kind="turnin",questId=5722,position=rows[5722].position}
    assert(insideDelivery.position.entityId==11834)
    assert(A.Dungeon.TaskApproach(insideDelivery,s,A.Data)==insideDelivery)
end
s.inInstance=false;s.position=gate.position
assert(A.Dungeon.TaskApproach(delivery,s,A.Data)==delivery)
assert(not s.completed[activeId] and s.quests[activeId].ready)
s.quests[readyId]=nil;s.completed[readyId]=true
assert(byId()[readyId].status=="已交付")
assert(next(A.Content.dungeons)==nil,"reference list must not masquerade as executable content")
s.clientBuild="next";assert(next(A.Dungeon.Catalog(s,A.Content))==nil)
print(faction..": 34 catalogue entries; quest eligibility, entrance, exit-to-recipient, indoor delivery, outdoor alternatives and build isolation passed (native instance/map states simulated)")
