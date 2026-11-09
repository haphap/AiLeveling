io.stdout:setvbuf("line")
local A, passed = {}, 0
local function load(path) assert(loadfile(path))("AiLeveling", A) end
for _, path in ipairs({"State.lua","Items.lua","Merchant.lua","Services.lua","Transport.lua","Instances.lua","Observations.lua","Data/Content.lua","Data/Questie.lua","Planner/Eligibility.lua",
    "Planner/Chains.lua","Planner/Travel.lua","Planner/Gear.lua","Planner/Progression.lua","Planner/Supplies.lua","Planner/Dungeon.lua","Planner/Planner.lua",
    "Planner/Selection.lua","QuestAssist.lua", "Data/Audit.lua","Data/Experience.lua","Planner/Estimates.lua"}) do load(path) end
local F = dofile("tests/fixtures.lua")
A.Navigation=F.Navigation
local function test(name, run)
    local ok, err = pcall(run)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("PASS " .. name)
end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function plan(state,data,options,engine)
    local co = coroutine.create(function() return (engine or A).Planner.Build(state,data,options or {minutes=60,mode="fast",dungeons=true,role="DAMAGER"}) end)
    while true do
        local ok, result = coroutine.resume(co)
        assert(ok,result)
        if coroutine.status(co)=="dead" then return result end
    end
end

