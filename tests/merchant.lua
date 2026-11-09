return function(test,eq,F,A,plan)
local names={"UnitGUID","UnitName","CanMerchantRepair","GetRepairAllCost","GetMerchantNumItems","GetMerchantItemLink","C_MerchantFrame","canaccessvalue",
    "BuyMerchantItem","RepairAllItems","UseContainerItem","SetMerchantFilter"}
local function setup()
    local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
    local B={};for k,v in pairs(A) do B[k]=v end
    assert(loadfile("Merchant.lua"))("AiLeveling",B)
    assert(loadfile("Planner/Supplies.lua"))("AiLeveling",B)
    assert(loadfile("Planner/Planner.lua"))("AiLeveling",B)
    B.Navigation={Distance=function() return 0 end};B.Roads=nil;B.TaskGuide=nil
    local env={guid="Creature-0-1-2-3-78-000001",repair=true,cost=27,rows={
        {id=100,name="补给",price=12,stackCount=5,numAvailable=-1,isPurchasable=true,hasExtendedCost=false}}}
    UnitGUID=function(unit) eq(unit,"npc");return env.guid end
    UnitName=function() return "当前商人" end
    CanMerchantRepair=function() return env.repair end
    GetRepairAllCost=function() return env.cost,env.cost~=0 end
    GetMerchantNumItems=function() return #env.rows end
    GetMerchantItemLink=function(i) return env.rows[i].id and ("item:"..env.rows[i].id) end
    C_MerchantFrame={GetItemInfo=function(i) return env.rows[i] end}
    canaccessvalue=nil
    for _,name in ipairs({"BuyMerchantItem","RepairAllItems","UseContainerItem","SetMerchantFilter"}) do
        _G[name]=function() error("只能建议，不能购买出售维修或切换商店筛选") end
    end
    local s=F.State();s.position={map=1,x=0.5,y=0.5};s.money=100;s.bags[100]=1
    local action={kind="service",npcId=78,serviceKind="supply",serviceGoal={items={[100]=7}}}
    B.Merchant:Event("MERCHANT_SHOW");B.Merchant:Snapshot(s)
    return B,s,action,env,function() for _,name in ipairs(names) do _G[name]=saved[name] end end
end

test("商店快照只关联当前真实NPC且关闭切换与受限身份清除旧报价",function()
    local B,s,a,e,finish=setup();local M=B.Merchant
    eq(s.merchant.npcId,78);eq(M.NpcId("Player-0-123"),nil);eq(M.NpcId("Creature-0-1-2-3-0-0001"),nil)
    a.npcId=79;eq(M.Quote(a,s),nil);a.npcId=78
    local first=M:Snapshot(s);e.rows[1].price=15;assert(first~=M:Snapshot(s))
    e.guid="Vehicle-0-1-2-3-79-0002";M:Snapshot(s);eq(s.merchant.npcId,79);eq(M.Quote(a,s),nil)
    canaccessvalue=function(v) return v~=e.guid end;M:Snapshot(s);eq(s.merchant,nil)
    canaccessvalue=nil;M:Snapshot(s);assert(s.merchant)
    M:Event("MERCHANT_CLOSED");M:Snapshot(s);eq(s.merchant,nil)
    M:Event("MERCHANT_SHOW");M:Snapshot(s);M:Event("PLAYER_ENTERING_WORLD");M:Snapshot(s);eq(s.merchant,nil)
    finish()
end)

