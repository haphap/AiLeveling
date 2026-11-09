return function(test,eq,F,A,plan)
local function item(id,loc,strength)
    return {id=id,equipLoc=loc,usable=true,requiredLevel=1,weaponDPS=0,stats={ITEM_MOD_STRENGTH_SHORT=strength or 0}}
end
local G=A.Gear

test("双手替换扣除主副手且背包搭配必须有双持能力",function()
    local s=F.State();s.equipment={[16]=item(1,"INVTYPE_WEAPON",10),[17]=item(2,"INVTYPE_WEAPON",5)}
    local r=G.Upgrade(item(3,"INVTYPE_2HWEAPON",20),s)
    eq(r.delta,5);eq(r.replacements[17],false)
    s.equipment={[16]=item(3,"INVTYPE_2HWEAPON",20)}
    s.bags[4]=1;s.items={[4]=item(4,"INVTYPE_WEAPON",12)}
    local off=item(5,"INVTYPE_WEAPONOFFHAND",15)
    eq(G.Upgrade(off,s),nil)
    s.capabilities={dualWield=true};r=G.Upgrade(off,s);eq(r.delta,7);eq(r.replacements[16].id,4)
end)
test("戒指更换较弱槽且唯一装备类别冲突阻断",function()
    local s=F.State();s.equipment={[11]=item(1,"INVTYPE_FINGER",10),[12]=item(2,"INVTYPE_FINGER",5)}
    local r=G.Upgrade(item(3,"INVTYPE_FINGER",12),s);eq(r.delta,7);assert(r.replacements[12])
    s.equipment[11].uniqueCategory=7;s.equipment[11].uniqueLimit=1
    local c=item(3,"INVTYPE_FINGER",12);c.uniqueCategory=7;c.uniqueLimit=2
    eq(G.Loadout({[12]=c},s),nil)
    c.pending=true;eq(G.Upgrade(c,s),nil);c.pending=false;c.usable=false;eq(G.Upgrade(c,s),nil)
end)
test("同 ID 背包实例保留附魔且单件不能同时占两手",function()
    local s=F.State();s.capabilities={dualWield=true};s.equipment={[16]=item(1,"INVTYPE_2HWEAPON",30)}
    local c=item(2,"INVTYPE_WEAPON",20);c.instanceKey="0:1";s.bags[2]=1;s.bagEquipment={c}
    local r=G.Upgrade(c,s);eq(r.delta,-10)
    local second=item(2,"INVTYPE_WEAPON",15);second.instanceKey="0:2";s.bags[2]=2;s.bagEquipment[2]=second
    r=G.Upgrade(c,s);eq(r.delta,5)
end)
test("整套比较列出被换下装备和双手替换丢失的效果",function()
    local s=F.State();s.equipment={[16]=item(1,"INVTYPE_WEAPON",10),[17]=item(2,"INVTYPE_SHIELD",5)}
    s.equipment[16].effectText="命中触发额外伤害";s.equipment[17].useSpell=42
    local r=G.Upgrade(item(3,"INVTYPE_2HWEAPON",20),s)
    eq(r.delta,5);eq(r.replacements[17],false)
    local notes=table.concat(r.notes,"\n")
    assert(notes:find("失去",1,true));assert(notes:find("命中触发额外伤害",1,true));assert(notes:find("#42",1,true))
    eq(s.equipment[17].id,2)
end)
test("来源按每次概率比较且未知分配份额保留零下界",function()
    local s=F.State();s.items={[7]=item(7,"INVTYPE_HEAD",10)}
    local source={verified=true,kind="dungeon",itemId=7,chance=0.2}
    local r=G.Source(source,s,{});eq(r.chanceLow,0);eq(r.chanceHigh,0.2);eq(r.expectedAttemptsHigh,nil)
    source.shareChance=0.5;r=G.Source(source,s,{});eq(r.expectedAttemptsHigh,10)
    s.failedDrops=99;eq(G.Source(source,s,{}).chanceHigh,0.1)
    s.bags[7]=1;eq(G.Source(source,s,{}).owned,true)
    s.items[7].weaponDPS=nil;s.items[7].equipLoc="INVTYPE_WEAPON";assert(G.Source(source,s,{}).upgrade.provisional)
end)
-- Native API mocks are scoped to the final scenarios and restored afterwards.
local saved={};local globals={"C_Map","C_TaxiMap","C_Container","GetBindLocation","GetTaxiMapID","TaxiNodeCost","GetTime","C_Item","C_PlayerInfo","CanDualWield",
    "TakeTaxiNode","UnitOnTaxi","InCombatLockdown","IsShiftKeyDown"}
