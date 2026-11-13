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
local count,skipped=0,0
local found={}
for _,id in ipairs(A.Data.ids) do
 local q=A.Data:GetQuest(id)
 if q.sourceItemId and q.sourceItemId>0 then
  local descriptions,_,complex=A.Data:ReferenceObjectiveTargets(q,s)
  local provided,remaining=0,0
  for _,o in ipairs(descriptions) do
   if o.providedOnAccept then
    assert(o.targetKind=="item" and o.targetId==q.sourceItemId and o.numRequired==1)
    assert(not o.finished and o.numFulfilled==0 and not next(s.bags))
    provided=provided+1
   elseif not o.finished then remaining=remaining+1 end
  end
  if provided>0 then
   count=count+1;skipped=skipped+provided;found[id]=true
   local stages=A.TaskGuide.Stages(q,s,A.Data,{kind="accept",position=A.Data:Target(q,s)})
   local objectives=0;for _,stage in ipairs(stages) do if stage.kind=="objective" then objectives=objectives+1 end end
   assert(objectives==remaining+(complex and 1 or 0),"lost another requirement "..id)
   s.quests[id]={objectives=descriptions}
   local active=A.Data:ReferenceObjectiveTargets(q,s)
   for _,o in ipairs(active) do assert(not o.providedOnAccept,"assumed new grant on active quest "..id) end
   assert(not s.quests[id].ready and not s.completed[id] and not next(s.bags))
   s.quests[id]=nil
  end
 end
end
assert(found[3100],"Simple Letter not handled")
assert(count>0)
print("PASS",faction,class,count,skipped,"provided item previews; other objectives and native state retained")
