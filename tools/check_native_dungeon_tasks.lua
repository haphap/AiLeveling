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
local native={}
for id in assert(arg[7]):gmatch("%d+") do native[tonumber(id)]=true end
C_Map.GetMapInfo=function(id) if native[id] then return {mapID=id,mapType=3,name="构建地图"} end end
local old
if arg[8] then
 local prior={State=A.State,Navigation=A.Navigation};assert(loadfile(arg[8]))("AiLeveling",prior)
 old=prior.Data;old.db,old.maps=A.Data.db,A.Data.maps
end
local F=dofile(root.."/tests/fixtures.lua")
local s=F.State()
s.clientVersion,s.clientBuild,s.faction,s.class,s.raceId="1.60.1","70862",faction,class,raceId
s.classMask,s.raceMask=db.Enum.classKeys[class],db.Enum.raceMaskById[raceId]
s.position={map=faction=="Horde" and 1413 or 1436,x=0.5,y=0.5}
local checked,unmapped,improved=0,0,0
for _,id in ipairs(A.Data.ids) do
 local q=A.Data:GetQuest(id)
 local descriptions=A.Data:ReferenceObjectiveTargets(q,s)
 for wanted=1,#descriptions do
  s.quests={[id]={objectives={}}}
  for i,o in ipairs(descriptions) do
   local c={};for k,v in pairs(o) do c[k]=v end;c.finished=i~=wanted;s.quests[id].objectives[i]=c
  end
  checked=checked+1
  if not A.Data:Target(q,s) then
   local area,index=A.Data:UnmappedTargetArea(q,s)
   local instance=A.Dungeon.TaskInstance(nil,s,A.Data,area)
   if instance then
    assert(index==wanted);unmapped=unmapped+1
    local action={kind="objective",questId=id,title=q.title,areaId=area,objectiveIndex=index}
    local stages,complete=A.TaskGuide.Stages(q,s,A.Data,action)
    assert(not complete and stages[1].areaId==area and not stages[1].position)
    local choice={questId=id,actions={action},stages=stages}
    local issue=A.Dungeon.TaskEntryIssue(choice,s,A.Data,{dungeons=false})
    assert(issue and issue:find("已关闭副本建议",1,true),"disabled dungeon task "..id)
    assert(not A.Dungeon.TaskEntryIssue(choice,s,A.Data,{dungeons=true}))
    local outside=A.Dungeon.TaskApproach(action,s,A.Data)
    assert(outside.kind=="dungeonEnter" or #instance.entrances==0)
    s.inInstance,s.instanceId=true,instance.instanceId
    local inside=A.Dungeon.TaskApproach(action,s,A.Data)
    assert(inside.kind=="objective" and not inside.position and inside.objectiveIndex==wanted)
    assert(inside.text:find(instance.title,1,true))
    s.inInstance=false
    if old and old:Target(q,s) then improved=improved+1;print("improved",id,q.title,wanted,area,instance.instanceId) end
   end
  end
 end
end
-- Independent mixed-objective states: local instance work must precede an exit.
local mixed=0
for _,id in ipairs(A.Data.ids) do
 local q=A.Data:GetQuest(id)
 s.inInstance=false;s.position={map=1436,x=0.5,y=0.5};s.quests={};s.locked=nil
 local descriptions=A.Data:ReferenceObjectiveTargets(q,s)
 if #descriptions>1 then
  s.quests={[id]={objectives=descriptions}}
  local point=A.Data:Target(q,s)
  local area,index
  if not point then area,index=A.Data:UnmappedTargetArea(q,s) end
  local stages=A.TaskGuide.Stages(q,s,A.Data,{kind="objective",questId=id,title=q.title,position=point,
   areaId=area,objectiveIndex=point and point.objectiveIndex or index})
  local destinations={}
  for _,stage in ipairs(stages) do
   if stage.kind=="objective" then
    local instance=A.Dungeon.TaskInstance(stage.position,s,A.Data,stage.areaId)
    if instance then destinations[instance.instanceId]=true end
   end
  end
  for instanceId in pairs(destinations) do
   local first=A.Dungeon.TaskInstance(stages[1].position,s,A.Data,stages[1].areaId)
   if not first or first.instanceId~=instanceId then
    s.inInstance,s.instanceId,s.position=true,instanceId,nil
    local choices=run(function() return A.Planner.TaskChoices(s,A.Data,{id},true) end)
    assert(#choices==1,"mixed objective quest omitted "..id)
    local choice=choices[1]
    local target=choice.actions[1]
    local actual=A.Dungeon.TaskInstance(target.position,s,A.Data,target.areaId)
    assert(actual and actual.instanceId==instanceId and choice.currentInstance,"premature exit "..id)
    assert(target.kind=="objective" and target.objectiveIndex and not descriptions[target.objectiveIndex].finished)
    assert(#choice.stages==#stages and choice.stages[#stages].kind=="turnin")
    mixed=mixed+1
   end
  end
 end
end
s.inInstance=false;s.position={map=1436,x=0.5,y=0.5}
assert(mixed>0)
print(string.format("MIXED %d quest/instance states retain local objectives before exit",mixed))
-- Identity coverage only: these independent quests are not a claimed simultaneous quest log.
local recipients,recipientState,expected={},{quests={},skipped={},chainDeferred={}},{}
for _,id in ipairs(A.Data.ids) do
 local q=A.Data:GetQuest(id)
 local state={quests={[id]={ready=true,objectives={}}},completed={},position=s.position,faction=s.faction}
 local point=A.Data:Target(q,state)
 local sources=db.Quest.Get(id,"finishedBy") or {}
 if not point and #(sources[1] or {})+#(sources[2] or {})==1 then
  local npc=#(sources[1] or {})==1
  local key=(npc and "npc:" or "object:")..sources[npc and 1 or 2][1]
  expected[key]=(expected[key] or 0)+1
  local stage={kind="turnin",questId=id,areaId=A.Data:UnmappedTargetArea(q,state)}
  local stages,complete=A.TaskGuide.Stages(q,state,A.Data,stage)
  assert(not complete and not stages[1].position)
  local recipient=assert(stages[1].recipient)
  assert(recipient.entityKind..":"..recipient.entityId==key)
  recipients[#recipients+1]={questId=id,stages=stages}
  recipientState.quests[id]=state.quests[id]
 end
end
local expectedGroups=0
for _,count in pairs(expected) do if count>1 then expectedGroups=expectedGroups+1 end end
local groups=A.TaskGuide.DeliveryGroups(recipients,recipientState)
assert(#groups==expectedGroups and expectedGroups>0)
for _,group in ipairs(groups) do assert(#group.choices==expected[group.key] and group.ready==#group.choices) end
print(string.format("RECIPIENTS %d independent quests without coordinates; %d shared-recipient groups",#recipients,#groups))
-- All four remaining-objective combinations must preserve the same real instance.
local q=assert(A.Data:GetQuest(914));local descriptions=A.Data:ReferenceObjectiveTargets(q,s)
s.locked=914;s.level=30;s.position={map=1413,x=0.46,y=0.365}
local function plan() return run(function() return A.Planner.Build(s,A.Data,{minutes=60,mode="fast",dungeons=false,role="DAMAGER"}) end) end
for wanted=1,4 do
 s.quests={[914]={objectives={}}};s.inInstance=false
 for i,o in ipairs(descriptions) do local c={};for k,v in pairs(o) do c[k]=v end;c.finished=i~=wanted;s.quests[914].objectives[i]=c end
 -- Use the actual quest's faction and race eligibility for this workflow.
 s.faction="Horde";s.raceMask=2;s.classMask=1
 local candidates=A.Data.Candidates;A.Data.Candidates=function() return {914} end
 s.locked=nil
 local disabled=plan()
 local held;for _,choice in ipairs(disabled.taskChoices) do if choice.questId==914 then held=choice end end
 assert(held and held.entryBlocked and held.entryBlocked:find("已关闭副本建议",1,true))
 -- Eligible outdoor prerequisites remain alternatives to the disabled instance task.
 assert(not disabled.fallback or disabled.fallback.questId~=914 or
     disabled.fallback.kind=="dungeonBlocked" and not disabled.fallback.position)
 s.locked=914;A.Data.Candidates=candidates
 local p=plan();assert(p.fallback.kind=="dungeonEnter" and p.fallback.questId==914)
 s.position=p.fallback.position;p=plan();assert(p.fallback.kind=="dungeonEnter" and not s.quests[914].ready)
 s.inInstance,s.instanceId,s.position=true,43,nil
 p=plan();assert(p.fallback.kind=="objective" and p.fallback.objectiveIndex==wanted and not p.fallback.position)
 s.quests[914].ready=true;p=plan();assert(p.fallback.kind=="dungeonLeave")
 s.inInstance=false;s.position={map=1456,x=0.5,y=0.5};p=plan();assert(p.fallback.kind=="turnin")
 assert(not s.completed[914])
end
print(string.format("PASS %d isolated objective states; %d unmapped dungeon objectives; %d restored; quest 914 all four disabled/manual/objective/entry/inside/exit/turnin flows",checked,unmapped,improved))