for _,key in ipairs(globals) do saved[key]=_G[key] end
local B={Content={nodes={a={hearth=true,verified=true,bindName="Inn",position={map=1,x=0,y=0},accessRadius=10}},edges={},transit={}},char={},state={position={map=1}},Navigation={Distance=function() return 2 end},RequestRefresh=function(self) self.wakes=(self.wakes or 0)+1 end}
assert(loadfile("Transport.lua"))("AiLeveling",B)
C_Map={GetBestMapForUnit=function() return 1 end,GetMapInfo=function() return {parentMapID=0} end}
C_TaxiMap={GetTaxiNodesForMap=function() return {{nodeID=1,faction=2,isUndiscovered=false},{nodeID=2,faction=2,isUndiscovered=true},{nodeID=3,faction=1,isUndiscovered=false},{nodeID=4,faction=2}} end}
GetBindLocation=function() return "Inn" end
C_Container={GetItemCooldown=function() return 100,60,1 end}
local function snapshot(now)
    local s=F.State();s.faction="Alliance";s.now=now or 120;s.bags[6948]=1;B.Transport:Snapshot(s);return s
end
test("交通发现过滤阵营与未知节点并忽略费用",function()
    local s=snapshot();eq(s.unlocked["taxi:1"],true);eq(s.unlocked["taxi:2"],false);eq(s.unlocked["taxi:3"],nil);eq(s.unlocked["taxi:4"],nil)
    GetTaxiMapID=function() return 1 end
    C_TaxiMap.GetAllTaxiNodes=function() return {{nodeID=1,state=0,slotIndex=1},{nodeID=5,state=1,slotIndex=2}} end
    TaxiNodeCost=function(slot) eq(slot,2);return 20 end
    B.Transport:CaptureTaxi();s=snapshot();s.money=20
    local flight={verified=true,kind="flight",fromTaxi=1,toTaxi=5,cost=100,seconds=30}
    eq(A.Travel.Transit(flight,120,s),30)
    s.money=0;eq(A.Travel.Transit(flight,120,s),30)
    local calls,shift,combat,flying=0,false,false,false
    TakeTaxiNode=function(slot) eq(slot,2);calls=calls+1 end
    IsShiftKeyDown=function() return shift end;InCombatLockdown=function() return combat end
    UnitOnTaxi=function() return flying end
    B.ready=true;B.settings={autoTaxi=true};B.Navigation.index=1
    B.Navigation.actions={{kind="move"},{kind="transit",mode="flight",fromTaxi=1,toTaxi=5}}
    B.Transport:CaptureTaxi();eq(calls,1);eq(B.Navigation.index,1);eq(B.Transport.flight,nil)
    eq(B.Transport.taxiRequest.to,5)
    B.Transport:CaptureTaxi();eq(calls,1);B.Transport.taxiSelected=nil
    for _,flag in ipairs({"paused","manual","disabled","shift","combat","flying"}) do
        B.char.paused=flag=="paused";B.Navigation.manual=flag=="manual";B.settings.autoTaxi=flag~="disabled"
        shift,combat,flying=flag=="shift",flag=="combat",flag=="flying"
        B.Transport:CaptureTaxi();eq(calls,1)
    end
    B.char.paused=nil;B.Navigation.manual=nil;B.settings.autoTaxi=true;shift,combat,flying=false,false,false
    B.Navigation.actions[1]={kind="objective"};B.Transport:CaptureTaxi();eq(calls,1)
    B.Navigation.actions[1]={kind="move"};B.Navigation.actions[2].fromTaxi=2;B.Transport:CaptureTaxi();eq(calls,1)
    B.Navigation.actions[2].fromTaxi=1
    for _,node in ipairs({{nodeID=5,state=2,slotIndex=2},{nodeID=5,state=1,slotIndex=2,isMapLayerTransition=true}}) do
        C_TaxiMap.GetAllTaxiNodes=function() return {{nodeID=1,state=0,slotIndex=1},node} end
        B.Transport:CaptureTaxi();eq(calls,1)
    end
    C_TaxiMap.GetAllTaxiNodes=function() return {} end
    B.Transport:CaptureTaxi();eq(B.Transport.taxiRequest,nil)
    C_TaxiMap.GetAllTaxiNodes=function() return {{nodeID=1,state=0,slotIndex=1},{nodeID=5,state=1,slotIndex=2}} end
    B.Transport:CaptureTaxi();eq(calls,2);B.Transport:World();eq(B.Transport.taxiSelected,nil);eq(B.Transport.taxiRequest,nil)
    B.ready,B.settings,B.Navigation.actions,B.Navigation.index=nil,nil,nil,nil
end)
test("飞行点已发现仍须尊重当前起点不可达",function()
    local flight={verified=true,kind="flight",fromTaxi=1,toTaxi=5,cost=100,seconds=30}
    C_TaxiMap.GetAllTaxiNodes=function() return {{nodeID=1,state=0,slotIndex=1},{nodeID=5,state=2,slotIndex=2}} end
    B.Transport:CaptureTaxi();local s=snapshot();s.money=100
    eq(s.unlocked["taxi:5"],true);eq(s.taxiAvailability["1:5"],false)
    eq(A.Travel.Transit(flight,120,s),nil)
    local key=B.Transport.Key(s)
    C_TaxiMap.GetAllTaxiNodes=function() return {{nodeID=1,state=0,slotIndex=1},{nodeID=5,state=1,slotIndex=2}} end
    B.Transport:CaptureTaxi();local fresh=snapshot();fresh.money=100
    eq(A.Travel.Transit(flight,120,fresh),30);assert(B.Transport.Key(fresh)~=key)
    eq(s.taxiAvailability["1:5"],false)
end)
test("飞行地图切层图标不能当作实际飞行连接或询价",function()
    local calls=0;local original=TaxiNodeCost
    TaxiNodeCost=function() calls=calls+1;return 1 end
    C_TaxiMap.GetAllTaxiNodes=function() return {{nodeID=1,state=0,slotIndex=1},{nodeID=9,state=1,slotIndex=3,isMapLayerTransition=true}} end
    B.Transport:CaptureTaxi();local s=snapshot()
    eq(s.unlocked["taxi:9"],nil);eq(s.taxiAvailability["1:9"],nil);eq(calls,0)
    TaxiNodeCost=original
end)
test("炉石读取实际冷却且到期只唤醒一次",function()
    local s=snapshot();eq(s.hearthReady,160);eq(s.hearthNode,"a")
    eq(B.Transport.Key(s),B.Transport.Key(snapshot(130)))
    GetTime=function() return 160 end;B.Transport:Update();B.Transport:Update();eq(B.wakes,1)
    C_Container.GetItemCooldown=function() return 0,0,1 end
    eq(B.Transport.Key(snapshot(200)),B.Transport.Key(snapshot(210)))
    local hearth={verified=true,kind="hearth",to="b",seconds=10,cooldown=3600}
    eq(A.Travel.Transit(hearth,120,s),nil);hearth.to="a";eq(A.Travel.Transit(hearth,120,s),50)
end)
test("重复炉石地名需要实际绑定位置且炉石可以从当前节点使用",function()
    B.Content.nodes.b={hearth=true,verified=true,bindName="Inn",position={map=2},accessRadius=10}
    eq(snapshot().hearthNode,nil);B.Transport:Bound();eq(snapshot().hearthNode,"a")
    local c={nodes={a=F.Node(0,1),c=F.Node(0,2)},edges={},transit={h={verified=true,kind="hearth",to="a",seconds=10,cooldown=3600}}}
    local s=snapshot();s.now=200;s.hearthReady=200
    eq(A.Travel.Route(c,"c","a",s).seconds,10);eq(A.Travel.Route(c,nil,"a",s),nil)
end)
test("原生装备读取保留背包独立实例与未加载状态",function()
    local calls=0
    C_Item={GetItemInfo=function(link)
        if link==99 then return nil end
        return "Item",tostring(link),1,20,1,nil,nil,1,"INVTYPE_WEAPON"
    end,GetItemStats=function(link) return {ITEM_MOD_STRENGTH_SHORT=link=="enchanted" and 20 or 10} end,
        GetItemInfoInstant=function() return 7,nil,nil,"INVTYPE_WEAPON" end,RequestLoadItemDataByID=function() calls=calls+1 end}
    C_PlayerInfo={CanUseItem=function() return true end};CanDualWield=function() return false end
    local E={Content={items={},sources={},gearSources={}},requestedItems={}}
    assert(loadfile("Items.lua"))("AiLeveling",E)
    local s=F.State();s.bagEntries={{id=7,link="plain",key="0:1"},{id=7,link="enchanted",key="0:2"}}
    E.Items:Snapshot(s);eq(#s.bagEquipment,2);eq(s.bagEquipment[2].stats.ITEM_MOD_STRENGTH_SHORT,20);eq(s.capabilities.dualWield,false)
    eq(E.Items:Read(99).pending,true);E.Items:Read(99);eq(calls,1)
end)
for _,key in ipairs(globals) do _G[key]=saved[key] end
test("双手改双持时缺少搭配武器伤害不能认定为确定提升",function()
    local s=F.State();s.capabilities={dualWield=true}
    s.equipment={[16]=item(1,"INVTYPE_2HWEAPON",20)}
    local candidate=item(2,"INVTYPE_WEAPONOFFHAND",15)
    local companion=item(3,"INVTYPE_WEAPONMAINHAND",15);companion.weaponDPS=nil
    s.bagEquipment={companion}
    local r=G.Upgrade(candidate,s);eq(r.delta,10);assert(r.provisional)
    assert(table.concat(r.notes):find("武器伤害加载中",1,true))
    local direct=G.Loadout({[16]=companion,[17]=candidate},s);assert(direct.provisional)
    local content={gearSources={target={verified=true,kind="quest",questId=7,itemId=2}}}
    s.items={[2]=candidate}
    local route={rate=96,actions={{kind="turnin",questId=7}}}
    local base={rate=100,actions={}}
    G.Benefits({base,route},s,content);eq(route.gear,nil)
    eq(G.Prefer({base,route},base,s,{}),base)
    companion.weaponDPS=5;r=G.Upgrade(candidate,s);assert(not r.provisional)
    G.Benefits({base,route},s,content);assert(route.gear)
end)
test("整套伤害完整性覆盖新旧替换槽位，未变槽位与属性武器不阻断",function()
    local s=F.State();s.capabilities={dualWield=true}
    s.equipment={[16]=item(1,"INVTYPE_WEAPONMAINHAND",10),[17]=item(2,"INVTYPE_WEAPONOFFHAND",10)}
    s.equipment[17].weaponDPS=nil
    local main=item(3,"INVTYPE_WEAPONMAINHAND",20)
    assert(not G.Loadout({[16]=main},s).provisional)
    assert(G.Loadout({[16]=item(4,"INVTYPE_2HWEAPON",30),[17]=false},s).provisional)
    main.weaponDPS=nil
    assert(G.Loadout({[16]=main},s).provisional)
    s.class="MAGE";assert(not G.Loadout({[16]=main},s).provisional)
end)

end
