return function(test,eq,F,A,plan)
local function fixture()
    local B={};for k,v in pairs(A) do B[k]=v end
    for _,file in ipairs({"Planner/Dungeon.lua","Planner/DungeonTasks.lua","Planner/TaskGuide.lua","Planner/Flights.lua","Planner/Planner.lua"}) do
        assert(loadfile(file))("AiLeveling",B)
    end
    B.DungeonCatalog={version="1.60.1",build="70862",entries={}}
    B.PvPCatalog={version="1.60.1",build="70862",entries={
        [529]={instanceId=529,title="阿拉希盆地",areas={3358},maps={2}},
        [2997]={instanceId=2997,title="暗矛群岛",areas={16606},maps={3}},
    }}
    B.Navigation=F.Navigation
    local s,quests=F.State(),{}
    s.clientVersion,s.clientBuild="1.60.1","70862"
    for id=1,2 do
        quests[id]=F.Quest(id);quests[id].verified=false;quests[id].questLevel=20
        quests[id].taskFacts={level=20,xp={{1,1000}},rewards={items={},choices={}}}
    end
    local data=F.Data(quests);data.maps={[3358]=2,[16606]=3}
    data.Target=function(_,q,state)
        local active=state.quests[q.id]
        local objective=active and not active.ready
        return {map=objective and q.id==1 and 2 or 1,x=q.id/10,y=0,entityKind="npc",entityId=99}
    end
    data.ObjectiveTargets=function(_,q) return {{map=q.id==1 and 2 or 1,x=q.id/10,y=0,objectiveIndex=1}} end
    data.ReferenceObjectiveTargets=function(_,q) return {{text="目标"}},data:ObjectiveTargets(q),false end
    return B,s,data
end
local function choice(p,id) for _,c in ipairs(p.taskChoices) do if c.questId==id then return c end end end
local function run(name,fn)
    test(name,function()
        local old=C_Map;C_Map={GetMapInfo=function(map) return {mapType=3,parentMapID=map==4 and 2 or 0} end}
        fn();C_Map=old
    end)
end
run("战场剩余阶段退出野外自动推荐且不阻止同NPC交付",function()
    local B,s,data=fixture();local p=plan(s,data,nil,B)
    eq(p.fallback.questId,2);assert(choice(p,1).entryBlocked:find("阿拉希盆地",1,true))
    s.quests[1]={objectives={{text="战场目标",numRequired=1,numFulfilled=0}}}
    s.quests[2]={ready=true,objectives={}}
    p=plan(s,data,nil,B);eq(p.fallback.questId,2);eq(p.fallback.kind,"turnin")
    eq(#B.TaskGuide.DeliveryGroups(p.taskChoices,s),0);eq(s.skipped[1],nil);eq(s.completed[1],nil)
end)
run("手动战场任务先接取再排队进入而不生成跨海步行",function()
    local B,s,data=fixture();s.locked=1
    local p=plan(s,data,nil,B);eq(p.fallback.kind,"accept");eq(choice(p,1).entryBlocked,nil)
    s.quests[1]={objectives={{text="战场目标",numRequired=1,numFulfilled=0}}}
    p=plan(s,data,nil,B);eq(p.fallback.kind,"pvpEnter");eq(p.fallback.position,nil);eq(p.travelActions,nil)
    assert(p.fallback.text:find("排队进入",1,true));eq(s.completed[1],nil)
    local BUI={UI={}};assert(loadfile("UI/Main.lua"))("AiLeveling",BUI);assert(loadfile("UI/Tracker.lua"))("AiLeveling",BUI)
    local model=BUI.UI.TrackerModel(s,p,p.fallback,false)
    assert(model.instruction:find("排队进入",1,true))
end)
run("已在对应战场继续目标并在完成后离开交付",function()
    local B,s,data=fixture();s.inInstance=true;s.instanceId=529;s.position={map=2,x=0.1,y=0}
    s.quests[1]={objectives={{text="战场目标",numRequired=1,numFulfilled=0}}}
    local p=plan(s,data,{dungeons=false,minutes=60,mode="fast"},B)
    eq(p.fallback.kind,"objective");eq(p.fallback.questId,1);eq(choice(p,1).entryBlocked,nil)
    eq(choice(p,1).currentInstance,true)
    s.quests[1].ready=true;p=plan(s,data,nil,B);eq(p.fallback.kind,"pvpLeave");eq(p.fallback.position,nil)
    s.inInstance=false;s.instanceId=nil;s.position={map=1,x=0,y=0}
    p=plan(s,data,nil,B);eq(p.fallback.kind,"turnin");eq(p.fallback.questId,1)
    eq(choice(p,1).entryBlocked,nil);eq(s.completed[1],nil)
end)
run("其他战场区域来源楼层和构建识别互不混淆",function()
    local B,s,data=fixture()
    eq(B.Dungeon.TaskPvP({map=4,x=0,y=0},s,data).instanceId,529)
    eq(B.Dungeon.TaskPvP(nil,s,data,16606).instanceId,2997)
    eq(B.Dungeon.TaskPvP({map=1,x=0,y=0},s,data),nil)
    s.inInstance=true;s.instanceId=2997;s.locked=1
    s.quests[1]={objectives={{text="目标"}}};s.position={map=3,x=0,y=0}
    local p=plan(s,data,nil,B);eq(p.fallback.kind,"pvpEnter");assert(p.fallback.text:find("离开当前实例",1,true))
    s.clientBuild="70840";eq(B.Dungeon.TaskPvP({map=2,x=0,y=0},s,data),nil)
end)
run("战场内接取可用任务并优先当前地图的剩余目标",function()
    local B,s,data=fixture();s.inInstance=true;s.instanceId=529;s.position={map=2,x=0,y=0}
    data.Target=function(_,q) return {map=q.id==1 and 2 or 1,x=0.1,y=0} end
    local p=plan(s,data,nil,B);eq(p.fallback.questId,1);eq(p.fallback.kind,"accept")
    local stages={{kind="objective",objectiveIndex=1,position={map=1,x=0,y=0}},
        {kind="objective",objectiveIndex=2,position={map=2,x=0,y=0}}}
    local first=B.Dungeon.OrderTaskObjectives(stages,s,data);eq(first.objectiveIndex,2)
end)
test("五个当前构建战场身份独立于地下城目录",function()
    local B={};assert(loadfile("Data/Dungeons.lua"))("AiLeveling",B)
    local n=0;for id,entry in pairs(B.PvPCatalog.entries) do n=n+1;eq(id,entry.instanceId);assert(entry.title~="") end
    eq(n,5);eq(B.PvPCatalog.entries[2997].maps[1],2524);eq(B.PvPCatalog.entries[529].maps[1],1461)
    eq(B.DungeonCatalog.entries["reference:529"],nil)
end)
end
