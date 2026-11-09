return function(test,eq,F,A,plan)
local names={"UnitGUID","UnitName","CanMerchantRepair","GetMerchantNumItems","GetMerchantItemLink","C_MerchantFrame","canaccessvalue",
    "BuyMerchantItem","RepairAllItems","UseContainerItem","SetMerchantFilter","C_Container","MerchantFrame","IsShiftKeyDown","InCombatLockdown"}
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
    local d=F.Data({})
    eq(M.CurrentService(s,"supply",{[100]=6},d),nil)
    d.ServicePoints=function() return {{npcId=78,targets={[100]=7}}} end
    local service=M.CurrentService(s,"supply",{[100]=6},d);assert(service and service.reference)
    local action=service.actions[1];eq(action.npcId,78);eq(action.serviceGoal.items[100],7)
    eq(service.seconds,nil);eq(B.Supplies.Done(action,s),false);eq(s.bags[100],1)
    s.itemMetadata={[100]={name="所需材料"}}
    eq(M.Lines(action,s)[1],"所需材料：还需购买 6 件")
    s.bags[100]=7;eq(B.Supplies.Done(action,s),true);eq(#M.Lines(action,s),0)
    s.durability=0.1;s.locked=42;s.quests[42]={title="保留任务",objectives={}}
    d.GetQuest=function(_,id) return id==42 and {id=42,title="保留任务"} end
    d.Target=function() return {map=1,x=0.6,y=0.5} end
    local result=plan(s,d,{minutes=60,dungeons=false},B)
    eq(result.maintenance,true);eq(result.fallback.npcId,78);eq(s.merchant.canRepair,true);eq(s.locked,42)
    s.durability=1;result=plan(s,d,{minutes=60,dungeons=false},B)
    eq(result.maintenance,nil);eq(result.fallback.questId,42)
    s.freeSlots=0;service=B.Supplies.Fallback(s,d,{});eq(service.actions[1].serviceKind,"vendor")
    eq(B.Supplies.Done(service.actions[1],s),false)
    local slots,calls={},{}
    s.bagEntries={}
    for slot=1,11 do
        slots[slot]={itemID=100+slot,stackCount=1,quality=0,isLocked=false,hasNoValue=false}
        s.bagEntries[slot]={bag=0,slot=slot,id=100+slot,count=1}
    end
    slots[2].quality=1;slots[6].isLocked=true;slots[8].hasNoValue=true;slots[9].itemID=999
    slots[10].quality=nil;slots[11].hasLoot=true;s.bagEntries[12]={bag=-2,slot=1,id=112,count=1}
    C_Container={GetContainerItemInfo=function(bag,slot) eq(bag,0);return slots[slot] end,
        GetContainerItemQuestInfo=function(_,slot) return {isQuestItem=slot==3,isActive=false} end,
        UseContainerItem=function(bag,slot) eq(bag,0);calls[#calls+1]=slot end}
    MerchantFrame={selectedTab=1,IsShown=function() return true end}
    local shift,combat=false,false
    IsShiftKeyDown=function() return shift end;InCombatLockdown=function() return combat end
    d.db={Item={Get=function(id,key)
        if key=="startQuest" and id==105 then return 77 end
        if key=="relatedQuests" and id==104 then return {42} end
    end}}
    d.GetQuest=function(_,id) return id==42 and {id=42,sourceItemId=107} end
    B.state,B.Data,B.char,B.settings=s,d,{}, {autoSellJunk=false}
    local function open() M:Event("MERCHANT_CLOSED");M:Event("MERCHANT_SHOW");M:Snapshot(s) end
    open();M:SellJunk();eq(#calls,0)
    B.settings.autoSellJunk=true;shift=true;open();M:SellJunk();shift=false;M:SellJunk();eq(#calls,0)
    B.char.paused=true;open();M:SellJunk();eq(#calls,0);B.char.paused=false
    combat=true;open();M:SellJunk();eq(#calls,0);combat=false
    open();M:SellJunk();eq(#calls,1);eq(calls[1],1);eq(s.freeSlots,0)
    M:Event("MERCHANT_SHOW");M:SellJunk();eq(#calls,1)
    slots[6].isLocked=false;M:SellJunk();eq(#calls,2);eq(calls[2],6)
    slots[10].quality=0;M:SellJunk();eq(#calls,3);eq(calls[3],10)
    M:Event("MERCHANT_CLOSED");M:SellJunk();eq(#calls,3)
    C_Container.UseContainerItem=function(_,slot) calls[#calls+1]=slot;M:Event("MERCHANT_CLOSED") end
    open();M:SellJunk();eq(#calls,4);eq(calls[4],1)
    s.freeSlots=1;eq(B.Supplies.Done(service.actions[1],s),true)
    s.dead=true;eq(M.CurrentService(s,"repair"),nil);s.dead=false;s.inInstance=true;eq(M.CurrentService(s,"vendor"),nil)
    finish()
end)
end
