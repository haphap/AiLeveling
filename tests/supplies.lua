return function(test,eq,F,A,plan)
local S=A.Supplies
local function state(free)
    local s=F.State();s.money=100;s.itemMetadata={[100]={stackSize=20,family=0,quality=1,sellPrice=0},[101]={stackSize=20,family=32},[900]={stackSize=10,family=0,quality=0,sellPrice=10}}
    s.inventory={bags={[0]={family=0,free=free or 0}},slots={}}
    s.freeSlots=free or 0;return s
end

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
    local B={Navigation=F.Navigation,char={ignoreRepair=true},requestedItems={},Data={GetQuest=function() return nil end}}
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

end
