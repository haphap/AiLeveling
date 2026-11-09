-- Fixed QuestieDB API; character state and map availability are simulated.
local root,package,faction,class=assert(arg[1]),assert(arg[2]),assert(arg[3]),assert(arg[4])
local client,metadata=dofile("emulator/client.lua"),dofile("emulator/metadata.lua")
client.install({expansion="Forever",faction=faction,classFile=class,locale="zhCN"})
metadata.load(package.."/QuestieDB_Forever.toc","QuestieDB")
local db=metadata.loadAddon(package.."/QuestieDB_Forever.toc","QuestieDB",package)
local A={Navigation=dofile(root.."/tests/fixtures.lua").Navigation}
C_Map={GetMapInfo=function(id) return {mapID=id} end};C_QuestLog={}
for _,file in ipairs({"State.lua","Data/Content.lua","Data/TaskFacts.lua","Data/Questie.lua"}) do assert(loadfile(root.."/"..file))("AiLeveling",A) end
assert(A.Data:Connect(db))
local s={clientVersion="1.60.1",clientBuild="70862",interface=16001,faction=faction,quests={},completed={},bags={},position={map=1413,x=0.5,y=0.5}}
local observed=A.Data.ObservedObjectiveTarget
local function noObservation() end
local imported,checked,improved=0,0,0
for id,row in pairs(A.TaskFacts.cacheXP.quests) do
 local has=false
 for _,o in ipairs(row.objectives) do if o.locations then has=true;imported=imported+1 end end
 if has then
  local q=A.Data:GetQuest(id)
  if q then
   s.quests={}
   local descriptions,current=A.Data:ReferenceObjectiveTargets(q,s)
   A.Data.ObservedObjectiveTarget=noObservation
   local _,before=A.Data:ReferenceObjectiveTargets(q,s)
   A.Data.ObservedObjectiveTarget=observed
   for index,p in pairs(current) do
    checked=checked+1
    if p.sourceKind=="observation" then
     assert(p.approximate and (not before[index] or before[index].approximate))
     s.quests={[id]={objectives={}}}
     for i,o in ipairs(descriptions) do
      local c={};for k,v in pairs(o) do c[k]=v end;c.finished=i~=index;s.quests[id].objectives[i]=c
     end
     local actual=A.Data:Target(q,s)
     assert(actual and actual.sourceKind=="observation" and actual.objectiveIndex==index,id)
     assert(not s.completed[id] and not s.quests[id].ready)
     improved=improved+1;print("improved",id,q.title,index,actual.map,actual.x,actual.y)
    else
     local old=before[index];assert(old and old.map==p.map and old.x==p.x and old.y==p.y,id)
    end
   end
  end
 end
end
assert(imported==82)
print("SUMMARY",faction,class,imported,checked,improved)
assert(loadfile(root.."/QuestAssist.lua"))("AiLeveling",A)
local count=0
for id,facts in pairs(A.TaskFacts.cacheXP.quests) do
 if facts.itemUses then
  local q=assert(A.Data:GetQuest(id));s.quests={[id]={objectives={}}}
  local action={kind="objective",questId=id}
  local wanted=A.QuestAssist.Desired(action,s,true,A.Data)
  local seen={};for _,item in ipairs(wanted) do seen[item]=true end
  for item in pairs(facts.itemUses) do
   assert(seen[item],id..":"..item)
   local found
   for _,row in ipairs(A.QuestAssist.Requirements(action,s,A.Data)) do if row.id==item then found=row end end
   assert(found and found.kind=="use" and not found.countKnown)
   count=count+1;print("itemUse",id,q.title,item,found.target or "")
  end
  assert(not A.Data:DeliveryOnly(q,s))
  s.quests[id].ready=true;assert(#A.QuestAssist.Desired(action,s,true,A.Data)==0)
 end
end
assert(count==11)
print("ITEMS",faction,class,count)
