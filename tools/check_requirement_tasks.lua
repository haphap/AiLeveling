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

local standings={}
C_Reputation={GetFactionDataByID=function(id) return {name="阵营"..id,currentStanding=standings[id]} end}
C_Spell={GetSpellName=function(id) return "法术"..id end}
local repCount,spellCount,repLocated,spellLocated,extraCount=0,0,0,0,0
for _,id in ipairs(A.Data.ids) do
 local rows=db.Quest.Get(id,"objectives") or {}
 if next(rows[4] or {}) or next(rows[6] or {}) then
  local q=A.Data:GetQuest(id)
  local s={faction=faction,quests={},completed={},spells={}}
  local rep=rows[4]
  if rep and next(rep) then
   repCount=repCount+1;assert(A.Data.requirements.reputations[rep[1]])
   standings[rep[1]]=rep[2]-1
   A.State:Qualifications(s,A.Data.requirements)
   assert(s.reputations[rep[1]]==rep[2]-1)
  end
  if next(rows[6] or {}) then spellCount=spellCount+1 end
  local descriptions,positions,complex=A.Data:ReferenceObjectiveTargets(q,s)
  assert(not complex,"unexpanded requirement "..id)
  local first={kind="accept",position=A.Data:Target(q,s)}
  local stages=A.TaskGuide.Stages(q,s,A.Data,first)
  local repIndex
  for index,d in ipairs(descriptions) do
   if d.targetKind=="reputation" or d.targetKind=="spell" then
    assert(not d.finished)
    local p=positions[index]
    assert(p,"missing reference destination "..id)
    if d.targetKind=="spell" and not A.Data:AreaTarget(q) and not p.sourceKind then
     local giver=A.Data:Target(q,{quests={},completed={}})
     assert(giver and p.map==giver.map and p.x==0.5 and p.y==0.5 and p.approximate)
    end
    if p then
     assert(p.targetKind==d.targetKind and p.targetId==d.targetId)
     if d.targetKind=="reputation" then repLocated=repLocated+1 else spellLocated=spellLocated+1 end
     if p.sourceKind=="extra" then extraCount=extraCount+1 end
    end
    local found
    for _,stage in ipairs(stages) do if stage.targetKind==d.targetKind and stage.targetId==d.targetId then found=stage end end
    assert(found,"missing stage "..id)
    if d.targetKind=="reputation" then
     assert(d.targetId==rep[1] and found.have==rep[2]-1 and found.need==rep[2]);repIndex=index
    else
     local raw=false;for _,row in ipairs(rows[6]) do if row[1]==d.targetId then raw=true end end;assert(raw)
     s.spells[d.targetId]=true
    end
    print(table.concat({"requirement",id,q.title,d.targetKind,d.targetId,p and p.map or 0,p and (p.sourceKind or "area") or "unlocated"},"\t"))
   end
  end
  if repIndex then
   standings[rep[1]]=rep[2];A.State:Qualifications(s,A.Data.requirements)
   local met,at=A.Data:ReferenceObjectiveTargets(q,s)
   assert(met[repIndex].finished and at[repIndex]==nil and #met==#descriptions)
   local reduced=A.TaskGuide.Stages(q,s,A.Data,first);assert(#reduced==#stages-1)
   assert(not s.quests[id] and not s.completed[id])
   standings[rep[1]]=nil;A.State:Qualifications(s,A.Data.requirements)
   met=A.Data:ReferenceObjectiveTargets(q,s);assert(not met[repIndex].finished)
  end
  -- Native log facts remain authoritative, even if reputation or spell knowledge is satisfied.
  local live={}
  for n,d in ipairs(descriptions) do
   live[n]={text=d.text,type=d.type or (d.targetKind=="item" and "item" or d.targetKind=="object" and "object" or "monster"),finished=false,numFulfilled=0,numRequired=1}
  end
  s.quests[id]={objectives=live}
  if rep then s.reputations=s.reputations or {};s.reputations[rep[1]]=rep[2] end
  local identities=A.Data:ObjectiveIdentities(q,s)
  for index,d in ipairs(descriptions) do
   if d.targetKind=="reputation" or d.targetKind=="spell" then
    assert(identities[index] and identities[index].kind==d.targetKind and identities[index].id==d.targetId,"native identity "..id)
    live[index].finished=true
    for _,p in ipairs(A.Data:ObjectiveTargets(q,s)) do assert(p.objectiveIndex~=index) end
   end
  end
  assert(not s.quests[id].ready and not s.completed[id])
 end
end
assert(repCount>0 and spellCount>0)
print(string.format("PASS %d reputation quests (%d located); %d spell quests (%d located goals); %d special placements",repCount,repLocated,spellCount,spellLocated,extraCount))
