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

local checked,located=0,0
for _,id in ipairs(A.Data.ids) do
 local q=A.Data:GetQuest(id)
 local trigger=db.Quest.Get(id,"triggerEnd")
 if trigger then
  checked=checked+1
  local s={faction=faction,quests={},completed={}}
  local descriptions,positions=A.Data:ReferenceObjectiveTargets(q,s)
  local eventIndex
  for index,o in ipairs(descriptions) do if o.type=="event" then assert(not eventIndex);eventIndex=index end end
  assert(eventIndex)
  local point=A.Data:TriggerTarget(q,s)
  if point then
   located=located+1
   local matched=false
   for area,spawns in pairs(trigger[2] or {}) do
    if A.Data.maps[area]==point.map then
     for _,raw in ipairs(spawns) do
      if point.approximate then
       if raw[1]==-1 and raw[2]==-1 and (not raw[3] or raw[3]==0) then matched=true end
      elseif math.abs(point.x-raw[1]/100)<0.000001 and math.abs(point.y-raw[2]/100)<0.000001 then matched=true end
     end
    end
   end
   assert(matched,"event destination not in actual trigger coordinates: "..id)
   assert(positions[eventIndex].sourceKind=="trigger")
   s.quests[id]={objectives={{type="event",text="实际日志语言独立",finished=false}}}
   local action=A.Data:Target(q,s)
   assert(action.sourceKind=="trigger" and action.objectiveIndex==1 and not action.targetId)
   local stages=A.TaskGuide.Stages(q,s,A.Data,{kind="objective",position=action,objectiveIndex=1})
   assert(stages[1].position.sourceKind=="trigger")
   assert(not s.quests[id].ready and not s.completed[id])
   s.quests[id].objectives[1].finished=true
   assert(#A.Data:ObjectiveTargets(q,s)==0)
   s.quests[id].ready=true;local finish=A.Data:Target(q,s)
   assert(not finish or finish.sourceKind~="trigger")
   print(table.concat({"located",id,q.title,point.map,point.x,point.y,point.approximate and "area" or "precise"},"\t"))
  else
   print(table.concat({"unlocated",id,q.title},"\t"))
  end
 end
end
assert(checked>0 and located>0)
print(string.format("PASS %d/%d trigger tasks located",located,checked))
