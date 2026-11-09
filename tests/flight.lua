return function(test,eq,F,A)
local globals={"UnitOnTaxi","GetTime","GetPlayerFacing","UnitIsDeadOrGhost","UnitIsAFK","IsPlayerMoving","UnitAffectingCombat","CreateFrame","SlashCmdList","debugprofilestop","C_SpellBook"}
local saved={}
for _,key in ipairs(globals) do saved[key]=_G[key] end
local now,flying=0,false
UnitOnTaxi=function(unit) eq(unit,"player");return flying end
GetTime=function() return now end
GetPlayerFacing=function() return 0 end
UnitIsDeadOrGhost=function() return false end
UnitIsAFK=function() return false end
IsPlayerMoving=function() return true end
UnitAffectingCombat=function() return false end
local function position(x,map,node) return {map=map or 1,x=x,y=0,node=node} end
local function fixture(actions)
    now,flying=0,false
    local content={version="v1",nodes={a={position=position(0),accessRadius=20},b={position=position(1)}},
        edges={},transit={f={from="a",to="b",kind="flight",seconds=10,cost=0,verified=true,title="飞往乙地"}}}
    local B={Content=content,Travel=A.Travel,settings={learn=true,pins=false},char={samples={}},jobs={},
        state={position=position(0,1,"a"),quests={},completed={},onTaxi=false},wakes=0,refreshes=0,replans=0,messages=0}
    B.RequestRefresh=function(self) self.wakes=self.wakes+1 end
    B.Replan=function(self) self.replans=self.replans+1 end
    B.Message=function(self) self.messages=self.messages+1 end
    B.QuestAssist={Update=function() end}
    B.UI={SetNavigation=function(_,distance) B.distance=distance end}
    B.State={Observe=A.State.Observe,Refresh=function(_,force)
        eq(force,true);B.refreshes=B.refreshes+1;B.state.onTaxi=flying
    end}
    assert(loadfile("Transport.lua"))("AiLeveling",B)
    assert(loadfile("Navigation.lua"))("AiLeveling",B)
    assert(loadfile("Observations.lua"))("AiLeveling",B)
    local route=A.Travel.Route(content,"a","b",{now=0,money=100})
    B.plan={best={actions=actions or route.actions}}
    B.Navigation:SetPlan(B.plan)
    B.Navigation.lastMap,B.Navigation.lastNode=1,"a"
    B.Navigation.hbd={GetZoneDistance=function(_,m,x,y,tm,tx,ty)
        if m==tm then return math.abs(x-tx)*1000 end
    end,GetWorldCoordinatesFromZone=function(_,x,y,m) return x,y,m end,GetWorldVector=function() return 0 end}
    B.Transport:Update()
    return B
end
local function step(B,time,onTaxi,pos)
    now,flying=time,onTaxi
    B.state.position=pos
    B.Transport:Update()
    B.Navigation:Update()
end
local function start(B)
    step(B,1,true,position(0.1,1,"a"))
end
local function finish(B,pos)
    for t=2,10 do step(B,t,true,position(1,1,"b")) end
    step(B,11,false,pos or position(1,1,"b"))
end

