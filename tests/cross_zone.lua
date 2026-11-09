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
