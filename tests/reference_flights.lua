return function(test,eq,F,A,plan)
local savedMap=C_Map
C_Map={GetMapInfo=function() return {mapType=3} end}
local function fixture()
    local B={FlightData={version="test",clientVersion="1.60.1",build=70862,interface=16001,
        nodes={[1]={name="出发地",instance=0,world={0.1,0.1,0},factionMask=1},
            [2]={name="目的地",instance=0,world={0.9,0.8,0},factionMask=1},
            [3]={name="敌方",instance=0,world={0.9,0.9,0},factionMask=2}},
        durations={Alliance={["1:2"]=100},Horde={}}}}
    assert(loadfile("Planner/Flights.lua"))("AiLeveling",B)
    local state=F.State()
    state.clientVersion,state.clientBuild,state.interface="1.60.1","70862",16001
    state.faction,state.money,state.now="Alliance",1000,10
    state.position={map=1,x=0.1,y=0.1}
    state.taxiOrigin={id=1,at=0,position={map=1,x=0.1,y=0.1}}
    state.unlocked={["taxi:1"]=true,["taxi:2"]=true,["taxi:3"]=true}
    state.taxiAvailability={["1:2"]=true,["1:3"]=true};state.taxiCosts={["1:2"]=110,["1:3"]=0}
    state.samples={};state.taxiSpeed=1
    local action={kind="turnin",questId=99,title="交付任务",position={map=2,x=0.9,y=0.9}}
    local nav={hbd={GetZoneCoordinatesFromWorldInstance=function(_,west,north,instance,map)
        eq(instance,0);if map==2 then return west,north end
    end}}
    function nav:Distance(a,b)
        return math.sqrt(((a.x+a.map)-(b.x+b.map))^2+(a.y-b.y)^2)*1000
    end
    return B,state,action,nav
end
test("原生可达即可接续跨图任务，忽略票价与金币",function()
    local B,s,a,nav=fixture();local route=B.Flights.Guide(a,s,nav)
    eq(route.from,1);eq(route.to,2);eq(route.cost,nil);eq(route.flightSeconds,100)
    eq(route.actions[1].mode,"flight");eq(route.actions[1].position.x,0.8)
    eq(route.actions[2],a);eq(route.groundComplete,nil)
    assert(route.actions[1].text:find("落地后继续任务",1,true));assert(not route.actions[1].text:find("分钟",1,true));eq(route.seconds,nil)
    s.taxiAvailability["1:2"]=false;eq(B.Flights.Guide(a,s,nav),nil)
    s.taxiAvailability["1:2"]=nil;eq(B.Flights.Guide(a,s,nav),nil)
    s.taxiAvailability["1:2"]=true;s.taxiCosts=nil;assert(B.Flights.Guide(a,s,nav))
    s.money=0;assert(B.Flights.Guide(a,s,nav))
    s.money=110;s.unlocked["taxi:2"]=nil;eq(B.Flights.Guide(a,s,nav),nil)
end)
test("飞行参考拒绝旧构建远离出发点过期和洞内投影",function()
    local B,s,a,nav=fixture()
    s.clientBuild="1";eq(B.Flights.Guide(a,s,nav),nil);s.clientBuild="70862"
    s.position.x=0.2;eq(B.Flights.Guide(a,s,nav),nil);s.position.x=0.1
    s.now=121;eq(B.Flights.Guide(a,s,nav),nil);s.now=10
    local original=C_Map.GetMapInfo;C_Map.GetMapInfo=function() return {mapType=4} end
    eq(B.Flights.Guide(a,s,nav),nil);C_Map.GetMapInfo=original
    s.taxiOrigin=nil;eq(B.Flights.Guide(a,s,nav),nil)
end)
test("新航线未知耗时可保留指引且有效绝对样本优先",function()
    local B,s,a,nav=fixture();B.FlightData.durations.Alliance={}
    local route=B.Flights.Guide(a,s,nav);eq(route.flightSeconds,nil)
    assert(route.actions[1].text:find("飞行管理员",1,true));assert(not route.actions[1].text:find("采样",1,true))
    local key=B.Flights.TimeKey(1,2,s.faction,nil,s.taxiSpeed)
    s.samples[key]={n=2,unit="seconds",mean=80};eq(B.Flights.Seconds(1,2,s),nil)
    s.samples[key].n=3;eq(B.Flights.Seconds(1,2,s),80)
    B.FlightData.durations.Alliance["1:2"]=100;eq(B.Flights.Seconds(1,2,s),80)
    eq(B.Flights.Seconds(2,1,s),nil);s.faction="Horde";eq(B.Flights.Seconds(1,2,s),nil)
end)
test("原生停靠改变时按实际分段估时且隔离不同路线的本地样本",function()
    local B,s=fixture()
    B.FlightData.observedDurations={Alliance={["1:2"]=80,["1:4"]=40,["4:2"]=20}}
    B.FlightData.observedHops={Alliance={["1:2"]="1:2",["1:4"]="1:4",["4:2"]="4:2"}}
    s.samples[B.Flights.TimeKey(1,2,s.faction,nil,s.taxiSpeed)]={n=3,mean=30,unit="seconds"}
    s.taxiHops={["1:2"]="1:2"};eq(B.Flights.Seconds(1,2,s),80)
    local direct=B.Flights.TimeKey(1,2,s.faction,"1:2",s.taxiSpeed)
    s.samples[direct]={n=3,mean=70,unit="seconds"};eq(B.Flights.Seconds(1,2,s),70)
    s.taxiHops["1:2"]="1:4:2";eq(B.Flights.Seconds(1,2,s),60)
    local via=B.Flights.TimeKey(1,2,s.faction,"1:4:2",s.taxiSpeed)
    s.samples[via]={n=3,mean=55,unit="seconds"};eq(B.Flights.Seconds(1,2,s),55)
    s.samples[via]=nil;B.FlightData.observedDurations.Alliance["4:2"]=nil
    eq(B.Flights.Seconds(1,2,s),nil)
    s.taxiHops={};eq(B.Flights.Seconds(1,2,s),30)
end)
test("飞行加速只读取当前构建已学法术且接口未知保持未知",function()
    local B,s=fixture();local old=C_SpellBook
    C_SpellBook={IsSpellKnown=function(id) eq(id,1225490);return true end}
    eq(B.Flights.ReadSpeed(s),1.2)
    C_SpellBook.IsSpellKnown=function() return false end;eq(B.Flights.ReadSpeed(s),1)
    for _,value in ipairs({"true",0,{}}) do C_SpellBook.IsSpellKnown=function() return value end;eq(B.Flights.ReadSpeed(s),nil) end
    C_SpellBook.IsSpellKnown=function() error("未就绪") end;eq(B.Flights.ReadSpeed(s),nil)
    C_SpellBook.IsSpellKnown=function() error("不应读取其他构建") end
    s.clientBuild="70863";eq(B.Flights.ReadSpeed(s),nil)
    C_SpellBook=nil;s.clientBuild="70862";eq(B.Flights.ReadSpeed(s),nil)
    C_SpellBook=old
end)
test("加速参考按速度缩短且各速度实测原值隔离不重复缩放",function()
    local B,s=fixture();B.FlightData.durations.Alliance["1:2"]=120
    s.taxiSpeed=1.2;eq(B.Flights.Seconds(1,2,s),100)
    B.FlightData.observedDurations={Alliance={["1:2"]=240}}
    eq(B.Flights.Seconds(1,2,s),200)
    local base=B.Flights.TimeKey(1,2,s.faction,nil,1)
    local fast=B.Flights.TimeKey(1,2,s.faction,nil,1.2)
    s.samples[base]={n=3,mean=210,unit="seconds"}
    s.samples[base:gsub(":speed:1$","")]={n=100,mean=1,unit="seconds"}
    eq(B.Flights.Seconds(1,2,s),200)
    s.samples[fast]={n=3,mean=180,unit="seconds"};eq(B.Flights.Seconds(1,2,s),180)
    s.taxiSpeed=1;eq(B.Flights.Seconds(1,2,s),210)
    s.taxiSpeed=nil;s.samples[B.Flights.TimeKey(1,2,s.faction)]={n=3,mean=1,unit="seconds"}
    eq(B.Flights.Seconds(1,2,s),240)
    s.taxiSpeed=1.2;s.taxiHops={["1:2"]="1:4:2"}
    B.FlightData.durations.Alliance["1:4"]=120;B.FlightData.durations.Alliance["4:2"]=60
    eq(B.Flights.Seconds(1,2,s),150)
    s.samples[B.Flights.TimeKey(1,4,s.faction,"1:4",1.2)]={n=3,mean=80,unit="seconds"}
    eq(B.Flights.Seconds(1,2,s),130)
end)
local function joint()
    local B,s,a,nav=fixture()
    B.Travel=A.Travel;B.Estimates={flightBoardSeconds=10}
    function nav:Distance(a,b)
        local function world(p)
            if p.map==1 then return p.x*1400 end
            if p.map==2 then return p.x*2100+2310 end
            return p.x*700+1000000
        end
        return math.abs(world(a)-world(b))
    end
    local O,D,L,T={map=1,x=0,y=0},{map=1,x=0.1,y=0},{map=2,x=0.8,y=0},{map=2,x=0.9,y=0}
    s.transportKnown=true;s.taxiOrigin=nil;s.position=O
    s.taxiDepartures={[1]=D};s.taxiLandings={["1:2"]=L}
    return B,s,a,nav,O,D,L,T
