return function(test,eq,F,plan)
local function fixture()
    local quests={}
    for id=1,5 do quests[id]=F.Quest(id);quests[id].verified=false end
    quests[1].preQuestGroup={3};quests[5].requiredLevel=40
    local s,data=F.State(),F.Data(quests)
    s.clientVersion,s.clientBuild,s.faction="1.60.1","70862","Alliance"
    data.maps={[100]=2,[200]=1}
    local d={id="ref",reference=true,title="测试副本",instanceId=42,areas={100},entrances={{200,20,30}},
        quests={Alliance={[1]="inside",[2]="inside",[5]="inside"}}}
    data.Target=function(_,q,state)
        local active=state.quests[q.id]
        local map=active and not active.ready and q.id<=2 and 2 or not active and q.id==2 and 3 or 1
        return {map=map,x=q.id/10,y=0.3,entityKind="npc",entityId=active and active.ready and 99 or q.id,entityName="任务NPC"}
    end
    data.ObjectiveTargets=function(_,q) return {{map=q.id<=2 and 2 or 1,x=q.id/10,y=0.3,objectiveIndex=1}} end
    local B={Data=data,Content=data.content,state=s,char={turnIns={},skipped={}},Navigation=F.Navigation,ready=true,
        settings={minutes=60,mode="fast",dungeons=true,role="DAMAGER"},
        DungeonCatalog={version="1.60.1",build="70862",entries={ref=d}}}
    for _,file in ipairs({"State.lua","Planner/Eligibility.lua","Planner/Chains.lua","Planner/Travel.lua","Planner/Gear.lua",
        "Planner/Progression.lua","Planner/Supplies.lua","Planner/Dungeon.lua","Planner/DungeonTasks.lua",
        "Planner/TaskGuide.lua","Planner/TaskQueue.lua","Planner/Planner.lua","Planner/Selection.lua","UI/Main.lua","UI/Tracker.lua"}) do
        assert(loadfile(file))("AiLeveling",B)
    end
    data.chainIndex=B.Chains.NewIndex()
    for _,q in pairs(quests) do B.Chains.IndexQuest(data.chainIndex,q,data) end
    B.State.Refresh=function()
        s.locked=B.char.locked;s.skipped=B.char.skipped
        B.Selection:Snapshot(s);B.Dungeon:TaskBatchSnapshot(s)
    end
    return B,s,data,quests,d
end
local function run(name,fn)
    test(name,function()
        local old=C_Map
        C_Map={GetMapInfo=function(id) return {name="任务区域",mapType=id==2 and 4 or 3} end}
        fn();C_Map=old
    end)
