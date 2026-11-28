return function(test,eq,F,A,setupMap)
local function point(x,y,map) return {map=map or 1,x=x,y=y} end
local function engine()
    local B={Travel=A.Travel,settings={routes=true},char={},Navigation={index=1,actions={}},state={position=point(0,0)},
        Transport={InFlight=function() return false end,FlightGate=function() end},UI={}}
    assert(loadfile("Navigation.lua"))("AiLeveling",B)
    assert(loadfile("Routes.lua"))("AiLeveling",B)
    return B
end
test("目的地连线与当前交通停靠点一致",function()
    local B=engine();local a,b,c=point(0,0),point(1,1),point(1,1,2)
    local boat={kind="transit",publicTransit=true,departure=b,position=c}
    local _,_,tx=B.Routes.Endpoints(a,B.Navigation.Target(boat),1)
    eq(tx,1);boat.atDeparture=true
    eq(B.Routes.Endpoints(a,B.Navigation.Target(boat),1),nil)
    eq(B.Routes.Endpoints(c,c,2),nil)
end)
test("总览坐标转换须匹配世界实例且区域楼层只精确匹配",function()
    local B=engine()
    local hbd={GetWorldCoordinatesFromZone=function(_,x,y,map) return x*100,y*100,map==1 and 100 or 200 end,
        GetZoneCoordinatesFromWorldInstance=function(_,x,y,instance) if instance==100 then return x/100,y/100 end end}
    eq(B.Routes.Project(point(0.5,0.5),10,hbd,false),nil)
    eq(B.Routes.Project(point(0.5,0.5),10,hbd,true),0.5)
    eq(B.Routes.Project(point(0.5,0.5,2),10,hbd,true),nil)
end)
local function widget()
    local w={shown=true}
    w.SetSize=function(self,x,y) self.width,self.height=x,y end;w.GetSize=function(self) return self.width,self.height end
    w.SetAllPoints=function() end;w.SetPoint=function() end;w.ClearAllPoints=function() end
    w.Show=function(self) self.shown=true end;w.Hide=function(self) self.shown=false end;w.IsShown=function(self) return self.shown end
    w.SetStartPoint=function(self,anchor,parent,x,y) self.start={x,y} end
    w.SetEndPoint=function(self,anchor,parent,x,y) self.finish={x,y} end
    w.SetThickness=function(self,n) self.thickness=n end
    w.SetTexture=function() end;w.SetTexCoord=function() end;w.SetVertexColor=function() end
    w.CreateLine=function() return widget() end
    return w
