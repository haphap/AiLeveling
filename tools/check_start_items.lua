local root=assert(arg[1])
local A=dofile(root.."/tools/quest_runtime.lua")
local faction,class=arg[3],arg[4]

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