end
run("多入口副本按当前可用交通选择更快入口",function()
    local B,s,data,_,d=fixture()
    d.entrances={{200,20,30},{200,90,30}}
    s.interface,s.money,s.transportKnown=16001,100,true
    s.unlocked={["taxi:1"]=true,["taxi:2"]=true}
    s.taxiAvailability={["1:2"]=true};s.taxiCosts={["1:2"]=20}
    s.taxiDepartures={[1]=s.position};s.taxiLandings={["1:2"]={map=1,x=0.9,y=0.3}}
    B.Estimates={flightBoardSeconds=3,hearthSeconds=10}
    B.FlightData={version="test",clientVersion="1.60.1",build=70862,interface=16001,
        nodes={[1]={instance=0,factionMask=1},[2]={instance=0,factionMask=1}},durations={Alliance={["1:2"]=1}}}
    assert(loadfile("Planner/Flights.lua"))("AiLeveling",B)
    local action={kind="objective",questId=1,title="本内目标",position={map=2,x=0.1,y=0.3}}
    local entry=B.Dungeon.TaskApproach(action,s,data)
    assert(entry.position.x==0.9,"flight must select the faster entrance");eq(entry.questId,1)
    s.money=0;eq(B.Dungeon.TaskApproach(action,s,data).position.x,0.2)
    s.money=100;s.transportKnown=false;eq(B.Dungeon.TaskApproach(action,s,data).position.x,0.2)
    s.transportKnown=true;s.taxiCosts={};eq(B.Dungeon.TaskApproach(action,s,data).position.x,0.2)
    assert(loadfile("Hearth.lua"))("AiLeveling",B)
    s.hearthPoint={map=1,x=0.9,y=0.3};s.hearthBindingKey="旅店";s.hearthReady=0;s.hearthCooldown=3600;s.bags[6948]=1
    assert(B.Dungeon.TaskApproach(action,s,data).position.x==0.9,"hearth must select the faster entrance")
    s.bags[6948]=nil;eq(B.Dungeon.TaskApproach(action,s,data).position.x,0.2)
    eq(s.completed[1],nil);eq(s.money,100)
end)
run("关闭副本建议排除自动进本且不拖住同收件人的野外交付",function()
    local B,s,data=fixture();s.completed[3]=true;B.settings.dungeons=false
    s.quests[1]={objectives={{text="本内目标",numRequired=1,numFulfilled=0}}}
    s.quests[2]={ready=true,objectives={}}
    local p=plan(s,data,B.settings,B)
    eq(p.fallback.questId,2);eq(p.fallback.kind,"turnin")
    local blocked;for _,c in ipairs(p.taskChoices) do if c.questId==1 then blocked=c end end
    assert(blocked.entryBlocked and blocked.entryBlocked:find("已关闭副本建议",1,true))
    eq(#B.TaskGuide.DeliveryGroups(p.taskChoices,s),0)
    local model=B.UI.TrackerModel(s,p,p.fallback,false)
    local row;for _,r in ipairs(model.rows) do if r.questId==1 then row=r end end
    assert(row.progress:find("已关闭副本建议",1,true));eq(s.completed[1],nil)
    B.settings.dungeons=true;p=plan(s,data,B.settings,B)
    eq(p.fallback.questId,1);eq(p.fallback.kind,"dungeonEnter")
end)
run("关闭副本建议不自动接取含本内阶段任务但保留手选及任务组",function()
    local B,s,data=fixture();s.completed[3]=true;B.settings.dungeons=false
    data.ReferenceObjectiveTargets=function(_,q)
        return {{text="任务目标",numRequired=1,numFulfilled=0}},data:ObjectiveTargets(q)
    end
    local target=data.Target
    data.Target=function(self,q,state)
        local point=target(self,q,state)
        if not state.quests[q.id] then point.map=1 end
        return point
    end
    local p=plan(s,data,B.settings,B)
    assert(p.fallback.questId~=1 and p.fallback.questId~=2)
    local checked=0;for _,c in ipairs(p.taskChoices) do
        if c.questId==1 or c.questId==2 then assert(c.entryBlocked);checked=checked+1 end
    end;eq(checked,2)
    assert(B.Selection:LockQuest(1));p=plan(s,data,B.settings,B)
    eq(p.fallback.questId,1);eq(p.fallback.kind,"accept")
    s.quests[1]={objectives={{text="本内目标",numRequired=1,numFulfilled=0}}}
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter")
    assert(B.Dungeon:StartTaskBatch("ref"));p=plan(s,data,B.settings,B)
    eq(p.fallback.questId,2);eq(p.fallback.kind,"accept")
    s.quests[2]={objectives={{text="本内目标",numRequired=1,numFulfilled=0}}}
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter")
end)
run("关闭副本建议仍继续当前本内目标及出本交付，缺图目标同样门控",function()
    local B,s,data=fixture();s.completed[3]=true;B.settings.dungeons=false
    s.completed[2],s.completed[4]=true,true
    s.quests[1]={objectives={{text="本内目标",numRequired=1,numFulfilled=0}}}
    local target=data.Target
    data.Target=function(self,q,state)
        if q.id==1 and not state.quests[1].ready then return end
        return target(self,q,state)
    end
    data.ObjectiveTargets=function() return {} end
    data.UnmappedTargetArea=function(_,q,state)
        if q.id==1 and not state.quests[1].ready then return 100,1 end
    end
    local p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonBlocked");eq(p.fallback.position,nil)
    assert(p.fallback.text:find("已关闭副本建议",1,true))
    s.inInstance,s.instanceId,s.position=true,42,{map=2,x=0,y=0}
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"objective");eq(p.fallback.questId,1)
    s.quests[1].ready=true;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonLeave")
    s.inInstance=false;s.position={map=1,x=0,y=0}
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"turnin");eq(s.completed[1],nil)
end)
run("关闭副本建议先继续当前本内目标，完成后不自动转入另一个副本",function()
    local B,s,data=fixture();s.completed[3]=true;B.settings.dungeons=false
    s.completed[2],s.completed[4]=true,true
    B.DungeonCatalog.entries.other={title="另一个副本",instanceId=43,areas={300},entrances={{200,50,50}}}
    data.maps[300]=4
    s.quests[1]={objectives={{text="本内目标",numRequired=1,numFulfilled=0},{text="另一本目标",numRequired=1,numFulfilled=0}}}
    data.ObjectiveTargets=function() return {{map=2,x=0.1,y=0.1,objectiveIndex=1},{map=4,x=0.2,y=0.2,objectiveIndex=2}} end
    local target=data.Target
    data.Target=function(self,q,state)
        if q.id==1 and state.quests[1] and not state.quests[1].ready then
            return data:ObjectiveTargets()[state.quests[1].objectives[1].finished and 2 or 1]
        end
        return target(self,q,state)
    end
    s.inInstance,s.instanceId,s.position=true,42,{map=2,x=0,y=0}
    local p=plan(s,data,B.settings,B);eq(p.fallback.kind,"objective");eq(p.fallback.position.map,2)
    s.quests[1].objectives[1].finished=true
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonBlocked")
    assert(p.fallback.text:find("已关闭副本建议",1,true));eq(s.completed[1],nil)
end)
run("副本整组先接齐可行任务，完成前置后入本，整组完成再出本交付",function()
    local B,s,data,q=fixture()
    s.quests[4]={ready=true};B.char.locked=4
    assert(B.Dungeon:StartTaskBatch("ref"));eq(B.char.locked,nil)
    eq(B.char.taskBatch.baselines[1],0);eq(B.char.taskBatch.baselines[2],0);eq(B.char.taskBatch.baselines[5],nil)
    local p=plan(s,data,B.settings,B)
    eq(p.fallback.questId,3);eq(p.preparingQuest.id,1);eq(#p.taskChoices,2);eq(p.taskBatch.remaining,2)
    s.quests[3]={ready=true,objectives={}};p=plan(s,data,B.settings,B);eq(p.fallback.kind,"turnin")
    s.quests[3]=nil;s.completed[3]=true
    p=plan(s,data,B.settings,B);eq(p.fallback.questId,1);eq(p.fallback.kind,"accept")
    s.quests[1]={objectives={{text="完成目标",numRequired=1,numFulfilled=0}}}
    p=plan(s,data,B.settings,B);eq(p.fallback.questId,2);eq(p.fallback.kind,"accept");eq(p.fallback.position.map,3)
    local model=B.UI.TrackerModel(s,p,p.fallback,false);assert(model.hint:find("测试副本",1,true))
    s.quests[2]={objectives={{text="完成目标",numRequired=1,numFulfilled=0}}}
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter")
    s.inInstance,s.instanceId,s.position=true,42,{map=2,x=0,y=0}
    s.quests[1].ready=true
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"objective");eq(p.fallback.questId,2)
    s.quests[2].ready=true;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonLeave")
    eq(s.completed[1],nil);eq(s.completed[2],nil)
    s.inInstance=false;s.position={map=1,x=0,y=0}
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"turnin")
    local id=p.fallback.questId;s.quests[id]=nil;s.completed[id]=true;B.char.turnIns[id]=1
    B.State:Refresh();eq(s.taskBatch.baselines[id],nil);assert(B.char.taskBatch)
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"turnin");assert(p.fallback.questId~=id)
    id=p.fallback.questId;s.quests[id]=nil;s.completed[id]=true;B.char.turnIns[id]=1;B.State:Refresh()
    eq(s.taskBatch,nil);eq(B.char.taskBatch,nil);assert(s.quests[4])
