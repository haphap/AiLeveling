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
for _,file in ipairs({"State.lua","Hearth.lua","Data/TaskFacts.lua","Data/Experience.lua","Data/Flights.lua","Data/Questie.lua",
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
local count,located,unmapped=0,0,0
local qualifying,hints={},{}
for _,id in ipairs(A.Data.ids) do
    local q=A.Data:GetQuest(id)
    if A.Data:DeliveryOnly(q,s) then
        count=count+1;qualifying[id]=true
        if next(db.Quest.Get(id,"extraObjectives") or {}) then
            assert(id==5931 or id==5932,"review new delivery hint "..id)
            hints[id]=true
        end
        local stages=A.TaskGuide.Stages(q,s,A.Data,{kind="accept",position=A.Data:Target(q,s)})
        assert(#stages==2 and stages[1].kind=="accept" and stages[2].kind=="turnin","invented objective "..id)
        local finish=stages[2].position
        s.quests[id]={objectives={}}
        local target=A.Data:Target(q,s)
        if target then
            assert(finish and same(target,finish),"different recipient target "..id)
            located=located+1
        elseif A.Data:UnmappedTargetArea(q,s) then unmapped=unmapped+1 end
        local activeStages=A.TaskGuide.Stages(q,s,A.Data,{kind="objective",position=target})
        assert(activeStages[1].kind=="objective" and activeStages[1].text:find("对话",1,true),"lost dialog instruction "..id)
        assert(not s.quests[id].ready and not s.completed[id],"changed native completion "..id)
        s.quests[id].objectives={{text="native requirement",finished=false}}
        assert(not A.Data:DeliveryOnly(q,s),"ignored native requirement "..id)
        s.quests[id]=nil
    end
end
for _,id in ipairs({1489,96627,97281,5931,5932}) do assert(qualifying[id],"missing known delivery "..id) end
assert(hints[5931] and hints[5932],"missing travel hint cases")
for _,id in ipairs({117,91740,96652}) do assert(not qualifying[id],"lost item requirement "..id) end
assert(count>0 and located>0)
print("PASS",faction,class,count,located,unmapped,"delivery previews; actual recipients; native completion retained")
