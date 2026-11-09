return function(test,eq,F,A,plan)
local function fixture(quests)
    local data=F.Data(quests)
    local state=F.State()
    local B={Data=data,Content=data.content,Eligibility=A.Eligibility,ready=true,char={deferredChains={},skipped={},turnIns={}},
        state=state,Navigation={Current=function() return {questId=1} end},UI={},refreshes=0}
    state.skipped=B.char.skipped
    B.State={Status=A.State.Status,Refresh=function(_,force)
        eq(force,true);B.refreshes=B.refreshes+1;state.revision=state.revision+1;B.Chains:Snapshot(state)
    end}
    assert(loadfile("Planner/Chains.lua"))("AiLeveling",B)
    assert(loadfile("Planner/Selection.lua"))("AiLeveling",B)
    data.chainIndex=B.Chains.NewIndex()
    local ids={}
    for id in pairs(quests) do ids[#ids+1]=id end
    table.sort(ids)
    for _,id in ipairs(ids) do B.Chains.IndexQuest(data.chainIndex,quests[id],data) end
    B.Chains:Snapshot(state)
    return B
end
local function linked(count)
    local quests={}
    for id=1,count do
        quests[id]=F.Quest(id)
        if id>1 then quests[id].preQuestGroup={id-1} end
    end
    return quests
end
local function edge(index,from,to,kind)
    for _,e in ipairs(index.outgoing[from] or {}) do if e.to==to and e.kind==kind then return e end end
end
test("任务关系区分精确交付可替代前置与任一分支",function()
    local qs=linked(7)
    qs[1].exclusiveTo={5};qs[2].exclusiveTo={6}
    qs[7].preQuestGroup={-1,2};qs[7].preQuestSingle={3,4}
    local B=fixture(qs);local index=B.Data.chainIndex
    assert(edge(index,1,7,"all").exact);eq(edge(index,5,7,"alternative"),nil)
    eq(edge(index,6,7,"alternative").group,2);assert(edge(index,3,7,"any"));assert(edge(index,4,7,"any"))
    eq(B.Chains.Label(edge(index,1,7,"all")),"全部·精确交付")
    B.state.completed[1]=true;B.state.quests[3]={ready=true,objectives={}}
    local graph=B.Chains.Graph(7,B.Data,B.state)
    eq(graph.byId[1].status,"turnedIn");eq(graph.byId[3].status,"ready");eq(graph.byId[7].eligible,false)
end)
test("互斥关闭和禁接关系不扩大整链暂缓范围",function()
    local qs={[1]=F.Quest(1),[2]=F.Quest(2),[3]=F.Quest(3),[4]=F.Quest(4),[5]=F.Quest(5)}
    qs[1].exclusiveTo={2};qs[2].exclusiveTo={1};qs[3].availableUntilCompleted=1;qs[4].disabledByQuest=1;qs[5].nextQuestInChain=1
    local B=fixture(qs);local members=B.Chains.Descendants(1,B.Data.chainIndex)
    eq(#members.ids,1);eq(members.members[2],nil);eq(members.members[3],nil);eq(members.members[4],nil)
    local graph=B.Chains.Graph(1,B.Data,B.state)
    eq(graph.cycle,nil);eq(#graph.nodes,5)
end)
test("依赖循环终止且缺失前置去重展示",function()
    local qs=linked(2);qs[1].preQuestGroup={2,99,99}
    local B=fixture(qs);local graph=B.Chains.Graph(1,B.Data,B.state)
    eq(graph.cycle,true);eq(graph.byId[99].status,"missing")
    eq(#B.Chains.Descendants(1,B.Data.chainIndex).ids,2)
    local nodes=B.Chains.Explain(1,B.Data,B.state);local missing=0
    for _,node in ipairs(nodes) do if node.id==99 then missing=missing+1 end end
    eq(missing,1)
end)
test("整链预览只读并在应用后保存独立起点偏好",function()
    local B=fixture(linked(3));B.state.quests[2]={ready=true,objectives={}};B.state.completed[1]=true
    local oldMap=B.state.chainDeferred
    local preview=B.Chains.Preview(1,B.Data,B.state)
    eq(#preview.ids,3);eq(next(B.char.deferredChains),nil);eq(B.refreshes,0)
    assert(B.Chains:Defer(preview));eq(B.char.deferredChains[1],true)
    eq(B.state.chainDeferred[3],1);eq(B.state.quests[2].ready,true);eq(B.state.completed[1],true)
    eq(B.state.completed[2],nil);eq(oldMap[2],nil);eq(next(B.char.skipped),nil)
    eq(A.Eligibility.Check(B.Data:GetQuest(2),B.state,B.Data),false)
end)
test("恢复一个链起点保留重叠整链与独立单任务暂缓",function()
    local B=fixture(linked(3))
    assert(B.Chains:Defer(B.Chains.Preview(1,B.Data,B.state)))
    assert(B.Chains:Defer(B.Chains.Preview(2,B.Data,B.state)))
    B.char.skipped[3]=true
    assert(B.Chains:Restore(1));eq(B.char.deferredChains[2],true);eq(B.state.chainDeferred[3],2)
    assert(B.Chains:Restore(2));eq(B.state.chainDeferred[3],nil);eq(B.char.skipped[3],true)
end)
test("整链暂缓应用拒绝过期预览篡改范围与活动副本冲突",function()
    local B=fixture(linked(3));local p=B.Chains.Preview(1,B.Data,B.state)
    B.state.revision=B.state.revision+1;eq(B.Chains:Defer(p),false)
    p=B.Chains.Preview(1,B.Data,B.state);B.refreshAt=1;eq(B.Chains:Defer(p),false);B.refreshAt=nil
    p.ids[1]=99;eq(B.Chains:Defer(p),false)
    p=B.Chains.Preview(1,B.Data,B.state);B.char.dungeon={phase="running"};eq(B.Chains:Defer(p),false)
    eq(B.refreshes,0);eq(next(B.char.deferredChains),nil)
    eq(B.Chains:Defer({root=1}),false);eq(B.Chains.Preview(999,B.Data,B.state),nil)
end)
test("暂缓整链解除冲突行程和装备目标且不放弃原生任务",function()
    local B=fixture(linked(3));B.char.locked=3
    B.char.itinerary={sequence="2>3",baselines={[2]=0,[3]=0}}
    B.char.gearTarget="wanted";B.char.gearBaseline=0;B.Content.gearSources={wanted={questId=3}}
    B.state.quests[3]={objectives={}}
    assert(B.Chains:Defer(B.Chains.Preview(1,B.Data,B.state)))
    eq(B.char.itinerary,nil);eq(B.char.locked,nil);eq(B.char.gearTarget,nil);assert(B.state.quests[3])
    eq(B.Selection:LockQuest(3),false)
end)
test("暂缓整链后未验证目标定位也不重新推荐该任务",function()
    local q=F.Quest(1);q.verified=false
    local B=fixture({[1]=q});B.state.quests[1]={objectives={}}
    assert(B.Chains:Defer(B.Chains.Preview(1,B.Data,B.state)))
    local result=plan(B.state,B.Data)
    eq(result.best,nil);eq(result.fallback,nil);eq(B.state.completed[1],nil)
end)
test("自有新增任务进入等级资格和关系索引且不改上游 ID 表",function()
    local B={Content={quests={[2]={title="自有任务",questLevel=21,requiredSkill={123,5},preQuestGroup={1}},
        [3]={title="随等级任务",questLevel=-1,requiredLevel=20}}}}
    assert(loadfile("Planner/Chains.lua"))("AiLeveling",B)
    assert(loadfile("Data/Questie.lua"))("AiLeveling",B)
    local ids={1};local source={name="上游任务",questLevel=20,requiredLevel=1}
    local db={RequireContract=function() return true end,Support={Get=function(name)
        return name=="QuestXP" and {db={[1]={20,1234}}} or {}
    end},
        Enum={npcFlags={VENDOR=4,REPAIR=16384}},Npc={GetAllIds=function() return {} end},Quest={
        Get=function(id,key) if id==1 and key=="objectives" then return {[4]={72,3000}} end end,
        GetAllIds=function() return ids end,GetAll=function(id,fields)
            if id~=1 then return end
            local values={};for i,key in ipairs(fields) do values[i]=source[key] end;return values
        end}}
    assert(B.Data:Connect(db));eq(#ids,1);eq(#B.Data.ids,3)
    local co=coroutine.create(function() B.Data:BuildIndex() end)
    repeat local ok,why=coroutine.resume(co);assert(ok,why) until coroutine.status(co)=="dead"
    eq(B.Data.count,3);eq(B.Data.byLevel[21][1],2);eq(B.Data.requirements.skills[123],true)
    local candidates=B.Data:Candidates({level=30,quests={}});eq(#candidates,1);eq(candidates[1],3)
    eq(B.Data.requirements.reputations[72],true)
    assert(edge(B.Data.chainIndex,1,2,"all"));eq(B.Data:GetQuest(2).title,"自有任务")
    source.name="另一个角色上下文";assert(B.Data:Connect(db));eq(B.Data:GetQuest(1).title,"另一个角色上下文")
    eq(B.Data:GetQuest(1).referenceXP,1234);eq(B.Data:GetQuest(1).referenceXPLevel,20)
    for _,bad in ipairs({{0,100},{20,-1},{20,math.huge},{20,"100"},{1.5,100},{61,100}}) do
        B.Data.xp[1]=bad;B.Data.cache={};eq(B.Data:GetQuest(1).referenceXP,nil)
    end
end)

local function widget()
    local w={scripts={}}
    for _,name in ipairs({"SetPoint","ClearAllPoints","SetWidth","SetHeight","SetAllPoints","SetMaxLines","SetBackdropColor","SetColorTexture","SetAutoFocus","SetFontObject","ClearFocus"}) do w[name]=function() end end
    w.SetMaxLetters=function(self,n) self.maxLetters=n end
    w.SetSize=function(self,width,height) self.width,self.height=width,height end
    w.SetText=function(self,text) self.textValue=text end;w.GetText=function(self) return self.textValue or "" end
    w.Show=function(self) self.shown=true end;w.Hide=function(self) self.shown=false end
    w.SetEnabled=function(self,value) self.enabled=value end
    w.SetScript=function(self,event,callback) self.scripts[event]=callback end
    w.SetScrollChild=function(self,child) self.child=child end
    w.SetHorizontalScroll=function(self,x) self.x=x end;w.SetVerticalScroll=function(self,y) self.y=y end
    w.GetVerticalScroll=function(self) return self.y or 0 end
    w.GetStringHeight=function(self) return #(self.textValue or "")/4 end
    w.CreateTexture=function() return widget() end
    return w
end
local function uiFixture(quests)
    local B=fixture(quests or linked(5))
    B.UI.Text=function() return widget() end;B.UI.Panel=function() return widget() end
    B.UI.Button=function(_,parent,label,width,callback)
        local b=widget();b.text=widget();b.text:SetText(label);b.callback=callback;return b
    end
    assert(loadfile("UI/Chains.lua"))("AiLeveling",B)
    B.UI.SelectTab=function() B.UI.Chains:Refresh() end
    local saved=CreateFrame;CreateFrame=function() return widget() end
    B.UI.Chains:Create({});B.UI.Chains:Refresh()
    B.savedCreateFrame=saved
    return B
end
local function done(B) CreateFrame=B.savedCreateFrame end
test("原生图形任务链入口显示节点关系并沿点击聚焦返回",function()
    local B=uiFixture();local U=B.UI.Chains
    eq(U.focus,1);eq(#U.cards,5);assert(#U.lines>=4);eq(U.input.maxLetters,10)
    local second
    for _,card in ipairs(U.cards) do if card.questId==2 then second=card end end
    assert(second);second.callback();eq(U.focus,2);eq(U.history[1],1)
    U.back.callback();eq(U.focus,1)
    U.input:SetText("5");U.input.scripts.OnEnterPressed();eq(U.focus,5)
    assert(U.lock.enabled);U.lock.callback();eq(B.char.locked,5)
    done(B)
end)
test("原生暂缓入口先预览名单再应用且恢复保留单任务暂缓",function()
    local B=uiFixture();local U=B.UI.Chains;B.char.skipped[3]=true
    U.defer.callback();eq(next(B.char.deferredChains),nil);eq(#U.preview.ids,5)
    eq(U.defer.text.textValue,"应用暂缓");assert(U.info.textValue:find("暂缓范围：5",1,true))
    U.defer.callback();eq(B.char.deferredChains[1],true);eq(U.preview,nil);eq(U.restore.enabled,true)
    U.restore.callback();eq(B.char.deferredChains[1],nil);eq(B.char.skipped[3],true)
    done(B)
end)
test("大图关联入口和分页名单覆盖视口之外的后续任务",function()
    local qs={[1]=F.Quest(1)};for id=2,81 do qs[id]=F.Quest(id);qs[id].preQuestSingle={1} end
    local B=uiFixture(qs);local U=B.UI.Chains
    eq(#U.cards,40);eq(#U.graph.related,80)
    U.relatedIndex=80;U:Refresh();U.visit.callback();eq(U.focus,81);assert(U.graph.byId[81])
    U:Focus(1);U.defer.callback();eq(#U.preview.ids,81)
    U:Pan(1);eq(U.page,2);assert(U.info.textValue:find("第 2/7 页",1,true))
    U:Focus(2);eq(U.preview,nil);eq(next(B.char.deferredChains),nil)
    done(B)
end)
test("图形横向平移更新控制且过期暂缓预览不会应用",function()
    local B=uiFixture(linked(15));local U=B.UI.Chains
    local original=U.offset or 0;U:Pan(1);assert(U.offset>original);eq(U.left.enabled,true)
    local panned=U.offset;B.state.revision=B.state.revision+1;U:Refresh();eq(U.offset,panned)
    U:Pan(-1);eq(U.offset,original)
    U.defer.callback();B.state.revision=B.state.revision+1;U:Refresh()
    eq(U.preview,nil);eq(next(B.char.deferredChains),nil)
    done(B)
end)

local function preparationFixture()
    local quests={}
    for id=1,5 do quests[id]=F.Quest(id);quests[id].verified=false end
    local data,state=F.Data(quests),F.State()
    data.Target=function(_,q) return {map=q.id==1 and 1 or 2,x=q.id/10,y=0.5} end
    local B={Navigation=F.Navigation,Data=data,Content=data.content,state=state,char={locked=1,skipped={}},ready=true,
        settings={minutes=60,mode="fast",dungeons=true,role="DAMAGER"}}
    for _,file in ipairs({"State.lua","Planner/Eligibility.lua","Planner/Chains.lua","Planner/Travel.lua","Planner/Gear.lua",
        "Planner/Progression.lua","Planner/Supplies.lua","Planner/Dungeon.lua","Planner/DungeonTasks.lua",
        "Planner/TaskGuide.lua","Planner/TaskQueue.lua","Planner/Planner.lua","Planner/Selection.lua","UI/Main.lua","UI/Tracker.lua"}) do
        assert(loadfile(file))("AiLeveling",B)
    end
    return B,state,data,quests
end

test("选择后续任务后跨地图完成前置并逐项交付，再回到原目标",function()
    local B,s,d,q=preparationFixture();q[1].preQuestGroup={2};q[2].preQuestGroup={3};s.locked=1
    local p=plan(s,d,B.settings,B)
    eq(p.fallback.questId,3);eq(p.fallback.kind,"accept");eq(p.preparingQuest.id,1)
    local model=B.UI.TrackerModel(s,p,p.fallback,false);assert(model.hint:find(q[1].title,1,true))
    s.quests[3]={objectives={{text="前置目标"}}};p=plan(s,d,B.settings,B);eq(p.fallback.kind,"objective")
    s.quests[3].ready=true;p=plan(s,d,B.settings,B);eq(p.fallback.questId,3);eq(p.fallback.kind,"turnin")
    eq(s.completed[3],nil);eq(s.completed[2],nil);eq(s.locked,1);eq(B.char.locked,1)
    s.completed[3]=true;s.quests[3]=nil;p=plan(s,d,B.settings,B);eq(p.fallback.questId,2);eq(p.fallback.kind,"accept")
    s.completed[2]=true;p=plan(s,d,B.settings,B);eq(p.fallback.questId,1);eq(p.preparingQuest,nil)
    eq(s.completed[1],nil);eq(s.locked,1)
end)
test("前置准备遵守全部任一及可替代关系，完成一个备选即不再做其余分支",function()
    local B,s,d,q=preparationFixture();q[1].preQuestGroup={2};q[2].preQuestSingle={3,4}
    eq(table.concat(B.Chains.Preparation(1,d,s),","),"3,4")
    s.completed[3]=true;eq(table.concat(B.Chains.Preparation(1,d,s),","),"2")
    q[1].preQuestGroup={2,5};eq(table.concat(B.Chains.Preparation(1,d,s),","),"2,5")
    q[2].exclusiveTo={5};s.completed[5]=true
    eq(table.concat(B.Chains.Preparation(1,d,s),","),"1")
    q[1].preQuestGroup={-2};eq(#B.Chains.Preparation(1,d,s),0)
end)
test("准备前置不绕过角色资格暂缓未知关系与缺失资料，也不遍历无法完成的必需分支",function()
    local B,s,d,q=preparationFixture();q[1].preQuestGroup={2,99}
    eq(#B.Chains.Preparation(1,d,s),0)
    q[1].preQuestGroup={2};q[1].requiredSkill={164,75};eq(#B.Chains.Preparation(1,d,s),0)
    s.skills[164]=75;eq(B.Chains.Preparation(1,d,s)[1],2)
    q[2].requiredRaces=2;eq(#B.Chains.Preparation(1,d,s),0);q[2].requiredRaces=0
    s.skipped[2]=true;eq(#B.Chains.Preparation(1,d,s),0);s.skipped[2]=nil
    s.chainDeferred={[2]=2};eq(#B.Chains.Preparation(1,d,s),0);s.chainDeferred=nil
    s.completionKnown=false;eq(#B.Chains.Preparation(1,d,s),0);s.completionKnown=true
    q[1].preQuestGroup=nil;q[1].preQuestSingle={-2};eq(#B.Chains.Preparation(1,d,s),0)
    q[1].preQuestSingle={2};d.Target=function() return nil end;eq(#B.Chains.Preparation(1,d,s),0)
end)
test("父任务只需接取时不强制交付，前置循环保留可行的其他分支",function()
    local B,s,d,q=preparationFixture();q[1].parentQuest=2
    eq(B.Chains.Preparation(1,d,s)[1],2)
    s.quests[2]={ready=true};eq(B.Chains.Preparation(1,d,s)[1],1)
    s.quests[2]=nil;s.completed[2]=true;eq(#B.Chains.Preparation(1,d,s),0)
    q[1].parentQuest=nil;q[1].availableStartingWith=2;eq(B.Chains.Preparation(1,d,s)[1],1)
    q[1].availableStartingWith=nil;s.completed[2]=nil
    q[1].preQuestSingle={2,3};q[2].preQuestGroup={1}
    eq(table.concat(B.Chains.Preparation(1,d,s),","),"3")
    q[3].preQuestGroup={1};eq(#B.Chains.Preparation(1,d,s),0)
end)
test("副本前置入口锁定原任务并在状态变化后重查准备条件",function()
    local B,s,d,q=preparationFixture();q[1].preQuestGroup={2}
    local dungeon={reference=true,quests={Alliance={[1]="inside"}}};s.faction="Alliance"
    B.State.Refresh=function() end
    local rows=B.Dungeon.Tasks(dungeon,s,d);eq(rows[1].allowed,false);eq(rows[1].preparation[1],2)
    eq(B.Dungeon:ContinueTask(dungeon,1),true);eq(B.char.locked,1)
    s.skipped[2]=true;eq(B.Dungeon.Tasks(dungeon,s,d)[1].preparation,nil)
    local ok,why=B.Dungeon:ContinueTask(dungeon,1);eq(ok,false);eq(why,"前置未交付")
end)

test("前置准备日志满时仍可交付已接分支，空出栏位后接取原目标",function()
    local B,s,d,q=preparationFixture();q[1].preQuestSingle={2,3};s.locked=1
    s.questCount,s.questLimit=20,20
    local p=plan(s,d,B.settings,B);eq(p.fallback.kind,"selectionBlocked")
    assert(p.fallback.text:find("任务日志已满",1,true));eq(s.locked,1)
    s.quests[3]={ready=true,objectives={}}
    p=plan(s,d,B.settings,B);eq(p.preparingQuest.id,1);eq(p.fallback.questId,3);eq(p.fallback.kind,"turnin")
    s.quests[3]=nil;s.completed[3]=true
    p=plan(s,d,B.settings,B);eq(p.fallback.kind,"selectionBlocked")
    s.questCount=19;p=plan(s,d,B.settings,B);eq(p.fallback.questId,1);eq(p.fallback.kind,"accept")
    eq(s.completed[2],nil);eq(B.char.locked,1)
end)

end
