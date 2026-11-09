return function(test,eq,F,A,plan)
local function graph()
    return {nodes={start=F.Node(0),goal=F.Node(0.2),home=F.Node(0,2)},edges={start={{to="goal",seconds=20,verified=true}}},transit={
        fast={from="start",to="goal",kind="flight",verified=true,seconds=1,cost=40},
        back={from="goal",to="home",kind="flight",verified=true,seconds=5,cost=40}}}
end
local function data(quests,content)
    local result=F.Data(quests);result.content=content;content.dungeons=content.dungeons or {};return result
end
local function dungeon(content,s)
    local d={id=1,instanceId=42,difficultyId=1,title="资源夹具副本",verified=true,minLevel=10,maxLevel=30,entryNode="goal",exitNode="goal",returnNode="home",actions={},runSeconds=600,xp=1000}
    content.dungeons={[1]=d}
    local B={Navigation=F.Navigation,Content=content,Data=data({},content),state=s,char={samples={}},settings={dungeons=true,minutes=60,mode="fast",role="DAMAGER"},RequestRefresh=function() end}
    for _,file in ipairs({"State.lua","Planner/Eligibility.lua","Planner/Travel.lua","Planner/Gear.lua","Planner/Progression.lua","Planner/Supplies.lua","Planner/Dungeon.lua","Planner/Planner.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    B.State.Refresh=function() B.Dungeon:Sync(s,{}) end
    return B,d
end
test("交通返回最快与省钱非劣方案并消除无资源收益的循环",function()
    local c,s=graph(),F.State();s.money=40;s.now=100
    c.transit.loop={from="goal",to="goal",kind="boat",verified=true,seconds=0}
    local routes=A.Travel.Routes(c,"start","goal",s)
    eq(#routes,2);eq(routes[1].seconds,1);eq(routes[1].money,0);eq(routes[2].seconds,20);eq(routes[2].money,40)
    s.maxSeconds=10;eq(#A.Travel.Routes(c,"start","goal",s),1)
    eq(s.money,40)
end)
test("同一任务的整程选择保留返程路费",function()
    local c,s,q=graph(),F.State(),F.Quest(1);s.money=40;s.now=100
    q.actions={{kind="accept",node="start",seconds=1},{kind="objective",node="goal",seconds=1},{kind="turnin",node="home",seconds=1}}
    local r=A.Planner.Evaluate(q,s,data({[1]=q},c),{minutes=60},"start")
    eq(r.seconds,28);eq(r.resources.money,0)
    local flights=0;for _,a in ipairs(r.actions) do if a.kind=="transit" then flights=flights+1;eq(a.transitId,"back") end end
    eq(flights,1)
end)
test("跨任务搜索保留较慢前段并继承剩余金币",function()
    local c,s,q1,q2=graph(),F.State(),F.Quest(1),F.Quest(2);s.money=40;s.now=100
    q1.setup=true;q1.xp=1;q1.actions={{kind="turnin",node="goal",seconds=1}}
    q2.preQuestGroup={1};q2.xp=20000;q2.actions={{kind="turnin",node="home",seconds=1}}
    local p=plan(s,data({[1]=q1,[2]=q2},c));eq(p.best.xp,20001);eq(p.best.seconds,27);eq(p.best.resources.money,0)
    eq(s.money,40);eq(s.completed[1],nil)
end)
test("直线往返更快时保留炉石而不受旧单向道路限制",function()
    local c={nodes={a=F.Node(0),b=F.Node(0.2),c=F.Node(0.21)},edges={a={{to="b",seconds=20,verified=true}},b={{to="c",seconds=1,verified=true}}},transit={
        h={to="b",kind="hearth",seconds=1,cooldown=3600,verified=true}}}
    local s,q1,q2=F.State(),F.Quest(1),F.Quest(2);s.position.node="a";s.now=100;s.hearthReady=100
    q1.setup=true;q1.xp=1;q1.actions={{kind="turnin",node="b",seconds=1}}
    q2.preQuestGroup={1};q2.xp=20000;q2.actions={{kind="objective",node="c",seconds=1},{kind="turnin",node="b",seconds=1}}
    local p=plan(s,data({[1]=q1,[2]=q2},c),{minutes=1,mode="fast",dungeons=false})
    eq(p.best.xp,20001);assert(math.abs(p.best.seconds-6)<0.000001);eq(p.best.resources.hearthReady,3701)
    eq(s.hearthReady,100)
end)
test("束宽按任务序列计算且路线稳定比较完整动作身份",function()
    local list={}
    for index=1,12 do list[index]={id=1,sequence="one",routeKey="route"..index} end
    list[13]={id=2,sequence="two",routeKey="second"}
    local selected,count=A.Planner.Select(list,2);eq(#selected,13);eq(count,2)
    local old={best={id=1,routeKey="old"}}
    local fresh={best={id=2,routeKey="new",rate=100},alternatives={{id=1,routeKey="different",rate=100}}}
    eq(A.Planner.Choose(old,fresh).best.id,2)
end)
test("副本整程与实际入口导航一致保留返程路费",function()
    local c,s=graph(),F.State();s.money=40;F.Party(s);s.now=100
    local B,d=dungeon(c,s)
    local r=B.Dungeon.Evaluate(d,s,B.settings,B.Data);eq(r.seconds,625);eq(r.resources.money,0)
    eq(B.Dungeon:Accept(1),true);eq(B.Dungeon:Control("ready"),true)
    local p=plan(s,B.Data,B.settings,B)
    eq(p.best.actions[1].kind,"move");eq(p.best.actions[1].node,"goal")
    for _,a in ipairs(p.best.actions) do assert(a.transitId~="fast") end
end)
test("等队活动选择须同时保留完整副本所需交通资源",function()
    local c,s=graph(),F.State();s.money=40;s.now=100
    c.nodes.side=F.Node(0.01,2);c.nodes.goal.position.x=10
    c.transit.toSide={from="start",to="side",kind="flight",verified=true,seconds=1,cost=40}
    c.edges.side={{to="start",seconds=1,verified=true}}
    local B,d=dungeon(c,s);d.waitSeconds=100;d.interruptibleQuestIds={1}
    local q=F.Quest(1);q.interruptible=true;q.actions={{kind="turnin",node="side",seconds=1}}
    B.Data=data({[1]=q},c)
    local r=B.Dungeon.Evaluate(d,s,B.settings,B.Data)
    eq(r.waitActivity,nil);eq(r.seconds,1705)
end)
test("已消耗等队时间从后续副本比较中扣除",function()
    local c,s=graph(),F.State();s.money=80;s.now=100
    local B,d=dungeon(c,s);d.waitSeconds=300
    B.Dungeon:Accept(1);B.char.dungeon.waited=250;B.Dungeon:Sync(s,{})
    local r=B.Dungeon.Evaluate(d,s,B.settings,B.Data);eq(r.waitSeconds,50);eq(r.seconds,656)
end)
test("副本交付后按直线返程且超过预算仍指引已接受行程返程",function()
    local c,s=graph(),F.State();s.money=0;F.Party(s);s.now=100
    c.transit={};c.nodes.home=F.Node(0.4);c.edges.goal={{to="home",seconds=20,verified=true,unlock="quest:1"}}
    local B,d=dungeon(c,s);local q=F.Quest(1);s.quests[1]={objectives={}}
    B.Data=data({[1]=q},c)
    d.actions={{stage="inside",kind="turnin",node="goal",questId=1}}
    eq(B.Dungeon.Evaluate(d,s,B.settings,B.Data).seconds,640)
    B.Dungeon:Accept(1);s.inInstance,s.instanceId=true,42;B.Dungeon:Sync(s,{})
    B.Dungeon:Control("finish");s.inInstance=false;s.position.node="goal";s.completed[1]=true;s.quests[1]=nil
    s.unlocked={["quest:1"]=true};B.char.dungeon.elapsed=4000;B.Dungeon:Sync(s,{})
    local actions=B.Dungeon.ActivePlan(d,s,B.Data);eq(actions[1].kind,"move");eq(actions[1].node,"home")
end)

end