test("补给报价按整份向上取整核对真实库存和金币且不执行购买",function()
    local B,s,a,e,finish=setup();local M=B.Merchant
    local q=M.Quote(a,s);eq(q.items[1].needed,6);eq(q.items[1].quantity,10);eq(q.cost,24);eq(q.ready,true)
    s.money=20;q=M.Quote(a,s);eq(q.shortage,4);eq(q.ready,false)
    s.money=nil;eq(M.Quote(a,s).ready,false)
    e.rows[1].numAvailable=9;M:Snapshot(s);q=M.Quote(a,s);eq(q.ready,false);eq(q.items[1].reason,"库存不足")
    e.rows[1].numAvailable=10;M:Snapshot(s);s.money=24;eq(M.Quote(a,s).ready,true)
    s.bags[100]=7;q=M.Quote(a,s);eq(#q.items,0);eq(q.cost,0)
    finish()
end)

test("额外货币缺失字段待加载和商店筛选不能生成零费用或足量假象",function()
    local B,s,a,e,finish=setup();local M=B.Merchant
    e.rows[1].hasExtendedCost=true;e.rows[1].price=0;M:Snapshot(s)
    local q=M.Quote(a,s);eq(q.cost,nil);eq(q.known,false);eq(q.ready,false)
    assert(q.items[1].reason:find("额外货币",1,true))
    e.rows[1].hasExtendedCost=false
    for _,field in ipairs({"price","stackCount","numAvailable","isPurchasable","hasExtendedCost"}) do
        local previous=e.rows[1][field];e.rows[1][field]=nil;M:Snapshot(s)
        q=M.Quote(a,s);eq(q.ready,false);eq(q.items[1].reason,"商品资料待加载");e.rows[1][field]=previous
    end
    e.rows={{currencyID=12},{spellID=34}};M:Snapshot(s);eq(s.merchant.pending,false)
    q=M.Quote(a,s);eq(q.cost,nil);assert(q.items[1].reason:find("筛选",1,true))
    e.rows={{name="等待物品链接"}};M:Snapshot(s);eq(s.merchant.pending,true)
    q=M.Quote(a,s);eq(q.cost,nil);eq(q.items[1].reason,"商品资料待加载")
    C_MerchantFrame=nil;M:Snapshot(s);eq(s.merchant.pending,true)
    finish()
end)

test("同物品多报价优先可购买库存且任一费用未知不输出部分总价",function()
    local B,s,a,e,finish=setup();local M=B.Merchant
    e.rows[2]={id=100,price=1,stackCount=1,numAvailable=0,isPurchasable=true,hasExtendedCost=false}
    e.rows[3]={id=100,price=2,stackCount=1,numAvailable=6,isPurchasable=true,hasExtendedCost=false}
    M:Snapshot(s);local q=M.Quote(a,s);eq(q.items[1].index,3);eq(q.cost,12)
    e.rows[3].isPurchasable=false;M:Snapshot(s);eq(M.Quote(a,s).items[1].index,1)
    a.serviceGoal.items[101]=1;M:Snapshot(s);q=M.Quote(a,s);eq(q.cost,nil);eq(q.known,false)
    eq(#q.items,2);assert(not table.concat(M.Lines(a,s),"\n"):find("报价合计",1,true))
    finish()
end)

test("维修自费报价尊重实际维修能力金币和暂未就绪费用",function()
    local B,s,a,e,finish=setup();local M=B.Merchant;a.serviceKind="repair"
    local q=M.Quote(a,s);eq(q.cost,27);eq(q.ready,true)
    s.money=20;eq(M.Quote(a,s).shortage,7)
    e.cost=0;M:Snapshot(s);eq(M.Quote(a,s).cost,0)
    e.cost=-1;M:Snapshot(s);q=M.Quote(a,s);eq(q.cost,nil);eq(q.issue,"维修报价待加载")
    e.repair=false;M:Snapshot(s);eq(M.Quote(a,s).issue,"当前商店不提供维修")
    finish()
end)

test("当前商店进入必要服务规划且仅实际恢复资源后返回保留任务",function()
    local B,s,a,e,finish=setup();local M=B.Merchant
    local q=F.Quest(1);q.actions[2].requiredItems={[100]=7};local d=F.Data({[1]=q})
    local service=B.Supplies.Fallback(s,d,{[1]="缺少必需物品"});assert(service and service.reference)
    local action=service.actions[1];eq(action.npcId,78);eq(action.serviceGoal.items[100],7)
    eq(service.seconds,nil);eq(B.Supplies.Done(action,s),false);eq(s.bags[100],1)
    s.bags[100]=7;eq(B.Supplies.Done(action,s),true)
    eq(B.Supplies.Fallback(s,d,{[1]="缺少必需物品"}),nil)
    s.durability=0.1;s.locked=42;s.quests[42]={title="保留任务",objectives={}}
    d.GetQuest=function(_,id) return id==42 and {id=42,title="保留任务"} end
    d.Target=function() return {map=1,x=0.6,y=0.5} end
    local result=plan(s,d,{minutes=60,dungeons=false},B)
    eq(result.maintenance,true);eq(result.fallback.npcId,78);eq(M.Quote(result.fallback,s).cost,27);eq(s.locked,42)
    s.durability=1;result=plan(s,d,{minutes=60,dungeons=false},B)
    eq(result.maintenance,nil);eq(result.fallback.questId,42)
    s.freeSlots=0;service=B.Supplies.Fallback(s,d,{});eq(service.actions[1].serviceKind,"vendor")
    eq(B.Supplies.Done(service.actions[1],s),false);s.freeSlots=1;eq(B.Supplies.Done(service.actions[1],s),true)
    s.dead=true;eq(M.CurrentService(s,"repair"),nil);s.dead=false;s.inInstance=true;eq(M.CurrentService(s,"vendor"),nil)
    finish()
end)
end
