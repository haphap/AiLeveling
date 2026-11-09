return function(test,eq,F,A,plan)
local function item(id,loc,strength)
    return {id=id,equipLoc=loc,usable=true,requiredLevel=1,weaponDPS=0,stats={ITEM_MOD_STRENGTH_SHORT=strength or 0}}
end
local G=A.Gear

test("装备模型区分九职业与坦克治疗职责",function()
    local s=F.State()
    for _,class in ipairs({"WARRIOR","PALADIN","ROGUE","HUNTER","MAGE","PRIEST","WARLOCK","DRUID","SHAMAN"}) do
        s.class=class;assert(G.Model(s))
    end
    s.role="TANK";eq(G.Score({stats={ITEM_MOD_STAMINA_SHORT=10,RESISTANCE0_NAME=100}},s),12)
    s.role="HEALER";eq(G.Score({stats={ITEM_MOD_SPIRIT_SHORT=10}},s),8)
end)
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
test("套装比较核对更换前后件数且不重复提示保留套装",function()
    local s=F.State();s.equipment={[1]=item(1,"INVTYPE_HEAD",1),[3]=item(2,"INVTYPE_SHOULDER",1)}
    s.equipment[1].setId=7;s.equipment[3].setId=7
    local r=G.Upgrade(item(3,"INVTYPE_HEAD",2),s)
    eq(#r.notes,1);assert(r.notes[1]:find("2 → 1",1,true))
    local c=item(4,"INVTYPE_HEAD",3);c.setId=7;r=G.Upgrade(c,s);eq(#r.notes,0)
    c.setId=8;r=G.Upgrade(c,s);eq(#r.notes,2)
    local notes=table.concat(r.notes,"\n");assert(notes:find("#7",1,true));assert(notes:find("#8",1,true))
end)
test("未知效果来源仅供手选且不能自动抬高任务或副本路线",function()
    local s=F.State();s.items={[7]=item(7,"INVTYPE_HEAD",10)};s.equipment[1]=item(1,"INVTYPE_HEAD",1)
    s.equipment[1].useSpell=42
    local content={gearSources={wanted={verified=true,kind="quest",questId=7,itemId=7}}}
    local base={rate=100,priority=0};local route={rate=96,priority=0,actions={{kind="turnin",questId=7}}}
    G.Benefits({base,route},s,content)
    assert(route.gearSources.wanted);eq(route.gear,nil)
    eq(G.Prefer({base,route},base,s,{mode="relaxed"}),base)
    s.gearTarget="wanted";eq(G.Prefer({base,route},base,s,{mode="relaxed"}),route)
    s.equipment[1].useSpell=nil;s.gearTarget=nil;G.Benefits({base,route},s,content)
    assert(route.gear);eq(G.Prefer({base,route},base,s,{mode="relaxed"}),route)
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
test("装备偏好不改变经验率且副本仍须明确接受",function()
    local base={id=1,rate=100,priority=0};local gear={id=2,rate=96,priority=0,gear={upgrade={delta=10},chanceLow=1},gearSources={wanted=true}}
    eq(G.Prefer({base,gear},base,{}, {mode="fast"}),base)
    eq(G.Prefer({base,gear},base,{}, {mode="relaxed"}),gear);eq(gear.rate,96)
    gear.rate=94;eq(G.Prefer({base,gear},base,{}, {mode="relaxed"}),base)
    gear.requiresAcceptance=true;eq(G.Prefer({gear},base,{gearTarget="wanted"},{mode="fast"}),base)
    local new={best=gear,alternatives={base,gear},preferenceApplied=true}
    eq(A.Planner.Choose({best=base},new).best,gear)
end)
test("装备目标在获得额外实物后清除",function()
    local B={Content={gearSources={wanted={itemId=7}}},char={gearTarget="wanted",gearBaseline=1}}
    assert(loadfile("Planner/Gear.lua"))("AiLeveling",B)
    local s=F.State();s.equipment[11]=item(7,"INVTYPE_FINGER",1);B.Gear:SyncTarget(s);eq(s.gearTarget,"wanted")
    s.bags[7]=1;B.Gear:SyncTarget(s);eq(B.char.gearTarget,nil);eq(s.gearAcquired,7)
end)
test("共享目标无需耗时和数量模型且保留两个交付",function()
    local s,q1,q2=F.State(),F.Quest(1),F.Quest(2)
    for _,q in ipairs({q1,q2}) do
        local a=q.actions[2];a.shareKey="wolves";a.shareType="kill";a.targetId=99;a.workUnits=nil;a.secondsPerUnit=nil
    end
    s.quests[1]={objectives={{numFulfilled=6}}};s.quests[2]={objectives={{numFulfilled=2}}}
    local r=A.Planner.EvaluateMany({q1,q2},s,F.Data({[1]=q1,[2]=q2}),{minutes=60},"start")
    eq(r.seconds,40);eq(r.xp,2000)
    local shared;for _,a in ipairs(r.actions) do if a.sharedObjectives then shared=a end end
    eq(#shared.sharedObjectives,2);eq(shared.seconds,0)
    q2.actions[2].targetId=100
    r=A.Planner.EvaluateMany({q1,q2},s,F.Data({[1]=q1,[2]=q2}),{minutes=60},"start");eq(r.seconds,40)
    q2.actions[2].targetId=-1;eq(A.Planner.EvaluateMany({q1,q2},s,F.Data({}),{minutes=60},"start"),nil)
end)
test("交付经验按交付时预测等级计算且升级解锁后续",function()
    local s,q1,q2=F.State(),F.Quest(1),F.Quest(2)
    s.xp=90;s.maxXP=100;q1.xp=10;q2.xp={[20]=1,[21]=20000};q2.requiredLevel=21;q2.preQuestGroup={1}
    local data=F.Data({[1]=q1,[2]=q2});data.content.progression={verified=true,xpToLevel={[21]=30000}}
    local p=plan(s,data);eq(p.best.xp,20010);eq(p.best.forecast.level,21);eq(s.level,20);eq(s.xp,90)
    q2.requiredLevel=1;q2.preQuestGroup=nil
    local r=A.Planner.EvaluateMany({q1,q2},s,data,{minutes=60},"start");eq(r.xp,20010)
end)
test("未知后续经验曲线停止展开且等级上限为六十",function()
    local s,q1,q2=F.State(),F.Quest(1),F.Quest(2)
    s.xp=90;s.maxXP=100;q1.xp=20;q2.preQuestGroup={1};q2.xp=20000
    local r=plan(s,F.Data({[1]=q1,[2]=q2}));eq(r.best.xp,20);eq(r.best.forecast.uncertain,true)
    s.level=59;s.xp=90;local x=A.Progression.Advance(s,100000,{});eq(x.level,60);eq(x.xp,0)
    q1.preQuestGroup={999};eq(plan(F.State(),F.Data({[1]=q1})).best,nil)
end)
test("手选装备来源超出经验率候选上限仍保留且任务锁定优先",function()
    local s,quests=F.State(),{}
    for id=1,12 do quests[id]=F.Quest(id) end
    quests[12].xp=1;s.gearTarget="wanted";s.items={[7]=item(7,"INVTYPE_HEAD",10)}
    local d=F.Data(quests);d.content.gearSources={wanted={kind="quest",questId=12,itemId=7,verified=true}}
    local p=plan(s,d);assert(p.best.gearSources.wanted);eq(p.preferenceApplied,true)
    s.locked=1;p=plan(s,d);local found=false
    for _,a in ipairs(p.best.actions) do if a.questId==1 then found=true end end
    eq(found,true)
end)
test("预测交付解锁后续道路且不改变原始解锁快照",function()
    local s,q1,q2=F.State(),F.Quest(1),F.Quest(2)
    s.unlocked={};q1.xp=1;q1.setup=true;q2.preQuestGroup={1};q2.xp=20000
    q1.actions={q1.actions[1],q1.actions[3]}
    local d=F.Data({[1]=q1,[2]=q2})
    for _,edge in ipairs(d.content.edges.start) do edge.unlock="quest:1" end
    local p=plan(s,d);eq(p.best.xp,20001);eq(s.unlocked["quest:1"],nil)
end)
-- Native API mocks are scoped to the final scenarios and restored afterwards.
local saved={};local globals={"C_Map","C_TaxiMap","C_Container","GetBindLocation","GetTaxiMapID","TaxiNodeCost","GetTime","C_Item","C_PlayerInfo","CanDualWield"}
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
test("交通发现过滤阵营与未知节点并使用实时折扣费用",function()
    local s=snapshot();eq(s.unlocked["taxi:1"],true);eq(s.unlocked["taxi:2"],false);eq(s.unlocked["taxi:3"],nil);eq(s.unlocked["taxi:4"],nil)
    GetTaxiMapID=function() return 1 end
    C_TaxiMap.GetAllTaxiNodes=function() return {{nodeID=1,state=0,slotIndex=1},{nodeID=5,state=1,slotIndex=2}} end
    TaxiNodeCost=function(slot) eq(slot,2);return 20 end
    B.Transport:CaptureTaxi();s=snapshot();s.money=20
    local flight={verified=true,kind="flight",fromTaxi=1,toTaxi=5,cost=100,seconds=30}
    eq(A.Travel.Transit(flight,120,s),30);eq(A.Travel.Cost(flight,s),20)
    s.money=19;eq(A.Travel.Transit(flight,120,s),nil)
end)
test("飞行点已发现仍须尊重当前起点不可达并清除旧票价",function()
    local flight={verified=true,kind="flight",fromTaxi=1,toTaxi=5,cost=100,seconds=30}
    C_TaxiMap.GetAllTaxiNodes=function() return {{nodeID=1,state=0,slotIndex=1},{nodeID=5,state=2,slotIndex=2}} end
    B.Transport:CaptureTaxi();local s=snapshot();s.money=100
    eq(s.unlocked["taxi:5"],true);eq(s.taxiAvailability["1:5"],false);eq(s.taxiCosts["1:5"],nil)
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
test("新飞行点与声望变化清除旧连通及价格缓存",function()
    B.Transport.costs["1:5"]=20;B.Transport.availability["1:5"]=false
    B.Transport:InvalidateFlights();eq(B.Transport.costs["1:5"],nil);eq(B.Transport.availability["1:5"],nil)
    eq(B.Transport.known["taxi:5"],true);eq(B.Transport.dirty,true)
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
    assert(table.concat(r.notes):find("武器伤害数据待补齐",1,true))
    local direct=G.Loadout({[16]=companion,[17]=candidate},s);assert(direct.provisional)
    local content={gearSources={target={verified=true,kind="quest",questId=7,itemId=2}}}
    s.items={[2]=candidate}
    local route={rate=96,actions={{kind="turnin",questId=7}}}
    local base={rate=100,actions={}}
    G.Benefits({base,route},s,content);eq(route.gear,nil)
    eq(G.Prefer({base,route},base,s,{mode="relaxed"}),base)
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
