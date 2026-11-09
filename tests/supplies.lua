return function(test,eq,F,A,plan)
local S=A.Supplies
local function state(free)
    local s=F.State();s.money=100;s.itemMetadata={[100]={stackSize=20,family=0,quality=1,sellPrice=0},[101]={stackSize=20,family=32},[900]={stackSize=10,family=0,quality=0,sellPrice=10}}
    s.inventory={bags={[0]={family=0,free=free or 0}},slots={}}
    s.freeSlots=free or 0;return s
end
local function services(quests)
    local d=F.Data(quests);d.content.sources={fixture={}}
    d.content.services={smith={verified=true,source="fixture",title="夹具服务点",node="near",repair={costMax=50,seconds=10},purchaseSeconds=8,stock={[100]={unitPrice=2,unlimited=true}},vendorSeconds=6}}
    return d
end
test("日志满时先交付再接新任务且已接任务不额外占槽",function()
    local s,q1,q2=state(16),F.Quest(1),F.Quest(2);s.questLimit=1
    s.quests[1]={ready=true,objectives={}};q1.xp=1;q2.xp=20000
    local d=services({[1]=q1,[2]=q2})
    eq(A.Planner.Evaluate(q2,s,d,{minutes=60},"start"),nil)
    local p=plan(s,d);eq(p.best.xp,20001);eq(p.best.actions[1].kind,"turnin")
    eq(p.best.resources.supplies.questCount,0);eq(s.quests[1].ready,true)
end)
test("专用包仅接收匹配物品且通用物品不能占草药包",function()
    local s=state(0);s.inventory.bags[1]={family=32,free=1}
    eq(S.Apply({gainItems={[100]=1}},S.Cursor(s),s.itemMetadata),nil)
    local after=S.Apply({gainItems={[101]=1}},S.Cursor(s),s.itemMetadata)
    eq(after.bags[101],1);eq(after.inventory.slots[1].bag,1);eq(s.inventory.bags[1].free,1)
end)
test("满包可补现有堆叠且优先使用匹配专用包",function()
    local s=state(0);s.bags[100]=10;s.inventory.slots={{id=100,count=10,bag=0}}
    local after=S.Apply({gainItems={[100]=10}},S.Cursor(s),s.itemMetadata);eq(after.bags[100],20)
    eq(S.Apply({gainItems={[100]=11}},S.Cursor(s),s.itemMetadata),nil)
    s=state(1);s.inventory.bags[1]={family=32,free=1}
    after=S.Apply({gainItems={[101]=1}},S.Cursor(s),s.itemMetadata);eq(after.inventory.bags[0].free,1)
end)
test("明确全量消耗释放空间，部分消耗不虚增空格",function()
    local s=state(0);s.bags[100]=10;s.inventory.slots={{id=100,count=10,bag=0}}
    local after=S.Apply({consumeItems={[100]=10},gainItems={[101]=1}},S.Cursor(s),s.itemMetadata)
    eq(after.bags[100],0);eq(after.bags[101],1)
    eq(S.Apply({consumeItems={[100]=5},gainItems={[101]=1}},S.Cursor(s),s.itemMetadata),nil)
end)
test("低耐久插入有来源维修并传播费用与耗时",function()
    local s,q=state(16),F.Quest(1);s.durability=0.1;q.combat=true
    local r=A.Planner.Evaluate(q,s,services({[1]=q}),{minutes=60},"start")
    eq(r.seconds,50);eq(r.resources.money,50);eq(r.resources.supplies.durability,1);eq(s.durability,0.1)
    local found=false
    for _,a in ipairs(r.actions) do if a.kind=="service" then found=true;eq(a.serviceKind,"repair");eq(a.serviceGoal.durability,0.2) end end
    eq(found,true)
end)
test("补给只购买有来源的足量库存并在使用后扣除",function()
    local s,q=state(16),F.Quest(1);q.actions[2].requiredItems={[100]=5};q.actions[2].consumeItems={[100]=5}
    local d=services({[1]=q});local r=A.Planner.Evaluate(q,s,d,{minutes=60},"start")
    eq(r.seconds,48);eq(r.resources.money,90);eq(r.resources.supplies.bags[100],0)
    d.content.services.smith.stock[100].unlimited=false
    local candidate,reason=A.Planner.Evaluate(q,s,d,{minutes=60},"start");eq(candidate,nil);assert(reason:find("必需物品"))
end)
test("买补给前空间不足先整理且不出售受保护物品",function()
    local s,q=state(0),F.Quest(1);s.bags[900]=2;s.inventory.slots={{id=900,count=2,bag=0,questKnown=true,questItem=false}}
    q.actions[2].requiredItems={[100]=1};q.actions[2].consumeItems={[100]=1}
    local d=services({[1]=q});local r=A.Planner.Evaluate(q,s,d,{minutes=60},"start")
    assert(r);eq(r.resources.money,118)
    local seen={};for _,a in ipairs(r.actions) do if a.kind=="service" then seen[#seen+1]=a.serviceKind end end
    eq(seen[1],"vendor");eq(seen[2],"supply")
    s.protectedItems={[900]=true};eq(A.Planner.Evaluate(q,s,d,{minutes=60},"start"),nil)
    s.protectedItems={};s.inventory.slots[1].questItem=true;eq(A.Planner.Evaluate(q,s,d,{minutes=60},"start"),nil)
end)
test("整理所得金币只能用于出售之后的交通",function()
    local s,q=state(0),F.Quest(1);s.money=0;s.bags[900]=2;s.inventory.slots={{id=900,count=2,bag=0,questKnown=true,questItem=false}}
    q.actions[2].gainItems={[100]=1}
    local d=services({[1]=q});d.content.transit={back={kind="flight",verified=true,from="goal",to="start",seconds=5,cost=20}}
    local r=A.Planner.Evaluate(q,s,d,{minutes=60},"start")
    eq(r.resources.money,0);eq(r.seconds,31)
    d.content.edges.start={};d.content.nodes.near.position.map=2;d.content.transit.go={kind="flight",verified=true,from="start",to="near",seconds=1,cost=1}
    eq(A.Planner.Evaluate(q,s,d,{minutes=60},"start"),nil)
end)
test("维修费用与交通共同计费且保留较便宜服务来源",function()
    local s,q=state(16),F.Quest(1);s.money=40;s.durability=0.1;q.combat=true
    local d=services({[1]=q});d.content.services.other={verified=true,source="fixture",title="远处维修",node="goal",repair={costMax=10,seconds=20}}
    local r=A.Planner.Evaluate(q,s,d,{minutes=60},"start")
    assert(r);eq(r.resources.money,30)
    local found;for _,a in ipairs(r.actions) do if a.kind=="service" then found=a.serviceId end end
    eq(found,"other")
    d.content.services.other.repair.costMax=nil;eq(A.Planner.Evaluate(q,s,d,{minutes=60},"start"),nil)
end)
test("未知堆叠数据保持阻断，预测消耗不修改真实物品",function()
    local s=state(1);s.itemMetadata[100].stackSize=nil
    local r,issue=S.Apply({gainItems={[100]=1}},S.Cursor(s),s.itemMetadata);eq(r,nil);eq(issue.kind,"metadata")
    s.bags[100]=5;s.inventory.slots={{id=100,count=5,bag=0}}
    local cursor=S.Apply({consumeItems={[100]=5}},S.Cursor(s),s.itemMetadata)
    eq(cursor.bags[100],0);eq(s.bags[100],5);eq(s.inventory.slots[1].count,5)
end)
test("服务动作等待实际数量或耐久变化才完成",function()
    local s=state(1);local action={kind="service",serviceGoal={items={[100]=5},durability=0.2}}
    eq(S.Done(action,s),false);s.bags[100]=5;s.durability=0.1;eq(S.Done(action,s),false)
    s.durability=1;eq(S.Done(action,s),true)
end)
test("金币不足时先出售已知灰色物品再支付服务费",function()
    local s,q=state(1),F.Quest(1);s.money=0;s.durability=0.1;q.combat=true
    s.bags[900]=2;s.inventory.slots={{id=900,count=2,bag=0,questKnown=true,questItem=false}}
    local d=services({[1]=q});d.content.services.smith.repair.costMax=20
    local r=A.Planner.Evaluate(q,s,d,{minutes=60},"start");assert(r);eq(r.resources.money,0)
    local kinds={};for _,a in ipairs(r.actions) do if a.kind=="service" then kinds[#kinds+1]=a.serviceKind end end
    eq(kinds[1],"vendor");eq(kinds[2],"repair")
end)
test("服务点阵营与解锁条件参与后续任务搜索",function()
    local s,q1,q2=state(16),F.Quest(1),F.Quest(2);s.faction="Alliance";s.durability=0.1
    q1.xp=1;q1.setup=true;q2.preQuestGroup={1};q2.xp=20000;q2.combat=true
    local d=services({[1]=q1,[2]=q2});d.content.services.smith.faction="Horde"
    eq(plan(s,d).best.xp,1)
    d.content.services.smith.faction="Alliance";d.content.services.smith.unlock="quest:1"
    eq(plan(s,d).best.xp,20001)
end)
test("未知维修费用先提供到店确认卡片且不预记任务经验",function()
    local s,q=state(16),F.Quest(1);s.durability=0.1;q.combat=true
    local d=services({[1]=q});d.content.services.smith.repair.costMax=nil
    local p=plan(s,d);eq(p.best.kind,"service");eq(p.best.xp,0);eq(p.maintenance,true)
    local last=p.best.actions[#p.best.actions];eq(last.serviceKind,"repair");eq(S.Done(last,s),false)
end)
test("副本出发补齐物品与耐久并保留内部消耗和返程资源",function()
    local s=state(16);s.durability=0.1;F.Party(s)
    local d=services({});local instance={id=1,instanceId=42,difficultyId=1,title="服务夹具副本",verified=true,minLevel=10,maxLevel=30,
        entryNode="goal",exitNode="goal",returnNode="start",runSeconds=600,xp=1000,waitSeconds=0,actions={},items={[100]=2},consumeItems={[100]=2},lootSlots=2,durabilityLoss=0.1}
    d.content.dungeons[1]=instance
    local r=A.Dungeon.Evaluate(instance,s,{minutes=60,role="DAMAGER",dungeons=true},d)
    assert(r);eq(r.resources.money,46);eq(r.resources.supplies.bags[100],0);eq(r.resources.supplies.durability,0.9)
    eq(r.resources.supplies.inventory.bags[0].free,14)
    local services=0;for _,a in ipairs(r.previewActions) do if a.kind=="service" then services=services+1;eq(a.stage,"before") end end
    eq(services,2)
end)
test("同目标但物品效果不同的行动分别保留库存变化",function()
    local s,q1,q2=state(2),F.Quest(1),F.Quest(2)
    for _,q in ipairs({q1,q2}) do
        local a=q.actions[2];a.shareKey="same";a.shareType="collect";a.targetId=33;a.workUnits=1;a.secondsPerUnit=10;a.gainItems={[100]=1}
    end
    local r=A.Planner.EvaluateMany({q1,q2},s,services({[1]=q1,[2]=q2}),{minutes=60},"start")
    eq(r.resources.supplies.bags[100],2)
end)
test("服务完成由实际状态推进且完成采样在重算前确认",function()
    local B={Supplies=S,char={samples={}},settings={learn=true},Navigation={},State=A.State,RequestRefresh=function() end}
    assert(loadfile("Observations.lua"))("AiLeveling",B)
    local action={kind="service",serviceId="smith",serviceKind="repair",referenceSeconds=10,serviceGoal={durability=0.2}}
    local o=B.Observations;o:Tick(0,action,true,true);for i=1,10 do o:Tick(i,action,true,true) end
    o:Refresh({durability=0.1});eq(B.char.samples.recovery,nil)
    o:Refresh({durability=1});eq(B.char.samples.recovery.n,1);eq(B.char.samples.recovery.mean,1)
    o:Refresh({durability=1});eq(B.char.samples.recovery.n,1)
end)
test("服务资源格式拒绝负数、无穷费用和空完成条件",function()
    eq(S.ValidAction({gainItems={[100]=-1}}),false)
    eq(S.ValidAction({moneyCost=math.huge}),false)
    eq(S.ValidAction({kind="service",serviceGoal={}}),false)
    eq(S.ValidAction({kind="service",serviceGoal={items={[100]=5}}}),true)
    local d=services({});local point=d.content.services.smith
    eq(S.ValidService(point,d.content),true);point.stock[100].unitPrice=-1;eq(S.ValidService(point,d.content),false)
end)

test("库存或价格未确认时导航到店核对而不计后续奖励",function()
    local s,q=state(16),F.Quest(1);q.actions[2].requiredItems={[100]=5}
    local d=services({[1]=q});d.content.services.smith.stock[100].unlimited=false
    local p=plan(s,d);eq(p.best.kind,"service");eq(p.best.xp,0)
    local action=p.best.actions[#p.best.actions];eq(action.serviceKind,"supply");eq(action.serviceGoal.items[100],5)
end)
test("服务导航不会以到达供应商代替实际购买完成",function()
    local oldTime,oldFacing=GetTime,GetPlayerFacing
    GetTime=function() return 100 end;GetPlayerFacing=function() return 0 end
    local s=state(16);s.position={node="start",map=1,x=0,y=0}
    local B={Supplies=S,state=s,char={},settings={pins=false},QuestAssist={Update=function() end},UI={SetNavigation=function() end},Replan=function() end}
    assert(loadfile("Navigation.lua"))("AiLeveling",B)
    local n=B.Navigation
    n.hbd={GetZoneDistance=function() return 0 end,GetWorldCoordinatesFromZone=function() return nil end}
    n.actions={{kind="service",node="start",position={map=1,x=0,y=0},serviceGoal={items={[100]=5}}}}
    n:Update();eq(n.index,1);s.bags[100]=5;n:Update();eq(n.index,2)
    GetTime,GetPlayerFacing=oldTime,oldFacing
end)
test("原生库存元数据保护任务物品并读取实际耐久",function()
    local names={"C_Item","C_Container","GetInventoryItemDurability"};local saved={}
    for _,name in ipairs(names) do saved[name]=_G[name] end
    C_Item={GetItemInfo=function(id) return "灰色物品",nil,0,1,1,nil,nil,10,nil,nil,10 end,GetItemFamily=function() return 0 end,RequestLoadItemDataByID=function() end}
    C_Container={GetContainerItemQuestInfo=function() return {isQuestItem=true} end}
    GetInventoryItemDurability=function(slot) if slot==16 then return 5,100 end end
    local s=state(0);s.bags[900]=2;s.bagEntries={{id=900,count=2,bag=0,slot=1}}
    local B={Navigation=F.Navigation,Content={items={},sources={},dungeons={}},requestedItems={},Data={GetQuest=function() return nil end}}
    assert(loadfile("Planner/Supplies.lua"))("AiLeveling",B)
    B.Supplies:Snapshot(s);eq(s.durability,0.05);eq(s.itemMetadata[900].stackSize,10);eq(s.inventory.slots[1].questItem,true)
    for _,name in ipairs(names) do _G[name]=saved[name] end
end)

test("副本准备行程可以先交付必要前置但不能借用副本内未来交付",function()
    local s,q=state(16),F.Quest(1);s.quests[1]={ready=true,objectives={}};F.Party(s)
    local d=services({[1]=q});local instance={id=1,instanceId=42,difficultyId=1,title="准备夹具",verified=true,minLevel=10,maxLevel=30,
        entryNode="goal",exitNode="goal",returnNode="start",runSeconds=600,xp=1000,waitSeconds=0,preQuests={1},
        actions={{stage="before",kind="turnin",questId=1,node="start",seconds=5}}}
    assert(A.Dungeon.Evaluate(instance,s,{minutes=60,role="DAMAGER",dungeons=true},d))
    instance.actions[1].stage="inside";eq(A.Dungeon.Evaluate(instance,s,{minutes=60,role="DAMAGER",dungeons=true},d),nil)
end)
test("已实际完成的准备服务不阻塞等队活动",function()
    local s,q=state(16),F.Quest(1);s.bags[100]=2;q.interruptible=true
    local d=services({[1]=q});local instance={id=1,instanceId=42,difficultyId=1,title="准备服务夹具",verified=true,minLevel=10,maxLevel=30,
        entryNode="goal",exitNode="goal",returnNode="start",runSeconds=600,xp=1000,waitSeconds=300,interruptibleQuestIds={1},
        actions={{stage="before",kind="service",node="start",seconds=5,serviceGoal={items={[100]=2}},gainItems={[100]=2}}}}
    local r=A.Dungeon.Evaluate(instance,s,{minutes=60,role="DAMAGER",dungeons=true},d);assert(r);eq(r.waitActivity.questId,1)
end)

test("副本实际准备先维修，等待活动消耗后再按实际数量补给",function()
    local s,q=state(16),F.Quest(1);s.bags[100]=2;s.inventory.slots={{id=100,count=2,bag=0}}
    s.durability=0.1;q.interruptible=true;q.actions[2].consumeItems={[100]=1}
    local data=services({[1]=q});local instance={id=1,instanceId=42,difficultyId=1,title="等队准备夹具",verified=true,minLevel=10,maxLevel=30,
        entryNode="goal",exitNode="goal",returnNode="start",runSeconds=600,xp=1000,waitSeconds=300,
        items={[100]=2},interruptibleQuestIds={1},actions={{stage="after",kind="turnin",questId=1,node="start",seconds=5}},questXP={[1]=1000}}
    data.content.dungeons[1]=instance
    local B={Navigation=F.Navigation,Content=data.content,Data=data,state=s,char={samples={}},settings={dungeons=true,minutes=60,mode="fast",role="DAMAGER"},RequestRefresh=function() end}
    for _,file in ipairs({"State.lua","Planner/Eligibility.lua","Planner/Travel.lua","Planner/Gear.lua","Planner/Progression.lua","Planner/Supplies.lua","Planner/Dungeon.lua","Planner/Planner.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    B.State.Refresh=function() B.Dungeon:Sync(s,{}) end
    eq(B.Dungeon:Accept(1),true)
    local p=plan(s,data,B.settings,B);local repair
    for _,a in ipairs(p.best.actions) do if a.serviceKind=="repair" then repair=a end end
    assert(repair);eq(repair.stage,"before")
    s.durability=1;B.Dungeon:Sync(s,{});p=plan(s,data,B.settings,B);eq(p.waitingDungeon,1)
    s.completed[1]=true;s.bags[100]=1;s.inventory.slots[1].count=1
    B.Dungeon:Sync(s,{});p=plan(s,data,B.settings,B)
    local supply;for _,a in ipairs(p.best.actions) do if a.serviceKind=="supply" then supply=a end end
    assert(supply);eq(supply.serviceGoal.items[100],2)
end)
test("未接取的可选副本交付不预记奖励或阻止进入",function()
    local s,q=state(16),F.Quest(1);F.Party(s)
    local d=services({[1]=q});local instance={id=1,instanceId=42,difficultyId=1,title="可选交付夹具",verified=true,minLevel=10,maxLevel=30,
        entryNode="goal",exitNode="goal",returnNode="start",runSeconds=600,xp=1000,waitSeconds=0,
        actions={{stage="after",kind="turnin",questId=1,node="start",seconds=5}},questXP={[1]=5000}}
    local r=A.Dungeon.Evaluate(instance,s,{minutes=60,role="DAMAGER",dungeons=true},d);assert(r);eq(r.xp,1000)
    for _,a in ipairs(r.previewActions) do assert(a.kind~="turnin") end
end)

end
