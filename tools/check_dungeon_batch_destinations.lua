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
assert(loadfile(root.."/Planner/Selection.lua"))("AiLeveling",A)
local s=dofile(root.."/tests/fixtures.lua").State()
s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
s.faction,s.class,s.raceId=faction,class,raceId
s.classMask,s.raceMask=db.Enum.classKeys[class],db.Enum.raceMaskById[raceId]
s.level,s.maxXP=40,A.Experience.xpToLevel[40]
s.position={map=faction=="Alliance" and 1436 or 1413,x=0.5,y=0.5}
A.state,A.ready=s,true
A.State.Refresh=function() s.locked=A.char.locked;A.Selection:Snapshot(s);A.Dungeon:TaskBatchSnapshot(s) end
local catalogs,selected,restored,journeySteps=0,0,0,0
for id,d in pairs(A.Dungeon.Catalog(s,A.Content)) do
 catalogs=catalogs+1;s.quests={};s.completed={};s.taskBatch=nil;s.locked=nil
 A.char={turnIns={},skipped={}}
 for qid in pairs(d.quests[faction] or {}) do
  local q=A.Data:GetQuest(qid)
  if q and A.Eligibility.InMask(q.requiredRaces,s.raceMask)==true and A.Eligibility.InMask(q.requiredClasses,s.classMask)==true then
   local descriptions=A.Data:ReferenceObjectiveTargets(q,s)
   s.quests[qid]={title=q.title,objectives=descriptions}
  end
 end
 local rows=A.Dungeon.Tasks(d,s,A.Data)
 local expected,missing={},{}
 for _,row in ipairs(rows) do
  if row.allowed and (row.position or row.areaId) or row.preparation then expected[row.id]=true end
  if row.allowed and not row.position and row.areaId then
   assert(A.Dungeon.TaskInstance(nil,s,A.Data,row.areaId));missing[row.id]=row.areaId
  end
 end
 local ok=A.Dungeon:StartTaskBatch(id)
 if next(expected) then
  assert(ok)
  for qid in pairs(expected) do assert(s.taskBatch.baselines[qid]~=nil);selected=selected+1 end
  for qid in pairs(s.taskBatch.baselines) do assert(expected[qid]) end
  local result=run(function() return {A.Dungeon.TaskBatchChoices(s,A.Data)} end)
  local choices,info=result[1],result[2]
  local expectedSteps={}
  for _,choice in ipairs(choices) do
   if not choice.lowValue and not choice.entryBlocked and not choice.requireCheck then
    for _,stage in ipairs(choice.stages or choice.actions) do expectedSteps[stage]=true end
   end
  end
  for _,phase in ipairs({"before","inside","after"}) do
   for _,step in ipairs(info.journey[phase]) do
    assert(expectedSteps[step.action]);expectedSteps[step.action]=nil;journeySteps=journeySteps+1
    local instance=A.Dungeon.TaskInstance(step.action.position,s,A.Data,step.action.areaId)
    if phase=="inside" then assert(instance and instance.instanceId==d.instanceId)
    else assert(not instance or instance.instanceId~=d.instanceId) end
   end
  end
  assert(not next(expectedSteps))
  local seen={};for _,choice in ipairs(choices) do
   if missing[choice.questId] then
    assert(not choice.actions[1].position and choice.actions[1].areaId==missing[choice.questId])
    seen[choice.questId]=true
   end
  end
  for qid in pairs(missing) do assert(seen[qid]);restored=restored+1 end
  local rewards=A.Dungeon.TaskRewards(rows,s.taskBatch.baselines,choices)
  local expectedCount=0;local byId={};for _,c in ipairs(choices) do byId[c.questId]=c end
  for _,row in ipairs(rows) do
   local c=byId[row.id]
   if expected[row.id] and row.group~=5 and not row.requireCheck and not row.lowValue and not (c and c.lowValue) then expectedCount=expectedCount+1 end
  end
  assert(rewards.count==expectedCount)
 else assert(not ok) end
end
assert(catalogs==34 and restored>0)
print(string.format("PASS %d native-map dungeon catalogs; %d selected roots; %d coordinate-free roots retained in batch/actions/rewards",catalogs,selected,restored))
print(string.format("PASS %d remaining actions preserved exactly once in dungeon task journey phases",journeySteps))
