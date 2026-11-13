return function(test,eq,F,A)
local savedMap,savedQuest=C_Map,C_QuestLog
local savedReputation,savedSpell=C_Reputation,C_Spell
local function fixture()
    C_Map={GetMapInfo=function(map) if map==1 then return {name="任务区域"} end end};C_QuestLog={}
    C_Reputation,C_Spell=nil,nil
    local B={State=A.State,Travel=A.Travel,Navigation={Distance=function(_,a,b)
        if a and b and a.map==b.map then return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)*1000 end
    end}}
    for _,file in ipairs({"Data/Questie.lua","Planner/TaskGuide.lua"}) do assert(loadfile(file))("AiLeveling",B) end
    local rows={finishedBy={{9}},startedBy={{8}},objectives={{{6},{7}}}}
    local npcs={[9]={name="交付者"},[8]={name="发布者"},[6]={name="怪物甲"},[7]={name="怪物乙"}}
    B.Data.maps={[12]=1}
    B.Data.db={Quest={Get=function(_,key) return rows[key] end},Npc={Get=function(id,key) return npcs[id] and npcs[id][key] end},
        Object={Get=function() end},Item={Get=function() end}}
    local q={id=1,title="区域任务",zoneOrSort=12}
    local s=F.State();s.position={map=1,x=0,y=0};s.runSpeed=7
    s.quests={[1]={objectives={{text="日志中无法对应的目标",type="monster",numRequired=3,numFulfilled=1}}}}
    return B,q,s,rows,npcs
