return function(test,eq)
local names={"Constants","NUM_BAG_SLOTS","NUM_REAGENTBAG_SLOTS","KEYRING_CONTAINER","C_ActionBar","GetKeyRingSize","GetCVarBool","C_Container","C_Item","GetInventoryItemDurability"}
local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
local function fixture()
    Constants={InventoryConstants={NumBagSlots=4,NumReagentBagSlots=2}}
    NUM_BAG_SLOTS=4;NUM_REAGENTBAG_SLOTS=0;KEYRING_CONTAINER=-2
    C_ActionBar={ShouldShowKeyring=function() return true end}
    GetCVarBool=function() error("visibility must not affect inventory") end
    GetKeyRingSize=function() return 2 end
    GetInventoryItemDurability=nil
    local containers={
        [0]={free=2,items={{itemID=100,stackCount=2}}},
        [1]={free=3,family=0,items={}},[2]={free=1,family=32,items={}},
        [3]={free=0,family=0,items={}},[4]={free=0,family=0,items={}},
        [5]={free=1,family=32,items={{itemID=100,stackCount=3}}},
        [6]={free=9,family=0,items={}},
        [-2]={free=10,family=0,items={{itemID=200,stackCount=1,isLocked=true}}}}
    C_Container={GetContainerNumFreeSlots=function(id)
        local c=assert(containers[id],"bank/unknown container read");return c.free,c.family
    end,GetContainerNumSlots=function(id) assert(id~=-2,"use native keyring size");return #containers[id].items end,
    GetContainerItemInfo=function(id,slot) return containers[id].items[slot] end,
    GetContainerItemQuestInfo=function() return {isQuestItem=true} end}
    C_Item={GetItemInfo=function(id) return "item"..id,nil,1,nil,nil,nil,nil,20,nil,nil,0 end,
        GetItemFamily=function(id) return id==100 and 32 or 0 end}
    local B={requestedItems={}}
    for _,path in ipairs({"State.lua","Planner/Supplies.lua","QuestAssist.lua"}) do assert(loadfile(path))("AiLeveling",B) end
    local function snapshot()
        local s={quests={}};local key={};B.State:SnapshotBags(s,key);B.Supplies:Snapshot(s)
        return s,table.concat(key,"|")
    end
    return B,containers,snapshot
end
test("专业包与隐藏钥匙链计数进入任务缺失判断且不读取银行",function()
    local B,c,snapshot=fixture();local s,key=snapshot()
    eq(s.bags[100],5);eq(s.bags[200],1);eq(#s.bagEntries,3);eq(s.freeSlots,5)
    eq(s.inventory.bags[6].family,nil);eq(s.inventory.bags[-2].family,nil)
    eq(s.bagEntries[3].key,"-2:1");eq(s.bagEntries[3].locked,true)
    local rows=B.QuestAssist.Requirements({requiredItems={[100]=5,[200]=1}},s)
    eq(rows[1].missing,0);eq(rows[2].missing,0)
    c[5].items[1].stackCount=2;local changed,nextKey=snapshot();assert(key~=nextKey)
    eq(B.QuestAssist.Requirements({requiredItems={[100]=5}},changed)[1].missing,1)
end)

test("缺少额外容器能力时兼容标准包并保留空容器",function()
    local B,c,snapshot=fixture();Constants=nil;C_ActionBar=nil
    local s=snapshot();eq(s.bags[100],2);eq(s.bags[200],nil);eq(s.inventory.bags[5],nil)
    NUM_REAGENTBAG_SLOTS=2;s=snapshot();eq(s.bags[100],5)
    C_ActionBar={ShouldShowKeyring=function() return false end};s=snapshot();eq(s.inventory.bags[-2],nil)
    C_ActionBar.ShouldShowKeyring=function() return true end
    c[-2].items={};s=snapshot();eq(s.inventory.bags[-2].free,10);eq(s.bags[200],nil)
end)
for _,name in ipairs(names) do _G[name]=saved[name] end
end
