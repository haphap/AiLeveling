-- Independent level-entry snapshots, not a simulated 1-60 playthrough.
-- Ground distances use the pinned native zone rectangles; character/game events are simulated.
local root,package,faction,class,raceId,raceFile=assert(arg[1]),assert(arg[2]),assert(arg[3]),assert(arg[4]),assert(tonumber(arg[5])),assert(arg[6])
local client,metadata=dofile("emulator/client.lua"),dofile("emulator/metadata.lua")
client.install({expansion="Forever",faction=faction,classFile=class,raceId=raceId,raceFile=raceFile,locale="zhCN"})
metadata.load(package.."/QuestieDB_Forever.toc","QuestieDB")
local db=metadata.loadAddon(package.."/QuestieDB_Forever.toc","QuestieDB",package)
local maps={}
local file=assert(io.open(root.."/.dependencies/UiMapAssignment-1.60.1.70862.csv"))
local keys={};for key in file:read():gmatch("[^,]+") do keys[#keys+1]=key end
for line in file:lines() do
    local row,i={},0
    for value in line:gmatch("[^,]+") do i=i+1;row[keys[i]]=assert(tonumber(value)) end
    -- World overview has multiple partial assignments; only full zone rectangles are used here.
    if row.UiMin_0==0 and row.UiMin_1==0 and row.UiMax_0==1 and row.UiMax_1==1 then
        assert(not maps[row.UiMapID]);maps[row.UiMapID]=row
    end
end
file:close()
local function world(p)
    local m=p and maps[p.map]
    if m then return m.MapID,m.Region_3-p.y*(m.Region_3-m.Region_0),m.Region_4-p.x*(m.Region_4-m.Region_1) end
end
local A={Navigation={Distance=function(_,a,b)
    local ai,ax,ay=world(a);local bi,bx,by=world(b)
    if ai and ai==bi then return math.sqrt((ax-bx)^2+(ay-by)^2) end
end}}
C_Map={GetMapInfo=function(id) return maps[id] and {mapID=id} end};C_QuestLog={}
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
local s=dofile(root.."/tests/fixtures.lua").State()
s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
s.level,s.maxXP,s.faction,s.class,s.raceId=1,A.Experience.xpToLevel[1],faction,class,raceId
s.classMask,s.raceMask=db.Enum.classKeys[class],db.Enum.raceMaskById[raceId]
s.spells,s.specializations,s.completionKnown={},{},true

local options={minutes=60,gearPreference="xp",dungeons=false,role="DAMAGER"}
local function plan() return run(function() return A.Planner.Build(s,A.Data,options) end) end
for level=1,60 do
    s.level,s.maxXP=level,A.Experience.xpToLevel[level]
    local origins=faction=="Alliance" and {1429,1436,1433,1434,1446,1452} or {1411,1413,1424,1434,1446,1452}
    local map=origins[math.floor((level-1)/10)+1]
    if level<=10 then
        local anchors={[1]=7,[2]=788,[3]=179,[4]=456,[5]=363,[6]=747,[7]=179,[8]=788,[95]=92460,[96]=92460}
        s.position=nil;s.position=assert(A.Data:Target(A.Data:GetQuest(anchors[raceId]),s))
    else s.position={map=map,x=.5,y=.5} end
    local p=plan();local a=p.fallback or {};local chosen
    if level==60 then
        assert(p.complete and not p.fallback);print("60\tcomplete")
    else
    assert(a.kind=="accept", "no automatic accept at level "..level)
    for _,c in ipairs(p.taskChoices) do
        assert(A.Eligibility.Check(A.Data:GetQuest(c.questId),s,A.Data))
        if c.questId==a.questId then chosen=c end
    end
    assert(chosen and not chosen.requireCheck and not chosen.lowValue)
    local previousRate
    for _,c in ipairs(p.taskChoices) do
        if c.status=="accept" and not c.lowValue and not c.entryBlocked and not c.acceptBlocked and c.timing.seconds and c.remainingXP~=nil then
            local rate=A.TaskGuide.MovementRate(c.timing.seconds,c.remainingXP)
            assert(not previousRate or rate<=previousRate,"known reward ordering lost at level "..level)
            previousRate=rate
        end
    end
    print(table.concat({"ENTRY",level,s.position.map,a.kind or "NONE",a.questId or 0,chosen and chosen.level or 0,#p.taskChoices,
        chosen and chosen.timing and chosen.timing.seconds or -1,chosen and chosen.remainingXP or -1},"\t"))
    if level%10==0 or level==59 then
        local id=a.questId
        local q=A.Data:GetQuest(id)
        local objectives=A.Data:ReferenceObjectiveTargets(q,s)
        if #objectives==0 then objectives={{text="按实际日志核对目标",numRequired=1,numFulfilled=0}} end
        s.quests[id]={title=q.title,objectives=objectives}
        local active=plan();assert(active.fallback and active.fallback.questId==id,"accepted task lost at level "..level)
        assert(not s.completed[id] and not s.quests[id].ready)
        if active.fallback.position then s.position=active.fallback.position end
        plan();assert(not s.completed[id] and not s.quests[id].ready)
        s.quests[id].ready=true
        local ready=plan();assert(ready.fallback.questId==id and ready.fallback.kind=="turnin")
        assert(ready.fallback.position,"turn-in destination missing at level "..level)
        s.position=ready.fallback.position;s.quests[id]=nil;s.completed[id]=true
        local after=plan()
        assert(after.fallback and after.fallback.kind=="accept","no following task at level "..level)
        assert(after.fallback.questId~=id or q.repeatable)
        print(table.concat({"FLOW",level,id,active.fallback.kind,after.fallback.questId},"\t"))
        s.completed={}
    end
    end
end
