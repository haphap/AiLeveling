return function(test,eq,F,plan)
    local function context(quests)
        local data,s = F.Data(quests or {}),F.State()
        local d = {id=1,title="夹具副本",instanceId=42,difficultyId=1,verified=true,minLevel=10,maxLevel=30,
            entryNode="goal",exitNode="goal",returnNode="start",actions={},runSeconds=600,waitSeconds=300,xp=1000}
        data.content.dungeons[1],data.content.version = d,"fixture"
        local B = {Navigation=F.Navigation,Content=data.content,Data=data,state=s,char={samples={}},
            settings={minutes=60,gearPreference="xp",dungeons=true,role="DAMAGER",learn=true},RequestRefresh=function() end}
        for _, file in ipairs({"State.lua","Planner/Eligibility.lua","Planner/Travel.lua","Planner/Gear.lua","Planner/Progression.lua","Planner/Supplies.lua","Planner/Dungeon.lua","Planner/DungeonTasks.lua","Planner/Planner.lua"}) do
            assert(loadfile(file))("AiLeveling",B)
        end
        B.State.Refresh=function() B.Dungeon:Sync(s,{}) end
        return B,d,s,data
    end
    local function party(run)
        local names={"IsInRaid","UnitGroupRolesAssigned","UnitIsConnected","UnitIsUnit","canaccessvalue"}
        local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
        local roles={player="DAMAGER",party1="TANK",party2="HEALER",party3="DAMAGER",party4="DAMAGER"}
        local offline={}
        IsInRaid=function() return false end
        UnitGroupRolesAssigned=function(unit) return roles[unit] end
        UnitIsConnected=function(unit) return not offline[unit] end
        UnitIsUnit=function(unit,other) return unit==other end
        canaccessvalue=nil
        local ok,why=pcall(run,roles,offline)
        for _,name in ipairs(names) do _G[name]=saved[name] end
        assert(ok,why)
    end
    test("副本队伍按原生职责计数且同人数换职责与离线改变状态",function()
        party(function(roles,offline)
            local B,d,s=context();s.groupSize=5
            local key=B.State.Group(s);eq(s.group.online,5);eq(s.group.tank,1);eq(s.group.healer,1);eq(s.group.damage,3)
            eq(B.Dungeon.GroupStatus(d,s),true)
            roles.party2="DAMAGER";assert(B.State.Group(s)~=key)
            local ready,text=B.Dungeon.GroupStatus(d,s);eq(ready,false);assert(text:find("需要治疗",1,true))
            roles.party2="HEALER";offline.party2=true;B.State.Group(s)
            ready,text=B.Dungeon.GroupStatus(d,s);eq(ready,false);eq(s.group.healer,0);assert(text:find("1 人离线",1,true))
            offline.party2=nil;eq(B.State.Group(s),key)
        end)
    end)
    test("未指定职责保留未知且仅本人使用设置补充",function()
        party(function(roles)
            local B,d,s=context();s.groupSize=5;s.role="HEALER"
            roles.player="NONE";roles.party2="NONE";B.State.Group(s)
            eq(s.group.healer,1);eq(s.group.unknown,1)
            local ready,text=B.Dungeon.GroupStatus(d,s);eq(ready,false);assert(text:find("职责未确认",1,true))
            roles.player="DAMAGER";B.State.Group(s);eq(s.group.healer,0)
            UnitGroupRolesAssigned=nil;B.State.Group(s);eq(s.group.healer,1);eq(s.group.unknown,4)
            UnitGroupRolesAssigned=function() error("不可读取") end;B.State.Group(s);eq(s.group.unknown,4)
            canaccessvalue=function(value) return value~="TANK" end
            UnitGroupRolesAssigned=function() return "TANK" end;B.State.Group(s);eq(s.group.tank,0);eq(s.group.unknown,4)
            UnitIsConnected=nil;B.State.Group(s);eq(s.group.connectionUnknown,5);eq(B.Dungeon.GroupStatus(d,s),false)
        end)
    end)
    test("团队成员不重复统计本人且不会视为五人小队就绪",function()
        party(function()
            local B,d,s=context();s.groupSize=5;s.role="HEALER"
            IsInRaid=function() return true end
            UnitIsUnit=function(unit,other) assert(other=="player");return unit=="raid3" end
            local seen={}
            UnitGroupRolesAssigned=function(unit) assert(unit:find("raid",1,true)==1);seen[unit]=true;return "NONE" end
            B.State.Group(s);eq(s.group.online,5);eq(s.group.healer,1);eq(s.group.unknown,4)
            assert(seen.raid1 and seen.raid5);eq(seen.player,nil)
            local ready,text=B.Dungeon.GroupStatus(d,s);eq(ready,false);assert(text:find("当前为团队",1,true))
        end)
    end)
    test("满员缺治疗仍计入等队且手动就绪保留玩家安排",function()
        party(function(roles)
            local B,d,s,data=context();s.groupSize=5;B.State.Group(s)
            local assembled=B.Dungeon.Evaluate(d,s,B.settings,data);assert(assembled)
            roles.party2="DAMAGER";B.State.Group(s)
            local waiting=B.Dungeon.Evaluate(d,s,B.settings,data);assert(waiting)
            eq(waiting.seconds-assembled.seconds,d.waitSeconds)
            eq(B.Dungeon:Accept(1),true);eq(B.char.dungeon.phase,"preparing")
            eq(B.Dungeon:Control("ready"),true);eq(B.char.dungeon.phase,"travel")
            eq(B.Dungeon.Evaluate(d,s,B.settings,data).seconds,assembled.seconds)
        end)
    end)
    test("同地图错误或未知难度不进入本轮，正确难度恢复接续",function()
        local B,d,s,data=context()
        eq(B.Dungeon:Accept(1),true)
        s.inInstance,s.instanceId,s.instanceDifficultyId=true,42,213
        B.Dungeon:Sync(s,{})
        eq(B.char.dungeon.entered,nil);eq(B.Dungeon.runSample,nil)
        local actions=B.Dungeon.ActivePlan(d,s,data)
        eq(actions[1].kind,"dungeonBlocked");assert(actions[1].text:find("难度",1,true))
        s.instanceDifficultyId=nil;B.Dungeon:Sync(s,{})
        eq(B.char.dungeon.entered,nil)
        assert(B.Dungeon.ActivePlan(d,s,data)[1].text:find("尚未确认",1,true))
        s.instanceDifficultyId=1;B.Dungeon:Sync(s,{})
        eq(B.char.dungeon.entered,true);eq(B.char.dungeon.phase,"inside")
        eq(B.Dungeon.ActivePlan(d,s,data)[1].kind,"dungeonRun")
    end)
    test("完成首领按实际目录核对副本难度且未知记录保留独立验证",function()
        local B,d,s,data=context()
        assert(loadfile("Data/Dungeons.lua"))("AiLeveling",B)
        s.clientVersion,s.clientBuild="1.60.1","70862"
        d.instanceId=389;d.completionEncounters={2732,2733}
        eq(B.Dungeon.Workflow(d,data.content,s),true)
        d.completionEncounters={2910};eq(B.Dungeon.Workflow(d,data.content,s),false)
        d.instanceId=48;eq(B.Dungeon.Workflow(d,data.content,s),true)
        d.difficultyId=201;eq(B.Dungeon.Workflow(d,data.content,s),false)
        d.completionEncounters={2761};eq(B.Dungeon.Workflow(d,data.content,s),true)
        d.completionEncounters={999999};eq(B.Dungeon.Workflow(d,data.content,s),true)
        d.completionEncounters={2910};s.clientBuild="other"
        eq(B.Dungeon.EncounterIdentity(2910,s),nil);eq(B.Dungeon.Workflow(d,data.content,s),true)
        s.clientBuild="70862";s.clientVersion="other";eq(B.Dungeon.EncounterIdentity(2910,s),nil)
    end)
    test("真实首领身份冲突不记录击败也不进入校准，缺名字使用目录中文",function()
        local B,d,s=context();local native=GetInstanceInfo
        assert(loadfile("Data/Dungeons.lua"))("AiLeveling",B)
        s.clientVersion,s.clientBuild="1.60.1","70862"
        d.instanceId=48;d.completionEncounters={2910}
        local difficulty=1
        GetInstanceInfo=function() return "黑暗深渊","party",difficulty,nil,nil,nil,nil,48 end
        B.Dungeon:Accept(1);s.inInstance,s.instanceId=true,48;B.Dungeon:Sync(s,{})
        local function kill(id,name)
            B.Dungeon:EncounterEvent("ENCOUNTER_START",id,name,difficulty,5)
            B.Dungeon:EncounterEvent("ENCOUNTER_END",id,name,difficulty,5,1)
        end
        kill(2732,"错误副本首领");kill(2761,"错误难度首领")
        eq(B.Dungeon.encounterVisit,nil);eq(B.Dungeon.runSample.encounters,nil)
        kill(2910,nil);eq(B.Dungeon.encounterVisit.kills[2910],B.DungeonCatalog.encounters[2910].title)
        eq(B.Dungeon.runSample.encounters[2910],true)
        kill(999999,"新增|首领");eq(B.Dungeon.encounterVisit.kills[999999],"新增||首领")
        eq(B.char.dungeon.settled,nil);eq(next(B.char.samples),nil)
        GetInstanceInfo=native
    end)
    test("原生首领胜利完成条件允许重复刷取独立校准且不改任务完成",function()
        local B,d,s=context();local native=GetInstanceInfo
        GetInstanceInfo=function() return "夹具副本","party",1,nil,nil,nil,nil,42 end
        d.completionEncounters={2732,2733}
        local function kill(id)
            B.Dungeon:EncounterEvent("ENCOUNTER_START",id,"首领",1,5)
            B.Dungeon:EncounterEvent("ENCOUNTER_END",id,"首领",1,5,1)
        end
        B.Dungeon:Accept(1);s.inInstance,s.instanceId=true,42;B.Dungeon:Sync(s,{})
        B.Dungeon.runSample.seconds=600;kill(2732);kill(2733)
        eq(B.char.dungeon.settled,nil);eq(s.completed[2732],nil);eq(s.quests[2732],nil)
        eq(B.Dungeon:Control("finish"),true);eq(B.char.samples["dungeon:1"].n,1)
        eq(B.Dungeon:Control("finish"),false);eq(B.char.samples["dungeon:1"].n,1)
        s.inInstance=false;B.Dungeon:Sync(s,{});eq(B.Dungeon:Control("again"),true)
        s.inInstance=true;B.Dungeon:Sync(s,{});B.Dungeon.runSample.seconds=900
        eq(B.Dungeon.runSample.encounters,nil);kill(2732);kill(2733)
        B.Dungeon:Control("finish");eq(B.char.samples["dungeon:1"].n,2)
        s.inInstance=false;B.Dungeon:Sync(s,{});B.Dungeon:Control("again")
        s.inInstance=true;B.Dungeon:Sync(s,{});B.Dungeon.runSample.seconds=600;kill(2732)
        B.Dungeon:Control("finish");eq(B.char.samples["dungeon:1"].n,2)
        GetInstanceInfo=native
    end)
    test("首领观察要求本次配对成功事件和实时实例难度",function()
        local B,d,s=context();local native=GetInstanceInfo
        local instance,difficulty=42,1
        GetInstanceInfo=function() return "夹具副本","party",difficulty,nil,nil,nil,nil,instance end
        B.Dungeon:Accept(1);s.inInstance,s.instanceId=true,42;B.Dungeon:Sync(s,{})
        local function start(id,diff) B.Dungeon:EncounterEvent("ENCOUNTER_START",id,"首领",diff or 1,5) end
        local function finish(id,success,diff) B.Dungeon:EncounterEvent("ENCOUNTER_END",id,"首领",diff or 1,5,success) end
        finish(1,1);eq(B.Dungeon.encounterVisit,nil)
        start(1);finish(1,0);finish(1,1);eq(B.Dungeon.encounterVisit,nil)
        start(1);finish(2,1);eq(B.Dungeon.encounterVisit,nil)
        start(1);difficulty=2;finish(1,1);eq(B.Dungeon.encounterVisit,nil);difficulty=1
        start(1);instance=43;finish(1,1);eq(B.Dungeon.encounterVisit,nil);instance=42
        start(1);B.Dungeon:EncounterEvent("PLAYER_ENTERING_WORLD");finish(1,1)
        eq(B.Dungeon.encounterVisit,nil);eq(B.Dungeon.runSample.valid,false)
        start(1);finish(1,1);eq(B.Dungeon.encounterVisit.count,1);eq(B.Dungeon.runSample.encounters,nil)
        finish(1,1);eq(B.Dungeon.encounterVisit.count,1)
        GetInstanceInfo=native
    end)
    test("首领进度适用于参考目录并在重新进入清空，不借观察推断通关",function()
        local B,d,s=context();local native=GetInstanceInfo
        d.reference=true;B.UI={Accent=function() return 1,1,1 end};assert(loadfile("UI/Dungeon.lua"))("AiLeveling",B)
        local ui=B.UI.Dungeon;ui.entries={[1]=d};ui.selected=1;ui.tasks={}
        GetInstanceInfo=function() return "夹具副本","party",1,nil,nil,nil,nil,42 end
        s.inInstance,s.instanceId=true,42
        B.Dungeon:EncounterEvent("ENCOUNTER_START",2732,"首领甲",1,5)
        B.Dungeon:EncounterEvent("ENCOUNTER_END",2732,"首领甲",1,5,1)
        local _,summary=ui:Lines();assert(table.concat(summary,"\n"):find("本次进入已击败：首领甲",1,true))
        eq(B.char.dungeon,nil);eq(B.Dungeon.runSample,nil);eq(next(B.char.samples),nil)
        s.instanceDifficultyId=2;eq(B.Dungeon.EncounterProgress(d,s),nil);s.instanceDifficultyId=1
        s.inInstance=false;eq(B.Dungeon.EncounterProgress(d,s),nil);s.inInstance=true
        B.Dungeon:EncounterEvent("PLAYER_ENTERING_WORLD")
        eq(B.Dungeon.EncounterProgress(d,s),nil)
        GetInstanceInfo=native
    end)
    test("首领与任务条件同时配置需全部满足且换内容或旧战斗不能校准",function()
        local B,d,s=context();local native=GetInstanceInfo
        GetInstanceInfo=function() return "夹具副本","party",1,nil,nil,nil,nil,42 end
        d.completionQuests={1};d.completionEncounters={2732}
        B.Dungeon:Accept(1);s.inInstance,s.instanceId=true,42;B.Dungeon:Sync(s,{})
        B.Dungeon.runSample.seconds=600
        B.Dungeon:EncounterEvent("ENCOUNTER_START",2732,"首领",1,5)
        B.Dungeon:EncounterEvent("ENCOUNTER_END",2732,"首领",1,5,1)
        B.Dungeon:Control("finish");eq(next(B.char.samples),nil)
        s.inInstance=false;B.Dungeon:Sync(s,{});B.Dungeon:Control("again")
        s.inInstance=true;B.Dungeon:Sync(s,{})
        B.Dungeon:EncounterEvent("ENCOUNTER_START",2732,"首领",1,5)
        local old=B.Dungeon.runSample;B.Dungeon.runSample={seconds=600,valid=true,initialCompleted={}}
        B.Dungeon:EncounterEvent("ENCOUNTER_END",2732,"首领",1,5,1)
        eq(B.Dungeon.runSample.encounters,nil)
        B.Dungeon.runSample=old;d.version="changed";B.Dungeon:Sync(s,{})
        eq(B.Dungeon.runSample.valid,false)
        GetInstanceInfo=native
    end)
    test("本内才接受行程或重载后接入不会把部分时间用于整轮校准",function()
        local B,d,s=context()
        s.inInstance,s.instanceId=true,42
        B.Dungeon:Accept(1);eq(B.Dungeon.runSample.valid,false)
        B.Dungeon:Control("stop");s.inInstance=false;B.Dungeon:Accept(1)
        B.Dungeon.sampleFromEntrance=nil
        s.inInstance=true;B.Dungeon:Sync(s,{})
        eq(B.Dungeon.runSample.valid,false)
    end)
    test("切入不同难度不消费旧本内步骤且废弃本轮耗时采样",function()
        local B,d,s,data=context()
        d.actions={{stage="inside",kind="move",node="goal"}};d.completionQuests={1}
        B.Dungeon:Accept(1);s.inInstance,s.instanceId=true,42;B.Dungeon:Sync(s,{})
        local action
        for _,step in ipairs(B.Dungeon.ActivePlan(d,s,data)) do if step.dungeonStep==1 then action=step end end
        assert(action)
        B.Dungeon.runSample.seconds=600
        s.instanceDifficultyId=213
        B.Dungeon:Arrived(action);eq(B.char.dungeon.done[1],nil)
        B.Dungeon:Sync(s,{});eq(B.char.dungeon.phase,"outside");eq(B.Dungeon.runSample.valid,false)
        s.instanceDifficultyId=1;B.Dungeon:Sync(s,{})
        eq(B.char.dungeon.phase,"inside");B.Dungeon:Arrived(action);eq(B.char.dungeon.done[1],true)
        s.quests[1]={ready=true};eq(B.Dungeon:Control("finish"),true)
        eq(B.char.samples["dungeon:1"],nil)
    end)
    test("副本按当前位置计入准备与交付绕路且奖励仅计已安排的交付",function()
        local B,d,s,data = context({[1]=F.Quest(1)})
        d.actions={{stage="before",kind="accept",node="goal",questId=1},
            {stage="after",kind="turnin",node="start",questId=1,seconds=100000}}
        d.questXP={[1]=200,[2]=999}
        local result=B.Dungeon.Evaluate(d,s,B.settings,data)
        eq(result.seconds,940);eq(result.xp,1200)
        s.completed[1]=true
        result=B.Dungeon.Evaluate(d,s,B.settings,data)
        eq(result.seconds,940);eq(result.xp,1000)
    end)
    test("副本须明确接受与就绪才执行且实例 ID 必须匹配",function()
        local B,d,s,data=context()
        local p=plan(s,data,B.settings,B)
        eq(p.best,nil);eq(p.suggestedDungeon.dungeonId,1)
        eq(B.Dungeon:Accept(1),true)
        p=plan(s,data,B.settings,B);eq(p.sessionActive,true);eq(p.best.actions[1].kind,"dungeonWait")
        eq(B.Dungeon:Control("ready"),true)
        p=plan(s,data,B.settings,B);eq(p.best.actions[#p.best.actions].kind,"dungeonEnter")
        s.inInstance,s.instanceId=true,999;B.Dungeon:Sync(s,{})
        eq(s.dungeon.entered,nil)
        p=plan(s,data,B.settings,B);eq(p.best.actions[1].kind,"dungeonBlocked")
        s.instanceId=42;B.Dungeon:Sync(s,{})
        eq(s.dungeon.phase,"inside");eq(s.dungeon.entered,true)
        p=plan(s,data,B.settings,B);eq(p.best.actions[1].kind,"dungeonRun")
    end)
    test("暂离与死亡保留本轮且明确结束只结算一次",function()
        local B,d,s=context()
        B.Dungeon:Accept(1);s.inInstance,s.instanceId=true,42;B.Dungeon:Sync(s,{})
        s.dead=true;B.Dungeon:Sync(s,{});eq(s.dungeon.phase,"recovering")
        s.dead=false;s.inInstance=false;B.Dungeon:Sync(s,{})
        eq(s.dungeon.phase,"outside");eq(s.dungeon.settled,nil)
        eq(B.Dungeon:Control("finish"),true);eq(s.dungeon.phase,"finished")
        eq(B.Dungeon:Control("finish"),false);eq(B.char.dungeon.round,1)
        eq(s.completed[1],nil)
        B.Dungeon:Arrived({kind="dungeonEnd",dungeonId=1});eq(B.char.dungeon.phase,"complete")
    end)
    test("解散后由玩家决定恢复且结束行程恢复野外规划",function()
        local B,d,s,data=context()
        B.Dungeon:Accept(1);s.groupSize=1;B.Dungeon:Sync(s,{groupSize=5})
        eq(s.dungeon.phase,"disbanded")
        local p=plan(s,data,B.settings,B);eq(p.best.actions[1].kind,"dungeonWait")
        eq(B.Dungeon:Control("stop"),true);eq(B.char.dungeon,nil)
        s.dungeon=nil;p=plan(s,data,B.settings,B);eq(p.sessionActive,nil)
    end)
    test("再刷重算剩余预算与当前资格且不自动申请重置",function()
        local B,d,s=context()
        B.Dungeon:Accept(1);s.inInstance,s.instanceId=true,42;B.Dungeon:Sync(s,{})
        B.Dungeon:Control("finish");eq(B.Dungeon:Control("again"),false)
        s.inInstance=false;B.Dungeon:Sync(s,{})
        B.char.dungeon.elapsed=2800
        eq(B.Dungeon:Control("again"),false);eq(B.char.dungeon.round,1)
        B.char.dungeon.elapsed=100
        eq(B.Dungeon:Control("again"),true);eq(B.char.dungeon.round,2)
        eq(B.char.dungeon.elapsed,100);eq(B.char.dungeon.budget,3600);eq(B.char.dungeon.settled,nil)
    end)
    test("副本数据更新重建道路游标且资料缺失保留明确选择",function()
        local B,d,s,data=context()
        B.Dungeon:Accept(1)
        B.char.dungeon.done[1]=true;d.version="updated";B.Dungeon:Sync(s,{})
        eq(s.dungeon.done[1],nil)
        data.content.dungeons[1]=nil;B.Dungeon:Sync(s,{})
        local p=plan(s,data,B.settings,B)
        eq(p.sessionActive,true);eq(p.best,nil);eq(p.fallback.kind,"dungeonBlocked")
    end)
    test("副本存档拒绝损坏预算与游标",function()
        local B=context()
        eq(B.Dungeon.ValidSession({}),false)
        local valid={id=1,phase="preparing",round=1,budget=3600,elapsed=100,done={}}
        eq(B.Dungeon.ValidSession(valid),true)
        valid.elapsed=math.huge;eq(B.Dungeon.ValidSession(valid),false)
        valid.elapsed=100;valid.done={bad=true};eq(B.Dungeon.ValidSession(valid),false)
    end)
    test("提前结束后只交付实际就绪任务，未完成任务继续保留",function()
        local q=F.Quest(1)
        local B,d,s,data=context({[1]=q})
        d.actions={{stage="after",kind="turnin",questId=1,node="start",seconds=5}}
        s.quests[1]={ready=false,objectives={}}
        B.Dungeon:Accept(1);s.inInstance,s.instanceId=true,42;B.Dungeon:Sync(s,{})
        B.Dungeon:Control("finish");s.inInstance=false;B.Dungeon:Sync(s,{})
        local actions=B.Dungeon.ActivePlan(d,s,data)
        for _,action in ipairs(actions) do assert(action.kind~="turnin") end
        eq(s.completed[1],nil);eq(s.quests[1].ready,false)
        s.quests[1].ready=true;actions=B.Dungeon.ActivePlan(d,s,data)
        local found=false;for _,action in ipairs(actions) do if action.kind=="turnin" then found=true end end
        eq(found,true)
    end)
    test("副本预算排除离线间隔且只有确认完整目标后校准一次",function()
        local B,d,s=context()
        local clock,afk=GetTime,UnitIsAFK
        local now=0
        GetTime=function() return now end;UnitIsAFK=function() return false end
        B.Navigation={Distance=F.Navigation.Distance,Current=function() return {kind="dungeonRun"} end}
        d.completionQuests={1}
        B.Dungeon:Accept(1);B.Dungeon:Update()
        s.inInstance,s.instanceId=true,42;B.Dungeon:Sync(s,{})
        for i=1,600 do now=i;B.Dungeon:Update() end
        s.quests[1]={ready=true,objectives={}}
        B.Dungeon:Control("finish")
        eq(B.char.samples["dungeon:1"].n,1);eq(B.char.samples["dungeon:1"].mean,1)
        B.Dungeon:Control("finish");eq(B.char.samples["dungeon:1"].n,1)
        local elapsed=B.char.dungeon.elapsed
        now=10000;B.Dungeon:Update();eq(B.char.dungeon.elapsed,elapsed)
        s.inInstance=false;B.Dungeon:Sync(s,{})
        eq(B.Dungeon:Control("again"),true)
        s.inInstance=true;B.Dungeon:Sync(s,{})
        for _=1,600 do now=now+1;B.Dungeon:Update() end
        B.Dungeon:Control("finish");eq(B.char.samples["dungeon:1"].n,1)
        GetTime,UnitIsAFK=clock,afk
    end)
    test("副本自有道路动作从节点补齐位置并由到达保存进度",function()
        local B,d,s,data=context()
        data.content.nodes.goal.position={map=1,x=0.5,y=0.5}
        d.actions={{stage="inside",kind="move",node="goal"}}
        B.Dungeon:Accept(1);s.inInstance,s.instanceId=true,42;B.Dungeon:Sync(s,{})
        s.position={node="goal"}
        local actions=B.Dungeon.ActivePlan(d,s,data)
        eq(actions[1].position.map,1);eq(actions[1].dungeonStep,1)
        B.Dungeon:Arrived(actions[1]);B.Dungeon:Sync(s,{})
        actions=B.Dungeon.ActivePlan(d,s,data);eq(actions[1].kind,"dungeonRun")
    end)
    test("副本界面通过同一接受与结束入口执行，空资料时关闭入口",function()
        local B,d,s,data=context()
        local create=CreateFrame
        CreateFrame=function() return {SetPoint=function() end,SetSize=function() end,SetHeight=function() end,SetScrollChild=function() end,Hide=function() end} end
        B.UI={Accent=function() return 1,1,1 end,SelectTab=function() end,Text=function()
            return {ClearAllPoints=function() end,SetPoint=function() end,SetWidth=function() end,SetHeight=function() end,GetStringHeight=function() return 100 end,SetText=function(self,v) self.value=v end}
        end,Button=function(_,_,_,_,callback)
            return {text={SetText=function(self,v) self.value=v end,SetWidth=function() end,SetJustifyH=function() end,SetMaxLines=function() end},ClearAllPoints=function() end,SetShown=function(self,v) self.shown=v end,SetPoint=function() end,SetSize=function() end,SetEnabled=function(self,v) self.enabled=v end,click=callback}
        end}
        assert(loadfile("UI/Dungeon.lua"))("AiLeveling",B)
        local ui=B.UI.Dungeon
        ui:Create({}); B.ready=true; ui:Refresh()
        eq(ui.accept.enabled,true);eq(ui.stop.enabled,false)
        ui.accept.click();eq(B.char.dungeon.id,1);eq(ui.stop.enabled,true)
        ui.ready.click();eq(B.char.dungeon.phase,"travel")
        ui.stop.click();eq(B.char.dungeon,nil)
        data.content.dungeons={};B.Content=data.content;ui:Refresh();eq(ui.accept.enabled,false)
        B.DungeonCatalog={version="1.60.1",build="70862",entries={ref={id="ref",reference=true,instanceId=99,title="参考副本",quests={Alliance={[1]="alternative"}}}}}
        s.clientVersion,s.clientBuild,s.faction="1.60.1","70862","Alliance"
        local q=F.Quest(1);data.GetQuest=function(_,id) if id==1 then return q end end
        data.Target=function() return {map=1,x=0.2,y=0.3} end
        local focused,locked
        B.UI.Chains={Focus=function(_,id) focused=id end}
        B.Selection={LockQuest=function(_,id) locked=id;return true end}
        ui:Refresh();eq(ui.accept.enabled,false);eq(ui.taskGo.enabled,true);eq(ui.accept.shown,false);eq(ui.bodyTop,136)
        eq(ui.retry.shown,false)
        s.instanceEntryError="实例次数受限";ui:Refresh()
        eq(ui.retry.shown,true);eq(ui.retry.enabled,true);eq(ui.accept.shown,false);eq(ui.bodyTop,136)
        assert(ui.status.value:find(s.instanceEntryError,1,true))
        B.Instances={Retry=function() s.instanceEntryError=nil;return true end}
        ui.retry.click();eq(ui.retry.shown,false);eq(ui.bodyTop,136)
        assert(table.concat(ui:Lines(),"\n"):find("部分目标有其他来源",1,true))
        local started
        local startBatch=B.Dungeon.StartTaskBatch
        B.Dungeon.StartTaskBatch=function(_,id) started=id;B.char.taskBatch={id=id,baselines={[1]=0}};return true end
        B.Selection.Automatic=function() B.char.taskBatch=nil;return true end
        eq(ui.taskBatch.enabled,true);ui.taskBatch.click();eq(started,"ref")
        eq(ui.taskBatch.text.value,"结束任务安排");assert(table.concat(ui:Lines(),"\n"):find("已安排",1,true))
        eq(ui.ready.shown,true);eq(ui.ready.text.value,"等队做任务");eq(ui.bodyTop,136)
        local waitRefresh=B.State.Refresh
        B.State.Refresh=function() end
        ui.ready.click();eq(B.char.taskBatch.waiting,true);eq(ui.ready.text.value,"出发去副本")
        assert(ui.status.value:find("等队",1,true))
        ui.ready.click();eq(B.char.taskBatch.waiting,nil);eq(ui.ready.text.value,"等队做任务")
        B.State.Refresh=waitRefresh
        ui.taskBatch.click();eq(B.char.taskBatch,nil);eq(ui.taskBatch.text.value,"安排关联任务")
        eq(ui.ready.shown,false);eq(ui.bodyTop,136)
        B.Dungeon.StartTaskBatch=startBatch
        ui.taskChain.click();eq(focused,1)
        ui.taskGo.click();eq(locked,1)
        local located=data.Target
        data.Target=function() end;data.maps={[100]=2}
        B.DungeonCatalog.entries.ref.areas={100}
        data.UnmappedTargetArea=function() return 100 end
        ui:Refresh();eq(ui.taskGo.enabled,true);eq(ui.taskBatch.enabled,true)
        eq(ui.tasks[1].position,nil);eq(ui.tasks[1].areaId,100)
        ui.taskGo.click();eq(locked,1)
        data.UnmappedTargetArea=function() return 999 end
        ui:Refresh();eq(ui.taskGo.enabled,false);assert(not ui.taskBatch.enabled)
        data.Target=located;data.UnmappedTargetArea=nil
        assert(loadfile("Planner/Chains.lua"))("AiLeveling",B)
        local before=F.Quest(2);q.preQuestGroup={2}
        data.GetQuest=function(_,id) return id==1 and q or id==2 and before end
        ui:Refresh();eq(ui.taskGo.enabled,true);eq(ui.taskGo.text.value,"准备前置任务")
        ui.taskGo.click();eq(locked,1)
        s.skipped[2]=true;ui:Refresh();eq(ui.taskGo.enabled,false)
        s.skipped[1]=true;ui:Refresh();eq(ui.taskGo.enabled,false)
        ui.taskGo.click();eq(ui.message,"已暂缓")
        s.clientBuild="different";ui:Refresh();eq(ui.selector.enabled,false);eq(ui.taskGo.enabled,false)
        CreateFrame=create
    end)
    test("副本任务目录按构建隔离且已验证行程覆盖同实例参考",function()
        local B,d,s,data=context()
        B.DungeonCatalog={version="1.60.1",build="70862",entries={ref={instanceId=42},other={instanceId=99}}}
        eq(B.Dungeon.Catalog(s,data.content).ref,nil)
        s.clientVersion,s.clientBuild="1.60.1",70862
        local entries=B.Dungeon.Catalog(s,data.content)
        eq(entries[1],d);eq(entries.ref,nil);assert(entries.other)
        s.clientBuild="next";eq(B.Dungeon.Catalog(s,data.content).other,nil)
    end)
    test("副本任务区分已接可交付前置资格和阵营并按收件人排序",function()
        local quests={}
        for id=1,7 do quests[id]=F.Quest(id) end
        quests[3].preQuestSingle={99,98};quests[6].requiredRaces=2
        local B,d,s,data=context(quests)
        data.Target=function(_,q) return {map=1,x=0.2,y=0.3,entityKind="npc",entityId=q.id==7 and 1 or q.id,entityName="收件人"} end
        d={reference=true,quests={Alliance={[1]="inside",[2]="category",[3]="category",[4]="alternative",[5]="inside",[6]="inside",[7]="inside"}}}
        s.faction="Alliance";s.quests={[1]={ready=true},[2]={},[7]={ready=true}};s.completed[5]=true
        local rows=B.Dungeon.Tasks(d,s,data)
        eq(#rows,6);eq(rows[1].id,1);eq(rows[2].id,7);eq(rows[1].recipient,rows[2].recipient)
        eq(rows[3].id,2);eq(rows[3].status,"已接取")
        eq(rows[4].id,4);eq(rows[4].status,"未接取")
        eq(rows[5].id,3);eq(rows[5].reason,"备选前置未交付")
        eq(rows[6].id,5);eq(rows[6].status,"已交付")
        s.completed[98]=true;rows=B.Dungeon.Tasks(d,s,data);eq(rows[4].id,3);eq(rows[4].allowed,true)
        eq(s.completed[3],nil);eq(s.quests[4],nil)
    end)

    local function approachFixture()
        local q=F.Quest(1);q.verified=false
        local B,_,s,data=context({[1]=q});data.content.dungeons={}
        local d={instanceId=42,title="测试副本",areas={100},entrances={{200,80,0},{200,20,0}},quests={}}
        B.DungeonCatalog={version="1.60.1",build="70862",entries={ref=d}}
        s.clientVersion,s.clientBuild="1.60.1","70862"
        data.maps={[100]=7,[200]=1}
        local point={map=7,x=0.5,y=0.5,entityKind="npc",entityId=99}
        data.Target=function() return point end
        s.quests[1]={title=q.title,objectives={{text="目标",numRequired=1,numFulfilled=0}}}
        return B,d,s,data,point
    end
    test("副本任务规划先到入口，真实进本后恢复目标且暂离可再次引导",function()
        local B,d,s,data,point=approachFixture()
        for _,file in ipairs({"Planner/Flights.lua","Planner/TaskGuide.lua","Planner/TaskQueue.lua"}) do
            assert(loadfile(file))("AiLeveling",B)
        end
        local p=plan(s,data,B.settings,B)
        eq(p.fallback.kind,"dungeonEnter");eq(p.fallback.position.map,1);eq(p.fallback.position.x,0.2)
        eq(p.fallback.questId,1);eq(p.taskChoices[1].actions[1].position,point)
        eq(p.travelActions[#p.travelActions],p.fallback)
        eq(#p.travelActions,1);eq(p.travelActions[1],p.fallback)
        for _,file in ipairs({"UI/Main.lua","UI/Tracker.lua","Routes.lua"}) do assert(loadfile(file))("AiLeveling",B) end
        local model=B.UI.TrackerModel(s,p,p.fallback,false)
        eq(model.questId,1);eq(model.title,s.quests[1].title);eq(model.objectives[1].have,0)
        assert(model.instruction:find("入口",1,true))
        local segments,missing=B.Routes.Segments(p.travelActions,1,1,function(point,map)
            if point.map==map then return point.x,point.y end
        end,s.position)
        eq(#segments,1);eq(segments[1].tx,0.2);eq(missing,0)
        s.position=p.fallback.position
        p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter")
        s.inInstance,s.instanceId,s.position=true,42,point
        p=plan(s,data,B.settings,B);eq(p.fallback.kind,"objective");eq(p.fallback.position,point)
        s.inInstance=false;s.position={map=1,x=0.8,y=0}
        p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter");eq(p.fallback.position.x,0.8)
        s.inInstance,s.instanceId=true,999
        p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonLeave");eq(p.fallback.position,nil)
        eq(s.completed[1],nil);eq(s.quests[1].ready,nil);eq(B.char.dungeon,nil)
    end)
    test("无内部地图时入口本内暂离与交付连续接续且保留目标进度",function()
        local B,d,s,data=approachFixture();data.maps[100]=nil
        data.Target=function() end;data.UnmappedTargetArea=function() return 100,1 end
        for _,file in ipairs({"Planner/Flights.lua","Planner/TaskGuide.lua","Planner/TaskQueue.lua"}) do assert(loadfile(file))("AiLeveling",B) end
        local p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter");eq(p.fallback.position.x,0.2)
        eq(p.taskChoices[1].actions[1].areaId,100);eq(p.taskChoices[1].actions[1].objectiveIndex,1)
        eq(p.taskChoices[1].timing.seconds,nil)
        s.position=p.fallback.position;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter")
        s.inInstance,s.instanceId,s.position=true,42,nil
        p=plan(s,data,B.settings,B);eq(p.fallback.kind,"objective");eq(p.fallback.position,nil)
        eq(p.taskChoices[1].currentInstance,true);assert(p.fallback.text:find("测试副本",1,true))
        eq(p.travelActions,nil);eq(s.quests[1].ready,nil);eq(s.completed[1],nil)
        for _,file in ipairs({"UI/Main.lua","UI/Tracker.lua"}) do assert(loadfile(file))("AiLeveling",B) end
        local model=B.UI.TrackerModel(s,p,p.fallback,false)
        assert(model.instruction:find("测试副本",1,true));eq(model.objectives[1].have,0)
        local oldCurrent=B.Navigation.Current
        B.state,B.plan=s,p;B.Navigation.Current=function() return p.fallback end
        assert(table.concat(B.UI:TaskLines(),"\n"):find("测试副本",1,true))
        B.Navigation.Current=oldCurrent
        s.quests[1].ready=true;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"turnin")
        s.quests[1]=nil;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"accept")
        s.instanceId=99;s.locked=1;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonLeave")
        s.inInstance=false;s.position={map=1,x=0.8,y=0};p=plan(s,data,B.settings,B)
        eq(p.fallback.kind,"dungeonEnter");eq(p.fallback.position.x,0.8)
        s.instanceEntryError="进入受限";p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonBlocked")
        eq(p.fallback.position,nil);eq(p.travelActions,nil)
    end)
    test("无地图区域归属保持版本和唯一性门控并让实际坐标优先",function()
        local B,d,s,data,point=approachFixture();data.maps[100]=nil
        local action={kind="objective",questId=1,areaId=100}
        eq(B.Dungeon.TaskApproach(action,s,data).kind,"dungeonEnter")
        action.position={map=1,x=0.4,y=0};eq(B.Dungeon.TaskApproach(action,s,data),action)
        action.position=nil;s.clientBuild="next";eq(B.Dungeon.TaskApproach(action,s,data),action)
        s.clientBuild="70862";B.DungeonCatalog.entries.other={instanceId=99,areas={100}}
        eq(B.Dungeon.TaskApproach(action,s,data),action);B.DungeonCatalog.entries.other=nil
        d.entrances={};local guide=B.Dungeon.TaskApproach(action,s,data)
        eq(guide.position,nil);assert(guide.text:find("测试副本入口",1,true))
        action.areaId=999;eq(B.Dungeon.TaskApproach(action,s,data),action)
    end)
    test("进入次数受限时参考任务不导航入口，保留其他任务及手动意图",function()
        local B,d,s,data,point=approachFixture()
        s.instanceEntryError="实例次数受限"
        local p=plan(s,data,B.settings,B)
        eq(p.fallback.kind,"dungeonBlocked");eq(p.fallback.position,nil);eq(p.travelActions,nil)
        eq(p.fallback.questId,1);assert(p.fallback.text:find(s.instanceEntryError,1,true))
        -- A locked task stays selected but cannot bypass the observed entry rejection.
        s.locked=1;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonBlocked")
        s.inInstance,s.instanceId=true,42
        p=plan(s,data,B.settings,B);eq(p.fallback.kind,"objective");eq(p.fallback.position,point)
        s.inInstance=false;s.locked=nil
        local q=F.Quest(2);q.verified=false
        local get=data.GetQuest
        data.GetQuest=function(self,id) return id==2 and q or get(self,id) end
        data.Target=function(_,quest) return quest.id==2 and {map=1,x=0.4,y=0} or point end
        data.Candidates=function() return {1,2} end
        p=plan(s,data,B.settings,B);eq(p.fallback.questId,2);eq(p.fallback.kind,"accept")
        eq(p.taskChoices[1].questId,2)
        for _,file in ipairs({"UI/Main.lua","UI/Tracker.lua"}) do assert(loadfile(file))("AiLeveling",B) end
        local model=B.UI.TrackerModel(s,p,p.fallback,false)
        eq(model.rows[1].questId,1);assert(model.rows[1].progress:find(s.instanceEntryError,1,true))
        s.quests[2]={ready=true,objectives={}}
        p=plan(s,data,B.settings,B);eq(p.fallback.questId,2);eq(p.fallback.kind,"turnin")
        s.quests[2]=nil;s.locked=1;s.instanceEntryError=nil
        p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter")
        eq(s.completed[1],nil);eq(s.quests[1].ready,nil)
    end)
    test("入口依据实际目标地图与楼层，野外目标和构建不符不改写",function()
        local B,d,s,data,point=approachFixture()
        local a={kind="objective",questId=1,position=point}
        local oldMap=C_Map
        C_Map={GetMapInfo=function(id) return {parentMapID=id==8 and 7 or 0} end}
        point.map=8;eq(B.Dungeon.TaskApproach(a,s,data).kind,"dungeonEnter")
        point.map=1;eq(B.Dungeon.TaskApproach(a,s,data),a)
        point.map=7;s.clientBuild="next";eq(B.Dungeon.TaskApproach(a,s,data),a)
        s.clientBuild="70862";d.entrances={};eq(B.Dungeon.TaskApproach(a,s,data),a)
        d.entrances={{999,20,30}};eq(B.Dungeon.TaskApproach(a,s,data),a)
        d.entrances={{200,20,0}};B.DungeonCatalog.entries.other={instanceId=99,areas={100}}
        eq(B.Dungeon.TaskApproach(a,s,data),a)
        B.DungeonCatalog.entries.other=nil;point.map=8
        C_Map.GetMapInfo=function(id) return {parentMapID=id} end
        eq(B.Dungeon.TaskApproach(a,s,data),a);C_Map=oldMap
    end)

    test("副本距离未知时先做本内任务，再出本交付，手动锁定及暂缓可覆盖",function()
        local B,_,s,data,inside=approachFixture()
        local q1,q2=F.Quest(1),F.Quest(2);q1.verified=false;q2.verified=false
        data.GetQuest=function(_,id) return id==1 and q1 or id==2 and q2 end
        data.Candidates=function() return {1,2} end
        local outside={map=1,x=0.4,y=0.2,entityKind="npc",entityId=9,entityName="交付者"}
        data.Target=function(_,q,state)
            if state.quests[q.id] and state.quests[q.id].ready then
                return {map=outside.map,x=outside.x,y=outside.y,entityKind="npc",entityId=q.id,entityName="不同收件人"}
            end
            return inside
        end
        s.quests[1].ready=true;s.quests[2]={objectives={{text="未完成",numRequired=1,numFulfilled=0}}}
        s.inInstance,s.instanceId,s.position=true,42,inside
        B.Navigation={Distance=function() return nil end}
        for _,file in ipairs({"Planner/Flights.lua","Planner/TaskGuide.lua","Planner/TaskQueue.lua"}) do assert(loadfile(file))("AiLeveling",B) end
        local oldMap=C_Map;C_Map={GetMapInfo=function(id) return {mapType=id==1 and 3 or 4} end}
        local p=plan(s,data,B.settings,B)
        eq(p.fallback.kind,"objective");eq(p.fallback.questId,2);eq(p.taskChoices[1].questId,2);eq(p.taskOrder[1].questId,2)
        s.locked=1;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonLeave");eq(p.fallback.questId,1)
        s.locked=nil;s.skipped[2]=true;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonLeave")
        s.skipped[2]=nil
        data.Target=function(_,q,state) return state.quests[q.id] and state.quests[q.id].ready and outside or inside end
        p=plan(s,data,B.settings,B);eq(p.fallback.questId,2)
        local groups=B.TaskGuide.DeliveryGroups(p.taskChoices,s);eq(#groups,1);eq(groups[1].ready,1)
        s.quests[2].ready=true;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonLeave")
        groups=B.TaskGuide.DeliveryGroups(p.taskChoices,s);eq(groups[1].ready,2)
        s.inInstance=false;s.position=outside;p=plan(s,data,B.settings,B);eq(p.fallback.kind,"turnin")
        eq(s.completed[1],nil);eq(s.completed[2],nil);eq(B.char.dungeon,nil)
        C_Map=oldMap
    end)
    test("出本指引只用于已知室外目的地，本内交付与未知地图保持原行动",function()
        local B,_,s,data,inside=approachFixture();s.inInstance,s.instanceId=true,42
        local a={kind="turnin",questId=1,position=inside}
        local oldMap=C_Map;C_Map={GetMapInfo=function(id) return {mapType=id==7 and 4 or 3} end}
        eq(B.Dungeon.TaskApproach(a,s,data),a)
        local outside={map=1,x=0.4,y=0.2};a.position=outside
        eq(B.Dungeon.TaskApproach(a,s,data).kind,"dungeonLeave")
        a.kind="objective";assert(B.Dungeon.TaskApproach(a,s,data).text:find("继续任务",1,true))
        C_Map.GetMapInfo=function() return {mapType=4} end;eq(B.Dungeon.TaskApproach(a,s,data),a)
        C_Map.GetMapInfo=function() return nil end;eq(B.Dungeon.TaskApproach(a,s,data),a)
        C_Map.GetMapInfo=function() return {mapType=3} end;s.clientBuild="next"
        eq(B.Dungeon.TaskApproach(a,s,data),a);C_Map=oldMap
    end)

end
