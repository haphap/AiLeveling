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
        q.startedBy={[3]={900}}
        local desired=A.QuestAssist.Desired({kind="accept",questId=1},s,true,data)
        eq(desired[1],900)
    end)
    test("超过四件任务物品可翻页且旧页越界时恢复有效页",function()
        local items={1,2,3,4,5,6}
        local page,index,pages=A.QuestAssist.Page(items,2)
        eq(#page,2);eq(page[1],5);eq(index,2);eq(pages,2)
        page,index=A.QuestAssist.Page({9},2);eq(index,1);eq(page[1],9)
    end)
    test("配置边界恢复损坏值且保留有效偏好",function()
        local s={mode="custom",role="HEALER",scale=0/0,alpha=5,minutes=90,waitMinutes=-1,position={"invalid","CENTER",0,0}}
        C:NormalizeSettings(s)
        eq(s.mode,"relaxed");eq(s.role,"HEALER");eq(s.scale,1);eq(s.alpha,0.94)
        eq(s.minutes,90);eq(s.waitMinutes,10);eq(s.position,nil)
    end)
    test("恢复设置保留角色事实、暂缓与副本选择",function()
        C.settings={mode="story",scale=1.3,position={"CENTER","CENTER",1,2}}
        C.char={skipped={[1]=true},samples={},dungeon={id=42}}
        C.state={completed={[7]=true}}
        C.UI={frame={ClearAllPoints=function() end,SetPoint=function() end},ApplyStyle=function() end,Settings={Refresh=function() end}}
        C.Observations={Reset=function() end};C.Navigation={RefreshPins=function() end};C.State={Refresh=function() end}
        C.Transport={InvalidateSample=function() end}
        C:RestoreSettings()
        eq(C.settings.mode,"relaxed");eq(C.settings.position,nil)
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
