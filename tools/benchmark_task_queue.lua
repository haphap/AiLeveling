-- Synthetic queue benchmark; actual client frame performance is measured separately.
local A={}
for _,path in ipairs({"Planner/Travel.lua","Planner/TaskGuide.lua","Planner/Flights.lua","Planner/TaskQueue.lua","Planner/Progression.lua"}) do
    assert(loadfile(path))("AiLeveling",A)
end
local F=dofile("tests/fixtures.lua")
local s=F.State();s.money=1000;s.now=0
local order={}
for id=1,25 do
    s.quests[id]={}
    order[id]={questId=id,stagesComplete=true,remainingXP=100,
        stages={{kind="objective",questId=id,position={map=1,x=0.2+id/100,y=0}},
            {kind="turnin",questId=id,position={map=1,x=0,y=0,entityKind="npc",entityId=900}}}}
end
local start=os.clock();local resumes,longest=0,0
local co=coroutine.create(function()
    local tasks,queue=A.TaskQueue.Solve(order,s,F.Navigation)
    assert(#tasks==25 and queue.taskCount==25 and queue.xp==2500)
    local sequence={}
    for index,step in ipairs(queue.steps) do
        assert(step.stage.kind==(index<=25 and "objective" or "turnin"))
        local id=step.choice.questId
        sequence[id]=(sequence[id] or 0)+1
        assert(step.stage==order[id].stages[sequence[id]])
    end
    for id=1,25 do assert(sequence[id]==2) end
    print(string.format("25 tasks / 50 stages: %.1f movement seconds, %.0f XP, interleaved=%s",queue.seconds,queue.xp,tostring(queue.stagePlan)))
end)
repeat
    local t=os.clock();local ok,err=coroutine.resume(co);assert(ok,err)
    longest=math.max(longest,os.clock()-t);resumes=resumes+1
until coroutine.status(co)=="dead"
print(string.format("CPU %.1f ms; resumes %d; longest resume %.2f ms",(os.clock()-start)*1000,resumes,longest*1000))
