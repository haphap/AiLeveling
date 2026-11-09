return function(test,eq,F,A,plan)
local names={"CreateFrame","UIParent","STANDARD_TEXT_FONT","GameFontHighlight","SlashCmdList","InCombatLockdown","GetTime","UnitClass","RAID_CLASS_COLORS",
    "geterrorhandler","C_Item","C_PlayerInfo","C_Container","GetQuestID","GetNumQuestChoices","GetQuestItemLink","GetQuestReward",
    "AcceptQuest","CompleteQuest","GetQuestMoneyToGet","IsQuestCompletable","IsShiftKeyDown","C_GossipInfo","UnitGUID","UnitLevel","UnitXP","UnitXPMax","UnitIsAFK",
    "PlaySound","SOUNDKIT","NUM_CONTAINER_FRAMES","ContainerFrameCombinedBags","AiLeveling",
    "debugprofilestop","C_PlayerInteractionManager","UnitClassification","UnitName","UnitCanAttack","UnitIsDeadOrGhost","UnitOnTaxi","C_NamePlate","UIErrorsFrame","issecretvalue","canaccessvalue","Enum",
    "IsInGroup","IsInRaid","UnitIsGroupLeader","UnitIsConnected","FollowUnit",
    "GetQuestLink","ChatFrameUtil","IsModifiedClick","QuestMapFrame_OpenToQuestDetails","GetRealmName",
    "WorldMapFrame","UnitHealth","UnitHealthMax","GetMirrorTimerInfo","GetMirrorTimerProgress","FlashClientIcon","GetActionInfo","ActionButton1"}
local function widget()
    local w={scripts={},width=100,height=40,shown=true,attributeWrites=0}
    for _,key in ipairs({"SetBackdrop","SetBackdropBorderColor","SetJustifyH","SetJustifyV","SetMovable","EnableMouse","EnableMouseWheel","RegisterForDrag",
        "RegisterForClicks","SetAllPoints","SetTexture","SetBlendMode","SetVertexColor","SetMaxLines","SetFontObject","SetMultiLine",
        "SetMaxLetters","SetShadowColor","SetShadowOffset","SetAutoFocus","ClearFocus","SetFocus","HighlightText","SetFrameStrata","SetCooldown","Clear"}) do w[key]=function() end end
    w.SetPoint=function(self,...) self.point={...} end
    w.GetPoint=function(self) return "CENTER",UIParent,"CENTER",25,-30 end
    w.ClearAllPoints=function(self) self.point=nil end
    w.SetSize=function(self,x,y) self.width,self.height=x,y end
    w.SetWidth=function(self,x) self.width=x end;w.SetHeight=function(self,y) self.height=y end
    w.GetSize=function(self) return self.width,self.height end
    w.GetWidth=function(self) return self.width end;w.GetHeight=function(self) return self.height end
    w.SetText=function(self,v) self.value=v end;w.GetText=function(self) return self.value or "" end
    w.GetStringHeight=function(self) return self.measuredHeight or 30 end
    w.SetFont=function(self,face,size,flags)
        assert(self.kind~="EditBox" or type(flags)=="string","bad argument #3 to SetFont: EditBox requires flags")
        self.fontSize,self.fontFlags=size,flags
        return true
    end
    w.SetAtlas=function(self,atlas) self.atlas=atlas end
    w.SetTextColor=function(self,...) self.color={...} end;w.SetColorTexture=w.SetTextColor
    w.SetBackdropColor=w.SetTextColor
    w.SetScale=function(self,v) self.scale=v end;w.SetAlpha=function(self,v) self.alpha=v end
    w.SetScript=function(self,event,callback) self.scripts[event]=callback end
    w.RegisterForClicks=function(self,...) self.clicks={...} end
    w.RegisterEvent=function(self,event) self.events=self.events or {};self.events[event]=true end
    w.StartMoving=function(self) self.moving=true end;w.StopMovingOrSizing=function(self) self.moving=false end
    w.Show=function(self) self.shown=true end;w.Hide=function(self) self.shown=false end
    w.SetShown=function(self,v) self.shown=v end;w.IsShown=function(self) return self.shown end
    w.SetEnabled=function(self,v) self.enabled=v end
    w.GetChecked=function(self) return self.checked end;w.SetChecked=function(self,v) self.checked=v end
    w.SetAttribute=function(self,k,v) assert(not InCombatLockdown(),"战斗中修改了受保护按钮");self.attributeWrites=self.attributeWrites+1;self[k]=v end
    w.SetDesaturated=function() end
    w.SetScrollChild=function(self,child) self.child=child end
    w.SetVerticalScroll=function(self,v) self.offset=v end
    w.CreateTexture=function() return widget() end;w.CreateFontString=function() return widget() end
    w.CreateLine=function() local line=widget();line.SetThickness=function() end;line.SetStartPoint=function() end;line.SetEndPoint=function() end;return line end
    return w
