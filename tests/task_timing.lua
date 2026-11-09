return function(test,eq,F,A)
local function timingFixture()
    local B={Travel=A.Travel,Observations=setmetatable({},{__index=function() error("排序不得读取执行或接交样本") end}),
        Estimates=setmetatable({},{__index=function() error("排序不得读取执行或掉率模型") end}),
        Navigation={Distance=function(_,a,b) if a and b and a.map==b.map then return math.abs(a.x-b.x) end end}}
    assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    assert(loadfile("Planner/Planner.lua"))("AiLeveling",B)
    local s={position={map=1,x=0},runSpeed=7,mode="fast",quests={[1]={},[2]={}}}
    local choices={
        {questId=1,remainingXP=850,actions={{position={map=1,x=70}}},stagesComplete=true,
            work={missing=99,seconds=99999},stages={{kind="objective",questId=1,position={map=1,x=70}},
                {kind="turnin",questId=1,position={map=1,x=140}}}},
        {questId=2,remainingXP=12,actions={{position={map=1,x=7}}},stagesComplete=true,
            stages={{kind="turnin",questId=2,position={map=1,x=7}}}}}
    return B,s,choices
end


test("移动估时不依赖执行样本掉率或任务数量且不伪报总完成时间",function()
    local B,s,choices=timingFixture()
    local t=B.TaskGuide.Timing(s.position,choices[1],s,B.Navigation)
    eq(t.travel,20);eq(t.seconds,20);eq(t.low,20);eq(t.high,20)
    eq(t.movementOnly,true);eq(t.work,nil);eq(t.talk,nil);eq(t.turninRate,nil)
    s.runSpeed=nil;eq(B.TaskGuide.Timing(s.position,choices[1],s,B.Navigation).seconds,nil)
    s.runSpeed=14;eq(B.TaskGuide.Timing(s.position,choices[1],s,B.Navigation).seconds,10)
    s.dead=true;eq(B.TaskGuide.Timing(s.position,choices[1],s,B.Navigation).seconds,nil)
    s.dead=false;choices[1].stagesComplete=false
    eq(B.TaskGuide.Timing(s.position,choices[1],s,B.Navigation).seconds,nil)
end)


test("移动时间接近时继续当前任务且明显减少跑路才切换",function()
    local B,s,choices=timingFixture();s.currentTask=1
    choices[1].remainingXP=12;choices[2].remainingXP=12
    choices[1].stages={{kind="turnin",position={map=1,x=7.5}}}
    local order=B.Planner.TaskOrder(s,choices);eq(order[1].questId,1);eq(order[1].orderHeld,true)
    choices[1].stages[1].position.x=70
    order=B.Planner.TaskOrder(s,choices);eq(order[1].questId,2)
end)
test("经验移动比处理同路程同经验零移动零经验与缺失经验",function()
    local B,s,c=timingFixture()
    c[1].stages={{kind="turnin",position={map=1,x=7}}}
    eq(B.Planner.TaskOrder(s,c)[1].questId,1)
    c[1].remainingXP=12;c[1].stages[1].position.x=70
    eq(B.Planner.TaskOrder(s,c)[1].questId,2)
    c[1].stages[1].position.x=0
    eq(B.Planner.TaskOrder(s,c)[1].questId,1)
    eq(B.TaskGuide.MovementRate(0,12),math.huge);eq(B.TaskGuide.MovementRate(0,0),0)
    c[1].remainingXP=0;eq(B.Planner.TaskOrder(s,c)[1].questId,2)
    c[2].remainingXP=0;eq(B.Planner.TaskOrder(s,c)[1].questId,1)
    c[1].remainingXP=nil;c[1].stages[1].position.x=70
    local order=B.Planner.TaskOrder(s,c);eq(#order,2);eq(order[1].questId,2);eq(order[1].orderBasis,"movement-time")
end)


test("同状态含未知经验时按移动排序且保留手动和已接任务",function()
    local B,s=timingFixture();s.quests={};s.level=20
    B.Eligibility={Check=function() return true end};B.Progression={Advance=function() return {} end}
    local quests={
        {id=1,questLevel=20,taskFacts={level=20,xp={{1,100}}}},
        {id=2,questLevel=20,taskFacts={level=20,xp={{1,1000}}}},
        {id=3,questLevel=20}, {id=4,questLevel=20}}
    local data={content={},GetQuest=function(_,id) return quests[id] end,
        Target=function(_,q) return {map=1,x=q.id==3 and 0 or q.id*7} end,
        ReferenceObjectiveTargets=function(_,q) return {{text="目标"}},{{map=1,x=q.id==3 and 0 or q.id*7}},false end}
    for _,ids in ipairs({{1,2,3,4},{4,3,2,1},{3,1,4,2}}) do
        local c=B.Planner.TaskChoices(s,data,ids)
        eq(#c,4);eq(c[1].questId,3);eq(c[2].questId,1)
        eq(c[3].questId,2);eq(c[4].questId,4);eq(c[1].remainingXP,nil)
    end
    quests[1].taskFacts.xp={{1,0}};quests[2].taskFacts.xp={{1,0}}
    local zero=B.Planner.TaskChoices(s,data,{1,2,3});eq(zero[1].questId,3)
    local c=B.Planner.TaskChoices(s,data,{3,4});eq(c[1].questId,3);eq(#c,2)
    s.locked=3;c=B.Planner.TaskChoices(s,data,{1,2,3});eq(c[1].questId,3)
    s.locked=nil;s.quests[3]={objectives={}}
    c=B.Planner.TaskChoices(s,data,{1,2,3});eq(c[1].questId,3);eq(c[1].status,"objective")
end)

test("原生速度读取保留站立时跑速并拒绝不可访问及无效值",function()
    local oldSpeed,oldAccess=GetUnitSpeed,canaccessvalue
    GetUnitSpeed=function() return 0,14,20,4 end
    local s={};A.State.Movement(s);eq(s.runSpeed,14);eq(s.swimSpeed,4)
    canaccessvalue=function(value) return value~=14 end
    s={};A.State.Movement(s);eq(s.runSpeed,nil);eq(s.swimSpeed,4)
    GetUnitSpeed=function() return 0,0,0,0/0 end
    s={};A.State.Movement(s);eq(s.runSpeed,nil);eq(s.swimSpeed,nil)
    GetUnitSpeed,canaccessvalue=oldSpeed,oldAccess
end)

end
