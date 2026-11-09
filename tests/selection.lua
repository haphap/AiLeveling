return function(test,eq,F,A,plan)
local S=A.Selection
local function intent(order,key)
    local baselines={}
    for _,group in ipairs(assert(S.Parse(order))) do for _,id in ipairs(group) do baselines[id]=0 end end
    return {sequence=order,baselines=baselines,version="v1",preferredKey=key}
end
local function hasTransit(candidate)
    for _,action in ipairs(candidate.actions) do if action.kind=="transit" then return true end end
    return false
end
local function fixture(quests)
    quests=quests or {[1]=F.Quest(1),[2]=F.Quest(2),[3]=F.Quest(3)}
    local state,data=F.State(),F.Data(quests)
    data.content.version="v1"
    local B={Planner=A.Planner,Content=data.content,Data=data,state=state,ready=true,
        char={turnIns={},skipped={},samples={}},Navigation={},refreshes=0,
        Transport={InFlight=function(self) return self.flying end},UI={}}
    assert(loadfile("Planner/Selection.lua"))("AiLeveling",B)
    B.State={Refresh=function(_,force)
        eq(force,true);B.refreshes=B.refreshes+1
        B.Selection:Snapshot(B.state);B.state.revision=B.state.revision+1
    end}
    B.plan=plan(state,data)
    return B
end

