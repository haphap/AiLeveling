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
local s=dofile(root.."/tests/fixtures.lua").State()
s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
s.level,s.maxXP,s.faction,s.class,s.raceId=1,A.Experience.xpToLevel[1],faction,class,raceId
s.classMask,s.raceMask=db.Enum.classKeys[class],db.Enum.raceMaskById[raceId]
s.spells,s.specializations,s.completionKnown={},{},true
local anchors={[1]=7,[2]=788,[3]=179,[4]=456,[5]=363,[6]=747,[7]=179,[8]=788,[95]=92460,[96]=92460}
local anchor=assert(A.Data:GetQuest(anchors[raceId]))
s.position=nil;s.position=assert(A.Data:Target(anchor,s),"starting anchor has no position")
local startMap=s.position.map
local options={minutes=60,gearPreference="xp",dungeons=false,role="DAMAGER"}
local function plan() return run(function() return A.Planner.Build(s,A.Data,options) end) end
local function emit(stage,action)
    local p=action.position or {}
    print(table.concat({stage,action.questId or 0,action.kind or "",p.map or 0,p.x or 0,p.y or 0,p.approximate and "area" or "precise"},"\t"))
end
local initial=plan()
assert(initial.fallback and initial.fallback.kind=="accept","no automatic starting quest")
assert(initial.fallback.position and initial.fallback.position.map==startMap,"starting navigation left its area")
for _,choice in ipairs(initial.taskChoices) do
    assert(A.Eligibility.Check(A.Data:GetQuest(choice.questId),s,A.Data))
    assert(choice.status=="accept" and choice.actions[1].position.map==startMap)
end
emit("automatic",initial.fallback)
-- Replay every initial candidate in isolation; accepted state comes from the simulated quest log.
for _,choice in ipairs(initial.taskChoices) do
    local id=choice.questId
    if not choice.requireCheck then
        s.locked=id
        local accepted=plan();assert(accepted.fallback.kind=="accept" and accepted.fallback.questId==id)
        s.quests[id]={title=choice.title,objectives={{text="目标未匹配时采用区域参考",numFulfilled=0,numRequired=1}}}
        local active=plan();assert(active.fallback.questId==id and active.fallback.kind=="objective")
        assert(active.fallback.position,"active task has no destination: "..id)
        assert(not s.quests[id].ready and not s.completed[id])
        emit("objective",active.fallback)
        s.quests[id].ready=true
        local ready=plan();assert(ready.fallback.questId==id and ready.fallback.kind=="turnin")
        assert(ready.fallback.position,"ready task has no recipient: "..id)
        emit("turnin",ready.fallback)
        s.quests[id]=nil;s.completed[id]=true;s.locked=nil
        local after=plan()
        for _,c in ipairs(after.taskChoices) do assert(c.questId~=id or A.Data:GetQuest(id).repeatable) end
        s.completed[id]=nil
    end
end
-- The real Skyborne opening unlocks both follow-ups only after turning in #92460.
if raceId==95 or raceId==96 then
    for _,id in ipairs({92461,92462}) do assert(not A.Eligibility.Check(A.Data:GetQuest(id),s,A.Data)) end
    s.quests[92460]={ready=true,objectives={}}
    assert(not A.Eligibility.Check(A.Data:GetQuest(92461),s,A.Data))
    s.quests[92460]=nil;s.completed[92460]=true
    local after=plan();local found={}
    for _,choice in ipairs(after.taskChoices) do found[choice.questId]=true end
    for _,id in ipairs({92461,92462}) do assert(found[id],"Skyborne opening follow-up missing: "..id) end
    emit("opening-followup",after.fallback)
    s.level=4
    local alliance,horde=A.Data:GetQuest(92597),A.Data:GetQuest(92598)
    s.completed[92461]=true
    assert(A.Eligibility.Check(faction=="Alliance" and alliance or horde,s,A.Data))
    assert(not A.Eligibility.Check(faction=="Alliance" and horde or alliance,s,A.Data))
end
print("PASS\t"..#initial.taskChoices)
