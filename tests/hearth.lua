return function(test,eq,F,A)
local globals={"GetTime","GetBindLocation","C_Item","C_Container","UnitIsDeadOrGhost","GetPlayerFacing"}
local saved={};for _,name in ipairs(globals) do saved[name]=_G[name] end
local now,name,coolStart,coolDuration,pos,dead
local function fixture(learn)
    now,name,coolStart,coolDuration,pos,dead=0,"测试旅店",0,0,{map=1,x=0,y=0},false
    GetTime=function() return now end;GetBindLocation=function() return name end
    C_Item={GetItemSpell=function(id) eq(id,6948);return "炉石",8690 end}
    C_Container={GetItemCooldown=function() return coolStart,coolDuration,1 end}
    UnitIsDeadOrGhost=function() return dead end;GetPlayerFacing=function() return 0 end
    local B={settings={learn=learn~=false,pins=false},char={samples={}},state=F.State(),Content={nodes={}},jobs={},
        QuestAssist={Update=function() end},UI={SetNavigation=function() end},Transport={InFlight=function() return false end,FlightGate=function() end}}
    B.state.clientVersion,B.state.clientBuild,B.state.interface="1.60.1","70862",16001
    B.state.bags={[6948]=1};B.state.bindName=name
    B.RequestRefresh=function() B.wakes=(B.wakes or 0)+1 end;B.Replan=function() end
    B.State={Observe=A.State.Observe,Position=function(_,s)
        s=s or B.state;s.position=pos and {map=pos.map,x=pos.x,y=pos.y} or nil
    end}
    assert(loadfile("Navigation.lua"))("AiLeveling",B)
    assert(loadfile("Hearth.lua"))("AiLeveling",B)
    B.Navigation.hbd={GetZoneDistance=function(_,m,x,y,tm,tx,ty) if m==tm then return math.abs(x-tx)*1000 end end,
        GetWorldCoordinatesFromZone=function(_,x,y) return x,y,0 end,GetWorldVector=function() return 0 end}
    local action={kind="transit",mode="hearth",questId=99,position={map=2,x=0.8,y=0},arrival=12}
    B.Navigation.actions={action,{kind="turnin",questId=99,position=action.position}};B.Navigation.index=1
    return B,action
end
local function snapshot(B)
    B.state.now=now;B.state.bindName=name;B.state.hearthReady=coolDuration>0 and coolStart+coolDuration or now
    B.Hearth:Snapshot(B.state)
end
local function start(B)
    B.Hearth:Event("UNIT_SPELLCAST_START","player","cast-one",8690)
    now=10;coolStart,coolDuration=10,3600
    B.Hearth:Event("UNIT_SPELLCAST_SUCCEEDED","player","cast-one",8690)
end
local function land(B)
    now=15;pos={map=2,x=0.8,y=0}
    B.Hearth:Event("PLAYER_ENTERING_WORLD");snapshot(B);B.State:Position();B.Hearth:Update()
end
test("炉石落点只在本人匹配施法与加载落地后记录并确认步骤",function()
    local B=fixture();snapshot(B);eq(B.state.hearthPoint,nil)
    start(B);assert(B.Hearth:InTransit());eq(B.Navigation:Current().kind,"hearthCast")
    snapshot(B);eq(B.state.hearthPoint,nil)
    land(B);eq(B.state.hearthPoint.map,2);eq(B.state.hearthCooldown,3600);eq(B.Navigation.index,2)
    local sample=B.char.samples[B.Hearth.Key(B.state)];eq(sample.n,1);eq(sample.mean,15)
    B.state.hearthPoint.x=0.2;eq(B.Hearth.landing.position.x,0.8)
    snapshot(B);eq(sample.n,1)
end)
test("中断其他法术缺少起点和超时不能推断炉石落点",function()
    local B=fixture()
    B.Hearth:Event("UNIT_SPELLCAST_START","party1","cast-one",8690);eq(B.Hearth.cast,nil)
    B.Hearth:Event("UNIT_SPELLCAST_START","player","cast-one",1);eq(B.Hearth.cast,nil)
    B.Hearth:Event("UNIT_SPELLCAST_SUCCEEDED","player","cast-one",8690);land(B);eq(B.Hearth.landing,nil)
    B=fixture();B.Hearth:Event("UNIT_SPELLCAST_START","player","cast-one",8690)
    B.Hearth:Event("UNIT_SPELLCAST_INTERRUPTED","player","cast-one",8690);land(B);eq(B.Hearth.landing,nil)
    B=fixture();start(B);now=121;B.Hearth:Update();eq(B.Hearth:InTransit(),false);eq(B.Hearth.landing,nil)
end)
test("同名重新绑定清除旧位置且缺少物品不提供炉石路线端点",function()
    local B=fixture();start(B);land(B);assert(B.state.hearthPoint)
    B.state.bags={};snapshot(B);eq(B.state.hearthPoint,nil)
    B.state.bags={[6948]=1};snapshot(B);assert(B.state.hearthPoint)
    B.Hearth:Event("HEARTHSTONE_BOUND");snapshot(B);eq(B.state.hearthPoint,nil);eq(B.Hearth.landing,nil)
end)
test("关闭学习仍确认本人实际返回但不新增落点或样本",function()
    local B=fixture(false);start(B);land(B)
    eq(B.Navigation.index,2);eq(B.Hearth.landing,nil);eq(next(B.char.samples),nil)
end)
test("加载后坐标暂不可用时重试且清除统计中断本次采样",function()
    local B=fixture();start(B);B.Hearth:Event("PLAYER_ENTERING_WORLD")
    now=15;pos=nil;snapshot(B);B.Hearth:Update();assert(B.wakes>0);eq(B.Hearth.landing,nil)
    now=16;pos={map=2,x=0.8,y=0};snapshot(B);B.Hearth:Update();assert(B.Hearth.landing)
    B=fixture();start(B);B.Hearth:InvalidateSample();land(B)
    eq(next(B.char.samples),nil);eq(B.Hearth.landing,nil);eq(B.Navigation.index,2)
end)
test("加载与成功事件交换顺序仍须匹配同一施法才能记录",function()
    local B=fixture();B.Hearth:Event("UNIT_SPELLCAST_START","player","cast-one",8690)
    now=10;pos={map=2,x=0.8,y=0};B.Hearth:Event("PLAYER_ENTERING_WORLD");snapshot(B);eq(B.Hearth.landing,nil)
    coolStart,coolDuration=10,3600
    B.Hearth:Event("UNIT_SPELLCAST_SUCCEEDED","player","cast-one",8690);snapshot(B);B.Hearth:Update()
    assert(B.Hearth.landing);eq(B.Navigation.index,2)
end)
test("走到绑定点不能代替使用炉石且暂停后不推进",function()
    local B=fixture();pos={map=2,x=0.8,y=0};B.State:Position();B.Navigation:Update();eq(B.Navigation.index,1)
    B=fixture();start(B);B.char.paused=true;land(B);eq(B.Navigation.index,1);eq(B.Hearth.landing,nil)
end)
test("可交付任务的炉石步骤仍提供独立合法物品按钮",function()
    local B,action=fixture();B.state.quests={[99]={ready=true}}
    local desired=A.QuestAssist.Desired(action,B.state,true,{GetQuest=function() error("不应查询任务物品") end})
    eq(#desired,1);eq(desired[1],6948)
end)
for _,key in ipairs(globals) do _G[key]=saved[key] end
end
