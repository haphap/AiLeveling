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
assert(loadfile(root.."/Planner/Selection.lua"))("AiLeveling",A)
local s=dofile(root.."/tests/fixtures.lua").State()
s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
s.faction,s.class,s.raceId=faction,class,raceId
s.classMask,s.raceMask=db.Enum.classKeys[class],db.Enum.raceMaskById[raceId]
s.spells,s.specializations,s.completionKnown={},{},true
s.items={}
local quests,sources=0,0
for _,id in ipairs(A.Data.ids) do
    local q=A.Data:GetQuest(id)
    local rewards=A.Gear.RewardSources(q)
    if next(rewards) then quests=quests+1 end
    for key,source in pairs(rewards) do
        sources=sources+1
        local actual=A.Gear.GetSource(key,A.Data)
        assert(actual.reference and not actual.verified and actual.questId==id and actual.itemId==source.itemId)
        local matched=false
        for _,row in ipairs(q.taskFacts.rewards[source.choice and "choices" or "items"] or {}) do
            if row.id==source.itemId then matched=true end
        end
        assert(matched and q.questLevel==q.taskFacts.level)
        -- Synthetic stats isolate source wiring; these are not claims about the real reward's attributes.
        s.items[source.itemId]={id=source.itemId,name="模拟奖励属性",equipLoc="INVTYPE_HEAD",usable=true,
            stats={ITEM_MOD_STRENGTH_SHORT=8,ITEM_MOD_AGILITY_SHORT=8,ITEM_MOD_INTELLECT_SHORT=8,
                ITEM_MOD_STAMINA_SHORT=8,ITEM_MOD_SPIRIT_SHORT=8}}
    end
end
assert(quests>1000 and sources>1000)
print(string.format("sources\t%d reward quests\t%d sources",quests,sources))
A.state,A.char=s,{turnIns={},skipped={}}
A.State.Refresh=function() s.gearTarget=A.char.gearTarget end
local options={minutes=60,mode="relaxed",gearPreference="balanced",dungeons=false,role="DAMAGER"}
local function plan() return run(function() return A.Planner.Build(s,A.Data,options) end) end
for _,level in ipairs({6,12,20}) do
    s.level,s.maxXP=level,A.Experience.xpToLevel[level]
    s.position={map=faction=="Alliance" and (level>=20 and 1436 or 1429) or (level>=20 and 1413 or 1411),x=0.5,y=0.5}
    local p=plan()
    local selected
    for _,choice in ipairs(p.taskChoices) do
        if not choice.requireCheck and not choice.acceptBlocked then
            selected=next(choice.gearSources or {})
            if selected then break end
        end
    end
    assert(selected,"no eligible reward source at level "..level)
    assert(A.Gear:SetTarget(selected))
    local source=A.Gear.GetSource(selected);local q=A.Data:GetQuest(source.questId)
    p=plan();assert(p.fallback.questId==q.id and p.fallback.kind=="accept")
    s.position=p.fallback.position;p=plan()
    assert(p.fallback.kind=="accept" and not s.quests[q.id] and not s.completed[q.id])
    s.quests[q.id]={title=q.title,objectives={{text="模拟日志目标",numFulfilled=0,numRequired=1}}}
    p=plan();assert(p.fallback.questId==q.id and p.fallback.kind=="objective")
    s.quests[q.id].ready=true;p=plan();assert(p.fallback.questId==q.id and p.fallback.kind=="turnin")
    assert(s.gearTarget==selected)
    s.bags[source.itemId]=1;A.Gear:SyncTarget(s);assert(not s.gearTarget and s.gearAcquired==source.itemId)
    s.bags[source.itemId]=nil;s.gearAcquired=nil;s.quests[q.id]=nil
    print(table.concat({"reward-route",level,q.id,q.title,source.itemId},"\t"))
end
print("PASS real reward identity scan and 3 level-band selection/accept/objective/turn-in/acquisition replays")