test("Forever 高位种族掩码不截断",function()
    eq(A.Eligibility.InMask(8589934593,8589934592),true)
    eq(A.Eligibility.InMask(8589934593,4294967296),false)
    eq(A.Eligibility.InMask(1,nil),nil)
end)
test("可交付尚未解除交付前置",function()
    local s,q=F.State(),F.Quest(2)
    s.quests[1]={ready=true};q.preQuestGroup={1}
    eq(A.State.Status(s,1),"ready");eq(A.Eligibility.Check(q,s),false)
    s.quests[1]=nil;s.completed[1]=true
    eq(A.Eligibility.Check(q,s),true)
end)
test("全部与任一前置分别检查",function()
    local s,q=F.State(),F.Quest(3)
    q.preQuestGroup={1,2};q.preQuestSingle={4,5};s.completed[1]=true;s.completed[4]=true
    eq(A.Eligibility.Check(q,s),false)
    s.completed[2]=true;eq(A.Eligibility.Check(q,s),true)
end)
test("互斥与专业未知不放行",function()
    local s,q=F.State(),F.Quest(3)
    q.exclusiveTo={2};s.quests[2]={};eq(A.Eligibility.Check(q,s),false)
    s.quests={};q.requiredSkill={164,75};eq(A.Eligibility.Check(q,s),false)
    s.skills[164]=75;eq(A.Eligibility.Check(q,s),true)
end)
test("放弃任务与用户暂缓都不写成完成",function()
    local s=F.State();s.skipped[1]=true
    eq(A.State.Status(s,1),"notStarted");eq(A.Eligibility.Check(F.Quest(1),s),false)
end)
test("重复交付事件只结算一次",function()
    A.state=F.State();A.char={turnIns={}};A.State.confirmed={}
    A.State:TurnedIn(1);A.State:TurnedIn(1)
    eq(A.char.turnIns[1],1);eq(A.state.completed[1],true)
end)
test("地面移动只按直线距离除以速度且不读取道路图",function()
    local d,s=F.Data({}),F.State()
    eq(A.Travel.Route(d.content,"start","goal",s).seconds,20)
    d.content.edges={};eq(A.Travel.Route(d.content,"start","goal",s).seconds,20)
end)
test("跨世界没有地面直线距离时保留未知交通连接",function()
    local d,s=F.Data({}),F.State();d.content.nodes.goal.position.map=2
    eq(A.Travel.Route(d.content,"start","goal",s),nil)
end)
test("炉石冷却与船只时刻纳入未来出发时间",function()
    eq(A.Travel.Transit({kind="hearth",verified=true,seconds=10,cooldown=3600},100,{hearthReady=160}),70)
    eq(A.Travel.Transit({kind="boat",verified=true,seconds=30,period=60},70,{}),80)
end)
test("路线须含往返与交付才记奖励",function()
    local q,s=F.Quest(1),F.State();local d=F.Data({[1]=q})
    local r=A.Planner.Evaluate(q,s,d,{minutes=60},"start")
    eq(r.seconds,40);eq(r.xp,1000)
    q.actions[3]=nil
    eq(A.Planner.Evaluate(q,s,d,{minutes=60},"start"),nil)
end)
test("已完成目标只规划交付余程",function()
    local q,s=F.Quest(1),F.State();local d=F.Data({[1]=q})
    s.quests[1]={ready=true,objectives={}};s.position.node="goal"
    local r=A.Planner.Evaluate(q,s,d,{minutes=60},"goal")
    eq(r.seconds,20);eq(r.actions[#r.actions].kind,"turnin")
end)
test("任务排序忽略旧耗时、武器计时模型与执行样本",function()
    local q,s=F.Quest(1),F.State();local data=F.Data({[1]=q})
    local baseline=A.Planner.Evaluate(q,s,data,{minutes=60},"start")
    q.seconds=100000;q.failureProbability=1;q.recoverySeconds=100000;q.gearTimeModel={class="WARRIOR",byWeapon={[999]=1}}
    q.actions[2].seconds=100000
    s.equipment[16]={id=999};s.samples.quest={n=100,mean=4,m2=0,unit="ratio"}
    local result=A.Planner.Evaluate(q,s,data,{minutes=60},"start")
    assert(result);eq(result.seconds,baseline.seconds);eq(result.xp,baseline.xp)
    q.seconds=nil;q.actions[2].seconds=nil
    result=A.Planner.Evaluate(q,s,data,{minutes=60},"start")
    assert(result);eq(result.seconds,baseline.seconds)
end)
test("短程搜索保留高价值后续的必要前置",function()
    local s,q1,q2,q3=F.State(),F.Quest(1),F.Quest(2),F.Quest(3)
    q1.xp=1;q1.setup=true;q2.preQuestGroup={1};q2.xp=20000;q3.xp=1000
    local p=plan(s,F.Data({[1]=q1,[2]=q2,[3]=q3}))
    eq(p.best.questId,1);assert(p.best.xp>=20001)
end)
test("比较使用重新计算的候选与新状态",function()
    local old={revision=1,best={id=1,rate=999999}}
    local fresh={revision=2,best={id=2,rate=1},alternatives={{id=1,rate=0.1},{id=2,rate=1}}}
    eq(A.Planner.Choose(old,fresh).best.id,2)
end)
test("副本等待与可中断任务的重叠时间只计一次",function()
    local d={id=1,title="测试副本",verified=true,minLevel=10,maxLevel=30,
        travelSeconds=100,runSeconds=600,waitSeconds=300,interruptibleSeconds=200,xp=1000}
    local c=A.Dungeon.Evaluate(d,F.State(),{dungeons=true,minutes=60,role="DAMAGER"})
    eq(c.seconds,1000)
end)
test("离开副本不等于本轮完成且只结算一次",function()
    local session={phase="inside",entered=true}
    eq(A.Dungeon.Transition(session,"leave"),false);eq(session.phase,"outside")
    eq(A.Dungeon.Transition(session,"finish"),true);eq(A.Dungeon.Transition(session,"finish"),false)
end)
test("任务物品移格后身份不变且去重",function()
    local s=F.State();s.quests[1]={itemId=123}
    local r=A.QuestAssist.Desired({questId=1,items={[123]=1,[456]=2}},s,true)
    eq(#r,2);eq(r[1],123);eq(r[2],456)
end)
test("战斗中合并待更新物品且不触碰安全属性",function()
    local calls,combat=0,true
    InCombatLockdown=function() return combat end
    A.QuestAssist.pending={123};A.QuestAssist.buttons={{SetAttribute=function() calls=calls+1 end}}
    A.QuestAssist:ApplyPending();eq(calls,0)
    A.QuestAssist.pending={456};A.QuestAssist:ApplyPending();eq(A.QuestAssist.pending[1],456);eq(calls,0)
end)
test("任务链解释能检测循环并保留 AND/OR 关系",function()
    local q1,q2=F.Quest(1),F.Quest(2);q1.preQuestGroup={2};q2.preQuestSingle={1}
    local nodes,cycles=A.Chains.Explain(1,F.Data({[1]=q1,[2]=q2}),F.State())
    eq(#nodes,2);eq(#cycles,1)
end)
test("本地样本排除明显挂机区间",function()
    local samples={}
    for _=1,6 do A.State.Observe(samples,"quest",60) end
    A.State.Observe(samples,"quest",3600);eq(samples.quest.n,6);eq(samples.quest.mean,60)
end)
test("地图支持表只解析数值不执行源码",function()
    local maps=A.Data.ParseMap("return {[1]=2, -- [3]=4\n [9]=0}; error('never execute')")
    eq(maps[1],2);eq(maps[3],nil);eq(maps[9],0)
end)
test("未知真实内容不产生模拟最优行程",function()
    local q=F.Quest(1);q.verified=false
    local p=plan(F.State(),F.Data({[1]=q}))
    eq(p.best,nil);eq(p.unverified,true)
end)
test("状态重建不修改正在计算的旧快照且走动不递增版本",function()
    local provider,oldNavigation=A.Data,A.Navigation
    A.Data={GetQuest=function(_,id) return F.Quest(id) end,Candidates=function() return {} end}
    A.state=F.State();local captured=A.state
    A.char={skipped={},samples={},turnIns={}}
    A.settings={role="DAMAGER",mode="fast",minutes=60,dungeons=true}
    A.indexReady=true;A.requestedItems={};A.State.confirmed={}
    A.Navigation={AttachNode=function() end}
    A.QuestAssist.Update=function() end
    A.Replan=function() end
    local x=0.1
    local objectiveText,objectiveType="目标待加载","item"
    GetTime=function() return 100 end
    UnitLevel=function() return 20 end;UnitXP=function() return 100 end;UnitXPMax=function() return 1000 end
    UnitClass=function() return "战士","WARRIOR",1 end;UnitRace=function() return "人类","Human",1 end
    UnitFactionGroup=function() return "Alliance" end;GetNumGroupMembers=function() return 0 end
    IsInInstance=function() return false end
    LibQuestieDB={Enum={classKeys={WARRIOR=1},raceMaskById={[1]=1}}}
    C_QuestLog={GetMaxNumQuestsCanAccept=function() return 20 end,GetAllCompletedQuestIDs=function() return {} end,GetNumQuestLogEntries=function() return 1,1 end,
        GetInfo=function() return {questID=42,title="测试"} end,
        GetQuestObjectives=function() return {{text=objectiveText,type=objectiveType,numFulfilled=0,numRequired=3,finished=false}} end,
        ReadyForTurnIn=function() return false end}
    C_Map={GetBestMapForUnit=function() return 1 end,GetPlayerMapPosition=function() return {x=x,y=0.5} end}
    NUM_BAG_SLOTS=4
    C_Container={GetContainerNumFreeSlots=function() return 16 end,GetContainerNumSlots=function() return 0 end}
    GetInventoryItemID=function() return nil end
    local dual=false
    C_SpellBook={IsSpellKnown=function(id) return id==674 and dual end}
    A.State:Refresh(true)
    eq(captured.quests[42],nil);eq(captured.revision,1);eq(A.state.quests[42].ready,false);eq(A.state.questCount,1);eq(A.state.questLimit,20)
    local revision=A.state.revision
    x=0.2;A.State:Position();eq(A.state.revision,revision);eq(A.state.position.x,0.2)
    dual=true;A.State:Refresh();eq(A.state.revision,revision+1);eq(A.state.capabilities.dualWield,true)
    local before=A.state
    objectiveText="任务物品：0/3";A.State:Refresh()
    eq(A.state.revision,before.revision+1);eq(before.quests[42].objectives[1].text,"目标待加载")
    before=A.state;objectiveType="event";A.State:Refresh();eq(A.state.revision,before.revision+1)
    before=A.state;A.State:Refresh();eq(A.state.revision,before.revision)
    local oldInfo,oldInside=GetInstanceInfo,IsInInstance
    local difficulty,calls=1,0
    IsInInstance=function() return true end
    GetInstanceInfo=function()
        calls=calls+1;return "测试副本","party",difficulty,"普通",5,0,false,36
    end
    A.State:Refresh();eq(calls,1);eq(A.state.instanceId,36);eq(A.state.instanceDifficultyId,1)
    local first=A.state;difficulty=201;A.State:Refresh()
    eq(A.state.revision,first.revision+1);eq(first.instanceDifficultyId,1);eq(A.state.instanceDifficultyId,201)
    first=A.state;A.State:Refresh();eq(A.state.revision,first.revision)
    IsInInstance=function() return false end;A.State:Refresh();eq(A.state.instanceDifficultyId,nil)
    GetInstanceInfo=nil;A.State:Refresh();eq(A.state.instanceId,nil);eq(A.state.instanceDifficultyId,nil)
    GetInstanceInfo,IsInInstance=oldInfo,oldInside
    local oldReward,oldAccess=GetQuestLogRewardXP,canaccessvalue
    local reward,accessible=450,true
    GetQuestLogRewardXP=function(id) eq(id,42);return reward,300 end
    canaccessvalue=function() return accessible end
    local previous=A.state
    A.State:Refresh();eq(A.state.quests[42].rewardXP,450);eq(A.state.quests[42].rewardXPLevel,20)
    eq(A.state.revision,previous.revision+1);eq(previous.quests[42].rewardXP,nil)
    previous=A.state;A.State:Refresh();eq(A.state.revision,previous.revision)
    reward=600;A.State:Refresh();eq(A.state.revision,previous.revision+1);eq(previous.quests[42].rewardXP,450)
    for _,invalid in ipairs({0,-1,math.huge,0/0,"450",false}) do
        reward=invalid;A.State:Refresh();eq(A.state.quests[42].rewardXP,nil)
    end
    reward=450;accessible=false;A.State:Refresh();eq(A.state.quests[42].rewardXP,nil)
    accessible=true;GetQuestLogRewardXP=function() error("unavailable") end
    A.State:Refresh();eq(A.state.quests[42].rewardXP,nil)
    GetQuestLogRewardXP=nil;A.State:Refresh();eq(A.state.quests[42].rewardXP,nil)
    GetQuestLogRewardXP,canaccessvalue=oldReward,oldAccess
    local oldSkills,oldWeaponSkills=C_SkillInfo,A.WeaponSkills
    local oldVersion,oldBuild,oldInterface=A.clientVersion,A.build,A.interface
    assert(loadfile("Data/WeaponSkills.lua"))("AiLeveling",A)
    A.clientVersion,A.build,A.interface="1.60.1","70862",16001
    local weapon={rank=80,maxRank=100,modifier=5,tempPoints=0}
    C_SkillInfo={GetSkillLineInfoByID=function(id) if id==43 then return weapon end end}
    A.State:Refresh();local prior=A.state
    A.State:Refresh();eq(A.state.revision,prior.revision)
    weapon.modifier=10;A.State:Refresh();eq(A.state.revision,prior.revision+1);eq(prior.weaponSkills[43].modifier,5)
    prior=A.state;weapon.tempPoints=5;A.State:Refresh();eq(A.state.revision,prior.revision+1)
    prior=A.state;weapon.rank=81;A.State:Refresh();eq(A.state.revision,prior.revision+1)
    prior=A.state
    A.State.questOffers={[11]={}}
    A.State.questOffersRevision=1
    A.State:Refresh();eq(A.state.questOffers[11][1],nil);eq(A.state.revision,prior.revision+1)
    local offers=A.state
    A.State:QuestOffersEvent("QUEST_TURNED_IN");A.State:Refresh()
    eq(A.state.questOffers[11],nil);assert(offers.questOffers[11]);eq(A.state.revision,offers.revision+1)
    A.State.questOffers,A.State.questOffersRevision=nil,nil
    C_SkillInfo,A.WeaponSkills=oldSkills,oldWeaponSkills
    A.clientVersion,A.build,A.interface=oldVersion,oldBuild,oldInterface
    A.Data=provider;A.Navigation=oldNavigation
end)
test("专业与声望资格直接按 ID 读取且支持多个已学专精",function()
    C_SkillInfo={GetSkillLineInfoByID=function(id) if id==164 then return {rank=150} end end}
    C_Reputation={GetFactionDataByID=function() return {currentStanding=3000} end}
    C_SpellBook={IsSpellKnown=function(id) return id==9787 or id==17040 end}
    local s=F.State()
    A.State:Qualifications(s,{skills={[164]=true,[165]=true},reputations={[72]=true},
        spells={[999]=true},specializations={[164]=true,[9787]=true,[17040]=true}})
    eq(s.skills[164],150);eq(s.skills[165],0);eq(s.reputations[72],3000)
    local q=F.Quest(1);q.requiredSpecialization=17040
    eq(A.Eligibility.Check(q,s),true)
    q.requiredSpell=999;eq(A.Eligibility.Check(q,s),false)
end)
test("任务完成历史未就绪时不放行新前置",function()
    local s,q=F.State(),F.Quest(1);s.completionKnown=false
    eq(A.State.Status(s,1),"unknown");eq(A.Eligibility.Check(q,s),false)
    s.quests[1]={};eq(A.Eligibility.Check(q,s),true)
end)
test("同路任务簇合并接取与交付移动且逐任务保留收益",function()
    local s,q1,q2=F.State(),F.Quest(1),F.Quest(2)
    local data=F.Data({[1]=q1,[2]=q2})
    local r=A.Planner.EvaluateMany({q1,q2},s,data,{minutes=60},"start")
    eq(r.kind,"cluster");eq(r.seconds,40);eq(r.xp,2000)
    eq(r.actions[1].kind,"accept");eq(r.actions[2].kind,"accept")
    local p=plan(s,data);eq(p.best.kind,"cluster");eq(p.best.xp,2000)
end)
test("交通可连续衔接且记录金币与炉石资源",function()
    local content={nodes={a=F.Node(0,1),b=F.Node(0,2),c=F.Node(0,3),d=F.Node(0,4)},edges={},transit={
        ship={from="a",to="b",kind="boat",seconds=20,verified=true},
        flight={from="b",to="c",kind="flight",seconds=30,cost=40,verified=true},
        hearth={from="c",to="d",kind="hearth",seconds=10,cooldown=3600,verified=true}}}
    local r=A.Travel.Route(content,"a","d",{now=100,money=100,hearthReady=200})
    eq(r.seconds,110);eq(r.money,60);eq(r.hearthReady,3810);eq(#r.actions,3)
    eq(A.Travel.Route(content,"a","d",{now=100,money=20,hearthReady=200}),nil)
end)
test("束搜索的后续步骤继承已消耗的交通金币",function()
    local q1,q2,s=F.Quest(1),F.Quest(2),F.State()
    q2.preQuestGroup={1};s.money=50;s.now=100
    local data=F.Data({[1]=q1,[2]=q2})
    data.content.edges.start={{to="goal",seconds=100,verified=true}}
    data.content.transit={one={from="start",to="goal",seconds=5,cost=40,verified=true,kind="flight"}}
    local p=plan(s,data)
    local count=0;for _,a in ipairs(p.best.actions) do if a.kind=="transit" then count=count+1 end end
    eq(count,1);eq(p.best.resources.money,10)
end)
test("带符号组前置区分指定交付与互斥分支替代",function()
    local q,pre,alt,s=F.Quest(3),F.Quest(1),F.Quest(2),F.State()
    pre.exclusiveTo={2};q.preQuestGroup={1};s.completed[2]=true
    local data=F.Data({[1]=pre,[2]=alt,[3]=q})
    eq(A.Eligibility.Check(q,s,data),true)
    q.preQuestGroup={-1};eq(A.Eligibility.Check(q,s,data),false)
    s.completed[1]=true;eq(A.Eligibility.Check(q,s,data),true)
end)
test("明确锁定优先于切换稳定阈值",function()
    local old={best={id=1,questId=1,rate=100}}
    local fresh={best={id=2,questId=2,rate=100},alternatives={{id=1,questId=1,rate=99}}}
    eq(A.Planner.Choose(old,fresh,2).best.id,2)
end)
test("恢复采样仅在确认后结算且排除挂机与中断",function()
    local o=A.Observations
    A.char={samples={}};A.RequestRefresh=function() end
    local action={kind="service",serviceId="recovery",referenceSeconds=10}
    o:Reset();o:Tick(0,action,true,true)
    for i=1,10 do o:Tick(i,action,true,true) end
    o:Finish(false);eq(A.char.samples.recovery,nil)
    o:Tick(20,action,true,true)
    for i=21,30 do o:Tick(i,action,true,true) end
    o:Finish(true);eq(A.char.samples.recovery.n,1);eq(A.char.samples.recovery.mean,1)
    o:Finish(true);eq(A.char.samples.recovery.n,1)
    o:Tick(100,action,true,true)
    for i=101,140 do o:Tick(i,action,false,true) end
    o:Finish(true);eq(A.char.samples.recovery.n,1)
    o:Tick(200,action,true,true);o:Tick(210,action,true,true)
    o:Finish(true);eq(A.char.samples.recovery.n,1)
end)
test("任务与步行不采样且清理旧执行样本",function()
    A.char={samples={quest={n=10},move={n=10},["taskwork:1"]={n=10}}}
    local o=A.Observations
    for _,kind in ipairs({"objective","move"}) do
        o:Tick(0,{kind=kind,questId=1,referenceSeconds=10},true,true)
        eq(o.current,nil)
    end
    o:Context(F.State());eq(next(A.char.samples),nil)
end)
test("有效审计将空接取集合记为缺口并保留任务 ID",function()
    local q=F.Quest(1);q.startedBy={};q.finishedBy={};q.actions=nil;q.preQuestGroup={-2}
    local none={GetAllIds=function() return {} end,Exists=function() return false end}
    local db={contractVersion=4,Npc=none,Object=none,Item=none,
        Quest={GetAllIds=function() return {1} end,Exists=function(id) return id==1 end,
            Get=function(_,key) return q[key] end},Support={Get=function() return {private={}} end}}
    local report=A.Audit.Build({db=db,ids={1},maps={},xp={},content={quests={},nodes={},dungeons={}}},true)
    eq(report.total,1);eq(report.gaps["starter-location"],1)
    eq(report.gaps["missing-prerequisite"],1);eq(report.signedPrerequisiteEntries,1)
    eq(report.gaps["signed-prerequisite-rule"],nil);eq(report.quests["1"].id,1)
end)
test("导航重接沿途节点且隐藏标记仍推进到达",function()
    local B={Content={nodes={}},state={position={map=1,x=0,y=0,node="near"}},
        settings={pins=false,arrow=true},char={},QuestAssist={Update=function() end},
        UI={SetNavigation=function() end},Replan=function() error("不应沿路重算") end}
    assert(loadfile("Navigation.lua"))("AiLeveling",B)
    B.plan={best={actions={{kind="move",node="near",position={map=1,x=0,y=0}},
        {kind="move",node="goal",position={map=1,x=1,y=0}},
        {kind="objective",node="goal",position={map=1,x=1,y=0}}}}}
    B.Navigation:SetPlan(B.plan);eq(B.Navigation.index,2)
    B.Navigation.hbd={GetZoneDistance=function() return 0 end,
        GetWorldCoordinatesFromZone=function() return 0,0,1 end,GetWorldVector=function() return 0 end}
    B.state.position.node="goal";B.Navigation:Update();eq(B.Navigation.index,3)
    GetPlayerFacing=function() return 0 end
    B.Navigation:Update();eq(B.Navigation.index,3)
end)
test("原生难度变化事件已注册并触发状态重建",function()
    local create,slash,addons=CreateFrame,SlashCmdList,C_AddOns
    C_AddOns={GetAddOnMetadata=function(name,key) eq(name,"AiLeveling");eq(key,"Version");return "test-installed-version" end}
    local scripts,events,C={},{},{}
    CreateFrame=function() return {RegisterEvent=function(_,name) events[name]=true end,
        SetScript=function(_,name,fn) scripts[name]=fn end} end
    SlashCmdList={}
    assert(loadfile("Core.lua"))("AiLeveling",C)
    eq(C.version,"test-installed-version")
    C.Initialize=function() C.ready=true end
    C.Instances={Request=function() end}
    scripts.OnEvent(nil,"ADDON_LOADED","AiLeveling")
    eq(events.PLAYER_DIFFICULTY_CHANGED,true)
    eq(events.GOSSIP_SHOW,true);eq(events.QUEST_DETAIL,true)
    local refreshes=0;C.RequestRefresh=function() refreshes=refreshes+1 end
    scripts.OnEvent(nil,"PLAYER_DIFFICULTY_CHANGED")
    eq(refreshes,1);eq(events.QUEST_DATA_LOAD_RESULT,true)
    C.state={quests={[42]={}}}
    scripts.OnEvent(nil,"QUEST_DATA_LOAD_RESULT",42,true);eq(refreshes,2)
    scripts.OnEvent(nil,"QUEST_DATA_LOAD_RESULT",42,false);eq(refreshes,2)
    scripts.OnEvent(nil,"QUEST_DATA_LOAD_RESULT",43,true);eq(refreshes,2)
    C.state.quests[42]=nil
    scripts.OnEvent(nil,"QUEST_DATA_LOAD_RESULT",42,true);eq(refreshes,2)
    local offerEvent
    C.State={QuestOffersEvent=function(_,event) offerEvent=event end}
    scripts.OnEvent(nil,"GOSSIP_SHOW");eq(offerEvent,"GOSSIP_SHOW");eq(refreshes,3)
    eq(events.ENCOUNTER_START,true);eq(events.ENCOUNTER_END,true)
    local received
    C.Dungeon={EncounterEvent=function(_,...) received={...} end}
    scripts.OnEvent(nil,"ENCOUNTER_END",2732,"首领",1,5,1)
    eq(received[1],"ENCOUNTER_END");eq(received[2],2732);eq(received[6],1)
    CreateFrame,SlashCmdList,C_AddOns=create,slash,addons
end)
test("只有本轮装备提示资料更新才触发重算且合并重复事件",function()
    local create,slash,tooltip,spell=CreateFrame,SlashCmdList,C_TooltipInfo,C_Spell
    local scripts,events,C={},{},{}
    CreateFrame=function() return {RegisterEvent=function(_,name) events[name]=true end,
        SetScript=function(_,name,fn) scripts[name]=fn end} end
    SlashCmdList={};C_TooltipInfo={GetHyperlink=function() end};C_Spell={GetSpellDescription=function() end}
    assert(loadfile("Core.lua"))("AiLeveling",C)
    C.Initialize=function() C.ready=true end;C.Instances={Request=function() end}
    C.Items={tooltipData={[55]=true},spellData={[15600]=true}};C.State={fingerprint="before"}
    scripts.OnEvent(nil,"ADDON_LOADED","AiLeveling");eq(events.TOOLTIP_DATA_UPDATE,true)
    local refreshes=0;C.RequestRefresh=function() refreshes=refreshes+1 end
    scripts.OnEvent(nil,"TOOLTIP_DATA_UPDATE",99);eq(refreshes,0);eq(C.State.fingerprint,"before")
    scripts.OnEvent(nil,"TOOLTIP_DATA_UPDATE");eq(refreshes,0)
    scripts.OnEvent(nil,"TOOLTIP_DATA_UPDATE",55);eq(refreshes,1);eq(C.State.fingerprint,nil)
    scripts.OnEvent(nil,"TOOLTIP_DATA_UPDATE",55);eq(refreshes,1)
    eq(events.SPELL_TEXT_UPDATE,true)
    scripts.OnEvent(nil,"SPELL_TEXT_UPDATE",42);eq(refreshes,1)
    scripts.OnEvent(nil,"SPELL_TEXT_UPDATE",15600);eq(refreshes,2);eq(C.Items.spellData[15600],nil)
    scripts.OnEvent(nil,"SPELL_TEXT_UPDATE",15600);eq(refreshes,2)
    C_Spell=nil;events.SPELL_TEXT_UPDATE=nil
    C_TooltipInfo=nil;events.TOOLTIP_DATA_UPDATE=nil
    scripts.OnEvent(nil,"ADDON_LOADED","AiLeveling");eq(events.TOOLTIP_DATA_UPDATE,nil)
    eq(events.SPELL_TEXT_UPDATE,nil)
    CreateFrame,SlashCmdList,C_TooltipInfo,C_Spell=create,slash,tooltip,spell
end)
test("Forever 接任务事件与规划期间沿路移动保留有效结果",function()
    local scripts, C = {}, {}
    CreateFrame=function() return {RegisterEvent=function() end,SetScript=function(_,k,v) scripts[k]=v end} end
    SlashCmdList={}
    assert(loadfile("Core.lua"))("AiLeveling",C)
    C.State={confirmed={[42]=true}}
    scripts.OnEvent(nil,"QUEST_ACCEPTED",42)
    eq(C.State.confirmed[42],nil)
    C.ready=true;C.state={revision=1,position={map=1,node="start"}};C.char={}
    C.Queue=function(_,_,fn) fn() end
    C.Navigation={OnApproach=function(_,node) return node=="near" end,SetPlan=function() end}
    C.Planner={Build=function()
        C.state={revision=1,position={map=1,node="near"}}
        return {best={id=1},alternatives={}}
    end,Choose=function(_,fresh) return fresh end}
    C:Replan();eq(C.plan.best.id,1)
    local pending
    C.settings={minutes=60}
    C.Queue=function(_,_,fn) pending=fn end
    C.Planner.Build=function(_,_,options)
        eq(options.minutes,60)
        return {best={id=1},alternatives={}}
    end
    C:Replan();C.settings.minutes=5;pending();eq(C.plan.best.id,1)
    dofile("tests/assist.lua")(test,eq,F,A,C)
end)
dofile("tests/dungeon.lua")(test,eq,F,plan)
dofile("tests/dungeon_batch.lua")(test,eq,F,plan)
dofile("tests/gear_transport.lua")(test,eq,F,A,plan)
dofile("tests/reward_gear.lua")(test,eq,F,A,plan)
dofile("tests/item_sets.lua")(test,eq,F,A,plan)
dofile("tests/item_effects.lua")(test,eq,F,A,plan)
dofile("tests/weapon_skills.lua")(test,eq,F,A,plan)
dofile("tests/resources.lua")(test,eq,F,A,plan)
dofile("tests/instances.lua")(test,eq,F)
dofile("tests/supplies.lua")(test,eq,F,A,plan)
dofile("tests/flight.lua")(test,eq,F,A)
dofile("tests/selection.lua")(test,eq,F,A,plan)
dofile("tests/chains.lua")(test,eq,F,A,plan)
dofile("tests/settings.lua")(test,eq,F,A,plan)
dofile("tests/routes.lua")(test,eq,F,A)
dofile("tests/tasks.lua")(test,eq,F,A,plan)
dofile("tests/cross_zone.lua")(test,eq,F,A,plan)
dofile("tests/movement.lua")(test,eq,F,A,plan)
dofile("tests/task_guide.lua")(test,eq,F,A,plan)
dofile("tests/task_timing.lua")(test,eq,F,A)
dofile("tests/task_value.lua")(test,eq,F,A,plan)
dofile("tests/reference_services.lua")(test,eq,F,A,plan)
dofile("tests/merchant.lua")(test,eq,F,A,plan)
dofile("tests/services.lua")(test,eq,F,A,plan)
dofile("tests/experience.lua")(test,eq,F,A,plan)
dofile("tests/reference_flights.lua")(test,eq,F,A,plan)
dofile("tests/public_transit.lua")(test,eq,F,A,plan)
dofile("tests/pvp_tasks.lua")(test,eq,F,A,plan)
dofile("tests/hearth.lua")(test,eq,F,A)
dofile("tests/world_interact.lua")(test,eq)
dofile("tests/area_fallback.lua")(test,eq,F,A)
dofile("tests/bag_highlight.lua")(test,eq)
dofile("tests/bag_snapshot.lua")(test,eq)
print(string.format("\n%d 个关键回归场景通过",passed))
