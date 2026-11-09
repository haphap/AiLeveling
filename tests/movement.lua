return function(test,eq,F,A,plan)
test("700码按7码每秒估为100秒且道路资料完全不参与",function()
    local nav={Distance=function() return 700 end}
    local B={Travel=A.Travel,Roads=setmetatable({},{__index=function() error("不应读取道路") end})}
    assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    local s={runSpeed=7}
    local choice={stagesComplete=true,stages={{kind="objective",position={map=1,x=1,y=0}}},
        work={seconds=20,low=20,high=20,missing=0},remainingXP=240}
    local t=B.TaskGuide.Timing({map=1,x=0,y=0},choice,s,nav)
    eq(t.travel,100);eq(t.seconds,100);eq(t.turninRate,nil);eq(t.coarse,true)
    s.runSpeed=14;eq(B.TaskGuide.Timing({map=1,x=0,y=0},choice,s,nav).travel,50)
end)
test("速度或跨世界距离未知时保留未知而原地移动为零",function()
    local p,q={map=1,x=0,y=0},{map=2,x=0,y=0}
    eq(A.Travel.Walk(p,p,{}),0)
    for _,speed in ipairs({0,-1,math.huge,0/0}) do
        eq(A.Travel.Walk(p,q,{runSpeed=speed},{Distance=function() return 700 end}),nil)
    end
    eq(A.Travel.Walk(p,q,{runSpeed=7},{Distance=function() return nil end}),nil)
end)
test("同世界跨地图仍用地图库直线距离估算",function()
    local p,q={map=1,x=0,y=0},{map=2,x=0.5,y=0.5}
    eq(A.Travel.Walk(p,q,{runSpeed=7},{Distance=function() return 1400 end}),200)
end)
test("耗时未知时相邻区域的近任务仍按直线距离排序",function()
    local B={Navigation={Distance=function(_,a,b)
        if a.map==3 or b.map==3 then return end
        return math.abs(a.x-b.x)*1000
    end},Travel=A.Travel}
    assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    assert(loadfile("Planner/Planner.lua"))("AiLeveling",B)
    local s=F.State();s.position={map=1,x=0,y=0};s.quests={[1]={},[2]={},[3]={}}
    local function choice(id,map,x)
        local p={map=map,x=x,y=0}
        return {questId=id,actions={{position=p}},stages={{position=p}},stagesComplete=true,work={missing=1}}
    end
    local far,near,other=choice(1,1,0.8),choice(2,2,0.1),choice(3,3,0.01)
    for _,mode in ipairs({"fast","relaxed","story"}) do
        s.mode=mode
        local order=B.Planner.TaskOrder(s,{far,other,near})
        eq(order[1],near);eq(order[2],far);eq(order[3],other)
        eq(order[1].orderBasis,"movement-time")
        near.stagesComplete=false
        order=B.Planner.TaskOrder(s,{far,other,near})
        eq(order[1],near);eq(order[1].orderBasis,"geometry")
        near.stagesComplete=true
    end
    s.locked=1;eq(B.Planner.TaskOrder(s,{far,other,near})[1],far)
end)
test("当前位置未接入任何命名节点时仍可直线前往目的地",function()
    local d,s=F.Data({}),F.State()
    local origin={map=1,x=0.1,y=0}
    local r=A.Travel.Route(d.content,origin,"goal",s)
    eq(r.seconds,10);eq(r.actions[1].position,d.content.nodes.goal.position)
    eq(r.actions[1].fromPosition,origin)
end)
test("道路模块和资料退出游戏加载与打包入口",function()
    local f=assert(io.open("AiLeveling.toc"));local toc=f:read("*a");f:close()
    assert(not toc:find("Roads.lua",1,true))
end)
end
