local root=assert(arg[1])
local A,db=dofile(root.."/tools/quest_runtime.lua")
local faction=arg[3]

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
