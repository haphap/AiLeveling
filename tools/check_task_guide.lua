-- Real QuestieDB release + generated reference facts; offline character/map stubs only.
local root,package,faction=assert(arg[1]),assert(arg[2]),assert(arg[3])
local client,metadata=dofile("emulator/client.lua"),dofile("emulator/metadata.lua")
client.install({expansion="Forever",faction=faction,classFile="WARRIOR",locale="zhCN"})
metadata.load(package.."/QuestieDB_Forever.toc","QuestieDB")
local db=metadata.loadAddon(package.."/QuestieDB_Forever.toc","QuestieDB",package)
local A={Navigation={Distance=function(_,a,b)
    if a and b and a.map==b.map then return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)*1000 end
end}}
C_Map={GetMapInfo=function(id) return {mapID=id} end};C_QuestLog={}
for _,file in ipairs({"State.lua","Hearth.lua","Data/Content.lua","Data/TaskFacts.lua","Data/Experience.lua","Data/Flights.lua","Data/Questie.lua","Planner/Eligibility.lua",
    "Planner/Chains.lua","Planner/TaskGuide.lua","Planner/TaskQueue.lua","Planner/Estimates.lua","Planner/Gear.lua","Planner/Progression.lua","Planner/Travel.lua","Planner/Flights.lua",
    "Planner/Supplies.lua","Planner/Dungeon.lua","Planner/Planner.lua"}) do
    assert(loadfile(root.."/"..file))("AiLeveling",A)
end
local function run(fn,label)
    local co=coroutine.create(fn)
    local started,maxResume,resumes=os.clock(),0,0
    while true do
        local tick=os.clock();local ok,value=coroutine.resume(co);assert(ok,value)
        maxResume=math.max(maxResume,os.clock()-tick);resumes=resumes+1
        if coroutine.status(co)=="dead" then
            if label then print(string.format("%s: %.1f ms CPU; %d resumes; longest %.1f ms",label,(os.clock()-started)*1000,resumes,maxResume*1000)) end
            return value
        end
    end
