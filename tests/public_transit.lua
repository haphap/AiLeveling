return function(test,eq,F,A,plan)
local function fixture()
    local B={};for k,v in pairs(A) do B[k]=v end
    for _,file in ipairs({"Data/PublicTransit.lua","Planner/Flights.lua","Planner/TaskGuide.lua","Planner/Planner.lua"}) do
        assert(loadfile(file))("AiLeveling",B)
    end
    local s=F.State();s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    s.faction="Alliance";s.position={map=1,x=0,y=0};s.money=0
    B.PublicTransitData.legs={
        {key="public:1:0",kind="boat",from={map=1,x=0.1,y=0},to={map=2,x=0.2,y=0},fromName="出发码头",toName="到达码头",seconds=100,low=60,high=140,cost=0},
        {key="public:1:1",kind="boat",from={map=2,x=0.2,y=0},to={map=1,x=0.1,y=0},fromName="到达码头",toName="出发码头",seconds=110,low=70,high=150,cost=0},
    }
    B.Navigation={Distance=function(_,a,b)
        if a and b and a.map==b.map then return math.abs(a.x-b.x)*700 end
    end}
    return B,s,B.PublicTransitData.legs
end
test("公共交通跨大陆双向接续且不依赖金币或解锁飞行点",function()
    local B,s,legs=fixture();local target={map=2,x=0.5,y=0}
    local routes=B.Flights.Routes(s.position,target,s,B.Navigation)
    eq(#routes,1);eq(routes[1].seconds,140);eq(routes[1].flights,0)
    eq(routes[1].legs[2],legs[1])
    local reverse=B.Flights.Routes(target,s.position,s,B.Navigation);eq(reverse[1].seconds,150)
    s.money=nil;assert(B.Flights.Routes(s.position,target,s,B.Navigation))
    s.clientVersion="other";eq(B.Flights.Routes(s.position,target,s,B.Navigation),nil)
    s.clientVersion="1.60.1";s.clientBuild="70862";legs[1].faction="Horde";eq(B.Flights.Routes(s.position,target,s,B.Navigation),nil)
    s.faction="Horde";assert(B.Flights.Routes(s.position,target,s,B.Navigation))
    s.inInstance=true;eq(B.Flights.Routes(s.position,target,s,B.Navigation),nil)
    s.inInstance=false;s.dead=true;eq(B.Flights.Routes(s.position,target,s,B.Navigation),nil)
    assert(loadfile("Data/PublicTransit.lua"))("AiLeveling",B)
    s.inInstance=false;s.dead=false;s.faction="Alliance";s.unlocked={};s.taxiAvailability={}
    local ship,returnShip
    for _,leg in ipairs(B.PublicTransitData.legs) do
        if leg.from.map==1453 and leg.to.map==1439 then ship=leg end
        if leg.from.map==1439 and leg.to.map==1453 then returnShip=leg end
    end
    assert(ship and returnShip)
    routes=B.Flights.Routes(ship.from,ship.to,s,B.Navigation)
    eq(routes[1].seconds,ship.seconds);eq(routes[1].flights,0);eq(routes[1].legs[2],ship)
    routes=B.Flights.Routes(ship.to,ship.from,s,B.Navigation);eq(routes[1].seconds,returnShip.seconds)
    local byKey={};for _,leg in ipairs(B.PublicTransitData.legs) do byKey[leg.key]=leg end
    local first,second,through=byKey["public:11167:0:1"],byKey["public:11167:1:2"],byKey["public:11167:0:2"]
    -- Menethil reaches Auberdine via Southshore, staying aboard through its stop.
    eq(through.low,first.low+60+second.low)
    eq(through.seconds-through.low,first.seconds-first.low)
    routes=B.Flights.Routes(through.from,through.to,s,B.Navigation)
    eq(routes[1].legs[2],through);eq(routes[1].seconds,through.seconds)
    eq(byKey["public:303:0"].to.map,1444);eq(byKey["public:303:1"].from.map,1444)
    eq(byKey["public:303:2"],nil)
end)
test("公共交通与炉石比较并给出具体上下船指引",function()
    local B,s,legs=fixture();local target=legs[1].to
    B.Hearth={Duration=function() return 20,20,20,false end}
    s.hearthPoint=target;s.hearthBindingKey="test";s.bags[6948]=1;s.hearthReady=0;s.hearthCooldown=3600
    local routes=B.Flights.Routes(s.position,target,s,B.Navigation)
    eq(#routes,2);eq(routes[1].hearths,1);eq(routes[2].hearths,0)
    local action={kind="objective",questId=9,title="目标",position=target}
    local actions=B.Flights.Actions(routes[2],action,B.Navigation)
    eq(actions[1].kind,"transit");eq(actions[1].mode,"boat");eq(actions[1].departure,legs[1].from)
    assert(actions[1].text:find("出发码头",1,true));assert(actions[1].text:find("到达码头",1,true))
    assert(not actions[1].text:find("分钟",1,true));eq(actions[#actions],action)
    legs[1].kind="tram";legs[1].fromName="暴风城地铁入口";legs[1].toName="铁炉堡地铁入口"
    actions=B.Flights.Actions(routes[2],action,B.Navigation)
    eq(actions[1].mode,"tram");eq(actions[1].publicTransit,true)
    eq(actions[1].fromName,"暴风城地铁入口");eq(actions[1].travelWait,40);eq(actions[1].travelRide,60)
    assert(actions[1].text:find("乘坐开往铁炉堡地铁入口的地铁",1,true))
end)
test("跨大陆未接任务进入完整收益比较并保留真实接交事件",function()
    local B,s=fixture();local q=F.Quest(1);q.verified=false;q.questLevel=s.level
    q.taskFacts={level=s.level,xp={{1,1000}},rewards={items={},choices={}}}
    local d=F.Data({[1]=q});d.Target=function() return {map=2,x=0.5,y=0} end
    d.ReferenceObjectiveTargets=function() return {{text="目标"}},{d:Target()},false end
    d.ObjectiveTargets=function() return {{map=2,x=0.5,y=0,objectiveIndex=1}} end
    local p=plan(s,d,nil,B);eq(p.fallback.questId,1);eq(p.fallback.kind,"accept")
    assert(p.taskChoices[1].timing.seconds);eq(p.travelActions[1].mode,"boat")
    eq(s.quests[1],nil);eq(s.completed[1],nil)
    s.position=d:Target();p=plan(s,d,nil,B);eq(p.fallback.kind,"accept")
    s.quests[1]={ready=true,objectives={}};p=plan(s,d,nil,B);eq(p.fallback.kind,"turnin")
    eq(s.completed[1],nil)
    -- QuestieDB's tram area has no map; use existing city entrances and name the platform.
    for _,file in ipairs({"Data/PublicTransit.lua","Data/Questie.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    local oldMap,oldQuest=C_Map,C_QuestLog
    C_Map={GetMapInfo=function(id) return {mapID=id} end};C_QuestLog={}
    local npcs={[12997]="蒙提",[13016]="矿道老鼠",[13018]="尼普希"}
    B.Data.maps={[2257]=0}
    B.Data.db={Npc={Get=function(id,key)
        if key=="name" then return npcs[id] elseif key=="spawns" and npcs[id] then return {[2257]={{-1,-1}}} end
    end},Quest={Get=function(id,key)
        if key=="startedBy" then return {{12997}} end
        if key=="finishedBy" then return {{id==6661 and 12997 or 13018}} end
        if key=="objectives" then return id==6661 and {{{13016}}} or {} end
    end},Object={Get=function() end},Item={Get=function() end}}
    s.quests={};s.position={map=1455,x=0.78,y=0.51}
    for _,id in ipairs({6661,6662}) do
        local quest=F.Quest(id);quest.questLevel=10;quest.zoneOrSort=2257
        quest.taskFacts={level=10,complex=false,objectives=id==6661 and {{kind="npc",id=13016,count=5}} or {}}
        local start=B.Data:Target(quest,s)
        eq(start.map,1455);eq(start.approximate,true);assert(start.travelHint:find("蒙提",1,true))
        local stages,complete=B.TaskGuide.Stages(quest,s,B.Data,{kind="accept",questId=id,position=start})
        assert(complete);eq(stages[#stages].position.map,id==6661 and 1455 or 1453)
        assert(stages[#stages].text:find(id==6661 and "铁炉堡" or "暴风城",1,true))
        if id==6661 then eq(stages[2].targetId,13016);eq(stages[2].need,5) end
        eq(s.quests[id],nil);eq(s.completed[id],nil)
    end
    C_Map,C_QuestLog=oldMap,oldQuest
end)
test("后续目标未定位仍安排当前跨大陆接取且不补造整程收益",function()
    local B,s=fixture();local q=F.Quest(1);q.verified=false;q.questLevel=s.level
    q.taskFacts={level=s.level,xp={{1,1000}},rewards={items={},choices={}}}
    local d=F.Data({[1]=q});d.Target=function() return {map=2,x=0.5,y=0} end
    d.ReferenceObjectiveTargets=function() return {{text="接取后确认目标"}},{},false end
    local p=plan(s,d,nil,B)
    eq(p.fallback.kind,"accept");eq(p.taskChoices[1].stagesComplete,false)
    eq(p.taskChoices[1].timing.seconds,nil);eq(p.taskChoices[1].timing.travelPlan,nil)
    assert(p.referenceJourney,"current reachable leg must retain transit when later stages are unknown")
    eq(p.travelActions[1].mode,"boat");eq(p.travelActions[#p.travelActions],p.fallback)
    eq(s.completed[1],nil);eq(s.quests[1],nil)
    s.position=d:Target();p=plan(s,d,nil,B);eq(p.fallback.kind,"accept");eq(s.quests[1],nil)
    s.locked=1;s.position={map=3,x=0.1,y=0};p=plan(s,d,nil,B)
    eq(p.travelActions,nil);eq(p.referenceJourney,nil)
end)
test("船舶导航在码头等候跨图保持并只推进到站步骤",function()
    local B,s,legs=fixture();assert(loadfile("Navigation.lua"))("AiLeveling",B)
    local n=B.Navigation;local distance=function(_,a,b) if a and b and a.map==b.map then return math.abs(a.x-b.x)*700 end end
    n.Distance=distance;n.hbd={GetWorldCoordinatesFromZone=function(_,x,y,map) return x,y,map end,GetWorldVector=function() return 0 end}
    B.state=s;B.char={};B.settings={};B.QuestAssist={Update=function() end};B.UI={SetNavigation=function() end}
    B.Transport=nil;B.Hearth=nil;B.Dungeon=nil
    local replans=0;B.Replan=function() replans=replans+1 end
    local oldTime,oldFacing=GetTime,GetPlayerFacing;GetTime=function() return 100 end;GetPlayerFacing=function() return 0 end
    local goal={kind="objective",questId=9,position={map=2,x=0.5,y=0}}
    local route=B.Flights.Routes(s.position,goal.position,s,{Distance=distance})[1]
    local actions=B.Flights.Actions(route,goal,n);B.plan={unverified=true,fallback=goal,travelActions=actions}
    n:SetPlan(B.plan);eq(n.Target(n:Current()),legs[1].from)
    s.position=legs[1].from;n:Update();eq(n:Current().mode,"boat")
    n:Update();local transit=n:Current();assert(transit.atDeparture);eq(n.Target(transit),legs[1].to)
    s.position=nil;n:Update();eq(n:Current(),transit)
    s.position={map=3,x=0.5,y=0};n:Update();eq(replans,0)
    n:SetPlan({fallback=goal});eq(n:Current(),transit)
    eq(s.completed[9],nil);eq(s.quests[9],nil)
    s.position=legs[1].to;n:Update();eq(n:Current(),goal)
    s.position=goal.position;n:Update();eq(n:Current(),goal);eq(s.completed[9],nil)
    -- A different manual selection, task status change or death must release the old journey.
    n.actions={transit,goal};n.index=1;n:SetPlan({fallback={kind="turnin",questId=9}});eq(n:Current().kind,"turnin")
    n.actions={transit,goal};n.index=1;n:SetPlan({fallback={kind="objective",questId=10}});eq(n:Current().questId,10)
    n.actions={transit,goal};n.index=1
    local changed={kind="objective",questId=9,position={map=2,x=0.6,y=0}}
    n:SetPlan({fallback=changed});eq(n:Current(),changed)
    n.actions={transit,goal};n.index=1;s.dead=true;n:SetPlan({fallback=goal});eq(n:Current(),goal)
    GetTime,GetPlayerFacing=oldTime,oldFacing
end)
end
