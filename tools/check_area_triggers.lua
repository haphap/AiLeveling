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

local s={clientVersion="1.60.1",clientBuild="70862",interface=16001,level=10,
    faction=faction,quests={},completed={},bags={}}
local function same(a,b)
    if type(a)~="table" or type(b)~="table" then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local count,located,approximate=0,0,0
for _,id in ipairs(A.Data.ids) do
    local q=A.Data:GetQuest(id)
    local facts=A.Data:CacheQuest(q,s)
    for _,fact in ipairs(facts and facts.objectives or {}) do
        if fact.kind=="areaTrigger" or fact.kind=="areaTriggerEnter" then
            count=count+1
            local descriptions,positions,complex=A.Data:ReferenceObjectiveTargets(q,s)
            local matches,index=0,nil
            for i,o in ipairs(descriptions) do
                if o.areaTriggerId==fact.id then
                    matches=matches+1;index=i
                    assert(o.type=="event" and not o.targetId and not o.targetKind and not o.finished)
                    assert(o.numRequired==(fact.count>0 and fact.count or nil))
                end
            end
            assert(matches==1,"missing or duplicated exploration "..id)
            assert(not A.Data:DeliveryOnly(q,s),"exploration treated as delivery "..id)
            local point=positions[index]
            if point then located=located+1;if point.approximate then approximate=approximate+1 end end
            local stages=A.TaskGuide.Stages(q,s,A.Data,{kind="accept",position=A.Data:Target(q,s)})
            local found=0
            for _,stage in ipairs(stages) do if stage.areaTriggerId==fact.id then found=found+1 end end
            assert(found==1,"missing exploration step "..id)
            s.quests[id]={objectives=descriptions}
            local identities=A.Data:ObjectiveIdentities(q,s)
            assert(not identities[index],"exploration received an entity identity "..id)
            A.Data:ObjectiveTargets(q,s)
            assert(not descriptions[index].finished and not s.quests[id].ready and not s.completed[id])
            s.quests[id]=nil
        end
    end
end
assert(count>0)
local inventory=dofile(root.."/tools/continuous_inventory.lua")
for _,case in ipairs({{870,216},{62,44590},{944,223}}) do
    local id,trigger=case[1],case[2]
    local q=A.Data:GetQuest(id)
    local active=assert(inventory.Accept(q,s,A.Data))
    assert(#active.objectives==1 and active.objectives[1].areaTriggerId==trigger and not active.ready)
    assert(not pcall(inventory.TurnIn,id,s))
    inventory.Objective(id,1,s)
    assert(active.ready);inventory.TurnIn(id,s);assert(s.completed[id])
end
print("PASS",faction,class,count,located,approximate,"exploration objectives; explicit simulated completion")
