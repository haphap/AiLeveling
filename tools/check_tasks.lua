-- Actual pinned release API; map availability is stubbed, client operation is tested separately.
local root,package,faction=assert(arg[1]),assert(arg[2]),assert(arg[3])
local client,metadata=dofile("emulator/client.lua"),dofile("emulator/metadata.lua")
client.install({expansion="Forever",faction=faction,classFile="WARRIOR",locale="zhCN"})
metadata.load(package.."/QuestieDB_Forever.toc","QuestieDB")
local db=metadata.loadAddon(package.."/QuestieDB_Forever.toc","QuestieDB",package)
local A={Navigation={Distance=function(_,a,b)
    if a and b and a.map==b.map then return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
end}}
C_Map={GetMapInfo=function(id) return {mapID=id} end}
C_QuestLog={}
for _,file in ipairs({"State.lua","Data/Content.lua","Data/Questie.lua","Planner/Chains.lua","Planner/Eligibility.lua","Planner/Planner.lua"}) do
    assert(loadfile(root.."/"..file))("AiLeveling",A)
end
assert(A.Data:Connect(db))
local function run(fn)
    local co=coroutine.create(fn)
    while true do
        local ok,result=coroutine.resume(co);assert(ok,result)
        if coroutine.status(co)=="dead" then return result end
    end
end
run(function() A.Data:BuildIndex() end)
local s={revision=1,level=1,quests={},completed={},skipped={},completionKnown=true,
    raceMask=db.Enum.raceMaskById[faction=="Alliance" and 1 or 2],classMask=db.Enum.classKeys.WARRIOR,
    faction=faction,skills={},reputations={},spells={},specializations={},
    position={map=faction=="Alliance" and 1429 or 1411,x=0.5,y=0.5}}
local choices=run(function() return A.Planner.TaskChoices(s,A.Data,A.Data:Candidates(s)) end)
assert(#choices>0,"new level-one character has no task choices")
print(faction.." level 1: "..#choices.." actual database task choices")
for i,c in ipairs(choices) do
    assert(c.status=="accept" and not c.rate and not c.seconds and c.actions[1].position.map==s.position.map)
    if i<=5 then print(c.questId.." "..c.title) end
end
local id=faction=="Alliance" and 7 or 788
local rows=db.Quest.Get(id,"objectives")
local name=db.Npc.Get(rows[1][1][1],"name")
s.quests[id]={title=A.Data:GetQuest(id).title,objectives={{text=name.." 0/1",finished=false}}}
local target=assert(A.Data:Target({id=id},s),"actual accepted objective could not be located without native waypoint")
print("active objective "..id..": map "..target.map.." "..target.label)
local quest=A.Data:GetQuest(id)
local points=A.Data.EntityPoints
A.Data.EntityPoints=function() return {} end
local fallback=assert(A.Data:Target(quest,s))
assert(fallback.approximate and fallback.map==s.position.map and fallback.x==0.5 and fallback.y==0.5)
s.quests[id].ready=true
local delivery=assert(A.Data:Target(quest,s))
assert(delivery.approximate and delivery.entityId==db.Quest.Get(id,"finishedBy")[1][1])
A.Data.EntityPoints=points
assert(not A.Data:Target(quest,s).approximate)
print("area fallback "..id..": objective and recipient center, precise location restored")

-- Real area-only source and mixed outdoor/instance alternatives.
local function objective(qid,itemId)
    local quest=A.Data:GetQuest(qid)
    assert(quest,"missing reference quest")
    s.quests[qid]={objectives={{text="source check",targetKind="item",targetId=itemId,finished=false}}}
    return quest,assert(A.Data:Target(quest,s))
end
local q,point=objective(166,3637)
assert(point.approximate and point.map==A.Data.maps[1581] and point.entityId==639)
assert(point.targetKind=="item" and point.targetId==3637 and point.objectiveIndex==1)
assert(not s.quests[166].objectives[1].finished)
assert(#A.Data:EntityPoints(db.Npc,639)==0,"area marker must not become a service location")
local oldZone=q.zoneOrSort;q.zoneOrSort=-61
assert(A.Data:Target(q,s).map==A.Data.maps[1581]);q.zoneOrSort=oldZone
C_QuestLog.GetNextWaypoint=function() return 1429,0.2,0.3 end
assert(A.Data:Target(q,s).label=="客户端任务目标")
C_QuestLog.GetNextWaypoint=nil
local _,mixed=objective(214,915)
assert(not mixed.approximate and mixed.map==A.Data.maps[40])
print("real sources: VanCleef area center, native priority, red silk outdoor alternative, identities preserved")
