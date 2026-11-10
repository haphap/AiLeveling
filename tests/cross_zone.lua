return function(test,eq,F,A,plan)
local function fixture()
    local B={};for k,v in pairs(A) do B[k]=v end
    for _,file in ipairs({"Planner/TaskGuide.lua","Planner/Flights.lua","Planner/Planner.lua"}) do
        assert(loadfile(file))("AiLeveling",B)
    end
    B.Navigation={Distance=function(_,a,b)
        if a and b and a.map<3 and b.map<3 then
            return math.abs((a.map-1+a.x)-(b.map-1+b.x))*700
        end
    end}
    local quests={}
    for id=1,3 do
        local q=F.Quest(id);q.verified=false;q.questLevel=20
        q.taskFacts={level=20,xp={{1,1000}},rewards={items={},choices={}}};quests[id]=q
    end
    local s,d=F.State(),F.Data(quests);s.position={map=1,x=0.95,y=0}
    d.Target=function(_,q) return {map=q.id,x=q.id==1 and 0.1 or 0.05,y=0} end
    d.ReferenceObjectiveTargets=function(_,q) return {{text="目标"}},{d:Target(q)},false end
    d.ObjectiveTargets=function(_,q) local p=d:Target(q);p.objectiveIndex=1;return {p} end
    d.chainIndex=A.Chains.NewIndex()
    for _,q in pairs(quests) do A.Chains.IndexQuest(d.chainIndex,q,d) end
    return B,s,d,quests
end
local function choice(result,id)
    for _,c in ipairs(result.taskChoices) do if c.questId==id then return c end end
end

test("跨区未接任务按完整移动收益比较并从接取衔接到交付后续",function()
    local B,s,d,q=fixture()
    local p=plan(s,d,nil,B)
    eq(p.fallback.questId,2);eq(p.fallback.kind,"accept");eq(p.fallback.position.map,2)
    assert(choice(p,1));assert(choice(p,2));eq(choice(p,3),nil)
    assert(choice(p,2).timing.seconds<choice(p,1).timing.seconds)
    eq(s.completed[2],nil);eq(s.quests[2],nil)
    s.position=p.fallback.position
    p=plan(s,d,nil,B);eq(p.fallback.kind,"accept")
    s.quests[2]={objectives={{numFulfilled=0,numRequired=1,text="目标"}}}
    p=plan(s,d,nil,B);eq(p.fallback.questId,2);eq(p.fallback.kind,"objective")
    s.quests[2].ready=true;p=plan(s,d,nil,B);eq(p.fallback.kind,"turnin")
    s.quests[2]=nil;s.completed[2]=true
    p=plan(s,d,nil,B);eq(p.fallback.questId,1);eq(p.fallback.position.map,1)
    q[1].preQuestGroup={4};p=plan(s,d,nil,B);eq(p.fallback,nil)
    s.level=30;s.quests={};s.completed={};q[1].preQuestGroup=nil
    q[2].questLevel=10;q[2].preQuestGroup={1};q[3].questLevel=40;q[3].preQuestGroup={2}
    d.byLevel={[20]={1},[10]={2},[40]={3}};d.chainIndex=B.Chains.NewIndex()
    for _,quest in pairs(q) do B.Chains.IndexQuest(d.chainIndex,quest,d) end
    local indexed={Chains=B.Chains};assert(loadfile("Data/Questie.lua"))("AiLeveling",indexed)
    d.Candidates=indexed.Data.Candidates
    d.Target=function(_,quest) return {map=2,x=quest.id/10,y=0,objectiveIndex=1} end
    eq(plan(s,d,nil,B).fallback,nil)
    s.completed[1]=true;p=plan(s,d,nil,B);eq(p.fallback.questId,2);eq(p.fallback.kind,"accept")
    s.quests[2]={objectives={{text="后续目标",numRequired=1,numFulfilled=0}}}
    p=plan(s,d,nil,B);eq(p.fallback.kind,"objective");eq(s.completed[2],nil)
    s.quests[2].ready=true;p=plan(s,d,nil,B);eq(p.fallback.kind,"turnin")
    s.quests[2]=nil;s.completed[2]=true;eq(plan(s,d,nil,B).fallback,nil)
    s.level=40;p=plan(s,d,nil,B);eq(p.fallback.questId,3);eq(p.fallback.kind,"accept");eq(s.completed[3],nil)
end)

