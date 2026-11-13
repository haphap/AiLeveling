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
    s.locked=nil;s.quests={};q.repeatable=true
    q.taskFacts={level=20,complex=false,objectives={},rewards={items={{id=18250,count=1}},choices={}}}
    d.DeliveryOnly=function() return true end
    result=plan(s,d,nil,B);eq(result.fallback.questId,2)
    assert(B.TaskGuide.LowValue(q,s,d));eq(s.bags[18250],1)
    local higher=F.Quest(3);higher.verified=false;higher.questLevel=20
    higher.taskFacts={level=20,xp={{1,10000}},objectives={}}
    local get=d.GetQuest;d.GetQuest=function(self,id) return id==3 and higher or get(self,id) end
    d.Candidates=function() return {1,2,3} end
    eq(plan(s,d,nil,B).fallback.questId,3)
    s.locked=1;eq(plan(s,d,nil,B).fallback.questId,1);s.locked=nil
    s.quests[1]={ready=true,objectives={}};eq(B.TaskGuide.LowValue(q,s,d),nil);s.quests={}
    s.bags[18250]=0;eq(B.TaskGuide.LowValue(q,s,d),nil);s.bags[18250]=1
    q.taskFacts.rewards.choices={{id=18250,count=1}};eq(B.TaskGuide.LowValue(q,s,d),nil)
    q.taskFacts.rewards.choices={};s.clientVersion="other";eq(B.TaskGuide.LowValue(q,s,d),nil)
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
    q.requiredClasses=1;eq(B.TaskGuide.LowValue(q,s,d),nil);q.requiredClasses=0
    q.taskFacts.rewards.spell=10;eq(B.TaskGuide.LowValue(q,s,d),nil);q.taskFacts.rewards.spell=nil
    B.Gear={GetSource=function(id) if id=="target" then return {questId=1} end end};s.gearTarget="target";eq(B.TaskGuide.LowValue(q,s,d),nil)