end
assert(A.Data:Connect(db));run(function() A.Data:BuildIndex() end,"task + service index")
local s=dofile(root.."/tests/fixtures.lua").State()
s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
s.maxXP=A.Experience.xpToLevel[1]
s.level=1;s.faction=faction;s.classMask=db.Enum.classKeys.WARRIOR;s.raceMask=db.Enum.raceMaskById[faction=="Alliance" and 1 or 2]
s.position={map=faction=="Alliance" and 1429 or 1411,x=0.5,y=0.5};s.completionKnown=true
local options={minutes=60,mode="fast",dungeons=false,role="DAMAGER"}
local plan=run(function() return A.Planner.Build(s,A.Data,options) end)
assert(plan.fallback and #plan.taskChoices>0)
for _,c in ipairs(plan.taskChoices) do
    assert(c.stages[1].kind=="accept" and c.stages[#c.stages].kind=="turnin")
    if c.questId==plan.fallback.questId then assert(not c.requireCheck) end
end
print(faction..": "..#plan.taskChoices.." reference task chains; automatic #"..plan.fallback.questId)
s.questCount=s.questLimit
local full=run(function() return A.Planner.Build(s,A.Data,options) end)
assert(full.fallback.kind=="selectionBlocked" and full.fallback.text:find("任务日志已满",1,true))
assert(#full.taskChoices==#plan.taskChoices)
for _,choice in ipairs(full.taskChoices) do assert(choice.acceptBlocked) end
s.locked=plan.fallback.questId
local locked=run(function() return A.Planner.Build(s,A.Data,options) end)
assert(locked.fallback.kind=="selectionBlocked" and s.locked==plan.fallback.questId)
s.questCount=s.questLimit-1
local available=run(function() return A.Planner.Build(s,A.Data,options) end)
assert(available.fallback.kind=="accept" and available.fallback.questId==s.locked)
s.locked=nil;s.questCount=nil
print(faction..": full native quest count blocks automatic/manual acceptance; releasing one slot resumes the selected task")
local id=faction=="Alliance" and 7 or 788
local objective=db.Quest.Get(id,"objectives")[1][1]
s.quests[id]={title=A.Data:GetQuest(id).title,objectives={{text=db.Npc.Get(objective[1],"name").." 0/10",numFulfilled=0,numRequired=10}}}
plan=run(function() return A.Planner.Build(s,A.Data,options) end)
local chosen
for _,c in ipairs(plan.taskChoices) do if c.questId==id then chosen=c end end
assert(chosen and chosen.stages[1].kind=="objective" and chosen.stages[#chosen.stages].kind=="turnin")
assert(chosen.work==nil)
assert(chosen.timing and chosen.timing.seconds and chosen.timing.coarse and chosen.timing.travel>0)
print(string.format("straight-line travel #%d: %.1f seconds, movement %.1f seconds",id,chosen.timing.travel,chosen.timing.seconds))
assert(chosen.stages[#chosen.stages].position and chosen.remainingXP and chosen.remainingXP>0)
local recipient=chosen.stages[#chosen.stages].position
assert(recipient.entityKind=="npc" and recipient.entityId and recipient.entityName)
local actual=false
for _,npc in ipairs((db.Quest.Get(id,"finishedBy") or {})[1] or {}) do if npc==recipient.entityId then actual=true end end
assert(actual,"recipient identity must come from finishedBy")
print(string.format("delivery recipient #%d: NPC #%d %s",id,recipient.entityId,recipient.entityName))
print(string.format("accepted #%d: %d remaining steps, %.0f reference XP, turn-in located",id,#chosen.stages,chosen.remainingXP))
s.quests[id].ready=true
plan=run(function() return A.Planner.Build(s,A.Data,options) end)
for _,c in ipairs(plan.taskChoices) do if c.questId==id then assert(#c.stages==1 and c.stages[1].kind=="turnin") end end
print("native ready fact reduces remaining chain to turn-in only")
s.xp=399
local prediction=run(function() return A.Planner.Build(s,A.Data,options) end)
for _,choice in ipairs(prediction.taskChoices) do
    if choice.questId==id then
        assert(choice.forecast and not choice.forecast.uncertain and choice.forecast.level==2 and choice.forecast.xp==169)
        assert(choice.forecast.curveSource==A.Experience.source and s.level==1 and s.xp==399 and not s.completed[id])
        print(string.format("reference #%d: turn-in 170 XP -> level 2, 169/900; actual level and completion unchanged",id))
    end
end
print(string.format("reference service NPCs: %d; active flags vendor=%d repair=%d",A.Data.serviceCount,db.Enum.npcFlags.VENDOR,db.Enum.npcFlags.REPAIR))
print(string.format("reference trainer/inn NPCs: %d; active flags trainer=%d innkeeper=%d",A.Data.amenityCount,db.Enum.npcFlags.TRAINER,db.Enum.npcFlags.INNKEEPER))
for _,kind in ipairs({"bind","train"}) do
    local points=A.Data:AmenityPoints(s,kind);assert(#points>0)
    for _,point in ipairs(points) do
        local friendly=db.Npc.Get(point.npcId,"friendlyToFaction")
        assert(friendly=="AH" or friendly==(faction=="Alliance" and "A" or "H"))
        assert(point.position.map==s.position.map)
    end
    print(string.format("%s: %s -> #%d %s, %d local reference points",faction,kind,points[1].npcId,points[1].title,#points))
end
do
    local destination=faction=="Alliance" and 1436 or 1413
    local previous=C_Map.GetMapInfo
    C_Map.GetMapInfo=function(id)
        local info=previous(id)
        if id==s.position.map or id==destination then info.mapType=3 end
        return info
    end
    for _,kind in ipairs({"bind","train"}) do
        local points=A.Data:AmenityPoints(s,kind,{[s.position.map]=true,[destination]=true})
        local seen,remote={},0
        for _,point in ipairs(points) do
            local p=point.position
            assert(p.map==s.position.map or p.map==destination)
            local friendly=db.Npc.Get(point.npcId,"friendlyToFaction")
            assert(friendly=="AH" or friendly==(faction=="Alliance" and "A" or "H"))
            local key=string.format("%d:%d:%.9f:%.9f",point.npcId,p.map,p.x,p.y)
            assert(not seen[key]);seen[key]=true
            if p.map==destination then remote=remote+1 end
        end
        assert(remote>0)
        print(string.format("%s: cross-zone %s -> map %d, %d remote reference points",faction,kind,destination,remote))
    end
    C_Map.GetMapInfo=previous
end
for _,kind in ipairs({"vendor","repair"}) do
    s.freeSlots=kind=="vendor" and 0 or 10;s.durability=kind=="repair" and 0.1 or 1
    plan=run(function() return A.Planner.Build(s,A.Data,options) end)
    assert(plan.maintenance and plan.fallback and plan.fallback.kind=="service" and plan.fallback.serviceKind==kind)
    local action=plan.fallback
    local friendly=db.Npc.Get(action.npcId,"friendlyToFaction")
    assert(friendly=="AH" or friendly==(faction=="Alliance" and "A" or "H"))
    assert(not plan.best and not action.seconds and not action.moneyCost)
    print(string.format("%s: %s -> #%d %s, map %d %.1f %.1f, native resource completion required",faction,kind,
        action.npcId,action.title,action.position.map,action.position.x*100,action.position.y*100))
end
s.freeSlots=10;s.durability=1
plan=run(function() return A.Planner.Build(s,A.Data,options) end)
assert(not plan.maintenance and plan.fallback.questId==id)
print("resolved maintenance returns to the native ready task")

local lowCount,chainCount=0,0
for _,id in ipairs(A.Data.ids) do
    local q=A.Data:GetQuest(id)
    if q and q.questLevel and q.questLevel>0 and q.questLevel<50 then
        local probe={level=q.questLevel+10,quests={[id]={}},items={},equipment={},class="WARRIOR"}
        local low=A.TaskGuide.LowValue(q,probe,A.Data)
        local index=A.Data.chainIndex
        local related=#(index.incoming[id] or {})+#(index.outgoing[id] or {})>0
        if related then assert(not low);chainCount=chainCount+1 end
        if low then
            assert(low.xp<=low.baseXP*0.25 and not related)
            probe.quests[id].ready=true;assert(not A.TaskGuide.LowValue(q,probe,A.Data))
            lowCount=lowCount+1
        end
    end
end
assert(lowCount>0 and chainCount>0)
print(string.format("real-data low-value checks: %d isolated low-XP quests without item-cache dependency; %d chain quests protected",lowCount,chainCount))

do
    local pickupState=dofile(root.."/tests/fixtures.lua").State()
    pickupState.clientVersion,pickupState.clientBuild,pickupState.interface="1.60.1","70862",16001
    pickupState.level,pickupState.maxXP,pickupState.faction=3,A.Experience.xpToLevel[3],faction
    pickupState.classMask,pickupState.raceMask=s.classMask,s.raceMask
    pickupState.completionKnown=true
    local extraId=faction=="Alliance" and 33 or 790
    pickupState.completed[faction=="Alliance" and 783 or 4641]=true
    pickupState.quests[id]={title=A.Data:GetQuest(id).title,
        objectives={{text=db.Npc.Get(objective[1],"name").." 0/10",numFulfilled=0,numRequired=10}}}
    pickupState.currentTask=id
    -- Full-zone rectangle widths/heights from fixed 1.60.1.70862 UiMapAssignment.csv.
    local size=faction=="Alliance" and {3470.8332519532,2314.5830078125} or {5287.4996337891,3524.9998779297}
    local distance=A.Navigation.Distance
    A.Navigation.Distance=function(_,a,b)
        if a and b and a.map==b.map then return math.sqrt(((a.x-b.x)*size[1])^2+((a.y-b.y)*size[2])^2) end
    end
    pickupState.position=assert(A.Data:Target(A.Data:GetQuest(extraId),pickupState))
    local candidates=A.Data.Candidates
    A.Data.Candidates=function() return {id,extraId} end
    local pickup=A.TaskQueue.Pickup
    A.TaskQueue.Pickup=function() end
    local before=run(function() return A.Planner.Build(pickupState,A.Data,options) end)
    local baseline=assert(A.TaskQueue.Evaluate(before.taskOrder,pickupState,A.Navigation,A.Data))
    A.TaskQueue.Pickup=pickup
    local after=run(function() return A.Planner.Build(pickupState,A.Data,options) end,"native-zone pickup plan")
    assert(before.fallback.questId==id and after.fallback.kind=="accept" and after.fallback.questId==extraId)
    local queue=assert(after.taskQueue)
    assert(queue.xpKnown and queue.xp/queue.seconds>baseline.xp/baseline.seconds)
    assert(after.fallback.pickupResume and not pickupState.quests[extraId] and not pickupState.completed[id])
    print(string.format("%s real pickup #%d + #%d: %.1f seconds / %.0f XP -> %.1f seconds / %.0f XP (straight-line model)",
        faction,id,extraId,baseline.seconds,baseline.xp,queue.seconds,queue.xp))
    A.Data.Candidates=candidates
    local full=run(function() return A.Planner.Build(pickupState,A.Data,options) end,"full candidate pickup plan")
    assert(full.fallback and #full.taskChoices>1 and not pickupState.quests[extraId])
    print(string.format("%s full candidate pool: %d choices, next #%d %s",faction,#full.taskChoices,full.fallback.questId,full.fallback.kind))
    A.Navigation.Distance=distance
end

do
    local q=A.Data:GetQuest(60860)
    assert(q.questLevel==0 and q.requiredLevel==0)
    local context=dofile(root.."/tests/fixtures.lua").State()
    context.faction,context.classMask,context.raceMask=faction,s.classMask,s.raceMask
    context.completionKnown=true
    for _,npc in ipairs(q.startedBy[1]) do
        local side=db.Npc.Get(npc,"friendlyToFaction")
        if side=="AH" or side==(faction=="Alliance" and "A" or "H") then
            context.position=A.Data:EntityPoints(db.Npc,npc)[1]
            if context.position then break end
        end
    end
    assert(context.position and not A.Data:Target(q,context))
    context.locked=q.id;local manual=assert(A.Data:Target(q,context));context.locked=nil
    context.questOffers={[manual.entityId]={[q.id]=true}}
    local offered=run(function() return A.Planner.TaskChoices(context,A.Data,{q.id},true,options) end)
    assert(#offered==1 and offered[1].actions[1].position.entityId==manual.entityId)
    context.questOffers={[manual.entityId]={}}
    assert(#run(function() return A.Planner.TaskChoices(context,A.Data,{q.id},true,options) end)==0)
    context.quests[q.id]={ready=true,objectives={}}
    assert(A.Data:Target(q,context) and not context.completed[q.id])
    print(faction..": real #60860 enters automatic choices only when offered; manual target and native ready delivery remain available")
end

if faction=="Horde" then
    local q=A.Data:GetQuest(99101)
    local context=dofile(root.."/tests/fixtures.lua").State()
    context.faction,context.classMask,context.raceMask=faction,s.classMask,s.raceMask
    context.clientVersion,context.clientBuild,context.interface="1.60.1","70862",16001
    context.position=A.Data:EntityPoints(db.Npc,3222)[1]
    assert(q.questLevel==9 and q.sourceItemId==286104 and not A.TaskGuide.XP(q,context.level,context))
    local descriptions,_,complex=A.Data:ReferenceObjectiveTargets(q,context)
    assert(not complex and #descriptions==1 and descriptions[1].targetId==286104 and
        descriptions[1].numRequired==1 and descriptions[1].providedOnAccept)
    local first={kind="accept",questId=q.id,title=q.title,position=assert(A.Data:Target(q,context))}
    local stages,complete=A.TaskGuide.Stages(q,context,A.Data,first)
    assert(complete and #stages==2 and stages[2].kind=="turnin" and
        stages[2].itemRequirements[1].need==1 and stages[2].itemRequirements[1].providedOnAccept)
    assert(not context.quests[q.id] and not context.completed[q.id] and not context.bags[286104])
    local saved=q.sourceItemId;q.sourceItemId=nil
    assert(not A.Data:CacheQuest(q,context));q.sourceItemId=saved
    local inventory=dofile(root.."/tools/continuous_inventory.lua")
    local active=assert(inventory.Accept(q,context,A.Data))
    assert(active.ready and context.bags[286104]==1 and not context.completed[q.id])
    inventory.TurnIn(q.id,context)
    assert(context.completed[q.id] and context.bags[286104]==0 and not context.quests[q.id])
    print("Horde: real #99101 previews accept + delivery; supplied report count is one; no XP invented; simulated turn-in consumes it")
end
