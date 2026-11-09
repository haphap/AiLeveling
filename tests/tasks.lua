return function(test,eq,F,A,plan)
local function fixture()
    local quests={}
    for i=1,8 do quests[i]={id=i,title="真实入口夹具 "..i,questLevel=20,requiredLevel=1} end
    local s,d=F.State(),F.Data(quests)
    s.position={map=1,x=0.5,y=0.5}
    d.Target=function(_,q,state)
        if q.id==7 then return end
        return {map=q.id==8 and 2 or 1,x=q.id/10,y=0.5,label="数据库位置"}
    end
    return s,d,quests
end
test("空自有内容仍列出本区资格通过的真实任务目标且不伪造经验率",function()
    local s,d,q=fixture();q[2].requiredLevel=99;q[3].requiredRaces=2
    s.completed[4]=true;s.skipped[5]=true;s.chainDeferred={[6]=1}
    local p=plan(s,d)
    eq(#p.alternatives,0);eq(p.best,nil);eq(#p.taskChoices,1)
    eq(p.taskChoices[1].questId,1);eq(p.taskChoices[1].rate,nil);eq(p.taskChoices[1].seconds,nil)
    eq(p.fallback.kind,"accept");eq(p.fallback.position.map,1)
end)
test("日志任务含无坐标和数据库未收录任务且交付优先",function()
    local s,d=fixture();s.quests={[7]={title="无位置",objectives={}},[99]={title="原生新增任务",ready=true,objectives={}}}
    d.Target=function(_,q) if q.id==99 then return {map=2,x=0.5,y=0.5} end end
    local p=plan(s,d);eq(#p.taskChoices,2);eq(p.taskChoices[1].questId,99)
    eq(p.fallback.kind,"turnin");eq(p.taskChoices[2].questId,7)
end)
test("任务入口只接受当前对象并经原有锁定入口保存和实际交付解除",function()
    local s,d=fixture()
    local B={ready=true,state=s,Data=d,Content=d.content,char={turnIns={},skipped={},paused=true},Navigation={manual={}}}
    assert(loadfile("Planner/Selection.lua"))("AiLeveling",B)
    B.State={Refresh=function() end};B.plan=plan(s,d)
    local c=B.plan.taskChoices[1]
    eq(B.Selection.CanChoose({kind="task",questId=c.questId},1),false)
    eq(B.Selection:Lock(c,1),true);eq(B.char.locked,c.questId);eq(B.char.itinerary,nil);eq(B.char.paused,false);eq(B.Navigation.manual,nil)
    s.completed[c.questId]=true;B.Selection:Snapshot(s);eq(B.char.locked,nil)
end)
test("任务行程页显示真实进度位置和导航入口且不输出零耗时方案",function()
    local s,d=fixture();s.quests[1]={title="进行中任务",objectives={{text="目标 1/3",finished=false}}}
    local B={Planner=A.Planner,UI={},char={},state=s,Navigation={Current=function() end}}
    assert(loadfile("UI/Main.lua"))("AiLeveling",B)
    assert(loadfile("UI/Plan.lua"))("AiLeveling",B)
    B.plan=plan(s,d);local rows=B.UI.Plan.Rows(B.plan);assert(#rows>0)
    B.UI.Plan.preview=rows[1]
    local text=table.concat(B.UI.Plan:Lines(),"\n")
    assert(text:find("目标 1/3",1,true));assert(text:find("10.0, 50.0",1,true))
    assert(not text:find("预计 0.0",1,true));assert(text:find("任务日志",1,true))
    B.Dungeon={TaskInstance=function(_,_,_,area) if area==96 then return {title="测试副本"} end end}
    B.UI.Plan.preview.stages={{kind="objective",text="收集目标",areaId=96},{kind="turnin",text="返回交付",position={map=1,x=0.1,y=0.2}}}
    text=table.concat(B.UI.Plan:Lines(),"\n")
    assert(text:find("目的地：测试副本",1,true));assert(text:find("返回交付",1,true))
end)
test("NPC 实际接取列表避开不可接任务并保留其他发布者与已接交付",function()
    local oldMap,oldLog,oldGossip,oldGuid,oldQuest,oldAccess=C_Map,C_QuestLog,C_GossipInfo,UnitGUID,GetQuestID,canaccessvalue
    C_Map={GetMapInfo=function() return {} end};C_QuestLog={};canaccessvalue=nil
    local npc,list=11,{}
    UnitGUID=function(unit) eq(unit,"npc");return "Creature-0-1-2-3-"..npc.."-00000001" end
    C_GossipInfo={GetAvailableQuests=function() return list end}
    local B={Content={quests={}},Navigation=F.Navigation,Merchant=A.Merchant}
    assert(loadfile("State.lua"))("AiLeveling",B)
    assert(loadfile("Data/Questie.lua"))("AiLeveling",B)
    local sources,q={{11}},{id=1,title="待接任务",questLevel=20,requiredLevel=1,zoneOrSort=10}
    local entity={Get=function(id,key) if key=="name" then return "发布者 "..id end return {[10]={{id,50}}} end}
    local d=B.Data;d.maps={[10]=1};d.content=F.Data({}).content
    d.db={Enum={npcFlags={}},Npc=entity,Object=entity,Quest={Get=function(_,key)
        if key=="startedBy" or key=="finishedBy" then return sources end
    end}}
    d.GetQuest=function(_,id) if id==q.id then return q end end;d.byLevel={[20]={1}}
    local s=F.State();s.position={map=1,x=0,y=0.5}
    eq(plan(s,d).fallback.questId,1)
    B.State:QuestOffersEvent("GOSSIP_SHOW");s.questOffers=B.State.questOffers
    eq(d:Target(q,s),nil);eq(#plan(s,d).taskChoices,0)
    local snapshot,revision=s.questOffers,B.State.questOffersRevision
    B.State:QuestOffersEvent("GOSSIP_SHOW");eq(B.State.questOffersRevision,revision)
    for _,invalid in ipairs({false,{{questID=0}},{{questID="1"}}}) do
        list=invalid;B.State:QuestOffersEvent("GOSSIP_SHOW");eq(B.State.questOffers,snapshot)
    end
    C_GossipInfo.GetAvailableQuests=function() error("not ready") end
    B.State:QuestOffersEvent("GOSSIP_SHOW");eq(B.State.questOffers,snapshot)
    C_GossipInfo.GetAvailableQuests=function() return list end
    sources={{11,12}};eq(d:Target(q,s).entityId,12);eq(plan(s,d).fallback.position.entityId,12)
    npc=12;list={};B.State:QuestOffersEvent("GOSSIP_SHOW");s.questOffers=B.State.questOffers
    eq(snapshot[12],nil);eq(d:Target(q,s),nil)
    sources={{11},{13}};eq(d:Target(q,s).entityKind,"object");sources={{11,12}}
    s.quests[1]={ready=true,objectives={}};eq(d:Target(q,s).entityId,11)
    eq(plan(s,d).fallback.kind,"turnin");s.quests[1]=nil
    npc=11;GetQuestID=function() return 1 end
    B.State:QuestOffersEvent("QUEST_DETAIL");s.questOffers=B.State.questOffers
    eq(snapshot[11][1],nil);eq(d:Target(q,s).entityId,11)
    list={{questID=2}};B.State:QuestOffersEvent("GOSSIP_SHOW");s.questOffers=B.State.questOffers
    eq(d:Target(q,s),nil);assert(s.questOffers[11][2])
    list={{questID=1}};B.State:QuestOffersEvent("GOSSIP_SHOW");s.questOffers=B.State.questOffers
    eq(d:Target(q,s).entityId,11)
    B.State:QuestOffersEvent("GOSSIP_CLOSED");eq(B.State.questOffers,s.questOffers)
    B.State:QuestOffersEvent("PLAYER_LEVEL_UP");s.questOffers=B.State.questOffers
    eq(d:Target(q,s).entityId,11);eq(next(s.questOffers),nil)
    npc=nil;UnitGUID=function() return "Player-1-123" end
    B.State:QuestOffersEvent("GOSSIP_SHOW");eq(next(B.State.questOffers),nil)
    q.questLevel=0;d.byLevel={[0]={1}};sources={{11,12}}
    eq(d:Target(q,s),nil);eq(#plan(s,d).taskChoices,0)
    sources={};eq(d:Target(q,s),nil);sources={{11,12}}
    s.locked=1;eq(plan(s,d).fallback.questId,1);s.locked=nil
    npc=12;UnitGUID=function() return "Creature-0-1-2-3-"..npc.."-00000001" end
    B.State:QuestOffersEvent("QUEST_DETAIL");s.questOffers=B.State.questOffers
    eq(table.concat(d:Candidates(s),","),"1")
    q.taskFacts={hidden=true}
    eq(d:Target(q,s).entityId,12)
    local offered=plan(s,d);eq(offered.taskChoices[1].requireCheck,false);eq(offered.fallback.questId,1)
    B.State:QuestOffersEvent("PLAYER_LEVEL_UP");s.questOffers=B.State.questOffers
    s.locked=1;eq(plan(s,d).taskChoices[1].requireCheck,true);s.locked=nil
    s.quests[1]={objectives={}};q.zoneOrSort=0
    assert(d:Target(q,s).approximate);eq(plan(s,d).fallback.kind,"objective")
    s.quests[1].ready=true;eq(plan(s,d).fallback.kind,"turnin");eq(s.completed[1],nil)
    C_Map,C_QuestLog,C_GossipInfo,UnitGUID,GetQuestID,canaccessvalue=oldMap,oldLog,oldGossip,oldGuid,oldQuest,oldAccess
end)
test("接交点目标分布与物品来源按跨区域直线距离选择",function()
    local previousMap,previousLog=C_Map,C_QuestLog
    C_Map={GetMapInfo=function() return {} end};C_QuestLog={}
    local B={State=A.State,Navigation={Distance=function(_,a,b)
        if a.map==3 or b.map==3 then return end
        return math.abs(a.x-b.x)*1000
    end}}
    assert(loadfile("Data/Questie.lua"))("AiLeveling",B)
    B.Data.maps={[10]=1,[20]=2,[30]=3}
    local drops,sources={11},{{11}}
    local entity={Get=function(id,key)
        if key=="name" then return id==11 and "狼" or "野猪" end
        if id>=100 then return {[10]={{id==499 and 0.5 or 50,50}}} end
        return id==11 and {[10]={{80,50}},[20]={{10,50}},[30]={{1,50}}} or {[10]={{50,50}}}
    end}
    B.Data.db={Npc=entity,Object=entity,Item={Get=function(id,key)
        if key=="name" then return "狼皮" elseif key=="npcDrops" then return drops
        elseif key=="startQuest" and id==21 then return 1 end
    end},Quest={Get=function(id,key)
        if key=="objectives" then return {{{11},{12}},{},{{21}}} end
        if key=="finishedBy" then return {{11}} end
        return sources
    end}}
    local s=F.State();s.position={map=1,x=0,y=0.5}
    eq(B.Data:Target({id=1},s).map,2)
    s.quests[1]={ready=true};eq(B.Data:Target({id=1},s).map,2)
    s.quests[1]={objectives={{text="狼 0/1",type="monster"},{text="野猪 0/1",type="monster"},{text="狼皮 0/1",type="item"}}}
    local points=B.Data:ObjectiveTargets({id=1},s)
    eq(#points,3);eq(points[1].map,2);eq(points[2].map,1);eq(points[3].map,2)
    eq(B.Data:ObjectiveTarget({id=1},s).map,2)
    local _,reference=B.Data:ReferenceObjectiveTargets({id=1},{position=s.position,quests={}})
    eq(reference[1].map,2);eq(reference[3].map,2)
    drops={};for id=100,499 do drops[#drops+1]=id end
    local co=coroutine.create(function() return B.Data:ObjectiveTargets({id=1},s) end)
    local resumes,result=0
    repeat
        local ok,value=coroutine.resume(co);assert(ok,value);resumes=resumes+1;result=value
    until coroutine.status(co)=="dead"
    assert(resumes>1);eq(result[3].entityId,499);eq(result[3].x,0.005)
    eq(B.Data:ObjectiveTargets({id=1},s)[3].entityId,499)
    eq(s.quests[1].ready,nil);eq(s.completed[1],nil)
    s.quests={};s.bags[21]=1;sources={{},{},{21}};B.Data.byLevel={}
    eq(B.Data:Candidates(s)[1],1)
    local starter=B.Data:Target({id=1},s)
    eq(starter.startItemId,21);eq(starter.map,s.position.map);eq(starter.x,s.position.x)
    eq(starter.entityId,nil);eq(s.position.startItemId,nil)
    s.quests[1]={ready=true};eq(B.Data:Target({id=1},s).startItemId,nil)
    s.quests={};s.bags[21]=0;eq(#B.Data:Candidates(s),0)
    C_Map,C_QuestLog=previousMap,previousLog
end)
test("任务总览分开已接和未接且顺序与预览使用真实日志状态",function()
    local s=F.State();s.quests={[1]={title="已接任务",objectives={}}}
    local held={kind="task",questId=1,title="已接任务",status="accept",actions={{text="继续"}}}
    local pending={kind="task",questId=2,title="未接任务",status="turnin",actions={{text="先接取"}}}
    local B={state=s,char={},plan={taskChoices={held,pending,pending},taskOrder={pending,held}},
        Navigation={Current=function() end}}
    assert(loadfile("UI/Main.lua"))("AiLeveling",B)
    assert(loadfile("UI/Plan.lua"))("AiLeveling",B)
    local text=table.concat(B.UI:TaskLines(),"\n")
    for _,value in ipairs({"已接取 1 项","未接取 1 项","已接取任务 ·","未接取任务 ·",
        "建议顺序：[未接取] 未接任务 → [已接取] 已接任务","先接取，再推进任务目标"}) do assert(text:find(value,1,true),value) end
    B.UI.Plan.preview=pending
    assert(table.concat(B.UI.Plan:Lines(),"\n"):find("[未接取] 先向任务发布者接取",1,true))
    s.quests[2]={title="未接任务",ready=true,objectives={}}
    text=table.concat(B.UI:TaskLines(),"\n");assert(text:find("未接取 0 项",1,true))
    assert(not text:find("未接取任务 ·",1,true));assert(text:find("[可交付] 未接任务",1,true))
    assert(table.concat(B.UI.Plan:Lines(),"\n"):find("[可交付] 目标已完成",1,true))
    s.quests={};B.plan.taskChoices={pending};B.plan.taskOrder={pending}
    text=table.concat(B.UI:TaskLines(),"\n");assert(text:find("已接取 0 项",1,true));assert(text:find("未接取 1 项",1,true))
end)
test("任务总览仅按确认的共享目标建议一起推进且飞行时不催促地面任务",function()
    local s=F.State();s.quests={[1]={title="任务甲"},[2]={title="任务乙"}}
    local action={questId=1,kind="objective",sharedObjectives={{questId=1},{questId=2}}}
    local B={state=s,char={},plan={best={}},Navigation={Current=function() return action end},Transport={InFlight=function() return false end}}
    assert(loadfile("UI/Main.lua"))("AiLeveling",B)
    assert(table.concat(B.UI:TaskLines(),"\n"):find("可一起推进：任务甲、任务乙",1,true))
    action.sharedObjectives=nil;assert(not table.concat(B.UI:TaskLines(),"\n"):find("可一起推进",1,true))
    B.Transport.InFlight=function() return true end
    assert(not table.concat(B.UI:TaskLines(),"\n"):find("建议先做",1,true))
end)
test("原生无任务航点时从数据库定位未完成目标并跳过已完成项",function()
    local previousMap,previousLog=C_Map,C_QuestLog
    C_Map={GetMapInfo=function() return {} end};C_QuestLog={}
    local B={State=A.State,Navigation={Distance=function(_,a,b) return math.abs(a.x-b.x) end}}
    assert(loadfile("Data/Questie.lua"))("AiLeveling",B)
    B.Data.maps={[10]=1}
    B.Data.db={Quest={Get=function(_,key) if key=="objectives" then return {{{11},{12}}} end end},
        Npc={Get=function(id,key)
            if key=="name" then return id==11 and "狼" or "狗头人" end
            return {[10]={{id==11 and 10 or 30,50}}}
        end}}
    local s={position={map=1,x=0,y=0.5},completed={},quests={[1]={objectives={
        {text="狼 3/3",finished=true},{text="狗头人 1/4",finished=false}}}}}
    local pos=B.Data:Target({id=1},s);eq(pos.x,0.3);eq(pos.objectiveIndex,2)
    s.quests[1].objectives[2].text="不明确的目标";eq(B.Data:Target({id=1},s),nil)
    C_Map,C_QuestLog=previousMap,previousLog
end)
test("参考任务日志满时保留未接列表与原因，优先已接目标和交付",function()
    local s,d=fixture();s.questCount,s.questLimit=20,20
    local p=plan(s,d);eq(p.fallback.kind,"selectionBlocked")
    assert(p.fallback.text:find("任务日志已满",1,true));assert(#p.taskChoices>0)
    for _,choice in ipairs(p.taskChoices) do assert(choice.acceptBlocked) end
    s.quests[1]={title="已接任务",objectives={{text="继续目标"}}}
    p=plan(s,d);eq(p.fallback.kind,"objective");eq(p.fallback.questId,1);eq(p.taskChoices[1].acceptBlocked,nil)
    s.quests[1].ready=true;p=plan(s,d);eq(p.fallback.kind,"turnin")
    s.quests[1]=nil;s.completed[1]=true;s.questCount=19
    p=plan(s,d);eq(p.fallback.kind,"accept")
    for _,choice in ipairs(p.taskChoices) do eq(choice.acceptBlocked,nil) end
end)
test("手动锁定不能绕过容量，未知上限只阻止新的接取",function()
    local s,d=fixture();s.locked=1;s.questLimit=1;s.quests[2]={ready=true}
    local p=plan(s,d);eq(p.fallback.kind,"selectionBlocked");eq(s.locked,1);eq(s.completed[2],nil)
    s.questLimit=nil;p=plan(s,d);assert(p.fallback.text:find("上限尚未确认",1,true))
    s.quests[1]={objectives={{text="已接目标"}}}
    p=plan(s,d);eq(p.fallback.questId,1);eq(p.fallback.kind,"objective")
    s.quests[1]=nil;s.quests[2]=nil;s.questLimit=1
    p=plan(s,d);eq(p.fallback.kind,"accept");eq(p.fallback.questId,1)
end)
test("满日志提示同步到主列表总览与预览，未接状态保持真实",function()
    local s,d=fixture();s.questLimit,s.questCount=20,20
    local p=plan(s,d)
    local B={state=s,char={},plan=p,Navigation={Current=function() return p.fallback end},Planner=A.Planner,settings={}}
    for _,file in ipairs({"UI/Main.lua","UI/Tracker.lua","UI/Plan.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    local model=B.UI.TrackerModel(s,p,p.fallback,false)
    assert(model.rows[1].progress:find("任务日志已满",1,true));eq(model.rows[1].accepted,false)
    local summary=table.concat(B.UI:TaskLines(),"\n")
    assert(summary:find("未接取任务",1,true));assert(summary:find("任务日志已满",1,true))
    B.UI.Plan.preview=p.taskChoices[1]
    local preview=table.concat(B.UI.Plan:Lines(),"\n")
    assert(preview:find("[未接取] 任务日志已满",1,true))
    assert(not preview:find("先向任务发布者接取",1,true))
end)

end
