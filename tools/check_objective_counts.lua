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
local count,targets=0,0
for _,id in ipairs(A.Data.ids) do
 local q=A.Data:GetQuest(id);local raw=db.Quest.Get(id,"objectives") or {}
 local cache=A.Data:CacheQuest(q,s)
 if cache and next(raw) then
  local changed=false
  local desc=A.Data:ReferenceObjectiveTargets(q,s)
  for _,o in ipairs(desc) do
   local explicit
   for _,fact in ipairs(q.taskFacts and q.taskFacts.objectives or {}) do
    if fact.kind==o.targetKind and fact.id==o.targetId then explicit=fact.count end
   end
   local index=({npc=1,object=2,item=3})[o.targetKind]
   for _,row in ipairs(raw[index] or {}) do if row[1]==o.targetId then explicit=row.count or explicit end end
   if not explicit then
    local amounts={};for _,fact in ipairs(cache.objectives) do
     if fact.kind==o.targetKind and fact.id==o.targetId then amounts[fact.count]=true end
    end
    local value,n=nil,0;for amount in pairs(amounts) do value=amount;n=n+1 end
    if n==1 then assert(o.numRequired==value,"missing count "..id);changed=true;targets=targets+1 end
   end
  end
  assert(same(raw,db.Quest.Get(id,"objectives") or {}),"provider mutated "..id)
  if changed then count=count+1 end
 end
end
for _,spec in ipairs({{97277,277976,1},{97279,277653,6}}) do
 local desc=A.Data:ReferenceObjectiveTargets(A.Data:GetQuest(spec[1]),s);local found
 for _,o in ipairs(desc) do if o.targetId==spec[2] then assert(o.numRequired==spec[3]);found=true end end
 assert(found)
end
assert(count>0 and targets>0)
print("PASS",faction,class,count,targets,"cached counts fill matching identities; explicit counts and provider retained")
