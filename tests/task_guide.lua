return function(test,eq,F,A,plan)
local function fixture()
    local B={UI={ActionText=function() return "" end},Navigation={Distance=function(_,a,b)
        if a and b and a.map==b.map then return math.abs(a.x-b.x) end
    end}}
    B.Travel=A.Travel;assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    local s=F.State();s.position={map=1,x=0};s.quests[1]={objectives={
        {text="已完成目标",finished=true},{text="剩余目标",numFulfilled=1,numRequired=3}}}
    local data={Target=function(_,q,state) if state.quests[q.id].ready then return {map=1,x=90} end end,
        ObjectiveTargets=function() return {{map=1,x=10,objectiveIndex=2}} end,
        ReferenceObjectiveTargets=function() return {{text="目标 NPC",targetKind="npc",targetId=6}},{{map=1,x=10}},false end}
    local q={id=1,title="参考任务",questLevel=10,taskFacts={level=10,xp={{1,1000},{16,800},{20,100}},
        objectives={{kind="npc",id=6,count=10}}}}
    return B,s,data,q
end
test("已完成物品仍保留原生需求与补收集位置且不改变真实日志",function()
    local B,s,data,q=fixture()
    s.quests[1]={ready=true,objectives={{type="item",text="物品",finished=true,numRequired=7,numFulfilled=7}}}
    data.ObjectiveIdentities=function(_,_,context)
        eq(context.quests[1].ready,false);eq(context.quests[1].objectives[1].finished,false)
        return {{kind="item",id=88}}
    end
    data.ObjectiveTargets=function() return {} end
    data.UnmappedTargetArea=function() return 100 end
    data.AreaTarget=function() return {map=1,x=0.5} end
    local stages=B.TaskGuide.Stages(q,s,data,{kind="turnin",questId=1,position={map=1,x=90}})
    local r=stages[1].itemRequirements[1]
    eq(#stages,1);eq(r.need,7);eq(r.targetId,88);eq(r.areaId,100);eq(r.position,nil);eq(r.objectiveIndex,1)
    eq(s.quests[1].ready,true);eq(s.quests[1].objectives[1].finished,true)
    s.quests[1].objectives[1].numRequired=nil
    eq(#B.TaskGuide.ItemRequirements(q,s,data),0)
end)
test("未接任务预览接取目标交付且未来目标不伪装原生日志索引",function()
    local B,s,data,q=fixture();s.quests={}
    local reference,calls=data.ReferenceObjectiveTargets,0
    data.ReferenceObjectiveTargets=function(...) calls=calls+1;return reference(...) end
    local stages,complete=B.TaskGuide.Stages(q,s,data,{kind="accept",position={map=1,x=1}})
    eq(#stages,3);eq(stages[1].kind,"accept");eq(stages[2].need,10)
    eq(stages[2].objectiveIndex,nil);eq(stages[2].expected,true);eq(stages[3].position.x,90)
    eq(complete,true);eq(s.quests[1],nil);eq(calls,1)
end)
test("缺失目标位置保留未知但事件标记不阻断已知位置的移动规划",function()
    local B,s,data,q=fixture();s.quests={}
    data.ReferenceObjectiveTargets=function() return {},{},true end
    local _,complete=B.TaskGuide.Stages(q,s,data,{kind="accept",position={map=1,x=1}});eq(complete,false)
    B,s,data,q=fixture();q.specialFlags=2
    _,complete=B.TaskGuide.Stages(q,s,data,{kind="objective",objectiveIndex=2,position={map=1,x=10}});eq(complete,true)
end)
test("等级经验按分段来源读取且等级修正不匹配时保留未知",function()
    local B,_,_,q=fixture()
    eq(B.TaskGuide.XP(q,10),1000);eq(B.TaskGuide.XP(q,16),800);eq(B.TaskGuide.XP(q,59),100)
    eq(B.TaskGuide.XP(q,60),nil);q.questLevel=11;eq(B.TaskGuide.XP(q,10),nil)
    q.questLevel,q.taskFacts.level=nil,nil;eq(B.TaskGuide.XP(q,10),nil)
    q.questLevel,q.taskFacts,q.referenceXPLevel,q.referenceXP=10,nil,10,1000
    eq(B.TaskGuide.XP(q,10),1000);eq(B.TaskGuide.XP(q,15),1000);eq(B.TaskGuide.XP(q,16),800)
    eq(B.TaskGuide.XP(q,20),100);eq(B.TaskGuide.XP(q,60),nil)
    q.referenceXP=335;eq(B.TaskGuide.XP(q,10),340);eq(B.TaskGuide.XP(q,16),270)
    q.referenceXP=0;eq(B.TaskGuide.XP(q,10),0)
    q.referenceXPLevel=11;eq(B.TaskGuide.XP(q,10),nil)
    q.referenceXPLevel=10;q.referenceXP=2000;q.taskFacts={level=10,xp={{1,1000}}}
    eq(B.TaskGuide.XP(q,10),1000)
end)
test("服务器缓存经验按构建与任务等级启用且原生奖励优先",function()
    local B,s,_,q=fixture()
    B.TaskFacts={cacheXP={version="1.60.1",build="70862",interface=16001,
        quests={[1]={level=10,xp={{1,1500},{16,1200},{20,150}}}}}}
    eq(B.TaskGuide.XP(q,10,s),1000)
    s.clientVersion,s.clientBuild,s.interface="1.60.1",70862,16001
    eq(B.TaskGuide.XP(q,10,s),1500);eq(B.TaskGuide.XP(q,16,s),1200)
    s.quests[1].rewardXP,s.quests[1].rewardXPLevel=1700,10
    eq(B.TaskGuide.XP(q,10,s),1700);eq(B.TaskGuide.XP(q,11,s),1500)
    q.questLevel=11;eq(B.TaskGuide.XP(q,11,s),nil)
    q.questLevel=10;s.clientVersion="other";eq(B.TaskGuide.XP(q,11,s),1000)
    q.taskFacts=nil;eq(B.TaskGuide.XP(q,11,s),nil)
    s.clientVersion="1.60.1";s.clientBuild="70862";eq(B.TaskGuide.XP(q,11,s),1500)
    eq(B.TaskGuide.XP(q,60,s),nil)
    q.questLevel=-1;eq(B.TaskGuide.XP(q,20,s),nil)
end)
test("缓存经验补齐后进入任务收益排序与低价值保护",function()
    local B={};for k,v in pairs(A) do B[k]=v end
    for _,file in ipairs({"Planner/TaskGuide.lua","Planner/TaskQueue.lua","Planner/Planner.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    local s=F.State();s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    s.quests={};s.position={map=1,x=0,y=0}
    local q1,q2=F.Quest(1),F.Quest(2)
    q1.verified,q2.verified=false,false;q1.questLevel,q2.questLevel=20,20
    local d=F.Data({[1]=q1,[2]=q2})
    d.Target=function(_,q) return {map=1,x=q.id/10,y=0} end
    d.ReferenceObjectiveTargets=function(_,q) return {{text="目标"}},{{map=1,x=q.id/10,y=0}},false end
    B.TaskFacts={cacheXP={version="1.60.1",build="70862",interface=16001,
        quests={[1]={level=20,xp={{1,100}}},[2]={level=20,xp={{1,2000}}}}}}
    local p=plan(s,d,nil,B);eq(p.fallback.questId,2)
    eq(q1.taskFacts,nil);eq(B.TaskGuide.LowValue(q1,s,d,p.taskChoices[2]),nil)
    s.clientVersion="other";p=plan(s,d,nil,B);eq(p.fallback.questId,1)
    q1.referenceXPLevel,q1.referenceXP=20,100;q2.referenceXPLevel,q2.referenceXP=20,2000
    p=plan(s,d,nil,B);eq(p.fallback.questId,2)
    q2.referenceXPLevel=21;p=plan(s,d,nil,B);eq(p.fallback.questId,1)
end)
test("节日退役参考任务不抢占自动首选但实际日志和明确锁定保留",function()
    local s=F.State();s.position={map=1,x=0};local q1,q2=F.Quest(1),F.Quest(2)
    q1.verified,q2.verified=false,false;q1.taskFacts={hidden="seasonal"}
    local d=F.Data({[1]=q1,[2]=q2});d.Target=function() return {map=1,x=1} end
    local p=plan(s,d);eq(p.fallback.questId,2)
    s.locked=1;p=plan(s,d);eq(p.fallback.questId,1)
    s.locked=nil;s.quests[1]={objectives={}};p=plan(s,d);eq(p.taskChoices[1].requireCheck,nil)
    s.quests={};q1.taskFacts=nil
    d.CacheQuest=function(_,q) if q.id==1 then return {hidden="unconfirmed"} end end
    d.Target=function() return {map=1,x=1,entityKind="npc",entityId=8} end
    p=plan(s,d);eq(p.fallback.questId,2)
    s.questOffers={[8]={[1]=true}};p=plan(s,d);eq(p.fallback.questId,1)
end)
end
