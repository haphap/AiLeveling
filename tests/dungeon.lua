return function(test,eq,F,plan)
    local function context(quests)
        local data,s = F.Data(quests or {}),F.State()
        local d = {id=1,title="夹具副本",instanceId=42,difficultyId=1,reference=true,minLevel=10,maxLevel=30}
        local B = {Navigation=F.Navigation,Data=data,state=s,char={samples={}},
            settings={minutes=60,gearPreference="xp",dungeons=true,role="DAMAGER",learn=true},RequestRefresh=function() end}
        for _, file in ipairs({"State.lua","Planner/Eligibility.lua","Planner/Travel.lua","Planner/Gear.lua","Planner/Progression.lua","Planner/Supplies.lua","Planner/Dungeon.lua","Planner/DungeonTasks.lua","Planner/Planner.lua"}) do
            assert(loadfile(file))("AiLeveling",B)
        end
        B.DungeonCatalog={entries={[1]=d}}
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

    test("真实首领身份冲突不记录击败也不进入校准，缺名字使用目录中文",function()
        local B,d,s=context();local native=GetInstanceInfo
        assert(loadfile("Data/Dungeons.lua"))("AiLeveling",B)
        s.clientVersion,s.clientBuild="1.60.1","70862"
        d.instanceId=48;d.completionEncounters={2910}
        local difficulty=1
        GetInstanceInfo=function() return "黑暗深渊","party",difficulty,nil,nil,nil,nil,48 end
        s.inInstance,s.instanceId=true,48
        local function kill(id,name)
            B.Dungeon:EncounterEvent("ENCOUNTER_START",id,name,difficulty,5)
            B.Dungeon:EncounterEvent("ENCOUNTER_END",id,name,difficulty,5,1)
        end
        kill(2732,"错误副本首领");kill(2761,"错误难度首领")
        eq(B.Dungeon.encounterVisit,nil)
        kill(2910,nil);eq(B.Dungeon.encounterVisit.kills[2910],B.DungeonCatalog.encounters[2910].title)
        kill(999999,"新增|首领");eq(B.Dungeon.encounterVisit.kills[999999],"新增||首领")
        eq(next(B.char.samples),nil)
        GetInstanceInfo=native
    end)

    test("首领观察要求本次配对成功事件和实时实例难度",function()
        local B,d,s=context();local native=GetInstanceInfo
        local instance,difficulty=42,1
        GetInstanceInfo=function() return "夹具副本","party",difficulty,nil,nil,nil,nil,instance end
        s.inInstance,s.instanceId=true,42
        local function start(id,diff) B.Dungeon:EncounterEvent("ENCOUNTER_START",id,"首领",diff or 1,5) end
        local function finish(id,success,diff) B.Dungeon:EncounterEvent("ENCOUNTER_END",id,"首领",diff or 1,5,success) end
        finish(1,1);eq(B.Dungeon.encounterVisit,nil)
        start(1);finish(1,0);finish(1,1);eq(B.Dungeon.encounterVisit,nil)
        start(1);finish(2,1);eq(B.Dungeon.encounterVisit,nil)
        start(1);difficulty=2;finish(1,1);eq(B.Dungeon.encounterVisit,nil);difficulty=1
        start(1);instance=43;finish(1,1);eq(B.Dungeon.encounterVisit,nil);instance=42
        start(1);B.Dungeon:EncounterEvent("PLAYER_ENTERING_WORLD");finish(1,1)
        eq(B.Dungeon.encounterVisit,nil)
        start(1);finish(1,1);eq(B.Dungeon.encounterVisit.count,1)
        finish(1,1);eq(B.Dungeon.encounterVisit.count,1)
        GetInstanceInfo=native
    end)
    test("首领进度适用于参考目录并在重新进入清空，不借观察推断通关",function()
        local B,d,s=context();local native=GetInstanceInfo
        d.reference=true;assert(loadfile("UI/Main.lua"))("AiLeveling",B)
        B.UI.Accent=function() return 1,1,1 end;B.UI.Icon=function() return "" end
        assert(loadfile("UI/Dungeon.lua"))("AiLeveling",B)
        local ui=B.UI.Dungeon;ui.entries={[1]=d};ui.selected=1;ui.tasks={}
        GetInstanceInfo=function() return "夹具副本","party",1,nil,nil,nil,nil,42 end
        s.inInstance,s.instanceId=true,42
        B.Dungeon:EncounterEvent("ENCOUNTER_START",2732,"首领甲",1,5)
        B.Dungeon:EncounterEvent("ENCOUNTER_END",2732,"首领甲",1,5,1)
        assert(B.Dungeon.EncounterProgress(d,s):find("本次进入已击败：首领甲",1,true))
        eq(next(B.char.samples),nil)
        s.instanceDifficultyId=2;eq(B.Dungeon.EncounterProgress(d,s),nil);s.instanceDifficultyId=1
        s.inInstance=false;eq(B.Dungeon.EncounterProgress(d,s),nil);s.inInstance=true
        B.Dungeon:EncounterEvent("PLAYER_ENTERING_WORLD")
        eq(B.Dungeon.EncounterProgress(d,s),nil)
        GetInstanceInfo=native
    end)

    test("副本目录不因补丁升级隐藏",function()
        local B,d,s,data=context()
        B.DungeonCatalog={version="1.60.1",build="70862",entries={ref={instanceId=42},other={instanceId=99}}}
        local entries=B.Dungeon.Catalog()
        eq(entries[1],nil);assert(entries.ref);assert(entries.other)
        s.clientVersion,s.clientBuild="1.60.1","70888"
        assert(loadfile("Data/Dungeons.lua"))("AiLeveling",B)
        entries=B.Dungeon.Catalog()
        local count=0;for _ in pairs(entries) do count=count+1 end
        eq(count,39);eq(entries["reference:36"].title,"死亡矿井")
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
        local B,_,s,data=context({[1]=q})
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
        s.clientBuild="70888"
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
        eq(s.completed[1],nil);eq(s.quests[1].ready,nil)
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
    test("无地图区域归属必须唯一且实际坐标优先",function()
        local B,d,s,data,point=approachFixture();data.maps[100]=nil
        local action={kind="objective",questId=1,areaId=100}
        eq(B.Dungeon.TaskApproach(action,s,data).kind,"dungeonEnter")
        action.position={map=1,x=0.4,y=0};eq(B.Dungeon.TaskApproach(action,s,data),action)
        action.position=nil;s.clientBuild="70888";eq(B.Dungeon.TaskApproach(action,s,data).kind,"dungeonEnter")
        B.DungeonCatalog.entries.other={instanceId=99,areas={100}}
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
        eq(#model.rows,0) -- Blocked candidates stay in the main task browser, outside the itinerary.
        s.quests[2]={ready=true,objectives={}}
        p=plan(s,data,B.settings,B);eq(p.fallback.questId,2);eq(p.fallback.kind,"turnin")
        s.quests[2]=nil;s.locked=1;s.instanceEntryError=nil
        p=plan(s,data,B.settings,B);eq(p.fallback.kind,"dungeonEnter")
        eq(s.completed[1],nil);eq(s.quests[1].ready,nil)
    end)
    test("入口依据实际目标地图与楼层且不改写野外目标",function()
        local B,d,s,data,point=approachFixture()
        local a={kind="objective",questId=1,position=point}
        local oldMap=C_Map
        C_Map={GetMapInfo=function(id) return {parentMapID=id==8 and 7 or 0} end}
        point.map=8;eq(B.Dungeon.TaskApproach(a,s,data).kind,"dungeonEnter")
        point.map=1;eq(B.Dungeon.TaskApproach(a,s,data),a)
        point.map=7;d.entrances={};eq(B.Dungeon.TaskApproach(a,s,data),a)
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
        eq(s.completed[1],nil);eq(s.completed[2],nil)
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
        C_Map.GetMapInfo=function() return nil end;eq(B.Dungeon.TaskApproach(a,s,data),a);C_Map=oldMap
    end)

end