end)
test("关键职业能力与坐骑从可接前置优先接续并尊重已学会和手动选择",function()
    local B,s,q,d=fixture();assert(loadfile("Planner/Flights.lua"))("AiLeveling",B)
    s.level,s.spells,s.currentTask=9,{},1;q.taskFacts.xp={{1,1000}}
    local pre,reward=F.Quest(2),F.Quest(3)
    pre.requiredLevel,reward.requiredLevel=10,10
    pre.requiredClasses,reward.requiredClasses=1,1
    reward.preQuestGroup={2};reward.taskFacts={level=10,xp={{1,10}},learnedSpells={355,71}}
    pre.taskFacts={level=10,xp={{1,10}}}
    local quests={[1]=q,[2]=pre,[3]=reward}
    d.GetQuest=function(_,id) return quests[id] end;d.Candidates=function() return {1,2,3} end
    A.Chains.IndexQuest(d.chainIndex,pre,d);A.Chains.IndexQuest(d.chainIndex,reward,d)
    eq(plan(s,d,nil,B).fallback.questId,1)
    s.level=10
    local result=plan(s,d,nil,B)
    eq(result.fallback.questId,2);eq(result.fallback.kind,"accept");eq(result.taskOrder[1].questId,2)
    eq(result.taskChoices[1].unlock.questId,3);eq(s.locked,nil);eq(s.completed[2],nil)
    if result.taskQueue then eq(result.taskQueue.steps[1].choice.questId,2) end
    -- A class unlock on another continent must not displace local work or pickups.
    local target,objectives,reference,candidates=d.Target,d.ObjectiveTargets,d.ReferenceObjectiveTargets,d.Candidates
    local nearby=F.Quest(4);nearby.questLevel=10;nearby.taskFacts={level=10,xp={{1,1000}}};quests[4]=nearby
    d.Candidates=function() return {1,2,3,4} end
    d.Target=function(self,quest,context)
        local p=target(self,quest,context);p.map=quest.id==4 and 1 or 2;return p
    end
    d.ObjectiveTargets=function(self,quest) local p=self:Target(quest);p.objectiveIndex=1;return {p} end
    d.ReferenceObjectiveTargets=function(self,quest) return {{text="本地目标"}},{self:Target(quest)},false end
    s.quests[4]={objectives={{text="本地目标",numRequired=1,numFulfilled=0}}}
    result=plan(s,d,nil,B);eq(result.fallback.questId,4)
    for _,c in ipairs(result.taskChoices) do if c.questId==2 then assert(c.unlock);eq(c.unlockPriority,nil) end end
    s.quests[4]=nil
    result=plan(s,d,nil,B);eq(result.fallback.questId,4);eq(result.fallback.kind,"accept")
    eq(result.taskQueue.remaining,1);eq(s.quests[4],nil);eq(s.skipped[1],nil)
    s.locked=2;eq(plan(s,d,nil,B).fallback.questId,2);s.locked=nil
    quests[4]=nil;d.Target,d.ObjectiveTargets,d.ReferenceObjectiveTargets,d.Candidates=target,objectives,reference,candidates
    s.locked=1;eq(plan(s,d,nil,B).fallback.questId,1);s.locked=nil
    s.skipped[2]=true;eq(plan(s,d,nil,B).fallback.questId,1);s.skipped[2]=nil
    s.spells={[355]=true,[71]=true};eq(plan(s,d,nil,B).fallback.questId,1);s.spells={}
    s.quests[2]={ready=true,objectives={}}
    result=plan(s,d,nil,B);eq(result.fallback.questId,2);eq(result.fallback.kind,"turnin")
    s.quests[2]=nil;s.completed[2]=true
    result=plan(s,d,nil,B);eq(result.fallback.questId,3);eq(result.fallback.kind,"accept")
    s.completed[3]=true;eq(plan(s,d,nil,B).fallback.questId,1);s.completed[3]=nil
    reward.taskFacts.learnedSpells=nil;reward.taskFacts.mountReward=13819
    result=plan(s,d,nil,B);eq(result.fallback.questId,3);eq(result.taskOrder[1].unlock.kind,"mount")
    s.spells[13819]=true;eq(plan(s,d,nil,B).fallback.questId,1);s.spells={}
    s.inInstance=true;eq(plan(s,d,nil,B).fallback.questId,1);s.inInstance=nil
    reward.requiredClasses=2;eq(plan(s,d,nil,B).fallback.questId,1)
    reward.requiredClasses=1;s.completed={}
    local supplier=F.Quest(4);supplier.requiredClasses=1;supplier.taskFacts={level=10,xp={{1,0}}}
    quests[4]=supplier;d.Candidates=function() return {1,2,3,4} end
    pre.startedBy={[3]={700}}
    d.db={Item={Get=function(item,key) eq(item,700);eq(key,"questRewards");return {4} end}}
    local target=d.Target
    d.Target=function(self,quest,state)
        if quest.id~=2 or ((state.bags or {})[700] or 0)>0 then return target(self,quest,state) end
    end
    eq(plan(s,d,nil,B).fallback.questId,4)
    s.completed[4]=true;s.bags[700]=1
    eq(plan(s,d,nil,B).fallback.questId,2)
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
    s.quests={};s.completed[1]=true;q.repeatable=true;q.questLevel=20;good.taskFacts.xp=nil
    q.taskFacts={level=20,xp={{1,0}},rewards={items={},choices={}}}
    d.ReferenceObjectiveTargets=function(_,quest) return {{text="目标"}},{{map=1,x=quest.id/10,y=0}},false end
    result=plan(s,d,nil,B);eq(result.fallback.questId,2);assert(result.taskChoices[2].lowValue)
    eq(s.skipped[1],nil);eq(s.completed[1],true)
    s.locked=1;eq(plan(s,d,nil,B).fallback.questId,1);s.locked=nil
    s.quests[1]={ready=false,objectives={{text="继续目标"}}};eq(B.TaskGuide.LowValue(q,s,d),nil);s.quests={}
    q.taskFacts.xp=nil;eq(B.TaskGuide.LowValue(q,s,d),nil)
    q.taskFacts.xp={{1,1000}};eq(B.TaskGuide.LowValue(q,s,d),nil)
    q.taskFacts.xp={{1,0}};q.taskFacts.rewards.items={{id=900,count=1}};eq(B.TaskGuide.LowValue(q,s,d),nil)
    q.taskFacts.rewards.items={};q.taskFacts.rewards.choices={{id=900,count=1}};eq(B.TaskGuide.LowValue(q,s,d),nil)
    q.taskFacts.rewards.choices={};q.taskFacts.rewards.srcItem={id=900,count=1};eq(B.TaskGuide.LowValue(q,s,d),nil)
    q.taskFacts.rewards.srcItem=nil;s.completed={};eq(B.TaskGuide.LowValue(q,s,d),nil)
    q.taskFacts=nil;s.completed[1]=true
    d.CacheQuest=function(_,quest) if quest.id==1 then return {companionReward=900} end end
    result=plan(s,d,nil,B);eq(result.fallback.questId,2);assert(result.taskChoices[2].lowValue)
    eq(result.taskChoices[2].remainingXP,nil)
    s.locked=1;eq(plan(s,d,nil,B).fallback.questId,1);s.locked=nil
    s.quests[1]={objectives={}};eq(B.TaskGuide.LowValue(q,s,d),nil);s.quests={}
    q.taskFacts={level=20,xp={{1,1000}}};eq(B.TaskGuide.LowValue(q,s,d),nil)
    q.taskFacts=nil;s.completed={};eq(B.TaskGuide.LowValue(q,s,d),nil)
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
