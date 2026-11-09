return function(test,eq,setup)
local function ready()
    local B=setup()
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
test("同NPC任务连续显示整组真实进度并保持行宽与点击",function()
    local B=ready();assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    for _,id in ipairs({1,3}) do
        B.plan.taskChoices[id].stages={{kind="turnin",position={map=1,x=0,y=0,entityKind="npc",entityId=900,entityName="治安官"}}}
    end
    B.state.quests[3].ready=true;B.UI:RenderTracker()
    local T=B.UI.tracker
    eq(#T.model.rows,3);eq(T.model.rows[1].questId,1);eq(T.model.rows[2].questId,3);eq(T.model.rows[3].questId,2)
    eq(T.rows[1].group.value,"治安官 · 已完成 1/2")
    eq(T.rows[2].group.shown,false);eq(T.rows[2].status.value,"可交付")
    eq(T.rows[2].progress.value,"已完成 · 等同组任务一起交付")
    assert(T.model.hint:find("先做完剩余任务",1,true))
    eq(T.rows[1].number.point[3],T.rows[1].title.point[3]);eq(T.queuePanel.width,T.card.width)
    T.rows[2].scripts.OnClick();eq(B.char.locked,3)
    B.state.quests[1].ready=true;B.UI:RenderTracker()
    eq(T.rows[1].group.value,"治安官 · 已完成 2/2");eq(T.rows[1].progress.value,"全部完成 · 一起交付")
    assert(loadfile("UI/Plan.lua"))("AiLeveling",B)
    local lines=table.concat(B.UI.Plan:Lines(),"\n");assert(lines:find("集中交付 · 治安官 · 已完成 2/2",1,true))
    B.state.quests[3]=nil;B.UI:RenderTracker();eq(T.rows[1].group.shown,false)
    B.finish()
end)
test("原生可交付但共用物品不足时显示补齐提示和整批数量",function()
    local B=ready();assert(loadfile("Planner/TaskGuide.lua"))("AiLeveling",B)
    B.state.bags={[2592]=60};B.state.quests[1].ready=true;B.state.quests[3].ready=true
    for _,id in ipairs({1,3}) do
        B.plan.taskChoices[id].stages={{kind="turnin",recipient={entityKind="npc",entityId=99,entityName="收件人"}}}
    end
    B.plan.taskChoices[1].itemShortage=true
    B.action.targetId=2592;B.action.itemGain=60;B.action.text="还需收集60块毛料"
    B.UI:RenderTracker()
    local model=B.UI.tracker.model
    eq(model.objectives[#model.objectives].have,60);eq(model.objectives[#model.objectives].need,120)
    assert(model.hint:find("1/2",1,true));eq(model.rows[1].progress,"共用物品不足 · 先补齐再一起交付")
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
    eq(model.rows[2].progress,"等待前项交付后再收集")
    eq(model.rows[1].groupTitle,"收件人 · 已完成 1/2")
    assert(loadfile("UI/Plan.lua"))("AiLeveling",B)
    assert(table.concat(B.UI.Plan:Lines(),"\n"):find("分批交付 · 收件人",1,true))
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
    B.action=actions[1];B.UI:RenderTracker()
    assert(B.UI.body.value:find("消灭狗头人",1,true))
    assert(B.UI.body.value:find("狗头人营地",1,true));assert(B.UI.body.value:find("60.0, 50.0",1,true))
    eq(B.UI.title.value,"当前任务");eq(T.objectives[1].count.value,"3/10");eq(T.objectives[1].ratio,0.3)
    eq(#T.model.rows,2);eq(T.rows[1].title.value,"后续交付");eq(T.rows[1].status.value,"可交付")
    eq(T.queuePanel.width,T.card.width)
    eq(T.rows[1].number.fontSize,T.rows[1].title.fontSize)
    eq(T.rows[1].number.point[3],T.rows[1].title.point[3])
    assert(T.queueScroll.width+16+24<=T.queuePanel.width)
    assert(B.UI.body.value:find("经验 1250",1,true));assert(B.UI.body.value:find("路程 2分15秒",1,true))
    assert(T.rows[1].metrics.value:find("经验 0",1,true));assert(T.rows[1].metrics.value:find("路程 0秒",1,true))
    assert(T.rows[2].metrics.value:find("路程 1小时01分",1,true))
    assert(T.rows[1].title.fontSize>=15);assert(T.rows[1].progress.fontSize>=13)
    assert(T.rows[1].progress.color[1]>=0.75);assert(T.queuePanel.color[4]>=0.9)
    eq(T.rows[2].progress.value,"物品 2/4");eq(T.rows[1].enabled,true)
    B.state.quests[3].objectives[1].text="收集物品";B.UI:RenderTracker()
    eq(T.rows[2].progress.value,"收集物品 · 2/4")
    T.rows[1].scripts.OnClick();eq(B.char.locked,2)
    B.finish()
end)
test("后续任务按真实日志区分已接和未接且接取后更新进度",function()
    local B=ready();local T=B.UI.tracker
    B.plan.taskChoices[#B.plan.taskChoices+1]={id="task:4",questId=4,kind="task",title="未接任务",
        actions={{questId=4,kind="accept",title="未接任务"}}}
    B.UI:RenderTracker()
    eq(T.rows[2].status.value,"已接取");eq(T.rows[3].status.value,"未接取")
    eq(T.rows[3].progress.value,"先接取，再推进任务目标")
    eq(T.model.acceptedCount,2);eq(T.model.unacceptedCount,1)
    assert(T.queueLabel.value:find("未接取 1",1,true))
    B.state.quests[4]={title="真实接取的任务",objectives={{text="收集 1/5",numFulfilled=1,numRequired=5}}}
    B.UI:RenderTracker()
    eq(T.rows[3].status.value,"已接取");eq(T.rows[3].progress.value,"收集 1/5")
    eq(T.model.acceptedCount,3);eq(T.model.unacceptedCount,0)
    B.state.quests[4].ready=true;B.UI:RenderTracker();eq(T.rows[3].status.value,"可交付")
    B.finish()
end)
test("接取状态标签随放弃和暂缓更新且大字号仍留出标题空间",function()
    local B=ready();local T=B.UI.tracker
    eq(T.rows[1].progress.value,"目标已完成，前往交付")
    B.state.quests[3]=nil;B.UI:RenderTracker()
    eq(T.rows[2].status.value,"未接取");eq(T.model.rows[2].kind,"accept")
    eq(T.rows[2].progress.value,"先接取，再推进任务目标")
    B.state.skipped={[3]=true};B.UI:RenderTracker()
    eq(T.rows[2].status.value,"未接·暂缓");eq(T.rows[2].enabled,false)
    T.rows[2].title.measuredHeight=90;T.rows[2].progress.measuredHeight=50
    B:SetOption("fontScale",1.2)
    local row=T.rows[2]
    eq(row.title.width,row.width-32)
    assert(32+row.progress.width+row.statusBack.width+8<=row.width)
    assert(-row.status.point[3]>-row.title.point[3]+row.title:GetStringHeight())
    assert(-row.metrics.point[3]>=-row.progress.point[3]+row.progress:GetStringHeight())
    assert(row.height>=-row.metrics.point[3]+row.metrics:GetStringHeight())
    assert(row.metrics.value:find("经验 —",1,true));assert(row.metrics.value:find("路程 —",1,true))
    B.finish()
end)
test("未来行动中的交付预期不能把未接任务显示成已接或可交付",function()
    local B=ready();local T=B.UI.tracker
    B.plan.best={actions={{questId=1,kind="objective"},{questId=99,kind="turnin",title="未来交付任务"}}}
    B.UI:RenderTracker()
    eq(T.model.rows[1].questId,99);eq(T.rows[1].status.value,"未接取")
    eq(T.model.rows[1].accepted,false);eq(T.model.unacceptedCount,1)
    eq(T.model.rows[1].kind,"accept");eq(T.rows[1].progress.value,"先接取，再推进任务目标")
    B.finish()
end)
test("原生更新后清除旧目标和旧任务行且拒绝过期任务点击",function()
    local B=ready();local T=B.UI.tracker
    B.state.revision=B.state.revision+1;T.rows[1].scripts.OnClick();eq(B.char.locked,nil)
    B.state.quests[2]=nil;B.state.quests[3]=nil;B.plan.taskChoices={};B.plan.taskOrder={}
    B.state.quests[1].objectives={};B.UI:RenderTracker()
    eq(T.objectives[1].shown,false);eq(T.rows[1].shown,false);eq(T.queueScroll.shown,false)
    B.finish()
end)
test("经验条使用真实角色比例且长文可滚动而不盖住后续列表",function()
    local B=ready();local T=B.UI.tracker
    B.state.xp=250;B.state.maxXP=1000;B.UI.title.measuredHeight=100
    B.UI:RenderTracker();assert(T.experience.value:find("25%%"))
    assert(T.currentChild.height>T.currentScroll.height)
    assert(-T.queueLabel.point[3]>42+T.card.height)
    B.finish()
end)
test("暂停飞行手动导航保持真实当前类型且不自动跳过任务",function()
    local B=ready();local T=B.UI.tracker
    B.char.paused=true;B.UI:RenderTracker();eq(T.step.value,"已暂停");eq(B.UI.title.value,"当前任务");eq(#T.model.rows,2)
    B.char.paused=false;B.action={kind="flight",title="正在飞行"};B.UI:RenderTracker();eq(T.step.value,"飞行中")
    B.Navigation.manual={};B.action={kind="manual",title="手动目的地"};B.UI:RenderTracker();assert(T.queueLabel.value:find("任务列表",1,true))
    B.finish()
end)
test("可交付任务的交通步骤保留航线票价说明",function()
    local B=ready();B.action={kind="transit",mode="flight",questId=2,text="手动选择落地点；实际票价 110 铜。"}
    B.UI:RenderTracker();eq(B.UI.tracker.step.value,"交通")
    assert(B.UI.body.value:find("实际票价 110 铜",1,true));B.finish()
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
    B.finish()
end)
test("重排普通步骤和队列不触碰战斗中安全物品属性",function()
    local B=ready();local writes=0
    for _,button in ipairs(B.QuestAssist.buttons) do writes=writes+button.attributeWrites end
    B.combat(true);B.UI:Combat(true);B.UI:RenderTracker();eq(B.UI.tracker.currentScroll.shown,false)
    B:SetOption("fontScale",1.2)
    local after=0;for _,button in ipairs(B.QuestAssist.buttons) do after=after+button.attributeWrites end
    eq(after,writes);B.finish()
end)
test("商店事件触发刷新且主服务卡片显示实时全修费用与金币缺口",function()
    local B=ready();assert(loadfile("Merchant.lua"))("AiLeveling",B)
    assert(loadfile("Planner/Supplies.lua"))("AiLeveling",B)
    B.action={kind="service",serviceKind="repair",npcId=78,title="铁匠",serviceGoal={durability=0.2}}
    B.state.merchant={npcId=78,canRepair=true,repairCost=123,items={}};B.state.money=100
    B.UI:RenderTracker();assert(B.UI.body.value:find("自费全修：123 铜",1,true));assert(B.UI.body.value:find("还差 23 铜",1,true))
    local T=B.UI.tracker;eq(T.skip.text.value,"忽略维修");eq(T.queuePanel.shown,true);eq(#T.model.rows,3)
    B.action.questId=1
    T.skip.scripts.OnClick();eq(B.char.ignoreRepair,true);assert(B.refreshAt)
    eq(B.char.skipped[1],nil);eq(B.state.quests[1].objectives[1].finished,nil)
    B.action={kind="objective",questId=1,title="当前任务"};B.UI:RenderTracker();eq(T.skip.text.value,"暂缓")
    local event=B.frame.scripts.OnEvent
    event(nil,"MERCHANT_SHOW");eq(B.Merchant.open,true);assert(B.refreshAt)
    for _,name in ipairs({"MERCHANT_UPDATE","MERCHANT_FILTER_ITEM_UPDATE"}) do B.refreshAt=nil;event(nil,name);assert(B.refreshAt) end
    event(nil,"MERCHANT_CLOSED");eq(B.Merchant.open,false)
    B.Merchant:Snapshot(B.state);B.UI:RenderTracker();assert(not B.UI.body.value:find("123 铜",1,true))
    B.finish()
end)
test("原生服务页可切换旅店与训练项目插入取消且页签隐藏正确",function()
    local B=ready()
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
    B.char.serviceStop.afterTask={kind="turnin",questId=42,title="旧换绑条件",turnIns=0}
    B:NormalizeCharacter(B.char);assert(B.char.serviceStop);eq(B.char.serviceStop.afterTask,nil)
    U.cancel.scripts.OnClick();eq(B.char.serviceStop,nil)
    U.mode.scripts.OnClick();eq(U.kind,"train");U.mode.scripts.OnClick();eq(U.kind,"learn")
    B.state.money=20;B.state.trainer={npcId=78,name="训练师",rows={{name="新技能",sub="等级 1",key="新技能\031等级 1",status="available",cost=30,playerTraining=true}}}
    B.UI:SelectTab(7);assert(B.UI.detailText.value:find("还差 10 铜",1,true))
    U.choose.scripts.OnClick();eq(B.char.serviceStop.kind,"train");assert(B.char.serviceStop.learnKey)
    B.action=B.Services.Build({serviceStop=B.char.serviceStop,position=B.state.position}).fallback
    B.UI:RenderTracker();eq(B.UI.tracker.step.value,"训练")
    B.UI:SelectTab(5);eq(U.frame.shown,false);eq(B.UI.Settings.frame.shown,true)
    B:NormalizeCharacter(B.char);assert(B.char.serviceStop);B.char.serviceStop.position.x=2
    B:NormalizeCharacter(B.char);eq(B.char.serviceStop,nil)
    B.finish()
end)
test("任务界面保留目标与进度并隐藏估时和算法说明",function()
    local B=ready();local choice=B.plan.taskChoices[1]
    choice.work={known=1,missing=0,initial=1,seconds=100,low=50,high=250}
    B.UI:RenderTracker();assert(not B.UI.body.value:find("目标起步粗估",1,true))
    choice.timing={seconds=120,low=70,high=280,initial=true,coarse=true}
    B.UI:RenderTracker();assert(not B.UI.body.value:find("预计移动",1,true));assert(not B.UI.body.value:find("粗估",1,true))
    eq(B.UI.tracker.objectives[1].count.value,"3/10");eq(B.UI.title.value,"当前任务")
    assert(not B.UI.body.value:find("有效进度样本",1,true))
    assert(loadfile("UI/Plan.lua"))("AiLeveling",B)
    B.UI.Plan.preview=choice
    local text=table.concat(B.UI.Plan:Lines(),"\n")
    assert(not text:find("预计移动",1,true));assert(not text:find("执行耗时视为相当",1,true));assert(not text:find("直线距离",1,true))
    assert(not text:find("耗时缺口",1,true));assert(not text:find("执行约",1,true))
    B.finish()
end)
test("低价值建议保留接取状态手动入口并为换行留出空间",function()
    local B=ready();local c=B.plan.taskChoices[3]
    c.lowValue={suggestion="建议放弃",reason="低经验、奖励无提升、无任务线关联。"}
    B.plan.taskChoices[4]={questId=4,kind="task",actions={{kind="accept",questId=4,title="有效新任务"}}}
    B.UI:RenderTracker();local row=B.UI.tracker.rows[3]
    eq(B.UI.tracker.model.rows[2].questId,4)
    eq(row.status.value,"已接取");assert(row.progress.value:find("建议放弃",1,true));eq(row.enabled,true)
    row.progress.measuredHeight=60;B.UI:LayoutTracker();assert(row.height>=90)
    assert(loadfile("UI/Plan.lua"))("AiLeveling",B);B.UI.Plan.preview=c
    local lines=table.concat(B.UI.Plan:Lines(),"\n")
    assert(lines:find("建议放弃",1,true));assert(lines:find("在任务日志中可放弃",1,true))
    B.finish()
end)

test("交错行程按任务数汇总并显示每个目标与交付步骤",function()
    local B=ready();local a,b=B.plan.taskChoices[1],B.plan.taskChoices[3]
    local oa={kind="objective",questId=1,text="目标甲"};local ob={kind="objective",questId=3,text="目标乙"}
    B.plan.taskQueue={stagePlan=true,taskCount=2,seconds=180,low=180,high=180,xp=200,xpKnown=true,
        steps={{choice=a,stage=oa},{choice=b,stage=ob},{choice=a,stage={kind="turnin"}},{choice=b,stage={kind="turnin"}}}}
    a.executionAction=oa;a.executionTiming={seconds=80,low=80,high=80};B.action=oa
    B.UI:RenderTracker();assert(B.UI.body.value:find("目标甲",1,true))
    assert(not B.UI.body.value:find("先完成附近目标，再集中交付",1,true))
    assert(loadfile("UI/Plan.lua"))("AiLeveling",B);B.UI.Plan.preview=a
    local text=table.concat(B.UI.Plan:Lines(),"\n")
    assert(text:find("本次行程 · 2 项任务",1,true))
    assert(text:find("01  完成目标",1,true));assert(text:find("04  交付",1,true))
    assert(not text:find("估时",1,true));eq(B.state.quests[3].ready,nil)
    B.finish()
end)

end
