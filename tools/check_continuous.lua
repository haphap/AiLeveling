-- Diagnostic simulated history, NOT a 1-60 coverage test or an estimate of real leveling speed.
-- Usage (from QuestieDB emulator checkout): lua5.1 tools/check_continuous.lua ROOT PACKAGE FACTION CLASS RACE_ID RACE_FILE
-- Acceptance, objective completion and turn-in are simulated; unknown rewards, kill/exploration XP,
-- money, professions, reputation changes, flights and hearth are not simulated.
-- Item objectives acquire their known required count; turn-ins consume it, updating every active quest.
-- Loot rates, capacity, rewards, source tools and special retained-item rules are not simulated.
-- Repeat recommendations stop for inspection: repeatable eligibility alone is not a planner error.
-- Ground distances use the pinned native zone rectangles; character/game events are simulated.
-- Public transport uses the planner's current route cost; boarding/arrival events are not simulated.
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
C_Map={GetMapInfo=function(id) return maps[id] and {mapID=id,mapType=3} end};C_QuestLog={}
for _,file in ipairs({"State.lua","Hearth.lua","Data/Content.lua","Data/TaskFacts.lua","Data/ItemLimits.lua","Data/Experience.lua","Data/Flights.lua","Data/PublicTransit.lua","Data/Dungeons.lua","Data/Questie.lua",
    "Planner/Eligibility.lua","Planner/Chains.lua","Planner/TaskGuide.lua","Planner/TaskQueue.lua","Planner/Estimates.lua","Planner/Gear.lua",
    "Planner/Progression.lua","Planner/Travel.lua","Planner/Flights.lua","Planner/Supplies.lua","Planner/Dungeon.lua","Planner/DungeonTasks.lua","Planner/Planner.lua"}) do
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

local options={minutes=60,mode="fast",dungeons=false,role="DAMAGER"}
local function plan() return run(function() return A.Planner.Build(s,A.Data,options) end) end

io.stdout:setvbuf("line")
local anchors={[1]=7,[2]=788,[3]=179,[4]=456,[5]=363,[6]=747,[7]=179,[8]=788,[95]=92460,[96]=92460}
s.position=nil;s.position=assert(A.Data:Target(A.Data:GetQuest(anchors[raceId]),s))
local inventory=dofile(root.."/tools/continuous_inventory.lua")
assert(not next(s.quests) and not next(s.completed))

local completed,movement,unknown,knownXP,direct=0,0,0,0,0
local function stop(reason,id,kind)
    print("STOP",reason,s.level,completed,id or "",kind or "")
    print("SUMMARY",faction,s.level,s.xp,completed,knownXP,unknown,direct,movement)
end
for step=1,3000 do
    local p=plan();local a=p.fallback
    if p.complete then stop("complete");break end
    if not a or not a.questId then stop(a and a.kind or "empty");break end
    local q=assert(A.Data:GetQuest(a.questId));local id=q.id
    if s.completed[id] then
        assert(q.repeatable,"non-repeatable quest recommended after turn-in: "..id)
        print("REPEAT",id,q.title,A.TaskGuide.XP(q,s.level,s) or "UNKNOWN")
        stop("repeat-needs-evaluation",id,a.kind);break
    end
    if not a.position then stop("position",id,a.kind);break end
    local distance=A.Navigation:Distance(s.position,a.position)
    local route=p.referenceJourney and p.referenceJourney.firstRoute
    local seconds=route and route.seconds or distance and distance/7
    if not seconds then stop("world",id,a.kind);break end
    if not distance then print("CROSS_WORLD",id,s.position.map,a.position.map,seconds) end
    movement=movement+seconds;s.position=a.position
    if a.kind=="accept" then
        assert(A.Eligibility.Check(q,s,A.Data))
        local active,reason=inventory.Accept(q,s,A.Data)
        if not active then stop(reason,id,a.kind);break end
        if active.ready then direct=direct+1;print("DIRECT_HANDIN",id,q.title) end
    elseif a.kind=="objective" then
        inventory.Objective(id,a.objectiveIndex,s,a.itemGain)
    elseif a.kind=="turnin" then
        local xp=A.TaskGuide.XP(q,s.level,s)
        if not xp then unknown=unknown+1;print("OMITTED_XP",id,q.title,unknown) end
        inventory.TurnIn(id,s)
        completed=completed+1;knownXP=knownXP+(xp or 0)
        local forecast=A.Progression.Advance(s,xp or 0,A.Data.content)
        assert(not forecast.uncertain)
        s.level,s.xp,s.maxXP=forecast.level,forecast.xp,forecast.maxXP
        print("TURNIN",completed,id,q.title,xp or "UNKNOWN",s.level,s.xp,s.position.map)
    else stop("action",id,a.kind);break end
    if step==3000 then stop("step-limit",id,a.kind) end
end
