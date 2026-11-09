return function(test,eq,F,A,plan)
local names={"UnitGUID","UnitName","GetTime","GetBindLocation","C_Trainer","Enum","GetNumTrainerServices","GetTrainerServiceInfo","GetTrainerServiceCost","canaccessvalue",
    "BuyTrainerService","SetTrainerServiceTypeFilter","ExpandTrainerSkillLine","ConfirmBinder",
    "GetTrainerServiceSkillReq","GetTrainerServiceNumAbilityReq","GetTrainerServiceAbilityReq"}
local function setup()
    local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
    local B={};for k,v in pairs(A) do B[k]=v end
    B.char={locked=42,itinerary={quests={42}},samples={}};B.state=F.State();B.state.position={map=1,x=0.5,y=0.5};B.state.money=20
    B.ready=true;B.indexReady=true;B.jobs={};B.Roads=nil;B.TaskGuide=nil
    B.State={Position=function() end,Refresh=function() B.Services:Snapshot(B.state);B.state.revision=B.state.revision+1 end}
    B.Observations={Reset=function() end};B.Transport={InFlight=function() return B.flying end}
    B.Navigation={Distance=function(_,a,b) return a.map==b.map and math.abs(a.x-b.x)*1000 or nil end}
    B.Navigation.Near=function(self,a,b,radius) local d=self:Distance(a,b);return d and d<=radius end
    assert(loadfile("Services.lua"))("AiLeveling",B);assert(loadfile("Planner/Planner.lua"))("AiLeveling",B)
    local e={npc=78,now=1,binding="旧旅店",kind=0,rows={{name="训练项目",status="available",sub="等级 1",cost=30},{name="下一等级",status="unavailable",cost=90}}}
    UnitGUID=function() return "Creature-0-1-2-3-"..e.npc.."-0001" end;UnitName=function() return "训练师" end
    GetTime=function() return e.now end;GetBindLocation=function() return e.binding end
    Enum={TrainerType={General=0,Tradeskills=2,Pet=3}};C_Trainer={GetTrainerType=function() return e.kind end}
    GetNumTrainerServices=function() return #e.rows end
    GetTrainerServiceInfo=function(i) local r=e.rows[i];return r.name,r.status,1,r.level or 10,r.sub end
    GetTrainerServiceCost=function(i) return e.rows[i].cost end
    GetTrainerServiceSkillReq=function(i) local r=e.rows[i];return r.skill,r.rank,r.skillMet end
    GetTrainerServiceNumAbilityReq=function(i) local r=e.rows[i];return r.abilityCount or #(r.abilities or {}) end
    GetTrainerServiceAbilityReq=function(i,j) local r=e.rows[i].abilities[j];return r.name,r.met end
    canaccessvalue=nil
    for _,key in ipairs({"BuyTrainerService","SetTrainerServiceTypeFilter","ExpandTrainerSkillLine","ConfirmBinder"}) do
        _G[key]=function() error("训练绑定和窗口筛选必须由玩家操作") end
    end
    return B,e,function() for _,name in ipairs(names) do _G[name]=saved[name] end end
end
local function chooseTraining(B)
    B.Services:Event("TRAINER_SHOW");B.Services:Snapshot(B.state)
    local rows=B.Services:Choices("learn");assert(B.Services:Pick(rows[1],B.state.revision));return B.char.serviceStop
