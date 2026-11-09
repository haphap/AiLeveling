return function(test,eq,F,A,plan)
local function item(id,strength)
    return {id=id,name="奖励 "..id,equipLoc="INVTYPE_HEAD",usable=true,stats={ITEM_MOD_STRENGTH_SHORT=strength}}
end
local function fixture()
    local B={};for k,v in pairs(A) do B[k]=v end
    for _,file in ipairs({"Planner/Gear.lua","Planner/TaskGuide.lua","Planner/TaskQueue.lua","Planner/Planner.lua","Planner/Selection.lua"}) do
        assert(loadfile(file))("AiLeveling",B)
    end
    local quests={}
    for id=1,3 do
        local q=F.Quest(id);q.verified=false;q.questLevel=20
        q.taskFacts={level=20,xp={{1,1000}},rewards={items={},choices={}}};quests[id]=q
    end
    quests[2].taskFacts.rewards.choices={{id=100,count=1},{id=101,count=1}}
    local s,d=F.State(),F.Data(quests);d.content.gearSources={};s.items={[100]=item(100,5),[101]=item(101,8)}
    s.equipment[1]=item(99,1)
    d.Target=function(_,q) return {map=1,x=q.id==1 and 0.5 or 0.52,y=0} end
    d.ReferenceObjectiveTargets=function(_,q) return {{text="目标"}},{d:Target(q)},false end
    d.ObjectiveTargets=function(_,q) local p=d:Target(q);p.objectiveIndex=1;return {p} end
    d.chainIndex=B.Chains.NewIndex();for _,q in pairs(quests) do B.Chains.IndexQuest(d.chainIndex,q,d) end
    B.Data,B.Content,B.state,B.char,B.ready=d,d.content,s,{turnIns={},skipped={}},true
    B.State={};for k,v in pairs(A.State) do B.State[k]=v end
    B.State.Refresh=function() s.gearTarget=B.char.gearTarget end
    B.Navigation={};for k,v in pairs(F.Navigation) do B.Navigation[k]=v end
    return B,s,d,quests
end
local function find(p,id) for _,c in ipairs(p.taskChoices) do if c.questId==id then return c end end end
local balanced={minutes=60,mode="relaxed",gearPreference="balanced",dungeons=false,role="DAMAGER"}