end
test("飞行天赋改变交通选择但不缩短地面候机",function()
    local B,s,a,nav,O,D,L,T=joint()
    B.FlightData.durations.Alliance["1:2"]=600
    local routes=B.Flights.Routes(O,T,s,nav);eq(#routes,1);eq(routes[1].flights,0);eq(routes[1].seconds,600)
    s.taxiSpeed=1.2;routes=B.Flights.Routes(O,T,s,nav)
    eq(routes[1].flights,1);eq(routes[1].seconds,560)
    eq(routes[1].legs[2].flightSeconds,500);eq(routes[1].legs[2].seconds,510)
    local actions=B.Flights.Actions(routes[1],a,nav)
    eq(actions[1].timeSampleKey,B.Flights.TimeKey(1,2,s.faction,nil,1.2))
    s.position=D;s.taxiOrigin={id=1,at=s.now,position=D}
    local guide=B.Flights.Guide(a,s,nav);eq(guide.flightSeconds,500)
    eq(guide.actions[1].timeSampleKey,actions[1].timeSampleKey)
end)
test("训练旅店服务使用统一交通且到达不完成服务",function()
    local B,s,a,nav,O,D,L,T=joint()
    B.Navigation=nav;B.state=s
    assert(loadfile("Services.lua"))("AiLeveling",B)
    s.serviceStop={kind="train",npcId=78,title="训练师",position=T}
    local result=B.Services.Build(s)
    eq(result.referenceJourney.flights,1);eq(result.travelActions[1].mode,"flight")
    eq(result.travelActions[#result.travelActions],result.fallback);eq(result.fallback.npcId,78)
    eq(result.fallback.serviceKind,"train");eq(s.money,1000)
    s.taxiAvailability={};result=B.Services.Build(s);eq(result.referenceJourney.flights,0)
    for _,action in ipairs(result.travelActions) do assert(action.kind~="transit") end
    s.serviceStop.kind="bind";s.position=T;result=B.Services.Build(s)
    eq(result.referenceJourney.seconds,0);eq(#result.travelActions,1);eq(result.fallback.serviceKind,"bind")
    assert(s.serviceStop)
    s.position=O;B.Hearth={Duration=function() return 10,10,10,false end}
    s.bags={[6948]=1};s.hearthPoint=T;s.hearthBindingKey="actual";s.hearthReady=s.now;s.hearthCooldown=3600
    result=B.Services.Build(s);eq(result.travelActions[1].mode,"hearth");eq(result.referenceJourney.hearths,1)
    eq(s.hearthReady,s.now);eq(s.hearthBindingKey,"actual")
    s.bags={};B.PublicTransitData={clientVersion=s.clientVersion,build=s.clientBuild,interface=s.interface,
        legs={{kind="boat",key="testboat",from=O,to=T,fromName="码头",toName="旅店码头",seconds=30,low=30,high=30,cost=0}}}
    result=B.Services.Build(s);eq(result.travelActions[1].mode,"boat");eq(result.fallback.serviceKind,"bind")
    B.PublicTransitData=nil;nav.Distance=function() return nil end
    result=B.Services.Build(s);eq(result.referenceJourney,nil);eq(#result.travelActions,1);assert(s.serviceStop)
end)
test("无需先飞过航线即可按参考落地点估时且实际落地点优先",function()
    local B,s,a,nav,O,D,L,T=joint()
    s.taxiLandings={}
    local route=B.Flights.Routes(O,T,s,nav)[1]
    eq(route.flights,1);eq(route.seconds,160);eq(route.legs[2].to.x,0.8)
    eq(B.Flights.Actions(route,a,nav)[1].arrival,25)
    eq(next(s.taxiLandings),nil)
    s.taxiLandings={["1:2"]={map=2,x=0.85,y=0}}
    route=B.Flights.Routes(O,T,s,nav)[1]
    assert(math.abs(route.seconds-145)<0.00001);eq(route.legs[2].to,s.taxiLandings["1:2"])
    eq(B.Flights.Actions(route,a,nav)[1].arrival,12)
    s.taxiLandings={["1:2"]=L}
    s.taxiAvailability={};eq(B.Flights.Routes(O,T,s,nav)[1].flights,0)
end)
test("参考落地点仍需原生可达版本与已知飞行耗时",function()
    local B,s,a,nav,O,D,L,T=joint();s.taxiLandings={}
    local function walking() eq(B.Flights.Routes(O,T,s,nav)[1].flights,0) end
    s.taxiAvailability["1:2"]=false;walking();s.taxiAvailability["1:2"]=true
    s.unlocked["taxi:2"]=nil;walking();s.unlocked["taxi:2"]=true
    s.clientBuild="other";walking();s.clientBuild="70862"
    B.FlightData.durations.Alliance["1:2"]=nil;walking();B.FlightData.durations.Alliance["1:2"]=100
    s.taxiDepartures={};walking();s.taxiDepartures={[1]=D}
    nav.hbd=nil;walking()
end)
test("参考落地点投影到区域或上级大陆且拒绝洞内和无效坐标",function()
    local B,s,a,nav,O,D,L,T=joint();s.taxiLandings={}
    local old=C_Map.GetMapInfo
    C_Map.GetMapInfo=function(map)
        if map==2 then return {mapType=4,parentMapID=9} end
        if map==9 then return {mapType=2,parentMapID=0} end
        return {mapType=3,parentMapID=0}
    end
    nav.hbd.GetZoneCoordinatesFromWorldInstance=function(_,west,north,instance,map)
        assert(map~=2,"不能把飞行点投影到洞内地图")
        if map==9 then return 0.8,0.9 end
    end
    function nav:Distance(a,b)
        local function world(p) return (p.map==9 or p.map==2) and 2310+p.x*2100 or p.x*1400 end
        return math.abs(world(a)-world(b))
    end
    local route=B.Flights.Routes(O,T,s,nav)[1]
    eq(route.flights,1);eq(route.legs[2].to.map,9);eq(route.seconds,160)
    nav.hbd.GetZoneCoordinatesFromWorldInstance=function() return 2,0.5 end
    eq(B.Flights.Routes(O,T,s,nav)[1].flights,0)
    C_Map.GetMapInfo=function() return {mapType=4,parentMapID=0} end
    nav.hbd.GetZoneCoordinatesFromWorldInstance=function() error("洞内不可投影") end
    eq(B.Flights.Routes(O,T,s,nav)[1].flights,0)
    C_Map.GetMapInfo=old
end)
test("连续航班的实际转乘点按直线连接",function()
    local B,s,a,nav,O,D,L,T=joint()
    local D3,L4,T4={map=2,x=0.85,y=0},{map=3,x=0.8,y=0},{map=3,x=0.9,y=0}
    B.FlightData.nodes[3].factionMask=1
    B.FlightData.nodes[4]={name="四号",instance=0,world={0,0,0},factionMask=1}
    B.FlightData.durations.Alliance["3:4"]=10
    s.unlocked["taxi:4"]=true;s.taxiDepartures[3]=D3;s.taxiLandings["3:4"]=L4
    s.taxiAvailability["3:4"]=true
    local routes=B.Flights.Routes(O,T4,s,nav)
    eq(routes[1].flights,2);eq(routes[1].seconds,175)
end)
test("完整参考规划只执行选中路线的首段并等待实际交付",function()
    local B,s,a,nav,O,D,L,T=joint()
    assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    local oldFlights,oldGuide,oldNav=A.Flights,A.TaskGuide,A.Navigation
    A.Flights,A.TaskGuide,A.Navigation=B.Flights,B.TaskGuide,nav
    s.quests={[99]={title="交付任务",ready=true,objectives={}}};s.locked=99
    local d=F.Data({[99]={id=99,title="交付任务"}});d.Target=function() return T end
    local result=plan(s,d)
    assert(result.referenceJourney);eq(result.referenceJourney.flights,1)
    eq(result.travelActions[1].kind,"transit");eq(result.travelActions[1].mode,"flight")
    eq(result.travelActions[#result.travelActions].kind,"turnin");eq(s.completed[99],nil)
    local count=0;for _,action in ipairs(result.travelActions) do if action.kind=="turnin" then count=count+1 end end
    eq(count,1)
    A.Flights,A.TaskGuide,A.Navigation=oldFlights,oldGuide,oldNav
end)
local function queueFixture()
    local B,s,a,nav,O,D,L,T=joint()
    B.Progression=A.Progression
    assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    assert(loadfile("Planner/TaskQueue.lua"))("AiLeveling",B)
    s.maxXP=1000000;s.xp=0
    local function choice(id,point)
        return {questId=id,stagesComplete=true,stages={{position=point,kind="turnin"}},
            remainingXP=10,actions={{position=point}},status="turnin"}
    end
    return B,s,nav,O,T,choice
end
local function sharedItemsFixture()
    local B,s,nav,O,T,choice=queueFixture()
    s.bags={[2592]=60};s.quests={[1]={ready=true,objectives={}},[2]={ready=true,objectives={}}}
    local a,b=choice(1,T),choice(2,T)
    for _,c in ipairs({a,b}) do
        c.stages[1].recipient={entityKind="npc",entityId=99,entityName="收件人"}
        c.stages[1].itemRequirements={{kind="objective",questId=c.questId,title="毛料任务",text="毛料",
            position=O,targetKind="item",targetId=2592,objectiveIndex=1,need=60}}
    end
    return B,s,nav,a,b
end
local function limitedItemsFixture()
    local B,s,nav,a,b=sharedItemsFixture()
    assert(loadfile("Data/ItemLimits.lua"))("AiLeveling",B)
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    s.bags={[18250]=1}
    for _,c in ipairs({a,b}) do
        local r=c.stages[1].itemRequirements[1];r.targetId=18250;r.need=1
    end
    return B,s,nav,a,b
end
test("共用库存随路线换序分配以便先交附近任务再补远处物品",function()
    local B,s,nav,a,b=sharedItemsFixture()
    s.taxiAvailability={};s.position={map=1,x=0,y=0}
    function nav:Distance(from,to) return math.abs(from.x-to.x)*700 end
    a.stages[1].position={map=1,x=0.9,y=0}
    b.stages[1].position={map=1,x=0.1,y=0}
    b.stages[1].recipient.entityId=100
    for _,c in ipairs({a,b}) do c.stages[1].itemRequirements[1].position={map=1,x=1,y=0} end
    local prepared=B.TaskQueue.PrepareItems({a,b},s)
    eq(prepared[1].itemShortage,nil);eq(prepared[2].itemShortage,true)
    local order,queue=B.TaskQueue.Solve(prepared,s,nav)
    assert(queue);assert(math.abs(queue.seconds-110)<0.00001,queue.seconds)
    eq(order[1].questId,2);eq(order[1].executionAction.kind,"turnin")
    eq(order[1].itemShortage,nil);eq(order[2].itemShortage,true)
    eq(queue.bags[2592],0);eq(s.bags[2592],60);eq(s.quests[1].ready,true)
    eq(prepared[1].itemShortage,nil);eq(prepared[2].itemShortage,true)
    eq(#a.stages,1);eq(#b.stages,1)
    s.locked=1;order,queue=B.TaskQueue.Solve(prepared,s,nav)
    eq(order[1].questId,1);eq(order[1].executionAction.kind,"turnin")
    assert(math.abs(queue.seconds-190)<0.00001,queue.seconds)
end)
test("持有上限使同NPC任务分批交付并禁止提前收集超额物品",function()
    local B,s,nav,a,b=limitedItemsFixture()
    local prepared=B.TaskQueue.PrepareItems({a,b},s)
    local impossible={
        {questId=2,stageIndex=1,stagesComplete=true,stages={prepared[2].stages[1]}},
        {questId=1,stageIndex=1,stagesComplete=true,stages={prepared[1].stages[1]}}}
    eq(B.TaskQueue.Evaluate(impossible,s,nav),nil)
    local order,queue=B.TaskQueue.Solve({a,b},s,nav)
    assert(queue);eq(order[1].questId,1);eq(order[1].executionAction.kind,"turnin")
    eq(queue.bags[18250],0)
    local groups=B.TaskGuide.DeliveryGroups({a,b},s,order)
    eq(#groups,1);eq(groups[1].splitDelivery,true);eq(groups[1].ready,1)
    eq(s.bags[18250],1);eq(s.quests[2].ready,true)
    s.bags={};order,queue=B.TaskQueue.Solve({a,b},s,nav);assert(queue)
    eq(order[1].executionAction.kind,"objective");eq(order[1].executionAction.itemGain,1)
    eq(queue.bags[18250],0)
end)
test("持有上限按构建启用且同时计算接取发放与收集数量",function()
    local B,s,nav,a,b=limitedItemsFixture()
    local stage={targetId=18250,itemGain=1,gainItems={[18250]=1}}
    eq(B.TaskGuide.ItemGainBlocked(stage,s,{}),true)
    stage.gainItems=nil;eq(B.TaskGuide.ItemGainBlocked(stage,s,{}),false)
    eq(B.TaskGuide.ItemGainBlocked(stage,s),true)
    s.clientBuild="other";eq(B.TaskGuide.ItemGainBlocked(stage,s),false)
    local groups=B.TaskGuide.DeliveryGroups({a,b},s);eq(groups[1].splitDelivery,nil)
    s.clientBuild="70862";stage.targetId=2592;stage.itemGain=120
    eq(B.TaskGuide.ItemGainBlocked(stage,s),false)
end)
test("共用物品只分配一次且同收件人先补齐再连续交付",function()
    local B,s,nav,a,b=sharedItemsFixture()
    local order,queue=B.TaskQueue.Solve({a,b},s,nav)
    assert(queue and queue.stagePlan);eq(#queue.steps,3);eq(queue.bags[2592],0)
    eq(queue.steps[1].stage.kind,"objective");eq(queue.steps[1].stage.itemGain,60)
    eq(queue.steps[1].stage.have,60);eq(queue.steps[1].stage.need,120)
    eq(queue.steps[2].stage.kind,"turnin");eq(queue.steps[3].stage.kind,"turnin")
    eq(order[1].executionAction.kind,"objective");eq(s.bags[2592],60);eq(s.quests[2].ready,true)
    eq(#a.stages,1);eq(#b.stages,1);eq(b.itemsPrepared,nil)
    local groups=B.TaskGuide.DeliveryGroups({a,b},s,order);eq(groups[1].ready,1)
    s.bags[2592]=120;order,queue=B.TaskQueue.Solve({a,b},s,nav)
    eq(#queue.steps,2);eq(queue.bags[2592],0);eq(order[1].executionAction.kind,"turnin")
    s.bags[2592]=140;_,queue=B.TaskQueue.Solve({a,b},s,nav);eq(queue.bags[2592],20)
end)
test("手选可先交一项且换序与部分库存不会重复计入物品",function()
    local B,s,nav,a,b=sharedItemsFixture();s.locked=1
    local order,queue=B.TaskQueue.Solve({a,b},s,nav)
    eq(order[1].questId,1);eq(order[1].executionAction.kind,"turnin");eq(queue.bags[2592],0)
    s.locked=nil;s.bags[2592]=90
    for _,input in ipairs({{a,b},{b,a}}) do
        order,queue=B.TaskQueue.Solve(input,s,nav)
        eq(queue.bags[2592],0);eq(queue.steps[1].stage.itemGain,30);eq(queue.steps[1].stage.need,120)
    end
    s.bags[2592]=0;order,queue=B.TaskQueue.Solve({a,b},s,nav)
    local gain=0;for _,step in ipairs(queue.steps) do gain=gain+(step.stage.itemGain or 0) end
    eq(gain,120);eq(queue.bags[2592],0)
end)
test("无完整路线时保留补收集步骤而非退回虚假的两次交付",function()
    local B,s,nav,a,b=sharedItemsFixture()
    B.Navigation=nav;assert(loadfile("Planner/Planner.lua"))("AiLeveling",B)
    b.stages[1].itemRequirements[1].position=nil
    local order,queue=B.Planner.TaskOrder(s,{a,b})
    eq(queue,nil)
    local shortage
    for _,c in ipairs(order) do if c.itemShortage then shortage=c end end
    assert(shortage);eq(shortage.executionAction.kind,"objective");eq(shortage.executionAction.itemGain,60)
    eq(shortage.stagesComplete,false)
    local groups=B.TaskGuide.DeliveryGroups({a,b},s,order);eq(groups[1].ready,1)
end)
test("接取发放物品只在接取后计入并在交付后扣除",function()
    local B,s,nav,a=sharedItemsFixture();s.bags={};s.quests={}
    a.stages[1].itemRequirements[1].need=1;a.stages[1].itemRequirements[1].providedOnAccept=true
    table.insert(a.stages,1,{kind="accept",questId=1,position=s.position})
    local queue=B.TaskQueue.Evaluate({a},s,nav);assert(queue);eq(queue.bags[2592],0)
    eq(#queue.steps[1].choice.stages,2);eq(s.bags[2592],nil)
    s.bags[2592]=1;queue=B.TaskQueue.Evaluate({a},s,nav);eq(queue.bags[2592],0)
end)
test("队列使用原生交付经验且跨级后恢复分级资料或未知",function()
    local B,s,nav,O,T,choice=queueFixture()
    B.Experience={version="1.60.1",build="70862",interface=16001,source="test",xpToLevel={[20]=100,[21]=100}}
    assert(loadfile("Planner/Progression.lua"))("AiLeveling",B)
    s.level,s.xp,s.maxXP=20,0,100
    s.quests={[1]={rewardXP=100,rewardXPLevel=20},[2]={rewardXP=80,rewardXPLevel=20}}
    local quests={{id=1},{id=2,questLevel=20,taskFacts={level=20,xp={{1,70},{21,10}}}}}
    local data={content={},GetQuest=function(_,id) return quests[id] end}
    local a,b=choice(1,O),choice(2,O)
    local queue=B.TaskQueue.Evaluate({a,b},s,nav,data)
    eq(queue.xp,110);eq(queue.xpKnown,true);eq(queue.forecast.level,21);eq(queue.forecast.xp,10)
    quests[2].taskFacts=nil
    queue=B.TaskQueue.Evaluate({a,b},s,nav,data)
    eq(queue.xp,100);eq(queue.xpKnown,false);eq(queue.forecast.uncertain,true)
    queue=B.TaskQueue.Evaluate({b,a},s,nav,data)
    eq(queue.xp,180);eq(queue.xpKnown,true);eq(queue.forecast.level,21);eq(queue.forecast.xp,80)
    eq(s.level,20);eq(s.quests[2].rewardXP,80)
end)
test("整批同路程优先保留升级前的较高交付经验",function()
    local B,s,nav,O,T,choice=queueFixture()
    B.Experience={version="1.60.1",build="70862",interface=16001,source="test",xpToLevel={[20]=100,[21]=100,[22]=100}}
    assert(loadfile("Planner/Progression.lua"))("AiLeveling",B)
    s.level,s.xp,s.maxXP=20,0,100
    local a,b=choice(1,T),choice(2,T)
    local data={content={},GetQuest=function(_,id)
        return {id=id,questLevel=20,taskFacts={level=20,xp={{1,100},{21,id==1 and 10 or 90}}}}
    end}
    local before=B.TaskQueue.Evaluate({b,a},s,nav,data)
    local order,queue=B.TaskQueue.Solve({b,a},s,nav,data)
    eq(before.xp,110);eq(queue.xp,190);eq(queue.seconds,before.seconds);eq(order[1],a)
end)
local function hearthFixture()
    local B,s,a,nav,O,D,L,T=joint()
    B.Estimates.hearthSeconds=20
    assert(loadfile("Hearth.lua"))("AiLeveling",B)
    s.bags={[6948]=1};s.hearthPoint=L;s.hearthBindingKey="0:旅店";s.bindName="旅店";s.hearthReady=0
    return B,s,a,nav,O,L,T
end
test("队列按整程跑路选择顺序而非只看最近首目标且无需执行资料",function()
    local B,s,nav,O,T,choice=queueFixture()
    s.taxiAvailability={}
    function nav:Distance(a,b) return math.abs(a.x-b.x)*700 end
    local function task(id,start,finish)
        local c=choice(id,{map=1,x=start,y=0})
        c.stages={{kind="objective",position={map=1,x=start,y=0}},
            {kind="turnin",position={map=1,x=finish,y=0}}}
        c.remainingXP=nil
        return c
    end
    local a,b,c=task(1,0.1,0.9),task(2,0.2,0.3),task(3,0.8,1)
    local before=B.TaskQueue.Evaluate({a,b,c},s,nav)
    assert(math.abs(before.seconds-240)<0.00001)
    local order,queue=B.TaskQueue.Solve({a,b,c},s,nav)
    eq(order[1],a);eq(order[2],b);eq(order[3],c)
    assert(math.abs(queue.seconds-100)<0.00001)
    eq(queue.remaining,0);eq(b.orderBasis,"queue-movement")
    eq(a.executionTiming.movementOnly,true)
    s.locked=1;local order=B.TaskQueue.Solve({a,b,c},s,nav);eq(order[1],a)
end)
local function stagedFixture()
    local B,s,nav,O,T,choice=queueFixture()
    s.taxiAvailability={}
    function nav:Distance(a,b) return math.abs(a.x-b.x)*700 end
    local function task(id,x)
        local c=choice(id,O)
        c.stages={{kind="objective",questId=id,objectiveIndex=1,position={map=1,x=x,y=0}},
            {kind="turnin",questId=id,position=O}}
        c.actions={c.stages[1]};return c
    end
    return B,s,nav,O,task(1,0.8),task(2,0.9)
end

test("交错目标期间不提前获得交付经验或跨级减奖励",function()
    local B,s,nav,O,a,b=stagedFixture()
    B.Experience={version="1.60.1",build="70862",interface=16001,source="test",xpToLevel={[20]=100,[21]=100,[22]=100}}
    assert(loadfile("Planner/Progression.lua"))("AiLeveling",B)
    s.level,s.xp,s.maxXP=20,0,100
    local data={content={},GetQuest=function(_,id) return {id=id,questLevel=20,taskFacts={level=20,xp={{1,100},{21,10}}}} end}
    local _,queue=B.TaskQueue.Solve({a,b},s,nav,data)
    eq(queue.stagePlan,true);eq(queue.xp,110);eq(queue.forecast.level,21);eq(queue.forecast.xp,10)
    eq(queue.steps[1].xp,0);eq(queue.steps[2].xp,0);eq(queue.steps[3].xp,100);eq(queue.steps[4].xp,10)
    eq(s.level,20);eq(s.xp,0)
end)
test("当前目标完成后继续附近任务而非被旧任务稳定规则带回交付",function()
    local B,s,nav,O=stagedFixture()
    for _,key in ipairs({"Eligibility","Gear","Dungeon","Supplies","State"}) do B[key]=A[key] end
    B.Navigation=nav
    assert(loadfile("Planner/Planner.lua"))("AiLeveling",B)
    local quests={}
    for id=1,2 do
        local q=F.Quest(id);q.verified=false;q.questLevel=20;q.taskFacts={level=20,xp={{1,10}}};quests[id]=q
        s.quests[id]={title="任务 "..id,objectives={{text="目标",numRequired=1,numFulfilled=0}}}
    end
    local d=F.Data(quests)
    d.Target=function(_,q,state) return state.quests[q.id].ready and O or {map=1,x=0.7+q.id/10,y=0,objectiveIndex=1} end
    d.ObjectiveTargets=function(_,q) return {{map=1,x=0.7+q.id/10,y=0,objectiveIndex=1}} end
    local result=plan(s,d,nil,B)
    assert(result.taskQueue.stagePlan);eq(result.fallback.questId,1);eq(result.fallback.objectiveIndex,1)
    eq(result.travelActions[#result.travelActions],result.fallback)
    s.position={map=1,x=0.8,y=0};s.quests[1].ready=true;s.quests[1].objectives[1].finished=true;s.currentTask=1
    result=plan(s,d,nil,B);eq(result.fallback.questId,2);eq(result.fallback.kind,"objective")
    eq(s.completed[1],nil);eq(s.quests[2].ready,nil)
    s.position={map=1,x=0.9,y=0};s.quests[2].ready=true;s.quests[2].objectives[1].finished=true
    result=plan(s,d,nil,B);eq(result.fallback.kind,"turnin");eq(result.taskQueue.seconds,90)
end)
test("同一NPC五项任务全部目标完成后才连续集中交付",function()
    local B,s,nav,O=stagedFixture()
    O.entityKind,O.entityId,O.entityName="npc",900,"治安官"
    for _,key in ipairs({"Eligibility","Gear","Dungeon","Supplies","State"}) do B[key]=A[key] end
    B.Navigation=nav;assert(loadfile("Planner/Planner.lua"))("AiLeveling",B)
    assert(loadfile("UI/Main.lua"))("AiLeveling",B);assert(loadfile("UI/Tracker.lua"))("AiLeveling",B)
    local quests={}
    for id=1,5 do
        local q=F.Quest(id);q.verified=false;q.questLevel=20;q.taskFacts={level=20,xp={{1,10}}};quests[id]=q
        s.quests[id]={title="任务 "..id,objectives={{text="目标",numRequired=1,numFulfilled=0}}}
    end
    local d=F.Data(quests)
    d.Target=function(_,q,state) return state.quests[q.id].ready and O or {map=1,x=q.id/10,y=0,objectiveIndex=1} end
    d.ObjectiveTargets=function(_,q) return {{map=1,x=q.id/10,y=0,objectiveIndex=1}} end
    local function check(unfinished)
        local result=plan(s,d,nil,B);local queue=assert(result.taskQueue)
        eq(#queue.steps,unfinished+5);eq(queue.taskCount,5);eq(#queue.deliveryBatches,1)
        for i,step in ipairs(queue.steps) do eq(step.stage.kind,i<=unfinished and "objective" or "turnin") end
        eq(result.fallback.kind,unfinished>0 and "objective" or "turnin")
        local model=B.UI.TrackerModel(s,result,result.fallback,false)
        if unfinished>0 and unfinished<5 then assert(model.deliverySummary:find("全部完成后",1,true));assert(model.deliverySummary:find("还差 "..unfinished.." 项",1,true))
        elseif unfinished==0 then assert(model.deliverySummary:find("一起交付：到治安官交 5 项任务",1,true)) end
        eq(s.completed[1],nil);return result
    end
    local result=check(5);assert(math.abs(result.taskQueue.seconds-100)<0.001)
    for id=1,2 do s.quests[id].ready=true;s.quests[id].objectives[1].finished=true end
    s.currentTask=1;result=check(3);assert(result.fallback.questId>2)
    local located=d.ObjectiveTargets;d.ObjectiveTargets=function() return {} end
    s.quests[5].objectives[2]={text="额外目标",numRequired=1,numFulfilled=0}
    result=plan(s,d,nil,B);eq(result.fallback.kind,"objective");assert(result.fallback.questId>2)
    eq(result.taskQueue,nil)
    s.quests[5].objectives[2]=nil;d.ObjectiveTargets=located
    for id=3,5 do s.quests[id].ready=true;s.quests[id].objectives[1].finished=true end
    result=check(0)
    local previous=result
    s.quests[2]=nil;s.completed[2]=true;s.revision=s.revision+1
    local model=B.UI.TrackerModel(s,previous,previous.fallback,false)
    eq(model.unacceptedCount,0);eq(#model.rows,4)
    for _,row in ipairs(model.rows) do assert(row.questId~=2) end
    B.state=s;B.plan=previous;nav.Current=function() return previous.fallback end
    assert(not table.concat(B.UI:TaskLines(false),"\n"):find("任务 2",1,true))
    assert(loadfile("UI/Plan.lua"))("AiLeveling",B);eq(#B.UI.Plan.Rows(previous),4)
    B.char={};B.UI.Plan.preview=previous.taskChoices[2]
    assert(not table.concat(B.UI.Plan:Lines(),"\n"):find("任务 2",1,true))
    model=B.UI.TrackerModel(s,previous,{kind="turnin",questId=2},false)
    eq(model.questId,nil);eq(#model.rows,4);eq(model.title,"正在更新行程")
    local renewed={revision=s.revision,taskChoices={{id="task:2",questId=2,kind="task",status="accept",actions={{kind="accept",questId=2}}}}}
    model=B.UI.TrackerModel(s,renewed,nil,false);eq(model.unacceptedCount,1)
    result=plan(s,d,nil,B);eq(result.taskQueue.taskCount,4);eq(#result.taskQueue.steps,4)
    eq(result.fallback.kind,"turnin")
    s.locked=1;result=plan(s,d,nil,B);eq(result.fallback.questId,1)
    s.locked=nil
    for index,id in ipairs({1,3,4,5}) do
        previous=result;s.quests[id]=nil;s.completed[id]=true;s.revision=s.revision+1
        model=B.UI.TrackerModel(s,previous,previous.fallback,false)
        eq(model.unacceptedCount,0);eq(#model.rows,4-index)
        result=plan(s,d,nil,B);eq(#result.taskChoices,4-index)
        if index<4 then eq(result.fallback.kind,"turnin")
        else eq(result.fallback,nil);eq(result.taskQueue,nil) end
    end
end)
test("集中交付只合并实际接取且同一收件人的有效任务",function()
    local B,s,nav,O,a,b=stagedFixture()
    O.entityKind,O.entityId="npc",900;s.quests={[1]={},[2]={ready=true}}
    local groups,byQuest=B.TaskGuide.DeliveryGroups({a,b},s)
    eq(#groups,1);eq(groups[1].ready,1);eq(byQuest[1],byQuest[2])
    s.quests[2]=nil;eq(#B.TaskGuide.DeliveryGroups({a,b},s),0)
    s.quests[2]={};b.lowValue={};eq(#B.TaskGuide.DeliveryGroups({a,b},s),0);b.lowValue=nil
    s.skipped={[2]=true};eq(#B.TaskGuide.DeliveryGroups({a,b},s),0);s.skipped={}
    b.stages[2].position={map=O.map,x=O.x,y=O.y,entityKind="npc",entityId=901}
    eq(#B.TaskGuide.DeliveryGroups({a,b},s),0)
    b.stages[2].position.entityId=900;b.stages[2].position.entityKind="object"
    eq(#B.TaskGuide.DeliveryGroups({a,b},s),0)
end)
test("整个队列保留炉石用于后续任务且传播使用后的冷却",function()
    local B,s,a,nav,O,L,T=hearthFixture()
    B.Progression=A.Progression
    assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B);assert(loadfile("Planner/TaskQueue.lua"))("AiLeveling",B)
    local function choice(id,p) return {questId=id,stagesComplete=true,stages={{position=p,kind="turnin"}},
        remainingXP=1} end
    local queue=B.TaskQueue.Evaluate({choice(1,T),choice(2,L)},s,nav)
    eq(queue.seconds,80);eq(queue.steps[1].timing.flightCount,0);eq(queue.steps[1].timing.hearthCount,1)
    eq(queue.steps[2].timing.hearthCount,0);eq(queue.hearthReady,math.huge)
    s.hearthCooldown=100;queue=B.TaskQueue.Evaluate({choice(1,T),choice(2,L)},s,nav)
    eq(queue.seconds,80);eq(queue.steps[1].timing.hearthCount,1);eq(queue.steps[2].timing.hearthCount,0)
end)
test("三项窗口滚动到全队列且始终包含窗口外任务",function()
    local B,s,nav,O,T,choice=queueFixture()
    s.taxiLandings={}
    local points,choices={},{}
    for i=1,4 do points[i]={map=1,x=i/10,y=0};choices[i]=choice(i,points[i]) end
    local order,queue=B.TaskQueue.Solve(choices,s,nav)
    eq(#order,4);eq(#queue.steps,4);eq(order[1].questId,1)
    local seen={};for _,c in ipairs(order) do assert(not seen[c.questId]);seen[c.questId]=true end
    for i=1,4 do assert(seen[i]) end
    assert(math.abs(queue.seconds-80)<0.000001);eq(s.position,O)
end)
test("位置未知的任务保留并按移动时间比较且保留锁定",function()
    local B,s,nav,O,T,choice=queueFixture()
    local unknown,first,second=choice(777,O),choice(99,T),choice(98,O)
    unknown.stagesComplete=false
    local order,queue=B.TaskQueue.Solve({unknown,first,second},s,nav)
    eq(#order,3);eq(order[3],unknown);eq(#queue.steps,2);eq(queue.remaining,1)
    eq(unknown.executionTiming,nil)
    s.locked=777;eq(B.TaskQueue.Solve({unknown,first,second},s,nav),nil)
    s.locked=nil;eq(B.TaskQueue.Solve({unknown,first,second},s,nav)[3],unknown)
    order,queue=B.TaskQueue.Solve({first,unknown,second},s,nav)
    eq(order[1],second);eq(order[2],first);eq(order[3],unknown);eq(#queue.steps,2);eq(queue.remaining,1)
end)
test("队列连续升级保留客户端曲线口径且未知门槛后停止累计确定经验",function()
    local B,s,nav,O,T,choice=queueFixture()
    B.Experience={version="1.60.1",build="70862",interface=16001,source="test",xpToLevel={[20]=100,[21]=100,[22]=100,[23]=100}}
    assert(loadfile("Planner/Progression.lua"))("AiLeveling",B)
    s.level,s.xp,s.maxXP=20,90,100
    local order={choice(1,O),choice(2,O),choice(3,O)}
    local data={content={},GetQuest=function(_,id) return {id=id,questLevel=20,taskFacts={level=20,xp={{1,100}}}} end}
    local queue=B.TaskQueue.Evaluate(order,s,nav,data)
    eq(queue.forecast.level,23);eq(queue.forecast.xp,90);eq(queue.xp,300);eq(queue.xpKnown,true)
    B.Experience.xpToLevel[21]=nil;queue=B.TaskQueue.Evaluate(order,s,nav,data)
    eq(queue.xpKnown,false);eq(queue.xp,100);eq(queue.forecast.uncertain,true);eq(s.level,20);eq(s.xp,90)
end)
test("原生飞行地图捕获独立快照并在世界变更或期限到期失效",function()
    local old={GetTime=GetTime,GetTaxiMapID=GetTaxiMapID,C_TaxiMap=C_TaxiMap,TaxiNodeCost=TaxiNodeCost,UnitOnTaxi=UnitOnTaxi}
    local now=0
    GetTime=function() return now end;GetTaxiMapID=function() return 1 end;TaxiNodeCost=function() return 110 end;UnitOnTaxi=nil
    C_TaxiMap={GetAllTaxiNodes=function() return {{nodeID=1,state=0,name="起点"},{nodeID=2,state=1,slotIndex=1,name="落地点"}} end}
    C_Map.GetBestMapForUnit=function() return 1 end
    local B={Content={nodes={},transit={}},char={},State={Position=function(_,s) s.position={map=1,x=0.1,y=0.1} end},RequestRefresh=function() end}
    assert(loadfile("Transport.lua"))("AiLeveling",B)
    B.Transport:CaptureTaxi()
    local s={now=0,faction="Alliance",completed={},bags={}}
    B.Transport:Snapshot(s);eq(s.taxiOrigin.id,1);eq(s.taxiNames[2],"落地点")
    s.taxiOrigin.position.x=0.9;s.taxiDepartures[1].x=0.9
    eq(B.Transport.taxiOrigin.position.x,0.1);eq(B.Transport.departures[1].x,0.1)
    now=121;B.Transport:Update();s.now=now;B.Transport:Snapshot(s);eq(s.taxiOrigin,nil)
    now=0;B.Transport:CaptureTaxi();B.Transport:World();eq(B.Transport.taxiOrigin,nil)
    GetTime,GetTaxiMapID,C_TaxiMap,TaxiNodeCost,UnitOnTaxi=old.GetTime,old.GetTaxiMapID,old.C_TaxiMap,old.TaxiNodeCost,old.UnitOnTaxi
end)
test("飞行加速变化清理旧可达信息且重新开图恢复",function()
    local old={GetTime=GetTime,GetTaxiMapID=GetTaxiMapID,C_TaxiMap=C_TaxiMap,TaxiNodeCost=TaxiNodeCost,C_SpellBook=C_SpellBook}
    local B,s=fixture();local learned=false
    B.state=s;B.Content={nodes={},transit={}};B.char={}
    B.State={Position=function(_,snapshot) snapshot.position=s.position end}
    GetTime=function() return s.now end;GetTaxiMapID=function() return 1 end
    C_SpellBook={IsSpellKnown=function() return learned end}
    C_TaxiMap={GetAllTaxiNodes=function() return {{nodeID=1,state=0},{nodeID=2,state=1,slotIndex=2}} end}
    TaxiNodeCost=function() return learned and 55 or 110 end
    C_Map.GetBestMapForUnit=function() return 1 end
    assert(loadfile("Transport.lua"))("AiLeveling",B)
    B.Transport:CaptureTaxi();B.Transport:Snapshot(s)
    eq(s.taxiSpeed,1);eq(s.taxiAvailability["1:2"],true)
    local key=B.Transport.Key(s);learned=true;B.Transport:Snapshot(s)
    eq(s.taxiSpeed,1.2);eq(next(s.taxiAvailability),nil)
    assert(key~=B.Transport.Key(s));eq(s.taxiOrigin,nil)
    B.Transport:CaptureTaxi();B.Transport:Snapshot(s);eq(s.taxiAvailability["1:2"],true)
    learned=false;B.Transport:CaptureTaxi();B.Transport:Snapshot(s);eq(s.taxiAvailability["1:2"],true);eq(s.taxiSpeed,1)
    C_SpellBook=nil;B.Transport:Snapshot(s);eq(s.taxiSpeed,nil);eq(next(s.taxiAvailability),nil)
    for _,name in ipairs({"GetTime","GetTaxiMapID","C_TaxiMap","TaxiNodeCost","C_SpellBook"}) do _G[name]=old[name] end
end)
test("飞行停靠由原生槽位映射为节点且变化触发重算并清理失效路线",function()
    local old={GetTime=GetTime,GetTaxiMapID=GetTaxiMapID,C_TaxiMap=C_TaxiMap,TaxiNodeCost=TaxiNodeCost,
        GetNumRoutes=GetNumRoutes,TaxiGetNodeSlot=TaxiGetNodeSlot}
    GetTime=function() return 0 end;GetTaxiMapID=function() return 1 end;TaxiNodeCost=function() return 110 end
    local nodes={{nodeID=80,state=0,slotIndex=3},{nodeID=25,state=1,slotIndex=7},
        {nodeID=23,state=1,slotIndex=9},{nodeID=999,state=1,slotIndex=4,isMapLayerTransition=true}}
    C_TaxiMap={GetAllTaxiNodes=function() return nodes end}
    local route={{3,7},{7,9}}
    GetNumRoutes=function(slot) return slot==7 and 1 or #route end
    TaxiGetNodeSlot=function(slot,index,source)
        local pair=slot==7 and {3,7} or route[index];return pair[source and 1 or 2]
    end
    local B={Content={nodes={},transit={}},char={},State={Position=function(_,s) s.position={map=1,x=0,y=0} end}}
    assert(loadfile("Transport.lua"))("AiLeveling",B)
    local function snapshot()
        B.Transport:CaptureTaxi();local s={now=0,faction="Horde",completed={},bags={}};B.Transport:Snapshot(s);return s
    end
    local s=snapshot();eq(s.taxiHops["80:23"],"80:25:23");eq(s.taxiHops["80:25"],"80:25");eq(s.taxiHops["80:999"],nil)
    local key=B.Transport.Key(s);s.taxiHops["80:23"]="changed";eq(B.Transport.hops["80:23"],"80:25:23")
    route={{3,9}};s=snapshot();eq(s.taxiHops["80:23"],"80:23");assert(B.Transport.Key(s)~=key)
    for _,bad in ipairs({{{3,7},{3,9}},{{3,7},{7,3}},{{3,4},{4,9}},{{3,7}}}) do
        route=bad;s=snapshot();eq(s.taxiHops["80:23"],nil);eq(s.taxiAvailability["80:23"],true)
    end
    route={{3,9}};s=snapshot();assert(s.taxiHops["80:23"])
    GetNumRoutes=nil;s=snapshot();eq(s.taxiHops["80:23"],nil);eq(s.taxiAvailability["80:23"],true)
    GetNumRoutes=old.GetNumRoutes;B.Transport:InvalidateFlights();eq(next(B.Transport.hops),nil)
    GetTime,GetTaxiMapID,C_TaxiMap,TaxiNodeCost,GetNumRoutes,TaxiGetNodeSlot=old.GetTime,old.GetTaxiMapID,old.C_TaxiMap,old.TaxiNodeCost,old.GetNumRoutes,old.TaxiGetNodeSlot
end)
C_Map=savedMap
test("交错顺序不得提前使用未来交付空位，重复接交也不能重复占用或释放",function()
    local B,s,nav,O,a,b=stagedFixture();B.Supplies=A.Supplies
    s.questLimit=1;s.quests={[1]={ready=true}}
    a.stages={a.stages[2]}
    table.insert(b.stages,1,{kind="accept",questId=2,position={map=1,x=0,y=0}})
    eq(B.TaskQueue.Evaluate({b,a},s,nav),nil)
    assert(B.TaskQueue.Evaluate({a,b},s,nav))
    local log=B.Supplies.QuestLog(s)
    assert(B.Supplies.ApplyQuestLog({kind="accept",questId=1},log));eq(log.questCount,1)
    assert(B.Supplies.ApplyQuestLog({kind="turnin",questId=1},log));eq(log.questCount,0)
    assert(B.Supplies.ApplyQuestLog({kind="turnin",questId=1},log));eq(log.questCount,0)
    assert(B.Supplies.ApplyQuestLog({kind="accept",questId=2},log));eq(log.questCount,1)
    eq(B.Supplies.ApplyQuestLog({kind="accept",questId=3},log),nil)
    eq(log.activeQuests[3],nil);eq(log.questCount,1);assert(s.quests[1]);eq(s.quests[2],nil)
end)

end