end)
run("副本任务行程随前置、接取、本内完成和交付更新",function()
    local B,s,data=fixture()
    data.ReferenceObjectiveTargets=function(_,q)
        return {{text="参考目标",numRequired=1,numFulfilled=0}},data:ObjectiveTargets(q)
    end
    assert(B.Dungeon:StartTaskBatch("ref"))
    local p=plan(s,data,B.settings,B)
    local j=p.taskBatch.journey
    eq(#j.before,4);eq(#j.inside,1);eq(#j.after,1)
    eq(j.inside[1].action.questId,2);eq(j.entry.kind,"dungeonEnter");assert(j.leave)
    for _,step in ipairs(j.before) do assert(step.action.questId~=1) end
    local prerequisite
    for _,step in ipairs(j.before) do if step.action.questId==3 then prerequisite=step end end
    eq(prerequisite.preparingQuest.id,1);eq(prerequisite.action.kind,"turnin")
    s.completed[3]=true
    s.quests[1]={objectives={{text="本内目标",numRequired=1,numFulfilled=0}}}
    p=plan(s,data,B.settings,B);j=p.taskBatch.journey
    eq(#j.before,1);eq(j.before[1].action.questId,2);eq(#j.inside,2);eq(#j.after,2)
    s.inInstance,s.instanceId,s.position=true,42,{map=2,x=0,y=0}
    s.quests[1].ready=true;s.quests[2]={ready=true,objectives={}}
    p=plan(s,data,B.settings,B);j=p.taskBatch.journey
    eq(#j.inside,0);eq(j.entry,nil);assert(j.leave);eq(#j.after,2)
    eq(j.after[1].recipient.entityId,99);eq(j.after[2].recipient.entityId,99)
    s.quests[1]=nil;s.completed[1]=true;B.char.turnIns[1]=1;B.State:Refresh()
    p=plan(s,data,B.settings,B);eq(#p.taskBatch.journey.after,1)
    eq(p.taskBatch.journey.after[1].action.questId,2);eq(s.completed[2],nil)
end)
run("副本行程保留缺图目标身份，剔除低价值和受阻项，交付按真实收件人归组",function()
    local B,s,data,q,d=fixture()
    local function choice(id,recipient)
        return {questId=id,stages={{kind="objective",questId=id,title=q[id].title,areaId=100},
            {kind="objective",questId=id,title=q[id].title,position={map=1,x=0.1,y=0.1}},
            {kind="turnin",questId=id,title=q[id].title,recipient={entityKind="npc",entityId=recipient}}}}
    end
    local choices={choice(1,99),choice(2,98),choice(3,99),choice(4,99),choice(5,99)}
    choices[4].lowValue={};choices[5].entryBlocked="进入受限"
    local j=B.Dungeon.TaskJourney(d,choices,s,data)
    eq(#j.inside,3);eq(j.inside[1].action.areaId,100);eq(j.entry.kind,"dungeonEnter")
    eq(#j.after,6)
    for i=1,3 do eq(j.after[i].action.kind,"objective") end
    eq(j.after[4].action.questId,1);eq(j.after[5].action.questId,3);eq(j.after[6].action.questId,2)
    eq(choices[1].stages[1].position,nil);eq(s.completed[1],nil)
end)
run("副本页显示当前任务行程及接取状态，状态过期不显示旧行程",function()
    local B,s,data=fixture();s.completed[3]=true;s.revision=7
    data.ReferenceObjectiveTargets=function(_,q)
        return {{text="参考目标",numRequired=1,numFulfilled=0}},data:ObjectiveTargets(q)
    end
    s.quests[1]={objectives={{text="本内目标",numRequired=1,numFulfilled=0}}}
    assert(B.Dungeon:StartTaskBatch("ref"));B.plan=plan(s,data,B.settings,B);B.plan.revision=7
    assert(loadfile("UI/Dungeon.lua"))("AiLeveling",B)
    local ui=B.UI.Dungeon;ui.selected="ref";ui.tasks=B.Dungeon.Tasks(B.Dungeon.Catalog(s,B.Content).ref,s,data)
    local text=table.concat(ui:Lines(),"\n")
    assert(text:find("已接 · 完成 · 测试任务 1",1,true));assert(text:find("未接 · 接取 · 测试任务 2",1,true))
    assert(text:find("出发前准备",1,true));assert(text:find("副本内任务",1,true));assert(text:find("出本后接续与交付",1,true))
    B.plan.revision=6;text=table.concat(ui:Lines(),"\n")
    assert(not text:find("本次任务安排",1,true))
end)
run("已就绪成员不会在门外先交付，同收件人未完成成员继续入本",function()
    local B,s,data=fixture();s.completed[3]=true
    s.quests[1]={ready=true,objectives={}};s.quests[2]={objectives={{text="完成目标",numRequired=1,numFulfilled=0}}}
    assert(B.Dungeon:StartTaskBatch("ref"))
    local p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter");eq(p.fallback.questId,2)
end)
run("副本内收件人缺地图仍等待整组完成并显示分组，手动交付可覆盖",function()
    local B,s,data=fixture();s.completed[3]=true
    local adapter={};assert(loadfile("Data/Questie.lua"))("AiLeveling",adapter)
    data.Recipient=adapter.Data.Recipient
    data.db={Quest={Get=function(_,key) if key=="finishedBy" then return {{99}} end end},
        Npc={Get=function() return "本内收件人" end}}
    local target=data.Target
    data.Target=function(self,q,state)
        if state.quests[q.id] and state.quests[q.id].ready then return end
        return target(self,q,state)
    end
    data.UnmappedTargetArea=function(_,q,state) if state.quests[q.id] and state.quests[q.id].ready then return 100 end end
    s.quests[1]={ready=true,objectives={}};s.quests[2]={objectives={{text="完成目标",numRequired=1,numFulfilled=0}}}
    s.inInstance,s.instanceId,s.position=true,42,{map=2,x=0,y=0}
    assert(B.Dungeon:StartTaskBatch("ref"))
    local p=plan(s,data,B.settings,B)
    eq(p.fallback.questId,2);eq(p.fallback.kind,"objective")
    local model=B.UI.TrackerModel(s,p,p.fallback,false)
    assert(model.hint:find("1/2",1,true));eq(model.includesCurrent,true)
    local rows=B.Dungeon.Tasks(B.DungeonCatalog.entries.ref,s,data)
    eq(rows[1].recipient,"npc:99");eq(rows[2].recipient,"npc:99");eq(rows[1].recipientName,"本内收件人")
    assert(B.Selection:LockQuest(1));p=plan(s,data,B.settings,B)
    eq(p.fallback.questId,1);eq(p.fallback.kind,"turnin");eq(p.fallback.position,nil)
    assert(B.Dungeon:StartTaskBatch("ref"));s.quests[2].ready=true
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"turnin")
    model=B.UI.TrackerModel(s,p,p.fallback,false);assert(model.hint:find("整组已完成",1,true))
    eq(s.completed[1],nil);eq(s.completed[2],nil)
end)
run("进入受限时整组先交付可交成员，重试后恢复入口且野外前置可继续",function()
    local B,s,data=fixture();s.completed[3]=true
    s.quests[1]={ready=true,objectives={}};s.quests[2]={objectives={{text="完成目标",numRequired=1,numFulfilled=0}}}
    assert(B.Dungeon:StartTaskBatch("ref"));s.instanceEntryError="实例次数受限"
    local p=plan(s,data,B.settings,B);eq(p.fallback.questId,1);eq(p.fallback.kind,"turnin")
    eq(#B.TaskGuide.DeliveryGroups(p.taskChoices,s),0)
    s.quests[1]=nil;s.completed[1]=true;B.char.turnIns[1]=1;B.State:Refresh()
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonBlocked");eq(p.fallback.position,nil)
    s.instanceEntryError=nil;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter")
    s.instanceEntryError="实例次数受限";s.quests[2]=nil
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"accept");eq(p.fallback.questId,2)
    eq(s.completed[2],nil)
end)
run("整组中单项前置失效不阻止其他任务，全部受阻显示原因且不改完成状态",function()
    local B,s,data=fixture();assert(B.Dungeon:StartTaskBatch("ref"))
    B.char.skipped[3]=true;B.State:Refresh()
    local p=plan(s,data,B.settings,B);eq(p.fallback.questId,2)
    s.completed[2]=true;B.State:Refresh();p=plan(s,data,B.settings,B)
    eq(p.fallback.kind,"selectionBlocked");assert(p.fallback.text:find("前置未交付",1,true));eq(s.completed[1],nil)
    s.clientBuild="next";p=plan(s,data,B.settings,B);eq(p.fallback.kind,"selectionBlocked");assert(B.char.taskBatch)
end)
run("整组选择不会保护远处低收益任务或拖住同NPC交付",function()
    local B,s,data,q,d=fixture();q[1].preQuestGroup=nil
    data.chainIndex=B.Chains.NewIndex()
    for _,quest in pairs(q) do B.Chains.IndexQuest(data.chainIndex,quest,data) end
    q[1].questLevel=17;q[1].taskFacts={xp={{1,1000}},level=17,rewards={items={},choices={}}}
    s.quests[1]={objectives={{text="完成目标",numRequired=1,numFulfilled=0}}};s.quests[2]={ready=true,objectives={}}
    data.Target=function(_,quest,state)
        return {map=1,x=state.quests[quest.id] and not state.quests[quest.id].ready and 2 or 0,y=0,entityKind="npc",entityId=99}
    end
    data.ObjectiveTargets=function() return {{map=1,x=2,y=0,objectiveIndex=1}} end
    assert(B.Dungeon:StartTaskBatch("ref"))
    local p=plan(s,data,B.settings,B);eq(p.fallback.questId,2);eq(p.fallback.kind,"turnin")
    local low;for _,c in ipairs(p.taskChoices) do if c.questId==1 then low=c.lowValue end end;assert(low and low.distant)
    s.quests[2]=nil;s.completed[2]=true;B.State:Refresh();p=plan(s,data,B.settings,B);eq(p.fallback.kind,"taskReview")
    eq(B.char.skipped[1],nil);eq(s.completed[1],nil)
end)
run("任务安排重载保留进度，重复任务按本次交付计数收尾",function()
    local B,s,data,q=fixture();q[2].repeatable=true;s.completed[2]=true;B.char.turnIns[2]=7
    assert(B.Dungeon:StartTaskBatch("ref"));eq(B.char.taskBatch.baselines[2],7)
    B.State:Refresh();eq(s.taskBatch.baselines[2],7)
    s.taskBatch.baselines[2]=99;eq(B.char.taskBatch.baselines[2],7)
    s.quests[2]={ready=true};B.State:Refresh();eq(B.char.taskBatch.baselines[2],7)
    s.quests[2]=nil;B.char.turnIns[2]=8;B.State:Refresh();eq(B.char.taskBatch.baselines[2],nil)
    assert(B.char.taskBatch.baselines[1]);eq(s.completed[1],nil)
end)
run("暂缓一项保留整组，手动选择或恢复自动清除整组且状态更新时拒绝启动",function()
    local B,s,data=fixture();assert(B.Dungeon:StartTaskBatch("ref"))
    B.Selection:Skip(2);eq(B.char.taskBatch.baselines[2],nil);eq(B.char.taskBatch.baselines[1],0)
    assert(B.Selection:LockQuest(4));eq(B.char.taskBatch,nil);eq(B.char.locked,4)
    assert(B.Dungeon:StartTaskBatch("ref"));assert(B.Selection:Automatic());eq(s.taskBatch,nil)
    B.refreshAt=1;eq(B.Dungeon:StartTaskBatch("ref"),false);eq(B.char.taskBatch,nil);B.refreshAt=nil
    B.Transport={InFlight=function() return true end};eq(B.Dungeon:StartTaskBatch("ref"),false);B.Transport=nil
    B.char.dungeon={phase="inside"};eq(B.Dungeon:StartTaskBatch("ref"),false)
end)
run("损坏任务组存档拒绝并清除，完整副本或单任务选择优先",function()
    local B,s=fixture()
    for _,bad in ipairs({{}, {id="ref",baselines={}}, {id="ref",baselines={[0]=0}},
        {id="ref",baselines={[1]=-1}}, {id="ref",baselines={[1]=math.huge}}, {id={},baselines={[1]=0}}}) do
        eq(B.Dungeon.ValidTaskBatch(bad),false);B.char.taskBatch=bad;B.Dungeon:TaskBatchSnapshot(s);eq(B.char.taskBatch,nil)
    end
    B.char.taskBatch={id="ref",baselines={[1]=0}};B.char.dungeon={phase="inside"}
    B.Dungeon:TaskBatchSnapshot(s);eq(B.char.taskBatch,nil)
    B.char.dungeon=nil;B.char.taskBatch={id="ref",baselines={[1]=0}};B.char.locked=1
    B.Dungeon:TaskBatchSnapshot(s);eq(B.char.taskBatch,nil)
end)
run("任务日志已满先推进已接成员，腾出名额后继续接取，全部未接时显示整理提示",function()
    local B,s,data=fixture();s.questLimit,s.questCount=20,20
    assert(B.Dungeon:StartTaskBatch("ref"))
    local p=plan(s,data,B.settings,B);eq(p.fallback.kind,"selectionBlocked")
    assert(p.fallback.text:find("任务日志已满",1,true))
    s.completed[3]=true;s.quests[1]={ready=true,objectives={}}
    p=plan(s,data,B.settings,B);eq(p.fallback.questId,1);eq(p.fallback.kind,"turnin")
    s.quests[1]=nil;s.completed[1]=true;s.questCount=19;B.State:Refresh()
    p=plan(s,data,B.settings,B);eq(p.fallback.questId,2);eq(p.fallback.kind,"accept")
end)

run("副本奖励汇总区分前置受阻已交付和已接状态且未知经验不补零",function()
    local B,s,data,q,d=fixture()
    for id,quest in pairs(q) do
        quest.questLevel=20;quest.taskFacts={level=20,xp={{1,id*100}},rewards={}}
    end
    s.quests[2]={ready=true,objectives={}}
    local rows=B.Dungeon.Tasks(d,s,data);local rewards=B.Dungeon.TaskRewards(rows)
    eq(rewards.count,2);eq(rewards.xp,300);eq(rewards.prepare,1);eq(rewards.ready,1);eq(rewards.blocked,1)
    q[2].taskFacts.xp=nil;rows=B.Dungeon.Tasks(d,s,data);rewards=B.Dungeon.TaskRewards(rows)
    eq(rewards.xp,100);eq(rewards.unknownXP,1)
    s.quests[2].rewardXP=700;s.quests[2].rewardXPLevel=s.level
    rows=B.Dungeon.Tasks(d,s,data);rewards=B.Dungeon.TaskRewards(rows)
    eq(rewards.xp,800);eq(rewards.unknownXP,0)
    s.quests[2]=nil;s.completed[2]=true;rows=B.Dungeon.Tasks(d,s,data);rewards=B.Dungeon.TaskRewards(rows)
    eq(rewards.count,1);eq(rewards.xp,100);eq(rewards.unknownXP,0)
    q[2].repeatable=true;rows=B.Dungeon.Tasks(d,s,data);rewards=B.Dungeon.TaskRewards(rows,{[2]=0})
    eq(rewards.count,1);eq(rewards.unknownXP,1);eq(rewards.prepare,0)
    rows[#rows+1]=rows[1];eq(B.Dungeon.TaskRewards(rows).count,2)
    q[2].taskFacts.hidden="获取限制";rows=B.Dungeon.Tasks(d,s,data)
    eq(B.Dungeon.TaskRewards(rows,{[2]=0}).count,0)
    s.quests[2]={};rows=B.Dungeon.Tasks(d,s,data);eq(B.Dungeon.TaskRewards(rows,{[2]=0}).count,1)
    s.quests[2]=nil;q[2].taskFacts.hidden=nil;data.Target=function() end
    rows=B.Dungeon.Tasks(d,s,data);eq(B.Dungeon.TaskRewards(rows,{[2]=0}).count,0)
end)
run("副本任务奖励分别比较互斥选择且缓存未知和特殊效果不计作明确提升",function()
    local B,s,data,q,d=fixture()
    q[2].questLevel=20;q[2].taskFacts={level=20,xp={{1,200}},rewards={choices={{id=100},{id=101}}}}
    s.items={[100]={id=100,usable=true,name="奖励甲",equipLoc="INVTYPE_HEAD",stats={ITEM_MOD_STRENGTH_SHORT=3}},
        [101]={id=101,usable=true,name="奖励乙",equipLoc="INVTYPE_HEAD",stats={ITEM_MOD_STRENGTH_SHORT=7}}}
    local rows=B.Dungeon.Tasks(d,s,data);local row
    for _,r in ipairs(rows) do if r.id==2 then row=r end end
    eq(row.gear.upgrade.delta,7);eq(B.Dungeon.TaskRewards(rows).upgrades,1)
    s.items[101].pending=true;s.items[100].useSpell=42
    rows=B.Dungeon.Tasks(d,s,data);eq(B.Dungeon.TaskRewards(rows).upgrades,0)
    s.items[100].useSpell=nil;s.items[101].pending=nil
    q[2].questLevel=21;rows=B.Dungeon.Tasks(d,s,data);eq(B.Dungeon.TaskRewards(rows).upgrades,0)
end)
run("本次副本收益只统计所选根任务且远处低价值成员退出建议收益",function()
    local B,s,data,q,d=fixture()
    q[1].preQuestGroup=nil;data.chainIndex=B.Chains.NewIndex()
    for _,quest in pairs(q) do B.Chains.IndexQuest(data.chainIndex,quest,data) end
    for id=1,2 do q[id].questLevel=17;q[id].taskFacts={level=17,xp={{1,1000}},rewards={items={},choices={}}} end
    s.quests[1]={objectives={{text="远处目标",numRequired=1,numFulfilled=0}}};s.quests[2]={ready=true,objectives={}}
    data.Target=function(_,quest,state)
        return {map=1,x=state.quests[quest.id] and not state.quests[quest.id].ready and 2 or 0,y=0,entityKind="npc",entityId=99}
    end
    data.ObjectiveTargets=function() return {{map=1,x=2,y=0,objectiveIndex=1}} end
    assert(B.Dungeon:StartTaskBatch("ref"))
    local p=plan(s,data,B.settings,B);eq(p.taskBatch.rewards.xp,1000);eq(p.taskBatch.rewards.count,1)
    eq(p.taskBatch.rewards.excluded,1);eq(p.taskBatch.rewards.ready,1);eq(p.fallback.questId,2)
    B.plan=p;assert(loadfile("UI/Dungeon.lua"))("AiLeveling",B)
    B.UI.Dungeon.selected="ref";B.UI.Dungeon.tasks=B.Dungeon.Tasks(d,s,data)
    local lines=table.concat(B.UI.Dungeon:Lines(),"\n")
    assert(lines:find("交付经验：1000",1,true));assert(lines:find("1 项低收益任务",1,true))
    assert(not lines:find("分钟",1,true));assert(not lines:find("经验/小时",1,true))
    B.Selection:Skip(1);p=plan(s,data,B.settings,B);eq(p.taskBatch.rewards.count,1);eq(p.taskBatch.rewards.excluded,0)
end)

run("缺本内坐标的已接任务可单独继续并完整加入同NPC交付组",function()
    local B,s,data,q,d=fixture();s.completed[3]=true
    for id=1,2 do q[id].questLevel=20;q[id].taskFacts={level=20,xp={{1,id*100}},rewards={}} end
    local target=data.Target
    data.Target=function(self,quest,state)
        local active=state.quests[quest.id]
        if quest.id==2 and active and not active.ready then return end
        return target(self,quest,state)
    end
    data.UnmappedTargetArea=function(_,quest,state)
        if quest.id==2 and state.quests[2] and not state.quests[2].ready then return 100,1 end
    end
    data.ObjectiveTargets=function() return {} end
    s.quests[1]={ready=true};s.quests[2]={objectives={{text="本内目标",numRequired=1,numFulfilled=0}}}
    local rows=B.Dungeon.Tasks(d,s,data)
    local row;for _,r in ipairs(rows) do if r.id==2 then row=r end end
    eq(row.position,nil);eq(row.areaId,100)
    local rewards=B.Dungeon.TaskRewards(rows);eq(rewards.count,2);eq(rewards.active,1);eq(rewards.ready,1);eq(rewards.xp,300)
    assert(B.Dungeon:ContinueTask(d,2));eq(s.locked,2)
    assert(B.Dungeon:StartTaskBatch("ref"));eq(B.char.taskBatch.baselines[2],0);eq(s.locked,nil)
    local p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter");eq(p.fallback.questId,2)
    eq(p.taskBatch.remaining,2);eq(p.taskBatch.rewards.count,2)
    eq(#B.TaskGuide.DeliveryGroups(p.taskChoices,s),1)
    s.position=p.fallback.position;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter")
    eq(s.quests[2].ready,nil)
    s.inInstance,s.instanceId,s.position=true,42,nil
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"objective");eq(p.fallback.areaId,100);eq(p.fallback.position,nil)
    B.State:Refresh();eq(s.taskBatch.baselines[2],0)
    s.quests[2].ready=true;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonLeave")
    s.inInstance=false;s.position={map=1,x=0,y=0}
    for i=1,2 do
        p=plan(s,data,B.settings,B);eq(p.fallback.kind,"turnin")
        local id=p.fallback.questId;s.quests[id]=nil;s.completed[id]=true;B.char.turnIns[id]=1;B.State:Refresh()
    end
    eq(s.taskBatch,nil)
end)
run("缺图目的地必须属于当前构建副本，资格受阻和真正未知仍不加入任务组",function()
    local B,s,data,q,d=fixture();q[1].preQuestGroup=nil;d.quests.Alliance={[1]="inside"}
    data.Target=function() end;data.UnmappedTargetArea=function() return 100 end
    local rows=B.Dungeon.Tasks(d,s,data);eq(rows[1].areaId,100)
    assert(B.Dungeon:StartTaskBatch("ref"));B.Selection:Automatic()
    data.UnmappedTargetArea=function() return 999 end
    rows=B.Dungeon.Tasks(d,s,data);eq(rows[1].areaId,nil);eq(B.Dungeon:ContinueTask(d,1),false)
    eq(B.Dungeon:StartTaskBatch("ref"),false);eq(B.Dungeon.TaskRewards(rows).count,0)
    data.UnmappedTargetArea=function() return 100 end;s.clientBuild="next"
    rows=B.Dungeon.Tasks(d,s,data);eq(rows[1].areaId,nil);eq(B.Dungeon.TaskRewards(rows).count,0)
    s.clientBuild="70862";q[1].requiredLevel=40
    rows=B.Dungeon.Tasks(d,s,data);eq(rows[1].areaId,nil);eq(B.Dungeon:ContinueTask(d,1),false)
end)

run("混合目标先做当前位置目标，缺图本内目标完成后才出本且真实交付后结束",function()
    local B,s,data,q,d=fixture();s.completed[3]=true;d.quests.Alliance={[1]="inside"}
    s.quests[1]={objectives={{text="野外物品",numRequired=1,numFulfilled=0},
        {text="本内物品",numRequired=2,numFulfilled=1}}}
    local target=data.Target
    data.Target=function(self,quest,state)
        local active=state.quests[quest.id]
        if active and not active.ready then
            if not active.objectives[1].finished then return {map=1,x=0.1,y=0.2,objectiveIndex=1} end
            return
        end
        return target(self,quest,state)
    end
    data.ObjectiveTargets=function(_,quest,state)
        if not state.quests[quest.id].objectives[1].finished then return {{map=1,x=0.1,y=0.2,objectiveIndex=1}} end
        return {}
    end
    data.UnmappedTargetArea=function(_,quest,state,index)
        local active=state.quests[quest.id]
        if active and not active.ready and not active.objectives[2].finished and (index==2 or not index) then return 100,2 end
    end
    data.ObjectiveIdentities=function() return {[1]={kind="item",id=101},[2]={kind="item",id=102}} end
    assert(B.Dungeon:StartTaskBatch("ref"))
    local p=plan(s,data,B.settings,B);eq(p.fallback.objectiveIndex,1)
    s.inInstance,s.instanceId,s.position=true,42,nil
    p=plan(s,data,B.settings,B)
    eq(p.fallback.kind,"objective");eq(p.fallback.objectiveIndex,2);eq(p.fallback.targetId,102)
    eq(p.fallback.position,nil);eq(p.fallback.areaId,100);eq(p.fallback.have,1);eq(p.fallback.need,2)
    eq(p.taskChoices[1].currentInstance,true);eq(p.taskChoices[1].stages[1].objectiveIndex,2)
    eq(p.taskChoices[1].stages[2].objectiveIndex,1);eq(p.taskChoices[1].stages[3].kind,"turnin")
    eq(s.quests[1].objectives[2].finished,nil);eq(s.completed[1],nil)
    s.quests[1].objectives[2].finished=true
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonLeave")
    s.inInstance=false;s.position={map=1,x=0,y=0}
    p=plan(s,data,B.settings,B);eq(p.fallback.objectiveIndex,1)
    s.quests[1].objectives[1].finished=true;s.quests[1].ready=true
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"turnin");assert(s.taskBatch)
    s.quests[1]=nil;s.completed[1]=true;B.char.turnIns[1]=1;B.State:Refresh();eq(s.taskBatch,nil)
end)
run("副本任务批次先处理野外目标再进本，普通与手选任务也保留本内目标",function()
    local B,s,data,q,d=fixture();s.completed[3]=true;d.quests.Alliance={[1]="inside"}
    local active={objectives={{text="本内目标",numRequired=1,numFulfilled=0},
        {text="野外目标",numRequired=1,numFulfilled=0}}}
    s.quests[1]=active
    data.Target=function(_,quest,state)
        return {map=state.quests[quest.id] and 2 or 1,x=0.1,y=0.2,objectiveIndex=1}
    end
    data.ObjectiveTargets=function() return {{map=2,x=0.1,y=0.2,objectiveIndex=1},{map=1,x=0.2,y=0.2,objectiveIndex=2}} end
    assert(B.Dungeon:StartTaskBatch("ref"))
    local p=plan(s,data,B.settings,B);eq(p.fallback.kind,"objective");eq(p.fallback.objectiveIndex,2)
    active.objectives[2].finished=true
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter")
    B.Selection:Automatic();s.inInstance,s.instanceId,s.position=true,42,nil
    p=plan(s,data,B.settings,B);eq(p.fallback.questId,1);eq(p.fallback.kind,"objective");eq(p.fallback.objectiveIndex,1)
    assert(B.Selection:LockQuest(1));p=plan(s,data,B.settings,B);eq(p.fallback.kind,"objective")
    s.quests[1]=nil;s.inInstance=false;s.position={map=1,x=0,y=0}
    p=plan(s,data,B.settings,B);eq(p.fallback.kind,"accept")
end)

run("混合目标按实际副本区分，保留目标身份顺序和未关联的原生引导",function()
    local B,s,data=fixture()
    B.DungeonCatalog.entries.other={id="other",instanceId=43,areas={300},entrances={}}
    data.maps[300]=4
    s.inInstance,s.instanceId,s.position=true,42,nil
    local a={kind="objective",objectiveIndex=1,areaId=100}
    local b={kind="objective",objectiveIndex=2,areaId=300}
    local c={kind="objective",objectiveIndex=3,areaId=100}
    local finish={kind="turnin",areaId=100}
    local stages={a,b,c,finish}
    eq(B.Dungeon.OrderTaskObjectives(stages,s,data),a)
    eq(stages[2],c);eq(stages[3],b);eq(stages[4],finish)
    s.instanceId=43
    eq(B.Dungeon.OrderTaskObjectives(stages,s,data),b);eq(stages[2],a);eq(stages[3],c)
    local waypoint={kind="objective",position={map=1,x=0.2,y=0.2,label="客户端任务目标"}}
    stages={waypoint,a,b,finish};eq(B.Dungeon.OrderTaskObjectives(stages,s,data),nil);eq(stages[1],waypoint)
    s.clientBuild="next";stages={a,b,finish};eq(B.Dungeon.OrderTaskObjectives(stages,s,data),nil);eq(stages[1],a)
    s.clientBuild="70862";stages={finish,a};eq(B.Dungeon.OrderTaskObjectives(stages,s,data),nil)
end)

end
