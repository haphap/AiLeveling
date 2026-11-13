return function(test,eq,F,A,plan)
local function fixture(quests)
    quests=quests or {[1]=F.Quest(1),[2]=F.Quest(2),[3]=F.Quest(3)}
    for _,q in pairs(quests) do q.questLevel=20;q.taskFacts={level=20,xp={{1,1000}}} end
    local state,data=F.State(),F.Data(quests)
    data.Target=function(_,q) return {map=1,x=q.id/10,y=0} end
    local B={Planner=A.Planner,Data=data,state=state,ready=true,
        char={turnIns={},skipped={},samples={}},Navigation={Current=function() end},refreshes=0,
        Transport={InFlight=function(self) return self.flying end},UI={}}
    assert(loadfile("Planner/Selection.lua"))("AiLeveling",B)
    B.State={Refresh=function(_,force)
        eq(force,true);B.refreshes=B.refreshes+1
        B.Selection:Snapshot(B.state);B.state.revision=B.state.revision+1
    end}
    B.plan=plan(state,data)
    return B
end

test("执行备选只接受当前计划对象与当前决策位置",function()
    local B=fixture();local candidate=B.plan.taskChoices[1]
    local function reject()
        local ok=B.Selection:Lock(candidate,B.plan.revision)
        eq(ok,false);eq(B.char.itinerary,nil);eq(B.refreshes,0)
    end
    B.state.revision=2;reject();B.state.revision=1
    B.refreshAt=1;reject();B.refreshAt=nil
    B.state.position.map=2;reject();B.state.position.map=1
    B.Transport.flying=true;reject();B.Transport.flying=false
    local forged={kind="task",questId=candidate.questId}
    eq(B.Selection:Lock(forged,B.plan.revision),false)
    B.char.turnIns[1]=2;B.char.gearTarget="other";B.char.gearBaseline=1
    B.char.paused=true;B.Navigation.manual={map=1,x=0,y=0}
    local ok,reason=B.Selection:Lock(candidate,B.plan.revision);assert(ok,reason)
    eq(B.char.locked,candidate.questId);eq(B.char.gearTarget,nil);eq(B.Navigation.manual,nil);eq(B.char.paused,false)
    eq(next(B.state.completed),nil);eq(B.refreshes,1)
end)
test("恢复自动与任务暂缓清理旧锁定并保留副本控制",function()
    local B=fixture();B.char.locked=1
    B.Selection:LockQuest(3);eq(B.char.itinerary,nil);eq(B.char.locked,3)
    B.char.locked=1;B.char.gearTarget="wanted";B.Gear={GetSource=function(id) if id=="wanted" then return {questId=1} end end}
    B.Selection:Skip(1);eq(B.char.itinerary,nil);eq(B.char.locked,nil);eq(B.char.skipped[1],true);eq(B.char.gearTarget,nil)
    B.char.serviceStop={};assert(B.Selection:Automatic());eq(B.char.itinerary,nil);eq(B.char.paused,false);eq(B.char.serviceStop,nil)
end)

test("列表选中真实任务后统一检查时效，副本须明确接受",function()
    local B=fixture();assert(loadfile("UI/Main.lua"))("AiLeveling",B)
    assert(loadfile("UI/Plan.lua"))("AiLeveling",B)
    local rows=B.UI.Plan.Rows(B.plan);eq(#rows,3)
    local candidate=rows[#rows]
    B.UI.Plan.preview=candidate
    B.state.revision=B.state.revision+1
    eq(B.UI.Plan:Choose(candidate,B.plan.revision),false);eq(B.refreshes,0)
    B.state.revision=B.plan.revision
    assert(B.UI.Plan:Choose(candidate,B.plan.revision));eq(B.char.locked,candidate.questId)
    local d={id="dungeon:7",kind="dungeon",dungeonId=7,title="测试副本",requiresAcceptance=true,actions={}}
    B.plan={revision=B.state.revision,origin=B.state.position,alternatives={d},best=d,taskChoices={}}
    local accepted=0;B.Dungeon={StartTaskBatch=function(_,id) eq(id,7);accepted=accepted+1;return true end}
    eq(B.UI.Plan.Rows(B.plan)[1],d);eq(accepted,0)
    assert(B.UI.Plan:Choose(d,B.plan.revision));eq(accepted,1)
end)
test("单任务锁定在实际非重复任务交付后解除",function()
    local B=fixture();B.char.locked=1;B.state.locked=1;B.state.completed[1]=true
    B.state.quests[1]={ready=true,objectives={}};B.Selection:Snapshot(B.state);eq(B.char.locked,1)
    B.state.quests[1]=nil;B.Selection:Snapshot(B.state);eq(B.char.locked,nil);eq(B.state.locked,nil)
    B.Data:GetQuest(2).repeatable=true;B.char.locked=2;B.state.completed[2]=true
    B.Selection:Snapshot(B.state);eq(B.char.locked,2)
end)
test("恢复命令清除任务和副本锁定并保留装备目标",function()
    local B=fixture();local oldCreate,oldSlash=CreateFrame,SlashCmdList
    CreateFrame=function() return {RegisterEvent=function() end,SetScript=function() end} end
    SlashCmdList={}
    assert(loadfile("Core.lua"))("AiLeveling",B)
    B.UI.frame={};B.char.locked=1;B.char.paused=true;B.char.serviceStop={}
    B.char.taskBatch={id="ref",baselines={[3]=0}};B.char.gearTarget="wanted";B.Navigation.manual={map=1}
    SlashCmdList.AILEVELING("resume");eq(B.char.serviceStop,nil)
    eq(B.char.itinerary,nil);eq(B.char.locked,nil);eq(B.char.paused,false)
    eq(B.char.taskBatch,nil);eq(B.char.gearTarget,"wanted");eq(B.Navigation.manual,nil)
    CreateFrame,SlashCmdList=oldCreate,oldSlash
end)
test("异步规划位置与交付快照独立于当前状态原地变化",function()
    local B=fixture();local oldCreate,oldSlash=CreateFrame,SlashCmdList
    CreateFrame=function() return {RegisterEvent=function() end,SetScript=function() end} end
    SlashCmdList={};assert(loadfile("Core.lua"))("AiLeveling",B)
    local oldPlan=B.plan
    local run
    B.Queue=function(_,_,fn) run=coroutine.create(fn) end
    B.Planner={Build=function(snapshot)
        eq(snapshot.position.x,0);eq(snapshot.completed[99],nil)
        coroutine.yield()
        eq(snapshot.position.x,0);eq(snapshot.completed[99],nil)
        return {revision=snapshot.revision,best={id=42},alternatives={}}
    end}
    B.Navigation.SetPlan=function() end
    B:Replan();assert(coroutine.resume(run))
    B.state.position.x=0.1;B.state.completed[99]=true
    local ok,reason=coroutine.resume(run);assert(ok,reason)
    eq(B.plan.best.id,42);assert(B.plan~=oldPlan)
    CreateFrame,SlashCmdList=oldCreate,oldSlash
end)
end