test("飞行前导航出发点且飞越终点不算落地",function()
    local B=fixture()
    B.Navigation:Update();eq(B.distance,0);eq(B.Navigation.index,1)
    local pinX
    B.settings.pins=true
    B.Navigation.pins={{Hide=function() end,texture={SetAtlas=function() end}},
        {Hide=function() end,texture={SetAtlas=function() end}}}
    B.Navigation.hbdPins={RemoveAllWorldMapIcons=function() pinX=nil end,RemoveAllMinimapIcons=function() end,
        AddWorldMapIconMap=function(_,owner,pin,map,x) pinX=x end,AddMinimapIconMap=function() end}
    B.Navigation:RefreshPins();eq(pinX,0)
    B.jobs.plan=coroutine.create(function() error("空中不应继续规划") end)
    start(B);eq(B.jobs.plan,nil);eq(B.Navigation:Current().kind,"flight")
    eq(pinX,nil)
    step(B,2,true,position(1,1,"b"));eq(B.Navigation.index,1);eq(B.replans,0);eq(B.distance,nil)
    eq(#A.QuestAssist.Desired(B.Navigation:Current(),B.state,true,{Get=function() error("飞行门控不应查询任务物品") end}),0)
end)
test("确认落地只结算对应航线且按真实状态刷新",function()
    local B=fixture();start(B);finish(B)
    eq(B.Navigation.index,2);eq(B.refreshes,1);eq(B.Transport.flight,nil)
    local sample=B.char.samples["flight:v1:f"]
    eq(sample.n,1);eq(sample.mean,1);eq(sample.unit,"ratio");eq(B.char.samples.move,nil)
    B.Transport:Update();eq(B.refreshes,1);eq(sample.n,1)
end)
test("无参考航线也仅在有效完整起降后记录独立绝对耗时",function()
    local B=fixture();local action=B.plan.best.actions[1]
    action.referenceSeconds=nil;action.timeSampleKey="flighttime:test:1:2"
    action.fromTaxi,action.toTaxi=1,2
    start(B);finish(B)
    local sample=B.char.samples[action.timeSampleKey]
    eq(sample.n,1);eq(sample.mean,10);eq(sample.unit,"seconds");eq(B.char.samples["flight:v1:f"],nil)
    eq(B.Transport.landings["1:2"].x,1);B.state.position.x=0.8;eq(B.Transport.landings["1:2"].x,1)
    B.Transport:Update();eq(sample.n,1)
    B=fixture();action=B.plan.best.actions[1];action.timeSampleKey="flighttime:test:1:2"
    start(B);finish(B,position(0.5,1,"other"));eq(B.char.samples[action.timeSampleKey],nil)
    for _,invalidate in ipairs({function(b) b.char.paused=true end,function(b) b.settings.learn=false end,
        function(b) b.Navigation.manual=position(0.5) end,function(b) b.Transport:World() end}) do
        B=fixture();action=B.plan.best.actions[1];action.timeSampleKey="flighttime:test:1:2"
        start(B);invalidate(B);finish(B);eq(B.char.samples[action.timeSampleKey],nil)
    end
    B=fixture();action=B.plan.best.actions[1];action.timeSampleKey="flighttime:test:1:2"
    for i=1,128 do B.char.samples["flighttime:old:1:"..i]={n=3,mean=1,m2=0,unit="seconds"} end
    start(B);finish(B)
    local count=0;for k in pairs(B.char.samples) do if k:sub(1,11)=="flighttime:" then count=count+1 end end
    eq(count,128);eq(B.char.samples[action.timeSampleKey].n,1)
end)
test("提前或错误落地点重新规划且不记为完整飞行样本",function()
    local B=fixture();start(B);finish(B,position(0.5,1,"other"))
    eq(B.Navigation.index,1);eq(B.refreshes,1);eq(B.messages,1);eq(B.char.samples["flight:v1:f"],nil)
end)
test("起飞时按最新原生停靠冻结采样键且不中途改写路线身份",function()
    local B=fixture();local action=B.plan.best.actions[1]
    B.FlightData={version="test"};assert(loadfile("Planner/Flights.lua"))("AiLeveling",B)
    B.state.faction="Horde";
    C_SpellBook={IsSpellKnown=function() return false end};B.Transport:SyncFlightSpeed(B.state);action.fromTaxi,action.toTaxi=1,2;action.referenceFlight=true
    action.referenceSeconds,action.sampleKind=nil,nil
    action.timeSampleKey=B.Flights.TimeKey(1,2,"Horde","1:2",1)
    B.Transport.hops={["1:2"]="1:3:2"};start(B)
    B.Transport.hops["1:2"]="1:4:2";finish(B)
    local key=B.Flights.TimeKey(1,2,"Horde","1:3:2",1)
    eq(B.char.samples[key].mean,10);eq(B.char.samples[key].n,1)
    eq(B.char.samples[action.timeSampleKey],nil)
    eq(B.char.samples[B.Flights.TimeKey(1,2,"Horde","1:4:2",1)],nil)
    C_SpellBook=saved.C_SpellBook
end)
test("起降样本按实际加速隔离且途中变化或未知不写入",function()
    for _,mode in ipairs({"base","fast","changed","unknown"}) do
        local B=fixture();local action=B.plan.best.actions[1]
        local learned=mode=="fast"
        B.FlightData={version="test"};assert(loadfile("Planner/Flights.lua"))("AiLeveling",B)
        C_SpellBook={IsSpellKnown=function() if mode~="unknown" then return learned end end}
        B.state.faction="Horde";action.fromTaxi,action.toTaxi=1,2;action.referenceFlight=true
        action.referenceSeconds,action.sampleKind=nil,nil
        B.Transport:SyncFlightSpeed(B.state);B.Transport.hops={["1:2"]="1:2"}
        start(B)
        if mode=="changed" then learned=true end
        finish(B)
        eq(B.Navigation.index,2);eq(B.refreshes,1)
        if mode=="changed" or mode=="unknown" then eq(next(B.char.samples),nil)
        else
            local speed=learned and 1.2 or 1
            eq(B.char.samples[B.Flights.TimeKey(1,2,"Horde","1:2",speed)].mean,10)
            eq(B.char.samples[B.Flights.TimeKey(1,2,"Horde","1:2",learned and 1 or 1.2)],nil)
        end
    end
    C_SpellBook=saved.C_SpellBook
end)
test("飞行落点使用大陆投影时按同世界距离确认且距离未知不结算",function()
    local B=fixture();local action=B.plan.best.actions[1]
    action.position=position(0.4,9);action.arrival=25
    action.fromTaxi,action.toTaxi=1,2
    B.Navigation.hbd.GetZoneDistance=function(_,m,x,y,tm,tx,ty)
        if m==tm then return math.abs(x-tx)*1000 end
        if m==1 and tm==9 then return math.abs(x-(tx+0.6))*1000 end
    end
    start(B);finish(B)
    eq(B.Navigation.index,2);eq(B.messages,0);eq(B.Transport.landings["1:2"].map,1)
    B=fixture();action=B.plan.best.actions[1];action.position=position(1,9)
    start(B);finish(B)
    eq(B.Navigation.index,1);eq(B.messages,1);eq(next(B.char.samples),nil)
end)
test("未观察到完整起飞和非计划航班保持实际落地重算",function()
    local B=fixture();B.Transport:World();start(B);finish(B)
    eq(B.Navigation.index,1);eq(B.refreshes,1);eq(next(B.char.samples),nil)
    B=fixture();step(B,0.5,false,position(0.5));start(B);finish(B)
    eq(B.Navigation.index,1);eq(B.refreshes,1);eq(next(B.char.samples),nil)
    B=fixture({{kind="objective",questId=1,position=position(1)}});start(B);finish(B)
    eq(B.Navigation.index,1);eq(B.refreshes,1);eq(next(B.char.samples),nil)
end)
test("登录时已在飞行中不反推起点或完整耗时",function()
    local B=fixture();B.Transport.wasFlying=nil
    start(B);eq(B.Transport.flight.action,nil);finish(B)
    eq(B.Navigation.index,1);eq(B.refreshes,1);eq(next(B.char.samples),nil)
end)
test("出发点附近未处理的移动动作可接续真实起飞",function()
    local B=fixture();local flight=B.plan.best.actions[1]
    B.Navigation.actions={{kind="move",node="a",position=position(0)},flight}
    B.Navigation.index=1;start(B);eq(B.Navigation.index,2);eq(B.Transport.flight.action,flight)
    finish(B);eq(B.Navigation.index,3);eq(B.char.samples["flight:v1:f"].n,1)
end)
test("落地无坐标时等待定位且等待时间不算飞行耗时",function()
    local B=fixture();start(B)
    for t=2,10 do step(B,t,true,position(0.5)) end
    step(B,11,false,nil);eq(B.refreshes,0);eq(B.Navigation:Current().kind,"flight")
    for t=12,20 do step(B,t,false,nil) end
    step(B,21,false,position(1,1,"b"));eq(B.refreshes,1);eq(B.char.samples["flight:v1:f"].mean,1)
end)
test("飞行暂停关闭学习重载和帧中断排除耗时样本",function()
    for _,change in ipairs({
        function(B) B.char.paused=true end,
        function(B) B.settings.learn=false end,
        function(B) B.Transport:World() end,
        function(B) B.char.samples={};B.Transport:InvalidateSample() end,
        function(B) now=5 end,
    }) do
        local B=fixture();start(B);change(B)
        step(B,math.max(now,2),true,position(0.5))
        B.char.paused=false;B.settings.learn=true
        for t=math.max(now+1,3),10 do step(B,t,true,position(0.5)) end
        step(B,11,false,position(1,1,"b"));eq(B.refreshes,1);eq(next(B.char.samples),nil)
    end
end)
test("飞行保留手动目的地且不混入步行校准",function()
    local B=fixture({{kind="move",position=position(1),referenceSeconds=10}})
    B.Navigation.manual=position(0.7)
    start(B);eq(B.Navigation:Current().kind,"flight")
    B.Observations:Update();eq(B.Observations.current,nil)
    finish(B);eq(B.Navigation:Current().kind,"manual");eq(B.Navigation.manual.x,0.7);eq(next(B.char.samples),nil)
end)
test("航线校准按内容版本隔离且不受装备上下文降权",function()
    local B=fixture();local key=A.Travel.FlightKey("f","v1")
    B.char.samples[key]={n=10,mean=2,m2=0,unit="ratio"}
    B.char.sampleContext="old"
    B.Observations:Context({class="MAGE",role="DAMAGER",level=20,equipment={}})
    eq(B.char.samples[key].n,10)
    local route=A.Travel.Route(B.Content,"a","b",{now=0,money=100,samples=B.char.samples})
    eq(route.seconds,15)
    B.Content.version="v2"
    route=A.Travel.Route(B.Content,"a","b",{now=0,money=100,samples=B.char.samples});eq(route.seconds,10)
end)
test("原生飞行状态变化进入决策指纹",function()
    local a={unlocked={},onTaxi=false,now=0}
    local B=fixture();local old=B.Transport.Key(a);a.onTaxi=true
    assert(B.Transport.Key(a)~=old)
end)
test("空中规划门控并丢弃起飞前尚未发布的计算",function()
    local B=fixture();local queued,called
    local scripts={}
    CreateFrame=function() return {RegisterEvent=function() end,SetScript=function(_,key,fn) scripts[key]=fn end} end
    SlashCmdList={}
    assert(loadfile("Core.lua"))("AiLeveling",B)
    B.ready=true;B.char={};B.state.revision=1
    B.Queue=function(_,_,fn) queued=fn end
    B.Planner={Build=function() called=(called or 0)+1;return {} end,Choose=function() error("不应发布过期计划") end}
    B:Replan();assert(queued)
    flying=true;queued();eq(B.plan.best.actions[1].mode,"flight");eq(called,1)
    queued=nil;B:Replan();eq(queued,nil);eq(B.jobs.plan,nil)
    B.jobs.plan=coroutine.create(function() error("空中不应恢复地面搜索") end)
    debugprofilestop=function() return 0 end
    scripts.OnUpdate(nil,0);eq(B.jobs.plan,nil)
end)

for _,key in ipairs(globals) do _G[key]=saved[key] end
end
