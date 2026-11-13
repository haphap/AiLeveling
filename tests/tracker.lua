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
    local B=ready();assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
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
    B.action.targetId=2592;B.action.itemGain=60;B.action.text="还需收集60块毛料"
    B.UI:RenderTracker()
    local model=B.UI.tracker.model
    eq(model.objectives[#model.objectives].have,60);eq(model.objectives[#model.objectives].need,120)
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
    local B=ready();local T=B.UI.tracker
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
    eq(T.objectives[1].check.value,"□");eq(T.progressRatio,0.3);eq(T.progress.shown,true)
    assert(T.rows[1].title.color[2]>T.rows[1].title.color[1])
    assert(T.rows[2].title.color[1]>T.rows[2].title.color[2])
    assert(T.queueScroll.width+16<=T.queuePanel.width);assert(T.card.width<=300)
    eq(T.location.width+T.area.width+12,T.card.width);eq(T.career.width,T.card.width)
    local goal=T.objectives[1]
    eq(goal.count.width,math.ceil(goal.count:GetStringWidth())+6)
    eq(goal.text.width,goal.width-goal.count.width-42)
    assert(T.footer.value:find("经验 1250",1,true));assert(T.footer.value:find("路程 2分15秒",1,true))
    assert(T.rows[1].metrics:find("经验 0",1,true));assert(T.rows[1].metrics:find("路程 0秒",1,true))
    assert(T.rows[2].metrics:find("路程 1小时01分",1,true))
    assert(T.rows[1].title.fontSize>=15);eq(T.rows[1].progress.fontSize,B.UI.fontSizes.caption)
    assert(T.rows[1].progress.color[2]>=0.75);eq(T.queuePanel.surface,nil);eq(T.card.surface,nil)
    eq(T.rows[1].title.fontFlags,"OUTLINE")
    eq(T.rows[2].objectives[1].text.value,"物品");eq(T.rows[2].objectives[1].count.value,"2/4");eq(T.rows[1].enabled,true)
    B.state.quests[3].objectives[1].text="收集物品";B.state.quests[3].objectives[1].type="item";B.UI:RenderTracker()
    eq(T.rows[2].objectives[1].text.value,"收集物品");eq(T.rows[2].objectives[1].count.value,"2/4")
    eq(T.rows[2].objectives[1].check.value,"□");assert(T.rows[2].objectives[1].text.color[1]>T.rows[2].objectives[1].text.color[2])
    local shown,inserted,opened,modified,focused=nil,nil,nil,false,true
    C_QuestLog.GetLogIndexForQuestID=function(id) return id<=3 and id+10 end
    QuestMapFrame_OpenToQuestDetails=function(id) shown=id end
    GetQuestLink=function(id) return "|Hquest:"..id..":20|h[任务]|h" end
    IsModifiedClick=function() return modified end
    ChatFrameUtil={InsertLink=function(link) inserted=link;return focused end,OpenChat=function(link) opened=link end}
    eq(T.rows[1].clicks[2],"RightButtonUp")
    T.rows[1].scripts.OnClick(nil,"LeftButton");eq(shown,2);eq(B.char.locked,nil)
    T.questTitle.scripts.OnClick(nil,"LeftButton");eq(shown,1);eq(B.char.locked,nil)
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
    local defer=B.menu["暂缓此任务"].callback
    T.rows[2].questId=1;defer();eq(B.char.skipped[3],true);eq(B.char.skipped[1],nil)
    eq(T.tools,nil)
    B.finish()
end)
test("后续任务按真实日志区分已接和未接且接取后更新进度",function()
    local B=ready(true);local T=B.UI.tracker
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
    assert(B.UI.Browser.detail.value:find("|Hquest:4:0|h",1,true))
    row.scripts.OnClick(row,"LeftButton")
    eq(B.UI.Plan.preview.questId,4);eq(B.char.locked,nil)
    local tooltip={}
    GameTooltip={SetOwner=function() end,SetText=function(_,v) tooltip[#tooltip+1]=v end,
        AddLine=function(_,v) tooltip[#tooltip+1]=v end,Show=function() end,Hide=function() end}
    row.scripts.OnEnter(row);assert(table.concat(tooltip,"\n"):find("未接任务",1,true))
    row.scripts.OnLeave(row)
    row.scripts.OnClick(row,"RightButton")
    assert(B.menu["优先做此任务"].enabled);B.menu["优先做此任务"].callback();eq(B.char.locked,4)
    B.Selection:Automatic();eq(B.char.locked,nil)
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
    eq(T.alongLabel.value,"顺路可做 · 1")
    starter.position.y=0.58;B.UI:RenderTracker();eq(T.alongLabel.shown,false)
    starter.position.y=0.5;B.UI:RenderTracker();eq(T.alongLabel.shown,true)
    eq(T.model.questId,1);eq(B.state.locked,1)
    -- Nearby work and ready hand-ins share the optional section without changing the main action.
    starter.position.x=0.525;starter.kind="objective";starter.objectiveIndex=1
    B.state.quests[4]={objectives={{type="item",text="收集 1/5",numRequired=5,numFulfilled=1}}}
    B.UI:RenderTracker();eq(T.model.rows[1].along,true);eq(T.rows[1].objectives[1].count.value,"1/5");eq(T.rows[1].progress.shown,false)
    local notice=T.nearby
    eq(notice.shown,true);eq(notice.body.value,"收集 · 还差 4")
    notice.scripts.OnClick(nil,"RightButton");B.UI:UpdateNearby();eq(notice.shown,false);eq(B.state.skipped[4],nil)
    local position,mainPoint=B.state.position,B.action.position
    B.state.position={map=1,x=0.56,y=0.5};starter.position.x=0.58;B.action.position={map=1,x=0.65,y=0.5}
    B.UI:UpdateNearby();eq(notice.shown,true)
    notice.scripts.OnClick(nil,"RightButton")
    B.state.position.x=0.64;starter.position.x=0.66;B.action.position.x=0.75
    B.UI:UpdateNearby();eq(notice.shown,false)
    B.state.position.map=2;starter.position.map=2;B.action.position.map=2
    B.UI:UpdateNearby();eq(notice.shown,true)
    notice.scripts.OnClick(nil,"LeftButton");eq(B.Navigation.manual.x,0.66);eq(B.Navigation.manual.title,"收集 · 还差 4")
    eq(B.char.locked,nil);eq(B.state.locked,1);eq(B.action.questId,1);eq(notice.shown,false)
    B.Navigation.manual=nil;B.state.position=position;B.action.position=mainPoint;starter.position={map=1,x=0.525,y=0.5}
    B.UI:UpdateNearby();eq(notice.shown,true)
    B.char.paused=true;B.UI:UpdateNearby();eq(notice.shown,false);B.char.paused=false
    B.state.quests[4].objectives[1].finished=true;B.UI:RenderTracker();eq(T.alongLabel.shown,false);eq(notice.shown,false)
    starter.kind="turnin";starter.objectiveIndex=nil;B.state.quests[4].ready=true
    B.UI:RenderTracker();eq(T.rows[1].status,"可交付");eq(T.rows[1].along,true);eq(B.action.questId,1)
    B.state.quests[4]=nil;starter.kind="accept"
    B.state.locked=nil;B.Navigation.Distance=distance;starter.position=nil;B.plan.taskOrder=B.plan.taskChoices
    B.state.quests[4]={title="真实接取的任务",objectives={{text="收集 1/5",numFulfilled=1,numRequired=5}}}
    B.UI:RenderTracker()
    eq(T.rows[3].status,"已接取");eq(T.rows[3].objectives[1].count.value,"1/5");eq(T.rows[3].objectiveFrame.shown,true)
    eq(T.model.acceptedCount,3);eq(T.model.unacceptedCount,0)
    eq(T.rows[3].along,false);eq(T.rows[3].parent,T.queueChild);eq(T.alongScroll.shown,false)
    B.state.quests[4].ready=true;B.UI:RenderTracker();eq(T.rows[3].status,"可交付")
    local suggestion={id="reference:3065",dungeonId="reference:3065",kind="dungeon",reference=true,requiresAcceptance=true,
        title="领主大厅",rewards={count=5,prepare=1},remainingXP=13300,timing={seconds=150}}
    B.refreshAt=nil;B.plan.revision=B.state.revision;B.plan.suggestedDungeon=suggestion;B.UI:RenderTracker()
    eq(T.rows[1].dungeonId,nil);eq(T.model.questId,1)
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
    B.plan.suggestedDungeon=nil;B.UI:RenderTracker();eq(T.rows[1].dungeonId,nil)
    B.plan.dungeonChoices={suggestion}
    eq(B.UI.Plan.Rows(B.plan)[1],suggestion);assert(B.Selection.CanChoose(suggestion,B.plan.revision))
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
    local B=ready();local T=B.UI.tracker
    B.state.revision=B.state.revision+1;T.rows[1].scripts.OnClick(nil,"RightButton")
    eq(B.menu["优先做此任务"].enabled,false);eq(B.char.locked,nil)
    B.state.quests[2]=nil;B.state.quests[3]=nil;B.plan.taskChoices={};B.plan.taskOrder={}
    B.state.quests[1].objectives={};B.UI:RenderTracker()
    eq(T.objectives[1].shown,false);eq(T.rows[1].shown,false);eq(T.queueScroll.shown,false)
    B.state.quests[1].objectives={{text="旧目标",finished=true}};B.action.objectiveIndex=1
    B.UI:RenderTracker();eq(T.model.questId,nil);eq(B.UI.title.value,"正在更新行程")
    eq(#T.model.rows,0);eq(B.UI.QuestStatus(B.state,1,B.plan),"已接取")
    B.state.quests[1].ready=true;B.UI:RenderTracker();eq(#T.model.rows,0);eq(B.UI.QuestStatus(B.state,1,B.plan),"可交付")
    B.action.itemGain=2;B.action.targetId=500;B.UI:RenderTracker();eq(T.model.questId,1)
    B.action.itemGain=nil;B.action.kind="accept";B.UI:RenderTracker();eq(T.model.questId,nil)
    B.action.kind="turnin";B.UI:RenderTracker();eq(T.model.questId,1)
    B.state.quests[1].ready=false;B.UI:RenderTracker();eq(T.model.questId,nil)
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
    B.action={title="当前任务",kind="objective",position={approximate=true}}
    U:SetNavigation(100,0.7,true);eq(U.tracker.navTitle.value,"当前任务 · 区域参考点")
    B.settings.arrow=false;U:SetNavigation(100,0.7,true);eq(U.navFrame.shown,false)
    B.settings.arrow=true;U:SetNavigation(nil);eq(U.navFrame.shown,false)
    U.navFrame.scripts.OnDragStop();eq(B.settings.navigationPosition[3],25)
    B:NormalizeSettings(B.settings);eq(B.settings.navigationPosition[3],25)
    B:RestoreSettings();eq(B.settings.navigationPosition,nil)
    assert(loadfile("Planner/Travel.lua"))("AiLeveling",B)
    local goal={kind="accept",questId=4,title="新的任务",position={map=2,x=0.5,y=0,entityName="接取人"}}
    local transit={kind="transit",mode="tram",questId=4,title="乘地铁前往铁炉堡",publicTransit=true,
        departure={map=1,x=0.1,y=0},position={map=2,x=0.2,y=0},departureRadius=40,
        fromName="暴风城地铁入口",travelSeconds=100,travelWait=40,travelRide=60}
    B.Navigation.Distance=function(_,a,b) if a and b and a.map==b.map then return math.abs(a.x-b.x)*700 end end
    B.state.position={map=1,x=0,y=0};B.state.runSpeed=7
    B.Navigation.actions={transit,goal};B.Navigation.index=1;B.action=transit
    U:RenderTracker();local T=U.tracker;local journey=T.model.journey
    eq(U.title.value,"新的任务");eq(T.model.kind,"accept");eq(T.action,transit)
    eq(#journey.steps,4);eq(journey.seconds,140);eq(journey.distance,280)
    eq(journey.steps[1].title,"走到 暴风城地铁入口");eq(journey.steps[2].detail,"平均等候 0:40 · 乘坐 1:00")
    eq(journey.steps[4].title,"接取 新的任务");eq(T.journey.shown,true)
    T.journeyHeader.scripts.OnClick();eq(T.journeyRows[1].shown,false);eq(U.title.value,"新的任务")
    T.journeyHeader.scripts.OnClick();eq(T.journeyRows[1].shown,true)
    B.state.position=transit.departure;T.journey.scripts.OnUpdate(nil,1)
    eq(#T.model.journey.steps,3);eq(T.model.journey.seconds,130)
    transit.atDeparture=true;B.state.position={map=1,x=0.2,y=0};U:RenderTracker()
    eq(#T.model.journey.steps,3);eq(T.model.journey.steps[1].kind,"tram")
    B.char.paused=true;U:RenderTracker();eq(T.journey.shown,false);B.char.paused=false
    transit.mode="flight";B.Transport.flight={action=transit,observedStart=true,duration=100,started=5}
    B.action={kind="flight",title="正在飞行"};U:RenderTracker()
    eq(T.model.journey.seconds,125);eq(T.model.journey.steps[1].detail,"飞行中")
    B.Navigation.index=2;B.action=goal;U:RenderTracker();eq(T.journey.shown,false);eq(T.model.questId,4)
    eq(B.state.quests[4],nil);eq(B.state.completed[4],nil)
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
    T.questTitle.scripts.OnClick(nil,"RightButton");assert(B.menu["暂缓此任务"]);eq(B.menu["忽略维修"],nil)
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
    local lines=table.concat(B.UI.Plan:Lines(),"\n")
    assert(lines:find("建议放弃",1,true));assert(lines:find("在任务日志中可放弃",1,true))
    B.finish()
end)

test("交错行程按任务数汇总并显示每个目标与交付步骤",function()
    local B=ready();local a,b=B.plan.taskChoices[1],B.plan.taskChoices[3]
    B.state.quests[3].level=9;B.state.quests[3].objectives[1].type="item"
    local oa={kind="objective",questId=1,text="目标甲"};local ob={kind="objective",questId=3,text="目标乙",position={entityName="林地"}}
    B.plan.taskQueue={stagePlan=true,taskCount=2,seconds=180,low=180,high=180,xp=200,xpKnown=true,
        steps={{choice=a,stage=oa},{choice=b,stage=ob},{choice=a,stage={kind="turnin"}},{choice=b,stage={kind="turnin"}}}}
    a.executionAction=oa;a.executionTiming={seconds=80,low=80,high=80};B.action=oa
    B.UI:RenderTracker();assert(B.UI.tracker.objectives[1].text.value:find("狗头人",1,true))
    assert(not B.UI.body.value:find("先完成附近目标，再集中交付",1,true))
    eq(B.UI.tracker.model.questId,1)
    eq(#B.UI.tracker.model.rows,0) -- The next task appears once, in the Then section.
    eq(B.state.quests[3].ready,nil)
    local T=B.UI.tracker
    assert(T.thenText.value:find("已接取",1,true));eq(T.thenButton.title.value,"[9] 后续目标")
    eq(T.thenButton.title.color[1],B.UI.colors.gold[1]);assert(T.thenButton.progress.value:find("林地",1,true))
    eq(T.thenButton.objectives[1].text.value,"物品");eq(T.thenButton.objectives[1].count.value,"2/4")
    eq(T.thenButton.objectives[1].text.color[1],B.UI.colors.purple[1])
    eq(T.thenText.shown,true);eq(T.thenButton.questId,3)
    assert(T.thenText.point[3]>T.queuePanel.point[3],"下一步应在其他任务之前")
    B.action=ob;B.UI:RenderTracker();eq(T.thenButton.title.value,"当前任务")
    eq(T.thenButton.status,"已接取");eq(T.thenButton.progress.value,"完成后交付")
    B.char.paused=true;B.UI:RenderTracker();eq(T.thenText.shown,false);eq(T.thenButton.shown,false)
    B.finish()
end)

test("分散交付点明确现在就近交和等同NPC任务一起交并跟随真实导航",function()
    local B=ready();assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
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
        if row.questId==3 then eq(row.atStop,false);eq(row.parent,T.queueChild);eq(row.progress.shown,false);eq(row.objectiveFrame.shown,true) end
    end
    B.state.locked=nil;B.action={kind="objective",questId=3,title=c.title};B.UI:RenderTracker()
    eq(T.model.deliverySummary,"同组还差 1 项，做完一起交")
    B.action={kind="service",title="维修"};B.UI:RenderTracker();eq(T.model.deliverySummary,nil)
    B.action=ta;B.char.paused=true;B.UI:RenderTracker();eq(T.model.deliverySummary,nil)
    B.finish()
end)

test("职业提醒随可学技能和待接任务更新，稍后保留行程并只导航本职业训练师",function()
    local B=ready();assert(loadfile("Services.lua"))("AiLeveling",B)
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
    eq(T.career.shown,true);assert(T.career.text.value:find("圣光术 · 等级 4",1,true));assert(T.career.text.value:find("圣洁之书",1,true))
    eq(T.model.questId,1);eq(T.objectives[1].count.value,"3/10")
    local clicked;SetItemRef=function(link) clicked=link end
    T.career.view:Click();B.menu["圣光术 · 等级 4 · 22级"].callback();eq(clicked,"spell:101")
    local questClick=B.UI.QuestClick;B.UI.QuestClick=function(_,id) clicked=id end
    B.menu["待接：圣洁之书"].callback();eq(clicked,1641)
    T.career.scripts.OnHyperlinkClick(T.career,"quest:1641:12","","LeftButton");eq(clicked,1641);B.UI.QuestClick=questClick
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
    B.finish()
end)

test("新获装备按次序提醒，接交任务显示对应奖励且换装只处理该件",function()
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
    eq(T.gear.text.value,"装备提升："..bag.link.."  ·  +50%  ·  头部")
    eq(T.gear.equip.text.value,"装备它");eq(T.gear.ignore.text.value,"忽略这件")
    eq(T.gear.shade.color[1],0.90);eq(T.gear.shade.color[4],0.10)
    eq(B.Gear.UpgradeText({upgrade={oldScore=1000,delta=1}}),"+<1%")
    eq(B.Gear.UpgradeText({upgrade={oldScore=0,delta=1}}),"新")
    eq(T.reward.shown,false);eq(T.model.questId,1);eq(T.objectives[1].count.value,"3/10")
    B.action.kind="accept";refresh()
    eq(T.reward.shown,true);assert(T.reward.text.value:find(reward.link,1,true))
    assert(T.reward.text.value:find("交还时",1,true));eq(T.reward.icon.shown,false)
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
    T.gear.close:Click();eq(T.gear.shown,false);eq(next(B.char.ignoredGear),nil)
    refresh();eq(T.gear.shown,false)
    B.state.bags[100]=3;refresh();eq(T.gear.shown,true)
    T.gear.ignore:Click();eq(T.gear.shown,false);eq(B.char.ignoredGear["item:100"],true)
    B.state.bags[100]=4;refresh();eq(T.gear.shown,false)
    B.UI:TrackerMenu(B.UI.frame);B.menu["恢复装备提醒"].callback();eq(T.gear.shown,false)
    B.state.bags[100]=5;refresh();eq(T.gear.shown,true)
    B.combat(true);B.UI:RenderTracker();eq(T.gear.equip.enabled,false)
    eq(B.Gear:EquipAdvice(T.gear.advice),false)
    B.combat(false);B.UI:RenderTracker()
    local equips=0
    C_Item.EquipItemByName=function(link,slot)
        eq(link,bag.link);eq(slot,1);equips=equips+1
        B.state.equipment[slot]=bag;B.state.bagEquipment={old};B.state.bags={[99]=1}
    end
    T.gear.equip:Click();eq(equips,1);eq(T.gear.shown,false)
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
    local two,one,off=item(200,10),item(201,5),item(202,20)
    two.equipLoc,one.equipLoc,off.equipLoc="INVTYPE_2HWEAPON","INVTYPE_WEAPON","INVTYPE_SHIELD"
    two.weaponDPS,one.weaponDPS=1,1
    B.state.equipment={[16]=two};B.state.bags={};B.state.bagEquipment={};refresh()
    B.state.bags={[201]=1,[202]=1};B.state.bagEquipment={one,off};refresh();eq(T.gear.shown,false)
    one.stats.ITEM_MOD_STRENGTH_SHORT=15;B.state.bags[201]=2;refresh();eq(T.gear.advice.slot,16)
    C_Item.EquipItemByName=function(link,slot) eq(link,one.link);eq(slot,16);equips=equips+1 end
    T.gear.equip:Click();eq(equips,2)
    B.finish()
end)

end
