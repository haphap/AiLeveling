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
C_Map.GetMapInfo=function(id) return {mapID=id,mapType=3,name="模拟地图"} end
local F=dofile(root.."/tests/fixtures.lua")
local stages,entrances=0,0
for _,id in ipairs(A.Data.ids) do
 local q=A.Data:GetQuest(id)
 for _,kind in ipairs({"accept","objective","turnin"}) do
  local s={faction=faction,quests={},completed={},clientVersion="1.60.1",clientBuild="70862"}
  if kind=="objective" then
   local descriptions=A.Data:ReferenceObjectiveTargets(q,s)
   s.quests[id]={objectives=descriptions}
  elseif kind=="turnin" then s.quests[id]={ready=true} end
  if not A.Data:Target(q,s) then
   local area,index=A.Data:UnmappedTargetArea(q,s)
   local instance=A.Dungeon.TaskInstance(nil,s,A.Data,area)
   if instance then
    stages=stages+1
    local action={kind=kind,questId=id,title=q.title,areaId=area,objectiveIndex=index}
    local outside=A.Dungeon.TaskApproach(action,s,A.Data)
    if outside.position then
     assert(outside.kind=="dungeonEnter")
     local matched=false
     for _,entry in ipairs(instance.entrances) do
      if A.Data.maps[entry[1]]==outside.position.map and math.abs(entry[2]/100-outside.position.x)<0.000001 and
       math.abs(entry[3]/100-outside.position.y)<0.000001 then matched=true end
     end
     assert(matched);entrances=entrances+1
    end
    s.inInstance,s.instanceId=true,instance.instanceId
    local inside=A.Dungeon.TaskApproach(action,s,A.Data)
    assert(inside.kind==kind and inside.questId==id and not inside.position and inside.text:find(instance.title,1,true))
    s.instanceId=999999;assert(A.Dungeon.TaskApproach(action,s,A.Data).kind=="dungeonLeave")
    s.inInstance=false;s.instanceEntryError="模拟次数受限"
    assert(A.Dungeon.TaskApproach(action,s,A.Data).kind=="dungeonBlocked")
    assert(not s.completed[id])
    print(table.concat({"unmapped",id,q.title,kind,area,instance.instanceId,outside.kind},"\t"))
   end
  end
 end
end
local id=92401;local q=assert(A.Data:GetQuest(id));local s=F.State()
s.clientVersion,s.clientBuild,s.faction,s.class,s.raceId="1.60.1","70862",faction,class,raceId
s.classMask,s.raceMask=db.Enum.classKeys[class],db.Enum.raceMaskById[raceId]
s.locked=id;s.quests={[id]={title=q.title,objectives={{type="event",text="按日志完成事件",numFulfilled=0,numRequired=1}}}}
s.position={map=1458,x=0.5,y=0.5}
local function plan() return run(function() return A.Planner.Build(s,A.Data,{minutes=60,mode="fast",dungeons=false,role="DAMAGER"}) end) end
local p=plan();assert(p.fallback.kind=="dungeonEnter" and p.fallback.questId==id)
assert(p.fallback.position.map==A.Data.maps[1497] and math.abs(p.fallback.position.x-0.7241)<0.000001)
s.position=p.fallback.position;p=plan();assert(p.fallback.kind=="dungeonEnter" and not s.quests[id].ready)
s.inInstance,s.instanceId,s.position=true,2999,nil
p=plan();assert(p.fallback.kind=="objective" and not p.fallback.position and p.fallback.areaId==16611)
assert(p.fallback.text:find("洛丹伦废墟",1,true) and not p.travelActions)
s.instanceId=999;p=plan();assert(p.fallback.kind=="dungeonLeave")
s.inInstance=false;s.position={map=1458,x=0.5,y=0.5}
s.instanceEntryError="模拟次数受限";p=plan();assert(p.fallback.kind=="dungeonBlocked" and not p.travelActions)
s.instanceEntryError=nil;p=plan();assert(p.fallback.kind=="dungeonEnter")
s.quests[id].objectives[1].finished=true;assert(A.Data:UnmappedTargetArea(q,s)==nil)
s.quests[id].ready=true;p=plan();assert(p.fallback.kind=="turnin" or p.fallback.kind=="dungeonEnter")
print("turnin",id,p.fallback.kind,p.fallback.position and p.fallback.position.map or 0)
assert(not s.completed[id])
assert(stages>0 and entrances>0)
print(string.format("PASS %d unmapped stages; %d outdoor entrances; quest 92401 full planner replay",stages,entrances))
