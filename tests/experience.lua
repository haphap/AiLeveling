return function(test,eq,F,A,plan)
local function state(level)
    local s=F.State();s.level=level or 1;s.xp=0;s.maxXP=A.Experience.xpToLevel[s.level]
    s.clientVersion="1.60.1";s.clientBuild="70862";s.interface=16001
    return s
end
test("当前构建参考升级表覆盖所有门槛且逐级和整程抵达六十级",function()
    local count,total=0,0
    for level,xp in pairs(A.Experience.xpToLevel) do count=count+1;total=total+xp;assert(level>=1 and level<60 and xp>0) end
    eq(count,59);eq(total,4084700);eq(A.Experience.xpToLevel[1],400);eq(A.Experience.xpToLevel[20],23200)
    for level=1,59 do
        local s=state(level);s.xp=s.maxXP-1
        local after=A.Progression.Advance(s,1,{})
        eq(after.level,level+1);eq(after.xp,0);eq(after.maxXP,A.Experience.xpToLevel[level+1] or 0)
        eq(after.uncertain,nil);eq(after.curveSource,A.Experience.source);eq(s.level,level);eq(s.xp,s.maxXP-1)
    end
    local after=A.Progression.Advance(state(),total,{})
    eq(after.level,60);eq(after.xp,0);eq(after.maxXP,0)
    after=A.Progression.Advance({level=60},100000,{});eq(after.level,60);eq(after.maxXP,0)
end)
test("版本构建接口或原生门槛不匹配时拒绝参考表但保留当前原生门槛",function()
    for _,change in ipairs({function(s) s.clientVersion="1.60.2" end,function(s) s.clientBuild="70532" end,
        function(s) s.interface=11508 end,function(s) s.maxXP=500 end,function(s) s.clientBuild=nil end}) do
        local s=state();change(s);s.xp=s.maxXP-1
        local curve=A.Progression.Curve(s,{});eq(curve,nil)
        local after=A.Progression.Advance(s,901,{})
        eq(after.level,2);eq(after.xp,900);eq(after.uncertain,true);eq(after.curveSource,nil)
    end
    local s=state();s.clientBuild="other";s.xp=399
    local after=A.Progression.Advance(s,901,{progression={verified=true,xpToLevel={[2]=900,[3]=1400}}})
    eq(after.level,3);eq(after.xp,0);eq(after.maxXP,1400);eq(after.curveSource,"authored")
end)
test("预测跨多个等级按每一级门槛扣除且精确边界与未知状态不误推进",function()
    local s=state();s.xp=399
    local after=A.Progression.Advance(s,1+900+1400+50,{})
    eq(after.level,4);eq(after.xp,50);eq(after.maxXP,2100)
    s.xpUncertain=true;after=A.Progression.Advance(s,10000,{})
    eq(after.level,1);eq(after.uncertain,true)
    s=state(59);after=A.Progression.Advance(s,s.maxXP+10000,{})
    eq(after.level,60);eq(after.xp,0)
end)
test("真实参考曲线贯通交付升级资格与后续经验计算且不改实际任务事实",function()
    local s=state();s.xp=399
    local q1,q2=F.Quest(1),F.Quest(2)
    q1.xp=1;q2.xp={[1]=1,[2]=1000};q2.requiredLevel=2;q2.preQuestGroup={1}
    local result=plan(s,F.Data({[1]=q1,[2]=q2}))
    eq(result.best.xp,1001);eq(result.best.forecast.level,3);eq(result.best.forecast.xp,100)
    eq(result.best.forecast.curveSource,A.Experience.source)
    eq(s.level,1);eq(s.xp,399);eq(next(s.completed),nil);eq(next(s.quests),nil)
    s.clientBuild="other";result=plan(s,F.Data({[1]=q1,[2]=q2}))
    eq(result.best.xp,1001);eq(result.best.forecast.level,2);eq(result.best.forecast.maxXP,nil);eq(result.best.forecast.uncertain,true)
end)
test("任务预览保留交付等级预测与原生状态且隐藏内部来源说明",function()
    local B={};for k,v in pairs(A) do B[k]=v end
    assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B);assert(loadfile("Planner/Planner.lua"))("AiLeveling",B)
    B.Navigation={Distance=function() return 1 end};B.Roads=nil
    local s=state();s.xp=399;s.position={map=1,x=0,y=0};s.quests[1]={title="实际日志任务",ready=true,objectives={}}
    local q=F.Quest(1);q.questLevel=1;q.taskFacts={level=1,xp={{1,170}},objectives={}}
    local d=F.Data({[1]=q});d.Target=function() return {map=1,x=0.1,y=0} end
    local result=plan(s,d,{minutes=60,mode="relaxed",dungeons=false},B)
    local choice=result.taskChoices[1]
    eq(choice.remainingXP,170);eq(choice.forecast.level,2);eq(choice.forecast.xp,169);eq(choice.forecast.maxXP,900)
    eq(s.completed[1],nil);eq(s.quests[1].ready,true)
    B.UI={};B.Navigation.Current=function() end
    assert(loadfile("UI/Main.lua"))("AiLeveling",B)
    assert(loadfile("UI/Plan.lua"))("AiLeveling",B)
    B.char={};B.plan=result;B.state=s;B.UI.Plan.preview=choice
    local text=table.concat(B.UI.Plan:Lines(),"\n")
    assert(text:find("交付后：2 级",1,true));assert(not text:find("当前构建客户端参考表",1,true))
    choice.forecast={level=2,xp=0};text=table.concat(B.UI.Plan:Lines(),"\n")
    assert(text:find("交付后：2 级",1,true));assert(not text:find("后续经验门槛待核对",1,true));assert(not text:find("0 / 0",1,true))
end)
end
