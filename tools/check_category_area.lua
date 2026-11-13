-- Fixed real QuestieDB category placement checks; player log and map availability are simulated.
-- Ground distances use the pinned native zone rectangles; character/game events are simulated.
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
for _,file in ipairs({"State.lua","Hearth.lua","Data/TaskFacts.lua","Data/Experience.lua","Data/Flights.lua","Data/Dungeons.lua","Data/Questie.lua",
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


local count=0
for _,id in ipairs(A.Data.ids) do
 local q=A.Data:GetQuest(id)
 if type(q.zoneOrSort)=="number" and q.zoneOrSort<0 then
  s.quests={}
  local giver=A.Data:Target(q,s)
  local point=A.Data:QuestAreaTarget(q,s)
  if giver then
   assert(point and point.map==giver.map and point.x==0.5 and point.y==0.5 and point.approximate)
   assert(not point.entityId and not point.targetId)
   count=count+1
  else assert(not point) end
 end
end
for _,id in ipairs({1682,96659}) do
 local q=A.Data:GetQuest(id)
 s.quests={[id]={objectives={{text="Unresolved native goal"}}}}
 local point=assert(A.Data:Target(q,s),"missing category fallback "..id)
 assert(point.approximate and point.x==0.5 and point.y==0.5)
 local stages=A.TaskGuide.Stages(q,s,A.Data,{kind="objective",questId=id,position=point})
 assert(stages[1].position and not s.quests[id].ready and not s.completed[id])
 print("RECOVERED",id,point.map)
end
assert(count>0)
print("PASS category giver-area references",count)
