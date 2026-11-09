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
test("交通只保留最快方案并消除无收益循环",function()
    local c,s=graph(),F.State();s.money=40;s.now=100
    c.transit.loop={from="goal",to="goal",kind="boat",verified=true,seconds=0}
    local routes=A.Travel.Routes(c,"start","goal",s)
    eq(#routes,1);eq(routes[1].seconds,1);eq(routes[1].money,nil)
    s.maxSeconds=10;eq(#A.Travel.Routes(c,"start","goal",s),1)
    eq(s.money,40)
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