end
test("原生地图绘制目的地直线且关闭和换图清除旧连线",function()
    local saved={CreateFrame=CreateFrame,WorldMapFrame=WorldMapFrame,Enum=Enum,C_Map=C_Map}
    local B=engine();CreateFrame=function() return widget() end
    local canvas=widget();canvas:SetSize(1000,500)
    local map=1;WorldMapFrame=widget();WorldMapFrame.GetCanvas=function() return canvas end;WorldMapFrame.GetMapID=function() return map end
    Enum={UIMapType={World=1,Continent=2,Zone=3}};C_Map={GetMapInfo=function() return {mapType=3} end}
    B.UI.ClassColor=function() return 0.2,0.8,0.7 end
    B.Navigation.actions={{kind="objective",position=point(1,0)},{kind="move",position=point(0.6,0.6)}}
    B.Routes:Update();assert(B.Routes.line.shown)
    eq(B.Routes.line.start[1],0);eq(B.Routes.line.finish[1],1000)
    B.Navigation.waypointDisplay="itinerary";B.Routes:Update();eq(B.Routes.line.shown,false)
    B.Navigation.waypointDisplay=nil;B.Routes:Update();eq(B.Routes.line.shown,true)
    B.settings.routes=false;B.Routes:Update();eq(B.Routes.line.shown,false)
    B.settings.routes=true;map=2;B.Routes:Update();eq(B.Routes.line.shown,false)
    for key,value in pairs(saved) do _G[key]=value end
    if saved.WorldMapFrame==nil then WorldMapFrame=nil end
    if saved.Enum==nil then Enum=nil end
end)
test("点任务标记聚焦原生地图范围，保留导航和原生选择",function()
    local B=setupMap()
    local nav=B.Navigation
    local oldOpen,oldDetail,oldTooltip=OpenWorldMap,QuestMapFrame_GetDetailQuestID,GameTooltip
    local oldRegistry,oldSuper=EventRegistry,C_SuperTrack
    local superChanged
    EventRegistry={RegisterFrameEventAndCallback=function(_,event,callback) eq(event,"SUPER_TRACKING_CHANGED");superChanged=callback end}
    local tracked,trackingType
    Enum={SuperTrackingType={Quest=1,UserWaypoint=2}}
    C_SuperTrack={GetSuperTrackedQuestID=function() return tracked end,GetHighestPrioritySuperTrackingType=function() return trackingType end}
    local map={shown=true,id=1,events={}}
    function map:IsShown() return self.shown end
    function map:GetMapID() return self.id end
    function map:HookScript(event,fn) eq(event,"OnHide");self.hide=fn end
    function map:RegisterCallback(event,fn) self.events[event]=fn end
    function map:SetFocusedQuestID(id) self.focus=id;self.events.SetFocusedQuestID() end
    function map:ClearFocusedQuestID() self.focus=nil;self.events.ClearFocusedQuestID() end
    WorldMapFrame=map
    local opens=0
    OpenWorldMap=function(id) opens=opens+1;map.shown=true;map.id=id end
    GameTooltip={Hide=function() end}
    local goal={kind="objective",questId=42,objectiveIndex=1,position=point(.3,.4,2)}
    local pickup={kind="accept",questId=43,position=point(.2,.3,2)}
    local q={objectives={{type="item"}}};B.state.quests[42]=q
    nav:SetPlan({fallback=goal,taskChoices={{questId=43,actions={pickup}}}})
    local function click(i,button) local pin=nav.pins[i];pin.scripts.OnClick(pin,button or "LeftButton") end
    click(1);eq(opens,1);eq(map.id,2);eq(map.focus,42);eq(nav.manual.action,goal)
    click(1);eq(opens,1);eq(map.focus,42)
    click(1,"RightButton");eq(map.focus,nil);eq(nav.manual,nil)
    map.shown=false;nav.waypointDisplay="itinerary";nav:DrawPins();eq(nav.pins[2].alpha,0)
    click(2);eq(opens,2);eq(map.focus,42);eq(nav.manual.action,goal)
    tracked=77;trackingType=2;superChanged();eq(map.focus,42)
    trackingType=1;superChanged();eq(map.focus,nil)
    click(2);map:SetFocusedQuestID(77);click(2,"RightButton");eq(map.focus,77)
    click(2);q.objectives[1].finished=true;nav:DrawPins();eq(map.focus,nil)
    q.objectives[1].finished=false;nav:ClearManual(false);click(1)
    map.hide();eq(map.focus,nil)
    nav:ClearManual(false);nav:SetPlan({fallback=pickup});click(1);eq(map.focus,nil);eq(nav.manual.action,pickup)
    EventRegistry,C_SuperTrack=oldRegistry,oldSuper
    OpenWorldMap,QuestMapFrame_GetDetailQuestID,GameTooltip=oldOpen,oldDetail,oldTooltip
    B.finish()
end)
test("同处交付与原生问号共用图标，保留行程序号和小地图",function()
    local B=setupMap()
    local nav=B.Navigation
    local oldHook,oldTimer=hooksecurefunc,C_Timer
    local queued,sourceID,sourceX=nil,2,300
    local callbacks={}
    hooksecurefunc=function(_,name,fn) callbacks[name]=fn end
    C_Timer={After=function(_,fn) assert(not queued);queued=fn end}
    local native={shown=true,GetQuestID=function() return sourceID end,IsShown=function(self) return self.shown end,
        GetCenter=function() return sourceX,400 end,GetEffectiveScale=function() return 1 end,
        HookScript=function(self,name,fn) self[name]=fn end}
    WorldMapFrame={IsShown=function() return true end,HookScript=function() end,
        EnumeratePinsByTemplate=function(_,which) eq(which,"QuestPinTemplate");return coroutine.wrap(function() coroutine.yield(native) end) end}
    nav.hbd={GetZoneDistance=function(_,_,x,y,_,ox,oy) return 1000*math.sqrt((ox-x)^2+(oy-y)^2) end}
    local function quest(id,x,npc)
        B.state.quests[id]={ready=true}
        return {kind="turnin",questId=id,position={map=1,x=x,y=.81,entityId=npc,entityKind="npc"}}
    end
    local first,second,far,neighbor=quest(1,.424,51),quest(2,.425,51),quest(3,.65,51),quest(4,.427,52)
    nav.actions={first,second,far,neighbor};nav:DrawPins()
    local pin=nav.pins[1]
    eq(#pin.point.actions,2);eq(nav.pins[3].action,far);eq(nav.pins[5].action,neighbor)
    local function flush() local fn=assert(queued);queued=nil;fn() end
    callbacks.AcquirePin(WorldMapFrame,"QuestPinTemplate");flush()
    eq(pin.texture.shown,false);eq(pin.face.shown,false);eq(pin.ring.shown,false)
    eq(pin.badge.shown,true);eq(pin.number.value,"1");eq(nav.pins[2].texture.shown,true)
    eq(nav.pins[3].texture.shown,true)
    native.shown=false;native:OnHide();flush();eq(pin.texture.shown,true)
    native.shown=true;native:OnShow();flush();eq(pin.texture.shown,false)
    sourceX=500;callbacks.OnCanvasScaleChanged();flush();eq(pin.texture.shown,true)
    sourceX=300;sourceID=4;callbacks.AcquirePin(WorldMapFrame,"QuestPinTemplate");flush()
    eq(pin.texture.shown,true);eq(nav.pins[5].texture.shown,false)
    nav.actions={{kind="move",position=point(.43,.81)}};nav:DrawPins()
    eq(nav.pins[1].face.shown,true);eq(queued,nil)
    hooksecurefunc,C_Timer=oldHook,oldTimer;B.finish()
end)
test("地图标记按任务阶段合并并移除失效的导航步骤",function()
    local B,adds=setupMap()
    for _,kind in ipairs({"accept","turnin","objective","transit","dungeonEnter"}) do
        B.Navigation.actions={{kind=kind,mode="flight",position={map=1,x=0.5,y=0.5}}}
        B.Navigation:RefreshPins()
        local tex=B.Navigation.pins[1].texture
        local icons={accept="accept",turnin="pending",objective="target",transit="flight",dungeonEnter="entry"}
        eq(tex.texture,B.UI.IconTexture(icons[kind]))
    end
    -- Exercise the same log objective on both map layers, including reused pins.
    local stage={kind="objective",questId=77,objectiveIndex=1,position={map=1,x=0.5,y=0.5}}
    B.Navigation.actions={stage}
    for kind,icon in pairs({monster="objective",item="collect",object="interact",talkto="talk",spell="spell",
        areaTrigger="location",reputation="reputation",event="target"}) do
        B.state.quests[77]={objectives={{type=kind}}}
        B.Navigation:RefreshPins()
        eq(B.Navigation.pins[1].texture.texture,B.UI.IconTexture(icon))
        eq(B.Navigation.pins[2].texture.texture,B.Navigation.pins[1].texture.texture)
    end
    B.state.quests[77]=nil
    local current={kind="objective",questId=1,title="当前目标",position={map=1,x=0.1,y=0.2}}
    local nextGoal={kind="objective",questId=2,expected=true,title="跨区目标",position={map=2,x=0.3,y=0.4}}
    local steps={{stage=current},{stage=nextGoal}}
    for id=2,6 do
        local action={kind="turnin",questId=id,expected=true,title="一起交付 "..id,position={map=1,x=0.7,y=0.2}}
        steps[#steps+1]=id==2 and {choice={stages={action}}} or {stage=action}
    end
    B.Navigation:SetPlan({fallback=current,taskQueue={steps=steps}})
    B.settings.pins,B.settings.minimapPins=true,true;adds.world,adds.mini=0,0
    B.Navigation:RefreshPins();eq(adds.world,3);eq(adds.mini,1)
    local pins=B.Navigation.pins
    eq(pins[1].point.action,current);eq(pins[3].point.action,nextGoal);eq(pins[3].point.position.map,2)
    eq(#pins[5].point.actions,5);eq(pins[5].number.value,"3");eq(pins[2].floats,true);eq(pins[2].number,nil);eq(pins[4],nil)
    B.Navigation.waypointDisplay="itinerary";B.Navigation:DrawPins()
    eq(pins[1].shown,true);eq(pins[1].alpha,0);eq(pins[2].alpha,0);eq(pins[3].shown,true);eq(pins[5].shown,true)
    B.Navigation:RefreshPins();eq(pins[1].shown,true);eq(pins[1].alpha,1);eq(pins[2].floats,true)
    local oldTooltip,tooltip=GameTooltip,{lines={}}
    GameTooltip={SetOwner=function() end,SetText=function(_,text) tooltip.title=text end,
        AddLine=function(_,text) tooltip.lines[#tooltip.lines+1]=text end,Show=function() end,Hide=function() end}
    pins[5].scripts.OnEnter(pins[5]);eq(#tooltip.lines,6)
    assert(tooltip.title:find("一起交付 2",1,true));assert(tooltip.lines[5]:find("完成后交付 · 一起交付 6",1,true))
    pins[2].onEdge=true;B.Navigation:Update();eq(pins[2].arrow.shown,true)
    pins[2].onEdge=false;B.Navigation:Update();eq(pins[2].arrow.shown,false)
    -- One giver can accept a finished quest even while other hand-ins there are future steps.
    B.state.quests[4]={ready=true,title="可以交付"}
    B.Navigation:RefreshPins()
    eq(pins[6].action.questId,4);eq(pins[6].floats,false)
    eq(pins[6].texture.texture,B.UI.IconTexture("turnin"));eq(pins[5].number.value,"3")
    tooltip.lines={};pins[6].scripts.OnEnter(pins[6]);eq(tooltip.title,"可以交付")
    eq(tooltip.lines[1],"交付任务");eq(#tooltip.lines,2)
    B.state.quests[4]=nil;B.Navigation:RefreshPins();eq(pins[6].shown,false)
    GameTooltip=oldTooltip
    B.Navigation.manual={map=3,x=0.5,y=0.5};adds.world,adds.mini=0,0
    B.Navigation:RefreshPins();eq(adds.world,1);eq(adds.mini,1);eq(pins[3].shown,false);eq(pins[6].shown,false)
    B.Navigation.manual=nil;adds.world,adds.mini=0,0;B.Navigation:RefreshPins();eq(adds.world,3);eq(adds.mini,1)
    B.Navigation.plan={};B.Navigation.actions={nextGoal};adds.world,adds.mini=0,0
    B.Navigation:RefreshPins();eq(adds.world,1);eq(adds.mini,1);eq(pins[1].point.action,nextGoal);eq(pins[5].shown,false)
    local journey={}
    for i=1,7 do journey[i]={kind="move",position={map=2,x=i/10,y=0.5}} end
    local pickup={kind="accept",questId=93585,position={map=1435,x=0.2222,y=0.5023}}
    B.Navigation.actions=journey;B.settings.mapTaskScope="route";B.Navigation.upcomingQuest=pickup
    local points=B.Navigation:MapPoints();eq(#points,7);eq(points[7].action,pickup);eq(points[7].upcoming,true)
    B.Navigation.actions={nextGoal};B.Navigation.upcomingQuest=nil;B.settings.mapTaskScope=nil
    B.Navigation.plan={taskChoices={{questId=2,stages={nextGoal,steps[3].choice.stages[1]}},
        {questId=7,stages={{kind="accept",position={map=4,x=0.1,y=0.1}}}}}}
    B.Navigation:RefreshPins();eq(#B.Navigation:MapPoints(),2);eq(pins[3].point.action,steps[3].choice.stages[1])
    B.char.paused=true;adds.world,adds.mini=0,0;B.Navigation:RefreshPins();eq(adds.world,0);eq(adds.mini,0);eq(pins[1].shown,false)
    eq(B.Navigation.index,1);eq(next(B.state.completed),nil);eq(current.kind,"objective")
    B.char.paused=false;B.Navigation:SetPlan({fallback={kind="accept",questId=1,position={map=1,x=0.5,y=0.5,startItemId=500}}})
    eq(B.Navigation.Target(B.Navigation:Current()),nil);eq(#B.Navigation:MapPoints(),0);eq(B.Navigation.index,1)
    B.Navigation:SetPlan({revision=B.state.revision,fallback=current,taskQueue={steps=steps}})
    B.state.completed[1]=true;B.state.quests[1]=nil;B.state.revision=B.state.revision+1
    eq(B.Navigation:Current(),nil);eq(#B.Navigation:MapPoints(),2);eq(B.Navigation.index,1)
    for _,point in ipairs(B.Navigation:MapPoints()) do
        for _,action in ipairs(point.actions) do assert(action.questId~=1) end
    end
    B.Navigation:SetPlan({revision=B.state.revision,fallback=nextGoal})
    eq(B.Navigation:Current(),nextGoal);eq(#B.Navigation:MapPoints(),1)
    B.state.completed[1]=nil;B.state.quests[1]=nil
    local accept={kind="accept",questId=1,position={map=1,x=0,y=0}}
    current.objectiveIndex=1
    local other={kind="objective",questId=1,objectiveIndex=2,position={map=1,x=0.4,y=0.2}}
    local delivery={kind="turnin",questId=1,expected=true,position={map=1,x=0.7,y=0.2}}
    local stages={{stage=accept},{stage=current},{stage=other},{stage=delivery},{stage=nextGoal}}
    B.Navigation:SetPlan({revision=B.state.revision,fallback=accept,taskQueue={steps=stages}})
    B.state.quests[1]={objectives={{finished=false},{finished=false}}};B.state.revision=B.state.revision+1
    eq(B.Navigation:Current(),nil);eq(#B.Navigation:MapPoints(),4)
    B.Navigation:SetPlan({revision=B.state.revision,fallback=current,taskQueue={steps=stages}})
    B.state.quests[1].objectives[1]={text="大蜡烛：6/8",numFulfilled=6,numRequired=8}
    GameTooltip={SetOwner=function() end,SetText=function() end,
        AddLine=function(_,text) tooltip.lines[#tooltip.lines+1]=text end,Show=function() end}
    tooltip.lines={};pins[1].scripts.OnEnter(pins[1]);eq(tooltip.lines[1],"大蜡烛  6/8");GameTooltip=oldTooltip
    B.state.quests[1].objectives[1].finished=true;B.state.revision=B.state.revision+1
    eq(B.Navigation:Current(),nil);eq(#B.Navigation:MapPoints(),3)
    B.Navigation:RefreshPins();eq(pins[1].point.action,other)
    B.state.quests[1].ready=true;B.state.quests[1].objectives[2].finished=true
    eq(#B.Navigation:MapPoints(),2);eq(B.Navigation.index,1)
    local transit={kind="transit",mode="flight",questId=1,position={map=2,x=0.1,y=0.1}}
    B.Navigation.plan.travelActions={transit,current};B.Navigation.actions={transit,current}
    eq(B.Navigation:Current(),nil);eq(#B.Navigation:MapPoints(),2)
    current.itemGain=2;eq(B.Navigation:Current(),transit);current.itemGain=nil
    current.itemGain,current.targetId=2,500;B.Navigation.plan.itemStock={[500]=2}
    B.state.bags[500]=3;eq(B.Navigation:Current(),transit)
    B.state.bags[500]=4;eq(B.Navigation:Current(),nil)
    current.itemGain,current.targetId=nil,nil;B.Navigation.plan.itemStock=nil
    delivery.expected=nil;B.Navigation:SetPlan({revision=B.state.revision,fallback=delivery})
    B.state.quests[1].ready=false;B.state.revision=B.state.revision+1
    eq(B.Navigation:Current(),nil);eq(#B.Navigation:MapPoints(),0)
    B.Navigation.manual={map=4,x=0.5,y=0.5};eq(B.Navigation:Current().kind,"manual")
    eq(B.state.quests[1].objectives[1].finished,true);eq(B.state.completed[1],nil)
    B.finish()
end)
test("低等级接取跟随追踪开关，同站适级任务和手动目标保持可见",function()
    local B=setupMap()
    local oldMinimap,oldLog,oldRange=C_Minimap,C_QuestLog,UnitQuestTrivialLevelRange
    local trackLow=false
    C_Minimap={IsTrackingHiddenQuests=function() return trackLow end}
    C_QuestLog={IsQuestTrivial=function(id) return id==203 end, GetQuestDifficultyLevel=function(id) return id==204 and 34 or 0 end}
    UnitQuestTrivialLevelRange=function() return 8 end
    B.state.level=34
    local function offer(id,level,x)
        return {questId=id,level=level,actions={{kind="accept",questId=id,position={map=1433,x=x,y=.46}}}}
    end
    local low,normal,other,scaled=offer(201,18,.30),offer(202,26,.30),offer(203,nil,.32),offer(204,18,.35)
    B.Navigation:SetPlan({revision=B.state.revision,taskChoices={low,normal,other,scaled}})
    local points=B.Navigation:MapPoints()
    eq(#points,2);eq(points[1].action.questId,202);eq(#points[1].actions,1)
    trackLow=true;B.frame.scripts.OnEvent(B.frame,"MINIMAP_UPDATE_TRACKING")
    local pins=B.Navigation.pins
    eq(#B.Navigation:MapPoints(),3)
    for _,i in ipairs({1,2}) do
        eq(pins[i].action.questId,202);eq(#pins[i].point.actions,2);eq(pins[i].texture:IsDesaturated(),false)
        eq(pins[i+2].action.questId,203);eq(pins[i+2].texture:IsDesaturated(),true)
        assert(pins[i+2]:GetWidth()<pins[i]:GetWidth())
    end
    trackLow=false;B.Navigation:DrawPins()
    eq(pins[3].action.questId,204);eq(pins[3].texture:IsDesaturated(),false)
    assert(B.Navigation:Navigate(other.actions[1]))
    eq(pins[1].action.questId,203);eq(pins[1].number.value,"1");eq(pins[1].texture:IsDesaturated(),false)
    C_Minimap,C_QuestLog,UnitQuestTrivialLevelRange=oldMinimap,oldLog,oldRange
    B.finish()
end)
test("普通任务地图点只显示可执行的接取、目标和交付",function()
    local B=setupMap()
    local choices={}
    for id=100,107 do
        local action={kind="accept",questId=id,title="可接任务 "..id,position={map=1,x=(id-99)/10,y=0.3}}
        choices[#choices+1]={questId=id,actions={action},stages={action,
            {kind="objective",questId=id,expected=true,position={map=2,x=0.5,y=0.5}}}}
    end
    local collect={kind="objective",questId=108,objectiveIndex=1,targetKind="item",targetId=500,
        title="收集物品",position={map=1,x=0.1,y=0.4}}
    local kill={kind="objective",questId=108,objectiveIndex=2,targetKind="npc",targetId=1000,
        title="击杀目标",position={map=1,x=0.2,y=0.4}}
    local turnin={kind="turnin",questId=109,title="已完成",position={map=1,x=0.3,y=0.4}}
    B.state.quests[108]={objectives={{type="item",finished=false},{type="monster",finished=false}}};B.state.quests[109]={ready=true}
    choices[#choices+1]={questId=108,actions={collect},stages={collect,kill,
        {kind="turnin",questId=108,expected=true,position={map=2,x=0.1,y=0.1}}}}
    choices[#choices+1]={questId=109,actions={turnin},stages={turnin}}
    local p={revision=B.state.revision,fallback=collect,taskChoices=choices,taskQueue={steps={}}}
    B.Navigation:SetPlan(p);eq(#B.Navigation:MapPoints(),11)
    local book=choices[1].actions[1]
    book.position.pickupLoot={id=215815,count=1};B.state.bags[215815]=1
    eq(#B.Navigation:MapPoints(),10);eq(B.Navigation:Pickup(book),false)
    B.state.bags[215815]=nil;eq(#B.Navigation:MapPoints(),11)
    local pins=B.Navigation.pins
    eq(pins[1].number.value,"1");assert(not pins[3].badge or not pins[3].badge:IsShown())
    eq(pins[1].texture.texture,B.UI.IconTexture("collect"))
    eq(pins[2].texture.texture,pins[1].texture.texture)
    eq(pins[3].texture.texture,B.UI.IconTexture("accept"))
    local pickupSpot=choices[1].actions[1].position
    kill.position=pickupSpot;B.Navigation:DrawPins()
    for _,i in ipairs({3,4}) do eq(pins[i].action,kill);eq(pins[i].texture.texture,B.UI.IconTexture("objective")) end
    for _,i in ipairs({3,4}) do
        local side=pins[i].sides[1]
        eq(side.texture.texture,B.UI.IconTexture("accept"));eq(side.action,book)
    end
    local other=choices[2].actions[1]
    local otherSpot,recipient=other.position,turnin.position
    other.position,turnin.position=pickupSpot,pickupSpot;B.Navigation:DrawPins()
    for _,i in ipairs({3,4}) do
        local pin=pins[i];eq(pin.action,turnin);eq(pin.sides[1].action,kill)
        local offer=pin.sides[2];eq(#offer.phaseActions,2);eq(offer.action.kind,"accept")
        eq(pin.countBadge.number.value,"×1");eq(pin.sides[1].countBadge.number.value,"×1")
        eq(offer.countBadge.number.value,"×2")
        offer.scripts.OnClick(offer,"LeftButton")
        assert(B.menu[book.title] and B.menu[other.title] and not B.menu[kill.title])
    end
    B.menu[other.title].callback();eq(B.Navigation:Current(),other)
    B.Navigation:ClearManual()
    local collectSpot=collect.position
    collect.position=pickupSpot;B.Navigation:DrawPins()
    for _,i in ipairs({1,2}) do
        local pin=pins[i];eq(pin.action,collect);eq(#pin.phaseActions,2);eq(pin.countBadge.number.value,"×1")
    end
    collect.position=collectSpot
    other.position,turnin.position=otherSpot,recipient
    kill.position={map=1,x=.2,y=.4};B.Navigation:DrawPins()
    assert(not pins[3].sides[1]:IsShown() and not pins[4].sides[2]:IsShown())
    assert(B.Navigation:Navigate(choices[1].actions[1]));eq(#B.Navigation:MapPoints(),11)
    eq(B.Navigation:Current(),choices[1].actions[1]);eq(pins[1].point.current,true)
    B.Navigation:ClearManual();B.state.quests[108].objectives[1].finished=true;B.state.revision=B.state.revision+1
    eq(#B.Navigation:MapPoints(),10)
    B.state.completed[109]=true;B.state.quests[109]=nil
    choices[1].lowValue={};choices[2].requireCheck=true;choices[3].acceptBlocked=true;choices[4].entryBlocked=true
    choices[5].revisitLevel=40;B.state.skipped[105]=true
    eq(#B.Navigation:MapPoints(),3)
    B.state.quests[106]={objectives={{finished=false}}};B.state.revision=B.state.revision+1
    for _,point in ipairs(B.Navigation:MapPoints()) do
        assert(not (point.action.questId==106 and point.action.kind=="accept"))
    end
    -- A just-completed quest can be absent from the last plan while another quest is selected.
    assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B);B.indexReady=true
    local pin={map=1417,x=.6024,y=.5392,ready=true}
    B.state.quests[657]={ready=true,title="新的瘟疫？",mapPin=pin}
    local function countHandins()
        local count=0
        for _,point in ipairs(B.Navigation:MapPoints()) do
            for _,action in ipairs(point.actions) do
                if action.questId==657 and action.kind=="turnin" then count=count+1;eq(point.position.map,1417) end
            end
        end
        return count
    end
    eq(countHandins(),1)
    B.settings.mapTaskScope="route";eq(countHandins(),0)
    choices[#choices+1]={questId=657,actions={{kind="turnin",questId=657,position=pin}}}
    B.settings.mapTaskScope="all";eq(countHandins(),1)
    B.State.confirmed={[657]=true};eq(countHandins(),0)
    B.finish()
end)
end
