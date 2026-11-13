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
for _,file in ipairs({"State.lua","Hearth.lua","Data/TaskFacts.lua","Data/ItemLimits.lua","Data/Experience.lua","Data/Flights.lua","Data/Questie.lua",
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

local inventory=dofile(root.."/tools/continuous_inventory.lua")
local s=dofile(root.."/tests/fixtures.lua").State()
s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
s.level=20;s.faction=faction;s.bags={};s.quests={};s.completed={}
assert(inventory.Accept(A.Data:GetQuest(3100),s,A.Data).ready)
assert(s.bags[9542]==1)
inventory.TurnIn(3100,s);assert(s.bags[9542]==0 and s.completed[3100])
assert(inventory.Accept(A.Data:GetQuest(117),s,A.Data).ready==false)
inventory.Objective(117,1,s);assert(s.quests[117].ready and s.bags[1274]==5)
inventory.TurnIn(117,s);assert(s.bags[1274]==0)
s.bags[2592]=60
for _,id in ipairs({7791,7792}) do assert(inventory.Accept(A.Data:GetQuest(id),s,A.Data).ready) end
-- Check the runtime forecast before applying either simulated hand-in.
A.Navigation.Distance=function(_,a,b) if a and b then return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)*1000 end end
s.position={map=1453,x=0.5,y=0.5}
local order={}
for _,id in ipairs({7791,7792}) do
 local q=A.Data:GetQuest(id);local first={kind="turnin",questId=id,position=A.Data:Target(q,s)}
 local stages,complete=A.TaskGuide.Stages(q,s,A.Data,first)
 order[#order+1]={questId=id,stages=stages,stagesComplete=complete,remainingXP=A.TaskGuide.XP(q,s.level,s)}
end
local forecast=A.TaskQueue.Evaluate(order,s,A.Navigation,A.Data)
assert(forecast and #forecast.steps==2 and forecast.bags[2592]==0)
assert(#forecast.steps[1].choice.stages==1 and #forecast.steps[2].choice.stages==2)
assert(forecast.steps[2].choice.stages[1].itemGain==60)
local _,queue=A.TaskQueue.Solve(order,s,A.Navigation,A.Data)
assert(queue and queue.bags[2592]==0)
local gained=0
for _,step in ipairs(queue.steps) do
 for _,stage in ipairs(step.stage and {step.stage} or step.choice.stages) do gained=gained+(stage.itemGain or 0) end
end
assert(gained==60 and s.bags[2592]==60 and s.quests[7791].ready and s.quests[7792].ready)
print("PASS","two wool donations reserve 120, collect missing 60, consume once per quest",7791,7792,2592)
inventory.Objective(7792,1,s,60);assert(s.bags[2592]==120)
local full=A.TaskQueue.Evaluate(order,s,A.Navigation,A.Data)
assert(full and #full.steps[2].choice.stages==1 and full.bags[2592]==0)
s.bags[2592]=60;inventory.Refresh(s)
inventory.TurnIn(7791,s)
assert(s.bags[2592]==0 and not s.quests[7792].ready and not s.quests[7792].objectives[1].finished)
assert(not pcall(inventory.TurnIn,7792,s) and not s.completed[7792])
inventory.Objective(7792,1,s);assert(s.bags[2592]==60 and s.quests[7792].ready)
inventory.TurnIn(7792,s);assert(s.bags[2592]==0 and s.completed[7792])
local fake={ReferenceObjectiveTargets=function() return {{targetKind="item",targetId=123,providedOnAccept=true}}, {},false end}
local before={bags={keep=1},quests={},completed={}}
local result,reason=inventory.Accept({id=1},before,fake)
assert(not result and reason=="unknown-item-count" and not before.bags[123] and not next(before.quests))
fake.ReferenceObjectiveTargets=function() return {{targetKind="item",targetId=123,numRequired=1,providedOnAccept=true}}, {},true end
result,reason=inventory.Accept({id=1},before,fake)
assert(not result and reason=="unsupported-objectives" and not before.bags[123])
print("PASS","grant, gather, consume, shared requirements, shortage refusal, unknown counts, complex requirements")