test("自动行程顺路接取合算任务并按原生进度继续整组交付",function()
    local B,s,d,q=fixture();assert(loadfile("Planner/TaskQueue.lua"))("AiLeveling",B)
    s.position={map=1,x=0,y=0};s.currentTask=1
    s.quests[1]={objectives={{text="共同目标",numFulfilled=0,numRequired=1}}}
    local target,third=0.5,false
    d.Target=function(_,quest,context)
        if quest.id==3 and not third then return {map=3,x=0.5,y=0} end
        local active=context.quests[quest.id]
        if active and active.ready then return {map=1,x=0,y=0,entityKind="npc",entityId=100,entityName="交付者"} end
        return {map=1,x=active and 0.5 or 0.1,y=0,objectiveIndex=active and 1 or nil}
    end
    d.ReferenceObjectiveTargets=function()
        return {{text="共同目标",targetKind="npc",targetId=200,numRequired=1}},{{map=1,x=target,y=0}},false
    end
    d.ObjectiveTargets=function() return {{map=1,x=0.5,y=0,objectiveIndex=1}} end
    local p=plan(s,d,nil,B)
    eq(p.fallback.questId,2);eq(p.fallback.kind,"accept");assert(p.taskQueue)
    assert(p.fallback.pickupResume);eq(s.quests[2],nil);eq(s.completed[1],nil)
    eq(choice(p,2).status,"accept")
    assert(loadfile("UI/Main.lua"))("AiLeveling",B);assert(loadfile("UI/Tracker.lua"))("AiLeveling",B)
    local model=B.UI.TrackerModel(s,p,p.fallback,false)
    eq(model.questId,2);eq(model.kind,"accept");assert(model.hint)
    eq(model.rows[1].questId,1);eq(model.rows[1].accepted,true)
    local objective,delivery=0,math.huge
    for index,step in ipairs(p.taskQueue.steps) do
        local stage=step.stage or step.choice.stages[1]
        if stage.kind=="objective" then objective=index elseif stage.kind=="turnin" then delivery=math.min(delivery,index) end
    end
    assert(objective<delivery)
    -- A worthwhile city pickup may be away from the first leg to the questing area.
    local cityTarget=d.Target
    d.Target=function(self,quest,context)
        local point=cityTarget(self,quest,context)
        if quest.id==2 and not context.quests[2] then point.x=-0.1 end
        return point
    end
    p=plan(s,d,nil,B);eq(p.fallback.questId,2);eq(p.fallback.kind,"accept")
    d.Target=cityTarget
    -- Compare candidates past the former three-item cutoff as well.
    local candidates,original2,original3={},q[2],q[3]
    for id=2,5 do
        local c={};for k,v in pairs(choice(p,2)) do c[k]=v end
        c.questId=id;c.stages={};c.actions={}
        for i,original in ipairs(choice(p,2).stages) do
            local stage={};for k,v in pairs(original) do stage[k]=v end
            stage.questId=id;c.stages[i]=stage
        end
        c.actions[1]=c.stages[1];c.remainingXP=id==5 and 2000 or 1000
        q[id]=F.Quest(id);q[id].taskFacts={level=20,xp={{1,c.remainingXP}}}
        candidates[#candidates+1]=c
    end
    local picked=B.TaskQueue.Pickup({choice(p,1)},candidates,s,B.Navigation,d)
    eq(picked[1].questId,5)
    q[2],q[3],q[4],q[5]=original2,original3,nil,nil
    third=true;s.currentTask=2;q[3].taskFacts.xp={{1,1050}}
    eq(plan(s,d,nil,B).fallback.questId,2)
    q[3].taskFacts.xp={{1,2000}};eq(plan(s,d,nil,B).fallback.questId,3)
    third=false;s.currentTask=1
    s.locked=1;eq(plan(s,d,nil,B).fallback.questId,1);s.locked=nil
    s.questCount=20;eq(plan(s,d,nil,B).fallback.questId,1);s.questCount=nil
    q[2].taskFacts.hidden=true;eq(plan(s,d,nil,B).fallback.questId,1);q[2].taskFacts.hidden=nil
    target=0.95;q[2].taskFacts.xp={{1,100}}
    eq(plan(s,d,nil,B).fallback.questId,1)
    q[2].taskFacts.xp=nil;eq(plan(s,d,nil,B).fallback.questId,1)
    target=0.5;q[2].taskFacts.xp={{1,1000}}
    q[2].requiredLevel=21;eq(plan(s,d,nil,B).fallback.questId,1)
    s.level=21;eq(plan(s,d,nil,B).fallback.questId,2)
    s.position={map=1,x=0.1,y=0};s.quests[2]={objectives={{text="共同目标",numFulfilled=0,numRequired=1}}}
    p=plan(s,d,nil,B);eq(p.fallback.kind,"objective")
    s.position=p.fallback.position;p=plan(s,d,nil,B);eq(p.fallback.kind,"objective")
    eq(s.quests[1].ready,nil);eq(s.quests[2].ready,nil)
    s.quests[1].ready=true;p=plan(s,d,nil,B);eq(p.fallback.questId,2);eq(p.fallback.kind,"objective")
    s.quests[2].ready=true;p=plan(s,d,nil,B);eq(p.fallback.kind,"turnin")
    local first=p.fallback.questId;s.quests[first]=nil;s.completed[first]=true
    p=plan(s,d,nil,B);eq(p.fallback.kind,"turnin");assert(p.fallback.questId~=first)
end)

test("跨区低价值任务退出推荐且已接任务和手动选择继续优先",function()
    local B,s,d,q=fixture()
    s.position={map=1,x=0,y=0};s.runSpeed=3;q[2].questLevel=17;q[2].taskFacts.level=17
    d.Target=function(_,quest) return {map=quest.id,x=quest.id==2 and 0.5 or 0.1,y=0} end
    local p=plan(s,d,nil,B);assert(choice(p,2).lowValue.distant);eq(p.fallback.questId,1)
    s.locked=2;p=plan(s,d,nil,B);eq(p.fallback.questId,2);eq(choice(p,2).lowValue,nil)
    s.locked=nil;q[2].questLevel=20;q[2].taskFacts.level=20
    s.quests[1]={objectives={{numFulfilled=0,numRequired=1,text="目标"}}}
    p=plan(s,d,nil,B);eq(p.fallback.questId,1)
    s.skipped[2]=true;p=plan(s,d,nil,B);eq(choice(p,2),nil)
end)

test("未知跨区距离不自动导航且无位置或速度时保留已接及手动任务",function()
    local B,s,d=fixture()
    local p=plan(s,d,nil,B);eq(choice(p,3),nil)
    s.locked=3;p=plan(s,d,nil,B);eq(p.fallback.questId,3)
    s.locked=nil;s.runSpeed=nil;p=plan(s,d,nil,B);eq(choice(p,2),nil);assert(choice(p,1))
    s.position=nil;p=plan(s,d,nil,B);eq(#p.taskChoices,0)
    s.quests[2]={ready=true,objectives={}};p=plan(s,d,nil,B);eq(p.fallback.questId,2)
end)

test("跨区扩展不自动带入其他副本且实例内保持当前实例任务",function()
    local B,s,d=fixture()
    B.Dungeon={};for k,v in pairs(A.Dungeon) do B.Dungeon[k]=v end
    B.Dungeon.TaskInstance=function(pos) if pos and pos.map==2 then return {instanceId=22} end end
    local p=plan(s,d,nil,B);eq(choice(p,2),nil);eq(p.fallback.questId,1)
    s.inInstance=true;s.instanceId=22
    p=plan(s,d,nil,B);assert(choice(p,2));eq(p.fallback.questId,2)
    s.instanceId=11;p=plan(s,d,nil,B);eq(choice(p,2),nil)
end)
test("副本与室外共用地图时按实体原始区域区分且原生野外目标不进本",function()
    local B,s,d=fixture()
    assert(loadfile("Data/Questie.lua"))("AiLeveling",B)
    assert(loadfile("Planner/DungeonTasks.lua"))("AiLeveling",B)
    local oldMap=C_Map;C_Map={GetMapInfo=function(id) return {mapID=id,mapType=3} end}
    s.clientVersion,s.clientBuild="1.60.1","70862"
    local dungeon={id="reference:43",instanceId=43,title="哀嚎洞穴",areas={718},entrances={{17,46,36.5}}}
    B.DungeonCatalog={version="1.60.1",build="70862",entries={dungeon}}
    B.Data.maps={[17]=2,[718]=2,[100]=3}
    local function target(area,marker)
        return B.Data:SpawnPoints({[area]={{marker and -1 or 40,marker and -1 or 50}}},true)[1]
    end
    for _,marker in ipairs({false,true}) do
        local outside,inside=target(17,marker),target(718,marker)
        eq(outside.sourceAreaId,17);eq(inside.sourceAreaId,718)
        eq(B.Dungeon.TaskInstance(outside,s,B.Data),nil)
        eq(B.Dungeon.TaskInstance(inside,s,B.Data),dungeon)
        local action={kind="objective",questId=1,position=outside}
        eq(B.Dungeon.TaskApproach(action,s,B.Data),action)
        action.position=inside;eq(B.Dungeon.TaskApproach(action,s,B.Data).kind,"dungeonEnter")
    end
    eq(B.Dungeon.TaskInstance({map=2,x=0.4,y=0.5},s,B.Data),nil)
    local mixed=B.Data:SpawnPoints({[17]={{-1,-1}},[718]={{-1,-1}}},true)
    eq(#mixed,1);assert(not mixed[1].sourceAreaId);eq(B.Dungeon.TaskInstance(mixed[1],s,B.Data),nil)
    s.inInstance=true;s.instanceId=43
    local action={kind="turnin",questId=1,position=target(17)}
    eq(B.Dungeon.TaskApproach(action,s,B.Data).kind,"dungeonLeave")
    action.position=target(718);eq(B.Dungeon.TaskApproach(action,s,B.Data),action)
    -- A unique internal UI map remains usable without raw entity metadata.
    B.Data.maps[718]=4;eq(B.Dungeon.TaskInstance({map=4,x=0.5,y=0.5},s,B.Data),dungeon)
    C_Map=oldMap
end)
end
