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

local checked,improved,fish=0,0,0
for _,id in ipairs(A.Data.ids) do
 local q=A.Data:GetQuest(id)
 local extras=db.Quest.Get(id,"extraObjectives") or {}
 if #extras>0 then
  checked=checked+1
  local s={faction=faction,quests={},completed={}}
  local descriptions,positions,complex=A.Data:ReferenceObjectiveTargets(q,s)
  local count=0
  for index,p in pairs(positions) do
   if p.sourceKind=="extra" then
    assert(not complex)
    assert(p.targetId==descriptions[index].targetId and p.targetKind==descriptions[index].targetKind)
    local extra,rows=nil,0
    for _,e in ipairs(extras) do
     if e[4]==index or e[4]==0 and #extras==1 and #descriptions==1 then extra=e;rows=rows+1 end
    end
    assert(rows==1)
    local matched=false
    for area,spawns in pairs(extra[1] or {}) do
     if A.Data.maps[area]==p.map then
      for _,raw in ipairs(spawns) do
       if p.approximate and raw[1]==-1 and raw[2]==-1 or
        not p.approximate and math.abs(p.x-raw[1]/100)<0.000001 and math.abs(p.y-raw[2]/100)<0.000001 then matched=true end
      end
     end
    end
    for _,ref in ipairs(extra[5] or {}) do
     if p.entityId==ref[2] and p.entityKind==(ref[1]=="monster" and "npc" or "object") then matched=true end
    end
    assert(matched,"unproven special destination "..id)
    count=count+1
    print(table.concat({"extra",id,q.title,index,p.map,p.x,p.y,p.targetId or 0,p.entityId or 0},"\t"))
   end
  end
  if count>0 then
   improved=improved+1
   s.quests[id]={objectives=descriptions}
   local actual=A.Data:ObjectiveTargets(q,s)
   local found={};for _,p in ipairs(actual) do found[p.objectiveIndex]=p end
   for index,p in pairs(positions) do if p.sourceKind=="extra" then assert(found[index].sourceKind=="extra") end end
   for _,d in ipairs(descriptions) do d.finished=true end
   assert(#A.Data:ObjectiveTargets(q,s)==0)
   assert(not s.completed[id] and not s.quests[id].ready)
  end
  if id==1579 or id==1580 then assert(count==1);fish=fish+1 end
 end
end
assert(fish==2 and improved>0)
print(string.format("PASS %d/%d special-objective quests improved; both fishing tasks located",improved,checked))
