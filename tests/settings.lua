return function(test,eq,F,A,plan,setup,widget,setupMap)
local function control(B,key)
    for _,row in ipairs(B.UI.Settings.controls) do if row.key==key then return row end end
    error("设置缺少入口："..key)
end

test("完整界面显示任务和详情，初始化失败显示可复制错误",function()
    local B=setup(true)
    B.Initialize=function(self) self.UI:Render() end
    eq(B:Start(),true)
    assert(B.UI.title:GetText()~="")
    eq(B.UI.ClockText(59.6),"1:00")
    B.UI:ToggleDetails()
    assert(B.UI.details:IsShown())
    assert(B.UI.Browser.frame:IsShown());assert(B.UI.Browser.rows[1].text:GetText()~="")
    local tracker=control(B,"trackerTransparency").button
    local hud=control(B,"hudTransparency").button
    local detail=control(B,"detailTransparency").button
    local before=B.refreshes
    eq(B.UI.tracker.background.color[4],0);eq(B.UI.frame.surface,nil)
    tracker.scripts.OnClick(tracker);B.menu["40%"].callback()
    eq(B.UI.tracker.background.color[4],0.6);eq(B.UI.navFrame.surface[1].color[4],0.4)
    hud.scripts.OnClick(hud);B.menu["100%"].callback()
    eq(B.UI.tracker.background.color[4],0.6);eq(B.UI.navFrame.surface[1].color[4],0)
    eq(B.UI.details.surface[1].color[4],0.9)
    detail.scripts.OnClick(detail);B.menu["0%"].callback()
    eq(B.UI.details.surface[1].color[4],1);eq(B.UI.details.alpha,1)
    local slider=B.UI.Settings.buttonTransparency
    for _,percent in ipairs({0,63,100}) do
        slider:SetValue(percent)
        eq(B.settings.trackerButtonTransparency,percent);eq(slider.percent:GetText(),percent.."%")
        eq(B.UI.tracker.menu.trackerBackground.color[4],(100-percent)/100)
        eq(B.UI.tracker.collapse.trackerBackground.color[4],(100-percent)/100)
        eq(B.UI.tracker.background.color[4],0.6)
    end
    eq(B.refreshes,before);eq(B.settings.alpha,0.94)
    B.UI.frame.scripts.OnMouseUp(nil,"RightButton");B.menu["详细面板"].callback()
    eq(B.UI.details:IsShown(),false)
    B.menu["暂停引导"].callback();eq(B.char.paused,true)
    B.UI.frame.scripts.OnMouseUp(nil,"RightButton");B.menu["继续引导"].callback();eq(B.char.paused,false)
    B.menu["收起任务列表"].callback();eq(B.UI.tracker.currentScroll.shown,false)
    B.UI.frame.scripts.OnMouseUp(nil,"RightButton");B.menu["展开任务列表"].callback();eq(B.UI.folded,false)
    B.UI.frame.scripts.OnDragStart();eq(B.UI.frame.moving,true)
    B.UI.frame.scripts.OnDragStop();eq(B.UI.frame.moving,false);eq(B.settings.position[3],25)
    local nativeError,message
    geterrorhandler=function() return function(err) nativeError=err end end
    B.Message=function(_,value) message=value end
    B.Initialize=function(self)
        self.ready=true
        self.jobs.plan=coroutine.create(function() end)
        self.UI.Settings.Create=function() error("模拟界面初始化失败") end
        self.UI:Create()
    end
    eq(B:Start(),false)
    assert(B.startupError:find("模拟界面初始化失败",1,true))
    eq(nativeError,B.startupError);assert(message:find(B.startupError,1,true))
    eq(B.ready,false);eq(next(B.jobs),nil)
    eq(B.UI.frame:IsShown(),false);eq(B.UI.details:IsShown(),false)
    assert(B.UI.startupPanel:IsShown())
    assert(B.UI.startupPanel.copy:GetText():find(B.startupError,1,true))
    B.UI.startupPanel:Hide();SlashCmdList.AILEVELING("status")
    assert(B.UI.startupPanel:IsShown())
    B.UI.Text=function() error("模拟文字创建失败") end
    eq(B:Start(),false)
    assert(B.UI.startupPanel.copy:GetText():find("模拟文字创建失败",1,true))
    B.finish()
    -- The optional skin uses the public controls and reacts to style changes without rebuilding tasks.
    local listeners,face,scale,texts,menuItems={},"DaylightFont",1,{},{}
    local questBox,windowAlpha={}
    local function nativeControl(kind,parent)
        local f=CreateFrame(kind,nil,parent)
        f.DisableDrawLayer=function(self,layer) self.hiddenLayer=layer end
        local texture=f.CreateTexture
        f.CreateTexture=function(self,name,layer,...)
            local fill=texture(self,name,layer,...)
            if layer=="BORDER" then self.fill=fill end
            return fill
        end
        return f
    end
    local sizes={small=12,body=13,head=15,title=18}
    local api={major=1,Colors=function() return {TEXT={1,1,1},VALUE={1,1,1},LABEL={0.8,0.7,0.6},WARN={1,0.8,0.3},GOOD={0.5,0.9,0.5},BAD={1,0.3,0.3}} end,
        Accent=function() return 0.8,0.4,0.6 end,Font=function() return face end,
        GetSetting=function(scope,key)
            if scope=="Quests" then return questBox[key] end
            if key=="windowAlpha" then return windowAlpha end
            if key=="fontScale" then return scale end
        end,
        On=function(event,fn) listeners[event]=fn end,
        Menu=function(owner,keys,labels,current,pick)
            for _,key in ipairs(keys) do menuItems[labels[key]]=function() pick(key) end end
        end,
        Skin=function(frame,opts) frame.daylightOpts=opts;frame.skinCalls=(frame.skinCalls or 0)+1 end,
        Text=function(parent,role)
            local fs=parent:CreateFontString();fs:SetFont(face,sizes[role]*scale,"")
            fs:SetShadowColor(0,0,0,0.6);fs:SetShadowOffset(1,-1);texts[fs]=role;return fs
        end,
        Button=function(parent,label) local b=nativeControl("Button",parent);b.text=b:CreateFontString();b.text:SetText(label);return b end,
        Close=function(parent,click) local b=CreateFrame("Button",nil,parent);b:SetScript("OnClick",click);return b end,
        Bar=function(parent) return CreateFrame("StatusBar",nil,parent) end,
        Switch=function(parent) local b=CreateFrame("Button",nil,parent);b.SetOn=function(on) b.checked=on end;return b end,
        Input=function(parent) return nativeControl("EditBox",parent) end}
    B=setup(true,api);B.UI:Render();local choice=B.action
    eq(B.UI.frame.daylightOpts,nil);eq(B.UI.tracker.background.color[4],0)
    eq(B.UI.navFrame.daylightOpts.noBorder,false)
    eq(B.UI.title.fontFace,face);assert(B.UI.tracker.chapter:IsShown())
    eq(B.UI.navFrame.daylightOpts.panel,true);eq(B.UI.navFrame.daylightOpts.bgAlpha,0.40)
    windowAlpha=0.35;listeners.SettingChanged("general","windowAlpha");eq(B.UI.navFrame.daylightOpts.bgAlpha,0.40)
    questBox.boxAlphaOwn,questBox.boxAlpha,questBox.boxBorder=true,0.45,false
    listeners.SettingChanged("Quests","boxBorder")
    eq(B.UI.navFrame.daylightOpts.noBorder,true);eq(B.UI.navFrame.daylightOpts.bgAlpha,0.40)
    B.settings.alpha=0.5;B.UI:ApplyStyle()
    eq(B.UI.details.alpha,1);eq(B.UI.tracker.navBearing.alpha,0.5);eq(B.UI.nav.alpha,0.5);eq(B.UI.navFrame.alpha or 1,1)
    eq(B.UI.tracker.headerLine.color[2],B.UI.colors.gold[2]);eq(B.UI.title.fontSize,17);eq(B.UI.tracker.location.fontSize,20)
    eq(B.UI.title.fontFlags,"OUTLINE");eq(B.UI.title.shadowColor[4],1)
    local before=B.UI.navFrame.skinCalls;B.UI.navFrame.scripts.OnSizeChanged();eq(B.UI.navFrame.skinCalls,before+1)
    face="UpdatedDaylightFont";scale=1.2
    for fs,role in pairs(texts) do fs:SetFont(face,sizes[role]*scale,"");fs:SetShadowColor(0,0,0,0) end
    listeners.StyleChanged();eq(B.UI.title.fontFace,face);eq(B.action,choice)
    eq(B.UI.frame.daylightOpts,nil)
    eq(B.UI.title.fontSize,17*1.2);eq(B.UI.title.shadowColor[4],1);eq(B.UI.tracker.navDetail.fontSize,16*1.2);eq(B.UI.tracker.navDetail.fontFlags,"OUTLINE")
    B.settings.fontScale=1.1;listeners.Login();eq(B.UI.title.fontSize,17*1.2*1.1)
    B.UI.details.scripts.OnSizeChanged()
    eq(B.UI.details.daylightOpts.window,true);eq(B.UI.details.daylightOpts.bgAlpha,0.90)
    eq(B.UI.Browser.detail.fontSize,16*1.2*1.1);eq(B.UI.Browser.detail.fontFace,face)
    eq(B.UI.tracker.background.color[4],0);eq(B.UI.tracker.nearby.daylightOpts.bgAlpha,0.4)
    local color=control(B,"backgroundStyle").button
    color.scripts.OnClick(color);menuItems["深蓝"]()
    B:SetOption("hudTransparency",30);listeners.StyleChanged();B.UI:LayoutTracker()
    eq(B.UI.tracker.background.color[4],0);eq(B.UI.navFrame.daylightOpts.bgAlpha,0.7)
    eq(B.UI.tracker.nearby.daylightOpts.bgAlpha,0.7);eq(B.UI.details.daylightOpts.bgAlpha,0.9)
    eq(B.UI.navFrame.daylightOpts.bgColor[3],0.14);eq(B.UI.tracker.background.color[3],0.14)
    B:SetOption("trackerTransparency",40);eq(B.UI.tracker.background.color[4],0.6);eq(B.UI.frame.daylightOpts,nil)
    B:SetOption("backgroundStyle","default");eq(B.UI.navFrame.daylightOpts.bgColor,nil)
    local link=B.UI.tracker.career.view
    eq(link.hiddenLayer,"BACKGROUND");eq(link.fill.color[4],0)
    link.scripts.OnEnter(link);eq(link.fill.color[4],0.40)
    link.scripts.OnLeave(link);eq(link.fill.color[4],0)
    B.UI.Settings.buttonTransparency:SetValue(50)
    for _,button in ipairs({B.UI.tracker.menu,B.UI.tracker.collapse}) do
        eq(button.trackerBackground.color[4],0.5)
        eq(button.fill.color[4],0)
        button.scripts.OnLeave(button);eq(button.fill.color[4],0)
    end
    eq(B.UI.Browser.search.hiddenLayer,"BACKGROUND");eq(B.UI.Browser.search.fill.color[4],0.40)
    eq(B.UI.colors.sidebar[4],0.40);eq(B.UI.colors.selected[4],0.40)
    B.UI:TrackerMenu(B.UI.frame)
    local detailsLabel=B.UI.tracker.experience:IsShown() and "详细面板" or "详细面板 · "..B.UI.tracker.experience:GetText()
    assert(menuItems[detailsLabel]);menuItems[detailsLabel]()
    assert(B.UI.Browser.frame:IsShown());assert(B.UI.details:IsShown())
    local book=B.UI.Browser
    local button=book.buttons[1]
    button.text:SetText(string.rep("长任务名",10));button.text.measuredHeight=60;button:Show()
    book:PlaceActions(0)
    eq(button.text.wordWrap,true);eq(button:GetWidth(),book.info:GetWidth());assert(button:GetHeight()>=68)
    local toggle=control(B,"quantity").button;toggle.scripts.OnClick();eq(B.settings.quantity,false);eq(toggle.checked,false)
    B.UI:ShowText("测试报告","运行诊断");listeners.StyleChanged()
    eq(B.UI.exporting,true);eq(B.UI.detailHeading:GetText(),"运行诊断")
    eq(B.UI.copyBox:IsShown(),true);eq(B.UI.scroll:GetVerticalScroll(),0)
    B.finish()

end)
test("设置开关跨归一化保留且清除已取消的旧采样",function()
    local B=setup()
    local row=control(B,"quantity");row.button.checked=false;row.button.scripts.OnClick()
    eq(B.settings.quantity,false);B:NormalizeSettings(B.settings);eq(B.settings.quantity,false)
    B.settings.mapTaskScope="invalid";B:NormalizeSettings(B.settings);eq(B.settings.mapTaskScope,"all")
    for _,key in ipairs({"mapTaskScope","pins","minimapPins","arrow","waypointUI","routes"}) do
        eq(control(B,key).button.parent,B.UI.Settings.groups[7])
    end
    control(B,"gearPreference").button.scripts.OnClick();eq(B.settings.gearPreference,"xp");assert(B.refreshes>0)
    for _,key in ipairs({"quest","move","recovery","taskwork:old","tasktalk:v1:turnin:fast"}) do B.char.samples[key]={n=3,mean=10,m2=0} end
    B.char.sampleContext="old equipment context"
    B:NormalizeCharacter(B.char);eq(next(B.char.samples),nil);eq(B.char.sampleContext,nil)
    B.finish()
end)
test("配置迁移、复制、切换与恢复保留角色进度，并可刷新任务历史",function()
    local B=setup();local char=B.char
    char.turnIns[1]=1;char.locked=1;B.state.completed[1]=true
    local db={scale=1.3,quantity=false,trackerDocked=false,position={"RIGHT","RIGHT",-120,80},mapTaskScope="route",pins=false,arrow=false}
    B:InitializeProfiles(db,char)
    eq(B.settings.scale,1.3);eq(B.settings.quantity,false);eq(db.scale,nil)
    local S=B.UI.Settings
    S.profileName:SetText("大字")
    S.profileName.scripts.OnEnterPressed()
    eq(char.profile,"大字");eq(B.settings.scale,1.3)
    eq(B.settings.mapTaskScope,"route");eq(B.settings.pins,false);eq(B.settings.arrow,false)
    local titleSize=B.UI.title.fontSize
    B.UI.tracker.menu:Click();B.menu["放大字体 · 110%"].callback()
    eq(B.settings.fontScale,1.1);eq(B.UI.title.fontSize,titleSize*1.1)
    B.UI:TrackerMenu(B.UI.frame);B.menu["放大字体 · 120%"].callback()
    B.UI:TrackerMenu(B.UI.frame);eq(B.menu["放大字体"].enabled,false)
    B.settings.position[3]=-200
    eq(db.profiles["默认"].position[3],-120)
    B:SelectProfile("默认");eq(B.settings.fontScale,1);eq(B.UI.frame.point[4],-120)
    S.profile.scripts.OnClick();eq(char.profile,"大字");eq(B.settings.fontScale,1.2)
    db.defaultProfile="大字"
    local other={};B:InitializeProfiles(db,other);eq(other.profile,"大字")
    B:InitializeProfiles(db,char);B:RestoreSettings()
    eq(db.profiles["默认"].scale,1.3);eq(B.settings.scale,1);eq(B.settings.position,nil)
    eq(db.profiles["默认"].mapTaskScope,"route");eq(B.settings.mapTaskScope,"all");eq(B.settings.pins,true)
    eq(char.turnIns[1],1);eq(char.locked,1);eq(B.state.completed[1],true)
    eq(B:DeleteProfile("大字"),false)
    B:SelectProfile("默认");eq(B:DeleteProfile("默认"),true)
    eq(char.profile,"大字");eq(db.profiles["默认"],nil)
    local refreshes=B.refreshes
    local history=B:QuestHistory();assert(history:find("已完成任务 · 1",1,true));assert(history:find("1 · ",1,true))
    eq(B.refreshes,refreshes+1);eq(char.turnIns[1],1)
    B.finish()
end)
test("原生任务对话自动接交同NPC任务，保留整组交付、多选奖励及手动覆盖",function()
    local B=setup();assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    local id,shift,count,money,complete=2,false,0,0,true
    local calls={}
    GetQuestID=function() return id end
    IsShiftKeyDown=function() return shift end
    AcceptQuest=function() calls[#calls+1]="accept:"..id end
    CompleteQuest=function() calls[#calls+1]="progress:"..id end
    GetNumQuestChoices=function() return count end
    GetQuestMoneyToGet=function() return money end
    IsQuestCompletable=function() return complete end
    GetQuestReward=function(choice) calls[#calls+1]="reward:"..choice end
    C_GossipInfo={GetAvailableQuests=function() return {{questID=99},{questID=2}} end,
        GetActiveQuests=function() return {{questID=1,isComplete=true}} end,
        SelectAvailableQuest=function(quest) calls[#calls+1]="select:"..quest end,
        SelectActiveQuest=function(quest) calls[#calls+1]="active:"..quest end}
    local accept={questId=2,status="accept",actions={{kind="accept"}}}
    local point={entityKind="npc",entityId=9,entityName="交付NPC"}
    local ready={questId=1,status="turnin",actions={{kind="turnin"}},stages={{kind="turnin",position=point}}}
    local pending={questId=3,status="objective",actions={{kind="objective"}},stages={{kind="turnin",position=point}}}
    B.plan={taskChoices={ready,pending,accept}}
    B.state.quests[1].ready=true;B.state.quests[3]={objectives={}}
    local function update() B.frame.scripts.OnUpdate(nil,0) end
    local function event(name,defer,...)
        B.frame.scripts.OnEvent(nil,name,...)
        if not defer then B.refreshAt=nil;update() end
    end
    event("GOSSIP_SHOW");eq(calls[1],"select:2")
    event("QUEST_DETAIL");event("QUEST_DETAIL");eq(#calls,2);eq(calls[2],"accept:2")
    eq(B.state.quests[2],nil);eq(B.state.completed[2],nil)
    event("QUEST_FINISHED");id=99;event("QUEST_DETAIL");eq(#calls,2)
    id=2;shift=true;event("QUEST_DETAIL");eq(#calls,2);shift=false
    B.char.paused=true;event("QUEST_DETAIL");eq(#calls,2);B.char.paused=false
    B.combat(true);event("QUEST_DETAIL");eq(#calls,2);B.combat(false)
    B.Navigation.manual={};event("QUEST_DETAIL");eq(#calls,2);B.Navigation.manual=nil
    B.settings.autoAccept=false;event("QUEST_DETAIL");eq(#calls,2);B.settings.autoAccept=true
    accept.acceptBlocked="日志满";event("QUEST_DETAIL");eq(#calls,2);accept.acceptBlocked=nil
    accept.lowValue={};event("QUEST_DETAIL");eq(#calls,2);accept.lowValue=nil
    B.state.locked=1;event("QUEST_DETAIL");eq(#calls,2);B.state.locked=nil
    id=1;event("QUEST_PROGRESS");eq(#calls,2)
    B.state.quests[3].ready=true;event("GOSSIP_SHOW");eq(calls[3],"active:1")
    complete=false;event("QUEST_PROGRESS");eq(#calls,3);complete=true
    event("QUEST_PROGRESS");eq(calls[4],"progress:1")
    count=2;event("QUEST_COMPLETE");eq(#calls,4)
    count=1;money=100;event("QUEST_COMPLETE");eq(#calls,4)
    money=0;event("QUEST_COMPLETE");event("QUEST_COMPLETE");eq(calls[5],"reward:1");eq(#calls,5)
    eq(B.state.completed[1],nil);eq(B.char.turnIns[1],nil)
    event("QUEST_FINISHED");count=0;event("QUEST_COMPLETE");eq(calls[6],"reward:0")
    event("GOSSIP_CLOSED");B.settings.autoTurnIn=false;event("QUEST_COMPLETE");eq(#calls,6)
    assert(loadfile("Transport.lua"))("AiLeveling",B)
    B.Transport.taxiSelected=true;event("TAXIMAP_CLOSED");eq(B.Transport.taxiSelected,nil)
    calls={};local menus=0
    B.Merchant={NpcId=A.Merchant.NpcId,Event=function() end};B.State.Position=function() end
    B.state.position={map=1,x=0.5,y=0.5}
    B.Navigation.Near=function(_,a,b) return a.map==b.map and math.abs(a.x-b.x)<0.01 end
    B.char.serviceStop={kind="train",npcId=9,title="训练师",position=B.state.position}
    local npcGuid="Creature-0-1-2-3-9-0000"
    UnitGUID=function() return npcGuid end
    Enum={GossipOptionStatus={Available=0}}
    C_GossipInfo.GetOptions=function() menus=menus+1;return {{icon=132058,status=0,gossipOptionID=44,orderIndex=2}} end
    C_GossipInfo.SelectOption=function(value) calls[#calls+1]="service:"..value end
    assert(loadfile("Services.lua"))("AiLeveling",B)
    local function dialog() event("GOSSIP_SHOW") end
    dialog();eq(menus,0);eq(calls[1],"select:2");calls={}
    event("GOSSIP_CLOSED");id=2;accept.revisitLevel=30
    event("QUEST_DETAIL");eq(#calls,0)
    accept.pickupAction={kind="accept",questId=2};B.Navigation.manual={action=accept.pickupAction}
    B.plan.taskChoices[4]={questId=99,status="accept"}
    B.state.locked=1;id=99;event("QUEST_DETAIL");eq(#calls,0)
    dialog();id=2;event("QUEST_DETAIL");eq(calls[1],"select:2");eq(calls[2],"accept:2")
    eq(B.state.locked,1);B.state.locked=nil;B.Navigation.manual=nil;B.plan.taskChoices[4]=nil
    accept.revisitLevel,accept.pickupAction=nil,nil;calls={};event("GOSSIP_CLOSED")
    C_GossipInfo.GetActiveQuests=function() return {} end
    B.settings.autoAccept=false;dialog();eq(menus,0);eq(#calls,0)
    C_GossipInfo.GetAvailableQuests=function() return {{questID=99}} end
    dialog();dialog();eq(#calls,1);eq(calls[1],"service:44")
    event("GOSSIP_CLOSED");dialog();eq(#calls,2)
    shift=true;dialog();eq(#calls,2);shift=false
    B.char.serviceStop=nil;calls={};id=2;B.settings.autoAccept=true
    event("QUEST_FINISHED");accept.requireCheck=true
    B.refreshAt=20;event("QUEST_DETAIL",true);update()
    eq(coroutine.status(assert(B.jobs["quest:dialog"])),"suspended");eq(#calls,0)
    local planningTime,resumes=0,0
    debugprofilestop=function() return planningTime end
    B.plan.fallback=accept.actions[1]
    B.refreshAt=nil;B:Queue("plan",function()
        for i=1,100 do resumes=resumes+1;planningTime=planningTime+0.1;eq(#calls,0);coroutine.yield() end
        accept.requireCheck=false
    end)
    update();eq(#calls,0);assert(B.jobs.plan);assert(resumes>1 and resumes<100);assert(planningTime>=6 and planningTime<6.2)
    update();eq(calls[1],"accept:2");eq(B.jobs["quest:dialog"],nil);eq(B.jobs.plan,nil)
    B.plan.fallback=nil
    B.planningManual=true
    for _,inCombat in ipairs({false,true}) do
        B.combat(inCombat);planningTime,resumes=0,0
        B:Queue("plan",function()
            for i=1,100 do resumes=resumes+1;planningTime=planningTime+0.1;coroutine.yield() end
        end)
        update()
        local budget=inCombat and 2 or 6
        assert(B.jobs.plan);assert(planningTime>=budget and planningTime<budget+0.2)
        B.jobs.plan=nil
    end
    B.combat(false)
    debugprofilestop=function() return 0 end
    local oldSpeed,oldPlanner,oldPlan=GetUnitSpeed,B.Planner,B.plan
    local oldPosition,oldPoint=B.State.Position,B.state.position
    local speed,builds,built,hold=7,0,nil,false
    local x=0.5
    GetUnitSpeed=function() return speed,7,0,4.7 end
    B.State.Position=function() B.state.position={map=1,x=x,y=0} end
    B.Navigation.SetPlan=function() end
    B.Planner={Build=function(snapshot)
        builds=builds+1;built=snapshot
        if hold then planningTime=planningTime+6;coroutine.yield() end
        return {revision=snapshot.revision,fallback=accept.actions[1]}
    end}
    B:Queue("index",function() B:Replan(true) end)
    update();eq(builds,0);eq(B.jobs.index,nil);assert(B.planningResumeAt);eq(B.plan,oldPlan)
    for i=1,3 do B.state.revision=B.state.revision+1;B:Replan(true);update() end
    eq(builds,0)
    speed=0;B.combat(true);update();eq(builds,0)
    B.combat(false);B.time(10.1);update();eq(builds,0)
    B.time(10.4);update();eq(builds,1);eq(built.revision,B.state.revision);eq(built.position.x,0.5)
    eq(B.planningResumeAt,nil);eq(B.jobs.plan,nil);update();eq(builds,1)
    B.plan.origin={map=2};B.plan.unverified=true
    speed=7;B:Replan(true);update();eq(builds,1)
    B:Replan(true,true);update();eq(builds,2);eq(built.currentTask,nil);eq(B.planningResumeAt,nil)
    speed=0;hold=true;debugprofilestop=function() return planningTime end
    B:Replan(true);update();eq(builds,3);local interrupted=B.jobs.plan
    speed=7;update();eq(builds,3);eq(B.jobs.plan,interrupted)
    B.state.revision=B.state.revision+1;B:Replan();update();eq(builds,3)
    speed=0;B.time(10.8);update();eq(builds,4);eq(built.revision,B.state.revision)
    update();eq(builds,4);eq(B.jobs.plan,nil);eq(B.plan.revision,B.state.revision)
    B:Replan(true);update();eq(builds,5)
    B.combat(true);update();x=0.6;B.combat(false);B.time(11.2);update()
    eq(builds,5);eq(B.jobs.plan,nil);eq(B.plan.revision,B.state.revision)
    B.Planner,B.plan,GetUnitSpeed=oldPlanner,oldPlan,oldSpeed
    B.State.Position,B.state.position=oldPosition,oldPoint
    B.Navigation.SetPlan=nil;B.planningManual=nil;B.time(10);debugprofilestop=function() return 0 end
    event("QUEST_FINISHED");B.refreshAt=1;event("QUEST_DETAIL",true)
    event("QUEST_FINISHED",true);B.refreshAt=nil;update();eq(B.jobs["quest:dialog"],nil);eq(#calls,1)
    B.refreshAt=1;event("QUEST_DETAIL",true);id=99;B.refreshAt=nil
    update();eq(#calls,1);id=2
    B.refreshAt=1;event("QUEST_DETAIL",true);B.refreshAt=nil;npcGuid="Creature-0-1-2-3-8-0000"
    update();eq(#calls,1);npcGuid="Creature-0-1-2-3-9-0000"
    B.refreshAt=1;event("QUEST_DETAIL",true);B.refreshAt=nil;shift=true
    update();eq(#calls,1);shift=false
    B.plan.revision=B.state.revision-1;event("QUEST_DETAIL");eq(#calls,1)
    B.plan.revision=B.state.revision;event("QUEST_DETAIL");eq(calls[2],"accept:2")
    B.char.serviceStop={kind="bind",npcId=9,title="旅店",position=B.state.position}
    Enum.PlayerInteractionType={Binder=77}
    local confirmed,cleared=0,0
    C_PlayerInteractionManager={IsValidNPCInteraction=function(kind) eq(kind,77);return true end,
        ConfirmationInteraction=function(kind) eq(kind,77);confirmed=confirmed+1 end,
        ClearInteraction=function(kind) eq(kind,77);cleared=cleared+1 end}
    event("CONFIRM_BINDER",true,"新旅店");eq(confirmed,0);assert(B.jobs["service:bind"])
    B.refreshAt=nil;update();eq(confirmed,1);eq(cleared,1);eq(B.jobs["service:bind"],nil)
    update();eq(confirmed,1);assert(B.char.serviceStop)
    B.char.serviceStop=nil;event("GOSSIP_CLOSED");calls={}
    B.action={kind="objective",questId=1,objectiveIndex=1,position=point}
    B.state.quests[1]={objectives={{finished=false}}}
    B.plan={revision=B.state.revision,taskChoices={}}
    C_GossipInfo.GetAvailableQuests=function() return {} end
    local options={{icon=132053,status=0,gossipOptionID=51,orderIndex=1,name="说下去。"}}
    C_GossipInfo.GetOptions=function() return options end
    dialog();dialog();eq(#calls,1);eq(calls[1],"service:51")
    options={{icon=132053,status=0,gossipOptionID=52,orderIndex=1,name="我准备好了。"}}
    dialog();eq(calls[2],"service:52")
    options={{icon=132053,status=0,gossipOptionID=53,name="左边"},{icon=132053,status=0,gossipOptionID=54,name="右边"}}
    dialog();eq(#calls,2) -- Player chooses the branch; subsequent single pages can continue.
    options={{icon=132053,status=0,gossipOptionID=55,orderIndex=1,name="继续。"}}
    npcGuid="Creature-0-1-2-3-8-0000";dialog();eq(#calls,2)
    npcGuid="Creature-0-1-2-3-9-0000";dialog();eq(calls[3],"service:55")
    eq(B.state.quests[1].objectives[1].finished,false)
    B.state.quests[1].objectives[1].finished=true
    options[1].gossipOptionID=56;dialog();eq(#calls,3)
    B.finish()
end)
test("天赋方案保存重载后在原生树预览并按前置载入，提交仍由原生按钮确认",function()
    local B=setup(true)
    local frame=widget();frame.LoadSystem=widget()
    local inspected,active,commits,resets,rollbacks=false,1,0,0,0
    local ranks={0,0,0};local chosen=30;local mismatch=false
    local entries={{nodeID=3,selectionEntryID=31,ranksPurchased=1},
        {nodeID=2,selectionEntryID=20,ranksPurchased=1},{nodeID=1,selectionEntryID=10,ranksPurchased=2}}
    UnitLevel=function() return 20 end
    PlayerUtil={GetCurrentSpecID=function() return 1486 end}
    ExportUtil={MakeImportDataStream=function(value) eq(value,"native-plan");return {} end}
    frame.IsInspecting=function() return inspected end
    frame.GetConfigID=function() return active*100 end
    frame.GetTalentTreeID=function() return 10 end
    frame.GetLoadoutExportString=function() return "native-plan" end
    frame.ReadLoadoutHeader=function() return true,1,1486,{1} end
    frame.HashEquals=function() return not mismatch end
    frame.ReadLoadoutContent=function() return entries end
    frame.ConvertToImportLoadoutEntryInfo=function(_,config,tree,content) eq(config,active*100);eq(tree,10);return content end
    frame.IsCommitInProgress=function() return false end
    frame.GetActiveTab=function() return active end
    frame.SetTab=function(_,tab) eq(tab,active) end
    frame.UpdateConfigButtonsState=function() end
    PlayerSpellsFrame={TalentsFrame=frame,ClearInspectUnit=function() inspected=false end,
        SetInspectString=function(_,value,level) eq(value,"native-plan");eq(level,20);inspected=true end,
        IsInspecting=function() return inspected end}
    PlayerSpellsUtil={OpenToClassTalentsTab=function() inspected=false end}
    GetNumSpecGroups=function() return 2 end
    C_SpecializationInfo={GetActiveSpecGroup=function() return active end,SetActiveSpecGroup=function(group) active=group end}
    C_ClassTalents={CanEditTalents=function() return true,"" end,CommitConfig=function() commits=commits+1 end}
    C_Traits={GetLoadoutSerializationVersion=function() return 1 end,GetTreeHash=function() return {1} end,
        ResetTree=function() resets=resets+1;ranks={0,0,0};return true end,
        GetNodeInfo=function(_,id) return {ranksPurchased=ranks[id],entryIDs=id==3 and {30,31} or {id*10},
            activeEntry={entryID=id==3 and chosen or id*10},canPurchaseRank=id==1 or id==2 and ranks[1]==2 or id==3 and ranks[2]==1} end,
        SetSelection=function(_,id,entry) eq(id,3);chosen=entry;return true end,
        PurchaseRank=function(_,id) ranks[id]=ranks[id]+1;return true end,
        RollbackConfig=function() rollbacks=rollbacks+1;return true end}
    assert(loadfile("Talents.lua"))("AiLeveling",B)
    local T=B.Talents;T:Show();assert(T.panel:IsShown())
    eq(T:Save("练级"),true);eq(B.char.talentPlans.plans["练级"].text,"native-plan")
    assert(loadfile("Talents.lua"))("AiLeveling",B);T=B.Talents
    eq(T:Preview(),true);eq(inspected,true);eq(resets,0)
    eq(T:Stage(),true);eq(inspected,false);eq(ranks[1],2);eq(ranks[2],1);eq(ranks[3],1);eq(chosen,31)
    eq(commits,0);eq(rollbacks,0);eq(resets,1)
    mismatch=true;eq(T:Stage(),false);eq(resets,1);mismatch=false
    B.combat(true);eq(T:Stage(),false);eq(T:SwitchSpec(),false);eq(resets,1);B.combat(false)
    eq(T:SwitchSpec(),true);eq(active,2);eq(B.char.talentPlans.selected,"练级")
    B.finish()
end)
test("窗口锁定阻止拖动且主详情分别保存位置并恢复",function()
    local B=setup();local U=B.UI
    U:LayoutCard()
    eq(U.frame.point[1],"TOPRIGHT");eq(U.frame.point[2],MinimapCluster);eq(U.frame.point[3],"BOTTOMRIGHT")
    eq(ObjectiveTrackerFrame.parent,U.tracker.nativeHider);eq(U.tracker.nativeHider.shown,false)
    ObjectiveTrackerFrame:Show();eq(ObjectiveTrackerFrame.parent.shown,false)
    U:Movable(U.frame,"position");U:Movable(U.details,"detailPosition")
    B.settings.lockWindow=true;U.frame.scripts.OnDragStart();eq(U.frame.moving,nil)
    B.settings.lockWindow=false;U.details.scripts.OnDragStart();eq(U.details.moving,true)
    U.details.scripts.OnDragStop();eq(B.settings.detailPosition[3],25)
    U.frame.scripts.OnDragStart();U.frame.scripts.OnDragStop();eq(B.settings.trackerDocked,false)
    U.frame.scripts.OnMouseUp(nil,"RightButton");B.menu["对齐小地图"].callback()
    eq(B.settings.trackerDocked,true);eq(B.settings.position,nil);eq(U.frame.point[2],MinimapCluster)
    local T=U.tracker
    B.settings.lockWindow=true;T.resize.scripts.OnMouseDown(nil,"LeftButton");eq(T.resizing,nil)
    B.settings.lockWindow=false;B.combat(true);T.resize.scripts.OnMouseDown(nil,"LeftButton");eq(T.resizing,nil);B.combat(false)
    T.resize.scripts.OnMouseDown(nil,"LeftButton");eq(U.frame.sizing,"BOTTOMRIGHT");eq(B.settings.trackerDocked,false)
    U.frame:SetSize(420,400);T.resize.scripts.OnUpdate()
    eq(U.frame.width,420);eq(U.frame.height,400)
    eq(T.content.width,420-2*U.metrics.padding);eq(U.title.width,T.content.width-U.metrics.indent-U.metrics.gap)
    T.resize.scripts.OnMouseUp();eq(T.resizing,nil);eq(T.resize.scripts.OnUpdate,nil)
    eq(B.settings.trackerWidth,420);eq(B.settings.trackerHeight,400);eq(B.settings.position[3],25)
    U:RenderTracker();eq(U.frame.width,420);eq(U.frame.height,400)
    assert(T.currentChild.height>T.currentScroll.height)
    local offset=math.min(30,T.currentChild.height-T.currentScroll.height)
    T.currentScroll:SetVerticalScroll(offset);U:LayoutTracker();eq(T.currentScroll.offset,offset)
    U.folded=true;U:LayoutTracker();assert(U.frame.height<400);eq(T.resize.shown,false)
    U.folded=false;U:LayoutTracker();eq(U.frame.height,400);eq(T.resize.shown,true)
    B:NormalizeSettings(B.settings);eq(B.settings.trackerWidth,420);eq(B.settings.trackerHeight,400)
    U.frame.scripts.OnMouseUp(nil,"RightButton");B.menu["恢复自动尺寸"].callback()
    eq(B.settings.trackerWidth,0);eq(B.settings.trackerHeight,0);eq(U.frame.width,340)
    U.frame.scripts.OnMouseUp(nil,"RightButton");B.menu["缩小字体 · 85%"].callback()
    U:TrackerMenu(U.frame);eq(B.menu["缩小字体"].enabled,false)
    B.menu["放大字体 · 100%"].callback();eq(B.settings.fontScale,1)
    B.char.deferredChains[1]=true;B.state.completed[7]=true
    B:RestoreSettings();eq(B.settings.detailPosition,nil);eq(B.char.deferredChains[1],true);eq(B.state.completed[7],true)
    B.finish()
end)
test("关闭数量与缺失文字不取消物品需求和规划约束",function()
    local B=setup();local Q=B.QuestAssist
    B:SetOption("quantity",false);B:SetOption("missingChecks",false)
    eq(Q.buttons[1].count.value,"");eq(Q.detailsText:find("2/5",1,true),nil);eq(Q.detailsText:find("缺少至少",1,true),nil)
    eq(Q.wanted[1],500)
    local result=plan(B.state,B.Data,{minutes=60,gearPreference="xp",missingChecks=false})
    eq(result.best,nil);eq(B.state.bags[500],2)
    local oldLocale=GetLocale
    GetLocale=function() return "zhCN" end
    assert(loadfile("Data/QuestTitles_zhCN.lua"))("AiLeveling",B)
    GetLocale=oldLocale
    B.items[500].name=nil
    B.Data.db={Item={Get=function(id) if id==500 then return "任务道具中文名" end end}}
    Q:Update()
    eq(Q.itemSummary,"任务道具中文名");assert(Q.detailsText:find("任务道具中文名",1,true))
    B.items[500].name="Client fallback";Q:Update();eq(Q.itemSummary,"任务道具中文名")
    B.items[500].name="客户端正式名";Q:Update();eq(Q.itemSummary,"客户端正式名")
    B.finish()
end)
test("战斗中显示设置不改变受保护容器和按钮属性",function()
    local B=setup();local Q=B.QuestAssist
    local icon=Q.buttons[1]
    eq(icon.type1,"item");eq(icon.type,nil);eq(icon.type2,nil)
    local U=B.UI;local anchor=U.navAnchor
    eq(Q.container.parent,anchor);eq(U.navFrame.parent,anchor);eq(Q.info.parent,U.navFrame)
    U:SetNavigation(nil,nil,nil,B.action);eq(U.tracker.navItemHeight,36);eq(Q.container.shown,true)
    local expanded=U.navFrame.height
    B:SetOption("items",false);U:SetNavigation(nil,nil,nil,B.action)
    eq(Q.container.shown,false);eq(Q.info.shown,false);eq(U.navFrame.height,expanded-36)
    B:SetOption("items",true);U:SetNavigation(nil,nil,nil,B.action)
    icon.scripts.OnDragStart();eq(anchor.moving,true);icon.scripts.OnDragStop()
    eq(B.settings.navigationPosition[3],25);eq(B.settings.navigationPosition[4],-30)
    U:PlaceNavigation(true);eq(anchor.point[4],25)
    B:SetOption("lockWindow",true);Q.info.scripts.OnDragStart();eq(anchor.moving,false)
    B:SetOption("lockWindow",false);Q.info.scripts.OnDragStart();eq(anchor.moving,true)
    local writes=Q.buttons[1].attributeWrites
    local width,height=Q.container:GetSize()
    B.combat(true)
    B.frame.scripts.OnEvent(nil,"PLAYER_REGEN_DISABLED");Q.info.scripts.OnDragStop();eq(U.navDragging,true)
    B.settings.navigationPosition={"CENTER","CENTER",100,-60};U:PlaceNavigation(true)
    eq(anchor.point[4],25)
    U:SetNavigation(nil);eq(U.navFrame.shown,true);eq(U.tracker.navTitle.value,"任务物品")
    eq(Q.info.text.value,"战斗结束后更新物品")
    U:SetNavigation(nil,nil,nil,B.action);eq(U.tracker.navItemHeight,36)
    B:SetOption("fontScale",1.1);B:SetOption("density","expanded");B:SetOption("quantity",false)
    eq(Q.buttons[1].attributeWrites,writes);eq(Q.buttons[1].count.value,2)
    eq(Q.container.width,width);eq(Q.container.height,height);assert(Q.pending)
    B.combat(false);B.frame.scripts.OnEvent(nil,"PLAYER_REGEN_ENABLED");eq(Q.buttons[1].count.value,"")
    eq(U.navDragging,nil);eq(anchor.point[4],100)
    B.settings.navigationPosition=nil;U:PlaceNavigation(true);eq(anchor.point[4],0);eq(anchor.point[5],-110)
    B.finish()
end)
test("凄凉之地的航段与飞行地图标记都只采用本站可点的落点",function()
    local B=setupMap()
    local names={"GetTaxiMapID","C_TaxiMap","TaxiNodeGetType","NumTaxiNodes","TaxiNodeName","TaxiFrame","TaxiButton2","FlightMapFrame","hooksecurefunc","C_Timer","TakeTaxiNode"}
    local saved={};for _,key in ipairs(names) do saved[key]=_G[key] end
    assert(loadfile("Data/Flights.lua"))("AiLeveling",B)
    assert(loadfile("Transport.lua"))("AiLeveling",B)
    local T,N=B.Transport,B.Navigation
    T:RestoreFlights(B.char);B.settings.autoTaxi=false
    local nodes,kind
    GetTaxiMapID=function() return 1 end
    C_TaxiMap={GetAllTaxiNodes=function() return nodes end}
    TaxiNodeGetType=function() return kind end
    TaxiFrame,TaxiButton2=widget(),widget();TaxiButton2.GetID=function() return 2 end
    FlightMapFrame=nil
    local create=CreateFrame
    CreateFrame=function(...)
        local frame=create(...)
        frame.GetParent=function(self) return self.parent end
        frame.CreateTexture=function()
            local tex=widget()
            tex.CreateAnimationGroup=function()
                local anim=setmetatable({},{__index=function() return function() end end})
                return {CreateAnimation=function() return anim end,SetLooping=function() end,IsPlaying=function() return false end,
                    Play=function() end,Stop=function() end}
            end
            return tex
        end
        return frame
    end
    for _,pair in ipairs({{33,37,"尼耶尔前哨站"},{22,38,"葬影村"}}) do
        local from,to,name=unpack(pair)
        local key=from..":"..to
        local flight={kind="transit",mode="flight",fromTaxi=from,toTaxi=to}
        N.actions={{kind="move"},flight}
        nodes={{nodeID=from,state=0,slotIndex=1},{nodeID=to,state=1,slotIndex=2,name=name}}
        kind="REACHABLE";T:CaptureTaxi();N:RefreshTaxiMarker()
        local mark=N.taxiMarker
        eq(mark.parent,TaxiButton2);eq(mark:IsShown(),true);eq(mark.label:GetText(),"下一步 · "..name);eq(B.char.flightRoutes[key],true)
        kind="DISTANT";T:CaptureTaxi(true);N:RefreshTaxiMarker()
        eq(T:TaxiDestination(),nil);eq(mark:IsShown(),false);eq(B.char.flightRoutes[key],nil)
        nodes[2]=nil;T:CaptureTaxi(true);eq(B.char.flightRoutes[key],nil)
        eq(N.StaleAction(flight,{transportKnown=true,unlocked={["taxi:"..from]=true,["taxi:"..to]=true},
            taxiAvailability=T.availability}),true)
    end
    -- The legacy map can draw selectable buttons without GetAllTaxiNodes reporting this menu.
    T:CloseTaxiMap();TaxiFrame:Hide()
    local station={"暴风城, 艾尔文森林","湖畔镇，赤脊山"}
    local count=0
    NumTaxiNodes=function() return count end
    TaxiNodeName=function(slot) return station[slot] end
    TaxiNodeGetType=function(slot) return slot==1 and "CURRENT" or kind end
    GetTaxiMapID=function() return 0 end
    N.actions={{kind="transit",mode="flight",fromTaxi=2,toTaxi=5}}
    local timers,boarded={},0
    C_Timer={After=function(delay,callback) timers[delay]=callback end}
    TakeTaxiNode=function(slot) eq(slot,2);boarded=boarded+1 end
    B.settings.autoTaxi=true
    N.taxiMarker.IsVisible=N.taxiMarker.IsShown
    B.frame.scripts.OnEvent(nil,"TAXIMAP_OPENED");timers[0]()
    eq(T:TaxiDestination(),nil)
    count,kind=2,"REACHABLE";TaxiFrame:Show();TaxiFrame.scripts.OnShow(TaxiFrame)
    eq(T:TaxiDestination(),2);eq(N.taxiMarker.parent,TaxiButton2);eq(N.taxiMarker:IsShown(),true)
    eq(N.taxiMarker.label:GetText(),"下一步 · 湖畔镇，赤脊山")
    eq(B.char.flightRoutes["2:5"],true);eq(boarded,0)
    timers[1]();eq(boarded,1)
    B.frame.scripts.OnEvent(nil,"TAXIMAP_CLOSED")
    B.frame.scripts.OnEvent(nil,"TAXIMAP_OPENED")
    B.frame.scripts.OnEvent(nil,"TAXIMAP_CLOSED");timers[1]();eq(boarded,1)
    B.settings.autoTaxi=false;B.frame.scripts.OnEvent(nil,"TAXIMAP_OPENED")
    kind="UNREACHABLE";T:CaptureTaxi(true);N:RefreshTaxiMarker()
    eq(T:TaxiDestination(),nil);eq(N.taxiMarker:IsShown(),false)
    station[2],kind="从未见过的站名","REACHABLE";T:CaptureTaxi(true)
    eq(T:TaxiDestination(),nil);eq(B.char.flightRoutes["2:5"],nil)
    T:CloseTaxiMap()
    GetTaxiMapID=function() return 1 end
    N.actions={{kind="move"},{kind="transit",mode="flight",fromTaxi=22,toTaxi=38}}
    TaxiFrame:Hide();FlightMapFrame=widget()
    local pin=widget();pin.taxiNodeData={nodeID=38,state=1}
    FlightMapFrame.EnumeratePinsByTemplate=function() return coroutine.wrap(function() coroutine.yield(pin) end) end
    local redraw
    hooksecurefunc=function(_,_,callback) redraw=callback end
    nodes[2]={nodeID=38,state=1,slotIndex=2,name="葬影村"}
    T:CaptureTaxi();N:RefreshTaxiMarker();eq(N.taxiMarker.parent,pin)
    pin.taxiNodeData.nodeID=37;redraw();eq(N.taxiMarker:IsShown(),false)
    pin.taxiNodeData.nodeID=38;redraw();eq(N.taxiMarker:IsShown(),true)
    T:CloseTaxiMap();redraw();eq(N.taxiMarker:IsShown(),false);eq(T:TaxiDestination(),nil)
    for _,key in ipairs(names) do _G[key]=saved[key] end
    B.finish()
end)
test("地图开关控制两张地图的标记范围且不改变导航",function()
    local B,adds=setupMap()
    B.Navigation.manual={map=1,x=0.5,y=0.5}
    B.settings.pins=false;B.settings.minimapPins=true;B.Navigation:RefreshPins()
    eq(adds.world,0);eq(adds.mini,1);eq(B.Navigation.pins[1],nil);eq(B.Navigation.pins[2].shown,true)
    B.settings.pins=true;B.settings.minimapPins=false;B.Navigation:RefreshPins()
    eq(adds.world,1);eq(adds.mini,1);eq(B.Navigation.pins[2].shown,false)
    eq(B.Navigation.pins[1].texture.texture,B.UI.IconTexture("location"))
    B.Navigation.manual=nil
    local collect={kind="objective",questId=1,position={map=1,x=0.2,y=0.1}}
    local accept={kind="accept",questId=2,position={map=1,x=0.3,y=0.1}}
    local p={fallback=collect,taskChoices={{questId=2,actions={accept},stages={accept}}}}
    B.settings.minimapPins=true;B.Navigation:SetPlan(p)
    local pins=B.Navigation.pins
    local scope=control(B,"mapTaskScope").button
    scope:Click();eq(B.settings.mapTaskScope,"route");eq(#B.Navigation:MapPoints(),1)
    eq(pins[1].shown,true);eq(pins[2].shown,true);eq(pins[3].shown,false)
    scope:Click();eq(B.settings.mapTaskScope,"off");eq(#B.Navigation:MapPoints(),0)
    eq(pins[1].shown,false);eq(pins[2].shown,false);eq(B.Navigation:Current(),collect)
    eq(B.Navigation.plan,p);eq(B.Navigation.index,1);eq(B.settings.pins,true);eq(B.settings.minimapPins,true)
    scope:Click();eq(B.settings.mapTaskScope,"all");eq(#B.Navigation:MapPoints(),2)
    eq(pins[3].shown,true);eq(pins[4].shown,true)
    B.finish()
end)
test("交付奖励只显示在任务列表且开关不触发自动领奖",function()
    local B=setup()
    B.frame.scripts.OnEvent(nil,"QUEST_COMPLETE")
    B.UI:RenderTracker()
    B.UI:SetNavigation(nil,nil,nil,B.action)
    assert(B.UI.tracker.reward.text.value:find("第 2 项",1,true));eq(B.UI.tracker.reward.shown,true)
    assert(not B.QuestAssist.info.text.value:find("奖励",1,true))
    B:SetOption("items",false);eq(B.QuestAssist.info.shown,false);eq(#B.QuestAssist.wanted,0)
    local reads=B.linkReads;B:SetOption("rewardAdvice",false)
    B.UI:RenderTracker();eq(B.linkReads,reads);eq(B.UI.tracker.reward.shown,false)
    B.frame.scripts.OnEvent(nil,"QUEST_FINISHED");eq(B.QuestAssist.rewardQuest,nil)
    B.finish()
end)
test("奖励缓存未知时等待比较且非装备不循环请求属性",function()
    local B=setup();B.items[101].pending=true
    B.frame.scripts.OnEvent(nil,"QUEST_COMPLETE")
    assert(B.QuestAssist.rewardLines[1]:find("奖励属性加载中",1,true));eq(B.requests,1)
    B.QuestAssist:Update();eq(B.requests,1)
    B.dirty=false;B.items[101].pending=false;B.QuestAssist:Update();eq(B.dirty,true)
    B.UI:RenderTracker();assert(B.UI.tracker.reward.text.value:find("第 2 项",1,true))
    B.choices={100,102};B.requests=0;B.QuestAssist:Update();B.QuestAssist:Update();eq(B.requests,0)
    B.finish()
end)
test("奖励武器关键数据缺失时不把已知护甲宣布为最佳",function()
    local B=setup();B.items[103]={name="武器",loc="INVTYPE_WEAPON",stats={ITEM_MOD_STRENGTH_SHORT=100}}
    B.choices={100,103};B.frame.scripts.OnEvent(nil,"QUEST_COMPLETE")
    assert(B.QuestAssist.rewardLines[1]:find("奖励属性加载中",1,true))
    eq(B.QuestAssist.rewardLines[1]:find("第 ",1,true),nil)
    B.finish()
end)
test("行动提示音首次静默重复去重并过滤战斗与设置更新",function()
    local B=setup();B:SetOption("sound",true);eq(B.sounds,0)
    B.action.kind="turnin";B.QuestAssist:Update();eq(B.sounds,1)
    B.QuestAssist:Update();eq(B.sounds,1)
    B.combat(true);B.action.kind="accept";B.time(20);B.QuestAssist:Update();eq(B.sounds,1)
    B.combat(false);B.QuestAssist:Update();eq(B.sounds,1)
    B.action.kind="objective";B.QuestAssist:Update(true);eq(B.sounds,1)
    B.finish()
end)
test("跟随队长快捷键按真实队伍更新且战斗后同步并保留任务",function()
    local B=setup();local Q=B.QuestAssist
    local grouped,raid,leader,connected,name,realm=true,false,"party2",true,"队长","异乡"
    IsInGroup=function() return grouped end;IsInRaid=function() return raid end
    UnitIsGroupLeader=function(unit) return unit==leader end;UnitIsConnected=function() return connected end
    UnitName=function() return name,realm end
    FollowUnit=function() error("跟随应由玩家按键执行") end
    B.action={kind="manual"};B.char.locked=1;Q:Update()
    eq(Q.followButton.type1,"macro");eq(Q.followButton.macrotext1,"/follow 队长-异乡")
    eq(Q.followButton.shown,true)
    leader,name,realm="party3","新队长",nil
    B.frame.scripts.OnEvent(nil,"PARTY_LEADER_CHANGED");assert(B.refreshAt)
    B.combat(true);local writes=Q.followButton.attributeWrites;Q:Update()
    eq(Q.followButton.attributeWrites,writes);eq(Q.followButton.macrotext1,"/follow 队长-异乡")
    B.combat(false);B.frame.scripts.OnEvent(nil,"PLAYER_REGEN_ENABLED")
    eq(Q.followButton.macrotext1,"/follow 新队长")
    leader="player";Q:Update();eq(Q.followButton.shown,false);eq(Q.followButton.macrotext1,nil)
    raid,leader,name,realm=true,"raid7","团队长","远行之地";Q:Update()
    eq(Q.followButton.macrotext1,"/follow 团队长-远行之地")
    connected=false;Q:Update();eq(Q.followButton.shown,false);connected=true
    name="队长\n/run bad()";Q:Update();eq(Q.followButton.macrotext1,nil)
    local secret={};canaccessvalue=function(value) return value~=secret end
    name=secret;Q:Update();eq(Q.followButton.shown,false)
    name="队长";B.settings.targets=false;Q:Update();eq(Q.followButton.shown,false)
    B.settings.targets=true;B.char.paused=true;Q:Update();eq(Q.followButton.shown,false)
    B.char.paused=false;grouped=false;Q:Update();eq(Q.followButton.macrotext1,nil)
    eq(B.char.locked,1);eq(B.state.completed[1],nil)
    B.finish()
end)
test("任务目标按钮按真实NPC身份更新，战斗结束同步且拒绝宏命令字符",function()
    local plate={namePlateUnitToken="nameplate1"}
    local B=setup(false,nil,{GetNamePlates=function() return {plate} end,GetNamePlateForUnit=function(unit)
        if unit=="nameplate1" then return plate end
    end});local Q=B.QuestAssist
    UnitGUID=function() return "Creature-0-1-2-3-10-0000" end
    local entities={[10]="矿工约翰",[20]="森林蜘蛛",[30]="旅店老板"}
    B.Data.db={Npc={Get=function(id,key) eq(key,"name");return entities[id] end}}
    B.action={kind="accept",questId=1,position={entityKind="npc",entityId=10}}
    Q:Update();eq(Q.targetActive.id,10)
    local list=Q.targetList;local row=list.rows[1]
    eq(list.parent,B.UI.navAnchor);eq(row.label:GetText(),"矿工约翰");eq(row.face.creature,10)
    row.face.scripts.OnModelLoaded(row.face);eq(row.face.zoom,1);eq(row.fallback.shown,false)
    assert(row.macrotext1:find("/cleartarget\n/targetexact 矿工约翰\n/tm",1,true))
    local written=row.attributeWrites;Q:Update();eq(row.attributeWrites,written)
    local manual=Q.targetButton.macrotext2
    eq(manual,"/tm [@target,harm,nodead] ~8\n/tm [@target,noharm,exists,nodead] ~1")
    local function markMacro(name) return "/cleartarget [nocombat]\n/targetexact "..name.."\n/stopmacro [combat]\n"..manual end
    eq(Q.targetButton.macrotext1,markMacro("矿工约翰"));eq(Q.targetButton.type1,"macro");eq(Q.targetButton.type2,"macro")
    local badge=Q.plateBadges.nameplate1
    eq(badge.shown,true);eq(badge.point[2],plate);eq(Q.plateIcon,"accept")
    local pickup=B.action
    B.action={kind="transit",mode="tram",questId=1,questAction=pickup,position={entityKind="npc",entityId=30}}
    Q:Update();eq(list.shown,true);eq(row.face.creature,10);eq(Q.plateIcon,"accept");eq(row.attributeWrites,written)
    B.action={kind="transit",mode="tram"};Q:Update();eq(list.shown,false)
    B.action=pickup;Q:Update()
    B:SetOption("markTargets",false);eq(badge.shown,false);eq(Q.targetButton.macrotext1,"/targetexact 矿工约翰")
    eq(row.macrotext1,"/targetexact 矿工约翰")
    B:SetOption("markTargets",true);eq(badge.shown,true)
    local raid,leader,assistant=IsInRaid,UnitIsGroupLeader,UnitIsGroupAssistant
    IsInRaid=function() return true end;UnitIsGroupLeader=function() return false end
    UnitIsGroupAssistant=function() return false end;Q:ApplyTarget()
    eq(Q.targetButton.macrotext2,nil);eq(Q.targetButton.macrotext1,"/targetexact 矿工约翰")
    UnitIsGroupAssistant=function() return true end;Q:ApplyTarget();eq(Q.targetButton.macrotext2,manual)
    IsInRaid,UnitIsGroupLeader,UnitIsGroupAssistant=raid,leader,assistant
    Q.container.scripts.OnEvent(nil,"NAME_PLATE_UNIT_REMOVED","nameplate1");eq(badge.shown,false)
    UnitGUID=function() return "Player-0-1-2-3-10-0000" end
    Q.container.scripts.OnEvent(nil,"NAME_PLATE_UNIT_ADDED","nameplate1");eq(badge.shown,false)
    eq(Q.targetButton.shown,true)
    eq(Q.targetButton.parent,UIParent);eq(Q.targetButton.text,nil);eq(Q.targetButton.status,nil)
    eq(Q.targetButton.template,"SecureActionButtonTemplate")
    local anchor=B.UI.tracker.actionIcon
    anchor.centerX,anchor.centerY=500,600;anchor:SetSize(18,18);B.UI.frame.scale=1.5
    Q:LayoutTarget();eq(Q.targetButton.point[2],UIParent)
    eq(Q.targetButton.point[4],750);eq(Q.targetButton.point[5],900);eq(Q.targetButton.width,36)
    eq(anchor.shown,true);eq(Q.targetButton.icon,nil)
    B.combat(true);anchor.centerX=700;Q:LayoutTarget();eq(Q.targetButton.point[4],750)
    B.combat(false);B.UI.frame.scripts.OnDragStop();eq(Q.targetButton.point[4],1050)
    local tip={};GameTooltip.SetOwner=function(_,owner) tip.owner=owner end
    GameTooltip.SetText=function(_,value) tip.title=value end
    GameTooltip.AddLine=function(_,value) tip[#tip+1]=value end;GameTooltip.Show=function() end
    Q.targetButton.scripts.OnEnter(Q.targetButton);eq(tip.owner,Q.targetButton)
    assert(tip.title:find("矿工约翰",1,true));assert(tip[1]:find("右键",1,true))
    UnitGUID=function() return "Creature-0-1-2-3-10-0000" end
    B.refreshAt=nil;B.frame.scripts.OnEvent(nil,"PLAYER_TARGET_CHANGED")
    assert(Q.targetStatus:find("已选中",1,true));eq(B.refreshAt,nil)
    local speedUpdates=0
    B.State.Movement=function(state) eq(state,B.state);speedUpdates=speedUpdates+1 end
    B.frame.scripts.OnEvent(nil,"UNIT_SPEED","target");eq(speedUpdates,0)
    B.frame.scripts.OnEvent(nil,"UNIT_SPEED","player");eq(speedUpdates,1);eq(B.refreshAt,nil)
    UnitGUID=function() return "Player-0-1-2-3-10-0000" end
    Q:TargetStatus();eq(Q.targetStatus:find("已选中",1,true),nil)
    B.action={kind="objective",questId=1,objectiveIndex=1,targetKind="npc",targetId=20}
    B.state.quests[1].objectives={{finished=false}}
    B.combat(true);local writes=Q.targetButton.attributeWrites
    Q:Update();eq(Q.targetActive.id,10);eq(Q.targetWanted.id,20);eq(Q.targetButton.attributeWrites,writes)
    assert(Q.targetStatus:find("战斗结束",1,true))
    B.combat(false);B.frame.scripts.OnEvent(nil,"PLAYER_REGEN_ENABLED")
    eq(Q.targetActive.id,20);eq(Q.targetButton.macrotext1,markMacro("森林蜘蛛"))
    B.state.quests[1].objectives[1].finished=true;Q:Update();eq(Q.targetButton.shown,false)
    B.state.quests[1].objectives[1].finished=false
    B.action.targetKind="item";B.action.targetId=100
    B.Data.ObjectiveTargets=function() return {{objectiveIndex=1,entityKind="npc",entityId=20}} end
    Q:Update();eq(Q.targetActive.id,20)
    B.Data.ObjectiveTargets=function() return {{objectiveIndex=1,entityKind="object",entityId=20}} end
    Q:Update();eq(Q.targetButton.shown,false)
    entities[21],entities[22]="黑熊","林间居民"
    B.action={kind="objective",questId=1,objectiveIndex=1,position={entityKind="npc",entityId=20}}
    B.state.quests[1].objectives={{finished=false},{finished=false}}
    B.Data.ObjectiveTargets=function() return {{objectiveIndex=1,entityKind="npc",entityId=20},{objectiveIndex=2,entityKind="npc",entityId=22}} end
    B.Data.ObjectiveIdentities=function() return {[1]={kind="killcredit",npcIds={20,21,21}},[2]={kind="npc",id=22}} end
    Q:Update();eq(#Q.targetChoices,3);eq(Q.targetActive.id,20)
    eq(list.rows[2].face.creature,21);assert(list.rows[2].macrotext1:find("/targetexact 黑熊\n",1,true))
    entities[23],entities[24]="小蜘蛛","大蜘蛛"
    local identities=B.Data.ObjectiveIdentities
    B.Data.ObjectiveIdentities=function() return {[1]={kind="killcredit",npcIds={20,21,23,24}},[2]={kind="npc",id=22}} end
    Q:Update();eq(#list.rows,4);eq(list.page.shown,true)
    row.scripts.OnMouseWheel(row,-1);eq(row.face.creature,22);eq(list.rows[2].shown,false)
    row.scripts.OnMouseWheel(row,1);eq(row.face.creature,20)
    B.Data.ObjectiveIdentities=identities;Q:Update()
    local wheel=assert(Q.targetButton.scripts.OnMouseWheel)
    wheel(nil,-1);eq(Q.targetActive.id,21);eq(Q.targetButton.macrotext1,markMacro("黑熊"))
    assert(Q.targetTitle:find("2/3",1,true))
    Q:Update();eq(Q.targetActive.id,21)
    UnitGUID=function() return "Creature-0-1-2-3-22-0000" end
    Q:TargetStatus();assert(Q.targetStatus:find("已选中 · 林间居民",1,true))
    Q.targetButton.scripts.PostClick(nil,"MiddleButton",true);eq(Q.targetActive.id,21)
    Q.targetButton.scripts.PostClick(nil,"MiddleButton",false);eq(Q.targetActive.id,22)
    wheel(nil,1);eq(Q.targetActive.id,21)
    B.combat(true);writes=Q.targetButton.attributeWrites;wheel(nil,-1);eq(Q.targetActive.id,21)
    B.state.quests[1].objectives[1].finished=true;Q:Update()
    eq(Q.targetActive.id,21);eq(Q.targetButton.attributeWrites,writes)
    B.combat(false);B.frame.scripts.OnEvent(nil,"PLAYER_REGEN_ENABLED")
    eq(Q.targetActive.id,22);eq(#Q.targetChoices,1)
    B.state.quests[1].ready=true;Q:Update();eq(Q.targetButton.shown,false);B.state.quests[1].ready=nil
    eq(list.shown,false)
    B.Data.ObjectiveIdentities=nil;B.state.quests[1].objectives={}
    B.action={kind="turnin",questId=1}
    B.Data.Target=function(_,q,s) eq(s.quests[1].ready,true);return {entityKind="npc",entityId=10} end
    UnitGUID=function() return "Creature-0-1-2-3-10-0000" end
    -- The same NPC goes from a pickup to a hand-in. Only its native question mark should remain.
    local handin=B.action;B.action=pickup;Q:Update();eq(badge.shown,true)
    local selectAndMark=row.macrotext1
    B.action=handin;Q:Update();eq(Q.targetActive.id,10);eq(badge.shown,false)
    B.state.quests[1].ready=true;Q:Update()
    Q.container.scripts.OnEvent(nil,"NAME_PLATE_UNIT_ADDED","nameplate1")
    eq(badge.shown,false);eq(row.face.creature,10);eq(row.macrotext1,selectAndMark)
    B.action={kind="accept",questId=2,position=pickup.position};Q:Update();eq(badge.shown,true)
    B.action=handin;Q:Update();eq(badge.shown,false)
    B.state.quests[1].ready=nil
    B.action.targetKind,B.action.targetId="npc",30;Q:Update();eq(row.face.creature,30)
    assert(row.macrotext1:find("/targetexact 旅店老板\n/tm",1,true))
    B.action.targetKind,B.action.targetId="object",30;Q:Update();eq(list.shown,false)
    B.action={kind="accept",questId=1,startItemId=100};Q:Update();eq(list.shown,false)
    B.action={kind="service",npcId=30};Q:Update();eq(Q.targetActive.id,30)
    eq(badge.shown,false)
    B.action={kind="manual"};Q:Update();eq(Q.targetButton.shown,false)
    B.action={kind="service",npcId=30};B:SetOption("targets",false);eq(Q.targetButton.shown,false)
    B:SetOption("targets",true);eq(Q.targetButton.shown,true)
    B:TogglePause();eq(Q.targetButton.shown,false);B:TogglePause();eq(Q.targetButton.shown,true)
    B.UI:TrackerMenu(B.UI.frame)
    B.combat(true);writes=Q.targetButton.attributeWrites
    B.menu["隐藏目标辅助"].callback();eq(B.settings.targets,false)
    eq(Q.targetButton.attributeWrites,writes)
    B:NormalizeSettings(B.settings);Q:Update()
    B.combat(false);B.frame.scripts.OnEvent(nil,"PLAYER_REGEN_ENABLED");eq(Q.targetButton.shown,false)
    B.UI:TrackerMenu(B.UI.frame);B.menu["显示目标辅助"].callback();eq(Q.targetButton.shown,true)
    for _,name in ipairs({"NPC\n/run bad()","NPC;bad","NPC[foo]","NPC/bar","NPC\\bar"," NPC","NPC "}) do
        entities[30]=name;Q:Update();eq(Q.targetButton.shown,false);eq(Q.targetButton.macrotext1,nil)
    end
    -- Native rare discoveries have their own button and never replace the task.
    local rare={guid="Creature-0-1-2-3-100-0000",name="觅食的灰熊",kind="rare"}
    local units={nameplate1=rare};local messages,errors,sounds={},{},0
    UnitClassification=function(unit) return units[unit] and units[unit].kind end
    UnitGUID=function(unit) return units[unit] and units[unit].guid end
    UnitName=function(unit) return units[unit] and units[unit].name end
    UnitLevel=function() return 12 end
    UnitCanAttack=function(_,unit) return units[unit] and not units[unit].friendly end
    UnitIsDeadOrGhost=function(unit) return units[unit] and units[unit].dead end
    UnitOnTaxi=function() return false end
    C_NamePlate={GetNamePlates=function() return {{namePlateUnitToken="nameplate1"}} end}
    local secret={};issecretvalue=function(value) return value==secret end
    canaccessvalue=function(value) return value~=secret end
    B.Message=function(_,text) messages[#messages+1]=text end
    UIErrorsFrame={AddMessage=function(_,text) errors[#errors+1]=text end}
    PlaySound=function(id,channel) eq(id,3175);eq(channel,"Master");sounds=sounds+1 end
    assert(loadfile("RareScanner.lua"))("AiLeveling",B)
    local actionBefore=B.action
    local R=B.RareScanner;R:Initialize();eq(#messages,1);eq(R.button.shown,true)
    eq(R.button.macrotext1,"/targetexact 觅食的灰熊");eq(Q.targetButton.shown,false)
    units.target=rare;R.events.scripts.OnEvent(nil,"PLAYER_TARGET_CHANGED");eq(#messages,1)
    R.events.scripts.OnEvent(nil,"NAME_PLATE_UNIT_ADDED","nameplate1");eq(#messages,1)
    local writes=R.button.attributeWrites;B.combat(true)
    rare.guid="Creature-0-1-2-3-101-0001";rare.name="霜鬃猎手";rare.kind="rareelite"
    R.events.scripts.OnEvent(nil,"UNIT_CLASSIFICATION_CHANGED","nameplate1")
    eq(#messages,2);eq(#errors,1);eq(sounds,0);eq(R.button.attributeWrites,writes)
    eq(R.button.macrotext1,"/targetexact 觅食的灰熊")
    B.combat(false);R.events.scripts.OnEvent(nil,"PLAYER_REGEN_ENABLED")
    eq(R.button.macrotext1,"/targetexact 霜鬃猎手");assert(R.button.heading.value:find("稀有精英",1,true))
    B:SetOption("scanRares",false);eq(R.button.shown,false)
    rare.guid="Creature-0-1-2-3-101-0002";R:Check("nameplate1");eq(#messages,2)
    B.settings.sound=true;B:SetOption("scanRares",true);eq(#messages,3);eq(sounds,1)
    R.button.scripts.PostClick(nil,"RightButton",false);eq(R.button.shown,false)
    R:Check("nameplate1");eq(#messages,3)
    for _,change in ipairs({{guid=secret},{name="NPC\n/run bad()"},{friendly=true},{dead=true},{kind="elite"},{guid="Player-0-1"}}) do
        local row={guid="Creature-0-1-2-3-102-0003",name="稀有",kind="rare"}
        for k,v in pairs(change) do row[k]=v end;units.nameplate1=row
        R:Check("nameplate1");eq(#messages,3)
    end
    units.nameplate1=rare;rare.guid="Creature-0-1-2-3-103-0004"
    B:TogglePause();R:Check("nameplate1");eq(#messages,3)
    B:TogglePause();eq(#messages,4);eq(R.button.shown,true)
    B.time(21);R.button.scripts.OnUpdate();eq(R.button.shown,false);eq(R.button.macrotext1,nil)
    eq(B.action,actionBefore)
    eq(B.state.quests[1].ready,nil);eq(next(B.state.completed),nil)
    B.finish()
end)
test("危险地图与急救提示随等级和实际生命呼吸变化，保留原生按钮",function()
    local B=setup();local Q=B.QuestAssist
    assert(loadfile("Data/Dangers.lua"))("AiLeveling",B)
    assert(loadfile("Dangers.lua"))("AiLeveling",B)
    local D=B.Dangers
    local canvas=widget();canvas:SetSize(800,500)
    WorldMapFrame=widget();WorldMapFrame.GetMapID=function() return 1429 end;WorldMapFrame.GetCanvas=function() return canvas end
    local marked=0
    B.Navigation.hbdPins={AddWorldMapIconMap=function(_,owner,pin,map,x,y)
        eq(owner,D);eq(map,1429);assert(x>=0 and x<=1 and y>=0 and y<=1);pin:Show();marked=marked+1
    end,RemoveAllWorldMapIcons=function(_,owner) eq(owner,D) end}
    B.state.faction,B.state.level="Alliance",7
    D:UpdateMap();assert(marked>0 and #D.segments>0);assert(D.overlay.shown)
    local route=B.action
    B.state.level=60;D:UpdateMap();eq(#D.segments,0)
    B.settings.dangerMap=false;D:UpdateMap();eq(D.overlay.shown,false);eq(D.mapKey,nil);eq(B.action,route)
    local oldDetail=QuestMapFrame_GetDetailQuestID
    local selected=1
    QuestMapFrame_GetDetailQuestID=function() return selected end
    B.Data.db={}
    local draws=0
    B.Data.QuestPatrolSegments=function(_,id,_,map,focus,out)
        eq(id,1);eq(map,1429);out[1]={0.2,0.3,0.4,0.5};draws=draws+1
    end
    B.state.quests[1]={objectives={{type="monster"}}}
    D:UpdateMap();eq(D.overlay.shown,true);eq(D.questSegments,1);eq(D.lines[1].color[1],1)
    D:UpdateMap();eq(draws,1)
    selected=nil;D:UpdateMap();eq(D.overlay.shown,false)
    B.Navigation.mapAreaAction={questId=1,kind="objective",objectiveIndex=1}
    D:UpdateMap();eq(D.overlay.shown,true)
    B.state.quests[1].objectives[1].finished=true;D:UpdateMap();eq(D.overlay.shown,false)
    QuestMapFrame_GetDetailQuestID=oldDetail;B.Navigation.mapAreaAction=nil
    local health,breath,rate=10,nil,-1
    local secret={}
    UnitHealth=function() return health end;UnitHealthMax=function() return 100 end
    UnitIsDeadOrGhost=function() return false end
    GetMirrorTimerInfo=function(i) if i==1 and breath then return "BREATH",breath,100,rate,false end;return "UNKNOWN" end
    GetMirrorTimerProgress=function() return breath end
    FlashClientIcon=function() end
    issecretvalue=function(value) return value==secret end
    canaccessvalue=function(value) return value~=secret end
    ActionButton1=widget();ActionButton1.GetPagedID=function() return 1 end
    GetActionInfo=function(slot) eq(slot,1);return "spell",633 end
    local bagButton=widget()
    C_Container.GetContainerItemID=function() return 118 end
    Q.EachBagButton=function(_,callback) callback(bagButton,0,1) end
    B.combat(true);D:Emergency()
    eq(D.warning.text.value,"生命危急");eq(D.glows[ActionButton1].shown,true);eq(D.glows[bagButton].shown,true)
    eq(ActionButton1.attributeWrites,0);eq(bagButton.attributeWrites,0)
    health=100;D:Emergency();eq(D.warning.shown,false);eq(D.glows[ActionButton1].shown,false)
    health=secret;D:Emergency();eq(D.warning.shown,false)
    breath=10;D:Emergency();eq(D.warning.text.value,"呼吸将尽 · 尽快上浮")
    rate=1;D:Emergency();eq(D.warning.shown,false)
    health=10;B.settings.emergency=false;D:Emergency();eq(D.warning.shown,false);eq(D.glows[bagButton].shown,false)
    B.combat(false);B.finish()
end)
test("练级统计按原生经验跨级结算，暂停AFK离线不计时并保留等级历史",function()
    local B=setup();local T=B.LevelingTracker
    B:InitializeProfiles(B.settings,B.char)
    UnitGUID=function() return "Player-1" end;UnitName=function() return "角色甲" end;GetRealmName=function() return "服务器" end
    local level,xp,maxXP,afk=20,900,1000,false
    UnitLevel=function() return level end;UnitXP=function() return xp end;UnitXPMax=function() return maxXP end
    UnitIsAFK=function(unit) eq(unit,"player");return afk end
    local event=B.frame.scripts.OnEvent
    event(nil,"PLAYER_XP_UPDATE","player")
    eq(B.char.leveling.levels[20].partial,true)
    B.state.level=level;B.refreshAt=nil
    B.time(20);xp=950;event(nil,"PLAYER_XP_UPDATE","target");eq(T.last.xp,900)
    event(nil,"PLAYER_XP_UPDATE","player");eq(B.char.leveling.levels[20].xp,50);eq(B.refreshAt,nil);eq(B.state.xp,950)
    B.time(30);xp=40;event(nil,"PLAYER_XP_UPDATE","player");eq(T.last.xp,950)
    level=21;maxXP=2000;event(nil,"PLAYER_LEVEL_UP",21);event(nil,"PLAYER_XP_UPDATE","player")
    eq(B.char.leveling.levels[20].xp,100);eq(B.char.leveling.levels[21].xp,40)
    eq(T.sessionXP,140);eq(B.char.leveling.levels[20].completed,true)
    eq(B.char.leveling.levels[20].seconds,20);eq(B.char.leveling.levels[21].partial,false)
    B.time(40);B:TogglePause();eq(T.running,false)
    B.time(90);xp=100;event(nil,"PLAYER_XP_UPDATE","player");B:TogglePause()
    B.time(100);afk=true;event(nil,"PLAYER_FLAGS_CHANGED","player")
    B.time(160);xp=150;event(nil,"PLAYER_XP_UPDATE","player")
    afk=false;event(nil,"PLAYER_FLAGS_CHANGED","player")
    B.time(170);xp=180;event(nil,"PLAYER_XP_UPDATE","player")
    eq(T.sessionSeconds,50);eq(T.sessionXP,170)
    event(nil,"PLAYER_DEAD");event(nil,"PLAYER_DEAD");eq(B.char.leveling.levels[21].deaths,1)
    event(nil,"PLAYER_ALIVE");event(nil,"PLAYER_DEAD");eq(B.char.leveling.levels[21].deaths,2)
    local stateModule={};assert(loadfile("State.lua"))("AiLeveling",stateModule)
    B.State.TurnedIn=stateModule.State.TurnedIn
    -- The module closure needs this addon's actual state and character tables.
    stateModule.state=B.state;stateModule.char=B.char
    local receipts=0
    B.UI.DungeonTurnedIn=function(_,id) eq(id,1);receipts=receipts+1 end
    event(nil,"QUEST_TURNED_IN",1,100,0);event(nil,"QUEST_TURNED_IN",1,100,0);eq(receipts,1)
    eq(B.char.leveling.levels[21].quests,1)
    B.time(180);B:SetOption("levelingStats",false)
    local before=B.char.leveling.levels[21].seconds
    B.time(280);xp=300;event(nil,"PLAYER_XP_UPDATE","player");eq(B.char.leveling.levels[21].seconds,before)
    B:SetOption("levelingStats",true);B.time(290);xp=320;event(nil,"PLAYER_XP_UPDATE","player")
    eq(T.sessionSeconds,70);eq(T.sessionXP,190)
    event(nil,"PLAYER_LOGOUT")
    assert(loadfile("LevelingTracker.lua"))("AiLeveling",B);T=B.LevelingTracker
    B.time(2000);event(nil,"PLAYER_XP_UPDATE","player")
    eq(B.char.leveling.levels[21].seconds,before+10);eq(T.sessionSeconds,nil)
    B.time(2010);xp=350;event(nil,"PLAYER_XP_UPDATE","player")
    eq(T.sessionSeconds,10);eq(T.sessionXP,30)
    local report=T:Report();assert(report:find("累计活动 0:01:20",1,true));assert(report:find("经验 220",1,true))
    assert(report:find("20 级（部分记录） · 已升级",1,true));assert(report:find("交付 1 · 死亡 2",1,true))
    B.char.leveling.levels[1]={seconds=0/0,xp=10,quests=0,deaths=0}
    B.char.leveling.levels[61]={seconds=1,xp=10,quests=0,deaths=0}
    T.Normalize(B.char);eq(B.char.leveling.levels[1],nil);eq(B.char.leveling.levels[61],nil)
    eq(B.char.leveling.levels[20].completed,true)
    level=22;xp=0;B.time(2020);event(nil,"PLAYER_XP_UPDATE","player")
    level=23;B.time(2120);event(nil,"PLAYER_XP_UPDATE","player")
    eq(B.db.levelingRuns["Player-1"],B.char.leveling)
    local original=B.char
    B.char={};T.last,T.lastAt,T.reportKey=nil,nil,nil
    UnitGUID=function() return "Player-2" end;UnitName=function() return "角色乙" end
    level=21;xp=500;event(nil,"PLAYER_XP_UPDATE","player")
    level=22;xp=0;B.time(2130);event(nil,"PLAYER_XP_UPDATE","player")
    level=23;B.time(2250);event(nil,"PLAYER_XP_UPDATE","player")
    local comparison=T:Report()
    assert(comparison:find("对比 角色甲 - 服务器",1,true))
    assert(comparison:find("22→23 级 · 本角色 0:02:00 · 对方 0:01:40 · 慢 0:00:20",1,true))
    assert(comparison:find("1 个相同等级合计",1,true))
    eq(B.db.levelingRuns["Player-1"],original.leveling)
    eq(B.db.levelingRuns["Player-2"],B.char.leveling)
    B.finish()
end)
dofile("tests/tracker.lua")(test,eq,setup)
end
