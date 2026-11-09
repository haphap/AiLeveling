return function(test,eq,F,A,plan)
local S=A.Supplies
local function state(free)
    local s=F.State();s.money=100;s.itemMetadata={[100]={stackSize=20,family=0,quality=1,sellPrice=0},[101]={stackSize=20,family=32},[900]={stackSize=10,family=0,quality=0,sellPrice=10}}
    s.inventory={bags={[0]={family=0,free=free or 0}},slots={}}
    s.freeSlots=free or 0;return s
end
local function services(quests)
    local d=F.Data(quests);d.content.sources={fixture={}}
    d.content.services={smith={verified=true,source="fixture",title="夹具服务点",node="near",repair={seconds=10},purchaseSeconds=8,stock={[100]={}},vendorSeconds=6}}
    return d
end

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

test("未知堆叠数据保持阻断，预测消耗不修改真实物品",function()
    local s=state(1);s.itemMetadata[100].stackSize=nil
    local r,issue=S.Apply({gainItems={[100]=1}},S.Cursor(s),s.itemMetadata);eq(r,nil);eq(issue.kind,"metadata")
    s.bags[100]=5;s.inventory.slots={{id=100,count=5,bag=0}}
    local cursor=S.Apply({consumeItems={[100]=5}},S.Cursor(s),s.itemMetadata)
    eq(cursor.bags[100],0);eq(s.bags[100],5);eq(s.inventory.slots[1].count,5)
end)

test("副本出发补齐物品与耐久并保留内部消耗和返程资源",function()
    local s=state(16);s.durability=0.1;F.Party(s)
    local d=services({});local instance={id=1,instanceId=42,difficultyId=1,title="服务夹具副本",verified=true,minLevel=10,maxLevel=30,
        entryNode="goal",exitNode="goal",returnNode="start",runSeconds=600,xp=1000,waitSeconds=0,actions={},items={[100]=2},consumeItems={[100]=2},lootSlots=2,durabilityLoss=0.1}
    d.content.dungeons[1]=instance
    local r=A.Dungeon.Evaluate(instance,s,{minutes=60,role="DAMAGER",dungeons=true},d)
    assert(r);eq(r.resources.supplies.bags[100],0);eq(r.resources.supplies.durability,0.9)
    eq(r.resources.supplies.inventory.bags[0].free,14)
    local services=0;for _,a in ipairs(r.previewActions) do if a.kind=="service" then services=services+1;eq(a.stage,"before") end end
    eq(services,2)
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
test("服务资源格式拒绝负数物品与空完成条件",function()
    eq(S.ValidAction({gainItems={[100]=-1}}),false)
    eq(S.ValidAction({kind="service",serviceGoal={}}),false)
    eq(S.ValidAction({kind="service",serviceGoal={items={[100]=5}}}),true)
    local d=services({});local point=d.content.services.smith
    eq(S.ValidService(point,d.content),true);point.purchaseSeconds=-1;eq(S.ValidService(point,d.content),false)
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
    local B={Navigation=F.Navigation,Content={items={},sources={},dungeons={}},char={ignoreRepair=true},requestedItems={},Data={GetQuest=function() return nil end}}
    assert(loadfile("Planner/Supplies.lua"))("AiLeveling",B)
    B.Supplies:Snapshot(s);eq(s.durability,0.05);eq(s.itemMetadata[900].stackSize,10);eq(s.inventory.slots[1].questItem,true)
    eq(s.ignoreRepair,true);eq(B.char.ignoreRepair,true)
    local nextState=state(0);local before=B.Supplies:Snapshot(nextState);eq(nextState.ignoreRepair,true)
    GetInventoryItemDurability=function() end
    B.Supplies:Snapshot(nextState);eq(nextState.ignoreRepair,true);eq(B.char.ignoreRepair,true)
    GetInventoryItemDurability=function(slot) if slot==16 then return 100,100 end end
    local after=B.Supplies:Snapshot(nextState);assert(before~=after);eq(B.char.ignoreRepair,nil);eq(nextState.ignoreRepair,false)
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

test("未接取的可选副本交付不预记奖励或阻止进入",function()
    local s,q=state(16),F.Quest(1);F.Party(s)
    local d=services({[1]=q});local instance={id=1,instanceId=42,difficultyId=1,title="可选交付夹具",verified=true,minLevel=10,maxLevel=30,
        entryNode="goal",exitNode="goal",returnNode="start",runSeconds=600,xp=1000,waitSeconds=0,
        actions={{stage="after",kind="turnin",questId=1,node="start",seconds=5}},questXP={[1]=5000}}
    local r=A.Dungeon.Evaluate(instance,s,{minutes=60,role="DAMAGER",dungeons=true},d);assert(r);eq(r.xp,1000)
    for _,a in ipairs(r.previewActions) do assert(a.kind~="turnin") end
end)

end
