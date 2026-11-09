return function(test,eq,F,A,C)
    test("任务物品区分可用道具、收集与钥匙并显示真实缺口",function()
        local s,q=F.State(),F.Quest(1)
        q.sourceItemId=500;q.requiredSourceItems={700}
        q.itemRules={[500]={kind="use",count=1,target="目标",condition="区域内",recovery="接取 NPC 补发"},
            [600]={kind="collect",count=5}}
        s.bags={[500]=0,[600]=3,[700]=1};s.quests[1]={objectives={},itemId=500}
        local data=F.Data({[1]=q})
        local rows=A.QuestAssist.Requirements({kind="objective",questId=1},s,data)
        eq(#rows,3);eq(rows[1].id,500);eq(rows[1].missing,1);eq(rows[1].recovery,"接取 NPC 补发")
        eq(rows[2].missing,2);eq(rows[3].kind,"key")
        local desired=A.QuestAssist.Desired({kind="objective",questId=1},s,true,data)
        eq(#desired,1);eq(desired[1],500)
        desired=A.QuestAssist.Desired({kind="move",questId=1},s,true,data)
        eq(#desired,0)
    end)
    test("来源物品用途未知时保留提示且完成任务收起使用按钮",function()
        local s,q=F.State(),F.Quest(1);q.sourceItemId=500
        local data=F.Data({[1]=q})
        eq(#A.QuestAssist.Desired({kind="objective",questId=1},s,true,data),0)
        s.quests[1]={ready=true,itemId=500,objectives={}}
        eq(#A.QuestAssist.Desired({kind="objective",questId=1},s,true,data),0)
        q.startedBy={[3]={900,901}}
        local desired=A.QuestAssist.Desired({kind="accept",questId=1},s,true,data)
        eq(desired[1],900)
        s.bags[901]=1;desired=A.QuestAssist.Desired({kind="accept",questId=1,position={startItemId=901}},s,true,data)
        eq(#desired,1);eq(desired[1],901)
    end)
    test("同构建成功物品用途补使用按钮与目标且不猜数量或覆盖明确规则",function()
        local s,q=F.State(),F.Quest(1);q.questLevel=10;q.sourceItemId=500
        s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
        s.quests[1]={objectives={}};s.bags[500]=0
        local B={TaskFacts={cacheXP={version="1.60.1",build="70862",interface=16001,quests={
            [1]={level=10,itemUses={[500]={spellId=123,targets={{kind="npc",id=6},{kind="npc",id=6},{kind="object",id=7}}}}}}}}}
        assert(loadfile("Data/Questie.lua"))("AiLeveling",B)
        B.Data.GetQuest=function() return q end
        B.Data.db={Npc={Get=function() return "任务角色" end},Object={Get=function() return "任务物件" end}}
        local action={kind="objective",questId=1}
        local rows=A.QuestAssist.Requirements(action,s,B.Data)
        eq(#rows,1);eq(rows[1].kind,"use");eq(rows[1].countKnown,nil);eq(rows[1].missing,1)
        eq(rows[1].target,"使用目标：任务角色、任务物件")
        eq(A.QuestAssist.Desired(action,s,true,B.Data)[1],500)
        eq(#A.QuestAssist.Desired(action,s,false,B.Data),0)
        q.itemRules={[500]={kind="key",count=2}}
        rows=A.QuestAssist.Requirements(action,s,B.Data);eq(rows[1].kind,"key");eq(rows[1].missing,2)
        eq(#A.QuestAssist.Desired(action,s,true,B.Data),0);q.itemRules=nil
        s.quests[1].ready=true;eq(#A.QuestAssist.Desired(action,s,true,B.Data),0);s.quests[1].ready=nil
        s.clientBuild="other";eq(#A.QuestAssist.Desired(action,s,true,B.Data),0);s.clientBuild="70862"
        q.questLevel=11;eq(#A.QuestAssist.Desired(action,s,true,B.Data),0);q.questLevel=10
        eq(#A.QuestAssist.Desired({kind="turnin",questId=1},s,true,B.Data),0)
        eq(#A.QuestAssist.Desired({kind="accept",questId=1},s,true,B.Data),0)
    end)
    test("超过四件任务物品可翻页且旧页越界时恢复有效页",function()
        local items={1,2,3,4,5,6}
        local page,index,pages=A.QuestAssist.Page(items,2)
        eq(#page,2);eq(page[1],5);eq(index,2);eq(pages,2)
        page,index=A.QuestAssist.Page({9},2);eq(index,1);eq(page[1],9)
    end)
    test("配置边界恢复损坏值且保留有效偏好",function()
        local s={mode="fast",gearPreference="nearby",role="HEALER",scale=0/0,alpha=5,minutes=90,waitMinutes=-1,position={"invalid","CENTER",0,0}}
        C:NormalizeSettings(s)
        eq(s.mode,nil);eq(s.gearPreference,"xp");eq(s.role,"HEALER");eq(s.scale,1);eq(s.alpha,0.94)
        eq(s.minutes,90);eq(s.waitMinutes,10);eq(s.position,nil)
    end)
    test("恢复设置保留角色事实、暂缓与副本选择",function()
        C.settings={scale=1.3,position={"CENTER","CENTER",1,2}}
        C.char={skipped={[1]=true},samples={},dungeon={id=42}}
        C.state={completed={[7]=true}}
        C.UI={frame={ClearAllPoints=function() end,SetPoint=function() end},ApplyStyle=function() end,Settings={Refresh=function() end}}
        C.Navigation={RefreshPins=function() end};C.State={Refresh=function() end}
        C.Transport={InvalidateSample=function() end}
        C:RestoreSettings()
        eq(C.settings.mode,nil);eq(C.settings.position,nil)
        eq(C.state.completed[7],true);eq(C.char.skipped[1],true);eq(C.char.dungeon.id,42)
    end)
    test("损坏角色统计不影响有效交付历史与偏好",function()
        C.Dungeon={ValidSession=function() return false end}
        local char={samples={bad={n="bad"},good={n=3,mean=1,m2=0,unit="ratio"}},
            turnIns={[1]=2,[2]="bad"},skipped={[42]=true},dungeon="bad",gearTarget="goal",gearBaseline=0/0,hearthBinding="bad",
            locked={},itinerary={sequence="1>>2"},deferredChains={[1]=true,[2]="bad",[-3]=true}}
        local routeKey="flighttime:1.60.1.70862:test:Horde:80:23:via:80:25:23"
        char.samples[routeKey]={n=3,mean=210,m2=2,unit="seconds"}
        char.samples[routeKey..":speed:1"]={n=3,mean=200,m2=2,unit="seconds"}
        char.samples[routeKey..":speed:1.2"]={n=3,mean=180,m2=2,unit="seconds"}
        for _,speed in ipairs({"unknown","0","2","nan","1.20"}) do
            char.samples[routeKey..":speed:"..speed]={n=3,mean=1,m2=0,unit="seconds"}
        end
        C:NormalizeCharacter(char)
        eq(char.samples.bad,nil);eq(char.samples.good.n,3)
        eq(char.samples[routeKey].mean,210)
        eq(char.samples[routeKey..":speed:1"].mean,200);eq(char.samples[routeKey..":speed:1.2"].mean,180)
        for _,speed in ipairs({"unknown","0","2","nan","1.20"}) do eq(char.samples[routeKey..":speed:"..speed],nil) end
        eq(char.turnIns[1],2);eq(char.turnIns[2],nil);eq(char.skipped[42],true);eq(char.dungeon,nil)
        eq(char.gearTarget,nil);eq(char.gearBaseline,nil);eq(char.hearthBinding,nil)
        eq(char.itinerary,nil);eq(char.locked,nil)
        eq(char.deferredChains[1],true);eq(char.deferredChains[2],nil);eq(char.deferredChains[-3],nil)
    end)
end
