return function(test,eq,F,A,plan)
local function fixture()
    local B={};for k,v in pairs(A) do B[k]=v end
    for _,file in ipairs({"Planner/TaskGuide.lua","Planner/TaskQueue.lua","Planner/Planner.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    B.Navigation=F.Navigation
    local s=F.State();s.items={};s.quests[1]={title="旧任务",objectives={{text="未完成",numRequired=1,numFulfilled=0}}}
    local q=F.Quest(1);q.verified=false;q.questLevel=10
    q.taskFacts={level=10,xp={{1,1000},{20,100}},rewards={items={},choices={}}}
    local d=F.Data({[1]=q});d.chainIndex=A.Chains.NewIndex();A.Chains.IndexQuest(d.chainIndex,q,d)
    d.Target=function(_,quest) return {map=1,x=quest.id/10,y=0} end
    d.ObjectiveTargets=function() return {{map=1,x=0.1,y=0,objectiveIndex=1}} end
    d.ReferenceObjectiveTargets=function() return {{text="目标"}},{{map=1,x=0.2,y=0}},false end
    return B,s,q,d
end

test("完整规划按共用库存换序后同步当前交付和缺额提示",function()
    local B,s,q,d=fixture()
    assert(loadfile("Planner/Flights.lua"))("AiLeveling",B)
    s.position={map=1,x=0,y=0};s.maxXP=1000000;s.xp=0;s.bags={[2592]=60}
    B.Navigation={Distance=function(_,a,b) return math.abs(a.x-b.x)*700 end}
    q.questLevel=20;q.taskFacts={level=20,xp={{1,1000}},objectives={{kind="item",id=2592,count=60}}}
    local other=F.Quest(2);other.verified=false;other.questLevel=20
    other.taskFacts={level=20,xp={{1,10}},objectives=q.taskFacts.objectives}
    d.GetQuest=function(_,id) return id==1 and q or other end;d.Candidates=function() return {1,2} end
    d.Target=function(_,quest) return {map=1,x=quest.id==1 and 0.9 or 0.1,y=0,entityKind="npc",entityId=quest.id} end
    d.ObjectiveIdentities=function() return {{kind="item",id=2592}} end
    d.ObjectiveTargets=function() return {{map=1,x=1,y=0,objectiveIndex=1}} end
    for id=1,2 do s.quests[id]={ready=true,objectives={{type="item",text="毛料",numRequired=60,numFulfilled=60,finished=true}}} end
    local result=plan(s,d,nil,B)
    eq(result.taskChoices[1].questId,1)
    assert(result.taskQueue);eq(result.fallback.questId,2);eq(result.fallback.kind,"turnin")
    eq(result.taskOrder[1].itemShortage,nil);eq(result.taskOrder[2].itemShortage,true)
    assert(math.abs(result.taskQueue.seconds-110)<0.00001,result.taskQueue.seconds)
    eq(s.bags[2592],60);eq(s.quests[1].ready,true);eq(s.quests[2].ready,true)
end)
test("持有上限下缺少完整收集路线仍先交付而不等待整组",function()
    local B,s,q,d=fixture();assert(loadfile("Data/ItemLimits.lua"))("AiLeveling",B)
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    q.questLevel=20;q.taskFacts={level=20,xp={{1,1000}},objectives={{kind="item",id=18250,count=1}}}
    local other=F.Quest(2);other.verified=false;other.questLevel=20;other.taskFacts=q.taskFacts
    d.GetQuest=function(_,id) return id==1 and q or other end;d.Candidates=function() return {1,2} end
    d.Target=function() return {map=1,x=0.2,y=0,entityKind="npc",entityId=9} end
    d.ObjectiveIdentities=function() return {{kind="item",id=18250}} end
    d.ObjectiveTargets=function() return {} end
    s.bags={[18250]=1}
    for id=1,2 do s.quests[id]={ready=true,objectives={{type="item",text="物品",numRequired=1,numFulfilled=1,finished=true}}} end
    local result=plan(s,d,nil,B)
    eq(result.taskQueue,nil);eq(result.fallback.kind,"turnin")
    eq(B.TaskGuide.DeliveryGroups(result.taskChoices,s,result.taskOrder)[1].splitDelivery,true)
    s.locked=2;result=plan(s,d,nil,B);eq(result.fallback.kind,"turnin");eq(result.fallback.questId,2)
    eq(s.bags[18250],1);eq(s.quests[1].ready,true)
end)
test("低等级低经验无装备收益无任务关联才建议放弃",function()
    local B,s,q,d=fixture()
    local value=B.TaskGuide.LowValue(q,s,d);eq(value.xp,100);eq(value.suggestion,"建议放弃")
    s.quests={};eq(B.TaskGuide.LowValue(q,s,d).suggestion,"建议跳过")
    s.level=15;eq(B.TaskGuide.LowValue(q,s,d),nil)
    s.level=20;q.taskFacts.xp[2][2]=400;eq(B.TaskGuide.LowValue(q,s,d),nil)
    q.taskFacts.xp=nil;eq(B.TaskGuide.LowValue(q,s,d),nil)
end)
test("低收益前置后续关联和未知关系索引均保留",function()
    local B,s,q,d=fixture()
    local other=F.Quest(2);other.preQuestGroup={1};A.Chains.IndexQuest(d.chainIndex,other,d)
    eq(B.TaskGuide.LowValue(q,s,d),nil)
    d.chainIndex=A.Chains.NewIndex();q.preQuestSingle={3};A.Chains.IndexQuest(d.chainIndex,q,d)
    eq(B.TaskGuide.LowValue(q,s,d),nil)
    d.chainIndex=nil;eq(B.TaskGuide.LowValue(q,s,d),nil)
end)
test("已完成锁定职业法术和装备目标不建议放弃",function()
    local B,s,q,d=fixture()
    s.quests[1].ready=true;eq(B.TaskGuide.LowValue(q,s,d),nil);s.quests[1].ready=false
    s.locked=1;eq(B.TaskGuide.LowValue(q,s,d),nil);s.locked=nil
    s.itinerary={};eq(B.TaskGuide.LowValue(q,s,d),nil);s.itinerary=nil
    q.requiredClasses=1;eq(B.TaskGuide.LowValue(q,s,d),nil);q.requiredClasses=0
    q.taskFacts.rewards.spell=10;eq(B.TaskGuide.LowValue(q,s,d),nil);q.taskFacts.rewards.spell=nil
    d.content.gearSources={target={questId=1}};s.gearTarget="target";eq(B.TaskGuide.LowValue(q,s,d),nil)
end)
test("装备提升未知缓存特殊效果及武器资料缺失保护低等级任务",function()
    local B,s,q,d=fixture();B.Items=nil
    q.taskFacts.rewards.choices={{id=100,count=1}}
    eq(B.TaskGuide.LowValue(q,s,d),nil)
    local item={id=100,usable=true,equipLoc="INVTYPE_HEAD",stats={ITEM_MOD_STRENGTH_SHORT=1}}
    s.items[100]=item;s.equipment[1]={id=101,usable=true,equipLoc="INVTYPE_HEAD",stats={ITEM_MOD_STRENGTH_SHORT=2}}
    assert(B.TaskGuide.LowValue(q,s,d))
    item.stats.ITEM_MOD_STRENGTH_SHORT=3;eq(B.TaskGuide.LowValue(q,s,d),nil)
    item.stats.ITEM_MOD_STRENGTH_SHORT=1;item.pending=true;eq(B.TaskGuide.LowValue(q,s,d),nil);item.pending=nil
    item.useSpell=5;eq(B.TaskGuide.LowValue(q,s,d),nil);item.useSpell=nil
    item.equipLoc="INVTYPE_WEAPON";eq(B.TaskGuide.LowValue(q,s,d),nil)
end)
test("自动规划跳过低价值任务但保留列表与手动锁定",function()
    local B,s,q,d=fixture()
    local result=plan(s,d,nil,B)
    eq(result.fallback.kind,"taskReview");eq(#result.taskChoices,1);assert(result.taskChoices[1].lowValue)
    eq(s.quests[1].ready,nil);eq(s.completed[1],nil);eq(s.skipped[1],nil)
    s.locked=1;result=plan(s,d,nil,B);eq(result.fallback.questId,1);eq(result.taskChoices[1].lowValue,nil)
end)
test("低价值已接任务不会阻止推荐未接的有效任务",function()
    local B,s,q,d=fixture();local good=F.Quest(2);good.verified=false;good.questLevel=20
    good.taskFacts={level=20,xp={{1,1000}},rewards={}}
    d.GetQuest=function(_,id) return id==1 and q or good end;d.Candidates=function() return {1,2} end
    A.Chains.IndexQuest(d.chainIndex,good,d)
    local result=plan(s,d,nil,B);eq(result.fallback.questId,2);eq(result.fallback.kind,"accept")
    eq(result.taskChoices[2].questId,1);assert(result.taskChoices[2].lowValue)
end)
test("低价值任务不被整程重排重新提升到首位",function()
    local B,s,q,d=fixture()
    local low={questId=1,lowValue={suggestion="建议放弃"},actions={{position=s.position}}}
    local good={questId=2,actions={{position={map=1,x=0.9,y=0}}},stagesComplete=true,
        stages={{kind="turnin",position={map=1,x=0.9,y=0}}},remainingXP=1000}
    s.quests[2]={}
    local order=B.Planner.TaskOrder(s,{low,good},d);eq(order[1],good);eq(order[2],low)
end)
test("未灰但远处低经验任务降级，近处高经验和同级任务保留",function()
    local B,s,q,d=fixture();q.questLevel=17;q.taskFacts.level=17;q.taskFacts.xp={{1,1000}}
    local choice={timing={seconds=300}}
    local value=B.TaskGuide.LowValue(q,s,d,choice);assert(value.distant);eq(value.suggestion,"建议放弃")
    choice.timing.seconds=299;eq(B.TaskGuide.LowValue(q,s,d,choice),nil)
    choice.timing.seconds=nil;eq(B.TaskGuide.LowValue(q,s,d,choice),nil)
    choice.timing.seconds=600;q.taskFacts.xp={{1,4000}};eq(B.TaskGuide.LowValue(q,s,d,choice),nil)
    q.taskFacts.xp={{1,1000}};q.questLevel=19;q.taskFacts.level=19;eq(B.TaskGuide.LowValue(q,s,d,choice),nil)
    q.questLevel=17;q.taskFacts.level=17;s.quests={};eq(B.TaskGuide.LowValue(q,s,d,choice).suggestion,"建议跳过")
    s.maxXP=nil;eq(B.TaskGuide.LowValue(q,s,d,choice),nil)
end)
test("远处任务仍保护任务线装备收益职业和手动选择",function()
    local B,s,q,d=fixture();q.questLevel=17;q.taskFacts.level=17;q.taskFacts.xp={{1,1000}}
    local choice={timing={seconds=600}}
    s.locked=1;eq(B.TaskGuide.LowValue(q,s,d,choice),nil);s.locked=nil
    s.quests[1].ready=true;eq(B.TaskGuide.LowValue(q,s,d,choice),nil);s.quests[1].ready=false
    q.requiredClasses=1;eq(B.TaskGuide.LowValue(q,s,d,choice),nil);q.requiredClasses=0
    q.taskFacts.rewards.choices={{id=100}};B.Items=nil;eq(B.TaskGuide.LowValue(q,s,d,choice),nil)
    s.items[100]={id=100,usable=true,equipLoc="INVTYPE_HEAD",stats={ITEM_MOD_STRENGTH_SHORT=3}}
    s.equipment[1]={id=101,usable=true,equipLoc="INVTYPE_HEAD",stats={ITEM_MOD_STRENGTH_SHORT=1}}
    eq(B.TaskGuide.LowValue(q,s,d,choice),nil)
    q.taskFacts.rewards.choices={};local other=F.Quest(2);other.preQuestGroup={1};A.Chains.IndexQuest(d.chainIndex,other,d)
    eq(B.TaskGuide.LowValue(q,s,d,choice),nil)
end)
test("远处低收益目标含返程后退出自动推荐且不拖住同NPC交付",function()
    local B,s,q,d=fixture();q.questLevel=17;q.taskFacts.level=17;q.taskFacts.xp={{1,1000}}
    d.Target=function(_,quest,state)
        return {map=1,x=state.quests[quest.id] and not state.quests[quest.id].ready and 2 or 0,y=0,entityKind="npc",entityId=9}
    end
    d.ObjectiveTargets=function() return {{map=1,x=2,y=0,objectiveIndex=1}} end
    local result=plan(s,d,nil,B)
    eq(result.taskChoices[1].timing.seconds,400);assert(result.taskChoices[1].lowValue.distant)
    eq(result.fallback.kind,"taskReview");eq(s.skipped[1],nil)
    local good=F.Quest(2);good.verified=false;good.questLevel=20
    d.GetQuest=function(_,id) return id==1 and q or good end;d.Candidates=function() return {1,2} end
    s.quests[2]={ready=true,objectives={}}
    result=plan(s,d,nil,B);eq(result.fallback.questId,2);eq(result.fallback.kind,"turnin")
    local groups=B.TaskGuide.DeliveryGroups(result.taskChoices,s);eq(#groups,0)
    s.locked=1;result=plan(s,d,nil,B);eq(result.fallback.questId,1);eq(result.taskChoices[1].lowValue,nil)
end)
end
