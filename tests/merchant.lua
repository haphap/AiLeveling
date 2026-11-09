return function(test,eq,F,A,plan)
local names={"UnitGUID","UnitName","CanMerchantRepair","GetMerchantNumItems","GetMerchantItemLink","C_MerchantFrame","canaccessvalue",
    "BuyMerchantItem","RepairAllItems","UseContainerItem","SetMerchantFilter"}
local function setup()
    local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
    local B={};for k,v in pairs(A) do B[k]=v end
    assert(loadfile("Merchant.lua"))("AiLeveling",B)
    assert(loadfile("Planner/Supplies.lua"))("AiLeveling",B)
    assert(loadfile("Planner/Planner.lua"))("AiLeveling",B)
    B.Navigation={Distance=function() return 0 end};B.TaskGuide=nil
    local env={guid="Creature-0-1-2-3-78-000001",repair=true}
    UnitGUID=function(unit) eq(unit,"npc");return env.guid end
    UnitName=function() return "当前商人" end
    CanMerchantRepair=function() return env.repair end
    GetMerchantNumItems=function() error("不读取商店库存") end
    GetMerchantItemLink=GetMerchantNumItems
    C_MerchantFrame={GetItemInfo=GetMerchantNumItems}
    canaccessvalue=nil
    for _,name in ipairs({"BuyMerchantItem","RepairAllItems","UseContainerItem","SetMerchantFilter"}) do
        _G[name]=function() error("只能建议，不能购买出售维修或切换商店筛选") end
    end
    local s=F.State();s.position={map=1,x=0.5,y=0.5};s.money=100;s.bags[100]=1
    local action={kind="service",npcId=78,serviceKind="supply",serviceGoal={items={[100]=7}}}
    B.Merchant:Event("MERCHANT_SHOW");B.Merchant:Snapshot(s)
    return B,s,action,env,function() for _,name in ipairs(names) do _G[name]=saved[name] end end
end

test("商店快照只关联当前真实NPC且关闭切换与受限身份清除旧状态",function()
    local B,s,a,e,finish=setup();local M=B.Merchant
    eq(s.merchant.npcId,78);eq(M.NpcId("Player-0-123"),nil);eq(M.NpcId("Creature-0-1-2-3-0-0001"),nil)
    local first=M:Snapshot(s);e.repair=false;assert(first~=M:Snapshot(s))
    e.guid="Vehicle-0-1-2-3-79-0002";M:Snapshot(s);eq(s.merchant.npcId,79)
    canaccessvalue=function(v) return v~=e.guid end;M:Snapshot(s);eq(s.merchant,nil)
    canaccessvalue=nil;M:Snapshot(s);assert(s.merchant)
    M:Event("MERCHANT_CLOSED");M:Snapshot(s);eq(s.merchant,nil)
    M:Event("MERCHANT_SHOW");M:Snapshot(s);M:Event("PLAYER_ENTERING_WORLD");M:Snapshot(s);eq(s.merchant,nil)
    finish()
end)

test("当前商店进入必要服务规划且仅实际恢复资源后返回保留任务",function()
    local B,s,a,e,finish=setup();local M=B.Merchant
    local q=F.Quest(1);q.actions[2].requiredItems={[100]=7};local d=F.Data({[1]=q})
    eq(M.CurrentService(s,"supply",{[100]=6},d),nil)
    d.ServicePoints=function() return {{npcId=78,targets={[100]=7}}} end
    local service=B.Supplies.Fallback(s,d,{[1]="缺少必需物品"});assert(service and service.reference)
    local action=service.actions[1];eq(action.npcId,78);eq(action.serviceGoal.items[100],7)
    eq(service.seconds,nil);eq(B.Supplies.Done(action,s),false);eq(s.bags[100],1)
    s.itemMetadata={[100]={name="所需材料"}}
    eq(M.Lines(action,s)[1],"所需材料：还需购买 6 件")
    s.bags[100]=7;eq(B.Supplies.Done(action,s),true);eq(#M.Lines(action,s),0)
    eq(B.Supplies.Fallback(s,d,{[1]="缺少必需物品"}),nil)
    s.durability=0.1;s.locked=42;s.quests[42]={title="保留任务",objectives={}}
    d.GetQuest=function(_,id) return id==42 and {id=42,title="保留任务"} end
    d.Target=function() return {map=1,x=0.6,y=0.5} end
    local result=plan(s,d,{minutes=60,dungeons=false},B)
    eq(result.maintenance,true);eq(result.fallback.npcId,78);eq(s.merchant.canRepair,true);eq(s.locked,42)
    s.durability=1;result=plan(s,d,{minutes=60,dungeons=false},B)
    eq(result.maintenance,nil);eq(result.fallback.questId,42)
    s.freeSlots=0;service=B.Supplies.Fallback(s,d,{});eq(service.actions[1].serviceKind,"vendor")
    eq(B.Supplies.Done(service.actions[1],s),false);s.freeSlots=1;eq(B.Supplies.Done(service.actions[1],s),true)
    s.dead=true;eq(M.CurrentService(s,"repair"),nil);s.dead=false;s.inInstance=true;eq(M.CurrentService(s,"vendor"),nil)
    finish()
end)
end