end
local function setup(fullUI)
    local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
    local clock,combat=10,false
    UIParent=widget();STANDARD_TEXT_FONT="font";GameFontHighlight={};SlashCmdList={};NUM_CONTAINER_FRAMES=0;ContainerFrameCombinedBags=nil
    CreateFrame=function(kind)
        local w=widget();w.kind=kind;if kind=="CheckButton" then w.Text=widget() end;return w
    end
    InCombatLockdown=function() return combat end;GetTime=function() return clock end
    debugprofilestop=function() return 0 end
    local B={}
    assert(loadfile("Core.lua"))("AiLeveling",B)
    B.settings={};for k,v in pairs(B.defaults) do B.settings[k]=v end
    B.char={samples={},skipped={},deferredChains={},turnIns={}}
    B.state=F.State();B.state.bags[500]=2;B.state.quests[1]={objectives={}}
    local q=F.Quest(1);q.itemRules={[500]={kind="use",count=5,recovery="找 NPC 补领"}}
    B.Data=F.Data({[1]=q});B.Data.count=1;B.Content=B.Data.content
    B.action={kind="objective",questId=1,objectiveIndex=1}
    local nav={};assert(loadfile("Navigation.lua"))("AiLeveling",nav)
    B.Navigation={Current=function() return B.action end,RefreshPins=function() end,Target=nav.Navigation.Target,StaleAction=nav.Navigation.StaleAction}
    B.Dungeon={};B.Transport={InvalidateSample=function() end,InFlight=function() return false end}
    B.State={Refresh=function() B.refreshes=(B.refreshes or 0)+1;B.state.revision=B.state.revision+1 end}
    B.Gear=A.Gear;B.ready=true
    assert(loadfile("LevelingTracker.lua"))("AiLeveling",B)
    B.Selection={CanChoose=function() return false,"没有候选行程" end}
    local items={[500]={name="道具",loc="",stats=nil},[100]={name="奖励甲",loc="INVTYPE_HEAD",stats={ITEM_MOD_STRENGTH_SHORT=1}},
        [101]={name="奖励乙",loc="INVTYPE_HEAD",stats={ITEM_MOD_STRENGTH_SHORT=10}},[102]={name="药水",loc="",stats=nil}}
    local function idOf(value) return type(value)=="number" and value or tonumber(value:match("item:(%d+)")) end
    B.requests=0
    C_Item={GetItemNameByID=function(id) return items[id] and items[id].name end,GetItemIconByID=function() return 1 end,
        RequestLoadItemDataByID=function() B.requests=B.requests+1 end,
        GetItemInfo=function(value)
            local id=idOf(value);local item=items[id];if not item or item.pending then return end
            return item.name,"item:"..id,2,20,1,"","",1,item.loc,1,0,4,0
        end,GetItemStats=function(value) return items[idOf(value)].stats end,
        GetItemInfoInstant=function(id) return id,"","",items[id] and items[id].loc,1,4,0 end}
    C_PlayerInfo={CanUseItem=function() return true end}
    C_Container={GetItemCooldown=function() return 0,0 end}
    GetQuestID=function() return 1 end
    B.choices={100,101};B.linkReads=0
    GetNumQuestChoices=function() return #B.choices end
    GetQuestItemLink=function(kind,index) eq(kind,"choice");B.linkReads=B.linkReads+1;return "item:"..B.choices[index] end
    GetQuestReward=function() error("插件不能替玩家领取奖励") end
    B.sounds=0;SOUNDKIT={IG_QUEST_LIST_SELECT=123};PlaySound=function(id) eq(id,123);B.sounds=B.sounds+1 end
    assert(loadfile("Items.lua"))("AiLeveling",B)
    assert(loadfile("UI/Main.lua"))("AiLeveling",B)
    assert(loadfile("UI/Tracker.lua"))("AiLeveling",B)
    assert(loadfile("UI/Settings.lua"))("AiLeveling",B)
    local U=B.UI
    if fullUI then
        for _,name in ipairs({"Dungeon","Gear","Plan","Chains","Services"}) do
            assert(loadfile("UI/"..name..".lua"))("AiLeveling",B)
        end
        U:Create()
    else U:CreateTracker();U.details=widget() end
    U.title.measuredHeight=40;U.body.measuredHeight=300
    if not fullUI then U.Settings:Create(U.details) end;U.Settings:Refresh()
    assert(loadfile("QuestAssist.lua"))("AiLeveling",B)
    B.QuestAssist:Create();B.QuestAssist:Update()
    B.items=items
    B.combat=function(value) combat=value end;B.time=function(value) clock=value end
    B.finish=function() for _,name in ipairs(names) do _G[name]=saved[name] end end
    return B