end
test("训练快照读取原生状态金币与费用类型且关闭后不保留旧列表",function()
    local B,e,finish=setup();local S=B.Services
    S:Event("TRAINER_SHOW");local first=S:Snapshot(B.state);local t=B.state.trainer
    eq(t.npcId,78);eq(t.rows[1].status,"available");eq(t.rows[1].cost,30);eq(t.rows[1].affordable,false)
    e.rows[1].cost=10;assert(S:Snapshot(B.state)~=first);eq(B.state.trainer.rows[1].affordable,true)
    e.kind=3;S:Snapshot(B.state);eq(B.state.trainer.rows[1].cost,nil)
    local rows=S:Choices("learn");eq(S:CanPick(rows[1],B.state.revision),false)
    e.kind=0;e.rows[1].cost=0/0;S:Snapshot(B.state);eq(B.state.trainer.rows[1].cost,nil)
    canaccessvalue=function(value) return type(value)~="string" end;S:Snapshot(B.state);eq(B.state.trainer,nil)
    canaccessvalue=nil;S:Event("TRAINER_CLOSED");S:Snapshot(B.state);eq(B.state.trainer,nil)
    finish()
end)
test("训练专业与前置技能条件影响状态指纹并区分未满足和未知",function()
    local B,e,finish=setup();local S=B.Services;local r=e.rows[1]
    r.skill,r.rank,r.skillMet="炼金术",75,false;r.abilities={{name="初级炼金术",met=true}}
    S:Event("TRAINER_SHOW");local before=S:Snapshot(B.state);local offer=B.state.trainer.rows[1]
    eq(offer.requirementsBlocked,true);eq(offer.requirementsPending,nil);eq(#offer.requirements,2)
    eq(S.TrainingNeeds(offer,B.state),"炼金术 75")
    local choices=S:Choices("learn");eq(S:CanPick(choices[1],B.state.revision),false)
    B.UI={};assert(loadfile("UI/Services.lua"))("AiLeveling",B);B.UI.Services.preview=choices[1]
    local lines=table.concat(B.UI.Services:Lines(),"\n")
    assert(lines:find("炼金术 75 · 未满足",1,true));assert(lines:find("初级炼金术 · 已满足",1,true))
    r.skillMet=true;assert(S:Snapshot(B.state)~=before);eq(B.state.trainer.rows[1].requirementsBlocked,nil)
    r.level=30;S:Snapshot(B.state);choices=S:Choices("learn");eq(S:CanPick(choices[1],B.state.revision),false);r.level=10
    r.skillMet={};canaccessvalue=function(v) return type(v)~="table" end
    S:Snapshot(B.state);offer=B.state.trainer.rows[1]
    eq(offer.requirements[1].met,nil);eq(offer.requirementsPending,true);eq(offer.requirementsBlocked,nil)
    canaccessvalue=nil;r.abilityCount=65;GetTrainerServiceSkillReq=nil
    S:Snapshot(B.state);eq(B.state.trainer.rows[1].requirementsPending,true)
    eq(#B.state.trainer.rows[1].requirements,0)
    finish()
end)
test("当前训练项目优先可学且付得起，资金与学习条件变化更新排序",function()
    local B,e,finish=setup();local S=B.Services
    e.rows={{name="已学",status="used",cost=0},{name="条件不足",status="unavailable",cost=0},
        {name="昂贵",status="available",cost=30},{name="可学",status="available",cost=10}}
    S:Event("TRAINER_SHOW");local before=S:Snapshot(B.state)
    local rows=S:Choices("learn");eq(rows[1].offer.name,"可学");eq(rows[2].offer.name,"昂贵")
    eq(rows[3].offer.name,"条件不足");eq(rows[4].offer.name,"已学")
    B.state.money=40;assert(S:Snapshot(B.state)~=before);rows=S:Choices("learn");eq(rows[1].offer.name,"昂贵")
    e.rows[3].skill,e.rows[3].rank,e.rows[3].skillMet="炼金术",75,false
    S:Snapshot(B.state);rows=S:Choices("learn");eq(rows[1].offer.name,"可学");eq(S:CanPick(rows[2],B.state.revision),false)
    finish()
end)
test("已安排训练显示实际缺少条件或资金且不自动学习或误完成",function()
    local B,e,finish=setup();local stop=chooseTraining(B);local S=B.Services
    local action=S.Build(B.state).fallback;assert(action.text:find("还差 10 铜",1,true))
    e.rows[1].skill,e.rows[1].rank,e.rows[1].skillMet="炼金术",75,false
    e.rows[1].abilities={{name="初级炼金术",met=false}};e.rows[1].level=30
    S:Snapshot(B.state);action=S.Build(B.state).fallback
    assert(action.text:find("等级 30、炼金术 75、初级炼金术",1,true));eq(B.char.serviceStop,stop)
    e.rows[1].skillMet=true;e.rows[1].abilities[1].met=true;e.rows[1].level=10;B.state.money=40
    S:Snapshot(B.state);action=S.Build(B.state).fallback;assert(action.text:find("原生训练窗口学习",1,true))
    e.rows[1].status="used";S:Snapshot(B.state);eq(B.char.serviceStop,nil)
    finish()
end)
test("训练完成只认同NPC同项目已学会且筛选消失和同名歧义保持安排",function()
    local B,e,finish=setup();local stop=chooseTraining(B);eq(B.char.locked,42);assert(B.char.itinerary)
    e.rows={};B.Services:Snapshot(B.state);eq(B.char.serviceStop,stop)
    e.rows={{name="训练项目",status="used",sub="等级 1",cost=0}};e.npc=79;B.Services:Snapshot(B.state);eq(B.char.serviceStop,stop)
    e.npc=78;e.rows[2]={name="训练项目",status="available",sub="等级 1",cost=30}
    B.Services:Snapshot(B.state);eq(B.char.serviceStop,stop)
    local rows=B.Services:Choices("learn");eq(B.Services:CanPick(rows[2],B.state.revision),false)
    e.rows[2]=nil;B.Services:Snapshot(B.state);eq(B.char.serviceStop,nil);eq(B.char.locked,42);assert(B.char.itinerary)
    finish()
end)
test("服务选择拒绝过期对象飞行死亡副本和不可学项目且持久意图独立复制",function()
    local B,e,finish=setup();B.Services:Event("TRAINER_SHOW");B.Services:Snapshot(B.state)
    local rows=B.Services:Choices("learn");eq(B.Services:CanPick(rows[2],B.state.revision),false)
    B.refreshAt=1;eq(B.Services:Pick(rows[1],B.state.revision),false);B.refreshAt=nil
    B.flying=true;eq(B.Services:Pick(rows[1],B.state.revision),false);B.flying=false
    B.char.dungeon={};eq(B.Services:Pick(rows[1],B.state.revision),false);B.char.dungeon=nil
    B.state.dead=true;eq(B.Services:Pick(rows[1],B.state.revision),false);B.state.dead=false
    B.Services:Choices("learn");eq(B.Services:Pick(rows[1],B.state.revision),false)
    rows=B.Services:Choices("learn");assert(B.Services:Pick(rows[1],B.state.revision));local p=B.char.serviceStop.position
    rows[1].position.x=0;eq(p.x,0.5);B.state.serviceStop.position.x=0;eq(p.x,0.5)
    assert(B.Services.ValidStop(B.char.serviceStop));B.char.serviceStop.learnKey="\031";eq(B.Services.ValidStop(B.char.serviceStop),false)
    B.char.serviceStop.learnKey=nil;B.char.serviceStop.position.x=0/0;eq(B.Services.ValidStop(B.char.serviceStop),false)
    finish()
end)
test("炉石安排须关联所选旅店确认和真实绑定事件且取消重载超时不误完成",function()
    local B,e,finish=setup();local S=B.Services
    local function reset()
        B.char.serviceStop={kind="bind",npcId=78,title="旅店",position={map=1,x=0.5,y=0.5}}
        e.npc=78;e.now=1;e.binding="旧旅店";B.state.position.x=0.5
    end
    reset();S:Event("HEARTHSTONE_BOUND");assert(B.char.serviceStop)
    e.npc=79;S:Event("CONFIRM_BINDER","新旅店");e.binding="新旅店";S:Event("HEARTHSTONE_BOUND");assert(B.char.serviceStop)
    reset();S:Event("CONFIRM_BINDER","新旅店");e.binding="新旅店";e.now=62;S:Event("HEARTHSTONE_BOUND");assert(B.char.serviceStop)
    reset();S:Event("CONFIRM_BINDER","新旅店");S:Event("PLAYER_ENTERING_WORLD");e.binding="新旅店";S:Event("HEARTHSTONE_BOUND");assert(B.char.serviceStop)
    reset();S:Event("CONFIRM_BINDER","新旅店");e.binding="新旅店";B.state.position.x=0.9;S:Event("HEARTHSTONE_BOUND");assert(B.char.serviceStop)
    reset();S:Event("CONFIRM_BINDER","新旅店");e.binding="新旅店";S:Event("HEARTHSTONE_BOUND");eq(B.char.serviceStop,nil);eq(B.char.locked,42)
    reset();S:Cancel();e.binding="新旅店";S:Event("HEARTHSTONE_BOUND");eq(B.char.serviceStop,nil)
    finish()
end)
test("服务插入覆盖普通规划保留锁定且必要维修优先并在完成后恢复任务",function()
    local B,e,finish=setup();local stop=chooseTraining(B);local s=B.state
    s.locked=42;s.quests[42]={title="原任务",ready=true,objectives={}}
    local d=F.Data({});d.GetQuest=function(_,id) return id==42 and {id=42,title="原任务"} end
    d.Target=function() return {map=1,x=0.6,y=0.5} end
    local result=plan(s,d,{minutes=60,dungeons=false},B)
    eq(result.serviceStop,true);eq(result.best,nil);eq(result.fallback.npcId,78);eq(result.fallback.serviceKind,"train")
    eq(result.serviceResume.questId,42);eq(result.serviceResume.kind,"turnin")
    eq(B.Supplies.Done(result.fallback,s),false);eq(s.locked,42)
    s.durability=0.1;s.merchant={npcId=9,name="铁匠",canRepair=true,items={}}
    result=plan(s,d,{minutes=60,dungeons=false},B);eq(result.maintenance,true);eq(result.fallback.serviceKind,"repair")
    s.durability=1;e.rows[1].status="used";B.Services:Snapshot(s)
    result=plan(s,d,{minutes=60,dungeons=false},B);eq(result.serviceStop,nil);eq(result.fallback.questId,42)
    finish()
end)
test("服务目录只按直线距离且未知距离排后",function()
    local B,e,finish=setup()
    B.Data={AmenityPoints=function() return {
        {kind="bind",npcId=1,title="近点绕路",position={map=1,x=0.51,y=0.5}},
        {kind="bind",npcId=2,title="远点通路",position={map=1,x=0.6,y=0.5}}} end}
    B.Navigation.hbd={};B.Roads={Route=function(_,from,to) return {complete=true,length=to.x==0.51 and 1000 or 200} end}
    local rows=B.Services:Choices("bind");eq(rows[1].npcId,1)
    B.Roads.Route=function(_,from,to) if to.x==0.51 then return {complete=true,length=1000} end end
    rows=B.Services:Choices("bind");eq(rows[1].npcId,1)
    B.Roads=nil;B.Navigation.Distance=function(_,from,to) if to.x~=0.51 then return 100 end end
    rows=B.Services:Choices("bind");eq(rows[1].npcId,2)
    finish()
end)
test("服务点比较接续任务的总直线距离且过期规划不参与",function()
    local B,e,finish=setup();B.plan=nil
    B.Data={AmenityPoints=function() return {
        {kind="bind",npcId=1,title="身后旅店",position={map=1,x=0.45,y=0.5}},
        {kind="bind",npcId=2,title="前方旅店",position={map=1,x=0.7,y=0.5}}} end}
    local target={kind="objective",questId=42,title="原任务",position={map=1,x=0.9,y=0.5}}
    local function check(id) local rows=B.Services:Choices("bind");eq(rows[1].npcId,id);return rows end
    check(1)
    B.plan={revision=B.state.revision,fallback=target}
    local rows=check(2);eq(rows[1].resumeTitle,"原任务");assert(rows[1].journeyDistance<rows[2].journeyDistance)
    B.plan.revision=B.state.revision-1;eq(check(1)[1].resumeTitle,nil)
    B.plan.revision=B.state.revision;B.jobs.plan={};check(1);B.jobs.plan=nil
    B.refreshAt=1;check(1);B.refreshAt=nil
    B.plan.maintenance=true;check(1);B.plan.maintenance=nil
    B.plan.sessionActive=true;check(1);B.plan.sessionActive=nil
    B.plan.fallback={kind="service",position={map=1,x=0.45,y=0.5}};B.plan.serviceResume=target;check(2)
    -- An unknown onward distance cannot beat a complete two-leg comparison.
    local distance=B.Navigation.Distance
    B.Navigation.Distance=function(self,a,b) if a.x==0.7 and b.x==0.9 then return end;return distance(self,a,b) end
    check(1)
    B.plan.serviceResume=nil;B.plan.best={actions={{kind="move",position=B.state.position},target}}
    eq(B.Services.TaskDestination(B.plan),target)
    target.kind="dungeonBlocked";eq(B.Services.TaskDestination(B.plan),nil)
    finish()
end)
test("服务页显示后续任务且不显示内部路程评分",function()
    local B,e,finish=setup();B.UI={};assert(loadfile("UI/Services.lua"))("AiLeveling",B)
    local ui=B.UI.Services;ui.preview={kind="bind",npcId=1,title="旅店",position=B.state.position,
        resumeTitle="继续交付",journeyDistance=123456}
    local lines=table.concat(ui:Lines(),"\n")
    assert(lines:find("服务后继续：继续交付",1,true));assert(not lines:find("123456",1,true))
    assert(not lines:find("预计移动时间",1,true));finish()
end)
local function bindingFixture()
    local B,e,finish=setup();local s=B.state
    B.FlightData=nil;B.PublicTransitData=nil;B.Travel=A.Travel;B.Estimates={hearthSeconds=10}
    assert(loadfile("Hearth.lua"))("AiLeveling",B);assert(loadfile("Planner/Flights.lua"))("AiLeveling",B)
    B.Navigation.Distance=function(_,a,b) if a.map==b.map then return math.abs(a.x-b.x)*7000 end end
    s.position={map=1,x=0,y=0};s.now=0;s.runSpeed=7;s.quests={[42]={}}
    s.hearthPoint={map=1,x=0,y=0};s.hearthBindingKey="old";s.hearthReady=0;s.hearthCooldown=3600;s.bags={[6948]=1}
    local stages={{kind="objective",questId=42,title="原任务",position={map=1,x=1,y=0}},
        {kind="turnin",questId=42,title="交付",position={map=1,x=0.8,y=0}}}
    local choice={questId=42,stages=stages,stagesComplete=true}
    local p={revision=s.revision,taskOrder={choice},fallback=stages[1]}
    local inns={{kind="bind",npcId=1,title="近旅店",position={map=1,x=0.05,y=0}},
        {kind="bind",npcId=2,title="交付地旅店",position={map=1,x=0.8,y=0}}}
    B.Data={AmenityPoints=function() return inns end};B.plan=p
    return B,s,p,inns,finish,e
end
local function automaticFixture()
    local B,s,_,inns,finish,e=bindingFixture()
    B.char.locked=nil;B.char.itinerary=nil;s.position.x=0.79
    for _,file in ipairs({"Planner/TaskGuide.lua","Planner/TaskQueue.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    local q={id=42,title="原任务",questLevel=20}
    local d=F.Data({[42]=q})
    local recipient=inns[2].position
    d.AmenityPoints=function() return inns end
    d.Target=function(_,quest,state) return {map=1,x=state.quests[42].ready and recipient.x or 1,y=0,objectiveIndex=1} end
    d.ObjectiveTargets=function() return {{map=1,x=1,y=0,objectiveIndex=1}} end
    B.Data=d;s.quests[42]={title="原任务",objectives={{text="目标",numRequired=1,numFulfilled=0,finished=false}}}
    local function rebuild()
        B.Services:Snapshot(s);B.plan=plan(s,d,{minutes=60,dungeons=false},B);return B.plan
    end
    return B,s,inns,finish,e,rebuild
end
test("自动旅店安排从完整任务规划进入行动并在原生绑定后继续任务",function()
    local B,s,inns,finish,e,rebuild=automaticFixture();local S=B.Services
    local p=rebuild();eq(p.automaticService.npcId,2);eq(p.fallback.serviceKind,"bind");eq(p.serviceResume.questId,42)
    eq(B.char.serviceStop,nil);eq(s.hearthPoint.x,0);eq(s.quests[42].objectives[1].finished,false)
    assert(p.fallback.text:find("服务页取消",1,true))
    s.position={map=1,x=0.8,y=0};e.npc=2;rebuild()
    S:Event("HEARTHSTONE_BOUND");eq(B.Hearth.landing,nil)
    S:Event("CONFIRM_BINDER","交付地旅店");assert(S.binding)
    e.binding="交付地旅店";s.bindName=e.binding
    B.Hearth:Event("HEARTHSTONE_BOUND");S:Event("HEARTHSTONE_BOUND");B.Hearth:Snapshot(s)
    eq(s.hearthPoint.x,0.8);eq(s.quests[42].objectives[1].finished,false)
    p=rebuild();eq(p.automaticService,nil);eq(p.serviceStop,nil);eq(p.fallback.questId,42);eq(p.fallback.kind,"objective")
    eq(B.char.serviceStop,nil);finish()
end)
test("自动换绑取消后同批任务不重复，进度走动重载保留且新任务重新评估",function()
    local B,s,inns,finish,e,rebuild=automaticFixture();local S=B.Services
    rebuild();S:Cancel();local declined=B.char.declinedBinding;eq(declined,"42:0")
    eq(rebuild().automaticService,nil);eq(B.plan.fallback.questId,42)
    s.position.x=0.01;s.quests[42].objectives[1].numFulfilled=1
    eq(rebuild().automaticService,nil);eq(B.char.declinedBinding,declined)
    assert(loadfile("Services.lua"))("AiLeveling",B);S=B.Services
    eq(rebuild().automaticService,nil)
    -- An explicit service choice is still allowed after declining automatic advice.
    local rows=S:Choices("bind");assert(S:Pick(rows[1],s.revision));eq(B.char.serviceStop.npcId,2)
    S:Cancel();B.char.turnIns={[42]=1};s.position.x=0.79
    assert(rebuild().automaticService);eq(s.bindingTaskKey,"42:1")
    S:Cancel();s.quests[43]={};S:Snapshot(s);assert(s.bindingTaskKey~=B.char.declinedBinding)
    finish()
end)
test("炉石只在交接据点附近建议绑定并保护当前任务和维护",function()
    local B,s,p,inns,finish=bindingFixture();local S=B.Services;S:Snapshot(s)
    p.bindingChoices=S.PlanBindings(p,s,B.Data)
    eq(S.AutomaticBinding(p,s),nil)
    s.position={map=1,x=0.79,y=0};assert(S.AutomaticBinding(p,s))
    s.hearthReady=nil;assert(S.AutomaticBinding(p,s))
    s.hearthPoint={map=1,x=0.81,y=0};eq(S.AutomaticBinding(p,s),nil)
    s.hearthPoint=nil;assert(S.AutomaticBinding(p,s))
    s.bags={};eq(S.AutomaticBinding(p,s),nil);s.bags={[6948]=1}
    p.fallback=p.taskOrder[1].stages[2];eq(S.AutomaticBinding(p,s),nil);p.fallback=p.taskOrder[1].stages[1]
    for _,field in ipairs({"locked","itinerary","gearTarget","taskBatch","serviceStop","dead","onTaxi","inInstance"}) do
        s[field]=true;eq(S.AutomaticBinding(p,s),nil);s[field]=nil
    end
    for _,field in ipairs({"best","sessionActive","maintenance"}) do
        p[field]=true;eq(S.AutomaticBinding(p,s),nil);p[field]=nil
    end
    finish()
end)
test("过期自动绑定建议和错误NPC不确认，取消或另选服务使待确认失效",function()
    local B,s,inns,finish,e,rebuild=automaticFixture();local S=B.Services
    s.position={map=1,x=0.8,y=0};rebuild();e.npc=2
    B.jobs.plan={};S:Event("CONFIRM_BINDER","新旅店");eq(S.binding,nil);B.jobs.plan=nil
    B.refreshAt=1;S:Event("CONFIRM_BINDER","新旅店");eq(S.binding,nil);B.refreshAt=nil
    B.plan.revision=s.revision-1;S:Event("CONFIRM_BINDER","新旅店");eq(S.binding,nil);rebuild()
    e.npc=3;S:Event("CONFIRM_BINDER","新旅店");eq(S.binding,nil);e.npc=2
    S:Event("CONFIRM_BINDER","新旅店");assert(S.binding);S:Cancel()
    e.binding="新旅店";S:Event("HEARTHSTONE_BOUND");eq(B.Hearth.landing,nil)
    B.char.declinedBinding=nil;rebuild();S:Event("CONFIRM_BINDER","新旅店");assert(S.binding)
    local rows=S:Choices("bind");assert(S:Pick(rows[1],s.revision));eq(S.binding,nil)
    S:Event("HEARTHSTONE_BOUND");assert(B.char.serviceStop);eq(B.Hearth.landing,nil)
    finish()
end)
test("自动旅店建议提供服务页取消入口且维修优先保留原任务",function()
    local B,s,inns,finish,e,rebuild=automaticFixture();rebuild()
    B.UI={};assert(loadfile("UI/Services.lua"))("AiLeveling",B);local ui=B.UI.Services
    local function widget() return {SetText=function() end,SetEnabled=function(self,v) self.enabled=v end} end
    ui.mode={text=widget()};ui.label=widget();ui.previous=widget();ui.next=widget();ui.choose=widget();ui.choose.text=widget();ui.cancel=widget()
    ui:Refresh();eq(ui.cancel.enabled,true)
    assert(table.concat(ui:Lines(),"\n"):find("当前建议：交付地旅店",1,true))
    B.Services:Cancel();rebuild();ui:Refresh();eq(ui.cancel.enabled,false)
    B.char.declinedBinding=nil;s.durability=0.1;s.merchant={npcId=9,name="铁匠",canRepair=true,items={}}
    local p=rebuild();eq(p.maintenance,true);eq(p.automaticService,nil);eq(p.fallback.serviceKind,"repair")
    finish()
end)
test("手选旅店直接到店不安排延后步骤且不预测新绑定",function()
    local B,s,p,inns,finish=bindingFixture();local S=B.Services
    p.bindingChoices=S.PlanBindings(p,s,B.Data)
    local rows=S:Choices("bind");eq(rows[1].npcId,2);assert(S:Pick(rows[1],s.revision))
    eq(s.serviceStop.afterTask,nil)
    p.taskOrder[1].stages[2].moneyCost=10000
    local result=S.Build(s,p);eq(result.fallback.serviceKind,"bind")
    eq(s.hearthBindingKey,"old");eq(s.hearthPoint.x,0)
    for _,leg in ipairs(result.referenceJourney.legs) do
        if leg.kind=="hearth" then eq(leg.bindingKey,"old") end
    end
    S:Cancel();eq(s.serviceStop,nil);finish()
end)
local function fundedServiceFixture()
    local B,s,p,inns,finish=bindingFixture()
    s.bags={};s.hearthPoint=nil;s.hearthBindingKey=nil;s.hearthReady=nil
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001;s.transportKnown=true;s.faction="Alliance";s.taxiSpeed=1
    B.FlightData={version="service-test",clientVersion="1.60.1",build=70862,interface=16001,
        nodes={[1]={name="出发",instance=0,world={0,0,0},factionMask=1},[2]={name="服务",instance=0,world={0.4,0,0},factionMask=1}},
        durations={Alliance={["1:2"]=20},Horde={}}}
    s.unlocked={["taxi:1"]=true,["taxi:2"]=true};s.taxiAvailability={["1:2"]=true};s.taxiCosts={["1:2"]=15}
    s.taxiDepartures={[1]={map=1,x=0,y=0}};s.taxiLandings={["1:2"]={map=1,x=0.4,y=0}}
    s.taxiHops={["1:2"]="1:2"};B.Estimates.flightBoardSeconds=3
    s.serviceStop={kind="train",npcId=78,title="训练师",position={map=1,x=0.4,y=0}}
    p.taskOrder[1].stages[2].moneyCost=20
    return B,s,p,finish
end
test("手选服务保留后续任务金币而不采用到店最快的付费飞行",function()
    local B,s,p,finish=fundedServiceFixture();local S=B.Services
    local greedy=S.Build(s);eq(greedy.referenceJourney.firstRoute.flights,1)
    local result=S.Build(s,p);eq(result.referenceJourney.firstRoute.flights,0);eq(result.referenceJourney.money,0)
    eq(s.money,20);eq(s.taxiCosts["1:2"],15);eq(p.taskOrder[1].stages[2].moneyCost,20)
    s.money=35;result=S.Build(s,p);eq(result.referenceJourney.firstRoute.flights,1);eq(result.referenceJourney.money,0)
    finish()
end)
test("服务整程计入当前所选训练报价且不沿用关闭窗口后的报价",function()
    local B,s,p,finish=fundedServiceFixture();local S=B.Services
    s.money=40;s.serviceStop.position={map=1,x=0,y=0};s.serviceStop.learnKey="训练"
    s.trainer={npcId=78,rows={{key="训练",name="训练",status="available",playerTraining=true,cost=20}}}
    local result=S.Build(s,p);eq(result.referenceJourney.flights,0);eq(result.referenceJourney.money,0);eq(s.money,40)
    s.trainer.rows[1].cost=5;result=S.Build(s,p);eq(result.referenceJourney.flights,1);eq(result.referenceJourney.money,0)
    s.trainer=nil;result=S.Build(s,p);eq(result.referenceJourney.flights,1);eq(result.referenceJourney.money,5)
    eq(s.serviceStop.cost,nil);finish()
end)
test("已知服务后段不可行时保持手选意图并拒绝单段贪心回退",function()
    local B,s,p,finish=fundedServiceFixture();local S=B.Services
    local stop=s.serviceStop;p.taskOrder[1].stages[2].moneyCost=21
    assert(S.Build(s).referenceJourney)
    local result=S.Build(s,p);eq(result.fallback.kind,"selectionBlocked");eq(result.travelActions,nil);eq(s.serviceStop,stop)
    s.money=21;result=S.Build(s,p);eq(result.fallback.kind,"service");eq(result.referenceJourney.firstRoute.flights,0)
    -- Incomplete task data cannot establish an unaffordable continuation.
    p.taskOrder[1].stagesComplete=false;s.money=20
    result=S.Build(s,p);eq(result.fallback.kind,"service");eq(result.referenceJourney.firstRoute.flights,1)
    finish()
end)
local function unlockFixture()
    local B,s,p,_,finish=bindingFixture();local oldMap=C_Map
    C_Map={GetMapInfo=function(id) return {mapType=3,name="区域"} end}
    s.bags={};s.hearthPoint=nil;s.hearthBindingKey=nil;s.hearthReady=nil;s.hearthCooldown=nil
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001;s.transportKnown=true;s.faction="Alliance";s.taxiSpeed=1
    s.unlocked={["taxi:1"]=false,["taxi:2"]=true};s.taxiAvailability={};s.taxiCosts={};s.taxiDepartures={};s.taxiLandings={};s.taxiHops={}
    B.FlightData={version="test",clientVersion="1.60.1",build=70862,interface=16001,nodes={
        [1]={name="沿途飞行点",world={0,0.2,0},instance=0,factionMask=1,condition=0,visibility=0},
        [2]={name="交付地",world={0,1,0},instance=0,factionMask=1,condition=0,visibility=0}},
        paths={{1,2,10}},durations={Alliance={["1:2"]=100}}}
    B.Navigation.hbd={GetZoneCoordinatesFromWorldInstance=function(_,x,y,instance,map) if map==1 then return x,y end end}
    B.Estimates.flightBoardSeconds=3
    local stages=p.taskOrder[1].stages
    stages[1].title="沿途目标";stages[1].objectiveIndex=1;stages[1].position.x=0.1
    stages[2].position.x=1
    return B,s,p,function() C_Map=oldMap;finish() end
end
test("开飞行点比较完整后续行程并优先做沿途目标且预览不改原生交通",function()
    local B,s,p,finish=unlockFixture();local S=B.Services
    p.flightUnlockChoices=S.PlanFlightUnlocks(p,s)
    local choice=p.flightUnlockChoices[1];assert(math.abs(choice.saving-697)<0.001);eq(choice.afterStage,1)
    eq(choice.afterTask,p.fallback);eq(s.unlocked["taxi:1"],false);eq(next(s.taxiAvailability),nil);eq(next(s.taxiCosts),nil);eq(s.money,20)
    local rows=S:Choices("unlockFlight");eq(#rows,1);eq(rows[1].taxiId,1);eq(rows[1].unlockSaving,choice.saving)
    B.UI={};assert(loadfile("UI/Services.lua"))("AiLeveling",B)
    B.UI.Services.kind="unlockFlight";B.UI.Services.preview=rows[1]
    local lines=table.concat(B.UI.Services:Lines(),"\n");assert(lines:find("先完成「沿途目标」",1,true));assert(not lines:find("697",1,true))
    assert(S:Pick(rows[1],s.revision));assert(S.ValidStop(B.char.serviceStop));eq(s.serviceStop.afterTask.objectiveIndex,1)
    eq(S.Build(s,p),nil);assert(p.serviceDeferred)
    s.quests[42]={objectives={{finished=true}}}
    local stop=S.Build(s,p);eq(stop.fallback.taxiId,1);eq(stop.referenceJourney.flights,0)
    s.position={map=1,x=0.2,y=0};S:Snapshot(s);assert(s.serviceStop)
    s.unlocked["taxi:2"]=true;S:Snapshot(s);assert(s.serviceStop)
    s.unlocked["taxi:1"]=true;S:Snapshot(s);eq(s.serviceStop,nil);eq(B.char.serviceStop,nil);eq(B.char.locked,42)
    finish()
end)
test("开点预览保留资金炉石与绕路约束且费用未知不补零",function()
    local B,s,p,finish=unlockFixture();local S=B.Services
    s.money=9;assert(S.PlanFlightUnlocks(p,s)[1].saving<=0)
    s.money=20;B.FlightData.paths[1][3]=nil;eq(next(S.PlanFlightUnlocks(p,s)),nil)
    B.FlightData.paths[1][3]=10;B.FlightData.durations.Alliance={};eq(next(S.PlanFlightUnlocks(p,s)),nil)
    B.FlightData.durations.Alliance["1:2"]=100
    s.bags={[6948]=1};s.hearthPoint={map=1,x=1,y=0};s.hearthBindingKey="near";s.hearthCooldown=3600;s.hearthReady=0
    assert(S.PlanFlightUnlocks(p,s)[1].saving<=0);eq(s.hearthReady,0);eq(s.hearthPoint.x,1)
    s.hearthReady=3600;assert(S.PlanFlightUnlocks(p,s)[1].saving>0)
    s.bags={};B.FlightData.nodes[1].world[2]=0.95;p.taskOrder[1].stages[2].position.x=0.4
    assert(S.PlanFlightUnlocks(p,s)[1].saving<0)
    finish()
end)
test("开点候选拒绝未知解锁敌方条件节点旧构建与不完整任务",function()
    local B,s,p,finish=unlockFixture();local S=B.Services;local node=B.FlightData.nodes[1]
    s.unlocked["taxi:1"]=nil;eq(#S:Choices("unlockFlight"),0)
    s.unlocked["taxi:1"]=false;node.factionMask=2;eq(#S:Choices("unlockFlight"),0)
    node.factionMask=1;node.condition=8;eq(#S:Choices("unlockFlight"),0)
    node.condition=0;node.visibility=8;eq(#S:Choices("unlockFlight"),0);node.visibility=0
    s.clientBuild="1";eq(S.PlanFlightUnlocks(p,s),nil);eq(#S:Choices("unlockFlight"),0);s.clientBuild="70862"
    p.taskOrder[1].lowValue={};eq(S.PlanFlightUnlocks(p,s),nil);p.taskOrder[1].lowValue=nil
    p.taskOrder[1].stagesComplete=false;eq(S.PlanFlightUnlocks(p,s),nil);p.taskOrder[1].stagesComplete=true
    p.taskQueue={remaining=1,steps={}};eq(S.PlanFlightUnlocks(p,s),nil);p.taskQueue=nil
    s.inInstance=true;eq(S.PlanFlightUnlocks(p,s),nil);eq(#S:Choices("unlockFlight"),0)
    s.inInstance=false;B.refreshAt=1;p.flightUnlockChoices={[1]={saving=999}}
    eq(S:Choices("unlockFlight")[1].unlockSaving,nil)
    finish()
end)
test("开点只预览有向直连不会臆造反向航线或解锁其他点",function()
    local B,s,p,finish=unlockFixture();local rows=B.Services:Choices("unlockFlight")
    local preview=B.Flights.PreviewUnlock(s,rows[1],B.Navigation)
    eq(preview.taxiAvailability["1:2"],true);eq(preview.taxiAvailability["2:1"],nil)
    eq(preview.taxiCosts["1:2"],10);eq(preview.taxiHops["1:2"],"1:2")
    B.FlightData.nodes[2].condition=1;eq(B.Flights.PreviewUnlock(s,rows[1],B.Navigation),nil)
    B.FlightData.nodes[2].condition=0;s.unlocked["taxi:2"]=false;eq(B.Flights.PreviewUnlock(s,rows[1],B.Navigation),nil)
    s.unlocked["taxi:2"]=true;assert(B.Services:Pick(rows[1],s.revision))
    B.char.serviceStop.taxiId=0;eq(B.Services.ValidStop(B.char.serviceStop),false);B.char.serviceStop.taxiId=1
    s.clientBuild="1";eq(B.Services.Build(s).fallback.kind,"selectionBlocked")
    B.Services:Cancel();eq(s.serviceStop,nil)
    finish()
end)
test("开点比较跨帧执行且原任务顺序不变",function()
    local B,s,p,finish=unlockFixture();local result
    local co=coroutine.create(function() result=B.Services.PlanFlightUnlocks(p,s) end)
    local frames=0
    while coroutine.status(co)~="dead" do frames=frames+1;local ok,err=coroutine.resume(co);assert(ok,err);assert(frames<1000) end
    assert(frames>1);assert(result[1].saving>0);eq(p.taskOrder[1].stages[1].kind,"objective");eq(p.taskOrder[1].stages[2].kind,"turnin")
    finish()
end)
test("原生明确未发现的飞行点进入状态指纹，未知标记不推定未开通",function()
    local oldTaxi,oldMap=C_TaxiMap,C_Map
    C_Map={GetMapInfo=function() return {mapType=3} end}
    C_TaxiMap={GetTaxiNodesForMap=function() return {
        {nodeID=1,faction=2,isUndiscovered=true},{nodeID=2,faction=2,isUndiscovered=false},
        {nodeID=3,faction=2,isUndiscovered=0},{nodeID=4,faction=1,isUndiscovered=true}} end}
    local B={Content={transit={}}};assert(loadfile("Transport.lua"))("AiLeveling",B)
    local s={unlocked={},taxiCosts={},now=0};local key=B.Transport.Key(s)
    B.Transport:RefreshKnown(1,"Alliance");s.unlocked=B.Transport.known
    eq(s.unlocked["taxi:1"],false);eq(s.unlocked["taxi:2"],true);eq(s.unlocked["taxi:3"],nil);eq(s.unlocked["taxi:4"],nil)
    assert(B.Transport.Key(s)~=key);s.unlocked["taxi:2"]=nil
    assert(B.Transport.Key(s)~=key);s.unlocked["taxi:1"]=true
    B.Transport:RefreshKnown(1,"Alliance");eq(s.unlocked["taxi:1"],true)
    C_TaxiMap,C_Map=oldTaxi,oldMap
end)
test("炉石旅店按集中交付与可接任务排序且不推演换绑行程",function()
    local B,s,p,inns,finish=bindingFixture();local S=B.Services
    B.Flights.Itinerary=function() error("绑定建议不做整程搜索") end
    p.taskOrder[2]={questId=43,stages={{kind="turnin",position={map=1,x=0.81,y=0}}}};s.quests[43]={}
    p.taskOrder[3]=p.taskOrder[2]
    p.taskOrder[4]={questId=44,actions={{kind="accept",position={map=1,x=0.8,y=0}}}}
    p.bindingChoices=S.PlanBindings(p,s,B.Data)
    local hub=p.bindingChoices[S.BindingKey(inns[2])];eq(hub.deliveryCount,2);eq(hub.acceptCount,1)
    eq(p.bindingChoices[S.BindingKey(inns[1])].deliveryCount,0)
    local rows=S:Choices("bind");eq(rows[1].npcId,2)
    eq(s.hearthBindingKey,"old");eq(s.hearthPoint.x,0);eq(s.money,20);eq(s.hearthReady,0)
    B.UI={};assert(loadfile("UI/Services.lua"))("AiLeveling",B);B.UI.Services.preview=rows[1]
    local lines=table.concat(B.UI.Services:Lines(),"\n")
    assert(lines:find("2 个已接任务",1,true));assert(lines:find("1 个可接任务",1,true))
    assert(not lines:find("预计",1,true));finish()
end)
test("炉石交接点保留已知收件人并排除低价值受限及缺位置任务",function()
    local B,s,p,inns,finish=bindingFixture();local S=B.Services
    p.taskQueue={remaining=1,steps={}};p.taskOrder[1].stagesComplete=false
    s.hearthPoint=nil;s.hearthReady=nil
    local function count() return S.PlanBindings(p,s,B.Data)[S.BindingKey(inns[2])].deliveryCount end
    eq(count(),1)
    for _,field in ipairs({"lowValue","entryBlocked","requireCheck","acceptBlocked"}) do
        p.taskOrder[1][field]=true;eq(count(),0);p.taskOrder[1][field]=nil
    end
    p.taskOrder[1].stages[2].position=nil;eq(count(),0)
    eq(s.hearthPoint,nil);eq(s.hearthReady,nil);finish()
end)
test("已确认所选旅店建立炉石参考点且再次绑定清除旧点",function()
    local B,e,finish=setup();assert(loadfile("Hearth.lua"))("AiLeveling",B)
    local s=B.state;s.hearthReady=1;s.bags={[6948]=1}
    B.char.serviceStop={kind="bind",npcId=78,title="旅店",position={map=1,x=0.5,y=0.5}}
    B.Services:Event("CONFIRM_BINDER","新旅店")
    e.binding="新旅店";s.bindName=e.binding
    B.Hearth:Event("HEARTHSTONE_BOUND");B.Services:Event("HEARTHSTONE_BOUND")
    eq(B.char.serviceStop,nil);assert(B.Hearth.landing.reference)
    B.Hearth:Snapshot(s);eq(s.hearthPoint.x,0.5);eq(s.hearthBindingKey,"1:新旅店")
    s.hearthPoint.x=0;eq(B.Hearth.landing.position.x,0.5);eq(next(B.char.samples),nil)
    B.Hearth:Event("HEARTHSTONE_BOUND");B.Services:Event("HEARTHSTONE_BOUND")
    B.Hearth:Snapshot(s);eq(s.hearthPoint,nil)
    finish()
end)
test("跨区旅店进入当前行程换绑比较且过期规划撤回扩展目录",function()
    local B,s,p,inns,finish=bindingFixture();local S=B.Services
    local stages=p.taskOrder[1].stages
    stages[1].position={map=2,x=0.2,y=0};stages[2].position={map=2,x=0,y=0}
    inns[2].position={map=2,x=0,y=0}
    B.Navigation.Distance=function(_,a,b) return math.abs((a.map-1+a.x)-(b.map-1+b.x))*7000 end
    B.Data.AmenityPoints=function(_,state,kind,maps)
        if maps and maps[2] then return inns end
        return {inns[1]}
    end
    p.bindingChoices=S.PlanBindings(p,s,B.Data)
    eq(p.bindingChoices[S.BindingKey(inns[2])].deliveryCount,1)
    local choices=S:Choices("bind");eq(#choices,2);eq(choices[1].npcId,2);eq(choices[1].position.map,2)
    assert(S:Pick(choices[1],s.revision));eq(B.char.serviceStop.position.map,2)
    S:Cancel();p.revision=s.revision
    eq(#S:Choices("train"),2)
    p.revision=s.revision-1;eq(#S:Choices("bind"),1);p.revision=s.revision
    B.jobs.plan={};eq(#S:Choices("bind"),1);B.jobs.plan=nil
    p.taskOrder[2]={questId=43,stages={{position={map=3,x=0.5,y=0.5}}},lowValue={}}
    s.quests[43]={};eq(S.ServiceMaps(p,s)[3],nil)
    p.taskOrder[2].lowValue=nil;p.taskOrder[2].entryBlocked="受限";eq(S.ServiceMaps(p,s)[3],nil)
    B.Navigation.Distance=function(_,a,b) if a.map==b.map then return math.abs(a.x-b.x)*7000 end end
    eq(S.PlanBindings(p,s,B.Data)[S.BindingKey(inns[2])].deliveryCount,1)
    finish()
end)
test("训练师按本职业和已学专业优先，未知与未学专业保留手选",function()
    local B,e,finish=setup();local s=B.state
    assert(loadfile("Data/Trainers.lua"))("AiLeveling",B)
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001;s.classMask=16;s.skills={[165]=50,[202]=0}
    local ids={3047,3412,999999,3365,2123,2704}
    B.Data={AmenityPoints=function(_,state,kind)
        local rows={};for i,id in ipairs(ids) do rows[i]={kind=kind,npcId=id,title="训练师"..id,position={map=1,x=0.5+i/100,y=0.5}} end
        return rows
    end}
    local rows=B.Services:Choices("train")
    eq(rows[1].npcId,3365);eq(rows[2].npcId,2123);eq(rows[3].npcId,999999);eq(rows[4].npcId,2704)
    eq(rows[5].npcId,3412);eq(rows[6].npcId,3047);eq(#rows,6)
    B.UI={};assert(loadfile("UI/Services.lua"))("AiLeveling",B);B.UI.Services.kind="train";B.UI.Services.preview=rows[1]
    assert(table.concat(B.UI.Services:Lines(),"\n"):find("已学习制皮",1,true))
    assert(B.Services:Pick(rows[5],s.revision));eq(B.char.serviceStop.npcId,3412)
    s.classMask=128;s.skills[165]=0;s.skills[202]=25
    rows=B.Services:Choices("train");eq(rows[1].npcId,3047);eq(rows[2].npcId,3412)
    s.classMask=nil;s.skills={};eq(B.Services.TrainerFit(s,3047),1);eq(B.Services.TrainerFit(s,3365),1)
    s.clientBuild="other";rows=B.Services:Choices("train");eq(rows[1].npcId,3047)
    for _,row in ipairs(rows) do eq(row.trainingRank,1);eq(row.trainingText,nil) end
    s.clientBuild="70862";rows=B.Services:Choices("bind");eq(rows[1].npcId,3047);eq(rows[1].trainingRank,nil)
    finish()
end)
test("训练专业按当前构建读取原生技能且缺接口保持未知",function()
    local B,e,finish=setup();local s=B.state
    assert(loadfile("Data/Trainers.lua"))("AiLeveling",B);assert(loadfile("State.lua"))("AiLeveling",B)
    B.ItemSets=nil;B.WeaponSkills=nil
    local old=C_SkillInfo;local calls={}
    C_SkillInfo={GetSkillLineInfoByID=function(id) calls[id]=true;if id==165 then return {rank=75} end end}
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    B.State:Qualifications(s,{skills={[999]=true}});eq(s.skills[165],75);eq(s.skills[202],0);assert(calls[999])
    local count=0;for id in pairs(B.Trainers.skills) do assert(calls[id]);count=count+1 end;eq(count,7)
    C_SkillInfo=nil;B.State:Qualifications(s,{});eq(s.skills[165],nil);eq(B.Services.TrainerFit(s,3365),1)
    calls={};C_SkillInfo={GetSkillLineInfoByID=function(id) calls[id]=true end};s.clientBuild="other"
    B.State:Qualifications(s,{});eq(next(calls),nil)
    C_SkillInfo=old;finish()
end)

end
