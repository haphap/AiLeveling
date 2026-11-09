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

local checked,located,aliases=0,0,0
for _,id in ipairs(A.Data.ids) do
 local rows=db.Quest.Get(id,"objectives") or {}
 if #(rows[5] or {})>0 then
  checked=checked+1
  local q=A.Data:GetQuest(id)
  local s={faction=faction,quests={},completed={}}
  local descriptions,positions,complex=A.Data:ReferenceObjectiveTargets(q,s)
  local goals=0
  for index,description in ipairs(descriptions) do
   if description.targetKind=="killcredit" then
    goals=goals+1
    local row
    for _,candidate in ipairs(rows[5]) do if candidate[2]==description.targetId then row=candidate end end
    assert(row,"missing raw credit group "..id)
    local p=positions[index]
    local actualSource=false
    if p and p.entityId then
     for _,npc in ipairs(row[1]) do
      if npc==p.entityId then
       for _,raw in ipairs(A.Data:EntityPoints(db.Npc,npc,true)) do
        if raw.map==p.map and raw.x==p.x and raw.y==p.y and raw.approximate==p.approximate then actualSource=true end
       end
      end
     end
    end
    assert(actualSource,"no source placement for "..id)
    assert(p.targetKind=="killcredit" and p.targetId==row[2])
    located=located+1
    local names={db.Npc.Get(row[2],"name")}
    for _,npc in ipairs(row[1]) do names[#names+1]=db.Npc.Get(npc,"name") end
    for _,name in ipairs(names) do
     local live={}
     for n,d in ipairs(descriptions) do
      live[n]={text=d.text,type=d.targetKind=="item" and "item" or d.targetKind=="object" and "object" or "monster",finished=false}
     end
     live[index]={text=name..": 1/3",type="monster",numRequired=3,numFulfilled=1,finished=false}
     s.quests[id]={objectives=live};s.position={map=p.map,x=p.x,y=p.y}
     local identity=A.Data:ObjectiveIdentities(q,s)[index]
     assert(identity and identity.kind=="killcredit" and identity.id==row[2],"live alias mismatch "..id.." "..name)
     local found
     for _,point in ipairs(A.Data:ObjectiveTargets(q,s)) do if point.objectiveIndex==index then found=point end end
     assert(found and found.targetId==row[2])
     local stages=A.TaskGuide.Stages(q,s,A.Data,{kind="objective",questId=id,position=found,objectiveIndex=index})
     local stage;for _,v in ipairs(stages) do if v.objectiveIndex==index then stage=v end end
     assert(stage and stage.targetId==row[2] and stage.have==1 and stage.need==3)
     live[index].finished=true
     for _,point in ipairs(A.Data:ObjectiveTargets(q,s)) do assert(point.objectiveIndex~=index) end
     assert(not s.quests[id].ready and not s.completed[id])
     aliases=aliases+1
    end
    print(table.concat({"credit",id,q.title,index,row[2],p.entityId,p.map,p.x,p.y,p.approximate and "area" or "exact"},"\t"))
   end
  end
  assert(goals==#rows[5],"group split or omitted "..id)
  local order=db.ObjectiveFirst.killCreditObjectiveFirst
  if order[id] then assert(descriptions[1].targetKind=="killcredit") end
 end
end
assert(checked>0)
print(string.format("PASS %d credit quests; %d located groups; %d native-style alias replays",checked,located,aliases))