test("整程意图只接受有界任务组与合法交付基线",function()
    assert(S.Parse("1:2>3>4:5"));assert(S.Valid(intent("1:2>3")))
    for _,value in ipairs({"","1:",":1","1>",">1","1>>2","0","-1","1:1","1>1","1e2","1;2","1:2:3:4","1>2>3>4","2147483648"}) do
        eq(S.Parse(value),nil)
    end
    local selected=intent("1");selected.baselines[1]=0/0;eq(S.Valid(selected),false)
    selected=intent("1");selected.preferredKey={};eq(S.Valid(selected),false)
end)
test("跨任务候选显示完整标题任务集合并投影独立资源",function()
    local s,data=F.State(),F.Data({[1]=F.Quest(1),[2]=F.Quest(2)})
    local first=A.Planner.Evaluate(data:GetQuest(1),s,data,{minutes=60,mode="fast"},"start")
    local virtual=A.Planner.Project(s,first)
    eq(virtual.completed[1],true);eq(s.completed[1],nil)
    local second=A.Planner.Evaluate(data:GetQuest(2),virtual,data,{minutes=55,mode="fast"},first.lastNode)
    local joined=A.Planner.Join(first,second)
    eq(joined.sequence,"1>2");eq(#joined.questIds,2);eq(joined.questIds[2],2)
    assert(joined.title:find("测试任务 1 → 测试任务 2",1,true))
    eq(#first.questIds,1);eq(joined.seconds,first.seconds+second.seconds)
end)
test("整程选择严格保留任务组合和先后顺序",function()
    local B=fixture();B.state.itinerary=intent("2>1");B.state.locked=2
    local result=plan(B.state,B.Data)
    eq(result.selectionActive,true);eq(result.best.sequence,"2>1")
    eq(#result.best.questIds,2);eq(result.best.questIds[1],2);eq(result.best.questIds[2],1)
    local ids={}
    for _,action in ipairs(result.best.actions) do if action.kind=="turnin" then ids[#ids+1]=action.questId end end
    eq(table.concat(ids,":"),"2:1")
    eq(A.Planner.Choose(B.plan,result).best,result.best)
end)
test("锁定任务不受普通候选索引和束宽截断影响",function()
    local B=fixture();B.Data.Candidates=function() return {} end
    B.state.itinerary=intent("3>2>1")
    local result=plan(B.state,B.Data)
    eq(result.best.sequence,"3>2>1");eq(#result.best.questIds,3)
end)
test("所选后续资格不足时保留意图并阻断其他任务替换",function()
    local B=fixture();B.Data:GetQuest(2).requiredLevel=99
    B.state.itinerary=intent("1>2");B.state.quests[3]={objectives={}}
    local result=plan(B.state,B.Data)
    eq(result.best,nil);eq(result.fallback.kind,"selectionBlocked");eq(result.unverified,nil)
    assert(result.selectionBlocked:find("第 2 组",1,true));eq(B.state.completed[1],nil)
end)
test("所选行程阻断时必要服务可先恢复且保留原任务顺序",function()
    local q=F.Quest(1);q.combat=true
    local B=fixture({[1]=q});B.state.itinerary=intent("1");B.state.durability=0.1
    B.Content.sources={fixture={}}
    B.Content.services={smith={verified=true,source="fixture",title="先维修",node="near",repair={seconds=10}}}
    local result=plan(B.state,B.Data)
    eq(result.selectionActive,true);eq(result.selectionBlocked,nil)
    local repair=false;for _,action in ipairs(result.best.actions) do if action.serviceKind=="repair" then repair=true end end
    eq(repair,true)
    eq(B.state.itinerary.sequence,"1");eq(B.state.durability,0.1)
    B.state.durability=1;result=plan(B.state,B.Data)
    eq(result.best.sequence,"1");eq(result.selectionBlocked,nil)
end)
test("当前仍可行的手选交通变体优先且使用重新计算后的数值",function()
    local B=fixture({[1]=F.Quest(1)})
    B.state.money=100;B.Content.transit={flight={from="start",to="goal",kind="flight",seconds=5,cost=40,verified=true}}
    B.state.itinerary=intent("1")
    local result=plan(B.state,B.Data)
    eq(hasTransit(result.best),true)
    local before=result.best;B.state.itinerary.preferredKey=before.routeKey
    B.Content.transit.flight.seconds=100;B.state.runSpeed=14
    result=plan(B.state,B.Data)
    eq(hasTransit(result.best),false);eq(result.best.seconds,20)
    assert(result.best.gearSources);assert(result.best~=before)
end)
test("原生交付推进整程且就绪任务保留至实际交付",function()
    local B=fixture();B.char.itinerary=intent("1:2>3","old-path")
    B.state.completed[1]=true;B.state.quests[2]={ready=true,objectives={}}
    B.Selection:Snapshot(B.state)
    eq(B.char.itinerary.sequence,"2>3");eq(B.state.locked,2);eq(B.state.itinerary.preferredKey,nil)
    eq(B.state.completed[2],nil);eq(B.state.quests[2].ready,true)
    B.char.turnIns[2]=1;B.Selection:Snapshot(B.state)
    eq(B.state.itinerary.sequence,"3");eq(B.state.locked,3)
    B.char.turnIns[3]=1;B.Selection:Snapshot(B.state)
    eq(B.char.itinerary,nil);eq(B.char.locked,nil);eq(B.state.itinerary,nil)
end)
test("重复任务历史完成标记不能代替本轮实际交付",function()
    local q=F.Quest(1);q.repeatable=true
    local B=fixture({[1]=q});B.char.turnIns[1]=5
    B.char.itinerary=intent("1","route");B.char.itinerary.baselines[1]=5
    B.state.completed[1]=true
    B.Selection:Snapshot(B.state);eq(B.char.itinerary.sequence,"1")
    B.char.turnIns[1]=6;B.Selection:Snapshot(B.state);eq(B.char.itinerary,nil)
end)
test("来源版本变化保留任务顺序并清除旧交通偏好",function()
    local B=fixture();B.char.itinerary=intent("2>1","old-route")
    B.Content.version="v2";B.Selection:Snapshot(B.state)
    eq(B.state.itinerary.sequence,"2>1");eq(B.state.itinerary.preferredKey,nil);eq(B.char.itinerary.version,"v2")
    B.char.dungeon={phase="preparing"};B.Selection:Snapshot(B.state)
    eq(B.char.itinerary,nil);eq(B.state.locked,nil)
end)
test("执行备选只接受当前计划对象与当前决策位置",function()
    local B=fixture();local candidate=B.plan.best
    local function reject()
        local ok=B.Selection:Lock(candidate,B.plan.revision)
        eq(ok,false);eq(B.char.itinerary,nil);eq(B.refreshes,0)
    end
    B.state.revision=2;reject();B.state.revision=1
    B.refreshAt=1;reject();B.refreshAt=nil
    B.state.position.node="goal";reject();B.state.position.node="start"
    B.Transport.flying=true;reject();B.Transport.flying=false
    B.char.dungeon={phase="preparing"};reject();B.char.dungeon=nil
    local forged={sequence=candidate.sequence,routeKey=candidate.routeKey}
    eq(B.Selection:Lock(forged,B.plan.revision),false)
    B.char.turnIns[1]=2;B.char.gearTarget="other";B.char.gearBaseline=1
    B.char.paused=true;B.Navigation.manual={map=1,x=0,y=0}
    local ok,reason=B.Selection:Lock(candidate,B.plan.revision);assert(ok,reason)
    eq(B.char.itinerary.baselines[1],2);eq(B.char.gearTarget,nil);eq(B.Navigation.manual,nil);eq(B.char.paused,false)
    eq(next(B.state.completed),nil);eq(B.refreshes,1)
end)
test("恢复自动与单任务锁定暂缓正确替换整程意图",function()
    local B=fixture();B.char.itinerary=intent("1>2");B.char.locked=1
    B.Selection:LockQuest(3);eq(B.char.itinerary,nil);eq(B.char.locked,3)
    B.char.itinerary=intent("1>2");B.char.gearTarget="wanted";B.Content.gearSources={wanted={questId=1}}
    B.Selection:Skip(1);eq(B.char.itinerary,nil);eq(B.char.locked,nil);eq(B.char.skipped[1],true);eq(B.char.gearTarget,nil)
    B.char.itinerary=intent("1>2");B.char.dungeon={phase="running"}
    eq(B.Selection:Automatic(),false);assert(B.char.itinerary)
    B.char.dungeon=nil;B.char.serviceStop={};assert(B.Selection:Automatic());eq(B.char.itinerary,nil);eq(B.char.paused,false);eq(B.char.serviceStop,nil)
end)

local function widget()
    return {SetPoint=function() end,SetSize=function() end,Hide=function() end,SetWidth=function() end,
        SetText=function(self,value) self.value=value end,SetEnabled=function(self,value) self.enabled=value end}
end
local function uiFixture()
    local B=fixture();B.UI.scroll={SetVerticalScroll=function() end}
    B.UI.Text=function() return widget() end
    B.UI.Button=function(_,parent,label,width,callback)
        local w=widget();w.text=widget();w.text.value=label;w.callback=callback;return w
    end
    assert(loadfile("UI/Plan.lua"))("AiLeveling",B)
    B.UI.SelectTab=function() B.UI.Plan:Refresh();B.lines=B.UI.Plan:Lines() end
    local saved=CreateFrame;CreateFrame=function() return widget() end
    B.UI.Plan:Create({});CreateFrame=saved
    B.UI:SelectTab(1)
    return B
end
test("行程浏览展示所有备选并保留完整行动与比较差异",function()
    local B=uiFixture();local rows=B.UI.Plan.Rows(B.plan)
    assert(#rows>8);eq(rows[1],B.plan.best)
    local count=#rows
    B.UI.Plan.previous.callback()
    eq(B.UI.Plan.preview,rows[count]);assert(B.UI.Plan.label.value:find("/ "..count,1,true))
    local text=table.concat(B.lines,"\n")
    assert(text:find("完整行动预览",1,true));assert(text:find("与当前规划方案相比",1,true))
    local candidate=B.UI.Plan.preview
    B.UI.Plan.choose.callback();eq(B.char.itinerary.sequence,candidate.sequence);eq(B.refreshes,1)
    eq(B.UI.Plan.choose.enabled,false)
end)
test("已显示但失效的方案点击被拒绝且副本须明确接受",function()
    local B=uiFixture();B.state.revision=B.state.revision+1
    B.UI.Plan.choose.callback();eq(B.char.itinerary,nil);eq(B.refreshes,0)
    B.state.revision=B.plan.revision
    local candidate={id="dungeon:7",kind="dungeon",dungeonId=7,title="测试副本",requiresAcceptance=true,
        actions={},seconds=600,xp=1000,rate=1000/600}
    B.plan.alternatives={candidate};B.plan.best=candidate
    local accepted=0;B.Dungeon={Accept=function(_,id) eq(id,7);accepted=accepted+1;return true end}
    B.UI:SelectTab(1);eq(B.UI.Plan.choose.text.value,"接受副本行程")
    B.UI.Plan.choose.callback();eq(accepted,1);eq(B.char.itinerary,nil)
end)
test("行程页起点变化时重新估价且不重复排队或在空中计算",function()
    local B=uiFixture();B.jobs={};B.replans=0
    B.Replan=function(self) self.replans=self.replans+1 end
    B.state.position.node="near";B.UI:SelectTab(1)
    eq(B.replans,1);eq(B.UI.Plan.choose.enabled,false)
    B.jobs.plan=true;B.UI:SelectTab(1);eq(B.replans,1)
    B.jobs.plan=nil;B.Transport.flying=true;B.UI:SelectTab(1)
    eq(B.replans,1);eq(B.UI.Plan.recalculate.enabled,false)
end)
test("进行中的副本剩余估计未知时不显示零分钟完成",function()
    local B=uiFixture()
    B.plan.best={id="accepted:7:1",kind="dungeon",title="当前副本",seconds=0,xp=0,rate=0,actions={}}
    B.plan.alternatives={};B.char.dungeon={phase="running"}
    B.UI:SelectTab(1)
    local text=table.concat(B.lines,"\n")
    assert(text:find("本轮副本行程进行中",1,true));eq(text:find("预计 0.0 分钟",1,true),nil)
    eq(B.UI.Plan.choose.enabled,false)
end)
test("达到等级目标时行程页说明完成而非报告数据缺口",function()
    local B=uiFixture();B.plan={complete=true,revision=B.state.revision,alternatives={}}
    B.UI:SelectTab(1)
    local text=table.concat(B.lines,"\n")
    assert(text:find("已达到 60 级",1,true));eq(text:find("路线数据尚未齐全",1,true),nil)
end)
test("单任务锁定在实际非重复任务交付后解除",function()
    local B=fixture();B.char.locked=1;B.state.locked=1;B.state.completed[1]=true
    B.state.quests[1]={ready=true,objectives={}};B.Selection:Snapshot(B.state);eq(B.char.locked,1)
    B.state.quests[1]=nil;B.Selection:Snapshot(B.state);eq(B.char.locked,nil);eq(B.state.locked,nil)
    B.Data:GetQuest(2).repeatable=true;B.char.locked=2;B.state.completed[2]=true
    B.Selection:Snapshot(B.state);eq(B.char.locked,2)
end)
test("恢复命令清除整程锁定并恢复现有副本与装备目标",function()
    local B=fixture();local oldCreate,oldSlash=CreateFrame,SlashCmdList
    CreateFrame=function() return {RegisterEvent=function() end,SetScript=function() end} end
    SlashCmdList={}
    assert(loadfile("Core.lua"))("AiLeveling",B)
    B.UI.frame={};B.char.itinerary=intent("1>2");B.char.locked=1;B.char.paused=true;B.char.serviceStop={}
    B.char.dungeon={phase="running"};B.char.gearTarget="wanted";B.Navigation.manual={map=1}
    SlashCmdList.AILEVELING("resume");eq(B.char.serviceStop,nil)
    eq(B.char.itinerary,nil);eq(B.char.locked,nil);eq(B.char.paused,false)
    eq(B.char.dungeon.phase,"running");eq(B.char.gearTarget,"wanted");eq(B.Navigation.manual,nil)
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
        eq(snapshot.position.node,"start");eq(snapshot.completed[99],nil)
        coroutine.yield()
        eq(snapshot.position.node,"start");eq(snapshot.completed[99],nil)
        return {revision=snapshot.revision,best={id=42},alternatives={}}
    end,Choose=function(_,new) return new end}
    B.Navigation.OnApproach=function(_,node) return node=="near" end
    B.Navigation.SetPlan=function() end
    B:Replan();assert(coroutine.resume(run))
    B.state.position.node="near";B.state.completed[99]=true
    local ok,reason=coroutine.resume(run);assert(ok,reason)
    eq(B.plan.best.id,42);assert(B.plan~=oldPlan)
    CreateFrame,SlashCmdList=oldCreate,oldSlash
end)
end