end
test("零数量进入区域仍需实际完成且多个触发目标分别保留",function()
    local B,q,s,rows=fixture();q.questLevel=10;s.quests={};rows.objectives={}
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    local facts={level=10,objectives={{kind="areaTriggerEnter",id=44590,count=0}},complex=false}
    B.TaskFacts={cacheXP={version="1.60.1",build="70862",interface=16001,quests={[1]=facts}}}
    rows.triggerEnd={"Explore",{[12]={{20,30}}}}
    local descriptions,positions,complex=B.Data:ReferenceObjectiveTargets(q,s)
    eq(#descriptions,1);eq(descriptions[1].areaTriggerId,44590);eq(descriptions[1].numRequired,nil)
    eq(descriptions[1].finished,false);eq(complex,false);eq(positions[1].x,0.2)
    eq(B.Data:DeliveryOnly(q,s),false)
    facts.objectives[2]={kind="areaTriggerEnter",id=44591,count=0}
    descriptions,positions=B.Data:ReferenceObjectiveTargets(q,s)
    eq(#descriptions,2);eq(positions[1].approximate,true);eq(positions[2].approximate,true)
    local stages=B.TaskGuide.Stages(q,s,B.Data,{kind="accept",position={map=1,x=0,y=0}})
    eq(#stages,4);eq(stages[2].areaTriggerId,44590);eq(stages[3].areaTriggerId,44591)
    s.quests[1]={objectives=descriptions};s.position=positions[1]
    eq(#B.Data:ObjectiveTargets(q,s),2);eq(s.quests[1].ready,nil)
    descriptions[1].finished=true;eq(#B.Data:ObjectiveTargets(q,s),1)
    eq(descriptions[2].finished,false);eq(s.completed[1],nil)
    s.quests={};facts.objectives={{kind="areaTrigger",id=223,count=0}}
    descriptions=B.Data:ReferenceObjectiveTargets(q,s)
    eq(#descriptions,1);eq(descriptions[1].numRequired,nil);eq(descriptions[1].finished,false)
    rows.triggerEnd=nil
    facts.objectives={{kind="criteriaTree",id=224929,count=1},{kind="criteriaTree",id=224931,count=1},{kind="npc",id=6,count=1}}
    descriptions,positions,complex=B.Data:ReferenceObjectiveTargets(q,s)
    eq(#descriptions,3);eq(complex,false);eq(B.Data:DeliveryOnly(q,s),false)
    local events={}
    for index,o in ipairs(descriptions) do if o.criteriaTreeId then
        events[o.criteriaTreeId]=index;eq(o.type,"event");eq(o.numRequired,1);eq(o.finished,false);eq(o.targetId,nil)
    end end
    assert(events[224929] and events[224931])
    stages=B.TaskGuide.Stages(q,s,B.Data,{kind="accept",position={map=1,x=0,y=0}})
    eq(#stages,5);eq(stages[events[224929]+1].criteriaTreeId,224929)
    s.quests[1]={objectives=descriptions};s.position=positions[events[224929]]
    eq(B.Data:ObjectiveIdentities(q,s)[events[224929]],nil)
    B.Data:ObjectiveTargets(q,s);eq(descriptions[events[224929]].finished,false);eq(s.quests[1].ready,nil)
    descriptions[events[224929]].finished=true;B.Data:ObjectiveTargets(q,s)
    eq(descriptions[events[224931]].finished,false);eq(s.completed[1],nil)
end)
test("同构建确认仅交付时未绑定日志目标的辅助提示不拦住收件人导航",function()
    local B,q,s,rows,npcs=fixture();q.questLevel=10;rows.objectives={};s.quests={}
    local facts={level=10,complex=false,objectives={}}
    q.taskFacts=facts;rows.extraObjectives={{nil,5,"乘坐交通返回交付",0,{{"monster",8}}}}
    eq(B.Data:DeliveryOnly(q,s),false)
    B.TaskFacts={cacheXP={version="1.60.1",build="70862",interface=16001,quests={[1]=facts}}}
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    npcs[8].spawns={[12]={{10,10}}};npcs[9].spawns={[12]={{80,90}}}
    eq(B.Data:DeliveryOnly(q,s),true)
    local stages,complete=B.TaskGuide.Stages(q,s,B.Data,{kind="accept",position=B.Data:Target(q,s)})
    eq(complete,true);eq(#stages,2);eq(stages[2].kind,"turnin");eq(stages[2].position.entityId,9)
    s.quests[1]={objectives={}}
    eq(B.Data:Target(q,s).entityId,9);eq(s.quests[1].ready,nil);eq(s.completed[1],nil)
    s.quests[1].objectives={{type="event",finished=false}}
    eq(B.Data:DeliveryOnly(q,s),false);s.quests={}
    rows.extraObjectives[1][4]=1;eq(B.Data:DeliveryOnly(q,s),false)
    rows.extraObjectives[1][4]=nil;eq(B.Data:DeliveryOnly(q,s),false)
    rows.extraObjectives[1][4]=0
    facts.complex=true;eq(B.Data:DeliveryOnly(q,s),false);facts.complex=false
    q.questLevel=-1;s.level=30;eq(B.Data:DeliveryOnly(q,s),true)
    stages,complete=B.TaskGuide.Stages(q,s,B.Data,{kind="accept",position=B.Data:Target(q,s)})
    eq(complete,true);eq(#stages,2);eq(stages[2].position.entityId,9)
    eq(s.quests[1],nil);eq(s.completed[1],nil)
    s.clientVersion="other";eq(B.Data:DeliveryOnly(q,s),false)
    s.clientVersion="1.60.1";s.clientBuild="70862";q.questLevel=10;rows.finishedBy={{9,10}}
    npcs[10]={name="另一交付者",spawns={[12]={{20,30}}}}
    eq(B.Data:DeliveryOnly(q,s),true);eq(B.Data:Recipient(q),nil)
    stages,complete=B.TaskGuide.Stages(q,s,B.Data,{kind="accept",position=B.Data:Target(q,s)})
    eq(complete,true);eq(#stages,2);eq(stages[2].position.entityId,10)
    eq(B.Data:Recipient(q,stages[2].position).entityId,10)
    s.quests[1]={objectives={}};eq(B.Data:Target(q,s).entityId,10)
    eq(s.quests[1].ready,nil);eq(s.completed[1],nil)
    s.quests={};rows.finishedBy={{},{}};eq(B.Data:DeliveryOnly(q,s),false)
end)
test("事件物品付款与未知资料不被归为仅交付任务",function()
    local B,q,s,rows=fixture();q.questLevel=10;rows.objectives={};s.quests={}
    local facts={level=10,complex=false,objectives={}};q.taskFacts=facts
    eq(B.Data:DeliveryOnly(q,s),true)
    for key,value in pairs({triggerEnd={1},extraObjectives={{1}},objectives={nil,nil,{{100}}}}) do
        local old=rows[key];rows[key]=value;eq(B.Data:DeliveryOnly(q,s),false);rows[key]=old
    end
    for key,value in pairs({specialFlags=2,requiredSourceItems={{100,1}}}) do
        local old=q[key];q[key]=value;eq(B.Data:DeliveryOnly(q,s),false);q[key]=old
    end
    for key,value in pairs({complex=true,objectives={{kind="item",id=100}},level=11}) do
        local old=facts[key];facts[key]=value;eq(B.Data:DeliveryOnly(q,s),false);facts[key]=old
    end
    s.quests[1]={objectives={{text="真实日志要求",finished=false}}};eq(B.Data:DeliveryOnly(q,s),false);s.quests={}
    q.taskFacts=nil;eq(B.Data:DeliveryOnly(q,s),false)
    B.TaskFacts={cacheXP={version="1.60.1",build="70862",interface=16001,quests={[1]=facts}}}
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001;eq(B.Data:DeliveryOnly(q,s),true)
    facts.itemUses={[500]={spellId=123}};eq(B.Data:DeliveryOnly(q,s),false);facts.itemUses=nil
    s.clientVersion="other";eq(B.Data:DeliveryOnly(q,s),false)
end)
test("接取时发放的单件交付物品不重复规划收集且不写入背包",function()
    local B,q,s,rows=fixture();s.quests={};s.bags={};rows.objectives={[3]={{100,count=1}}}
    q.sourceItemId=100;q.startedBy=rows.startedBy
    local descriptions=B.Data:ReferenceObjectiveTargets(q,s)
    eq(descriptions[1].providedOnAccept,true);eq(descriptions[1].finished,false);eq(descriptions[1].numFulfilled,0)
    local stages=B.TaskGuide.Stages(q,s,B.Data,{kind="accept",position=B.Data:Target(q,s)})
    eq(#stages,2);eq(stages[2].kind,"turnin");eq(s.bags[100],nil);eq(s.completed[q.id],nil)
    s.quests[q.id]={objectives={{text="实际尚未取得",type="item",finished=false,numRequired=1,numFulfilled=0}}}
    descriptions=B.Data:ReferenceObjectiveTargets(q,s);eq(descriptions[1].providedOnAccept,nil)
    stages=B.TaskGuide.Stages(q,s,B.Data,{kind="objective",position=B.Data:Target(q,s)})
    eq(stages[1].kind,"objective");eq(s.quests[q.id].objectives[1].finished,false)
end)
test("掉落触发物品与多件未知发放数量仍需收集且事件保留",function()
    local B,q,s,rows=fixture();s.quests={};s.bags={};rows.objectives={[3]={{100,count=1}}}
    q.sourceItemId=100;q.startedBy={[3]={100}}
    eq(B.Data:ReferenceObjectiveTargets(q,s)[1].providedOnAccept,nil)
    q.startedBy={[3]={99}}
    eq(B.Data:ReferenceObjectiveTargets(q,s)[1].providedOnAccept,true)
    eq(s.bags[100],nil);eq(s.completed[q.id],nil)
    q.startedBy={[3]={99,100}}
    eq(B.Data:ReferenceObjectiveTargets(q,s)[1].providedOnAccept,nil)
    q.startedBy=rows.startedBy;rows.objectives[3][1].count=2
    eq(B.Data:ReferenceObjectiveTargets(q,s)[1].providedOnAccept,nil)
    rows.objectives[3][1].count=1;rows.triggerEnd={"事件",{[12]={{20,30}}}}
    local stages=B.TaskGuide.Stages(q,s,B.Data,{kind="accept",position=B.Data:Target(q,s)})
    eq(#stages,3);eq(stages[2].kind,"objective");assert(stages[2].text:find("事件",1,true))
end)
test("已有目标身份仅补匹配缓存数量且保留明确数量及版本边界",function()
    local B,q,s,rows=fixture();q.questLevel=10;s.quests={};s.bags={[100]=5}
    rows.objectives={[3]={{100},{101}}}
    local facts={level=10,objectives={{kind="item",id=100,count=6},{kind="npc",id=101,count=7}}}
    B.TaskFacts={cacheXP={version="1.60.1",build="70862",interface=16001,quests={[1]=facts}}}
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    local desc=B.Data:ReferenceObjectiveTargets(q,s)
    eq(desc[1].numRequired,6);eq(desc[1].numFulfilled,5);eq(desc[1].finished,false);eq(desc[2].numRequired,nil)
    eq(rows.objectives[3][1].count,nil)
    rows.objectives[3][1].count=2;eq(B.Data:ReferenceObjectiveTargets(q,s)[1].numRequired,2)
    rows.objectives[3][1].count=nil;q.taskFacts={objectives={{kind="item",id=100,count=3}}}
    eq(B.Data:ReferenceObjectiveTargets(q,s)[1].numRequired,3);q.taskFacts=nil
    s.clientVersion="other";eq(B.Data:ReferenceObjectiveTargets(q,s)[1].numRequired,nil);s.clientVersion="1.60.1";s.clientBuild="70862"
    q.questLevel=11;eq(B.Data:ReferenceObjectiveTargets(q,s)[1].numRequired,nil);q.questLevel=10
    facts.objectives[3]={kind="item",id=100,count=4};eq(B.Data:ReferenceObjectiveTargets(q,s)[1].numRequired,nil)
end)
test("当前构建缓存补充空目标并识别物品来源但保留原生日志状态",function()
    local B,q,s,rows,npcs=fixture();q.questLevel=10;rows.objectives={}
    B.TaskFacts={cacheXP={version="1.60.1",build="70862",interface=16001,quests={
        [1]={level=10,objectives={{kind="item",id=100,count=2}},complex=false}}}}
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    B.Data.db.Item.Get=function(_,key) if key=="name" then return "头颅" elseif key=="npcDrops" then return {6} end end
    npcs[6].spawns={[12]={{25,30}}}
    s.quests[1].objectives={{text="头颅：0/2",type="item",finished=false}}
    local p=B.Data:Target(q,s);eq(p.targetId,100);eq(p.entityId,6);eq(p.x,0.25)
    s.bags[100]=2
    p=B.Data:Target(q,s);eq(p.targetId,100);eq(s.quests[1].objectives[1].finished,false)
    eq(s.quests[1].ready,nil);eq(s.completed[1],nil)
    s.quests[1].objectives[1].finished=true;eq(#B.Data:ObjectiveTargets(q,s),0)
    s.quests={};local descriptions,positions=B.Data:ReferenceObjectiveTargets(q,s)
    eq(descriptions[1].finished,true);eq(descriptions[1].numRequired,2);eq(descriptions[1].numFulfilled,2);eq(next(positions),nil)
    local stages=B.TaskGuide.Stages(q,s,B.Data,{kind="accept",position={map=1,x=0,y=0}})
    eq(#stages,2);eq(stages[2].kind,"turnin");eq(s.quests[1],nil)
    s.bags[100]=1;descriptions,positions=B.Data:ReferenceObjectiveTargets(q,s)
    eq(descriptions[1].finished,false);eq(positions[1].targetId,100)
    stages=B.TaskGuide.Stages(q,s,B.Data,{kind="accept",position={map=1,x=0,y=0}})
    eq(#stages,3);eq(stages[2].need,2);eq(stages[2].have,1)
end)
test("缓存目标按构建与任务等级隔离且不覆盖Questie修正",function()
    local B,q,s,rows=fixture();q.questLevel=10;rows.objectives={}
    B.TaskFacts={cacheXP={version="1.60.1",build="70862",interface=16001,quests={
        [1]={level=10,objectives={{kind="item",id=100,count=2}},complex=false}}}}
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    eq(B.Data:ObjectiveEntries(q,s)[3][1][1],100)
    for key,value in pairs({clientVersion="other",interface=1}) do
        local old=s[key];s[key]=value;eq(next(B.Data:ObjectiveEntries(q,s)),nil);s[key]=old
    end
    q.questLevel=11;eq(next(B.Data:ObjectiveEntries(q,s)),nil);q.questLevel=10
    q.questLevel=-1;s.level=30;eq(B.Data:ObjectiveEntries(q,s)[3][1].count,2)
    s.clientVersion="other";eq(next(B.Data:ObjectiveEntries(q,s)),nil);s.clientVersion="1.60.1";s.clientBuild="70862"
    rows.objectives={{{6}}};eq(B.Data:ObjectiveEntries(q,s),rows.objectives)
end)
test("缓存未支持要求保留复杂标记且不按单目标猜测身份",function()
    local B,q,s,rows=fixture();q.questLevel=10;rows.objectives={}
    B.TaskFacts={cacheXP={version="1.60.1",build="70862",interface=16001,quests={
        [1]={level=10,objectives={{kind="npc",id=6,count=1}},complex=true}}}}
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    eq(next(B.Data:ObjectiveIdentities(q,s)),nil)
    local _,_,complex=B.Data:ReferenceObjectiveTargets(q,s);eq(complex,true)
end)
test("同构建目标进度位置补区域兜底并按身份数量匹配且不覆盖精确坐标",function()
    local B,q,s,rows,npcs=fixture();q.questLevel=10;rows.objectives={{{6,count=3}}}
    s.clientVersion,s.clientBuild,s.interface="1.60.1","70862",16001
    s.quests[1].objectives[1].text="怪物甲 1/3"
    local fact={kind="npc",id=6,count=3,locations={{map=1,x=0.2,y=0.3},{map=1,x=0.8,y=0.3},{map=99,x=0,y=0}}}
    B.TaskFacts={cacheXP={version="1.60.1",build="70862",interface=16001,quests={
        [1]={level=10,objectives={fact},complex=false}}}}
    local p=B.Data:Target(q,s);eq(p.x,0.2);eq(p.approximate,true);eq(p.sourceKind,"observation");eq(p.targetId,6)
    eq(fact.locations[1].sourceKind,nil)
    s.position={map=1,x=0.95,y=0.3};eq(B.Data:Target(q,s).x,0.8)
    npcs[6].spawns={[12]={{70,60}}};p=B.Data:Target(q,s);eq(p.x,0.7);eq(p.approximate,nil)
    npcs[6].spawns={[12]={{-1,-1}}};eq(B.Data:Target(q,s).x,0.8)
    C_QuestLog.GetNextWaypoint=function() return 1,0.9,0.4 end
    eq(B.Data:Target(q,s).x,0.9);C_QuestLog.GetNextWaypoint=nil
    s.clientVersion="other";eq(B.Data:Target(q,s).x,0.5);s.clientVersion="1.60.1";s.clientBuild="70862"
    q.questLevel=11;eq(B.Data:Target(q,s).x,0.5);q.questLevel=10
    s.quests[1].objectives[1].numRequired=4;eq(B.Data:Target(q,s).x,0.5)
    s.quests[1].objectives[1].numRequired=3;fact.id=7;eq(B.Data:Target(q,s).x,0.5);fact.id=6
    s.quests[1].objectives[1].finished=true;eq(#B.Data:ObjectiveTargets(q,s),0);eq(s.completed[1],nil)
    s.quests={}
    local descriptions,positions=B.Data:ReferenceObjectiveTargets(q,s)
    eq(descriptions[1].numRequired,3);eq(positions[1].x,0.8);eq(positions[1].sourceKind,"observation")
end)
test("缺交付坐标或目标对应时使用任务区域中心且精确位置优先",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    local p=d:Target(q,s);eq(p.map,1);eq(p.x,0.5);eq(p.y,0.5);eq(p.approximate,true);eq(p.objectiveIndex,1)
    eq(next(d:ObjectiveIdentities(q,s)),nil);eq(p.targetId,nil)
    s.quests[1].ready=true;p=d:Target(q,s);eq(p.entityId,9);eq(p.approximate,true)
    npcs[9].spawns={[12]={{20,30}}};p=d:Target(q,s);eq(p.x,0.2);eq(p.approximate,nil)
    s.quests[1].ready=nil;s.quests[1].objectives[1].text="怪物甲：1/3"
    npcs[6].spawns={[12]={{25,35}}};p=d:Target(q,s);eq(p.x,0.25);eq(p.targetId,6)
    C_QuestLog.GetNextWaypoint=function() return 1,0.1,0.2 end
    p=d:Target(q,s);eq(p.x,0.1);eq(p.label,"客户端任务目标")
    C_QuestLog.GetNextWaypoint=nil;s.quests={};p=d:Target(q,s);eq(p.x,0.5);eq(p.entityId,8)
    q.zoneOrSort=-12;eq(d:AreaTarget(q),nil)
    q.zoneOrSort=99;eq(d:AreaTarget(q),nil)
end)
test("已知实体区域的缺坐标标记优先于任务分类并保留身份",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    C_Map.GetMapInfo=function(map) return {mapID=map} end
    d.maps[99]=2;npcs[6].spawns={[99]={{-1,-1}}}
    q.zoneOrSort=-61;s.quests[1].objectives[1].text="怪物甲：1/3"
    local p=d:Target(q,s);eq(p.map,2);eq(p.approximate,true);eq(p.targetId,6);eq(p.entityId,6)
    eq(p.label,"区域参考点");eq(#d:EntityPoints(d.db.Npc,6),0)
    s.quests[1].ready=true;npcs[9].spawns={[99]={{-1,-1}}}
    p=d:Target(q,s);eq(p.map,2);eq(p.entityId,9);eq(p.approximate,true)
    s.quests={};npcs[8].spawns={[99]={{-1,-1}}}
    p=d:Target(q,s);eq(p.map,2);eq(p.entityId,8)
end)
test("缺地图收件人仍按真实身份归组且不混同发布者或备选收件人",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    npcs[9].spawns={[97]={{-1,-1}}};npcs[8].spawns={[12]={{10,20}}}
    local choices={}
    for id=1,2 do
        local quest={id=id,title="同收件人任务",zoneOrSort=12}
        s.quests[id]={ready=id==1,objectives={{text="怪物甲",type="monster"}}}
        local first={kind=id==1 and "turnin" or "objective",questId=id,areaId=id==1 and 97 or nil}
        local stages,complete=B.TaskGuide.Stages(quest,s,d,first)
        eq(complete,false);eq(stages[#stages].position,nil)
        choices[id]={questId=id,stages=stages}
    end
    local groups,byQuest=B.TaskGuide.DeliveryGroups(choices,s)
    eq(#groups,1);eq(groups[1].key,"npc:9");eq(groups[1].title,"交付者");eq(groups[1].ready,1)
    eq(byQuest[1],byQuest[2]);eq(s.completed[1],nil)
    rows.finishedBy={{9,8}};eq(d:Recipient(q),nil)
    local chosen={entityKind="npc",entityId=8,entityName="发布者"}
    eq(d:Recipient(q,chosen).entityId,8)
    rows.finishedBy={nil,{9}};d.db.Object.Get=function() return "交付对象" end
    eq(d:Recipient(q).entityKind,"object")
    choices[2].stages[#choices[2].stages].recipient=d:Recipient(q)
    eq(#B.TaskGuide.DeliveryGroups(choices,s),0)
    rows.finishedBy={};eq(d:Recipient(q),nil)
end)
test("多来源目标及接交始终优先精确坐标且忽略其他无效标记",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    npcs[9].spawns={[12]={{-1,-1}}};npcs[8].spawns={[12]={{90,90}}}
    rows.finishedBy={{9,8}};s.quests[1].ready=true
    local p=d:Target(q,s);eq(p.entityId,8);eq(p.approximate,nil)
    rows.finishedBy={{8,9}};p=d:Target(q,s);eq(p.entityId,8)
    s.quests[1].ready=nil;rows.objectives={nil,nil,{{100}}}
    d.db.Item.Get=function(_,key) if key=="npcDrops" then return {9,8} elseif key=="name" then return "物品" end end
    s.quests[1].objectives={{text="物品",type="item"}}
    p=d:Target(q,s);eq(p.entityId,8);eq(p.targetId,100);eq(p.approximate,nil)
    npcs[9].spawns={[12]={{-1,10}}};eq(#d:EntityPoints(d.db.Npc,9,true),0)
end)
test("购买型任务使用友好商人坐标并保留物品身份和参考阶段阵营",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    q.zoneOrSort=-284;s.faction="Alliance";rows.objectives={nil,nil,{{100}}}
    d.db.Item.Get=function(_,key) if key=="vendors" then return {9,8} elseif key=="name" then return "饲料" end end
    npcs[9].friendlyToFaction="H";npcs[9].spawns={[12]={{10,10}}}
    npcs[8].friendlyToFaction="A";npcs[8].spawns={[12]={{20,30}}}
    s.quests[1].objectives={{text="饲料：0/1",type="item",numRequired=1,numFulfilled=0}}
    local p=d:Target(q,s);eq(p.entityId,8);eq(p.targetKind,"item");eq(p.targetId,100)
    eq(p.sourceKind,"vendor");eq(p.x,0.2);eq(p.objectiveIndex,1)
    eq(s.quests[1].ready,nil);eq(s.completed[1],nil)
    B.UI={};assert(loadfile("UI/Main.lua"))("AiLeveling",B)
    local text=B.UI.ActionText({kind="objective",position=p},{})
    assert(text:find("向发布者购买饲料",1,true));assert(not text:find("库存",1,true))
    eq(B.UI.ActionText({kind="turnin",position=p},{}),"交付任务")
    local stages=B.TaskGuide.Stages(q,s,d,{kind="objective",objectiveIndex=1,position=p})
    eq(stages[1].purchase.npcId,8);eq(stages[1].purchase.map,1)
    -- A closer drop source must not suppress the buying alternative.
    npcs[6].spawns={[12]={{1,1}}}
    d.db.Item.Get=function(_,key)
        if key=="vendors" then return {9,8} elseif key=="npcDrops" then return {6} elseif key=="name" then return "饲料" end
    end
    p=d:Target(q,s);eq(p.entityId,6);eq(p.purchase.npcId,8)
    stages=B.TaskGuide.Stages(q,s,d,{kind="objective",objectiveIndex=1,position={map=1,x=0.01,y=0.01,label="客户端任务目标"}})
    eq(stages[1].purchase.npcId,8)
    npcs[6].spawns=nil
    s.quests={};local descriptions,positions=d:ReferenceObjectiveTargets(q,s)
    eq(positions[1].entityId,8);eq(descriptions[1].targetId,100)
    s.faction="Horde";descriptions,positions=d:ReferenceObjectiveTargets(q,s);eq(positions[1].entityId,9)
    s.faction=nil;descriptions,positions=d:ReferenceObjectiveTargets(q,s);eq(positions[1].approximate,true);eq(positions[1].entityId,nil);eq(positions[1].sourceKind,nil)
    npcs[8].friendlyToFaction="AH";descriptions,positions=d:ReferenceObjectiveTargets(q,s);eq(positions[1].entityId,8)
    npcs[8].spawns={[12]={{-1,-1}}};descriptions,positions=d:ReferenceObjectiveTargets(q,s)
    eq(positions[1].approximate,true);eq(positions[1].targetId,100)
end)
test("独立事件地点进入已接和未接规划且保留原生完成事实",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    q.zoneOrSort=-141;rows.objectives={};rows.triggerEnd={"Protect Daphne",{[12]={{42,88}}}}
    npcs[8].spawns={[12]={{20,30}}};npcs[9].spawns={[12]={{25,35}}}
    s.quests[1].objectives={{text="保护目标",type="event",finished=false}}
    local p=d:Target(q,s);eq(p.x,0.42);eq(p.sourceKind,"trigger");eq(p.objectiveIndex,1);eq(p.targetId,nil)
    local stages,complete=B.TaskGuide.Stages(q,s,d,{kind="objective",position=p,objectiveIndex=1})
    eq(complete,true);eq(#stages,2);eq(stages[1].position.sourceKind,"trigger")
    eq(s.completed[1],nil);eq(s.quests[1].ready,nil)
    s.quests[1].objectives[1].finished=true;eq(#d:ObjectiveTargets(q,s),0)
    s.quests[1].ready=true;p=d:Target(q,s);eq(p.entityId,9);eq(p.sourceKind,nil)
    s.quests={};stages,complete=B.TaskGuide.Stages(q,s,d,{kind="accept",position=d:Target(q,s)})
    eq(complete,true);eq(#stages,3);eq(stages[2].position.x,0.42);eq(stages[2].targetId,nil)
    s.quests[1]={objectives={}};p=d:Target(q,s);eq(p.sourceKind,"trigger")
    stages,complete=B.TaskGuide.Stages(q,s,d,{kind="objective",position=p});eq(complete,true)
    C_QuestLog.GetNextWaypoint=function() return 1,0.1,0.2 end
    eq(d:Target(q,s).label,"客户端任务目标")
    C_QuestLog.GetNextWaypoint=nil;rows.triggerEnd=nil
    s.quests[1].objectives={{type="event",text="聆听交付者的教诲",finished=false}}
    p=d:Target(q,s);eq(p.entityId,9);eq(p.entityName,"交付者");eq(p.x,0.25);eq(p.targetId,nil)
    s.position=p;p=d:Target(q,s);eq(p.objectiveIndex,1);eq(s.quests[1].ready,nil);eq(s.completed[1],nil)
    rows.triggerEnd={"Event",{[12]={{42,88}}}};eq(d:Target(q,s).sourceKind,"trigger");rows.triggerEnd=nil
    s.quests[1].objectives[1].text="交付者与发布者";eq(d:Target(q,s).entityId,nil)
    s.quests[1].objectives[1].text="聆听交付者";s.quests[1].objectives[1].targetId=6
    eq(d:Target(q,s).entityId,nil);s.quests[1].objectives[1].targetId=nil
    s.quests[1].objectives[1].finished=true;eq(#d:ObjectiveTargets(q,s),0)
end)
test("事件与怪物混合目标保持独立且不猜测多个事件的对应",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    rows.objectives={{{6}}};rows.triggerEnd={"Event",{[12]={{42,88}}}}
    npcs[6].spawns={[12]={{10,20}}}
    s.quests[1].objectives={{text="怪物甲",type="monster"},{text="另一语言事件",type="event"}}
    local p=d:ObjectiveTargets(q,s);eq(#p,2);eq(p[1].targetId,6);eq(p[2].sourceKind,"trigger")
    local descriptions,positions=d:ReferenceObjectiveTargets(q,s)
    eq(#descriptions,2);eq(positions[1].targetId,6);eq(positions[2].sourceKind,"trigger")
    s.quests[1].objectives={{text="怪物甲",type="event"}}
    eq(next(d:ObjectiveIdentities(q,s)),nil);eq(d:Target(q,s).sourceKind,"trigger")
    s.quests[1].objectives[2]={text="另一个事件",type="event",finished=true}
    p=d:Target(q,s);eq(p.approximate,true);eq(p.sourceKind,nil)
    s.quests[1].objectives={{text="无对应的怪物",type="monster"},{text="未知目标"}}
    p=d:ObjectiveTargets(q,s);eq(p[1].sourceKind,nil);eq(p[2].sourceKind,nil)
    rows.objectives={};s.quests[1].objectives={{text="无类型事件"}}
    eq(d:Target(q,s).sourceKind,"trigger")
end)
test("单目标特殊坐标修复钓鱼来源并保持目标身份和完成判据",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    q.zoneOrSort=-101;rows.objectives={nil,nil,{{100}}}
    d.db.Item.Get=function(_,key) if key=="name" then return "小齿轮" end end
    rows.extraObjectives={{{[12]={{35,44},{60,70}}},20,"Fish",0}}
    s.quests[1].objectives={{text="小齿轮",type="item",numFulfilled=0,numRequired=8}}
    npcs[8].spawns={[12]={{10,20}}};npcs[9].spawns={[12]={{10,20}}}
    local p=d:Target(q,s);eq(p.sourceKind,"extra");eq(p.x,0.35);eq(p.targetId,100);eq(p.objectiveIndex,1)
    local stages,complete=B.TaskGuide.Stages(q,s,d,{kind="objective",position=p,objectiveIndex=1})
    eq(complete,true);eq(stages[1].need,8);eq(stages[1].targetId,100)
    eq(s.completed[1],nil);eq(s.quests[1].ready,nil)
    s.quests[1].objectives[1].finished=true;eq(#d:ObjectiveTargets(q,s),0)
    s.quests={};local descriptions,positions=d:ReferenceObjectiveTargets(q,s)
    eq(positions[1].sourceKind,"extra");eq(descriptions[1].targetId,100)
    stages,complete=B.TaskGuide.Stages(q,s,d,{kind="accept",position=d:Target(q,s)})
    eq(complete,true);eq(stages[2].position.sourceKind,"extra")
end)
test("特殊实体按明确目标序号定位且多个说明不合并为单一目标",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    rows.extraObjectives={{nil,4,"Use first",1,{{"object",100}}},{nil,4,"Use second",2,{{"monster",8}}}}
    d.db.Object.Get=function(id,key) if key=="spawns" then return {[12]={{40,60}}} end end
    npcs[8].spawns={[12]={{20,30}}}
    s.quests[1].objectives={{text="怪物甲",type="monster"},{text="怪物乙",type="monster"}}
    local p=d:ObjectiveTargets(q,s);eq(p[1].entityId,100);eq(p[1].targetId,6);eq(p[2].entityId,8);eq(p[2].targetId,7)
    s.quests[1].objectives[1].finished=true;p=d:ObjectiveTargets(q,s);eq(#p,1);eq(p[1].objectiveIndex,2)
    rows.extraObjectives[2][4]=1;s.quests[1].objectives[1].finished=false
    p=d:ObjectiveTargets(q,s);eq(p[1].approximate,true);eq(p[1].sourceKind,nil)
    rows.extraObjectives[1][4]=0;rows.extraObjectives[2][4]=0;s.quests[1].objectives[2]=nil
    eq(d:Target(q,s).sourceKind,nil)
    rows.extraObjectives={{{[12]={{-1,-1,1},{101,10}}},20,"invalid",1}}
    eq(d:Target(q,s).sourceKind,nil)
    rows.extraObjectives={{nil,4,"use",1,{{"monster",8}}}}
    npcs[6].spawns={[12]={{10,15}}};p=d:Target(q,s);eq(p.entityId,6);eq(p.sourceKind,nil)
end)
test("参考特殊目标尊重数据库顺序修正并隔离格式不全的序号",function()
    local B,q,s,rows=fixture();local d=B.Data
    rows.objectives={{{6}},nil,{{100}}};d.db.Item.Get=function(_,key) if key=="name" then return "物品" end end
    rows.extraObjectives={{{[12]={{40,60}}},20,"item",1},{{[12]={{20,30}}},4,"npc",2}}
    d.db.ObjectiveFirst={itemObjectiveFirst={[1]=true}}
    local descriptions,p=d:ReferenceObjectiveTargets(q,s)
    eq(descriptions[1].targetKind,"item");eq(p[1].x,0.4);eq(p[1].targetId,100);eq(p[2].targetId,6)
    rows.objectives[4]={99};descriptions,p=d:ReferenceObjectiveTargets(q,s)
    eq(p[1].sourceKind,nil);eq(p[1].approximate,true)
    rows.objectives[4]=nil;rows.triggerEnd={"event",{[12]={{70,80}}}}
    d.db.ObjectiveFirst.eventObjectiveFirst={[1]=true}
    descriptions,p=d:ReferenceObjectiveTargets(q,s);eq(descriptions[1].type,"event");eq(p[1].sourceKind,"trigger")
end)
test("计数目标选最近可用实体并保留独立目标身份和日志进度",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    rows.objectives={[5]={{{6,7},100}}};npcs[100]={name="共同计数"}
    npcs[6].spawns={[12]={{70,80}}};npcs[7].spawns={[12]={{20,30}}}
    s.quests[1].objectives={{text="不同语言计数",type="monster",numRequired=8,numFulfilled=2}}
    local p=d:Target(q,s);eq(p.entityId,7);eq(p.targetId,100);eq(p.targetKind,"killcredit")
    local stages=B.TaskGuide.Stages(q,s,d,{kind="objective",position=p,objectiveIndex=1})
    eq(stages[1].targetKind,"killcredit");eq(stages[1].need,8);eq(stages[1].have,2)
    eq(s.quests[1].ready,nil);eq(s.completed[1],nil)
    s.position={map=1,x=0.7,y=0.8};eq(d:Target(q,s).entityId,6)
    npcs[6].spawns={[12]={{-1,-1}}};eq(d:Target(q,s).entityId,7)
    npcs[7].spawns=nil;p=d:Target(q,s);eq(p.entityId,6);eq(p.approximate,true)
    s.quests[1].objectives[1].finished=true;eq(#d:ObjectiveTargets(q,s),0)
    s.quests[1].ready=true;eq(d:Target(q,s).entityId,9)
end)
test("计数目标混合顺序和别名匹配不将每种实体展开成独立任务",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    rows.objectives={[1]={{8}},[5]={{{6,7},100,"特殊行动"}}};npcs[100]={name="共同计数"}
    npcs[6].spawns={[12]={{20,30}}};npcs[7].spawns={[12]={{40,50}}}
    d.db.ObjectiveFirst={killCreditObjectiveFirst={[1]=true}}
    local descriptions,p,complex=d:ReferenceObjectiveTargets(q,s)
    eq(complex,false);eq(#descriptions,2);eq(descriptions[1].targetId,100);eq(p[1].entityId,6)
    s.quests[1].objectives={{text="怪物乙：2/8",type="monster"},{text="发布者",type="monster"}}
    local ids=d:ObjectiveIdentities(q,s);eq(ids[1].id,100);eq(ids[2].id,8)
    s.quests[1].objectives[1].text="特殊行动：2/8";eq(d:ObjectiveIdentities(q,s)[1].id,100)
    s.quests[1].objectives[1]={targetId=7,targetKind="npc",type="monster"};eq(d:ObjectiveIdentities(q,s)[1].id,100)
    s.quests[1].objectives[1].targetId=999;eq(d:ObjectiveIdentities(q,s)[1],nil)
    rows.objectives[5][2]={{7},101};npcs[101]={name="另一计数"}
    s.quests[1].objectives[1]={text="怪物乙：2/8",type="monster"};eq(d:ObjectiveIdentities(q,s)[1],nil)
end)
test("单项护送计数保留事件说明并与独立事件和物品目标隔离",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    rows.objectives={[5]={{{6,7},100}}};npcs[100]={name="护送完成"};npcs[6].spawns={[12]={{20,30}}}
    s.quests[1].objectives={{text="护送到达",type="event"}}
    local p=d:Target(q,s);eq(p.targetKind,"killcredit");eq(p.entityId,6)
    s.quests[1].objectives[1].type="item";eq(next(d:ObjectiveIdentities(q,s)),nil)
    s.quests[1].objectives[1].type="event";rows.triggerEnd={"separate",{[12]={{40,50}}}}
    eq(next(d:ObjectiveIdentities(q,s)),nil);eq(d:Target(q,s).sourceKind,"trigger")
    s.quests[1].objectives[1].type="monster";eq(next(d:ObjectiveIdentities(q,s)),nil)
end)
test("已展开计数目标允许特殊序号定位而声望格式不全仍隔离",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    rows.objectives={[1]={{8}},[5]={{{6,7},100}}};npcs[100]={name="共同计数"}
    d.db.ObjectiveFirst={killCreditObjectiveFirst={[1]=true}}
    rows.extraObjectives={{{[12]={{40,60}}},3,"target",1}}
    local descriptions,p,complex=d:ReferenceObjectiveTargets(q,s)
    eq(complex,false);eq(p[1].sourceKind,"extra");eq(p[1].targetId,100)
    rows.objectives[4]={99};descriptions,p,complex=d:ReferenceObjectiveTargets(q,s)
    eq(complex,true);eq(p[1].sourceKind,nil);eq(p[1].approximate,true)
end)
test("声望目标展开具体门槛且已满足时省去参考步骤而不写入完成",function()
    local B,q,s,rows=fixture();local d=B.Data
    rows.objectives={[4]={72,3000}};s.quests={};s.reputations={[72]=2999}
    C_Reputation={GetFactionDataByID=function() return {name="暴风城",currentStanding=2999} end}
    local descriptions,p,complex=d:ReferenceObjectiveTargets(q,s)
    eq(complex,false);eq(#descriptions,1);eq(descriptions[1].text,"暴风城声望达到友善")
    eq(descriptions[1].finished,false);eq(p[1].targetKind,"reputation");eq(p[1].targetId,72)
    local stages=B.TaskGuide.Stages(q,s,d,{kind="accept",position=d:Target(q,s)})
    eq(#stages,3);eq(stages[2].have,2999);eq(stages[2].need,3000)
    s.reputations[72]=3000;descriptions,p=d:ReferenceObjectiveTargets(q,s)
    eq(descriptions[1].finished,true);eq(next(p),nil)
    stages=B.TaskGuide.Stages(q,s,d,{kind="accept",position=d:Target(q,s)})
    eq(#stages,2);eq(stages[2].kind,"turnin");eq(s.completed[1],nil);eq(s.quests[1],nil)
    s.reputations={};descriptions=d:ReferenceObjectiveTargets(q,s);eq(descriptions[1].finished,false)
    eq(descriptions[1].numFulfilled,nil)
end)
test("已接声望以日志完成为准且不会把阵营ID当物品来源",function()
    local B,q,s,rows=fixture();local d=B.Data
    rows.objectives={[4]={72,3000}};s.reputations={[72]=4000}
    C_Reputation={GetFactionDataByID=function() return {name="暴风城"} end}
    d.db.Item.Get=function() error("声望不能查物品掉落") end
    s.quests[1].objectives={{text="暴风城声望",type="reputation",numRequired=3000,numFulfilled=2999,finished=false}}
    local p=d:Target(q,s);eq(p.targetId,72);eq(p.approximate,true)
    local stages=B.TaskGuide.Stages(q,s,d,{kind="objective",position=p,objectiveIndex=1})
    eq(stages[1].have,2999);eq(s.quests[1].ready,nil)
    s.quests[1].objectives[1].type="item";eq(next(d:ObjectiveIdentities(q,s)),nil)
    s.quests[1].objectives[1].type="reputation";s.quests[1].objectives[1].finished=true
    eq(#d:ObjectiveTargets(q,s),0)
    s.quests[1].ready=true;eq(d:Target(q,s).entityId,9)
end)
test("混合声望目标保持序号并使用明确特殊目标实体",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    rows.objectives={[1]={{6}},[4]={72,3000}}
    rows.extraObjectives={{nil,1,"Gain reputation",2,{{"monster",7}}}}
    npcs[6].spawns={[12]={{20,30}}};npcs[7].spawns={[12]={{40,50}}}
    s.quests={};s.reputations={[72]=1000}
    local descriptions,p,complex=d:ReferenceObjectiveTargets(q,s)
    eq(complex,false);eq(#descriptions,2);eq(p[2].entityId,7);eq(p[2].targetId,72)
    eq(p[2].targetKind,"reputation");eq(p[2].sourceKind,"extra")
    s.reputations[72]=3000;descriptions,p=d:ReferenceObjectiveTargets(q,s)
    eq(#descriptions,2);eq(descriptions[2].finished,true);eq(p[2],nil);eq(p[1].targetId,6)
end)
test("施法目标分开展示和匹配且学会法术不推定施法完成",function()
    local B,q,s,rows=fixture();local d=B.Data
    rows.objectives={[6]={{100,nil,777},{101}}}
    C_Spell={GetSpellName=function(id) return id==100 and "缓落术" or "影遁" end}
    d.db.Item.Get=function() error("施法地点不能用法术物品的掉落地点") end
    s.quests={};s.spells={[100]=true,[101]=true}
    local descriptions,p,complex=d:ReferenceObjectiveTargets(q,s)
    eq(complex,false);eq(#descriptions,2);eq(descriptions[1].text,"按任务要求施放缓落术")
    eq(descriptions[1].finished,false);eq(p[1].targetKind,"spell");eq(p[1].targetId,100)
    s.quests[1]={objectives={{text="影遁：0/1",type="spell"},{text="缓落术：0/1",type="spell"}}}
    local ids=d:ObjectiveIdentities(q,s);eq(ids[1].id,101);eq(ids[2].id,100)
    s.quests[1].objectives[1].type="event";eq(d:ObjectiveIdentities(q,s)[1].id,101)
    s.quests[1].objectives[1].finished=true;p=d:ObjectiveTargets(q,s);eq(#p,1);eq(p[1].objectiveIndex,2)
    eq(s.completed[1],nil);eq(s.quests[1].ready,nil)
    C_Spell=nil;descriptions=d:ReferenceObjectiveTargets(q,s);eq(descriptions[1].text,"按任务日志施放指定法术")
end)
test("职业种族分类施法目标用发布者区域中心兜底并保留原生坐标优先",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    rows.objectives={[6]={{100},{101}}};q.zoneOrSort=-261
    npcs[8].spawns={[12]={{20,30}}}
    local descriptions,p=d:ReferenceObjectiveTargets(q,s)
    eq(#descriptions,2);eq(p[1].map,1);eq(p[1].x,0.5);eq(p[1].approximate,true);eq(p[2].targetId,101)
    s.quests[1].objectives=descriptions
    C_QuestLog.GetNextWaypoint=function() return 1,0.2,0.3 end
    eq(d:Target(q,s).label,"客户端任务目标")
    C_QuestLog.GetNextWaypoint=nil;rows.extraObjectives={{{[12]={{60,70}}},4,"cast",1}}
    p=d:ObjectiveTargets(q,s);eq(p[1].x,0.6);eq(p[1].approximate,nil);eq(p[2].x,0.5)
    rows.extraObjectives[1][1]={[96]={{60,70}}}
    p=d:ObjectiveTargets(q,s);eq(#p,1);eq(p[1].objectiveIndex,2)
    eq(d:UnmappedTargetArea(q,s,1),96)
    local stages,complete=B.TaskGuide.Stages(q,s,d,{kind="objective",areaId=96,objectiveIndex=1})
    eq(complete,false);eq(stages[1].areaId,96);eq(stages[1].position,nil)
    local _,positions,_,areas=d:ReferenceObjectiveTargets(q,s)
    eq(positions[1],nil);eq(areas[1],96);eq(positions[2].x,0.5)
end)
test("施法前置顺序修正保留原目标索引且同名匹配不猜测",function()
    local B,q,s,rows=fixture();local d=B.Data
    rows.objectives={[1]={{6}},[6]={{100},{101}}}
    d.db.ObjectiveFirst={spellObjectiveFirst={[1]=true}}
    rows.extraObjectives={{{[12]={{40,50}}},4,"cast",1}}
    local descriptions,p=d:ReferenceObjectiveTargets(q,s)
    eq(descriptions[1].targetId,101);eq(descriptions[2].targetId,100);eq(descriptions[3].targetId,6)
    eq(p[1].sourceKind,"extra");eq(p[1].targetKind,"spell")
    C_Spell={GetSpellName=function() return "同名法术" end}
    s.quests[1].objectives={{text="同名法术",type="spell"}};eq(next(d:ObjectiveIdentities(q,s)),nil)
    s.quests[1].objectives[1].targetKind="spell";s.quests[1].objectives[1].targetId=101
    eq(d:ObjectiveIdentities(q,s)[1].id,101)
end)
test("缺UI地图的事件保留实际区域并排除已完成和多事件歧义",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data;q.zoneOrSort=99;rows.objectives={}
    rows.triggerEnd={"event",{[99]={{-1,-1}}}};s.quests[1].objectives={{text="事件",type="event"}}
    eq(d:Target(q,s),nil);local area,index=d:UnmappedTargetArea(q,s);eq(area,99);eq(index,1)
    s.quests[1].objectives[1].type=nil;eq(d:UnmappedTargetArea(q,s),99)
    s.quests[1].objectives[1].type="event";s.quests[1].objectives[1].finished=true;eq(d:UnmappedTargetArea(q,s),nil)
    s.quests[1].objectives[1].finished=false;s.quests[1].objectives[2]={type="event",finished=true}
    eq(d:UnmappedTargetArea(q,s),nil)
    s.quests[1].objectives={};eq(d:UnmappedTargetArea(q,s),99)
    rows.triggerEnd[2][98]={{20,30}};eq(d:UnmappedTargetArea(q,s),nil)
    rows.triggerEnd[2]={[99]={{-1,-1,1},{101,1}}};eq(d:UnmappedTargetArea(q,s),nil)
    rows.triggerEnd[2]={[12]={{20,30}}};eq(d:UnmappedTargetArea(q,s),nil)
    rows.triggerEnd=nil;npcs[9].spawns={[98]={{-1,-1}}}
    s.quests[1].objectives={{type="event",text="聆听交付者"}}
    eq(d:Target(q,s),nil);area,index=d:UnmappedTargetArea(q,s);eq(area,98);eq(index,1)
end)
test("缺地图的接交和实体目标按实际来源区域解析且不猜任务分类",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data;q.zoneOrSort=99
    npcs[8].spawns={[98]={{20,30}}};npcs[9].spawns={[97]={{-1,-1}}};npcs[6].spawns={[96]={{30,40}}}
    s.quests={};eq(d:UnmappedTargetArea(q,s),98)
    s.quests[1]={ready=true,objectives={}};eq(d:UnmappedTargetArea(q,s),97)
    s.quests[1]={objectives={{text="怪物甲",type="monster"}}}
    local area,index=d:UnmappedTargetArea(q,s);eq(area,96);eq(index,1)
    s.quests[1].objectives[1].text="无法对应";eq(d:UnmappedTargetArea(q,s),nil)
    rows.objectives={[5]={{{6,7},100}}};npcs[7].spawns={[96]={{50,60}}}
    eq(d:UnmappedTargetArea(q,s),96)
    npcs[7].spawns={[95]={{50,60}}};eq(d:UnmappedTargetArea(q,s),nil)
    npcs[7].spawns={[12]={{50,60}}};eq(d:UnmappedTargetArea(q,s),nil)
end)
test("副本目标缺地图时不退回野外分类中心且逐目标保留区域",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    npcs[6].spawns={[96]={{20,30}}};npcs[7].spawns={[97]={{30,40}}}
    npcs[9].spawns={[12]={{20,20}}}
    s.quests[1].objectives={{text="怪物甲",type="monster"},{text="怪物乙",type="monster"}}
    eq(d:Target(q,s),nil);eq(#d:ObjectiveTargets(q,s),0)
    eq(d:UnmappedTargetArea(q,s,1),96);eq(d:UnmappedTargetArea(q,s,2),97)
    eq(d:UnmappedTargetArea(q,s,3),nil)
    local stages,complete=B.TaskGuide.Stages(q,s,d,{kind="objective",questId=1,areaId=96,objectiveIndex=1})
    eq(complete,false);eq(#stages,3);eq(stages[1].areaId,96);eq(stages[2].areaId,97)
    eq(stages[1].position,nil);eq(stages[2].position,nil);eq(stages[3].position.x,0.2)
    eq(B.TaskGuide.Timing(s.position,{stages=stages,stagesComplete=complete},s,B.Navigation).seconds,nil)
    npcs[7].spawns={[12]={{30,40}}}
    local p=d:Target(q,s);eq(p.objectiveIndex,2);eq(p.x,0.3)
    s.quests[1].objectives[2].finished=true;eq(d:Target(q,s),nil)
    eq(d:UnmappedTargetArea(q,s,2),nil);eq(s.quests[1].objectives[1].finished,nil)
end)
test("缺地图接交与未接任务的未来目标优先保留各自实际区域",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    npcs[8].spawns={[98]={{20,30}}};npcs[9].spawns={[97]={{-1,-1}}}
    npcs[6].spawns={[96]={{20,30}}};npcs[7].spawns={[12]={{30,40}}}
    s.quests={};eq(d:Target(q,s),nil)
    local descriptions,positions,complex,areas=d:ReferenceObjectiveTargets(q,s)
    eq(positions[1],nil);eq(areas[1],96);eq(positions[2].x,0.3)
    local stages,complete=B.TaskGuide.Stages(q,s,d,{kind="accept",questId=1,areaId=98})
    eq(complete,false);eq(#stages,4);eq(stages[1].areaId,98);eq(stages[2].areaId,96)
    eq(stages[2].position,nil);eq(stages[3].position.x,0.3);eq(stages[4].areaId,97);eq(stages[4].position,nil)
    eq(s.quests[1],nil)
    s.quests[1]={ready=true,objectives={}};eq(d:Target(q,s),nil)
    npcs[9].spawns={[12]={{10,20}}};eq(d:Target(q,s).x,0.1)
    s.quests={};rows.startedBy={nil,nil,{100}}
    d.db.Item.Get=function(_,key) if key=="objectDrops" then return {200} end end
    d.db.Object.Get=function(_,key) if key=="spawns" then return {[98]={{-1,-1}}} end end
    eq(d:Target(q,s),nil);eq(d:UnmappedTargetArea(q,s),98)
    s.bags[100]=1;eq(d:Target(q,s).startItemId,100);eq(d:UnmappedTargetArea(q,s),nil)
    s.bags[100]=nil;rows.startedBy={};rows.finishedBy={}
    s.clientVersion,s.clientBuild="1.60.1","70862"
    B.DungeonCatalog={version="1.60.1",build="70862",objectiveAreas={[1]={accept=98,turnin=98}}}
    eq(d:UnmappedTargetArea(q,s),98);s.quests[1]={ready=true};eq(d:UnmappedTargetArea(q,s),98)

end)
test("缺地图的物品来源保留友好商人并拒绝跨区域歧义",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data;q.zoneOrSort=-1
    rows.objectives={[3]={{100}}};s.faction="Alliance";s.quests[1].objectives={{text="物品",type="item"}}
    d.db.Item.Get=function(_,key) if key=="vendors" then return {8,9} elseif key=="name" then return "物品" end end
    npcs[8].spawns={[98]={{20,30}}};npcs[8].friendlyToFaction="A"
    npcs[9].spawns={[97]={{20,30}}};npcs[9].friendlyToFaction="H"
    eq(d:UnmappedTargetArea(q,s),98);s.faction="Horde";eq(d:UnmappedTargetArea(q,s),97)
    npcs[8].friendlyToFaction="AH";eq(d:UnmappedTargetArea(q,s),nil)
end)
test("缺来源且副本无地图时沿用任务区域但不覆盖已知来源歧义",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data;q.zoneOrSort=99
    rows.objectives={[3]={{100}}};s.quests[1].objectives={{text="宝石",type="item"}}
    d.db.Item.Get=function(_,key) if key=="name" then return "宝石" end end
    local area,index=d:UnmappedTargetArea(q,s);eq(area,99);eq(index,1)
    s.quests[1].objectives[1].finished=true;eq(d:UnmappedTargetArea(q,s),nil)
    s.quests[1].objectives[1].finished=false;q.zoneOrSort=-99;eq(d:UnmappedTargetArea(q,s),nil)
    q.zoneOrSort=12;eq(d:UnmappedTargetArea(q,s),nil);q.zoneOrSort=99
    d.db.Item.Get=function(_,key) if key=="npcDrops" then return {6,7} elseif key=="name" then return "宝石" end end
    npcs[6].spawns={[97]={{-1,-1}}};npcs[7].spawns={[98]={{-1,-1}}}
    eq(d:UnmappedTargetArea(q,s),nil)
    npcs[7].spawns={[97]={{-1,-1}}};eq(d:UnmappedTargetArea(q,s),97)
end)
test("特殊目标无地图时保留具体来源区域和原序号",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data;q.zoneOrSort=99
    rows.objectives={[3]={{100}}};s.quests[1].objectives={{text="宝石",type="item"}}
    d.db.Item.Get=function(_,key) if key=="name" then return "宝石" end end
    rows.extraObjectives={{{[98]={{20,30}}},4,"取物",1}}
    eq(d:UnmappedTargetArea(q,s),98)
    s.quests[1].objectives[1].text="日志不同名";rows.objectives={[3]={{100},{101}}}
    eq(next(d:ObjectiveIdentities(q,s)),nil);eq(d:UnmappedTargetArea(q,s),98)
    rows.extraObjectives[2]=rows.extraObjectives[1];eq(d:UnmappedTargetArea(q,s),nil)
    rows.extraObjectives[2]=nil
    rows.extraObjectives={{nil,4,"取物",1,{{"monster",6}}}};npcs[6].spawns={[97]={{-1,-1}}}
    eq(d:UnmappedTargetArea(q,s),97)
    rows.extraObjectives[1][1]={[98]={{20,30}}};eq(d:UnmappedTargetArea(q,s),nil)
    rows.extraObjectives[1][1]={[12]={{20,30}}};eq(d:UnmappedTargetArea(q,s),nil)
    s.quests[1].objectives[1].finished=true;eq(d:UnmappedTargetArea(q,s),nil)
end)
test("区域中心覆盖全部未匹配目标和额外要求并参与完整移动比较",function()
    local B,q,s,rows=fixture();local d=B.Data
    s.quests[1].objectives[2]={text="另一项未匹配目标",numRequired=2,numFulfilled=0}
    local first={kind="objective",questId=1,position=d:Target(q,s)};first.objectiveIndex=first.position.objectiveIndex
    local stages,complete=B.TaskGuide.Stages(q,s,d,first)
    eq(complete,true);eq(#stages,3);eq(stages[1].need,3);eq(stages[2].need,2)
    for _,stage in ipairs(stages) do eq(stage.position.approximate,true) end
    local timing=B.TaskGuide.Timing(s.position,{stages=stages,stagesComplete=complete},s,B.Navigation)
    assert(timing.seconds>0);eq(s.quests[1].ready,nil);eq(s.completed[1],nil)
    B.Eligibility=A.Eligibility;assert(loadfile("Planner/Planner.lua"))("AiLeveling",B)
    d.GetQuest=function() return q end
    local candidates=B.Planner.TaskChoices(s,d,{1})
    eq(candidates[1].stagesComplete,true);assert(candidates[1].timing.seconds>0)
    local choices={{questId=1,stages=stages},{questId=2,stages={{kind="turnin",position=d:Target(q,{quests={[1]={ready=true}},completed={},position=s.position})}}}}
    s.quests[2]={};local groups=B.TaskGuide.DeliveryGroups(choices,s);eq(#groups,1)
    choices[2].stages[1].position.entityId=10;groups=B.TaskGuide.DeliveryGroups(choices,s);eq(#groups,0)
    s.quests={};rows.objectives={nil,nil,nil,{1}}
    stages,complete=B.TaskGuide.Stages(q,s,d,{kind="accept",position=d:Target(q,s)})
    eq(complete,true);eq(#stages,3);eq(stages[2].position.approximate,true)
    rows.objectives={};stages,complete=B.TaskGuide.Stages(q,s,d,{kind="accept",position=d:Target(q,s)})
    eq(complete,true);eq(#stages,3)
end)
test("职业分类缺目标位置时沿用发布者区域中心并保持真实目标身份",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    q.zoneOrSort=-81;npcs[8].spawns={[12]={{20,30}}}
    local p=d:Target(q,s);assert(p);eq(p.map,1);eq(p.x,0.5);eq(p.y,0.5)
    eq(p.approximate,true);eq(p.entityId,nil);eq(p.objectiveIndex,1)
    s.quests[1].objectives={{text="怪物甲",type="monster"}}
    p=d:Target(q,s);eq(p.targetId,6);eq(p.entityId,nil)
    s.quests[1].objectives={};p=d:Target(q,s);eq(p.x,0.5)
    eq(s.quests[1].ready,nil);eq(s.completed[1],nil)
end)
test("发布者区域兜底覆盖参考阶段但不覆盖已知缺图目标或原生坐标",function()
    local B,q,s,rows,npcs=fixture();local d=B.Data
    q.zoneOrSort=-81;npcs[8].spawns={[12]={{20,30}}}
    rows.objectives={};s.quests={}
    local stages,complete=B.TaskGuide.Stages(q,s,d,{kind="accept",position=d:Target(q,s)})
    eq(complete,true);eq(#stages,3);eq(stages[2].position.x,0.5);eq(stages[3].position.entityId,9)
    s.quests[1]={objectives={{text="怪物甲",type="monster"}}};rows.objectives={{{6}}}
    npcs[6].spawns={[97]={{-1,-1}}};eq(d:Target(q,s),nil);eq(d:UnmappedTargetArea(q,s),97)
    C_QuestLog.GetNextWaypoint=function() return 1,0.1,0.2 end
    eq(d:Target(q,s).x,0.1);C_QuestLog.GetNextWaypoint=nil
    npcs[6].spawns=nil;npcs[8].spawns=nil;eq(d:Target(q,s),nil)
    npcs[8].spawns={[12]={{20,30}}};q.zoneOrSort=97;eq(d:Target(q,s),nil)
    -- Same-build quest text identifies this objective's dungeon even when all provider placements are absent.
    q.zoneOrSort=0;s.clientVersion,s.clientBuild="1.60.1","70862"
    B.DungeonCatalog={version="1.60.1",build="70862",objectiveAreas={[1]={["npc:6"]=97}}}
    eq(d:UnmappedTargetArea(q,s),97);eq(d:Target(q,s),nil)
    s.quests[1].ready=true;rows.finishedBy={};rows.startedBy={}
    C_QuestLog.GetNextWaypoint=function() return 1,0.8,0.9 end
    C_QuestLog.ReadyForTurnIn=function() return false end
    eq(d:Target(q,s),nil)
    C_QuestLog.ReadyForTurnIn=function() return true end
    local p=d:Target(q,s);eq(p.x,0.8);eq(p.y,0.9);eq(p.entityId,nil)
    eq(s.completed[1],nil)
end)
C_Map,C_QuestLog=savedMap,savedQuest
C_Reputation,C_Spell=savedReputation,savedSpell
end
