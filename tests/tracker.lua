return function(test,eq,setup)
local function ready(fullUI)
    local B=setup(fullUI)
    B.Message=function(_,message) B.lastMessage=message end
    B.indexReady=true
    B.state.quests={
        [1]={title="当前任务",objectives={{text="狗头人 3/10",numFulfilled=3,numRequired=10}}},
        [2]={title="后续交付",ready=true,objectives={}},
        [3]={title="后续目标",objectives={{text="物品 2/4",numFulfilled=2,numRequired=4}}}}
    B.state.position={map=1,x=0.5,y=0.5,node="start"}
    B.action={questId=1,title="当前任务",kind="objective",position={map=1,x=0.6,y=0.5}}
    local choices={}
    for id=1,3 do choices[id]={id="task:"..id,questId=id,kind="task",title="任务 "..id,
        actions={{questId=id,kind=id==2 and "turnin" or "objective"}}} end
    B.plan={revision=B.state.revision,taskChoices=choices,taskOrder=choices,unverified=true,
        origin={map=1,node="start"}}
    assert(loadfile("Planner/Selection.lua"))("AiLeveling",B)
    B.UI:RenderTracker()
    return B
end
test("同NPC交付建议保留真实进度并按行程显示后续任务",function()
    local B=ready();B.UI.tracker.otherHeader:Click();assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    for _,id in ipairs({1,3}) do
        B.plan.taskChoices[id].stages={{kind="turnin",position={map=1,x=0,y=0,entityKind="npc",entityId=900,entityName="治安官"}}}
    end
    B.state.quests[3].ready=true;B.UI:RenderTracker()
    local T=B.UI.tracker
    eq(#T.model.rows,3);eq(T.model.rows[1].questId,1);eq(T.model.rows[2].questId,2);eq(T.model.rows[3].questId,3)
    eq(T.model.rows[1].groupTitle,"治安官 · 已完成 1/2")
    eq(T.model.rows[3].groupTitle,nil);eq(T.rows[3].status,"可交付")
    eq(T.rows[3].progress.value,"同组还差 1 项，做完一起交")
    eq(T.model.deliverySummary,"同组还差 1 项，做完一起交")
    eq(T.queuePanel.width,T.card.width)
    T.rows[3].scripts.OnClick(nil,"RightButton");B.menu["优先做此任务"].callback();eq(B.char.locked,3)
    B.state.quests[1].ready=true;B.UI:RenderTracker()
    eq(T.model.rows[1].groupTitle,"治安官 · 已完成 2/2");eq(T.rows[1].progress.value,"一起交给治安官（2项）")
    B.state.quests[3]=nil;B.UI:RenderTracker();eq(T.model.rows[1].groupTitle,nil)
    B.finish()
end)
test("原生可交付但共用物品不足时显示补齐提示和整批数量",function()
    local B=ready();assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    B.state.bags={[2592]=60};B.state.quests[1].ready=true;B.state.quests[3].ready=true
    for _,id in ipairs({1,3}) do
        B.plan.taskChoices[id].stages={{kind="turnin",recipient={entityKind="npc",entityId=99,entityName="收件人"},
            itemRequirements={{targetId=2592,need=60}}}}
    end
    B.plan.taskChoices[1].itemShortage=true
    B.state.quests[1].objectives={{text="毛料",type="item",numFulfilled=60,numRequired=60,finished=true}}
    B.action.targetId=2592;B.action.itemGain=60;B.action.objectiveIndex=1;B.action.text="还需收集60块毛料"
    B.UI:RenderTracker()
    local model=B.UI.tracker.model
    eq(#model.objectives,1);eq(model.objectives[1].have,60);eq(model.objectives[1].need,120)
    eq(model.objectives[1].text,"毛料");eq(model.objectives[1].done,false)
    B.plan.itemStock={[2592]=60};B.state.bags[2592]=65
    B.UI:RenderTracker();eq(B.UI.tracker.model.objectives[1].need,120)
    B.plan.itemStock=nil;B.state.bags[2592]=60
    assert(model.hint:find("1/2",1,true));eq(model.rows[1].progress,"共用物品不足 · 先补齐再一起交付")
    B.action.itemGain=1;B.UI:RenderTracker();eq(B.UI.tracker.model.objectives[#model.objectives].need,120)
    eq(B.state.quests[1].ready,true);B.finish()
end)
test("受持有上限限制时仍按NPC归组并提示先交付已备齐任务",function()
    local B=ready();assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    assert(loadfile("Data/ItemLimits.lua"))("AiLeveling",B)
    B.state.clientVersion,B.state.clientBuild,B.state.interface="1.60.1","70862",16001
    for _,id in ipairs({1,3}) do
        B.state.quests[id].ready=true
        B.plan.taskChoices[id].stages={{kind="turnin",recipient={entityKind="npc",entityId=99,entityName="收件人"},
            itemRequirements={{targetId=18250,need=1}}}}
    end
    B.plan.taskChoices[3].itemShortage=true;B.action.kind="turnin"
    B.UI:RenderTracker();local model=B.UI.tracker.model
    assert(model.hint:find("先交付已备齐任务",1,true))
    eq(model.rows[1].progress,"已备齐 · 可先交付")
    eq(model.nextId,3) -- The next quest is shown once below the current step.
    eq(model.rows[1].groupTitle,"收件人 · 已完成 1/2")
    B.action.kind="objective";B.action.targetId=18250;B.action.itemGain=1;B.state.bags[18250]=0
    B.UI:RenderTracker();model=B.UI.tracker.model;eq(model.objectives[#model.objectives].need,1)
    B.finish()
end)
test("步骤界面突出当前任务真实进度且后续列表去重可点击",function()
    local B=ready();B.UI.tracker.otherHeader:Click();local T=B.UI.tracker
    B.plan.taskChoices[1].remainingXP=1250;B.plan.taskChoices[1].timing={seconds=135}
    B.plan.taskChoices[2].remainingXP=0;B.plan.taskChoices[2].timing={seconds=0}
    B.plan.taskChoices[3].remainingXP=900;B.plan.taskChoices[3].timing={seconds=3665}
    assert(loadfile("Planner/Flights.lua"))("AiLeveling",B)
    local action=B.action
    action.text="消灭狗头人，3/10";action.objectiveIndex=1;action.position.entityName="狗头人营地"
    local route={legs={{kind="walk",from=B.state.position,to=action.position,seconds=100}}}
    local actions=B.Flights.Actions(route,action,B.Navigation)
    eq(#actions,1);eq(actions[1],action)
    local savedMap=C_Map;C_Map={GetMapInfo=function() return {name="艾尔文森林"} end}
    B.action=actions[1];B.UI:RenderTracker()
    C_Map=savedMap
    assert(not B.UI.body.value:find(action.text,1,true));assert(not B.UI.body.value:find("60.0, 50.0",1,true))
    assert(T.objectives[1].text.value:find("狗头人",1,true));assert(not T.objectives[1].text.value:find("3/10",1,true))
    eq(B.UI.title.value,"当前任务");assert(T.location.value:find("狗头人营地",1,true));eq(T.location.shown,true);eq(B.UI.body.value,"");eq(T.objectives[1].count.value,"3/10");eq(T.objectives[1].ratio,0.3)
    eq(#T.model.rows,2);eq(T.rows[1].title.value,"后续交付");eq(T.rows[1].status,"可交付")
    eq(T.queuePanel.width,T.card.width)
    eq(T.rows[1].title.shown,true);eq(T.rows[2].objectiveFrame.shown,true);eq(T.rows[2].progress.shown,false)
    eq(T.objectives[1].check.shown,false);eq(T.progressRatio,0.3);eq(T.progress.shown,true)
    assert(T.rows[1].title.color[2]>T.rows[1].title.color[1])
    eq(T.rows[2].title.color[2],B.UI.colors.white[2])
    assert(T.queueScroll.width+16<=T.queuePanel.width);assert(T.card.width<=300)
    assert(T.location.width+2*B.UI.metrics.hit<=T.card.width);eq(T.career.width,T.currentChild.width)
    local goal=T.objectives[1]
    eq(goal.count.width,math.ceil(goal.count:GetStringWidth())+6)
    eq(goal.text.width,goal.width-goal.count.width-20)
    assert(T.footer.value:find("经验 1250",1,true));assert(T.footer.value:find("路程 2分15秒",1,true))
    assert(T.rows[1].metrics:find("经验 0",1,true));assert(T.rows[1].metrics:find("路程 0秒",1,true))
    assert(T.rows[2].metrics:find("路程 1小时01分",1,true))
    assert(T.rows[1].title.fontSize>=15);eq(T.rows[1].progress.fontSize,B.UI.fontSizes.caption)
    assert(T.rows[1].progress.color[2]>=0.75);eq(T.queuePanel.surface,nil);eq(T.card.surface,nil)
    eq(T.rows[1].title.fontFlags,"OUTLINE")
    eq(T.rows[2].objectives[1].text.value,"物品");eq(T.rows[2].objectives[1].count.value,"2/4");eq(T.rows[1].enabled,true)
    B.state.quests[3].objectives[1].text="收集物品";B.state.quests[3].objectives[1].type="item";B.UI:RenderTracker()
    eq(T.rows[2].objectives[1].text.value,"收集物品");eq(T.rows[2].objectives[1].count.value,"2/4")
    eq(T.rows[2].objectives[1].check.shown,false);eq(T.rows[2].objectives[1].text.color[2],B.UI.colors.white[2])
    for _,id in ipairs({1,3}) do
        B.plan.taskChoices[id].stages={{kind="objective",objectiveIndex=1,purchase={npcId=8,name="任务商人",map=1}}}
    end
    B.state.quests[1].objectives[1].type="item";B.action.itemGain=4;B.action.targetId=2455
    B.state.quests[1].objectives[2]={text="初级坚韧药剂",type="item",numRequired=2,numFulfilled=0}
    B.UI:RenderTracker()
    eq(#T.model.objectives,2);eq(T.objectives[3],nil);eq(T.objectives[1].count.value,"0/4")
    assert(T.objectives[1].purchaseText.value:find("可购买 · 任务商人",1,true))
    local purchaseRow=T.thenButton.questId==3 and T.thenButton or T.rows[2]
    assert(purchaseRow.objectives[1].purchaseText.value:find("可购买",1,true))
    assert(purchaseRow.objectives[1].purchase:find("任务商人",1,true))
    B.state.quests[3].objectives[1].numFulfilled=4;B.UI:RenderTracker()
    eq(purchaseRow.objectives[1].purchase,nil);eq(purchaseRow.objectives[1].text.value,"收集物品")
    eq(purchaseRow.objectives[1].purchaseText.shown,false)
    B.state.quests[3].objectives[1].numFulfilled=2
    B.action.itemGain=nil;B.action.targetId=nil;B.state.quests[1].objectives[2]=nil
    B.plan.taskChoices[1].stages=nil;B.plan.taskChoices[3].stages=nil;B.UI:RenderTracker()
    local shown,inserted,opened,modified,focused=nil,nil,nil,false,true
    C_QuestLog.GetLogIndexForQuestID=function(id) return id<=3 and id+10 end
    QuestMapFrame_OpenToQuestDetails=function(id) shown=id end
    GetQuestLink=function(id) return "|Hquest:"..id..":20|h[任务]|h" end
    IsModifiedClick=function() return modified end
    ChatFrameUtil={InsertLink=function(link) inserted=link;return focused end,OpenChat=function(link) opened=link end}
    eq(T.rows[1].clicks[2],"RightButtonUp")
    T.rows[1].scripts.OnClick(nil,"LeftButton");eq(shown,2);eq(B.char.locked,nil)
    T.questTitle.scripts.OnClick(nil,"LeftButton");eq(shown,1);eq(B.char.locked,nil)
    B.UI:SetTrackerNavigation(nil,nil,nil,B.action)
    shown=nil;B.UI.navFrame.scripts.OnClick(B.UI.navFrame,"LeftButton");eq(shown,1)
    local nav=B.UI.navFrame
    nav.scripts.OnDragStart(nav);nav.scripts.OnDragStop(nav)
    shown=nil;nav.scripts.OnClick(nav,"LeftButton");eq(shown,nil)
    nav.scripts.OnMouseDown(nav);nav.scripts.OnClick(nav,"LeftButton");eq(shown,1)
    modified=true;T.rows[1].scripts.OnClick(nil,"LeftButton")
    eq(inserted,GetQuestLink(2));eq(opened,nil);eq(B.char.locked,nil)
    focused=false;T.questTitle.scripts.OnClick(nil,"LeftButton");eq(opened,GetQuestLink(1))
    GetQuestLink=function() end;opened=nil;T.rows[1].scripts.OnClick(nil,"LeftButton");eq(opened,nil);eq(B.char.locked,nil)
    modified=false
    T.rows[1].scripts.OnClick(nil,"RightButton");assert(B.menu["优先做此任务"].enabled)
    B.menu["优先做此任务"].callback();eq(B.char.locked,2)
    B.state.revision=B.state.revision+1;T.rows[1].scripts.OnClick(nil,"RightButton")
    eq(B.menu["优先做此任务"].enabled,false);B.menu["查看任务详情"].callback();eq(shown,2)
    eq(B.char.locked,2);eq(B.state.completed[2],nil)
    T.questTitle.scripts.OnClick(nil,"RightButton");B.menu["恢复自动安排"].callback();eq(B.char.locked,nil)
    T.rows[2].scripts.OnClick(nil,"RightButton")
    local defer=B.menu["暂时不做"].callback
    T.rows[2].questId=1;defer();eq(B.char.skipped[3],B.state.level);eq(B.char.skipped[1],nil)
    eq(T.skip:IsShown(),true);T.skip:Click();eq(B.char.skipped[1],B.state.level);assert(B.state.quests[1])
    nav.scripts.OnClick(nav,"RightButton");B.menu["忽略此任务"].callback();eq(B.char.skipped[1],"ignored")
    nav.scripts.OnClick(nav,"RightButton");B.menu["恢复推荐"].callback()
    eq(B.char.skipped[1],nil);eq(B.char.skipped[3],B.state.level)
    eq(T.tools,nil)
    B.finish()
end)
test("未列入行程的任务链接打开对应详情并保留当前路线",function()
    local B=ready(true);local browser=B.UI.Browser
    assert(loadfile("Planner/Eligibility.lua"))("AiLeveling",B)
    B.state.quests[1]=nil;B.plan.taskChoices={};B.plan.taskOrder={}
    B.Data.db={Quest={Get=function(id,key)
        if id==1 and key=="objectivesText" then return {"把包裹送到旅店。"} end
    end}}
    C_QuestLog.GetLogIndexForQuestID=function() return 0 end
    browser.infoChild.scripts.OnHyperlinkClick(browser.infoChild,"quest:1:0","测试任务","LeftButton")
    eq(browser.selected.questId,1);assert(browser.detail.value:find("把包裹送到旅店。",1,true))
    eq(B.UI.selectedTab,1);eq(B.Navigation.manual,nil);eq(B.char.locked,nil);eq(#B.plan.taskChoices,0)
    eq(browser.buttons[2].text.value,"暂时不做");browser.buttons[2]:Click()
    B.UI.Plan.key=nil
    local deferred
    for _,row in ipairs(browser:TaskRows(1)) do if row.questId==1 then deferred=row end end
    assert(deferred and deferred.sub:find("已暂缓",1,true));eq(deferred.allowed,false)
    browser.buttons[5]:Click();assert(browser.selected.sub:find("已忽略",1,true));eq(browser.buttons[5]:IsShown(),false)
    eq(browser.buttons[2].text.value,"恢复推荐");browser.buttons[2]:Click();eq(B.char.skipped[1],nil)
    B.UI.Plan.key="q:1"
    B.state.completed[1]=true;B.state.revision=B.state.revision+1;B.UI:RefreshDetails()
    eq(browser.selected.questId,1);assert(browser.selected.sub:find("已交付",1,true));eq(browser.selected.allowed,false)
    B.finish()
end)
test("后续任务按真实日志区分已接和未接且接取后更新进度",function()
    local B=ready(true);B.UI.tracker.otherHeader:Click();local T=B.UI.tracker
    B.plan.taskChoices[#B.plan.taskChoices+1]={id="task:4",questId=4,kind="task",title="未接任务",
        actions={{questId=4,kind="accept",title="未接任务"}}}
    B.UI:RenderTracker()
    eq(T.rows[2].status,"已接取");eq(T.rows[3].status,"未接取")
    eq(T.rows[3].progress.value,"先接取，再推进任务目标")
    eq(T.rows[3].along,false);eq(T.rows[3].parent,T.queueChild);eq(T.alongLabel.shown,false)
    eq(T.queueLabel.value,"后续行程")
    eq(T.model.acceptedCount,2);eq(T.model.unacceptedCount,1)
    T.rows[3].scripts.OnClick(nil,"LeftButton")
    eq(B.UI.Plan.preview.questId,4);eq(B.UI.details.shown,true);eq(B.char.locked,nil)
    local row
    for _,card in ipairs(B.UI.Browser.rows) do if card.questId==4 then row=card end end
    assert(B.UI.Browser.title.value:find("|Hquest:4:0|h",1,true))
    local browser=B.UI.Browser
    local build,builds=browser.TaskRows,0
    browser.TaskRows=function(...) builds=builds+1;return build(...) end
    for _,other in ipairs(browser.rows) do
        if other.questId and other.questId~=4 then
            other.scripts.OnClick(other,"LeftButton");eq(B.UI.Plan.preview.questId,other.questId);break
        end
    end
    row.scripts.OnClick(row,"LeftButton");eq(B.UI.Plan.preview.questId,4)
    browser.search:SetText("未接");browser.search.scripts.OnTextChanged(browser.search)
    eq(builds,0);eq(browser.selected.questId,4)
    browser.search:SetText("");browser.search.scripts.OnTextChanged(browser.search);eq(builds,0)
    B.state.revision=B.state.revision+1
    browser:Refresh(1,true);eq(builds,1)
    B.state.revision=B.plan.revision;browser:Refresh(1)
    browser.TaskRows=build
    eq(B.UI.Plan.preview.questId,4);eq(B.char.locked,nil)
    local tooltip={}
    GameTooltip={SetOwner=function() end,SetText=function(_,v) tooltip[#tooltip+1]=v end,
        AddLine=function(_,v) tooltip[#tooltip+1]=v end,Show=function() end,Hide=function() end}
    row.scripts.OnEnter(row);assert(table.concat(tooltip,"\n"):find("未接任务",1,true))
    row.scripts.OnLeave(row)
    row.scripts.OnClick(row,"RightButton")
    assert(B.menu["优先做此任务"].enabled);B.menu["优先做此任务"].callback();eq(B.char.locked,4)
    B.Selection:Automatic();eq(B.char.locked,nil)
    local current={map=1,title="当前区域",choices={B.plan.taskChoices[1]},current=true}
    local region={map=2,title="下一站",choices={B.plan.taskChoices[4]},pickups={B.plan.taskChoices[4]},
        handins={B.plan.taskChoices[4]},revisit={},xp=1000,unknownXP=0,minLevel=20,maxLevel=20,first=B.plan.taskChoices[4]}
    local revisit={choice=B.plan.taskChoices[3],level=22}
    current.revisit={revisit}
    B.plan.regions={region}
    B.plan.regionPlan={current=current,destination=region,handins={B.plan.taskChoices[1]},revisit=current.revisit}
    B.UI:RenderTracker();local rows=T.region.rows
    assert(rows[1].label.value:find("交",1,true));eq(rows[1].value.value,B.plan.taskChoices[1].title)
    eq(rows[2].value.value,"下一站 · 接 未接任务");assert(rows[3].value.value:find("22级",1,true))
    eq(T.region.shown,true)
    T.region.scripts.OnClick();eq(browser.selection[10],"map:2")
    assert(browser.detail.value:find("出发前交付",1,true))
    assert(browser.detail.value:find("到达后接取",1,true))
    assert(browser.detail.value:find("22级回访",1,true))
    assert(browser.detail.value:find("|Hquest:4:0|h",1,true))
    current.revisit[2]={choice=B.plan.taskChoices[4],level=24}
    B.plan.regionPlan.destination=nil;B.UI:RenderTracker()
    eq(rows[3].value.value,"22级起 · 2项任务");eq(rows[2].value.shown,false)
    B.plan.regionPlan=nil;B.UI:RenderTracker();eq(T.region.shown,false)
    B.UI:SelectTab(5);eq(B.UI.Browser.frame.shown,false)
    B.UI:SelectTab(1);eq(B.UI.Browser.frame.shown,true)
    B.UI:ShowText("导出内容");eq(B.UI.Browser.frame.shown,false)
    B.UI:SelectTab(1)
    B.state.skipped[4]=true;B.UI:RenderTracker();eq(T.rows[3].shown,false)
    eq(T.alongLabel.shown,false);eq(#T.model.rows,2)
    B.UI.Browser:Refresh(1);eq(B.UI.Plan.preview.questId,4);eq(B.char.locked,nil);eq(B.state.skipped[4],true)
    B.state.skipped[4]=nil
    eq(T.model.unacceptedCount,1)
    local starter=B.plan.taskChoices[4].actions[1]
    starter.position={map=1,x=0.5,y=0.5,startItemId=500};starter.text="使用「任务信件」接取任务。"
    B.UI:RenderTracker();eq(T.rows[3].progress.value,starter.text)
    local model=B.UI.TrackerModel(B.state,B.plan,starter,false);eq(model.destination,nil);eq(model.instruction,starter.text)
    B.plan.taskOrder={B.plan.taskChoices[1],B.plan.taskChoices[4],B.plan.taskChoices[2],B.plan.taskChoices[3]}
    B.UI:RenderTracker();eq(T.model.rows[1].questId,4);eq(T.rows[1].status,"未接取")
    B.plan.taskOrder=nil
    local distance=B.Navigation.Distance
    B.Navigation.Distance=function(_,a,b) if a and b and a.map==b.map then return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)*4000 end end
    starter.position={map=1,x=0.55,y=0.5,entityKind="object",entityName="焦焚残骸"};starter.text=nil
    B.state.locked=1;B.UI:RenderTracker()
    eq(T.model.rows[1].questId,4);assert(T.rows[1].progress.value:find("顺路接取 · 焦焚残骸",1,true))
    eq(T.rows[1].parent,T.alongChild);eq(T.alongLabel.shown,true)
    eq(T.alongLabel.value,"顺路可接 · 1")
    starter.position.y=0.58;B.UI:RenderTracker();eq(T.alongLabel.shown,false)
    starter.position.y=0.5;B.UI:RenderTracker();eq(T.alongLabel.shown,true)
    eq(T.model.questId,1);eq(B.state.locked,1)
    local originalAction,originalPosition,originalQuest=B.action,B.state.position,B.state.quests[1]
    B.state.quests[1]=nil
    B.action={questId=1,kind="accept",position={map=1,x=0.55,y=0.5}}
    B.state.position=B.action.position;starter.position.x=0.576
    B.UI:RenderTracker();eq(T.model.rows[1].questId,4);eq(T.rows[1].along,true)
    local candidate=B.plan.taskChoices[4]
    candidate.revisitLevel=B.state.level+1;candidate.pickupAction=starter
    B.UI:RenderTracker();assert(T.rows[1].progress.value:find("级再做",1,true))
    candidate.acceptBlocked="日志已满";B.UI:RenderTracker();eq(T.alongLabel.shown,false)
    candidate.acceptBlocked=nil;candidate.revisitLevel=nil;candidate.pickupAction=nil
    B.action,B.state.position=originalAction,originalPosition;B.state.quests[1]=originalQuest;starter.position.x=0.55
    -- An unaccepted quest's objectives have not been displayed above yet.
    B.action=starter;B.state.locked=nil;candidate.stages={starter,
        {kind="objective",questId=4,expected=true,text="迪克斯特·瓦德的手掌",areaId=717,targetKind="item",need=1},
        {kind="turnin",questId=4,expected=true,position=starter.position}}
    B.plan.taskOrder={candidate}
    local taskInstance=B.Dungeon.TaskInstance
    B.Dungeon.TaskInstance=function(_,_,_,area) if area==717 then return {title="暴风城监狱"} end end
    B.UI:RenderTracker();eq(T.model.nextStep.kind,"objective");eq(T.thenText.value,"接取后")
    eq(T.thenButton.title.value,"迪克斯特·瓦德的手掌");eq(T.thenButton.progress.value,"副本 · |cff"..B.UI.hex.place.."暴风城监狱|r")
    assert(B.UI.body.value:find("先接备用",1,true))
    -- A selected dungeon keeps later pickups visible instead of jumping straight to this quest's objective.
    local choices=B.plan.taskChoices
    local outside={kind="accept",questId=5,title="另一城的副本任务",position={map=3,x=0.5,y=0.5,entityName="接取NPC"}}
    local inside={kind="accept",questId=6,title="副本内的任务",areaId=717}
    B.plan.taskChoices={candidate,{questId=5,title=outside.title,actions={outside}},
        {questId=6,title=inside.title,actions={inside}}}
    B.plan.taskBatch={title="暴风城监狱",remaining=3,journey={before={{action=starter},{action=outside}},
        inside={{action=inside}},after={}}}
    B.UI:RenderTracker();eq(T.model.nextId,5);eq(T.model.nextStep.kind,"accept")
    assert(T.thenButton.progress.value:find("入本前接取",1,true))
    local oldMap,oldTarget,oldNavigate=C_Map,B.Navigation.Target,B.Navigation.Navigate
    local opened,picked
    C_Map={GetMapInfo=function(id) if id==1435 then return {name="悲伤沼泽"} end end,
        OpenWorldMap=function(id) opened=id end}
    B.Navigation.Target=function(step) return step and step.position end
    B.Navigation.Navigate=function(_,step) picked=step;return true end
    outside.position={map=1435,x=0.2222,y=0.5023,entityName="塔特尔神父"}
    B.UI:RenderTracker()
    assert(T.thenButton.progress.value:find("悲伤沼泽 22.2，50.2",1,true))
    assert(T.thenButton.progress.value:find("入本前接取 · 塔特尔神父",1,true))
    T.thenButton.scripts.OnClick(nil,"RightButton");B.menu["在地图上查看位置"].callback();eq(opened,1435)
    T.thenButton.scripts.OnClick(nil,"LeftButton");eq(B.UI.Browser.selected.questId,5);eq(picked,nil)
    T.thenButton.scripts.OnClick(nil,"RightButton");B.menu["导航到此任务"].callback();eq(picked,outside)
    C_Map,B.Navigation.Target,B.Navigation.Navigate=oldMap,oldTarget,oldNavigate
    local insideRow;for _,row in ipairs(T.rows) do if row.shown and row.questId==6 then insideRow=row end end
    assert(insideRow);assert(insideRow.progress.value:find("副本内接取",1,true))
    B.plan.taskBatch=nil;B.plan.taskChoices=choices
    B.Dungeon.TaskInstance=taskInstance;B.action=originalAction;B.state.locked=1;candidate.stages=nil;B.plan.taskOrder=nil;B.UI:RenderTracker()
    -- Flight unlocks use the same optional list and existing service navigation.
    local flight={kind="unlockFlight",taxiId=12,title="夜色镇",position={map=1,x=0.525,y=0.5}}
    B.plan.flightUnlocks={flight};B.state.unlocked={["taxi:12"]=false};B.UI:RenderTracker()
    eq(T.rows[1].serviceStop,flight);eq(T.rows[1].parent,T.alongChild)
    assert(T.rows[1].title.value:find("开通飞行点",1,true))
    local units=B.settings.distanceUnits;B.settings.distanceUnits="yards"
    B.state.position={map=1,x=0.505,y=0.5};B.UI:UpdateTrackerDynamic()
    eq(T.rows[1].progress.value,"与飞行管理员交谈 · 80 码")
    B.state.position=originalPosition;B.settings.distanceUnits=units;B.UI:RenderTracker()
    local services=B.Services
    local picked
    B.Services={Choices=function() return {flight} end,Pick=function(_,stop) picked=stop;return true end}
    T.rows[1].scripts.OnClick(nil,"LeftButton");eq(picked,flight);eq(B.action,originalAction)
    T.rows[1].scripts.OnClick(nil,"RightButton");B.menu["暂不提示此飞行点"].callback()
    eq(T.rows[1].serviceStop,nil);T.nearby.ignored={}
    B.state.unlocked["taxi:12"]=true;B.UI:RenderTracker();eq(T.rows[1].serviceStop,nil)
    B.Services=services;B.plan.flightUnlocks=nil;B.state.unlocked=nil
    local originalNavigation=B.Navigation
    assert(loadfile("Navigation.lua"))("AiLeveling",B)
    B.Transport.FlightGate=function() end
    B.Navigation.actions={B.action};B.Navigation.plan=B.plan;B.Navigation.Distance=originalNavigation.Distance
    B.char.locked=1
    local modified=IsModifiedClick
    IsModifiedClick=function() return true end
    T.rows[1].scripts.OnClick(nil,"LeftButton");eq(B.Navigation.manual,nil)
    IsModifiedClick=modified
    T.rows[1].scripts.OnClick(nil,"LeftButton")
    eq(B.UI.Browser.selected.questId,4);eq(B.Navigation.manual,nil)
    T.rows[1].scripts.OnClick(nil,"RightButton");B.menu["导航到此任务"].callback()
    eq(B.Navigation:Current(),starter);eq(B.Navigation:MapPoints()[1].position.entityName,"焦焚残骸")
    B.UI:RenderTracker();eq(T.model.questId,4);eq(T.model.destination,"焦焚残骸")
    eq(B.char.locked,1);eq(B.Navigation.actions[1],B.action)
    T.questTitle.scripts.OnClick(nil,"RightButton");assert(B.menu["返回任务"])
    B.state.quests[4]={title="已接的顺路任务",objectives={}}
    eq(B.Navigation:Current(),B.action);eq(B.Navigation.manual,nil);eq(B.char.locked,1)
    eq(B.Navigation:Pickup(starter),false)
    B.state.quests[4]=nil
    local objectPoint=starter.position
    starter.position={map=1,x=0.5,y=0.5,startItemId=500};starter.text="使用「任务信件」接取任务。"
    local getQuest=B.Data.GetQuest
    B.Data.GetQuest=function(self,id) if id==4 then return {id=4,startedBy={{},{},{500}}} end;return getQuest(self,id) end
    B.UI:RenderTracker();T.rows[1].scripts.OnClick(nil,"RightButton");B.menu["导航到此任务"].callback();B.UI:RenderTracker()
    eq(B.Navigation:Current(),starter);eq(#B.Navigation:MapPoints(),0)
    eq(T.model.instruction,starter.text);eq(B.QuestAssist.wanted[1],500);eq(B.QuestAssist.requirements[1].kind,"start")
    B.state.quests[4]={objectives={}};eq(B.Navigation:Current(),B.action)
    eq(B.Navigation.manual,nil);eq(B.QuestAssist.requirements[1].kind,"use")
    B.state.quests[4]=nil;B.Data.GetQuest=getQuest;B.char.locked=nil
    starter.position=objectPoint;starter.text=nil
    -- Nearby work and ready hand-ins share the optional section without changing the main action.
    starter.position.x=0.525;starter.kind="objective";starter.objectiveIndex=1
    B.state.quests[4]={objectives={{type="item",text="一捆木材：3/10",numRequired=10,numFulfilled=3}}}
    B.UI:RenderTracker();eq(T.model.rows[1].along,true);eq(T.rows[1].objectives[1].count.value,"3/10");eq(T.rows[1].progress.shown,false)
    local notice=T.nearby
    eq(notice.shown,true);eq(notice.body.value,"从 焦焚残骸 收集 一捆木材，还差 7  ·  100 码")
    notice.scripts.OnClick(nil,"RightButton");B.UI:UpdateNearby();eq(notice.shown,false);eq(B.state.skipped[4],nil)
    local position,mainPoint=B.state.position,B.action.position
    B.state.position={map=1,x=0.56,y=0.5};starter.position.x=0.58;B.action.position={map=1,x=0.65,y=0.5}
    B.UI:UpdateNearby();eq(notice.shown,true)
    notice.scripts.OnClick(nil,"RightButton")
    B.state.position.x=0.64;starter.position.x=0.66;B.action.position.x=0.75
    B.UI:UpdateNearby();eq(notice.shown,false)
    B.state.position.map=2;starter.position.map=2;B.action.position.map=2
    B.UI:UpdateNearby();eq(notice.shown,true)
    notice.scripts.OnClick(nil,"LeftButton");eq(B.Navigation:Current(),starter)
    local goal=B.state.quests[4].objectives[1]
    goal.numFulfilled,goal.text=8,"一捆木材：8/10"
    B.UI:RenderTracker();eq(T.model.questId,4);eq(T.objectives[1].count.value,"8/10")
    B.UI:SetTrackerNavigation(nil,nil,nil,B.Navigation:Current());eq(T.navDetail.value,goal.text)
    eq(B.char.locked,nil);eq(B.state.locked,1);eq(B.action.questId,1);eq(notice.shown,false)
    B.Navigation:ClearManual(false)
    B.state.position=position;B.action.position=mainPoint;starter.position={map=1,x=0.525,y=0.5}
    B.UI:UpdateNearby();eq(notice.shown,true);assert(notice.body.value:find("还差 2",1,true))
    B.char.paused=true;B.UI:UpdateNearby();eq(notice.shown,false);B.char.paused=false
    B.UI:UpdateNearby();notice.scripts.OnClick(nil,"LeftButton");eq(B.Navigation:Current(),starter)
    goal.numFulfilled,goal.text,goal.finished=10,"一捆木材：10/10",true
    eq(B.Navigation:Current(),B.action);eq(B.Navigation.manual,nil);B.Navigation=originalNavigation
    B.UI:RenderTracker();eq(T.alongLabel.shown,false);eq(notice.shown,false)
    starter.kind="turnin";starter.objectiveIndex=nil;B.state.quests[4].ready=true
    B.UI:RenderTracker();eq(T.rows[1].status,"可交付");eq(T.rows[1].along,true);eq(B.action.questId,1)
    B.state.quests[4]=nil;starter.kind="accept"
    B.state.locked=nil;B.Navigation.Distance=distance;starter.position=nil;B.plan.taskOrder=B.plan.taskChoices
    B.state.quests[4]={title="真实接取的任务",objectives={{text="收集 1/5",numFulfilled=1,numRequired=5}}}
    B.UI:RenderTracker()
    eq(T.rows[3].status,"已接取");eq(T.rows[3].objectives[1].count.value,"1/5");eq(T.rows[3].objectiveFrame.shown,true)
    eq(T.model.acceptedCount,3);eq(T.model.unacceptedCount,0)
    eq(T.rows[3].along,false);eq(T.rows[3].parent,T.otherChild);eq(T.alongScroll.shown,false)
    B.state.quests[4].ready=true;B.UI:RenderTracker();eq(T.rows[3].status,"可交付")
    local suggestion={id="reference:3065",dungeonId="reference:3065",kind="dungeon",reference=true,requiresAcceptance=true,
        title="领主大厅",rewards={count=5,prepare=1},remainingXP=13300,timing={seconds=150}}
    B.refreshAt=nil;B.plan.revision=B.state.revision;B.plan.suggestedDungeon=suggestion;B.UI:RenderTracker()
    eq(T.rows[1].dungeonId,nil);eq(T.model.questId,1)
    eq(T.dungeons.shown,true);eq(T.dungeons.heading.value,"副本建议 · 1处  ›")
    assert(T.dungeons.text.value:find("领主大厅 · 5项任务",1,true));eq(T.dungeons.candidate.rewards.prepare,1)
    -- The browser keeps the same current recommendation as navigation, ahead of dungeon options.
    B.UI.Plan.key=nil;B.UI:SelectTab(1)
    local browser=B.UI.Browser
    eq(browser.entries[1].questId,1);eq(browser.selected.questId,1)
    assert(browser.entries[1].sub:find("推荐先做",1,true))
    eq(browser.entries[2].dungeonCandidate,suggestion)
    local previous=B.action
    B.action=B.plan.taskChoices[4].actions[1];browser:Refresh(1)
    eq(browser.entries[1].questId,4);eq(browser.selected.questId,4)
    browser.rows[3].scripts.OnClick(browser.rows[3],"LeftButton")
    eq(browser.selected.questId,1);eq(B.char.locked,nil)
    browser:Refresh(1);eq(browser.entries[1].questId,4);eq(browser.selected.questId,1)
    B.char.locked=4;browser:Refresh(1);assert(browser.entries[1].sub:find("已锁定",1,true))
    B.char.paused=true;browser:Refresh(1);assert(browser.entries[1].sub:find("已暂停",1,true))
    B.char.locked=nil;B.char.paused=nil;B.action=previous;B.UI.Plan.key=nil
    local selectedTab,started
    B.UI.Dungeon={};B.UI.SelectTab=function(_,index) selectedTab=index end
    browser:Refresh(1);browser.rows[2].scripts.OnClick(browser.rows[2],"LeftButton");browser.buttons[2].run();eq(B.UI.Dungeon.selected,suggestion.dungeonId);eq(selectedTab,4)
    B.Dungeon={StartTaskBatch=function(_,id) started=id;return true end}
    local valid,why=B.Selection.CanChoose(suggestion,B.plan.revision);assert(valid,why);browser.buttons[1].run();eq(started,suggestion.dungeonId)
    B.plan.suggestedDungeon=nil;B.UI:RenderTracker();eq(T.rows[1].dungeonId,nil);eq(T.dungeons.shown,false)
    B.plan.dungeonChoices={suggestion}
    eq(B.UI.Plan.Rows(B.plan)[1],suggestion);assert(B.Selection.CanChoose(suggestion,B.plan.revision))
    local second={dungeonId="reference:36",title="死亡矿井",rewards={count=6,prepare=0}}
    B.plan.dungeonChoices[2]=second;B.UI:RenderTracker()
    eq(T.dungeons.heading.value,"副本建议 · 2处  ›");eq(T.model.questId,1)
    T.dungeons.scripts.OnClick()
    assert(B.menu["领主大厅 · 5项任务"]);B.menu["死亡矿井 · 6项任务"].callback()
    eq(B.UI.Dungeon.selected,second.dungeonId);eq(selectedTab,4);eq(B.char.taskBatch,nil)
    -- Recommendations stay visible while automatic planning waits for the player to stop.
    B.plan.revision=B.state.revision-1;B.UI:RenderTracker();eq(T.dungeons.shown,true)
    B.plan.revision=B.state.revision
    for _,key in ipairs({"inInstance","taskBatch","gearTarget"}) do
        B.state[key]=true;B.UI:RenderTracker();eq(T.dungeons.shown,false);B.state[key]=nil
    end
    B.settings.dungeons=false;B.UI:RenderTracker();eq(T.dungeons.shown,false);B.settings.dungeons=true
    B.char.paused=true;B.UI:RenderTracker();eq(T.dungeons.shown,false);B.char.paused=false
    B.UI:RenderTracker();T.dungeons.scripts.OnClick();B.menu["本级稍后提醒"].callback();eq(T.dungeons.shown,false)
    B.state.level=B.state.level+1;B.UI:RenderTracker();eq(T.dungeons.shown,true)
    B.state.level=B.state.level-1;T.dungeons.dismissedLevel=nil
    B.plan.dungeonChoices={suggestion}
    -- A chosen dungeon has a visible exit even after dismissing suggestions or pausing.
    T.dungeons.dismissedLevel=B.state.level
    B.char.taskBatch={id=suggestion.dungeonId};B.char.paused=true
    B.UI:RenderTracker();eq(T.dungeons.shown,true);eq(T.dungeons.text.value,"返回正常练级  ›")
    local quests,refreshes=B.state.quests,B.refreshes or 0
    B.refreshAt=1;T.dungeons.scripts.OnClick()
    eq(B.char.taskBatch,nil);eq(B.char.paused,false);eq(B.state.quests,quests);eq(B.refreshes,refreshes+1)
    B.refreshAt=nil;B.plan.revision=B.state.revision;T.dungeons.dismissedLevel=nil
    B.char.taskBatch={id=suggestion.dungeonId}
    B.UI:TrackerMenu(B.UI.frame);B.menu["返回正常练级"].callback();eq(B.char.taskBatch,nil)
    B.plan.revision=B.state.revision
    -- Dungeon actions call the task batch directly, with no hidden legacy widgets.
    local stopped,waiting,retried=false,false,false
    B.Dungeon.CanContinueTask=function(row) return row.id==166 end
    B.Dungeon.ToggleTaskBatchWait=function() waiting=true;return true end
    B.Selection.Automatic=function() stopped=true;return true end
    B.Instances={Retry=function() retried=true;return true end}
    browser.DungeonDetail=function() end;browser.Refresh=function() end
    browser.selected={key=suggestion.dungeonId,title=suggestion.title,dungeon={},tasks={{id=166}}}
    browser:Detail();eq(browser.buttons[1].enabled,true);eq(browser.buttons[2].shown,false)
    browser.selected.tasks={};browser:Detail();eq(browser.buttons[1].enabled,false)
    browser.selected.tasks={{id=166}};browser:Detail()
    started=nil;browser.buttons[1].run();eq(started,suggestion.dungeonId)
    B.char.taskBatch={id=suggestion.dungeonId,waiting=true};B.state.instanceEntryError="entry"
    browser:Detail();browser.buttons[1].run();browser.buttons[2].run();browser.buttons[3].run()
    assert(stopped and waiting and retried)
    B.refreshAt=1;browser:Detail();eq(browser.buttons[1].enabled,true);eq(browser.buttons[2].enabled,false)
    B.finish()
end)
test("未来行动中的交付预期不能把未接任务显示成已接或可交付",function()
    local B=ready();local T=B.UI.tracker
    B.plan.best={actions={{questId=1,kind="objective"},{questId=99,kind="turnin",title="未来交付任务"}}}
    B.UI:RenderTracker()
    local row;for _,item in ipairs(T.model.rows) do if item.questId==99 then row=item end end
    eq(row.status,"未接取");eq(row.accepted,false);eq(T.model.unacceptedCount,1)
    eq(row.kind,"accept");eq(row.progress,"先接取，再推进任务目标")
    B.finish()
end)
test("原生更新后清除旧目标和旧任务行且拒绝过期任务点击",function()
    local B=ready();B.UI.tracker.otherHeader:Click();local T=B.UI.tracker
    B.state.revision=B.state.revision+1;T.rows[1].scripts.OnClick(nil,"RightButton")
    eq(B.menu["优先做此任务"].enabled,false);eq(B.char.locked,nil)
    B.state.quests[2]=nil;B.state.quests[3]=nil;B.plan.taskChoices={};B.plan.taskOrder={}
    B.state.quests[1].objectives={};B.UI:RenderTracker()
    eq(T.objectives[1].shown,false);eq(T.rows[1].shown,false);eq(T.queueScroll.shown,false)
    B.state.quests[1].objectives={{text="旧目标",finished=true}};B.action.objectiveIndex=1
    B.UI:RenderTracker();eq(T.model.questId,nil);eq(B.UI.title.value,"正在安排行程")
    eq(#T.model.rows,1);eq(B.UI.QuestStatus(B.state,1,B.plan),"已接取")
    B.state.quests[1].ready=true;B.UI:RenderTracker();eq(#T.model.rows,1);eq(B.UI.QuestStatus(B.state,1,B.plan),"可交付")
    B.action.itemGain=2;B.action.targetId=500;B.UI:RenderTracker();eq(T.model.questId,1)
    B.action.itemGain=nil;B.action.kind="accept";B.UI:RenderTracker();eq(T.model.questId,nil)
    B.action.kind="turnin";B.UI:RenderTracker();eq(T.model.questId,1)
    B.state.quests[1].ready=false;B.UI:RenderTracker();eq(T.model.questId,nil)
    B.state.quests[1].ready=true
    B.action={kind="transit",mode="flight",fromTaxi=2,toTaxi=5,questId=1,title="飞往 湖畔镇"}
    B.state.transportKnown=true;B.state.unlocked={["taxi:2"]=true,["taxi:5"]=true}
    B.state.taxiAvailability={["2:5"]=true}
    B.Navigation.actions={B.action};B.Navigation.index=1
    B.UI:RenderTracker();eq(T.model.questId,1)
    B.state.unlocked["taxi:5"]=false;B.UI:RenderTracker();eq(T.model.questId,nil)
    B.state.unlocked["taxi:5"]=true;B.state.taxiAvailability["2:5"]=false
    B.UI:RenderTracker();eq(T.model.questId,nil)
    B.Navigation.actions=nil
    T.otherOpen=false
    -- A first plan can still be running with a full quest log. Native empty font strings return nil.
    B.action=nil;B.plan=nil;B.jobs.plan=coroutine.create(function() coroutine.yield() end)
    for id=1,30 do
        B.state.quests[id]={title="已接任务 "..id,objectives={{text="收集物品",numFulfilled=2,numRequired=5}}}
    end
    for _,font in ipairs({T.career.text,T.area,T.location,T.thenText,T.footer,T.reward.text}) do
        font.GetText=function(self) if self.value~="" then return self.value end end
    end
    B.UI:RenderTracker()
    eq(B.UI.title.value,"正在安排行程");eq(T.queueLabel.value,"已接任务");eq(#T.model.rows,30)
    eq(T.queueScroll.shown,true);eq(T.rows[1].status,"已接取");eq(T.rows[1].objectives[1].count.value,"2/5")
    eq(T.career.shown,false);eq(T.thenButton.shown,false);eq(T.location.value,"当前行程");eq(T.footer.shown,false)
    eq(T.reward.shown,false)
    eq(T.otherLabel.value,"其他已接任务 · 29");eq(#T.displayRows,1);eq(T.otherChild.shown,false)
    T.otherHeader:Click();eq(#T.displayRows,30);eq(T.otherChild.shown,true)
    eq(T.rows[30].parent,T.otherChild);eq(T.rows[30].objectives[1].count.value,"2/5")
    T.otherHeader:Click();eq(#T.displayRows,1);eq(T.rows[30].shown,false)
    B.planningResumeAt=10;B.UI:RenderTracker()
    eq(B.UI.title.value,"停下后更新行程");eq(#T.model.rows,30)
    eq(T.rows[1].objectives[1].count.value,"2/5")
    B.planningResumeAt=nil
    local order={}
    for id=1,30 do
        local stage={kind="objective",questId=id,objectiveIndex=1}
        order[id]={kind="task",questId=id,actions={stage},stages={stage}}
    end
    B.plan={taskOrder=order,taskChoices=order,revision=B.state.revision}
    B.action=order[1].actions[1];B.UI:RenderTracker()
    eq(T.model.questId,1);eq(T.thenButton.questId,2);eq(T.thenButton.shown,true)
    eq(#T.displayRows,0);eq(T.otherLabel.value,"其他已接任务 · 28");eq(T.otherChild.shown,false)
    B.state.quests[1]=nil;B.state.completed[1]=true;B.action=order[2].actions[1]
    B.UI:RenderTracker();eq(T.model.questId,2);eq(T.thenButton.questId,3);eq(T.otherLabel.value,"其他已接任务 · 27")
    B.finish()
end)
test("暂停飞行手动导航保持真实当前类型且不自动跳过任务",function()
    local B=ready();local T=B.UI.tracker
    B.char.paused=true;B.UI:RenderTracker();eq(T.experience.value,"已暂停");eq(B.UI.title.value,"当前任务");eq(#T.model.rows,2)
    B.char.paused=false;B.plan.preparingQuest={title="旧前置"}
    B.action={kind="flight",title="正在飞行"};B.UI:RenderTracker();eq(T.model.kind,"flight");eq(T.model.hint,nil)
    assert(not B.UI.body.value:find("旧前置",1,true));B.plan.preparingQuest=nil
    B.Navigation.manual={};B.action={kind="manual",title="手动目的地"};B.UI:RenderTracker();eq(T.model.kind,"manual");eq(#T.model.rows,3)
    local cleared=0;B.Navigation.ClearManual=function(self) self.manual=nil;cleared=cleared+1 end
    B.char.locked=1;T.questTitle.scripts.OnClick(nil,"RightButton");B.menu["返回任务"].callback()
    eq(cleared,1);eq(B.Navigation.manual,nil);eq(B.char.locked,1);eq(B.state.quests[1].objectives[1].numFulfilled,3)
    B.finish()
end)
test("施法事件只为相关炉石状态请求刷新而不响应其他单位法术",function()
    local B=ready();B.Hearth={Event=function(_,event,unit,guid,spell) return unit=="player" and spell==8690 or nil end}
    B.refreshAt=nil;B.dirty=false
    local event=B.frame.scripts.OnEvent
    event(nil,"UNIT_SPELLCAST_START","party1","cast",8690);eq(B.refreshAt,nil);eq(B.dirty,false)
    event(nil,"UNIT_SPELLCAST_START","player","cast",1);eq(B.refreshAt,nil)
    event(nil,"UNIT_SPELLCAST_START","player","cast",8690);assert(B.refreshAt);eq(B.dirty,true)
    B.finish()
end)
test("导航独立定位旋转关闭隐藏并保留窗口设置",function()
    local B=ready();local U=B.UI
    U:SetNavigation(100,0.7,true);eq(U.navFrame.shown,true);eq(U.tracker.navTitle.value,"当前任务")
    eq(U.tracker.navBearing.rotation,-0.7)
    B.action={title="当前任务",kind="objective",position={approximate=true}}
    U:SetNavigation(100,0.7,true);eq(U.tracker.navTitle.value,"当前任务 · 区域参考点")
    B.settings.arrow=false;U:SetNavigation(100,0.7,true);eq(U.navFrame.shown,true)
    eq(U.nav.value,"");eq(U.tracker.navBearing.shown,false);eq(U.tracker.navNext.shown,false)
    B.settings.arrow=true;U:SetNavigation(nil);eq(U.navFrame.shown,false)
    local guide={kind="turnin",questId=4601,title="超级清洁器5200型！",text="在清洁区使用清洁器交付任务。",roomName="清洁区"}
    local T=U.tracker;local originalFrame=U.frame
    B.state.inInstance,B.state.instanceType,B.state.instanceId,B.state.instanceName=true,"party",90,"诺莫瑞根"
    B.settings.arrow=false
    B.DungeonCatalog={entries={["reference:90"]={id="reference:90"}}}
    local indexReady=B.indexReady;B.indexReady=false
    U:RenderTracker();eq(U.frame,originalFrame);eq(T.model.dungeonName,"诺莫瑞根");eq(U.title.value,"副本任务");eq(#T.model.rows,0)
    B.action=guide;B.Navigation.planInstance=90;U:RenderTracker()
    local transit={kind="transit",mode="tram",title="乘地铁前往铁炉堡",fromName="暴风城",toName="铁炉堡",atDeparture=true}
    B.Navigation.actions={transit,guide};B.Navigation.index=1
    U:SetNavigation(nil,nil,nil,transit);eq(U.nav.value,"1/2")
    local place="|cff"..U.hex.place
    eq(T.navTitle.value,"搭乘开往"..place.."铁炉堡|r的地铁");eq(T.navNext.value,"下一步  交付「"..guide.title.."」")
    B.Navigation.index=2
    U:SetNavigation(nil,nil,nil,guide);eq(U.navFrame.shown,true);eq(U.nav.value,"2/2")
    eq(T.navTitle.value,"交付「"..guide.title.."」");eq(T.navDetail.value,"在"..place.."清洁区|r使用清洁器交付任务。");eq(T.navNext.shown,false)
    B.Navigation.actions=nil
    eq(T.rows[1].questId,4601);eq(T.rows[1].progress.value,guide.text)
    local previous=B.Dungeon
    local d=B.DungeonCatalog.entries["reference:90"]
    local reads=0
    B.Dungeon={TaskApproach=function(a) return a end,TaskInstance=function() return d end,
        Tasks=function()
            reads=reads+1
            return {{id=4601,title=guide.title,allowed=true,group=1},{id=1,title="收集零件",allowed=true,group=2,lowValue=true},
                {id=4,title="护送机器人",allowed=true,group=3,position={entityName="机器人"}},
                {id=5,title="一团混乱",allowed=true,group=3},
                {id=6,title="已交付",group=5},{id=7,title="已暂缓",group=4}}
        end}
    B.indexReady=true;B.state.locked=1
    B.state.quests[1].objectives={{text="零件",targetKind="item",numRequired=6,numFulfilled=2},{text="调查图纸",type="object",numRequired=1,numFulfilled=0}}
    U:RenderTracker();eq(T.rows[2].objectives[1].count.value,"2/6");eq(T.rows[2].objectives[2].count.value,"0/1")
    assert(T.rows[2].icon.texture:find("collect.tga",1,true));eq(T.rows[2].objectives[1].icon.texture,T.rows[2].icon.texture)
    eq(T.rows[3].status,"未接取");eq(T.rows[4].questId,5);eq(T.rows[3].parent,T.queueChild)
    eq(T.rows[3].progress.value,"向「机器人」接取任务。")
    eq(#T.model.rows,4);eq(T.queueLabel.value,"进行中 1 · 未接取 2 · 可交付 1")
    B.state.quests[1].objectives[1].numFulfilled=4;U:RenderTracker()
    eq(T.rows[2].objectives[1].count.value,"4/6");eq(reads,1)
    local timers,oldTimer={},C_Timer
    C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
    eq(T.model.feedback,nil)
    local savedQuests=B.state.quests
    B.state.quests={[1]={objectives={{text="零件",finished=true,numRequired=6,numFulfilled=6},{text="调查图纸",type="object",numRequired=1}}}}
    U:RenderTracker();eq(T.model.feedback,"目标完成 · 零件")
    eq(T.rows[2].objectives[1].check.value,"✓");assert(T.rows[2].icon.texture:find("interact.tga",1,true))
    assert(T.rows[2].objectives[1].icon.texture:find("done.tga",1,true));U:RenderTracker();eq(#timers,1)
    B.Dungeon.Tasks=function() return {{id=1,title="收集零件",allowed=true,group=1,position={entityName="技师"}}} end
    B.state.quests={[1]={ready=true,title="收集零件"}};B.state.revision=(B.state.revision or 0)+1
    U:RenderTracker();eq(T.model.feedback,"任务完成 · 收集零件（本内可交）")
    eq(T.rows[1].status,"可交付");assert(T.rows[1].progress.value:find("技师",1,true))
    timers[1]();assert(T.model.feedback)
    U:DungeonTurnedIn(1);B.state.quests={};U:RenderTracker();eq(T.model.feedback,"已交付 · 收集零件")
    timers[#timers]();U:RenderTracker();eq(T.model.feedback,nil)
    B.state.quests=savedQuests;C_Timer=oldTimer
    B.Dungeon=previous;B.state.locked=nil
    local browser,dungeon,selectTab=U.Browser,U.Dungeon,U.SelectTab
    U.Browser={ClearSearch=function(b) b.cleared=true end,dungeonDetail={showLoot=true}};U.Dungeon={}
    U.SelectTab=function(_,i) eq(i,4) end
    T.questTitle:Click();eq(U.Dungeon.selected,"reference:90");eq(U.Browser.cleared,true);eq(U.Browser.dungeonDetail.showLoot,false)
    U.Browser,U.Dungeon,U.SelectTab=browser,dungeon,selectTab;U.details:Hide()
    B.state.inInstance=false;U:RenderTracker();eq(U.frame,originalFrame);eq(T.instanceRoster,nil);eq(T.model.dungeonName,nil);assert(#T.model.rows>0)
    B.indexReady=indexReady
    B.settings.arrow=true
    U.navFrame.scripts.OnDragStop();eq(B.settings.navigationPosition[3],25)
    B:NormalizeSettings(B.settings);eq(B.settings.navigationPosition[3],25)
    B:RestoreSettings();eq(B.settings.navigationPosition,nil)
    assert(loadfile("Planner/Travel.lua"))("AiLeveling",B)
    local goal={kind="accept",questId=4,title="新的任务",position={map=2,x=0.5,y=0,entityName="接取人"}}
    local transit={kind="transit",mode="tram",questId=4,title="乘地铁前往铁炉堡",publicTransit=true,
        departure={map=1,x=0.1,y=0},position={map=2,x=0.2,y=0},departureRadius=40,
        fromName="暴风城地铁入口",toName="铁炉堡",travelSeconds=100,travelWait=40,travelRide=60}
    B.Navigation.Distance=function(_,a,b) if a and b and a.map==b.map then return math.abs(a.x-b.x)*700 end end
    B.state.position={map=1,x=0,y=0};B.state.runSpeed=7
    B.Navigation.actions={transit,goal};B.Navigation.index=1;B.action=transit
    U:RenderTracker();local T=U.tracker;local journey=T.model.journey
    eq(U.title.value,"新的任务");eq(T.model.kind,"accept");eq(T.action,transit)
    eq(#journey.steps,4);eq(journey.seconds,140);eq(journey.distance,280)
    eq(journey.steps[1].title,"走到 暴风城地铁入口");eq(journey.steps[2].detail,"平均等候 0:40 · 乘坐 1:00")
    U:SetNavigation(nil,nil,nil,transit)
    local place="|cff"..U.hex.place
    eq(T.navTitle.value,"走到 "..place.."暴风城地铁入口|r");eq(T.navNext.value,"下一步  乘地铁前往"..place.."铁炉堡|r")
    eq(T.journeyRows[1].title.value,T.navTitle.value)
    assert(T.navIcon.texture:find("location.tga",1,true) and T.navNextIcon.texture:find("tram.tga",1,true))
    eq(journey.steps[4].title,"接取 新的任务");eq(T.journey.shown,true)
    local model,models,layout,layouts=U.TrackerModel,0,U.LayoutTracker,0
    U.TrackerModel=function(...) models=models+1;return model(...) end
    U.LayoutTracker=function(...) layouts=layouts+1;return layout(...) end
    local distance,reads=B.Navigation.Distance,0
    B.Navigation.Distance=function(...) reads=reads+1;return distance(...) end
    for _=1,10 do U.frame.scripts.OnUpdate(nil,1) end
    eq(models,0);eq(layouts,0);eq(reads,0)
    eq(T.journeyRows[1].shown,true);eq(T.journeyRows[2].shown,false)
    T.journeyHeader.scripts.OnClick();eq(T.journeyRows[2].shown,true);eq(U.title.value,"新的任务")
    U.frame.scripts.OnUpdate(nil,1);eq(T.journeyRows[2].shown,true)
    T.journeyHeader.scripts.OnClick();eq(T.journeyRows[1].shown,true);eq(T.journeyRows[2].shown,false)
    B.state.position=transit.departure;U.frame.scripts.OnUpdate(nil,1)
    eq(#T.model.journey.steps,3);eq(T.model.journey.seconds,130);eq(models,0);assert(reads>0)
    U.TrackerModel,U.LayoutTracker=model,layout
    transit.atDeparture=true;B.state.position={map=1,x=0.2,y=0};U:RenderTracker()
    eq(#T.model.journey.steps,3);eq(T.model.journey.steps[1].kind,"tram")
    U:SetNavigation(nil,nil,nil,transit)
    eq(T.navTitle.value,"乘地铁前往"..place.."铁炉堡|r");eq(T.navNext.value,"下一步  走到 接取人")
    B.char.paused=true;U:RenderTracker();eq(T.journey.shown,false);B.char.paused=false
    transit.mode="flight";B.Transport.flight={action=transit,observedStart=true,duration=100,started=5}
    B.action={kind="flight",title="正在飞行"};U:RenderTracker()
    eq(T.model.journey.seconds,125);eq(T.model.journey.steps[1].detail,"飞行中")
    B.Navigation.index=2;B.action=goal;U:RenderTracker();eq(T.journey.shown,false);eq(T.model.questId,4)
    U:SetNavigation(nil,nil,nil,goal);eq(T.navTitle.value,"接取「新的任务」");eq(T.navDetail.value,"向「接取人」接取任务。")
    eq(B.state.quests[4],nil);eq(B.state.completed[4],nil)
    local savedMap=C_Map
    C_Map={GetMapInfo=function(id) if id==1417 then return {name="阿拉希高地"} end end}
    local point={map=1417,x=.6024,y=.5392,entityName="基恩洛",sourceKind="escortStart",
        travelHint="若只看到奎艾，可在奎艾处等基恩洛护送结束后返回。"}
    local handin={questId=657,kind="turnin",title="新的瘟疫？",position=point}
    B.state.quests[657]={title=handin.title,ready=true};B.action=handin;B.Navigation.actions={handin};B.Navigation.index=1
    U:RenderTracker();U:SetNavigation(nil,nil,nil,handin)
    local location="护送起点 · 阿拉希高地 60.2，53.9"
    assert(T.footer.value:find(location,1,true));eq(U.body.value,point.travelHint)
    assert(T.navDetail.value:find(location,1,true));assert(T.navDetail.value:find(point.travelHint,1,true))
    point.approximate=true;point.sourceKind="patrol"
    U:RenderTracker();U:SetNavigation(nil,nil,nil,handin)
    assert(not T.footer.value:find("60.2",1,true));assert(not T.navDetail.value:find("60.2",1,true))
    C_Map=savedMap
    B.finish()
end)
test("商店事件触发刷新且维修卡片可以忽略",function()
    local B=ready();assert(loadfile("Merchant.lua"))("AiLeveling",B)
    assert(loadfile("Planner/Supplies.lua"))("AiLeveling",B)
    B.action={kind="service",serviceKind="repair",npcId=78,title="铁匠",serviceGoal={durability=0.2}}
    B.state.merchant={npcId=78,canRepair=true,repairCost=123,items={}};B.state.money=100
    B.UI:RenderTracker();assert(not B.UI.body.value:find("铜",1,true))
    local T=B.UI.tracker;eq(T.queuePanel.shown,true);eq(#T.model.rows,3)
    B.action.questId=1
    T.questTitle.scripts.OnClick(nil,"RightButton");B.menu["忽略维修"].callback();eq(B.char.ignoreRepair,true);assert(B.refreshAt)
    eq(B.char.skipped[1],nil);eq(B.state.quests[1].objectives[1].finished,nil)
    B.action={kind="objective",questId=1,title="当前任务"};B.UI:RenderTracker()
    T.questTitle.scripts.OnClick(nil,"RightButton");assert(B.menu["暂时不做"]);eq(B.menu["忽略维修"],nil)
    local event=B.frame.scripts.OnEvent
    event(nil,"MERCHANT_SHOW");eq(B.Merchant.open,true);assert(B.refreshAt)
    local saleRefresh
    B.Merchant.SellJunk=function() saleRefresh=B.refreshes end
    B.time(11);B.frame.scripts.OnUpdate(nil,0)
    eq(saleRefresh,B.refreshes);assert(saleRefresh>0)
    event(nil,"MERCHANT_CLOSED");eq(B.Merchant.open,false)
    B.Merchant:Snapshot(B.state);B.UI:RenderTracker();assert(not B.UI.body.value:find("123 铜",1,true))
    B.finish()
end)
test("原生服务页可切换旅店与训练项目插入取消且页签隐藏正确",function()
    local B=ready(true)
    assert(loadfile("Services.lua"))("AiLeveling",B);assert(loadfile("UI/Services.lua"))("AiLeveling",B)
    B.UI.Services:Create(B.UI.details)
    B.UI.scroll=CreateFrame("ScrollFrame");B.UI.scrollChild=CreateFrame("Frame")
    B.UI.detailText=B.UI:Text(B.UI.scrollChild,13);B.UI.copyBox=CreateFrame("EditBox")
    for _,key in ipairs({"Dungeon","Gear","Plan","Chains"}) do B.UI[key]={frame=CreateFrame("Frame")} end
    B.Data.AmenityPoints=function(_,state,kind) return {{kind=kind,npcId=78,title="服务NPC",description="旅店老板",position={map=1,x=0.5,y=0.5}}} end
    B.Navigation.Distance=function() return 10 end
    B.indexReady=true;B.jobs={};B.state.bindName="旧旅店"
    local event=B.frame.scripts.OnEvent
    B.refreshAt=nil;event(nil,"TRAINER_SHOW");eq(B.Services.trainerOpen,true);assert(B.refreshAt)
    B.refreshAt=nil;event(nil,"TRAINER_SERVICE_INFO_NAME_UPDATE");assert(B.refreshAt)
    event(nil,"TRAINER_CLOSED");eq(B.Services.trainerOpen,false);B.refreshAt=nil
    B.UI:SelectTab(7);local U=B.UI.Services
    eq(U.frame.shown,true);eq(B.UI.Settings.frame.shown,false);eq(U.choose.enabled,true)
    assert(B.UI.detailText.value:find("旧旅店",1,true));U.choose.scripts.OnClick();eq(B.char.serviceStop.kind,"bind")
    for _,kind in ipairs({"bind","unlockFlight"}) do
        B.char.serviceStop.kind=kind;B.char.serviceStop.taxiId=1
        B.char.serviceStop.afterTask={kind="turnin",questId=42,title="旧服务条件",turnIns=0}
        B:NormalizeCharacter(B.char);assert(B.char.serviceStop);eq(B.char.serviceStop.afterTask,nil)
    end
    U.cancel.scripts.OnClick();eq(B.char.serviceStop,nil)
    U.mode.scripts.OnClick();eq(U.kind,"train");U.mode.scripts.OnClick();eq(U.kind,"learn")
    B.state.money=20;B.state.trainer={npcId=78,name="训练师",rows={{name="新技能",sub="等级 1",key="新技能\031等级 1",status="available",cost=30,playerTraining=true}}}
    B.UI:SelectTab(7);assert(B.UI.detailText.value:find("新技能",1,true))
    U.choose.scripts.OnClick();eq(B.char.serviceStop.kind,"train");assert(B.char.serviceStop.learnKey)
    B.action=B.Services.Build({serviceStop=B.char.serviceStop,position=B.state.position}).fallback
    B.UI:RenderTracker();eq(B.UI.tracker.model.kind,"service")
    B.UI:SelectTab(5);eq(U.frame.shown,false);eq(B.UI.Settings.frame.shown,true)
    B:NormalizeCharacter(B.char);assert(B.char.serviceStop);B.char.serviceStop.position.x=2
    B:NormalizeCharacter(B.char);eq(B.char.serviceStop,nil)
    B.finish()
end)
test("低价值任务留在主界面建议中不混入后续行程",function()
    local B=ready();local c=B.plan.taskChoices[3]
    c.lowValue={suggestion="建议放弃",reason="低经验、奖励无提升、无任务线关联。"}
    B.plan.taskChoices[4]={questId=4,kind="task",actions={{kind="accept",questId=4,title="有效新任务"}}}
    B.UI:RenderTracker()
    eq(#B.UI.tracker.model.rows,2);eq(B.UI.tracker.model.rows[2].questId,4)
    eq(B.UI.QuestStatus(B.state,3,B.plan),"已接取")
    assert(loadfile("UI/Plan.lua"))("AiLeveling",B);B.UI.Plan.preview=c
    B.finish()
end)

test("交错行程按任务数汇总并显示每个目标与交付步骤",function()
    local B=ready();local a,b=B.plan.taskChoices[1],B.plan.taskChoices[3]
    B.state.quests[3].level=9;B.state.quests[3].objectives[1].type="item"
    local oa={kind="objective",questId=1,objectiveIndex=1,text="目标甲"};local ob={kind="objective",questId=3,text="目标乙",position={entityName="林地"}}
    local oa2={kind="objective",questId=1,objectiveIndex=2,text="第二件物品"}
    B.plan.taskQueue={stagePlan=true,taskCount=2,seconds=180,low=180,high=180,xp=200,xpKnown=true,
        steps={{choice=a,stage=oa},{choice=a,stage=oa2},{choice=b,stage=ob},{choice=a,stage={kind="turnin"}},{choice=b,stage={kind="turnin"}}}}
    a.executionAction=oa;a.executionTiming={seconds=80,low=80,high=80};B.action=oa
    B.UI:RenderTracker();assert(B.UI.tracker.objectives[1].text.value:find("狗头人",1,true))
    assert(not B.UI.body.value:find("先完成附近目标，再集中交付",1,true))
    eq(B.UI.tracker.model.questId,1)
    eq(#B.UI.tracker.model.rows,0) -- The next task appears once, in the Then section.
    eq(B.state.quests[3].ready,nil)
    local T=B.UI.tracker
    assert(T.thenText.value:find("已接取",1,true));eq(T.thenButton.title.value,"[9] 后续目标")
    eq(T.thenButton.title.color[1],B.UI.colors.white[1]);assert(T.thenButton.progress.value:find("林地",1,true))
    eq(T.thenButton.objectives[1].text.value,"物品");eq(T.thenButton.objectives[1].count.value,"2/4")
    eq(T.thenButton.objectives[1].text.color[1],B.UI.colors.white[1])
    eq(T.thenText.shown,true);eq(T.thenButton.questId,3)
    assert(T.thenText.point[3]>T.queuePanel.point[3],"下一步应在其他任务之前")
    local steps=B.plan.taskQueue.steps
    B.plan.taskQueue.steps={steps[1],steps[2],{choice=a,stage={kind="turnin",position={entityName="收件人"}}}}
    B.UI:RenderTracker();eq(T.thenButton.title.value,"完成后交付 · 收件人")
    eq(T.thenButton.objectiveFrame.shown,false);eq(T.thenButton.progress.value,"")
    B.plan.taskQueue.steps=steps
    B.action=ob;B.UI:RenderTracker();eq(T.thenButton.title.value,"当前任务")
    eq(T.thenButton.status,"已接取");eq(T.thenButton.progress.value,"完成后交付")
    B.action=oa;B.state.revision=B.plan.revision+1;B.state.quests[3]=nil;B.state.completed[3]=true
    B.UI:RenderTracker();eq(T.model.nextId,1);eq(T.model.nextStep.kind,"turnin")
    B.char.paused=true;B.UI:RenderTracker();eq(T.thenText.shown,false);eq(T.thenButton.shown,false)
    B.finish()
end)

test("分散交付点明确现在就近交和等同NPC任务一起交并跟随真实导航",function()
    local B=ready();B.UI.tracker.otherHeader:Click();assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    local a,b,c=unpack(B.plan.taskChoices)
    local function finish(choice,npc,name,x)
        choice.stages={{kind="turnin",questId=choice.questId,position={map=1,x=x,y=0.5,entityKind="npc",entityId=npc,entityName=name}}}
        return choice.stages[1]
    end
    local ta=finish(a,100,"东谷守卫",0.51);local tb=finish(b,200,"闪金镇治安官",0.2);local tc=finish(c,200,"闪金镇治安官",0.2)
    a.distance,b.distance,c.distance=10,300,300
    B.state.quests[1].ready=true;B.action=ta
    B.plan.taskQueue={steps={{choice=a,stage=ta},{choice=c,stage={kind="objective"}},{choice=c,stage=tc},{choice=b,stage=tb}}}
    B.UI:RenderTracker();local T=B.UI.tracker
    assert(T.model.deliverySummary:find("就近交付：到东谷守卫",1,true))
    local rows={};for _,row in ipairs(T.model.rows) do rows[row.questId]=row end
    eq(rows[2].delivery,"同组还差 1 项，做完一起交")
    eq(rows[2].status,"可交付");eq(B.action,ta);eq(B.state.completed[1],nil)
    B.state.quests[3].ready=true;B.plan.taskQueue.steps={{choice=a,stage=ta},{choice=b,stage=tb},{choice=c,stage=tc}}
    B.UI:RenderTracker();assert(T.model.deliverySummary:find("再去闪金镇治安官",1,true))
    B.action=tb;B.UI:RenderTracker()
    assert(T.model.deliverySummary:find("一起交付：到闪金镇治安官交 2 项任务",1,true))
    for _,row in ipairs(T.rows) do
        if row.questId==3 then eq(row.atStop,true);eq(row.parent,T.currentChild);eq(row.progress.shown,false) end
    end
    eq(T.thenText.shown,false)
    B.state.locked=2;B.state.quests[3].ready=false;B.UI:RenderTracker()
    assert(T.model.deliverySummary:find("顺路先交：到闪金镇治安官",1,true))
    for _,row in ipairs(T.rows) do
        if row.questId==3 then eq(row.atStop,false);eq(row.parent,T.otherChild);eq(row.progress.shown,false);eq(row.objectiveFrame.shown,true) end
    end
    B.state.locked=nil;B.action={kind="objective",questId=3,title=c.title};B.UI:RenderTracker()
    eq(T.model.deliverySummary,"同组还差 1 项，做完一起交")
    B.action={kind="service",title="维修"};B.UI:RenderTracker();eq(T.model.deliverySummary,nil)
    B.action=ta;B.char.paused=true;B.UI:RenderTracker();eq(T.model.deliverySummary,nil)
    -- Two journal hand-ins at a manually chosen landing must survive a plan that only visits Wetlands.
    B.char.paused=false
    local village={map=1437,x=.45,y=.45,entityName="麦琳·石纹"}
    local city={map=1455,x=.7,y=.2,entityName="勘察员塔伯斯·雷矛"}
    B.state={revision=3,position=village,quests={[1]={title="寻找挖掘队",ready=true},
        [2]={title="向铁炉堡报告",ready=true},[3]={title="森内尔的报告",ready=true}}}
    B.plan={revision=2,origin=village,taskChoices={a},taskOrder={a}}
    B.Data.GetQuest=function(_,id) return {id=id} end
    B.Data.Target=function(_,q) return q.id==1 and village or city end
    B.Transport.flight={toTaxi=6}
    B.FlightData={nodes={[6]={}}}
    B.Navigation.hbd={};B.Navigation.Distance=function(_,from,to) return from.map==to.map and 1 or nil end
    B.Flights={Position=function(_,map) return map==1455 and city end}
    local flight={kind="flight",title="飞行中 · 铁炉堡"}
    local model=B.UI.TrackerModel(B.state,B.plan,flight,false)
    eq(model.nextId,2);eq(model.rows[1].questId,3)
    assert(model.rows[1].delivery:find("抵达后交付",1,true));eq(model.rows[1].turnInAction.position,city)
    B.Transport.flight=nil;B.Transport.FlightGate=function() end
    assert(loadfile("Navigation.lua"))("AiLeveling",B)
    B.Navigation.Distance=function(_,from,to) return from.map==to.map and 1 or nil end
    B.Navigation.actions={ta};B.jobs.plan=true;B.state.position=city
    eq(B.Navigation:Current().questId,2)
    B.state={revision=4,position=city,quests={[3]=B.state.quests[3]}}
    eq(B.Navigation:Current().questId,3)
    -- Crossing into a new zone can precede the planning job or leave it waiting while moving.
    local arrivalState=B.state
    local key={kind="objective",questId=97329,position=village}
    local localWork={kind="objective",questId=58,position=city}
    B.state={revision=5,position=city,quests={[97329]={},[58]={}}}
    B.Navigation.actions={key};B.plan.regions={{map=city.map,choices={{questId=58,actions={localWork}}}}}
    B.Navigation.plan=B.plan;B.plan.taskQueue={steps={{stage=key}}};B.Navigation.upcomingQuest=key
    B.settings.mapTaskScope="route"
    B.jobs.plan=nil;eq(B.Navigation:Current(),localWork)
    local pins=B.Navigation:MapPoints();eq(#pins,1);eq(pins[1].action,localWork)
    local view=B.Navigation:TrackerPlan(B.plan,B.state)
    eq(view.taskQueue,nil);eq(view.taskChoices[1].questId,58)
    B.jobs.plan=true;eq(B.Navigation:Current(),localWork)
    B.state.quests[58]=nil;eq(B.Navigation:Current(),nil)
    B.state.locked=97329;eq(B.Navigation:Current(),key)
    B.state=arrivalState;B.plan.regions=nil;B.Navigation.actions={ta}
    -- Manual tram travel has no selected taxi node or outdoor player position.
    assert(loadfile("Data/PublicTransit.lua"))("AiLeveling",B)
    assert(loadfile("Planner/Flights.lua"))("AiLeveling",B)
    assert(loadfile("Transport.lua"))("AiLeveling",B)
    local sw={map=1453,x=.5,y=.5,entityName="格瑞曼德·艾尔默"}
    B.state.quests[1]={title="湿地交付",ready=true}
    B.state.quests[2]={title="暴风城交付",ready=true}
    B.Data.Target=function(_,q) return ({village,sw,city})[q.id] end
    B.Transport:ObserveTram(0,1453)
    B.state.position=nil
    B.Transport:ObserveTram(369,nil)
    local function riding()
        return B.UI.TrackerModel(B.state,B.plan,B.Navigation:Current(),false)
    end
    model=riding();eq(model.nextOnArrival,"下车后");eq(model.nextId,3);eq(#model.rows,0)
    B.UI:RenderTracker();assert(T.thenText.value:find("下车后",1,true));assert(T.thenButton.progress.value:find("雷矛",1,true))
    assert(loadfile("Transport.lua"))("AiLeveling",B)
    B.Transport:ObserveTram(369,nil);eq(riding().nextId,3)
    B.state.position=city;B.Transport:ObserveTram(0,city.map)
    B.Navigation.actions={{kind="move",position=village}}
    eq(B.Navigation:Current().questId,3)
    B.state.position=nil;B.Transport:ObserveTram(369,nil);eq(riding().nextId,2)
    B.Transport:ObserveTram(0,village.map);B.Transport:ObserveTram(369,nil)
    model=riding();eq(model.nextId,nil);eq(#model.rows,2)
    local saved=UnitPosition
    local y=1500
    UnitPosition=function() return 0,y,0,369 end
    B.Transport:Update();y=1350;B.Transport:Update();eq(riding().nextId,3)
    UnitPosition=saved
    B.finish()
end)

test("职业提醒随可学技能和待接任务更新，稍后保留行程并只导航本职业训练师",function()
    local B=ready(true);assert(loadfile("Services.lua"))("AiLeveling",B)
    assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    B.state.level,B.state.class,B.state.className,B.state.classMask=22,"PALADIN","圣骑士",2
    Enum={SpellBookSpellBank={Player=0},SpellBookItemType={Spell=1,FutureSpell=2}}
    local spells={{spellID=101,name="圣光术",subName="等级 4",itemType=2,level=22},
        {spellID=102,name="正义圣印",subName="等级 3",itemType=2,level=20},
        {spellID=103,name="未来技能",itemType=2,level=24},
        {spellID=104,name="其他专精",itemType=2,level=20,isOffSpec=true}}
    IsCharacterNewlyBoosted=function() return false end
    C_SpellBook={GetNumSpellBookSkillLines=function() return 1 end,
        GetSpellBookSkillLineInfo=function() return {itemIndexOffset=0,numSpellBookItems=#spells} end,
        GetSpellBookItemInfo=function(i,bank) eq(bank,0);return spells[i] end,
        GetSpellBookItemLevelLearned=function(i) return spells[i].level end}
    local before=B.Services:Snapshot(B.state);eq(#B.state.trainableSpells,2)
    local get=B.Data.GetQuest
    B.Data.GetQuest=function(self,id) if id==1641 then return {id=id,title="圣洁之书",requiredClasses=2} end return get(self,id) end
    local quest={questId=1641,title="圣洁之书",level=12,kind="task",actions={{kind="accept",questId=1641}}}
    B.plan.taskChoices[#B.plan.taskChoices+1]=quest
    local T=B.UI.tracker;B.UI:RenderTracker()
    eq(T.career.shown,true);assert(T.career.text.value:find("圣光术 · 等级 4",1,true));assert(not T.career.text.value:find("圣洁之书",1,true))
    eq(T.model.questId,1);eq(T.objectives[1].count.value,"3/10")
    local clicked;SetItemRef=function(link) clicked=link end
    T.career.view:Click();B.menu["圣光术 · 等级 4 · 22级"].callback();eq(clicked,"spell:101")
    T.career.later:Click();eq(T.career.shown,false);eq(B.char.classReminderLevel,22);eq(T.model.questId,1);eq(B.char.skipped[1641],nil)
    B:NormalizeCharacter(B.char);B.UI:RenderTracker();eq(T.career.shown,false)
    B.UI:TrackerMenu(B.UI.frame);B.menu["恢复职业提醒"].callback();eq(T.career.shown,true)
    B.Data.amenitiesByMap={[2]={9}}
    B.Data.AmenityPoints=function(_,state,kind,maps)
        eq(kind,"train");eq(maps[2],true)
        return {{kind="train",npcId=8,title="铁匠",description="锻造训练师",position={map=1,x=0.51,y=0.5}},
            {kind="train",npcId=9,title="圣骑士导师",description="圣骑士训练师",position={map=1,x=0.6,y=0.5}}}
    end
    B.Navigation.Distance=function(_,a,b) return math.abs(a.x-b.x)*1000 end
    B.char.locked=1;T.career.train:Click();eq(B.char.serviceStop.npcId,9);eq(B.char.serviceStop.classTraining,true);eq(B.char.locked,1)
    B.Services:Cancel();B.plan.revision=B.state.revision
    spells[1].itemType=1;assert(B.Services:Snapshot(B.state)~=before);eq(#B.state.trainableSpells,1)
    B.state.quests[1641]={title=quest.title,objectives={}};B.UI:RenderTracker();assert(not T.career.text.value:find("圣洁之书",1,true))
    T.career.later:Click();B.state.level=24;B.Services:Snapshot(B.state);B.UI:RenderTracker()
    eq(T.career.shown,true);eq(#B.state.trainableSpells,2);assert(T.career.text.value:find("未来技能",1,true))
    T.career.train:Click();eq(B.char.serviceStop.npcId,9)
    spells[2].itemType=1;spells[3].itemType=1;B.Services:Snapshot(B.state);B.UI:RenderTracker();eq(T.career.shown,false)
    eq(B.char.serviceStop,nil);eq(B.char.locked,1)
    local unlock={questId=900,title="职业技能解锁",kind="class",spell=355}
    quest.unlock=unlock;B.char.classReminderLevel=nil
    B.plan.revision=B.state.revision
    B.UI:RenderTracker();eq(T.career.shown,false);eq(T.model.questId,1)
    local browser=B.UI.Browser
    assert(loadfile("Planner/Eligibility.lua"))("AiLeveling",B)
    B.Data.ids={1641};browser:Refresh(9);eq(browser.selected.questId,1641);eq(B.char.locked,1)
    eq(browser.buttons[1].text.value,"跟随这条职业任务线");browser.buttons[1].run();eq(B.char.locked,900)
    browser.buttons[3].run();eq(B.char.locked,nil)
    B.finish()
end)

test("装备和奖励留在任务列表，一键忽略且右键换装只处理该件",function()
    local B=ready();assert(loadfile("Planner/Gear.lua"))("AiLeveling",B)
    assert(loadfile("Merchant.lua"))("AiLeveling",B)
    local function item(id,score)
        return {id=id,name="装备 "..id,link="|cff1eff00|Hitem:"..id.."|h[装备 "..id.."]|h|r",
            equipLoc="INVTYPE_HEAD",usable=true,stats={ITEM_MOD_STRENGTH_SHORT=score}}
    end
    local old,bag,reward=item(99,4),item(100,6),item(101,8)
    B.state.class,B.state.role,B.state.damageStyle="WARRIOR","DAMAGER","auto"
    B.state.equipment={[1]=old};B.state.bagEquipment={bag};B.state.bags[100]=1
    B.char.ignoredGear={}
    B.plan.taskChoices[1].rewardPick={item=reward,upgrade=B.Gear.Upgrade(reward,B.state)}
    local T=B.UI.tracker
    local function refresh() B.Gear:ScanBagOffers(B.state);B.UI:RenderTracker() end
    refresh();eq(T.gear.shown,false);eq(T.reward.shown,false)
    B.state.bags[100]=2;refresh()
    eq(T.gear.shown,true);assert(T.gear.text.value:find(bag.link,1,true));assert(T.gear.text.value:find("+50%",1,true))
    eq(T.gear.parent,T.currentChild);eq(T.gear.shade,nil);eq(T.gear.equip,nil)
    eq(B.Gear.UpgradeText({upgrade={oldScore=1000,delta=1}}),"+<1%")
    eq(B.Gear.UpgradeText({upgrade={oldScore=0,delta=1}}),"新")
    eq(T.reward.shown,false);eq(T.model.questId,1);eq(T.objectives[1].count.value,"3/10")
    B.action.kind="accept";refresh()
    eq(T.reward.shown,true);assert(T.reward.text.value:find(reward.link,1,true))
    assert(T.reward.text.value:find("奖励：",1,true));eq(T.reward.icon.shown,false)
    assert(T.reward.text.value:find("大幅提升",1,true));assert(not T.reward.text.value:find("\n",1,true))
    B.action.kind="turnin";refresh();eq(T.reward.icon.shown,true)
    B.plan.taskChoices[1].rewardPick.upgrade.delta=-1;refresh()
    eq(T.reward.icon.shown,false);assert(T.reward.text.value:find("选择 ",1,true))
    B.action.kind="accept";refresh();eq(T.reward.shown,false)
    B.plan.taskChoices[1].rewardPick.upgrade.delta=4;refresh()
    local previous=SetItemRef;local clicked
    SetItemRef=function(link) clicked=link end
    T.reward.scripts.OnHyperlinkClick(T.reward,"item:101",reward.link,"LeftButton");eq(clicked,"item:101")
    SetItemRef=previous
    T.gear.close:Click();eq(T.gear.shown,false);eq(B.char.ignoredGear["item:100"],true)
    refresh();eq(T.gear.shown,false)
    B.state.bags[100]=3;refresh();eq(T.gear.shown,false)
    B.state.bags[100]=4;refresh();eq(T.gear.shown,false)
    B.UI:TrackerMenu(B.UI.frame);B.menu["恢复装备提醒"].callback();eq(T.gear.shown,false)
    B.state.bags[100]=5;refresh();eq(T.gear.shown,true)
    local function menu() T.gear.scripts.OnMouseUp(T.gear,"RightButton") end
    B.combat(true);menu();eq(B.menu["装备这件"].enabled,false)
    eq(B.Gear:EquipAdvice(T.gear.advice),false)
    B.combat(false);B.UI:RenderTracker()
    local equips=0
    C_Item.EquipItemByName=function(link,slot)
        eq(link,bag.link);eq(slot,1);equips=equips+1
        B.state.equipment[slot]=bag;B.state.bagEquipment={old};B.state.bags={[99]=1}
    end
    menu();eq(B.menu["装备这件"].enabled,true);B.menu["装备这件"].callback();eq(equips,1);eq(T.gear.shown,false)
    refresh();B.state.equipment={[1]=old};B.state.bagEquipment={bag};B.state.bags={[100]=1}
    refresh();eq(T.gear.shown,false) -- Just taken off, not newly acquired.
    B.state.bags[100]=2;bag.pending=true;refresh();eq(T.gear.shown,false)
    bag.pending=nil;refresh();eq(T.gear.shown,true)
    bag.effects={{kind="equip",text="特殊效果"}};refresh();eq(T.gear.shown,false);bag.effects=nil
    B.state.bags[100]=3;refresh();local stale=T.gear.advice
    B.state.bagEquipment={};eq(B.Gear:EquipAdvice(stale),false);eq(equips,1)
    B.state.bagEquipment={bag};B.settings.rewardAdvice=false;refresh()
    eq(T.gear.shown,false);eq(T.reward.shown,false)
    B.settings.rewardAdvice=true;refresh();eq(T.gear.shown,false)
    local second=item(102,20)
    B.state.bagEquipment={bag,second};B.state.bags[100]=4;B.state.bags[102]=1;refresh()
    eq(T.gear.advice.item.id,100);T.gear.close:Click();eq(T.gear.advice.item.id,102)
    B.plan.taskQueue={steps={{stage={itemRequirements={{targetId=102}}}}}};refresh();eq(T.gear.shown,false)
    B.plan.taskQueue=nil;B.char.junk={[102]=true};B.state.bags[102]=2;refresh();eq(T.gear.shown,false)
    B.char.junk[102]=false;second.quality=0;B.state.bags[102]=3;refresh();eq(T.gear.shown,false)
    eq(B.Gear.Upgrade(second,B.state),nil);eq(B.char.junk[102],false)
    local two,one,off=item(200,10),item(201,5),item(202,20)
    two.equipLoc,one.equipLoc,off.equipLoc="INVTYPE_2HWEAPON","INVTYPE_WEAPON","INVTYPE_SHIELD"
    two.weaponDPS,one.weaponDPS=1,1
    B.state.equipment={[16]=two};B.state.bags={};B.state.bagEquipment={};refresh()
    B.state.bags={[201]=1,[202]=1};B.state.bagEquipment={one,off};refresh();eq(T.gear.shown,false)
    one.stats.ITEM_MOD_STRENGTH_SHORT=15;B.state.bags[201]=2;refresh();eq(T.gear.advice.slot,16)
    C_Item.EquipItemByName=function(link,slot) eq(link,one.link);eq(slot,16);equips=equips+1 end
    T.gear.scripts.OnHyperlinkClick(T.gear,"item:201",one.link,"RightButton")
    B.menu["装备这件"].callback();eq(equips,2)
    B.finish()
end)

test("Shortest Path 的实走步骤跟随路段更新且保留玩家改道",function()
    local B=ready()
    assert(loadfile("Planner/ShortestPath.lua"))("AiLeveling",B)
    local provider=B.ShortestPath
    local old=ShortestPathForever
    local expectedHandins
    local calls,owner,listen,legs=0,nil,nil,{{mode="walk",text="走到地铁入口",seconds=42},{mode="tram",text="乘地铁前往铁炉堡",seconds=71}}
    ShortestPathForever={API={
        Subscribe=function(fn) listen=fn end,
        CurrentStop=function(key) return owner==key and 1 or nil end,
        JourneyState=function() return {owner=owner,busy=owner~=nil} end,
        NavigateRoute=function(key,stops)
            calls=calls+1;owner=key
            eq(stops[1].map,B.action.position.map);eq(stops[1].kind,B.action.kind);assert(stops[1].hold)
            eq(stops[1].handins and table.concat(stops[1].handins,","),expectedHandins)
            return true
        end,
        Journey=function() return {owner=owner,legs=legs,secondsLeft=113} end,
        Cancel=function(key) eq(owner,key);owner=nil end}}
    B.Navigation.Near=function() return false end
    local legacy={kind="transit",questAction=B.action}
    provider:Sync(legacy);provider:Sync(B.action)
    eq(calls,1);eq(provider:For(legacy),B.action)
    B.UI:RenderTracker()
    local T=B.UI.tracker
    eq(T.journeyRows[1].title.value,"走到地铁入口");eq(T.journeyRows[2].title.value,"乘地铁前往铁炉堡")
    eq(T.model.journey.steps[3].action,B.action)
    table.remove(legs,1);listen({leg=true});B.UI:RenderTracker()
    eq(T.journeyRows[1].title.value,"乘地铁前往铁炉堡");eq(calls,1)
    owner="玩家";listen({changed=true});provider:Sync(legacy);eq(provider.owned,nil);eq(calls,1)
    provider:Sync(nil);provider:Sync(legacy);eq(owner,"玩家");eq(calls,1)
    owner=nil;listen({ended=true});provider:Sync(legacy);eq(calls,2)
    B.action={kind="turnin",questId=1,position=B.action.position};B.state.quests[1].ready=true
    local colocated={[2]={position=B.action.position},[3]={position={map=3,x=.6,y=.5}}}
    B.TaskGuide={ReadyTurnIns=function() return colocated end}
    expectedHandins="1,2";provider:Sync(B.action);eq(calls,3)
    B.state=setmetatable({},{__index=B.state});provider:Sync(B.action);eq(calls,3)
    colocated[2]=nil;B.state=setmetatable({},{__index=B.state});expectedHandins="1"
    provider:Sync(B.action);eq(calls,4)
    B.char.paused=true;provider:Sync(legacy);eq(owner,nil);eq(provider.journey,nil)
    ShortestPathForever=old;B.finish()
end)

end