end
local function control(B,key)
    for _,row in ipairs(B.UI.Settings.controls) do if row.key==key then return row end end
    error("设置缺少入口："..key)
end

test("完整界面显示任务和详情，初始化失败显示可复制错误",function()
    local B=setup(true)
    B.Initialize=function(self) self.UI:Render() end
    eq(B:Start(),true)
    assert(B.UI.title:GetText()~="")
    B.UI:ToggleDetails()
    assert(B.UI.details:IsShown())
    assert(B.UI.detailText:GetText()~="")
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
end)
test("设置开关跨归一化保留且清除已取消的旧采样",function()
    local B=setup()
    local row=control(B,"quantity");row.button.checked=false;row.button.scripts.OnClick()
    eq(B.settings.quantity,false);B:NormalizeSettings(B.settings);eq(B.settings.quantity,false)
    control(B,"gearPreference").button.scripts.OnClick();eq(B.settings.gearPreference,"xp");assert(B.refreshes>0)
    for _,key in ipairs({"quest","move","recovery","taskwork:old","tasktalk:v1:turnin:fast"}) do B.char.samples[key]={n=3,mean=10,m2=0} end
    B.char.sampleContext="old equipment context"
    B:NormalizeCharacter(B.char);eq(next(B.char.samples),nil);eq(B.char.sampleContext,nil)
    B.finish()
end)
test("配置迁移、复制、切换与恢复保留角色进度，并可刷新任务历史",function()
    local B=setup();local char=B.char
    char.turnIns[1]=1;char.locked=1;B.state.completed[1]=true
    local db={scale=1.3,quantity=false,position={"RIGHT","RIGHT",-120,80}}
    B:InitializeProfiles(db,char)
    eq(B.settings.scale,1.3);eq(B.settings.quantity,false);eq(db.scale,nil)
    local S=B.UI.Settings
    S.profileName:SetText("大字")
    S.profileName.scripts.OnEnterPressed()
    eq(char.profile,"大字");eq(B.settings.scale,1.3)
    B:SetOption("fontScale",1.2);B.settings.position[3]=-200
    eq(db.profiles["默认"].position[3],-120)
    B:SelectProfile("默认");eq(B.settings.fontScale,1);eq(B.UI.frame.point[4],-120)
    S.profile.scripts.OnClick();eq(char.profile,"大字");eq(B.settings.fontScale,1.2)
    db.defaultProfile="大字"
    local other={};B:InitializeProfiles(db,other);eq(other.profile,"大字")
    B:InitializeProfiles(db,char);B:RestoreSettings()
    eq(db.profiles["默认"].scale,1.3);eq(B.settings.scale,1);eq(B.settings.position,nil)
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
    dialog();eq(menus,0);eq(#calls,0) -- Manual turn-in takes priority over service automation.
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
    B.refreshAt=nil;B:Queue("plan",function() coroutine.yield();accept.requireCheck=false end)
    update();eq(#calls,0);assert(B.jobs.plan)
    update();eq(calls[1],"accept:2");eq(B.jobs["quest:dialog"],nil);eq(B.jobs.plan,nil)
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
    B.finish()
end)
test("窗口锁定阻止拖动且主详情分别保存位置并恢复",function()
    local B=setup();local U=B.UI
    U:Movable(U.frame,"position");U:Movable(U.details,"detailPosition")
    B.settings.lockWindow=true;U.frame.scripts.OnDragStart();eq(U.frame.moving,nil)
    B.settings.lockWindow=false;U.details.scripts.OnDragStart();eq(U.details.moving,true)
    U.details.scripts.OnDragStop();eq(B.settings.detailPosition[3],25)
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
    B.finish()
end)
test("战斗中显示设置不改变受保护容器和按钮属性",function()
    local B=setup();local Q=B.QuestAssist
    local writes=Q.buttons[1].attributeWrites
    local width,height=Q.container:GetSize()
    B.combat(true)
    B:SetOption("fontScale",1.1);B:SetOption("density","expanded");B:SetOption("quantity",false)
    eq(Q.buttons[1].attributeWrites,writes);eq(Q.buttons[1].count.value,2)
    eq(Q.container.width,width);eq(Q.container.height,height);assert(Q.pending)
    B.combat(false);Q:ApplyPending();eq(Q.buttons[1].count.value,"")
    B.finish()
end)
test("世界地图点与小地图点独立且关闭方没有游离图标",function()
    local B=setup();B.Transport.FlightGate=function() end
    assert(loadfile("Navigation.lua"))("AiLeveling",B)
    B.Navigation.manual={map=1,x=0.5,y=0.5}
    local world,mini=0,0
    B.Navigation.hbdPins={RemoveAllWorldMapIcons=function() end,RemoveAllMinimapIcons=function() end,
        AddWorldMapIconMap=function(_,owner,pin) world=world+1;pin:Show() end,
        AddMinimapIconMap=function(_,owner,pin,map,x,y,parent,floatOnEdge) mini=mini+1;pin.floats=floatOnEdge;pin:Show() end}
    B.settings.pins=false;B.settings.minimapPins=true;B.Navigation:RefreshPins()
    eq(world,0);eq(mini,1);eq(B.Navigation.pins[1].shown,false);eq(B.Navigation.pins[2].shown,true)
    B.settings.pins=true;B.settings.minimapPins=false;B.Navigation:RefreshPins()
    eq(world,1);eq(mini,1);eq(B.Navigation.pins[2].shown,false)
    eq(B.Navigation.pins[1].texture.atlas,"Waypoint-MapPin-Tracked")
    B.Navigation.manual=nil
    for _,row in ipairs({{"accept","QuestNormal"},{"turnin","UI-QuestPoi-QuestBangTurnIn"},
        {"objective","Waypoint-MapPin-Tracked"},{"transit","FlightPath"},{"dungeonEnter","Dungeon"}}) do
        B.Navigation.actions={{kind=row[1],mode="flight",position={map=1,x=0.5,y=0.5}}}
        B.Navigation:RefreshPins()
        eq(B.Navigation.pins[1].texture.atlas,row[2]);eq(B.Navigation.pins[2].texture.atlas,row[2])
    end
    local current={kind="objective",questId=1,title="当前目标",position={map=1,x=0.1,y=0.2}}
    local nextGoal={kind="objective",questId=2,title="跨区目标",position={map=2,x=0.3,y=0.4}}
    local steps={{stage=current},{stage=nextGoal}}
    for id=2,6 do
        local action={kind="turnin",questId=id,title="一起交付 "..id,position={map=1,x=0.7,y=0.2}}
        steps[#steps+1]=id==2 and {choice={stages={action}}} or {stage=action}
    end
    B.Navigation:SetPlan({fallback=current,taskQueue={steps=steps}})
    B.settings.pins,B.settings.minimapPins=true,true;world,mini=0,0
    B.Navigation:RefreshPins();eq(world,3);eq(mini,3);eq(#B.Navigation.pins,6)
    local pins=B.Navigation.pins
    eq(pins[1].point.action,current);eq(pins[3].point.action,nextGoal);eq(pins[3].point.position.map,2)
    eq(#pins[5].point.actions,5);eq(pins[5].number.value,"03");eq(pins[2].floats,true);eq(pins[4].floats,false)
    local oldTooltip,tooltip=GameTooltip,{lines={}}
    GameTooltip={SetOwner=function() end,SetText=function(_,text) tooltip.title=text end,
        AddLine=function(_,text) tooltip.lines[#tooltip.lines+1]=text end,Show=function() end,Hide=function() end}
    pins[5].scripts.OnEnter(pins[5]);eq(#tooltip.lines,5)
    assert(tooltip.title:find("一起交付 2",1,true));assert(tooltip.lines[5]:find("交付 · 一起交付 6",1,true))
    GameTooltip=oldTooltip
    B.Navigation.manual={map=3,x=0.5,y=0.5};world,mini=0,0
    B.Navigation:RefreshPins();eq(world,1);eq(mini,1);eq(pins[3].shown,false);eq(pins[6].shown,false)
    B.Navigation.manual=nil;world,mini=0,0;B.Navigation:RefreshPins();eq(world,3);eq(mini,3)
    B.Navigation.plan={};B.Navigation.actions={nextGoal};world,mini=0,0
    B.Navigation:RefreshPins();eq(world,1);eq(mini,1);eq(pins[1].point.action,nextGoal);eq(pins[5].shown,false)
    B.Navigation.plan={taskChoices={{questId=2,stages={nextGoal,steps[3].choice.stages[1]}},
        {questId=7,stages={{kind="accept",position={map=4,x=0.1,y=0.1}}}}}}
    B.Navigation:RefreshPins();eq(#B.Navigation:MapPoints(),2);eq(pins[3].point.action,steps[3].choice.stages[1])
    B.char.paused=true;world,mini=0,0;B.Navigation:RefreshPins();eq(world,0);eq(mini,0);eq(pins[1].shown,false)
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
    B.state.quests[1].objectives[1].finished=true;B.state.revision=B.state.revision+1
    eq(B.Navigation:Current(),nil);eq(#B.Navigation:MapPoints(),3)
    B.Navigation:RefreshPins();eq(pins[1].point.action,other)
    B.state.quests[1].ready=true;B.state.quests[1].objectives[2].finished=true
    eq(#B.Navigation:MapPoints(),2);eq(B.Navigation.index,1)
    local transit={kind="transit",mode="flight",questId=1,position={map=2,x=0.1,y=0.1}}
    B.Navigation.plan.travelActions={transit,current};B.Navigation.actions={transit,current}
    eq(B.Navigation:Current(),nil);eq(#B.Navigation:MapPoints(),2)
    current.itemGain=2;eq(B.Navigation:Current(),transit);current.itemGain=nil
    delivery.expected=nil;B.Navigation:SetPlan({revision=B.state.revision,fallback=delivery})
    B.state.quests[1].ready=false;B.state.revision=B.state.revision+1
    eq(B.Navigation:Current(),nil);eq(#B.Navigation:MapPoints(),0)
    B.Navigation.manual={map=4,x=0.5,y=0.5};eq(B.Navigation:Current().kind,"manual")
    eq(B.state.quests[1].objectives[1].finished,true);eq(B.state.completed[1],nil)
    B.finish()
end)
test("真实交付界面比较奖励且开关不触发自动领奖",function()
    local B=setup()
    B.frame.scripts.OnEvent(nil,"QUEST_COMPLETE")
    assert(B.QuestAssist.detailsText:find("第 2 项",1,true));assert(not B.QuestAssist.detailsText:find("由玩家确认领取",1,true))
    B:SetOption("items",false);eq(B.QuestAssist.info.shown,true);eq(#B.QuestAssist.wanted,0)
    local reads=B.linkReads;B:SetOption("rewardAdvice",false)
    eq(B.linkReads,reads);eq(B.QuestAssist.detailsText:find("奖励建议",1,true),nil)
    B.frame.scripts.OnEvent(nil,"QUEST_FINISHED");eq(B.QuestAssist.rewardQuest,nil)
    B.finish()
end)
test("奖励缓存未知时等待比较且非装备不循环请求属性",function()
    local B=setup();B.items[101].pending=true
    B.frame.scripts.OnEvent(nil,"QUEST_COMPLETE")
    assert(B.QuestAssist.detailsText:find("奖励属性加载中",1,true));eq(B.requests,1)
    B.QuestAssist:Update();eq(B.requests,1)
    B.items[101].pending=false;B.QuestAssist:Update();assert(B.QuestAssist.detailsText:find("第 2 项",1,true))
    B.choices={100,102};B.requests=0;B.QuestAssist:Update();B.QuestAssist:Update();eq(B.requests,0)
    B.finish()
end)
test("奖励武器关键数据缺失时不把已知护甲宣布为最佳",function()
    local B=setup();B.items[103]={name="武器",loc="INVTYPE_WEAPON",stats={ITEM_MOD_STRENGTH_SHORT=100}}
    B.choices={100,103};B.frame.scripts.OnEvent(nil,"QUEST_COMPLETE")
    assert(B.QuestAssist.detailsText:find("奖励属性加载中",1,true))
    eq(B.QuestAssist.detailsText:find("奖励建议：",1,true),nil)
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
test("跟随队长按真实队伍生成点击入口且战斗后同步并保留任务",function()
    local B=setup();local Q=B.QuestAssist
    local grouped,raid,leader,connected,name,realm=true,false,"party2",true,"队长","异乡"
    IsInGroup=function() return grouped end;IsInRaid=function() return raid end
    UnitIsGroupLeader=function(unit) return unit==leader end;UnitIsConnected=function() return connected end
    UnitName=function() return name,realm end
    FollowUnit=function() error("跟随应由玩家点击执行") end
    B.action={kind="manual"};B.char.locked=1;Q:Update()
    eq(Q.followButton.type1,"macro");eq(Q.followButton.macrotext1,"/follow 队长-异乡")
    eq(Q.followButton.shown,true);eq(Q.followButton.point[2],Q.info)
    leader,name,realm="party3","新队长",nil
    B.frame.scripts.OnEvent(nil,"PARTY_LEADER_CHANGED");assert(B.refreshAt)
    B.combat(true);local writes=Q.followButton.attributeWrites;Q:Update()
    eq(Q.followButton.attributeWrites,writes);eq(Q.followButton.macrotext1,"/follow 队长-异乡")
    assert(Q.followButton.text.value:find("待更新",1,true))
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
    local B=setup();local Q=B.QuestAssist
    local entities={[10]="矿工约翰",[20]="森林蜘蛛",[30]="旅店老板"}
    B.Data.db={Npc={Get=function(id,key) eq(key,"name");return entities[id] end}}
    B.action={kind="accept",questId=1,position={entityKind="npc",entityId=10}}
    Q:Update();eq(Q.targetActive.id,10);eq(Q.targetButton.macrotext1,"/targetexact 矿工约翰")
    eq(Q.targetButton.type1,"macro");eq(Q.targetButton.type2,"raidtarget")
    eq(Q.targetButton.action2,"set-unmarked");eq(Q.targetButton.unit2,"target");eq(Q.targetButton.marker2,8)
    eq(Q.targetButton.shown,true)
    UnitGUID=function() return "Creature-0-1-2-3-10-0000" end
    B.refreshAt=nil;B.frame.scripts.OnEvent(nil,"PLAYER_TARGET_CHANGED")
    assert(Q.targetButton.status.value:find("已选中",1,true));eq(B.refreshAt,nil)
    B.frame.scripts.OnEvent(nil,"UNIT_SPEED","target");eq(B.refreshAt,nil)
    B.frame.scripts.OnEvent(nil,"UNIT_SPEED","player");assert(B.refreshAt)
    UnitGUID=function() return "Player-0-1-2-3-10-0000" end
    Q:TargetStatus();eq(Q.targetButton.status.value:find("已选中",1,true),nil)
    B.action={kind="objective",questId=1,objectiveIndex=1,targetKind="npc",targetId=20}
    B.state.quests[1].objectives={{finished=false}}
    B.combat(true);local writes=Q.targetButton.attributeWrites
    Q:Update();eq(Q.targetActive.id,10);eq(Q.targetWanted.id,20);eq(Q.targetButton.attributeWrites,writes)
    assert(Q.targetButton.status.value:find("战斗结束",1,true))
    B.combat(false);B.frame.scripts.OnEvent(nil,"PLAYER_REGEN_ENABLED")
    eq(Q.targetActive.id,20);eq(Q.targetButton.macrotext1,"/targetexact 森林蜘蛛")
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
    local wheel=assert(Q.targetButton.scripts.OnMouseWheel)
    wheel(nil,-1);eq(Q.targetActive.id,21);eq(Q.targetButton.macrotext1,"/targetexact 黑熊")
    assert(Q.targetButton.text.value:find("2/3",1,true))
    Q:Update();eq(Q.targetActive.id,21)
    UnitGUID=function() return "Creature-0-1-2-3-22-0000" end
    Q:TargetStatus();assert(Q.targetButton.status.value:find("已选中 · 林间居民",1,true))
    Q.targetButton.scripts.PostClick(nil,"MiddleButton",true);eq(Q.targetActive.id,21)
    Q.targetButton.scripts.PostClick(nil,"MiddleButton",false);eq(Q.targetActive.id,22)
    wheel(nil,1);eq(Q.targetActive.id,21)
    B.combat(true);writes=Q.targetButton.attributeWrites;wheel(nil,-1);eq(Q.targetActive.id,21)
    B.state.quests[1].objectives[1].finished=true;Q:Update()
    eq(Q.targetActive.id,21);eq(Q.targetButton.attributeWrites,writes)
    B.combat(false);B.frame.scripts.OnEvent(nil,"PLAYER_REGEN_ENABLED")
    eq(Q.targetActive.id,22);eq(#Q.targetChoices,1)
    B.state.quests[1].ready=true;Q:Update();eq(Q.targetButton.shown,false);B.state.quests[1].ready=nil
    B.Data.ObjectiveIdentities=nil;B.state.quests[1].objectives={}
    B.action={kind="turnin",questId=1}
    B.Data.Target=function(_,q,s) eq(s.quests[1].ready,true);return {entityKind="npc",entityId=10} end
    Q:Update();eq(Q.targetActive.id,10)
    B.action={kind="service",npcId=30};Q:Update();eq(Q.targetActive.id,30)
    B.action={kind="manual"};Q:Update();eq(Q.targetButton.shown,false)
    B.action={kind="service",npcId=30};B:SetOption("targets",false);eq(Q.targetButton.shown,false)
    B:SetOption("targets",true);eq(Q.targetButton.shown,true)
    B:TogglePause();eq(Q.targetButton.shown,false);B:TogglePause();eq(Q.targetButton.shown,true)
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
    B.time(20);xp=950;event(nil,"PLAYER_XP_UPDATE","target");eq(T.last.xp,900)
    event(nil,"PLAYER_XP_UPDATE","player");eq(B.char.leveling.levels[20].xp,50)
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
    event(nil,"QUEST_TURNED_IN",1,100,0);event(nil,"QUEST_TURNED_IN",1,100,0)
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