test("同构建首领掉落进入比较与手选导航，击败不当作拿到装备且版本失配保留选择",function()
    local B,s,d=fixture()
    for _,file in ipairs({"Data/Dungeons.lua","Planner/Dungeon.lua","Planner/DungeonTasks.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    s.clientVersion,s.clientBuild="1.60.1","70862"
    local id="drop:2732:272998"
    local source=B.Gear.GetSource(id,d)
    assert(source and source.reference);eq(source.instanceId,389);eq(source.kind,"dungeon")
    local count=0;for _ in pairs(B.Gear.DungeonSources(s)) do count=count+1 end;eq(count,11)
    s.items[source.itemId]=item(source.itemId,8)
    local value=B.Gear.Source(source,s,d.content,d)
    eq(value.upgrade.delta,7);eq(value.chanceLow,0);eq(value.chanceHigh,1);eq(value.expectedAttemptsHigh,nil)
    local candidate={dungeonId=source.dungeonId}
    B.Gear.Benefits({candidate},s,d.content);assert(candidate.gearSources[id]);eq(candidate.gear.chanceLow,0)
    local fake={};for key,v in pairs(source) do fake[key]=v end
    fake.encounterId=2733;eq(B.Gear.Source(fake,s,d.content,d),nil)
    local dungeon=B.DungeonCatalog.entries[source.dungeonId]
    eq(#B.Gear.DungeonBenefits(dungeon,s,d),1)
    d.maps={};for _,area in ipairs(dungeon.areas) do d.maps[area]=2 end
    for _,entry in ipairs(dungeon.entrances) do d.maps[entry[1]]=1 end
    eq(B.Gear:SetTarget(id),true);eq(B.char.gearTarget,id)
    local p=plan(s,d,balanced,B)
    assert(p.gearPlan);eq(p.best,nil);eq(p.fallback.kind,"dungeonEnter");eq(p.fallback.questId,nil)
    eq(p.fallback.position.map,1);assert(p.fallback.text:find("奥格弗林特",1,true))
    s.instanceEntryError="等级不足";eq(plan(s,d,balanced,B).fallback.kind,"dungeonBlocked");s.instanceEntryError=nil
    s.inInstance,s.instanceId=true,389
    p=plan(s,d,balanced,B);eq(p.fallback.kind,"dungeonRun");assert(p.fallback.text:find("拾取",1,true))
    B.Dungeon.encounterVisit={instanceId=389,difficulty=1,kills={[2732]="奥格弗林特"}}
    p=plan(s,d,balanced,B);assert(p.fallback.text:find("已击败",1,true))
    B.Gear:SyncTarget(s);eq(s.gearTarget,id);eq(s.gearAcquired,nil)
    B.plan=p;B.UI={};assert(loadfile("UI/Gear.lua"))("AiLeveling",B)
    local ui=B.UI.Gear;ui.selected=id
    ui.selector={text={SetText=function() end},SetEnabled=function() end};ui.choose={SetEnabled=function() end}
    local lines=table.concat(ui:Lines(),"\n")
    assert(lines:find("获得概率区间 0%—100%",1,true));assert(not lines:find("交付任务",1,true));assert(not lines:find("预计刷取",1,true))
    assert(loadfile("UI/Dungeon.lua"))("AiLeveling",B)
    B.UI.Dungeon.entries={[dungeon.id]=dungeon};B.UI.Dungeon.selected=dungeon.id;B.UI.Dungeon.tasks={}
    lines=table.concat(B.UI.Dungeon:Lines(),"\n");assert(lines:find("副本装备提升",1,true))
    s.clientBuild="other";eq(B.Gear.GetSource(id,d),nil);eq(B.Gear.Source(source,s,d.content,d),nil)
    p=plan(s,d,balanced,B);eq(p.fallback.kind,"selectionBlocked");eq(s.gearTarget,id)
    s.clientBuild="70862";s.bags[source.itemId]=1;B.Gear:SyncTarget(s)
    eq(s.gearTarget,nil);eq(s.gearAcquired,source.itemId)
    eq(B.Gear:SetTarget(id),false)
    eq(next(s.completed),nil)
end)

test("真实任务奖励解析来源身份并按互斥奖励分别比较而不相加",function()
    local B,s,d,q=fixture()
    local source=B.Gear.GetSource("reward:2:101",d);assert(source.reference);eq(source.verified,nil);eq(source.choice,true)
    eq(B.Gear.GetSource("reward:2:999",d),nil);eq(B.Gear.GetSource("reward:999:101",d),nil)
    eq(B.Gear.GetSource("reward:02:101",d),nil)
    local p=plan(s,d,balanced,B);local c=find(p,2)
    eq(c.gear.upgrade.delta,7);eq(c.gearSources["reward:2:100"].upgrade.delta,4)
    eq(c.gearSources["reward:2:101"].upgrade.delta,7);eq(c.remainingXP,1000)
    eq(next(d.content.gearSources or {}),nil)
    local fake={id="reward:2:101",reference=true,kind="quest",questId=1,itemId=101}
    eq(B.Gear.Source(fake,s,d.content,d),nil)
    q[2].questLevel=21;eq(B.Gear.GetSource("reward:2:101",d),nil)
end)

test("装备偏好只在接近最高移动收益的未接任务间生效且不挤掉已接整组",function()
    local B,s,d,q=fixture()
    local p=plan(s,d,balanced,B);eq(p.fallback.questId,2);assert(p.preferenceApplied)
    eq(plan(s,d,{minutes=60,mode="fast",gearPreference="balanced"},B).fallback.questId,1)
    eq(plan(s,d,{minutes=60,mode="relaxed",gearPreference="xp"},B).fallback.questId,1)
    q[2].taskFacts.xp={{1,900}};eq(plan(s,d,balanced,B).fallback.questId,1)
    q[2].taskFacts.xp={{1,1000}};s.items[101]=item(101,0);s.items[100]=item(100,0)
    eq(plan(s,d,balanced,B).fallback.questId,1)
    s.items[101]=item(101,8);s.quests[1]={ready=true,objectives={}}
    p=plan(s,d,balanced,B);eq(p.fallback.questId,1);eq(p.fallback.kind,"turnin")
    s.quests[1]={objectives={{text="未完成",numRequired=1,numFulfilled=0}}}
    eq(plan(s,d,balanced,B).fallback.questId,1)
end)

test("奖励缓存未知武器资料及特殊效果不驱动自动切换",function()
    local B,s,d=fixture();s.items[100].pending=true;s.items[101].pending=true
    local p=plan(s,d,balanced,B);eq(p.fallback.questId,1);eq(find(p,2).gear,nil)
    s.items[101].pending=nil;s.items[101].equipLoc="INVTYPE_WEAPON"
    p=plan(s,d,balanced,B);eq(p.fallback.questId,1);assert(find(p,2).gearSources["reward:2:101"].upgrade.provisional)
    s.items[101].equipLoc="INVTYPE_HEAD";s.items[101].useSpell=42
    p=plan(s,d,balanced,B);eq(p.fallback.questId,1);assert(find(p,2).gearSources["reward:2:101"])
    s.items[101].usable=false;p=plan(s,d,balanced,B);eq(find(p,2).gearSources["reward:2:101"],nil)
end)

test("手选任务奖励接续前置及任务并在实际获得或交付其他奖励后解除",function()
    local B,s,d,q=fixture();q[2].preQuestGroup={3}
    B.Chains.IndexQuest(d.chainIndex,q[2],d)
    eq(B.Gear:SetTarget("reward:2:101"),true);eq(B.char.gearTarget,"reward:2:101");eq(B.char.locked,nil)
    local p=plan(s,d,nil,B);eq(p.fallback.questId,3);eq(p.preparingQuest.id,2)
    s.quests[3]={ready=true,objectives={}};eq(plan(s,d,nil,B).fallback.questId,3)
    s.quests[3]=nil;s.completed[3]=true;p=plan(s,d,nil,B);eq(p.fallback.questId,2)
    s.quests[2]={objectives={{numRequired=1,numFulfilled=0,text="目标"}}}
    p=plan(s,d,nil,B);eq(p.fallback.kind,"objective");eq(p.fallback.questId,2)
    B.Gear:SyncTarget(s);eq(s.gearTarget,"reward:2:101")
    s.bags[101]=1;B.Gear:SyncTarget(s);eq(s.gearTarget,nil);eq(s.gearAcquired,101)
    s.bags[101]=nil;s.gearAcquired=nil;eq(B.Gear:SetTarget("reward:2:101"),true)
    s.quests[2]=nil;s.completed[2]=true;B.Gear:SyncTarget(s);eq(s.gearTarget,nil);eq(s.gearAcquired,nil)
    eq(B.Gear:SetTarget("reward:2:101"),false)
end)

test("装备目标暂缓和缺前置阻断保留用户选择且不回落其他任务",function()
    local B,s,d,q=fixture();eq(B.Gear:SetTarget("reward:2:101"),true)
    q[2].requiredLevel=99
    local p=plan(s,d,nil,B);eq(p.fallback.kind,"selectionBlocked");eq(s.gearTarget,"reward:2:101")
    q[2].requiredLevel=1;B.Selection:Skip(2);eq(B.char.gearTarget,nil)
    s.skipped[2]=true;eq(B.Gear:SetTarget("reward:2:101"),false)
end)

test("装备页从当前真实奖励提供选择并在任务详情显示装备提升",function()
    local B,s,d=fixture();B.plan=plan(s,d,balanced,B);B.UI={};B.Navigation.Current=function() end
    assert(loadfile("UI/Main.lua"))("AiLeveling",B)
    assert(loadfile("UI/Gear.lua"))("AiLeveling",B)
    assert(loadfile("UI/Plan.lua"))("AiLeveling",B)
    local gear=B.UI.Gear
    gear.selector={text={SetText=function(_,v) gear.title=v end},SetEnabled=function() end}
    gear.choose={SetEnabled=function(_,v) gear.enabled=v end}
    local ids=gear:Ids();eq(#ids,2);gear.selected="reward:2:101"
    local lines=table.concat(gear:Lines(),"\n");assert(gear.enabled);assert(lines:find("交付任务时选择此奖励",1,true))
    assert(not lines:find("获得概率区间",1,true));assert(not lines:find("分钟",1,true))
    B.UI.Plan.preview=find(B.plan,2)
    lines=table.concat(B.UI.Plan:Lines(),"\n");assert(lines:find("属性评分提升 +7.0",1,true))
    eq(B.Gear:SetTarget(gear.selected),true);B.plan={taskChoices={}}
    eq(#gear:Ids(),1);gear:Lines();eq(gear.selected,"reward:2:101")
end)
test("远处低价值奖励任务退出整组而有效装备和手选目标保留",function()
    local B,s,d,q=fixture()
    q[2].questLevel=17;q[2].taskFacts.level=17
    s.items[100]=item(100,0);s.items[101]=item(101,0)
    s.quests[1]={ready=true,objectives={}}
    s.quests[2]={objectives={{text="远处目标",numRequired=1,numFulfilled=0}}}
    d.Target=function(_,quest,state)
        return {map=1,x=quest.id==2 and state.quests[2] and not state.quests[2].ready and 2 or 0,y=0,entityKind="npc",entityId=9}
    end
    d.ObjectiveTargets=function() return {{map=1,x=2,y=0,objectiveIndex=1}} end
    local p=plan(s,d,balanced,B);assert(find(p,2).lowValue.distant);eq(p.fallback.questId,1)
    eq(#B.TaskGuide.DeliveryGroups(p.taskChoices,s),0);eq(s.skipped[2],nil)
    s.items[101]=item(101,8);p=plan(s,d,balanced,B)
    eq(find(p,2).lowValue,nil);eq(p.fallback.questId,2);eq(#B.TaskGuide.DeliveryGroups(p.taskChoices,s),1)
    eq(B.Gear:SetTarget("reward:2:101"),true);s.items[101]=item(101,0)
    eq(B.TaskGuide.LowValue(q[2],s,d,{timing={seconds=400}}),nil)
    q[2].taskFacts=nil;p=plan(s,d,balanced,B)
    eq(p.fallback.kind,"selectionBlocked");eq(s.gearTarget,"reward:2:101")
end)

test("奖励物品延迟加载合并请求且选定来源加入状态快照",function()
    local B,s,d=fixture();B.requestedItems={};B.Content.items={};B.Content.sources={}
    assert(loadfile("Items.lua"))("AiLeveling",B)
    local oldItem,oldPlayer=C_Item,C_PlayerInfo
    local calls,loaded=0,false
    C_Item={GetItemInfo=function(id)
        if loaded then return "奖励",tostring(id),1,20,1,nil,nil,1,"INVTYPE_HEAD" end
    end,GetItemStats=function() return {ITEM_MOD_STRENGTH_SHORT=8} end,
        RequestLoadItemDataByID=function() calls=calls+1 end}
    C_PlayerInfo={CanUseItem=function() return true end}
    s.items={};s.equipment={}
    local source=B.Gear.GetSource("reward:2:101",d)
    eq(B.Gear.Source(source,s,d.content,d),nil);eq(B.Gear.Source(source,s,d.content,d),nil);eq(calls,1)
    loaded=true;B.requestedItems[101]=nil
    assert(B.Gear.Source(source,s,d.content,d).upgrade.delta>0)
    B.char.gearTarget=source.id;B.Items:Snapshot(s);eq(s.items[101].pending,false)
    C_Item,C_PlayerInfo=oldItem,oldPlayer
end)
test("换下装备的特殊效果保留详情但不触发自动绕路且可手选",function()
    local B,s,d,q=fixture();s.equipment[1].useSpell=42
    local p=plan(s,d,balanced,B);eq(p.fallback.questId,1);eq(find(p,2).gear,nil)
    local source=find(p,2).gearSources["reward:2:101"];assert(source)
    assert(table.concat(source.upgrade.notes,"\n"):find("失去：主动效果 #42",1,true))
    eq(B.Gear:SetTarget("reward:2:101"),true);eq(plan(s,d,balanced,B).fallback.questId,2)
    B.char.gearTarget=nil;s.gearTarget=nil
    q[2].questLevel=17;q[2].taskFacts.level=17;s.items[100]=item(100,0);s.items[101]=item(101,0)
    eq(B.TaskGuide.LowValue(q[2],s,d,{timing={seconds=400}}),nil)
    s.equipment[1].useSpell=nil;assert(B.TaskGuide.LowValue(q[2],s,d,{timing={seconds=400}}).distant)
end)
test("低属性套装奖励保留效果比较与手动任务接续，不自动当作提升",function()
    local B,s,d,q=fixture();assert(loadfile("Data/ItemSets.lua"))("AiLeveling",B)
    local function piece(id,slot,strength)
        local sid=B.ItemSets.items[id]
        return {id=id,name="套装候选",usable=true,equipLoc=slot,stats={ITEM_MOD_STRENGTH_SHORT=strength},
            setId=sid,setInfo=sid and B.ItemSets.sets[sid]}
    end
    s.equipment={[5]=piece(999,"INVTYPE_CHEST",5),[10]=piece(10401,"INVTYPE_HAND",1)}
    s.items={[10399]=piece(10399,"INVTYPE_CHEST",2)}
    q[2].taskFacts.rewards.choices={{id=10399,count=1}}
    local p=plan(s,d,balanced,B);local c=find(p,2);local id="reward:2:10399"
    assert(c.gearSources[id]);eq(c.gearSources[id].upgrade.delta,-3);eq(c.gear,nil);eq(p.fallback.questId,1)
    assert(table.concat(c.gearSources[id].upgrade.notes,"\n"):find("获得 2 件套效果",1,true))
    B.plan=p;B.UI={};B.Navigation.Current=function() end
    for _,file in ipairs({"UI/Main.lua","UI/Gear.lua","UI/Plan.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    local gear=B.UI.Gear;gear.selector={text={SetText=function() end},SetEnabled=function() end}
    gear.choose={SetEnabled=function() end};gear.selected=id
    s.bagEquipment={s.items[10399]}
    local lines=table.concat(gear:Lines(),"\n")
    assert(lines:find("属性评分变化 -3.0",1,true));assert(lines:find("获得 2 件套效果",1,true))
    eq(#gear:Ids(),1)
    B.UI.Plan.preview=c;lines=table.concat(B.UI.Plan:Lines(),"\n")
    assert(lines:find("属性评分变化 -3.0",1,true));assert(lines:find("获得 2 件套效果",1,true))
    eq(B.Gear:SetTarget(id),true);eq(plan(s,d,balanced,B).fallback.questId,2)
    s.bags[10399]=1;B.Gear:SyncTarget(s);eq(s.gearTarget,nil);eq(s.gearAcquired,10399)
    s.bags[10399]=nil;s.equipment[10]=nil
    eq(B.Gear:SetTarget(id),false);eq(find(plan(s,d,balanced,B),2).gearSources[id],nil)
end)

test("自有装备来源保留负属性效果权衡，仅手选时切换",function()
    local B,s,d=fixture();local source={id="test",verified=true,kind="quest",questId=2,itemId=100}
    d.content.gearSources={test=source};s.items[100].stats.ITEM_MOD_STRENGTH_SHORT=0;s.items[100].useSpell=42
    local base={actions={},rate=10};local candidate={actions={{kind="turnin",questId=2}},rate=10}
    B.Gear.Benefits({base,candidate},s,d.content)
    assert(candidate.gearSources.test);eq(candidate.gear,nil)
    eq(B.Gear.Prefer({base,candidate},base,s,balanced),base)
    eq(B.Gear:SetTarget("test"),true)
    eq(B.Gear.Prefer({base,candidate},base,s,balanced),candidate)
end)

test("原生装备提示按链接读取主动及命中效果并列出换装得失",function()
    local B,s,d=fixture();B.requestedItems={};B.Content.items={};B.Content.sources={}
    assert(loadfile("Items.lua"))("AiLeveling",B)
    local oldItem,oldPlayer,oldTooltip,oldEnum=C_Item,C_PlayerInfo,C_TooltipInfo,Enum
    local loc,calls="INVTYPE_HEAD",{}
    C_Item={GetItemInfo=function(link) return "原生装备",link,2,20,1,nil,nil,1,loc end,
        GetItemStats=function() return {ITEM_MOD_STRENGTH_SHORT=8} end,
        GetItemSpell=function() return "主动",42 end}
    C_PlayerInfo={CanUseItem=function() return true end}
    Enum={TooltipDataLineType={ItemSpellTriggerOnUse=144,ItemSpellTriggerOnProc=146,ItemSpellTriggerOnEquip=145}}
    C_TooltipInfo={GetHyperlink=function(link)
        calls[#calls+1]=link
        return {dataInstanceID=99,lines={{type=0,leftText="普通属性"},{type=145,leftText="装备：增加力量"},
            {type=144,leftText="使用：恢复生命"},{type=146,leftText="命中时：造成额外伤害"}}}
    end}
    local old=B.Items:Read(99,"item:99:123");local new=B.Items:Read(100,"item:100:456")
    eq(calls[1],"item:99:123");eq(calls[2],"item:100:456");eq(#new.effects,3);eq(B.Items.tooltipData[99],true)
    eq(new.effects[2].kind,"proc");eq(new.effects[2].text,"命中时：造成额外伤害")
    s.equipment[1]=old;local r=B.Gear.Upgrade(new,s);eq(#r.notes,6)
    local notes=table.concat(r.notes,"\n");assert(notes:find("失去：",1,true));assert(notes:find("获得：",1,true))
    assert(not notes:find("#42",1,true));assert(not notes:find("普通属性",1,true))
    loc="";B.Items:Read(101,"item:101");eq(#calls,2)
    C_Item,C_PlayerInfo,C_TooltipInfo,Enum=oldItem,oldPlayer,oldTooltip,oldEnum
end)
test("装备效果延迟或接口异常保留未知，重新读取成功后恢复",function()
    local B,s,d=fixture();B.requestedItems={};B.Content.items={};B.Content.sources={}
    assert(loadfile("Items.lua"))("AiLeveling",B)
    local oldItem,oldPlayer,oldTooltip,oldEnum=C_Item,C_PlayerInfo,C_TooltipInfo,Enum
    C_Item={GetItemInfo=function(link) return "奖励",link,2,20,1,nil,nil,1,"INVTYPE_HEAD" end,
        GetItemStats=function() return {ITEM_MOD_STRENGTH_SHORT=8} end}
    C_PlayerInfo={CanUseItem=function() return true end}
    Enum={TooltipDataLineType={ItemSpellTriggerOnUse=144,ItemSpellTriggerOnProc=146}}
    C_TooltipInfo={GetHyperlink=function() end}
    local candidate=B.Items:Read(101,"item:101");eq(candidate.pending,false);assert(candidate.effectsPending)
    s.items[100]=item(100,0);s.items[101]=candidate
    local p=plan(s,d,balanced,B);eq(p.fallback.questId,1);eq(find(p,2).gear,nil)
    C_TooltipInfo.GetHyperlink=function() error("资料尚未就绪") end
    assert(B.Items:Read(101,"item:101").effectsPending)
    C_TooltipInfo.GetHyperlink=function() return {dataInstanceID=55,lines={}} end
    assert(B.Items:Read(101,"item:101").effectsPending);eq(B.Items.tooltipData[55],true)
    C_TooltipInfo.GetHyperlink=function() return {lines={false}} end
    assert(B.Items:Read(101,"item:101").effectsPending)
    C_TooltipInfo.GetHyperlink=function() return {lines={{type=0,leftText="奖励"}}} end
    s.items[101]=B.Items:Read(101,"item:101");eq(s.items[101].effectsPending,nil)
    eq(plan(s,d,balanced,B).fallback.questId,2)
    C_TooltipInfo.GetHyperlink=function() return {lines={{type=146}}} end
    candidate=B.Items:Read(101,"item:101");eq(candidate.effects[1].text,"命中触发效果")
    C_TooltipInfo=nil;eq(B.Items:Read(101,"item:101").pending,false)
    s.equipment={};s.bagEntries={};B.Items:Snapshot(s);eq(next(B.Items.tooltipData),nil)
    C_Item,C_PlayerInfo,C_TooltipInfo,Enum=oldItem,oldPlayer,oldTooltip,oldEnum
end)

end
