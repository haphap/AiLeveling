return function(test,eq,F,A,plan)
local names={"CreateFrame","UIParent","STANDARD_TEXT_FONT","GameFontHighlight","SlashCmdList","InCombatLockdown","GetTime",
    "geterrorhandler","C_Item","C_PlayerInfo","C_Container","GetQuestID","GetNumQuestChoices","GetQuestItemLink","GetQuestReward",
    "PlaySound","SOUNDKIT","NUM_CONTAINER_FRAMES","ContainerFrameCombinedBags","AiLeveling"}
local function widget()
    local w={scripts={},width=100,height=40,shown=true,attributeWrites=0}
    for _,key in ipairs({"SetBackdrop","SetBackdropBorderColor","SetJustifyH","SetJustifyV","SetMovable","EnableMouse","RegisterForDrag",
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
    local B={}
    assert(loadfile("Core.lua"))("AiLeveling",B)
    B.settings={};for k,v in pairs(B.defaults) do B.settings[k]=v end
    B.char={samples={},skipped={},deferredChains={},turnIns={}}
    B.state=F.State();B.state.bags[500]=2;B.state.quests[1]={objectives={}}
    local q=F.Quest(1);q.itemRules={[500]={kind="use",count=5,recovery="找 NPC 补领"}}
    B.Data=F.Data({[1]=q});B.Data.count=1;B.Content=B.Data.content
    B.action={kind="objective",questId=1,objectiveIndex=1}
    local nav={};assert(loadfile("Navigation.lua"))("AiLeveling",nav)
    B.Navigation={Current=function() return B.action end,RefreshPins=function() end,Target=nav.Navigation.Target}
    B.Observations={Reset=function() end,TalkOpened=function() end,TalkConfirmed=function() end}
    B.Dungeon={};B.Transport={InvalidateSample=function() end,InFlight=function() return false end}
    B.State={Refresh=function() B.refreshes=(B.refreshes or 0)+1;B.state.revision=B.state.revision+1 end}
    B.Gear=A.Gear;B.ready=true
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
test("全部设置有原生控件且有效关闭值跨归一化保留",function()
    local B=setup()
    for key in pairs(B.defaults) do assert(control(B,key)) end
    local row=control(B,"quantity");row.button.checked=false;row.button.scripts.OnClick()
    eq(B.settings.quantity,false);B:NormalizeSettings(B.settings);eq(B.settings.quantity,false)
    B.settings.fontScale=0/0;B.settings.density="bad";B.settings.detailPosition={"bad","CENTER",0,0}
    B:NormalizeSettings(B.settings);eq(B.settings.fontScale,1);eq(B.settings.density,"normal");eq(B.settings.detailPosition,nil)
    control(B,"gearPreference").button.scripts.OnClick();eq(B.settings.gearPreference,"xp");assert(B.refreshes>0)
    B.finish()
end)
test("字号与密度改变普通卡片并保留完整滚动说明",function()
    local B=setup();local U=B.UI
    U.body:SetText("完整说明");U:LayoutCard();local normal=U.frame.height
    B:SetOption("density","compact");assert(U.frame.height<normal);eq(U.body.value,"完整说明")
    B:SetOption("density","expanded");assert(U.frame.height>normal)
    local fontSize=U.title.fontSize;B:SetOption("fontScale",1.2);assert(U.title.fontSize>fontSize)
    U:Combat(true);eq(U.tracker.currentScroll.shown,false);local folded=U.frame.height
    U:Combat(false);assert(U.frame.height>folded);eq(U.tracker.currentScroll.shown,true)
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
test("多任务主卡片自动扩展并同时列出各任务摘要与当前建议",function()
    local B=setup();B.state.quests[1].title="任务甲"
    B.state.quests[1].objectives={{text="狼 1/3",numFulfilled=1,numRequired=3}}
    B.state.quests[2]={title="任务乙",ready=true,objectives={}}
    B.UI:LayoutCard();assert(B.UI.tracker.currentScroll.shown)
    local text=table.concat(B.UI:TaskLines(true),"\n")
    assert(text:find("任务甲 · 1/3",1,true));assert(text:find("[可交付] 任务乙",1,true))
    assert(text:find("建议先做：任务甲",1,true));assert(text:find("狼 1/3",1,true))
    B.finish()
end)
test("强调色距离单位与交通提示实际联动",function()
    local B=setup();local previous=B.UI.nav.color[1];B:SetOption("accent","gold");assert(B.UI.nav.color[1]~=previous)
    B:SetOption("distanceUnits","meters")
    B.UI:SetNavigation(100,nil,false);assert(B.UI.nav.value:find("91 米",1,true))
    local text=B.UI.ActionText({kind="transit",mode="flight",text="管理员条件"},B.settings);eq(text,"管理员条件")
    B.settings.transportHints=false;eq(B.UI.ActionText({kind="transit",mode="flight",text="管理员条件"},B.settings),"前往下一交通目的地")
    B.finish()
end)
test("关闭数量与缺失文字不取消物品需求和规划约束",function()
    local B=setup();local Q=B.QuestAssist
    B:SetOption("quantity",false);B:SetOption("missingChecks",false)
    eq(Q.buttons[1].count.value,"");eq(Q.detailsText:find("2/5",1,true),nil);eq(Q.detailsText:find("缺少至少",1,true),nil)
    eq(Q.wanted[1],500)
    local q=B.Data:GetQuest(1);q.actions[2].requiredItems={[500]=5}
    local result=plan(B.state,B.Data,{minutes=60,mode="fast",missingChecks=false})
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
        AddMinimapIconMap=function(_,owner,pin) mini=mini+1;pin:Show() end}
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
    B.finish()
end)
test("真实交付界面比较奖励且开关不触发自动领奖",function()
    local B=setup()
    B.frame.scripts.OnEvent(nil,"QUEST_COMPLETE")
    assert(B.QuestAssist.detailsText:find("第 2 项",1,true));assert(B.QuestAssist.detailsText:find("由玩家确认领取",1,true))
    B:SetOption("items",false);eq(B.QuestAssist.info.shown,true);eq(#B.QuestAssist.wanted,0)
    local reads=B.linkReads;B:SetOption("rewardAdvice",false)
    eq(B.linkReads,reads);eq(B.QuestAssist.detailsText:find("奖励建议",1,true),nil)
    B.frame.scripts.OnEvent(nil,"QUEST_FINISHED");eq(B.QuestAssist.rewardQuest,nil)
    B.finish()
end)
test("多项奖励效果详情保留在悬停，小框体显示简短入口且不改安全按钮",function()
    local B=setup();B.Content.sources={effect=true};B.Content.items={[100]={verified=true,source="effect",useSpell=42}}
    local Q=B.QuestAssist;Q:Update();local writes=Q.buttons[1].attributeWrites
    B.combat(true);B.frame.scripts.OnEvent(nil,"QUEST_COMPLETE")
    assert(Q.detailsText:find("第 1 项",1,true));assert(Q.detailsText:find("第 2 项",1,true))
    assert(Q.detailsText:find("主动效果 #42",1,true))
    assert(Q.info.text.value:find("悬停查看各项比较",1,true))
    eq(Q.info.text.value:find("第 2 项",1,true),nil);eq(Q.buttons[1].attributeWrites,writes)
    assert(Q.info.text.value:find("战斗结束后同步",1,true))
    B.combat(false);B.frame.scripts.OnEvent(nil,"QUEST_FINISHED")
    eq(Q.info.text.value:find("奖励需要权衡",1,true),nil)
    B.finish()
end)
test("奖励缓存未知时等待比较且非装备不循环请求属性",function()
    local B=setup();B.items[101].pending=true
    B.frame.scripts.OnEvent(nil,"QUEST_COMPLETE")
    assert(B.QuestAssist.detailsText:find("资料尚未齐全",1,true));eq(B.requests,1)
    B.QuestAssist:Update();eq(B.requests,1)
    B.items[101].pending=false;B.QuestAssist:Update();assert(B.QuestAssist.detailsText:find("第 2 项",1,true))
    B.choices={100,102};B.requests=0;B.QuestAssist:Update();B.QuestAssist:Update();eq(B.requests,0)
    B.finish()
end)
test("奖励武器关键数据缺失时不把已知护甲宣布为最佳",function()
    local B=setup();B.items[103]={name="武器",loc="INVTYPE_WEAPON",stats={ITEM_MOD_STRENGTH_SHORT=100}}
    B.choices={100,103};B.frame.scripts.OnEvent(nil,"QUEST_COMPLETE")
    assert(B.QuestAssist.detailsText:find("武器资料尚未齐全",1,true))
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
test("装备偏好关闭时保留经验排序和手动来源优先",function()
    local base={rate=100,priority=0};local gear={rate=97,priority=0,gear={upgrade={delta=10},chanceLow=1},gearSources={wanted=true}}
    eq(A.Gear.Prefer({base,gear},base,{}, {mode="relaxed",gearPreference="xp"}),base)
    eq(A.Gear.Prefer({base,gear},base,{gearTarget="wanted"},{mode="relaxed",gearPreference="xp"}),gear)
end)
test("本地绝对耗时存档检查单位数值并限制记录数",function()
    local B=setup()
    for i=1,130 do B.char.samples["taskwork:valid:"..i]={n=3,mean=10,m2=0,unit="seconds/unit"} end
    B.char.samples["taskwork:badunit"]={n=3,mean=10,m2=0,unit="ratio"}
    B.char.samples["taskwork:badtime"]={n=3,mean=0.5,m2=0,unit="seconds/unit"}
    B.char.samples["tasktalk:v1:turnin:fast"]={n=3,mean=5,m2=0,unit="seconds"}
    B.char.samples["tasktalk:v1:turnin:invalid"]={n=3,mean=5,m2=0,unit="seconds"}
    B:NormalizeCharacter(B.char)
    local count=0;for key in pairs(B.char.samples) do if key:sub(1,9)=="taskwork:" then count=count+1 end end
    eq(count,128);eq(B.char.samples["taskwork:badunit"],nil);eq(B.char.samples["taskwork:badtime"],nil)
    eq(B.char.samples["tasktalk:v1:turnin:fast"].mean,5);eq(B.char.samples["tasktalk:v1:turnin:invalid"],nil)
    B.finish()
end)
test("接交事件保留实际任务事实但不采集耗时且玩家速度触发重算",function()
    local B=setup();local calls={}
    B.Observations.TalkOpened=function(_,kind,id) calls[#calls+1]={kind,id,"opened"} end
    B.Observations.TalkConfirmed=function(_,kind,id) calls[#calls+1]={kind,id,"confirmed"} end
    B.State.TurnedIn=function(_,id) B.turnedIn=id end
    local event=B.frame.scripts.OnEvent
    event(nil,"QUEST_DETAIL");event(nil,"QUEST_ACCEPTED",1)
    event(nil,"QUEST_COMPLETE");event(nil,"QUEST_TURNED_IN",1,100,0)
    eq(#calls,0);eq(B.turnedIn,1)
    B.refreshAt=nil;event(nil,"UNIT_SPEED","target");eq(B.refreshAt,nil)
    event(nil,"UNIT_SPEED","player");assert(B.refreshAt)
    B.finish()
end)
test("取消自动换绑的当前任务组偏好可持久保存且拒绝损坏大值",function()
    local B=setup()
    B.char.declinedBinding="42:0,43:1";B:NormalizeCharacter(B.char);eq(B.char.declinedBinding,"42:0,43:1")
    B.char.declinedBinding={};B:NormalizeCharacter(B.char);eq(B.char.declinedBinding,nil)
    B.char.declinedBinding=string.rep("x",4097);B:NormalizeCharacter(B.char);eq(B.char.declinedBinding,nil)
    B.finish()
end)
dofile("tests/tracker.lua")(test,eq,setup)
end
